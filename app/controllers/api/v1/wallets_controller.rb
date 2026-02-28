# frozen_string_literal: true

module Api
  module V1
    class WalletsController < BaseController
      # Тільки власники гаманців або адміни можуть бачити деталі транзакцій
      before_action :authorize_wallet_access!, only: [:show, :history]

      # --- ЗАГАЛЬНИЙ ОГЛЯД СКАРБНИЦІ ---
      # GET /api/v1/wallets
      def index
        # Якщо це адмін — бачить усі гаманці, якщо користувач — тільки гаманці своєї організації
        @wallets = current_user.role_admin? ? Wallet.all : current_user.organization.wallets
        
        respond_to do |format|
          format.json { render json: @wallets }
          format.html do
            render_dashboard(
              title: "Treasury Matrix",
              component: Views::Components::Wallets::Index.new(wallets: @wallets)
            )
          end
        end
      end

      # --- ДЕТАЛІ ГАМАНЦЯ (On-Chain Audit) ---
      # GET /api/v1/wallets/:id
      def show
        @wallet = Wallet.find(params[:id])
        @transactions = @wallet.blockchain_transactions.order(created_at: :desc).limit(50)

        respond_to do |format|
          format.json { render json: @wallet.as_json(include: :blockchain_transactions) }
          format.html do
            render_dashboard(
              title: "Wallet // #{@wallet.address.first(8)}...",
              component: Views::Components::Wallets::Show.new(wallet: @wallet, transactions: @transactions)
            )
          end
        end
      end

      private

      def authorize_wallet_access!
        @wallet = Wallet.find(params[:id])
        unless current_user.role_admin? || @wallet.organization == current_user.organization || @wallet.tree&.cluster&.organization == current_user.organization
          render_forbidden
        end
      end
    end
  end
end
