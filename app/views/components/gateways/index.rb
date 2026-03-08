# frozen_string_literal: true

module Gateways
  class Index < ApplicationComponent
    def initialize(gateways:, pagy:)
      @gateways = gateways
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @gateways.each do |gateway|
            render Gateways::Item.new(gateway: gateway)
          end
        end

        render Shared::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_gateways_path(page: page) }
        )
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end mb-6") do
        div do
          h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "Queen Registry // Global Relays" }
          p(class: "text-xs text-gray-600 mt-1") { "Monitoring neural synapses of the forest network." }
        end

        div(class: "text-right font-mono text-[10px] text-emerald-900") do
          online_count = @gateways.count { |g| g.last_seen_at&. > 5.minutes.ago }
          plain "Nodes Online: "
          span(class: "text-emerald-500") { "#{online_count} / #{@gateways.count}" }
        end
      end
    end
  end
end
