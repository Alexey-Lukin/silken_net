# SPDX-License-Identifier: AGPL-3.0-or-later
# app/views/components/users/profile.rb
module Users
  class Profile < ApplicationComponent
    # @param user [User] the user to display
    # @param maintenance_count [Integer] pre-computed count (eager-load in controller)
    # @param active_identities [Array<Identity>] pre-loaded active identities (eager-load in controller)
    def initialize(user:, maintenance_count: 0, active_identities: [])
      @user = user
      @active_identities = active_identities
      @maintenance_count = maintenance_count
    end

    def view_template
      div(class: "max-w-4xl mx-auto space-y-8") do
        render_hero_profile

        div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
          render_access_privileges
          render_activity_stats
        end

        render_security_status
        render_linked_providers
      end
    end

    private

    def render_hero_profile
      div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none uppercase", aria_hidden: "true") { @user.role_label }

        div(class: "flex flex-col md:flex-row items-center md:items-start gap-6 md:gap-10") do
          # Аватар-плейсхолдер
          div(class: "h-32 w-32 rounded-none border-2 border-emerald-500 bg-emerald-950 flex items-center justify-center") do
            span(class: "text-5xl font-extralight text-emerald-400") { @user.first_name&.first || @user.email_address.first }
          end

          div(class: "text-center md:text-left") do
            h2(class: "text-4xl font-extralight text-white tracking-tighter") { "#{@user.first_name} #{@user.last_name}" }
            p(class: "text-emerald-800 font-mono text-xs uppercase tracking-widest mt-2") { @user.email_address }
            div(class: "mt-6 flex justify-center md:justify-start gap-4") do
              badge(t(".role", role: @user.role_label.upcase))
              badge(t(".id", id: @user.id))
            end
          end
        end
      end
    end

    def render_access_privileges
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".sections.access_privileges") }
        div(class: "space-y-4 font-mono text-compact") do
          access_item(t(".access.organization"), @user.organization&.name || t(".none"))
          # Через предикат, а не рядкове порівняння: `role == "admin"` казало
          # super_admin'ові, що його доступ обмежений (`User#admin_or_above?`).
          access_item(t(".access.command_execution"), @user.admin_or_above? ? t(".access.full") : t(".access.limited"))
          # [UI.17] Тут стояв `access_item(t(".access.encryption"), "AES-256-GCM")`.
          # Режим названо правильно — це дефолт AR-encryption, — але НЕ ПРО ЦЬОГО
          # СУБʼЄКТА: `User` не має жодного `encrypts` (шифруються лише `Identity`
          # і `HardwareKey`), тож у панелі привілеїв акаунта рядок читався як
          # обіцянка захисту, якої цій таблиці ніхто не давав. Хибною була АДРЕСА
          # твердження, не термін — і саме тому греп за «чи існує GCM» його виправдовував.
        end
      end
    end

    def render_activity_stats
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".sections.activity") }
        div(class: "grid grid-cols-2 gap-4 text-center") do
          stat_box(t(".activity.records"), @maintenance_count)
          stat_box_last_seen
        end
      end
    end

    def render_security_status
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".sections.security") }
          a(href: account_security_path, class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-400 transition-colors border border-emerald-900 px-3 py-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") { t(".security.manage") }
        end

        div(class: "grid grid-cols-3 gap-4 font-mono text-compact") do
          security_indicator(t(".security.mfa"), @user.mfa_enabled?, @user.mfa_enabled? ? t(".security.active") : t(".security.disabled"))
          security_indicator(t(".security.password"), @user.password_digest.present?, @user.password_digest.present? ? t(".security.set") : t(".security.not_set"))
          security_indicator(t(".security.providers"), @active_identities.any?, t(".security.linked_count", count: @active_identities.size))
        end
      end
    end

    def render_linked_providers
      return if @active_identities.empty?

      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".sections.linked_providers") }
        div(class: "flex flex-wrap gap-3") do
          @active_identities.each do |identity|
            provider_badge(identity)
          end
        end
      end
    end

    def security_indicator(label, is_active, value)
      div(class: "p-3 border border-emerald-900/30 text-center") do
        div(class: "flex items-center justify-center gap-2 mb-2") do
          div(class: tokens("h-2 w-2 rounded-full", "bg-gaia-primary-strong": is_active, "bg-status-danger-accent": !is_active)) { }
          span(class: "text-mini text-gray-600 uppercase") { label }
        end
        p(class: tokens("text-compact", "text-gaia-primary-strong": is_active, "text-status-danger-accent": !is_active)) { value }
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
        span(class: "text-tiny text-emerald-500 font-mono") { identity.provider_name }
        if identity.primary?
          span(class: "text-micro px-1 bg-emerald-900/30 text-emerald-600 uppercase") { t(".provider.primary") }
        end
      end
    end

    def access_item(label, value)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-500") { value }
      end
    end

    def stat_box(label, value = nil)
      div do
        p(class: "text-mini uppercase text-gray-600") { label }
        p(class: "text-xl text-emerald-100 font-light mt-1") { block_given? ? yield : value }
      end
    end

    # [UI.10] Мітка питає ЧАС («Last Sync»), тож у комірці стоїть час.
    # Вердикт «online» тут був presence-перевіркою: акаунт, що заходив торік,
    # лишався «онлайн» назавжди. Recency-предикат за зразком `Gateway#online?`
    # тут побудувати НІЧИМ — у людини немає задекларованої каденції, тож будь-яке
    # вікно було б вигаданим порогом; сусідній `Users::Index` рівно тому й
    # показує факт. Ніколи не баченого відрізняємо явно.
    def stat_box_last_seen
      stat_box(t(".activity.last_sync")) do
        if @user.last_seen_at
          render Views::Shared::UI::RelativeTime.new(
            datetime: @user.last_seen_at,
            css_class: "text-xl text-emerald-100 font-light"
          )
        else
          plain t(".activity.never_seen")
        end
      end
    end

    def badge(text)
      span(class: "px-3 py-1 border border-emerald-900 text-mini text-emerald-600 uppercase tracking-tighter") { text }
    end
  end
end
