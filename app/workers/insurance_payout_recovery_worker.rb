# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛡️ INSURANCE PAYOUT RECOVERY (страхувальна сітка) [S6.20]
# = ===================================================================
# Підбирає страховки, що залипли у стані :triggered. [INS.1] Кандидати озброює денний
# `InsuranceOracleWorker` → `ParametricInsurance#arm_candidate!` (БЕЗ enqueue payout — dual-
# trigger); settlement enqueue йде подієво з `Dclimate::VerificationService` (fire_confirmed)
# → `InsurancePayoutWorker.perform_async`. Якщо той enqueue загубився (Dclimate-воркер упав
# після AASM-переходу), виплата зависла б — ця сітка перепоставляє.
#
# Re-enqueue безпечний: InsurancePayoutWorker ідемпотентний (pessimistic lock +
# `status_triggered?` guard + dual-trigger gate + double-spend захист), тож повторна постановка
# вже-обробленої АБО ще-не-підтвердженої (held) страховки = no-op. Canon: 04_02 §11.
class InsurancePayoutRecoveryWorker
  include Sidekiq::Job

  # Та сама черга, що й у воркера виплат, який він відновлює (critical, пріоритет 3).
  sidekiq_options queue: "critical", retry: 3

  def perform
    recovered = 0
    ParametricInsurance.status_triggered.find_each do |insurance|
      InsurancePayoutWorker.perform_async(insurance.id)
      recovered += 1
    end
    Rails.logger.warn "🛡️ [Insurance Recovery] Перепоставлено #{recovered} застряглих :triggered виплат." if recovered.positive?
  end
end
