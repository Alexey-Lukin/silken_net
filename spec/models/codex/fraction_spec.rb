# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fraction, type: :model do
  let(:realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }

  it "has a valid factory" do
    expect(build(:codex_fraction, node: node)).to be_valid
  end

  describe "associations & uniqueness" do
    it "belongs to user and node and is unique per user" do
      user = create(:user)
      create(:codex_fraction, user: user, node: node)
      duplicate = build(:codex_fraction, user: user, node: create(:codex_node, realm: realm))
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end

    it "rejects extinct or destroyed nodes" do
      extinct = create(:codex_node, realm: realm, lifecycle_status: :extinct)
      destroyed = create(:codex_node, realm: realm, lifecycle_status: :destroyed)
      expect(build(:codex_fraction, node: extinct)).not_to be_valid
      expect(build(:codex_fraction, node: destroyed)).not_to be_valid
    end

    it "permits mythical nodes" do
      mythical = create(:codex_node, realm: realm, lifecycle_status: :mythical)
      expect(build(:codex_fraction, node: mythical)).to be_valid
    end

    it "skips the lifecycle check when node is absent (belongs_to reports it)" do
      fraction = build(:codex_fraction, node: nil)

      expect(fraction).not_to be_valid
      expect(fraction.errors[:codex_node_id]).to be_empty
      expect(fraction.errors[:node]).to include("must exist")
    end
  end

  describe "cooldown helpers" do
    it "treats a freshly-set fraction as locked for 7 days" do
      now = Time.zone.parse("2026-05-09 10:00:00")
      fraction = build(:codex_fraction,
                       node: node,
                       chosen_at: now, last_changed_at: now)
      expect(fraction.cooldown_active?(now)).to be(true)
      expect(fraction.cooldown_until).to eq(now + 7.days)
      expect(fraction.seconds_until_unlocked(now)).to eq(7.days.to_i)
    end

    it "is unlocked once 7 days elapse" do
      now = Time.current
      fraction = build(:codex_fraction,
                       node: node, chosen_at: 8.days.ago, last_changed_at: 8.days.ago)
      expect(fraction.cooldown_active?(now)).to be(false)
      expect(fraction.seconds_until_unlocked(now)).to eq(0)
    end
  end

  describe "scopes" do
    it "ordered returns most-recently-changed first" do
      old = create(:codex_fraction, last_changed_at: 5.days.ago, node: node)
      recent = create(:codex_fraction, last_changed_at: 1.minute.ago, node: create(:codex_node, realm: realm))
      expect(described_class.ordered.first).to eq(recent)
      expect(described_class.ordered.second).to eq(old)
    end

    it "by_archetype filters by denormalised key" do
      f1 = create(:codex_fraction, archetype_key: "nlos_routing", node: node)
      _f2 = create(:codex_fraction, archetype_key: "mesh_sharding", node: create(:codex_node, realm: realm))
      expect(described_class.by_archetype("nlos_routing")).to contain_exactly(f1)
      expect(described_class.by_archetype(nil).count).to eq(2)
    end
  end
end
