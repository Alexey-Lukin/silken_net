# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Comments::Form do
  def render_form(node:)
    helpers = ActionController::Base.helpers
    Class.new(Codex::Comments::Form) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_node_comments_path) { |slug| "/api/v1/codex/nodes/#{slug}/comments" }
    end.new(node: node).call
  end

  let(:node) do
    OpenStruct.new(id: 9, slug: "cherkasy-bir").tap do |n|
      n.define_singleton_method(:to_param) { n.slug }
    end
  end

  describe "rendering" do
    it "posts to the node-scoped comments endpoint" do
      html = render_form(node: node)
      expect(html).to include('action="/api/v1/codex/nodes/cherkasy-bir/comments"')
      expect(html).to include('method="post"')
    end

    it "renders a textarea named comment[body_md] with the i18n placeholder" do
      html = render_form(node: node)
      expect(html).to include('name="comment[body_md]"')
      expect(html).to include("Write a comment in Markdown")
    end

    it "renders a submit button labelled Post" do
      html = render_form(node: node)
      expect(html).to include('type="submit"')
      expect(html).to include(">Post<")
    end
  end

  describe "trust-boundary validation" do
    it "marks the textarea as required so empty submissions are rejected before reaching the server" do
      html = render_form(node: node)
      expect(html).to include("required")
    end

    it "caps the textarea at Codex::Comment::BODY_MAX characters via maxlength" do
      html = render_form(node: node)
      expect(html).to include(%(maxlength="#{Codex::Comment::BODY_MAX}"))
    end
  end

  describe "Stimulus wiring" do
    it "wires the codex--comment target on both the form and the textarea for live reset behavior" do
      html = render_form(node: node)
      expect(html).to include('data-codex--comment-target="form"')
      expect(html).to include('data-codex--comment-target="body"')
    end
  end

  describe "design system compliance" do
    it "uses gaia-input-* tokens for the textarea, not raw Tailwind input styling" do
      html = render_form(node: node)
      expect(html).to include("bg-gaia-input-bg")
      expect(html).to include("border-gaia-input-border")
      expect(html).to include("text-gaia-input-text")
      expect(html).not_to include("bg-white")
    end

    it "uses gaia-primary tokens for the submit button" do
      html = render_form(node: node)
      expect(html).to include("bg-gaia-primary")
      expect(html).to include("text-gaia-primary-text")
    end
  end

  describe "accessibility" do
    it "wires focus-visible ring on both the textarea and the submit button" do
      html = render_form(node: node)
      expect(html.scan("focus-visible:ring-2").size).to be >= 2
    end
  end
end
