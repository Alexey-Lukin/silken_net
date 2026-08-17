# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Form do
  def mock_family(id: nil, name: nil, scientific_name: nil)
    family = TreeFamily.new(id: id, name: name, scientific_name: scientific_name)
    family.define_singleton_method(:persisted?) { id.present? }
    family.define_singleton_method(:to_key) { id ? [ id ] : nil }
    family
  end

  describe "form structure" do
    let(:html) { render_component(family: mock_family) }

    it "renders a form tag" do
      expect(html).to include("<form")
    end

    # 🔴 [UI.3] Див. `provisioning/new_spec` — периметр носія був третиною поверхні.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

    it "uses gaia design system surface classes" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
    end
  end

  describe "form labels (a11y)" do
    let(:html) { render_component(family: mock_family) }

    it "renders label tags associated with inputs" do
      expect(html).to include("<label")
      expect(html).to include("for=")
    end

    it "displays Species Identity label" do
      expect(html).to include("Species Identity")
    end

    it "displays Scientific Name label" do
      expect(html).to include("Scientific Name (Latin)")
    end

    it "displays all field labels" do
      expect(html).to include("Critical Z Min")
      expect(html).to include("Critical Z Max")
      expect(html).to include("Sequestration Coefficient")
      expect(html).to include("Sap Flow Index")
      expect(html).to include("Bark Thickness")
    end
  end

  # 🔴 [UI.3] Per-field індикація помилки (WCAG 3.3.1). `ErrorSummary` показує
  # СПИСОК причин згори — тобто людина зі скрінрідером чує їх усі, а дійшовши до
  # конкретного поля не дізнається, що невалідне саме воно. Доти `aria-invalid`
  # мав нуль входжень у всьому `app/`.
  #
  # ⚠️ Субʼєкт — РЕАЛЬНО невалідний запис (`valid?` наповнює `errors`), а не мок із
  # підробленим `errors`: саме така фікстура вже двічі цементувала тут неіснуючий
  # контракт (`04_06 §B.2` BP #14). Піни ПАРСЯТЬ розмітку через спільний дім
  # `LabelAssociation`, бо `include("aria-invalid")` зелений і тоді, коли атрибут
  # сів не на те поле й вказує в порожнечу.
  describe "per-field error indication" do
    let(:invalid_family) do
      family = mock_family
      family.valid?
      family
    end
    let(:fragment) { Nokogiri::HTML5.fragment(render_component(family: invalid_family)) }

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
      expect(LabelAssociation.unmarked_error_fields(fragment, invalid_family, "tree_family")).to be_empty
    end

    it "друкує текст причини саме в тому вузлі, на який показує поле" do
      # 🔴 Пін на ЗБІГ адреси з умістом, не на присутність рядка: `can't be blank`
      # є і в `ErrorSummary` згори, тож `include(...)` по документу зелений навіть
      # коли per-field вузол порожній або відсутній.
      target = fragment.at_css('[name="tree_family[name]"]')["aria-describedby"]

      expect(fragment.at_css("##{target}").text).to include("can't be blank")
    end

    it "мовчить на валідному записі — `aria-invalid` на справному полі теж є твердженням" do
      clean = Nokogiri::HTML5.fragment(render_component(family: mock_family))

      expect(LabelAssociation.invalid_fields(clean)).to be_empty
    end
  end

  describe "form inputs" do
    let(:html) { render_component(family: mock_family) }

    it "includes text fields for name and scientific_name" do
      expect(html).to include('type="text"')
    end

    it "includes number fields for numeric attributes" do
      expect(html).to include('type="number"')
    end

    it "applies gaia input design tokens" do
      expect(html).to include("bg-gaia-input-bg")
      expect(html).to include("border-gaia-input-border")
    end

    it "includes focus-visible ring on inputs" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "submit button" do
    let(:html) { render_component(family: mock_family) }

    it "renders the submit button" do
      expect(html).to include("WRITE GENETIC CODE")
    end

    it "includes disabled opacity for accessibility" do
      expect(html).to include("disabled:opacity-50")
    end

    it "includes focus-visible ring for keyboard navigation" do
      expect(html).to include("focus-visible:ring-2")
    end

    it "uses gaia primary color tokens" do
      expect(html).to include("border-gaia-primary")
      expect(html).to include("text-gaia-primary")
    end
  end
end
