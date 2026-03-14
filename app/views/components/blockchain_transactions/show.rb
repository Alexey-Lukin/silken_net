# frozen_string_literal: true

module BlockchainTransactions
  class Show < ApplicationComponent
    def initialize(transaction:)
      @tx = transaction
    end

    def view_template
      div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_transaction_details
            render_notes_panel
          end
          div(class: "space-y-8") do
            render_wallet_info
            render_on_chain_panel
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "TX" }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { "Transaction Record" }
            h2(class: "text-3xl font-extralight tracking-tighter text-white") { "#{@tx.amount} SCC" }
            p(class: "text-tiny font-mono text-gray-600 mt-2") { "##{@tx.id} // #{@tx.created_at.strftime('%d.%m.%Y %H:%M:%S UTC')}" }
          end
          div(class: "flex items-center gap-3") do
            span(class: tokens("px-3 py-1 text-mini font-bold uppercase", status_badge_styles)) { @tx.status }
            span(class: tokens("px-3 py-1 text-mini font-bold uppercase border", token_badge_styles)) { @tx.token_type }
          end
        end
      end
    end

    def render_transaction_details
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { "Field" }
              th(scope: "col", class: "p-4") { "Value" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            detail_row("Amount", "#{@tx.amount} SCC")
            detail_row("Token Type", @tx.token_type)
            detail_row("Status", @tx.status)
            detail_row("Blockchain Network", @tx.blockchain_network&.upcase || "—")
            detail_row("Locked Points", @tx.locked_points || "—")
            detail_row("To Address", @tx.to_address)
            detail_row("Gas Price", @tx.gas_price ? "#{@tx.gas_price} wei" : "—")
            detail_row("Gas Used", @tx.gas_used || "—")
            detail_row("Block Number", @tx.block_number || "—")
            detail_row("Nonce", @tx.nonce || "—")
            detail_row("Sent At", @tx.sent_at&.strftime("%d.%m.%Y %H:%M:%S") || "—")
            detail_row("Confirmed At", @tx.confirmed_at&.strftime("%d.%m.%Y %H:%M:%S") || "—")
            detail_row("Created", @tx.created_at.strftime("%d.%m.%Y %H:%M:%S"))
            detail_row("Updated", @tx.updated_at.strftime("%d.%m.%Y %H:%M:%S"))
          end
        end
      end
    end

    def detail_row(label, value)
      tr(class: "hover:bg-emerald-950/10") do
        td(class: "p-4 text-emerald-500") { label }
        td(class: "p-4 text-gray-300") { value.to_s }
      end
    end

    def render_notes_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "Transaction Notes" }
        if @tx.notes.present?
          p(class: "text-compact text-gray-400 font-mono leading-relaxed") { @tx.notes }
        else
          p(class: "text-compact text-gray-700 italic") { "No notes attached." }
        end
        if @tx.error_message.present?
          div(class: "mt-4 p-3 border border-red-900 bg-red-950/20") do
            p(class: "text-mini uppercase text-red-500 tracking-widest mb-1") { "Error Message" }
            p(class: "text-compact text-red-400 font-mono") { @tx.error_message }
          end
        end
      end
    end

    def render_wallet_info
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "Linked Wallet" }
        if @tx.wallet.present?
          div do
            p(class: "text-mini text-gray-600 uppercase mb-1") { "Tree DID" }
            p(class: "text-compact text-emerald-400 font-mono") { @tx.wallet.tree&.did || "N/A" }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-mini text-gray-600 uppercase mb-1") { "Wallet Balance" }
            p(class: "text-lg text-white font-light") do
              plain @tx.wallet.balance.to_f.round(4).to_s
              span(class: "text-xs text-emerald-600 ml-2") { "SCC" }
            end
          end
        else
          p(class: "text-compact text-gray-700 italic") { "No wallet linked." }
        end
      end
    end

    def render_on_chain_panel
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "On-Chain Verification" }
        if @tx.tx_hash.present?
          div do
            p(class: "text-mini text-gray-600 uppercase mb-1") { "Transaction Hash" }
            p(class: "text-tiny font-mono text-emerald-500 break-all leading-relaxed") { @tx.tx_hash }
          end
          div(class: "mt-4") do
            a(href: @tx.explorer_url, target: "_blank", class: "w-full block text-center py-2 border border-emerald-500 text-tiny uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: "View transaction on Polygonscan") { "View on Polygonscan →" }
          end
        else
          p(class: "text-compact text-gray-700 italic") { "Transaction not yet submitted to chain." }
        end
      end
    end

    def status_badge_styles
      case @tx.status
      when "confirmed" then "bg-emerald-900 text-emerald-200"
      when "processing", "sent" then "bg-status-warning text-status-warning-text"
      when "pending" then "bg-zinc-800 text-zinc-300"
      when "failed" then "bg-red-900 text-red-200"
      else "bg-zinc-900 text-zinc-400"
      end
    end

    def token_badge_styles
      case @tx.token_type
      when "carbon_coin" then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
      when "forest_coin" then "bg-token-forest/20 text-token-forest border-token-forest/30"
      else "bg-zinc-900 text-zinc-400 border-zinc-700"
      end
    end
  end
end
