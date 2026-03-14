# frozen_string_literal: true

# @label Stat Card
# @display bg_color "#000"
class StatCardPreview < Lookbook::Preview
  # @label Default
  def default
    render Views::Shared::UI::StatCard.new(label: "Active Trees", value: "12,847", sub: "nodes")
  end

  # @label Danger Mode
  # @notes Red highlight for critical metrics (e.g. unresolved alerts)
  def danger
    render Views::Shared::UI::StatCard.new(label: "Threat Alerts", value: "3", sub: "unresolved", danger: true)
  end

  # @label Without Subtitle
  def minimal
    render Views::Shared::UI::StatCard.new(label: "Gateways Online", value: "24")
  end

  # @label Interactive
  # @param label text
  # @param value text
  # @param sub text
  # @param danger toggle
  def interactive(label: "Metric", value: "42", sub: "", danger: false)
    render Views::Shared::UI::StatCard.new(label: label, value: value, sub: sub.presence, danger: danger)
  end
end
