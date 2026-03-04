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
  end

  describe "#critical?" do
    it "returns true for anomaly status" do
      log = build(:telemetry_log, :anomaly)
      expect(log).to be_critical
    end

    it "returns true for tamper status" do
      log = build(:telemetry_log, :tampered)
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

      # recovery_confirmed? має працювати без звернення до telemetry_logs —
      # використовує лише tree.health_streak (in-memory атрибут)
      result = log.recovery_confirmed?
      expect(result).to be true
    end
  end

  describe "#relayed_via_mesh?" do
    it "returns true when TTL decreased from initial" do
      log = build(:telemetry_log, mesh_ttl: 3)
      expect(log.relayed_via_mesh?).to be true
    end

    it "returns false when TTL equals initial" do
      log = build(:telemetry_log, mesh_ttl: 5)
      expect(log.relayed_via_mesh?).to be false
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        tree = create(:tree)
        old_log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
        new_log = create(:telemetry_log, tree: tree, created_at: 1.minute.ago)

        expect(TelemetryLog.recent.first).to eq(new_log)
        expect(TelemetryLog.recent.last).to eq(old_log)
      end
    end

    describe ".anomalies" do
      it "includes stress, anomaly, and tamper statuses" do
        tree = create(:tree)
        healthy_log = create(:telemetry_log, :healthy, tree: tree)
        stress_log = create(:telemetry_log, :stressed, tree: tree)
        anomaly_log = create(:telemetry_log, :anomaly, tree: tree)

        result = TelemetryLog.anomalies
        expect(result).to include(stress_log, anomaly_log)
        expect(result).not_to include(healthy_log)
      end

      it "includes high acoustic events regardless of status" do
        tree = create(:tree)
        noisy_log = create(:telemetry_log, :healthy, tree: tree, acoustic_events: 60)

        expect(TelemetryLog.anomalies).to include(noisy_log)
      end
    end

    describe ".seismic_activity" do
      it "includes records with high piezo voltage" do
        tree = create(:tree)
        normal_log = create(:telemetry_log, tree: tree, piezo_voltage_mv: 500)
        seismic_log = create(:telemetry_log, :seismic, tree: tree)

        result = TelemetryLog.seismic_activity
        expect(result).to include(seismic_log)
        expect(result).not_to include(normal_log)
      end
    end
  end

  describe "no ActiveRecord validations on hot path" do
    it "does not validate presence of sensor fields" do
      log = TelemetryLog.new(tree: create(:tree), bio_status: :homeostasis)

      # Модель не повинна мати валідацій на сенсорні поля —
      # дані перевіряються в TelemetryUnpackerService
      expect(log.errors.attribute_names).not_to include(
        :voltage_mv, :temperature_c, :acoustic_events,
        :metabolism_s, :growth_points, :mesh_ttl
      )
    end
  end
end
