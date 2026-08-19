# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module Web3
      class Address < ApplicationComponent
        PREFIX_LENGTH = 6
        SUFFIX_LENGTH = 4

        # Абсолютні ключі, як у решті `shared/` — autoscope дав би незручний
        # `views.shared.web3.address.*` (див. Pagination/DataTable).
        # `fallback` резолвиться при рендері, а не в сигнатурі: конструювання і
        # рендер компонента можуть розійтися в часі (Turbo-броадкаст).
        def initialize(address:, fallback: nil)
          @address  = address
          @fallback = fallback
        end

        def view_template
          if @address.present?
            span(
              class: "inline-flex items-center gap-1",
              data: {
                controller: "clipboard",
                clipboard_content_value: @address,
                # Локаль знає ЛИШЕ сервер: контролер не сміє вигадувати текст,
                # а порожнє значення там вимикає оголошення, а не підставляє
                # англійський дефолт усередині JS.
                clipboard_copied_text_value: t("ui.web3_address.copied"),
                clipboard_failed_text_value: t("ui.web3_address.copy_failed")
              }
            ) do
              span(
                class: "text-compact font-mono text-gaia-primary-strong break-all leading-relaxed",
                title: @address
              ) { truncated_address }
              button(
                type: "button",
                class: copy_button_classes,
                title: t("ui.web3_address.copy"),
                aria_label: t("ui.web3_address.copy_aria", address: truncated_address),
                data: { action: "clipboard#copy" }
              ) do
                copy_icon
                check_icon
              end
              # Результат оголошується ОКРЕМИМ live-регіоном, а не підміною
              # вмісту кнопки: у кнопки є `aria-label`, і він перекриває будь-який
              # текст усередині — тобто доти успіх не отримував ЖОДНОГО
              # звукового підтвердження, лише візуальну «✓».
              span(
                class: "sr-only",
                role: "status",
                aria_live: "polite",
                data: { clipboard_target: "status" }
              )
            end
          else
            span(class: "text-compact font-mono text-gaia-text-muted italic") do
              @fallback || t("ui.web3_address.not_provisioned")
            end
          end
        end

        private

        def truncated_address
          return @address if @address.length <= PREFIX_LENGTH + SUFFIX_LENGTH

          "#{@address.first(PREFIX_LENGTH)}…#{@address.last(SUFFIX_LENGTH)}"
        end

        def copy_button_classes
          "text-gaia-primary-strong hover:text-gaia-primary-hover " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
            "transition-colors duration-200 cursor-pointer"
        end

        def copy_icon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            fill: "none",
            viewbox: "0 0 24 24",
            stroke_width: "1.5",
            stroke: "currentColor",
            class: "w-3 h-3",
            aria_hidden: "true",
            data: { clipboard_target: "icon" }
          ) do |s|
            s.path(
              stroke_linecap: "round",
              stroke_linejoin: "round",
              d: "M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 " \
                 "1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9.75a.75.75 " \
                 "0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 " \
                 "1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 " \
                 "1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 " \
                 "1.907-2.185a48.208 48.208 0 0 1 1.927-.184"
            )
          end
        end

        # Обидві іконки рендеряться СЕРВЕРОМ, контролер лише перемикає `hidden`.
        # Доти він робив `button.innerHTML = "✓"` і відновлював рядок — тобто
        # знищував SVG і збирав його назад із памʼяті; будь-яка вкладена зміна
        # (клас, атрибут) при цьому губилась.
        def check_icon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            fill: "none",
            viewbox: "0 0 24 24",
            stroke_width: "2",
            stroke: "currentColor",
            class: "w-3 h-3 hidden",
            aria_hidden: "true",
            data: { clipboard_target: "check" }
          ) do |s|
            s.path(stroke_linecap: "round", stroke_linejoin: "round", d: "m4.5 12.75 6 6 9-13.5")
          end
        end
      end
    end
  end
end
