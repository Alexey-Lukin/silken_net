# frozen_string_literal: true

module Api
  module V1
    class BlockchainTransactionsController < BaseController
      # GET /api/v1/blockchain_transactions
      # Глобальний аудит блокчейн-подій (Minting/Slashing) для Організації
      def index
        @transactions = BlockchainTransaction
                          .joins(wallet: { tree: :cluster })
                          .where(clusters: { organization_id: current_user.organization_id })
                          .includes(wallet: :tree)
                          .order(created_at: :desc)

        # Фільтрація
        @transactions = @transactions.where(token_type: params[:token_type]) if params[:token_type].present?
        @transactions = @transactions.where(status: params[:status]) if params[:status].present?
        @transactions = @transactions.limit(params.fetch(:limit, 50).to_i.clamp(1, 100))

        respond_to do |format|
          format.json do
            render json: BlockchainTransactionBlueprint.render(@transactions, view: :index)
          end
          format.html do
            render_dashboard(
              title: "Blockchain Ledger",
              component: Views::Components::BlockchainTransactions::Index.new(transactions: @transactions)
            )
          end
        end
      end

      # GET /api/v1/blockchain_transactions/:id
      def show
        @transaction = BlockchainTransaction
                         .joins(wallet: { tree: :cluster })
                         .where(clusters: { organization_id: current_user.organization_id })
                         .includes(wallet: :tree)
                         .find(params[:id])

        respond_to do |format|
          format.json do
            render json: BlockchainTransactionBlueprint.render(@transaction, view: :show)
          end
          format.html do
            render_dashboard(
              title: "Transaction ##{@transaction.id}",
              component: Views::Components::BlockchainTransactions::Show.new(transaction: @transaction)
            )
          end
        end
      end
    end
  end
end
