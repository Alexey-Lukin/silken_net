# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::New do
  # 🔴 [TEST.12] Тут стояв `OpenStruct` із рукописним `model_name` і полями
  # `target_hardware`/`notes`, яких на моделі НЕМАЄ — тобто фікстура оголошувала
  # світ, де сабміт цієї форми можливий, тоді як у проді він падав 500. Сусідній
  # `form_spec` уже переведено на справжню модель [SEC.25]; ця — остання копія.
  def mock_firmware
    BioContractFirmware.new
  end

  describe "rendering" do
    let(:html) { render_component(firmware: mock_firmware) }


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

    it "uses the strong token for the page title" do
      expect(html).to include("text-gaia-text-strong")
    end
  end
end
