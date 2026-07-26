# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # [SLASH-1] Спільне денне читання (DRY з insurance-шляхом B) + blackout-рішення в ОДНОМУ домі.
    router = DailyHealthRouter.new(@cluster, @target_date)
    return :skipped if router.skipped?

    # [SLASH-1 / 05_05 §6] Cluster-wide data blackout (нуль інсайтів на ВЕСЬ кластер) — сигнатура
    # gateway-fault / force-majeure (вкрадений/знищений шлюз, Starlink-блекаут, шторм), НЕ per-tree
    # недбалість. НІКОЛИ авто-burn на відсутність даних → Field Audit / peer-review (Категорія C);
    # людина класифікує A (недбалість → slash) vs B (форс-мажор → insurance).
    return flag_data_blackout! if router.blackout?

    # Математична межа порушення — частка активної біомаси (default 20%).
    # [ARCH.46] Спільний slash-поріг (= damage-сайзинг у BlockchainBurningService) — одне
    # читання AiInsight.slash_stress_threshold, щоб тригер і розмір не розходились.
    # [GOV.1] Обидва пороги DAO-live (SystemParameter ← ProtocolParameters.sol); Rational
    # із to_s — точна десяткова частка без IEEE-похибки на межі (спадок Rational(1,5)).
    critical_insights_count = router.critical_count(AiInsight.slash_stress_threshold)

    slash_fraction = Rational(SystemParameter.current(:slash_threshold, default: 0.2).to_s)
    if critical_insights_count > router.total_active_trees * slash_fraction
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
    # [ARCH.46] Прокидаємо @target_date у burn (5-й позиц. арг), щоб damage-ratio рахувався за ТУ Ж
    # добу, що тут — інакше burn перевираховує local_yesterday у свій момент → інша дата → 100%.
    BurnCarbonTokensWorker.perform_async(@contract.organization_id, @contract.id, nil, false, @target_date.to_s)
    :degraded
  end

  # [SLASH-1] Absence-of-data → freeze for Field Audit, NEVER slash. A
  # cluster-wide blackout (stolen/destroyed gateway, Starlink outage, storm) is
  # force-majeure, not the forester's negligence — burning investor tokens on it
  # would be a false slash (05_05 §1/§6). Raise a :field_audit escalation (NOT
  # :system_fault — see gap-D); the contract stays :active pending human
  # classification (Category C). «Тиша замовклого дерева — теж його голос».
  def flag_data_blackout!
    Rails.logger.warn "🌐 [D-MRV] NaasContract ##{@contract.id}: cluster-wide data blackout (#{@target_date}) — gateway-fault signature → Field Audit, NO slash (05_05 §6)."

    # [SLASH-1] :field_audit (не :system_fault): дерево замовкло — це НАШ виклик «слухай», окремий
    # від comms-fault, щоб не накручувати penalty_factor (gap-D) і не маскувати сигнали при дедупі.
    # Хелпер дедуплікує: багатоденний блекаут не плодить дубль щодоби.
    EwsAlert.escalate_field_audit!(
      cluster: @cluster,
      message_key: "cluster_data_blackout",
      message_params: { target_date: @target_date }
    )

    :blackout
  end
end
