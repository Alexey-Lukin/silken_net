# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Sessions
  class New < ApplicationComponent
    # @param flash_alert [String, nil] alert message to display
    # @param flash_notice [String, nil] notice message to display
    def initialize(flash_alert: nil, flash_notice: nil)
      @flash_alert = flash_alert
      @flash_notice = flash_notice
    end

    def view_template
      # Окремий мінімалістичний лейаут для входу.
      main(class: "min-h-screen bg-gaia-surface-base flex items-center justify-center p-4 font-mono relative overflow-hidden", role: "main") do
        # Фоновий ефект Матриці/Міцелію — декоративні брендові акценти лишаються raw (intentional).
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]", aria_hidden: "true")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_portal_header

          form_with(url: api_v1_login_path, method: :post, class: "p-8 border border-gaia-border bg-gaia-surface/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do |f|
            render_flash_messages

            div(class: "space-y-6") do
              field_container(t(".identity_label")) do
                f.email_field :email, class: input_classes, placeholder: t(".identity_placeholder"), required: true
              end

              field_container(t(".access_code_label")) do
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

    def field_container(text, &block)
      div(class: "space-y-2") do
        label(class: "text-mini uppercase tracking-widest text-gaia-text-subtle font-bold") { text }
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-surface-sunken border border-gaia-border-strong text-gaia-text-strong p-4 font-mono text-sm focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all placeholder:text-gaia-text-subtle"
    end

    def submit_classes
      "w-full py-4 bg-emerald-500/10 border border-gaia-primary text-gaia-primary uppercase text-xs tracking-[0.4em] " \
        "hover:bg-emerald-500 hover:text-gaia-surface focus-visible:outline-none focus-visible:ring-2 " \
        "focus-visible:ring-gaia-primary transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
    end

    def render_flash_messages
      if @flash_alert
        div(class: "p-3 border border-status-danger bg-status-danger text-status-danger-text text-tiny uppercase tracking-widest text-center", role: "alert") do
          @flash_alert
        end
      end
      if @flash_notice
        div(class: "p-3 border border-gaia-border bg-gaia-surface-sunken text-gaia-primary text-tiny uppercase tracking-widest text-center", role: "status") do
          @flash_notice
        end
      end
    end

    def render_forgot_password_link
      div(class: "text-right") do
        a(href: api_v1_forgot_password_path, class: "text-tiny text-gaia-text-subtle uppercase tracking-widest hover:text-gaia-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary transition-colors") do
          t(".forgot_link")
        end
      end
    end

    def render_social_providers
      div(class: "space-y-4 pt-4 border-t border-gaia-border") do
        p(class: "text-mini uppercase tracking-widest text-gaia-text-subtle text-center") { t(".provider_separator") }

        div(class: "grid grid-cols-2 gap-3") do
          provider_button("google_oauth2", "Google", "🔵")
          provider_button("facebook", "Facebook", "🟦")
          provider_button("linkedin", "LinkedIn", "🔷")
          provider_button("twitter", "Twitter", "🐦")
        end
      end
    end

    def provider_button(provider, label, icon)
      a(
        href: "/auth/#{provider}",
        aria_label: t(".provider_aria", provider: label),
        class: "flex items-center justify-center gap-2 py-3 border border-gaia-border-strong text-gaia-text-muted text-tiny uppercase tracking-widest hover:border-gaia-primary hover:text-gaia-text hover:bg-gaia-surface-sunken focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary transition-all"
      ) do
        span(aria_hidden: "true") { icon }
        span { label }
      end
    end

    def render_footer_seal
      div(class: "text-center") do
        p(class: "text-micro text-gaia-text-subtle uppercase tracking-widest") { t(".footer_status") }
      end
    end
  end
end
