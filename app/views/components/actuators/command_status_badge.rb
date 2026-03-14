# frozen_string_literal: true

module Actuators
  class CommandStatusBadge < ApplicationComponent
    STATUS_STYLES = {
      "issued"       => "bg-yellow-900 text-yellow-200",
      "sent"         => "bg-blue-900 text-blue-200",
      "acknowledged" => "bg-emerald-900 text-emerald-200",
      "failed"       => "bg-red-900 text-red-200",
      "confirmed"    => "bg-emerald-800 text-emerald-100"
    }.freeze

    def initialize(command:)
      @command = command
    end

    def view_template
      status = @command.status.to_s
      style  = STATUS_STYLES.fetch(status, "bg-zinc-800 text-zinc-300")

      span(
        id: "command_status_#{@command.id}",
        class: tokens("px-2 py-0.5 rounded text-[10px] font-bold uppercase", style)
      ) { status }
    end
  end
end
