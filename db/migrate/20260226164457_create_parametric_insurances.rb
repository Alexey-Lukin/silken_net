class CreateParametricInsurances < ActiveRecord::Migration[8.1]
  def change
    create_table :parametric_insurances do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :cluster, null: false, foreign_key: true
      t.integer :status
      t.integer :trigger_event
      t.decimal :payout_amount
      t.decimal :threshold_value

      t.timestamps
    end
  end
end
