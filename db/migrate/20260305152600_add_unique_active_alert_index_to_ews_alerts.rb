# frozen_string_literal: true

class AddUniqueActiveAlertIndexToEwsAlerts < ActiveRecord::Migration[8.1]
  def change
    # [STORM PROTECTION]: Частковий унікальний індекс для запобігання каскадних дублікатів.
    # Дозволяє лише одну активну (status = 0) тривогу на комбінацію [tree_id, alert_type].
    # Вирішені/проігноровані тривоги не підпадають під обмеження.
    add_index :ews_alerts, [ :tree_id, :alert_type, :status ],
              unique: true,
              where: "status = 0 AND tree_id IS NOT NULL",
              name: "index_ews_alerts_unique_active_per_tree"
  end
end
