# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Attunement do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  describe "validations" do
    it "is valid with a user, node and intensity in 1..5" do
      (1..5).each do |i|
        expect(build(:codex_attunement, user: user, node: node, intensity: i)).to be_valid
      end
    end

    it "rejects intensity 0 or 6" do
      [ 0, 6 ].each do |i|
        att = build(:codex_attunement, user: user, node: node, intensity: i)
        expect(att).not_to be_valid
        expect(att.errors[:intensity]).to be_present
      end
    end

    it "caps quote at 280 chars" do
      att = build(:codex_attunement, user: user, node: node, quote: "x" * 281)
      expect(att).not_to be_valid
    end

    it "permits a nil quote" do
      expect(build(:codex_attunement, user: user, node: node, quote: nil)).to be_valid
    end

    it "is unique per (user, node)" do
      create(:codex_attunement, user: user, node: node)
      dup = build(:codex_attunement, user: user, node: node)
      expect(dup).not_to be_valid
      expect(dup.errors[:user_id]).to be_present
    end
  end

  describe "counter cache" do
    it "increments node attunement_count on create and decrements on destroy" do
      expect { create(:codex_attunement, user: user, node: node) }
        .to change { node.reload.attunement_count }.by(1)
      a = node.attunements.first
      expect { a.destroy }.to change { node.reload.attunement_count }.by(-1)
    end
  end

  describe "started_at default" do
    it "fills started_at on create when blank" do
      att = create(:codex_attunement, user: user, node: node)
      expect(att.started_at).to be_within(5.seconds).of(Time.current)
    end

    it "preserves an explicitly-supplied started_at" do
      ts = 3.days.ago.change(usec: 0)
      att = create(:codex_attunement, user: user, node: node, started_at: ts)
      expect(att.started_at).to eq(ts)
    end
  end

  describe "scopes" do
    it "filters by node and by user" do
      a = create(:codex_attunement, user: user, node: node)
      another_node = create(:codex_node)
      another_user = create(:user)
      create(:codex_attunement, user: another_user, node: node)
      create(:codex_attunement, user: user, node: another_node)

      expect(described_class.for_node(node).pluck(:id)).to include(a.id)
      expect(described_class.for_user(user).pluck(:codex_node_id)).to contain_exactly(node.id, another_node.id)
    end
  end
end
