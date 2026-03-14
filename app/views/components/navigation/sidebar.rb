# frozen_string_literal: true

module Navigation
  class Sidebar < ApplicationComponent
    # All data must be passed explicitly — no DB queries, no request/session access.
    # @param current_path [String] current request path for active-nav highlighting
    # @param ews_alert_count [Integer] pre-computed count of unresolved EWS alerts (eager-load in controller/layout)
    def initialize(current_path: "/", ews_alert_count: 0)
      @current_path = current_path
      @ews_alert_count = ews_alert_count
    end

    def view_template
      aside(
        class: "w-64 h-screen sticky top-0 bg-white dark:bg-black border-r border-gray-200 dark:border-emerald-900/50 flex flex-col z-50 overflow-y-auto font-mono transition-colors duration-300",
        role: "navigation",
        aria_label: "Main navigation"
      ) do
        render_logo
        render_status_pulse

        nav(class: "flex-1 px-4 py-8 space-y-10") do
          # СТРАТЕГІЧНИЙ КОНТУР
          section_group("Strategic Insight") do
            nav_item("Oracle Visions", helpers.api_v1_oracle_visions_path, "eye")
            nav_item("Treasury Matrix", helpers.api_v1_wallets_path, "bank")
            nav_item("NaaS Contracts", helpers.api_v1_contracts_path, "clipboard")
            nav_item("Blockchain Ledger", helpers.api_v1_blockchain_transactions_path, "bank")
            nav_item("Reports Archive", helpers.api_v1_reports_path, "clipboard")
          end

          # ОПЕРАЦІЙНИЙ КОНТУР
          section_group("Forest Operations") do
            nav_item("Threat Alerts", helpers.api_v1_alerts_path, "zap", badge: @ews_alert_count)
            nav_item("Soldier Fleet", helpers.api_v1_clusters_path, "tree")
            nav_item("Maintenance Log", helpers.api_v1_maintenance_records_path, "clipboard")
            nav_item("Crew Registry", helpers.api_v1_users_path, "users")
            nav_item("Clan Hierarchy", helpers.api_v1_organizations_path, "users")
          end

          # ТЕХНІЧНИЙ КОНТУР
          section_group("Neural Network") do
            nav_item("Queen Relays", helpers.api_v1_gateways_path, "radio")
            nav_item("Species DNA", helpers.api_v1_tree_families_path, "activity") # Нове: Геноми
            nav_item("Firmware OTA", helpers.api_v1_firmwares_path, "cpu")
            nav_item("Live Telemetry", helpers.live_api_v1_telemetry_index_path, "activity", pulse: true)
            nav_item("Initiate Node", helpers.new_api_v1_provisioning_path, "zap") # Швидкий доступ до ініціації
          end

          # АДМІНІСТРУВАННЯ
          section_group("Administration") do
            nav_item("Account Security", helpers.api_v1_account_security_path, "eye")
            nav_item("Notifications", helpers.api_v1_notifications_settings_path, "radio")
            nav_item("Org Settings", helpers.api_v1_settings_path, "cpu")
            nav_item("Audit Log", helpers.api_v1_audit_logs_path, "eye")
            nav_item("System Audits", helpers.api_v1_system_audits_path, "clipboard")
            nav_item("System Health", helpers.api_v1_system_health_path, "activity")
          end
        end

        render_user_footer
      end
    end

    private

    def render_logo
      div(class: "px-6 py-8 border-b border-gray-200 dark:border-emerald-900/30 transition-colors duration-300") do
        h1(class: "text-gaia-primary font-extralight tracking-[0.4em] uppercase text-lg leading-tight") { "Silken Net" }
        p(class: "text-micro text-gray-400 dark:text-emerald-900 mt-1 uppercase tracking-widest") { "Central Command Citadel" }
      end
    end

    def render_status_pulse
      div(class: "px-6 py-4 bg-gray-50 dark:bg-emerald-950/10 flex items-center justify-between border-b border-gray-200 dark:border-emerald-900/20 transition-colors duration-300") do
        div(class: "flex items-center gap-2") do
          div(class: "h-1.5 w-1.5 rounded-full bg-gaia-primary animate-pulse")
          span(class: "text-mini text-gray-500 dark:text-emerald-700 uppercase tracking-widest") { "Sync: 1.12 THz" }
        end
        span(class: "text-mini text-gray-400 dark:text-emerald-900") { "v8.0.ocean" }
      end
    end

    def section_group(title, &block)
      div(class: "space-y-4") do
        h3(class: "text-mini uppercase tracking-[0.3em] text-gray-400 dark:text-emerald-900 px-2") { title }
        div(class: "space-y-1", &block)
      end
    end

    def nav_item(label, path, icon, badge: nil, pulse: false)
      active = @current_path.start_with?(path.split("?").first)

      a(
        href: path,
        aria_current: (active ? "page" : nil),
        aria_label: label,
        class: tokens(
          nav_item_base_classes,
          active ? nav_item_active_classes : nav_item_inactive_classes
        )
      ) do
        div(class: "flex items-center gap-3") do
          span(class: tokens("w-4 h-4", "text-gaia-primary": active, "text-gray-300 dark:text-emerald-900 group-hover:text-gaia-primary": !active), aria_hidden: "true") { render_icon(icon) }
          span { label }
        end

        if badge&.positive?
          span(class: "bg-red-100 dark:bg-red-900/50 text-red-600 dark:text-red-500 text-micro px-1.5 py-0.5 rounded-sm") { badge }
        elsif pulse
          div(class: "h-1 w-1 rounded-full bg-gaia-primary animate-ping")
        end
      end
    end

    def nav_item_base_classes
      "group flex items-center justify-between px-3 py-2 text-compact uppercase tracking-widest " \
        "transition-all duration-200 ease-in-out border-l-2 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-emerald-500"
    end

    def nav_item_active_classes
      "text-gaia-primary bg-emerald-50 dark:bg-emerald-950/20 border-gaia-primary"
    end

    def nav_item_inactive_classes
      "text-gray-500 border-transparent hover:text-gaia-primary hover:bg-gray-50 dark:hover:bg-emerald-950/5 " \
        "hover:border-gray-300 dark:hover:border-emerald-900/50 active:bg-emerald-950/10"
    end

    def render_user_footer
      div(class: "p-4 border-t border-gray-200 dark:border-emerald-900/30 mt-auto bg-white dark:bg-black transition-colors duration-300") do
        div(class: "flex items-center gap-3 px-2") do
          div(class: "h-8 w-8 rounded-none border border-gaia-primary flex items-center justify-center text-gaia-primary text-tiny") { "A" }
          div(class: "flex-1 overflow-hidden") do
            p(class: "text-tiny text-gray-900 dark:text-emerald-100 truncate") { "Architect" }
            p(class: "text-micro text-gray-400 dark:text-emerald-900 uppercase tracking-widest") { "Full Access Link" }
          end
        end
      end
    end

    def render_icon(name)
      case name
      when "eye" then "⊙"
      when "bank" then "⬢"
      when "zap" then "⚡"
      when "users" then "◈"
      when "radio" then "📡"
      when "cpu" then "⚙"
      when "activity" then "〰"
      when "tree" then "🌳"
      when "clipboard" then "▤"
      else "○"
      end
    end
  end
end
