# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Row do

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

  describe "rendering" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "displays the firmware version with v prefix" do
      expect(html).to include("v1.4.2")
    end

    it "displays the target hardware" do
      expect(html).to include("stm32_l0")
    end

    it "displays truncated checksum (first 16 chars)" do
      expect(html).to include("abcdef1234567890")
    end

    it "displays formatted created_at" do
      expect(html).to include("15.03.24 // 10:30")
    end

    it "renders the deploy button" do
      expect(html).to include("Order Evolution →")
    end

    it "renders as a table row" do
      expect(html).to include("<tr")
    end

    it "applies hover transition effect" do
      expect(html).to include("hover:bg-emerald-950/10")
    end

    it "includes turbo confirm dialog" do
      expect(html).to include("Initiate evolution to v1.4.2")
    end
  end

  describe "nil checksum" do
    it "displays N/A when checksum is nil" do
      html = render_component(firmware: mock_firmware(checksum: nil))
      expect(html).to include("N/A")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "uses text-tiny for typography" do
      expect(html).to include("text-tiny")
    end

    it "uses text-mini for button text" do
      expect(html).to include("text-mini")
    end

    it "uses font-mono for data display" do
      expect(html).to include("font-mono")
    end

    it "uses tracking-widest for button label" do
      expect(html).to include("tracking-widest")
    end
  end
end
