# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module TreeFamilies
  class Index < ApplicationComponent
    # [UI.6] `current_user` потрібен ЛИШЕ для видимості мутаційних дій: сторінка
    # відкрита admin+ (`authorize_admin!`), а «Define DNA»/«Edit» ведуть в екшени під
    # `authorize_super_admin!, only:` — тобто гард сидить ГЛИБШЕ за саму сторінку, і
    # доти обидві кнопки бачив admin, дістаючи на клік сирий JSON-блоб 403.
    # Дефолт `nil` fail-CLOSED, як і в `Navigation::Sidebar` (04_04 §6.4).
    def initialize(families:, pagy:, current_user: nil)
      @families = families
      @pagy = pagy
      @current_user = current_user
    end

    def view_template
      div(class: "space-y-8") do
        render_header

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full shadow-2xl") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.species_name") }
                th(scope: "col", class: "p-4") { t(".columns.safe_range") }
                th(scope: "col", class: "p-4") { t(".columns.population") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.command") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              @families.each { |f| render_row(f) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { tree_families_path(page: page) }
        )
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-emerald-700") { t(".kicker") }
          h2(class: "text-2xl font-light text-emerald-400 mt-1") { t(".title") }
        end
        if @current_user&.super_admin?
          a(
            href: new_tree_family_path,
            class: "px-4 py-2 border border-emerald-500 text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all uppercase text-tiny tracking-widest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria_label: t(".define_aria")
          ) { t(".define_dna") }
        end
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
        td(class: "p-4 text-gray-500") { t(".range_value", min: family.critical_z_min, max: family.critical_z_max) }
        td(class: "p-4 text-emerald-900") { t(".soldiers_count", count: family.trees_count) }
        td(class: "p-4 text-right space-x-4") do
          a(href: tree_family_path(family), class: "text-emerald-700 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".audit_aria", name: family.name)) { t(".audit") }
          if @current_user&.super_admin?
            a(href: edit_tree_family_path(family), class: "text-zinc-700 hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".edit_aria", name: family.name)) { t(".edit") }
          end
        end
      end
    end
  end
end
