module Views
  module Components
    module Actuators
      class Show < ApplicationComponent
        def initialize(actuator:, commands:)
          @actuator = actuator
          @commands = commands
        end

        def view_template
          div(class: "space-y-10 animate-in fade-in duration-700") do
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Головна картка стану
              div(class: "lg:col-span-1") do
                render Views::Components::Actuators::Card.new(actuator: @actuator)
              end

              # Реєстр команд
              div(class: "lg:col-span-2 space-y-4") do
                h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Command Execution Log" }
                render_command_table
              end
            end
          end
        end

        private

        def render_command_table
          div(class: "border border-emerald-900 bg-black overflow-hidden") do
            table(class: "w-full text-left font-mono text-[10px]") do
              thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[8px] tracking-widest") do
                tr do
                  th(class: "p-4") { "ID" }
                  th(class: "p-4") { "Operator" }
                  th(class: "p-4") { "Payload" }
                  th(class: "p-4") { "Status" }
                  th(class: "p-4 text-right") { "Executed At" }
                end
              end
              tbody(class: "divide-y divide-emerald-900/30") do
                @commands.each do |cmd|
                  tr(class: "hover:bg-emerald-950/10") do
                    td(class: "p-4 text-emerald-900") { "##{cmd.id}" }
                    td(class: "p-4 text-emerald-100") { cmd.user&.first_name || "SYSTEM" }
                    td(class: "p-4 font-bold text-white") { cmd.command_payload }
                    td(class: "p-4") do
                      span(class: tokens("px-2 py-0.5 border text-[8px] uppercase", cmd_status_class(cmd))) { cmd.status }
                    end
                    td(class: "p-4 text-right text-gray-600") { cmd.executed_at&.strftime("%d.%m.%y // %H:%M:%S") || "---" }
                  end
                end
              end
            end
          end
        end

        def cmd_status_class(cmd)
          case cmd.status
          when "executed" then "border-emerald-500 text-emerald-500"
          when "failed" then "border-red-900 text-red-500"
          else "border-zinc-800 text-zinc-600"
          end
        end
      end
    end
  end
end
