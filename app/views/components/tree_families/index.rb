module Views
  module Components
    module TreeFamilies
      class Index < ApplicationComponent
        def initialize(families:)
          @families = families
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            render_header
            
            div(class: "border border-emerald-900 bg-black overflow-hidden shadow-2xl") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Species Name" }
                    th(class: "p-4") { "Baseline Z" }
                    th(class: "p-4") { "Safe Range" }
                    th(class: "p-4") { "Population" }
                    th(class: "p-4 text-right") { "Command" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @families.each { |f| render_row(f) }
                end
              end
            end
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-end") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Biological Matrix" }
              h2(class: "text-2xl font-light text-emerald-400 mt-1") { "Global Species Constants" }
            end
            a(
              href: helpers.new_api_v1_tree_family_path,
              class: "px-4 py-2 border border-emerald-500 text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all uppercase text-[10px] tracking-widest"
            ) { "+ Define DNA" }
          end
        end

        def render_row(family)
          tr(class: "hover:bg-emerald-950/10 transition-colors group") do
            td(class: "p-4 text-emerald-100 font-bold") { family.name }
            td(class: "p-4 text-emerald-500") { "#{family.baseline_impedance} kΩ" }
            td(class: "p-4 text-gray-500") { "#{family.critical_z_min} - #{family.critical_z_max} kΩ" }
            td(class: "p-4 text-emerald-900") { "#{family.trees.count} Soldiers" }
            td(class: "p-4 text-right space-x-4") do
              a(href: helpers.api_v1_tree_family_path(family), class: "text-emerald-700 hover:text-white") { "AUDIT" }
              a(href: helpers.edit_api_v1_tree_family_path(family), class: "text-zinc-700 hover:text-emerald-500") { "EDIT" }
            end
          end
        end
      end
    end
  end
end
