class CreateEwsAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :ews_alerts do |t|
      t.references :cluster, null: false, foreign_key: true
      t.references :tree, null: false, foreign_key: true
      t.integer :severity
      t.integer :alert_type
      t.text :message

      t.timestamps
    end
  end
end
