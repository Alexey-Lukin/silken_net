# frozen_string_literal: true

# = ===================================================================
# 📜 CONTRACT TERMINATION SERVICE (Дострокове розірвання контракту)
# = ===================================================================
# Виконує дострокове розірвання NaasContract з розрахунком штрафу,
# пропорційного повернення коштів та спалюванням нарахованих балів.
#
# Вилучено з NaasContract#terminate_early! для дотримання
# принципу "тонка модель" (Thin Model) та Single Responsibility.
#
# Використання:
#   result = ContractTerminationService.call(naas_contract)
#   result[:refund]  # BigDecimal
#   result[:fee]     # BigDecimal
#   result[:burned]  # Boolean
class ContractTerminationService < ApplicationService
  def initialize(naas_contract)
    @contract = naas_contract
  end

  def perform
    validate_termination!

    refund = @contract.calculate_prorated_refund
    should_burn = ActiveModel::Type::Boolean.new.cast(@contract.burn_accrued_points)

    @contract.transaction do
      @contract.update!(status: :cancelled, cancelled_at: Time.current)

      if should_burn
        BurnCarbonTokensWorker.perform_async(@contract.organization_id, @contract.id)
        Rails.logger.warn "🔥 [NaasContract] Контракт ##{@contract.id} розірвано. Нараховані бали спалюються."
      end

      Rails.logger.info "📜 [NaasContract] Контракт ##{@contract.id} розірвано достроково. Повернення: #{refund}, Штраф: #{@contract.calculate_early_exit_fee}."
    end

    { refund: refund, fee: @contract.calculate_early_exit_fee, burned: should_burn }
  end

  private

  def validate_termination!
    raise "🛑 [NaasContract] Контракт не активний. Розірвання неможливе." unless @contract.status_active?

    min_days = (@contract.min_days_before_exit || 0).to_i
    elapsed = (Time.current.utc.to_date - @contract.start_date.to_date).to_i
    if min_days.positive? && elapsed < min_days
      raise "🛑 [NaasContract] Мінімальний термін до розірвання: #{min_days} днів (пройшло: #{elapsed})."
    end
  end
end
