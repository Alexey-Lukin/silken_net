# frozen_string_literal: true

# @label Action Badge
# @display bg_color "#000"
class ActionBadgePreview < Lookbook::Preview
  # @label All Action Types
  def all_types
    render_with_template(template: "action_badge_preview/all_types")
  end

  # @label Interactive
  # @param action text "Action name (e.g. create_user, delete_tree, update_firmware, login)"
  def interactive(action: "create_node")
    render Views::Shared::UI::ActionBadge.new(action: action)
  end
end
