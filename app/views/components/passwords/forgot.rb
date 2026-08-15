# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Passwords
  class Forgot < ApplicationComponent
    # [SEC.25] Kwarg'ів тут свідомо НЕМАЄ. Компонент приймав `flash_alert:`/
    # notice-варіант і чесно їх рендерив — але жоден викликач їх не передавав
    # (`passwords#new` конструює його порожнім, інших сайтів у дереві нема), тобто
    # обидві гілки були мертві з народження, а живими їх тримала власна спека.
    # Обидва шляхи цієї сторінки (rate-limit, протермінований токен) приходять
    # РЕДИРЕКТОМ, тож їхнє повідомлення несе `FlashMessages` у layout'і.
    def view_template
      main(class: "min-h-screen bg-black flex items-center justify-center p-4 font-mono relative overflow-hidden") do
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_header

          # [UI.7] `form_with`, не рукописна `<form>`: токен приходить сам.
          # Скоупу НЕМА свідомо — `passwords#create` читає `params[:email]` плоско.
          form_with(url: forgot_password_path, method: :post, class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
            div(class: "space-y-6") do
              field_container(t(".email_label")) do
                input(type: "email", name: "email", class: input_classes, placeholder: "architect@silken.net", required: true)
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
        div(class: "inline-block h-12 w-12 border border-token-forest rotate-45 mb-4 relative") do
          div(class: "absolute inset-1 bg-token-forest/50 animate-pulse")
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
      "w-full py-4 bg-token-forest/10 border border-token-forest text-token-forest uppercase text-xs tracking-[0.4em] hover:bg-token-forest hover:text-black transition-all cursor-pointer"
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
