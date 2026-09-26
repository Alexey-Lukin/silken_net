# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TimeSyncDownlinkWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) do
    create(:gateway,
           cluster: cluster,
           ip_address: "192.168.10.42",
           state: :idle,
           last_seen_at: 30.seconds.ago)
  end
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before do
    allow(CoapClient).to receive(:put).and_return(instance_double(CoapClient::Response, success?: true, code: "2.04"))
  end

  describe "sidekiq configuration" do
    it "is enqueued on the downlink queue with retry: 2" do
      expect(described_class.sidekiq_options).to include("queue" => "downlink", "retry" => 2)
    end
  end

  describe "#perform happy path" do
    it "sends a CMD_TIME_SYNC envelope to the best gateway's CoAP endpoint" do
      described_class.new.perform(cluster.id)

      expect(CoapClient).to have_received(:put).with(
        "coap://#{gateway.ip_address}/cmd/time_sync",
        kind_of(String)
      )
    end

    it "logs success including cluster id and gateway uid" do
      allow(Rails.logger).to receive(:info)
        .with(a_string_matching(/\[TimeSyncDownlink\] Cluster #{cluster.id}: time beacon queued via #{gateway.uid}/))

      described_class.new.perform(cluster.id)

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/\[TimeSyncDownlink\] Cluster #{cluster.id}: time beacon queued via #{gateway.uid}/))
    end

    it "selects the most recently-seen eligible gateway when several exist" do
      stale = create(:gateway,
                     cluster: cluster,
                     ip_address: "192.168.10.99",
                     state: :idle,
                     last_seen_at: 1.hour.ago)
      create(:hardware_key, device_uid: stale.uid)

      described_class.new.perform(cluster.id)

      expect(CoapClient).to have_received(:put).with(
        "coap://#{gateway.ip_address}/cmd/time_sync",
        anything
      )
    end

    # Ротований KEYC доїжджає до Королеви лише re-provision'ом, тож у її
    # grace-вікні конверт мусить бути під ПОПЕРЕДНІМ (HardwareKey#coap_binary_key).
    it "encrypts under the key the Queen still holds while her grace is open" do
      held_key = key_record.binary_key.dup
      key_record.update!(previous_aes_key_hex: key_record.aes_key_hex,
                         aes_key_hex: SecureRandom.hex(32).upcase)
      sent_payload = nil
      allow(CoapClient).to receive(:put) do |_url, payload|
        sent_payload = payload
        instance_double(CoapClient::Response, success?: true, code: "2.04")
      end

      described_class.new.perform(cluster.id)

      cipher = OpenSSL::Cipher.new("aes-256-cbc").decrypt
      cipher.key = held_key
      cipher.iv = sent_payload.byteslice(0, 16)
      cipher.padding = 0
      plain = cipher.update(sent_payload.byteslice(16..)) + cipher.final
      # [0x9C][ts:4] + 11 нульових байтів доповнення: чужий ключ дав би сміття
      expect(plain.getbyte(0)).to eq(0x9C)
      expect(plain.byteslice(5..)).to eq("\x00".b * 11)
    end
  end

  describe "#perform — gateway selection short-circuits" do
    it "returns nil and skips CoAP when no gateway in the cluster" do
      empty_cluster = create(:cluster, organization: organization)

      expect(described_class.new.perform(empty_cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end

    it "skips gateways with nil ip_address" do
      gateway.update_column(:ip_address, nil)

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end

    it "skips gateways with empty-string ip_address" do
      gateway.update_column(:ip_address, "")

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end

    it "skips gateways in maintenance state" do
      gateway.update_column(:state, "maintenance")

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end

    it "skips gateways in faulty state" do
      gateway.update_column(:state, "faulty")

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end
  end

  describe "#perform — hardware key short-circuits" do
    it "returns nil when no HardwareKey exists for the gateway" do
      key_record.destroy!

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end

    it "returns nil when binary_key is blank" do
      allow(HardwareKey).to receive(:find_by).with(device_uid: gateway.uid).and_return(
        instance_double(HardwareKey, binary_key: nil)
      )

      expect(described_class.new.perform(cluster.id)).to be_nil
      expect(CoapClient).not_to have_received(:put)
    end
  end

  describe "#perform — CoAP timeout" do
    it "logs a warning and re-raises so Sidekiq can retry" do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      allow(Rails.logger).to receive(:warn)
        .with(a_string_matching(/\[TimeSyncDownlink\] Cluster #{cluster.id}: #{gateway.uid} timeout/))

      expect { described_class.new.perform(cluster.id) }.to raise_error(Timeout::Error)

      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/\[TimeSyncDownlink\] Cluster #{cluster.id}: #{gateway.uid} timeout/))
    end
  end

  describe "sidekiq_retries_exhausted (FW.60 — слід замість тихого DeadSet)" do
    it "logs the dead job loudly (Королева синкнеться наступним poll'ом)" do
      allow(Rails.logger).to receive(:error).with(a_string_matching(/TimeSyncDownlink.*помер/))

      described_class.sidekiq_retries_exhausted_block.call(
        { "args" => [ 42 ], "error_message" => "Timeout::Error" }, StandardError.new
      )

      expect(Rails.logger).to have_received(:error).with(a_string_matching(/TimeSyncDownlink.*помер/))
    end

    it "is nil-safe on a malformed job payload" do
      expect {
        described_class.sidekiq_retries_exhausted_block.call({ "args" => nil }, StandardError.new)
      }.not_to raise_error
    end
  end
end
