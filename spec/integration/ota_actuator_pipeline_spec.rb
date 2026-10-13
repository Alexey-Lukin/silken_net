# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Actuator command pipeline" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # ---------------------------------------------------------------------------
  # ResetActuatorStateWorker
  # ---------------------------------------------------------------------------
  describe "ResetActuatorStateWorker" do
    let!(:actuator) { create(:actuator, gateway: gateway, state: :active) }
    let!(:command) do
      cmd = create(:actuator_command,
             actuator: actuator,
             status: :issued,
             duration_seconds: 60)
      # Bypass dispatch callback and set to acknowledged directly
      cmd.update_columns(status: ActuatorCommand.statuses[:acknowledged], sent_at: Time.current)
      cmd
    end

    it "resets active actuator to idle and confirms command" do
      ResetActuatorStateWorker.new.perform(command.id)

      actuator.reload
      expect(actuator.state).to eq("idle")

      command.reload
      expect(command.status).to eq("confirmed")
      expect(command.completed_at).to be_present
    end

    it "confirms acknowledged command when actuator not active" do
      actuator.update!(state: :maintenance_needed)

      ResetActuatorStateWorker.new.perform(command.id)
      command.reload
      expect(command.status).to eq("confirmed")
    end

    it "does not crash for non-existent command" do
      expect {
        ResetActuatorStateWorker.new.perform(-1)
      }.not_to raise_error
    end
  end
end
