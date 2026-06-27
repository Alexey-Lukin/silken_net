# frozen_string_literal: true

# = ===================================================================
# 🌳 DAILY HEALTH ROUTER (Спільне денне читання здоров'я кластера)
# = ===================================================================
# One-Home ЛОГІКИ денного зрізу здоров'я (спільний клас, не спільний рядок): кожен консумер
# будує свій `DailyHealthRouter`, тож запит `AiInsight.daily_health_summary` йде раз НА КОНСУМЕРА
# (A + B = 2 queries/cluster; `ai_insights` co-partition → 00_07 E.37). One-Home тут — це сама
# логіка читання + `blackout?`-рішення, яку споживають ОБИДВА денні шляхи —
#   • A (slashing):  `ContractHealthCheckService` (>20% дерев stress ≥ 0.83)
#   • B (insurance): `ParametricInsurance#evaluate_daily_health!` (dual-trigger)
# Раніше кожен читав окремо (DRY-порушення, SLASH-1 §11 «кандидат на спільний
# DailyHealthRouter»). Пороги (0.83 slash / 0.8 insurance) свідомо лишаються
# per-consumer — це РІЗНІ концепти (slash-тригер vs insurance-кандидат), а не
# дублікат значення (00_07 SLASH-1 — задокументований spread, не уніфікуємо).
#
# `blackout?` — спільне рішення «дерево замовкло»: активні дерева Є, а жодного
# інсайту за добу немає. Це сигнатура force-majeure (відмова шлюзу / Starlink-
# блекаут / знищені сенсори), НЕ per-tree недбалість (05_05 §6). Обидва шляхи на
# blackout ескалюють у Field Audit, а не караються/платяться наосліп.
# «Тиша замовклого дерева — теж його голос» — ескалюємо слухати.
class DailyHealthRouter
  def initialize(cluster, target_date)
    @cluster = cluster
    @target_date = target_date
  end

  # Активні дерева кластера (денормалізований лічильник — без COUNT(*) на мільйонах).
  def total_active_trees
    @total_active_trees ||= @cluster.active_trees_count
  end

  # Денний зріз здоров'я за активними деревами кластера (memoized relation).
  # [SQL]: підзапит замість масиву ID (The Polymorphic IN Trap).
  def insights
    @insights ||= AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: @cluster.trees.active.select(:id),
      target_date: @target_date
    )
  end

  # Немає активних дерев → евалуацію пропускаємо (не blackout, не degradation).
  def skipped?
    total_active_trees.zero?
  end

  # Cluster-wide data blackout: активні дерева Є, але нуль інсайтів за добу.
  # Force-majeure-сигнатура → Field Audit (Кат-C), НІКОЛИ авто-burn/payout (05_05 §6).
  def blackout?
    total_active_trees.positive? && insights.empty?
  end

  # Кількість критично стресованих дерев за заданим порогом (consumer-specific:
  # A передає AiInsight::SLASH_STRESS_THRESHOLD = 0.83).
  def critical_count(threshold)
    insights.where("stress_index >= ?", threshold).count
  end
end
