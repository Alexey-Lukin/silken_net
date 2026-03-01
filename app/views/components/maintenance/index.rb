module Views
  module Components
    module Maintenance
      class Index < ApplicationComponent
        def initialize(records:)
          @records = records
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            header_section
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Technician" }
                    th(class: "p-4") { "Unit (Soldier/Queen)" }
                    th(class: "p-4") { "Action Type" }
                    th(class: "p-4") { "Timestamp" }
                    th(class: "p-4 text-right") { "Command" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @records.each { |record| render_row(record) }
                end
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-end mb-6") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "Maintenance Records" }
              p(class: "text-xs text-gray-600 mt-1") { "Chronicles of physical intervention and ecosystem healing." }
            end
            a(
              href: helpers.new_api_v1_maintenance_record_path,
              class: "px-4 py-2 border border-emerald-500 text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all uppercase text-[10px] tracking-widest"
            ) { "+ Register Intervention" }
          end
        end

        def render_row(record)
          tr(class: "hover:bg-emerald-950/10 transition-colors group") do
            td(class: "p-4") { "#{record.user.first_name} #{record.user.last_name}" }
            td(class: "p-4 text-emerald-500") { "#{record.maintainable_type} // #{record.maintainable&.did || record.maintainable&.uid}" }
            td(class: "p-4 uppercase text-emerald-100") { record.action_type }
            td(class: "p-4 text-gray-600") { record.performed_at&.strftime("%d.%m.%y // %H:%M") }
            td(class: "p-4 text-right") do
              a(href: helpers.api_v1_maintenance_record_path(record), class: "text-emerald-700 hover:text-white") { "OPEN_LOG →" }
            end
          end
        end
      end
    end
  end
end
