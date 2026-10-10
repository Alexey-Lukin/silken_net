# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Actuator command pipeline" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # ---------------------------------------------------------------------------
  # ActuatorCommandWorker
  # ---------------------------------------------------------------------------
  describe "ActuatorCommandWorker" do
    let!(:actuator) { create(:actuator, gateway: gateway) }
    let!(:command) do
      create(:actuator_command, :with_ttl,
             actuator: actuator,
             command_payload: "OPEN",
             duration_seconds: 60,
             status: :issued)
    end

    let(:mock_response) { instance_double(CoapClient::Response, success?: true, code: "2.04") }

    before do
      allow(CoapClient).to receive(:put).and_return(mock_response)
      allow(ResetActuatorStateWorker).to receive(:perform_in)
    end

    it "sends command via CoAP and acknowledges" do
      ActuatorCommandWorker.new.perform(command.id)

      command.reload
      expect(command.status).to eq("acknowledged")
      expect(command.sent_at).to be_present
      expect(actuator.reload.state).to eq("active")
    end

    it "schedules reset worker after command duration" do
      ActuatorCommandWorker.new.perform(command.id)

      expect(ResetActuatorStateWorker).to have_received(:perform_in).with(60.seconds, command.id)
    end

    it "fails expired commands" do
      command.update_columns(expires_at: 1.minute.ago)

      ActuatorCommandWorker.new.perform(command.id)
      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("протермінована")
    end

    it "fails when gateway has no IP" do
      gateway.update_columns(ip_address: nil)

      ActuatorCommandWorker.new.perform(command.id)
      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("не має IP")
    end

    it "fails when hardware key missing" do
      key_record.destroy!

      ActuatorCommandWorker.new.perform(command.id)
      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("Ключ")
    end

    it "raises when gateway is updating (for Sidekiq retry)" do
      gateway.update!(state: :updating)

      expect {
        ActuatorCommandWorker.new.perform(command.id)
      }.to raise_error(RuntimeError, /Gateway Busy/)
    end

    it "skips already acknowledged commands" do
      command.update!(status: :acknowledged)
      ActuatorCommandWorker.new.perform(command.id)

      expect(CoapClient).not_to have_received(:put)
    end

    it "skips when command not found" do
      ActuatorCommandWorker.new.perform(-1)

      expect(CoapClient).not_to have_received(:put)
    end

    it "uses explicit key when provided" do
      explicit_hex = SecureRandom.hex(32)
      ActuatorCommandWorker.new.perform(command.id, explicit_hex)

      command.reload
      expect(command.status).to eq("acknowledged")
    end

    it "uses previous key during grace period" do
      key_record.update!(previous_aes_key_hex: SecureRandom.hex(32).upcase)

      ActuatorCommandWorker.new.perform(command.id)
      command.reload
      expect(command.status).to eq("acknowledged")
    end
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
