# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.17] Доставка CMD_ROTATE_KEY (0x9E) через Queen кластера. Сам ключ в
# ефір не їде — кадр несе лише target_version (канон 03_05 §3.8).
RSpec.describe KeyRotationDownlinkWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let!(:gateway) do
    create(:gateway,
           cluster: cluster,
           ip_address: "192.168.10.42",
           state: :idle,
           last_seen_at: 30.seconds.ago)
  end
  let!(:gateway_key) { create(:hardware_key, device_uid: gateway.uid) }

  before do
    allow(CoapClient).to receive(:put).and_return(double(success?: true, code: "2.04"))
    allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(true)
  end

  describe "sidekiq configuration" do
    it "is enqueued on the downlink queue with retry: 2" do
      expect(described_class.sidekiq_options).to include("queue" => "downlink", "retry" => 2)
    end
  end

  describe "#perform happy path" do
    it "encrypts the 0x9E block with the gateway CoAP key and PUTs to /cmd/rotate_key" do
      described_class.new.perform(tree.did, 3)

      expect(CoapClient).to have_received(:put).with(
        "coap://#{gateway.ip_address}/cmd/rotate_key",
        kind_of(String)
      )
    end

    it "carries the freeze-contract 0x9E frame inside the encrypted envelope" do
      sent_payload = nil
      allow(CoapClient).to receive(:put) do |_url, payload|
        sent_payload = payload
        double(success?: true, code: "2.04")
      end

      described_class.new.perform(tree.did, 3)

      # Розшифровуємо так, як це зробить Queen: [IV:16][CBC(0x9C envelope + frame)]
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = gateway_key.binary_key
      cipher.iv = sent_payload.byteslice(0, 16)
      cipher.padding = 0
      plain = cipher.update(sent_payload.byteslice(16..)) + cipher.final

      # Після 5-байтного 0x9C time-sync envelope — golden-кадр 9E 0400 0300 5C48
      expect(plain.bytes[0]).to eq(0x9C)
      expect(plain.byteslice(5, 7)).to eq(
        OtaPackagerService.build_rotate_key_block(3)
      )
    end
  end

  describe "#perform guards" do
    it "refuses dispatch while the FW17 gate is closed (defense-in-depth)" do
      allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(false)

      described_class.new.perform(tree.did, 3)

      expect(CoapClient).not_to have_received(:put)
    end

    it "no-ops when the tree is unknown" do
      described_class.new.perform("SNET-00000000", 3)

      expect(CoapClient).not_to have_received(:put)
    end

    it "no-ops when the gateway has no HardwareKey (nil key_record)" do
      gateway_key.destroy!

      described_class.new.perform(tree.did, 3)

      expect(CoapClient).not_to have_received(:put)
    end

    it "raises (for Sidekiq retry) when the cluster has no eligible gateway" do
      gateway.update!(state: :faulty)

      expect {
        described_class.new.perform(tree.did, 3)
      }.to raise_error(/No eligible gateway/)
    end

    it "logs and re-raises (for Sidekiq retry) when the CoAP PUT times out" do
      allow(CoapClient).to receive(:put).and_raise(Timeout::Error)

      expect {
        described_class.new.perform(tree.did, 3)
      }.to raise_error(Timeout::Error)
    end
  end

  describe "sidekiq_retries_exhausted (FW.60 — key_version уже бампнутий, кадр не доставлений)" do
    it "logs loudly and names the Grace-derivation recovery path" do
      allow(Rails.logger).to receive(:error)
        .with(a_string_matching(/KeyRotationDownlink.*помер.*poll-derivation/))

      described_class.sidekiq_retries_exhausted_block.call(
        { "args" => [ "SNET-00000001", 3 ], "error_message" => "boom" }, StandardError.new
      )

      expect(Rails.logger).to have_received(:error)
        .with(a_string_matching(/KeyRotationDownlink.*помер.*poll-derivation/))
    end

    it "is nil-safe on a malformed job payload" do
      expect {
        described_class.sidekiq_retries_exhausted_block.call({ "args" => nil }, StandardError.new)
      }.not_to raise_error
    end
  end
end
