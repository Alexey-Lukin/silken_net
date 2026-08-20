# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  class Index < ApplicationComponent
    # `last_commands` — мапа `actuator_id => ActuatorCommand`, зібрана
    # контролером з уже преloaded асоціації (`04_04 §6.4`: компонент даних не
    # добирає). Дефолт порожній, щоб картка чесно показала «немає команд».
    def initialize(cluster:, actuators:, pagy:, active_count: 0, last_commands: {})
      @cluster = cluster
      @actuators = actuators
      @pagy = pagy
      @active_count = active_count
      @last_commands = last_commands
    end

    def view_template
      div(class: "space-y-8") do
        header_section

        div(class: "grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6") do
          if @actuators.any?
            @actuators.each do |actuator|
              render Actuators::Card.new(actuator: actuator, last_command: @last_commands[actuator.id])
            end
          else
            render_empty_state
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { cluster_actuators_path(@cluster, page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "p-8 border border-gaia-border bg-gaia-surface flex flex-col md:flex-row justify-between items-start md:items-center relative overflow-hidden shadow-2xl") do
        # Декоративний фон
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }

        div do
          h3(class: "text-tiny uppercase tracking-[0.5em] text-gaia-text-muted mb-2") { t(".title") }
          h2(class: "text-3xl font-extralight text-gaia-text-strong tracking-tighter") { t(".sector_matrix", name: @cluster.name) }
        end

        div(class: "mt-4 md:mt-0 flex gap-6 text-tiny font-mono") do
          stat_label(t(".active_nodes"), @active_count)
          stat_label(t(".total_units"), @pagy.count)
        end
      end
    end

    def stat_label(label, value)
      div(class: "text-right") do
        p(class: "text-gaia-text-subtle uppercase") { label }
        p(class: "text-lg text-gaia-text-strong") { value }
      end
    end

    def render_empty_state
      render Views::Shared::UI::EmptyState.new(
        title: t(".empty_title"),
        icon: "⚙",
        description: t(".empty_description")
      )
    end
  end
end
