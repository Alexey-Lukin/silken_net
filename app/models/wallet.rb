# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Wallet < ApplicationRecord
  include EthAddressValidatable

  # --- ЗВ'ЯЗКИ (The Financial Fabric) ---
  belongs_to :tree
  # [ARCH.57] nullify (не delete_all): guard нижче — первинний захист (settled/in-flight
  # недоторкані), nullify — backstop дозволеного destroy (порожній/чисто-pending гаманець):
  # навіть ці рядки лишаються сиротами замість стирання (`wallet` на tx optional за дизайном —
  # cluster-sourced money вже живе без wallet, MRV.1). Масова таблиця: один UPDATE без
  # інстанціації — OOM-safe, як і колишній delete_all [Чорна Діра Пам'яті].
  has_many :blockchain_transactions, dependent: :nullify

  # [MRV.1] Settled/in-flight money-tx = докази під виданими кредитами (ISO 14064/Verra) —
  # хардделіт гаманця стер би trail. Порожній/чисто-pending гаманець видаляється вільно;
  # off-board з доказами = деактивація, не destroy.
  # prepend: true — guard стріляє ДО dependent-обробки (оголошеної вище).
  before_destroy :guard_mrv_evidence!, prepend: true

  # ⚡ [ВИПРАВЛЕНО: The Join Abyss]: Прямий зв'язок з організацією через денормалізований FK.
  # Замінює глибокий ланцюг wallet → tree → cluster → organization на один SELECT.
  belongs_to :organization, optional: true

  has_one :cluster, through: :tree

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :locked_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :esg_retired_balance, numericality: { greater_than_or_equal_to: 0 }
  # [MRV.1] watermark-курсор lineage (позиція останнього лога, спожитого mint-вікном)
  validates :lineage_cursor_log_id, numericality: { only_integer: true }, allow_nil: true

  # SCC = Silken Carbon Coin — public-facing alias for the internal balance column.
  # ⚠️ [ARCH.88] Ім'я БРЕШЕ: колонка тримає growth_points, тож аліас — ренейм, не
  # конверсія. Лишений як депрекований для вже-наявних Bearer/mobile-клієнтів
  # (публікується таблицею полів `04_03`); на шляху показу й на доказовому шляху
  # більше не вживається — там читається `balance` напряму.
  alias_attribute :scc_balance, :balance

  # [ARCH.87] One-Home резолву «чий це гаманець»: денормалізована колонка АБО
  # похідний ланцюг `tree → cluster → organization`. Обидві гілки звіряються з
  # ОДНІЄЮ організацією, тож периметр не ширшає; однозначність `OR` тримає
  # структурний інваріант «колонка не розходиться з ланцюгом» (носій —
  # `spec/quality/wallet_org_denormalization_spec.rb`).
  #
  # Дім свідомо ОДИН: `WalletPolicy::Scope` і org-скоуп транзакцій
  # (`BlockchainTransaction.for_organization`) беруть його звідси — дві копії
  # предиката розійшлися б тихо, і список гаманців почав би відповідати на
  # питання «чий це гаманець» інакше, ніж грошовий агрегат.
  scope :for_organization, lambda { |org_id|
    left_joins(tree: :cluster)
      .where("wallets.organization_id = :org OR clusters.organization_id = :org", org: org_id)
  }

  # Стандартний формат Ethereum/Polygon адреси для On-Chain операцій
  validates_eth_address :crypto_public_address, allow_blank: true

  # [KYC.1] KYC чіпляється до адреси-бенефіціара: власна адреса → власний статус;
  # зміна адреси = новий суб'єкт → скидання у pending + ре-верифікація.
  before_update :reset_hadron_kyc_on_address_change
  after_commit :enqueue_hadron_kyc_verification,
               if: -> { saved_change_to_crypto_public_address? && crypto_public_address.present? }

  # [KYC.1] Ефективний KYC-гейт мінтингу — статус БЕНЕФІЦІАРА адреси призначення
  # (дзеркало lock_and_mint!: власна адреса АБО custodial-адреса організації).
  # Custodial-гаманець (без власної адреси) успадковує статус організації.
  def kyc_approved_for_minting?
    if crypto_public_address.present?
      hadron_kyc_status == "approved"
    else
      organization&.hadron_kyc_status == "approved"
    end
  end

  # Троттлінг трансляції: оновлюємо UI не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" WebSocket-повідомлень при масовій телеметрії.
  # --- МЕТОДИ НАРАХУВАННЯ (Growth Credit) ---

  # Доступний баланс — це загальний баланс мінус заблоковані кошти (Pending транзакції).
  # Захищає від Double Spend: користувач не може витратити кошти, що вже відправлені в блокчейн.
  def available_balance
    balance - locked_balance
  end

  # Блокування коштів для Pending транзакцій (Double Spend Protection).
  # Кошти залишаються на балансі, але не доступні для витрат.
  # [BLOCKER FIX]: with_lock запобігає TOCTOU race condition — перевірка available_balance
  # та increment! тепер атомарні під SELECT ... FOR UPDATE.
  def lock_funds!(amount)
    with_lock do
      raise "⚠️ [Wallet] Недостатньо доступних коштів (Доступно: #{available_balance}, Потрібно: #{amount})" if available_balance < amount

      increment!(:locked_balance, amount)
    end
  end

  # Повернення заблокованих коштів після невдалої транзакції (Rollback).
  # [BLOCKER FIX]: with_lock запобігає race condition при одночасному rollback кількох TX.
  def release_locked_funds!(amount)
    with_lock do
      raise "⚠️ [Wallet] Спроба розблокувати більше, ніж заблоковано (Заблоковано: #{locked_balance}, Запит: #{amount})" if locked_balance < amount

      decrement!(:locked_balance, amount)
    end
  end

  # Викликається TelemetryUnpackerService після кожного успішного пакету даних від STM32.
  # Кожен подих дерева конвертується в бали росту.
  #
  # [BLOCKER FIX: Database Locking — Wiki 04_01]
  # Pessimistic lock (SELECT ... FOR UPDATE) запобігає race conditions
  # при одночасному надходженні тисяч пакетів телеметрії для одного дерева.
  # with_lock відкриває власну коротку транзакцію — lock тримається лише мілісекунди
  # (тільки на час INCREMENT), а не на всю тривалість commit_telemetry.
  # Це критично при 100+ млрд дерев та Sidekiq concurrency=15.
  def credit!(points)
    with_lock do
      increment!(:balance, points)
    end

    # 🔴 [UI.4, ⚖️ 2026-08-17] Коалесування, а не ТРОТЛ — і різниця тут грошова.
    #
    # Доти стояв `broadcast_balance_update if should_broadcast?` — leading-edge
    # з ВИКИДАННЯМ (`return false if Rails.cache.exist?`, вікно 10 с). Перший
    # кредит у вікні летів, решта гинули, тож рамка балансу застрягала на
    # ПЕРШОМУ значенні: виміряно прикладом — броадкаст ніс `10.0`, тоді як у
    # базі вже було `30.0`. Для леджера це «застаріло», для гаманця — показане
    # число, що розходиться з базою.
    #
    # ⚠️ І обіцянки власного коментаря той тротл не виконував: він казав «щоб
    # при 1 000 000 дерев не створювати ~16 000 повідомлень/сек», але ключ був
    # **per-WALLET** — мільйон дерев дає мільйон окремих ключів і ті самі
    # 16 000/с. Крос-флотового захисту він не давав ЗА ПОБУДОВОЮ.
    #
    # `Turbo::ThreadDebouncer` — той самий примітив, яким гем дебаунсить власні
    # refresh-броадкасти (`Turbo::Streams::Broadcasts#broadcast_refresh_later_to`):
    # новий виклик СКАСОВУЄ заплановане й планує своє, тож останній кадр
    # доїжджає завжди, а серія кредитів в одному батчі коштує один broadcast.
    # ⚠️ Стеля: дебаунсер живе в `Thread.current`, тобто коалесує в межах ОДНОГО
    # треда; глобального капу немає ні тут, ні в гема — і він свідомо не
    # будується, доки навантаження не виміряне ([`00_07`] UI.4).
    Turbo::ThreadDebouncer.for("wallet-balance-#{id}").debounce { broadcast_balance_update }
  end

  # --- МЕТОДИ ЕМІСІЇ (Web3 Minting) ---

  # Конвертація накопичених балів росту в реальні токени SCC/SFC у мережі Polygon
  def lock_and_mint!(points_to_lock, threshold, token_type = :carbon_coin)
    # 1. ПЕРЕВІРКА ЖИТТЄЗДАТНОСТІ
    raise "🛑 [Wallet] Дерево не активне. Мінтинг заборонено." unless tree.active?
    return if threshold.to_f <= 0

    # 2. ПОШУК АДРЕСИ ПРИЗНАЧЕННЯ
    # Пріоритет: Власний гаманець дерева -> Гаманець Організації (Власника)
    target_address = crypto_public_address.presence || organization&.crypto_public_address

    if target_address.blank?
      raise "🛑 [Wallet] Відсутня крипто-адреса для мінтингу (Tree чи Organization)"
    end

    tx = transaction do
      # 3. PESSIMISTIC LOCKING (Захист від Race Conditions під час мінтингу)
      lock!

      if available_balance < points_to_lock
        raise "⚠️ [Wallet] Недостатньо балів (Доступно: #{available_balance}, Потрібно: #{points_to_lock})"
      end

      tokens_to_mint = (points_to_lock.to_f / threshold).floor
      return if tokens_to_mint.zero? # Немає сенсу створювати транзакцію на 0 токенів (курсор НЕ рухається)

      # [ARCH.94] Блокуємо рівно СКОНВЕРТОВАНЕ, а не запитане. Некратний
      # `points_to_lock` (25 000 при порозі 10 000) дає 2 токени, і залишок 5 000
      # осідав у `locked_balance` під нуль монет — НАЗАВЖДИ, бо за ратифікованою
      # reserve-семантикою (`04_01 §6`) locked не звільняється взагалі.
      # Клампінг тут не ховає помилку викликача — він виконує визначення, яке
      # канон уже дає цій колонці: locked_balance = бали, позначені СКОНВЕРТОВАНИМИ.
      # Блокувати більше, ніж сконвертовано, означало б, що колонка бреше про
      # власний зміст. Живий викликач (`EvaluateTreeBatchWorker`) завжди передає
      # кратне, тож його поведінка не змінюється; гілка озброїлась би першим новим.
      converted_points = tokens_to_mint * threshold
      if converted_points != points_to_lock
        Rails.logger.warn "⚠️ [Wallet ##{id}] Некратний points_to_lock=#{points_to_lock} " \
                          "при порозі #{threshold}: блокуємо #{converted_points} (#{tokens_to_mint} токенів), " \
                          "решта лишається доступною [ARCH.94]"
      end

      # 4. БЛОКУВАННЯ КОШТІВ (Pending Balance Protection)
      # Замість негайного списання з balance, блокуємо кошти в locked_balance.
      # Це захищає від Double Spend: кошти недоступні, але залишаються на балансі
      # до фіналізації транзакції в блокчейні.
      increment!(:locked_balance, converted_points)

      # [MRV.1] Lineage-вікно вимірів (під тим самим wallet-локом — дешеве: 1 SELECT позиції):
      # (курсор .. останній лог ≤ now−GRACE]. GRACE — щоб лог, що комітиться зараз, не випав
      # з вікон назавжди (Mrv::WINDOW_GRACE). Курсор рухається ЛИШЕ разом зі створенням tx
      # і монотонно (fail! мінта його НЕ відкочує — вікна чіпляються до СПРОБ, успішний
      # кредит у bundle успадковує вікна failed-попередників). Порожнє вікно = from==to.
      window_upper = tree.telemetry_logs
                         .where(created_at: ..(Time.current - Mrv::WINDOW_GRACE))
                         .order(created_at: :desc, id: :desc).pick(:created_at, :id)
      # Монотонний clamp (clock-regression / майбутній ретеншн-дроп): верхня межа
      # НЕ вище курсора = аномалія — вікно порожнє, курсор стоїть (інакше наступне
      # вікно перекрило б уже-атрибутовані логи, double-attribution). `.to_i`:
      # непарний курсор (id nil при рівних часах) дає <=> nil — safe-degrade у
      # clamp, НЕ NoMethodError у mint-транзакції (fail-open принцип).
      if window_upper && lineage_cursor_at &&
         (window_upper <=> [ lineage_cursor_at, lineage_cursor_log_id ]).to_i <= 0
        window_upper = nil
      end
      window_to_at, window_to_id =
        window_upper || [ lineage_cursor_at, lineage_cursor_log_id ]

      tx_record = blockchain_transactions.create!(
        amount: tokens_to_mint,
        token_type: token_type,
        status: :pending,
        to_address: target_address,
        locked_points: converted_points,
        telemetry_window_from_at: lineage_cursor_at,
        telemetry_window_from_id: lineage_cursor_log_id,
        telemetry_window_to_at: window_to_at,
        telemetry_window_to_id: window_to_id,
        telemetry_lineage_version: Mrv::TelemetryLeaf::LEAF_VERSION,
        notes: "Конвертація #{converted_points} балів росту (Поріг: #{threshold})."
      )

      update!(lineage_cursor_at: window_to_at, lineage_cursor_log_id: window_to_id) if window_upper

      tx_record
    end

    # `unless tx`-then dead: transaction-блок завжди завершується create! (non-nil) або
    # виходить з методу раніше (`return if tokens_to_mint.zero?` / raise) — tx тут non-nil;
    # guard = financial-safety-defensive проти зміни семантики блоку (§B.4 leave).
    return unless tx

    # [MRV.1] Корінь вікна — ПІСЛЯ коміту і fail-open: обчислення (SELECT вікна + N×sha256)
    # не тримає wallet-лок і НІКОЛИ не валить мінт (прецедент best-effort audit-trail);
    # rescue → root лишається NULL + WARN + метрика (bundle покаже unsealed).
    attach_lineage_root(tx)

    # 5. ЛОГУВАННЯ ТА ОНОВЛЕННЯ UI
    # [TRUSTLESS]: MintCarbonCoinWorker тепер працює з telemetry_log_id (oracle-driven flow).
    # Фактичний мінтинг запускається через OracleCallbacksController після верифікації
    # IoTeX + Chainlink, або через TokenomicsEvaluatorWorker → BlockchainMintingService.call_batch.
    Rails.logger.info "💎 [Wallet] Створено запит на мінтинг #{tx.amount} #{token_type} для #{target_address}."

    broadcast_balance_update
    tx
  end

  # [MRV.1] Merkle-корінь lineage-вікна tx (Mrv::LineageWindow — One-Home запиту).
  def attach_lineage_root(tx)
    root = Mrv::LineageWindow.root_for(tx)
    tx.update!(telemetry_merkle_root: root) if root
  rescue StandardError => e
    Rails.logger.warn "⚠️ [MRV.1] Lineage-root failed для tx ##{tx.id} (мінт НЕ зачеплено): #{e.message}"
    SilkenNet::Metrics::LINEAGE_ROOT_FAILURES_TOTAL.increment
  end

  # Трансляція оновленого балансу через Turbo Streams.
  #
  # 🔴 Стрім — `[self, :transactions]`, а НЕ голий `self`. Голий стрім не слухала
  # жодна сторінка (`Wallets::Show` підписана саме на композитний), тож ця
  # трансляція не доходила НІКУДИ з дня написання. Наслідок був не косметичний:
  # баланс тягнеться лінивим turbo-frame'ом рівно ОДИН раз, нічого його потім не
  # перечитує — тобто цифра протухала після завантаження сторінки назавжди.
  #
  # Payload — локаль-вільна заглушка (клас 2, `04_04 §8.1а`): див. `BalanceFrameStub`,
  # там же й причина, чому не можна слати сам `BalanceDisplay`.
  def broadcast_balance_update
    Turbo::StreamsChannel.broadcast_replace_to(
      [ self, :transactions ],
      target: Wallets::BalanceFrame.dom_id(id),
      html: Wallets::BalanceFrameStub.new(
        wallet_id: id,
        src: Rails.application.routes.url_helpers.balance_wallet_path(self)
      ).call
    )
  end

  private


  # [MRV.1] Абортить destroy за наявності settled/in-flight money-tx (докази MRV).
  # [E.60 Фаза 1б] + tx із archive_batch_id: стемпнутий tx = член archive-батчу
  # (root міг поїхати on-chain / артефакт запінено) — видалення wallet стерло б
  # вікна і дало pin-воркеру ХИБНИЙ mismatch на легальну операцію.
  def guard_mrv_evidence!
    evidence = blockchain_transactions.where(status: [ :confirmed, :sent, :manual_review ])
                                      .or(blockchain_transactions.where.not(archive_batch_id: nil))
    return unless evidence.exists?

    errors.add(:base, "Wallet має settled/in-flight/архів-стемпнуті blockchain-транзакції (MRV-докази) — деактивуй, не видаляй")
    throw :abort
  end

  # [KYC.1] Явний одночасний сет статусу (verify-воркер / seeds) має пріоритет.
  def reset_hadron_kyc_on_address_change
    return unless will_save_change_to_crypto_public_address?
    return if will_save_change_to_hadron_kyc_status?

    self.hadron_kyc_status = "pending"
  end

  def enqueue_hadron_kyc_verification
    HadronKycVerificationWorker.perform_async("Wallet", id)
  end
end
