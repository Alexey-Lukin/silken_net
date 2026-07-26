# SPDX-License-Identifier: AGPL-3.0-or-later
module SystemAudits
  class Index < ApplicationComponent
    def initialize(audit:)
      @audit = audit
    end

    def view_template
      div(class: "space-y-6 animate-in fade-in duration-500") do
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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".title") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
        div(class: "flex gap-2") do
          status_badge
        end
      end
    end

    def status_banner
      if @audit.critical
        div(class: "border border-red-700 bg-red-950/30 p-4", role: "alert") do
          p(class: "text-red-400 text-xs font-mono font-bold uppercase tracking-widest") do
            t(".critical", delta: format_scc(@audit.delta))
          end
        end
      else
        div(class: "border border-emerald-900 bg-emerald-950/20 p-4", role: "status") do
          p(class: "text-emerald-500 text-xs font-mono uppercase tracking-widest") do
            t(".ok", delta: format_scc(@audit.delta))
          end
        end
      end
    end

    def comparison_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact", role: "table") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".columns.source") }
              th(scope: "col", class: "p-4 text-right") { t(".columns.total") }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            tr(class: "hover:bg-emerald-950/10") do
              td(class: "p-4 text-emerald-500") { t(".sources.postgres") }
              td(class: "p-4 text-right text-gray-300") { format_scc(@audit.db_total) }
            end
            tr(class: "hover:bg-emerald-950/10") do
              td(class: "p-4 text-emerald-500") { t(".sources.polygon") }
              td(class: "p-4 text-right text-gray-300") { format_scc(@audit.chain_total) }
            end
            tr(class: tokens("font-bold", "bg-red-950/20": @audit.critical, "bg-emerald-950/10": !@audit.critical)) do
              td(class: tokens("p-4", "text-red-400": @audit.critical, "text-emerald-400": !@audit.critical)) { t(".sources.delta") }
              td(class: tokens("p-4 text-right", "text-red-300": @audit.critical, "text-emerald-300": !@audit.critical)) { format_scc(@audit.delta) }
            end
          end
        end
      end
    end

    def timestamp_footer
      div(class: "text-mini text-gray-600 text-right mt-2 font-mono") do
        t(".checked_at", at: @audit.checked_at.strftime("%Y-%m-%d %H:%M:%S UTC"))
      end
    end

    def status_badge
      if @audit.critical
        span(class: "px-2 py-0.5 bg-red-900 text-red-200 text-mini uppercase font-bold") { t(".badges.critical") }
      else
        span(class: "px-2 py-0.5 bg-emerald-900 text-emerald-200 text-mini uppercase font-bold") { t(".badges.ok") }
      end
    end

    def format_scc(value)
      "%.6f" % value
    end
  end
end
