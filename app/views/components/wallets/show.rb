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
          div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
            render_balance_hero
            
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

        def render_balance_hero
          div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
            # Фоновий декор
            div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "SCC" }
            
            p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-4") { "Verified Balance" }
            div(class: "flex items-baseline space-x-4") do
              span(class: "text-7xl font-extralight text-white tracking-tighter") { @wallet.scc_balance.to_f.round(6) }
              span(class: "text-xl text-emerald-500 font-mono") { "SCC" }
            end
            p(class: "mt-6 text-xs font-mono text-gray-500") { "Locked for: #{@wallet.tree&.did || @wallet.organization&.name}" }
          end
        end

        def render_transaction_ledger
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "On-Chain Transaction Ledger" }
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Type" }
                    th(class: "p-4") { "Amount" }
                    th(class: "p-4") { "TX Hash" }
                    th(class: "p-4 text-right") { "Timestamp" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  if @transactions.any?
                    @transactions.each { |tx| render_tx_row(tx) }
                  else
                    tr { td(colspan: 4, class: "p-10 text-center text-gray-700 italic") { "No transactions detected in this cycle." } }
                  end
                end
              end
            end
          end
        end

        def render_tx_row(tx)
          tr(class: "hover:bg-emerald-950/10 transition-colors") do
            td(class: "p-4") do
              span(class: tokens("px-2 py-0.5 rounded-sm text-[9px] font-bold uppercase", tx_type_color(tx.transaction_type))) do
                tx.transaction_type
              end
            end
            td(class: "p-4 text-white") { "#{tx.amount} SCC" }
            td(class: "p-4 text-gray-600 truncate max-w-[150px]") { tx.tx_hash }
            td(class: "p-4 text-right text-gray-500") { tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
          end
        end

        def render_wallet_metadata
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Blockchain Identity" }
            div(class: "space-y-4 font-mono text-[10px]") do
              div do
                p(class: "text-gray-600 mb-1 uppercase") { "Polygon Address" }
                p(class: "text-emerald-400 break-all leading-relaxed") { @wallet.address }
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

        def tx_type_color(type)
          case type
          when 'mint' then "bg-emerald-900 text-emerald-200"
          when 'burn' then "bg-red-900 text-red-200"
          when 'transfer' then "bg-zinc-800 text-zinc-300"
          else "bg-blue-900 text-blue-200"
          end
        end
      end
    end
  end
end
