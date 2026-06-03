# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Citation do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  describe "validations" do
    it "is valid with allowed citable_type and required associations" do
      cit = build(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: 1)
      expect(cit).to be_valid
    end

    it "rejects citable_type outside allow-list" do
      cit = build(:codex_citation, node: node, created_by_user: user, citable_type: "User", citable_id: 1)
      expect(cit).not_to be_valid
      expect(cit.errors[:citable_type]).to be_present
    end

    it "caps note length at 140" do
      cit = build(:codex_citation, node: node, created_by_user: user, note: "x" * 141)
      expect(cit).not_to be_valid
    end

    it "prevents the same user citing the same node on the same target twice" do
      create(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: 7)
      dup = build(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: 7)
      expect(dup).not_to be_valid
    end

    it "allows different users to cite the same node on the same target" do
      other_user = create(:user)
      create(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: 9)
      cit = build(:codex_citation, node: node, created_by_user: other_user, citable_type: "Tree", citable_id: 9)
      expect(cit).to be_valid
    end
  end

  describe "counter cache" do
    it "increments node.citation_count on create and decrements on destroy" do
      expect {
        create(:codex_citation, node: node, created_by_user: user)
      }.to change { node.reload.citation_count }.by(1)

      cit = node.citations.first
      expect { cit.destroy }.to change { node.reload.citation_count }.by(-1)
    end
  end

  describe ".for_target" do
    it "scopes by polymorphic target type and id" do
      cit = create(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: 42)
      expect(described_class.where(citable_type: "Tree", citable_id: 42)).to include(cit)
    end

    it "returns none for an untyped target (anonymous class → nil polymorphic type)" do
      expect(described_class.for_target(Class.new.new)).to be_empty
    end
  end

  describe ".bulk_for (Phase 6)" do
    let(:tree)    { create(:tree) }
    let(:cluster) { create(:cluster) }

    it "returns citations grouped by [type, id]" do
      on_tree    = create(:codex_citation, node: node, created_by_user: user, citable_type: "Tree", citable_id: tree.id)
      on_cluster = create(:codex_citation, node: node, created_by_user: user, citable_type: "Cluster", citable_id: cluster.id)
      result = described_class.bulk_for([ tree, cluster ])
      expect(result[[ "Tree", tree.id ]]).to contain_exactly(on_tree)
      expect(result[[ "Cluster", cluster.id ]]).to contain_exactly(on_cluster)
    end

    it "returns an empty hash for blank input" do
      expect(described_class.bulk_for(nil)).to eq({})
      expect(described_class.bulk_for([])).to eq({})
    end

    it "skips untyped targets (anonymous class → nil polymorphic type)" do
      expect(described_class.bulk_for([ Class.new.new ])).to eq({})
    end
  end

  describe "#within_edit_grace? (Phase 6)" do
    it "is true within 24 h, false past it, nil-safe" do
      cit = build(:codex_citation, created_at: 1.hour.ago)
      expect(cit.within_edit_grace?).to be true
      cit.created_at = 25.hours.ago
      expect(cit.within_edit_grace?).to be false
      cit.created_at = nil
      expect(cit.within_edit_grace?).to be false
    end
  end
end
