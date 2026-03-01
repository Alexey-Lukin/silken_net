# frozen_string_literal: true

module Views
  module Components
    module Wallets
      class BalanceDisplay < ApplicationComponent
        def initialize(wallet:)
          @wallet = wallet
        end

        def view_template
          # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для BlockchainMintingService
          div(id: "wallet_balance_#{@wallet.id}", class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden shadow-2xl") do
            div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "SCC" }
            
            p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-4") { "Verified Balance" }
            div(class: "flex items-baseline space-x-4") do
              span(class: "text-7xl font-extralight text-white tracking-tighter") { @wallet.scc_balance.to_f.round(6) }
              span(class: "text-xl text-emerald-500 font-mono animate-pulse") { "SCC" }
            end
            p(class: "mt-6 text-xs font-mono text-gray-500") { "Locked for: #{@wallet.tree&.did || @wallet.organization&.name}" }
          end
        end
      end
    end
  end
end
