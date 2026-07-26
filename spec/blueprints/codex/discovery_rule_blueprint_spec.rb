# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryRuleBlueprint do
  let(:node) { create(:codex_node, slug: "mycorrhiza") }
  let(:user) { create(:user) }
  let(:rule) do
    create(:codex_discovery_rule,
           node: node,
           created_by_user: user,
           name: "Battle Veteran",
           condition_type: :match_count,
           threshold_value: 10,
           params: { "realm_slug" => "ecosystem" },
           active: true)
  end

  describe "rendering" do
    let(:payload) { described_class.render_as_hash(rule) }

    it "includes all fields plus denormalised node_slug" do
      aggregate_failures do
        expect(payload[:id]).to eq(rule.id)
        expect(payload[:name]).to eq("Battle Veteran")
        expect(payload[:codex_node_id]).to eq(node.id)
        expect(payload[:condition_type]).to eq("match_count")
        expect(payload[:threshold_value]).to eq(10)
        expect(payload[:params]).to eq({ "realm_slug" => "ecosystem" })
        expect(payload[:active]).to be(true)
        expect(payload[:created_by_user_id]).to eq(user.id)
        expect(payload[:node_slug]).to eq("mycorrhiza")
      end
    end
  end

  describe "nil node tolerance" do
    it "returns nil for node_slug when node is missing" do
      rule.node = nil
      payload = described_class.render_as_hash(rule)
      expect(payload[:node_slug]).to be_nil
    end
  end
end
