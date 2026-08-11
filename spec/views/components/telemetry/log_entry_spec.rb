# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::LogEntry do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # Єдиний виробник — `UnpackTelemetryWorker#broadcast_to_matrix`: він передає
  # сюди сам запис `Gateway`, `Time.current` і hex, ВЖЕ піднятий у верхній регістр
  # (`binary_data.unpack1("H*").upcase` — сам `unpack1` віддає нижній).
  def relay(uid: "SNET-Q-AABB0011", ip_address: "192.168.1.100")
    Gateway.new(uid: uid, ip_address: ip_address)
  end

  # Дробова частина ненульова СВІДОМО: комірка друкує `%L`, і на рівній секунді
  # пін не відрізнив би формат із мілісекундами від формату без них.
  # 🔴 Мікросекунди йдуть ОКРЕМИМ аргументом, не дробовою секундою: `45.123`
  # доїжджає як `45.122999999` (0.123 не представиться в двійковому Float), а
  # `%L` зрізає, не округлює, — тобто Float-форма мовчки дала б «122».
  def stamp = Time.zone.local(2024, 6, 15, 10, 30, 45, 123_000)

  describe "rendering" do
    let(:html) { render_component(gateway: relay, hex_payload: "DEADBEEF1234", timestamp: stamp) }

    it "renders the gateway UID" do
      expect(html).to include("SNET-Q-AABB0011")
    end

    it "displays the IP address" do
      expect(html).to include("192.168.1.100")
    end

    it "displays the hex payload" do
      expect(html).to include("DEADBEEF1234")
    end

    it "renders BATCH_RECEIVED status" do
      expect(html).to include("BATCH_RECEIVED")
    end

    it "renders the timestamp with milliseconds" do
      expect(html).to include("10:30:45.123")
    end

    it "renders as a table row" do
      expect(html).to include("<tr")
    end

    it "applies hover effect" do
      expect(html).to include("hover:bg-gaia-surface-sunken")
    end

    it "applies slide-in animation" do
      expect(html).to include("slide-in-from-left")
    end
  end

  # ⊥ Оголошений carve-out, не жива гілка. `gateway` тут НЕ буває `nil`: єдиний
  # виробник розіменовує `gateway.uid` за шість рядків до виклику, `cluster_id`
  # оголошено `NOT NULL`, а `belongs_to :cluster` обовʼязковий (виміряно). Гард
  # `&.` лишається свідомо: броадкаст стоїть у `perform` ПЕРЕД
  # `TelemetryUnpackerService.call` і власного `rescue` не має, тож виняток у
  # прикрасі UI коштував би цілого конверта телеметрії (`00_07` UI.4).
  describe "nil gateway handling (defensive branch, unreachable from the sole producer)" do
    let(:html) { render_component(gateway: nil, hex_payload: "AABB", timestamp: stamp) }

    it "shows UNKNOWN_RELAY for nil gateway" do
      expect(html).to include("UNKNOWN_RELAY")
    end

    it "shows ?.?.?.? for nil IP" do
      expect(html).to include("?.?.?.?")
    end
  end

  describe "various hex payloads" do
    it "renders short payload" do
      html = render_component(gateway: relay, hex_payload: "FF", timestamp: stamp)
      expect(html).to include("FF")
    end

    it "renders long payload" do
      long_payload = "A" * 64
      html = render_component(gateway: relay, hex_payload: long_payload, timestamp: stamp)
      expect(html).to include(long_payload)
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(gateway: relay, hex_payload: "BEEF", timestamp: stamp) }

    it "uses text-mini for timestamp" do
      expect(html).to include("text-mini")
    end

    it "uses text-micro for IP label and status" do
      expect(html).to include("text-micro")
    end

    it "uses font-mono for data display" do
      expect(html).to include("font-mono")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-gaia-primary")
    end

    it "uses tracking-widest for status text" do
      expect(html).to include("tracking-widest")
    end
  end
end
