# frozen_string_literal: true

# = ===================================================================
# 🛡️ HADRON KYC RE-VERIFY RECOVERY (ARCH.65)
# = ===================================================================
# `HadronKycVerificationWorker` (retry:5) НЕ має `sidekiq_retries_exhausted` і
# enqueue'иться ЛИШЕ разово — `after_commit` на біндингу/зміні crypto_public_address
# (Wallet / Organization). Якщо Hadron API лежить усі 5 спроб → job осідає в
# Dead Set → `hadron_kyc_status` лишається "pending" НАЗАВЖДИ (cron re-verify не
# було), а mint-гейт `Wallet#kyc_approved_for_minting?` щоцикл (MintBatchCollectorWorker,
# 5хв) мовчки скіпає pending-tx цього бенефіціара — без escalation/alert. У prod
# (WEB3_STRICT_MODE) гейт живий (не simulate-approve), тож застрягання РЕАЛЬНО
# блокує mint коштів на невизначений час.
#
# Ця сітка дає періодичний auto-heal: коли Hadron оживе, застряглі "pending"
# доверифіковуються наступним прогоном. Re-enqueue ідемпотентний
# (`HadronComplianceService` повторний виклик безпечний; скоуп лише "pending" —
# approved/rejected не чіпаємо). Backlog-видимість = gauge `silkennet_hadron_kyc_pending_depth`.
class HadronKycReverifyWorker
  include Sidekiq::Job

  # `unique_for` = Enterprise-шим (зараз no-op без sidekiq-ent); overlap безпечний і
  # так — re-verify ідемпотентний. BATCH_LIMIT дренажить backlog послідовними cron'ами.
  sidekiq_options queue: "web3_low", retry: 3, unique_for: 55.minutes

  # Даємо разовому `after_commit`-шляху відпрацювати; підбираємо лише ЗАСТРЯГЛІ
  # (не свіжо-створені, ще в первинному verify-циклі).
  STALE_THRESHOLD = 1.hour

  # Стеля re-enqueue за прогін (на модель) — тривалий Hadron-даунтайм міг накопичити
  # великий backlog; oldest-first дренаж послідовними cron'ами замість flood проти
  # щойно-оживаючого API (дзеркало `CeloRewardReconcileWorker`).
  BATCH_LIMIT = 500

  def perform
    cutoff = STALE_THRESHOLD.ago

    reenqueued = reenqueue_stale(Wallet, "Wallet", cutoff) +
                 reenqueue_stale(Organization, "Organization", cutoff)

    sample_pending_depth!

    return unless reenqueued.positive?

    Rails.logger.warn "🛡️ [ARCH.65] Re-verify #{reenqueued} застряглих pending Hadron-KYC " \
                      "(auto-heal після відновлення API)."
  end

  private

  # Власна адреса → власний KYC. Custodial без адреси governиться org-KYC (worker
  # сам skip'ить безадресні) — не тягнемо дарма. oldest-first (`updated_at` ASC),
  # cap на модель → backlog дренажить наступними прогонами, а не flood'ом.
  def reenqueue_stale(model, label, cutoff)
    ids = model.where(hadron_kyc_status: "pending")
               .where.not(crypto_public_address: [ nil, "" ])
               .where(updated_at: ..cutoff)
               .order(:updated_at)
               .limit(BATCH_LIMIT)
               .pluck(:id)
    ids.each { |id| HadronKycVerificationWorker.perform_async(label, id) }
    ids.size
  end

  # Backlog-видимість (симетрія з Celo `manual_review_depth`): ВЕСЬ pending-пул,
  # не лише stale — показує, скільки KYC чекає, поки Hadron лежить. Семплиться раз
  # на прогін (:50 щогодини); тренд достатній для операторського сигналу.
  def sample_pending_depth!
    depth = Wallet.where(hadron_kyc_status: "pending").count +
            Organization.where(hadron_kyc_status: "pending").count
    SilkenNet::Metrics::HADRON_KYC_PENDING_DEPTH.set(depth)
  end
end
