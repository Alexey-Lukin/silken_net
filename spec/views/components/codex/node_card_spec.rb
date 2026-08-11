# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::NodeCard do
  # [TEST.12] Реальні незбережені записи. Мок доти ВИГОТОВЛЯВ `display_glyph`
  # (щоправда чесно — через ті самі константи) і три метадані фреймворку
  # (`to_param`/`model_name`/`to_key`); усе це реальна модель віддає сама, а
  # `to_param` у `Codex::Node` ще й перевизначений на `slug`.
  def build_realm(slug: "ecosystem", glyph: "forest", name_en: "Ecosystems", accent_token: "status-success")
    Codex::Realm.new(slug: slug, glyph: glyph, name_en: name_en, accent_token: accent_token)
  end

  # 🔴 `geo_region` СВІДОМО відмінний від `slug`. Доти обидва були рядком
  # «cherkasy-bir», а приклад про футер пінив саме його — тобто був зелений
  # через href сусіднього приклада й пережив би зняття гілки geo_region цілком.
  def build_node(**overrides)
    realm = overrides.delete(:realm) || build_realm
    node = Codex::Node.new(
      {
        id: 1,
        slug: "cherkasy-bir",
        codex_uid: "CDX-ECO-0001",
        title_uk: "Черкаський бір",
        title_en: "Cherkasy Pine Forest",
        subtitle_en: "Pine cathedral of the Dnipro",
        lifecycle_status: "thriving",
        attunement_elo: 1700,
        geo_region: "Dnipro Basin"
      }.merge(overrides.except(:cover_image))
    )
    node.realm = realm
    if overrides.key?(:cover_image)
      allow(node).to receive(:cover_image).and_return(overrides[:cover_image])
    end
    node
  end

  describe "rendering" do
    let(:html) { render_component(node: build_node) }

    it "renders the bilingual title" do
      expect(html).to include("Черкаський бір")
      expect(html).to include("Cherkasy Pine Forest")
    end

    it "renders the codex_uid" do
      expect(html).to include("CDX-ECO-0001")
    end

    it "renders the realm pill with the realm name" do
      expect(html).to include("Ecosystems")
    end

    it "renders the lifecycle badge with semantic token" do
      expect(html).to include("bg-status-success")
    end

    it "links to the show route by slug" do
      expect(html).to include("/codex/nodes/cherkasy-bir")
    end

    it "renders Elo and geo_region in the footer" do
      expect(html).to include("Elo 1700")
      expect(html).to include("Dnipro Basin")
    end
  end

  describe "edge cases" do
    it "renders a placeholder glyph when cover_image is not attached" do
      html = render_component(node: build_node)
      expect(html).to include("🌲")
    end

    it "renders an img tag when cover_image is attached and representable" do
      # Exercise the img branch of render_cover by stubbing the ActiveStorage-like
      # cover_image. We use a plain double with the exact interface the component
      # queries (attached?, representable?, variant) so the stub stays honest
      # while avoiding a full blob/variant database setup.
      variant = double("ActiveStorage::VariantRecord")
      cover = double("ActiveStorage::Attached::One",
                     attached?: true,
                     representable?: true)
      allow(cover).to receive(:variant).and_return(variant)
      node_with_cover = build_node(cover_image: cover)

      # ⚠️ ЄДИНИЙ приклад цього файла повз `render_component`, і виняток названий:
      # `cover` — double, а не справжнє вкладення, тож реальний
      # `rails_representation_path` шляху з нього не побудує. Решта прикладів іде
      # через справжній renderer [ARCH.77]; тут стаб компенсує ФІКСТУРУ, а не
      # маршрутизатор — і саме тому маршрут-хелпер серед стабів більше не стоїть.
      comp = Class.new(Codex::NodeCard) do
        define_method(:helpers) { ActionController::Base.helpers }
        define_method(:codex_node_path) { |_n| Rails.application.routes.url_helpers.codex_node_path(_n) }
        define_method(:rails_representation_path) { |_v, **| "/rails/img.webp" }
      end.new(node: node_with_cover)

      html = comp.call
      expect(html).to include("<img")
      expect(html).to include('loading="lazy"')
    end

    it "renders an em dash when geo_region is blank" do
      html = render_component(node: build_node(geo_region: nil))
      expect(html).to include("—")
    end

    it "omits subtitle row when subtitle_en is blank" do
      html = render_component(node: build_node(subtitle_en: nil))
      expect(html).not_to include("Pine cathedral")
    end
  end

  describe "design system compliance" do
    let(:html) { render_component(node: build_node) }

    it "uses gaia design tokens, not raw Tailwind colors" do
      expect(html).not_to include("bg-white")
      expect(html).not_to include("text-gray-900")
      expect(html).to include("bg-gaia-surface")
      expect(html).to include("border-gaia-border")
    end

    it "uses the custom text scale (mini/tiny/micro)" do
      expect(html).to include("text-mini")
      expect(html).to include("text-tiny")
      expect(html).to include("text-micro")
    end

    it "has a focus-visible ring on the link" do
      expect(html).to include("focus-visible:ring-2")
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end
end
