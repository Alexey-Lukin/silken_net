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

        # Фільтрація — параметри клієнта обмежуємо до enum-словника моделі,
        # інакше довільна строка ламає AR PG::InvalidTextRepresentation
        # (e.g. `?status=robert');drop table--`) та поглинає Sentry events.
        if params[:token_type].present?
          token_type_param = params[:token_type].to_s
          unless BlockchainTransaction.token_types.key?(token_type_param)
            render json: { error: I18n.t("flash.blockchain_transactions.invalid_token_type", value: token_type_param) }, status: :bad_request
            return
          end
          @transactions = @transactions.where(token_type: token_type_param)
        end

        if params[:status].present?
          status_param = params[:status].to_s
          unless BlockchainTransaction.statuses.key?(status_param)
            render json: { error: I18n.t("flash.blockchain_transactions.invalid_status", value: status_param) }, status: :bad_request
            return
          end
          @transactions = @transactions.where(status: status_param)
        end

        @pagy, @transactions = pagy(@transactions, limit: params.fetch(:limit, 50).to_i.clamp(1, 100))

        respond_to do |format|
          format.json do
            render json: {
              data: BlockchainTransactionBlueprint.render_as_hash(@transactions, view: :index),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: "Blockchain Ledger",
              component: BlockchainTransactions::Index.new(transactions: @transactions, pagy: @pagy)
            )
          end
        end
      end

      # GET /api/v1/blockchain_transactions/:id
      def show
        @transaction = find_transaction

        respond_to do |format|
          format.json do
            render json: BlockchainTransactionBlueprint.render(@transaction, view: :show)
          end
          format.html do
            render_dashboard(
              title: "Transaction ##{@transaction.id}",
              component: BlockchainTransactions::Show.new(transaction: @transaction)
            )
          end
        end
      end

      # --- ON-CHAIN ВЕРИФІКАЦІЯ (Lazy-Loaded Turbo Frame) ---
      # GET /api/v1/blockchain_transactions/:id/on_chain
      def on_chain
        @transaction = find_transaction

        render BlockchainTransactions::OnChainFrame.new(transaction: @transaction), layout: false
      end

      private

      # [PARTITION PRUNING]: blockchain_transactions партиціоновано по created_at.
      # Якщо клієнт передає ?created_at=..., запит потрапляє в одну партицію (O(log N)).
      # Без нього — PostgreSQL сканує індекси всіх партицій (Global Partition Scan).
      def find_transaction
        scope = BlockchainTransaction
                  .joins(wallet: { tree: :cluster })
                  .where(clusters: { organization_id: current_user.organization_id })
                  .includes(wallet: :tree)

        if params[:created_at].present?
          begin
            scope = scope.where(blockchain_transactions: { created_at: Time.iso8601(params[:created_at]) })
          rescue ArgumentError
            # Invalid ISO 8601 — skip partition pruning, fall back to full scan
          end
        end

        scope.find(params[:id])
      end
    end
  end
end
