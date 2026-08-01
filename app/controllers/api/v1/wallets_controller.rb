# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class WalletsController < BaseController
      # --- ЗАГАЛЬНИЙ ОГЛЯД СКАРБНИЦІ (The Treasury Matrix) ---
      # GET /wallets
      def index
        scope = policy_scope(Wallet).includes(:organization, :tree)
        @pagy, @wallets = pagy(scope)

        respond_to do |format|
          format.json do
            render json: {
              data: WalletBlueprint.render_as_hash(@wallets),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            total_liquidity = scope.sum(:scc_balance)
            render_dashboard(
              title: I18n.t("wallets.index_title"),
              component: Wallets::Index.new(wallets: @wallets, pagy: @pagy, total_liquidity: total_liquidity)
            )
          end
        end
      end

      # --- ДЕТАЛІ ГАМАНЦЯ (On-Chain Audit) ---
      # GET /wallets/:id
      def show
        @wallet = Wallet.find(params[:id])
        authorize @wallet
        @pagy_tx, @transactions = pagy(@wallet.blockchain_transactions.order(created_at: :desc), limit: 50)

        respond_to do |format|
          format.json do
            render json: {
              data: WalletBlueprint.render_as_hash(@wallet, view: :show),
              transactions: BlockchainTransactionBlueprint.render_as_hash(@transactions, view: :index),
              pagy: pagy_metadata(@pagy_tx)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("wallets.show_title", address: @wallet.crypto_public_address&.first(8)),
              component: Wallets::Show.new(wallet: @wallet, transactions: @transactions, pagy: @pagy_tx)
            )
          end
        end
      end

      # --- БАЛАНС ГАМАНЦЯ (Lazy-Loaded Turbo Frame) ---
      # GET /wallets/:id/balance
      def balance
        @wallet = Wallet.find(params[:id])
        authorize @wallet

        respond_to do |format|
          format.json do
            render json: { data: WalletBlueprint.render_as_hash(@wallet, view: :balance) }
          end
          format.html do
            render Wallets::BalanceFrame.new(wallet: @wallet), layout: false
          end
        end
      end

      # --- БЛОКЧЕЙН ІДЕНТИЧНІСТЬ (Lazy-Loaded Turbo Frame) ---
      # GET /wallets/:id/metadata
      def metadata
        @wallet = Wallet.find(params[:id])
        authorize @wallet

        respond_to do |format|
          format.json do
            render json: { data: WalletBlueprint.render_as_hash(@wallet, view: :metadata) }
          end
          format.html do
            render Wallets::MetadataFrame.new(wallet: @wallet), layout: false
          end
        end
      end
    end
  end
end
