# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Firmwares
  class Index < ApplicationComponent
    def initialize(firmwares:, inventory_stats:, pagy:, active_ota_gateways: [])
      @firmwares = firmwares
      @inventory_stats = inventory_stats
      @pagy = pagy
      @active_ota_gateways = active_ota_gateways
    end

    def view_template
      div(class: "space-y-10") do
        render_active_evolutions
        render_inventory_summary
        render_firmware_registry
      end
    end

    private

    # [SEC.20] Живі OTA-кампанії: підписка + initial-render прогрес-барів;
    # broadcast'ить Downlink::PendingQueueService (FW.60 poll-тракт).
    def render_active_evolutions
      return if @active_ota_gateways.empty?

      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-6") { t(".active_evolutions") }
        div(class: "space-y-4") do
          @active_ota_gateways.each do |gateway|
            turbo_stream_from TurboStreams::Name.gateway_ota(gateway)
            render Firmwares::OtaProgressBar.new(
              uid: gateway.uid,
              percent: 0, current: 0, total: 0,
              status: gateway.updating? ? "TRANSMITTING" : "PENDING"
            )
          end
        end
      end
    end

    # [ARCH.83] Каталог образів глобальний, а ЦЯ панель — org-скоуплена, тож на
    # платформеному контексті вона не «порожня», а НЕВИМІРЯНА. `nil` ⊥ `{}` тут
    # несуче: порожній хеш надрукував би тиху нульову статистику по кожній версії,
    # тобто рівно той клас, що [ARCH.84]. Кнопки перемикання панель не рендерить
    # свідомо — перемикач уже стоїть у шапці (`navigation.top_bar.context_none`),
    # а гейтована дія в компоненті потребувала б актора (UI.5/UI.6).
    def render_inventory_summary
      div(class: "p-6 border border-gaia-border bg-gaia-surface shadow-2xl") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-6") { t(".inventory_title") }

        if @inventory_stats.nil?
          p(class: "text-compact font-mono text-gaia-text-muted") { t(".inventory_no_context") }
        else
          div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
            inventory_block(t(".queens"), @inventory_stats[:gateways])
            inventory_block(t(".soldiers"), @inventory_stats[:trees])
          end
        end
      end
    end

    def inventory_block(title, stats)
      div do
        p(class: "text-xs font-mono text-gaia-text-muted mb-3") { title }
        div(class: "space-y-2") do
          stats.each do |version, count|
            div(class: "flex justify-between items-center text-compact font-mono") do
              span(class: "text-gaia-text-strong") { t(".version_label", version: version || "0.0.0") }
              div(class: "flex-1 mx-4 h-px bg-gaia-border border-dotted")
              span(class: "text-gaia-text-strong") { t(".units", count: count) }
            end
          end
        end
      end
    end

    def render_firmware_registry
      div(class: "space-y-4") do
        div(class: "flex justify-between items-end") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".registry_title") }

          # Кнопка переходу до порталу завантаження
          a(
            href: new_firmware_path,
            class: "text-tiny border border-gaia-primary-strong px-4 py-1 text-gaia-primary-strong hover:bg-gaia-primary hover:text-gaia-primary-text transition-all uppercase tracking-widest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria_label: t(".upload_aria")
          ) { t(".upload") }
        end

        div(class: "overflow-x-auto w-full border border-gaia-border bg-gaia-surface") do
          table(role: "table", class: "w-full text-left font-mono text-xs") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.version") }
                th(scope: "col", class: "p-4") { t(".columns.target_hardware") }
                th(scope: "col", class: "p-4") { t(".columns.checksum") }
                th(scope: "col", class: "p-4") { t(".columns.uploaded") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.command") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              @firmwares.each { |f| render_firmware_row(f) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { firmwares_path(page: page) }
        )
      end
    end

    def render_firmware_row(firmware)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors group") do
        td(class: "p-4 text-gaia-text-strong font-bold font-mono") { t("firmwares.row.version", version: firmware.version) }
        td(class: "p-4 text-gaia-primary-strong uppercase font-mono text-tiny") { firmware.target_hardware_type }
        td(class: "p-4 text-gaia-text-muted font-mono text-tiny") { firmware.binary_sha256&.first(16) || t("firmwares.row.not_available") }
        td(class: "p-4 text-gaia-text-muted font-mono text-tiny") { firmware.created_at.strftime("%d.%m.%y // %H:%M") }

        td(class: "p-4 text-right") do
          # [UI.7] `button_to`, не рукописна `<form>` — див. ноту у `firmwares/row.rb`.
          # ⚠️ `aria:`, не `aria_label:`: `button_to` розкладає вкладений хеш у
          # `aria-label` сам, а плаский kwarg поїхав би в розмітку як є.
          button_to(
            t("firmwares.row.order_evolution"),
            deploy_firmware_path(firmware),
            method: :post,
            class: "text-gaia-primary-strong hover:text-gaia-text-strong border border-gaia-border hover:border-gaia-primary-strong px-4 py-1 uppercase text-mini tracking-widest transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria: { label: t(".deploy_aria", version: firmware.version) },
            data: { turbo_confirm: t("firmwares.row.confirm", version: firmware.version) }
          )
        end
      end
    end
  end
end
