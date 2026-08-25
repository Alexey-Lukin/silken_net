# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [INF.22] Пускач для recovery, який доти був оголошений і недосяжний.
RSpec.describe IotexBackfillWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }

  before do
    allow(IotexVerificationWorker).to receive(:perform_async)
  end

  def unverified_log(created_at:)
    create(:telemetry_log, tree: tree, created_at: created_at, verified_by_iotex: false)
  end

  describe "#perform" do
    it "re-arms an unverified log inside the window" do
      log = unverified_log(created_at: 2.hours.ago)

      described_class.new.perform

      expect(IotexVerificationWorker).to have_received(:perform_async)
        .with(log.id_value, log.created_at.iso8601(6))
    end

    # 🔴 Обидві координати НЕСУЧІ: `telemetry_logs` партиційований по `created_at`, тож
    # без нього `find_telemetry_log_with_pruning` рядок не резолвить — джоба поїхала б
    # у чергу й тихо не знайшла свій лог. Пін на самий `id` цього не бачить.
    it "passes BOTH partition coordinates, not just the id" do
      log = unverified_log(created_at: 2.hours.ago)

      described_class.new.perform

      expect(IotexVerificationWorker).to have_received(:perform_async) do |id, iso|
        expect(id).to eq(log.id_value)
        expect(iso).to be_present
        expect(iso).to include("T")
      end
    end

    it "leaves an already verified log alone" do
      create(:telemetry_log, tree: tree, created_at: 2.hours.ago, verified_by_iotex: true)

      described_class.new.perform

      expect(IotexVerificationWorker).not_to have_received(:perform_async)
    end

    # ⚠️ Вікно — визначення ПРЕДМЕТА, не оптимізація: лог, незверифікований довше за
    # `LOOKBACK_WINDOW`, є предметом ретеншену, а не recovery. Пін навмисно кладе рядок
    # ОДРАЗУ за межею, інакше він зелений і при безмежному скані.
    it "ignores a log older than the lookback window" do
      unverified_log(created_at: described_class::LOOKBACK_WINDOW.ago - 1.hour)

      described_class.new.perform

      expect(IotexVerificationWorker).not_to have_received(:perform_async)
    end

    it "stays silent when there is nothing to re-arm" do
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn).with(/IoTeX Backfill/)
    end

    it "counts the re-armed logs, not the passes" do
      2.times { |i| unverified_log(created_at: (i + 1).hours.ago) }
      before_val = SilkenNet::Metrics::IOTEX_BACKFILL_REARMED_TOTAL.get

      described_class.new.perform

      expect(SilkenNet::Metrics::IOTEX_BACKFILL_REARMED_TOTAL.get - before_val).to eq(2)
    end

    it "caps one pass so a long outage cannot flood the money queue" do
      stub_const("#{described_class}::BATCH_LIMIT", 1)
      2.times { |i| unverified_log(created_at: (i + 1).hours.ago) }

      described_class.new.perform

      expect(IotexVerificationWorker).to have_received(:perform_async).once
    end

    it "runs on the observability queue, never a money one" do
      expect(described_class.sidekiq_options["queue"]).to eq("low")
    end

    # 🔴 Ізоляція збою ОДНОГО рядка: Redis може відмовити на будь-якому `perform_async`,
    # і без per-record rescue решта вікна не доїхала б до черги — тобто зовнішній збій
    # обертався б утратою решти recovery. Пін заразом накриває другу гілку: при нулі
    # ре-армованих лічильник НЕ рухається (інакше метрика рахувала б проходи).
    it "isolates a failing enqueue and does not count it as re-armed" do
      unverified_log(created_at: 1.hour.ago)
      unverified_log(created_at: 2.hours.ago)
      allow(IotexVerificationWorker).to receive(:perform_async).and_raise(Redis::BaseError, "down")
      allow(Rails.logger).to receive(:error)
      before_val = SilkenNet::Metrics::IOTEX_BACKFILL_REARMED_TOTAL.get

      expect { described_class.new.perform }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/IoTeX Backfill/).twice
      expect(SilkenNet::Metrics::IOTEX_BACKFILL_REARMED_TOTAL.get).to eq(before_val)
    end
  end
end
