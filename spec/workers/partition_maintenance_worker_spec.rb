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

      it "creates partitions for previous, current and next month" do
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
        expect(Rails.logger).to have_received(:info).with(/Partition Maintenance.*OK/).exactly(9).times.ordered
        expect(Rails.logger).to have_received(:info).with(/Partition Maintenance.*Завершено.*Створено нових партицій: 9/).ordered
      end
    end
  end

  # [ARCH.70] Прилад росту. Три приклади, і третій несучий: він пінить не значення,
  # а АСИМЕТРІЮ — вимірювання свідомо винесене з-під критичного rescue, бо той
  # інкрементить P0-лічильник і re-raise'ить.
  describe "growth instrument" do
    let(:tree_sql) do
      lambda do |table|
        connection.select_one(<<~SQL.squish)
          SELECT count(*) FILTER (WHERE isleaf) AS leaves,
                 COALESCE(sum(pg_total_relation_size(relid)), 0) AS bytes
          FROM pg_partition_tree(#{connection.quote(table)})
        SQL
      end
    end

    it "records leaf-partition count and byte size for every partitioned table" do
      described_class.new.perform

      described_class::PARTITIONED_TABLES.each do |table|
        expected = tree_sql.call(table)

        # Пін на РОЗМІР множини: на порожньому дереві обидва ассерти нижче були б
        # зелені й без механізму.
        expect(expected["leaves"].to_i).to be > 0

        expect(SilkenNet::Metrics::PARTITIONS_PRESENT.get(labels: { table: table }))
          .to eq(expected["leaves"].to_f)
        expect(SilkenNet::Metrics::PARTITIONED_TABLE_BYTES.get(labels: { table: table }))
          .to eq(expected["bytes"].to_f)
      end
    end

    it "stamps the freshness witness after a full pass" do
      described_class.new.perform

      expect(SilkenNet::Metrics::PARTITION_SAMPLE_TIMESTAMP.get)
        .to be_within(60).of(Time.current.to_i)
    end

    it "keeps a sampling failure OFF the P0 failure counter and out of Sidekiq retry" do
      allow(connection).to receive(:select_one).and_call_original
      allow(connection).to receive(:select_one)
        .with(a_string_matching(/pg_partition_tree/))
        .and_raise(ActiveRecord::StatementInvalid.new("PG::Error: boom"))
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

      counter = SilkenNet::Metrics::PARTITION_MAINTENANCE_FAILURES_TOTAL
      before = counter.get

      expect { described_class.new.perform }.not_to raise_error
      expect(counter.get).to eq(before)
    end
  end

  # [ARCH.70] ЧЕТВЕРТА вісь приладу, і вона не про ріст, а про ПОЛОМКУ: DEFAULT-лист
  # є єдиною партицією, чия непорожність ламає обслуговування НЕЗВОРОТНО. Другий
  # приклад тут несучий — він не пінить гейдж, а ВІДТВОРЮЄ саме те падіння, задля
  # якого гейдж заведено; без нього рунбук `06_06 §5.5` був би описом механізму,
  # якого ніхто не спостерігав.
  describe "DEFAULT-partition occupancy" do
    def gauge_for(table)
      SilkenNet::Metrics::PARTITION_DEFAULT_OCCUPIED.get(labels: { table: table })
    end

    def next_month_partition
      nxt = Time.current.utc.to_date.next_month.beginning_of_month
      "telemetry_logs_y#{nxt.strftime('%Y')}m#{nxt.strftime('%m')}"
    end

    it "reports 0 for every table while the DEFAULT leaves stay empty" do
      described_class.new.perform

      described_class::PARTITIONED_TABLES.each do |table|
        expect(gauge_for(table)).to eq(0.0)
      end
    end

    it "reports 1 for the table whose DEFAULT leaf holds a row, and 0 for its siblings" do
      # `created_at` поза КОЖНИМ місячним діапазоном → рядок маршрутизується в
      # DEFAULT. Пін на саму фікстуру: без нього приклад був би зелений і тоді,
      # коли рядок насправді осів у звичайній партиції.
      create(:telemetry_log, created_at: 3.years.ago)
      expect(connection.select_value("SELECT count(*) FROM telemetry_logs_default").to_i).to be > 0

      described_class.new.perform

      expect(gauge_for("telemetry_logs")).to eq(1.0)
      expect(gauge_for("gateway_telemetry_logs")).to eq(0.0)
      expect(gauge_for("blockchain_transactions")).to eq(0.0)
    end

    it "fails LOUDLY and says retries will not help when DEFAULT already holds next month's rows" do
      # Робимо приклад детермінованим незалежно від того, чи попередній прогін уже
      # створив партицію наступного місяця: DDL відкотиться разом із транзакцією.
      connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(next_month_partition)}")
      create(:telemetry_log, created_at: 1.month.from_now)

      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform }.to raise_error(ActiveRecord::StatementInvalid)

      expect(Rails.logger).to have_received(:error).with(/РЕТРАЇ ЦЬОГО НЕ ВИПРАВЛЯТЬ/)
    end
  end

  # 🔴 [ARCH.70] Третій вимір ретеншну — РЯДКИ. Пін живий (не мок): він ганяє
  # справжній `count` проти справжніх партицій, тож стереже і величину, і те, що
  # запит узагалі виконуваний на партиційній таблиці.
  describe "retention row-count gauge (ARCH.70)" do
    let(:gauge) { SilkenNet::Metrics::TELEMETRY_ORACLE_DISPATCHED_ROWS }

    it "records the retained dispatched-row count, not a hardcoded zero" do
      tree = create(:tree)
      3.times do |i|
        create(:telemetry_log, tree: tree, oracle_status: :dispatched)
      end

      described_class.new.perform

      expect(gauge.get).to eq(3)
    end

    # ⊥ Дзеркало: величина мусить РУХАТИСЬ, інакше пін вище зелений і на константі.
    it "reflects a population change on the next pass" do
      tree = create(:tree)
      create(:telemetry_log, tree: tree, oracle_status: :dispatched)
      described_class.new.perform
      first = gauge.get

      create(:telemetry_log, tree: tree, oracle_status: :dispatched)
      described_class.new.perform

      expect(gauge.get).to eq(first + 1)
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
