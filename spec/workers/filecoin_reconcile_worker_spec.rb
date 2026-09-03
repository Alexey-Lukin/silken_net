# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilecoinReconcileWorker, type: :worker do
  # [ARCH.118-клас] Нога Filecoin ACTIVATION-GATED: без ключа enqueue не робиться ЗОВСІМ.
  # Ці приклади про ПОВЕДІНКУ enqueue, не про гейт, тож нога тут оголошено жива;
  # сам гейт пінить негативний приклад нижче.
  before { allow(Filecoin::ArchiveService).to receive(:configured?).and_return(true) }

  def archive_intent(archive_requested_at:, ipfs_cid: nil)
    create(:audit_log, archive_requested_at: archive_requested_at, ipfs_cid: ipfs_cid)
  end

  describe "#perform" do
    it "re-enqueues a stale archive-requested log still missing ipfs_cid" do
      log = archive_intent(archive_requested_at: 3.hours.ago)

      allow(FilecoinArchiveWorker).to receive(:perform_async).with(log.id)

      described_class.new.perform

      expect(FilecoinArchiveWorker).to have_received(:perform_async).with(log.id)
    end

    # GOLDEN LINCHPIN: a direct-create! log (factory/console) has NO archive_requested_at →
    # it was NEVER meant to be pinned. A naive `not_archived` scan would pin it (Pinata waste +
    # security over-exposure of factory-provenance on public IPFS). Fails if scope regresses.
    it "IGNORES a not-archived log with no outbox marker (factory/console never pinned)" do
      create(:audit_log, archive_requested_at: nil, ipfs_cid: nil)

      allow(FilecoinArchiveWorker).to receive(:perform_async)

      described_class.new.perform

      expect(FilecoinArchiveWorker).not_to have_received(:perform_async)
    end

    it "ignores an already-archived log (ipfs_cid present — idempotency)" do
      archive_intent(archive_requested_at: 3.hours.ago, ipfs_cid: "bafybeigdyrztest")

      allow(FilecoinArchiveWorker).to receive(:perform_async)

      described_class.new.perform

      expect(FilecoinArchiveWorker).not_to have_received(:perform_async)
    end

    it "leaves a fresh archive request alone (still inside FilecoinArchiveWorker retry window)" do
      archive_intent(archive_requested_at: 5.minutes.ago)

      allow(FilecoinArchiveWorker).to receive(:perform_async)

      described_class.new.perform

      expect(FilecoinArchiveWorker).not_to have_received(:perform_async)
    end

    it "skips requests older than LOOKBACK (budget-starvation guard — forensic tail)" do
      archive_intent(archive_requested_at: 40.days.ago)

      allow(FilecoinArchiveWorker).to receive(:perform_async)

      described_class.new.perform

      expect(FilecoinArchiveWorker).not_to have_received(:perform_async)
    end

    it "caps re-enqueues at BATCH_LIMIT, oldest-first (backlog drains across crons)" do
      stub_const("#{described_class}::BATCH_LIMIT", 2)
      oldest = archive_intent(archive_requested_at: 5.hours.ago)
      mid    = archive_intent(archive_requested_at: 4.hours.ago)
      archive_intent(archive_requested_at: 3.hours.ago) # newest — skipped by cap

      allow(FilecoinArchiveWorker).to receive(:perform_async).with(oldest.id)
      allow(FilecoinArchiveWorker).to receive(:perform_async).with(mid.id)

      described_class.new.perform

      expect(FilecoinArchiveWorker).to have_received(:perform_async).with(oldest.id)
      expect(FilecoinArchiveWorker).to have_received(:perform_async).with(mid.id)
    end

    it "is a no-op (no warn) when nothing is stuck" do
      archive_intent(archive_requested_at: 5.minutes.ago) # fresh only
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  # [E.60 Фаза 1б] Друга нога: backstop для архів-батчів (первинний enqueue при
  # створенні; тут — crash/exhaustion recovery + repair build_failed).
  describe "archive-batch reconcile leg" do
    it "re-enqueues stale pending/build_failed batches, skips fresh and terminal" do
      stale = TelemetryArchiveBatch.create!(archive_root: "a" * 64, token_type: :carbon_coin)
      trace = TelemetryArchiveBatch.create!(token_type: :carbon_coin, status: :build_failed)
      [ stale, trace ].each { |b| b.update_column(:updated_at, 3.hours.ago) }
      TelemetryArchiveBatch.create!(archive_root: "b" * 64, token_type: :carbon_coin) # fresh

      allow(TelemetryArchiveBatchWorker).to receive(:perform_async).with(stale.id)
      allow(TelemetryArchiveBatchWorker).to receive(:perform_async).with(trace.id)

      described_class.new.perform

      expect(TelemetryArchiveBatchWorker).to have_received(:perform_async).with(stale.id)
      expect(TelemetryArchiveBatchWorker).to have_received(:perform_async).with(trace.id)
    end
  end

  # [ARCH.118-клас, 2026-09-03] Пін САМОГО гейта: ре-арм без ключа лише палив би слоти.
  # [ARCH.118-клас, 2026-09-03] Пін САМОГО гейта: ре-арм без ключа лише палив би слоти,
  # а стаб на початку файлу робить ногу живою в кожному іншому прикладі.
  describe "activation gate (ARCH.118-клас)" do
    it "не ре-армить нічого, коли нога не сконфігурована" do
      allow(Filecoin::ArchiveService).to receive(:configured?).and_return(false)
      allow(FilecoinArchiveWorker).to receive(:perform_async)
      archive_intent(archive_requested_at: 3.hours.ago)

      described_class.new.perform

      expect(FilecoinArchiveWorker).not_to have_received(:perform_async)
    end
  end
end
