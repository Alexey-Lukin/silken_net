# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AlertDispatchService with clusterless trees" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "tree with cluster — normal path" do
    let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates fire alert for extreme temperature" do
      log = create(:telemetry_log, tree: tree, temperature_c: 70, bio_status: :homeostasis,
                                   voltage_mv: 3500, acoustic_events: 5)
      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("fire_detected")
      expect(alert.severity).to eq("critical")
      expect(alert.cluster).to eq(cluster)
    end

    # [SLASH-1 P0] status=3 = софт-збій прошивки → firmware_fault, НЕ vandalism_breach.
    # z_value у межах породи: vm_error більше не обриває аналіз, тож фабричний
    # z=0.35 (поза 5..45) додав би ще й severe_drought.
    it "creates firmware_fault alert for a vm_error frame" do
      log = create(:telemetry_log, tree: tree, bio_status: :vm_error,
                                   temperature_c: 25, voltage_mv: 3500, acoustic_events: 5,
                                   z_value: 25.0)
      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("firmware_fault")
    end

    it "creates low voltage alert without halting analysis" do
      log = create(:telemetry_log, tree: tree, voltage_mv: 50, temperature_c: 70,
                                   bio_status: :homeostasis, acoustic_events: 5)
      # Should create both system_fault AND fire_detected
      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(2)
    end
  end

  describe "clusterless tree — does not crash" do
    let(:tree) { create(:tree, cluster: nil, tree_family: tree_family) }

    it "handles fire alert without cluster" do
      log = create(:telemetry_log, tree: tree, temperature_c: 70, bio_status: :homeostasis,
                                   voltage_mv: 3500, acoustic_events: 5)
      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.cluster).to be_nil
      expect(alert.tree).to eq(tree)
    end

    it "uses family fire_resistance_rating as fallback" do
      tree_family.update!(fire_resistance_rating: 80)
      log = create(:telemetry_log, tree: tree, temperature_c: 75, bio_status: :homeostasis,
                                   voltage_mv: 3500, acoustic_events: 5, z_value: 25.0)
      # 75°C < 80 threshold, so NO fire alert
      # z_value 25.0 is within tree_family bounds (5.0–45.0), so NO drought alert
      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .not_to change(EwsAlert, :count)
    end
  end

  describe ".create_fraud_alert!" do
    let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates a fraud alert" do
      expect { AlertDispatchService.create_fraud_alert!(tree, Date.new(2026, 3, 14)) }
        .to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      I18n.with_locale(:uk) { expect(alert.message).to include("ФРОД") }
      expect(alert.severity).to eq("critical")
    end

    it "respects silence window" do
      AlertDispatchService.create_fraud_alert!(tree, Date.new(2026, 3, 14))
      expect { AlertDispatchService.create_fraud_alert!(tree, Date.new(2026, 3, 15)) }
        .not_to change(EwsAlert, :count)
    end

    it "works for clusterless tree" do
      clusterless_tree = create(:tree, cluster: nil, tree_family: tree_family)
      expect { AlertDispatchService.create_fraud_alert!(clusterless_tree, Date.new(2026, 3, 14)) }
        .to change(EwsAlert, :count).by(1)
    end
  end
end
