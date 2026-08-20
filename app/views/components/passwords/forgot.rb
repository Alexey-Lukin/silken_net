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
      main(class: "min-h-screen bg-gaia-surface-base flex items-center justify-center p-4 font-mono relative overflow-hidden") do
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(var(--gaia-primary)_1px,transparent_1px)] [background-size:20px_20px]")

        div(class: "w-full max-w-md relative z-10") do
          render_header

          # [UI.7] `form_with`, не рукописна `<form>`: токен приходить сам.
          # Скоупу НЕМА свідомо — `passwords#create` читає `params[:email]` плоско.
          form_with(url: forgot_password_path, method: :post, class: "p-8 border border-gaia-border bg-gaia-surface/80 backdrop-blur-xl space-y-8") do |f|
            div(class: "space-y-6") do
              field_container(f, :email, t(".email_label")) do
                f.email_field :email, class: input_classes, placeholder: "architect@silken.net", required: true
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
        div(class: "inline-block h-12 w-12 border border-gaia-primary rotate-45 mb-4 relative", aria_hidden: "true") do
          div(class: "absolute inset-1 bg-gaia-primary animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-gaia-text-strong tracking-[0.3em] uppercase") { t(".heading") }
        p(class: "text-tiny text-gaia-text-muted uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    # Голий `<label>` поруч із `<input>` — сиблінги, не вкладені: ні явного, ні
    # неявного звʼязку, і скрінрідер не називає поле (WCAG 1.3.1). Білдер виводить
    # `for` із того самого джерела, що й `id` поля, тож розійтись вони не можуть.
    def field_container(form, attribute, text, &block)
      div(class: "space-y-2") do
        form.label attribute, text, class: "text-mini uppercase tracking-widest text-gaia-text-subtle font-bold"
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-surface-sunken border border-gaia-border-strong text-gaia-text-strong p-4 font-mono text-sm focus-visible:border-gaia-primary-strong focus-visible:ring-0 outline-none transition-all placeholder:text-gaia-text-subtle"
    end

    def submit_classes
      "w-full py-4 bg-gaia-primary/10 border border-gaia-primary-strong text-gaia-primary-strong uppercase text-xs tracking-[0.4em] " \
        "hover:bg-gaia-primary hover:text-gaia-surface focus-visible:outline-none focus-visible:ring-2 " \
        "focus-visible:ring-gaia-primary-strong transition-all cursor-pointer"
    end

    def render_back_link
      div(class: "text-center pt-2") do
        a(href: login_path, class: "text-tiny text-gaia-text-subtle uppercase tracking-widest hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors") do
          t(".back_link")
        end
      end
    end
  end
end
