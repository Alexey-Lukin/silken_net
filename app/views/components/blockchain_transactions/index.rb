# frozen_string_literal: true

module BlockchainTransactions
  class Index < ApplicationComponent
    def initialize(transactions:, pagy:)
      @transactions = transactions
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-6 animate-in fade-in duration-500") do
        header_section
        transactions_table
        render Shared::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_blockchain_transactions_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "📒 Blockchain Ledger — Global Audit" }
          p(class: "text-xs text-gray-600 mt-1") { "Minting, slashing та всі on-chain події вашої Організації." }
        end
        div(class: "flex space-x-2") do
          %w[carbon_coin forest_coin].each do |t|
            span(class: "px-2 py-0.5 border border-emerald-900 text-[9px] text-emerald-900 uppercase") { t }
          end
        end
      end
    end

    def transactions_table
      div(class: "border border-emerald-900 bg-black overflow-hidden") do
        table(class: "w-full text-left font-mono text-[11px]") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
            tr do
              th(class: "p-4") { "Type" }
              th(class: "p-4") { "Amount" }
              th(class: "p-4") { "Status" }
              th(class: "p-4") { "Tree" }
              th(class: "p-4") { "TX Hash" }
              th(class: "p-4 text-right") { "Timestamp" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @transactions.any?
              @transactions.each { |tx| render_transaction_row(tx) }
            else
              tr do
                td(colspan: 6, class: "p-10 text-center text-gray-700 italic") { "No blockchain transactions recorded." }
              end
            end
          end
        end
      end
    end

    def render_transaction_row(tx)
      tr(class: "hover:bg-emerald-950/10 transition-colors") do
        td(class: "p-4") do
          span(class: tokens("px-2 py-0.5 text-[9px] font-bold uppercase border", token_type_styles(tx.token_type))) { tx.token_type }
        end
        td(class: "p-4 text-white font-bold") { "#{tx.amount} SCC" }
        td(class: "p-4") do
          span(class: tokens("text-[8px] uppercase tracking-widest", status_color(tx.status))) { tx.status }
        end
        td(class: "p-4 text-emerald-500") { tx.wallet&.tree&.did || "—" }
        td(class: "p-4 text-gray-600 truncate max-w-[150px] font-mono text-[10px]") do
          if tx.tx_hash.present?
            a(href: tx.explorer_url, target: "_blank", class: "hover:text-emerald-500 underline decoration-emerald-900") { tx.tx_hash.first(16) + "..." }
          else
            span(class: "italic text-zinc-800") { "PENDING_BLOCK" }
          end
        end
        td(class: "p-4 text-right text-gray-500") { tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
      end
    end

    def token_type_styles(type)
      case type
      when "carbon_coin" then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
      when "forest_coin" then "bg-amber-900/20 text-amber-400 border-amber-500/30"
      else "bg-zinc-900 text-zinc-400 border-zinc-700"
      end
    end

    def status_color(status)
      case status
      when "confirmed" then "text-emerald-500"
      when "processing", "sent" then "text-amber-500 animate-pulse"
      when "failed" then "text-red-500"
      else "text-gray-600"
      end
    end
  end
end
