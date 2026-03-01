# frozen_string_literal: true

module Views
  module Components
    module Wallets
      class Show < ApplicationComponent
        def initialize(wallet:, transactions:)
          @wallet = wallet
          @transactions = transactions
        end

        def view_template
          # ⚡ [СИНХРОНІЗАЦІЯ]: Підписка на потік оновлень гаманця
          turbo_stream_from @wallet

          div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
            # Винесено в окремий компонент для Turbo-заміни
            render Views::Components::Wallets::BalanceDisplay.new(wallet: @wallet)
            
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Головний Ledger
              div(class: "lg:col-span-2") do
                render_transaction_ledger
              end

              # Метадані та Дії
              div(class: "space-y-8") do
                render_wallet_metadata
                render_on_chain_actions
              end
            end
          end
        end

        private

        def render_transaction_ledger
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "On-Chain Transaction Ledger" }
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Type" }
                    th(class: "p-4") { "Amount" }
                    th(class: "p-4") { "Status" }
                    th(class: "p-4") { "TX Hash" }
                    th(class: "p-4 text-right") { "Timestamp" }
                  end
                end
                # ⚡ [СИНХРОНІЗАЦІЯ]: ID для вставки нових транзакцій
                tbody(id: "transactions_ledger", class: "divide-y divide-emerald-900/30") do
                  if @transactions.any?
                    @transactions.each { |tx| render Views::Components::Wallets::TransactionRow.new(tx: tx) }
                  else
                    tr(id: "empty_ledger") do
                      td(colspan: 5, class: "p-10 text-center text-gray-700 italic") { "No transactions detected." }
                    end
                  end
                end
              end
            end
          end
        end

        def render_wallet_metadata
          div(class: "p-6 border border-emerald-900 bg-black shadow-xl") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Blockchain Identity" }
            div(class: "space-y-4 font-mono text-[10px]") do
              div do
                p(class: "text-gray-600 mb-1 uppercase") { "Polygon Address" }
                p(class: "text-emerald-400 break-all leading-relaxed hover:text-emerald-300 transition-colors") { @wallet.address }
              end
              div do
                p(class: "text-gray-600 mb-1 uppercase") { "Network" }
                p(class: "text-white") { "Polygon PoS (Mainnet)" }
              end
            end
          end
        end

        def render_on_chain_actions
          div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Actions" }
            div(class: "space-y-2") do
              button(class: "w-full py-2 border border-emerald-500 text-[10px] uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { "Sync with Polygon" }
              button(class: "w-full py-2 border border-emerald-900 text-[10px] uppercase text-emerald-900 hover:border-emerald-700 transition-all") { "Export CSV Ledger" }
            end
          end
        end
      end
    end
  end
end
