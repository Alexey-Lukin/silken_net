# frozen_string_literal: true

module Views
  module Components
    module Actuators
      class Card < ApplicationComponent
        def initialize(actuator:, last_command: nil)
          @actuator = actuator
          @last_command = last_command || @actuator.actuator_commands.last
        end

        def view_template
          div(id: "actuator_#{@actuator.id}", class: "group p-6 border border-emerald-900 bg-zinc-950 hover:border-emerald-500 transition-all duration-500 relative overflow-hidden shadow-2xl") do
            # Фоновий індикатор типу (декоративний)
            div(class: "absolute -right-4 -top-4 text-[40px] font-bold text-emerald-900/5 select-none") { @actuator.actuator_type[0..2].upcase }
            
            render_header
            render_status_matrix
            render_controls
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-start mb-6") do
            div do
              span(class: "text-[8px] px-2 py-0.5 border border-emerald-800 text-emerald-700 uppercase font-mono tracking-widest") { @actuator.actuator_type }
              h4(class: "text-lg font-light text-emerald-100 mt-2 tracking-tighter") { @actuator.tree&.did || "Sector Relay // #{@actuator.gateway&.uid}" }
            end
            div(class: tokens("h-2 w-2 rounded-full", status_led_class))
          end
        end

        def render_status_matrix
          div(class: "space-y-2 mb-6 font-mono text-[10px] uppercase tracking-tighter") do
            div(class: "flex justify-between border-b border-emerald-900/20 pb-1") do
              span(class: "text-gray-600") { "Physical State:" }
              span(class: "text-emerald-500") { @actuator.status }
            end
            div(class: "flex justify-between") do
              span(class: "text-gray-600") { "Last Sync Status:" }
              span(class: tokens(@last_command&.status == 'failed' ? "text-red-500" : "text-gray-400")) do
                @last_command&.status || "IDLE"
              end
            end
          end
        end

        def render_controls
          div(class: "grid grid-cols-2 gap-2") do
            # Кнопка Увімкнення/Відкриття (Execute Open/ON)
            button_to(
              helpers.execute_api_v1_actuator_path(@actuator, action_payload: 'open'),
              method: :post,
              class: "py-2 border border-emerald-500 text-[9px] uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all font-bold tracking-widest"
            ) { "EXECUTE_ON" }

            # Кнопка Вимкнення/Закриття (Execute Close/OFF)
            button_to(
              helpers.execute_api_v1_actuator_path(@actuator, action_payload: 'close'),
              method: :post,
              class: "py-2 border border-emerald-900 text-[9px] uppercase text-gray-600 hover:border-red-900 hover:text-white transition-all tracking-widest"
            ) { "EXECUTE_OFF" }
          end
        end

        def status_led_class
          case @actuator.status
          when 'active' then "bg-emerald-500 shadow-[0_0_10px_#10b981]"
          when 'faulty' then "bg-red-600 animate-pulse shadow-[0_0_10px_red]"
          else "bg-gray-800"
          end
        end
      end
    end
  end
end
