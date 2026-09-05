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

        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full shadow-2xl") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.species_name") }
                # ⛔ [E.64 ⚖️ 2026-09-05] Заголовок був «Безпечний діапазон», і це
                # твердження, а не назва: після зняття Z-похідних вердиктів родинна
                # смуга `critical_z_min..max` НЕ судить нічого — ні алерту, ні DCI
                # (той бере `Tree#device_lorenz_thresholds`), ні мінту. Напис
                # стверджував, що поза нею НЕБЕЗПЕЧНО, тобто ніс знятий вердикт у
                # єдиному місці, де його ще читала людина. Ім'я тепер ОПИСОВЕ.
                th(scope: "col", class: "p-4") { t(".columns.family_z_band") }
                th(scope: "col", class: "p-4") { t(".columns.population") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.command") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
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
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted") { t(".kicker") }
          h2(class: "text-2xl font-light text-gaia-text-strong mt-1") { t(".title") }
        end
        if @current_user&.super_admin?
          a(
            href: new_tree_family_path,
            class: "px-4 py-2 bg-gaia-primary/10 border border-gaia-primary-strong text-gaia-primary-strong hover:bg-gaia-primary hover:text-gaia-primary-text transition-all uppercase text-tiny tracking-widest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria_label: t(".define_aria")
          ) { t(".define_dna") }
        end
      end
    end

    def render_row(family)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors group") do
        td(class: "p-4") do
          span(class: "text-gaia-text-strong font-bold") { family.name }
          if family.scientific_name.present?
            br
            span(class: "text-mini italic text-gaia-text-muted") { family.scientific_name }
          end
        end
        td(class: "p-4 text-gaia-text-muted") { t(".range_value", min: family.critical_z_min, max: family.critical_z_max) }
        td(class: "p-4 text-gaia-text-subtle") { t(".soldiers_count", count: family.trees_count) }
        td(class: "p-4 text-right space-x-4") do
          a(href: tree_family_path(family), class: "text-gaia-text-muted hover:text-gaia-text-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".audit_aria", name: family.name)) { t(".audit") }
          if @current_user&.super_admin?
            a(href: edit_tree_family_path(family), class: "text-gaia-text-muted hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".edit_aria", name: family.name)) { t(".edit") }
          end
        end
      end
    end
  end
end
