# frozen_string_literal: true

module Views
  module Components
    module Actuators
      class Index < ApplicationComponent
        def initialize(cluster:, actuators:)
          @cluster = cluster
          @actuators = actuators
        end

        def view_template
          div(class: "space-y-8 animate-in slide-in-from-right duration-700") do
            header_section
            
            div(class: "grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6") do
              if @actuators.any?
                @actuators.each do |actuator|
                  render Views::Components::Actuators::Card.new(actuator: actuator)
                end
              else
                render_empty_state
              end
            end
          end
        end

        private

        def header_section
          div(class: "p-8 border border-emerald-900 bg-black flex flex-col md:flex-row justify-between items-start md:items-center relative overflow-hidden shadow-2xl") do
            # Декоративний фон
            div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "ACTUATORS" }
            
            div do
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700 mb-2") { "Hardware Interaction Layer" }
              h2(class: "text-3xl font-extralight text-emerald-400 tracking-tighter") { "Sector Matrix // #{@cluster.name}" }
            end
            
            div(class: "mt-4 md:mt-0 flex space-x-6 text-[10px] font-mono") do
              stat_label("Active Nodes", @actuators.count { |a| a.status == 'active' })
              stat_label("Total Units", @actuators.count)
            end
          end
        end

        def stat_label(label, value)
          div(class: "text-right") do
            p(class: "text-emerald-900 uppercase") { label }
            p(class: "text-lg text-emerald-100") { value }
          end
        end

        def render_empty_state
          div(class: "col-span-full p-20 border border-dashed border-emerald-900/30 text-center") do
            p(class: "text-emerald-900 font-mono text-xs uppercase tracking-widest") { "No actuator nodes provisioned in this sector." }
          end
        end
      end
    end
  end
end
