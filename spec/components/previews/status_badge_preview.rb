# frozen_string_literal: true

# @label Status Badge
# @display bg_color "#000"
class StatusBadgePreview < Lookbook::Preview
  # @label All AASM States
  # @notes Shows every predefined status badge variant mapped to semantic color tokens.
  def all_states
    render_with_template(template: "status_badge_preview/all_states")
  end

  # @label Transaction States
  def transaction_states
    render_with_template(template: "status_badge_preview/transaction_states")
  end

  # @label Interactive
  # @param status select { choices: [pending, processing, sent, confirmed, failed, issued, acknowledged, active, resolved, ignored, triggered, paid, expired, draft, fulfilled, breached, cancelled, idle, updating, maintenance, faulty, dormant, removed, deceased, offline, maintenance_needed] }
  def interactive(status: "pending")
    render Views::Shared::UI::StatusBadge.new(status: status)
  end
end
