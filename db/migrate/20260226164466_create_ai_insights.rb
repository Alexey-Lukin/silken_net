class CreateAiInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_insights do |t|
      t.references :cluster, null: false, foreign_key: true
      t.integer :insight_type
      t.jsonb :prediction_data

      t.timestamps
    end
  end
end
