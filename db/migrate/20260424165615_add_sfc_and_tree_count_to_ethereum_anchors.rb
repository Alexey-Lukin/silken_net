# [E.53] Add SFC total supply to state root for complete tokenomics verification.
# [E.54] Add active tree count to state root for ecosystem coverage verification.
# Both fields are stored alongside existing state root components (total_scc, chain_hash)
# to enable independent reproducibility by external auditors.
#
# Note: Default values (0) are acceptable for historical records — state root is a
# point-in-time snapshot, and existing anchors were computed without these fields.
# Backfilling would produce incorrect historical hashes.
class AddSfcAndTreeCountToEthereumAnchors < ActiveRecord::Migration[8.1]
  def change
    add_column :ethereum_anchors, :total_sfc, :decimal, precision: 30, scale: 4, default: 0
    add_column :ethereum_anchors, :active_tree_count, :integer, default: 0
  end
end
