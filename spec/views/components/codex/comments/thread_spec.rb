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

  it "renders the canonical DOM id used by the Turbo Stream broadcaster" do
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
      user: OpenStruct.new(email_address: "user@example.com")
    )
    html = render_thread(node: node, comments: [ comment ], current_user: nil)
    expect(html).not_to include("Be the first to share")
    expect(html).to include("Great tree!")
    expect(html).to include("user@example.com")
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

  it "uses gaia-* tokens only" do
    html = render_thread(node: node, comments: [], current_user: nil)
    expect(html).not_to include("bg-white")
    expect(html).not_to match(/text-gray-\d+/)
    expect(html).to include("text-gaia-text-muted")
  end
end
