# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::NodeBlueprint do
  let(:realm) { create(:codex_realm, slug: "ecosystem") }
  let(:node)  { create(:codex_node, realm: realm, slug: "cherkasy-bir", codex_uid: "CDX-ECO-0001", title_uk: "Черкаський бір", title_en: "Cherkasy Pine Forest", archetype_key: Codex::ARCHETYPES.first, lifecycle_status: :thriving, geo_region: "cherkasy") }

  describe "default view" do
    let(:payload) { described_class.render_as_hash(node) }

    it "includes all identity and counter fields" do
      aggregate_failures do
        expect(payload[:id]).to eq(node.id)
        expect(payload[:slug]).to eq("cherkasy-bir")
        expect(payload[:codex_uid]).to eq("CDX-ECO-0001")
        expect(payload[:title_uk]).to eq("Черкаський бір")
        expect(payload[:title_en]).to eq("Cherkasy Pine Forest")
        expect(payload[:archetype_key]).to eq(Codex::ARCHETYPES.first)
        expect(payload[:lifecycle_status]).to eq("thriving")
        expect(payload[:geo_region]).to eq("cherkasy")
        expect(payload[:attunement_count]).to eq(0)
        expect(payload[:attunement_elo]).to eq(1500)
        expect(payload[:realm_slug]).to eq("ecosystem")
      end
    end

    it "excludes show-only fields in the default view" do
      expect(payload).not_to have_key(:context_md)
      expect(payload).not_to have_key(:lore_md)
      expect(payload).not_to have_key(:external_refs)
    end
  end

  describe ":show view" do
    let(:node_with_lore) { create(:codex_node, :with_lore, realm: realm) }
    let(:payload) { described_class.render_as_hash(node_with_lore, view: :show) }

    it "includes lore markdown fields and external_refs" do
      expect(payload).to have_key(:context_md)
      expect(payload).to have_key(:cyber_meaning_md)
      expect(payload).to have_key(:lore_md)
      expect(payload).to have_key(:external_refs)
      expect(payload).to have_key(:view_count)
    end
  end

  describe "realm_slug when realm is nil" do
    it "returns nil gracefully" do
      node.realm = nil
      payload = described_class.render_as_hash(node)
      expect(payload[:realm_slug]).to be_nil
    end
  end
end
