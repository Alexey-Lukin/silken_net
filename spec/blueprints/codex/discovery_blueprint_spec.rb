# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryBlueprint do
  let(:node)      { create(:codex_node, slug: "mafusail", title_en: "Mafusail", title_uk: "Мафусаїл", archetype_key: "relict_oracle") }
  let(:user)      { create(:user) }
  let(:discovery) { create(:codex_discovery, user: user, node: node, trigger_type: :match_milestone) }

  describe "rendering" do
    let(:payload) { described_class.render_as_hash(discovery) }

    it "includes denormalised node fields for the discovery list" do
      aggregate_failures do
        expect(payload[:id]).to eq(discovery.id)
        expect(payload[:user_id]).to eq(user.id)
        expect(payload[:codex_node_id]).to eq(node.id)
        expect(payload[:trigger_type]).to eq("match_milestone")
        expect(payload[:unlocked_at]).to be_present
        expect(payload[:node_slug]).to eq("mafusail")
        expect(payload[:node_title_en]).to eq("Mafusail")
        expect(payload[:node_title_uk]).to eq("Мафусаїл")
        expect(payload[:node_archetype_key]).to eq("relict_oracle")
      end
    end
  end

  describe "nil node tolerance" do
    it "returns nil for node-derived fields when node is missing" do
      discovery.node = nil
      payload = described_class.render_as_hash(discovery)
      expect(payload[:node_slug]).to be_nil
      expect(payload[:node_title_en]).to be_nil
      expect(payload[:node_archetype_key]).to be_nil
    end
  end
end
