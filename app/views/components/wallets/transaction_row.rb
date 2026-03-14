# frozen_string_literal: true

module Wallets
  class TransactionRow < ApplicationComponent
    def initialize(tx:)
      @tx = tx
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для оновлення статусу транзакції
      tr(id: dom_id(@tx), class: row_classes) do
        td(class: "p-4") do
          span(class: tokens("px-2 py-0.5 rounded-sm text-mini font-bold uppercase border", tx_type_styles)) do
            @tx.token_type
          end
        end
        td(class: "p-4 text-white font-bold") { "#{@tx.amount} SCC" }
        td(class: "p-4") do
          span(class: tokens("text-micro uppercase tracking-widest", status_color)) { @tx.status }
        end
        td(class: "p-4 text-gray-600 truncate max-w-[150px] font-mono text-tiny") do
          if @tx.tx_hash.present?
            a(href: @tx.explorer_url, target: "_blank", class: "hover:text-emerald-500 underline decoration-emerald-900") do
              @tx.tx_hash.length > 16 ? "#{@tx.tx_hash.first(16)}…" : @tx.tx_hash
            end
          else
            span(class: "italic text-zinc-800") { "PENDING_BLOCK" }
          end
        end
        td(class: "p-4 text-right text-gray-500") { @tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
      end
    end

    private

    def tx_type_styles
      case @tx.token_type
      when "carbon_coin" then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
      when "forest_coin" then "bg-token-forest/20 text-token-forest border-token-forest/30"
      else "bg-zinc-900 text-zinc-400 border-zinc-700"
      end
    end

    def status_color
      case @tx.status
      when "confirmed" then "text-emerald-500"
      when "processing", "sent" then "text-status-warning-text animate-pulse"
      when "pending" then "text-gray-400"
      when "failed" then "text-red-500"
      else "text-gray-600"
      end
    end

    def row_classes
      "hover:bg-emerald-950/10 transition-colors animate-in fade-in duration-500"
    end
  end
end
