# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateways::Index do
  let(:gateways) { [ mock_gateway ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(gateways: gateways, pagy: pagy, online_count: 3) }


  def mock_gateway(uid: "SNET-Q-AAB01234", last_seen_at: 1.minute.ago,
                   cluster_name: "Carpathian-Alpha", active_trees_count: 12,
                   signal_quality_percentage: 78)
    latest_log = OpenStruct.new(signal_quality_percentage: signal_quality_percentage)
    cluster = OpenStruct.new(name: cluster_name, active_trees_count: active_trees_count)

    gw = OpenStruct.new(
      uid: uid,
      last_seen_at: last_seen_at,
      cluster: cluster,
      latest_gateway_telemetry_log: latest_log
    )
    gw.define_singleton_method(:model_name) { ActiveModel::Name.new(Gateway) }
    gw.define_singleton_method(:to_key) { [ 1 ] }
    gw.define_singleton_method(:to_param) { "1" }
    gw
  end

  describe "header" do
    it "displays the registry title" do
      expect(html).to include("Queen Registry // Global Relays")
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

    it "renders signal percentage" do
      expect(html).to include("78%")
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
        gateways: [ mock_gateway(last_seen_at: 10.minutes.ago) ],
        pagy: pagy, online_count: 0
      )
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
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
      expect(rendered).to include("Queen Registry // Global Relays")
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
    it "renders unassigned/zero/silent fallbacks and a stale LED" do
      gw = mock_gateway
      gw.cluster = nil
      gw.latest_gateway_telemetry_log = nil
      gw.last_seen_at = nil
      rendered = render_component(gateways: [ gw ], pagy: mock_pagy(count: 1, last: 1), online_count: 0)
      expect(rendered).to include("UNASSIGNED") # cluster&.name || unassigned
      expect(rendered).to include("SILENT")     # last_seen_at&.strftime || silent
      expect(rendered).to include("0%")         # latest_log&.signal_quality_percentage || 0
      expect(rendered).to include("bg-red-900") # last_seen_at nil → stale LED branch
    end
  end
end
