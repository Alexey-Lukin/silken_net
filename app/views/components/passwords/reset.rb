# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Passwords
  class Reset < ApplicationComponent
    def initialize(token:, flash_alert: nil)
      @token = token
      @flash_alert = flash_alert
    end

    def view_template
      main(class: "min-h-screen bg-black flex items-center justify-center p-4 font-mono relative overflow-hidden") do
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_header

          # [UI.7] `form_with`: токен і `_method=patch` приходять самі.
          # Скоупу НЕМА — контролер читає `params[:token]`/`[:password]` плоско,
          # ба більше: `token` узагалі не є атрибутом `User`.
          form_with(url: reset_password_path, method: :patch, class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
            input(type: "hidden", name: "token", value: @token)

            render_flash_messages

            div(class: "space-y-6") do
              field_container(t(".new_password_label")) do
                input(type: "password", name: "password", class: input_classes, placeholder: "••••••••••••", required: true, minlength: "12")
              end

              field_container(t(".confirm_password_label")) do
                input(type: "password", name: "password_confirmation", class: input_classes, placeholder: "••••••••••••", required: true, minlength: "12")
              end
            end

            div(class: "pt-4") do
              button(type: "submit", class: submit_classes) { t(".submit") }
            end

            render_back_link
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-emerald-500 rotate-45 mb-4 relative") do
          div(class: "absolute inset-1 bg-emerald-500 animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase") { t(".heading") }
        p(class: "text-tiny text-emerald-700 uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    def field_container(label, &)
      div(class: "space-y-2") do
        label(class: "text-mini uppercase tracking-widest text-emerald-900 font-bold") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-4 font-mono text-sm focus-visible:border-emerald-500 focus-visible:ring-0 outline-none transition-all placeholder:text-emerald-950"
    end

    def submit_classes
      "w-full py-4 bg-emerald-500/10 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-[0.4em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
    end

    # [SEC.25] Плашка помилки ПОТОЧНОГО сабміту — свідомо тут, а не у `FlashMessages`:
    # це інше дієслово. `FlashMessages` несе повідомлення, що пережило редирект;
    # тут людина лишається у формі зі збереженим статусом (422/401), і помилка мусить
    # стояти біля поля, яке треба перевводити.
    #
    # 🔴 Було німим для скрінрідера (жодного `role`) і на сирому Tailwind повз
    # дизайн-токени — на відміну від дзеркального `Sessions::New`, який робив
    # обидва правильно від початку.
    def render_flash_messages
      return if @flash_alert.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @flash_alert
      end
    end

    def render_back_link
      div(class: "text-center pt-2") do
        a(href: login_path, class: "text-tiny text-emerald-900 uppercase tracking-widest hover:text-emerald-500 transition-colors") do
          t(".back_link")
        end
      end
    end
  end
end
