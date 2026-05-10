# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Discovery, type: :model do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  it "has a valid factory" do
    expect(build(:codex_discovery, user: user, node: node)).to be_valid
  end

  describe "uniqueness" do
    it "rejects a duplicate user/node pair" do
      create(:codex_discovery, user: user, node: node)
      dup = build(:codex_discovery, user: user, node: node)
      expect(dup).not_to be_valid
      expect(dup.errors[:user_id]).to include("has already unlocked this node")
    end
  end

  describe "trigger_type enum" do
    it "exposes prefixed predicates" do
      d = build(:codex_discovery, trigger_type: :match_milestone)
      expect(d.triggered_by_match_milestone?).to be(true)
      expect(d.triggered_by_telemetry_observation?).to be(false)
    end
  end

  describe "polymorphic trigger_ref" do
    it "stores type + id loosely (no FK)" do
      d = create(:codex_discovery, user: user, node: node,
                 trigger_ref_type: "TelemetryLog", trigger_ref_id: 999_999)
      expect(d.trigger_ref_type).to eq("TelemetryLog")
      expect(d.trigger_ref_id).to eq(999_999)
    end
  end

  describe "callbacks" do
    it "defaults unlocked_at on create when missing" do
      d = described_class.create!(user: user, node: node, codex_node_id: node.id,
                                  trigger_type: :manual_unlock, unlocked_at: nil)
      expect(d.unlocked_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "scopes" do
    it "for_user / recent" do
      other = create(:user)
      n2 = create(:codex_node)
      old_d = create(:codex_discovery, user: user, node: node, unlocked_at: 1.day.ago)
      new_d = create(:codex_discovery, user: user, node: n2,   unlocked_at: 1.minute.ago)
      _other = create(:codex_discovery, user: other, node: node)

      expect(described_class.for_user(user)).to contain_exactly(old_d, new_d)
      expect(described_class.for_user(user).recent.first).to eq(new_d)
    end
  end

  describe "counter cache" do
    it "increments codex_nodes.discovery_count on create" do
      expect {
        create(:codex_discovery, user: user, node: node)
      }.to change { node.reload.discovery_count }.by(1)
    end
  end
end
