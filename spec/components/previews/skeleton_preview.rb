# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# @label Skeleton
# @display bg_color "#000"
class SkeletonPreview < Lookbook::Preview
  # @label Lines (Default)
  # @notes Bones only — the box comes from the owner's `PANEL`. The caller declares the height via `lines:`.
  # @param lines range { min: 1, max: 12, step: 1 }
  def default(lines: 3)
    render Views::Shared::UI::Skeleton.new(lines: lines.to_i)
  end

  # @label Balance
  # @notes Label, hero figure, value row, footnote — the shape of `Wallets::BalanceDisplay`.
  def balance
    render Views::Shared::UI::Skeleton.new(variant: :balance)
  end

  # @label In owner's panel
  # @notes How a page places it: inside the loaded component's own `PANEL`, so both states share one box.
  def in_panel
    render Views::Shared::UI::Skeleton.new(lines: 10, class: Wallets::MetadataFrame::PANEL)
  end
end
