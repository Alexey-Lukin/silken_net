# frozen_string_literal: true

# @label Meta Row
# @display bg_color "#000"
class MetaRowPreview < Lookbook::Preview
  # @label Default
  def default
    render Views::Shared::UI::MetaRow.new(label: "Firmware Version", value: "v2.1.3-ocean")
  end

  # @label Numeric Value
  def numeric
    render Views::Shared::UI::MetaRow.new(label: "Battery Charge", value: 87)
  end

  # @label Interactive
  # @param label text
  # @param value text
  def interactive(label: "Key", value: "Value")
    render Views::Shared::UI::MetaRow.new(label: label, value: value)
  end
end
