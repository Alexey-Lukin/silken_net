# frozen_string_literal: true

# Індекси для оптимізації запитів на масштабі сотень мільйонів дерев.
# Кожен індекс відповідає реальному hot-path у контролерах та сервісах.
class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Blockchain Transactions: фільтрація pending/processing транзакцій для кожного гаманця
    # Використовується в WalletsController#show та BlockchainConfirmationWorker
    add_index :blockchain_transactions, [ :wallet_id, :status ],
              name: "index_blockchain_transactions_on_wallet_id_and_status"

    # Wallets: агрегація балансів по організації (Organization#total_carbon_points)
    add_index :wallets, [ :organization_id, :balance ],
              name: "index_wallets_on_organization_id_and_balance"

    # EWS Alerts: швидка перевірка наявності активних загроз по кластеру
    # Використовується в Cluster#active_threats?, ContractsController, DashboardController
    add_index :ews_alerts, [ :cluster_id, :status ],
              name: "index_ews_alerts_on_cluster_id_and_status"

    # Trees: швидка вибірка активних дерев у кластері (найпоширеніший запит)
    add_index :trees, [ :cluster_id, :status ],
              name: "index_trees_on_cluster_id_and_status"

    # BioContractFirmwares: фільтрація активних прошивок
    add_index :bio_contract_firmwares, :is_active,
              name: "index_bio_contract_firmwares_on_is_active",
              where: "is_active = true"

    # NaasContracts: фільтрація активних контрактів для slashing та daily health
    add_index :naas_contracts, [ :cluster_id, :status ],
              name: "index_naas_contracts_on_cluster_id_and_status"

    # Parametric Insurances: фільтрація для щоденної оцінки
    add_index :parametric_insurances, [ :cluster_id, :status ],
              name: "index_parametric_insurances_on_cluster_id_and_status"

    # TreeFamilies: counter cache для відображення кількості дерев на UI
    # Замінює N+1 запит family.trees.count у TreeFamilies::Index
    add_column :tree_families, :trees_count, :integer, default: 0, null: false
  end
end
