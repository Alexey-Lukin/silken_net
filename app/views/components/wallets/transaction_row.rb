# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  class TransactionRow < ApplicationComponent
    # @param status_src [String, nil] контекст рендеру, а не оздоблення:
    #   `nil` = сторінка (комірка статусу віддає бейдж одразу — дані вже в
    #   `@transactions`), рядок = БРОАДКАСТ (комірка віддає locale-вільний стаб
    #   зі `src`, і кожен глядач тягне свій фрагмент власним запитом).
    #   Дім адреси — `Wallets::TransactionStatusFrame.dom_id`; сам URL будує
    #   ПРОДЮСЕР (`04_04 §8.1а`, клас 2), щоб маршрут-хелпери не заходили в
    #   компонент, який рендериться через `.call`.
    def initialize(tx:, status_src: nil)
      @tx = tx
      @status_src = status_src
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: target ID для оновлення статусу транзакції
      tr(id: dom_id(@tx), class: row_classes) do
        td(class: "p-4") do
          # 🔴 Чіп несе ТІКЕР, а не сире `token_type` — і це не переклад, а
          # виправлення ОДИНИЦІ (⚖️ founder 2026-08-06). Деномінація стояла в
          # рядку ДВІЧІ: сирий enum тут і тікер у сумі поруч, тобто одне й те саме
          # двома різними мовами. Тікер locale-ІНВАРІАНТНИЙ (його верхній дім —
          # `ERC20(…, "SCC")` у контракті, звірку тримає `token_ticker_parity_spec`),
          # тож payload лишається без прози, а сирий англійський enum зникає з
          # екрана БЕЗ жодного перекладу. Мапа кольорів і далі ключується на
          # `token_type` — вона теж locale-інваріантна.
          span(class: tokens("px-2 py-0.5 rounded-sm text-mini font-bold uppercase border", tx_type_styles)) do
            @tx.ticker
          end
        end
        # Сума лишається голим числом: одиницю несе чіп ліворуч. Доти тут стояло
        # `"#{amount} #{ticker}"`, і саме та пара дублювала деномінацію.
        td(class: "p-4 text-gaia-text-strong font-bold") { @tx.amount.to_s }
        td(class: "p-4") do
          # [I18N.2] Єдина локаль-залежна комірка рядка — тому саме вона стала
          # фреймом, а не весь рядок: `<tbody>` приймає лише `<tr>`, зате `<td>`
          # приймає flow-контент (прецедент `Actuators::Show`). Решта комірок
          # (тікер · сума · хеш · час) locale-інваріантні й їдуть у payload'і як є —
          # тому РЯДОК лишається одиницею броадкасту, і комірка хеша, що змінюється
          # разом зі статусом (`mark_as_sent` пише `tx_hash`), далі оновлюється.
          if @status_src
            render Wallets::TransactionStatusFrameStub.new(tx_id: @tx.id, src: @status_src)
          else
            render Wallets::TransactionStatusFrame.new(tx: @tx)
          end
        end
        td(class: "p-4 text-gaia-text-muted truncate max-w-[150px] font-mono text-tiny") do
          if @tx.tx_hash.present?
            a(href: @tx.explorer_url, target: "_blank", class: "hover:text-gaia-primary-strong underline decoration-gaia-border") do
              @tx.tx_hash.length > 16 ? "#{@tx.tx_hash.first(16)}…" : @tx.tx_hash
            end
          else
            span(class: "italic text-gaia-text-strong") { "PENDING_BLOCK" }
          end
        end
        td(class: "p-4 text-right text-gaia-text-muted") { @tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
      end
    end

    private

    def tx_type_styles
      case @tx.token_type
      # [UI.1] `token-carbon` у ролі ФОН/РАМКА (текст — нейтральний gaia-text):
      # непридатність токена виміряна для ТЕКСТ-ролі (4.66:1 — чекає парного
      # `-text`), а ця роль — дзеркало живої forest-гілки рядком нижче.
      when "carbon_coin" then "bg-token-carbon/20 text-gaia-text border-token-carbon/30"
      when "forest_coin" then "bg-token-forest/20 text-token-forest border-token-forest/30"
      # `cusd` СВІДОМО падає в else: власного токена дизайн-системи в нього нема
      # (зовнішній Celo-долар), а окрема гілка з тим самим рядком лише вдавала,
      # що він її має — і робила сам else недосяжним.
      else "bg-gaia-surface text-gaia-text-subtle border-gaia-border-strong"
      end
    end

    def row_classes
      "hover:bg-gaia-surface-sunken transition-colors duration-500"
    end
  end
end
