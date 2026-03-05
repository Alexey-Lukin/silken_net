# frozen_string_literal: true

class AddActiveTreesCountToClusters < ActiveRecord::Migration[8.1]
  def up
    add_column :clusters, :active_trees_count, :integer, default: 0, null: false

    # Backfill: синхронізуємо лічильник з актуальним станом бази
    execute <<~SQL
      UPDATE clusters
      SET active_trees_count = (
        SELECT COUNT(*)
        FROM trees
        WHERE trees.cluster_id = clusters.id
          AND trees.status = 0
      )
    SQL
  end

  def down
    remove_column :clusters, :active_trees_count
  end
end
