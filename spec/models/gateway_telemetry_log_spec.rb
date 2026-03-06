# frozen_string_literal: true

require "rails_helper"

RSpec.describe GatewayTelemetryLog, type: :model do
  # =========================================================================
  # CONSTANTS
  # =========================================================================
  describe "constants" do
    it "defines LOW_BATTERY_THRESHOLD" do
      expect(described_class::LOW_BATTERY_THRESHOLD).to eq(3300)
    end

    it "defines OVERHEAT_THRESHOLD" do
      expect(described_class::OVERHEAT_THRESHOLD).to eq(65)
    end

    it "defines LOW_SIGNAL_THRESHOLD" do
      expect(described_class::LOW_SIGNAL_THRESHOLD).to eq(5)
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  # [KENOSIS TITAN]: AR-валідації видалено з моделі для hot-path оптимізації.
  # Перевірка даних відбувається в GatewayTelemetryWorker.valid_gateway_stats?
  # перед записом. insert_all на Series D ігнорує AR-валідації моделі.
  describe "validations" do
    it "is valid with factory defaults (no AR validations enforced on model)" do
      log = build(:gateway_telemetry_log)
      expect(log).to be_valid
    end

    it "is valid even with nil numeric fields (validated at worker level)" do
      log = build(:gateway_telemetry_log, voltage_mv: nil, temperature_c: nil)
      expect(log).to be_valid
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        gateway = create(:gateway)
        old_log = create(:gateway_telemetry_log, gateway: gateway, queen_uid: gateway.uid, created_at: 1.hour.ago)
        new_log = create(:gateway_telemetry_log, gateway: gateway, queen_uid: gateway.uid, created_at: 1.minute.ago)

        expect(described_class.recent.first).to eq(new_log)
        expect(described_class.recent.last).to eq(old_log)
      end
    end

    describe ".critical_battery" do
      it "returns logs below LOW_BATTERY_THRESHOLD" do
        gateway    = create(:gateway)
        low_log    = create(:gateway_telemetry_log, :low_battery, gateway: gateway, queen_uid: gateway.uid)
        normal_log = create(:gateway_telemetry_log, gateway: gateway, queen_uid: gateway.uid,
                            voltage_mv: GatewayTelemetryLog::LOW_BATTERY_THRESHOLD + 100)

        expect(described_class.critical_battery).to include(low_log)
        expect(described_class.critical_battery).not_to include(normal_log)
      end
    end

    describe ".overheated" do
      it "returns logs above OVERHEAT_THRESHOLD" do
        gateway  = create(:gateway)
        hot_log  = create(:gateway_telemetry_log, :overheated, gateway: gateway, queen_uid: gateway.uid)
        cool_log = create(:gateway_telemetry_log, gateway: gateway, queen_uid: gateway.uid,
                          temperature_c: GatewayTelemetryLog::OVERHEAT_THRESHOLD - 1)

        expect(described_class.overheated).to include(hot_log)
        expect(described_class.overheated).not_to include(cool_log)
      end
    end

    describe ".weak_signal" do
      it "returns logs with CSQ below LOW_SIGNAL_THRESHOLD (excluding 99)" do
        gateway      = create(:gateway)
        weak_log     = create(:gateway_telemetry_log, :weak_signal, gateway: gateway, queen_uid: gateway.uid)
        unknown_log  = create(:gateway_telemetry_log, :unknown_signal, gateway: gateway, queen_uid: gateway.uid)
        strong_log   = create(:gateway_telemetry_log, gateway: gateway, queen_uid: gateway.uid,
                              cellular_signal_csq: 20)

        expect(described_class.weak_signal).to include(weak_log)
        expect(described_class.weak_signal).not_to include(unknown_log, strong_log)
      end
    end
  end

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================
  describe "#signal_quality_percentage" do
    it "returns 0 for CSQ = 99 (unknown)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 99)
      expect(log.signal_quality_percentage).to eq(0)
    end

    it "returns 0 for nil CSQ" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 15)
      allow(log).to receive(:cellular_signal_csq).and_return(nil)
      expect(log.signal_quality_percentage).to eq(0)
    end

    it "returns 100 for maximum CSQ (31)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 31)
      expect(log.signal_quality_percentage).to eq(100.0)
    end

    it "returns 0 for minimum CSQ (0)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 0)
      expect(log.signal_quality_percentage).to eq(0.0)
    end

    it "calculates correct percentage for mid-range CSQ" do
      # CSQ 15 / 31 * 100 = 48.4%
      log = build(:gateway_telemetry_log, cellular_signal_csq: 15)
      expect(log.signal_quality_percentage).to be_within(0.1).of(48.4)
    end
  end

  describe "#signal_dbm" do
    it "returns nil for CSQ = 99 (unknown)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 99)
      expect(log.signal_dbm).to be_nil
    end

    it "returns -113 for CSQ = 0 (minimum sensitivity)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 0)
      expect(log.signal_dbm).to eq(-113)
    end

    it "returns -51 for CSQ = 31 (best signal)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 31)
      expect(log.signal_dbm).to eq(-51)
    end

    it "applies the 3GPP formula: 2 * CSQ - 113" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: 15)
      expect(log.signal_dbm).to eq(2 * 15 - 113)
    end
  end

  describe "#critical_fault?" do
    it "returns true when voltage is below LOW_BATTERY_THRESHOLD" do
      log = build(:gateway_telemetry_log, :low_battery)
      expect(log.critical_fault?).to be true
    end

    it "returns true when temperature exceeds OVERHEAT_THRESHOLD" do
      log = build(:gateway_telemetry_log, :overheated)
      expect(log.critical_fault?).to be true
    end

    it "returns true when signal is weak (CSQ below LOW_SIGNAL_THRESHOLD, not 99)" do
      log = build(:gateway_telemetry_log, :weak_signal)
      expect(log.critical_fault?).to be true
    end

    it "returns false for CSQ = 99 even though value < LOW_SIGNAL_THRESHOLD" do
      # 99 means "unknown", not truly weak — should not trigger
      log = build(:gateway_telemetry_log, :unknown_signal)
      expect(log.critical_fault?).to be false
    end

    it "returns false when all metrics are within safe bounds" do
      log = build(:gateway_telemetry_log,
                  voltage_mv: GatewayTelemetryLog::LOW_BATTERY_THRESHOLD + 500,
                  temperature_c: GatewayTelemetryLog::OVERHEAT_THRESHOLD - 5,
                  cellular_signal_csq: 20)
      expect(log.critical_fault?).to be false
    end

    # [KENOSIS TITAN]: Nil-safety — без AR-валідацій поля можуть бути nil при insert_all
    it "returns false when voltage_mv is nil (guard clause)" do
      log = build(:gateway_telemetry_log, voltage_mv: nil)
      expect(log.critical_fault?).to be false
    end

    it "returns false when temperature_c is nil (guard clause)" do
      log = build(:gateway_telemetry_log, temperature_c: nil)
      expect(log.critical_fault?).to be false
    end

    it "returns false when cellular_signal_csq is nil (guard clause)" do
      log = build(:gateway_telemetry_log, cellular_signal_csq: nil)
      expect(log.critical_fault?).to be false
    end
  end
end
