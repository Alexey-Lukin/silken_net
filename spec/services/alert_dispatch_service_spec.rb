# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertDispatchService, type: :service do
  let(:family) { create(:tree_family) }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: family) }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow(SilkenNet::Attractor).to receive(:homeostatic?).and_return(true)
  end

  describe "defensive nil / defined?-guards" do
    def base_log(**overrides)
      instance_double(TelemetryLog, {
        tree: tree, bio_status_vm_error?: false, firmware_report_reverted?: false,
        voltage_mv: 3500, temperature_c: 25,
        bio_status_anomaly?: false, panic?: false, bio_status_stress?: false,
        acoustic_events: 10, z_value: 20.0
      }.merge(overrides))
    end

    it "uses a zero temperature offset when the tree has no device_calibration" do
      tree.device_calibration&.destroy
      log = base_log(tree: tree.reload)

      expect { described_class.analyze_and_trigger!(log) }.not_to raise_error
    end

    it "skips EmergencyResponseService when the constant is undefined (defined?-guard else)" do
      hide_const("EmergencyResponseService")

      expect { described_class.analyze_and_trigger!(base_log(bio_status_vm_error?: true)) }
        .to change(EwsAlert, :count).by(1)
    end
  end

  # [SEC.20] Reverted-біт wire fw-report = термінальний відкат на baseline:
  # окремий тип firmware_reverted (ops-дія «re-issue версією > спаленої»),
  # НЕ транзієнтний firmware_fault і тим паче не A-сет.
  describe "firmware_reverted (SEC.20 baseline-revert)" do
    def reverted_log(**overrides)
      instance_double(TelemetryLog, {
        tree: tree, bio_status_vm_error?: false, firmware_report_reverted?: true,
        firmware_report_contract_id: 42,
        voltage_mv: 3500, temperature_c: 25,
        bio_status_anomaly?: false, panic?: false, bio_status_stress?: false,
        acoustic_events: 10, z_value: 20.0
      }.merge(overrides))
    end

    it "raises firmware_reverted with the burned contract id in the message" do
      expect {
        described_class.analyze_and_trigger!(reverted_log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("firmware_reverted")
      expect(alert.severity).to eq("critical")
      expect(alert.message_key).to eq("firmware_reverted")
      I18n.with_locale(:uk) { expect(alert.message).to include("ВІДКАТ ПРОШИВКИ").and include("42") }
      expect(EwsAlert.alert_type_vandalism_breach).to be_empty
    end

    it "does not raise firmware_reverted for a healthy frame (bit clear)" do
      expect {
        described_class.analyze_and_trigger!(reverted_log(firmware_report_reverted?: false))
      }.not_to change(EwsAlert, :count)
    end
  end

  # [SLASH-1 P0] Wire status=3 = BIO_STATUS_VM_ERROR (софт-збій), НЕ tamper:
  # firmware_fault (ops-тріаж), НІКОЛИ vandalism_breach (positive-A сигнал).
  describe "firmware fault vs low-voltage logic" do
    it "raises firmware_fault (NOT vandalism_breach) for a vm_error frame" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: true,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("firmware_fault")
      expect(alert.severity).to eq("critical")
      expect(alert.message_key).to eq("firmware_fault")
      I18n.with_locale(:uk) { expect(alert.message).to include("ЗБІЙ ПРОШИВКИ") }
      expect(EwsAlert.alert_type_vandalism_breach).to be_empty
    end

    it "continues fire analysis after a vm_error (sensor half of the frame is real)" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: true,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 80,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(2)

      alert_types = EwsAlert.last(2).map(&:alert_type)
      expect(alert_types).to include("firmware_fault")
      expect(alert_types).to include("fire_detected")
    end

    it "continues fire analysis when voltage is low but no tamper" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 50,
        temperature_c: 80,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(2)

      alert_types = EwsAlert.last(2).map(&:alert_type)
      expect(alert_types).to include("system_fault")
      expect(alert_types).to include("fire_detected")
    end

    it "does not trigger fire when voltage is low but temperature is normal" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 50,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("system_fault")
    end
  end

  # [SLASH-1] acoustic-vs-thermal: anomaly без жару = вирубка, не вогонь.
  describe "chainsaw vs fire discriminator" do
    it "routes acoustic anomaly WITHOUT heat to chainsaw_detected" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3300,
        temperature_c: 25,
        bio_status_anomaly?: true,
        panic?: false
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("chainsaw_detected")
      expect(alert.severity).to eq("critical")
      expect(alert.message_key).to eq("chainsaw_detected")
      I18n.with_locale(:uk) { expect(alert.message).to include("Акустична аномалія") }
    end

    it "keeps thermal breach as fire_detected even when anomaly flag is set" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3300,
        temperature_c: 80,
        bio_status_anomaly?: true
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("fire_detected")
    end

    it "marks panic-TX provenance in the chainsaw message" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3300,
        temperature_c: 25,
        bio_status_anomaly?: true,
        panic?: true
      )

      described_class.analyze_and_trigger!(log)

      expect(EwsAlert.last.message_key).to eq("chainsaw_detected_panic")
      I18n.with_locale(:uk) { expect(EwsAlert.last.message).to include("PANIC-TX") }
    end

    # [SLASH-1] РЕАЛЬНА пилка: Trigger_Emergency_LoRa_TX шле status=homeostasis +
    # PANIC_FLAG + acoustic=0xFF (255) + vcap=0 — до фікса падала у seismic_anomaly
    # (255≥200) повз chainsaw-маршрут, а vcap=0 плодив фантомний system_fault.
    it "routes a REAL chainsaw panic frame (status=homeostasis) to chainsaw_detected, not seismic" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 0,          # panic-кадр свідомо несе vcap=0 (legacy-parity)
        temperature_c: 0,
        bio_status_anomaly?: false, # пилка НЕ ставить anomaly — status лишається homeostasis
        panic?: true,
        acoustic_events: 255
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("chainsaw_detected")
      expect(alert.message_key).to eq("chainsaw_detected_panic")
      I18n.with_locale(:uk) { expect(alert.message).to include("PANIC-TX") }
      expect(EwsAlert.alert_type_system_fault).to be_empty # vcap=0 panic ≠ «втрата живлення»
      expect(EwsAlert.alert_type_seismic_anomaly).to be_empty
    end
  end

  describe "cache invalidation on critical alerts" do
    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "clears oracle yield cache when a critical alert is created" do
      Rails.cache.write("oracle_expected_yield_24h", 42.0)

      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: true,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      expect(Rails.cache.read("oracle_expected_yield_24h")).to be_nil
    end

    it "does not clear oracle yield cache for non-critical alerts" do
      Rails.cache.write("oracle_expected_yield_24h", 42.0)

      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: true,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      expect(Rails.cache.read("oracle_expected_yield_24h")).to eq(42.0)
    end
  end

  describe "seismic anomaly branch" do
    it "creates a critical seismic_anomaly alert when acoustic_events >= 200" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 200,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("seismic_anomaly")
      expect(alert.severity).to eq("critical")
      expect(alert.message_key).to eq("seismic_anomaly")
      I18n.with_locale(:uk) { expect(alert.message).to include("СЕЙСМІКА") }
    end
  end

  describe "pest detection branch" do
    let(:family_with_sap) { create(:tree_family, sap_flow_index: 1.0) }
    let(:tree_with_sap) { create(:tree, cluster: cluster, tree_family: family_with_sap) }

    it "creates medium severity insect_epidemic alert when bio_status is stress" do
      log = instance_double(TelemetryLog,
        tree: tree_with_sap,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: true,
        acoustic_events: 100,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      pest_alert = EwsAlert.where(tree: tree_with_sap, alert_type: :insect_epidemic).last
      expect(pest_alert).to be_present
      expect(pest_alert.severity).to eq("medium")
    end

    it "creates low severity insect_epidemic alert when bio_status is not stress" do
      log = instance_double(TelemetryLog,
        tree: tree_with_sap,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 100,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      pest_alert = EwsAlert.where(tree: tree_with_sap, alert_type: :insect_epidemic).last
      expect(pest_alert).to be_present
      expect(pest_alert.severity).to eq("low")
    end
  end

  describe "attractor homeostasis check" do
    it "creates drought alert when attractor says NOT homeostatic" do
      allow(SilkenNet::Attractor).to receive(:homeostatic?).and_return(false)

      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 99.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("severe_drought")
      expect(alert.message_key).to eq("attractor_destabilised")
      I18n.with_locale(:uk) { expect(alert.message).to include("АТРАКТОР") }
    end
  end

  describe "adaptive thresholds" do
    let(:family_custom) { create(:tree_family, fire_resistance_rating: 80, sap_flow_index: 2.0) }
    let(:tree_custom) { create(:tree, cluster: cluster, tree_family: family_custom) }

    it "uses family fire_resistance_rating when cluster has no custom threshold" do
      log = instance_double(TelemetryLog,
        tree: tree_custom,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 70,  # above default 60 but below family's 80
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end

    it "triggers fire alert when temperature reaches family's custom threshold" do
      log = instance_double(TelemetryLog,
        tree: tree_custom,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 80,  # exactly at family's fire_resistance_rating
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("fire_detected")
    end

    it "uses cluster custom_fire_threshold over family rating when available" do
      cluster.update!(custom_fire_threshold: 90)

      log = instance_double(TelemetryLog,
        tree: tree_custom,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 85,  # above family's 80 but below cluster's 90
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end

    it "adapts pest_limit by sap_flow_index" do
      # pest_limit = 50 * 2.0 = 100
      log = instance_double(TelemetryLog,
        tree: tree_custom,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 90,  # above default 50 but below adapted 100
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end

    it "triggers pest alert when acoustic_events exceed adapted pest_limit" do
      log = instance_double(TelemetryLog,
        tree: tree_custom,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 110,  # above adapted 100, below seismic 200
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)
      pest_alert = EwsAlert.where(alert_type: :insect_epidemic).last
      expect(pest_alert).to be_present
    end
  end

  describe "silence key behavior" do
    it "prevents duplicate alerts of same type within 5 minutes" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 250,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.to change(EwsAlert, :count).by(1)

      # Same alert type should be silenced
      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end
  end

  describe "rate limiting (SEC.10)" do
    it "suppresses critical alerts after MAX_ALERTS_PER_DID_PER_WINDOW" do
      target_tree = create(:tree, cluster: cluster, tree_family: family)

      # Pre-populate the rate counter to simulate 5 prior critical alerts
      time_bucket = Time.current.to_i / AlertDispatchService::DID_RATE_LIMIT_WINDOW.to_i
      rate_key = "ews_did_rate:#{target_tree.did}:#{time_bucket}"
      Rails.cache.write(rate_key, AlertDispatchService::MAX_ALERTS_PER_DID_PER_WINDOW,
                        expires_in: AlertDispatchService::DID_RATE_LIMIT_WINDOW * 2)

      # This alert should be suppressed by rate limiting
      log = instance_double(TelemetryLog,
        tree: target_tree,
        bio_status_vm_error?: true,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )
      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end
  end

  describe "voltage boundary (100mV)" do
    it "triggers system_fault at exactly 99mV" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 99,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)
      expect(EwsAlert.last.alert_type).to eq("system_fault")
    end

    it "does not trigger system_fault at exactly 100mV" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 100,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      expect {
        described_class.analyze_and_trigger!(log)
      }.not_to change(EwsAlert, :count)
    end
  end

  describe "EmergencyResponseService integration" do
    it "calls EmergencyResponseService with the created alert" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: true,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)

      expect(EmergencyResponseService).to have_received(:call).with(kind_of(EwsAlert))
    end
  end

  # [SLASH-1] Раніше anomaly без жару падав у fire_detected (конфляція пилка↔пожежа);
  # спліт маршрутизує його в chainsaw_detected.
  describe "bio_status_anomaly without thermal breach" do
    it "triggers chainsaw_detected (NOT fire) when anomaly comes with normal temperature" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,  # normal temperature
        bio_status_anomaly?: true,
        panic?: false,
        bio_status_stress?: false,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)
      expect(EwsAlert.last.alert_type).to eq("chainsaw_detected")
    end
  end

  describe "drought with stress bio_status" do
    it "creates drought alert with stress message when bio_status is stress" do
      log = instance_double(TelemetryLog,
        tree: tree,
        bio_status_vm_error?: false,
        firmware_report_reverted?: false,
        voltage_mv: 3500,
        temperature_c: 25,
        bio_status_anomaly?: false,
        panic?: false,
        bio_status_stress?: true,
        acoustic_events: 10,
        z_value: 20.0
      )

      described_class.analyze_and_trigger!(log)
      expect(EwsAlert.last.message_key).to eq("hydrological_stress")
      I18n.with_locale(:uk) { expect(EwsAlert.last.message).to include("ПОСУХА") }
    end
  end

  describe ".create_fraud_alert!" do
    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "creates a critical fraud alert for the tree" do
      expect {
        described_class.create_fraud_alert!(tree, "Виявлено фрод-телеметрію")
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.severity).to eq("critical")
      expect(alert.alert_type).to eq("system_fault")
      expect(alert.message).to include("ФРОД")
      expect(alert.tree).to eq(tree)
    end

    it "is silenced by cache on second call within 30 minutes" do
      described_class.create_fraud_alert!(tree, "First fraud")

      expect {
        described_class.create_fraud_alert!(tree, "Second fraud")
      }.not_to change(EwsAlert, :count)
    end

    it "dispatches notifications via EwsAlert after_create_commit callback" do
      # [A-1 FIX]: Notification тепер відбувається через after_create_commit :dispatch_notifications!
      # замість явного AlertNotificationWorker.perform_async в сервісі.
      # Дозволяємо колбеку виконатися для перевірки повного ланцюга.
      allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!).and_call_original

      described_class.create_fraud_alert!(tree, "Fraud detected")

      expect(AlertNotificationWorker).to have_received(:perform_async).with(kind_of(Integer))
    end
  end
end
