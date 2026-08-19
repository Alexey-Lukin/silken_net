# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  class BalanceDisplay < ApplicationComponent
    def initialize(wallet:)
      @wallet = wallet
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для BlockchainMintingService
      div(id: "wallet_balance_#{@wallet.id}", class: container_classes) do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }

        p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-4") { t(".verified_balance") }
        div(class: "flex items-baseline gap-4") do
          # [ARCH.88] `balance` НАПРЯМУ, не через alias `scc_balance`: колонка тримає
          # БАЛИ росту, і аліас лише перейменовував їх у монету. Одиниця — з локалі,
          # бо зашитий літерал «SCC» тут і був завищенням у 10 000×.
          span(class: "text-7xl font-extralight text-gaia-text-strong tracking-tighter") { formatted_points(@wallet.balance) }
          # [UI.3] Пульс знято: він був БЕЗУМОВНИЙ, тобто не ніс жодного сигналу —
          # чиста декорація на ОДИНИЦІ грошового рядка, найдорожчому токені цього
          # екрана (`00_07` ARCH.95: одиниця коштує 10 000×). Мигтіння півсекунди
          # на секунду робило нечитабельним рівно те, що мусить читатись першим.
          span(class: "text-xl text-gaia-primary-strong font-mono") { t(".unit") }
        end
        div(class: "mt-6 flex gap-8 text-xs font-mono") do
          div do
            span(class: "text-gaia-text-muted uppercase") { "#{t('.locked')} " }
            span(class: "text-status-warning-text") { formatted_points(@wallet.locked_balance) }
          end
          div do
            span(class: "text-gaia-text-muted uppercase") { "#{t('.available')} " }
            span(class: "text-gaia-text") { formatted_points(@wallet.available_balance) }
          end
          div do
            span(class: "text-gaia-text-muted uppercase") { "#{t('.esg_retired')} " }
            span(class: "text-gaia-text-muted") { formatted_points(@wallet.esg_retired_balance) }
          end
        end
        p(class: "mt-4 text-xs font-mono text-gaia-text-muted") { t(".locked_for", owner: @wallet.tree&.did || @wallet.organization&.name) }
      end
    end

    private

    def container_classes
      "p-10 border border-gaia-border bg-gaia-surface-sunken relative overflow-hidden shadow-2xl"
    end
  end
end
