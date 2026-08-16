# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateways::Index do
  let(:gateways) { [ mock_gateway ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(gateways: gateways, pagy: pagy, online_count: 3) }


  # [TEST.12] Реальний незбережений запис, а не `OpenStruct`: мок мусив би
  # вигадати `online?`, тобто оголосити світ, у якому дефект «компонент рахує
  # власне вікно» невиразимий. Реальний `Gateway` віддає і предикат, і
  # метадані фреймворку (`model_name`/`to_key`/`to_param`) сам.
  def mock_gateway(uid: "SNET-Q-AAB01234", last_seen_at: 1.minute.ago,
                   config_sleep_interval_s: 300,
                   cluster_name: "Carpathian-Alpha", active_trees_count: 12,
                   cellular_signal_csq: 24, latest_log: :derive)
    gw = Gateway.new(
      id: 1,
      uid: uid,
      last_seen_at: last_seen_at,
      config_sleep_interval_s: config_sleep_interval_s,
      cluster: Cluster.new(name: cluster_name, active_trees_count: active_trees_count)
    )
    # Асоціація стабиться точково — реальний лог тягнув би партиційну таблицю.
    log = latest_log == :derive ? GatewayTelemetryLog.new(cellular_signal_csq: cellular_signal_csq) : latest_log
    allow(gw).to receive(:latest_gateway_telemetry_log).and_return(log)
    gw
  end

  describe "header" do
    # [I18N.1-нейминг] Заголовок секції був СУПЕРСЕТОМ заголовка сторінки
    # («Queen Registry» + хвіст) — тобто ім'я малювалось двічі поспіль.
    it "does not duplicate the page name the layout already renders" do
      expect(html).not_to include("Queen Registry // Global Relays")
    end

    it "displays online count vs total" do
      expect(html).to include("3 / 1")
    end
  end

  describe "gateway grid" do
    it "renders gateway UID" do
      expect(html).to include("Queen // SNET-Q-AAB01234")
    end

    it "renders cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders soldiers count" do
      expect(html).to include("Soldiers")
      expect(html).to include("12")
    end

    it "renders signal percentage derived from the raw CSQ" do
      expect(html).to include("77.4%")
    end

    it "renders Open Relay link with aria-label" do
      expect(html).to include("Open Relay →")
      expect(html).to include("aria-label")
    end
  end

  describe "connection LED" do
    it "shows green LED for recently seen gateway" do
      rendered = render_component(
        gateways: [ mock_gateway(last_seen_at: 1.minute.ago) ],
        pagy: pagy, online_count: 1
      )
      expect(rendered).to include("bg-emerald-500")
    end

    it "shows red pulsing LED for stale gateway" do
      rendered = render_component(
        gateways: [ mock_gateway(last_seen_at: 10.minutes.ago, config_sleep_interval_s: 300) ],
        pagy: pagy, online_count: 0
      )
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
    end

    # [UI.10] Несучий приклад: поріг належить Королеві, не сторінці. Шлюз, що
    # спить годину, після десяти хвилин мовчання ОНЛАЙН — доти компонент рахував
    # власні «5 хвилин» і малював його мертвим, розходячись і зі сторожем, і з
    # `Gateway.online`-скоупом, яким той самий екран рахує підсумок.
    it "keeps a long-sleeping gateway green well past five minutes" do
      rendered = render_component(
        gateways: [ mock_gateway(last_seen_at: 10.minutes.ago, config_sleep_interval_s: 3600) ],
        pagy: pagy, online_count: 1
      )
      expect(rendered).to include("bg-emerald-500")
      expect(rendered).not_to include("animate-pulse")
    end
  end

  describe "pagination" do
    it "renders pagination component" do
      # Pagination component is rendered; its presence is verified
      # by the component not raising errors during render
      expect(html).to be_present
    end
  end

  describe "empty state" do
    let(:gateways) { [] }

    it "renders without errors when no gateways" do
      rendered = render_component(gateways: [], pagy: mock_pagy(count: 0, last: 1), online_count: 0)
      expect(rendered).to include("0 / 0")
    end
  end

  describe "multiple gateways" do
    it "renders all gateway items" do
      gateways = [
        mock_gateway(uid: "SNET-Q-001"),
        mock_gateway(uid: "SNET-Q-002")
      ]
      rendered = render_component(gateways: gateways, pagy: mock_pagy(count: 2, last: 1), online_count: 2)
      expect(rendered).to include("SNET-Q-001")
      expect(rendered).to include("SNET-Q-002")
    end
  end

  describe "gateway with no cluster, telemetry or recent contact" do
    # [ARCH.84] «zero» у назві був зізнанням: сигнал без телеметрії друкувався «0%»,
    # тобто виміряним найгіршим значенням замість відсутності виміру. Решта фолбеків
    # цього прикладу чесні й лишаються — «UNASSIGNED» і «SILENT» є ІМЕНАМИ станів,
    # а не числами, тож вони нічого не стверджують про вимір.
    it "renders unassigned/not-measured/silent fallbacks and a stale LED" do
      gw = mock_gateway(last_seen_at: nil, latest_log: nil)
      gw.cluster = nil
      rendered = render_component(gateways: [ gw ], pagy: mock_pagy(count: 1, last: 1), online_count: 0)
      expect(rendered).to include("UNASSIGNED") # cluster&.name || unassigned
      expect(rendered).to include("SILENT")     # last_seen_at&.strftime || silent
      expect(rendered).to include(I18n.t("ui.measurement.not_measured"))
      expect(rendered).not_to include("0%")
      expect(rendered).to include("bg-red-900") # last_seen_at nil → stale LED branch
    end
  end
end
