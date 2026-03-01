# frozen_string_literal: true

module Api
  module V1
    class WalletsController < BaseController
      # Тільки власники гаманців або адміни можуть бачити деталі та історію
      before_action :authorize_wallet_access!, only: [ :show ]

      # --- ЗАГАЛЬНИЙ ОГЛЯД СКАРБНИЦІ (The Treasury Matrix) ---
      # GET /api/v1/wallets
      def index
        # Оптимізація: підвантажуємо асоціації, щоб уникнути N+1
        @wallets = if current_user.role_admin?
          Wallet.includes(:organization, :tree).all
        else
          current_user.organization.wallets.includes(:tree)
        end

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
        # Ми вже знайшли @wallet у фільтрі authorize_wallet_access!
        @transactions = @wallet.blockchain_transactions.order(created_at: :desc).limit(50)

        respond_to do |format|
          format.json do
            render json: @wallet.as_json(include: :blockchain_transactions)
          end
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
        
        # Перевірка прав: Адмін, або Гаманець належить Організації користувача,
        # або Гаманець прив'язаний до Дерева, що належить Організації користувача.
        access_granted = current_user.role_admin? || 
                         @wallet.organization == current_user.organization ||
                         @wallet.tree&.cluster&.organization == current_user.organization

        render_forbidden unless access_granted
      end
    end
  end
end
