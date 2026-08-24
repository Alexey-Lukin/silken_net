# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorCommandWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "192.168.1.100") }
  let(:actuator) { create(:actuator, gateway: gateway) }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  # Пригнічуємо after_commit :dispatch_to_edge!, щоб не тригерити Phlex-компоненти
  let(:command) do
    allow_any_instance_of(ActuatorCommand).to receive(:dispatch_to_edge!)
    cmd = create(:actuator_command, actuator: actuator, expires_at: 30.minutes.from_now)
    cmd.update_column(:status, :issued)
    cmd
  end

  before do
    key_record # Ensure key exists
    allow(CoapClient).to receive(:put).and_return(instance_double(CoapClient::Response, success?: true, code: "2.04"))
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "sends encrypted command to gateway via CoAP and acknowledges" do
      described_class.new.perform(command.id)

      command.reload
      expect(command.status).to eq("acknowledged")
      expect(command.sent_at).to be_present
      expect(CoapClient).to have_received(:put).with(
        "coap://#{gateway.ip_address}/actuator/#{actuator.endpoint}",
        anything
      )
    end

    it "schedules ResetActuatorStateWorker after acknowledgement" do
      described_class.new.perform(command.id)

      expect(ResetActuatorStateWorker.jobs.size).to eq(1)
    end

    it "marks actuator as active after successful delivery" do
      described_class.new.perform(command.id)

      actuator.reload
      expect(actuator.state).to eq("active")
    end

    it "returns nil for non-existent command" do
      expect(described_class.new.perform(-1)).to be_nil
    end

    it "skips already acknowledged commands" do
      command.update_column(:status, :acknowledged)

      described_class.new.perform(command.id)
      expect(CoapClient).not_to have_received(:put)
    end

    it "re-delivers a :sent command on retry without re-raising dispatch (may_dispatch? guard)" do
      command.update_column(:status, :sent)

      expect { described_class.new.perform(command.id) }.not_to raise_error

      command.reload
      expect(command.status).to eq("acknowledged")
      # re-PUT happens; the Queen dedupes by idempotency_token, so it is safe
      expect(CoapClient).to have_received(:put)
    end

    it "fails expired commands" do
      command.update_column(:expires_at, 1.minute.ago)

      described_class.new.perform(command.id)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("протермінована")
    end

    it "fails when gateway has no IP address" do
      gateway.update_column(:ip_address, nil)

      described_class.new.perform(command.id)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("не має IP")
    end

    it "raises when gateway is updating (for Sidekiq retry)" do
      gateway.update_column(:state, :updating)

      expect { described_class.new.perform(command.id) }.to raise_error("Gateway Busy: Updating")
    end

    it "fails when hardware key is missing" do
      key_record.destroy!

      described_class.new.perform(command.id)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("Ключ")
    end

    it "uses explicit_key when provided" do
      explicit_hex = SecureRandom.hex(32)

      described_class.new.perform(command.id, explicit_hex)

      command.reload
      expect(command.status).to eq("acknowledged")
    end

    it "uses previous key when in grace period" do
      key_record.update!(previous_aes_key_hex: SecureRandom.hex(32).upcase)

      described_class.new.perform(command.id)

      command.reload
      expect(command.status).to eq("acknowledged")
    end

    it "raises on CoAP timeout for Sidekiq retry" do
      allow(CoapClient).to receive(:put).and_raise(Timeout::Error)

      expect { described_class.new.perform(command.id) }.to raise_error(Timeout::Error)
    end

    it "raises on CoAP failure response for Sidekiq retry" do
      allow(CoapClient).to receive(:put).and_return(instance_double(CoapClient::Response, success?: false, code: "4.04"))

      expect { described_class.new.perform(command.id) }.to raise_error(RuntimeError, /Королева відхилила/)
    end

    it "encrypts payload with AES-256-CBC and prepends IV" do
      encrypted = nil
      allow(CoapClient).to receive(:put) do |_url, payload|
        encrypted = payload
        instance_double(CoapClient::Response, success?: true, code: "2.04")
      end

      described_class.new.perform(command.id)

      # Encrypted payload must contain IV (16 bytes) + at least one AES block (16 bytes)
      expect(encrypted.bytesize).to be >= 32
      expect(encrypted.bytesize % 16).to eq(0) # IV (16) + N*16 ciphertext

      # Extract IV and ciphertext, decrypt, verify round-trip
      iv = encrypted[0, 16]
      ciphertext = encrypted[16..]

      binary_key = key_record.binary_previous_key || key_record.binary_key
      decipher = OpenSSL::Cipher.new("aes-256-cbc")
      decipher.decrypt
      decipher.key = binary_key
      decipher.iv = iv
      decipher.padding = 0

      plaintext = decipher.update(ciphertext) + decipher.final
      # FW.20: payload is wrapped as [0x9C][unix_ts_be:4][inner], inner starts with "CMD:"
      expect(plaintext.bytes.first).to eq(0x9C)
      inner = plaintext.byteslice(5..)
      expect(inner).to start_with("CMD:")
      expect(inner).to include(command.idempotency_token)
    end
  end

  describe ".sidekiq_retries_exhausted" do
    it "marks command as failed after all retries" do
      job = { "args" => [ command.id ], "error_message" => "Permanent failure" }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("Permanent failure")
    end
  end

  describe "sidekiq_retries_exhausted when command is nil (not found)" do
    it "does nothing when command not found" do
      job = { "args" => [ -999 ], "error_message" => "some error" }
      expect {
        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new("test"))
      }.not_to raise_error
    end
  end

  describe "sidekiq_retries_exhausted when AASM transition is not allowed" do
    it "skips broadcast when may_fail? returns false" do
      allow(ActuatorCommand).to receive(:find_by).with(id: command.id).and_return(command)
      allow(command).to receive(:may_fail?).and_return(false)

      job = { "args" => [ command.id ], "error_message" => "some error" }
      allow(described_class).to receive(:broadcast_command_state_static)
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new("test"))

      expect(described_class).not_to have_received(:broadcast_command_state_static)
    end
  end

  describe "broadcast_command_state_static when org is nil" do
    it "returns nil when organization chain resolves to nil" do
      command.update_columns(organization_id: nil)
      command.reload

      allow(command.actuator.gateway.cluster).to receive(:organization).and_return(nil)
      result = described_class.broadcast_command_state_static(command)
      expect(result).to be_nil
    end
  end

  # =========================================================================
  # AASM TRANSITION (dispatch!)
  # =========================================================================
  describe "dispatch! AASM transition" do
    it "transitions command to sent state before CoAP send" do
      states = []
      allow(CoapClient).to receive(:put) do |_url, _payload|
        cmd = ActuatorCommand.find(command.id)
        states << cmd.status
        instance_double(CoapClient::Response, success?: true, code: "2.04")
      end

      described_class.new.perform(command.id)

      expect(states).to include("sent")
    end
  end

  # =========================================================================
  # ACTUATOR MARK_ACTIVE! TRANSITION
  # =========================================================================
  describe "actuator.mark_active!" do
    it "sets actuator state to active after acknowledgement" do
      expect(actuator.state).to eq("idle")

      described_class.new.perform(command.id)

      actuator.reload
      expect(actuator.state).to eq("active")
    end
  end

  # =========================================================================
  # FULL ENCRYPTION ROUNDTRIP
  # =========================================================================
  describe "encryption roundtrip" do
    it "[FW.20] wraps payload with CMD_TIME_SYNC envelope; inner CMD: payload survives roundtrip" do
      captured_payload = nil
      allow(CoapClient).to receive(:put) do |_url, payload|
        captured_payload = payload
        instance_double(CoapClient::Response, success?: true, code: "2.04")
      end

      before_ts = Time.now.utc.to_i
      described_class.new.perform(command.id)
      after_ts = Time.now.utc.to_i

      # Decrypt the captured payload
      iv = captured_payload[0, 16]
      ciphertext = captured_payload[16..]
      binary_key = key_record.binary_previous_key || key_record.binary_key

      decipher = OpenSSL::Cipher.new("aes-256-cbc")
      decipher.decrypt
      decipher.key = binary_key
      decipher.iv = iv
      decipher.padding = 0
      plaintext = decipher.update(ciphertext) + decipher.final

      # [FW.20] Plaintext = [0x9C][ts:4][CMD:...][zero-padding]
      expect(plaintext.bytes.first).to eq(CoapEncryption::CMD_TIME_SYNC)
      ts = plaintext.byteslice(1, 4).unpack1("N")
      expect(ts).to be_between(before_ts, after_ts)

      inner = plaintext.byteslice(CoapEncryption::TIME_SYNC_HEADER_SIZE..)
      expect(inner).to start_with("CMD:")
      expect(inner).to include(command.command_payload)
      expect(inner).to include(command.duration_seconds.to_s)
      expect(inner).to include(command.idempotency_token)
    end
  end

  # =========================================================================
  # RESET ACTUATOR STATE WORKER SCHEDULING
  # =========================================================================
  describe "ResetActuatorStateWorker scheduling" do
    it "schedules reset for the command duration" do
      described_class.new.perform(command.id)

      job = ResetActuatorStateWorker.jobs.last
      expect(job["args"]).to eq([ command.id ])
    end
  end

  # =========================================================================
  # SIDEKIQ OPTIONS
  # =========================================================================
  describe "sidekiq configuration" do
    it "uses downlink queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("downlink")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end

  describe "perform — nil response from CoAP" do
    it "raises when response is nil" do
      allow(CoapClient).to receive(:put).and_return(nil)
      allow(ResetActuatorStateWorker).to receive(:perform_in)

      expect {
        described_class.new.perform(command.id)
      }.to raise_error(RuntimeError, /Королева відхилила/)
    end
  end

  describe "perform — response with code but not success" do
    it "raises with the response code in the message" do
      response = instance_double(CoapClient::Response, success?: false, code: "5.00")
      allow(CoapClient).to receive(:put).and_return(response)
      allow(ResetActuatorStateWorker).to receive(:perform_in)

      expect {
        described_class.new.perform(command.id)
      }.to raise_error(RuntimeError, /5\.00/)
    end
  end
end
