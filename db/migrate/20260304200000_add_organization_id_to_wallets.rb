# frozen_string_literal: true

class AddOrganizationIdToWallets < ActiveRecord::Migration[8.1]
  def change
    add_reference :wallets, :organization, null: true, foreign_key: true, index: true

    # Бекфіл: заповнюємо organization_id для існуючих гаманців через ланцюг Tree -> Cluster -> Organization
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE wallets
          SET organization_id = clusters.organization_id
          FROM trees
          JOIN clusters ON clusters.id = trees.cluster_id
          WHERE wallets.tree_id = trees.id
            AND trees.cluster_id IS NOT NULL
            AND clusters.organization_id IS NOT NULL
        SQL
      end
    end
  end
end
