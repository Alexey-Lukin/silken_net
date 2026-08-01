# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ContractsController < BaseController
      # Тільки автентифіковані користувачі (Інвестори бачать свої, Адміни — всі)

      # --- ПОРТФЕЛЬ КОНТРАКТІВ (Registry + Dashboard) ---
      # GET /contracts
      def index
        scope = policy_scope(NaasContract).includes(:organization, cluster: :ews_alerts)
        @pagy, @contracts = pagy(scope)

        # Агрегуємо дані для Phlex-дашборду, використовуючи твою логіку
        @stats = {
          total_contracted: scope.sum(:total_value),
          total_minted: scope.sum(:emitted_tokens),
          # [ОПТИМІЗАЦІЯ]: SQL агрегація замість перебору масиву в Ruby
          cluster_health: calculate_cluster_health_for_scope(scope)
        }

        respond_to do |format|
          format.json do
            render json: {
              data: @contracts.as_json(
                only: [ :id, :status, :total_value, :emitted_tokens ],
                include: {
                  cluster: { only: [ :id, :name ] },
                  organization: { only: [ :id, :name ] }
                },
                # [UI/UX]: Додано active_threats?, щоб інвестор бачив "червоний вогник" у списку
                methods: [ :current_yield_performance, :active_threats? ]
              ),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("contracts.index_title"),
              component: Contracts::Index.new(contracts: @contracts, stats: @stats, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ КРЕДИТНОЇ ЛІНІЇ (Deep Audit) ---
      # GET /contracts/:id
      def show
        @contract = find_contract(params[:id])
        @emission_history = BlockchainTransaction
          .joins(:wallet)
          .where(wallets: { organization_id: @contract.organization_id })
          .where(status: :confirmed)
          .order(created_at: :desc)
          .limit(10)

        respond_to do |format|
          format.json do
            render json: {
              contract: @contract.as_json(methods: [ :current_yield_performance, :active_threats? ]),
              emission_history: @emission_history,
              backing_asset: {
                cluster_health: @contract.cluster.health_index,
                active_trees: @contract.cluster.active_trees_count,
                active_threats: @contract.cluster.ews_alerts.unresolved.any?
              }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("contracts.show_title", id: @contract.id),
              component: Contracts::Show.new(contract: @contract, history: @emission_history)
            )
          end
        end
      end

      # --- ФІНАНСОВА АНАЛІТИКА (Повністю відновлено) ---
      # GET /contracts/stats
      def stats
        # [SEC.25 Ф2] Ручний гард «нема організації → 403» тут стояв доти й тепер
        # недосяжний: `acting_organization!` кидає раніше. Це не втрата, а вирівнювання
        # — 403 означає «тобі заборонено», тоді як насправді користувач просто без
        # організації, і решта дашборду відповідає на це 422 з `code: "no_organization"`.
        organization = acting_organization!

        render json: {
          total_contracted: organization.naas_contracts.sum(:total_value),
          total_tokens_minted: organization.naas_contracts.sum(:emitted_tokens),
          cluster_health: calculate_cluster_health(organization),
          attested_value_usd: calculate_attested_value(organization)
        }
      end

      private

      def find_contract(id)
        policy_scope(NaasContract).find(id)
      end

      # [ОПТИМІЗАЦІЯ]: Використовуємо SQL average для економії RAM
      def calculate_cluster_health(org)
        return 1.0 if org.clusters.empty?
        org.clusters.average(:health_index) || 1.0
      rescue
        1.0
      end

      # [ОПТИМІЗАЦІЯ]: SQL агрегація для вибірки контрактів (joins + average)
      #
      # Шкала — 0..1, як у `health_index` (`1.0 - stress_index`, `04_01 §3`), і як у
      # сусіднього `calculate_cluster_health`. Доти два fallback'и стояли на 100/100.0,
      # тобто ОДИН метод повертав дві різні шкали; сама середня — завжди 0..1, тож
      # «100» не було ні досяжним максимумом, ні нейтральним дефолтом. Обидва гарди
      # надлишкові: `average` на порожній релації вже віддає nil.
      def calculate_cluster_health_for_scope(contracts)
        contracts.joins(:cluster).average("clusters.health_index")&.to_f || 1.0
      end

      # [DYNAMIC PRICE]: Заміна хардкоду на Oracle Service
      def calculate_attested_value(org)
        # Ціна SCC тепер динамічна, підтягується з DEX через наш сервіс
        current_price = PriceOracleService.current_scc_price
        org.naas_contracts.sum(:emitted_tokens) * current_price
      end
    end
  end
end
