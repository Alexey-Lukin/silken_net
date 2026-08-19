# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Navigation
  class Sidebar < ApplicationComponent
    # All data must be passed explicitly — no DB queries, no request/session access.
    # @param current_path [String] current request path for active-nav highlighting
    # @param ews_alert_count [Integer] pre-computed count of unresolved EWS alerts (eager-load in controller/layout)
    # @param current_user [User, nil] актор — потрібен ЛИШЕ для роле-фільтра пунктів [UI.5]
    #
    # Дефолт `nil` навмисно fail-CLOSED: якщо шар вище забуде передати актора, меню
    # звузиться до відкритих пунктів, а не роздасть гейтовані. Компонент-спека такої
    # помилки не побачила б у принципі — вона конструює компонент повз `DashboardLayout`,
    # тож сторожем проводки є request-спека.
    def initialize(current_path: "/", ews_alert_count: 0, current_user: nil)
      @current_path = current_path
      @ews_alert_count = ews_alert_count
      @current_user = current_user
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
        aria_label: t("navigation.logo.title")
      ) do
        render_logo
        render_status_pulse

        nav(class: "flex-1 px-4 py-8 space-y-10") do
          section_group(:strategic_insight) do
            nav_item(:oracle_visions,    oracle_visions_path,           "eye", min_role: :forester)
            nav_item(:treasury_matrix,   wallets_path,                  "bank")
            nav_item(:naas_contracts,    contracts_path,                "clipboard")
            nav_item(:blockchain_ledger, blockchain_transactions_path,  "bank")
            nav_item(:reports_archive,   reports_path,                  "clipboard")
          end

          section_group(:forest_operations) do
            nav_item(:threat_alerts,   alerts_path,                "zap", badge: @ews_alert_count)
            nav_item(:soldier_fleet,   clusters_path,              "tree")
            nav_item(:maintenance_log, maintenance_records_path,   "clipboard", min_role: :forester)
            nav_item(:crew_registry,   users_path,                 "users",     min_role: :admin)
            nav_item(:clan_hierarchy,  organizations_path,         "users",     min_role: :super_admin)
          end

          section_group(:neural_network) do
            nav_item(:queen_relays,   gateways_path,                     "radio")
            nav_item(:species_dna,    tree_families_path,                "activity", min_role: :admin)
            nav_item(:firmware_ota,   firmwares_path,                    "cpu",      min_role: :admin)
            nav_item(:live_telemetry, live_stream_telemetry_index_path,  "activity", pulse: true)
            nav_item(:initiate_node,  new_provisioning_path,             "zap",      min_role: :forester)
          end

          section_group(:administration) do
            nav_item(:account_security, account_security_path,        "eye")
            nav_item(:notifications,    notifications_settings_path,  "radio")
            nav_item(:org_settings,     settings_path,                "cpu",       min_role: :admin)
            nav_item(:audit_log,        audit_logs_path,              "eye",       min_role: :admin)
            nav_item(:system_audits,    system_audits_path,           "clipboard", min_role: :admin)
            nav_item(:system_health,    system_health_path,           "activity",  min_role: :admin)
          end
        end

        render_user_footer
      end
    end

    private


    def render_logo
      div(class: "px-6 py-8 border-b border-gaia-border transition-colors duration-300") do
        h1(class: "text-gaia-primary font-extralight tracking-[0.4em] uppercase text-lg leading-tight") { t("navigation.logo.title") }
        p(class: "text-micro text-gaia-text-subtle mt-1 uppercase tracking-widest")                   { t("navigation.logo.subtitle") }
      end
    end

    def render_status_pulse
      div(class: "px-6 py-4 bg-gaia-surface-sunken flex items-center justify-between border-b border-gaia-border transition-colors duration-300") do
        div(class: "flex items-center gap-2") do
          div(class: "h-1.5 w-1.5 rounded-full bg-gaia-primary animate-pulse", aria_hidden: "true")
          span(class: "text-mini text-gaia-text-muted uppercase tracking-widest") { t("navigation.status.sync_label") }
        end
        span(class: "text-mini text-gaia-text-subtle") { t("navigation.status.version") }
      end
    end

    def section_group(key, &block)
      div(class: "space-y-4") do
        h3(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-subtle px-2") { t("navigation.sections.#{key}") }
        div(class: "space-y-1", &block)
      end
    end

    # [UI.5] `min_role:` стоїть у РЯДКУ самого пункту навмисно: розходження меню з
    # гардом контролера має бути видно оком, а не вишукуватись у таблиці десь нижче.
    # Значення — не власне правило, а вказівник на предикат `User`, тобто те саме
    # джерело, яке читають `authorize_admin!`/`authorize_forester!`/`authorize_super_admin!`.
    def nav_item(key, path, icon, badge: nil, pulse: false, min_role: nil)
      return unless visible_to_actor?(min_role)

      label  = t("navigation.items.#{key}")
      # Збіг по МЕЖІ СЕГМЕНТА, не по підрядку [ARCH.77]. Сьогодні колізії немає
      # (жоден із коренів меню не є префіксом іншого — перевірено попарно), тож
      # це профілактика: голий `start_with?` підсвітив би два пункти одразу в
      # день, коли зʼявиться маршрут із рядковим, а не сегментним, збігом — і
      # спека цього не побачила б, бо перевіряє ПРИСУТНІСТЬ `aria-current`,
      # а не його одиничність.
      target = path.split("?").first
      active = @current_path == target || @current_path.start_with?("#{target}/")

      # [UI.3] Без aria_label: він ПЕРЕКРИВАВ дочірній текст для SR — незрячий
      # не чув EWS-badge («Threat Alerts 5» ставало «Threat Alerts»). Діти
      # самодостатні: icon aria_hidden, label-span + badge-span читаються.
      a(
        href: path,
        aria_current: (active ? "page" : nil),
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
              "text-gaia-text-subtle group-hover:text-gaia-primary-strong": !active
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

    # Диспетчер, а не правило: кожна гілка кличе предикат `User` — той самий, який
    # читає відповідний гард контролера. Власної умови тут немає навмисно, інакше
    # меню стало б четвертим домом RBAC-формул. Невідомий рівень і відсутній актор
    # дають `false` — fail-closed.
    def visible_to_actor?(min_role)
      return true if min_role.nil?

      # Найвужчий рівень стоїть в `else` навмисно, і це не стиль: окрема гілка під
      # невідомий рівень була б НЕДОСЯЖНОЮ (метод приватний, значення задають тут же),
      # тобто мертвим кодом, який per-group branch-coverage чесно ловить. Так само
      # тримається й fail-closed: незнайомий рівень читається як найсуворіший.
      case min_role
      when :forester then @current_user&.forest_commander?
      when :admin    then @current_user&.admin_or_above?
      else                @current_user&.super_admin?
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
      "text-gaia-text-muted border-transparent hover:text-gaia-primary-strong " \
        "hover:bg-gaia-surface-sunken hover:border-gaia-border-strong"
    end

    def render_user_footer
      div(class: "p-4 border-t border-gaia-border mt-auto bg-gaia-surface transition-colors duration-300") do
        div(class: "flex items-center gap-3 px-2") do
          div(class: "h-8 w-8 border border-gaia-primary flex items-center justify-center text-gaia-primary text-tiny") { "A" }
          div(class: "flex-1 overflow-hidden") do
            p(class: "text-tiny text-gaia-text-strong truncate")                          { t("navigation.footer.role") }
            p(class: "text-micro text-gaia-text-subtle uppercase tracking-widest")        { t("navigation.footer.access") }
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
