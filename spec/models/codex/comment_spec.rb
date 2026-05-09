# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Comment do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  describe "validations" do
    it "is valid with a body and a commentable" do
      expect(build(:codex_comment, user: user, commentable: node)).to be_valid
    end

    it "requires body_md" do
      expect(build(:codex_comment, user: user, commentable: node, body_md: "")).not_to be_valid
    end

    it "rejects body longer than BODY_MAX" do
      huge = "x" * (described_class::BODY_MAX + 1)
      expect(build(:codex_comment, user: user, commentable: node, body_md: huge)).not_to be_valid
    end

    it "permits flag_reason from FLAG_REASONS only" do
      ok  = build(:codex_comment, user: user, commentable: node, flag_reason: "spam")
      bad = build(:codex_comment, user: user, commentable: node, flag_reason: "garbage")
      expect(ok).to be_valid
      expect(bad).not_to be_valid
    end
  end

  describe "threading" do
    let!(:top) { create(:codex_comment, user: user, commentable: node) }

    it "allows a one-level reply that shares the commentable" do
      reply = build(:codex_comment, user: user, commentable: node, parent: top)
      expect(reply).to be_valid
    end

    it "rejects a reply to a reply" do
      reply  = create(:codex_comment, user: user, commentable: node, parent: top)
      nested = build(:codex_comment, user: user, commentable: node, parent: reply)
      expect(nested).not_to be_valid
      expect(nested.errors[:parent_id]).to be_present
    end

    it "rejects a reply whose parent belongs to a different commentable" do
      other_node = create(:codex_node)
      reply = build(:codex_comment, user: user, commentable: other_node, parent: top)
      expect(reply).not_to be_valid
    end
  end

  describe "counter cache + scopes" do
    it "increments commentable comments_count on create and decrements on destroy" do
      expect { create(:codex_comment, user: user, commentable: node) }
        .to change { node.reload.comments_count }.by(1)
      comment = node.comments.first
      expect { comment.destroy }.to change { node.reload.comments_count }.by(-1)
    end

    it "exposes visible/hidden/top_level/chronological scopes" do
      visible_one  = create(:codex_comment, user: user, commentable: node)
      visible_two  = create(:codex_comment, user: user, commentable: node)
      hidden       = create(:codex_comment, user: user, commentable: node)
      hidden.update!(hidden_at: Time.current, hidden_by_admin: create(:user, :admin))
      reply        = create(:codex_comment, user: user, commentable: node, parent: visible_one)

      expect(described_class.visible).to include(visible_one, visible_two, reply)
      expect(described_class.visible).not_to include(hidden)
      expect(described_class.hidden).to contain_exactly(hidden)
      expect(described_class.top_level).to include(visible_one, visible_two, hidden)
      expect(described_class.top_level).not_to include(reply)
      ordered = described_class.chronological.to_a
      expect(ordered.first.created_at).to be <= ordered.last.created_at
    end
  end

  describe "#editable_by?" do
    let(:author) { create(:user) }
    let(:other)  { create(:user) }
    let(:comment) { create(:codex_comment, user: author, commentable: node) }

    it "is true for the author within the EDIT_GRACE window" do
      expect(comment.editable_by?(author)).to be(true)
    end

    it "is false for someone else" do
      expect(comment.editable_by?(other)).to be(false)
    end

    it "is false outside the grace window" do
      comment.update_column(:created_at, 25.hours.ago)
      expect(comment.editable_by?(author)).to be(false)
    end

    it "is false when other_user is nil" do
      expect(comment.editable_by?(nil)).to be(false)
    end
  end
end
