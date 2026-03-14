# frozen_string_literal: true

# @label Empty State
# @display bg_color "#000"
class EmptyStatePreview < Lookbook::Preview
  # @label Default (Grid Mode)
  def default
    render Views::Shared::UI::EmptyState.new(title: "No records found", description: "Try adjusting your filters or search criteria.")
  end

  # @label Custom Icon
  def custom_icon
    render Views::Shared::UI::EmptyState.new(title: "Sensor is silent", description: "Check hardware connections.", icon: "⚙")
  end

  # @label Minimal
  def minimal
    render Views::Shared::UI::EmptyState.new(title: "Nothing here yet")
  end
end
