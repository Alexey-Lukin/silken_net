# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateways::Show do
  let(:gateway) { mock_gateway }
  let(:latest_log) { build_latest_log }
  let(:active_soldiers) { [ mock_soldier ] }
  let(:html) { render_component(gateway: gateway, latest_log: latest_log, active_soldiers: active_soldiers) }

  def mock_gateway(uid: "SNET-Q-AAB01234", state: "active", ip_address: "192.168.1.42",
                   last_seen_at: 1.minute.ago, cluster_name: "Carpathian-Alpha",
                   sleep_interval: 120, firmware_version: "2.1.0",
                   hardware_key_uid: "HK-001")
    # [TEST.12] Реальний незбережений запис: `OpenStruct` мовчки віддавав `nil`
    # на `online?`, тож лампа зв'язку була невидима для сюїти в обидва боки.
    gw = Gateway.new(
      id: 1,
      uid: uid,
      state: state,
      ip_address: ip_address,
      last_seen_at: last_seen_at,
      cluster: Cluster.new(name: cluster_name),
      config_sleep_interval_s: sleep_interval,
      firmware_version: firmware_version
    )
    allow(gw).to receive(:hardware_key).and_return(HardwareKey.new(device_uid: hardware_key_uid))
    gw
  end

  # [TEST.12] Реальний незбережений `GatewayTelemetryLog`, і фікстура годує ДЖЕРЕЛО.
  # `signal_quality_percentage` — не колонка, а метод, що виводить відсоток із CSQ,
  # тож доти мок суперечив сам собі: клав відсоток НЕЗАЛЕЖНО від `cellular_signal_csq`,
  # який сусідній приклад пінить тим самим рендером. Пара була недосяжною для будь-якого
  # реального запису, і саме перетворення не перевірялось ніколи.
  #
  # 🔴 `voltage_mv`/`temperature_c` — колонки `numeric`, тобто BigDecimal: у проді це
  # «4100.0»/«23.0», а не «4100»/«23». Доти фікстура подавала Integer, тож питання «як
  # ТИП рендериться в рядок» із сюїти неможливо було поставити.
  def build_latest_log(cellular_signal_csq: 18, voltage_mv: 4100, temperature_c: 23)
    GatewayTelemetryLog.new(
      cellular_signal_csq: cellular_signal_csq,
      voltage_mv: voltage_mv,
      temperature_c: temperature_c
    )
  end

  # [TEST.12] Реальний незбережений Tree: `active?` — AASM-предикат над enum-колонкою
  # `status`, тож фікстура годує ДЖЕРЕЛО (OpenStruct вигадував сам вердикт і лишав
  # деривацію неперевіреною). `under_threat?` на незбереженому записі чесно false
  # (порожня асоціація без запиту); загрозна гілка дістається стабом САМОГО ридера —
  # той самий хід, що UI.4 на недосяжній дефолт-гілці.
  def mock_soldier(did: "SNET-00000001", active: true, under_threat: false)
    soldier = Tree.new(did: did, status: active ? :active : :dormant)
    allow(soldier).to receive(:under_threat?).and_return(true) if under_threat
    soldier
  end

  describe "argument validation" do
    it "raises ArgumentError if gateway does not respond to :uid" do
      expect {
        component_class.new(gateway: Object.new, latest_log: nil, active_soldiers: [])
      }.to raise_error(ArgumentError, /uid/)
    end
  end

  describe "status header" do
    # [I18N.1] Заголовок реюзає канонічний `gateways.show_title` (той самий, що
    # контролер кладе у <title>) — доти екран і вкладка розходились словом «Relay»,
    # якого не мала жодна локаль.
    it "displays the canonical show_title with UID" do
      expect(html).to include("Queen // SNET-Q-AAB01234")
    end

    it "renders the show_title in the viewer's locale (uk)" do
      rendered = I18n.with_locale(:uk) { render_component(gateway: gateway, latest_log: latest_log, active_soldiers: active_soldiers) }
      expect(rendered).to include("Королева // SNET-Q-AAB01234")
    end

    it "displays the IP address" do
      expect(html).to include("192.168.1.42")
    end

    it "shows 0.0.0.0 when IP is nil" do
      gw = mock_gateway(ip_address: nil)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("0.0.0.0")
    end

    it "shows heartbeat timestamp" do
      frozen_time = Time.zone.parse("2025-03-15 14:30:00")
      gw = mock_gateway(last_seen_at: frozen_time)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("14:30:00 // 15.03.25")
    end

    it "shows SILENT when last_seen_at is nil" do
      gw = mock_gateway(last_seen_at: nil)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("SILENT")
    end
  end

  # Стан іде через спільний `StatusBadge` (I18N.1, 2026-08-05) — приватна
  # `state_badge_classes` знесена. Піни на семантичні токени бейджа.
  describe "state badge" do
    # 🔴 `active` тут НЕСУЧИЙ: доти цей запис у спільній мапі належав `EwsAlert`
    # і був `danger`, тож дротування пофарбувало б живий шлюз у червоне.
    # [TEST.12] `>active<` — текст МІЖ тегами: голий include("active") був
    # вакуумний, слово тримає й aria-стрічка флоту («Soldier …: active»).
    it "renders active state with the success token" do
      expect(html).to include(">active<")
      expect(html).to include("bg-status-success")
      expect(html).not_to include("bg-status-danger")
    end

    it "renders updating state with the warning token" do
      gw = mock_gateway(state: "updating")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("updating")
      expect(rendered).to include("bg-status-warning")
    end

    it "renders maintenance state with the info token" do
      gw = mock_gateway(state: "maintenance")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("maintenance")
      expect(rendered).to include("bg-status-info")
    end

    it "renders faulty state with the danger token" do
      gw = mock_gateway(state: "faulty")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("faulty")
      expect(rendered).to include("bg-status-danger")
    end

    # [TEST.12] Гілка досяжна лише стабом РИДЕРА: enum `state` кидає
    # `ArgumentError` уже в конструкторі, тож приклад, що подавав «quarantined»
    # як значення, ходив входом, якого в проді не буває.
    it "renders an unrecognized state with the neutral fallback" do
      gw = mock_gateway
      allow(gw).to receive(:state).and_return("quarantined")
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("quarantined")
      expect(rendered).to include("bg-status-neutral")
    end
  end

  describe "technical matrix" do
    # 🔴 Відсоток ВИВОДИТЬСЯ з того самого CSQ, який сусідній приклад пінить окремо.
    # Доти мок задавав обидва незалежно, тож пара була самосуперечливою і жоден
    # реальний запис її не дав би.
    it "derives signal strength from the CSQ it also displays" do
      expect(html).to include("Signal Strength")
      expect(html).to include("58.1%")
      expect(html).not_to include("85%")
    end

    it "displays CSQ value" do
      expect(html).to include("CSQ: 18")
    end

    # ⚠️ Обидві колонки `numeric` → BigDecimal, тож рендер несе десяткову частку.
    # Пін навмисно на повну форму: доти фікстура подавала Integer, і питання «як тип
    # рендериться в рядок» із сюїти неможливо було поставити.
    it "displays voltage in mV with the decimal the numeric column really carries" do
      expect(html).to include("Voltage Matrix")
      expect(html).to include("4100.0")
    end

    it "displays temperature in °C with its numeric decimal" do
      expect(html).to include("Thermal State")
      expect(html).to include("23.0°C")
    end

    # [ARCH.84] 🔴 Приклад цементував дефект і зізнавався в назві («falls back to 0»).
    # Обидва нулі були вигадані: 0% читалось як «модем на звʼязку, якість нульова», а
    # «CSQ: 0» — це ВАЛІДНИЙ вимір (−113 dBm, гранична чутливість), тож підстановка
    # робила «не відповів» невідрізнимим від «на межі».
    # ⚠️ Пін цілиться в «CSQ: 0», а НЕ в голе «0%» — і це виміряно, не вгадано:
    # `style="width: 0%"` живе в прогрес-барі того ж екрана, тож широкий матч
    # проходив би через сусідній вузол і червонів на здоровому коді.
    it "says NOT MEASURED without telemetry, never a fabricated zero" do
      rendered = render_component(gateway: gateway, latest_log: nil, active_soldiers: active_soldiers)

      expect(rendered).to include(I18n.t("ui.measurement.not_measured"))
      expect(rendered).not_to include("CSQ: 0")
    end
  end

  describe "battery color" do
    it "shows red border when voltage is below 3400mV" do
      log = build_latest_log(voltage_mv: 3200)
      rendered = render_component(gateway: gateway, latest_log: log, active_soldiers: active_soldiers)
      expect(rendered).to include("border-red-900")
    end

    it "shows emerald border when voltage is healthy" do
      log = build_latest_log(voltage_mv: 4100)
      rendered = render_component(gateway: gateway, latest_log: log, active_soldiers: active_soldiers)
      expect(rendered).not_to include("border-red-900")
    end
  end

  describe "soldier fleet overview" do
    it "displays active soldiers count" do
      expect(html).to include("1 Active nodes")
    end

    it "renders soldier node indicator with DID" do
      expect(html).to include("SNET-00000001")
    end

    it "renders emerald indicator for active soldier" do
      expect(html).to include("border-emerald-500")
    end

    it "renders gray indicator for inactive soldier" do
      soldiers = [ mock_soldier(did: "SNET-INACTIVE", active: false) ]
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: soldiers)
      expect(rendered).to include("border-gray-800")
    end

    it "renders red pulsing indicator for under-threat soldier" do
      soldiers = [ mock_soldier(did: "SNET-THREAT", active: true, under_threat: true) ]
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: soldiers)
      expect(rendered).to include("border-red-600")
      expect(rendered).to include("animate-pulse")
    end

    it "handles empty soldier list" do
      rendered = render_component(gateway: gateway, latest_log: latest_log, active_soldiers: [])
      expect(rendered).to include("0 Active nodes")
    end
  end

  describe "network config" do
    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "shows UNASSIGNED when cluster is nil" do
      gw = mock_gateway(cluster_name: nil)
      gw.cluster = nil
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("UNASSIGNED")
    end

    it "displays sleep interval" do
      expect(html).to include("120s")
    end

    it "displays firmware version" do
      expect(html).to include("2.1.0")
    end

    # [UI.10] Присуд founder 2026-08-14: рядок «Firmware Hash» знято, бо джерела
    # для нього не існувало ніколи. Пін лишається як заборона його повернення —
    # він мусить уміти впасти, тому пінить ВІДСУТНІСТЬ підпису поруч із
    # ПРИСУТНІСТЮ сусіда, чиє джерело живе (інакше приклад був би зелений і на
    # порожній сторінці). ⚠️ «Firmware Version» тут несуче: без нього пін не
    # відрізняє «рядок знято» від «панель не відрендерилась».
    it "більше не малює безджерельний рядок хешу прошивки" do
      expect(Gateway.new).not_to respond_to(:firmware_hash)
      expect(html).to include("Firmware Version")
      expect(html).not_to include("Firmware Hash")
    end
  end

  describe "hardware vault" do
    it "displays hardware key UID" do
      expect(html).to include("HK-001")
    end

    it "shows UNDEFINED when hardware key is nil" do
      gw = mock_gateway(hardware_key_uid: nil)
      gw.hardware_key = nil
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("UNDEFINED")
    end
  end

  describe "OTA evolution (SEC.20)" do
    it "subscribes to the gateway's personal ota channel" do
      expect(html).to include("turbo-cable-stream-source")
    end

    it "renders the progress bar target with IDLE initial state" do
      expect(html).to include("ota_progress_SNET-Q-AAB01234")
      expect(html).to include("IDLE")
    end

    it "renders TRANSMITTING when the gateway is updating" do
      gw = mock_gateway(state: "updating")
      gw.define_singleton_method(:updating?) { true }
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("TRANSMITTING")
    end

    it "renders PENDING when firmware is targeted but not yet polled" do
      gw = mock_gateway
      gw.pending_firmware_id = 42
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("PENDING")
    end
  end

  # Піни цілять у САМУ лампу (`rotate-45` не має інших носіїв на цій сторінці):
  # голий `include("bg-emerald-500")` задовольнявся будь-яким зеленим елементом
  # сторінки, тож був зелений при обох поведінках.
  describe "connection LED" do
    it "shows green LED when recently seen" do
      gw = mock_gateway(last_seen_at: 1.minute.ago)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("rotate-45 bg-emerald-500")
    end

    it "shows red pulsing LED when not recently seen" do
      gw = mock_gateway(last_seen_at: 10.minutes.ago)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("rotate-45 bg-red-900")
      expect(rendered).to include("animate-pulse")
    end

    # [UI.10] Поріг належить Королеві: при годинному сні десять хвилин мовчання —
    # норма, і локальні «5 хвилин» називали такий шлюз мертвим.
    it "keeps a long-sleeping gateway green well past five minutes" do
      gw = mock_gateway(last_seen_at: 10.minutes.ago, sleep_interval: 3600)
      rendered = render_component(gateway: gw, latest_log: latest_log, active_soldiers: active_soldiers)
      expect(rendered).to include("rotate-45 bg-emerald-500")
    end
  end
end
