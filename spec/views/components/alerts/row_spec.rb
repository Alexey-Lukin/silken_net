# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alerts::Row do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_alert(id: 7, severity: "medium", alert_type: "fire_detected", status: "active",
                 cluster_name: "Carpathian-7", tree_did: "TREE::0xBEEF", message: "Thermal anomaly detected")
    alert = EwsAlert.allocate
    alert.define_singleton_method(:id) { id }
    alert.define_singleton_method(:severity) { severity }
    alert.define_singleton_method(:alert_type) { alert_type }
    alert.define_singleton_method(:cluster) { OpenStruct.new(name: cluster_name) }
    alert.define_singleton_method(:tree) { OpenStruct.new(did: tree_did) }
    alert.define_singleton_method(:message) { message }
    alert.define_singleton_method(:created_at) { Time.current }
    alert.define_singleton_method(:status_resolved?) { status == "resolved" }
    alert.define_singleton_method(:to_key) { [ id ] }
    alert.define_singleton_method(:to_param) { id.to_s }
    alert.define_singleton_method(:to_model) { self }
    alert
  end

  describe "DOM ID" do
    it "uses dom_id format for the row id" do
      html = render_component(alert: mock_alert(id: 42))
      expect(html).to include('id="ews_alert_42"')
    end
  end

  describe "severity badge" do
    it "renders critical severity with danger styles and pulse" do
      html = render_component(alert: mock_alert(severity: "critical"))
      expect(html).to include("bg-status-danger")
      expect(html).to include("animate-pulse")
    end

    it "renders medium severity with warning styles" do
      html = render_component(alert: mock_alert(severity: "medium"))
      expect(html).to include("bg-status-warning")
    end

    it "renders low severity with emerald styles" do
      html = render_component(alert: mock_alert(severity: "low"))
      expect(html).to include("bg-emerald-900")
    end

    it "includes aria-label for accessibility" do
      html = render_component(alert: mock_alert(severity: "critical"))
      expect(html).to include("aria-label")
      expect(html).to include("Severity")
    end
  end

  describe "alert content" do
    let(:html) { render_component(alert: mock_alert) }

    it "displays the alert type humanized" do
      expect(html).to include("Fire detected")
    end

    it "displays cluster and tree source" do
      expect(html).to include("Carpathian-7")
      expect(html).to include("TREE::0xBEEF")
    end

    it "displays the alert message" do
      expect(html).to include("Thermal anomaly detected")
    end
  end

  describe "resolved state" do
    let(:html) { render_component(alert: mock_alert(status: "resolved")) }

    it "shows resolved indicator instead of action button" do
      expect(html).to include("Resolved")
    end

    it "applies reduced opacity for resolved rows" do
      expect(html).to include("opacity-40")
    end
  end

  describe "active state" do
    let(:html) { render_component(alert: mock_alert(status: "active")) }

    it "renders the resolve button" do
      expect(html).to include("Acknowledge")
    end

    it "includes hover transition styles" do
      expect(html).to include("hover:bg-emerald-950/10")
    end
  end
end
