# frozen_string_literal: true

module Dashboard
  class EventRow < ApplicationComponent
    ICON_COLORS = {
      "blue"    => "text-blue-400",
      "red"     => "text-red-400",
      "emerald" => "text-emerald-400",
      "amber"   => "text-amber-400"
    }.freeze

    def initialize(event:, icon: "activity", color: "emerald")
      @event = event
      @icon  = icon
      @color = color
    end

    def view_template
      color_class = ICON_COLORS.fetch(@color, "text-zinc-400")

      div(class: "flex items-center gap-3 py-2 px-3 border-b border-zinc-800 text-[11px]") do
        span(class: color_class) { "● #{@icon}" }
        span(class: "text-zinc-300 font-mono") { event_summary }
        span(class: "text-zinc-600 ml-auto") { @event.created_at&.strftime("%H:%M") }
      end
    end

    private

    def event_summary
      case @event
      when BlockchainTransaction
        "TX ##{@event.id}: #{@event.amount} #{@event.token_type} → #{@event.to_address&.truncate(16)}"
      else
        "Event ##{@event.id}"
      end
    end
  end
end
