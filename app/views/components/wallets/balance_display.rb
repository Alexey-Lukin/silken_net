# frozen_string_literal: true

module Wallets
  class BalanceDisplay < ApplicationComponent
    def initialize(wallet:)
      @wallet = wallet
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для BlockchainMintingService
      div(id: "wallet_balance_#{@wallet.id}", class: container_classes) do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "SCC" }

        p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-4") { "Verified Balance" }
        div(class: "flex items-baseline gap-4") do
          span(class: "text-7xl font-extralight text-white tracking-tighter") { @wallet.scc_balance.to_f.round(6) }
          span(class: "text-xl text-emerald-500 font-mono animate-pulse") { "SCC" }
        end
        div(class: "mt-6 flex gap-8 text-xs font-mono") do
          div do
            span(class: "text-gray-600 uppercase") { "Locked: " }
            span(class: "text-status-warning-text") { @wallet.locked_balance.to_f.round(4) }
          end
          div do
            span(class: "text-gray-600 uppercase") { "Available: " }
            span(class: "text-emerald-400") { @wallet.available_balance.to_f.round(4) }
          end
          div do
            span(class: "text-gray-600 uppercase") { "ESG Retired: " }
            span(class: "text-gray-500") { @wallet.esg_retired_balance.to_f.round(4) }
          end
        end
        p(class: "mt-4 text-xs font-mono text-gray-500") { "Locked for: #{@wallet.tree&.did || @wallet.organization&.name}" }
      end
    end

    private

    def container_classes
      "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden shadow-2xl"
    end
  end
end
