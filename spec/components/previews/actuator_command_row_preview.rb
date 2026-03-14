# frozen_string_literal: true

# @label Actuator Command Row
# @display bg_color "#000"
class ActuatorCommandRowPreview < Lookbook::Preview
  # @label Open Command (Confirmed)
  # @notes Shows a confirmed OPEN command for a water valve.
  def confirmed_open
    command = mock_command(payload: "OPEN:60", status: "confirmed")
    render Actuators::CommandRow.new(command: command)
  end

  # @label Activate Command (Issued)
  # @notes Shows a recently issued ACTIVATE command awaiting execution.
  def issued_activate
    command = mock_command(payload: "ACTIVATE:120", status: "issued")
    render Actuators::CommandRow.new(command: command)
  end

  # @label Failed Command
  # @notes Shows a failed CLOSE command with red status.
  def failed_close
    command = mock_command(payload: "CLOSE:0", status: "failed")
    render Actuators::CommandRow.new(command: command)
  end

  # @label Interactive
  # @param payload text "Command payload string"
  # @param status select { choices: [issued, sent, acknowledged, confirmed, failed] }
  def interactive(payload: "OPEN:30", status: "issued")
    command = mock_command(payload: payload, status: status)
    render Actuators::CommandRow.new(command: command)
  end

  private

  def mock_command(payload:, status:)
    OpenStruct.new(
      id: 1,
      command_payload: payload,
      status: status,
      created_at: 5.minutes.ago
    )
  end
end
