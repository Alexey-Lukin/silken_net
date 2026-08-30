# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [BLOCKER-2] Модель для зберігання L1 Ethereum state root anchoring записів.
# Забезпечує аудит-трейл: { state_root, tx_hash, anchored_at, block_number }.
# [BLOCKER-6] Зберігає компоненти state_root (total_growth_points, total_scc_supply,
# total_sfc, active_tree_count, chain_hash, anchored_at) для незалежної верифікації
# зовнішнім аудитором. [ARCH.97] Дві перші — РІЗНІ величини: бали офчейн-леджера
# ⊥ чинний monetary supply (Σmints − Σburns, дзеркало on-chain `totalSupply()`);
# доти перша стояла тут під іменем другої. ⚠️ Ім'я каже «supply», а НЕ «minted»:
# величина не кумулятивна — slash її зменшує, тож «змінтоване» брехало б після
# першого ж спалення.
class EthereumAnchor < ApplicationRecord
  # --- СТАТУСИ ---
  enum :status, {
    pending: 0,     # State root обчислено, транзакція ще не відправлена
    sent: 1,        # Транзакція відправлена в мемпул, чекаємо підтвердження
    confirmed: 2,   # Транзакція підтверджена в L1 блоці (з достатньою глибиною проти reorg)
    failed: 3,      # storeStateRoot revert на рівні контракту, або guard відправлення (balance)
    manual_review: 4 # [ARCH.66] broadcast, але доля невідома після poll-SLA — людська звірка на etherscan
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :state_root, presence: true, uniqueness: true,
            format: { with: /\A[a-f0-9]{64}\z/, message: "must be a 64-char hex SHA-256" }
  validates :total_growth_points, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_scc_supply, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :chain_hash, presence: true
  validates :anchored_at, presence: true
  validates :tx_hash, uniqueness: true, allow_nil: true,
            format: { with: /\A0x[a-fA-F0-9]{64}\z/, message: "must be a valid Ethereum tx hash" },
            if: -> { tx_hash.present? }
  # [ARCH.66 companion] manual_review НЕ вимагає tx_hash: resume-ambiguous escalate (нижче) створює
  # `:manual_review` без hash (перший broadcast досяг мережі, tx_hash втрачено у crash-вікні —
  # оператор шукає за address+nonce). Poller-шлях manual_review фактично несе tx_hash (успадкований
  # з `:sent`). Дзеркало `04_01` §EthereumAnchor: presence лише для sent/confirmed.
  validates :tx_hash, presence: true, if: -> { status_sent? || status_confirmed? }
  validates :block_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :gas_used, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  # [ARCH.66 companion] nonce broadcast'у — персиститься ДО transact, щоб resume ре-використав
  # той самий слот (same-nonce, не N+1). Nil доти, доки anchor не дійшов до broadcast.
  validates :nonce, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :error_message, length: { maximum: 500 }, allow_nil: true
  # [ARCH.12 Фаза 1а] Merkle-якір: version-умовні (legacy flat-рядки root_version=0 лишаються
  # валідними на resume-update!). window_from nullable і для v1 — перший merkle-якір =
  # from-genesis вікно (prev confirmed v1 ще не існує).
  validates :root_version, inclusion: { in: [ 0, 1 ] }
  validates :leaf_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :subtree_roots, presence: true, if: -> { root_version == 1 }
  validates :window_to, presence: true, if: -> { root_version == 1 }

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: :confirmed) }
  scope :latest_confirmed, -> { status_confirmed.order(created_at: :desc).first }
  scope :in_flight, -> { where(status: [ :pending, :sent ]).where("created_at > ?", 1.week.ago) }

  # [ARCH.66] Anchor, що завис у :sent довше за poll-SLA (RPC/gas-затримка АБО крах поллера
  # під час підтвердження). Здоровий anchor підтверджується за хвилини → у нормі порожній;
  # ненульовий = реально-завислий. Ключ = updated_at (pending→sent бампає його; sent_at-колонки
  # немає), поріг > confirmation-горизонту, щоб не сплутати живий поллер з мертвим. One-Home
  # предикат: спільний для StuckSentAnchorSweeperWorker (re-arm) і Treasury-gauge (глибина).
  STUCK_SENT_THRESHOLD = 6.hours
  scope :stuck_sent, -> { status_sent.where(updated_at: ...STUCK_SENT_THRESHOLD.ago) }

  # --- ХЕЛПЕРИ ---

  # [ARCH.12] One-Home агрегат-формули: ЄДИНЕ місце рядка-payload'а — юзають і
  # generate_state_root (leaf0), і verify нижче. Розійтись їм більше нема як.
  # [ARCH.97] Порядок полів = порядок історії формули (E.53/E.54 додавали в хвіст),
  # тож нове поле теж іде В ХВІСТ — інакше payload перестав би читатись як
  # накопичувальний журнал розширень. `total_growth_points` — офчейн-леджер балів
  # (єдине його криптографічне засвідчення: `Wallet` не має `Auditable`, а `credit!`
  # це голий `increment!` без сліду); `total_scc_supply` — чинний monetary supply.
  # ⚠️ `total_sfc` СВІДОМО лишається сирою Σ confirmed-мінтів, тобто кумулятивною, а
  # не supply: бекенд SFC не палить (`BlockchainBurningService` хардкодить
  # `carbon_coin`). Але `SilkenForestCoin.sol` МАЄ `slash()`/`slashUpTo()`, тож
  # перший же DAO-слеш зробить цю величину розбіжною з `totalSupply()` — тоді вона
  # мусить перейти на `net_minted_supply(:forest_coin)`. Різні семантики двох
  # сусідніх полів названі тут навмисно, щоб наступний читач не вивів симетрію.
  def self.aggregate_payload(total_growth_points:, total_sfc:, active_tree_count:, chain_hash:, anchored_at:,
                             total_scc_supply:)
    "#{total_growth_points}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|" \
      "#{anchored_at.utc.iso8601}|#{total_scc_supply}"
  end

  # Перевіряє, чи можна незалежно відтворити state_root з збережених компонентів.
  # Дозволяє зовнішньому аудитору верифікувати хеш без доступу до PostgreSQL.
  # [E.53/E.54] Формула оновлена: включає total_sfc та active_tree_count.
  # [ARCH.12] Версіонування: 0 = legacy flat SHA-256 (стара формула verbatim, назавжди);
  # 1 = Merkle — leaf0 звіряється з агрегат-формулою, корінь перераховується зі збережених
  # subtree_roots (самодостатньо O(#кластерів), переживає ретеншн-дроп телеметрія-партицій).
  def verify_state_root
    root_version.to_i >= 1 ? verify_merkle_root : verify_flat_root
  end

  # Etherscan URL для L1 транзакції. 🔴 [INF.27] Дзеркало `BlockchainTransaction#explorer_url`
  # з ПРОТИЛЕЖНОГО боку осі: той був зашитий у testnet і хибний уже сьогодні, цей зашитий у
  # mainnet і стає хибним у мить, коли зʼявляється testnet-слот. Ціна тут вища — цей лінк
  # їде АУДИТОРОВІ як референс якоря в `Mrv::LineageReportService`, і «transaction not found»
  # читається не як «не той чейн», а як «якоря не існує».
  def etherscan_url = Web3::Explorer.tx_url(:ethereum, tx_hash)

  # --- [ARCH.66] ГАРДОВАНІ ПЕРЕХОДИ ЖИТТЄВОГО ЦИКЛУ ---
  # Модель = plain enum (не AASM), тож idempotency тримає with_lock + status-гард: рядкове
  # блокування (SELECT…FOR UPDATE) + re-check у транзакції → перехід рівно-раз проти
  # конкурентного reconcile-re-arm / weekly-resume. `confirm!`/`mark_failed!` переходять з :sent
  # АБО :manual_review — останнє дає ГАРДОВАНИЙ людський вихід із manual_review (оператор звірив
  # tx на etherscan → console `confirm!`, без raw update_column повз валідації/аудит). `escalate!`
  # лише з :sent (не ре-ескалює вже-ескальоване). Термінальні :confirmed/:failed не відкочуються
  # (глибокий reorg вже-:confirmed = P0-подія для людини). error_message ≤500 → truncate(450).

  # storeStateRoot підтверджено on-chain (авто-поллер з :sent; оператор-console з :manual_review).
  def confirm!(block_number, gas_used)
    with_lock do
      return false unless status_sent? || status_manual_review?

      # error_message: nil — чистимо старий escalate-текст, якщо confirm приходить з :manual_review.
      update!(status: :confirmed, block_number: block_number, gas_used: gas_used, error_message: nil)
    end
  end

  # storeStateRoot revert (авто-поллер з :sent; оператор-console з :manual_review).
  def mark_failed!(reason)
    with_lock do
      return false unless status_sent? || status_manual_review?

      update!(status: :failed, error_message: reason.to_s.truncate(450))
    end
  end

  # Poll-SLA вичерпано на все ще :pending-receipt: tx у мемпулі, доля ambiguous — людська
  # звірка на etherscan; виходить з in_flight → наступний тижневий seal більше не блокується.
  def escalate_to_review!(reason)
    with_lock do
      return false unless status_sent?

      update!(status: :manual_review, error_message: reason.to_s.truncate(450))
    end
  end

  # [ARCH.66 companion] Resume-ambiguous escalate: re-broadcast застряглого `:pending` відхилено
  # нодою на same-nonce (`nonce too low` = tx замайнено / `already known` = у мемпулі) → перший
  # broadcast під цим nonce уже досяг мережі до crash, tx_hash втрачено у вікні. НЕ blind-retry
  # (N+1 неможливий — той самий слот), а людська звірка: `:pending` → `:manual_review` (tx_hash NULL,
  # оператор шукає на etherscan за address+nonce). Дзеркало money-path ambiguous-broadcast escalate.
  # Окремий від `escalate_to_review!` (той — poller-exhausted з `:sent`; цей — resume-landed з `:pending`).
  def escalate_pending_ambiguous!(reason)
    with_lock do
      return false unless status_pending?

      update!(status: :manual_review, error_message: reason.to_s.truncate(450))
    end
  end

  private

  def verify_flat_root
    Digest::SHA256.hexdigest(components_payload) == state_root
  end

  def verify_merkle_root
    return false if subtree_roots.blank?

    tier2 = subtree_roots.map { |entry| entry["root"] }
    subtree_roots.first["root"] == Digest::SHA256.hexdigest(components_payload) &&
      MerkleTree.root(tier2) == state_root
  end

  def components_payload
    self.class.aggregate_payload(
      total_growth_points: total_growth_points, total_scc_supply: total_scc_supply,
      total_sfc: total_sfc, active_tree_count: active_tree_count,
      chain_hash: chain_hash, anchored_at: anchored_at
    )
  end
end
