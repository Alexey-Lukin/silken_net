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
        h2(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".heading") }
        p(class: "text-xs text-gray-600 mt-2") { t(".subtitle") }
      end
    end

    # --- MFA СЕКЦІЯ ---
    # [S6.21] Toggle прибрано (interim): recovery-codes без login-challenge не
    # захищають акаунт (sessions#create не читає otp_required_for_login) —
    # контроль був security-theatre. Повертається разом із TOTP → 00_07 S6.21.
    def render_mfa_section
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".mfa.heading") }
        div(class: "p-3 border border-status-warning/50 bg-status-warning/10") do
          p(class: "text-mini text-status-warning-text uppercase tracking-widest") { t(".mfa.wip_caveat") }
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

        form(action: api_v1_account_security_password_path, method: "post", class: "space-y-4") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          if @user.password_digest.present?
            field_container(t(".password.current_label")) do
              input(type: "password", name: "current_password", class: input_classes, required: true)
            end
          end

          field_container(t(".password.new_label")) do
            input(type: "password", name: "new_password", class: input_classes, required: true, minlength: "12")
          end

          field_container(t(".password.confirm_label")) do
            input(type: "password", name: "new_password_confirmation", class: input_classes, required: true, minlength: "12")
          end

          button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-tiny text-emerald-500 uppercase tracking-widest hover:bg-emerald-500 hover:text-black transition-all") do
            @user.password_digest.present? ? t(".password.change_submit") : t(".password.set_submit")
          end
        end
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
              span(class: "text-compact text-white font-mono") { identity.provider.titleize }
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

    def render_lock_toggle(identity)
      if identity.locked?
        form(action: api_v1_unlock_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-emerald-900 text-micro text-emerald-700 uppercase hover:text-emerald-400 transition-all") { t(".identities.unlock") }
        end
      else
        form(action: api_v1_lock_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-status-warning text-micro text-status-warning-text uppercase hover:text-status-warning-text transition-all") { t(".identities.lock") }
        end
      end
    end

    def render_unlink_button(identity)
      can_unlink = @user.password_digest.present? || @identities.count { |i| i.active? } > 1

      if can_unlink
        form(action: api_v1_account_security_identity_path(identity), method: "post", class: "inline") do
          input(type: "hidden", name: "_method", value: "delete")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          button(type: "submit", class: "px-3 py-1 border border-red-900 text-micro text-red-700 uppercase hover:text-red-400 transition-all",
                 data: { turbo_confirm: t(".identities.unlink_confirm", provider: identity.provider.titleize) }) { t(".identities.unlink") }
        end
      else
        span(class: "px-3 py-1 border border-gray-800 text-micro text-gray-700 uppercase cursor-not-allowed", title: t(".identities.unlink_disabled_title")) { t(".identities.unlink") }
      end
    end

    def render_available_providers
      linked = @identities.map(&:provider)
      available = Identity::SUPPORTED_PROVIDERS.reject { |p| linked.include?(p) }

      return if available.empty?

      div(class: "pt-4 border-t border-emerald-900/30") do
        h4(class: "text-mini text-gray-600 uppercase tracking-widest mb-3") { t(".identities.available_heading") }
        div(class: "flex flex-wrap gap-3") do
          available.each do |provider|
            a(
              href: "/auth/#{provider}",
              class: "flex items-center gap-2 px-4 py-2 border border-emerald-900/50 text-tiny text-emerald-700 uppercase tracking-widest hover:border-emerald-500 hover:text-emerald-400 transition-all"
            ) do
              span { provider_icon(provider) }
              span { t(".identities.link_provider", provider: provider.titleize) }
            end
          end
        end
      end
    end

    def field_container(label, &)
      div(class: "space-y-2") do
        label(class: "text-mini text-gray-600 uppercase tracking-widest block") { label }
        yield
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
