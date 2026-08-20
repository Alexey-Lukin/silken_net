# SPDX-License-Identifier: AGPL-3.0-or-later
module SystemAudits
  class Index < ApplicationComponent
    def initialize(audit:)
      @audit = audit
    end

    def view_template
      div(class: "space-y-6") do
        header_section
        status_banner
        comparison_table
        timestamp_footer
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
        div(class: "flex gap-2") do
          status_badge
        end
      end
    end

    def status_banner
      if @audit.critical
        div(class: "border border-status-danger-accent bg-status-danger/10 p-4", role: "alert") do
          p(class: "text-status-danger-accent text-xs font-mono font-bold uppercase tracking-widest") do
            t(".critical", delta: format_scc(@audit.delta))
          end
        end
      else
        div(class: "border border-gaia-border bg-gaia-surface-sunken p-4", role: "status") do
          p(class: "text-gaia-primary-strong text-xs font-mono uppercase tracking-widest") do
            t(".ok", delta: format_scc(@audit.delta))
          end
        end
      end
    end

    def comparison_table
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact", role: "table") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".columns.source") }
              th(scope: "col", class: "p-4 text-right") { t(".columns.total") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            tr(class: "hover:bg-gaia-surface-sunken") do
              td(class: "p-4 text-gaia-primary-strong") { t(".sources.postgres") }
              td(class: "p-4 text-right text-gaia-text-subtle") { format_scc(@audit.db_total) }
            end
            tr(class: "hover:bg-gaia-surface-sunken") do
              td(class: "p-4 text-gaia-primary-strong") { t(".sources.polygon") }
              td(class: "p-4 text-right text-gaia-text-subtle") { format_scc(@audit.chain_total) }
            end
            tr(class: tokens("font-bold", "bg-status-danger/10": @audit.critical, "bg-gaia-surface-sunken": !@audit.critical)) do
              td(class: tokens("p-4", "text-status-danger-accent": @audit.critical, "text-gaia-text": !@audit.critical)) { t(".sources.delta") }
              td(class: tokens("p-4 text-right", "text-status-danger-accent": @audit.critical, "text-gaia-primary-strong": !@audit.critical)) { format_scc(@audit.delta) }
            end
          end
        end
      end
    end

    def timestamp_footer
      div(class: "text-mini text-gaia-text-muted text-right mt-2 font-mono") do
        t(".checked_at", at: @audit.checked_at.strftime("%Y-%m-%d %H:%M:%S UTC"))
      end
    end

    def status_badge
      if @audit.critical
        span(class: "px-2 py-0.5 bg-status-danger text-status-danger-text text-mini uppercase font-bold") { t(".badges.critical") }
      else
        span(class: "px-2 py-0.5 bg-status-active text-status-active-text text-mini uppercase font-bold") { t(".badges.ok") }
      end
    end

    def format_scc(value)
      "%.6f" % value
    end
  end
end
