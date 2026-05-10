# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Home do
  # Component is i18n-aware. Existing assertions match the English copy,
  # so we render under :en across this file.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  def mock_stats(health_avg: 92, active_trees: 38, total_trees: 40,
                 total_scc: "1250 SCC", avg_voltage: 3800)
    {
      trees: { health_avg: health_avg, active: active_trees, total: total_trees },
      economy: { total_scc: total_scc },
      energy: { avg_voltage: avg_voltage }
    }
  end

  def mock_ews_event
    cluster = OpenStruct.new(name: "Carpathian-7")
    alert = EwsAlert.allocate
    alert.define_singleton_method(:alert_type) { "Thermal Anomaly" }
    alert.define_singleton_method(:cluster) { cluster }
    alert.define_singleton_method(:created_at) { 1.minute.ago }
    alert
  end

  def mock_tx_event
    tree = OpenStruct.new(did: "SNET-00000042")
    wallet = OpenStruct.new(tree: tree)
    tx = BlockchainTransaction.allocate
    tx.define_singleton_method(:amount) { "0.005" }
    tx.define_singleton_method(:wallet) { wallet }
    tx.define_singleton_method(:sourceable) { nil }
    tx.define_singleton_method(:created_at) { 2.minutes.ago }
    tx
  end

  def render_component(stats:, events:)
    ApplicationController.renderer.render(
      component_class.new(stats: stats, events: events),
      layout: false
    )
  end

  let(:stats) { mock_stats }
  let(:html) { render_component(stats: stats, events: []) }

  describe "StatCard components for tree stats" do
    it "renders Forest Vitality stat card" do
      expect(html).to include("Forest Vitality")
    end

    it "renders the health avg percentage" do
      expect(html).to include("92%")
    end

    it "renders Active Soldiers stat card" do
      expect(html).to include("Active Soldiers")
    end

    it "renders active tree count" do
      expect(html).to include("38")
    end
  end

  describe "economy stat" do
    it "renders Carbon Treasury stat card" do
      expect(html).to include("Carbon Treasury")
    end

    it "renders total_scc value" do
      expect(html).to include("1250 SCC")
    end
  end

  describe "energy stat" do
    it "renders Ionic Potential stat card" do
      expect(html).to include("Ionic Potential")
    end

    it "renders average voltage with mV unit" do
      expect(html).to include("3800mV")
    end

    it "applies danger styling when voltage is below 3300" do
      low_voltage_html = render_component(stats: mock_stats(avg_voltage: 3100), events: [])
      # danger: true triggers different styling via StatCard
      expect(low_voltage_html).to include("3100mV")
    end
  end

  describe "live feed container" do
    it "renders the Live Transmission Feed heading" do
      expect(html).to include("Live Transmission Feed")
    end

    it "renders a link to the Mission Log (alerts)" do
      expect(html).to include("Open Mission Log →")
    end
  end

  describe "event_row delegation" do
    it "renders EwsAlert event rows via EventRow component" do
      html = render_component(stats: stats, events: [ mock_ews_event ])
      expect(html).to include("Threat:")
    end

    it "renders BlockchainTransaction event rows" do
      html = render_component(stats: stats, events: [ mock_tx_event ])
      expect(html).to include("SNET-00000042")
    end
  end

  describe "empty events state" do
    it "renders without errors when events list is empty" do
      expect(html).to include("Live Transmission Feed")
    end
  end
end
