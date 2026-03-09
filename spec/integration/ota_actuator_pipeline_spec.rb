# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OTA transmission and actuator command pipeline" do
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
  # OtaTransmissionWorker
  # ---------------------------------------------------------------------------
  describe "OtaTransmissionWorker" do
    let!(:firmware) { create(:bio_contract_firmware, version: "3.0.0", bytecode_payload: "AA" * 600) }

    let(:mock_response) { double("response", success?: true, code: "2.04") }

    before do
      allow(CoapClient).to receive(:put).and_return(mock_response)
    end

    it "transmits first chunk and schedules next" do
      expect(OtaTransmissionWorker).to receive(:perform_in).with(0.4.seconds, gateway.uid, "firmware", firmware.id, 1, 0)

      OtaTransmissionWorker.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)

      gateway.reload
      expect(gateway.state).to eq("updating")
    end

    it "completes OTA on last chunk" do
      # Small firmware that fits in one chunk
      small_fw = create(:bio_contract_firmware, version: "3.1.0", bytecode_payload: "BB" * 200)
      ota_data = OtaPackagerService.prepare(small_fw, chunk_size: 512)
      total = ota_data[:manifest][:total_chunks]

      # Simulate transmitting the last chunk (index = total - 1)
      OtaTransmissionWorker.new.perform(gateway.uid, "firmware", small_fw.id, total - 1, 0)

      gateway.reload
      expect(gateway.state).to eq("idle")
      expect(gateway.firmware_version).to eq("3.1.0")
    end

    it "handles TinyML model OTA" do
      model = create(:tiny_ml_model, version: "v5.0.0", binary_weights_payload: "CC" * 200)
      ota_data = OtaPackagerService.prepare(model, chunk_size: 512)
      total = ota_data[:manifest][:total_chunks]

      OtaTransmissionWorker.new.perform(gateway.uid, "tinyml", model.id, total - 1, 0)

      gateway.reload
      expect(gateway.state).to eq("idle")
      expect(gateway.firmware_version).to eq("v5.0.0")
    end

    it "retries with exponential backoff on CoAP failure" do
      allow(CoapClient).to receive(:put).and_raise(StandardError, "CoAP NACK")

      expect(OtaTransmissionWorker).to receive(:perform_in).with(15.seconds, gateway.uid, "firmware", firmware.id, 0, 1)

      OtaTransmissionWorker.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)
    end

    it "marks gateway faulty after max retries" do
      allow(CoapClient).to receive(:put).and_raise(StandardError, "CoAP NACK")

      OtaTransmissionWorker.new.perform(gateway.uid, "firmware", firmware.id, 0, 5)

      gateway.reload
      expect(gateway.state).to eq("faulty")
    end

    it "raises for unknown firmware type" do
      expect {
        OtaTransmissionWorker.new.perform(gateway.uid, "unknown_type", 1)
      }.to raise_error(ArgumentError, /Невідомий тип прошивки/)
    end
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

    let(:mock_response) { double("response", success?: true, code: "2.04") }

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
      expect(ResetActuatorStateWorker).to receive(:perform_in).with(60.seconds, command.id)
      ActuatorCommandWorker.new.perform(command.id)
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
      expect(CoapClient).not_to receive(:put)
      ActuatorCommandWorker.new.perform(command.id)
    end

    it "skips when command not found" do
      expect(CoapClient).not_to receive(:put)
      ActuatorCommandWorker.new.perform(-1)
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
