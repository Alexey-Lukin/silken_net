# frozen_string_literal: true

module Actuators
  class Card < ApplicationComponent
    def initialize(actuator:, last_command: nil)
      @actuator = actuator
      @last_command = last_command || @actuator.commands.last
    end

    def view_template
      div(id: "actuator_#{@actuator.id}", class: card_container_classes) do
        # Фоновий індикатор типу (декоративний)
        div(class: "absolute -right-4 -top-4 text-[40px] font-bold text-gaia-text-muted/5 select-none", aria_hidden: "true") { @actuator.device_type[0..2].upcase }

        render_header
        render_status_matrix
        render_controls
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-start mb-6") do
        div do
          span(class: "text-micro px-2 py-0.5 border border-gaia-border text-gaia-text-muted uppercase font-mono tracking-widest") { @actuator.device_type }
          h4(class: "text-lg font-light text-gaia-text mt-2 tracking-tighter") { "Sector Relay // #{@actuator.gateway&.uid}" }
        end
        div(class: tokens("h-2 w-2 rounded-full", status_led_class))
      end
    end

    def render_status_matrix
      div(class: "space-y-2 mb-6 font-mono text-tiny uppercase tracking-tighter") do
        div(class: "flex justify-between border-b border-gaia-border pb-1") do
          span(class: "text-gaia-text-muted") { "Physical State:" }
          span(class: "text-gaia-primary") { @actuator.state }
        end
        div(class: "flex justify-between") do
          span(class: "text-gaia-text-muted") { "Last Sync Status:" }
          failed = @last_command&.status == "failed"
          span(class: tokens("text-status-danger-accent": failed, "text-gaia-text-muted": !failed)) do
            @last_command&.status || "IDLE"
          end
        end
      end
    end

    def render_controls
      # Route helpers потребують request context (url_options).
      # При Turbo broadcast з воркера — request context відсутній.
      return unless respond_to?(:view_context) && view_context&.respond_to?(:url_options)

      div(class: "grid grid-cols-2 gap-2") do
        # Кнопка Увімкнення/Відкриття (Execute Open/ON)
        button_to(
          execute_api_v1_actuator_path(@actuator, action_payload: "open"),
          method: :post,
          aria: { label: "Execute ON command for actuator #{@actuator.device_type}" },
          class: execute_on_classes
        ) { "EXECUTE_ON" }

        # Кнопка Вимкнення/Закриття (Execute Close/OFF)
        button_to(
          execute_api_v1_actuator_path(@actuator, action_payload: "close"),
          method: :post,
          aria: { label: "Execute OFF command for actuator #{@actuator.device_type}" },
          class: execute_off_classes
        ) { "EXECUTE_OFF" }
      end
    end

    def status_led_class
      case @actuator.state
      when "active" then "bg-emerald-500 shadow-[0_0_10px_#10b981]"
      when "maintenance_needed" then "bg-red-600 animate-pulse shadow-[0_0_10px_red]"
      when "offline" then "bg-red-900"
      else "bg-gray-800"
      end
    end

    def card_container_classes
      "group p-6 border border-gaia-border bg-gaia-surface " \
        "shadow-sm dark:shadow-none " \
        "hover:border-gaia-primary transition-all duration-500 " \
        "relative overflow-hidden"
    end

    def execute_on_classes
      "py-2 border border-gaia-primary text-mini uppercase text-gaia-primary " \
        "hover:bg-gaia-primary hover:text-black " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary " \
        "transition-all font-bold tracking-widest"
    end

    def execute_off_classes
      "py-2 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
        "hover:border-status-danger-accent hover:text-status-danger-accent " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger-accent " \
        "transition-all tracking-widest"
    end
  end
end
