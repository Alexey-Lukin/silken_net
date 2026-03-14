# frozen_string_literal: true

module Maintenance
  class Index < ApplicationComponent
    def initialize(records:, pagy:)
      @records = records
      @pagy    = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        header_section
        filter_bar
        records_table
        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_maintenance_records_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-2") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Maintenance Records" }
          p(class: "text-xs text-gray-600 mt-1") do
            "#{@pagy.count} intervention#{@pagy.count == 1 ? '' : 's'} · Page #{@pagy.page} of #{@pagy.last}"
          end
        end
        a(
          href: helpers.new_api_v1_maintenance_record_path,
          aria_label: "Register new maintenance intervention",
          class: register_button_classes
        ) { "+ Register Intervention" }
      end
    end

    def filter_bar
      div(class: "flex flex-wrap gap-2 mb-4") do
        action_types = MaintenanceRecord.action_types.keys
        action_types.each do |type|
          a(
            href: helpers.api_v1_maintenance_records_path(action_type: type),
            aria_label: "Filter by #{type}",
            class: filter_link_classes
          ) { type }
        end
        a(
          href: helpers.api_v1_maintenance_records_path(verified: "1"),
          aria_label: "Show only verified records",
          class: filter_verified_classes
        ) { "✓ Verified Only" }
        a(
          href: helpers.api_v1_maintenance_records_path,
          aria_label: "Clear all filters",
          class: filter_clear_classes
        ) { "Clear" }
      end
    end

    def records_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact min-w-[900px]", role: "table") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { "Technician" }
              th(scope: "col", class: "p-4") { "Unit" }
              th(scope: "col", class: "p-4") { "Action" }
              th(scope: "col", class: "p-4 text-right") { "Cost" }
              th(scope: "col", class: "p-4 text-center") { "Photos" }
              th(scope: "col", class: "p-4 text-center") { "HW" }
              th(scope: "col", class: "p-4") { "Timestamp" }
              th(scope: "col", class: "p-4 text-right") { "" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @records.any?
              @records.each { |record| render_row(record) }
            else
              tr do
                td(colspan: 8, class: "p-10 text-center text-emerald-900 uppercase tracking-widest text-mini") do
                  "No interventions recorded"
                end
              end
            end
          end
        end
      end
    end

    def render_row(record)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4 text-emerald-100") { "#{record.user&.first_name} #{record.user&.last_name}" }
        td(class: "p-4 text-emerald-500 text-tiny") do
          "#{record.maintainable_type} // #{record.maintainable&.did || record.maintainable&.uid || '—'}"
        end
        td(class: "p-4") { action_badge(record.action_type) }
        td(class: "p-4 text-right text-gray-400") do
          cost = record.total_cost
          cost > 0 ? span(class: "text-emerald-300") { "$#{cost.round(2)}" } : span(class: "text-gray-700") { "—" }
        end
        td(class: "p-4 text-center") do
          count = record.photos_attachments.size
          if count > 0
            span(class: "text-mini text-emerald-600 font-mono") { "📷 #{count}" }
          else
            span(class: "text-gray-700") { "—" }
          end
        end
        td(class: "p-4 text-center") do
          if record.hardware_verified
            span(class: "text-emerald-500 text-compact", title: "Hardware Verified") { "✓" }
          else
            span(class: "text-status-warning text-compact", title: "Pending Verification") { "◌" }
          end
        end
        td(class: "p-4 text-gray-600 text-tiny") { record.performed_at&.strftime("%d.%m.%y // %H:%M") }
        td(class: "p-4 text-right") do
          a(
            href: helpers.api_v1_maintenance_record_path(record),
            aria_label: "Open maintenance record details",
            class: "text-emerald-700 hover:text-white text-tiny focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors"
          ) { "OPEN →" }
        end
      end
    end

    def action_badge(type)
      colors = {
        "repair"          => "text-status-warning-text",
        "installation"    => "text-blue-500",
        "inspection"      => "text-emerald-500",
        "cleaning"        => "text-cyan-600",
        "decommissioning" => "text-red-700"
      }
      span(class: tokens("uppercase", colors[type] || "text-gray-500")) { type }
    end

    def register_button_classes
      "px-4 py-2 border border-emerald-500 text-emerald-500 " \
        "hover:bg-emerald-500 hover:text-black " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 " \
        "transition-all uppercase text-tiny tracking-widest"
    end

    def filter_link_classes
      "px-3 py-1 border border-emerald-900 text-mini uppercase text-emerald-900 " \
        "hover:border-emerald-600 hover:text-emerald-600 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 " \
        "transition-all font-mono"
    end

    def filter_verified_classes
      "px-3 py-1 border border-emerald-700 text-mini uppercase text-emerald-700 " \
        "hover:bg-emerald-900/20 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 " \
        "transition-all font-mono"
    end

    def filter_clear_classes
      "px-3 py-1 border border-gray-800 text-mini uppercase text-gray-600 " \
        "hover:border-gray-600 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 " \
        "transition-all font-mono"
    end
  end
end
