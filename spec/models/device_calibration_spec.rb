# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeviceCalibration, type: :model do
  before do
    silence_broadcasts!(:tree_map, :alert_notify, :alert_update)
  end

  describe "validations" do
    it "is valid with default attributes" do
      calibration = build(:device_calibration)
      expect(calibration).to be_valid
    end

    it "requires temperature_offset_c" do
      calibration = build(:device_calibration, temperature_offset_c: nil)
      expect(calibration).not_to be_valid
    end

    it "requires vcap_coefficient to be positive" do
      calibration = build(:device_calibration, vcap_coefficient: 0)
      expect(calibration).not_to be_valid
    end

    it "requires vcap_coefficient to be less than 2.0" do
      calibration = build(:device_calibration, vcap_coefficient: 2.0)
      expect(calibration).not_to be_valid
    end
  end

  describe "#normalize_temperature" do
    it "applies temperature offset" do
      calibration = build(:device_calibration, temperature_offset_c: -1.5)
      expect(calibration.normalize_temperature(25.0)).to eq(23.5)
    end
  end

  describe "#normalize_voltage" do
    it "applies vcap coefficient" do
      calibration = build(:device_calibration, vcap_coefficient: 0.9)
      expect(calibration.normalize_voltage(5000)).to eq(4500)
    end
  end

  describe "#sensor_drift_critical?" do
    it "returns false when within thresholds" do
      calibration = build(:device_calibration, temperature_offset_c: 2.0, vcap_coefficient: 1.1)
      expect(calibration.sensor_drift_critical?).to be false
    end

    it "returns true when temperature drift exceeds threshold" do
      calibration = build(:device_calibration, temperature_offset_c: 6.0)
      expect(calibration.sensor_drift_critical?).to be true
    end

    it "returns true when vcap coefficient deviates beyond tolerance" do
      calibration = build(:device_calibration, vcap_coefficient: 1.3)
      expect(calibration.sensor_drift_critical?).to be true
    end
  end

  # [ARCH.84] Ліхтар на ІНЕРТНІСТЬ шару, а не на його логіку. Приклади вище самі
  # ПИШУТЬ колонки, тож доводять, що предикат уміє спрацювати — але не те, що йому є
  # на чому: писачів немає ніде в `app/`, тож рядок, який створює прод
  # (`Tree#ensure_calibration`), назавжди лишається на дефолтах. Червоніє в день, коли
  # зміниться дефолт або зʼявиться писач — тобто рівно на пускачі, названому в `04_01`.
  describe "рядок у продовій формі (писача не існує)" do
    let(:calibration) { create(:tree).device_calibration }

    it "не є drift-critical, тож канал апаратної несправності не має чим вистрелити" do
      expect(calibration.temperature_offset_c).to eq(0.0)
      expect(calibration.vcap_coefficient).to eq(1.0)
      expect(calibration.sensor_drift_critical?).to be false
    end

    it "нормалізує тотожно по обох осях — «нормалізований» вимір дорівнює сирому" do
      expect(calibration.normalize_temperature(23.5)).to eq(23.5)
      expect(calibration.normalize_voltage(3300)).to eq(3300)
    end
  end

  describe ".critical_drift scope" do
    it "returns calibrations with temperature offset exceeding threshold" do
      tree = create(:tree)
      cal = create(:device_calibration, tree: tree, temperature_offset_c: 6.0)
      expect(described_class.critical_drift).to include(cal)
    end

    it "excludes calibrations within thresholds" do
      tree = create(:tree)
      cal = create(:device_calibration, tree: tree, temperature_offset_c: 2.0)
      expect(described_class.critical_drift).not_to include(cal)
    end
  end

  describe "delegate :cluster_id" do
    it "delegates cluster_id to tree" do
      tree = create(:tree)
      calibration = build(:device_calibration, tree: tree)

      expect(calibration.cluster_id).to eq(tree.cluster_id)
    end
  end

  describe "#check_for_hardware_fault (after_save callback)" do
    it "creates an EwsAlert when sensor drift is critical and tree has a cluster" do
      tree = create(:tree)

      expect {
        create(:device_calibration, :critical_drift, tree: tree)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.tree).to eq(tree)
      expect(alert.cluster_id).to eq(tree.cluster_id)
      expect(alert).to be_alert_type_system_fault
      expect(alert).to be_severity_medium
      expect(alert.message).to include(tree.did)
    end

    it "does not create an alert when drift is within thresholds" do
      tree = create(:tree)

      expect {
        create(:device_calibration, tree: tree)
      }.not_to change(EwsAlert, :count)
    end

    it "does not create an alert when tree has no cluster" do
      tree = create(:tree, cluster: nil)

      expect {
        create(:device_calibration, :critical_drift, tree: tree)
      }.not_to change(EwsAlert, :count)
    end

    it "does not duplicate alerts on repeated saves (deduplication via tree + type + severity)" do
      tree = create(:tree)
      calibration = create(:device_calibration, :critical_drift, tree: tree)
      original_alert = EwsAlert.last

      expect {
        calibration.update!(temperature_offset_c: 7.0)
      }.not_to change(EwsAlert, :count)

      expect(EwsAlert.last.id).to eq(original_alert.id)
    end

    it "uses tree.cluster_id without loading Cluster object (N+1 fix)" do
      tree = create(:tree)
      calibration = build(:device_calibration, :critical_drift, tree: tree)

      # Verify we access cluster_id directly from tree (FK column), not through cluster association
      allow(tree).to receive(:cluster)
      calibration.save!

      expect(tree).not_to have_received(:cluster)
    end
  end
end
