# frozen_string_literal: true

class AddLatestStressIndexAndAiInsightsCompositeIndex < ActiveRecord::Migration[8.1]
  # [ВИПРАВЛЕНО: N+1 TreeBlueprint#current_stress]:
  # Денормалізуємо latest_stress_index у таблицю trees (аналогічно latest_voltage_mv).
  # Це усуває N+1 запит до ai_insights для КОЖНОГО дерева в TreeBlueprint :index,
  # Dashboard::MapNode та oracle_visions_controller.
  #
  # [ВИПРАВЛЕНО: Missing Composite Index]:
  # Додаємо оптимізований індекс для запитів critical_stress скоупу та
  # ContractHealthCheckService, де фільтрація йде по (type, id, insight_type, date).

  def change
    # Денормалізована колонка стресу (як latest_voltage_mv — оновлюється InsightGeneratorService)
    add_column :trees, :latest_stress_index, :decimal, precision: 4, scale: 3, default: 0.0, null: false

    # Композитний індекс для запитів по AI Insights (critical_stress scope, contract health check)
    # Порядок колонок оптимізований під типові запити:
    # WHERE analyzable_type='Tree' AND analyzable_id IN (...) AND insight_type=0 AND target_date=?
    # safety_assured: 4-колонковий індекс необхідний для покриття поліморфного запиту з фільтром
    # по insight_type + target_date. Без нього PostgreSQL використовує 2-колонковий
    # index_ai_insights_on_analyzable та фільтрує решту рядків.
    safety_assured do
      add_index :ai_insights, [ :analyzable_type, :analyzable_id, :insight_type, :target_date ],
                name: "idx_ai_insights_polymorphic_type_date"
    end
  end
end
