# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# @label Action Badge
# @display bg_color "#000"
class ActionBadgePreview < Lookbook::Preview
  # @label All Action Types
  def all_types
    render_with_template(template: "action_badge_preview/all_types")
  end

  # @label Interactive
  # @param action text "Action token (e.g. user_role_changed, naas_contract_to_active, slash_verdict_burn)"
  def interactive(action: "user_role_changed")
    render Views::Shared::UI::ActionBadge.new(action: action)
  end
end
