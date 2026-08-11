# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Row do
  # [TEST.12] Реальний незбережений `BioContractFirmware`. Дві поправки, і обидві
  # про вигаданий вокабуляр, а не про типи.
  #
  # 🔴 `target_hardware_type` — це ТИП ПРИСТРОЮ (`HARDWARE_TYPES = %w[Tree Gateway]`,
  # `inclusion`-валідований), а мок клав туди назву мікроконтролера. Тобто значення
  # було не просто поза списком — воно з ІНШОЇ предметної області, і рядок таблиці
  # рендерив те, чого модель ніколи не віддасть.
  #
  # ⚠️ Рукописний `model_name` знято: він оголошував `firmware`/`firmwares`, тоді як
  # модель дає `bio_contract_firmware`/`bio_contract_firmwares` — саме та підміна
  # контракту, що описана в `04_06 §A.2` 10а. Тут вона була безпечна лише випадково
  # (роут `deploy_firmware_path` іменований, тож йому досить `to_param`), і перевірено
  # рантаймом: на реальному записі він резолвиться в `/firmwares/1/deploy`.
  def build_firmware(id: 1, version: "1.4.2", target_hardware_type: "Tree", binary_sha256: "abcdef1234567890AABB", created_at: Time.zone.local(2024, 3, 15, 10, 30))
    BioContractFirmware.new(
      id: id,
      version: version,
      target_hardware_type: target_hardware_type,
      binary_sha256: binary_sha256,
      created_at: created_at
    )
  end

  describe "rendering" do
    let(:html) { render_component(firmware: build_firmware) }

    it "displays the firmware version with v prefix" do
      expect(html).to include("v1.4.2")
    end

    it "displays the target hardware type" do
      expect(html).to include("Tree")
    end

    it "displays truncated binary_sha256 (first 16 chars)" do
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

  describe "nil binary_sha256" do
    it "displays N/A when binary_sha256 is nil" do
      html = render_component(firmware: build_firmware(binary_sha256: nil))
      expect(html).to include("N/A")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmware: build_firmware) }

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
