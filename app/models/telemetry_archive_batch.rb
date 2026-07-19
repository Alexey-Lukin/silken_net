# frozen_string_literal: true

# [E.60 Фаза 1б] Реєстр телеметрія-батчів mint-anchored архівації: один рядок =
# один archive_root (Merkle-корінь union'а lineage-вікон tx'ів одного диспатчу),
# що їде в mint(bytes32) і піниться JSON-артефактом (Pinata IPFS pinning — чесно
# НЕ Filecoin-deal). Membership = set-once: tx.archive_batch_id ставиться раз,
# атомарно з create (root-set ≡ bind-set); re-dispatch реюзає stored root.
# zero32 on-chain = «без witness-клейму», derived-only — у реєстрі НІКОЛИ:
# windowless-диспатч рядка не створює; збій побудови → build_failed (NULL-root,
# reason, tx_ids-слід) БЕЗ біндингу tx (інакше set-once навічно прирік би їх
# на zero32). Авторитетне членство = tx.archive_batch_id; tx_ids = snapshot-слід.
class TelemetryArchiveBatch < ApplicationRecord
  # Дзеркало BlockchainTransaction.token_type (mint-able підмножина — cusd не мінтиться).
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # Термінали (лише з pending, CAS нижче): pinned · mismatch (rebuild ≠ root при
  # живих логах = integrity-алерт, runbook 06_08 §4) · retention_expired (листя <
  # leaf_count через дропнуті партиції — НЕ tamper) · superseded (жодного tx —
  # defensive, досяжний лише в обхід Wallet#guard_mrv_evidence!). build_failed =
  # створюється напряму (не перехід); reconcile може відремонтувати → repair!.
  # pin-вичерпання СВІДОМО без окремого стану: лишається pending + error_message
  # з retries_exhausted-hook (документована стеля, прецедент FilecoinReconcileWorker).
  enum :status, {
    pending: 0, pinned: 1, build_failed: 2,
    mismatch: 3, retention_expired: 4, superseded: 5
  }, prefix: true

  has_many :blockchain_transactions, foreign_key: :archive_batch_id,
           inverse_of: :archive_batch, dependent: :restrict_with_error

  validates :archive_root, format: { with: /\A[a-f0-9]{64}\z/, message: "must be a 64-char hex SHA-256" },
            allow_nil: true
  # NULL-root легальний для build_failed (слід збою) і superseded-через-abandon
  # (невиправний слід); решта станів народжуються з pending, де root уже є.
  validates :archive_root, presence: true,
            unless: -> { status_build_failed? || status_superseded? }
  validates :leaf_count, :tx_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :error_message, length: { maximum: 500 }, allow_nil: true

  # Reconcile-скоуп (дзеркало AuditLog.pending_archive): недопінені + ремонтопридатні.
  STALE_THRESHOLD = 2.hours
  scope :reconcilable, -> {
    where(status: [ :pending, :build_failed ]).where(updated_at: ...STALE_THRESHOLD.ago)
  }

  # --- CAS-гардовані переходи (прецедент EthereumAnchor ARCH.66) ---
  # with_lock + status-гард → перехід рівно-раз проти конкурентної pin-копії
  # (первинний enqueue × reconcile re-enqueue): stale-копія no-op'иться,
  # mismatch/superseded не перетираються pinned.

  def mark_pinned!(cid)
    cas_from_pending! { update!(status: :pinned, ipfs_cid: cid, error_message: nil) }
  end

  def mark_mismatch!(reason)
    cas_from_pending! { update!(status: :mismatch, error_message: reason.to_s.truncate(450)) }
  end

  def mark_retention_expired!(reason)
    cas_from_pending! { update!(status: :retention_expired, error_message: reason.to_s.truncate(450)) }
  end

  def mark_superseded!
    cas_from_pending! { update!(status: :superseded) }
  end

  # Ремонт build_failed (reconcile: пізній rebuild вдався) → pending + root; далі
  # звичайний пін. Chain на той мінт уже поїхав zero32 — root off-chain-only,
  # легально за семантикою «zero32 = без клейму» (runbook 06_08 §4).
  def repair!(root, leaf_count:, tx_count:)
    with_lock do
      return false unless status_build_failed?

      update!(status: :pending, archive_root: root, leaf_count: leaf_count,
              tx_count: tx_count, error_message: nil)
      true
    end
  end

  # Невиправний build_failed (усі tx розібрані іншими батчами /
  # вікна порожні) → superseded: виходить із .reconcilable, daily-шум зникає.
  def abandon_repair!(reason)
    with_lock do
      return false unless status_build_failed?

      update!(status: :superseded, error_message: reason.to_s.truncate(450))
      true
    end
  end

  private

  def cas_from_pending!
    with_lock do
      return false unless status_pending?

      yield
      true
    end
  end
end
