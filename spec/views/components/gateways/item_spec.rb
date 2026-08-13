# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [TEST.12] Конвертовано з OpenStruct-моку на РЕАЛЬНІ незбережені записи, і
# конверсія оголила два дефекти, які мок ховав за побудовою.
#
# 🔴 (1) LED судив живість власним `last_seen_at&.after?(5.minutes.ago)`, тоді як
# дім цього питання — `Gateway#online?` (`config_sleep_interval_s * 1.2`). Мок
# подавав 1 хв / 10 хв, тобто значення по різні боки САМЕ 5-хвилинної межі, тож
# приклади проходили однаково з дефектом і без нього. Тепер фікстура має явний
# `config_sleep_interval_s`, і приклади ставлять час відносно НЬОГО.
#
# 🔴 (2) `signal_quality_percentage: 78` — значення, якого модель НЕ ВИРОБЛЯЄ:
# воно деривується як `(csq / 31.0 * 100).round(1)`, тобто крок ≈3.2 (csq 24 →
# 77.4, csq 25 → 80.6). Спека пінила недосяжне число, а сама деривація не
# перевірялась ЖОДНОГО разу — рівно вісь «мок вигадує ТИП/значення».
RSpec.describe Gateways::Item do
  # `Gateway.new` + `Cluster.new` — реальні типи й реальні методи, нуль БД.
  # `active_trees_count` — справжня counter-cache колонка `Cluster`.
  def build_gateway(uid: "SNET-Q-AAB01234", last_seen_at: 1.minute.ago,
                    sleep_s: 300, cluster_name: "Carpathian-Alpha",
                    active_trees_count: 12, csq: 24)
    gateway = Gateway.new(
      id: 1, uid: uid, last_seen_at: last_seen_at, config_sleep_interval_s: sleep_s,
      cluster: cluster_name && Cluster.new(name: cluster_name, active_trees_count: active_trees_count)
    )
    log = csq && GatewayTelemetryLog.new(cellular_signal_csq: csq)
    gateway.define_singleton_method(:latest_gateway_telemetry_log) { log }
    gateway
  end

  let(:gateway) { build_gateway }
  let(:html) { render_component(gateway: gateway) }

  describe "header" do
    it "displays Queen // UID" do
      expect(html).to include("Queen // SNET-Q-AAB01234")
    end

    it "displays the cluster name" do
      expect(html).to include("Cluster: Carpathian-Alpha")
    end

    it "shows UNASSIGNED when cluster is nil" do
      rendered = render_component(gateway: build_gateway(cluster_name: nil))
      expect(rendered).to include("UNASSIGNED")
    end
  end

  describe "stats section" do
    it "displays soldiers count" do
      expect(html).to include("Soldiers")
      expect(html).to include("12")
    end

    # Значення тепер ДЕРИВОВАНЕ, а не подане: csq 24 → 77.4 %. Пін заразом
    # перевіряє саму формулу, чого мок не вмів у принципі.
    it "derives the signal percentage from the raw CSQ" do
      expect(html).to include("Signal")
      expect(html).to include("77.4%")
    end

    it "renders 0% for the sentinel CSQ 99 (модем каже «невідомо»)" do
      rendered = render_component(gateway: build_gateway(csq: 99))
      expect(rendered).to include("0%")
    end

    it "shows 0% signal when no telemetry log" do
      rendered = render_component(gateway: build_gateway(csq: nil))
      expect(rendered).to include("0%")
    end
  end

  describe "footer" do
    it "displays formatted last_seen_at" do
      frozen_time = Time.zone.parse("2025-03-15 14:30:00")
      rendered = render_component(gateway: build_gateway(last_seen_at: frozen_time))
      expect(rendered).to include("14:30 // 15.03")
    end

    it "shows SILENT when last_seen_at is nil" do
      rendered = render_component(gateway: build_gateway(last_seen_at: nil))
      expect(rendered).to include("SILENT")
    end

    it "renders Open Relay link" do
      expect(html).to include("Open Relay →")
    end
  end

  # 🔴 Піни нижче ставлять час відносно `config_sleep_interval_s`, а не відносно
  # вигаданої константи — інакше вони не здатні відрізнити `#online?` від будь-якого
  # рукописного порога. Сон 300 с → чесне вікно 360 с.
  describe "connection LED" do
    it "shows green LED within the gateway's OWN sleep window" do
      rendered = render_component(gateway: build_gateway(sleep_s: 300, last_seen_at: 4.minutes.ago))
      expect(rendered).to include("bg-emerald-500")
    end

    it "shows red pulsing LED past that window" do
      rendered = render_component(gateway: build_gateway(sleep_s: 300, last_seen_at: 20.minutes.ago))
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
    end

    # Дискримінатор класу: 30 хв тиші — це МЕРТВО для сну 300 с і ЖИВО для сну
    # 3600 с. Рукописний 5-хвилинний поріг дав би червоне в обох випадках, тож
    # саме цей приклад червоніє на поверненні дефекту.
    it "reads the threshold from the gateway, not from a hardcoded five minutes" do
      long_sleeper = build_gateway(sleep_s: 3600, last_seen_at: 30.minutes.ago)
      expect(render_component(gateway: long_sleeper)).to include("bg-emerald-500")

      short_sleeper = build_gateway(sleep_s: 300, last_seen_at: 30.minutes.ago)
      expect(render_component(gateway: short_sleeper)).to include("bg-red-900")
    end
  end
end
