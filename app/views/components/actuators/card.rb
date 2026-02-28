module Views
  module Components
    module Actuators
      class Card < ApplicationComponent
        def initialize(actuator:, last_command: nil)
          @actuator = actuator
          @last_command = last_command || @actuator.actuator_commands.last
        end

        def view_template
          div(id: "actuator_#{@actuator.id}", class: "p-6 border border-emerald-900 bg-zinc-950 relative group") do
            render_header
            render_status_matrix
            render_controls
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-start mb-6") do
            div do
              span(class: "text-[9px] px-2 py-0.5 border border-emerald-800 text-emerald-600 uppercase font-mono") { @actuator.actuator_type }
              h4(class: "text-lg font-light text-emerald-100 mt-2") { @actuator.tree&.did || "Sector Unit" }
            end
            div(class: tokens("h-2 w-2 rounded-full", status_color))
          end
        end

        def render_status_matrix
          div(class: "space-y-2 mb-6 font-mono text-[10px]") do
            div(class: "flex justify-between") do
              span(class: "text-gray-600") { "State:" }
              span(class: "text-emerald-500") { @actuator.status.upcase }
            end
            div(class: "flex justify-between") do
              span(class: "text-gray-600") { "Last Cmd:" }
              span(class: "text-gray-400") { @last_command&.status&.upcase || "NONE" }
            end
          end
        end

        def render_controls
          div(class: "grid grid-cols-2 gap-2") do
            # Кнопка Увімкнення/Відкриття
            button_to(
              "Execute ON",
              helpers.execute_api_v1_actuator_path(@actuator, action: 'open'),
              method: :post,
              class: "py-2 border border-emerald-500 text-[9px] uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all"
            )
            # Кнопка Вимкнення/Закриття
            button_to(
              "Execute OFF",
              helpers.execute_api_v1_actuator_path(@actuator, action: 'close'),
              method: :post,
              class: "py-2 border border-emerald-900 text-[9px] uppercase text-gray-600 hover:border-emerald-500 hover:text-white transition-all"
            )
          end
        end

        def status_color
          @actuator.status == 'online' ? "bg-emerald-500 shadow-[0_0_8px_#10b981]" : "bg-red-900"
        end
      end
    end
  end
end
