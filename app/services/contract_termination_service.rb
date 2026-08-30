# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 📜 CONTRACT TERMINATION SERVICE (Дострокове розірвання контракту)
# = ===================================================================
# Виконує дострокове розірвання NaasContract за Опцією 1 MSA
# (`protocols/legal/msa_skeleton.md §B.6.3`, ⚖️ founder 2026-08-29):
# передоплачена послуга НЕ повертається, early-exit-fee не існує — термінація
# це cancel + опційна ПОГОДЖЕНА форфейтура нарахованих монет
# (`burn_accrued_points`). Розрахунок refund/fee ЗНЯТО [BIZ.22, ⚖️ 2026-08-30]:
# redemption-механіка суперечила підписуваному документу (F5/F6).
#
# Вилучено з NaasContract#terminate_early! для дотримання
# принципу "тонка модель" (Thin Model) та Single Responsibility.
#
# Використання:
#   result = ContractTerminationService.call(naas_contract)
#   result[:burned]  # Boolean
class ContractTerminationService < ApplicationService
  def initialize(naas_contract)
    @contract = naas_contract
  end

  def perform
    validate_termination!

    should_burn = ActiveModel::Type::Boolean.new.cast(@contract.burn_accrued_points)

    @contract.transaction do
      @contract.update!(status: :cancelled, cancelled_at: Time.current)

      if should_burn
        Rails.logger.warn "🔥 [NaasContract] Контракт ##{@contract.id} розірвано. Нараховані SCC-МОНЕТИ кластера спалюються (contractual forfeiture)."
      end

      Rails.logger.info "📜 [NaasContract] Контракт ##{@contract.id} розірвано достроково (Опція 1: без повернення коштів)."
    end

    # [P0 FIX]: Enqueue burn job ПІСЛЯ успішного commit транзакції.
    # При rollback контракт повертається до :active, але burn-job вже в Redis —
    # BurnCarbonTokensWorker виконає Slashing на активному контракті. Фінансова катастрофа.
    if should_burn
      # [SLASH-1] contractual: true (4-й арг) — early-exit форфейтура (погоджена умова
      # burn_accrued_points), НЕ slash-за-провину → пропускає positive-A gate чокпоінта (§3.2).
      BurnCarbonTokensWorker.perform_async(@contract.organization_id, @contract.id, nil, true)
    end

    { burned: should_burn }
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
