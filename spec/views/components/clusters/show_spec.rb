# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Show do
  let(:cluster) { mock_cluster }
  let(:gateways) { [ mock_gateway ] }
  let(:recent_alerts) { [] }
  let(:html) { render_component(cluster: cluster, gateways: gateways, recent_alerts: recent_alerts) }

  def mock_cluster(id: 1, name: "Carpathian-Alpha", region: "Cherkasy Oblast",
                   health_index: 0.87, total_active_trees: 142, active_threats: false)
    cluster = OpenStruct.new(
      id: id,
      name: name,
      region: region,
      health_index: health_index,
      total_active_trees: total_active_trees,
      environmental_settings: {},
      active_contract: nil
    )
    cluster.define_singleton_method(:active_threats?) { active_threats }
    cluster.define_singleton_method(:geo_center) { { lat: 49.4444, lng: 32.0597 } }
    cluster.define_singleton_method(:mapped?) { true }
    cluster.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    cluster.define_singleton_method(:to_key) { [ id ] }
    cluster.define_singleton_method(:to_param) { id.to_s }
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
      html = render_component(cluster: mock_cluster(active_threats: true), gateways: [], recent_alerts: [])
      expect(html).to include("Threat Detected")
    end
  end

  describe "vitals panel" do
    it "displays health index as percentage" do
      expect(html).to include("87%")
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

      it "displays alert type" do
        expect(html).to include("fire_detected")
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
  end

  describe "environmental settings" do
    it "renders fire threshold when set" do
      cluster = mock_cluster
      cluster.environmental_settings = { "custom_fire_threshold" => 65 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Fire Threshold")
      expect(html).to include("65°C")
    end

    it "renders seismic sensitivity when set" do
      cluster = mock_cluster
      cluster.environmental_settings = { "seismic_sensitivity_threshold" => 0.8 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Seismic Sensitivity")
      expect(html).to include("0.8")
    end

    it "renders timezone when set" do
      cluster = mock_cluster
      cluster.environmental_settings = { "timezone" => "Europe/Kyiv" }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Timezone")
      expect(html).to include("Europe/Kyiv")
    end

    it "renders Environmental Config heading when settings present" do
      cluster = mock_cluster
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
        contract = OpenStruct.new(status: "active", total_value: 50_000, emitted_tokens: 1200)
        cluster = mock_cluster
        cluster.define_singleton_method(:active_contract) { contract }
        html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
        expect(html).to include("ACTIVE")
        expect(html).to include("50000")
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
end
