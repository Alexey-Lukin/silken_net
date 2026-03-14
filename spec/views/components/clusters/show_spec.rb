# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Show do
  let(:component_class) { described_class }
  let(:cluster) { mock_cluster }
  let(:gateways) { [ mock_gateway ] }
  let(:recent_alerts) { [] }
  let(:html) { render_component(cluster: cluster, gateways: gateways, recent_alerts: recent_alerts) }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

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
end
