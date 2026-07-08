# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::CommentPolicy do
  let(:org)      { create(:organization) }
  let(:author)   { create(:user, organization: org) }
  let(:other)    { create(:user, organization: org) }
  let(:admin)    { create(:user, :admin, organization: org) }
  let(:node)     { create(:codex_node) }
  let(:comment)  { create(:codex_comment, user: author, commentable: node) }

  describe "#index? / #show?" do
    it "permits authenticated readers" do
      expect(described_class.new(author, comment)).to be_index
    end

    it "denies anonymous readers" do
      expect(described_class.new(nil, comment)).not_to be_index
      expect(described_class.new(nil, comment)).not_to be_show
    end

    it "hides hidden comments from non-admins" do
      comment.update!(hidden_at: Time.current, hidden_by_admin: admin)
      expect(described_class.new(other, comment)).not_to be_show
      expect(described_class.new(admin, comment)).to be_show
    end
  end

  describe "#create?" do
    it "permits any authenticated user" do
      expect(described_class.new(other, Codex::Comment.new)).to be_create
      expect(described_class.new(nil, Codex::Comment.new)).not_to be_create
    end
  end

  describe "#update? / #destroy?" do
    it "permits the author within EDIT_GRACE" do
      expect(described_class.new(author, comment)).to be_update
      expect(described_class.new(author, comment)).to be_destroy
    end

    it "denies the author after the grace window expires" do
      comment.update_column(:created_at, 25.hours.ago)
      expect(described_class.new(author, comment)).not_to be_update
      expect(described_class.new(author, comment)).not_to be_destroy
    end

    it "denies non-author non-admins" do
      expect(described_class.new(other, comment)).not_to be_update
      expect(described_class.new(other, comment)).not_to be_destroy
    end

    it "permits admin+ regardless of grace window" do
      comment.update_column(:created_at, 7.days.ago)
      expect(described_class.new(admin, comment)).to be_update
      expect(described_class.new(admin, comment)).to be_destroy
    end
  end

  describe "#hide?" do
    it "is admin-only" do
      expect(described_class.new(admin, comment)).to be_hide
      expect(described_class.new(author, comment)).not_to be_hide
    end
  end

  describe "Scope#resolve" do
    let!(:visible) { create(:codex_comment, user: author, commentable: node) }
    let!(:hidden) do
      c = create(:codex_comment, user: author, commentable: node)
      c.update!(hidden_at: Time.current, hidden_by_admin: admin)
      c
    end

    it "hides hidden comments from regular users" do
      scoped = described_class::Scope.new(author, Codex::Comment.all).resolve
      expect(scoped).to include(visible)
      expect(scoped).not_to include(hidden)
    end

    it "shows everything to admins" do
      scoped = described_class::Scope.new(admin, Codex::Comment.all).resolve
      expect(scoped).to include(visible, hidden)
    end

    it "returns only visible comments for an anonymous scope" do
      scoped = described_class::Scope.new(nil, Codex::Comment.all).resolve
      expect(scoped).to include(visible)
      expect(scoped).not_to include(hidden)
    end
  end
end
