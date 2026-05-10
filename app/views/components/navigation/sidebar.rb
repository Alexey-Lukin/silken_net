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
        class: tokens(
          "w-64 h-full md:h-screen md:sticky md:top-0",
          "bg-gaia-surface border-r border-gaia-border",
          "flex flex-col z-50 overflow-y-auto font-mono",
          "transition-colors duration-300"
        ),
        role: "navigation",
        aria_label: tr("logo.title")
      ) do
        render_logo
        render_status_pulse

        nav(class: "flex-1 px-4 py-8 space-y-10") do
          section_group(:strategic_insight) do
            nav_item(:oracle_visions,    api_v1_oracle_visions_path,           "eye")
            nav_item(:treasury_matrix,   api_v1_wallets_path,                  "bank")
            nav_item(:naas_contracts,    api_v1_contracts_path,                "clipboard")
            nav_item(:blockchain_ledger, api_v1_blockchain_transactions_path,  "bank")
            nav_item(:reports_archive,   api_v1_reports_path,                  "clipboard")
          end

          section_group(:library) do
            nav_item(:codex_atlas,  api_v1_codex_nodes_path,           "book")
            nav_item(:battle_arena, new_api_v1_codex_match_path,       "swords")
            nav_item(:leaderboard,  api_v1_codex_leaderboard_path,     "trophy")
            nav_item(:my_codex,     api_v1_codex_my_discoveries_path,  "book")
            nav_item(:my_fraction,  api_v1_codex_my_fraction_path,     "shield")
          end

          section_group(:forest_operations) do
            nav_item(:threat_alerts,   api_v1_alerts_path,                "zap", badge: @ews_alert_count)
            nav_item(:soldier_fleet,   api_v1_clusters_path,              "tree")
            nav_item(:maintenance_log, api_v1_maintenance_records_path,   "clipboard")
            nav_item(:crew_registry,   api_v1_users_path,                 "users")
            nav_item(:clan_hierarchy,  api_v1_organizations_path,         "users")
          end

          section_group(:neural_network) do
            nav_item(:queen_relays,   api_v1_gateways_path,                     "radio")
            nav_item(:species_dna,    api_v1_tree_families_path,                "activity")
            nav_item(:firmware_ota,   api_v1_firmwares_path,                    "cpu")
            nav_item(:live_telemetry, live_stream_api_v1_telemetry_index_path,  "activity", pulse: true)
            nav_item(:initiate_node,  new_api_v1_provisioning_path,             "zap")
          end

          section_group(:administration) do
            nav_item(:account_security, api_v1_account_security_path,        "eye")
            nav_item(:notifications,    api_v1_notifications_settings_path,  "radio")
            nav_item(:org_settings,     api_v1_settings_path,                "cpu")
            nav_item(:audit_log,        api_v1_audit_logs_path,              "eye")
            nav_item(:system_audits,    api_v1_system_audits_path,           "clipboard")
            nav_item(:system_health,    api_v1_system_health_path,           "activity")
          end
        end

        render_user_footer
      end
    end

    private

    # Lazy-lookup helper scoped to the `navigation.*` namespace so call-sites
    # stay terse: `tr("logo.title")` instead of `I18n.t("navigation.logo.title")`.
    # Mirrors the Rails view-helper convention `t(".key")` adapted for Phlex.
    def tr(key)
      I18n.t("navigation.#{key}")
    end

    def render_logo
      div(class: "px-6 py-8 border-b border-gaia-border transition-colors duration-300") do
        h1(class: "text-gaia-primary font-extralight tracking-[0.4em] uppercase text-lg leading-tight") { tr("logo.title") }
        p(class: "text-micro text-gaia-text-subtle mt-1 uppercase tracking-widest")                   { tr("logo.subtitle") }
      end
    end

    def render_status_pulse
      div(class: "px-6 py-4 bg-gaia-surface-sunken flex items-center justify-between border-b border-gaia-border transition-colors duration-300") do
        div(class: "flex items-center gap-2") do
          div(class: "h-1.5 w-1.5 rounded-full bg-gaia-primary animate-pulse", aria_hidden: "true")
          span(class: "text-mini text-gaia-text-muted uppercase tracking-widest") { tr("status.sync_label") }
        end
        span(class: "text-mini text-gaia-text-subtle") { tr("status.version") }
      end
    end

    def section_group(key, &block)
      div(class: "space-y-4") do
        h3(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-subtle px-2") { tr("sections.#{key}") }
        div(class: "space-y-1", &block)
      end
    end

    def nav_item(key, path, icon, badge: nil, pulse: false)
      label  = tr("items.#{key}")
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
        div(class: "flex items-center gap-3 min-w-0") do
          span(
            class: tokens(
              "w-4 h-4 shrink-0",
              "text-gaia-primary": active,
              "text-gaia-text-subtle group-hover:text-gaia-primary": !active
            ),
            aria_hidden: "true"
          ) { render_icon(icon) }
          span(class: "truncate") { label }
        end

        if badge&.positive?
          span(class: "bg-status-danger text-status-danger-text text-micro px-1.5 py-0.5 rounded-sm shrink-0") { badge }
        elsif pulse
          div(class: "h-1 w-1 rounded-full bg-gaia-primary animate-ping", aria_hidden: "true")
        end
      end
    end

    def nav_item_base_classes
      "group flex items-center justify-between px-3 py-2 text-compact uppercase tracking-widest " \
        "transition-all duration-200 ease-in-out border-l-2 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-gaia-primary"
    end

    def nav_item_active_classes
      "text-gaia-primary bg-gaia-primary-soft border-gaia-primary"
    end

    def nav_item_inactive_classes
      "text-gaia-text-muted border-transparent hover:text-gaia-primary " \
        "hover:bg-gaia-surface-sunken hover:border-gaia-border-strong"
    end

    def render_user_footer
      div(class: "p-4 border-t border-gaia-border mt-auto bg-gaia-surface transition-colors duration-300") do
        div(class: "flex items-center gap-3 px-2") do
          div(class: "h-8 w-8 border border-gaia-primary flex items-center justify-center text-gaia-primary text-tiny") { "A" }
          div(class: "flex-1 overflow-hidden") do
            p(class: "text-tiny text-gaia-text-strong truncate")                          { tr("footer.role") }
            p(class: "text-micro text-gaia-text-subtle uppercase tracking-widest")        { tr("footer.access") }
          end
        end
      end
    end

    ICON_GLYPHS = {
      "eye" => "⊙", "bank" => "⬢", "zap" => "⚡", "users" => "◈",
      "radio" => "📡", "cpu" => "⚙", "activity" => "〰", "tree" => "🌳",
      "clipboard" => "▤", "book" => "📖", "shield" => "🛡",
      "swords" => "⚔", "trophy" => "🏆"
    }.freeze

    def render_icon(name)
      ICON_GLYPHS.fetch(name, "○")
    end
  end
end
