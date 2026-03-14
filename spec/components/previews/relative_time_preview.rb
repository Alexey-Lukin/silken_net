# frozen_string_literal: true

# @label Relative Time
class RelativeTimePreview < Lookbook::Preview
  # @label Recent
  # @notes Shows relative time for a recent timestamp.
  def recent
    render Views::Shared::UI::RelativeTime.new(datetime: 5.minutes.ago)
  end

  # @label With Prefix
  # @notes Displays prefix text before relative time.
  def with_prefix
    render Views::Shared::UI::RelativeTime.new(datetime: 2.hours.ago, prefix: "Active ")
  end

  # @label Nil Datetime
  # @notes Gracefully renders a dash when datetime is nil.
  def nil_datetime
    render Views::Shared::UI::RelativeTime.new(datetime: nil)
  end
end
