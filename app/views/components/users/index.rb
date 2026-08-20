# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Users
  class Index < ApplicationComponent
    def initialize(users:, pagy: nil)
      @users = users
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8") do
        header_section

        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".table.identity") }
                th(scope: "col", class: "p-4") { t(".table.role_access") }
                th(scope: "col", class: "p-4") { t(".table.neural_link") }
                th(scope: "col", class: "p-4 text-right") { t(".table.audit") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              @users.each { |user| render_user_row(user) }
            end
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { users_path(page: page) }
          )
        end
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".heading") }
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
      end
    end

    def render_user_row(user)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors group") do
        td(class: "p-4") do
          div(class: "flex items-center gap-3") do
            div(class: "h-8 w-8 rounded-full bg-gaia-surface-sunken border border-gaia-primary flex items-center justify-center text-gaia-primary-strong font-bold") { user.first_name&.first || user.email_address.first }
            span(class: "text-gaia-text-strong") { "#{user.first_name} #{user.last_name}" }
          end
        end
        td(class: "p-4") do
          span(class: tokens("px-2 py-0.5 rounded-sm text-mini font-bold uppercase", role_color(user.role))) { user.role_label }
        end
        td(class: "p-4 text-gaia-text-muted") do
           if user.last_seen_at
             render Views::Shared::UI::RelativeTime.new(
               datetime: user.last_seen_at,
               css_class: "text-gaia-text-muted text-compact font-mono",
               prefix: "#{t('.active_prefix')} "
             )
           else
             plain t(".link_offline")
           end
        end
        td(class: "p-4 text-right") do
          # Аудиторії збігаються точно, тож роле-гейт тут не потрібен: `UserPolicy#index?`
          # і `AuditLogsController#authorize_admin!` обидва питають `admin_or_above?`.
          a(
            href: audit_logs_path(user_id: user.id),
            class: "text-gaia-primary-strong hover:text-gaia-text-strong transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria_label: t(".table.view_logs_aria", name: "#{user.first_name} #{user.last_name}")
          ) { t(".table.view_logs") }
        end
      end
    end

    # 🔴 [TEST.12] `super_admin` мусить мати ВЛАСНУ гілку: enum має чотири значення,
    # а мапа знала три — тож найпривілейованіша роль падала в той самий `else`, що й
    # пошкоджене значення, тобто візуально не відрізнялась від «невідомо що це».
    # Бурштин (warning), а не червоний: платформенний рівень стоїть НАД org-адміном,
    # і сусідні кольори вже зайняті ієрархією investor→forester→admin.
    #
    # [UI.1] Бейдж = пастель + `-text`-пара (роль за каноном §3.2); мапа лишається
    # приватною, бо ключі ролей не живуть у спільному `StatusBadge::STYLES`, а мітку
    # дає власний дім `User#role_label` — тут лише колір.
    def role_color(role)
      case role
      when "super_admin" then "bg-status-warning text-status-warning-text border border-status-warning-accent"
      when "admin" then "bg-status-danger text-status-danger-text border border-status-danger-accent"
      when "forester" then "bg-status-active text-status-active-text border border-gaia-primary-strong"
      when "investor" then "bg-status-info text-status-info-text border border-status-info-accent"
      else "bg-gaia-surface-elevated text-gaia-text-subtle"
      end
    end
  end
end
