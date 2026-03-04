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

        render json: @transactions.as_json(
          only: [ :id, :amount, :token_type, :status, :tx_hash, :to_address, :notes, :error_message, :created_at ],
          methods: [ :explorer_url ],
          include: {
            wallet: { only: [ :id, :balance ],
              include: { tree: { only: [ :id, :did ] } } }
          }
        )
      end

      # GET /api/v1/blockchain_transactions/:id
      def show
        @transaction = BlockchainTransaction
                         .joins(wallet: { tree: :cluster })
                         .where(clusters: { organization_id: current_user.organization_id })
                         .find(params[:id])

        render json: @transaction.as_json(
          only: [ :id, :amount, :token_type, :status, :tx_hash, :to_address, :locked_points, :notes, :error_message, :created_at, :updated_at ],
          methods: [ :explorer_url ],
          include: {
            wallet: { only: [ :id, :balance, :crypto_public_address ],
              include: { tree: { only: [ :id, :did ] } } }
          }
        )
      end
    end
  end
end
