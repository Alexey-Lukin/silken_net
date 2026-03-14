# frozen_string_literal: true

# @label Alert Badge
# @display bg_color "#000"
class AlertBadgePreview < Lookbook::Preview
  # @label All Severity × Status Combos
  def all_combos
    render_with_template(template: "alert_badge_preview/all_combos")
  end

  # @label Interactive
  # @param severity select { choices: [low, medium, critical] }
  # @param status select { choices: [active, resolved, ignored] }
  def interactive(severity: "critical", status: "active")
    alert = OpenStruct.new(id: 1, severity: severity, status: status)
    render Alerts::Badge.new(alert: alert)
  end
end
