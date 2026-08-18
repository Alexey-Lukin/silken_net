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

  # 🔴 [UI.3] Дротування per-field індикації В ЦЬОМУ файлі, а не лише в еталоні:
  # хелпер спільний (`ApplicationComponent#field_error_attrs`), але прокинути його
  # в блок мусить КОЖЕН `field_container` окремо, тож «працює в одній формі» про
  # решту не каже нічого. Пін парсить розмітку — `include("aria-invalid")` зелений
  # і тоді, коли атрибут сів не на те поле й вказує в порожнечу.
  describe "per-field error indication" do
    let(:invalid_firmware) do
      firmware = BioContractFirmware.new
      firmware.valid?
      firmware
    end
    let(:fragment) { Nokogiri::HTML5.fragment(render_component(firmware: invalid_firmware)) }

    it "позначає невалідні поля й веде кожне до ЖИВОГО вузла з причиною" do
      expect(LabelAssociation.invalid_fields(fragment)).not_to be_empty
      expect(LabelAssociation.unexplained_invalid_fields(fragment)).to be_empty
      expect(LabelAssociation.dangling_descriptions(fragment)).to be_empty
    end

    it "не лишає НЕПОЗНАЧЕНИМ жодного поля, яке модель вважає невалідним" do
      # 🔴 Дериваційна половина, без якої пін вище не падає на найправдоподібнішій
      # регресії: зняття `**aria` з ОДНОГО `field_container` лишає множину
      # позначених непорожньою. Тут звіряються дві незалежні сторони — `errors`
      # моделі ⊥ атрибути в HTML, — і промах називає поле поіменно.
      expect(LabelAssociation.unmarked_error_fields(fragment, invalid_firmware, "bio_contract_firmware")).to be_empty
    end
  end

  describe "form fields" do
    let(:html) { render_component(firmware: mock_firmware) }

    # [UI.3] Асоціація мітка↔контрол — форма з `sessions/new_spec`. Сусідні
    # приклади цього ж файлу пінять ТЕКСТ мітки, і всі вони лишались зелені при
    # `for`, якого не було взагалі: присутність рядка не є асоціацією.
    # ⚠️ Предикат — зі СПІЛЬНОГО дому (`spec/support/label_association.rb`): інлайн-копія
    # знає лише ЯВНУ асоціацію й оголосила б сиротою законну ВКЛАДЕНУ мітку — саме та
    # over-broad половина, заради якої предикат і звели в один дім.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label").size).to eq(3), "очікувались 3 мітки — пін інакше вакуумний"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

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
      # 🔴 `include("text-gaia-primary")` тут був НЕДИСКРИМІНУЮЧИМ: підпис кнопки
      # переїхав на `--gaia-primary-strong` (UI.3, 2026-08-18), а підрядок
      # проходить і на новому токені — тобто пін лишався зеленим по обидва боки
      # фіксу. Дефіс не є межею слова; форма з lookahead дзеркалить ту, що вже
      # вжита для `status-warning` ⊥ `status-warning-accent`.
      expect(html).to match(/text-gaia-primary-strong\b/)
      expect(html).not_to match(/text-gaia-primary(?!-)/)
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
