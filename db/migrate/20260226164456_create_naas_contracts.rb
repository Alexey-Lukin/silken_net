class CreateNaasContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :naas_contracts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :cluster, null: false, foreign_key: true
      t.decimal :total_funding
      t.datetime :start_date
      t.datetime :end_date
      t.integer :status

      t.timestamps
    end
  end
end
