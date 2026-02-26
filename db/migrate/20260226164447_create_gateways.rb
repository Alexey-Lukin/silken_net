class CreateGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :gateways do |t|
      t.string :uid
      t.string :ip_address
      t.decimal :latitude
      t.decimal :longitude
      t.decimal :altitude
      t.datetime :last_seen_at
      t.references :cluster, null: false, foreign_key: true

      t.timestamps
    end
    add_index :gateways, :uid, unique: true
  end
end
