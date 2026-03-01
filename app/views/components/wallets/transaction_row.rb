module Views
  module Components
    module Wallets
      class TransactionRow < ApplicationComponent
        def initialize(tx:)
          @tx = tx
        end

        def view_template
          tr(id: "transaction_#{@tx.id}", class: "hover:bg-emerald-950/10 transition-colors animate-in fade-in duration-500") do
            td(class: "p-4") do
              span(class: tokens("px-2 py-0.5 rounded-sm text-[9px] font-bold uppercase", tx_type_color)) { @tx.transaction_type }
            end
            td(class: "p-4 text-white") { "#{@tx.amount} SCC" }
            td(class: "p-4") do
              span(class: tokens("text-[8px] uppercase tracking-widest", status_color)) { @tx.status }
            end
            td(class: "p-4 text-gray-600 truncate max-w-[120px] font-mono text-[10px]") do
              @tx.tx_hash ? a(href: "https://polygonscan.com/tx/#{@tx.tx_hash}", target: "_blank", class: "hover:text-emerald-500") { @tx.tx_hash.first(12) + "..." } : "WAITING..."
            end
            td(class: "p-4 text-right text-gray-500") { @tx.created_at.strftime("%H:%M:%S") }
          end
        end

        private

        def tx_type_color
          @tx.mint? ? "bg-emerald-900/50 text-emerald-400 border border-emerald-500/30" : "bg-red-900/50 text-red-400 border border-red-500/30"
        end

        def status_color
          case @tx.status
          when "confirmed" then "text-emerald-500"
          when "processing" then "text-amber-500 animate-pulse"
          when "failed" then "text-red-500"
          else "text-gray-600"
          end
        end
      end
    end
  end
end
