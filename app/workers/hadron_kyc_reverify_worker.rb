# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛡️ HADRON KYC RE-VERIFY RECOVERY (ARCH.65)
# = ===================================================================
# `HadronKycVerificationWorker` (retry:5) НЕ має `sidekiq_retries_exhausted` і
# enqueue'иться ЛИШЕ разово — `after_commit` на біндингу/зміні crypto_public_address
# (Wallet / Organization). Вичерпані 5 спроб → job осідає в Dead Set →
# `hadron_kyc_status` лишається "pending", а mint-гейт `Wallet#kyc_approved_for_minting?`
# щоцикл (MintBatchCollectorWorker, 5хв) мовчки скіпає pending-tx цього бенефіціара —
# без escalation/alert і без власного лічильника скіпів.
#
# 🔴 МОДЕЛЬ ЦІЄЇ СІТКИ БУЛА «ВЕНДОР ЛЕЖИТЬ» — ВИМІР ДАВ «ВЕНДОРА НЕ ІСНУЄ» [ARCH.118,
# 2026-09-02]. Продукту «Polygon Hadron» публічно немає (нуль A-записів у авторитетній
# зоні на двох незалежних DoH-резолверах, нуль знімків Wayback, compliance-доки Polygon
# Labs називають Sumsub/Onfido/Persona). `Polygon::HadronComplianceService` є ЄДИНИМ
# рантайм-писачем `hadron_kyc_status = "approved"`, і адресата в нього немає — отже
# статус не виходить із "pending" НІКОЛИ, а не «поки вендор лежить». Тобто сітка
# щогодини переозброює драбину, якій нема куди дійти, а тихий mint-skip є не рідкісним
# крайовим випадком, а ПОСТІЙНИМ станом кожного custodial-бенефіціара.
# Шлях розблокування один — реальний провайдер (00_07 BIZ.20); присуд про долю самої
# сітки (зняти / перецілити / гейтувати `configured?`) — 00_07 ARCH.119 (⚖️ founder).
# Re-enqueue лишається ідемпотентним
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

  # Стеля re-enqueue за прогін (на модель) — oldest-first дренаж послідовними cron'ами
  # замість flood (дзеркало `CeloRewardReconcileWorker`). ⚠️ Підставою був «тривалий
  # Hadron-даунтайм»; після ARCH.118 підстава інша — стеля обмежує ціну прогону,
  # який за побудовою нічого не дренажить, доки провайдера не обрано.
  BATCH_LIMIT = 500

  def perform
    cutoff = STALE_THRESHOLD.ago

    reenqueued = reenqueue_stale(Wallet, "Wallet", cutoff) +
                 reenqueue_stale(Organization, "Organization", cutoff)

    sample_pending_depth!

    return unless reenqueued.positive?

    Rails.logger.warn "🛡️ [ARCH.65] Re-verify #{reenqueued} застряглих pending Hadron-KYC " \
                      "(KYC-провайдера не обрано — 00_07 BIZ.20; дренажу не буде)."
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
  # не лише stale. ⚠️ Сьогодні це не «черга, що чекає вендора», а лічильник
  # бенефіціарів, яких мінт скіпає ЩОЦИКЛ — KYC-провайдера не обрано (00_07 BIZ.20).
  # Семплиться раз на прогін (:50 щогодини).
  def sample_pending_depth!
    depth = Wallet.where(hadron_kyc_status: "pending").count +
            Organization.where(hadron_kyc_status: "pending").count
    SilkenNet::Metrics::HADRON_KYC_PENDING_DEPTH.set(depth)
  end
end
