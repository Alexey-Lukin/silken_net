# frozen_string_literal: true

module AuditLogs
  class Index < ApplicationComponent
    def initialize(logs:, pagy:)
      @logs = logs
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-6 animate-in fade-in duration-500") do
        header_section
        audit_table
        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_audit_logs_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "👁️ The Watcher — Audit Log" }
          p(class: "text-xs text-gray-600 mt-1") { "Журнал дій адміністраторів: хто, коли та що змінив." }
        end
        div(class: "text-right font-mono text-[10px] text-emerald-900") do
          plain "Records: "
          span(class: "text-emerald-500") { @pagy.count.to_s }
        end
      end
    end

    def audit_table
      div(class: "border border-emerald-900 bg-black overflow-hidden") do
        table(class: "w-full text-left font-mono text-[11px]") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
            tr do
              th(class: "p-4") { "Timestamp" }
              th(class: "p-4") { "User" }
              th(class: "p-4") { "Action" }
              th(class: "p-4") { "Target" }
              th(class: "p-4 text-right") { "Details" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @logs.any?
              @logs.each { |log| render_log_row(log) }
            else
              render Views::Shared::UI::EmptyState.new(
                title: "No audit events recorded.",
                icon: "👁️",
                colspan: 5
              )
            end
          end
        end
      end
    end

    def render_log_row(log)
      tr(class: "hover:bg-emerald-950/10 transition-colors") do
        td(class: "p-4 text-[10px] text-gray-600") { log.created_at.strftime("%H:%M:%S // %d.%m.%y") }
        td(class: "p-4 text-emerald-400") { log.user&.full_name || "System" }
        td(class: "p-4") do
          render Views::Shared::UI::ActionBadge.new(action: log.action)
        end
        td(class: "p-4 text-gray-400") do
          if log.auditable_type.present?
            plain "#{log.auditable_type} ##{log.auditable_id}"
          else
            span(class: "text-gray-700 italic") { "—" }
          end
        end
        td(class: "p-4 text-right") do
          a(href: helpers.api_v1_audit_log_path(log), class: "text-emerald-600 hover:text-white transition-all text-[9px] uppercase tracking-widest") { "Inspect →" }
        end
      end
    end
  end
end
