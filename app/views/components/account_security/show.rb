# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AccountSecurity
  class Show < ApplicationComponent
    # @param password_error [String, nil] помилка ПОТОЧНОГО сабміту форми пароля.
    #   [SEC.25] Доти ці три відмови (`current_invalid` · `too_short` · `mismatch`)
    #   їхали `redirect_to … error:`, тобто викидали людину з форми зі стертими
    #   полями — при тому, що сусідній `PasswordsController` ту саму задачу
    #   розв'язував правильно: лишав у формі з 422. Асиметрія, не задум.
    def initialize(user:, identities:, password_error: nil)
      @user = user
      @identities = identities
      @password_error = password_error
    end

    def view_template
      div(class: "max-w-4xl mx-auto space-y-8") do
        render_header
        render_mfa_section
        render_password_section
        render_identities_section
      end
    end

    private

    def render_header
      div(class: "p-6 border border-emerald-900 bg-zinc-950") do
        h2(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".heading") }
        p(class: "text-xs text-gray-600 mt-2") { t(".subtitle") }
      end
    end

    # --- MFA СЕКЦІЯ ---
    # ✅ [S6.21] Toggle ПОВЕРНУВСЯ 2026-08-20 разом із verify-on-login — рівно як
    # interim і обіцяв. Увімкнення веде в setup-флоу (секрет → QR → verify), а не
    # піднімає прапорець сліпо; вимкнення тримає step-up (current_password).
    def render_mfa_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".mfa.heading") }

        if @user.mfa_enabled?
          p(class: "text-tiny text-emerald-500") { t(".mfa.enabled_with_remaining", count: @user.recovery_codes_remaining) }
          p(class: "text-mini text-gray-600") { t(".mfa.recovery_warning") }

          render_rotate_codes_form

          form_with(url: account_security_mfa_path, method: :patch, class: "space-y-4") do |f|
            if @user.password_digest.present?
              div(class: "space-y-2") do
                label(for: f.field_id(:current_password),
                      class: "text-tiny text-gray-500 uppercase tracking-widest") { t(".password.current_label") }
                f.password_field :current_password, class: input_classes, required: true
              end
            end
            button(type: "submit", class: "px-6 py-2 border border-status-danger-accent text-tiny " \
                                          "text-status-danger-text uppercase tracking-widest " \
                                          "hover:bg-status-danger focus-visible:outline-none " \
                                          "focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-all") do
              t(".mfa.disable_button")
            end
          end
        else
          p(class: "text-tiny text-gray-500") { t(".mfa.disabled_hint") }
          button_to t(".mfa.enable_button"), mfa_setup_path, method: :post,
                                                            class: "px-6 py-2 border border-emerald-500 text-tiny text-emerald-500 " \
                                                                   "uppercase tracking-widest hover:bg-emerald-500 hover:text-black " \
                                                                   "focus-visible:outline-none focus-visible:ring-2 " \
                                                                   "focus-visible:ring-gaia-primary-strong transition-all"
        end
      end
    end

    # [S6.21] Ротація recovery-набору: «загубив аркуш, телефон живий» — новий
    # набір без пересканування QR. Step-up дзеркалить disable-форму (ротація
    # знецінює збережені коди, вкрадена сесія не сміє робити це мовчки);
    # OAuth-only акаунт поля не має — спільного секрета не існує.
    def render_rotate_codes_form
      form_with(url: mfa_recovery_codes_path, method: :post, class: "space-y-4") do |f|
        if @user.password_digest.present?
          div(class: "space-y-2") do
            label(for: f.field_id(:current_password),
                  class: "text-tiny text-gray-500 uppercase tracking-widest") { t(".password.current_label") }
            f.password_field :current_password, class: input_classes, required: true
          end
        end
        button(type: "submit", class: "px-6 py-2 border border-gaia-primary-strong text-tiny " \
                                      "text-gaia-primary-strong uppercase tracking-widest " \
                                      "hover:bg-gaia-primary hover:text-gaia-primary-text " \
                                      "focus-visible:outline-none focus-visible:ring-2 " \
                                      "focus-visible:ring-gaia-primary-strong transition-all") do
          t(".mfa.rotate_codes_button")
        end
      end
    end

    # --- ПАРОЛЬ СЕКЦІЯ ---
    def render_password_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".password.heading") }

        if @user.password_digest.present?
          p(class: "text-tiny text-emerald-500 mb-4") { t(".password.set_ok") }
        else
          p(class: "text-tiny text-status-warning-text mb-4") { t(".password.not_set") }
        end

        # [UI.7] `form_with` без скоупу: контролер читає `params[:current_password]`
        # та `[:new_password]` плоско, і жодне з цих імен не є атрибутом `User`.
        form_with(url: account_security_password_path, method: :patch, class: "space-y-4") do
          render_password_error

          if @user.password_digest.present?
            field_container(t(".password.current_label"), "current_password") do |id|
              input(id: id, type: "password", name: "current_password", class: input_classes, required: true)
            end
          end

          field_container(t(".password.new_label"), "new_password") do |id|
            input(id: id, type: "password", name: "new_password", class: input_classes, required: true, minlength: "12")
          end

          field_container(t(".password.confirm_label"), "new_password_confirmation") do |id|
            input(id: id, type: "password", name: "new_password_confirmation", class: input_classes, required: true, minlength: "12")
          end

          button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-tiny text-emerald-500 uppercase tracking-widest hover:bg-emerald-500 hover:text-black transition-all") do
            @user.password_digest.present? ? t(".password.change_submit") : t(".password.set_submit")
          end
        end
      end
    end

    # [SEC.25] Помилка сабміту стоїть У ФОРМІ, над полями — та сама форма, що вже
    # вживається в `Sessions::New` і `Passwords::Reset`. `role="alert"` обов'язковий:
    # вузол приходить разом із відповіддю, і без нього AT його не оголосить.
    def render_password_error
      return if @password_error.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @password_error
      end
    end

    # --- ПРОВАЙДЕРИ СЕКЦІЯ ---
    def render_identities_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".identities.heading") }

        if @identities.any?
          div(class: "space-y-3") do
            @identities.each { |identity| render_identity_row(identity) }
          end
        else
          p(class: "text-tiny text-gray-600") { t(".identities.none_linked") }
        end

        render_available_providers
      end
    end

    def render_identity_row(identity)
      div(class: "flex items-center justify-between p-4 border border-emerald-900/30 bg-zinc-950") do
        div(class: "flex items-center gap-4") do
          span(class: "text-lg") { provider_icon(identity.provider) }
          div do
            div(class: "flex items-center gap-2") do
              span(class: "text-compact text-white font-mono") { identity.provider_name }
              if identity.primary?
                span(class: "text-micro px-2 py-0.5 bg-emerald-900/30 text-emerald-500 uppercase") { t(".identities.primary") }
              end
              if identity.locked?
                span(class: "text-micro px-2 py-0.5 bg-red-900/30 text-red-500 uppercase") { t(".identities.locked") }
              end
            end
            span(class: "text-mini text-gray-600 font-mono") { t(".identities.uid_line", prefix: identity.uid[0..12]) }
          end
        end

        div(class: "flex items-center gap-2") do
          render_lock_toggle(identity)
          render_unlink_button(identity)
        end
      end
    end

    # [UI.7] `button_to`, не рукописна `<form>`: обидві гілки — дія без вводу, тож
    # форма була лише обгорткою. ⚠️ `form_class: "inline"` НЕСУЧИЙ: без нього
    # `button_to` перезаписує клас самої `<form>` своїм дефолтним `"button_to"`,
    # і кнопка втрачає інлайн-розкладку.
    def render_lock_toggle(identity)
      if identity.locked?
        button_to(
          t(".identities.unlock"),
          unlock_account_security_identity_path(identity),
          method: :patch,
          form_class: "inline",
          class: "px-3 py-1 border border-emerald-900 text-micro text-emerald-700 uppercase hover:text-emerald-400 transition-all"
        )
      else
        button_to(
          t(".identities.lock"),
          lock_account_security_identity_path(identity),
          method: :patch,
          form_class: "inline",
          class: "px-3 py-1 border border-status-warning text-micro text-status-warning-text uppercase hover:text-status-warning-text transition-all"
        )
      end
    end

    def render_unlink_button(identity)
      # [TEST.12] `Identity#active?` НЕ існує — `active` є лише скоупом (`where(locked_at: nil)`),
      # тож цей рядок кидав NoMethodError на кожному OAuth-only власнику (`password_digest`
      # порожній за побудовою: `User#password_required?` = `identities.none?`), тобто сторінка
      # безпеки віддавала 500. Ховала це фікстура, що вигадала предикат. Контролер той самий
      # намір уже виражав правильно — `identities.active.count` (account_security_controller.rb).
      can_unlink = @user.password_digest.present? || @identities.count { |i| !i.locked? } > 1

      if can_unlink
        # [UI.7] `button_to` — див. ноту біля `render_lock_toggle`. `_method=delete`
        # хелпер кладе сам, і саме він робить його ВАЛІДНИМ: у розмітці
        # `method="delete"` — неіснуюче значення, браузер відкотився б на GET.
        button_to(
          t(".identities.unlink"),
          account_security_identity_path(identity),
          method: :delete,
          form_class: "inline",
          class: "px-3 py-1 border border-red-900 text-micro text-red-700 uppercase hover:text-red-400 transition-all",
          data: { turbo_confirm: t(".identities.unlink_confirm", provider: identity.provider_name) }
        )
      else
        span(class: "px-3 py-1 border border-gray-800 text-micro text-gray-700 uppercase cursor-not-allowed", title: t(".identities.unlink_disabled_title")) { t(".identities.unlink") }
      end
    end

    # [ARCH.69] Interim-stub: OmniAuth ще не задротований (гемів/роутів нема) —
    # «Available Providers»-лінки вели на /auth/:provider = 404. Повне тіло
    # (рендер лінків) — у git; повертається разом із дротуванням + ключами.
    def render_available_providers
      nil
    end

    # [UI.3] Мітка ЗВʼЯЗАНА з полем: `for` ⟷ `id`, обидва з одного дому
    # (`field_id_for`). Доти `<label>` і `<input>` були сиблінгами без жодної
    # асоціації — ні явної, ні через вкладеність, — тож скрінрідер не називав поле
    # взагалі (WCAG 1.3.1). Тут форма йде `form_with(url:)` БЕЗ моделі, тобто білдера
    # в блоці немає й `id` не згенерується сам; блок дістає його аргументом, щоб
    # рукописних копій не було двох.
    def field_container(label_text, name, &)
      field_id = field_id_for(name)

      div(class: "space-y-2") do
        label(for: field_id, class: "text-mini text-gray-600 uppercase tracking-widest block") { label_text }
        yield(field_id)
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-compact font-mono text-emerald-400 px-4 py-3 focus-visible:border-emerald-500 focus-visible:outline-none transition-colors"
    end

    def provider_icon(provider)
      case provider
      when "google_oauth2" then "🔵"
      when "facebook"      then "🟦"
      when "linkedin"      then "🔷"
      when "twitter"       then "🐦"
      else "🔗"
      end
    end
  end
end
