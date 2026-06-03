# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Node do
  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:codex_node)).to be_valid
    end

    it "requires slug, codex_uid, bilingual title and archetype_key" do
      node = build(:codex_node, slug: nil, codex_uid: nil, title_uk: nil, title_en: nil, archetype_key: nil)
      node.valid?
      %i[slug codex_uid title_uk title_en archetype_key].each do |attr|
        expect(node.errors[attr]).to be_present, "expected error on #{attr}"
      end
    end

    it "enforces codex_uid format CDX-{ECO|TRE|PRT|MYT}-####" do
      bad = build(:codex_node, codex_uid: "BAD-001")
      expect(bad).not_to be_valid

      good = build(:codex_node, codex_uid: "CDX-ECO-9999")
      expect(good).to be_valid
    end

    it "rejects archetype_key outside ARCHETYPES registry" do
      node = build(:codex_node, archetype_key: "not_in_registry")
      expect(node).not_to be_valid
      expect(node.errors[:archetype_key]).to be_present
    end

    it "caps lore_md length to LORE_MAX" do
      node = build(:codex_node, lore_md: "x" * (described_class::LORE_MAX + 1))
      expect(node).not_to be_valid
      expect(node.errors[:lore_md]).to be_present
    end

    it "rejects external_refs that are not array of {label, url} hashes" do
      node = build(:codex_node, external_refs: "not an array")
      expect(node).not_to be_valid
    end

    it "accepts well-formed external_refs" do
      node = build(:codex_node, external_refs: [ { "label" => "Wiki", "url" => "https://example.com" } ])
      expect(node).to be_valid
    end

    it "rejects out-of-range attunement_elo" do
      node = build(:codex_node, attunement_elo: 5000)
      expect(node).not_to be_valid
    end
  end

  describe "callbacks" do
    it "normalises slug to lowercase, dash-separated" do
      node = create(:codex_node, slug: "Pine_Forest")
      expect(node.slug).to eq("pine-forest")
    end

    it "syncs PostGIS geo_point when latitude/longitude change" do
      node = create(:codex_node, :with_geo)
      expect(node.geo_point).to include("POINT")
      expect(node.geo_point).to include(node.longitude.to_s)
    end

    it "clears geo_point when coordinates are removed" do
      node = create(:codex_node, :with_geo)
      node.update!(latitude: nil, longitude: nil)
      expect(node.reload.geo_point).to be_nil
    end
  end

  describe "scopes" do
    let!(:eco_realm) { create(:codex_realm, slug: "ecosystem") }
    let!(:thriving)  { create(:codex_node, realm: eco_realm, lifecycle_status: :thriving, attunement_elo: 1700) }
    let!(:extinct)   { create(:codex_node, realm: eco_realm, lifecycle_status: :extinct,  attunement_elo: 1300) }
    let!(:other)     { create(:codex_node) } # other realm

    it ".for_realm filters by realm slug" do
      expect(described_class.for_realm("ecosystem")).to contain_exactly(thriving, extinct)
    end

    it ".for_realm accepts a Realm instance" do
      expect(described_class.for_realm(eco_realm)).to contain_exactly(thriving, extinct)
    end

    it ".for_realm with nil returns all (case when-nil branch)" do
      expect(described_class.for_realm(nil).count).to eq(described_class.count)
    end

    it ".for_realm with a blank slug returns all (slug.blank? guard)" do
      expect(described_class.for_realm("").count).to eq(described_class.count)
    end

    it ".for_realm with an unsupported argument type returns none (case else)" do
      expect(described_class.for_realm(42)).to be_empty
    end

    it ".by_lifecycle filters by status string" do
      expect(described_class.by_lifecycle("thriving")).to include(thriving)
      expect(described_class.by_lifecycle("thriving")).not_to include(extinct)
    end

    it ".search_title is case-insensitive across both locales" do
      hit = create(:codex_node, title_uk: "Криптокарпус", title_en: "Cryptocarpus")
      expect(described_class.search_title("crypto")).to include(hit)
      expect(described_class.search_title("крипто")).to include(hit)
    end

    it ".ordered_by_elo orders desc" do
      result = described_class.where(realm: eco_realm).ordered_by_elo
      expect(result.first.attunement_elo).to be >= result.last.attunement_elo
    end

    it ".published excludes drafts" do
      draft = create(:codex_node, published_at: nil)
      expect(described_class.published).not_to include(draft)
    end
  end

  describe "#to_param" do
    it "returns the slug, not the id" do
      node = create(:codex_node, slug: "yggdrasil")
      expect(node.to_param).to eq("yggdrasil")
    end
  end

  describe "#title / #subtitle locale switch" do
    let(:node) do
      build(:codex_node, title_uk: "Сосна", title_en: "Pine",
            subtitle_uk: "Сосна звичайна", subtitle_en: "Common pine")
    end

    it "returns Ukrainian for :uk" do
      expect(node.title(:uk)).to eq("Сосна")
      expect(node.subtitle(:uk)).to eq("Сосна звичайна")
    end

    it "returns English for any other locale" do
      expect(node.title(:en)).to eq("Pine")
      expect(node.subtitle(:de)).to eq("Common pine")
    end
  end
end
