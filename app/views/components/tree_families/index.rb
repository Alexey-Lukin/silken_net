# frozen_string_literal: true

module TreeFamilies
  class Index < ApplicationComponent
    def initialize(families:, pagy:)
      @families = families
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full shadow-2xl") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { "Species Name" }
                th(scope: "col", class: "p-4") { "Baseline Z" }
                th(scope: "col", class: "p-4") { "Safe Range" }
                th(scope: "col", class: "p-4") { "Population" }
                th(scope: "col", class: "p-4 text-right") { "Command" }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              @families.each { |f| render_row(f) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { api_v1_tree_families_path(page: page) }
        )
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-emerald-700") { "Biological Matrix" }
          h2(class: "text-2xl font-light text-emerald-400 mt-1") { "Global Species Constants" }
        end
        a(
          href: new_api_v1_tree_family_path,
          class: "px-4 py-2 border border-emerald-500 text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all uppercase text-tiny tracking-widest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500",
          aria_label: "Define new tree species"
        ) { "+ Define DNA" }
      end
    end

    def render_row(family)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4") do
          span(class: "text-emerald-100 font-bold") { family.name }
          if family.scientific_name.present?
            br
            span(class: "text-mini italic text-emerald-700") { family.scientific_name }
          end
        end
        td(class: "p-4 text-emerald-500") { "#{family.baseline_impedance} kΩ" }
        td(class: "p-4 text-gray-500") { "#{family.critical_z_min} - #{family.critical_z_max} kΩ" }
        td(class: "p-4 text-emerald-900") { "#{family.trees_count} Soldiers" }
        td(class: "p-4 text-right space-x-4") do
          a(href: api_v1_tree_family_path(family), class: "text-emerald-700 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: "Audit #{family.name} species") { "AUDIT" }
          a(href: edit_api_v1_tree_family_path(family), class: "text-zinc-700 hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: "Edit #{family.name} species") { "EDIT" }
        end
      end
    end
  end
end
