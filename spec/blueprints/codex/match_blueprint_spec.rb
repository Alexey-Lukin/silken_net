# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::MatchBlueprint do
  let(:realm) { create(:codex_realm) }
  let(:left)  { create(:codex_node, realm: realm, slug: "left-node") }
  let(:right) { create(:codex_node, realm: realm, slug: "right-node") }
  let(:user)  { create(:user) }
  let(:match) do
    create(:codex_match, user: user, realm: realm, left: left, right: right)
  end

  describe "rendering" do
    let(:payload) { described_class.render_as_hash(match) }

    it "includes all fields including computed is_skip and winner_slug" do
      aggregate_failures do
        expect(payload[:id]).to eq(match.id)
        expect(payload[:user_id]).to eq(user.id)
        expect(payload[:codex_realm_id]).to eq(realm.id)
        expect(payload[:left_node_id]).to eq(left.id)
        expect(payload[:right_node_id]).to eq(right.id)
        expect(payload[:winner_node_id]).to eq(left.id) # factory default
        expect(payload[:pair_seed]).to be_present
        expect(payload[:elo_delta_left]).to eq(16)
        expect(payload[:elo_delta_right]).to eq(-16)
        expect(payload[:is_skip]).to be(false)
        expect(payload[:winner_slug]).to eq("left-node")
      end
    end
  end

  describe "skip match (no winner)" do
    it "reports is_skip: true and winner_slug: nil" do
      skip_match = create(:codex_match, user: user, realm: realm, left: left, right: right).tap do |m|
        m.update_columns(winner_node_id: nil, elo_delta_left: 0, elo_delta_right: 0)
      end
      payload = described_class.render_as_hash(skip_match.reload)
      expect(payload[:is_skip]).to be(true)
      expect(payload[:winner_slug]).to be_nil
    end
  end
end
