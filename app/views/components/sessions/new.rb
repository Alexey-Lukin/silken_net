# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Sessions
  class New < ApplicationComponent
    # @param flash_alert [String, nil] помилка ПОТОЧНОГО сабміту (401/429), яку
    #   сторінка показує на місці зі збереженим статусом — інше дієслово, ніж
    #   `FlashMessages` у layout'і (той несе повідомлення, що пережило редирект).
    #
    # [SEC.25] Notice-kwarg знято: нуль викликачів у дереві. Успішні події цієї
    # сторінки (лист надіслано, пароль змінено) приходять редиректом і рендеряться
    # `FlashMessages`, тож notice-гілка була мертвою, а живою її тримала спека.
    def initialize(flash_alert: nil)
      @flash_alert = flash_alert
    end

    def view_template
      # Окремий мінімалістичний лейаут для входу.
      main(class: "min-h-screen bg-gaia-surface-base flex items-center justify-center p-4 font-mono relative overflow-hidden", role: "main") do
        # Фоновий ефект Матриці/Міцелію — декоративні брендові акценти лишаються raw (intentional).
        # ⚠️ Це СТАТИЧНИЙ CSS-градієнт (крапки 20×20), а НЕ той canvas-«дощ», що його
        # знято з `telemetry/live_stream` присудом [UI.1] 2026-08-14: тут нуль JS і нуль
        # перемальовувань, тож енергетичний аргумент того присуду сюди не поширюється.
        # Уточнення коштує рядок, бо слово «Матриця» в цьому дереві означає ТРИ різні
        # речі — брендову метафору системи (`Treasury Matrix`, «схема Матриці»), знятий
        # ефект і оцей градієнт, — і сплутати їх легко саме тут.
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]", aria_hidden: "true")

        div(class: "w-full max-w-md relative z-10") do
          render_portal_header

          form_with(url: login_path, method: :post, class: "p-8 border border-gaia-border bg-gaia-surface/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do |f|
            render_flash_messages

            div(class: "space-y-6") do
              field_container(f, :email, t(".identity_label")) do
                f.email_field :email, class: input_classes, placeholder: t(".identity_placeholder"), required: true
              end

              field_container(f, :password, t(".access_code_label")) do
                f.password_field :password, class: input_classes, placeholder: t(".access_code_placeholder"), required: true
              end
            end

            div(class: "pt-4") do
              f.submit t(".submit").upcase, class: submit_classes
            end

            render_forgot_password_link
            render_social_providers
            render_footer_seal
          end
        end
      end
    end

    private

    # Lazy-lookup helper scoped to the `sessions.new.*` namespace so call-sites
    # stay terse: `t(".submit")` instead of `t(".submit")`.

    def render_portal_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-gaia-primary rotate-45 mb-4 relative", aria_hidden: "true") do
          div(class: "absolute inset-1 bg-emerald-500 animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-gaia-text-strong tracking-[0.3em] uppercase") { t(".title") }
        p(class: "text-tiny text-gaia-text-muted uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    # `form.label` (не голий `label`) — Rails виводить `for` із того самого
    # form-builder'а, що й `id` поля, тож асоціація не може розійтися вручну.
    # Голий `<label>` поруч із `<input>` — сиблінги, не вкладені: ні явного,
    # ні неявного звʼязку, і скрінрідер не називає поле (WCAG 1.3.1).
    def field_container(form, attribute, text, &block)
      div(class: "space-y-2") do
        form.label attribute, text, class: "text-mini uppercase tracking-widest text-gaia-text-subtle font-bold"
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-surface-sunken border border-gaia-border-strong text-gaia-text-strong p-4 font-mono text-sm focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all placeholder:text-gaia-text-subtle"
    end

    def submit_classes
      "w-full py-4 bg-emerald-500/10 border border-gaia-primary text-gaia-primary-strong uppercase text-xs tracking-[0.4em] " \
        "hover:bg-emerald-500 hover:text-gaia-surface focus-visible:outline-none focus-visible:ring-2 " \
        "focus-visible:ring-gaia-primary-strong transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
    end

    def render_flash_messages
      return if @flash_alert.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @flash_alert
      end
    end

    def render_forgot_password_link
      div(class: "text-right") do
        a(href: forgot_password_path, class: "text-tiny text-gaia-text-subtle uppercase tracking-widest hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors") do
          t(".forgot_link")
        end
      end
    end

    # [ARCH.69] Interim-stub — ДРУГИЙ сайт того самого рішення. OmniAuth не
    # задротований (гемів і роуту `/auth/:provider` немає), тож чотири провайдер-
    # кнопки на сторінці входу вели в 404. Дзеркало `AccountSecurity::Show
    # #render_available_providers`, яке зробили ще 2026-07-16 — сюди той коміт не
    # дійшов, і пункт лишився позначеним закритим при живій половині. Повне тіло —
    # у git; повертається разом із дротуванням + ключами.
    def render_social_providers
      nil
    end

    def render_footer_seal
      div(class: "text-center") do
        p(class: "text-micro text-gaia-text-subtle uppercase tracking-widest") { t(".footer_status") }
      end
    end
  end
end
