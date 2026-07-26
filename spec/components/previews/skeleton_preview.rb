# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# @label Skeleton
# @display bg_color "#000"
class SkeletonPreview < Lookbook::Preview
  # @label Balance (Default)
  # @notes Default skeleton variant for balance/wallet displays. Shows label, value, and subtitle lines.
  def default
    render Views::Shared::UI::Skeleton.new
  end

  # @label Text
  # @notes Single full-width line for inline text placeholders.
  def text
    render Views::Shared::UI::Skeleton.new(variant: :text)
  end

  # @label Card
  # @notes Three lines mimicking a card layout with heading, body, and metadata.
  def card
    render Views::Shared::UI::Skeleton.new(variant: :card)
  end

  # @label Stats
  # @notes Stat card skeleton with label, large value, and small subtitle.
  def stats
    render Views::Shared::UI::Skeleton.new(variant: :stats)
  end

  # @label Table
  # @notes Four full-width rows simulating a data table loading state.
  def table
    render Views::Shared::UI::Skeleton.new(variant: :table)
  end

  # @label Map
  # @notes Tall placeholder for map widgets with header and footer lines.
  def map
    render Views::Shared::UI::Skeleton.new(variant: :map)
  end

  # @label Custom Lines
  # @notes Override with a specific number of skeleton lines.
  # @param lines range { min: 1, max: 10, step: 1 }
  def custom_lines(lines: 5)
    render Views::Shared::UI::Skeleton.new(lines: lines.to_i)
  end

  # @label Interactive
  # @notes Pick any variant interactively.
  # @param variant select { choices: [balance, text, card, stats, table, map] }
  def interactive(variant: "balance")
    render Views::Shared::UI::Skeleton.new(variant: variant.to_sym)
  end
end
