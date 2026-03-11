# frozen_string_literal: true

module Api
  module V1
    class WalletsController < BaseController
      # --- ЗАГАЛЬНИЙ ОГЛЯД СКАРБНИЦІ (The Treasury Matrix) ---
      # GET /api/v1/wallets
      def index
        scope = policy_scope(Wallet).includes(:organization, :tree)
        @pagy, @wallets = pagy(scope)

        respond_to do |format|
          format.json do
            render json: {
              wallets: @wallets,
              pagy: { page: @pagy.page, limit: @pagy.limit, count: @pagy.count, pages: @pagy.last }
            }
          end
          format.html do
            render_dashboard(
              title: "Treasury Matrix",
              component: Wallets::Index.new(wallets: @wallets, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ ГАМАНЦЯ (On-Chain Audit) ---
      # GET /api/v1/wallets/:id
      def show
        @wallet = Wallet.find(params[:id])
        authorize @wallet
        @pagy_tx, @transactions = pagy(@wallet.blockchain_transactions.order(created_at: :desc), limit: 50)

        respond_to do |format|
          format.json do
            render json: {
              wallet: @wallet,
              transactions: @transactions,
              pagy: { page: @pagy_tx.page, limit: @pagy_tx.limit, count: @pagy_tx.count, pages: @pagy_tx.last }
            }
          end
          format.html do
            render_dashboard(
              title: "Wallet // #{@wallet.crypto_public_address&.first(8)}...",
              component: Wallets::Show.new(wallet: @wallet, transactions: @transactions)
            )
          end
        end
      end
    end
  end
end
