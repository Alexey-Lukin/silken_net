# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartitionMaintenanceWorker, type: :worker do
  let(:connection) { ActiveRecord::Base.connection }

  describe "#perform" do
    context "when generating partition DDL" do
      before do
        allow(connection).to receive(:execute)
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      end

      it "creates partitions for current and next month" do
        travel_to Time.utc(2026, 3, 15) do
          described_class.new.perform

          expect(connection).to have_received(:execute).with(
            a_string_matching(/"telemetry_logs_y2026m03"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"telemetry_logs_y2026m04"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"gateway_telemetry_logs_y2026m03"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"gateway_telemetry_logs_y2026m04"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"blockchain_transactions_y2026m03"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"blockchain_transactions_y2026m04"/)
          )
        end
      end

      it "generates correct range boundaries" do
        travel_to Time.utc(2026, 12, 1) do
          described_class.new.perform

          expect(connection).to have_received(:execute).with(
            a_string_matching(/"telemetry_logs_y2026m12" PARTITION OF "telemetry_logs".*FROM \('2026-12-01 00:00:00'\) TO \('2027-01-01 00:00:00'\)/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"telemetry_logs_y2027m01" PARTITION OF "telemetry_logs".*FROM \('2027-01-01 00:00:00'\) TO \('2027-02-01 00:00:00'\)/)
          )
        end
      end

      it "handles year boundary correctly" do
        travel_to Time.utc(2026, 12, 28) do
          described_class.new.perform

          expect(connection).to have_received(:execute).with(
            a_string_matching(/"gateway_telemetry_logs_y2027m01"/)
          )
          expect(connection).to have_received(:execute).with(
            a_string_matching(/"blockchain_transactions_y2027m01"/)
          )
        end
      end
    end

    context "when partitions already exist" do
      it "completes without errors due to IF NOT EXISTS" do
        # Партиції для поточного місяця вже існують у тестовій БД —
        # воркер має відпрацювати ідемпотентно.
        expect { described_class.new.perform }.not_to raise_error
      end
    end

    context "when DDL error occurs" do
      before do
        allow(connection).to receive(:execute)
          .and_raise(ActiveRecord::StatementInvalid.new("PG::Error: permission denied"))
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      end

      it "re-raises non-duplicate errors for Sidekiq retry" do
        expect {
          described_class.new.perform
        }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      end

      it "increments the partition_maintenance_failures counter (06_03 §2.8 / S2.5 alert)" do
        counter = SilkenNet::Metrics::PARTITION_MAINTENANCE_FAILURES_TOTAL
        before = counter.get
        expect { described_class.new.perform }.to raise_error(ActiveRecord::StatementInvalid)
        expect(counter.get).to eq(before + 1.0)
      end

      it "still re-raises when Sentry is undefined (defined?-guard else)" do
        hide_const("Sentry")
        expect { described_class.new.perform }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context "when race condition produces already exists error" do
      before do
        call_count = 0
        allow(connection).to receive(:execute) do
          call_count += 1
          if call_count == 1
            raise ActiveRecord::StatementInvalid.new("PG::DuplicateTable: ERROR: relation already exists")
          end
        end
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      end

      it "gracefully handles already exists and continues" do
        expect { described_class.new.perform }.not_to raise_error
      end
    end

    context "with logging" do
      before do
        allow(connection).to receive(:execute)
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      end

      it "logs partition creation summary with correct count" do
        # PARTITIONED_TABLES has 3 entries (telemetry_logs, gateway_telemetry_logs,
        # blockchain_transactions) × 2 months = 6 ensure_partition invocations,
        # each emitting one "OK" line.
        allow(Rails.logger).to receive(:info)

        described_class.new.perform

        expect(Rails.logger).to have_received(:info).with(/Partition Maintenance.*Перевірка партицій/).ordered
        expect(Rails.logger).to have_received(:info).with(/Partition Maintenance.*OK/).exactly(6).times.ordered
        expect(Rails.logger).to have_received(:info).with(/Partition Maintenance.*Завершено.*Створено нових партицій: 6/).ordered
      end
    end
  end

  describe "sidekiq options" do
    it "uses default queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("default")
    end

    it "retries up to 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end
end
