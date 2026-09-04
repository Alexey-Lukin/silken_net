# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.54 Шар 1] Споживач пульсу Королеви: stats приходить з ПІДПИСАНОГО
# health-блоку QATT-v2 (UnpackTelemetryWorker#enqueue_envelope_health) —
# стара DID=0-милиця з voltage/temp вбита; напруги/температури v2 не несе
# (Королева без ADC — колонки лишаються nil до заліза).
RSpec.describe GatewayTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster) }

  let(:valid_stats) do
    {
      "uptime_min" => 5310,
      "cifo_fill" => 12,
      "lora_rx_drops" => 0,
      "coap_fail_count" => 0,
      "cellular_signal_csq" => 15,
      "flags" => 0,
      "ip_address" => "10.0.0.42"
    }
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "logs the gateway uid and re-raises a StandardError raised after the gateway is loaded" do
      allow_any_instance_of(described_class).to receive(:check_system_health).and_raise(StandardError, "boom")

      allow(Rails.logger).to receive(:error).with(a_string_including(gateway.uid))

      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to raise_error(StandardError, "boom")

      expect(Rails.logger).to have_received(:error).with(a_string_including(gateway.uid))
    end

    it "creates a GatewayTelemetryLog pulse record" do
      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to change(GatewayTelemetryLog, :count).by(1)

      log = GatewayTelemetryLog.last
      expect(log.uptime_min).to eq(5310)
      expect(log.cifo_fill).to eq(12)
      expect(log.lora_rx_drops).to eq(0)
      expect(log.coap_fail_count).to eq(0)
      expect(log.cellular_signal_csq).to eq(15)
      expect(log.health_flags).to eq(0)
      # v2-пульс напруги не несе — чесний nil, не фальшивий нуль
      expect(log.voltage_mv).to be_nil
      expect(log.temperature_c).to be_nil
    end

    it "updates gateway last_seen_at and IP (без voltage — нема ADC)" do
      freeze_time do
        described_class.new.perform(gateway.uid, valid_stats)

        gateway.reload
        expect(gateway.ip_address).to eq("10.0.0.42")
        expect(gateway.last_seen_at).to be_within(1.second).of(Time.current)
        expect(gateway.latest_voltage_mv).to be_nil
      end
    end

    it "accepts nil csq (модем не відповів — сентинель 0xFF на дроті)" do
      stats = valid_stats.merge("cellular_signal_csq" => nil)

      expect {
        described_class.new.perform(gateway.uid, stats)
      }.to change(GatewayTelemetryLog, :count).by(1)

      expect(GatewayTelemetryLog.last.cellular_signal_csq).to be_nil
    end

    context "with critical pulse" do
      it "creates EwsAlert for weak signal" do
        stats = valid_stats.merge("cellular_signal_csq" => 2)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        I18n.with_locale(:uk) { expect(alert.message).to include("Слабкий сигнал") }
      end

      it "creates EwsAlert for degraded uplink (coap_fail_count ≥ поріг)" do
        stats = valid_stats.merge("coap_fail_count" => 12)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        I18n.with_locale(:uk) { expect(EwsAlert.last.message).to include("провалених") }
      end

      # [SLASH-1 2026-09-04] Тип виводиться з ключа, і це НЕ косметика: предикати
      # `penalty_factor` читають `alert_type` і до `message_key` сліпі за побудовою,
      # тож поки деградований uplink їхав як `system_fault`, він годував ОБИДВА
      # предикати (1.0 + 0.5 + 0.5 = стеля) — за подію, чийого винуватця встановити
      # неможливо. Пін тримає ОБИДВІ половини: тип рядка І його невидимість для
      # `critical_unmaintained?`.
      it "деградований uplink дістає ВЛАСНИЙ тип і не годує critical_unmaintained? [SLASH-1]" do
        stats = valid_stats.merge("coap_fail_count" => 99)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.alert_type).to eq("gateway_uplink_degraded")
        expect(alert.message_key).to eq("gateway_uplink_degraded")

        # ⛔ Другу половину (невидимість для `critical_unmaintained?`) пінить
        # `blockchain_burning_service_spec` ВИКЛИКОМ справжнього предиката —
        # повторити тут список виключень означало б пінити ПРОКСІ, який
        # переживе будь-яку зміну самого предиката (guard-craft #133).
      end

      # ⛔ Дедуп ПО ТИПУ, не по кошику: спільний глушник ховав би новий тип за
      # стоячим `system_fault` іншого предмета — тобто рівно ту подію, задля
      # видимості якої тип і вирізали.
      it "стоячий system_fault НЕ глушить алерт нового типу [SLASH-1]" do
        create(:ews_alert, cluster: cluster, tree: nil,
                           alert_type: :system_fault, severity: :critical,
                           message_key: "gateway_overheat", message_params: { uid: gateway.uid, temperature_c: 71 })

        expect {
          described_class.new.perform(gateway.uid, valid_stats.merge("coap_fail_count" => 99))
        }.to change(EwsAlert, :count).by(1)

        expect(EwsAlert.last.alert_type).to eq("gateway_uplink_degraded")
      end

      it "не плодить дублікат при активному system_fault кластера (анти-спам)" do
        stats = valid_stats.merge("cellular_signal_csq" => 2)
        described_class.new.perform(gateway.uid, stats)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(EwsAlert, :count)
      end

      it "не глушиться стоячим tree-scoped system_fault (fraud/power-loss — чужий сигнал) [SLASH-1]" do
        tree = create(:tree, cluster: cluster)
        create(:ews_alert, cluster: cluster, tree: tree,
                           alert_type: :system_fault, severity: :critical,
                           message_key: "fraud_telemetry_detected", message_params: { target_date: "2026-03-14" })

        stats = valid_stats.merge("cellular_signal_csq" => 2)
        expect {
          described_class.new.perform(gateway.uid, stats)
        }.to change(EwsAlert, :count).by(1)

        expect(EwsAlert.last.tree_id).to be_nil
        expect(EwsAlert.last.message_key).to eq("gateway_weak_signal")
        I18n.with_locale(:uk) { expect(EwsAlert.last.message).to include("Слабкий сигнал") }
      end

      it "fallback-повідомлення для battery-critical (voltage поза thermal/signal-гілками; майбутній ADC-шлях)" do
        # Пульс v2 напруги не несе, але модель дозволяє legacy/ADC-рядки
        # (insert_all-ера): voltage-critical лог мусить дати чесний вердикт.
        log = gateway.gateway_telemetry_logs.create!(gateway_id: gateway.id, voltage_mv: 3000)
        key, = described_class.new.send(:health_message_key, gateway, log)
        expect(key).to eq("gateway_hardware_fault")
      end

      it "❄️-вердикт для замерзання (temperature_c < LOW_TEMPERATURE_THRESHOLD; charge-protect зона, HW.16)" do
        log = gateway.gateway_telemetry_logs.create!(gateway_id: gateway.id, temperature_c: -25)
        key, = described_class.new.send(:health_message_key, gateway, log)
        expect(key).to eq("gateway_freezing")
      end

      it "🔥-вердикт для перегріву (temperature_c > OVERHEAT_THRESHOLD)" do
        log = gateway.gateway_telemetry_logs.create!(gateway_id: gateway.id, temperature_c: 70)
        key, = described_class.new.send(:health_message_key, gateway, log)
        expect(key).to eq("gateway_overheat")
      end

      it "no_signal (csq 99) не тригерить алерт (за специфікацією 3GPP)" do
        stats = valid_stats.merge("cellular_signal_csq" => 99)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(EwsAlert, :count)
      end
    end

    context "with invalid stats (KENOSIS-гейт)" do
      it "rejects pulse without uptime_min" do
        stats = valid_stats.except("uptime_min")

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects pulse without cifo_fill" do
        stats = valid_stats.except("cifo_fill")

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end

      it "rejects out-of-range csq (не 0-31/99)" do
        stats = valid_stats.merge("cellular_signal_csq" => 42)

        expect {
          described_class.new.perform(gateway.uid, stats)
        }.not_to change(GatewayTelemetryLog, :count)
      end
    end

    it "re-raises unexpected errors for Sidekiq retry (broad-rescue не ковтає)" do
      allow(Gateway).to receive(:find_by!).and_raise(ActiveRecord::ConnectionTimeoutError, "db hiccup")

      expect {
        described_class.new.perform(gateway.uid, valid_stats)
      }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    end

    it "logs error for phantom gateway without raising" do
      expect {
        described_class.new.perform("SNET-Q-DEADBEEF", valid_stats)
      }.not_to change(GatewayTelemetryLog, :count)
    end
  end
end
