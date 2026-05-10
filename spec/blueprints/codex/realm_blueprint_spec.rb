# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::RealmBlueprint do
  let(:realm) { create(:codex_realm, slug: "ecosystem", name_uk: "Екосистеми", name_en: "Ecosystems", glyph: "forest", accent_token: "gaia-primary", position: 1) }

  it "renders all fields including the dynamic nodes_count" do
    payload = described_class.render_as_hash(realm, nodes_counts: { realm.id => 42 })

    aggregate_failures do
      expect(payload[:id]).to eq(realm.id)
      expect(payload[:slug]).to eq("ecosystem")
      expect(payload[:name_uk]).to eq("Екосистеми")
      expect(payload[:name_en]).to eq("Ecosystems")
      expect(payload[:glyph]).to eq("forest")
      expect(payload[:accent_token]).to eq("gaia-primary")
      expect(payload[:position]).to eq(1)
      expect(payload[:is_active]).to be(true)
      expect(payload[:nodes_count]).to eq(42)
    end
  end

  it "defaults nodes_count to 0 when options[:nodes_counts] is nil" do
    payload = described_class.render_as_hash(realm)
    expect(payload[:nodes_count]).to eq(0)
  end

  it "defaults nodes_count to 0 when the realm id is missing from the hash" do
    payload = described_class.render_as_hash(realm, nodes_counts: {})
    expect(payload[:nodes_count]).to eq(0)
  end
end
