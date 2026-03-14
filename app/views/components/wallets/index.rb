# frozen_string_literal: true

module Wallets
  class Index < ApplicationComponent
    # @param wallets [Array<Wallet>] pre-loaded wallets
    # @param pagy [Pagy, nil] pagination metadata
    # @param total_liquidity [Numeric] pre-computed sum of scc_balance (eager-load in controller)
    def initialize(wallets:, pagy: nil, total_liquidity: 0)
      @wallets = wallets
      @pagy = pagy
      @total_liquidity = total_liquidity
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @wallets.each do |wallet|
            render_wallet_card(wallet)
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { helpers.api_v1_wallets_path(page: page) }
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end mb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Treasury Matrix" }
          p(class: "text-xs text-gray-600 mt-1") { "Monitoring the flow of Silken Carbon Coins across the network." }
        end
        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "Total Liquidity: "
          span(class: "text-emerald-500") { "#{@total_liquidity.to_f.round(2)} SCC" }
        end
      end
    end

    def render_wallet_card(wallet)
      # Визначаємо ім'я власника (Дерево або Організація)
      owner_name = wallet.tree&.did || wallet.organization&.name || "System Reserve"

      div(class: "group p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
        div(class: "flex justify-between items-start mb-6") do
          div do
            p(class: "text-mini uppercase text-emerald-800 tracking-tighter") { wallet.tree ? "Soldier Wallet" : "Clan Treasury" }
            h4(class: "text-lg font-light text-emerald-100 mt-1") { owner_name }
          end
          div(class: "h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]")
        end

        div(class: "mb-6") do
          span(class: "text-3xl font-light text-white") { wallet.scc_balance.to_f.round(4) }
          span(class: "ml-2 text-xs text-emerald-600 font-mono") { "SCC" }
          if wallet.locked_balance.to_f > 0
            div(class: "mt-1 text-micro font-mono text-status-warning-text") { "🔒 #{wallet.locked_balance.to_f.round(2)} locked" }
          end
          if wallet.esg_retired_balance.to_f > 0
            div(class: "mt-1 text-micro font-mono text-gray-600") { "♻ #{wallet.esg_retired_balance.to_f.round(2)} retired" }
          end
        end

        div(class: "flex justify-between items-center pt-4 border-t border-emerald-900/30") do
          render Views::Shared::Web3::Address.new(address: wallet.crypto_public_address, truncate: 10)
          a(
            href: helpers.api_v1_wallet_path(wallet),
            class: "text-tiny uppercase tracking-widest text-emerald-600 hover:text-white transition-colors"
          ) { "Audit Ledger →" }
        end
      end
    end
  end
end
