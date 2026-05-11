# app/views/components/users/profile.rb
module Users
  class Profile < ApplicationComponent
    # @param user [User] the user to display
    # @param maintenance_count [Integer] pre-computed count (eager-load in controller)
    # @param active_identities [Array<Identity>] pre-loaded active identities (eager-load in controller)
    # @param codex_fraction [Codex::Fraction, nil] eager-loaded current fraction
    def initialize(user:, maintenance_count: 0, active_identities: [], codex_fraction: nil)
      @user = user
      @active_identities = active_identities
      @maintenance_count = maintenance_count
      @codex_fraction    = codex_fraction
    end

    def view_template
      div(class: "max-w-4xl mx-auto space-y-8 animate-in slide-in-from-bottom-8 duration-700") do
        render_hero_profile

        div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
          render_access_privileges
          render_activity_stats
        end

        render_security_status
        render_linked_providers
        render_codex_fraction
      end
    end

    private

    def render_hero_profile
      div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none uppercase") { @user.role }

        div(class: "flex flex-col md:flex-row items-center md:items-start gap-6 md:gap-10") do
          # Аватар-плейсхолдер
          div(class: "h-32 w-32 rounded-none border-2 border-emerald-500 bg-emerald-950 flex items-center justify-center") do
            span(class: "text-5xl font-extralight text-emerald-400") { @user.first_name&.first || @user.email_address.first }
          end

          div(class: "text-center md:text-left") do
            h2(class: "text-4xl font-extralight text-white tracking-tighter") { "#{@user.first_name} #{@user.last_name}" }
            p(class: "text-emerald-800 font-mono text-xs uppercase tracking-widest mt-2") { @user.email_address }
            div(class: "mt-6 flex justify-center md:justify-start gap-4") do
              badge(t("users.profile.role", role: @user.role.upcase))
              badge(t("users.profile.id", id: @user.id))
            end
          end
        end
      end
    end

    def render_access_privileges
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("users.profile.sections.access_privileges") }
        div(class: "space-y-4 font-mono text-compact") do
          access_item(t("users.profile.access.organization"), @user.organization&.name || t("users.profile.none"))
          access_item(t("users.profile.access.command_execution"), @user.role == "admin" ? t("users.profile.access.full") : t("users.profile.access.limited"))
          access_item(t("users.profile.access.encryption"), "AES-256-GCM")
        end
      end
    end

    def render_activity_stats
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("users.profile.sections.activity") }
        div(class: "grid grid-cols-2 gap-4 text-center") do
          stat_box(t("users.profile.activity.records"), @maintenance_count)
          stat_box(t("users.profile.activity.last_sync"), @user.last_seen_at ? t("users.profile.activity.online") : t("users.profile.activity.offline"))
        end
      end
    end

    def render_security_status
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("users.profile.sections.security") }
          a(href: api_v1_account_security_path, class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-400 transition-colors border border-emerald-900 px-3 py-1") { t("users.profile.security.manage") }
        end

        div(class: "grid grid-cols-3 gap-4 font-mono text-compact") do
          security_indicator(t("users.profile.security.mfa"), @user.mfa_enabled?, @user.mfa_enabled? ? t("users.profile.security.active") : t("users.profile.security.disabled"))
          security_indicator(t("users.profile.security.password"), @user.password_digest.present?, @user.password_digest.present? ? t("users.profile.security.set") : t("users.profile.security.not_set"))
          security_indicator(t("users.profile.security.providers"), @active_identities.any?, t("users.profile.security.linked_count", count: @active_identities.size))
        end
      end
    end

    def render_linked_providers
      return if @active_identities.empty?

      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("users.profile.sections.linked_providers") }
        div(class: "flex flex-wrap gap-3") do
          @active_identities.each do |identity|
            provider_badge(identity)
          end
        end
      end
    end

    # Phase 3 — Codex Identity badge. Lives inside its own gaia-* island so
    # the legacy emerald palette of the surrounding profile is not touched.
    def render_codex_fraction
      div(class: "pt-2") do
        render Codex::Fractions::ProfileBadge.new(fraction: @codex_fraction)
      end
    end

    def security_indicator(label, is_active, value)
      div(class: "p-3 border border-emerald-900/30 text-center") do
        div(class: "flex items-center justify-center gap-2 mb-2") do
          div(class: tokens("h-2 w-2 rounded-full", "bg-emerald-500": is_active, "bg-red-500": !is_active)) { }
          span(class: "text-mini text-gray-600 uppercase") { label }
        end
        p(class: tokens("text-compact", "text-emerald-400": is_active, "text-red-400": !is_active)) { value }
      end
    end

    def provider_badge(identity)
      icon = case identity.provider
      when "google_oauth2" then "🔵"
      when "facebook"      then "🟦"
      when "linkedin"      then "🔷"
      when "twitter"       then "🐦"
      else "🔗"
      end

      div(class: "flex items-center gap-2 px-3 py-2 border border-emerald-900/50 bg-zinc-950") do
        span { icon }
        span(class: "text-tiny text-emerald-500 font-mono") { identity.provider.titleize }
        if identity.primary?
          span(class: "text-micro px-1 bg-emerald-900/30 text-emerald-600 uppercase") { t("users.profile.provider.primary") }
        end
      end
    end

    def access_item(label, value)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-500") { value }
      end
    end

    def stat_box(label, value)
      div do
        p(class: "text-mini uppercase text-gray-600") { label }
        p(class: "text-xl text-emerald-100 font-light mt-1") { value }
      end
    end

    def badge(text)
      span(class: "px-3 py-1 border border-emerald-900 text-mini text-emerald-600 uppercase tracking-tighter") { text }
    end
  end
end
