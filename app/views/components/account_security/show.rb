# frozen_string_literal: true

module AccountSecurity
  class Show < ApplicationComponent
    def initialize(user:, identities:)
      @user = user
      @identities = identities
    end

    def view_template
      div(class: "max-w-4xl mx-auto space-y-8 animate-in slide-in-from-bottom-8 duration-700") do
        render_header
        render_mfa_section
        render_password_section
        render_identities_section
      end
    end

    private

    def render_header
      div(class: "p-6 border border-emerald-900 bg-zinc-950") do
        h2(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "🔐 Account Security" }
        p(class: "text-xs text-gray-600 mt-2") { "Керуйте методами входу, двофакторною автентифікацією та зв'язаними провайдерами." }
      end
    end

    # --- MFA СЕКЦІЯ ---
    def render_mfa_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        div(class: "flex justify-between items-center") do
          div do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Two-Factor Authentication (2FA)" }
            p(class: "text-[10px] text-gray-600 mt-1") do
              if @user.mfa_enabled?
                "✅ MFA увімкнено. Recovery codes залишилось: #{@user.recovery_codes_remaining}"
              else
                "⚠️ MFA вимкнено. Рекомендуємо увімкнути для захисту акаунту."
              end
            end
          end
          render_mfa_toggle
        end

        if @user.mfa_enabled?
          div(class: "p-3 border border-amber-900/50 bg-amber-950/10") do
            p(class: "text-[9px] text-amber-500 uppercase tracking-widest") { "Recovery codes збережіть в безпечному місці. Вони потрібні для входу при втраті TOTP." }
          end
        end
      end
    end

    def render_mfa_toggle
      form(action: helpers.api_v1_account_security_mfa_path, method: "post", class: "inline") do
        input(type: "hidden", name: "_method", value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        if @user.mfa_enabled?
          button(type: "submit", class: "px-4 py-2 border border-red-900 text-[9px] text-red-500 uppercase tracking-widest hover:bg-red-900 hover:text-white transition-all") { "Disable MFA" }
        else
          button(type: "submit", class: "px-4 py-2 border border-emerald-500 text-[9px] text-emerald-500 uppercase tracking-widest hover:bg-emerald-500 hover:text-black transition-all") { "Enable MFA" }
        end
      end
    end

    # --- ПАРОЛЬ СЕКЦІЯ ---
    def render_password_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Password" }

        if @user.password_digest.present?
          p(class: "text-[10px] text-emerald-500 mb-4") { "✅ Пароль встановлено" }
        else
          p(class: "text-[10px] text-amber-500 mb-4") { "⚠️ Пароль не встановлено. Встановіть пароль для можливості відв'язки провайдерів." }
        end

        form(action: helpers.api_v1_account_security_password_path, method: "post", class: "space-y-4") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

          if @user.password_digest.present?
            field_container("Current Password") do
              input(type: "password", name: "current_password", class: input_classes, required: true)
            end
          end

          field_container("New Password (min 12 chars)") do
            input(type: "password", name: "new_password", class: input_classes, required: true, minlength: "12")
          end

          field_container("Confirm New Password") do
            input(type: "password", name: "new_password_confirmation", class: input_classes, required: true, minlength: "12")
          end

          button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-[10px] text-emerald-500 uppercase tracking-widest hover:bg-emerald-500 hover:text-black transition-all") do
            @user.password_digest.present? ? "Change Password" : "Set Password"
          end
        end
      end
    end

    # --- ПРОВАЙДЕРИ СЕКЦІЯ ---
    def render_identities_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Linked Identity Providers" }

        if @identities.any?
          div(class: "space-y-3") do
            @identities.each { |identity| render_identity_row(identity) }
          end
        else
          p(class: "text-[10px] text-gray-600") { "Жоден провайдер не прив'язаний." }
        end

        render_available_providers
      end
    end

    def render_identity_row(identity)
      div(class: "flex items-center justify-between p-4 border border-emerald-900/30 bg-zinc-950") do
        div(class: "flex items-center space-x-4") do
          span(class: "text-lg") { provider_icon(identity.provider) }
          div do
            div(class: "flex items-center space-x-2") do
              span(class: "text-[11px] text-white font-mono") { identity.provider.titleize }
              if identity.primary?
                span(class: "text-[8px] px-2 py-0.5 bg-emerald-900/30 text-emerald-500 uppercase") { "Primary" }
              end
              if identity.locked?
                span(class: "text-[8px] px-2 py-0.5 bg-red-900/30 text-red-500 uppercase") { "Locked" }
              end
            end
            span(class: "text-[9px] text-gray-600 font-mono") { "UID: #{identity.uid[0..12]}..." }
          end
        end

        div(class: "flex items-center space-x-2") do
          render_lock_toggle(identity)
          render_unlink_button(identity)
        end
      end
    end

    def render_lock_toggle(identity)
      if identity.locked?
        form(action: helpers.api_v1_unlock_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-emerald-900 text-[8px] text-emerald-700 uppercase hover:text-emerald-400 transition-all") { "Unlock" }
        end
      else
        form(action: helpers.api_v1_lock_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-amber-900 text-[8px] text-amber-700 uppercase hover:text-amber-400 transition-all") { "Lock" }
        end
      end
    end

    def render_unlink_button(identity)
      can_unlink = @user.password_digest.present? || @user.identities.active.count > 1

      if can_unlink
        form(action: helpers.api_v1_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "delete")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-red-900 text-[8px] text-red-700 uppercase hover:text-red-400 transition-all",
                 data: { turbo_confirm: "Відв'язати #{identity.provider.titleize}?" }) { "Unlink" }
        end
      else
        span(class: "px-3 py-1 border border-gray-800 text-[8px] text-gray-700 uppercase cursor-not-allowed", title: "Встановіть пароль перед відв'язкою") { "Unlink" }
      end
    end

    def render_available_providers
      linked = @identities.map(&:provider)
      available = Identity::SUPPORTED_PROVIDERS.reject { |p| linked.include?(p) }

      return if available.empty?

      div(class: "pt-4 border-t border-emerald-900/30") do
        h4(class: "text-[9px] text-gray-600 uppercase tracking-widest mb-3") { "Available Providers" }
        div(class: "flex flex-wrap gap-3") do
          available.each do |provider|
            a(
              href: "/auth/#{provider}",
              class: "flex items-center space-x-2 px-4 py-2 border border-emerald-900/50 text-[10px] text-emerald-700 uppercase tracking-widest hover:border-emerald-500 hover:text-emerald-400 transition-all"
            ) do
              span { provider_icon(provider) }
              span { "Link #{provider.titleize}" }
            end
          end
        end
      end
    end

    def field_container(label, &)
      div(class: "space-y-2") do
        label(class: "text-[9px] text-gray-600 uppercase tracking-widest block") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-[11px] font-mono text-emerald-400 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
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
