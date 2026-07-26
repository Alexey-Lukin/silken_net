# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateways::Item do
  let(:gateway) { mock_gateway }
  let(:html) { render_component(gateway: gateway) }

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
    it "displays Queen // UID" do
      expect(html).to include("Queen // SNET-Q-AAB01234")
    end

    it "displays the cluster name" do
      expect(html).to include("Cluster: Carpathian-Alpha")
    end

    it "shows UNASSIGNED when cluster is nil" do
      gw = mock_gateway(cluster_name: nil)
      gw.cluster = nil
      rendered = render_component(gateway: gw)
      expect(rendered).to include("UNASSIGNED")
    end
  end

  describe "stats section" do
    it "displays soldiers count" do
      expect(html).to include("Soldiers")
      expect(html).to include("12")
    end

    it "displays signal percentage" do
      expect(html).to include("Signal")
      expect(html).to include("78%")
    end

    it "shows 0% signal when no telemetry log" do
      gw = mock_gateway
      gw.latest_gateway_telemetry_log = nil
      rendered = render_component(gateway: gw)
      expect(rendered).to include("0%")
    end
  end

  describe "footer" do
    it "displays formatted last_seen_at" do
      frozen_time = Time.zone.parse("2025-03-15 14:30:00")
      gw = mock_gateway(last_seen_at: frozen_time)
      rendered = render_component(gateway: gw)
      expect(rendered).to include("14:30 // 15.03")
    end

    it "shows SILENT when last_seen_at is nil" do
      gw = mock_gateway(last_seen_at: nil)
      rendered = render_component(gateway: gw)
      expect(rendered).to include("SILENT")
    end

    it "renders Open Relay link" do
      expect(html).to include("Open Relay →")
    end
  end

  describe "connection LED" do
    it "shows green LED when recently seen" do
      gw = mock_gateway(last_seen_at: 1.minute.ago)
      rendered = render_component(gateway: gw)
      expect(rendered).to include("bg-emerald-500")
    end

    it "shows red pulsing LED when not recently seen" do
      gw = mock_gateway(last_seen_at: 10.minutes.ago)
      rendered = render_component(gateway: gw)
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
    end

    it "shows red pulsing LED when never seen" do
      gw = mock_gateway(last_seen_at: nil)
      rendered = render_component(gateway: gw)
      expect(rendered).to include("bg-red-900")
      expect(rendered).to include("animate-pulse")
    end
  end
end
