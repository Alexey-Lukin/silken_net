# frozen_string_literal: true

module Api
  module V1
    class ContractsController < BaseController
      # Тільки автентифіковані користувачі (Інвестори бачать свої, Адміни — всі)

      # --- ПОРТФЕЛЬ КОНТРАКТІВ (Registry + Dashboard) ---
      # GET /api/v1/contracts
      def index
        scope = if current_user.role_admin? || current_user.role_super_admin?
                       NaasContract.includes(:organization, :cluster).all
        else
                       current_user.organization.naas_contracts.includes(:cluster)
        end

        @pagy, @contracts = pagy(scope)

        # Агрегуємо дані для Phlex-дашборду, використовуючи твою логіку
        @stats = {
          total_invested: scope.sum(:total_value),
          total_minted: scope.sum(:emitted_tokens),
          # [ОПТИМІЗАЦІЯ]: SQL агрегація замість перебору масиву в Ruby
          portfolio_health: calculate_portfolio_health_for_scope(scope)
        }

        respond_to do |format|
          format.json do
            render json: {
              data: @contracts.as_json(
                only: [ :id, :status, :total_value, :emitted_tokens, :signed_at ],
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
              title: "Nature-as-a-Service Registry",
              component: Contracts::Index.new(contracts: @contracts, stats: @stats, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ КРЕДИТНОЇ ЛІНІЇ (Deep Audit) ---
      # GET /api/v1/contracts/:id
      def show
        @contract = find_contract(params[:id])
        @emission_history = @contract.blockchain_transactions.confirmed.limit(10)

        respond_to do |format|
          format.json do
            render json: {
              contract: @contract.as_json(methods: [ :current_yield_performance, :active_threats? ]),
              emission_history: @emission_history,
              backing_asset: {
                cluster_health: @contract.cluster.health_index,
                active_trees: @contract.cluster.active_trees_count,
                active_threats: @contract.cluster.ews_alerts.active.any?
              }
            }
          end
          format.html do
            render_dashboard(
              title: "Contract Audit // ##{@contract.id}",
              component: Contracts::Show.new(contract: @contract, history: @emission_history)
            )
          end
        end
      end

      # --- ФІНАНСОВА АНАЛІТИКА (Повністю відновлено) ---
      # GET /api/v1/contracts/stats
      def stats
        organization = current_user.organization
        return render_forbidden unless organization

        render json: {
          total_invested: organization.naas_contracts.sum(:total_value),
          total_tokens_minted: organization.naas_contracts.sum(:emitted_tokens),
          portfolio_health: calculate_portfolio_health(organization),
          market_value_usd: calculate_market_value(organization)
        }
      end

      private

      def find_contract(id)
        current_user.role_admin? ? NaasContract.find(id) : current_user.organization.naas_contracts.find(id)
      end

      # [ОПТИМІЗАЦІЯ]: Використовуємо SQL average для економії RAM
      def calculate_portfolio_health(org)
        return 1.0 if org.clusters.empty?
        org.clusters.average(:health_index) || 1.0
      rescue
        1.0
      end

      # [ОПТИМІЗАЦІЯ]: SQL агрегація для вибірки контрактів (joins + average)
      def calculate_portfolio_health_for_scope(contracts)
        return 100 if contracts.empty?
        # Розрахунок середнього здоров'я через SQL для уникнення N+1 та забиття пам'яті
        (contracts.joins(:cluster).average("clusters.health_index") || 100.0).round(1)
      end

      # [DYNAMIC PRICE]: Заміна хардкоду на Oracle Service
      def calculate_market_value(org)
        # Ціна SCC тепер динамічна, підтягується з DEX через наш сервіс
        current_price = PriceOracleService.current_scc_price
        org.naas_contracts.sum(:emitted_tokens) * current_price
      end
    end
  end
end
