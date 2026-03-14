# frozen_string_literal: true

module Clusters
  class Show < ApplicationComponent
    # All data must be pre-loaded in the controller — no fallback queries.
    # @param cluster [Cluster] must respond to :name, :region, :health_index
    # @param gateways [Array<Gateway>] pre-loaded gateways for this cluster
    # @param recent_alerts [Array<EwsAlert>] pre-loaded unresolved alerts
    def initialize(cluster:, gateways:, recent_alerts:)
      raise ArgumentError, "cluster must respond to :name" unless cluster.respond_to?(:name)

      @cluster = cluster
      @gateways = gateways
      @active_contract = @cluster.active_contract
      @recent_alerts = recent_alerts
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: Підписка на потік оновлень алертів кластера
      turbo_stream_from @cluster, :alerts

      div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_vitals_panel
            render_gateways_table
            render_alerts_panel
          end
          div(class: "space-y-8") do
            render_contract_panel
            render_geography_panel
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none") { "SECTOR" }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { "Cluster Matrix" }
            h2(class: "text-3xl font-extralight tracking-tighter text-white") { @cluster.name }
            p(class: "text-tiny font-mono text-gray-600 mt-2") { "#{@cluster.region} // ID: #{@cluster.id}" }
          end
          div(class: "flex items-center gap-4") do
            div(class: tokens(
              "h-3 w-3 rounded-full",
              "bg-red-500 animate-pulse": @cluster.active_threats?,
              "bg-emerald-500": !@cluster.active_threats?
            ))
            span(class: "text-tiny font-mono text-emerald-800 uppercase") do
              @cluster.active_threats? ? "Threat Detected" : "Nominal"
            end
          end
        end
      end
    end

    def render_vitals_panel
      div(class: "p-8 border border-emerald-900 bg-zinc-950") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-8") { "Sector Vitals" }
        div(class: "grid grid-cols-3 gap-8") do
          vital_block("Health Index", "#{(@cluster.health_index * 100).round}%")
          vital_block("Active Trees", @cluster.total_active_trees.to_s)
          vital_block("Queen Gateways", @gateways.size.to_s)
        end
        if @cluster.environmental_settings.present?
          div(class: "mt-8 pt-6 border-t border-emerald-900/30") do
            h4(class: "text-mini uppercase tracking-widest text-emerald-800 mb-4") { "Environmental Config" }
            div(class: "grid grid-cols-3 gap-6 text-tiny font-mono") do
              if @cluster.environmental_settings["custom_fire_threshold"]
                env_block("Fire Threshold", "#{@cluster.environmental_settings['custom_fire_threshold']}°C")
              end
              if @cluster.environmental_settings["seismic_sensitivity_threshold"]
                env_block("Seismic Sensitivity", @cluster.environmental_settings["seismic_sensitivity_threshold"].to_s)
              end
              if @cluster.environmental_settings["timezone"]
                env_block("Timezone", @cluster.environmental_settings["timezone"])
              end
            end
          end
        end
      end
    end

    def vital_block(label, value)
      div do
        p(class: "text-mini uppercase tracking-tighter text-gray-600") { label }
        p(class: "text-3xl font-extralight text-emerald-100") { value }
      end
    end

    def env_block(label, value)
      div do
        p(class: "text-gaia-text-muted uppercase") { label }
        p(class: "text-gaia-primary mt-1") { value }
      end
    end

    def render_gateways_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        h3(class: "p-4 text-tiny uppercase tracking-widest text-emerald-700 border-b border-emerald-900/30") { "Gateway Fleet" }
        table(role: "table", class: "w-full text-left font-mono text-tiny") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-micro tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { "UID" }
              th(scope: "col", class: "p-4") { "State" }
              th(scope: "col", class: "p-4") { "Coordinates" }
              th(scope: "col", class: "p-4 text-right") { "Last Seen" }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @gateways.any?
              @gateways.each { |gw| render_gateway_row(gw) }
            else
              tr { td(colspan: 4, class: "p-10 text-center text-emerald-900 uppercase tracking-widest") { "No gateways deployed" } }
            end
          end
        end
      end
    end

    def render_gateway_row(gw)
      tr(class: "hover:bg-emerald-950/10 transition-colors") do
        td(class: "p-4 text-emerald-400") { gw.uid }
        td(class: "p-4 uppercase") { gw.state }
        td(class: "p-4 text-gray-500") { "#{gw.latitude}, #{gw.longitude}" }
        td(class: "p-4 text-right text-gray-600") { gw.last_seen_at&.strftime("%H:%M:%S // %d.%m.%y") || "—" }
      end
    end

    def render_alerts_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "Active Threats" }
        # ⚡ [СИНХРОНІЗАЦІЯ]: alerts_list — контейнер для broadcast_prepend нових алертів
        div(id: "alerts_list", class: "space-y-2") do
          if @recent_alerts.any?
            @recent_alerts.each do |alert|
              div(id: dom_id(alert), class: "flex justify-between items-center py-2 border-b border-emerald-900/20 font-mono text-tiny") do
                div(class: "flex items-center gap-3") do
                  div(class: tokens("h-2 w-2 rounded-full", alert_severity_class(alert)))
                  span(class: "text-emerald-400 uppercase") { alert.alert_type }
                end
                span(class: "text-gray-600") { alert.created_at.strftime("%d.%m.%y %H:%M") }
              end
            end
          else
            p(class: "text-compact text-gray-700 italic") { "No active threats. Sector is nominal." }
          end
        end
      end
    end

    def render_contract_panel
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "NaaS Contract" }
        if @active_contract
          div(class: "space-y-3 font-mono text-tiny") do
            contract_row("Status", @active_contract.status.upcase)
            contract_row("Value", @active_contract.total_value.to_s)
            contract_row("Emitted SCC", @active_contract.emitted_tokens.to_s)
          end
        else
          p(class: "text-compact text-gray-700 italic") { "No active NaaS contract." }
        end
      end
    end

    def contract_row(label, value)
      div(class: "flex justify-between items-center") do
        span(class: "text-gray-600 uppercase") { label }
        span(class: "text-emerald-400") { value }
      end
    end

    def render_geography_panel
      center = @cluster.geo_center
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "Geographic Anchor" }
        div(class: "space-y-3 text-tiny font-mono") do
          geo_row("Region", @cluster.region)
          geo_row("Mapped", @cluster.mapped? ? "Yes" : "No")
          if center
            geo_row("Centroid", "#{center[:lat].round(4)}, #{center[:lng].round(4)}")
            a(
              href: "https://www.google.com/maps?q=#{center[:lat]},#{center[:lng]}",
              target: "_blank",
              class: "block mt-4 text-center p-2 border border-emerald-800 text-emerald-600 hover:bg-emerald-900 hover:text-white transition-all uppercase focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500",
              aria_label: "View cluster location on Google Maps"
            ) { "View on Map →" }
          end
        end
      end
    end

    def geo_row(label, value)
      div(class: "flex justify-between") do
        span(class: "text-gray-600") { "#{label}:" }
        span(class: "text-emerald-400") { value }
      end
    end

    def alert_severity_class(alert)
      case alert.severity.to_s
      when "critical" then "bg-red-500 animate-pulse"
      when "medium" then "bg-status-warning"
      when "low" then "bg-emerald-500"
      else "bg-emerald-500"
      end
    end
  end
end
