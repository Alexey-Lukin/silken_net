# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AuditLogs
  class Index < ApplicationComponent
    # `filters:` — активні фільтри запиту (`user_id` / `action_type`). Приймаються
    # ЯВНО, бо без них сторінка бреше двічі: пагінація губила б фільтр на другій
    # сторінці (тихо повертаючи повний журнал), а відфільтрована видача була б
    # візуально невідрізнима від повної — тобто порожній результат читався б як
    # «журнал аудиту порожній». [UI.7]
    def initialize(logs:, pagy:, filters: {})
      @logs    = logs
      @pagy    = pagy
      @filters = filters.compact
    end

    def view_template
      div(class: "space-y-6") do
        header_section
        filter_notice
        audit_table
        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { audit_logs_path(**@filters, page: page) }
        )
      end
    end

    private

    def filter_notice
      return if @filters.empty?

      div(class: "flex items-center gap-3 border border-gaia-border bg-gaia-surface-sunken px-4 py-2") do
        span(class: "text-mini uppercase tracking-widest text-gaia-text-muted") { t(".filtered") }
        a(
          href: audit_logs_path,
          class: "text-mini uppercase tracking-widest text-gaia-primary-strong hover:text-gaia-text-strong " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
        ) { t(".clear_filter") }
      end
    end

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".title") }
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
        div(class: "text-right font-mono text-tiny text-gaia-text-subtle") do
          plain "#{t('.records')} "
          span(class: "text-gaia-primary-strong") { @pagy.count.to_s }
        end
      end
    end

    def audit_table
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".columns.timestamp") }
              th(scope: "col", class: "p-4") { t(".columns.user") }
              th(scope: "col", class: "p-4") { t(".columns.action") }
              th(scope: "col", class: "p-4") { t(".columns.target") }
              th(scope: "col", class: "p-4 text-right") { t(".columns.details") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            if @logs.any?
              @logs.each { |log| render_log_row(log) }
            else
              render Views::Shared::UI::EmptyState.new(
                title: t(".empty_title"),
                icon: "👁️",
                colspan: 5
              )
            end
          end
        end
      end
    end

    def render_log_row(log)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors") do
        td(class: "p-4 text-tiny text-gaia-text-muted") { log.created_at.strftime("%H:%M:%S // %d.%m.%y") }
        td(class: "p-4 text-gaia-text") { log.user&.full_name || t(".system_user") }
        td(class: "p-4") do
          render Views::Shared::UI::ActionBadge.new(action: log.action, metadata: log.metadata)
        end
        td(class: "p-4 text-gaia-text-subtle") do
          if log.auditable_type.present?
            plain "#{log.auditable_type} ##{log.auditable_id}"
          else
            span(class: "text-gaia-text italic") { "—" }
          end
        end
        td(class: "p-4 text-right") do
          a(href: audit_log_path(log), class: "text-gaia-primary-strong hover:text-gaia-text-strong transition-all text-mini uppercase tracking-widest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".inspect_aria", id: log.id)) { t(".inspect") }
        end
      end
    end
  end
end
