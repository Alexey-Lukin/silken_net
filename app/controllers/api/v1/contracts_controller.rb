# frozen_string_literal: true

module Api
  module V1
    class ContractsController < BaseController
      # Тільки автентифіковані користувачі (Інвестори бачать свої, Адміни — всі)

      # --- ПОРТФЕЛЬ КОНТРАКТІВ (Registry + Dashboard) ---
      # GET /api/v1/contracts
      def index
        @contracts = if current_user.role_admin?
                       NaasContract.includes(:organization, :cluster).all
        else
                       current_user.organization.naas_contracts.includes(:cluster)
        end

        # Агрегуємо дані для Phlex-дашборду, використовуючи твою логіку
        @stats = {
          total_invested: @contracts.sum(:total_value),
          total_minted: @contracts.sum(:emitted_tokens),
          portfolio_health: calculate_portfolio_health_for_scope(@contracts)
        }

        respond_to do |format|
          format.json do
            render json: @contracts.as_json(
              only: [ :id, :status, :total_value, :emitted_tokens, :signed_at ],
              include: {
                cluster: { only: [ :id, :name ] },
                organization: { only: [ :id, :name ] }
              },
              methods: [ :current_yield_performance ]
            )
          end
          format.html do
            render_dashboard(
              title: "Nature-as-a-Service Registry",
              component: Views::Components::Contracts::Index.new(contracts: @contracts, stats: @stats)
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
              contract: @contract.as_json(methods: [ :current_yield_performance ]),
              emission_history: @emission_history,
              backing_asset: {
                cluster_health: @contract.cluster.health_index,
                active_trees: @contract.cluster.trees.count, # Згідно з твоєю структурою
                active_threats: @contract.cluster.ews_alerts.active.any?
              }
            }
          end
          format.html do
            render_dashboard(
              title: "Contract Audit // ##{@contract.id}",
              component: Views::Components::Contracts::Show.new(contract: @contract, history: @emission_history)
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

      # Твоя оригінальна логіка розрахунку здоров'я
      def calculate_portfolio_health(org)
        return 1.0 if org.clusters.empty?
        org.clusters.map(&:health_index).sum / org.clusters.size.to_f
      rescue
        1.0
      end

      # Допоміжний метод для індексу (для Phlex)
      def calculate_portfolio_health_for_scope(contracts)
        return 100 if contracts.empty?
        healths = contracts.map { |c| c.cluster&.health_index }.compact
        return 100 if healths.empty?
        (healths.sum / healths.size.to_f).round(1)
      end

      # Твоя оригінальна логіка ринкової вартості
      def calculate_market_value(org)
        org.naas_contracts.sum(:emitted_tokens) * 25.5
      end
    end
  end
end
