# app/views/components/users/profile.rb
module Users
  class Profile < ApplicationComponent
    def initialize(user:)
      @user = user
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
      end
    end

    private

    def render_hero_profile
      div(class: "p-10 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none uppercase") { @user.role }

        div(class: "flex flex-col md:flex-row items-center md:items-start space-y-6 md:space-y-0 md:space-x-10") do
          # Аватар-плейсхолдер
          div(class: "h-32 w-32 rounded-none border-2 border-emerald-500 bg-emerald-950 flex items-center justify-center") do
            span(class: "text-5xl font-extralight text-emerald-400") { @user.first_name&.first || @user.email_address.first }
          end

          div(class: "text-center md:text-left") do
            h2(class: "text-4xl font-extralight text-white tracking-tighter") { "#{@user.first_name} #{@user.last_name}" }
            p(class: "text-emerald-800 font-mono text-xs uppercase tracking-widest mt-2") { @user.email_address }
            div(class: "mt-6 flex justify-center md:justify-start space-x-4") do
              badge("Role: #{@user.role.upcase}")
              badge("ID: ##{@user.id}")
            end
          end
        end
      end
    end

    def render_access_privileges
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Neural Access Privileges" }
        div(class: "space-y-4 font-mono text-[11px]") do
          access_item("Organization Access", @user.organization&.name || "None")
          access_item("Command Execution", @user.role == "admin" ? "Full" : "Limited")
          access_item("Encryption Level", "AES-256-GCM")
        end
      end
    end

    def render_activity_stats
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-6") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Operational Activity" }
        div(class: "grid grid-cols-2 gap-4 text-center") do
          stat_box("Records", @user.maintenance_records.count)
          stat_box("Last Sync", @user.last_seen_at ? "ONLINE" : "OFFLINE")
        end
      end
    end

    def render_security_status
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Security Status" }
          a(href: helpers.api_v1_account_security_path, class: "text-[9px] text-emerald-700 uppercase tracking-widest hover:text-emerald-400 transition-colors border border-emerald-900 px-3 py-1") { "Manage →" }
        end

        div(class: "grid grid-cols-3 gap-4 font-mono text-[11px]") do
          security_indicator("2FA / MFA", @user.mfa_enabled?, @user.mfa_enabled? ? "Active" : "Disabled")
          security_indicator("Password", @user.password_digest.present?, @user.password_digest.present? ? "Set" : "Not Set")
          security_indicator("Providers", @user.identities.active.any?, "#{@user.identities.active.count} linked")
        end
      end
    end

    def render_linked_providers
      identities = @user.identities.active

      return if identities.empty?

      div(class: "p-6 border border-emerald-900 bg-emerald-950/5 space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Linked Identity Providers" }
        div(class: "flex flex-wrap gap-3") do
          identities.each do |identity|
            provider_badge(identity)
          end
        end
      end
    end

    def security_indicator(label, is_active, value)
      div(class: "p-3 border border-emerald-900/30 text-center") do
        div(class: "flex items-center justify-center space-x-2 mb-2") do
          div(class: "h-2 w-2 rounded-full #{is_active ? 'bg-emerald-500' : 'bg-red-500'}") { }
          span(class: "text-[9px] text-gray-600 uppercase") { label }
        end
        p(class: "text-[11px] #{is_active ? 'text-emerald-400' : 'text-red-400'}") { value }
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

      div(class: "flex items-center space-x-2 px-3 py-2 border border-emerald-900/50 bg-zinc-950") do
        span { icon }
        span(class: "text-[10px] text-emerald-500 font-mono") { identity.provider.titleize }
        if identity.primary?
          span(class: "text-[7px] px-1 bg-emerald-900/30 text-emerald-600 uppercase") { "Primary" }
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
        p(class: "text-[9px] uppercase text-gray-600") { label }
        p(class: "text-xl text-emerald-100 font-light mt-1") { value }
      end
    end

    def badge(text)
      span(class: "px-3 py-1 border border-emerald-900 text-[9px] text-emerald-600 uppercase tracking-tighter") { text }
    end
  end
end
