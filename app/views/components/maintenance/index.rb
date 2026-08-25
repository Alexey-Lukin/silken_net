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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".heading") }
          p(class: "text-xs text-gaia-text-muted mt-1") do
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
        # [E.20] Черга «чекає на засвідчення» — єдина поверхня, з якої лісник бачить
        # заявки, що ЩЕ можна врятувати підписом. Доти такої вибірки не існувало
        # взагалі, і застрягла заявка була видима лише ops-у як число в DeadSet.
        a(
          href: maintenance_records_path(pending_attestation: "1"),
          aria_label: t(".filter.pending_attestation_aria"),
          class: filter_pending_classes
        ) { t(".filter.pending_attestation") }
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
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact min-w-[900px]", role: "table") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
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
          tbody(class: "divide-y divide-gaia-border") do
            if @records.any?
              @records.each { |record| render_row(record) }
            else
              tr do
                td(colspan: 8, class: "p-10 text-center text-gaia-text-muted uppercase tracking-widest text-mini") do
                  t(".table.empty")
                end
              end
            end
          end
        end
      end
    end

    def render_row(record)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors group") do
        td(class: "p-4 text-gaia-text-strong") { "#{record.user&.first_name} #{record.user&.last_name}" }
        td(class: "p-4 text-gaia-primary-strong text-tiny") do
          "#{record.maintainable_type} // #{record.maintainable&.display_identifier || '—'}"
        end
        td(class: "p-4") do
          action_badge(record.action_type)
          claim_marker(record)
        end
        td(class: "p-4 text-right text-gaia-text-muted") do
          # 🔴 [ARCH.103] Тут була ТРЕТЯ поведінка того самого числа: `cost > 0`
          # зливало «безкоштовний візит» (явний нуль — законний вимір) із «не
          # введено» в один прочерк, тоді як сторінка запису друкувала на тому
          # самому місці впевнений `$0.00`. Одна величина, три різні відповіді на
          # трьох поверхнях — і жодна не називала, яку з двох порожнеч показує.
          # ⚠️ `total_cost` тепер уміє бути `nil`, тож старий `cost > 0` кинув би
          # `NoMethodError`: перевірка мусить питати про ВИМІР, не про знак.
          cost = record.total_cost
          if cost.nil?
            span(class: "text-gaia-text-subtle") { t("ui.measurement.not_measured") }
          else
            span(class: "text-gaia-text-strong") { "$#{formatted_amount(cost)}" }
          end
        end
        td(class: "p-4 text-center") do
          count = record.photos_attachments.size
          if count > 0
            span(class: "text-mini text-gaia-primary-strong font-mono") { "📷 #{count}" }
          else
            span(class: "text-gaia-text-subtle") { "—" }
          end
        end
        td(class: "p-4 text-center") do
          if record.hardware_verified
            span(class: "text-gaia-primary-strong text-compact", title: t(".hw_verified_title")) { "✓" }
          else
            span(class: "text-status-warning-accent text-compact", title: t(".hw_pending_title")) { "◌" }
          end
        end
        td(class: "p-4 text-gaia-text-muted text-tiny") { record.performed_at&.strftime("%d.%m.%y // %H:%M") }
        td(class: "p-4 text-right") do
          a(
            href: maintenance_record_path(record),
            aria_label: t(".table.open_aria"),
            class: "text-gaia-primary-strong hover:text-gaia-text-strong text-tiny focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors"
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
    # [UI.1] Кольори — `-accent`-родина + `-strong`: `-text`-токени поза пастеллю =
    # токен поза роллю (§3.2). Колір тут кодує ВАГУ дії, не ідентичність (її несе
    # мітка): biomass (слешинг) > repair (несправність) > installation (нова
    # установка) > inspection/cleaning (планова рутина — свідомо ОДИН тон) >
    # decommissioning (адмін-виведення заліза — сірий, щоб не кричав гучніше за
    # biomass, як робив старий red-700). Не «уніфікуй» рутинну пару вроздріб.
    def action_badge(type)
      colors = {
        "repair"             => "text-status-warning-accent",
        "installation"       => "text-status-info-accent",
        "inspection"         => "text-gaia-primary-strong",
        "cleaning"           => "text-gaia-primary-strong",
        "decommissioning"    => "text-status-neutral-accent",
        "biomass_extraction" => "text-status-danger-accent"
      }
      span(class: tokens("uppercase", colors[type.to_s] || "text-gaia-text-subtle")) do
        MaintenanceRecord.action_type_label(type)
      end
    end

    # [E.20] Маркер стану заявки на CORC у самому рядку — БЕЗ жодного запиту
    # (`biomass_claim_state` читає лише колонки вже завантаженого рядка).
    # 🔴 Він стоїть тут, а не за фільтром, свідомо: фільтр знаходить того, хто вже
    # ШУКАЄ, а подавач заявки не шукає — він вважає, що подав. Мовчить лише
    # `confirmed`: доти заявки в реєстрі НЕМА, хай яка причина.
    def claim_marker(record)
      state = record.biomass_claim_state
      return if state.nil? || state == :confirmed

      div(class: tokens("text-micro mt-1", claim_marker_color(state))) do
        record.biomass_claim_state_label
      end
    end

    # Колір — з ТОГО САМОГО `state`, що й текст (frontend #25).
    def claim_marker_color(state)
      case state
      when :sent then "text-status-info-accent"
      when :awaiting_attestation, :manual_review then "text-status-warning-accent"
      else "text-status-danger-accent"
      end
    end

    def filter_pending_classes
      "px-3 py-1 border border-status-warning-accent text-mini uppercase text-status-warning-accent " \
        "hover:bg-status-warning/10 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
        "transition-all font-mono"
    end

    def register_button_classes
      "px-4 py-2 border border-gaia-primary-strong text-gaia-primary-strong " \
        "hover:bg-gaia-primary hover:text-gaia-primary-text " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
        "transition-all uppercase text-tiny tracking-widest"
    end

    def filter_link_classes
      "px-3 py-1 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
        "hover:border-gaia-primary-strong hover:text-gaia-primary-strong " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
        "transition-all font-mono"
    end

    def filter_verified_classes
      "px-3 py-1 border border-gaia-border-strong text-mini uppercase text-gaia-primary-strong " \
        "hover:bg-gaia-primary/10 " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
        "transition-all font-mono"
    end

    def filter_clear_classes
      "px-3 py-1 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
        "hover:border-gaia-border-strong " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong " \
        "transition-all font-mono"
    end
  end
end
