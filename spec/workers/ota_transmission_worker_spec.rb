# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaTransmissionWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }
  let(:firmware) { create(:bio_contract_firmware, :active, version: "2.0.0", bytecode_payload: "A" * 2048) }

  let(:ota_packages) do
    {
      packages: [ "chunk0data_padded!!", "chunk1data_padded!!", "chunk2data_padded!!" ],
      manifest: { total_chunks: 3, version: firmware.version }
    }
  end

  before do
    key_record # Ensure key exists
    allow(OtaPackagerService).to receive(:prepare).and_return(ota_packages)
    allow(CoapClient).to receive(:put).and_return(double(success?: true, code: "2.04"))
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when first chunk (chunk_index=0)" do
      it "sets gateway state to updating" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)

        gateway.reload
        expect(gateway.state).to eq("updating")
      end

      it "sends encrypted chunk via CoAP" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)

        expect(CoapClient).to have_received(:put).with(
          /coap:\/\/#{gateway.ip_address}\/ota\/firmware/,
          anything
        )
      end

      it "schedules next chunk" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)

        expect(described_class.jobs.size).to eq(1)
        args = described_class.jobs.first["args"]
        expect(args[3]).to eq(1) # next chunk_index
      end
    end

    context "when last chunk" do
      it "sets gateway state to idle and updates firmware version" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 2, 0)

        gateway.reload
        expect(gateway.state).to eq("idle")
        expect(gateway.firmware_version).to eq("2.0.0")
      end

      it "broadcasts COMPLETE status" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 2, 0)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
          .with("ota_channel_#{gateway.uid}", hash_including(target: "ota_progress_#{gateway.uid}"))
          .at_least(:once)
      end

      it "does not schedule more chunks" do
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 2, 0)

        expect(described_class.jobs).to be_empty
      end
    end

    context "when firmware type routing" do
      it "handles mruby firmware type" do
        described_class.new.perform(gateway.uid, "mruby", firmware.id, 0, 0)

        expect(CoapClient).to have_received(:put)
      end

      it "handles tinyml type" do
        ml_model = create(:tiny_ml_model, :active, binary_weights_payload: "X" * 1024)
        allow(OtaPackagerService).to receive(:prepare).and_return(ota_packages)

        described_class.new.perform(gateway.uid, "tinyml", ml_model.id, 0, 0)

        expect(CoapClient).to have_received(:put)
      end

      it "raises for unknown firmware type" do
        expect {
          described_class.new.perform(gateway.uid, "unknown_type", firmware.id, 0, 0)
        }.to raise_error(ArgumentError, /Невідомий тип прошивки/)
      end
    end

    context "when chunk failure handling" do
      it "retries on CoAP failure" do
        allow(CoapClient).to receive(:put).and_raise(Timeout::Error)

        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)

        # Повинен запланувати ретрай з інкрементованим retry_count
        expect(described_class.jobs.size).to eq(1)
        args = described_class.jobs.first["args"]
        expect(args[3]).to eq(0) # same chunk_index
        expect(args[4]).to eq(1) # incremented retry_count
      end

      it "marks gateway as faulty after max retries" do
        allow(CoapClient).to receive(:put).and_raise(StandardError, "NACK")

        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, OtaTransmissionWorker::MAX_CHUNK_RETRIES)

        gateway.reload
        expect(gateway.state).to eq("faulty")
      end
    end

    it "raises RecordNotFound for unknown gateway" do
      expect {
        described_class.new.perform("SNET-Q-FFFFFFFF", "firmware", firmware.id, 0, 0)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound for missing hardware key" do
      key_record.destroy!

      expect {
        described_class.new.perform(gateway.uid, "firmware", firmware.id, 0, 0)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
