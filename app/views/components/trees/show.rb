# frozen_string_literal: true

module Views
  module Components
    module Trees
      class Show < ApplicationComponent
        def initialize(tree:)
          @tree = tree
          @latest_log = @tree.telemetry_logs.order(created_at: :desc).first
          @family = @tree.tree_family
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            render_status_header
            
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Основна біо-метрика (Імпеданс та Стрес)
              div(class: "lg:col-span-2 space-y-8") do
                render_biometric_panel
                render_environmental_panel
              end

              # Бічна панель (Wallet, Location, Metadata)
              div(class: "space-y-8") do
                render_economic_panel
                render_metadata_panel
              end
            end
          end
        end

        private

        def render_status_header
          div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-6 border border-emerald-900 bg-black/50 backdrop-blur-sm") do
            div do
              h2(class: "text-3xl font-light tracking-tighter text-emerald-400") { "Soldier // #{@tree.did}" }
              p(class: "text-xs font-mono text-emerald-800 uppercase mt-1") { "#{@family.name} • #{@tree.status}" }
            end

            div(class: "mt-4 md:mt-0 flex items-center space-x-6") do
              div(class: "text-right") do
                p(class: "text-[10px] text-gray-600 uppercase tracking-widest") { "Last Sync" }
                p(class: "text-sm font-mono") { @latest_log&.created_at&.strftime("%H:%M:%S // %d.%m.%y") || "NEVER" }
              end
              div(class: tokens("h-3 w-3 rounded-full shadow-lg", status_color_class))
            end
          end
        end

        def render_biometric_panel
          div(class: "p-8 border border-emerald-900 bg-zinc-950") do
            h3(class: "text-xs uppercase tracking-[0.3em] text-emerald-700 mb-8") { "Biometric Pulse (Impedance & Stress)" }
            
            div(class: "flex flex-col md:flex-row items-center justify-between gap-12") do
              # Велика діаграма або показник Z
              div(class: "relative") do
                render_radial_stress_indicator
                div(class: "absolute inset-0 flex flex-col items-center justify-center") do
                  span(class: "text-5xl font-extralight text-emerald-100") { @latest_log&.z_value || "---" }
                  span(class: "text-[10px] text-emerald-800") { "kOhm (Z)" }
                end
              end

              # Деталізація відхилення
              div(class: "flex-1 space-y-6 w-full") do
                metric_row("Baseline", "#{@family.baseline_impedance} kΩ")
                metric_row("Deviation", "#{z_deviation}%")
                metric_row("Stress Index", "#{(@tree.current_stress * 100).round(1)}%", alert: @tree.under_threat?)
              end
            end
          end
        end

        def render_environmental_panel
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-4") do
            environment_card("Temperature", "#{@latest_log&.temperature_c}°C", icon: "temp")
            environment_card("Battery", "#{@latest_log&.voltage_mv} mV", icon: "bolt")
            environment_card("Mesh Signal", "#{@latest_log&.relayed_via_mesh? ? 'Relayed' : 'Direct'}", icon: "wifi")
          end
        end

        def render_economic_panel
          div(class: "p-6 border border-emerald-900 bg-emerald-950/10") do
            h3(class: "text-xs uppercase tracking-widest text-emerald-700 mb-4") { "Carbon Economy (Wallet)" }
            div(class: "space-y-4") do
              div(class: "flex justify-between items-end") do
                span(class: "text-2xl font-light text-white") { "#{@tree.wallet&.scc_balance || 0.0}" }
                span(class: "text-[10px] text-emerald-600 mb-1") { "SCC (Silken Carbon Coin)" }
              end
              div(class: "h-px bg-emerald-900")
              p(class: "text-[10px] text-gray-500 font-mono break-all") { "Address: #{@tree.wallet&.address}" }
            end
          end
        end

        def render_metadata_panel
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-xs uppercase tracking-widest text-emerald-700 mb-4") { "Geo-Location" }
            div(class: "space-y-2") do
              p(class: "text-sm text-gray-400") { "Lat: #{@tree.latitude}" }
              p(class: "text-sm text-gray-400") { "Lng: #{@tree.longitude}" }
              a(
                href: "https://www.google.com/maps?q=#{@tree.latitude},#{@tree.longitude}", 
                target: "_blank",
                class: "inline-block mt-4 text-[10px] text-emerald-500 hover:text-white underline underline-offset-4"
              ) { "VIEW ON MAP →" }
            end
          end
        end

        # Helpers
        def metric_row(label, value, alert: false)
          div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
            span(class: "text-xs text-gray-600 uppercase") { label }
            span(class: tokens("font-mono text-sm", alert ? "text-red-500 animate-pulse" : "text-emerald-300")) { value }
          end
        end

        def environment_card(label, value, icon:)
          div(class: "p-4 border border-emerald-900 bg-zinc-900") do
            p(class: "text-[9px] text-emerald-800 uppercase mb-1") { label }
            p(class: "text-xl font-light text-emerald-100") { value }
          end
        end

        def render_radial_stress_indicator
          # Проста SVG-архітектура для візуалізації стресу
          svg(class: "h-48 w-48 -rotate-90") do
            circle(cx: "96", cy: "96", r: "88", class: "fill-none stroke-emerald-950 stroke-1")
            circle(
              cx: "96", cy: "96", r: "88", 
              class: tokens("fill-none stroke-2 transition-all duration-1000", @tree.under_threat? ? "stroke-red-600" : "stroke-emerald-500"),
              style: "stroke-dasharray: 552; stroke-dashoffset: #{552 * (1 - @tree.current_stress)};"
            )
          end
        end

        def status_color_class
          case @tree.status
          when "active" then "bg-emerald-500"
          when "dormant" then "bg-amber-500"
          when "deceased" then "bg-red-900"
          else "bg-gray-800"
          end
        end

        def z_deviation
          return 0 unless @latest_log
          (((@latest_log.z_value.to_f - @family.baseline_impedance) / @family.baseline_impedance) * 100).round(1)
        end
      end
    end
  end
end
