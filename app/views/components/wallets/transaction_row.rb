# frozen_string_literal: true

module Views
  module Components
    module Wallets
      class TransactionRow < ApplicationComponent
        def initialize(tx:)
          @tx = tx
        end

        def view_template
          # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для оновлення статусу транзакції
          tr(id: "transaction_#{@tx.id}", class: "hover:bg-emerald-950/10 transition-colors animate-in fade-in duration-500") do
            td(class: "p-4") do
              span(class: tokens("px-2 py-0.5 rounded-sm text-[9px] font-bold uppercase border", tx_type_styles)) do
                @tx.transaction_type
              end
            end
            td(class: "p-4 text-white font-bold") { "#{@tx.amount} SCC" }
            td(class: "p-4") do
              span(class: tokens("text-[8px] uppercase tracking-widest", status_color)) { @tx.status }
            end
            td(class: "p-4 text-gray-600 truncate max-w-[150px] font-mono text-[10px]") do
              if @tx.tx_hash.present?
                a(href: "https://polygonscan.com/tx/#{@tx.tx_hash}", target: "_blank", class: "hover:text-emerald-500 underline decoration-emerald-900") { @tx.tx_hash.first(16) + "..." }
              else
                span(class: "italic text-zinc-800") { "PENDING_BLOCK" }
              end
            end
            td(class: "p-4 text-right text-gray-500") { @tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
          end
        end

        private

        def tx_type_styles
          case @tx.transaction_type
          when 'mint' then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
          when 'burn' then "bg-red-900/20 text-red-400 border-red-500/30"
          else "bg-zinc-900 text-zinc-400 border-zinc-700"
          end
        end

        def status_color
          case @tx.status
          when 'confirmed' then "text-emerald-500"
          when 'processing' then "text-amber-500 animate-pulse"
          when 'failed' then "text-red-500"
          else "text-gray-600"
          end
        end
      end
    end
  end
end
