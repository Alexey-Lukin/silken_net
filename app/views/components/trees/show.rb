# frozen_string_literal: true

module Views
  module Components
    module Trees
      class Show < ApplicationComponent
        def initialize(tree:)
          @tree = tree
          # Беремо останній пульс
          @latest_log = @tree.telemetry_logs.order(created_at: :desc).first
          @recent_logs = @tree.telemetry_logs.order(created_at: :desc).limit(10)
          @family = @tree.tree_family
          @maintenance_history = @tree.maintenance_records.includes(:user).order(performed_at: :desc)
          @hardware_key = @tree.hardware_key
        end

        def view_template
          div(class: "space-y-10 animate-in fade-in duration-1000") do
            render_header
            
            div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
              # ЛІВИЙ КОНТУР: Біометрія та Графіки
              div(class: "xl:col-span-2 space-y-10") do
                render_biometric_panel
                render_impedance_history # Новий блок графіків
                render_maintenance_ledger # Журнал зцілень
              end

              # ПРАВИЙ КОНТУР: Економіка, Безпека, Локація
              div(class: "space-y-10") do
                render_economic_panel
                render_hardware_security_vault # Криптографічний статус
                render_metadata_panel
              end
            end
          end
        end

        private

        def render_header
          div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
            # Декоративний фон
            div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none") { "SOLDIER" }
            
            div do
              h2(class: "text-4xl font-extralight tracking-tighter text-emerald-400") { @tree.did }
              div(class: "flex items-center space-x-3 mt-2") do
                span(class: tokens("text-[10px] px-2 py-0.5 border font-mono uppercase tracking-widest", status_color_class)) { @tree.status }
                span(class: "text-[10px] text-emerald-900 font-mono") { "Family: #{@family.name}" }
              end
            end

            div(class: "mt-6 md:mt-0 flex items-center space-x-12") do
              div(class: "text-right") do
                p(class: "text-[9px] text-gray-600 uppercase tracking-widest") { "Uplink State" }
                p(class: "text-sm font-mono text-emerald-100") { @latest_log&.created_at&.strftime("%H:%M:%S // %d.%m.%y") || "SILENT" }
              end
              div(class: tokens("h-4 w-4 rounded-sm rotate-45", status_led_class))
            end
          end
        end

        def render_biometric_panel
          div(class: "p-8 border border-emerald-900 bg-zinc-950") do
            h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-10") { "Live Biometric Matrix" }
            
            div(class: "grid grid-cols-1 md:grid-cols-2 gap-12 items-center") do
              div(class: "relative h-56 w-56 mx-auto") do
                render_radial_svg
                div(class: "absolute inset-0 flex flex-col items-center justify-center") do
                  span(class: "text-6xl font-extralight text-white") { @latest_log&.z_value || "---" }
                  span(class: "text-[10px] text-emerald-800 font-mono uppercase") { "kΩ Impedance" }
                end
              end

              div(class: "space-y-6") do
                metric_row("Ionic Potential", "#{@latest_log&.voltage_mv || 0} mV", sub: "Streaming potential charge")
                metric_row("Xylem Thermal", "#{@latest_log&.temperature_c || 0} °C", sub: "Internal core temp")
                metric_row("Stress Index", "#{(@tree.current_stress * 100).round(1)}%", danger: @tree.under_threat?)
              end
            end
          end
        end

        def render_impedance_history
          div(class: "p-8 border border-emerald-900 bg-black/40") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Impedance Flux (Last 10 Cycles)" }
            
            # Візуалізація міні-графіка через висоту барів
            div(class: "flex items-end space-x-2 h-32 border-b border-emerald-900/30 pb-2") do
              @recent_logs.reverse_each do |log|
                height = [(log.z_value.to_f / @family.baseline_impedance * 100), 100].min
                div(
                  class: "flex-1 bg-emerald-500/20 border-t border-emerald-500 hover:bg-emerald-500 transition-all",
                  style: "height: #{height}%",
                  title: "#{log.z_value} kΩ at #{log.created_at.to_fs(:short)}"
                )
              end
            end
            div(class: "flex justify-between mt-2 text-[8px] font-mono text-emerald-900 uppercase") do
              span { "T-10 Cycles" }
              span { "Real-time Sampling" }
              span { "Current" }
            end
          end
        end

        def render_maintenance_ledger
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Maintenance Rituals & Healing History" }
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[10px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[8px]") do
                  tr do
                    th(class: "p-4") { "Technician" }
                    th(class: "p-4") { "Action" }
                    th(class: "p-4") { "Observations" }
                    th(class: "p-4 text-right") { "Timestamp" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  if @maintenance_history.any?
                    @maintenance_history.each do |record|
                      tr(class: "hover:bg-emerald-950/10 transition-colors") do
                        td(class: "p-4 text-emerald-100") { record.user.full_name }
                        td(class: "p-4 uppercase text-emerald-500") { record.action_type }
                        td(class: "p-4 text-gray-500 italic") { record.notes.truncate(50) }
                        td(class: "p-4 text-right text-gray-600") { record.performed_at.strftime("%d.%m.%y") }
                      end
                    end
                  else
                    tr { td(colspan: 4, class: "p-10 text-center text-emerald-900 uppercase tracking-widest") { "No physical interventions recorded" } }
                  end
                end
              end
            end
          end
        end

        def render_hardware_security_vault
          div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
            div(class: "flex justify-between items-center") do
              h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Hardware Security Vault" }
              span(class: "h-2 w-2 rounded-full bg-blue-500 shadow-[0_0_8px_#3b82f6]")
            end

            div(class: "space-y-4 text-[10px] font-mono") do
              security_item("Key Identity", @hardware_key&.device_uid || "NOT_PROVISIONED")
              security_item("Cipher Suite", "AES-256-ECB (CoAP Level)")
              security_item("Integrity", "Verified Hardware Anchor")
              security_item("OTA Status", "Channel Encrypted")
            end

            div(class: "pt-4 border-t border-emerald-900/30") do
              button(class: "w-full py-2 border border-emerald-900 text-[9px] uppercase text-emerald-700 hover:border-emerald-500 hover:text-emerald-500 transition-all") do
                "Rotate Hardware Key →"
              end
            end
          end
        end

        def render_economic_panel
          div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Economic Yield" }
            div(class: "space-y-4") do
              div do
                p(class: "text-[9px] text-gray-600 uppercase") { "Verified Balance" }
                div(class: "flex items-baseline space-x-2") do
                  span(class: "text-3xl font-light text-white") { @tree.wallet&.scc_balance || "0.0" }
                  span(class: "text-xs text-emerald-600 font-mono") { "SCC" }
                end
              end
              security_item("Address", @tree.wallet&.address&.first(12) + "...", full: @tree.wallet&.address)
            end
          end
        end

        def render_metadata_panel
          div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Deployment Matrix" }
            div(class: "space-y-3 text-[10px] font-mono") do
              meta_row("Cluster", @tree.cluster&.name)
              meta_row("Coordinates", "#{@tree.latitude}, #{@tree.longitude}")
              
              a(
                href: "https://www.google.com/maps?q=#{@tree.latitude},#{@tree.longitude}",
                target: "_blank",
                class: "block mt-4 text-center p-2 border border-emerald-800 text-emerald-600 hover:bg-emerald-900 hover:text-white transition-all uppercase"
              ) { "Locate Node →" }
            end
          end
        end

        # --- HELPERS ---

        def metric_row(label, value, sub: nil, danger: false)
          div(class: "flex justify-between items-end border-b border-emerald-900/30 pb-2") do
            div do
              p(class: "text-[9px] text-gray-600 uppercase") { label }
              p(class: "text-[8px] text-emerald-900 font-mono") { sub } if sub
            end
            span(class: tokens("text-lg font-mono", danger ? "text-red-500 animate-pulse" : "text-emerald-300")) { value }
          end
        end

        def security_item(label, value, full: nil)
          div do
            p(class: "text-[8px] text-gray-600 uppercase mb-1") { label }
            p(class: "text-emerald-500 truncate", title: full) { value }
          end
        end

        def meta_row(label, value)
          div(class: "flex justify-between") do
            span(class: "text-gray-600") { "#{label}:" }
            span(class: "text-emerald-400") { value }
          end
        end

        def render_radial_svg
          stress_factor = @tree.current_stress
          offset = 552 * (1 - stress_factor)
          svg(class: "h-56 w-56 -rotate-90 transform") do
            circle(cx: "112", cy: "112", r: "88", class: "fill-none stroke-emerald-950 stroke-1")
            circle(
              cx: "112", cy: "112", r: "88", 
              class: tokens("fill-none stroke-[3] transition-all duration-1000", @tree.under_threat? ? "stroke-red-600 animate-pulse" : "stroke-emerald-500 shadow-[0_0_15px_#10b981]"),
              style: "stroke-dasharray: 552; stroke-dashoffset: #{offset};"
            )
          end
        end

        def status_color_class
          case @tree.status
          when "active" then "border-emerald-500 text-emerald-500"
          when "dormant" then "border-amber-600 text-amber-600"
          else "border-red-800 text-red-800"
          end
        end

        def status_led_class
          @latest_log&.created_at&. > 15.minutes.ago ? "bg-emerald-500 shadow-[0_0_12px_#10b981]" : "bg-red-900"
        end
      end
    end
  end
end
