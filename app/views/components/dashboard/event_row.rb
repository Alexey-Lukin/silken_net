# frozen_string_literal: true

module Dashboard
  class EventRow < ApplicationComponent
    def initialize(event:)
      @event = event
    end

    def view_template
      div(class: "flex items-start gap-4 border-l border-emerald-900/30 pl-4 py-1") do
        div(class: "flex flex-col flex-1 font-mono text-tiny") do
          span(class: "text-emerald-900 text-micro mb-1") { time_ago_text }
          span(class: tokens("leading-relaxed", event_color)) { event_summary }
        end
      end
    end

    private

    def event_summary
      case @event
      when EwsAlert then "⚠ Threat: #{@event.alert_type} in #{@event.cluster&.name || 'Unknown'}"
      when BlockchainTransaction then blockchain_transaction_summary
      when MaintenanceRecord then "🔧 #{@event.action_type&.capitalize}: by #{@event.user&.first_name || 'System'}"
      else "● System pulse detected"
      end
    end

    def event_color
      case @event
      when EwsAlert then "text-red-400"
      when BlockchainTransaction then "text-emerald-400"
      when MaintenanceRecord then "text-status-warning-text"
      else "text-gray-400"
      end
    end

    def time_ago_text
      render Views::Shared::UI::RelativeTime.new(datetime: @event.created_at)
    end

    def blockchain_transaction_summary
      sourceable = @event.sourceable
      if sourceable.is_a?(ParametricInsurance) && sourceable.uses_etherisc?
        "🛡️ Etherisc DIP claim #{@event.amount} USDC → #{short_address(@event.to_address)}"
      else
        "⬢ Minted #{@event.amount} SCC → #{@event.wallet&.tree&.did || 'System'}"
      end
    end

    def short_address(address)
      return "Pool" unless address.present? && address.length > 10

      "#{address[0..5]}…#{address[-4..]}"
    end
  end
end
