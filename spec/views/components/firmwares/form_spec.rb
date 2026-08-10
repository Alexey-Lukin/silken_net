# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Form do
  # 🔴 [SEC.25] Тут доти стояв OpenStruct із ВИГАДАНИМ `model_name`, який оголошував
  # `route_key: "firmwares"` і `param_key: "firmware"`. Реальний
  # `BioContractFirmware` не має ані першого (`bio_contract_firmwares`), ані другого
  # (`bio_contract_firmware`) — тобто фікстура не маскувала баг, а **створювала світ,
  # де баг неможливий**: сторінка завантаження прошивки віддавала 500 і не рендерила
  # форми взагалі, а ця спека лишалась зеленою на всіх своїх прикладах.
  #
  # Тому модель тут ТІЛЬКИ справжня (`.new` — БД не потрібна), і саме вона робить
  # приклад нижче здатним упасти.
  def mock_firmware
    BioContractFirmware.new
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

    it "includes version placeholder text" do
      expect(html).to include("1.4.2")
    end

    # 🔴 Пін на ЗНАЧЕННЯ, не лише на мітку. Селект роками пропонував `stm32_l0`/
    # `esp32_s3` — значення поза `HARDWARE_TYPES`, тож навіть із правильним іменем
    # поля запис не створився б. Мітки при цьому виглядали правдоподібно, бо називали
    # MCU — і теж помилково: обидва наші процесори STM32WLE5JC.
    it "пропонує рівно ті значення цільового заліза, які приймає модель" do
      expect(html.scan(/<option value="([^"]*)"/).flatten)
        .to match_array(BioContractFirmware::HARDWARE_TYPES)
    end

    it "renders the Tree (Soldier) hardware option" do
      expect(html).to include("Soldier (Tree)")
    end

    it "renders the Gateway (Queen) hardware option" do
      expect(html).to include("Queen (Gateway)")
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
