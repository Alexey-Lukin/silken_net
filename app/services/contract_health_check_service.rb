# frozen_string_literal: true

# = ===================================================================
# 🏥 CONTRACT HEALTH CHECK SERVICE (D-MRV Арбітраж)
# = ===================================================================
# Перевіряє здоров'я лісового кластера за NaasContract і активує
# Slashing Protocol у разі порушення порогу 20% критичних аномалій.
#
# Вилучено з NaasContract#check_cluster_health! для дотримання
# принципу "тонка модель" (Thin Model) та Single Responsibility.
#
# Використання:
#   ContractHealthCheckService.call(naas_contract)
#   ContractHealthCheckService.call(naas_contract, target_date)
class ContractHealthCheckService < ApplicationService
  def initialize(naas_contract, target_date = nil)
    @contract = naas_contract
    @cluster = naas_contract.cluster
    @target_date = target_date || @cluster.local_yesterday
  end

  def perform
    return unless @contract.status_active?

    # [Counter Cache]: Використовуємо денормалізований лічильник замість COUNT(*).
    total_active_count = @cluster.active_trees_count
    return if total_active_count.zero?

    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: @cluster.trees.active.select(:id),
      target_date: @target_date
    )

    # Відсутність даних > 24 год = порушення контракту (Starlink-блекаут)
    if daily_insights.empty?
      activate_slashing_protocol!
      return
    end

    # Математична межа порушення — 20% від активної біомаси
    critical_insights_count = daily_insights.where("stress_index >= 1.0").count

    if critical_insights_count > total_active_count * Rational(1, 5)
      activate_slashing_protocol!
    end
  end

  private

  # [ВИПРАВЛЕНО]: Ліквідація Race Condition.
  # BurnCarbonTokensWorker гарантовано бачить статус :breached у базі.
  def activate_slashing_protocol!
    breach_confirmed = @contract.transaction do
      @contract.update!(status: :breached)
      true
    rescue StandardError => e
      Rails.logger.error "🛑 [D-MRV] Провал активації Slashing для контракту ##{@contract.id}: #{e.message}"
      false
    end

    if breach_confirmed
      Rails.logger.warn "🚨 [D-MRV] NaasContract ##{@contract.id} РОЗІРВАНО. Сигнал на Slashing відправлено."
      BurnCarbonTokensWorker.perform_async(@contract.organization_id, @contract.id)
    end
  end
end
