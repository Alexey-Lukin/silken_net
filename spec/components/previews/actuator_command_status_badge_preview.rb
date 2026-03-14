# frozen_string_literal: true

# @label Actuator Command Status Badge
# @display bg_color "#000"
class ActuatorCommandStatusBadgePreview < Lookbook::Preview
  # @label All Command Statuses
  # @notes Renders every predefined command status variant.
  def all_statuses
    render_with_template(template: "actuator_command_status_badge_preview/all_statuses")
  end

  # @label Interactive
  # @param status select { choices: [issued, sent, acknowledged, confirmed, failed] }
  def interactive(status: "issued")
    command = OpenStruct.new(id: 1, status: status)
    render Actuators::CommandStatusBadge.new(command: command)
  end
end
