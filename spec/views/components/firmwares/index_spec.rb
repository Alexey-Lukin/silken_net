# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Index do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_pagy(count: 3, page: 1)
    pagy = OpenStruct.new(count: count, page: page, last: 1, from: 1, to: count, prev: nil, next: nil, vars: { items: 21 })
    pagy.define_singleton_method(:series) { [1] }
    pagy
  end

  def mock_firmware(id: 1, version: "1.4.2", target_hardware: "stm32_l0", checksum: "abcdef1234567890AABB", created_at: Time.new(2024, 3, 15, 10, 30))
    OpenStruct.new(
      id: id,
      version: version,
      target_hardware: target_hardware,
      checksum: checksum,
      created_at: created_at,
      to_param: id.to_s,
      model_name: OpenStruct.new(param_key: "firmware", route_key: "firmwares", singular_route_key: "firmware")
    )
  end

  def mock_inventory_stats
    {
      gateways: { "2.1.0" => 5, "2.0.0" => 3 },
      trees: { "1.4.2" => 100, "1.3.0" => 50 }
    }
  end

  describe "rendering" do
    let(:firmwares) { [mock_firmware(id: 1), mock_firmware(id: 2, version: "1.3.0")] }
    let(:html) { render_component(firmwares: firmwares, inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 2)) }

    it "renders with fade-in animation" do
      expect(html).to include("animate-in")
    end

    it "displays the inventory summary heading" do
      expect(html).to include("Forest Inventory (Version Distribution)")
    end

    it "displays the firmware registry heading" do
      expect(html).to include("Available Binary Evolutions")
    end

    it "renders the upload new firmware link" do
      expect(html).to include("+ Inject New Code")
    end

    it "renders table column headers" do
      expect(html).to include("Version")
      expect(html).to include("Target Hardware")
      expect(html).to include("Checksum (MD5)")
      expect(html).to include("Uploaded")
      expect(html).to include("Command")
    end

    it "renders firmware version" do
      expect(html).to include("v1.4.2")
    end

    it "renders firmware rows with deploy button" do
      expect(html).to include("Order Evolution →")
    end
  end

  describe "inventory stats" do
    let(:html) { render_component(firmwares: [], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 0)) }

    it "displays Queens (Gateways) section" do
      expect(html).to include("Queens (Gateways)")
    end

    it "displays Soldiers (Trees) section" do
      expect(html).to include("Soldiers (Trees)")
    end

    it "displays version counts with units label" do
      expect(html).to include("units")
    end

    it "displays gateway version stats" do
      expect(html).to include("v2.1.0")
      expect(html).to include("5 units")
    end

    it "displays tree version stats" do
      expect(html).to include("v1.4.2")
      expect(html).to include("100 units")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(firmwares: [mock_firmware], inventory_stats: mock_inventory_stats, pagy: mock_pagy) }

    it "renders table with role=table" do
      expect(html).to include('role="table"')
    end

    it "includes aria-label on upload link" do
      expect(html).to include("Upload new firmware binary")
    end

    it "includes focus-visible ring styling" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmwares: [mock_firmware], inventory_stats: mock_inventory_stats, pagy: mock_pagy) }

    it "uses text-tiny for typography" do
      expect(html).to include("text-tiny")
    end

    it "uses text-mini for small labels" do
      expect(html).to include("text-mini")
    end

    it "uses tracking-widest for uppercase labels" do
      expect(html).to include("tracking-widest")
    end
  end
end
