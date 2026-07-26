# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# app/views/components/alerts/row.rb
module Alerts
  class Row < ApplicationComponent
    # `citations:` is an optional, pre-fetched Array<Codex::Citation> for THIS
    # alert. When the parent `Alerts::Index` renders many rows it computes
    # `Codex::Citation.bulk_for(@alerts)` ONCE and threads each row's slice
    # in here, eliminating the N+1 that Prosopite caught. When `citations`
    # is nil (single-row Turbo Stream replace, e.g. resolve action) we fall
    # back to a per-row query — that's at most one extra round-trip.
    def initialize(alert:, citations: nil)
      @alert = alert
      @citations = citations
    end

    def view_template
      tr(id: dom_id(@alert), class: row_classes) do
        # `data-label` powers the CSS-only mobile card flip in
        # application.css § "Responsive Table Pattern". Each label mirrors
        # the column header in `Alerts::Index` so the visible text matches
        # what a desktop user would see in the <th>.
        td(class: "p-4", data_label: t("alerts.table.severity")) { severity_badge }
        # Мітка типу — через TextFormatter, а не власний лукап: одна деривація
        # ключа на застосунок (див. `ALERT_TYPE_SCOPE`), тож спека покриває оби́два
        # шляхи рендеру. Раніше тут жив locale-сліпий `.humanize`.
        td(class: "p-4 text-mini uppercase text-gaia-text-subtle tracking-widest", data_label: t("alerts.table.alert_type")) do
          TreeChronicle::TextFormatter.alert_title(@alert)
        end
        td(class: "p-4 text-gaia-primary", data_label: t("alerts.table.source")) do
          "#{@alert.cluster&.name} // #{@alert.tree&.did || 'System'}"
        end
        td(class: "p-4 text-gaia-text-subtle", data_label: t("alerts.table.message")) do
          div { @alert.message }
          render_codex_citations
        end
        td(class: "p-4 text-tiny text-gaia-text-muted", data_label: t("alerts.table.timestamp")) do
          @alert.created_at.strftime("%H:%M:%S")
        end
        # Action cell intentionally has no data-label — the CSS rule turns
        # it into a centred footer block on mobile (no column heading dupe).
        td(class: "p-4 text-right") { action_button }
      end
    end

    private


    # Phase 6 — Codex citation strip beneath the alert message. A
    # forester citing `chainsaw_protocol` on a `chainsaw_detected`
    # alert turns the row into auditable, lore-linked forensic data.
    # Wrapped in a `gaia-*` island so the surrounding emerald palette
    # of the alerts table doesn't bleed through.
    def render_codex_citations
      return unless defined?(::Codex::Citation)
      citations = @citations || ::Codex::Citation.for_target(@alert).includes(node: :realm).limit(10)
      return if citations.empty?

      div(class: "mt-2") do
        render ::Codex::Citations::Strip.new(target: @alert, citations: citations)
      end
    end

    def severity_badge
      color = case @alert.severity.to_s
      when "critical" then "bg-status-danger text-status-danger-text animate-pulse"
      when "medium" then "bg-status-warning text-status-warning-text"
      when "low" then "bg-status-info text-status-info-text"
      else "bg-status-neutral text-status-neutral-text"
      end
      # Та сама деривація, що в `Alerts::Badge` — через `SEVERITY_SCOPE`.
      # Раніше сюди летіло сире значення enum'а, ще й двічі: у видимий текст і
      # в перекладений aria-шаблон, тобто скрін-рідер читав англійське слово
      # всередині української фрази.
      label = TreeChronicle::TextFormatter.alert_severity_label(@alert)
      span(
        role: "status",
        aria_label: t(".severity_aria", severity: label),
        class: tokens("px-2 py-0.5 rounded-sm text-mini uppercase font-bold", color)
      ) { label }
    end

    def action_button
      if @alert.status_resolved?
        span(class: "text-gaia-text-muted text-mini uppercase tracking-widest", role: "status") do
          t(".resolved")
        end
      else
        # Acknowledge form posts via Turbo Stream — single-row replace.
        button_to(
          t(".acknowledge"),
          resolve_api_v1_alert_path(@alert),
          method: :patch,
          aria: { label: t(".resolve_aria", id: @alert.id) },
          class: resolve_button_classes,
          data: { turbo_confirm: t(".resolve_confirm", id: @alert.id) }
        )
      end
    end

    def row_classes
      tokens(
        "transition-all duration-700",
        "bg-gaia-surface-sunken opacity-40": @alert.status_resolved?,
        "hover:bg-gaia-surface-sunken": !@alert.status_resolved?
      )
    end

    def resolve_button_classes
      "text-mini uppercase tracking-tighter border border-status-danger text-status-danger-text " \
        "hover:bg-status-danger hover:text-gaia-text-strong " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger " \
        "px-3 py-1 transition-all"
    end
  end
end
