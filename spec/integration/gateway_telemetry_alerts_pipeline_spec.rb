# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Gateway telemetry relay and alert notification pipeline" do
  let(:organization) { create(:organization, billing_email: "ops@forest.org") }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
    allow(AlertNotificationWorker).to receive(:perform_async)
  end

  # ---------------------------------------------------------------------------
  # GatewayTelemetryWorker
  # ---------------------------------------------------------------------------
  describe "GatewayTelemetryWorker" do
    it "creates telemetry log and updates gateway" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, {
          voltage_mv: 4200,
          temperature_c: 25.0,
          cellular_signal_csq: 15,
          ip_address: "10.0.0.2"
        })
      }.to change(GatewayTelemetryLog, :count).by(1)

      gateway.reload
      expect(gateway.ip_address).to eq("10.0.0.2")
      expect(gateway.last_seen_at).to be_present
    end

    it "creates critical alert for low battery" do
      allow(AlertNotificationWorker).to receive(:perform_async)

      GatewayTelemetryWorker.new.perform(gateway.uid, {
        voltage_mv: 2800,
        temperature_c: 25.0,
        cellular_signal_csq: 15,
        ip_address: "10.0.0.1"
      })

      alert = EwsAlert.last
      expect(alert).to be_present
      expect(alert.severity).to eq("critical")
      expect(alert.alert_type).to eq("system_fault")
      expect(alert.message).to include("виснажена")
    end

    it "creates critical alert for overheated gateway" do
      GatewayTelemetryWorker.new.perform(gateway.uid, {
        voltage_mv: 4200,
        temperature_c: 70.0,
        cellular_signal_csq: 15,
        ip_address: "10.0.0.1"
      })

      alert = EwsAlert.last
      expect(alert).to be_present
      expect(alert.message).to include("перегріта")
    end

    it "creates critical alert for weak signal" do
      GatewayTelemetryWorker.new.perform(gateway.uid, {
        voltage_mv: 4200,
        temperature_c: 25.0,
        cellular_signal_csq: 2,
        ip_address: "10.0.0.1"
      })

      alert = EwsAlert.last
      expect(alert).to be_present
      expect(alert.message).to include("Слабкий сигнал")
    end

    it "rejects invalid sensor data" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, {
          voltage_mv: nil,
          temperature_c: 25.0,
          cellular_signal_csq: 15
        })
      }.not_to change(GatewayTelemetryLog, :count)
    end

    it "does not create alert for normal telemetry data" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, {
          voltage_mv: 4200,
          temperature_c: 25.0,
          cellular_signal_csq: 15,
          ip_address: "10.0.0.1"
        })
      }.not_to change(EwsAlert, :count)
    end

    it "handles unknown gateway UID" do
      expect {
        GatewayTelemetryWorker.new.perform("UNKNOWN-GW", {
          voltage_mv: 4200,
          temperature_c: 25.0,
          cellular_signal_csq: 15
        })
      }.not_to change(GatewayTelemetryLog, :count)
    end

    it "accepts CSQ value 99 as valid (undetermined signal)" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, {
          voltage_mv: 4200,
          temperature_c: 25.0,
          cellular_signal_csq: 99,
          ip_address: "10.0.0.1"
        })
      }.to change(GatewayTelemetryLog, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # AlertNotificationWorker
  # ---------------------------------------------------------------------------
  describe "AlertNotificationWorker" do
    let!(:tree) { create(:tree, cluster: cluster, latitude: 49.4285, longitude: 32.062) }
    let!(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let!(:admin) { create(:user, :admin, organization: organization, phone_number: "+380501234567") }
    let!(:forester) { create(:user, :forester, organization: organization) }

    before do
      allow(AlertNotificationWorker).to receive(:perform_async).and_call_original
      allow(SingleNotificationWorker).to receive(:perform_async)
      allow(AlertMailer).to receive_message_chain(:with, :critical_notification, :deliver_later)
    end

    it "broadcasts alert to cluster and organization channels" do
      expect(ActionCable.server).to receive(:broadcast).with("cluster_#{cluster.id}_alerts", hash_including(:id, :severity))
      expect(ActionCable.server).to receive(:broadcast).with("org_#{organization.id}_alerts", hash_including(:id, :severity))

      AlertNotificationWorker.new.perform(alert.id)
    end

    it "sends SMS notifications for critical alerts to admin/forester" do
      AlertNotificationWorker.new.perform(alert.id)

      expect(SingleNotificationWorker).to have_received(:perform_async).with(admin.id, alert.id, "sms")
      expect(SingleNotificationWorker).to have_received(:perform_async).with(admin.id, alert.id, "push")
      expect(SingleNotificationWorker).to have_received(:perform_async).with(forester.id, alert.id, "push")
    end

    it "does not crash for non-existent alert" do
      expect { AlertNotificationWorker.new.perform(-1) }.not_to raise_error
    end

    it "uses cluster geo_center when tree has no coordinates" do
      alert_without_tree = create(:ews_alert, cluster: cluster, tree: nil)
      expect { AlertNotificationWorker.new.perform(alert_without_tree.id) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # SingleNotificationWorker
  # ---------------------------------------------------------------------------
  describe "SingleNotificationWorker" do
    let!(:alert) { create(:ews_alert, :fire, cluster: cluster) }
    let!(:user) { create(:user, :forester, organization: organization, phone_number: "+380501234567") }

    it "handles SMS channel" do
      expect { SingleNotificationWorker.new.perform(user.id, alert.id, "sms") }.not_to raise_error
    end

    it "handles push channel" do
      expect { SingleNotificationWorker.new.perform(user.id, alert.id, "push") }.not_to raise_error
    end

    it "skips when user not found" do
      expect { SingleNotificationWorker.new.perform(-1, alert.id, "sms") }.not_to raise_error
    end

    it "skips when alert not found" do
      expect { SingleNotificationWorker.new.perform(user.id, -1, "push") }.not_to raise_error
    end

    it "skips SMS when user has no phone number" do
      user.update!(phone_number: nil)
      expect { SingleNotificationWorker.new.perform(user.id, alert.id, "sms") }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # UnpackTelemetryWorker
  # ---------------------------------------------------------------------------
  describe "UnpackTelemetryWorker" do
    let!(:hw_key) { create(:hardware_key, device_uid: gateway.uid) }
    let(:raw_data) { "A" * 64 } # arbitrary payload

    before do
      allow(TelemetryUnpackerService).to receive(:call)
    end

    it "decrypts with primary key and passes to service" do
      # Build a properly encrypted payload
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = hw_key.binary_key
      iv = cipher.random_iv
      cipher.padding = 0

      data = "X" * 32 # multiple of 16
      encrypted = iv + cipher.update(data) + cipher.final
      encoded = Base64.strict_encode64(encrypted)

      expect(TelemetryUnpackerService).to receive(:call)

      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)
    end

    it "identifies gateway by IP when UID not provided" do
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = hw_key.binary_key
      iv = cipher.random_iv
      cipher.padding = 0

      data = "Y" * 32
      encrypted = iv + cipher.update(data) + cipher.final
      encoded = Base64.strict_encode64(encrypted)

      expect(TelemetryUnpackerService).to receive(:call)
      UnpackTelemetryWorker.new.perform(encoded, gateway.ip_address, nil)
    end

    it "skips unknown gateway" do
      encoded = Base64.strict_encode64("X" * 48)
      expect(TelemetryUnpackerService).not_to receive(:call)
      UnpackTelemetryWorker.new.perform(encoded, "192.168.99.99", "UNKNOWN-UID")
    end

    it "skips when no hardware key found" do
      hw_key.destroy!
      encoded = Base64.strict_encode64("X" * 48)
      expect(TelemetryUnpackerService).not_to receive(:call)
      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)
    end

    it "handles corrupted Base64 gracefully" do
      expect(TelemetryUnpackerService).not_to receive(:call)
      expect { UnpackTelemetryWorker.new.perform("NOT_VALID_BASE64!!!", "10.0.0.1", gateway.uid) }.not_to raise_error
    end

    it "falls back to previous key during grace period" do
      # Generate a previous key
      old_key = OpenSSL::Random.random_bytes(32)
      hw_key.update!(previous_aes_key_hex: old_key.unpack1("H*").upcase)

      # Encrypt with the old key
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = old_key
      iv = cipher.random_iv
      cipher.padding = 0
      data = "Z" * 32
      encrypted = iv + cipher.update(data) + cipher.final
      encoded = Base64.strict_encode64(encrypted)

      expect(TelemetryUnpackerService).to receive(:call)
      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)
    end
  end
end
