# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  include AASM
  include EthAddressValidatable

  # PostgreSQL PK is composite (id, created_at) for declarative partitioning,
  # but Rails should use id alone for lookups, dom_id, and associations.
  self.primary_key = "id"

  # ---------------------------------------------------------------------------
  # PARTITION-AWARE LOOKUPS (Planetary Scale Guard)
  # ---------------------------------------------------------------------------
  # blockchain_transactions is RANGE-partitioned by created_at. Queries without
  # the partition key in WHERE force PostgreSQL to scan ALL partitions (O(P×log N)
  # instead of O(log N)). Always prefer find_with_partition_pruning when created_at
  # is available — it enables single-partition index seek.
  # ---------------------------------------------------------------------------

  # @param id [Integer] record ID
  # @param created_at [Time, String, nil] partition key for pruning
  # @param metric_caller [String, nil] who is asking — labels the degraded-path counter
  # @return [BlockchainTransaction]
  # @raise [ActiveRecord::RecordNotFound] if not found
  def self.find_with_partition_pruning(id, created_at = nil, metric_caller: nil)
    if created_at.blank?
      record_unpruned_lookup(metric_caller, "missing_created_at")
      return where(id: id).first!
    end

    # `Time.zone.iso8601`, ніколи голий `Time.iso8601` [ARCH.92]: другий читає зону
    # ПРОЦЕСУ, тож `params[:created_at]` без суфікса зони зсував би секундне вікно на
    # UTC-офсет хоста — і `first!` віддав би `RecordNotFound` ПОВЗ rescue нижче (той
    # ловить формат, не порожній результат). Гард на час тримає fallback досяжним:
    # дата-без-часу проходить `Time.zone.iso8601`, але шукати навколо півночі — не те
    # саме, що шукати без прунінгу.
    if created_at.is_a?(String)
      raise ArgumentError, "created_at without a time component" unless created_at.include?("T")
    end

    time = created_at.is_a?(String) ? Time.zone.iso8601(created_at) : created_at.to_time
    # Use a 1-second range to account for sub-second precision differences
    # between ISO 8601 (second precision) and DB timestamps (microsecond).
    # PostgreSQL still prunes to at most one partition for a 1-second window.
    where(id: id).where(created_at: time...(time + 1)).first!
  rescue ArgumentError, TypeError, NoMethodError
    # Invalid format or unexpected type — fall back to unscoped lookup
    record_unpruned_lookup(metric_caller, "invalid_created_at")
    where(id: id).first!
  end

  # [S6.16 / PERF.1] SET-form of the One-Home. `find_with_partition_pruning` narrows
  # ONE row; the mint tract works in batches by construction, so every batch site had
  # to hand-roll `where(id: …)` — not carelessness, there was nowhere to delegate to.
  # That missing shape is why the invariant kept being violated on the money path.
  #
  # `span` carries the `created_at` values of the SAME rows whose ids are passed (a
  # Range, or any enumerable of timestamps we reduce to [min, max]). The row set is
  # therefore identical with or without it — this is a hint to the planner, never a
  # filter. `created_at` is the partition key and no code path mutates it, so the
  # bounds cannot go stale between the SELECT that produced them and this call.
  #
  # @param ids [Array<Integer>]
  # @param span [Range, Enumerable<Time>, nil]
  # @param metric_caller [String, nil]
  # @return [ActiveRecord::Relation] chainable
  def self.where_ids_pruned(ids, span = nil, metric_caller: nil)
    scope = where(id: ids)
    bounds = partition_span_for(span)
    return scope.where(created_at: bounds) if bounds

    # 🔴 [PERF.1] Порожній набір id — це `WHERE 1=0`, тобто сканувати НЕМА ЧОГО: подія
    # «деградували до повного скану» тут не відбулась, і рахувати її означало б труїти
    # ту саму панель, задля якої лічильник і заводили (виміряно: ×3 на один rescue-батч
    # `MintCarbonCoinWorker` плюс кожна КОНСТРУКЦІЯ сервісу до його ж `return if empty?`).
    record_unpruned_lookup(metric_caller, "missing_span") if Array.wrap(ids).any?
    scope
  end

  # Range passes through; a bare timestamp or any list collapses to its [min, max].
  # Returns nil when there is nothing to bound with — the caller then degrades
  # loudly (counter) instead of silently.
  #
  # 🔴 `Array.wrap`, NEVER `Kernel#Array`: the latter calls `to_a`, and
  # `Time`/`TimeWithZone` answer it with a ten-element decomposition
  # (`[sec, min, hour, mday, mon, year, wday, yday, isdst, zone]`), so `.min`
  # then raises `ArgumentError: comparison of Integer with false failed` on the
  # `isdst` boolean. A single scalar caller (`InsurancePayoutWorker`) is enough
  # to make that every internal insurance payout — caught by adversarial review,
  # invisible to the suite because every call-site spec stubs the service.
  def self.partition_span_for(span)
    # 🔴 [PERF.1] ЕКСКЛЮЗИВНИЙ Range нормалізується в інклюзивний, бо це ПІДКАЗКА, а не
    # фільтр: `min...max`, побудований із самих рядків, викинув би рядок із максимальним
    # `created_at` — той самий недорахований набір, що й у частковому nil нижче. Ідіома
    # `...` живе за десять рядків звідси (`find_with_partition_pruning` рахує вікно
    # `time...time+1s`), тож викликач природно скопіює саме її.
    return span.exclude_end? ? (span.begin..span.end) : span if span.is_a?(Range)

    raw = Array.wrap(span)
    stamps = raw.compact
    return nil if stamps.empty?

    # 🔴 [PERF.1] ЧАСТКОВИЙ `nil` деградує, а не звужує — і це єдина форма входу, на
    # якій інваріант «підказка, НІКОЛИ фільтр» справді ламався. `.compact` над `[t, nil]`
    # мовчки давав `t..t`, тобто рядок із невідомим часом ВИПАДАВ би з результату: на
    # money-таблиці це не повільніший запит, а недорахований набір. Сьогодні вхід такої
    # форми недосяжний (`created_at` входить у composite PK, тож NOT NULL; `bounded_txs`
    # має гард «обидва або жоден») — саме тому гард СТАВИТЬСЯ зараз: латентна міна
    # детонує в день, коли зʼявиться викликач із nullable-джерелом, і зробить це тихо.
    return nil if stamps.size != raw.size

    stamps.min..stamps.max
  end
  private_class_method :partition_span_for

  # Degraded path = a full Global Partition Scan on the money model. It used to be
  # SILENT here while its `TelemetryLog` twin counted — the asymmetry meant the one
  # event worth alerting on was invisible exactly where a scan costs most.
  def self.record_unpruned_lookup(metric_caller, reason)
    SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL
      .increment(labels: { caller: "#{metric_caller || 'undeclared'}:#{reason}" })
  end
  private_class_method :record_unpruned_lookup

  # --- ЗВ'ЯЗКИ ---
  # optional: true — для аудит-транзакцій slashing, коли весь кластер мертвий
  # і жодного дерева-носія немає (пастка "Останнього дерева")
  belongs_to :wallet, optional: true

  # Запасний власник аудит-запису, коли wallet відсутній
  belongs_to :cluster, optional: true

  # Поліморфний зв'язок для аудиту (Напр. AiInsight, EwsAlert або NaasContract)
  belongs_to :sourceable, polymorphic: true, optional: true

  # [E.60 Фаза 1б] Set-once membership архів-батчу: ставиться РАЗ (атомарно зі
  # створенням батчу в Mrv::TelemetryArchiveBatchService), re-dispatch групує по
  # ньому і реюзає stored root. Ніколи не перевішувати на інший батч.
  belongs_to :archive_batch, class_name: "TelemetryArchiveBatch", optional: true

  # ---------------------------------------------------------------------------
  # SCALABILITY NOTE (Series D — Planetary Scale)
  # ---------------------------------------------------------------------------
  # При масштабуванні до мільярдів транзакцій (кожне дерево мінтить SCC щомісяця)
  # ця таблиця стане найбільшою в базі. Рекомендується:
  # 1. PostgreSQL Declarative Partitioning по created_at (RANGE, monthly/quarterly)
  # 2. Альтернатива: партиціювання по cluster_id (LIST) для географічної ізоляції
  # 3. pg_partman для автоматичного створення та maintenance нових партицій
  # Приклад:
  #   CREATE TABLE blockchain_transactions (...) PARTITION BY RANGE (created_at);
  #   CREATE TABLE blockchain_transactions_2026_q1 PARTITION OF blockchain_transactions
  #     FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
  # ---------------------------------------------------------------------------

  # --- ТИПИ ТА СТАТУСИ (The Web3 State Machine) ---
  enum :token_type, { carbon_coin: 0, forest_coin: 1, cusd: 2 }, prefix: true

  # Тікер, яким сума транзакції підписується в UI. Дім — заморожена Ruby-мапа, а
  # НЕ локаль-файл: символ однаковий в усіх мовах, тож YAML змусив би тримати по
  # копії на кожну локаль каталогу плюс стільки ж зобовʼязань парності, і кожну з
  # них перекладач може «виправити» (`04_04 §12.14`, той самий клас, що емодзі-мапи).
  # ⚠️ ВЕРХНІЙ дім символу — не тут, а в Solidity: `contracts/SilkenCarbonCoin.sol`
  # (`ERC20(…, "SCC")`) і `contracts/SilkenForestCoin.sol` (`ERC20(…, "SFC")`), тож ця
  # мапа — ДРУГИЙ дім чужого значення; розходження червонить
  # `spec/quality/token_ticker_parity_spec.rb`. `cusd` контракту в цьому репо не має
  # (зовнішній Celo-токен), тому парність його не стереже — і не може.
  TOKEN_TICKERS = {
    "carbon_coin" => "SCC",
    "forest_coin" => "SFC",
    "cusd" => "cUSD"
  }.freeze

  # Fail-open на сирому значенні — дзеркало `StatusBadge.label`: новий тип токена
  # мусить рендеритись рівно, ще до того як тікер доїде в мапу.
  def ticker
    TOKEN_TICKERS.fetch(token_type.to_s, token_type.to_s.upcase)
  end

  # Дім МІТКИ типу токена — пара до `TOKEN_TICKERS` вище, і дім спільний не за
  # аналогією: `ERC20(name, symbol)` оголошує назву й символ ОДНИМ конструктором,
  # тож у них один верхній дім у Solidity. Різниця лише в тому, де живе наша
  # копія: символ locale-інваріантний і лежить у Ruby-мапі, назва перекладається
  # і лежить у локалях — базова мусить дослівно дорівнювати `ERC20("…")`, і це
  # стереже `spec/quality/token_ticker_parity_spec.rb` разом із символом.
  # Скоуп належить домену МОДЕЛІ, а не компоненту, який показав значення першим
  # (`04_04 §12.14`).
  TOKEN_TYPE_LABEL_SCOPE = "blockchain_transactions.token_types"

  # ОДНА деривація ключа на застосунок: викликач бере цей метод, а не будує
  # `"#{SCOPE}.#{value}"` сам — друга деривація означає, що друкарська помилка в
  # одній із них лишається зеленою назавжди (обидві сторони «present» для
  # будь-якого parity-гейта). Класовий, бо легенда реєстру рендерить мітки з
  # `token_types.keys`, не маючи жодного запису під рукою.
  # ⚠️ Сусідні моделі з тим самим іменем enum'а (`ParametricInsurance`,
  # `TelemetryArchiveBatch` — обидві без `cusd`) цей скоуп можуть ПОЗИЧАТИ; це
  # свідомо, бо мітка описує токен, а не транзакцію. Заводячи там власні мітки,
  # спершу перетни множини значень — збіг слова в спільному bag'у і є дефектом.
  def self.token_type_label(token_type)
    value = token_type.to_s
    I18n.t("#{TOKEN_TYPE_LABEL_SCOPE}.#{value}", default: value)
  end

  # Fail-open — дзеркало `#ticker`: новий член enum'а рендериться сирим значенням
  # ще до того, як мітка доїде в локалі.
  def token_type_label
    self.class.token_type_label(token_type)
  end

  # [ARCH.88 фаза 2] Приналежність транзакції організації резолвиться ДВОМА шляхами,
  # і це не надмірність: cluster-sourced гроші (celo-винагорода, слеш останнього дерева)
  # живуть із `wallet: nil` — та сама пара, що вже стоїть в аудит-трейлі MRV.1
  # (`wallet&.organization_id || cluster&.organization_id`).
  #
  # Гаманцева половина делегує в One-Home `Wallet.for_organization` [ARCH.87] — тобто
  # приймає й порожню денормалізовану колонку, резолвлену через ланцюг. Другої копії
  # предиката тут свідомо НЕМА: інакше грошовий агрегат почав би відповідати на «чий це
  # гаманець» інакше, ніж список скарбниці.
  scope :for_organization, lambda { |org_id|
    where(wallet_id: Wallet.for_organization(org_id).select(:id))
      .or(where(cluster_id: Cluster.where(organization_id: org_id).select(:id)))
  }

  # [ARCH.96] Кластерний сиблінг — та сама двошляхова резолюція, лише вужча координата.
  # Друга гілка НЕ косметична: slash-інтент при мертвому кластері чіпляється прямо до
  # `cluster` (`wallet: nil` — «пастка останнього дерева»), тож join лише через гаманець
  # такі рядки не бачить, і база розміру наступного спалення виходить завищеною.
  scope :for_cluster, lambda { |cluster_id|
    where(wallet_id: Wallet.joins(:tree).where(trees: { cluster_id: cluster_id }).select(:id))
      .or(where(cluster_id: cluster_id))
  }

  # Дім ЗНАЧЕННЯ ознаки «цей burn є СЛЕШЕМ». ⚠️ Після [ARCH.95] це вже НЕ
  # дискримінатор напрямку — напрямок носить колонка `direction` нижче. Константа
  # відповідає на вужче питання: яка ПРИЧИНА вилучення з обігу є слешингом (база
  # розміру — [`05_05 §3`](../../docs/05_05_Slashing_and_Risk_Policy.md)). Рід
  # операції ⊥ її причина: `slash` і `esg_retirement` обидва `direction: :burn`,
  # але лише перший несе `sourceable: NaasContract`.
  # Живий споживач один — інваріант `slash_intent_must_be_a_burn` нижче.
  BURN_SOURCEABLE_TYPE = "NaasContract"

  # [ARCH.95 ⚖️ 2026-08-25] Напрямок руху коштів — ЯВНА колонка, не деривація.
  #
  # Доти він виводився з `sourceable_type = "NaasContract"`, і [ARCH.101] цю
  # деривацію ратифікував — але на ПЕРЕДУМОВІ, записаній тут же дослівно: «єдиний
  # slash-шлях». ESG-погашення (`KlimaDao::RetirementService`) є ДРУГИМ родом
  # вилучення з обігу й природного `sourceable`-об'єкта не має, тобто передумову
  # знімає. Ратифіковано було «деривація, доки burn має одну причину».
  #
  # ⛔ Знак `amount` напрямку НЕ несе й нести не буде: slash пишеться ДОДАТНИМ.
  # Читай `direction`, ніколи не вгадуй зі знака.
  enum :direction, { mint: "mint", burn: "burn" }, prefix: true, default: "mint"

  # Рядковий бік напрямку. Ім'я лишається `burn?` (не `direction_burn?`) — його
  # читають одинадцять в'ю/сервіс-сайтів, і воно є частиною публічної форми моделі.
  #
  # ⚠️ Читає ПУБЛІЧНИЙ reader, а не enum-предикат `direction_burn?`, і це не стиль:
  # той іде прямо в `@attributes`, тож на `.allocate`-фікстурі (єдина законна форма
  # для рядка стрічки — вона не тягне `wallet → tree → cluster → organization`)
  # кидає `NoMethodError` замість читатись. Reader же стабиться, як і решта полів,
  # що їх така фікстура оголошує. У проді різниці немає: колонка `NOT NULL`.
  def burn?
    direction.to_s == "burn"
  end

  # [ARCH.101 ⚖️ 2026-08-20] Дисплей-форма суми: напрямок входить у ЧИСЛО (−X для
  # спалення) — леджерна конвенція, ратифікована разом із «чесним мінусом» агрегатів
  # [ARCH.103]. Дім ОДИН на чотирьох читачів (обидва леджери, tx-show, стрічка):
  # рукописні тернари розійшлися б тихо. НЕ для дроту (JSON/CSV віддають сирий
  # `amount` + деривацію окремим полем — аудиторська форма) і НЕ для агрегатів
  # (там SQL-CASE `net_minted_by_cluster` з тим самим BURN_SOURCEABLE_TYPE).
  def signed_amount
    burn? ? -amount : amount
  end

  # [G4/ARCH.97] One-Home ЧИСТОЇ ЕМІСІЇ: Σ(mints) − Σ(burns).
  #
  # 🔴 **«Дзеркало `totalSupply()`» — правда лише доти, доки живий ЛИШЕ slash-burn**
  # (переміряно 2026-08-26). Slash кличе `_burn` нашого контракту, тож `totalSupply`
  # справді падає. ESG-ретайрмент — НІ: `retire()` це чужий ABI KlimaDAO після `approve`,
  # тобто трансфер, і on-chain supply не змінюється (канон-дім наслідку — `05_03`).
  # А тут він однаково віднімається, бо несе `direction: :burn`. Отже після першого
  # погашення DB і ланцюг розходяться НАЗАВЖДИ, і `ChainAuditService` (поріг 0.0001)
  # читатиме легальне погашення як фрод. Сьогодні латентно — ESG-рейка має нуль
  # enqueue-сайтів; озброюється рівно тим комітом, що її дротує → `00_07` ARCH.95.
  #
  # 🔴 **Рахує ЛИШЕ `:confirmed`, і межа несуча** [DOC-T.89, названо 2026-08-26]:
  # `:manual_review` канон оголошує age-unbounded BY DESIGN, і саме туди їде
  # ambiguous-broadcast batchMint («міг landed»). Отже монети, що ЙМОВІРНО існують
  # on-chain, для бази слешингу, L1-якоря і org/cluster-поверхонь дорівнюють нулю
  # НАЗАВЖДИ — доки людина не розсудить. Напрямок помилки безпечний (недо-, не
  # над-облік), але він не нульовий, і жоден дім цього доти не називав.
  # ⊕ Сиблінг: `KlimaDao::RetirementService` пише `:sent` і НЕ планує
  # `BlockchainConfirmationWorker`, тож гард `retirable_scc` не бачить щойно
  # зробленого погашення, поки його не підбере sweeper.
  #
  # Вилучення з обігу теж `carbon_coin` і теж доходить до `:confirmed`, але on-chain
  # ЗМЕНШУЄ supply — тож сумувати його позитивно роздуває результат на 2×burn.
  # Причин вилучення ДВІ: slash (`BlockchainBurningService#create_slash_intent!`)
  # і ESG-погашення (`KlimaDao::RetirementService`); обидві несуть `direction: :burn`.
  #
  # 🔴 **[ARCH.95] Дискримінатор — колонка `direction`, а не `sourceable_type`.**
  # Доти тут стояв `IS DISTINCT FROM 'NaasContract'`, і та форма мала ДВІ ціни:
  # (а) вона рахувала ESG-погашення ЕМІСІЄЮ, бо погашення `sourceable` не має;
  # (б) NULL-пастку (`NULL != 'x'` = NULL, не TRUE) мусив відтворювати руками
  # кожен новий читач — і два сайти вже робили це ПОЗА моделлю, попри «Дім
  # свідомо ОДИН» рядком нижче. `direction` — `NOT NULL`, тож вісь зникає.
  #
  # ⚠️ Дім свідомо ОДИН: два місця з цим дискримінатором розійшлися б тихо, і саме
  # тому формула переїхала сюди з приватного методу chain-аудиту — її другим
  # споживачем став L1-якір ([`05_04 §3`](../../docs/05_04_Ethereum_L1_State_Anchor.md)).
  #
  # ✅ Викликається і на КЛАСІ, і на RELATION (перевірено рантаймом: `where` всередині
  # чіпляється до `current_scope`), тож кластерний споживач бере ТОЙ САМИЙ дім:
  # `BlockchainTransaction.joins(wallet: :tree).where(trees: { cluster_id: id })
  #                       .net_minted_supply(:carbon_coin)`.
  # Це навмисно — щоб [ARCH.96] не завів другу копію дискримінатора під кластер.
  # Повертає BigDecimal (без `.to_f`): Float дав би e-нотацію в хешованому payload'і.
  def self.net_minted_supply(token_type)
    base  = where(token_type: token_type, status: :confirmed)
    mints = base.where(direction: :mint).sum(:amount)
    burns = base.where(direction: :burn).sum(:amount)
    mints - burns
  end

  # [ARCH.103] Батчева форма того самого агрегату під СПИСКОВІ поверхні: віддає
  # `{cluster_id => BigDecimal}` ОДНИМ запитом. Заведено тому, що після переходу на
  # кластерну семантику кожен рядок списку контрактів питав би власний агрегат — N
  # запитів на грошовій поверхні, які Prosopite побачив би лише з другого рядка.
  #
  # ⚠️ Дискримінатор напрямку тут ТОЙ САМИЙ (колонка `direction`, [ARCH.95]) — третьої
  # КОПІЇ формули не заводимо, лише третю ФОРМУ її застосування (агрегат по групах).
  # Доти тут стояв `IS DISTINCT FROM 'NaasContract'` з обов'язковою NULL-обережністю;
  # `NOT NULL`-колонка цю вісь зняла, тож `= 'mint'` тут достатній і безпечний.
  #
  # 🔴 Координата кластера резолвиться ДВОМА шляхами, і друга гілка не косметична —
  # рівно як у `for_cluster` [ARCH.96]: slash-інтент «останнього дерева» чіпляється
  # прямо до `cluster` з `wallet: nil`, тож `LEFT JOIN` через гаманець його не бачить.
  # `COALESCE` зводить обидві координати в одну вісь групування.
  #
  # 🔴 **Нуль ТУТ виміряний, а не фабрикований — і цю межу треба тримати поруч із
  # сусідами:** `naas_contracts.emitted_tokens` віддавав нуль, бо писача не існувало;
  # цей агрегат віддає нуль, бо запит ВИКОНАВСЯ і підтверджених рухів справді немає.
  # Тому кластер, відсутній у хеші, = `0`, а не «не виміряно».
  #
  # ⚠️ Часового вікна НЕМА свідомо: питання звучить «скільки намінтовано за ВЕСЬ час»,
  # тож будь-яка межа змінила б ВІДПОВІДЬ, а не лише вартість — прецедент `PERF.1` (г).
  def self.net_minted_by_cluster(cluster_ids, token_type)
    ids = Array(cluster_ids).compact.uniq
    return {} if ids.empty?

    coordinate = "COALESCE(trees.cluster_id, blockchain_transactions.cluster_id)"
    signed_amount = "CASE WHEN blockchain_transactions.direction = " \
                    "#{connection.quote(directions[:mint])} " \
                    "THEN blockchain_transactions.amount ELSE -blockchain_transactions.amount END"

    where(token_type: token_type, status: :confirmed)
      .joins("LEFT JOIN wallets ON wallets.id = blockchain_transactions.wallet_id")
      .joins("LEFT JOIN trees ON trees.id = wallets.tree_id")
      .where("#{coordinate} IN (?)", ids)
      .group(Arel.sql(coordinate))
      .sum(Arel.sql(signed_amount))
  end

  # [СИНХРОНІЗОВАНО]: Додано статус :sent для підтримки асинхронного Fire-and-Forget
  enum :status, {
    pending: 0,        # Очікує в черзі на обробку
    processing: 1,     # В процесі підпису/відправки в RPC (заблоковано локом)
    sent: 4,           # [НОВЕ]: Відправлено в Polygon, чекаємо підтвердження блоку (tx_hash вже є)
    confirmed: 2,      # Успішно зафіксовано в блокчейні (Finalized)
    failed: 3,         # Помилка транзакції або Revert на рівні EVM
    manual_review: 5   # [DOUBLE-SPEND GUARD]: tx_hash існує або стан невідомий — потребує ручної звірки
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :amount, presence: true, numericality: { greater_than: 0 }

  # [MULTICHAIN]: Валідація адреси призначення залежить від мережі.
  # EVM (Polygon/Ethereum): 0x + 40 hex символів
  # Solana: Base58 адреса (32-44 символи), не починається з 0x
  validates_eth_address :to_address, presence: true, unless: :solana_network?
  validates :to_address, presence: true, format: {
    with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/,
    message: "має бути валідною Solana Base58 адресою"
  }, if: :solana_network?

  # [ОПТИМІЗОВАНО]: tx_hash має бути присутнім для статусів sent та confirmed
  validates :tx_hash, presence: true, if: -> { status_sent? || status_confirmed? }

  # Валідація метрик газу (якщо присутні)
  validates :gas_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :gas_used, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :block_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :nonce, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # [MRV.1] lineage-вікно вимірів mint-інтенту + Merkle-корінь вікна (fail-open:
  # nil легітимний — witness-фіча ніколи не блокує мінт)
  validates :telemetry_merkle_root,
            format: { with: /\A[a-f0-9]{64}\z/, message: "must be a 64-char hex Merkle root" },
            allow_nil: true
  validates :telemetry_window_from_id, :telemetry_window_to_id, :telemetry_lineage_version,
            numericality: { only_integer: true }, allow_nil: true

  # [MULTICHAIN]: blockchain_network визначає мережу транзакції
  validates :blockchain_network, inclusion: { in: %w[evm solana celo] }

  # 🔴 [ARCH.95] Інваріант, а НЕ деривація — і різниця тут несуча.
  #
  # Деривація («якщо `sourceable_type` = NaasContract, значить burn») — це рівно те,
  # що присуд ARCH.95 зняв: вона за побудовою не бачить ESG-погашення, бо те
  # `sourceable` не має, тобто відновила б half-fix. Інваріант робить зворотне: він
  # НІЧОГО не виводить, а лише не дає slash-інтенту поїхати мінтом. Погашення й далі
  # оголошує напрямок само.
  #
  # Ціна названа: писач, що забуде `direction: :burn` на slash-шляху, дістане ГУЧНУ
  # відмову замість тихого завищення емісії — а завищення тут годує L1-якір і базу
  # розміру спалення. Це також єдиний живий споживач `BURN_SOURCEABLE_TYPE` після
  # того, як напрямок переїхав у колонку.
  validate :slash_intent_must_be_a_burn

  def slash_intent_must_be_a_burn
    return unless sourceable_type == BURN_SOURCEABLE_TYPE
    return if direction_burn?

    errors.add(:direction, "slash-інтент мусить нести напрямок :burn [ARCH.95]")
  end

  # [ARCH.45 / ARCH.51] ЄДИНИЙ живий money-path intent-marker guard: незавершена tx у `window`
  # (включно з `:manual_review` — можливо-landed виплата під ручною звіркою блокує re-pay).
  # ⚠️ `window`-bound тут НЕ прунить, і це вимір, а не оцінка: `OR` робить кандидатом КОЖНУ
  # партицію, тож `created_at` лишається самим лише `Filter` (EXPLAIN 2026-08-07: 9 із 9 листів
  # у плані). Доти цей рядок стверджував протилежне — і три call-site-коментарі успадкували
  # заяву звідси. Ціна прийнятна свідомо (обґрунтування нижче), але вона Є. Покриває всю
  # родину (burn 2h · Solana payout / insurance /
  # Etherisc 7d); `:manual_review` + configurable window роблять його суворо потужнішим за колишній
  # flat `in_flight`-scope (видалено в ARCH.51 як dead code — 0 callerів). DRY-джерело lookup-патерну
  # для BatchPayoutService + InsurancePayoutWorker + BurningService. Anchor має власний
  # `EthereumAnchor.in_flight` (окремий live scope, 1-week вікно).
  #
  # [ARCH.45 fix] `:manual_review` — БЕЗ часової межі (лише pending/sent зв'язані `window`). Ambiguous
  # possibly-landed slash/payout переживає re-fire cron через ДНІ: щоденний slash-cron (02:00) і
  # погодинний Solana-payout інакше re-fire-ять ПІСЛЯ спливу вузького вікна (burn 2h, Solana 7d) →
  # детермінований double-burn / double-pay (не гонка — календар). manual_review надрідкісний
  # (потребує людської звірки) + `sourceable`/`wallet_id` індекси звужують lookup, тож втрата
  # created_at-prune не б'є по гарячому шляху. ⚠️ Втрата ця — на ВСЬОМУ запиті, не «на цій гілці»:
  # `OR` знімає прунінг цілком, а не лише для manual_review-диз'юнкта. Індекс, а не партиційний
  # відбір, і є тим, що тримає вартість. SQL: (status=5) OR (status∈{0,4} ∧ у вікні).
  scope :unsettled_within, ->(window) {
    where(status: [ :pending, :sent, :manual_review ])
      .where("status = ? OR created_at > ?", statuses[:manual_review], window.ago)
  }

  # --- РЕЗОЛЮЦІЯ ВЛАСНИКА ---
  # Дім ОДИН, і він мусить відповідати рівно так, як `for_organization` (↑): інакше
  # рядок, ВИДИМИЙ в аудит-списку організації, адресувався б у чужий стрім або нікуди.
  # Тут доти стояв `delegate :organization, to: :wallet, allow_nil: true` з коментарем
  # «може бути nil для slashing-аудиту — тоді через cluster», але фолбеку через cluster
  # делегат не мав: cluster-sourced рядок віддавав `nil` МОВЧКИ. Це не помічалось, бо
  # викликачів у делегата не було жодного — тобто обіцянка коментаря ніколи не
  # перевірялась реальністю.
  #
  # Три ланки — та сама пара координат, якою `for_organization` резолвить приналежність:
  # денормалізований ярлик гаманця (nullable, без бекфілу — пишеться лише при народженні
  # дерева) → ланцюг дерево→кластер → власний кластер рядка (Celo-винагорода кластеру,
  # слеш «останнього дерева»). ⚠️ НЕ звужувати до `wallet&.organization_id ||
  # cluster&.organization_id`: та форма читає лише колонку, тобто ВУЖЧА за скоуп
  # сторінки, і рядок, видимий через ланцюгову гілку, мовчки лишився б без адреси.
  def organization
    wallet&.organization || wallet&.tree&.cluster&.organization || cluster&.organization
  end

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРАНЗАКЦІЇ (The Web3 State Machine — AASM)
  # =========================================================================
  # [MRV.1] Кожен money-перехід → tamper-evident AuditLog-ланцюг (compliance-trail).
  # [ARCH.57] after_update_commit, НЕ AASM after_all_transitions: той файрить ДО
  # персистенції — rollback переходу (deadlock/validation у save-вікні) лишав би
  # фантомний money-audit рядок + IPFS-пін (Sidekiq-push у Redis не відкочується).
  # ⚠️ Стеля: два переходи одного instance в ОДНІЙ AR-транзакції злилися б в один
  # рядок (last-save saved_changes) — таких шляхів нема (Solana-пари йдуть під
  # Kredis.lock окремими комітами); не загортай послідовні transitions у transaction.
  after_update_commit :record_money_audit_trail, if: :saved_change_to_status?

  aasm column: :status, enum: true, whiny_persistence: true do
    state :pending, initial: true
    state :processing
    state :sent
    state :confirmed
    state :failed
    state :manual_review

    # Початок обробки (підпис / відправка в RPC)
    event :process do
      transitions from: :pending, to: :processing
    end

    # Фіксація моменту вильоту в мемпул
    event :mark_as_sent do
      before do |hash|
        self.tx_hash = hash
        self.sent_at = Time.current
        self.error_message = nil
      end
      transitions from: [ :pending, :processing ], to: :sent
    end

    # Успішне підтвердження в мережі (авто-поллер із `:sent`; ОПЕРАТОР із `:manual_review`).
    #
    # 🔴 [ARCH.115] `:manual_review` доти був станом БЕЗ ВИХОДУ: подій із `from:
    # :manual_review` було нуль, тож рядок, ескальований double-spend guard'ом, лишався
    # там назавжди, а `net_minted_supply` рахує лише `:confirmed` — отже монети, що
    # ЙМОВІРНО існують on-chain, дорівнювали нулю для L1-якоря й бази слешингу
    # НАЗАВЖДИ. Єдиним фактичним шляхом лишався сирий SQL повз валідації й аудит-хук.
    #
    # 🔑 Форму взято з ратифікованого сиблінга `EthereumAnchor` [ARCH.66], і ключове в
    # ній — ДЕ стоїть гард: подія приймає обидва стани, а від авто-резолву захищає
    # СПОЖИВАЧ (`BlockchainConfirmationWorker.confirmation_scope` виключає
    # `:manual_review`). Це не послаблення double-spend guard'а (CLAUDE §6 «не
    # авто-резолвити»), а рівно його збереження: машина далі не сміє закрити
    # ambiguous-рядок, а людина, що звірила tx на експлорері, більше не мусить лізти
    # в базу руками.
    # ⛔ Не давати авто-поллеру бачити `:manual_review`: гард тримається саме там, і
    # розширення його скоупу поверне дефект, проти якого ескалація й існує.
    event :confirm do
      before do |block_num, gas_cost|
        self.block_number = block_num if block_num.present?
        self.gas_used = gas_cost if gas_cost.present?
        self.confirmed_at = Time.current
        self.error_message = nil
      end
      transitions from: [ :sent, :processing, :manual_review ], to: :confirmed
    end

    # Фіксація збою (як при відправці, так і при Revert)
    event :fail do
      before do |reason|
        self.error_message = reason.to_s.truncate(500)
      end
      after do
        Rails.logger.error "🛑 [Web3] Транзакція ##{id} провалилася: #{error_message}"
        # [M2/ARCH.45] Mint-tx тримає growth_points у Wallet#locked_balance до фіналізації.
        # На fail (on-chain revert / permanent RPC error) токенів НЕ створено → бали МУСЯТЬ
        # повернутись у available, інакше баланс форестера заморожено назавжди. Раніше release
        # жив ЛИШЕ у MintingRollbackService, який кличеться тільки з retries_exhausted — а
        # ConfirmationWorker revert-гілка й mint_individual rescue роблять голий fail! → strand.
        # Дискримінатор `locked_points`: лише growth-points-mint (Wallet#lock_and_mint!) його має;
        # slash-intent / celo / anchor / insurance-mint audit-tx = nil → no-op. `from_state` guard
        # не дає повторному fail! (failed→failed retry) звільнити двічі.
        release_locked_points_on_fail! if aasm.from_state != :failed
      end
      # :failed → :failed дозволяє оновити error_message при повторному збої
      # (напр. sidekiq_retries_exhausted після попереднього fail)
      # [ARCH.115] `:manual_review` — другий бік операторського виходу: звірка на
      # експлорері може показати, що tx НЕ пройшла. Без цієї гілки оператор мав би
      # єдиний вихід «підтвердити», тобто вибір між правдою і нічим.
      transitions from: [ :pending, :processing, :sent, :failed, :manual_review ], to: :failed
    end

    # [DOUBLE-SPEND GUARD]: Ескалація до ручної перевірки.
    # Використовується коли tx_hash існує або стан транзакції на блокчейні невідомий.
    # Кошти залишаються в locked_balance до ручної звірки з блокчейн-експлорером.
    event :escalate_to_review do
      before do |reason|
        self.error_message = reason.to_s.truncate(500)
      end
      after do
        Rails.logger.warn "⚠️ [Web3] Транзакція ##{id} потребує ручної перевірки: #{error_message}"
      end
      transitions from: [ :pending, :processing, :sent, :failed ], to: :manual_review
    end
  end

  # [MULTICHAIN]: Хелпер для визначення мережі транзакції
  def solana_network?
    blockchain_network == "solana"
  end

  def celo_network?
    blockchain_network == "celo"
  end

  # Хелпер для посилання на block explorer (Polygonscan, Solana Explorer або Celo Explorer)
  def explorer_url
    return nil unless tx_hash

    if solana_network?
      "https://explorer.solana.com/tx/#{tx_hash}?cluster=devnet"
    elsif celo_network?
      "https://explorer.celo.org/alfajores/tx/#{tx_hash}"
    else
      "https://polygonscan.com/tx/#{tx_hash}"
    end
  end

  alias_method :polygonscan_url, :explorer_url

  # ⚡ [СИНХРОНІЗАЦІЯ]: Real-time broadcast при зміні статусу транзакції.
  # Оновлюємо рядок у таблиці Wallet Ledger та на сторінці деталей TX.
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # ⚡ [СИНХРОНІЗАЦІЯ]: поява транзакції в леджері гаманця. Окремий хук потрібен
  # тому, що створення оновленням не є: доти щойно намінтована транзакція не
  # з'являлась у відкритому леджері ЖОДНОГО разу, а порожній гаманець лишався з
  # написом «транзакцій не виявлено» до перезавантаження сторінки [UI.4].
  after_create_commit :broadcast_new_transaction

  # ⚡ [UI.4] Сигнал в org-аудит. Окремий хук потрібен, бо обидва продюсери нижче
  # починаються з `return unless wallet`, а глобальний реєстр організації
  # (`blockchain_transactions#index`) мусить чути САМЕ ті рухи, у яких гаманця немає
  # ЗА ПОБУДОВОЮ — Celo-винагороду кластеру й слеш «останнього дерева». Тобто під
  # спільним гардом німими лишались найматеріальніші рядки, і це «живість, що бреше»:
  # екран оновлювався б на дрібному й мовчав на великому.
  #
  # 🔴 ОДНА реєстрація на обидві події, і це не стиль. `after_create_commit :x` плюс
  # `after_update_commit :x` НЕ дають двох колбеків: ActiveSupport ключує їх ІМЕНЕМ
  # фільтра, тож друга реєстрація тихо заміщає першу — лишається один колбек з
  # опціями ОСТАННЬОЇ. Виміряно на `_commit_callbacks`: у реєстрі стояв рівно один
  # запис, з `on: :update` і чужою умовою, тобто поява транзакції не сигналилась
  # ЖОДНОГО разу. Помилки при цьому немає — механізм на місці, пускач наполовину
  # мертвий, і мовчить усе, крім екрана.
  after_commit :broadcast_ledger_signal, on: %i[create update],
                                         if: -> { previously_new_record? || saved_change_to_status? }

  private

  # [MRV.1] Tamper-evident слід money-переходів у SHA-256 AuditLog-ланцюг організації
  # (ISO 14064/Verra: аудитор простежує хто/коли/чому рухав стан коштів). Асинхронно
  # (record_async! → AuditLogWorker) — не блокує money-path. Org резолвиться wallet АБО
  # cluster: cluster-sourced money (celo reward + last-tree slash, wallet=nil) має org через
  # cluster, не wallet — інакше найматеріальніші рухи писали б нуль audit-row (ISO 14064/Verra
  # compliance-діра). Без ЖОДНОЇ org чи системного юзера аудит неможливий (chain_hash —
  # per-organization) → свідомий skip з WARN, транзакцію НЕ валимо.
  def record_money_audit_trail
    org_id = wallet&.organization_id || cluster&.organization_id
    # Actor-lookup (Prosopite-нюанси, §B.4/§B.5 leave) → One-Home Auditable.system_actor_id.
    actor_id = Auditable.system_actor_id
    from, to = saved_change_to_status

    if org_id.blank? || actor_id.blank?
      Rails.logger.warn "📋 [MRV.1] AuditLog skip tx ##{id} (#{from}→#{to}): " \
                        "organization=#{org_id.inspect}, oracle_executioner=#{actor_id.inspect}"
      return
    end

    # Event-ім'я лише коли aasm-стан свіжий САМЕ для цієї зміни; raw update!
    # (хук тепер ловить і не-AASM шляхи) або stale instance → state-based fallback.
    event = aasm.current_event.to_s.delete("!")
    action = event.present? && aasm.to_state.to_s == to ? "blockchain_tx_#{event}" : "blockchain_tx_to_#{to}"

    AuditLog.record_async!(
      {
        user_id: actor_id,
        organization_id: org_id,
        action: action,
        auditable_type: self.class.name,
        auditable_id: id,
        metadata: {
          from: from.to_s, to: to.to_s,
          token_type: token_type, amount: amount.to_s,
          tx_hash: tx_hash,
          # [SEC.18 / DPIA M6] КОД, ніколи сирий текст: цей рядок їде в публічний
          # незворотний IPFS-пін, а `error_message` несе `e.message` довільного
          # винятку (чуже RPC-тіло, URL, Kredis). Класифікатор fail-CLOSED —
          # невідоме стає `:unknown` і не виносить назовні жодного байта.
          # Повний текст лишається в `blockchain_transactions.error_message`.
          error: Web3::TransactionErrorClassifier.classify(error_message).to_s,
          # [MRV.1/ARCH.12] транзитивна печатка: корінь вікна → AuditLog-ланцюг →
          # leaf0 наступного тижневого якоря (nil = unsealed, bundle покаже чесно)
          telemetry_merkle_root: telemetry_merkle_root
        }
      }
    )
  end

  # [M2/ARCH.45] Повертає заблоковані growth_points у available при провалі mint-tx.
  # Ідемпотентний: клампимо до поточного locked_balance (частковий rollback уже міг звільнити
  # частину) і виходимо, якщо звільняти нічого. Викликається ЛИШЕ з fail-after при переході
  # НЕ-з-:failed (guard у події) → подвійного звільнення на retry-fail не буде.
  def release_locked_points_on_fail!
    return if locked_points.blank? || locked_points.zero?
    return unless wallet

    wallet.with_lock do
      releasable = [ locked_points.to_i, wallet.locked_balance ].min
      wallet.release_locked_funds!(releasable) if releasable.positive?
    end
  rescue StandardError => e
    # Звільнення — best-effort у after-hook; збій логуємо, але не валимо сам fail-перехід
    # (tx мусить лишитись :failed навіть якщо wallet тимчасово недоступний). Strand у цьому
    # вузькому вікні — той самий recoverable клас, що ARCH.55, не double-spend.
    Rails.logger.error "🛑 [Web3] release_locked_points_on_fail! ##{id}: #{e.message}"
  end

  # СИГНАЛ, а не рядок — дзеркало `EwsAlert#broadcast_org_refresh`, і підстава та сама:
  # сторінка має фільтри (`token_type`/`status`), пагінацію Й дефолтне вікно по
  # `created_at`, тож сліпий `prepend` вставив би нагору транзакцію, що не відповідає
  # активному фільтру, а на другій сторінці — не в той зріз. `refresh` переобчислює
  # сторінку її ж власними параметрами, тобто єдина форма, що поважає всі три.
  # Ціна виміряна: lazy-фреймів у ланцюгу цієї сторінки НУЛЬ, тож це рівно один GET
  # на глядача, без додатку «по GET на фрейм» (`04_04 §8.1б`).
  #
  # ⚠️ Броадкаст іде в org ВЛАСНИКА рядка, підписка — в acting-org ГЛЯДАЧА (`04_04 §8.1`):
  # плутанина цих двох кладе рухи одного тенанта в стрім іншого. Береться org-ЗАПИС,
  # а не `organization_id` — імʼя стріму несе `stream_epoch` [SEC.25 Ф3], а дім імен
  # лишається чистою функцією й у БД не ходить.
  #
  # Літерал стріму тут не пишеться взагалі: адресу дає дім імен, тож обидві сторони
  # тракту кличуть ОДНУ функцію.
  def broadcast_ledger_signal
    owner = organization
    # Fail-closed без тиші: осиротілий кластер — реальний стан схеми
    # (`clusters.organization_id` nullable), і `TurboStreams::Name.org` на `nil`
    # кинув би `ArgumentError`, який власний `rescue` нижче зʼїв би у WARN. Тобто
    # без цього гарда рядок лишався б німим ТАК САМО, лише вже без жодного сліду.
    return if owner.blank?

    Turbo::StreamsChannel.broadcast_refresh_later_to(TurboStreams::Name.org(:ledger, owner))
  rescue StandardError => e
    # Та сама ізоляція, що у двох продюсерів нижче, і з тієї ж причини: `commit_records`
    # має `ensure` без `rescue`, тож виняток UI-декорації пролетів би нагору з
    # `create!`/`update!` — а всі пускачі цього хука лежать на money-шляху.
    Rails.logger.warn "📡 [UI.4] broadcast_ledger_signal ##{id}: #{e.message}"
  end

  # Леджер відсортований `created_at: :desc`, тому `prepend`, не `append`:
  # свіжий запис належить угорі, інакше він сідає під п'ятдесятим рядком.
  #
  # СИНХРОННО — це умова коректності, а не стиль. У формі `_later_`, симетричній
  # до сусіда нижче, обидва броадкасти стали б незалежними Sidekiq-джобами без
  # гарантії порядку: при інверсії `replace` прилітає в ціль, якої ще немає
  # (тихий no-op), а слідом `prepend` садить рядок, відрендерений на старому
  # статусі — і той застрягає до наступного переходу, а після `confirmed`
  # переходів не буває.
  #
  # Літерал стріму повторено свідомо: `turbo_stream_scope_spec` вимагає, щоб
  # адреса на боці продюсера була видима статично (винесена в локал читається
  # як `:indirect` і червоніє), а дім імен record-form стріми не покриває.
  def broadcast_new_transaction
    return unless wallet

    Turbo::StreamsChannel.broadcast_prepend_to(
      [ wallet, :transactions ],
      target: Wallets::Show::LEDGER_TARGET,
      html: Wallets::TransactionRow.new(tx: self, status_src: status_frame_src).call
    )

    # Плейсхолдер порожнього леджера зникає разом із першою транзакцією. Друга
    # половина безпечна сама по собі: `remove` у ціль, якої немає в DOM, Turbo
    # тихо ігнорує, тож порядок доставки двох повідомлень значення не має.
    Turbo::StreamsChannel.broadcast_remove_to(
      [ wallet, :transactions ],
      target: Wallets::Show::EMPTY_PLACEHOLDER_TARGET
    )
  rescue StandardError => e
    # Прикраса екрана НЕ сміє вбити money-шлях. `commit_records` не має `rescue`
    # (лише `ensure`), тож виняток із `after_*_commit` пролітає нагору з `create!`
    # — а на трьох сайтах створення це коштувало б необоротно: KlimaDAO вже
    # виконав on-chain `retire` ДО транзакції й пішов би на другий по Sidekiq-
    # retry, а slash та Solana осіли б у `manual_review` через збій кабелю.
    # Стеля названа: втрачений пульс не повторюється — глядач побачить рядок
    # після перезавантаження, бо сама транзакція в БД уже є.
    Rails.logger.warn "📡 [UI.4] broadcast_new_transaction ##{id}: #{e.message}"
  end

  # [I18N.2 · клас 2] Адресу локаль-вільного стаба будує ПРОДЮСЕР, а не компонент:
  # рядок рендериться через `.call`, де view-контексту (а отже й `*_path`-хелперів
  # Phlex::Rails) не існує. `created_at` їде параметром як ключ партиції — без нього
  # ендпоінт сканує всі партиції RANGE-таблиці.
  def status_frame_src
    Rails.application.routes.url_helpers.wallet_transaction_status_path(
      wallet_id: wallet_id, id: id, created_at: created_at&.iso8601
    )
  end

  def broadcast_status_change
    return unless wallet

    # Оновлення рядка транзакції в Wallet Ledger (підписка: [wallet, :transactions])
    Turbo::StreamsChannel.broadcast_replace_later_to(
      [ wallet, :transactions ],
      target: ActionView::RecordIdentifier.dom_id(self),
      html: Wallets::TransactionRow.new(tx: self, status_src: status_frame_src).call
    )

    # Оновлення балансу при фінальних статусах (confirmed/failed)
    wallet.broadcast_balance_update if status_confirmed? || status_failed?
  rescue StandardError => e
    # Дзеркало гарда вище, і поставлено ТИМ САМИМ проходом свідомо: дірка тут
    # та сама (виняток із `after_update_commit` пролітає з `update!`/AASM-події,
    # а всі три її пускачі — `mark_as_sent!`/`confirm!`/`fail!` — money-переходи),
    # тож закрити лише новий продюсер означало б лишити асиметрію без причини.
    Rails.logger.warn "📡 [UI.4] broadcast_status_change ##{id}: #{e.message}"
  end
end
