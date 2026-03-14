# frozen_string_literal: true

module Dashboard
  class EventRow < ApplicationComponent
    def initialize(event:)
      @event = event
    end

    def view_template
      div(class: "flex items-start space-x-4 border-l border-emerald-900/30 pl-4 py-1") do
        div(class: "flex flex-col flex-1 font-mono text-[10px]") do
          span(class: "text-emerald-900 text-[8px] mb-1") { time_ago_text }
          span(class: tokens("leading-relaxed", event_color)) { event_summary }
        end
      end
    end

    private

    def event_summary
      case @event
      when EwsAlert then "⚠ Threat: #{@event.alert_type} in #{@event.cluster&.name || 'Unknown'}"
      when BlockchainTransaction then "⬢ Minted #{@event.amount} SCC → #{@event.wallet&.tree&.did || 'System'}"
      when MaintenanceRecord then "🔧 #{@event.action_type&.capitalize}: by #{@event.user&.first_name || 'System'}"
      else "● System pulse detected"
      end
    end

    def event_color
      case @event
      when EwsAlert then "text-red-400"
      when BlockchainTransaction then "text-emerald-400"
      when MaintenanceRecord then "text-amber-400"
      else "text-gray-400"
      end
    end

    def time_ago_text
      render Views::Shared::UI::RelativeTime.new(datetime: @event.created_at)
    end
  end
end
