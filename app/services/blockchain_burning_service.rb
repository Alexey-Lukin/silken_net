# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

class BlockchainBurningService < ApplicationService
  include Auditable

  # ABI для Sovereign Slashing. [SLASH.2] `slashUpTo(investor, maxAmount)` замість `slash`:
  # спалює min(maxAmount, balanceOf) АТОМАРНО on-chain → строгий slash() тихо revert-ив, коли
  # бекенд рахував pre-tax БД-суму > on-chain балансу (DynamicTax пішов у treasury, SCC вільно
  # переказуваний), і переказ 1 wei перед транзакцією Оракула скасовував би повний slash. Плюс
  # `balanceOf` — pre-read для чесного обліку (intent/метрика) + tripwire на повне виведення.
  CONTRACT_ABI = [
    {
      "inputs" => [ { "internalType" => "address", "name" => "investor", "type" => "address" },
                    { "internalType" => "uint256", "name" => "maxAmount", "type" => "uint256" },
                    { "internalType" => "bytes32", "name" => "contextHash", "type" => "bytes32" } ],
      "name" => "slashUpTo",
      "outputs" => [ { "internalType" => "uint256", "name" => "slashed", "type" => "uint256" } ],
      "stateMutability" => "nonpayable",
      "type" => "function"
    },
    {
      "inputs" => [ { "internalType" => "address", "name" => "account", "type" => "address" } ],
      "name" => "balanceOf",
      "outputs" => [ { "internalType" => "uint256", "name" => "", "type" => "uint256" } ],
      "stateMutability" => "view",
      "type" => "function"
    }
  ].to_json

  # Кількість десяткових знаків токена (ERC-20 стандарт = 18).
  # Змініть тут, якщо почнемо підтримувати стейблкоіни з іншою розрядністю (напр. USDC = 6).
  TOKEN_DECIMALS = 18

  # [ARCH.53 TOCTOU] Дві істинно-конкурентні екзекуції одного контракту (zombie-Sidekiq +
  # свіжий крон) обидві проходили in-flight guard ДО того, як перша створила інтент →
  # подвійний необоротний slashUpTo. Партиційний partial-UNIQUE-index неможливий
  # (PARTITION BY RANGE(created_at) вимагає partition-key в unique — вбиває dedup-семантику),
  # `unique_for` = Sidekiq Enterprise (шим no-op, 04_02 DOC-R.10 — познач залежність,
  # не костиль). Тому non-blocking per-contract claim через Kredis.lock (SET NX + UUID-токен
  # + CAS-release — безумовний delete після TTL-експірі знімав би ЧУЖИЙ claim) навколо
  # вікна guard→transact→mark_as_sent; конкурент → Kredis::LockTimeout → Sidekiq-retry,
  # який уже бачить інтент переможця (:sent → re-arm; stale :pending → supersede).
  # TTL страхує hard-kill; CAS-release не блокує легітимний наступний прохід.
  SLASH_CLAIM_TTL = 2.minutes

  # [05_05 §3 Slashing curve — DAO-governed via SystemParameter ← ProtocolParameters.sol (05_03)]
  DEFAULT_SLASH_GAMMA = 1.3          # convex progressive curve (no dead-zone)
  DEFAULT_PENALTY_FACTOR_MAX = 2.0   # ceiling on the penalty MULTIPLIER (not final slash_ratio)
  DEFAULT_PENALTY_FACTOR = 1.0       # negligence baseline (no cause-driven uplift)

  # [SLASH-1 §3/§6] Ваги cause-driven penalty_factor uplift (дзеркало канону 05_05 §3 —
  # правити ТАМ). Comms-correlated сигнали мають ОДИН root-cause «вузол/шлюз offline» →
  # комбінуються через max(), НЕ суму (SLASH-SAFETY §6, як sap+acoustic max() у §7); фізична
  # халатність — незалежна → additive. Promotable до SystemParameter коли DAO калібрує (як
  # GAMMA/PF_MAX). Комбінатор — #calculate_penalty_factor.
  # ⚫ Другий comms-член (`PF_STREAMR_GAP` 0.25, guarded hook, що завжди віддавав 0) знято разом із
  # Streamr ⚖️ 2026-09-03 (ARCH.118); клас лишається одночленним, доки не зʼявиться нове
  # comms-correlated джерело з ground-truth (00_07 SLASH-1).
  PF_NO_ACK         = 0.5   # comms-correlated: непідтверджений critical EwsAlert (no ack)
  PF_NO_MAINTENANCE = 0.5   # independent: critical EwsAlert без MaintenanceRecord

  # @param contractual [Boolean] true — це погоджена контрактна форфейтура (early-exit
  #   `burn_accrued_points`, `ContractTerminationService`), НЕ slash-за-провину → гейт
  #   positive-A пропускається (інвестор сам розірвав, burn — погоджена умова, не Кат-A).
  # @param stress_threshold [Numeric, nil] поріг «стресованого дерева», ЗАФІКСОВАНИЙ на
  #   момент тригера [SLASH-1, 2026-08-25]. Дзеркало `target_date`: ARCH.46 протягнув сюди
  #   ДАТУ, щоб обидві половини вироку міряли одну добу, — але поріг кожна половина й далі
  #   читала у СВІЙ момент, тож DAO-голос (чи закінчення 24-год TTL `SystemParameter`)
  #   між диспатчем і виконанням розводив тригер і розмір ТІЄЮ САМОЮ парою, лише іншою
  #   координатою. Напрямок помилки асиметричний: підняли поріг у вікні → менший burn
  #   (безпечний бік), знизили → burn БІЛЬШИЙ за підставу, на якій тригер спрацював.
  #   ⚖️ Підстава протягування — не «акуратність», а принцип, уже ратифікований для дати:
  #   вирок судиться правом на момент ПОДІЇ, не на момент виконання.
  #   `nil` → сервіс читає DAO-live сам (tree-death / dClimate / contractual тригери порога
  #   не мають, бо розміру з вибірки не питають).
  # @param slash_gamma [Numeric, nil] показник опуклої кривої, ЗАФІКСОВАНИЙ тригером
  # @param penalty_factor_max [Numeric, nil] стеля множника, ЗАФІКСОВАНА тригером
  #   🔴 [DOC-T.89] Третя й четверта координати того самого інваріанта. Формула
  #   `calculate_slash_ratio` множить ТРИ входи, і доти рівно ОДИН із них судився
  #   правом ПОДІЇ (`damage_ratio`, виведений із замороженого порога), а два —
  #   правом ВИКОНАННЯ. Тобто один вирок стояв на двох різних законах одночасно.
  #   Напрямок ризику виміряно: `damage^γ` при damage<1 УБУВАЄ по γ, тож голос
  #   ЗНИЗИТИ γ у вікні між диспатчем і виконанням робить burn БІЛЬШИМ за підставу,
  #   на якій тригер спрацював — рівно та асиметрія, яку цей файл уже називає для
  #   порога вісьмома рядками вище.
  #   ⚠️ **Стеля оголошена: заморожує ЛИШЕ статистичний канал.** Три інші тригери
  #   (смерть дерева · dClimate · contractual) параметрів не передають і читають
  #   DAO-live у момент виконання — і це не половинчастий фікс, а другий ЗВʼЯЗНИЙ
  #   режим: їхній вирок не виводиться з ВИБІРКИ, тож інваріанта «тригер ≡ розмір»
  #   там нема чому порушувати, а розрив диспатч→виконання в них — один хоп черги.
  def initialize(organization_id, naas_contract_id, source_tree: nil, contractual: false,
                 target_date: nil, stress_threshold: nil,
                 slash_gamma: nil, penalty_factor_max: nil)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
    @source_tree = source_tree
    @contractual = contractual
    # [ARCH.46] Дата для damage-ratio — прокинута від ContractHealthCheckService (де порахована
    # й де відбувся blackout-guard), щоб burn НЕ перевираховував добу у свій момент
    # (date-mismatch → запит на іншу добу → нуль записів → хибне 100%). Інші тригери
    # (tree-death/dClimate/contractual) дати не передають → дефолт `AiInsight.reporting_date`.
    @target_date = target_date
    @stress_threshold = stress_threshold
    @frozen_slash_gamma = slash_gamma
    @frozen_penalty_factor_max = penalty_factor_max
  end

  #
  # Ключі й дефолти живуть ТУТ, поруч із формулою, що їх споживає: тригер не
  # мусить знати ані імен `SystemParameter`, ані чим вони дефолтяться. Інакше
  # кожен новий тригер відтворював би цю трійку з голови — і розійшовшись,
  # обидва доми лишились би зеленими, бо жоден не звіряється з іншим.
  #
  # ⚠️ Повертає РЯДКОВІ ключі: значення їде через Sidekiq, а `strict_args`
  # пропускає лише JSON-нативне — символи серіалізації не переживають.
  def self.frozen_verdict_law(stress_threshold:)
    {
      "stress_threshold"   => stress_threshold.to_f,
      "slash_gamma"        => SystemParameter.current(:slash_gamma, default: DEFAULT_SLASH_GAMMA).to_f,
      "penalty_factor_max" => SystemParameter.current(:slash_penalty_factor_max,
                                                      default: DEFAULT_PENALTY_FACTOR_MAX).to_f
    }
  end

  # [SLASH-1] Поріг вироку: зафіксований тригером, інакше DAO-live на цю мить.
  # Дзеркало `effective_target_date` — та сама форма для тієї самої пари.
  def effective_stress_threshold
    @effective_stress_threshold ||= (@stress_threshold || AiInsight.slash_stress_threshold).to_f
  end

  def perform
    # =========================================================================
    # [HYBRID PROTOCOL GAIA — SLASHING REDISTRIBUTION (Deflation)]
    #
    # Виклик slash() (який внутрішньо використовує _burn у Solidity) перманентно
    # видаляє токени з totalSupply ERC-20 контракту. Це створює дефляційний ефект:
    # загальна кількість SCC в обігу зменшується, що підвищує вартість кожного
    # залишкового токена, утримуваного чесними форестерами.
    #
    # Цей механізм "Slashing Redistribution" діє як неявна винагорода для всіх
    # учасників, що дотримуються умов контракту — їхня частка в загальному пулі
    # зростає без необхідності додаткового мінтингу.
    # =========================================================================

    # 1. АГРЕГАЦІЯ: Рахуємо токени, що ЛИШИЛИСЬ зароблені цим кластером — база розміру спалення.
    # [КЕНОЗИС]: Якщо порушення локальне (одне дерево), ми можемо вилучати
    # або частку, або весь контракт. Наразі йдемо шляхом повної ануляції за порушення гомеостазу.
    #
    # 🔴 [ARCH.96] Доти тут стояв голий `sum(:amount)` по `joins(wallet: :tree)` — дві діри,
    # обидві в бік ЗБІЛЬШЕННЯ незворотної дії:
    #   (1) без фільтра `token_type` SFC-виплати гаманців кластера рахувались як зароблений SCC;
    #   (2) без виключення самих спалень попередній burn-інтент (той самий `carbon_coin`,
    #       ДОДАТНИЙ `amount`, `sourceable: NaasContract`) зараховувався як «зароблене» —
    #       повторний слеш того ж кластера палив із роздутої бази.
    # Лік — не третя формула, а наявний One-Home: `net_minted_supply` = Σmints − Σburns із
    # дискримінатором `sourceable_type`. `for_cluster` додає другу гілку резолюції, бо
    # slash-інтент при мертвому кластері живе з `wallet: nil` і join через гаманець його не
    # бачить — саме той рядок і роздував базу найсильніше.
    total_minted_amount = BlockchainTransaction.for_cluster(@cluster.id)
                                               .net_minted_supply(:carbon_coin)

    # [ARCH.103 ⚖️ 08-20] `<= 0`, не `.zero?`: чиста база буває ВІДʼЄМНОЮ (спалення >
    # мінт — легально, відколи кластер несе кілька контрактів одночасно), а відʼємний
    # інтент падав би об `validates greater_than: 0` у вічний :manual_review.
    return if total_minted_amount <= 0

    # [SLASH-1 §3.2] Positive-A-evidence gate — на чокпоінті, накриває всі тригери burn.
    # Необоротний slash() лише за прямого доказу Кат-A (tamper); інакше freeze (Field Audit,
    # Кат-C) — відновлює канон-дефолт §2 «freeze-поки-не-A», а не палить-поки-не-відведено.
    # Контрактна форфейтура (early-exit) — свідомий виняток. Freeze дзеркалить flag_data_blackout!.
    unless @contractual || positive_a_evidence?
      return freeze_for_field_audit!
    end

    # [ARCH.53 TOCTOU] Non-blocking claim НАВКОЛО вікна guard→transact→mark_as_sent (шапка
    # класу). Конфлікт → Kredis::LockTimeout ЗВІДСИ (поза step-3 begin/rescue) → без
    # audit-сміття і хибного system_fault, чистий Sidekiq-retry.
    Kredis.lock("slash:claim:#{@naas_contract.id}", expires_in: SLASH_CLAIM_TTL) do
      execute_slash!(total_minted_amount)
    end
  end

  private

  # [ARCH.53] Тіло вироку — виконується ПІД per-contract claim'ом (perform).
  # Kredis::LockTimeout тут = ОРАКУЛ-лок (step 3), його ловить власний rescue нижче.
  def execute_slash!(total_minted_amount)
    # [ARCH.45/ARCH.48] In-flight guard ПІСЛЯ positive-A gate (лише slash-шлях, НЕ freeze — інакше
    # intent-сміття для заморожених). `unsettled_within` (вкл. :manual_review), бо ambiguous slash
    # (broadcast невідомий) ескалюється у :manual_review і МУСИТЬ блокувати re-slash:
    #   :sent          → slash уже broadcast → :slashed без повтору (ConfirmationWorker дорезолвить);
    #   :manual_review → ambiguous (можливо-landed, ARCH.48) → НЕ повторюємо до ручної звірки;
    #   :pending       → крах ДО broadcast → старий intent у :failed, перепускаємо й re-slash-имо.
    existing_slash = BlockchainTransaction.where(sourceable: @naas_contract).unsettled_within(2.hours).order(created_at: :desc).first
    if existing_slash
      if existing_slash.status_sent?
        # Re-arm confirmation worker — на випадок краху до його планування на
        # першій спробі (ConfirmationWorker сам дедуплікує за tx_hash через unique_for).
        # `.present?`-else = model-validation-dead: :sent-tx завжди має tx_hash
        # (validates :tx_hash, if: status_sent?) → гілка недосяжна (§B.4 leave).
        BlockchainConfirmationWorker.perform_in(30.seconds, existing_slash.tx_hash, existing_slash.created_at.iso8601) if existing_slash.tx_hash.present? # [ARCH.52] partition-prune
        return :slashed
      end

      if existing_slash.status_manual_review?
        # [ARCH.48] Попередній slash міг потрапити в мемпул до RPC-збою (intent escalate-нуто) —
        # blind re-slash = double-burn. Чекаємо ручну звірку на Polygonscan, не повторюємо.
        Rails.logger.warn "⚠️ [Slashing] ##{@naas_contract.id}: попередній slash у manual_review (можливо-landed) — НЕ повторюємо."
        return :manual_review
      end

      existing_slash.fail!("Superseded — re-slash після pre-broadcast краху (ARCH.45)")
    end

    # [КОЕФІЦІЄНТ ВТРАТ]: Спалюємо лише ту частку токенів, що відповідає
    # відсотку пошкодженої біомаси (розрахунок через AiInsight).
    # Це запобігає повній ануляції контракту при загибелі одного дерева з тисячі.
    # [05_05 §3] Progressive convex slash curve (damage_ratio^GAMMA × min(pf, MAX)),
    # NOT the old linear total × damage_ratio. See #calculate_slash_ratio.
    damage_ratio = calculate_damage_ratio

    # [ARCH.46] Genuine no-data (нуль AiInsight-записів за дату, fault-шлях без конкретного дерева)
    # → magnitude indeterminate → freeze (Кат-C), НЕ worst-case 100%. positive-A довів ПРИЧИНУ
    # (tamper), але РОЗМІР шкоди потребує власних даних (§3.2: burn необоротний, freeze — ні).
    # Дзеркало flag_data_blackout!; contractual-форфейтура сюди не доходить (damage_ratio → 1.0).
    return freeze_for_field_audit!(reason: :indeterminate_magnitude) if damage_ratio.nil?

    slash_ratio  = calculate_slash_ratio(damage_ratio, calculate_penalty_factor)
    burn_amount  = (total_minted_amount * slash_ratio).ceil

    return if burn_amount.zero?

    # 2. WEB3 ПІДГОТОВКА (The Judgment Bridge) — Thread-cached RPC client
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    # [E.2 ROLE SEPARATION]: Окремий ключ для SLASHER_ROLE зменшує blast radius
    # при компрометації — мінтинг залишається під окремим ключем.
    # Легасі-fallback на спільний ORACLE_PRIVATE_KEY retired [INF.22] — ключ dedicated-only.
    # [SEC.17] Деривація живе в seam'і `Web3::OracleSigner` — E.2 mint⊥burn лишається
    # роздільним ключем, лише дім деривації спільний.
    signer = Web3::OracleSigner.for(:slasher)
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    investor_address = @organization.crypto_public_address

    # [SLASH.2] Pre-read on-chain балансу: (1) tripwire на ПОВНЕ виведення (нема чого палити →
    # escalate, НЕ транслюємо приречену `slashUpTo`-revert tx + не лишаємо :breached-брехню);
    # (2) intent/метрика записують РЕАЛІСТИЧНУ суму `effective_burn = min(burn_amount, balance)`,
    # а не pre-tax БД-суму (яка > балансу). Сам burn робить slashUpTo(maxAmount) — clamp до
    # balanceOf АТОМАРНО, тож дрейф балансу між цим читанням і виконанням лише зменшує спалене
    # (без revert; TOCTOU-safe). Floor до цілих SCC (dust < 1 SCC не істотний, консервативно).
    investor_balance_wei = client.call(contract, "balanceOf", investor_address)
    return escalate_evasion!(burn_amount) if investor_balance_wei.zero?

    balance_whole = investor_balance_wei / (10**TOKEN_DECIMALS)
    effective_burn = [ burn_amount, balance_whole ].min
    return escalate_evasion!(burn_amount) if effective_burn.zero? # балансу < 1 SCC — теж evasion

    amount_in_wei = Web3::WeiConverter.to_wei(effective_burn, TOKEN_DECIMALS)

    # [ARCH.57] Slash-вердикт (ПРИЧИНА) в audit-ланцюг: MRV.1 логує лише tx-переходи (РУХ
    # коштів), а тут фіксується ЧОМУ — contractual vs positive-A + розміри. ДО broadcast:
    # вирок зафіксований незалежно від долі транзакції (її життя доскаже MRV.1).
    # Chain-only (без IPFS): source_tree_did + fraud-attribution + detection-пороги
    # на публічному сховищі = INF.22 over-exposure клас; tamper-evidence дає сам ланцюг.
    record_audit_trail!(
      action: "slash_verdict_burn",
      organization_id: @naas_contract.organization_id,
      auditable: @naas_contract,
      metadata: {
        verdict: @contractual ? "contractual_forfeiture" : "positive_a_tamper",
        cluster_id: @cluster.id, source_tree_did: @source_tree&.did,
        damage_ratio: damage_ratio.to_s, slash_ratio: slash_ratio.to_s,
        effective_burn: effective_burn, total_minted: total_minted_amount.to_s
      }
    )

    # 3. ВИКОНАННЯ (The Verdict)
    lock_key = "lock:web3:oracle:#{signer.address}"

    audit = nil
    begin
      tx_hash = nil
      outcome = nil
      # 🔴 [SLASH-1] Цей рядок їде в `notes` ГРОШОВОГО рядка, який рендериться КЛІЄНТОВІ,
      # тож вердикт читається першим. Доти обидві гілки писали «🚨 SLASHING … порушення»
      # навіть за добровільний early-exit — тобто платформа звинувачувала замовника в
      # його ж власному рішенні, на поверхні, яку він бачить. Дискримінатор `@contractual`
      # уже стояв за кілька рядків вище (у `verdict:` audit-ланцюга) і сюди не доїжджав.
      reason = if @contractual
                 "дострокове завершення за ініціативою замовника (погоджена умова договору)"
      elsif @source_tree
                 "загибель дерева #{@source_tree.did}"
      else
                 "порушення умов кластера"
      end

      clamp_note = effective_burn < burn_amount ? " (clamp з #{burn_amount} до on-chain балансу)" : ""
      Rails.logger.warn "🔥 [Slashing] Вилучення #{effective_burn}/#{total_minted_amount} SCC#{clamp_note} (damage #{(damage_ratio * 100).round(1)}% → slash #{(slash_ratio * 100).round(1)}%, 05_05 §3 γ=#{slash_gamma}) у #{@organization.name}. Причина: #{reason}."

      # [ARCH.45] Durable intent-marker (:pending, sourceable: contract) ПЕРЕД on-chain slash.
      # На краху retry бачить його через in-flight guard (вгорі) і не палить удруге.
      # [SLASH.2] Записуємо effective_burn (on-chain-реалістичний), не pre-tax burn_amount.
      audit = create_slash_intent!(effective_burn, reason)
      SilkenNet::Metrics::SLASH_ATTEMPTS_TOTAL.increment

      # [ВИПРАВЛЕНО: Lock Duration]: 30 секунд достатньо для transact() (fire-and-forget,
      # повертається миттєво після відправки TX у мемпул). Операції всередині локу:
      # client.transact (~1-3s мережева затримка) + DB writes (~10-50ms) = ~5s worst case.
      # Попередній 60s лок був для transact_and_wait, який чекав підтвердження блоку.
      Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
        # [ВИПРАВЛЕНО: The 429 Trap]: Використовуємо transact (fire-and-forget) замість
        # transact_and_wait, який блокує Sidekiq-потік нескінченно при перевантаженні Polygon.
        # Підтвердження транзакції делеговано BlockchainConfirmationWorker (як у BlockchainMintingService).
        # [SLASH.2] slashUpTo (не slash): on-chain clamp до balanceOf → без тихого revert/evasion.
        # [CONTRACT.1] contextHash = bytes32(intent tx id) — subgraph/аудитор атрибутує
        # on-chain подію прямо до BlockchainTransaction (manual DAO-slash емітить нуль).
        context_hash = "0x" + audit.id.to_i.to_s(16).rjust(64, "0")
        tx_hash = signer.transact(
          client, contract, "slashUpTo", investor_address, amount_in_wei, context_hash,
          legacy: false
        )
      end

      # 4. ФІКСАЦІЯ (Immutable Audit)
      if tx_hash.present?
        # [ARCH.45] Intent → :sent (BlockchainConfirmationWorker дорезолвить :confirmed/:failed).
        audit.mark_as_sent!(tx_hash)
        SilkenNet::Metrics::SLASH_SUCCESS_TOTAL.increment

        # [ARCH.45] Воркер-підтверджувач планується ОДРАЗУ після mark_as_sent —
        # ДО breach-update. Інакше крах на breach-update лишав би :sent tx без жодного
        # confirmation-воркера (orphan), а retry рано-повертав би через in-flight guard.
        BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash, audit.created_at.iso8601) # [ARCH.52] partition-prune

        # Маркуємо контракт як розірваний. Це автоматично блокує майбутні виплати.
        # 🔴 [SLASH-1] ЛИШЕ на positive-A шляху. На contractual-шляху контракт уже
        # `:cancelled` (його поставив `ContractTerminationService`), і перезапис на
        # `:breached` був не реєстровою неточністю, а ГРОШИМА: `total_insurance_premiums`
        # рахує `[active, fulfilled, breached]` із власним коментарем «cancelled
        # повертається — виключено», тож перезапис утримував 5% премії у Real-Yield
        # звіті за договором, який замовник ЗАКОННО скасував. Канон на боці ліку:
        # `00_04 §5` колонкою результату каже `status = :cancelled`, а `04_02` —
        # «breach лише на РЕАЛЬНОМУ positive-A слешингу». AASM теж: подія `breach`
        # переходу з `:cancelled` не дозволяє (обидва сайти пишуть raw `update!`).
        @naas_contract.update!(status: :breached) unless @contractual

        # [OBSERVABILITY]: Track slashed tokens for Prometheus/Grafana.
        # [SLASH.2] effective_burn (on-chain-реалістичний upper-bound), не pre-tax burn_amount.
        SilkenNet::Metrics::SCC_SLASHED_TOTAL.increment(by: effective_burn)

        Rails.logger.info "✅ [Slashing] Виконано. TX: #{tx_hash}"
        outcome = :slashed
      end

      outcome

    rescue Kredis::LockTimeout => e
      # [ARCH.48] Лок НЕ взято → `transact` НЕ виконувався → tx НЕ у мемпулі → безпечно retry-ити.
      # Саме той мовчазний-abort, який ARCH.48 лікує: раніше rescue breach-ив контракт, а worker-guard
      # `return if status_breached?` глушив кожен retry → on-chain `slash()` ніколи не транслювався.
      # Тепер контракт лишається `:active`, intent → :failed (НЕ in-flight) → re-raise → Sidekiq retry re-slash-ить.
      # audit гарантовано створено (ПЕРЕД локом) і `:pending` (transact не виконувався).
      # `audit&.` else dead: LockTimeout лише з Kredis.lock (після create_slash_intent!) →
      # audit non-nil; `&.` = захист від reorder create-vs-lock (§B.4 leave).
      audit&.fail!("Slash lock-timeout: #{e.message}")
      handle_slashing_failure(e.message, total_minted_amount)
      raise e
    rescue StandardError => e
      if audit&.status_sent?
        # [ARCH.45] Broadcast УЖЕ стався (tx_hash отримано) — крах ПІСЛЯ `mark_as_sent` (ConfirmationWorker
        # / breach-update). Slash потрапить у ланцюг → контракт МАЄ бути `:breached` (як і раніше); re-arm
        # confirmation (`:sent` ⇒ tx_hash присутній — model-validated). Retry безпечний — guard побачить :sent.
        # 🔴 [SLASH-1] Той самий `unless @contractual`, що на happy-path вище, і з тієї ж
        # причини: контрактна форфейтура НЕ робить договір порушеним. Крах у цьому вікні
        # не міняє ПРИРОДИ події — burn однаково стався, але для early-exit він є
        # погодженою умовою, а не вироком.
        @naas_contract.update!(status: :breached) unless @contractual
        BlockchainConfirmationWorker.perform_in(30.seconds, audit.tx_hash, audit.created_at.iso8601) # [ARCH.52] partition-prune
        handle_slashing_failure(e.message, total_minted_amount)
        raise e
      end

      # [ARCH.48] Помилка З `transact`, intent ще `:pending` — AMBIGUOUS: tx міг піти в мемпул до того,
      # як RPC-відповідь загубилась (RPC-лаг) → blind retry = double-burn (свіжий nonce, другий
      # необоротний slash). ARCH.45-інваріант: ескалюй у manual_review, НІКОЛИ не re-attempt наосліп.
      # Контракт лишається `:active` (НЕ :breached); :manual_review блокує re-slash (in-flight guard вгорі).
      # НЕ raise → без Sidekiq retry; повертаємо :manual_review → людська звірка на Polygonscan.
      audit&.escalate_to_review!("Slash міг піти в мемпул до збою — звір на Polygonscan ПЕРЕД повтором: #{e.message}")
      handle_slashing_failure(e.message, total_minted_amount, ambiguous: true)
      :manual_review
    end
  end

  # [SLASH-1 §3.2] Чи є прямий доказ Категорії A для цього кластера. Дім сигналів —
  # Slashing::CauseEvidence (фаза-1 = tamper). source_tree пробрасується для майбутнього
  # per-tree звуження.
  def positive_a_evidence?
    Slashing::CauseEvidence.new(@cluster, source_tree: @source_tree).positive_a?
  end

  # [SLASH-1 §3.2] Freeze (Категорія C) — спалення заблоковано, бо немає прямого доказу A.
  # Дзеркалить ContractHealthCheckService#flag_data_blackout!: піднімає critical Field-Audit
  # алерт (system_fault), НЕ палить і НЕ breach-ить контракт (лишається :active до людської
  # класифікації A/B/C). Burn необоротний, freeze — ні (05_05 §3.2 асиметрія). Повертає :frozen.
  def freeze_for_field_audit!(reason: :no_category_a_evidence)
    # Контекст для аудитора (дзеркало slash-`reason`): конкретне дерево, якщо є джерело,
    # інакше — кластер. Дає Field-Audit з чого почати C→A класифікацію.
    context = @source_tree ? "дерево #{@source_tree.did}" : "кластер ##{@cluster.id}"

    # [ARCH.46] Два приводи для freeze (обидва → Кат-C, no burn/breach): немає прямого доказу A
    # (positive-A gate) АБО доказ A є, але РОЗМІР шкоди невизначений (нема AiInsight-даних). Меседж
    # диференціюємо, щоб Field-Audit мав чіткий triage-контекст (дедуп — 00_07 SLASH-1).
    detail = if reason == :indeterminate_magnitude
               "доказ Категорії A є, але РОЗМІР шкоди невизначений (нема AiInsight-даних за дату)"
    else
               "немає прямого доказу Категорії A"
    end

    # Ключ несе ОБИДВІ осі (привід × суб'єкт), бо і привід, і слово «дерево»/
    # «кластер» — це проза. Раніше вони їхали параметрами `context`/`detail`,
    # і українські фрагменти сідали всередину локалізованої рамки: англієць
    # читав «Slashing blocked (дерево SNET-…): немає прямого доказу…».
    # `context`/`detail` вище лишаються — вони для логу оператора, не для UI.
    subject = @source_tree ? "tree" : "cluster"
    magnitude = reason == :indeterminate_magnitude ? "indeterminate" : "no_evidence"
    audit_key = "slash_frozen_#{magnitude}_#{subject}"
    audit_params = @source_tree ? { tree_did: @source_tree.did } : { cluster_id: @cluster.id }

    Rails.logger.warn "🧊 [SLASH-1] NaasContract ##{@naas_contract.id} (#{context}): спалення заблоковано — #{detail} (05_05 §3.2) → Field Audit, без burn/breach."

    # [SLASH-1] :field_audit (не :system_fault): freeze — це НАШ вирок «слухай, не карай»,
    # а не доказ «вузол offline». Окремий тип не дає freeze самонакручувати penalty_factor
    # через comms_no_ack? (ARCH.46 gap-D) і не конфлатить аудит із comms-fault при дедупі.
    # Хелпер дедуплікує: щоденний cron при тривалій деградації не плодить дублі.
    EwsAlert.escalate_field_audit!(
      cluster: @cluster,
      message_key: audit_key,
      message_params: audit_params
    )

    # [ARCH.57] Freeze — теж привілейований вирок (кошти утримано без burn) → ланцюг.
    # Chain-only; щоденний re-freeze незакритого інциденту пише новий рядок — кожен
    # істинний факт «на цю дату», без IPFS-піна це прийнятний append-шум.
    record_audit_trail!(
      action: "slash_verdict_frozen",
      organization_id: @naas_contract.organization_id,
      auditable: @naas_contract,
      metadata: { verdict: "frozen_cat_c", reason: reason.to_s,
                  cluster_id: @cluster.id, source_tree_did: @source_tree&.did }
    )

    :frozen
  end

  # [SLASH.2] Повне виведення коштів (balanceOf ≈ 0) до слешу: positive-A ВЖЕ довів провину
  # (tamper), але палити нічого — токени переказані/продані. НЕ транслюємо приречену slashUpTo
  # (revert "nothing to slash" → приземлився б хибний :failed при оптимістичному :breached).
  # Піднімаємо critical :field_audit (evasion-контекст) для юридично-ручного треку; контракт
  # лишається :active до людського рішення (позов / clawback-роадмеп ARCH.12). Повертає :evaded
  # → BurnCarbonTokensWorker трактує як non-slash (без надгробка/трансляції). Метрика attempts
  # НЕ інкрементиться (спроби on-chain не було). Клас той самий, що freeze, але причина інша:
  # тут доказ A Є, бракує АКТИВІВ (не magnitude/evidence). Дзеркало freeze_for_field_audit!.
  def escalate_evasion!(requested_burn)
    context = @source_tree ? "дерево #{@source_tree.did}" : "кластер ##{@cluster.id}"

    Rails.logger.warn "🏃 [SLASH.2] NaasContract ##{@naas_contract.id} (#{context}): on-chain баланс порушника ≈0 — активи виведено ПЕРЕД слешем (запит #{requested_burn} SCC). Slash не транслюємо (нема чого палити) → Field Audit / юридичний трек."

    EwsAlert.escalate_field_audit!(
      cluster: @cluster,
      # Та сама причина, що у freeze: «дерево»/«кластер» — проза, тож вона в ключі.
      message_key: @source_tree ? "slash_evasion_tree" : "slash_evasion_cluster",
      message_params: (@source_tree ? { tree_did: @source_tree.did } : { cluster_id: @cluster.id })
                        .merge(requested_burn: requested_burn)
    )

    # [ARCH.57] Evasion-вердикт → ланцюг (chain-only): доказ A є, активи виведено —
    # юридичний трек.
    record_audit_trail!(
      action: "slash_verdict_evasion",
      organization_id: @naas_contract.organization_id,
      auditable: @naas_contract,
      metadata: { verdict: "evaded_pre_slash", requested_burn: requested_burn,
                  cluster_id: @cluster.id, source_tree_did: @source_tree&.did }
    )

    :evaded
  end

  # [ARCH.45] Intent-marker :pending ДО on-chain slash (sourceable: contract = ключ in-flight
  # guard). mark_as_sent! проставить tx_hash після broadcast; BlockchainConfirmationWorker
  # дорезолвить :sent→:confirmed/:failed. Раніше створювався одразу :confirmed за фактом слешу.
  def create_slash_intent!(amount, reason)
    # Пастка "Останнього дерева": якщо весь кластер мертвий, audit_wallet буде nil.
    # У такому разі прив'язуємо запис до самого кластера, а не до дерева-носія.
    audit_wallet = @source_tree&.wallet || @cluster.trees.active.first&.wallet

    BlockchainTransaction.create!(
      wallet:     audit_wallet,
      cluster:    audit_wallet.nil? ? @cluster : nil,
      sourceable: @naas_contract,
      to_address: @organization.crypto_public_address,
      amount:     amount,
      token_type: :carbon_coin,
      # [ARCH.95] Напрямок ЯВНИЙ. `sourceable: NaasContract` лишається — але тепер
      # він відповідає на інше питання («цей burn є слешем», база розміру `05_05 §3`),
      # а не на «це burn». Знак `amount` тут ДОДАТНИЙ і напрямку не несе.
      direction:  :burn,
      status:     :pending,
      # [SLASH-1] Префікс теж належить вердикту, не лише причина: «🚨 SLASHING» над
      # добровільним виходом є твердженням про провину, а не описом руху коштів.
      notes:      @contractual ? "📄 ФОРФЕЙТУРА: монети списано. Підстава: #{reason}." : "🚨 SLASHING: Кошти вилучено. Причина: #{reason}."
    )
  end

  # Розраховує частку біомаси, що підлягає вилученню (damage_ratio ∈ [0,1], або nil). Гілки:
  #   • contractual          → погоджене повне вилучення (early-exit форфейтура; ПЕРШОЮ — не damage-based)
  #   • critical>0           → пропорційно (частка АКТИВНИХ дерев ≥ порога — канон §3)
  #   • source_tree          → загибель конкретного дерева (1/ліс-на-момент-події)
  #   • дані Є, 0 critical    → ліс здоровий → 0 шкоди → 0 slash
  #   • genuine no-data → nil → magnitude indeterminate → `perform` робить freeze (§3.2 асиметрія,
  #     дзеркало `flag_data_blackout!`), НЕ 100% worst-case
  # [ARCH.46] Поріг = `AiInsight.slash_stress_threshold` (той САМИЙ DAO-live поріг, що ТРИГЕРИТЬ
  # слеш у `ContractHealthCheckService` — GOV.1; раніше хибне `≥ 1.0` → помірний стрес давав
  # critical=0 → 100% over-burn). Дата прокинута від health-check (`effective_target_date`).
  #
  # [⚖️ 2026-07-30] Третя вісь того ж інваріанта — МНОЖИНА дерев. Тригер міряє частку від
  # АКТИВНИХ (`DailyHealthRouter`), а розмір міряв від УСІХ, вкл. `deceased`/`removed`. Мертве
  # дерево телеметрії не шле → інсайту не має → в чисельник не входило, лише в знаменник, тобто
  # кладовище РОЗБАВЛЯЛО шкоду: що більше вирубано, то менший відсоток за решту — напрямок,
  # протилежний наміру §3. Тепер обидві половини міряють один ліс. Мертвих свідомо НЕМА і в
  # чисельнику: смерть має власний тракт (`Tree#trigger_slashing_protocol` → `source_tree`), і
  # тримати її ще й у статистичній частці = подвійний рахунок за ту саму подію.
  def calculate_damage_ratio
    # Contractual — ПЕРШОЮ: повне погоджене вилучення, не залежить ані від damage, ані від
    # наявності дерев; AiInsight-запит зайвий.
    return 1.0 if @contractual

    # Знаменник = живий ліс на МОМЕНТ ПОДІЇ, і читається РЕАЛЬНИМ COUNT, а не денормалізованим
    # `active_trees_count`: лічильник тримають Tree-колбеки, а `update_columns`/`update_all` їх
    # обходять. Розбіжність тут не косметична — чисельник іде живим запитом, тож занижений
    # лічильник МНОЖИТЬ damage, а занижений до нуля дав би `1.0/0 = Infinity` → `.min` → рівно
    # 100% тихого спалення (той самий over-burn клас, що ARCH.46 і закривав). Тригер лишається
    # на денормалізованому свідомо: він щодня обходить УСІ кластери, а тут — один контракт і
    # необоротні гроші, тож точність дорожча за COUNT(*).
    total_trees = @cluster.trees.active.count

    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree", analyzable_id: @cluster.trees.active.select(:id), target_date: effective_target_date
    )
    # 🔴 Дві осі ОДНОГО інваріанта «тригер ≡ розмір» — міряти ТИМ САМИМ порогом і рахувати
    # ДЕРЕВА, а не РЯДКИ. (1) Поріг — DAO-live метод, не константа: константа = лише
    # default-fallback, тож будь-який голос за `:stress_threshold` (bounds 0.5..1.0) розводив
    # поріг спрацювання і поріг розміру, а обидва доми стверджували протилежне.
    # (2) `.distinct` по `analyzable_id`: unique-індекс `idx_ai_insights_unique_report` включає
    # `model_source`, тобто два інсайти на одне дерево за добу легальні за дизайном
    # (oracle-consensus), а генератор пише `model_source` NULL — PG unique NULL-и не дедуплікує.
    # Голий `.count` давав одному дереву вагу двох; від 100% рятував лише `.min`-clamp нижче,
    # тобто симптом маскувався. Дзеркало `DailyHealthRouter#critical_count`. [⚖️ 2026-07-30]
    # ⊕ [SLASH-1] Поріг береться ЗАФІКСОВАНИЙ тригером (`effective_stress_threshold`), а не
    # перечитується тут: доти ARCH.46 звів обидві половини на один ДЕНЬ, лишивши їм два
    # РІЗНІ моменти читання порога — те саме розходження, лише іншою координатою.
    critical_count = daily_insights.where("stress_index >= ?", effective_stress_threshold)
                                   .select(:analyzable_id).distinct.count

    # Ділення в обох гілках безпечне БЕЗ zero-guard, і доказ тримається лише тому, що чисельник
    # і знаменник тепер з ОДНОГО джерела (жива `trees.active`): `critical > 0` ⇒ у скоупі є
    # активні дерева ⇒ `total_trees > 0`. З денормалізованим лічильником ця імплікація була б
    # НЕдоведеною — два джерела правди не дають виводити одне з одного.
    if critical_count.positive?
      # 🔴 [SLASH-1, ⚖️ 2026-08-26] Знаменник — ті, хто СВІДЧИВ цієї доби, а не всі
      # `active`. Мовчазне дерево в чисельник потрапити не може (немає інсайту), а в
      # знаменнику стояло — тобто його мовчання рахувалось свідченням про ВИЖИВАННЯ й
      # РОЗБАВЛЯЛО шкоду тих, хто справді свідчив. 100 зрубаних зі 101 давали ≈1%.
      # Множина тепер ОДНА в обох частинах дробу — той самий інваріант ARCH.46
      # «тригер ≡ розмір», застосований ще раз: чисельник і знаменник беруться з
      # `daily_insights`, тож розійтись їм ніде.
      # ⛔ Не порушує «тиша НІКОЛИ не slash»: мовчазне дерево штрафу не дістає — воно
      # лише перестає бути доказом здоров'я (скіл `backend` #61: машина знімає
      # твердження про СИГНАЛ, не про світ за ним).
      # ⚠️ Гілка нижче (`@source_tree`) СВІДОМО лишається на `total_trees`: вона судить
      # прямий факт смерті, а не вибірку, тож її знаменник — «ліс до події».
      witnessing = daily_insights.select(:analyzable_id).distinct.count
      # 🔴 [SLASH-1 §7] Поріг ВИРОДЖЕННЯ переїхав сюди РАЗОМ зі знаменником, і без
      # нього перенос був би не фіксом, а множником: при малій вибірці свідків
      # будь-яке одне критичне дерево дає ≈100%, тоді як стара шкала давала
      # частку від усього кластера. Тригерний шлях це вже гейтує
      # (`ContractHealthCheckService` → `:insufficient_sample`), але ПРЯМІ тригери
      # (смерть дерева · dClimate · contractual) приходять сюди повз нього —
      # тобто гард стояв би на одній гілці розвилки, а гроші текли б другою.
      # Межа деривується з САМОГО порога (`1 / slash_fraction`), як і в §7, тож
      # DAO-зміна рухає її автоматично. Нижче межі — `nil`, тобто той самий
      # genuine-no-data шлях: `freeze_for_field_audit!`, НІКОЛИ авто-burn.
      # 🔴 І межа НЕ коротить метод: нижче неї статистична гілка лише ВІДМОВЛЯЄТЬСЯ,
      # а оцінка йде далі. Голий `return nil` глушив би й гілку `@source_tree` —
      # тобто вироджена вибірка скасовувала б вирок за ПРЯМИМ ФАКТОМ смерті, який
      # вибірки не питає взагалі. Freeze лишається лише там, де критичні дерева Є,
      # а прямого факту НЕМА: тоді судити нема з чого й нема кому, крім людини.
      if witnessing >= degeneracy_floor
        [ critical_count.to_f / witnessing, 1.0 ].min   # частка тих, хто свідчив
      elsif @source_tree.blank?
        nil
      else
        source_tree_damage_ratio(total_trees)
      end
    elsif @source_tree.present?
      # «Ліс ДО події» — і ТІЛЬКИ тут: жертву додаємо в знаменник, якщо її вже нема серед
      # активних (інакше кластер із двох дерев дав би 1/1 = 100% замість чесних 1/2, а останнє
      # дерево — ділення на нуль). Предикат саме `!active?`, а не «вмерло»: сенс += 1 —
      # «включи жертву в ліс», щоб знаменник збігався з множиною чисельника, тож він однаково
      # правильний для dormant-джерела (dClimate шле `@alert.tree_id`, який може бути живим —
      # тоді дерево ВЖЕ в `total_trees` і += 1 не спрацьовує).
      # ⚠️ Свідомо НЕ глобально: у статистичній гілці труп не рахується ні тут, ні в чисельнику
      # (канон §3), бо смерть має власний тракт. Глобальний += 1 розбавляв би частку живого лісу.
      # 🔴 [SLASH-1, ⚖️ 2026-08-26] Чисельник — УСІ трупи доби, не один. Доти тут
      # стояло `1.0 / (total + 1)`, тобто N зрубаних дерев давали розмір ОДНОГО, а
      # решта N−1 не входили ні в чисельник, ні в знаменник — і канон §2 обіцяв
      # «до 100% при повній загибелі», чого ця форма дати не могла НІКОЛИ (100
      # зрубаних зі 101 → ≈0,25% після `^GAMMA`).
      # `.max` із мертвим source — це і zero-guard, і зворотна сумісність: у дерев,
      # що вмерли ДО появи `status_changed_at`, колонка NULL, тож без нього
      # мертвий кластер дав би `0/0`. При одному трупі формула тотожна старій.
      source_tree_damage_ratio(total_trees)
    elsif daily_insights.exists?
      0.0                                              # дані Є, ліс здоровий → 0 шкоди → 0 slash
    end
    # else: нуль AiInsight-записів (вкл. кластер без жодного живого дерева) → nil (genuine
    # no-data) → perform → freeze_for_field_audit!, а НЕ старе `total_trees.zero? → 1.0`.
  end

  # Гілка «ліс ДО події» — винесена в ОДИН дім, бо кличуть її ДВА входи: звичайний
  # source_tree-тракт і статистична гілка, що відмовилась через вироджену вибірку.
  # Порізно вони розійшлися б тихо — рівно клас, який цей файл і лікує.
  def source_tree_damage_ratio(total_trees)
    dead = [ dead_tree_count, @source_tree.active? ? 0 : 1 ].max
    victims = @source_tree.active? ? dead + 1 : dead
    [ victims.to_f / (total_trees + dead), 1.0 ].min
  end

  # [ARCH.46] Дата для AiInsight-запиту: прокинута від `ContractHealthCheckService` (де порахована
  # й де відпрацював blackout-guard), інакше дефолт [ARCH.100] `AiInsight.reporting_date`
  # (tree-death/dClimate/contractual) — той САМИЙ якір, яким інсайти записані.
  def effective_target_date
    @target_date || AiInsight.reporting_date
  end

  # [SLASH-1] Скільки дерев кластера перейшли в термінальний статус у добу вироку.
  #
  # Носій — `trees.status_changed_at`, а НЕ `MaintenanceRecord.performed_at`: ту
  # дату вводить у форму сам оператор (валідація лише `<= Time.current`), тобто на
  # грошовому шляху вона була б клієнт-контрольованим чисельником — подати
  # демонтажі поза вікном і обнулити власне спалення. Розбір трьох кандидатів —
  # у шапці міграції `add_status_changed_at_to_trees`.
  #
  # ⚠️ Вікно якореться на смерті SOURCE, а НЕ на `effective_target_date` — і це не
  # деталь: `AiInsight.reporting_date` є ВЧОРАШНЬОЮ UTC-добою (інсайти рахуються за
  # вчора), тоді як трупи вмирають у момент вироку. Прив'язка до дати звітності
  # давала б нуль на кожній реальній вирубці — спіймано піном, не читанням.
  # Предмет лічби — один ІНЦИДЕНТ (багато смертей в одному вікні), тож якір
  # природний саме такий. UTC-межі, бо колонку пишемо в UTC.
  def dead_tree_count
    anchor = @source_tree.status_changed_at&.utc || Time.current.utc
    @cluster.trees
            .where(status: %i[removed deceased])
            .where(status_changed_at: anchor.beginning_of_day..anchor.end_of_day)
            .count
  end

  # [05_05 §3 Slashing curve] Progressive CONVEX penalty:
  #   slash_ratio = clamp(damage_ratio^GAMMA × min(penalty_factor, PENALTY_FACTOR_MAX), 0, 1.0)
  # Replaces the old LINEAR burn (total × damage_ratio — no GAMMA, no penalty_factor; the
  # verified code↔doc divergence, 05_05 §3 / 04_02 §11). GAMMA>1 makes the curve convex:
  # a small loss is punished gently (d=0.10 → ~5%) so an investor isn't wiped out over a
  # minor incident, yet full negligent loss reaches 100% (d=1.0, pf=1.0 → 1.0) — the
  # "no dead-zone" property (the old min(…, 0.40) ceiling that flat-lined 40%→100% damage
  # is removed). penalty_factor — baseline; cause-driven uplift із comms-loss DE-correlation
  # будує #calculate_penalty_factor (SLASH-1 §6, INERT за SystemParameter до DAO-confirm).
  # GAMMA + PENALTY_FACTOR_MAX are DAO-governed (SystemParameter ← ProtocolParameters.sol).
  def calculate_slash_ratio(damage_ratio, penalty_factor = DEFAULT_PENALTY_FACTOR)
    return 0.0 if damage_ratio <= 0.0

    effective_pf = [ penalty_factor, penalty_factor_max ].min
    ((damage_ratio**slash_gamma) * effective_pf).clamp(0.0, 1.0)
  end

  # [SLASH-1 §3/§6] Cause-driven penalty_factor (gated). INERT за замовчуванням
  # (gate :slash_cause_uplift_enabled, default false → baseline, без зміни живої поведінки);
  # активація — DAO/founder перед mainnet (05_05 §3). Сорсить сигнали → #combine_penalty_factor.
  def calculate_penalty_factor
    return DEFAULT_PENALTY_FACTOR unless cause_uplift_enabled?

    combine_penalty_factor(
      no_ack:         comms_no_ack?,
      no_maintenance: critical_unmaintained?
    )
  end

  # Pure de-correlation combiner (SLASH-SAFETY §6): comms-correlated сигнали (спільний root-cause
  # «вузол offline») комбінуються через max(), НЕ суму (інакше один outage карається
  # багаторазово — збитий/вкрадений шлюз); фізична халатність незалежна → additive. Виокремлено
  # від сорсингу, щоб інваріант був явним. ⚠️ Із 2026-09-03 comms-клас має ОДИН член (no-ack), тож
  # `max()` тут вироджений до нього — носій де-кореляції повертається разом із другим членом.
  # Cluster-wide blackout відведено раніше (ContractHealthCheckService).
  def combine_penalty_factor(no_ack:, no_maintenance:)
    comms_loss  = no_ack ? PF_NO_ACK : 0.0
    independent = no_maintenance ? PF_NO_MAINTENANCE : 0.0

    DEFAULT_PENALTY_FACTOR + comms_loss + independent
  end

  # DAO/founder activation gate (05_05 §3). Default OFF → uplift inert до mainnet-confirm.
  # `defined?`-memo (не ||=), бо легітимне значення — false.
  def cause_uplift_enabled?
    return @cause_uplift_enabled if defined?(@cause_uplift_enabled)

    @cause_uplift_enabled = ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:slash_cause_uplift_enabled, default: false)
    )
  end

  # [comms-correlated] «No ack»: критичний node/gateway-offline алерт лишається непідтвердженим
  # (scope `critical` = severity_critical.unresolved).
  # [P1-3] Whitelist саме node-offline типів (§6 root-cause «вузол/шлюз offline»): `queen_offline`
  # (dead-man switch), `queen_uplink_lost` (Helium-крик), `system_fault` (шлюз доповів про збій).
  # Раніше рахувався БУДЬ-який critical (крім field_audit), включно з `vandalism_breach`, що ВЖЕ дав
  # `positive_a?` → той самий tamper-алерт накручував penalty на СОБІ (self-ref → множник завжди
  # сідав на стелю). tamper/fire/chainsaw = не comms-loss (свій root-cause), сюди не рахуємо.
  def comms_no_ack?
    @cluster.ews_alerts.critical
            .where(alert_type: [ :queen_offline, :queen_uplink_lost, :system_fault ])
            .exists?
  end

  # [independent] Фізична халатність: критичний EwsAlert без жодного MaintenanceRecord по спливу
  # вікна реакції (оператора алертнули, але він не виїхав). Незалежний від comms-loss → additive.
  def critical_unmaintained?
    # [SLASH-1 gap-D] Виключаємо :field_audit — наш власний audit-виклик «слухай» без
    # MaintenanceRecord ≠ операторська недбалість; рахуємо лише реальні tree/hardware-алерти.
    # [P1-3] Виключаємо і :vandalism_breach — коли він дав `positive_a?` (єдиний шлях до Cat-A
    # slash), «не виїхав на tamper» вже покарано НЕОБОРОТНИМ slash → накручувати penalty на тому
    # самому алерті = self-ref подвійне. Незалежна фізична недбалість = реальні tree/hardware-алерти.
    # [SLASH-1] І :firmware_fault — софт-збій прошивки vendor-attributable (наш баг,
    # лікується OTA з бекенду): «не виїхав на mruby-crash» ≠ фізична недбалість оператора.
    # [SEC.20] І :firmware_reverted — той самий vendor-клас, але ТЕРМІНАЛЬНИЙ (не
    # самогаситься; лікується лише re-issue OTA версією > спаленої) → без виключення
    # штрафував би оператора гарантовано, щойно cause_uplift увімкнеться.
    # [SLASH-1 gap-E] Виключаємо МАШИННИЙ resolve. `severity_critical` (без `.unresolved`)
    # тут свідомий — форестер сам може закрити власний алерт (`alerts_controller#resolve`,
    # resolve ≡ ack), тож фільтр по unresolved знімав би штраф одним кліком. Але коли алерт
    # закрила СИСТЕМА (Королева повернулась в ефір сама — GatewayStalenessSweepWorker), виїзд
    # не був потрібен нікому → MaintenanceRecord не може існувати за визначенням → рядок
    # інакше читався б як «недбалість» ВІЧНО (ретеншену нема, а `created_at`-предикат
    # рахується в момент слешу, тож транзієнтна тиша латчила б PF_NO_MAINTENANCE назавжди).
    # Дискримінатор: `resolve!(user:)` лишає `resolved_by` NULL лише на машинному шляху —
    # обидва людські сайти передають user. Звуження свідоме: оператор, що полагодив Королеву
    # без paperwork, штрафу уникне — false-negative, а burn необоротний (05_05 §3.2 асиметрія).
    # [ARCH.58] І :actuator_stuck — Rails загубив слід ВЛАСНОЇ команди (втрачена
    # scheduled-джоба / крах між комітом видачі та плануванням). Той самий
    # vendor-attributable клас, що firmware_fault: виїзд лісника нашого
    # bookkeeping-збою не лікує, а карати оператора за нього — те саме, що
    # штрафувати за mruby-crash.
    # [ARCH.75] І :emergency_response_undeliverable — платформа сама відмовилась
    # видати аварійну команду, бо стеля пристрою чи каденс шлюза її не пропускають.
    # Це наша конфігурація, а не операторська недбалість: виїзд лісника не полагодить
    # число, яке ми ж і задали. Той самий vendor-attributable клас, що actuator_stuck.
    stale_critical = @cluster.ews_alerts.severity_critical
                             .where.not(alert_type: [ :field_audit, :vandalism_breach, :firmware_fault,
                                                      :firmware_reverted, :firmware_canary_trip,
                                                      :actuator_stuck, :emergency_response_undeliverable ])
                             # rubocop:disable Rails/WhereNotWithMultipleConditions -- заперечення
                             # КОНʼЮНКЦІЇ тут і є наміром [SLASH-1 gap-E]: викидаємо рівно
                             # машинно-закриті (`resolved` І `resolved_by` NULL), лишаючи
                             # і відкриті, і закриті людиною.
                             .where.not(status: :resolved, resolved_by: nil)
                             # rubocop:enable Rails/WhereNotWithMultipleConditions
                             .where(created_at: ..30.minutes.ago)
    return false unless stale_critical.exists?

    stale_critical.where.not(
      id: MaintenanceRecord.where.not(ews_alert_id: nil).select(:ews_alert_id)
    ).exists?
  end

  # [SLASH-1 §7] Мінімальна вибірка свідків, нижче якої статистичний вирок не
  # виноситься. Деривується з порога, не хардкодиться: при `N < 1/f` добуток
  # `N × f` менший за одиницю, тобто БУДЬ-ЯКЕ одне дерево перетинає поріг і
  # «понад f» перестає бути статистичним твердженням. Для дефолтних 0.2 це N ≤ 4.
  def degeneracy_floor
    @degeneracy_floor ||= 1 / Rational(SystemParameter.current(:slash_threshold, default: 0.2).to_s)
  end

  # DAO-governed slash curve exponent (SystemParameter ← on-chain ProtocolParameters.sol).
  # Memoized per instance. Falls back to the canon default (1.3) when unset.
  def slash_gamma
    @slash_gamma ||= (@frozen_slash_gamma || SystemParameter.current(:slash_gamma, default: DEFAULT_SLASH_GAMMA)).to_f
  end

  # DAO-governed ceiling on the penalty MULTIPLIER (not the final slash_ratio). Memoized.
  def penalty_factor_max
    @penalty_factor_max ||= (@frozen_penalty_factor_max ||
      SystemParameter.current(:slash_penalty_factor_max, default: DEFAULT_PENALTY_FACTOR_MAX)).to_f
  end

  def handle_slashing_failure(error_msg, amount, ambiguous: false)
    Rails.logger.error "🛑 [Slashing Failure] ##{@naas_contract.id}: #{error_msg}"

    # Створюємо критичний алерт для ручного втручання Оракула
    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :system_fault,
      # `ambiguous` — окремий КЛЮЧ, а не префікс у рядку: «можливо-landed, НЕ
      # авто-повтор» — це проза, і раніше вона приклеювалась українською до
      # тексту виключення просто на місці виклику. `error` лишається сирим
      # текстом ЧУЖОГО виключення — його не локалізує жодна схема, це
      # діагностичний додаток, і так і має бути.
      message_key: ambiguous ? "burn_failure_ambiguous" : "burn_failure",
      message_params: { amount: amount, error: error_msg }
    )
  end
end
