# SPDX-License-Identifier: AGPL-3.0-or-later
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
      div(class: "space-y-8") do
        render_header

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @wallets.each do |wallet|
            render_wallet_card(wallet)
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { wallets_path(page: page) }
          )
        end
      end
    end

    private

    def render_header
      div(class: "flex flex-col sm:flex-row sm:justify-between sm:items-end gap-3 mb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".title") }
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
        div(class: "text-right font-mono text-tiny text-gaia-text-subtle") do
          plain "#{t('.total_liquidity')} "
          # [ARCH.88] Сума БАЛІВ (`scope.sum(:balance)`), не монет — тікер звідси знято.
          span(class: "text-gaia-primary-strong") { "#{formatted_points(@total_liquidity)} #{t('.unit')}" }
        end
      end
    end

    def render_wallet_card(wallet)
      owner_name = wallet.tree&.did || wallet.organization&.name || t(".system_reserve")

      div(class: "group p-6 border border-gaia-border bg-gaia-surface hover:bg-gaia-surface-sunken transition-all duration-500") do
        div(class: "flex justify-between items-start mb-6") do
          div do
            p(class: "text-mini uppercase text-gaia-text-subtle tracking-tighter") do
              wallet.tree ? t(".kind_soldier") : t(".kind_clan")
            end
            h4(class: "text-lg font-light text-gaia-text-strong mt-1") { owner_name }
          end
          div(class: "h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]", aria_hidden: "true")
        end

        div(class: "mb-6") do
          # [ARCH.88] `balance` напряму — аліас `scc_balance` лише перейменовував бали в монету.
          span(class: "text-3xl font-light text-gaia-text-strong") { formatted_points(wallet.balance) }
          span(class: "ml-2 text-xs text-gaia-primary-strong font-mono") { t(".unit") }
          # [ARCH.88] Гард стоїть на ВІДФОРМАТОВАНОМУ значенні, не на сирому:
          # інакше величина, доведено ненульова, могла б надрукуватись як «0.0»
          # (клас «механізм ⟷ його пускач»). Покладатись тут на те, що крок
          # балансу = 0.01, не можна — це властивість ЖИВИХ трактів, а не
          # інваріант колонки (`numeric(24,6)` приймає 0.004 вільно).
          locked = formatted_points(wallet.locked_balance)
          if locked > 0
            div(class: "mt-1 text-micro font-mono text-status-warning-text") do
              t(".locked_label", amount: locked)
            end
          end
          retired = formatted_points(wallet.esg_retired_balance)
          if retired > 0
            div(class: "mt-1 text-micro font-mono text-gaia-text-muted") do
              t(".retired_label", amount: retired)
            end
          end
        end

        div(class: "flex justify-between items-center pt-4 border-t border-gaia-border") do
          render Views::Shared::Web3::Address.new(address: wallet.crypto_public_address)
          a(
            href: wallet_path(wallet),
            class: "text-tiny uppercase tracking-widest text-gaia-primary-strong hover:text-gaia-text-strong transition-colors"
          ) { t(".audit_link") }
        end
      end
    end
  end
end
