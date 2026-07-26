# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class EventRow < ApplicationComponent
    def initialize(event:)
      @event = event
    end

    def view_template
      div(class: "flex items-start gap-4 border-l border-gaia-border pl-4 py-1") do
        div(class: "flex flex-col flex-1 font-mono text-tiny") do
          span(class: "text-gaia-text-subtle text-micro mb-1") { time_ago_text }
          span(class: tokens("leading-relaxed", event_color)) { event_summary }
        end
      end
    end

    private

    def event_summary
      case @event
      when EwsAlert then t(".threat", type: @event.alert_type, cluster: @event.cluster&.name || t(".unknown_cluster"))
      when BlockchainTransaction then blockchain_transaction_summary
      when MaintenanceRecord then t(".maintenance", action: @event.action_type&.capitalize, user: @event.user&.first_name || t(".system_user"))
      else t(".system_pulse")
      end
    end

    def event_color
      case @event
      when EwsAlert then "text-red-400"
      when BlockchainTransaction then "text-gaia-text"
      when MaintenanceRecord then "text-status-warning-text"
      else "text-gaia-text-subtle"
      end
    end

    def time_ago_text
      render Views::Shared::UI::RelativeTime.new(datetime: @event.created_at)
    end

    def blockchain_transaction_summary
      sourceable = @event.sourceable
      if sourceable.is_a?(ParametricInsurance) && sourceable.uses_etherisc?
        t(".etherisc_claim", amount: @event.amount, address: short_address(@event.to_address))
      else
        t(".minted", amount: @event.amount, target: @event.wallet&.tree&.did || t(".system_user"))
      end
    end

    def short_address(address)
      return t(".pool") unless address.present? && address.length > 10

      "#{address[0..5]}…#{address[-4..]}"
    end
  end
end
