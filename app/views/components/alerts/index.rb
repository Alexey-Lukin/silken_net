# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Alerts
  class Index < ApplicationComponent
    # Filter chips (severity). Order is the visual order — keep critical
    # first so it gets keyboard focus on Tab traversal.
    FILTER_SEVERITIES = %w[critical medium low].freeze

    # [UI.6] `current_user` тут транзитний — сам список його не вживає, але веде далі
    # в `Alerts::Row`, де від нього залежить видимість «Acknowledge». Проводка мусить
    # пройти ОБИДВА щаблі: контролер → Index → Row.
    def initialize(alerts:, pagy:, organization: nil, current_user: nil)
      @alerts = alerts
      @pagy = pagy
      @organization = organization
      @current_user = current_user
    end

    def view_template
      # ⚡ Підписка на потік оновлень алертів організації.
      turbo_stream_from TurboStreams::Name.org(:alerts, @organization) if @organization

      div(class: "space-y-6") do
        header_section
        render_table
        render_pagination
      end
    end

    private


    def render_table
      # `gaia-responsive-table` flips into card-list on mobile via CSS only
      # (see application.css § "Responsive Table Pattern"). Markup stays a
      # real <table> so AT and Turbo Streams keep working unchanged.
      div(class: "border border-gaia-border bg-gaia-surface md:overflow-x-auto w-full") do
        table(class: "gaia-responsive-table w-full text-left font-mono text-compact md:min-w-[640px]", role: "table") do
          render_thead
          render_tbody
        end
      end
    end

    def render_thead
      thead(class: "gaia-sticky-thead bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
        tr do
          th(scope: "col", class: "p-4") { t("alerts.table.severity") }
          th(scope: "col", class: "p-4") { t("alerts.table.alert_type") }
          th(scope: "col", class: "p-4") { t("alerts.table.source") }
          th(scope: "col", class: "p-4") { t("alerts.table.message") }
          th(scope: "col", class: "p-4") { t("alerts.table.timestamp") }
          th(scope: "col", class: "p-4 text-right") { t("alerts.table.command") }
        end
      end
    end

    def render_tbody
      tbody(id: "alerts_list", class: "md:divide-y md:divide-gaia-border") do
        @alerts.each do |alert|
          render Alerts::Row.new(alert: alert, current_user: @current_user)
        end
      end
    end

    def render_pagination
      render Views::Shared::UI::Pagination.new(
        pagy: @pagy,
        url_helper: ->(page:) { alerts_path(page: page) },
        sticky_mobile: true
      )
    end

    def header_section
      div(class: "flex flex-col sm:flex-row sm:justify-between sm:items-end gap-3 mb-4") do
        div do
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
        div(class: "flex flex-wrap gap-2") do
          a(
            href: alerts_path,
            aria_label: t(".filter_aria_all"),
            class: filter_link_classes
          ) { t(".filter_all") }
          FILTER_SEVERITIES.each do |s|
            a(
              href: alerts_path(severity: s),
              aria_label: t(".filter_aria_severity", severity: s),
              class: filter_link_classes
            ) { t("alerts.index.filter_#{s}") }
          end
        end
      end
    end

    def filter_link_classes
      "px-2 py-0.5 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
        "hover:border-gaia-primary hover:text-gaia-primary-strong " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-all"
    end
  end
end
