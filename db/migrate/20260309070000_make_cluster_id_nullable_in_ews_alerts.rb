# frozen_string_literal: true

class MakeClusterIdNullableInEwsAlerts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :ews_alerts, :cluster_id, true
  end
end
