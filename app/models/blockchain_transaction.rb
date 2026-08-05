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
  # @return [BlockchainTransaction]
  # @raise [ActiveRecord::RecordNotFound] if not found
  def self.find_with_partition_pruning(id, created_at = nil)
    scope = where(id: id)
    if created_at.present?
      time = created_at.is_a?(String) ? Time.iso8601(created_at) : created_at.to_time
      # Use a 1-second range to account for sub-second precision differences
      # between ISO 8601 (second precision) and DB timestamps (microsecond).
      # PostgreSQL still prunes to at most one partition for a 1-second window.
      scope = scope.where(created_at: time...(time + 1))
    end
    scope.first!
  rescue ArgumentError, TypeError, NoMethodError
    # Invalid format or unexpected type — fall back to unscoped lookup
    where(id: id).first!
  end

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

  # [ARCH.45 / ARCH.51] ЄДИНИЙ живий money-path intent-marker guard: незавершена tx у `window`
  # (включно з `:manual_review` — можливо-landed виплата під ручною звіркою блокує re-pay).
  # `window`-bound prunes RANGE-партиції. Покриває всю родину (burn 2h · Solana payout / insurance /
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
  # created_at-prune на цій гілці не б'є по гарячому шляху. SQL: (status=5) OR (status∈{0,4} ∧ у вікні).
  scope :unsettled_within, ->(window) {
    where(status: [ :pending, :sent, :manual_review ])
      .where("status = ? OR created_at > ?", statuses[:manual_review], window.ago)
  }

  # --- ДЕЛЕГУВАННЯ ---
  # Навігація через wallet (може бути nil для slashing-аудиту — тоді через cluster)
  delegate :organization, to: :wallet, allow_nil: true

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

    # Успішне підтвердження в мережі (виклик від BlockchainConfirmationWorker)
    event :confirm do
      before do |block_num, gas_cost|
        self.block_number = block_num if block_num.present?
        self.gas_used = gas_cost if gas_cost.present?
        self.confirmed_at = Time.current
        self.error_message = nil
      end
      transitions from: [ :sent, :processing ], to: :confirmed
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
      transitions from: [ :pending, :processing, :sent, :failed ], to: :failed
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
          tx_hash: tx_hash, error: error_message,
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

  def broadcast_status_change
    return unless wallet

    # Оновлення рядка транзакції в Wallet Ledger (підписка: [wallet, :transactions])
    Turbo::StreamsChannel.broadcast_replace_later_to(
      [ wallet, :transactions ],
      target: ActionView::RecordIdentifier.dom_id(self),
      html: Wallets::TransactionRow.new(tx: self).call
    )

    # Оновлення балансу при фінальних статусах (confirmed/failed)
    wallet.broadcast_balance_update if status_confirmed? || status_failed?
  end
end
