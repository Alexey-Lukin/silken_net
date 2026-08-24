# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilecoinVerificationSweepWorker, type: :worker do
  let(:worker) { described_class.new }

  describe "sidekiq options" do
    it "uses the low queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("low")
    end
  end

  describe "#perform" do
    let!(:fresh_archived) { create(:audit_log, ipfs_cid: "bafkfresh") }
    let!(:old_archived) do
      create(:audit_log, ipfs_cid: "bafkold").tap { |l| l.update_column(:updated_at, 3.days.ago) }
    end
    let!(:unarchived) { create(:audit_log) }

    before do
      allow(SilkenNet::Metrics::FILECOIN_VERIFICATION_FAILURES_TOTAL).to receive(:increment)
    end

    it "verifies fresh AND randomly-sampled older archives, skipping unarchived" do
      service = instance_double(Filecoin::VerificationService, verify!: { verified: true })
      allow(Filecoin::VerificationService).to receive(:new).and_return(service)

      worker.perform

      expect(Filecoin::VerificationService).to have_received(:new).with(fresh_archived)
      expect(Filecoin::VerificationService).to have_received(:new).with(old_archived)
      expect(Filecoin::VerificationService).not_to have_received(:new).with(unarchived)
    end

    it "logs ERROR + increments the failure metric on an integrity mismatch" do
      allow(Filecoin::VerificationService).to receive(:new).and_return(
        instance_double(Filecoin::VerificationService,
                        verify!: { verified: false, reason: "cid_mismatch" })
      )
      allow(Rails.logger).to receive(:error)

      worker.perform

      expect(Rails.logger).to have_received(:error).with(/INTEGRITY FAIL/).at_least(:once)
      expect(SilkenNet::Metrics::FILECOIN_VERIFICATION_FAILURES_TOTAL)
        .to have_received(:increment).with(labels: { reason: "cid_mismatch" }).at_least(:once)
    end

    it "labels a chain-hash mismatch distinctly (no reason key from the service)" do
      allow(Filecoin::VerificationService).to receive(:new).and_return(
        instance_double(Filecoin::VerificationService, verify!: { verified: false })
      )
      allow(Rails.logger).to receive(:error)

      worker.perform

      expect(SilkenNet::Metrics::FILECOIN_VERIFICATION_FAILURES_TOTAL)
        .to have_received(:increment).with(labels: { reason: "chain_hash_mismatch" }).at_least(:once)
    end

    it "counts gateway flakes as unreachable — no failure metric, sweep survives" do
      service = instance_double(Filecoin::VerificationService)
      allow(service).to receive(:verify!).and_raise(Web3::HttpClient::RequestError, "gateway 504")
      allow(Filecoin::VerificationService).to receive(:new).and_return(service)
      allow(Rails.logger).to receive(:warn)

      expect { worker.perform }.not_to raise_error

      expect(SilkenNet::Metrics::FILECOIN_VERIFICATION_FAILURES_TOTAL).not_to have_received(:increment)
      expect(Rails.logger).to have_received(:warn).with(/gateway unreachable/).at_least(:once)
    end
  end

  # [E.60 Фаза 1б] Leaf-стемп-нога: пара до seal-guard'а моделі (guard = AR-шлях,
  # sweeper = raw-SQL-шлях).
  describe "leaf-stamp sample leg" do
    let(:tree) { create(:tree) }

    before { silence_broadcasts!(:tree_map) }

    it "ловить drift: перерахований CID ≠ merkle_leaf → метрика leaf_stamp_drift" do
      log = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
      TelemetryLog.where(id: log.id, created_at: log.created_at)
                  .update_all(merkle_leaf: "bafkrei" + "x" * 52) # битий стемп raw-SQL'ем

      allow(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to receive(:increment).with(labels: { reason: "leaf_stamp_drift" })

      described_class.new.perform

      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL)
        .to have_received(:increment).with(labels: { reason: "leaf_stamp_drift" })
    end

    it "чистий стемп проходить без метрики" do
      log = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
      TelemetryLog.where(id: log.id, created_at: log.created_at)
                  .update_all(merkle_leaf: Mrv::TelemetryLeaf.cid_for(log))

      allow(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL).to receive(:increment)

      described_class.new.perform

      expect(SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL).not_to have_received(:increment)
    end
  end
end
