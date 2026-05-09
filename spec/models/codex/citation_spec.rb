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
  end
end
