# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Show do
  let(:cluster) { build_cluster }
  let(:gateways) { [ mock_gateway ] }
  let(:recent_alerts) { [] }
  let(:html) { render_component(cluster: cluster, gateways: gateways, recent_alerts: recent_alerts) }

  def build_cluster(id: 1, name: "Carpathian-Alpha", region: "Cherkasy Oblast",
                   health_index: 0.87, total_active_trees: 142, active_threats: false)
    # [TEST.12] Реальний незбережений `Cluster`. Колонки годуються як колонки
    # (`active_trees_count` — читач `total_active_trees`), а стабляться РІВНО ті три
    # методи, що ходять у БД: `active_threats?` (`ews_alerts…exists?`), `geo_center`
    # (агрегат по деревах) і `active_contract` (`naas_contracts.active…first`).
    # ⚠️ `mapped?` НЕ стабиться свідомо — він чистий (`geojson_polygon.present? && …`),
    # тож на реальному записі відповідає сам, і фікстура більше не вигадує його відповідь.
    cluster = Cluster.new(
      id: id,
      name: name,
      region: region,
      health_index: health_index,
      active_trees_count: total_active_trees,
      environmental_settings: {},
      # 🔴 Годуємо ДЖЕРЕЛО, а не відповідь: доти `mapped?` був синглтоном `true`,
      # тобто фікстура сама вирішувала, чи кластер має контур. Метод чистий
      # (`geojson_polygon.present? && …["coordinates"].present?`), тож реальна
      # колонка робить його перевірним — і заразом видно, що порожній полігон
      # (`{}`) дає `false`, чого мок не показував ніколи.
      geojson_polygon: { "type" => "Polygon", "coordinates" => [ [ [ 32.0, 49.4 ], [ 32.1, 49.4 ], [ 32.1, 49.5 ] ] ] }
    )
    allow(cluster).to receive_messages(active_threats?: active_threats, active_contract: nil, geo_center: { lat: 49.4444, lng: 32.0597 })
    cluster
  end

  def mock_gateway(uid: "QUEEN-01", state: "active", latitude: 49.4, longitude: 32.1)
    OpenStruct.new(uid: uid, state: state, latitude: latitude, longitude: longitude, last_seen_at: Time.current)
  end

  def mock_alert(id: 1, alert_type: "fire_detected", severity: "critical")
    alert = OpenStruct.new(id: id, alert_type: alert_type, severity: severity, created_at: Time.current)
    alert.define_singleton_method(:model_name) { ActiveModel::Name.new(EwsAlert) }
    alert.define_singleton_method(:to_key) { [ id ] }
    alert
  end

  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source for alerts" do
      expect(html).to include("turbo-cable-stream-source")
    end
  end

  describe "header" do
    it "displays the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays the region and ID" do
      expect(html).to include("Cherkasy Oblast")
    end

    it "shows nominal status when no active threats" do
      expect(html).to include("Nominal")
    end

    it "shows threat detected when active threats" do
      html = render_component(cluster: build_cluster(active_threats: true), gateways: [], recent_alerts: [])
      expect(html).to include("Threat Detected")
    end
  end

  describe "vitals panel" do
    it "displays health index as percentage" do
      expect(html).to include("87%")
    end

    # 🔴 [ARCH.84] Пара до попереднього: невиміряний ⊥ виміряний. Без другої половини
    # приклад доводив би лише «щось відрендерилось».
    it "displays «not measured» instead of a fabricated percentage when there is no reading" do
      unmeasured = render_component(cluster: build_cluster(health_index: nil), gateways: [], recent_alerts: [])

      expect(unmeasured).to include(I18n.t("ui.measurement.not_measured"))
      expect(unmeasured).not_to include("0%")
    end

    it "displays active trees count" do
      expect(html).to include("142")
    end

    it "displays gateway count" do
      expect(html).to include("1")
    end
  end

  describe "gateways table" do
    it "renders gateway UID" do
      expect(html).to include("QUEEN-01")
    end

    it "shows empty state when no gateways" do
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("No gateways deployed")
    end
  end

  describe "alerts panel" do
    it "shows empty state when no alerts" do
      expect(html).to include("No active threats")
    end

    it "renders alerts_list container for turbo prepend" do
      expect(html).to include('id="alerts_list"')
    end

    context "with active alerts" do
      let(:recent_alerts) { [ mock_alert(id: 5, alert_type: "fire_detected", severity: "critical") ] }

      it "displays the localized alert-type label, not the raw enum value" do
        expect(html).to include("Fire Detected")
        expect(html).not_to include("fire_detected")
      end

      it "uses dom_id for alert elements" do
        expect(html).to include('id="ews_alert_5"')
      end
    end
  end

  describe "geography panel" do
    it "displays region" do
      expect(html).to include("Cherkasy Oblast")
    end

    it "displays mapped status" do
      expect(html).to include("Yes")
    end

    it "includes Google Maps link" do
      expect(html).to include("google.com/maps")
    end

    it "displays mapped=No when the cluster is not mapped" do
      cl = build_cluster
      cl.geojson_polygon = {} # джерело, не відповідь: `mapped?` виводить це сам
      out = render_component(cluster: cl, gateways: [], recent_alerts: [])
      expect(out).to include("Mapped")
      expect(out).not_to include("Yes")
    end

    it "omits the centroid and map link when geo_center is nil" do
      cl = build_cluster
      cl.define_singleton_method(:geo_center) { nil }
      out = render_component(cluster: cl, gateways: [], recent_alerts: [])
      expect(out).not_to include("google.com/maps")
    end
  end

  describe "environmental settings" do
    it "renders fire threshold when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "custom_fire_threshold" => 65 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Fire Threshold")
      expect(html).to include("65°C")
    end

    it "renders seismic sensitivity when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "seismic_sensitivity_threshold" => 0.8 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Seismic Sensitivity")
      expect(html).to include("0.8")
    end

    it "renders timezone when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "timezone" => "Europe/Kyiv" }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Timezone")
      expect(html).to include("Europe/Kyiv")
    end

    it "renders Environmental Config heading when settings present" do
      cluster = build_cluster
      cluster.environmental_settings = { "custom_fire_threshold" => 65 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Environmental Config")
    end
  end

  describe "contract panel" do
    it "renders NaaS Contract heading" do
      expect(html).to include("NaaS Contract")
    end

    it "shows 'No active NaaS contract.' when no contract" do
      expect(html).to include("No active NaaS contract.")
    end

    context "with active contract" do
      it "renders contract details" do
        # 🔴 [TEST.12] Реальний `NaasContract`, і це не гігієна: `total_value` — alias
        # на `total_funding`, колонка `numeric`, тож прод друкує BigDecimal («50000.0»),
        # а не Integer. Доти пін `include("50000")` був підрядком обох форм — тобто не
        # здатен був побачити ані тип, ані ОДИНИЦЮ, яку цей рядок тепер несе (USD:
        # сусідній рядок правомірно каже «Emitted SCC», і без підпису плата за послугу
        # читалась у тій самій валюті — восьмий сайт класу, закритого в [I18N.1]).
        #
        # ⚠️ [UI.3] Контракт тепер ПЕРЕДАЄТЬСЯ, а не стабиться на кластері: доти
        # компонент діставав його сам у `initialize`, тобто спека мусила підробляти
        # DB-виклик, щоб описати екран. Стаб на `active_contract` став би тепер
        # мертвим — і мовчки, бо `nil`-гілка теж рендериться.
        contract = NaasContract.new(status: :active, total_funding: 50_000, emitted_tokens: 1200)
        html = render_component(cluster: build_cluster, gateways: [], recent_alerts: [],
                                active_contract: contract)
        expect(html).to include("ACTIVE")
        expect(html).to include("50000.0 USD")
        expect(html).to include("1200")
      end
    end
  end

  describe "alert severity class" do
    it "uses warning style for medium severity" do
      alert = mock_alert(severity: "medium")
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [ alert ])
      expect(html).to include("bg-status-warning")
    end

    it "uses emerald style for low severity" do
      alert = mock_alert(severity: "low")
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [ alert ])
      expect(html).to include("bg-emerald-500")
    end

    it "uses emerald style for unknown severity" do
      alert = mock_alert(severity: "unknown")
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [ alert ])
      expect(html).to include("bg-emerald-500")
    end
  end

  describe "initialize guard" do
    it "raises ArgumentError when cluster does not respond to :name" do
      bad = Object.new
      expect {
        described_class.new(cluster: bad, gateways: [], recent_alerts: [])
      }.to raise_error(ArgumentError, /cluster must respond to :name/)
    end
  end

  describe "gateway row last_seen_at fallback" do
    it "renders a dash when a gateway has no last_seen_at timestamp" do
      gw = OpenStruct.new(uid: "QUEEN-NIL", state: "active", latitude: 0, longitude: 0, last_seen_at: nil)
      out = render_component(cluster: cluster, gateways: [ gw ], recent_alerts: [])
      expect(out).to include("QUEEN-NIL")
      expect(out).to include("—")
    end
  end
end
