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

  # Повертає verdict-символ для крона (`ClusterHealthCheckWorker` гілкує Celo-винагороду
  # за verdict, а НЕ за `status_breached?` — breach тепер асинхронний, лише на реальному
  # слешингу у `BlockchainBurningService`): `:skipped` · `:blackout` · `:degraded`
  # (>20% → чокпоінт слешингу, cause-gate вирішить slash/freeze) · `:healthy`.
  def perform
    return :skipped unless @contract.status_active?

    # [Counter Cache]: Використовуємо денормалізований лічильник замість COUNT(*).
    total_active_count = @cluster.active_trees_count
    return :skipped if total_active_count.zero?

    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: @cluster.trees.active.select(:id),
      target_date: @target_date
    )

    # [SLASH-1, 2026-05-29] Cluster-wide data blackout (zero insights for the
    # WHOLE cluster) is a gateway-fault / force-majeure signature (stolen or
    # destroyed gateway, Starlink outage, storm) — NOT per-tree negligence.
    # NEVER auto-burn on absence of data (05_05 §6 correlated comms-loss guard,
    # §7). Route to Field Audit / peer-review (Category C); a human classifies
    # A (negligence → slash) vs B (force-majeure → insurance).
    return flag_data_blackout! if daily_insights.empty?

    # Математична межа порушення — 20% від активної біомаси.
    # Поріг 0.83 відповідає порогу впевненості Random Forest (замість детерміністичного 1.0)
    critical_insights_count = daily_insights.where("stress_index >= 0.83").count

    if critical_insights_count > total_active_count * Rational(1, 5)
      flag_degradation!
    else
      :healthy
    end
  end

  private

  # [SLASH-1] >20% критичних аномалій → на чокпоінт слешингу. БЕЗ pre-breach: breach
  # тепер ставить ЛИШЕ BlockchainBurningService на РЕАЛЬНОМУ (positive-A) слешингу, а
  # cause-gate чокпоінта вирішує slash-vs-freeze (§3.2). Це й полагодило латентний баг:
  # раніше pre-breach коротко-замикав воркер (`return if status_breached?`) → daily-шлях
  # ніколи реально не палив. Тепер не пре-маркуємо → daily нарешті доходить до burn/freeze.
  def flag_degradation!
    Rails.logger.warn "🚨 [D-MRV] NaasContract ##{@contract.id}: >20% критичних аномалій — на чокпоінт слешингу (cause-gate вирішить slash/freeze)."
    BurnCarbonTokensWorker.perform_async(@contract.organization_id, @contract.id)
    :degraded
  end

  # [SLASH-1] Absence-of-data → freeze for Field Audit, NEVER slash. A
  # cluster-wide blackout (stolen/destroyed gateway, Starlink outage, storm) is
  # force-majeure, not the forester's negligence — burning investor tokens on it
  # would be a false slash (05_05 §1/§6). Raise a gateway-fault (system_fault)
  # alert; the contract stays :active pending human classification (Category C).
  def flag_data_blackout!
    Rails.logger.warn "🌐 [D-MRV] NaasContract ##{@contract.id}: cluster-wide data blackout (#{@target_date}) — gateway-fault signature → Field Audit, NO slash (05_05 §6)."

    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :system_fault,
      message: "Cluster-wide data blackout (#{@target_date}): можлива відмова шлюзу / Starlink-блекаут (force-majeure). Slashing НЕ застосовано — потрібен Field Audit (Category C, 05_05 §5)."
    )

    :blackout
  end
end
