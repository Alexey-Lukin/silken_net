# frozen_string_literal: true

module Views
  module Components
    module Navigation
      class Sidebar < ApplicationComponent
        def view_template
          aside(class: "w-64 h-screen sticky top-0 bg-black border-r border-emerald-900/50 flex flex-col z-50 overflow-y-auto font-mono") do
            render_logo
            render_status_pulse
            
            nav(class: "flex-1 px-4 py-8 space-y-10") do
              # СТРАТЕГІЧНИЙ КОНТУР
              section_group("Strategic Insight") do
                nav_item("Oracle Visions", helpers.api_v1_oracle_visions_path, "eye")
                nav_item("Treasury Matrix", helpers.api_v1_wallets_path, "bank")
              end

              # ОПЕРАЦІЙНИЙ КОНТУР
              section_group("Forest Operations") do
                nav_item("Threat Alerts", helpers.api_v1_alerts_path, "zap", badge: ews_alert_count)
                nav_item("Soldier Fleet", "#", "tree") # Посилання на масив дерев
                nav_item("Crew Registry", helpers.api_v1_users_path, "users")
              end

              # ТЕХНІЧНИЙ КОНТУР
              section_group("Neural Network") do
                nav_item("Queen Relays", helpers.api_v1_gateways_path, "radio")
                nav_item("Firmware OTA", helpers.api_v1_firmwares_path, "cpu")
                nav_item("Live Telemetry", helpers.live_api_v1_telemetry_index_path, "activity", pulse: true)
                nav_item("Maintenance Log", helpers.api_v1_maintenance_records_path, "clipboard")
              end
            end

            render_user_footer
          end
        end

        private

        def render_logo
          div(class: "px-6 py-8 border-b border-emerald-900/30") do
            h1(class: "text-emerald-500 font-extralight tracking-[0.4em] uppercase text-lg") { "Silken Net" }
            p(class: "text-[8px] text-emerald-900 mt-1 uppercase tracking-widest") { "Central Command Citadel" }
          end
        end

        def render_status_pulse
          div(class: "px-6 py-4 bg-emerald-950/10 flex items-center justify-between border-b border-emerald-900/20") do
            div(class: "flex items-center space-x-2") do
              div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse")
              span(class: "text-[9px] text-emerald-700 uppercase") { "Sync: 1.12 THz" }
            end
            span(class: "text-[9px] text-emerald-900") { "v8.0.ocean" }
          end
        end

        def section_group(title, &block)
          div(class: "space-y-4") do
            h3(class: "text-[9px] uppercase tracking-[0.3em] text-emerald-900 px-2") { title }
            div(class: "space-y-1", &block)
          end
        end

        def nav_item(label, path, icon, badge: nil, pulse: false)
          active = helpers.current_page?(path)
          
          a(
            href: path,
            class: tokens(
              "group flex items-center justify-between px-3 py-2 text-[11px] uppercase tracking-widest transition-all duration-300 border-l-2",
              active ? "text-emerald-400 bg-emerald-950/20 border-emerald-500" : "text-gray-500 border-transparent hover:text-emerald-600 hover:bg-emerald-950/5 hover:border-emerald-900/50"
            )
          ) do
            div(class: "flex items-center space-x-3") do
              # SVG-плейсхолдер для іконок (можна замінити на Heroicons або власні)
              span(class: tokens("w-4 h-4", active ? "text-emerald-500" : "text-emerald-900 group-hover:text-emerald-700")) { render_icon(icon) }
              span { label }
            end
            
            if badge&.positive?
              span(class: "bg-red-900/50 text-red-500 text-[8px] px-1.5 py-0.5 rounded-sm") { badge }
            elsif pulse
              div(class: "h-1 w-1 rounded-full bg-emerald-500 animate-ping")
            end
          end
        end

        def render_user_footer
          div(class: "p-4 border-t border-emerald-900/30 mt-auto bg-black") do
            div(class: "flex items-center space-x-3 px-2") do
              div(class: "h-8 w-8 rounded-none border border-emerald-700 flex items-center justify-center text-emerald-500 text-[10px]") { "A" }
              div(class: "flex-1 overflow-hidden") do
                p(class: "text-[10px] text-emerald-100 truncate") { "Architect" }
                p(class: "text-[8px] text-emerald-900 uppercase tracking-tighter") { "Full Access Link" }
              end
            end
          end
        end

        def ews_alert_count
          # Отримуємо кількість активних алертів для бейджа
          EwsAlert.unresolved.count rescue 0
        end

        def render_icon(name)
          # Спрощена логіка іконок — ти можеш вставити сюди SVG
          case name
          when "eye" then "⊙"
          when "bank" then "⬢"
          when "zap" then "⚡"
          when "users" then "◈"
          when "radio" then "📡"
          when "cpu" then "⚙"
          when "activity" then "〰"
          when "tree" then "🌳"
          else "○"
          end
        end
      end
    end
  end
end
