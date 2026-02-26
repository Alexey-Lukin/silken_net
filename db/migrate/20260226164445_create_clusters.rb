class CreateClusters < ActiveRecord::Migration[8.1]
  def change
    create_table :clusters do |t|
      t.string :name
      t.string :region

      t.timestamps
    end
  end
end
