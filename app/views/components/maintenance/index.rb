# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Maintenance
  class Index < ApplicationComponent
    def initialize(records:, pagy:)
      @records = records
      @pagy    = pagy
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        filter_bar
        records_table
        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { maintenance_records_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-2") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".heading") }
          p(class: "text-xs text-gray-600 mt-1") do
            t(".page_info", count: @pagy.count, page: @pagy.page, total: @pagy.last)
          end
        end
        a(
          href: new_maintenance_record_path,
          aria_label: t(".register_aria"),
          class: register_button_classes
        ) { t(".register") }
      end
    end

    def filter_bar
      div(class: "flex flex-wrap gap-2 mb-4") do
        action_types = MaintenanceRecord.action_types.keys
        action_types.each do |type|
          a(
            href: maintenance_records_path(action_type: type),
            # 🔴 [I18N.1] Три роди вжитку в ОДНОМУ циклі, і плутати їх коштує по-різному:
            # `type` у `href` лишається СИРИМ enum'ом (це значення параметра — мітка
            # зламала б фільтр), а в `aria_label` і в тексті кнопки їде МІТКА, бо це показ.
            aria_label: t(".filter.by_aria", type: MaintenanceRecord.action_type_label(type)),
            class: filter_link_classes
          ) { MaintenanceRecord.action_type_label(type) }
        end
        a(
          href: maintenance_records_path(verified: "1"),
          aria_label: t(".filter.verified_aria"),
          class: filter_verified_classes
        ) { t(".filter.verified") }
        a(
          href: maintenance_records_path,
          aria_label: t(".filter.clear_aria"),
          class: filter_clear_classes
        ) { t(".filter.clear") }
      end
    end

    def records_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact min-w-[900px]", role: "table") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".table.technician") }
              th(scope: "col", class: "p-4") { t(".table.unit") }
              th(scope: "col", class: "p-4") { t(".table.action") }
              th(scope: "col", class: "p-4 text-right") { t(".table.cost") }
              th(scope: "col", class: "p-4 text-center") { t(".table.photos") }
              th(scope: "col", class: "p-4 text-center") { t(".table.hw") }
              th(scope: "col", class: "p-4") { t(".table.timestamp") }
              th(scope: "col", class: "p-4 text-right") { "" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @records.any?
              @records.each { |record| render_row(record) }
            else
              tr do
                td(colspan: 8, class: "p-10 text-center text-emerald-900 uppercase tracking-widest text-mini") do
                  t(".table.empty")
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
          "#{record.maintainable_type} // #{record.maintainable&.display_identifier || '—'}"
        end
        td(class: "p-4") { action_badge(record.action_type) }
        td(class: "p-4 text-right text-gray-400") do
          # 🔴 [ARCH.103] Тут була ТРЕТЯ поведінка того самого числа: `cost > 0`
          # зливало «безкоштовний візит» (явний нуль — законний вимір) із «не
          # введено» в один прочерк, тоді як сторінка запису друкувала на тому
          # самому місці впевнений `$0.00`. Одна величина, три різні відповіді на
          # трьох поверхнях — і жодна не називала, яку з двох порожнеч показує.
          # ⚠️ `total_cost` тепер уміє бути `nil`, тож старий `cost > 0` кинув би
          # `NoMethodError`: перевірка мусить питати про ВИМІР, не про знак.
          cost = record.total_cost
          if cost.nil?
            span(class: "text-gray-700") { t("ui.measurement.not_measured") }
          else
            span(class: "text-emerald-300") { "$#{cost.round(2)}" }
          end
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
            span(class: "text-emerald-500 text-compact", title: t(".hw_verified_title")) { "✓" }
          else
            span(class: "text-status-warning text-compact", title: t(".hw_pending_title")) { "◌" }
          end
        end
        td(class: "p-4 text-gray-600 text-tiny") { record.performed_at&.strftime("%d.%m.%y // %H:%M") }
        td(class: "p-4 text-right") do
          a(
            href: maintenance_record_path(record),
            aria_label: t(".table.open_aria"),
            class: "text-emerald-700 hover:text-white text-tiny focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors"
          ) { t(".table.open") }
        end
      end
    end

    # [I18N.1] Приймає СИРИЙ токен — саме ним ключується мапа — а мітку деривує з
    # дому (`MaintenanceRecord.action_type_label`). Доти тут друкувався сам токен,
    # тобто рядок реєстру лишався англійським у всіх локалях; дзеркальний дефект
    # у `Maintenance::Show` був протилежний (мітка подавалась У мапу й гасила колір).
    # `biomass_extraction` має ВЛАСНИЙ колір, не спільний із `decommissioning`:
    # то дія над залізом, а це над деревом (тягне declare_deceased! → слешинг).
    def action_badge(type)
      colors = {
        "repair"             => "text-status-warning-text",
        "installation"       => "text-blue-500",
        "inspection"         => "text-emerald-500",
        "cleaning"           => "text-cyan-600",
        "decommissioning"    => "text-red-700",
        "biomass_extraction" => "text-status-danger-accent"
      }
      span(class: tokens("uppercase", colors[type.to_s] || "text-gray-500")) do
        MaintenanceRecord.action_type_label(type)
      end
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
