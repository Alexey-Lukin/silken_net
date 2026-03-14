# frozen_string_literal: true

module Gateways
  class Show < ApplicationComponent
    # Default healthy voltage (mV) when no telemetry is available.
    # Based on fully charged Li-Po battery typical voltage.
    DEFAULT_HEALTHY_VOLTAGE_MV = 4200

    # All data must be pre-loaded in the controller — no fallback queries.
    # @param gateway [Gateway] must respond to :uid, :state, :last_seen_at
    # @param latest_log [GatewayTelemetryLog, nil] pre-loaded latest telemetry
    # @param active_soldiers [Array<Tree>] pre-loaded active soldiers
    def initialize(gateway:, latest_log:, active_soldiers:)
      raise ArgumentError, "gateway must respond to :uid" unless gateway.respond_to?(:uid)

      @gateway = gateway
      @latest_log = latest_log
      @active_soldiers = active_soldiers
    end

    def view_template
      div(class: "space-y-8 animate-in slide-in-from-bottom-4 duration-700") do
        render_status_header

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Технічний контур (Сигнал, Енергія, Температура)
          div(class: "lg:col-span-2 space-y-8") do
            render_technical_matrix
            render_soldier_fleet_overview
          end

          # Панель управління та Метадані
          div(class: "space-y-8") do
            render_network_config
            render_hardware_vault
          end
        end
      end
    end

    private

    def render_status_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-6 border border-emerald-900 bg-black shadow-2xl") do
        div do
          h2(class: "text-3xl font-extralight tracking-tighter text-emerald-400") { "Queen Relay // #{@gateway.uid}" }
          div(class: "flex items-center mt-2 space-x-3") do
            span(class: tokens("text-[10px] px-2 py-0.5 border font-mono uppercase tracking-widest", state_badge_classes)) { @gateway.state }
            span(class: "text-[10px] text-emerald-900 font-mono") { "IP: #{@gateway.ip_address || '0.0.0.0'}" }
          end
        end

        div(class: "mt-4 md:mt-0 flex items-center space-x-10") do
          div(class: "text-right") do
            p(class: "text-[9px] text-gray-600 uppercase tracking-widest") { "Heartbeat" }
            p(class: "text-sm font-mono text-emerald-100") { @gateway.last_seen_at&.strftime("%H:%M:%S // %d.%m.%y") || "SILENT" }
          end
          div(class: tokens("h-4 w-4 rounded-sm rotate-45", connection_led_classes))
        end
      end
    end

    def render_technical_matrix
      div(class: "p-8 border border-emerald-900 bg-zinc-950") do
        h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-10") { "System Telemetry (Queen Diagnostics)" }

        div(class: "grid grid-cols-1 md:grid-cols-3 gap-12") do
          # Cellular Signal (CSQ)
          render_circular_metric(
            label: "Signal Strength",
            value: "#{@latest_log&.signal_quality_percentage || 0}%",
            subtext: "CSQ: #{@latest_log&.cellular_signal_csq || 0}",
            color: signal_color
          )

          # Power / Battery
          render_circular_metric(
            label: "Voltage Matrix",
            value: "#{@latest_log&.voltage_mv || '---'}",
            subtext: "mVolts (Li-Po)",
            color: battery_color
          )

          # Internal Temperature
          render_circular_metric(
            label: "Thermal State",
            value: "#{@latest_log&.temperature_c || '--'}°C",
            subtext: "Internal Core",
            color: temp_color
          )
        end
      end
    end

    def render_soldier_fleet_overview
      div(class: "p-6 border border-emerald-900 bg-black/20") do
        div(class: "flex justify-between items-center mb-6") do
          h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Soldier Fleet Under Command" }
          span(class: "text-[10px] font-mono text-emerald-500") { "#{@active_soldiers.count} Active nodes" }
        end

        # Маленька сітка солдатів у реальному часі
        div(class: "flex flex-wrap gap-2") do
          @active_soldiers.each do |tree|
            render_soldier_node_indicator(tree)
          end
        end
      end
    end

    def render_network_config
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Network Configuration" }
        div(class: "space-y-4 font-mono text-[11px]") do
          config_row("Cluster", @gateway.cluster&.name || "UNASSIGNED")
          config_row("Sleep Interval", "#{@gateway.config_sleep_interval_s || 60}s")
          config_row("Mesh Mode", "Enabled")

          button(class: "w-full mt-4 p-2 border border-emerald-800 text-[10px] uppercase text-emerald-600 hover:bg-emerald-900 hover:text-white transition-all") do
            "Push New Configuration →"
          end
        end
      end
    end

    def render_hardware_vault
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Hardware Cryptography" }
        div(class: "space-y-2 text-[10px] font-mono") do
          p(class: "text-gray-600") { "Hardware UID:" }
          p(class: "text-emerald-500 truncate") { @gateway.hardware_key&.uid || "UNDEFINED" }

          div(class: "mt-4 flex items-center space-x-2 text-emerald-800") do
            span(class: "h-2 w-2 bg-emerald-900 rounded-full")
            span { "AES-256 Provisioned" }
          end
        end
      end
    end

    # --- HELPERS ---

    def render_circular_metric(label:, value:, subtext:, color:)
      div(class: "flex flex-col items-center") do
        div(class: tokens("h-24 w-24 rounded-full border-2 flex flex-col items-center justify-center mb-4", color)) do
          span(class: "text-xl font-light text-white") { value }
        end
        p(class: "text-[9px] uppercase text-gray-600 tracking-tighter") { label }
        p(class: "text-[10px] font-mono text-emerald-900") { subtext }
      end
    end

    def render_soldier_node_indicator(tree)
      # Квадратик статусу дерева — маленька візуальна мапа флоту
      div(
        title: tree.did,
        class: tokens(
          "h-4 w-4 border transition-colors",
          "border-emerald-500 bg-emerald-950/50": tree.active?,
          "border-gray-800 bg-gray-900": !tree.active?,
          "border-red-600 bg-red-950/20 animate-pulse": tree.under_threat?
        )
      )
    end

    def config_row(label, value)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-gray-600") { "#{label}:" }
        span(class: "text-emerald-300") { value }
      end
    end

    def state_badge_classes
      case @gateway.state
      when "active" then "border-emerald-500 text-emerald-500"
      when "updating" then "border-amber-500 text-amber-500"
      when "maintenance" then "border-blue-500 text-blue-500"
      when "faulty" then "border-red-500 text-red-500"
      else "border-gray-800 text-gray-700"
      end
    end

    def connection_led_classes
      recently_seen = @gateway.last_seen_at&.after?(5.minutes.ago)
      tokens("bg-emerald-500 shadow-[0_0_10px_#10b981]": recently_seen, "bg-red-900 animate-pulse": !recently_seen)
    end

    def signal_color; "border-emerald-900/50"; end
    def battery_color
      low_voltage = (@latest_log&.voltage_mv || DEFAULT_HEALTHY_VOLTAGE_MV).to_i < 3400
      tokens("border-red-900": low_voltage, "border-emerald-900/50": !low_voltage)
    end
    def temp_color; "border-emerald-900/50"; end
  end
end
