# frozen_string_literal: true

module AuditLogs
  class Show < ApplicationComponent
    def initialize(log:)
      @log = log
    end

    def view_template
      div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_details_table
            render_metadata_panel
          end
          div(class: "space-y-8") do
            render_actor_info
            render_target_info
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "LOG" }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-2") { "Audit Event Record" }
            h2(class: "text-3xl font-extralight tracking-tighter text-white") { @log.action }
            p(class: "text-[10px] font-mono text-gray-600 mt-2") { "##{@log.id} // #{@log.created_at.strftime('%d.%m.%Y %H:%M:%S UTC')}" }
          end
          render Views::Shared::UI::ActionBadge.new(action: @log.action)
        end
      end
    end

    def render_details_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-[11px]") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { "Field" }
              th(scope: "col", class: "p-4") { "Value" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            detail_row("Action", @log.action)
            detail_row("Performed By", @log.user&.full_name || "System")
            detail_row("Target Type", @log.auditable_type || "—")
            detail_row("Target ID", @log.auditable_id || "—")
            detail_row("Timestamp", @log.created_at.strftime("%d.%m.%Y %H:%M:%S UTC"))
          end
        end
      end
    end

    def detail_row(label, value)
      tr(class: "hover:bg-emerald-950/10") do
        td(class: "p-4 text-emerald-500") { label }
        td(class: "p-4 text-gray-300") { value.to_s }
      end
    end

    def render_metadata_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Event Metadata" }
        if @log.metadata.present? && @log.metadata.any?
          div(class: "space-y-2 font-mono text-[10px]") do
            @log.metadata.each do |key, value|
              div(class: "flex justify-between items-center py-1 border-b border-emerald-900/20") do
                span(class: "text-gray-600 uppercase") { key.to_s }
                span(class: "text-emerald-400") { value.to_s }
              end
            end
          end
        else
          p(class: "text-[11px] text-gray-700 italic") { "No additional metadata." }
        end
      end
    end

    def render_actor_info
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Actor Identity" }
        if @log.user.present?
          div do
            p(class: "text-[9px] text-gray-600 uppercase mb-1") { "Name" }
            p(class: "text-[11px] text-emerald-400 font-mono") { @log.user.full_name }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-[9px] text-gray-600 uppercase mb-1") { "Email" }
            p(class: "text-[11px] text-gray-400") { @log.user.email_address }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-[9px] text-gray-600 uppercase mb-1") { "Role" }
            span(class: "px-2 py-0.5 bg-emerald-900 text-emerald-200 text-[9px] uppercase font-bold") { @log.user.role }
          end
        else
          p(class: "text-[11px] text-gray-700 italic") { "System actor." }
        end
      end
    end

    def render_target_info
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Auditable Target" }
        if @log.auditable_type.present?
          div(class: "space-y-3 font-mono text-[10px]") do
            div(class: "flex justify-between items-center") do
              span(class: "text-gray-600 uppercase") { "Type" }
              span(class: "text-emerald-400") { @log.auditable_type }
            end
            div(class: "flex justify-between items-center") do
              span(class: "text-gray-600 uppercase") { "ID" }
              span(class: "text-emerald-400") { @log.auditable_id.to_s }
            end
          end
        else
          p(class: "text-[11px] text-gray-700 italic") { "No specific target." }
        end
      end
    end
  end
end
