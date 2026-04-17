# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::New do
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

  describe "rendering" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "renders with zoom-in animation" do
      expect(html).to include("animate-in")
    end

    it "displays the New Code Injection heading" do
      expect(html).to include("New Code Injection")
    end

    it "displays the OTA deployment subtitle" do
      expect(html).to include("Prepare the binary artifact for OTA deployment")
    end

    it "renders centered text alignment for header" do
      expect(html).to include("text-center")
    end

    it "constrains max width" do
      expect(html).to include("max-w-2xl")
    end

    it "centers the container" do
      expect(html).to include("mx-auto")
    end

    it "renders the Form sub-component" do
      expect(html).to include("Evolution Version")
    end

    it "renders the submit button text" do
      expect(html).to include("COMMIT EVOLUTION")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmware: mock_firmware) }

    it "uses text-tiny for subtitle" do
      expect(html).to include("text-tiny")
    end

    it "uses tracking-widest for uppercase labels" do
      expect(html).to include("tracking-widest")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-emerald-400")
    end
  end
end
