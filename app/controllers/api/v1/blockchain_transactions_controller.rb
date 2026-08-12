# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class BlockchainTransactionsController < BaseController
      # GET /blockchain_transactions
      # Глобальний аудит блокчейн-подій (Minting/Slashing) для Організації
      def index
        # [ARCH.98] One-Home: INNER JOIN через гаманець ховав cluster-sourced рядки
        # (Celo-винагорода, слеш останнього дерева) з АУДИТ-списку організації.
        @transactions = BlockchainTransaction
                          .for_organization(acting_organization!.id)
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
              title: I18n.t("blockchain_transactions.index_title"),
              component: BlockchainTransactions::Index.new(transactions: @transactions, pagy: @pagy)
            )
          end
        end
      end

      # GET /blockchain_transactions/:id
      def show
        @transaction = find_transaction

        respond_to do |format|
          format.json do
            render json: BlockchainTransactionBlueprint.render(@transaction, view: :show)
          end
          format.html do
            render_dashboard(
              title: I18n.t("blockchain_transactions.show_title", id: @transaction.id),
              component: BlockchainTransactions::Show.new(transaction: @transaction)
            )
          end
        end
      end

      # --- ON-CHAIN ВЕРИФІКАЦІЯ (Lazy-Loaded Turbo Frame) ---
      # GET /blockchain_transactions/:id/on_chain
      def on_chain
        @transaction = find_transaction

        render BlockchainTransactions::OnChainFrame.new(transaction: @transaction), layout: false
      end

      private

      # [PARTITION PRUNING / S6.16]: blockchain_transactions партиціоновано по
      # created_at, тож `?created_at=` звужує запит до однієї партиції. Форму
      # звуження НЕ пишемо тут — її дім `BlockchainTransaction.find_with_partition_pruning`
      # (⚡ PARTITION PRUNING INVARIANT, `04_01`: «контролери делегують сюди,
      # НЕ дублюють»). Рукописна копія, що стояла на цьому місці, звіряла
      # created_at ТОЧНОЮ рівністю — а ISO-8601 несе секундну точність проти
      # мікросекундної колонки, тож збігалась лише випадково; хелпер бере
      # 1-секундне вікно, яким PostgreSQL прунить так само до однієї партиції.
      # Битий/відсутній created_at хелпер сам відкочує в lookup без прунінгу.
      def find_transaction
        # [ARCH.98] Та сама резолюція, що в #index — інакше cluster-sourced
        # транзакція давала 404 за ПРЯМОЮ адресою на власні гроші організації.
        BlockchainTransaction
          .for_organization(acting_organization!.id)
          .includes(wallet: :tree)
          .find_with_partition_pruning(params[:id], params[:created_at])
      end
    end
  end
end
