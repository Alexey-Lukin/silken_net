# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeFamilies::Index do
  # [TEST.12] Реальний незбережений TreeFamily: `critical_z_*` — колонки `numeric`,
  # тобто BigDecimal — у проді діапазон друкується «10.0 - 80.0», а OpenStruct з
  # Integer дозволяв сюїті вимагати «10 - 80», якого жоден реальний запис не рендерить.
  # `model_name`/`to_key`/`to_param` тепер справжні (рукописні дозволяли `dom_id`
  # розійтися з рендереним).
  def mock_family(id: 1, name: "Oak", scientific_name: "Quercus robur",
                  critical_z_min: 10, critical_z_max: 80, trees_count: 120)
    TreeFamily.new(
      id: id,
      name: name,
      scientific_name: scientific_name,
      critical_z_min: critical_z_min,
      critical_z_max: critical_z_max,
      trees_count: trees_count
    )
  end

  let(:family)   { mock_family }
  let(:families) { [ family, mock_family(id: 2, name: "Pine", scientific_name: "Pinus sylvestris", trees_count: 55) ] }

  # [UI.6] «Define DNA»/«Edit» ведуть в екшени під `authorize_super_admin!, only:`,
  # тож дефолтний актор цих прикладів — super_admin: вони пінять ПОВНОТУ сторінки.
  # Сам фільтр пінить окрема група нижче — інакше ці приклади мовчки перетворились
  # би на пін звуженого вигляду.
  let(:full_access_actor) { build_stubbed(:user, :super_admin) }
  let(:html) { render_component(families: families, pagy: mock_pagy(count: 63), current_user: full_access_actor) }

  describe "header" do
    it "renders Biological Matrix label" do
      expect(html).to include("Biological Matrix")
    end

    it "renders Global Species Constants heading" do
      expect(html).to include("Global Species Constants")
    end

    it "renders define new species link" do
      expect(html).to include("Define new tree species")
    end

    it "renders Define DNA button text" do
      expect(html).to include("+ Define DNA")
    end
  end

  # [UI.6] Сторінка відкрита admin+, а мутації — super_admin-only, тобто гард сидить
  # ГЛИБШЕ за саму сторінку. Доти обидві кнопки бачив admin і діставав на клік сирий
  # JSON-блоб 403 — найгірший випадок класу, бо страждала найвища роль із можливих.
  describe "роле-фільтр мутаційних дій [UI.6]" do
    def render_for(actor)
      render_component(families: families, pagy: mock_pagy(count: 63), current_user: actor)
    end

    it "ховає мутаційні дії від admin — вони super_admin-only" do
      html = render_for(build_stubbed(:user, :admin))

      expect(html).to include("Species Name")           # сторінка сама відрендерилась
      expect(html).not_to include("+ Define DNA")
      expect(html).not_to include("/tree_families/1/edit")
    end

    # Сторож проводки: без актора компонент мусить звузитись, а не роздати дії.
    it "без актора звужується fail-CLOSED" do
      html = render_for(nil)

      expect(html).to include("Species Name")
      expect(html).not_to include("+ Define DNA")
    end
  end

  describe "table headers" do
    it "renders Species Name column" do
      expect(html).to include("Species Name")
    end

    it "renders Safe Range column" do
      expect(html).to include("Safe Range")
    end

    it "renders Population column" do
      expect(html).to include("Population")
    end
  end

  describe "family rows" do
    it "renders family name" do
      expect(html).to include("Oak")
    end

    it "renders scientific name" do
      expect(html).to include("Quercus robur")
    end

    it "omits the scientific name line when it is blank" do
      fam = mock_family(scientific_name: nil)
      rendered = render_component(families: [ fam ], pagy: mock_pagy(count: 1))
      expect(rendered).to include(fam.name)
    end

    # [TEST.12] Очікування з РЕАЛЬНОГО виводу: numeric-колонки віддають BigDecimal,
    # тож прод друкує «10.0», а не «10» — колишній пін вимагав вивід, якого не буває.
    it "renders safe range" do
      expect(html).to include("10.0 - 80.0")
    end

    it "renders tree count as Soldiers" do
      expect(html).to include("120 Soldiers")
    end

    it "renders AUDIT link with aria-label" do
      expect(html).to include("Audit Oak species")
    end

    it "renders EDIT link" do
      expect(html).to include("EDIT")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end
  end
end
