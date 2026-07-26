# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::FractionBlueprint do
  let(:realm)    { create(:codex_realm, slug: "ecosystem") }
  let(:node)     { create(:codex_node, realm: realm, slug: "cherkasy-bir", title_uk: "Черкаський бір", title_en: "Cherkasy") }
  let(:user)     { create(:user) }
  let(:fraction) { create(:codex_fraction, user: user, node: node, archetype_key: node.archetype_key, house_color_token: "gaia-primary") }

  describe "rendering" do
    let(:payload) { described_class.render_as_hash(fraction) }

    it "includes identity, denormalised node fields, and cooldown state" do
      aggregate_failures do
        expect(payload[:id]).to eq(fraction.id)
        expect(payload[:user_id]).to eq(user.id)
        expect(payload[:codex_node_id]).to eq(node.id)
        expect(payload[:archetype_key]).to eq(node.archetype_key)
        expect(payload[:house_color_token]).to eq("gaia-primary")
        expect(payload[:node_slug]).to eq("cherkasy-bir")
        expect(payload[:node_title_uk]).to eq("Черкаський бір")
        expect(payload[:node_title_en]).to eq("Cherkasy")
        expect(payload[:realm_slug]).to eq("ecosystem")
        expect(payload[:cooldown_until]).to be_a(String) # ISO 8601
        expect(payload[:cooldown_active]).to be(true).or be(false)
      end
    end
  end

  describe "nil node tolerance" do
    it "returns nil for node-derived fields when node is missing" do
      fraction.node = nil
      payload = described_class.render_as_hash(fraction)
      expect(payload[:node_slug]).to be_nil
      expect(payload[:node_title_en]).to be_nil
      expect(payload[:realm_slug]).to be_nil
    end
  end
end
