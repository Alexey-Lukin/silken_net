# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::CommentBlueprint do
  let(:user)    { create(:user) }
  let(:node)    { create(:codex_node) }
  let(:comment) { create(:codex_comment, user: user, commentable: node, body_md: "**Hello** world") }

  describe "rendering" do
    let(:payload) { described_class.render_as_hash(comment) }

    it "includes identity, body_md, and computed fields" do
      aggregate_failures do
        expect(payload[:id]).to eq(comment.id)
        expect(payload[:body_md]).to eq("**Hello** world")
        expect(payload[:parent_id]).to be_nil
        expect(payload[:author]).to eq({ id: user.id })
        expect(payload[:hidden]).to be(false)
        expect(payload[:replies_count]).to eq(0)
      end
    end

    it "renders body_html via Codex::MarkdownRenderer" do
      expect(payload[:body_html]).to include("<strong>Hello</strong>")
      expect(payload[:body_html]).to include("world")
    end
  end

  describe "hidden comment" do
    it "reports hidden: true when hidden_at is set" do
      comment.update!(hidden_at: Time.current)
      payload = described_class.render_as_hash(comment)
      expect(payload[:hidden]).to be(true)
    end
  end
end
