# app/views/components/actuators/index.rb
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
              @actuators.each do |actuator|
                render Views::Components::Actuators::Card.new(actuator: actuator)
              end
            end
          end
        end

        private

        def header_section
          div(class: "p-6 border border-emerald-900 bg-black flex justify-between items-center") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Hardware Interaction Layer" }
              h2(class: "text-2xl font-light text-emerald-400 mt-2") { "Cluster: #{@cluster.name}" }
            end
            div(class: "flex space-x-4 text-[10px] font-mono") do
              span(class: "text-emerald-900") { "Online Nodes: #{@actuators.count}" }
            end
          end
        end
      end
    end
  end
end
