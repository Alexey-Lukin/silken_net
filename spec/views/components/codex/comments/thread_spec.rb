# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Comments::Thread do
  def render_thread(node:, comments:, current_user:)
    helpers = ActionController::Base.helpers
    Class.new(Codex::Comments::Thread) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_node_comments_path) { |slug| "/api/v1/codex/nodes/#{slug}/comments" }
      # When `current_user` is present the Thread renders Codex::Comments::Form
      # — patch the same routing helper on Form's instance via a subclass.
      define_method(:render) do |component|
        if component.is_a?(Codex::Comments::Form)
          form = Class.new(Codex::Comments::Form) do
            define_method(:helpers) { helpers }
            define_method(:api_v1_codex_node_comments_path) { |slug| "/api/v1/codex/nodes/#{slug}/comments" }
          end.new(node: node)
          super(form)
        else
          super(component)
        end
      end
    end.new(node: node, comments: comments, current_user: current_user).call
  end

  let(:node) do
    OpenStruct.new(id: 9, slug: "cherkasy-bir").tap do |n|
      n.define_singleton_method(:to_param) { n.slug }
    end
  end

  it "renders the canonical DOM id — a stable list anchor with no producer (UI.2)" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).to include('id="codex_node_9_comments"')
  end

  it "renders the empty-state copy when there are no comments" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).to include("Be the first to share")
  end

  it "renders each comment item when comments are present" do
    comment = OpenStruct.new(
      id: 1,
      body_md: "Great tree!",
      hidden?: false,
      created_at: Time.utc(2026, 5, 10, 8, 0, 0),
      user: OpenStruct.new(email_address: "user@example.com", full_name: "Tree Fan")
    )
    html = render_thread(node: node, comments: [ comment ], current_user: nil)
    expect(html).not_to include("Be the first to share")
    expect(html).to include("Great tree!")
    expect(html).to include("Tree Fan")
    expect(html).not_to include("user@example.com")
  end

  it "omits the composer when there is no current_user" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).not_to include("Post")
    expect(html).not_to include("comment[body_md]")
  end

  it "renders the composer when current_user is present" do
    user = double("User")
    html = render_thread(node: node, comments: [], current_user: user)
    expect(html).to include("comment[body_md]")
    expect(html).to include("Post")
  end

  it "wires the Stimulus controller for live appends" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).to include('data-controller="codex--comment"')
  end

  # [UI.2] Stimulus-scope = controller-елемент + нащадки. Form (target=form/
  # body) — sibling списку, тож controller мусить сидіти на СПІЛЬНОМУ предку,
  # інакше composer-таргети поза scope і Cmd/Ctrl+Enter мертвий (регресія
  # coverage-sweep 2026-07-08).
  it "keeps the form/body targets INSIDE the controller element's subtree" do
    user = double("User")
    html = render_thread(node: node, comments: [], current_user: user)

    doc = Nokogiri::HTML5.fragment(html)
    scope = doc.at_css('[data-controller="codex--comment"]')
    expect(scope).to be_present
    expect(scope.at_css('[data-codex--comment-target="list"]')).to be_present
    expect(scope.at_css('[data-codex--comment-target="form"]')).to be_present
    expect(scope.at_css('[data-codex--comment-target="body"]')).to be_present
  end

  it "uses gaia-* tokens only" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).not_to include("bg-white")
    expect(html).not_to match(/text-gray-\d+/)
    expect(html).to include("text-gaia-text-muted")
  end

  it "renders multiple comments in the given order" do
    first = OpenStruct.new(
      id: 1, body_md: "First!", hidden?: false, created_at: Time.utc(2026, 5, 10, 8, 0, 0),
      user: OpenStruct.new(email_address: "a@example.com", full_name: "Ann")
    )
    second = OpenStruct.new(
      id: 2, body_md: "Second!", hidden?: false, created_at: Time.utc(2026, 5, 10, 9, 0, 0),
      user: OpenStruct.new(email_address: "b@example.com", full_name: "Bo")
    )
    html = render_thread(node: node, comments: [ first, second ], current_user: nil)
    expect(html.index("First!")).to be < html.index("Second!")
  end

  it "derives the comment list DOM id from the node's id, not a hardcoded value" do
    other_node = OpenStruct.new(id: 123, slug: "other-node").tap { |n| n.define_singleton_method(:to_param) { n.slug } }
    html = render_thread(node: other_node, comments: [], current_user: nil)
    expect(html).to include('id="codex_node_123_comments"')
  end

  it "renders the section heading as a semantic <h3> for screen-reader navigation" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).to include("<h3")
    expect(html).to include(">Discussion<")
  end
end
