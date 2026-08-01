# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::NodeCard do
  def mock_realm(slug: "ecosystem", glyph: "forest", name_en: "Ecosystems", accent_token: "gaia-primary")
    realm = OpenStruct.new(
      slug: slug, glyph: glyph, name_en: name_en, accent_token: accent_token
    )
    # Mirror the real `Codex::Realm#display_glyph` lookup so the mock matches
    # the production API surface; otherwise components that call it on a mock
    # would silently fall through to the default placeholder glyph.
    realm.define_singleton_method(:display_glyph) do
      ::Codex::Realm::DISPLAY_GLYPHS.fetch(glyph.to_s, ::Codex::Realm::DEFAULT_DISPLAY_GLYPH)
    end
    realm
  end

  def mock_node(**overrides)
    realm = overrides.delete(:realm) || mock_realm
    cover = OpenStruct.new(attached?: false, representable?: false)
    attrs = {
      id: 1,
      slug: "cherkasy-bir",
      codex_uid: "CDX-ECO-0001",
      title_uk: "Черкаський бір",
      title_en: "Cherkasy Pine Forest",
      subtitle_en: "Pine cathedral of the Dnipro",
      lifecycle_status: "thriving",
      attunement_elo: 1700,
      geo_region: "cherkasy-bir",
      realm: realm,
      cover_image: cover
    }.merge(overrides)
    OpenStruct.new(attrs).tap do |n|
      n.define_singleton_method(:to_param) { n.slug }
      n.define_singleton_method(:model_name) { ActiveModel::Name.new(Codex::Node) }
      n.define_singleton_method(:to_key) { [ n.id ] }
    end
  end

  describe "rendering" do
    let(:html) { render_component(node: mock_node) }

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
      expect(html).to include("/api/v1/codex/nodes/cherkasy-bir")
    end

    it "renders Elo and geo_region in the footer" do
      expect(html).to include("Elo 1700")
      expect(html).to include("cherkasy-bir")
    end
  end

  describe "edge cases" do
    it "renders a placeholder glyph when cover_image is not attached" do
      html = render_component(node: mock_node)
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
      node_with_cover = mock_node(cover_image: cover)

      # ⚠️ ЄДИНИЙ приклад цього файла повз `render_component`, і виняток названий:
      # `cover` — double, а не справжнє вкладення, тож реальний
      # `rails_representation_path` шляху з нього не побудує. Решта прикладів іде
      # через справжній renderer [ARCH.77]; тут стаб компенсує ФІКСТУРУ, а не
      # маршрутизатор — і саме тому маршрут-хелпер серед стабів більше не стоїть.
      comp = Class.new(Codex::NodeCard) do
        define_method(:helpers) { ActionController::Base.helpers }
        define_method(:api_v1_codex_node_path) { |_n| Rails.application.routes.url_helpers.api_v1_codex_node_path(_n) }
        define_method(:rails_representation_path) { |_v, **| "/rails/img.webp" }
      end.new(node: node_with_cover)

      html = comp.call
      expect(html).to include("<img")
      expect(html).to include('loading="lazy"')
    end

    it "renders an em dash when geo_region is blank" do
      html = render_component(node: mock_node(geo_region: nil))
      expect(html).to include("—")
    end

    it "omits subtitle row when subtitle_en is blank" do
      html = render_component(node: mock_node(subtitle_en: nil))
      expect(html).not_to include("Pine cathedral")
    end
  end

  describe "design system compliance" do
    let(:html) { render_component(node: mock_node) }

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
