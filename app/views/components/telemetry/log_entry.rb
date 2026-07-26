# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Telemetry::LogEntry — single row appended to the live HUD via Turbo Stream.
# Carries `data-label` attributes so the parent `gaia-responsive-table`
# flips into a card on mobile (CSS in application.css).
module Telemetry
  class LogEntry < ApplicationComponent
    def initialize(gateway:, hex_payload:, timestamp:)
      @gateway = gateway
      @hex_payload = hex_payload
      @timestamp = timestamp
    end

    def view_template
      tr(class: "hover:bg-gaia-surface-sunken md:border-b md:border-gaia-border animate-in slide-in-from-left duration-300 group") do
        td(
          class: "p-3 text-gaia-text-muted font-mono text-mini",
          data_label: t("telemetry.table.timestamp")
        ) { @timestamp.strftime("%H:%M:%S.%L") }

        td(class: "p-3", data_label: t("telemetry.table.gateway")) do
          span(class: "text-gaia-primary font-bold") { @gateway&.uid || t(".unknown_relay") }
          span(class: "ml-2 text-micro text-gaia-text-subtle") do
            t(".ip_label", ip: @gateway&.ip_address || t(".unknown_ip"))
          end
        end

        td(
          class: "p-3 font-mono text-gaia-text-strong/80 break-all leading-tight text-mini tracking-tighter",
          data_label: t("telemetry.table.payload")
        ) { @hex_payload }

        td(class: "p-3 text-right text-micro uppercase tracking-widest", data_label: t("telemetry.table.status")) do
          span(class: "px-2 py-0.5 border border-gaia-border text-gaia-text-muted group-hover:text-gaia-text group-hover:border-gaia-primary transition-colors") do
            t(".batch_received")
          end
        end
      end
    end

    private
  end
end
