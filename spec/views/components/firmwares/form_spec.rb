# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Form do

  def mock_firmware
    fw = OpenStruct.new(
      id: nil,
      version: nil,
      target_hardware: nil,
      notes: nil,
      binary_file: nil,
      errors: OpenStruct.new(any?: false),
      new_record?: true,
      to_param: nil,
      persisted?: false
    )
    fw.define_singleton_method(:to_model) { self }
    fw.define_singleton_method(:model_name) do
      OpenStruct.new(
        param_key: "firmware",
        route_key: "firmwares",
        singular_route_key: "firmware",
        name: "Firmware",
        human: "Firmware",
        i18n_key: :firmware,
        element: "firmware",
        collection: "firmwares"
      )
    end
    fw
  end

  describe "form fields" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "renders the Evolution Version field label" do
      expect(html).to include("Evolution Version")
    end

    it "renders the Target Hardware Architecture field label" do
      expect(html).to include("Target Hardware Architecture")
    end

    it "renders the Binary Artifact field label" do
      expect(html).to include("Binary Artifact (.bin)")
    end

    it "renders the Release Notes field label" do
      expect(html).to include("Release Notes / Logical Changes")
    end

    it "includes version placeholder text" do
      expect(html).to include("1.4.2")
    end

    it "renders Soldier hardware option" do
      expect(html).to include("STM32-L0 (Soldier)")
    end

    it "renders Queen hardware option" do
      expect(html).to include("ESP32-S3 (Queen)")
    end

    it "renders the submit button" do
      expect(html).to include("COMMIT EVOLUTION")
    end
  end

  describe "form attributes" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "includes multipart encoding for file upload" do
      expect(html).to include("multipart/form-data")
    end

    it "renders required attribute on version field" do
      expect(html).to include("required")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "uses gaia design tokens for borders" do
      expect(html).to include("border-gaia-border")
    end

    it "uses gaia design tokens for surface background" do
      expect(html).to include("bg-gaia-surface")
    end

    it "uses gaia design tokens for text colors" do
      expect(html).to include("text-gaia-primary")
    end

    it "uses text-mini for field labels" do
      expect(html).to include("text-mini")
    end

    it "uses gaia-label for label color" do
      expect(html).to include("text-gaia-label")
    end

    it "uses focus-visible for input focus states" do
      expect(html).to include("focus-visible:border-gaia-primary")
    end
  end
end
