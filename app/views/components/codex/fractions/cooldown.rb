# frozen_string_literal: true

# Codex::Fractions::Cooldown — tiny status pill showing the unlock window.
module Codex
  module Fractions
    class Cooldown < ApplicationComponent
      def initialize(fraction:)
        @fraction = fraction
      end

      def view_template
        return render_open unless @fraction&.cooldown_active?

        span(
          class: tokens(
            "inline-flex items-center gap-1 px-2 py-0.5 border",
            "bg-status-warning text-status-warning-text border-status-warning",
            "text-mini uppercase tracking-[0.2em] font-mono"
          ),
          title: t(".title", timestamp: @fraction.cooldown_until.iso8601)
        ) do
          span { t(".locked") }
          span { "·" }
          span { format_remaining(@fraction.seconds_until_unlocked) }
        end
      end

      private

      def render_open
        span(
          class: tokens(
            "inline-flex items-center gap-1 px-2 py-0.5 border",
            "bg-status-success text-status-success-text border-status-success",
            "text-mini uppercase tracking-[0.2em] font-mono"
          )
        ) { t(".open") }
      end

      def format_remaining(seconds)
        return "0s" if seconds <= 0

        days  = seconds / 86_400
        hours = (seconds % 86_400) / 3600
        return "#{days}d#{hours}h" if days.positive?

        minutes = (seconds % 3600) / 60
        "#{hours}h#{minutes}m"
      end
    end
  end
end
