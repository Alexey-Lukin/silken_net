# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  class Show < ApplicationComponent
    # Спільний дім target-id леджера: обидва боки тракту — ця сторінка й
    # `BlockchainTransaction#broadcast_new_transaction` — мусять називати ту саму
    # ціль. Рукописний рядок по обидва боки вже давав у цьому репо мертві тракти
    # (`04_04 §8.3`), тож адреса живе константою, як `telemetry_feed` мав би.
    LEDGER_TARGET = "transactions_ledger"
    EMPTY_PLACEHOLDER_TARGET = "empty_ledger"

    def initialize(wallet:, transactions:, pagy: nil)
      @wallet = wallet
      @transactions = transactions
      @pagy = pagy
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: Підписка на потік оновлень транзакцій гаманця
      turbo_stream_from @wallet, :transactions

      div(class: "space-y-8") do
        # Lazy-load: Turbo Frame підвантажує BalanceDisplay окремим запитом,
        # поки що показуємо Skeleton (пульсуючі блоки).
        turbo_frame_tag Wallets::BalanceFrame.dom_id(@wallet.id),
                        src: balance_wallet_path(@wallet),
                        loading: :lazy do
          render Views::Shared::UI::Skeleton.new(variant: :balance)
        end

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Головний Ledger
          div(class: "lg:col-span-2") do
            render_transaction_ledger
          end

          # Метадані та Дії
          div(class: "space-y-8") do
            # Lazy-load: Blockchain Identity підвантажується окремим запитом
            turbo_frame_tag "wallet_metadata_frame_#{@wallet.id}",
                            src: metadata_wallet_path(@wallet),
                            loading: :lazy do
              render Views::Shared::UI::Skeleton.new(variant: :card)
            end
          end
        end
      end
    end

    private

    # Леджер відсортований `created_at: :desc`, тож продюсер робить `prepend` —
    # а він коректний ЛИШЕ там, де рендериться початок списку. На сторінці ≥2
    # адреси не віддаємо ВЗАГАЛІ (`nil` → Phlex опускає атрибут): свіжа
    # транзакція сіла б у чужий зріз пагінації, ще й розсинхронивши лічильники.
    # Саме `nil`, а не власне ім'я для кожної сторінки: друге народило б адресу,
    # якої не кличе жоден продюсер, тобто новий екземпляр рівно того класу, що
    # інвентаризує [UI.4]. Turbo мовчки ігнорує ціль, якої немає в DOM.
    def ledger_target_id
      page = @pagy&.page
      LEDGER_TARGET if page.nil? || page == 1
    end

    def render_transaction_ledger
      div(class: "space-y-4") do
        div(class: "flex items-center justify-between gap-4") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".ledger_title") }
          # [UI.7] Reports-патерн дослівно: голий лінк на CSV, жодного JS. Панель
          # `render_on_chain_actions`, у якій кнопка жила серед мертвих сусідів,
          # знято 2026-08-06 — повертається рівно та її частина, що має бекенд.
          a(href: ledger_wallet_path(@wallet, format: :csv),
            class: "text-mini uppercase tracking-widest text-gaia-text-muted border " \
                   "border-gaia-border px-3 py-1.5 hover:bg-gaia-surface-sunken " \
                   "focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") { t(".export_csv") }
        end

        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(class: "w-full text-left font-mono text-compact min-w-[640px]", role: "table") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.type") }
                th(scope: "col", class: "p-4") { t(".columns.amount") }
                th(scope: "col", class: "p-4") { t(".columns.status") }
                th(scope: "col", class: "p-4") { t(".columns.tx_hash") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.timestamp") }
              end
            end
            # ⚡ [СИНХРОНІЗАЦІЯ]: ціль для вставки нових транзакцій
            tbody(id: ledger_target_id, class: "divide-y divide-gaia-border") do
              if @transactions.any?
                @transactions.each { |tx| render Wallets::TransactionRow.new(tx: tx) }
              else
                tr(id: EMPTY_PLACEHOLDER_TARGET) do
                  td(colspan: 5, class: "p-10 text-center text-gaia-text italic") { t(".empty") }
                end
              end
            end
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { wallet_path(@wallet, page: page) }
          )
        end
      end
    end
  end
end
