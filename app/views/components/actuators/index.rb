# frozen_string_literal: true

module Actuators
  class Index < ApplicationComponent
    def initialize(cluster:, actuators:, pagy:, active_count: 0)
      @cluster = cluster
      @actuators = actuators
      @pagy = pagy
      @active_count = active_count
    end

    def view_template
      div(class: "space-y-8 animate-in slide-in-from-right duration-700") do
        header_section

        div(class: "grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6") do
          if @actuators.any?
            @actuators.each do |actuator|
              render Actuators::Card.new(actuator: actuator)
            end
          else
            render_empty_state
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_cluster_actuators_path(@cluster, page: page) }
        )
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
          stat_label("Active Nodes", @active_count)
          stat_label("Total Units", @pagy.count)
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
      render Views::Shared::UI::EmptyState.new(
        title: "No actuator nodes provisioned in this sector.",
        icon: "⚙",
        description: "Deploy hardware to begin monitoring."
      )
    end
  end
end
