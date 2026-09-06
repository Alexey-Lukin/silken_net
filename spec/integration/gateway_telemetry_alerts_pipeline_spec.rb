# SPDX-License-Identifier: AGPL-3.0-or-later
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
    # [ARCH.54] stats = пульс v2 з ПІДПИСАНОГО QATT-header'а
    # (enqueue_envelope_health); voltage/temp у пульсі відсутні (нема ADC).
    def pulse(overrides = {})
      {
        uptime_min: 5310, cifo_fill: 12, lora_rx_drops: 0,
        coap_fail_count: 0, cellular_signal_csq: 15, flags: 0,
        ip_address: "10.0.0.2"
      }.merge(overrides)
    end

    it "creates pulse log and updates gateway" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, pulse)
      }.to change(GatewayTelemetryLog, :count).by(1)

      gateway.reload
      expect(gateway.ip_address).to eq("10.0.0.2")
      expect(gateway.last_seen_at).to be_present
      expect(GatewayTelemetryLog.last.uptime_min).to eq(5310)
    end

    it "creates critical alert for weak signal" do
      GatewayTelemetryWorker.new.perform(gateway.uid, pulse(cellular_signal_csq: 2))

      alert = EwsAlert.last
      expect(alert).to be_present
      expect(alert.severity).to eq("critical")
      # [SLASH-1 2026-09-04] Слабкий CSQ = клас каналу, не спільний кошик:
      # канон `00_04 §2` ратифікував «карати лісника за збитий шлюз = false slash».
      expect(alert.alert_type).to eq("comms_fault")
      I18n.with_locale(:uk) { expect(alert.message).to include("Слабкий сигнал") }
    end

    it "creates critical alert for degraded uplink (coap_fail ≥ поріг)" do
      GatewayTelemetryWorker.new.perform(gateway.uid, pulse(coap_fail_count: 12))

      alert = EwsAlert.last
      expect(alert).to be_present
      I18n.with_locale(:uk) { expect(alert.message).to include("провалених") }
    end

    it "rejects pulse without uptime_min (KENOSIS-гейт)" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, pulse(uptime_min: nil))
      }.not_to change(GatewayTelemetryLog, :count)
    end

    it "does not create alert for a healthy pulse" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, pulse)
      }.not_to change(EwsAlert, :count)
    end

    it "handles unknown gateway UID" do
      expect {
        GatewayTelemetryWorker.new.perform("UNKNOWN-GW", pulse)
      }.not_to change(GatewayTelemetryLog, :count)
    end

    it "accepts CSQ value 99 as valid (undetermined signal)" do
      expect {
        GatewayTelemetryWorker.new.perform(gateway.uid, pulse(cellular_signal_csq: 99))
      }.to change(GatewayTelemetryLog, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # AlertNotificationWorker
  # ---------------------------------------------------------------------------
  describe "AlertNotificationWorker" do
    let!(:tree) { create(:tree, cluster: cluster, latitude: 49.4285, longitude: 32.062) }
    let!(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let!(:admin) { create(:user, :admin, organization: organization) }
    let!(:forester) { create(:user, :forester, organization: organization) }

    before do
      allow(AlertNotificationWorker).to receive(:perform_async).and_call_original
      mailer_delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: nil)
      mailer_with = double(critical_notification: mailer_delivery) # rubocop:disable RSpec/VerifiedDoubles -- проксі від `.with(...)` віддає ActionMailer::Parameterized::Mailer, а той не ВИЗНАЧАЄ mailer-методів (method_missing) — verifying double їх не бачить за побудовою; звірено `public_method_defined?`
      allow(AlertMailer).to receive(:with).and_return(mailer_with)
    end

    # [UI.4] Обидва raw-ActionCable знято 2026-07-27. ⚠️ Тут стояло, що вони були
    # недосяжні структурно, «бо `app/channels/` у репо не існує» — це вже НЕПРАВДА
    # (SEC.25 Ф1 завела `ApplicationCable::Connection` 2026-07-28), і сама підстава
    # була хибною ще тоді: `ActionCable::Engine` монтує `/cable` сам, без рядка в
    # `routes.rb` (див. шапку `spec/security/no_raw_action_cable_spec.rb`). Пін від
    # цього не слабшає, лише міняє причину: raw-broadcast заборонений не через
    # недосяжність, а тому що імʼя каналу там — довільний рядок без жодної
    # поверхні авторизації, на відміну від підписаного Turbo-тракту.
    it "does not reach for raw ActionCable — the alert rides the signed Turbo tract" do
      AlertNotificationWorker.new.perform(alert.id)

      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    # 🔴 [E.33] ДРУГИЙ сайт того самого класу: приклад пінив енкʼю ОБОХ каналів у
    # тест-середовищі, де `TELEGRAM_BOT_TOKEN` не заданий, а `available?(:push)` —
    # жорсткий `false`. Тобто інтеграційний пін стверджував доставку транспортами,
    # яких платформа не має. Лік був — стабити ТРАНСПОРТ, не предикат.
    #
    # ⚫ [ARCH.60] Той транспорт зрізано ⚖️ founder 2026-09-06, і з ним пішла сама
    # можливість такого стабу: у `OPERATIONAL_CHANNELS` лишився самий `:push`,
    # ратифіковано недоступний [ARCH.108], тож без втручання набір порожній і
    # воркер повертає 0 ще до `push_bulk`.
    # 🔒 ОГОЛОШЕНА ДЕГРАДАЦІЯ: стаб тепер стоїть на самому предикаті, отже приклад
    # більше НЕ свідчить, що предикат правдиво читає платформу — він свідчить лише
    # про маршрут ПІСЛЯ нього: кого саме воркер кладе в чергу і яким каналом.
    # Правдивість предиката несе `spec/services/notifications/delivery_channels_spec.rb`.
    it "enqueues notifications for critical alerts to admin/forester — only via LIVE channels" do
      allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
      allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)

      AlertNotificationWorker.new.perform(alert.id)

      # [A-4]: push_bulk enqueues jobs via Sidekiq::Client, verified through .jobs in fake mode
      jobs = SingleNotificationWorker.jobs
      sms_args = jobs.select { |j| j["args"][2] == "sms" }.map { |j| j["args"][0] }
      push_args = jobs.select { |j| j["args"][2] == "push" }.map { |j| j["args"][0] }

      # [ARCH.78] SMS відкинуто присудом 2026-08-20 — джоб немає навіть для critical.
      expect(sms_args).to be_empty
      expect(push_args).to contain_exactly(admin.id, forester.id)
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
    let!(:user) { create(:user, :forester, organization: organization) }

    # [ARCH.78] SMS відкинуто — застарілий продюсер потрапляє в гучну
    # unknown-гілку, але воркер не падає (5 ретраїв тут нічого не полікують).
    it "survives a retired sms job without raising" do
      expect { SingleNotificationWorker.new.perform(user.id, alert.id, "sms") }.not_to raise_error
    end

    it "handles push channel" do
      expect { SingleNotificationWorker.new.perform(user.id, alert.id, "push") }.not_to raise_error
    end

    it "skips when user not found" do
      expect { SingleNotificationWorker.new.perform(-1, alert.id, "push") }.not_to raise_error
    end

    it "skips when alert not found" do
      expect { SingleNotificationWorker.new.perform(user.id, -1, "push") }.not_to raise_error
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

      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
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

      UnpackTelemetryWorker.new.perform(encoded, gateway.ip_address, nil)

      expect(TelemetryUnpackerService).to have_received(:call)
    end

    it "skips unknown gateway" do
      encoded = Base64.strict_encode64("X" * 48)
      UnpackTelemetryWorker.new.perform(encoded, "192.168.99.99", "UNKNOWN-UID")

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "skips when no hardware key found" do
      hw_key.destroy!
      encoded = Base64.strict_encode64("X" * 48)
      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "handles corrupted Base64 gracefully" do
      expect { UnpackTelemetryWorker.new.perform("NOT_VALID_BASE64!!!", "10.0.0.1", gateway.uid) }.not_to raise_error

      expect(TelemetryUnpackerService).not_to have_received(:call)
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

      UnpackTelemetryWorker.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
    end
  end
end
