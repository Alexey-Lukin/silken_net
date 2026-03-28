# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuroEarthPassportWorker, type: :worker do
  let(:fake_tx_hash) { "0x#{"fa" * 32}" }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)

    # Stub PuroEarth::PassportService to return a realistic on-chain tx_hash
    allow_any_instance_of(PuroEarth::PassportService).to receive(:anchor!).and_return(fake_tx_hash)
    allow(BlockchainConfirmationWorker).to receive(:perform_in)
  end

  describe "#perform" do
    context "when record is a biomass_extraction on a Tree" do
      it "generates a biomass passport tx_hash" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)

        described_class.new.perform(record.id)

        record.reload
        expect(record.biomass_passport_tx_hash).to be_present
        expect(record.biomass_passport_tx_hash).to start_with("0x")
        expect(record.biomass_passport_tx_hash.length).to eq(66) # "0x" + 64 hex chars
      end

      it "delegates to PuroEarth::PassportService for on-chain anchoring" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)

        expect_any_instance_of(PuroEarth::PassportService).to receive(:anchor!)

        described_class.new.perform(record.id)
      end

      it "schedules BlockchainConfirmationWorker for tx tracking" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)

        described_class.new.perform(record.id)

        expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash)
      end

      it "returns the D-MRV passport payload with correct fields" do
        tree = create(:tree, status: :deceased, latitude: 49.4285, longitude: 32.0620)
        record = create(:maintenance_record, :biomass_extraction, :with_gps, maintainable: tree)

        payload = described_class.new.perform(record.id)

        expect(payload[:tree_did]).to eq(tree.did)
        expect(payload[:biomass_yield_kg]).to eq(record.biomass_yield_kg.to_f)
        expect(payload[:extraction_date]).to eq(record.performed_at.iso8601)
        expect(payload[:gps_coordinates][:latitude]).to be_a(Float)
        expect(payload[:gps_coordinates][:longitude]).to be_a(Float)
        expect(payload[:lifetime_telemetry_hash]).to be_present
      end

      it "logs success message" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)

        expect(Rails.logger).to receive(:info).with(a_string_matching(/Biomass Passport for Puro\.earth generated/))

        described_class.new.perform(record.id)
      end
    end

    context "when maintainable is not a Tree" do
      it "skips processing and logs a warning" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :inspection)

        expect(Rails.logger).to receive(:warn).with(a_string_matching(/not a Tree/))

        described_class.new.perform(record.id)

        record.reload
        expect(record.biomass_passport_tx_hash).to be_nil
      end
    end

    it "raises RecordNotFound for missing record" do
      expect { described_class.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when record has nil coordinates" do
      it "falls back to tree coordinates" do
        tree = create(:tree, status: :deceased, latitude: 49.4285, longitude: 32.0620)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)
        record.update_columns(latitude: nil, longitude: nil)

        result = described_class.new.perform(record.id)
        expect(result[:gps_coordinates][:latitude]).to eq(tree.latitude.to_f)
        expect(result[:gps_coordinates][:longitude]).to eq(tree.longitude.to_f)
      end
    end

    context "when anchoring fails" do
      it "re-raises the error for Sidekiq retry" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, maintainable: tree)

        allow_any_instance_of(PuroEarth::PassportService).to receive(:anchor!)
          .and_raise(PuroEarth::PassportService::AnchoringError, "RPC timeout")

        expect {
          described_class.new.perform(record.id)
        }.to raise_error(PuroEarth::PassportService::AnchoringError)
      end
    end
  end
end
