# frozen_string_literal: true

module Api
  module V1
    class ContractsController < BaseController
      # Тільки автентифіковані користувачі (Інвестори бачать свої, Адміни — всі)
      
      # --- ПОРТФЕЛЬ КОНТРАКТІВ ---
      # GET /api/v1/contracts
      def index
        # Якщо користувач не адмін — показуємо лише контракти його організації
        @contracts = if current_user.role_admin?
                       NaasContract.includes(:organization, :cluster)
                     else
                       current_user.organization.naas_contracts.includes(:cluster)
                     end

        render json: @contracts.as_json(
          only: [:id, :status, :total_value, :emitted_tokens, :signed_at],
          include: {
            cluster: { only: [:id, :name] },
            organization: { only: [:id, :name] }
          },
          methods: [:current_yield_performance]
        )
      end

      # --- ДЕТАЛІ КРЕДИТНОЇ ЛІНІЇ ---
      # GET /api/v1/contracts/:id
      def show
        @contract = find_contract(params[:id])

        render json: {
          contract: @contract.as_json(methods: [:current_yield_performance]),
          # Статистика випуску токенів по цьому контракту
          emission_history: @contract.blockchain_transactions.confirmed.limit(10),
          # Стан кластера, який забезпечує контракт
          backing_asset: {
            cluster_health: @contract.cluster.health_index,
            active_trees: @contract.cluster.total_active_trees,
            active_threats: @contract.cluster.active_threats?
          }
        }
      end

      # --- ФІНАНСОВА АНАЛІТИКА (The Oracle's Math) ---
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

      def calculate_portfolio_health(org)
        # Середнє арифметичне індексів здоров'я всіх кластерів організації
        org.clusters.map(&:health_index).sum / org.clusters.size.to_f rescue 1.0
      end

      def calculate_market_value(org)
        # Гіпотетична ціна Carbon Coin на DEX
        org.naas_contracts.sum(:emitted_tokens) * 25.5 # Наприклад, $25.5 за SCC
      end
    end
  end
end
