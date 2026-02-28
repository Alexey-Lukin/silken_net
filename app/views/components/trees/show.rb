# frozen_string_literal: true

module Views
  module Components
    module Trees
      class Show < ApplicationComponent
        def initialize(tree:)
          @tree = tree
          # Беремо останній пульс для актуальних показників
          @latest_log = @tree.telemetry_logs.order(created_at: :desc).first
          @family = @tree.tree_family
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-1000") do
            render_header
            
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Ліва колонка: Біометрія та Аналітика
              div(class: "lg:col-span-2 space-y-8") do
                render_biometric_panel
                render_environmental_grid
              end

              # Права колонка: Економіка та Локація
              div(class: "space-y-8") do
                render_economic_panel
                render_metadata_panel
              end
            end
          end
        end

        private

        def render_header
          div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-6 border border-emerald-900 bg-black/40 backdrop-blur-md") do
            div do
              h2(class: "text-3xl font-extralight tracking-tighter text-emerald-400") { "Soldier // #{@tree.did}" }
              p(class: "text-[10px] font-mono text-emerald-800 uppercase mt-1 tracking-widest") do
                plain "#{@family.name} • Status: "
                span(class: status_color_class) { @tree.status.upcase }
              end
            end

            div(class: "mt-4 md:mt-0 flex items-center space-x-8") do
              div(class: "text-right") do
                p(class: "text-[9px] text-gray-600 uppercase tracking-widest") { "Last Transmission" }
                p(class: "text-sm font-mono text-emerald-100") { @latest_log&.created_at&.strftime("%H:%M:%S // %d.%m.%y") || "OFFLINE" }
              end
              # Живий індикатор зв'язку
              div(class: tokens("h-3 w-3 rounded-full shadow-[0_0_10px_rgba(16,185,129,0.5)]", status_led_class))
            end
          end
        end

        def render_biometric_panel
          div(class: "p-8 border border-emerald-900 bg-zinc-950 relative overflow-hidden") do
            h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-10") { "Biometric Matrix (Impedance & Stress)" }
            
            div(class: "flex flex-col md:flex-row items-center justify-around gap-12") do
              # Радіальний індикатор Z-значення
              div(class: "relative h-48 w-48") do
                render_radial_svg
                div(class: "absolute inset-0 flex flex-col items-center justify-center") do
                  span(class: "text-5xl font-extralight text-emerald-50") { @latest_log&.z_value || "---" }
                  span(class: "text-[10px] text-emerald-800 font-mono") { "kΩ (Impedance)" }
                end
              end

              # Порівняльні метрики
              div(class: "flex-1 space-y-6 w-full max-w-xs") do
                metric_item("Baseline", "#{@family.baseline_impedance} kΩ")
                metric_item("Current Deviation", "#{z_deviation}%")
                metric_item("Stress Index", "#{(@tree.current_stress * 100).round(1)}%", critical: @tree.under_threat?)
              end
            end
          end
        end

        def render_environmental_grid
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-4") do
            env_card("Xylem Temp", "#{@latest_log&.temperature_c || '--'} °C", "thermometer")
            env_card("Cell Voltage", "#{@latest_log&.voltage_mv || '--'} mV", "battery")
            env_card("Signal Path", @latest_log&.relayed_via_mesh? ? "MESH_RELAY" : "DIRECT_LINK", "antenna")
          end
        end

        def render_economic_panel
          div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Silken Economy" }
            div(class: "space-y-6") do
              div do
                p(class: "text-[9px] text-gray-600 uppercase mb-1") { "Accumulated Carbon Value" }
                div(class: "flex items-baseline space-x-2") do
                  span(class: "text-3xl font-light text-white") { @tree.wallet&.scc_balance || "0.0" }
                  span(class: "text-xs text-emerald-600 font-mono") { "SCC" }
                end
              end
              div(class: "h-px bg-emerald-900/30")
              div do
                p(class: "text-[9px] text-gray-600 uppercase mb-2") { "On-Chain Identity" }
                p(class: "text-[10px] font-mono text-emerald-800 break-all leading-relaxed") { @tree.wallet&.address || "NO_WALLET_SYNCED" }
              end
            end
          end
        end

        def render_metadata_panel
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Deployment Metadata" }
            div(class: "space-y-3 font-mono text-[11px]") do
              meta_row("Cluster", @tree.cluster.name)
              meta_row("Hardware UID", @tree.hardware_key&.uid || "UNSET")
              meta_row("Coordinates", "#{@tree.latitude}, #{@tree.longitude}")
              
              a(
                href: "https://www.google.com/maps?q=#{@tree.latitude},#{@tree.longitude}",
                target: "_blank",
                class: "block mt-4 text-center p-2 border border-emerald-800 text-emerald-600 hover:bg-emerald-900 hover:text-white transition-all uppercase tracking-tighter"
              ) { "Locate in Forest →" }
            end
          end
        end

        # --- HELPERS ---

        def metric_item(label, value, critical: false)
          div(class: "flex justify-between items-end border-b border-emerald-900/40 pb-2") do
            span(class: "text-[10px] text-gray-600 uppercase") { label }
            span(class: tokens("font-mono text-sm", critical ? "text-red-500 animate-pulse" : "text-emerald-300")) { value }
          end
        end

        def env_card(label, value, icon)
          div(class: "p-4 border border-emerald-900 bg-zinc-900/50") do
            p(class: "text-[9px] text-emerald-800 uppercase tracking-tighter mb-1") { label }
            p(class: "text-xl font-light text-emerald-100") { value }
          end
        end

        def meta_row(label, value)
          div(class: "flex justify-between") do
            span(class: "text-gray-600") { "#{label}:" }
            span(class: "text-emerald-400") { value }
          end
        end

        def render_radial_svg
          # Розрахунок stroke-dashoffset для візуалізації стресу
          # Коло 2 * PI * R (R=88) ~= 552
          stress_factor = @tree.current_stress
          offset = 552 * (1 - stress_factor)

          svg(class: "h-48 w-48 -rotate-90 transform") do
            # Background circle
            circle(cx: "96", cy: "96", r: "88", class: "fill-none stroke-emerald-950 stroke-1")
            # Progress circle
            circle(
              cx: "96", cy: "96", r: "88", 
              class: tokens("fill-none stroke-[3] transition-all duration-1000", critical_led_class),
              style: "stroke-dasharray: 552; stroke-dashoffset: #{offset};"
            )
          end
        end

        def status_color_class
          case @tree.status
          when "active" then "text-emerald-500"
          when "dormant" then "text-amber-600"
          else "text-red-800"
          end
        end

        def status_led_class
          @latest_log&.created_at&. > 10.minutes.ago ? "bg-emerald-500 animate-pulse" : "bg-red-900"
        end

        def critical_led_class
          @tree.under_threat? ? "stroke-red-600" : "stroke-emerald-500 shadow-[0_0_15px_rgba(16,185,129,0.3)]"
        end

        def z_deviation
          return 0 unless @latest_log && @family.baseline_impedance > 0
          (((@latest_log.z_value.to_f - @family.baseline_impedance) / @family.baseline_impedance) * 100).round(1)
        end
      end
    end
  end
end
