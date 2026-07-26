# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Match, type: :model do
  let(:realm) { create(:codex_realm) }
  let(:left)  { create(:codex_node, realm: realm) }
  let(:right) { create(:codex_node, realm: realm) }

  it "has a valid factory" do
    expect(build(:codex_match, realm: realm, left: left, right: right)).to be_valid
  end

  # [ARCH.56] Composite partition-PK (id, created_at) is a DB requirement; ActiveRecord must
  # still expose the SCALAR id. Declaring the composite PK here made `match.id` an array,
  # which wrote an array into the bigint `codex_discoveries.trigger_ref_id` (StatementInvalid
  # past the rescue → DeadSet) and rendered `"id": [42, …]` into the public POST /matches
  # response via MatchBlueprint#identifier. Mirrors TelemetryLog / GatewayTelemetryLog.
  describe "primary key" do
    it "exposes a scalar id despite the composite partition PK" do
      match = create(:codex_match, realm: realm, left: left, right: right)
      expect(match.id).to be_an(Integer)
    end

    it "serialises a scalar id through MatchBlueprint (public API contract)" do
      match = create(:codex_match, realm: realm, left: left, right: right)
      expect(Codex::MatchBlueprint.render_as_hash(match)[:id]).to be_an(Integer)
    end
  end

  describe "validations" do
    it "requires winner to be one of the pair" do
      stranger = create(:codex_node, realm: realm)
      m = build(:codex_match,
                realm: realm, left: left, right: right,
                winner_node_id: stranger.id)
      expect(m).not_to be_valid
      expect(m.errors[:winner_node_id]).to include("must equal left_node_id or right_node_id")
    end

    it "permits NULL winner (skip)" do
      m = build(:codex_match, realm: realm, left: left, right: right,
                winner_node_id: nil)
      expect(m).to be_valid
      expect(m.skip?).to be(true)
    end

    it "rejects same node on both sides" do
      m = build(:codex_match, realm: realm, left: left, right: left,
                winner_node_id: left.id)
      expect(m).not_to be_valid
      expect(m.errors[:right_node_id]).to include("must differ from left_node_id")
    end

    it "rejects cross-realm pair" do
      other_realm = create(:codex_realm)
      foreign = create(:codex_node, realm: other_realm)
      m = build(:codex_match, realm: realm, left: left, right: foreign,
                winner_node_id: left.id)
      expect(m).not_to be_valid
      expect(m.errors[:right_node_id]).to include("must share the same realm as left_node")
    end

    it "rejects a mismatched codex_realm_id (realm envelope ≠ pair realm)" do
      other_realm = create(:codex_realm)
      m = build(:codex_match, realm: other_realm, left: left, right: right,
                codex_realm_id: other_realm.id, winner_node_id: left.id)
      expect(m).not_to be_valid
      expect(m.errors[:codex_realm_id]).to include("must match the pair realm")
    end

    it "skips the pair-shape validations when a node is absent (guard early-returns)" do
      m = build(:codex_match, realm: realm, left: left, right: right, winner_node_id: nil)
      m.right_node = nil
      m.right_node_id = nil

      expect(m).not_to be_valid # belongs_to :right_node is required
      expect(m.errors[:right_node_id]).not_to include("must differ from left_node_id")
      expect(m.errors[:right_node_id]).not_to include("must share the same realm as left_node")
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:m1) { create(:codex_match, user: user, realm: realm, left: left, right: right, created_at: 2.hours.ago) }
    let!(:m2) { create(:codex_match, user: user, realm: realm, left: left, right: right, created_at: 1.minute.ago) }

    it "for_user filters" do
      other = create(:user)
      _other_match = create(:codex_match, user: other, realm: realm, left: left, right: right)
      expect(described_class.for_user(user).count).to eq(2)
    end

    it "recent orders desc by created_at" do
      expect(described_class.recent.first).to eq(m2)
    end

    it "for_realm filters" do
      other_realm = create(:codex_realm)
      other_left = create(:codex_node, realm: other_realm)
      other_right = create(:codex_node, realm: other_realm)
      _other = create(:codex_match, user: user, realm: other_realm,
                                    left: other_left, right: other_right)
      expect(described_class.for_realm(realm.id).count).to eq(2)
    end

    it "for_realm without a realm_id is a no-op (blank guard → unscoped)" do
      expect(described_class.for_realm(nil).count).to eq(described_class.count)
    end
  end
end
