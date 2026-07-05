# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryLog, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#healthy?" do
    it "returns true for homeostasis with normal readings" do
      log = build(:telemetry_log, :healthy)
      expect(log).to be_healthy
    end

    it "returns false when bio_status is stress" do
      log = build(:telemetry_log, :stressed)
      expect(log).not_to be_healthy
    end

    it "returns false when temperature is extreme" do
      log = build(:telemetry_log, :healthy, temperature_c: 55)
      expect(log).not_to be_healthy
    end

    it "returns false when acoustic events are high" do
      log = build(:telemetry_log, :healthy, acoustic_events: 25)
      expect(log).not_to be_healthy
    end
  end

  describe "#optimal?" do
    it "returns true for ideal conditions" do
      log = build(:telemetry_log, :optimal)
      expect(log).to be_optimal
    end

    it "returns false when voltage is low" do
      log = build(:telemetry_log, :optimal, voltage_mv: 3000)
      expect(log).not_to be_optimal
    end

    it "returns false when z_value is out of range" do
      log = build(:telemetry_log, :optimal, z_value: 1.5)
      expect(log).not_to be_optimal
    end

    it "returns false when the log is not in homeostasis" do
      log = build(:telemetry_log, :optimal, bio_status: :stress)
      expect(log).not_to be_optimal
    end

    it "returns false when z_value is absent" do
      log = build(:telemetry_log, :optimal, z_value: nil)
      expect(log).not_to be_optimal
    end
  end

  describe "#critical?" do
    it "returns true for anomaly status" do
      log = build(:telemetry_log, :anomaly)
      expect(log).to be_critical
    end

    it "returns true for vm_error status" do
      log = build(:telemetry_log, :vm_errored)
      expect(log).to be_critical
    end

    it "returns false for homeostasis" do
      log = build(:telemetry_log, :healthy)
      expect(log).not_to be_critical
    end
  end

  describe "#recovery_confirmed?" do
    let(:tree) { create(:tree, health_streak: 0) }

    it "returns true when log is healthy and health_streak >= 3" do
      tree.update_column(:health_streak, 3)
      log = build(:telemetry_log, :healthy, tree: tree)

      expect(log.recovery_confirmed?).to be true
    end

    it "returns false when health_streak < 3" do
      tree.update_column(:health_streak, 2)
      log = build(:telemetry_log, :healthy, tree: tree)

      expect(log.recovery_confirmed?).to be false
    end

    it "returns false when log is not healthy even with high streak" do
      tree.update_column(:health_streak, 10)
      log = build(:telemetry_log, :stressed, tree: tree)

      expect(log.recovery_confirmed?).to be false
    end

    it "uses denormalized counter instead of querying telemetry_logs" do
      tree.update_column(:health_streak, 5)
      log = build(:telemetry_log, :healthy, tree: tree)

      # recovery_confirmed? works without querying telemetry_logs —
      # uses only tree.health_streak (in-memory attribute)
      result = log.recovery_confirmed?
      expect(result).to be true
    end
  end

  describe "#relayed_via_mesh?" do
    # Стартовий TTL залежить від типу пакета (firmware DEFAULT_TTL=3 /
    # PANIC_TTL=5) — до FW.29-panic-персистенції default=5 позначав
    # «релейнутим» КОЖЕН direct normal-пакет.
    it "returns false for a direct normal packet (TTL still at 3)" do
      log = build(:telemetry_log, mesh_ttl: 3, panic: false)
      expect(log.relayed_via_mesh?).to be false
    end

    it "returns true for a relayed normal packet (TTL decremented below 3)" do
      log = build(:telemetry_log, mesh_ttl: 2, panic: false)
      expect(log.relayed_via_mesh?).to be true
    end

    it "returns false for a direct panic packet (TTL still at 5)" do
      log = build(:telemetry_log, mesh_ttl: 5, panic: true)
      expect(log.relayed_via_mesh?).to be false
    end

    it "returns true for a relayed panic packet (TTL decremented below 5)" do
      log = build(:telemetry_log, mesh_ttl: 4, panic: true)
      expect(log.relayed_via_mesh?).to be true
    end
  end

  # [S6.16] One-Home pruning-логіки: 1с-вікно (стандарт BlockchainTransaction)
  # + degraded-облік. Воркери/сервіси/контролери делегують сюди.
  describe ".partition_pruned" do
    let(:tree) { create(:tree) }
    let!(:log) { create(:telemetry_log, tree: tree, created_at: Time.current) }

    before do
      allow(SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL).to receive(:increment)
    end

    it "finds the record from a seconds-precision ISO despite microsecond created_at" do
      # Давня точна рівність `created_at == Time.iso8601(iso)` тут мовчки
      # промахувалась (DB тримає мікросекунди) — 1с-вікно це закриває.
      seconds_iso = log.created_at.iso8601
      found = described_class.where(id: log.id)
                          .partition_pruned(seconds_iso, metric_caller: "Spec")
                          .first
      expect(found).to eq(log)
      expect(SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL)
        .not_to have_received(:increment)
    end

    it "finds the record from a microseconds-precision ISO" do
      found = described_class.where(id: log.id)
                          .partition_pruned(log.created_at.iso8601(6), metric_caller: "Spec")
                          .first
      expect(found).to eq(log)
    end

    it "falls back unpruned and counts the degraded path when ISO is blank" do
      found = described_class.where(id: log.id)
                          .partition_pruned(nil, metric_caller: "Spec")
                          .first
      expect(found).to eq(log)
      expect(SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL)
        .to have_received(:increment)
        .with(labels: { caller: "Spec:missing_created_at_iso" })
    end

    it "falls back unpruned and counts the degraded path when ISO is malformed" do
      found = described_class.where(id: log.id)
                          .partition_pruned("not-a-date", metric_caller: "Spec")
                          .first
      expect(found).to eq(log)
      expect(SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL)
        .to have_received(:increment)
        .with(labels: { caller: "Spec:invalid_iso8601" })
    end

    it "excludes records outside the 1-second window (pruning actually filters)" do
      stale_iso = (log.created_at - 1.hour).iso8601
      found = described_class.where(id: log.id)
                          .partition_pruned(stale_iso, metric_caller: "Spec")
                          .first
      expect(found).to be_nil
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        tree = create(:tree)
        old_log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
        new_log = create(:telemetry_log, tree: tree, created_at: 1.minute.ago)

        expect(described_class.recent.first).to eq(new_log)
        expect(described_class.recent.last).to eq(old_log)
      end
    end

    describe ".anomalies" do
      it "includes stress, anomaly, and tamper statuses" do
        tree = create(:tree)
        healthy_log = create(:telemetry_log, :healthy, tree: tree)
        stress_log = create(:telemetry_log, :stressed, tree: tree)
        anomaly_log = create(:telemetry_log, :anomaly, tree: tree)

        result = described_class.anomalies
        expect(result).to include(stress_log, anomaly_log)
        expect(result).not_to include(healthy_log)
      end

      it "includes high acoustic events regardless of status" do
        tree = create(:tree)
        noisy_log = create(:telemetry_log, :healthy, tree: tree, acoustic_events: 60)

        expect(described_class.anomalies).to include(noisy_log)
      end
    end
  end

  # =========================================================================
  # ORACLE_STATUS ENUM (Proof of Growth Pipeline)
  # =========================================================================
  describe "oracle_status enum" do
    let(:tree) { create(:tree) }

    it "defaults to pending for new records" do
      log = create(:telemetry_log, tree: tree)
      expect(log.oracle_status).to eq("pending")
    end

    it "supports dispatched status" do
      log = create(:telemetry_log, tree: tree, oracle_status: :dispatched)
      expect(log).to be_oracle_status_dispatched
    end

    it "supports fulfilled status" do
      log = create(:telemetry_log, tree: tree, oracle_status: :fulfilled)
      expect(log).to be_oracle_status_fulfilled
    end

    it "supports failed status" do
      log = create(:telemetry_log, tree: tree, oracle_status: :failed)
      expect(log).to be_oracle_status_failed
    end

    it "raises on invalid oracle_status value" do
      expect {
        create(:telemetry_log, tree: tree, oracle_status: :invalid_status)
      }.to raise_error(ArgumentError)
    end
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to tree" do
      assoc = described_class.reflect_on_association(:tree)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to gateway (optional, via queen_uid)" do
      assoc = described_class.reflect_on_association(:gateway)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be true
    end

    it "does NOT expose bio_contract_firmware (mis-join trap, E.62-патерн)" do
      # firmware_version_id зберігає wire-ідентифікатор (21B uint16 /
      # CCM 4-бітний epoch-нібл), не автоінкрементний bio_contract_firmwares.id —
      # belongs_to по цій колонці повертав би чужий запис. Guard проти
      # випадкового повернення асоціації без канонізованого мапінгу.
      expect(described_class.reflect_on_association(:bio_contract_firmware)).to be_nil
    end
  end

  # =========================================================================
  # ADDITIONAL SCOPES
  # =========================================================================
  describe ".in_timeframe" do
    it "filters logs within the given time range" do
      tree = create(:tree)
      inside = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
      outside = create(:telemetry_log, tree: tree, created_at: 3.days.ago)

      result = described_class.in_timeframe(2.hours.ago, Time.current)
      expect(result).to include(inside)
      expect(result).not_to include(outside)
    end
  end

  # =========================================================================
  # BIO_STATUS ENUM
  # =========================================================================
  describe "bio_status enum" do
    let(:tree) { create(:tree) }

    it "supports homeostasis status" do
      log = build(:telemetry_log, tree: tree, bio_status: :homeostasis)
      expect(log).to be_bio_status_homeostasis
    end

    it "supports stress status" do
      log = build(:telemetry_log, tree: tree, bio_status: :stress)
      expect(log).to be_bio_status_stress
    end

    it "supports anomaly status" do
      log = build(:telemetry_log, tree: tree, bio_status: :anomaly)
      expect(log).to be_bio_status_anomaly
    end

    it "supports vm_error status" do
      log = build(:telemetry_log, tree: tree, bio_status: :vm_error)
      expect(log).to be_bio_status_vm_error
    end
  end

  describe "no ActiveRecord validations on hot path" do
    it "does not validate presence of sensor fields" do
      log = described_class.new(tree: create(:tree), bio_status: :homeostasis)

      # Model should not have validations on sensor fields —
      # data is validated in TelemetryUnpackerService
      expect(log.errors.attribute_names).not_to include(
        :voltage_mv, :temperature_c, :acoustic_events,
        :metabolism_s, :growth_points, :mesh_ttl
      )
    end
  end
end
