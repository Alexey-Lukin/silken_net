# frozen_string_literal: true

module Wallets
  class Show < ApplicationComponent
    def initialize(wallet:, transactions:, pagy: nil)
      @wallet = wallet
      @transactions = transactions
      @pagy = pagy
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: Підписка на потік оновлень гаманця
      turbo_stream_from @wallet

      div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
        # Lazy-load: Turbo Frame підвантажує BalanceDisplay окремим запитом,
        # поки що показуємо Skeleton (пульсуючі блоки).
        turbo_frame_tag "wallet_balance_frame_#{@wallet.id}",
                        src: helpers.balance_api_v1_wallet_path(@wallet),
                        loading: :lazy do
          render Views::Shared::UI::Skeleton.new(variant: :balance)
        end

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Головний Ledger
          div(class: "lg:col-span-2") do
            render_transaction_ledger
          end

          # Метадані та Дії
          div(class: "space-y-8") do
            # Lazy-load: Blockchain Identity підвантажується окремим запитом
            turbo_frame_tag "wallet_metadata_frame_#{@wallet.id}",
                            src: helpers.metadata_api_v1_wallet_path(@wallet),
                            loading: :lazy do
              render Views::Shared::UI::Skeleton.new(variant: :card)
            end
            render_on_chain_actions
          end
        end
      end
    end

    private

    def render_transaction_ledger
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "On-Chain Transaction Ledger" }

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(class: "w-full text-left font-mono text-compact min-w-[640px]", role: "table") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { "Type" }
                th(scope: "col", class: "p-4") { "Amount" }
                th(scope: "col", class: "p-4") { "Status" }
                th(scope: "col", class: "p-4") { "TX Hash" }
                th(scope: "col", class: "p-4 text-right") { "Timestamp" }
              end
            end
            # ⚡ [СИНХРОНІЗАЦІЯ]: ID для вставки нових транзакцій
            tbody(id: "transactions_ledger", class: "divide-y divide-emerald-900/30") do
              if @transactions.any?
                @transactions.each { |tx| render Wallets::TransactionRow.new(tx: tx) }
              else
                tr(id: "empty_ledger") do
                  td(colspan: 5, class: "p-10 text-center text-gray-700 italic") { "No transactions detected." }
                end
              end
            end
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { helpers.api_v1_wallet_path(@wallet, page: page) }
          )
        end
      end
    end

    def render_on_chain_actions
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "Actions" }
        div(class: "space-y-2") do
          button(
            aria_label: "Sync wallet with Polygon blockchain",
            class: "w-full py-2 border border-emerald-500 text-tiny uppercase text-emerald-500 hover:bg-emerald-500 " \
                   "hover:text-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-all"
          ) { "Sync with Polygon" }
          button(
            aria_label: "Export transaction ledger as CSV",
            class: "w-full py-2 border border-emerald-900 text-tiny uppercase text-emerald-900 hover:border-emerald-700 " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-all"
          ) { "Export CSV Ledger" }
        end
      end
    end
  end
end
