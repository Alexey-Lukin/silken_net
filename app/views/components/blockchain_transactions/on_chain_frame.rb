# frozen_string_literal: true

module BlockchainTransactions
  class OnChainFrame < ApplicationComponent
    def initialize(transaction:)
      @tx = transaction
    end

    def view_template
      turbo_frame_tag "tx_onchain_frame_#{@tx.id}" do
        render_on_chain_panel
      end
    end

    private

    def render_on_chain_panel
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "On-Chain Verification" }
        if @tx.tx_hash.present?
          div do
            p(class: "text-mini text-gray-600 uppercase mb-1") { "Transaction Hash" }
            p(class: "text-tiny font-mono text-emerald-500 break-all leading-relaxed") { @tx.tx_hash }
          end
          div(class: "mt-4") do
            a(
              href: @tx.explorer_url,
              target: "_blank",
              class: explorer_link_classes,
              aria_label: "View transaction on blockchain explorer"
            ) { "View on #{explorer_name} →" }
          end
        else
          p(class: "text-compact text-gray-700 italic") { "Transaction not yet submitted to chain." }
        end
      end
    end

    def explorer_name
      if @tx.solana_network?
        "Solana Explorer"
      elsif @tx.celo_network?
        "Celo Explorer"
      else
        "Polygonscan"
      end
    end

    def explorer_link_classes
      "w-full block text-center py-2 border border-emerald-500 text-tiny uppercase text-emerald-500 " \
        "hover:bg-emerald-500 hover:text-black transition-all " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500"
    end
  end
end
