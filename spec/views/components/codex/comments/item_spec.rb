# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Comments::Item do
  def render_item(comment)
    helpers = ActionController::Base.helpers
    Class.new(Codex::Comments::Item) do
      define_method(:helpers) { helpers }
    end.new(comment: comment).call
  end

  def fake_comment(**overrides)
    base = {
      id: 7,
      body_md: "Hello **world**.",
      hidden?: false,
      created_at: Time.utc(2026, 5, 9, 13, 0, 0),
      user: OpenStruct.new(email_address: "ranger@example.com", full_name: "Ranger Rick")
    }
    OpenStruct.new(base.merge(overrides))
  end

  it "uses the canonical DOM id codex_comment_<id>" do
    html = render_item(fake_comment)
    expect(html).to include('id="codex_comment_7"')
  end

  it "renders sanitised markdown for the body" do
    html = render_item(fake_comment)
    expect(html).to include("<strong>world</strong>")
  end

  it "shows the author's display name (never the email — cross-org PII) and an ISO timestamp" do
    html = render_item(fake_comment)
    expect(html).to include("Ranger Rick")
    expect(html).not_to include("ranger@example.com")
    expect(html).to include("2026-05-09 13:00 UTC")
  end

  it "shows a moderator-hidden notice and skips body when hidden" do
    html = render_item(fake_comment(hidden?: true, body_md: "shouldn't render"))
    expect(html).to include("Hidden by moderator")
    expect(html).not_to include("shouldn't render")
  end

  it "uses gaia-* tokens" do
    html = render_item(fake_comment)
    expect(html).not_to include("bg-white")
    expect(html).not_to match(/text-gray-\d+/)
    expect(html).to include("bg-gaia-surface")
  end
end
