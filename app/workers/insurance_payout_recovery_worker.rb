# frozen_string_literal: true

# = ===================================================================
# 🛡️ INSURANCE PAYOUT RECOVERY (страхувальна сітка) [S6.20]
# = ===================================================================
# Підбирає страховки, що залипли у стані :triggered. ПЕРВИННИЙ тригер
# лишається подієвим (ParametricInsurance#evaluate_trigger! та
# Dclimate::VerificationService → InsurancePayoutWorker.perform_async); якщо
# той enqueue загубився (напр. Dclimate-воркер упав ПІСЛЯ AASM-переходу
# triggered), виплата зависла б назавжди — кошти не дійшли б до інвестора.
#
# Re-enqueue безпечний: InsurancePayoutWorker ідемпотентний (pessimistic lock +
# `status_triggered?` guard + double-spend захист), тож повторна постановка
# вже-обробленої страховки = no-op. Canon: 04_02 §11.
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
