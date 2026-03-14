# frozen_string_literal: true

module Actuators
  class CommandRow < ApplicationComponent
    def initialize(command:)
      @command = command
    end

    def view_template
      div(
        id: "command_row_#{@command.id}",
        class: "flex items-center gap-3 py-2 px-3 border-b border-zinc-800 text-compact font-mono"
      ) do
        span(class: "text-zinc-500") { @command.created_at&.strftime("%H:%M:%S") }
        span(class: "text-emerald-400") { @command.command_payload }
        render Actuators::CommandStatusBadge.new(command: @command)
      end
    end
  end
end
