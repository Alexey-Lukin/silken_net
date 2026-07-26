# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Attunements::Toggle do
  def render_toggle(node:, attuned:, count:)
    helpers = ActionController::Base.helpers
    Class.new(Codex::Attunements::Toggle) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_node_attunements_path) { |slug| "/api/v1/codex/nodes/#{slug}/attunements" }
    end.new(node: node, current_user_attuned: attuned, count: count).call
  end

  let(:node) do
    OpenStruct.new(id: 42, slug: "cherkasy-bir", attunement_count: 7).tap do |n|
      n.define_singleton_method(:to_param) { n.slug }
    end
  end

  describe "rendering" do
    it "renders the count using the public DOM id" do
      html = render_toggle(node: node, attuned: false, count: 7)
      expect(html).to include('id="codex_node_42_attunement_count"')
      expect(html).to include(">7<")
    end

    it "shows 'Attune' label and POST verb when the user is not attuned" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include(">Attune<")
      expect(html).to include('method="post"')
      expect(html).to include('value="post"')
    end

    it "shows 'Attuned' label and DELETE verb when the user is attuned" do
      html = render_toggle(node: node, attuned: true, count: 1)
      expect(html).to include(">Attuned<")
      expect(html).to include('method="delete"')
      expect(html).to include('value="delete"')
    end

    it "does not wire any Stimulus controller (Turbo Stream handles live updates)" do
      html = render_toggle(node: node, attuned: true, count: 1)
      expect(html).not_to include('data-controller=')
    end

    it "renders the 'Attunement' section title" do
      html = render_toggle(node: node, attuned: false, count: 3)
      expect(html).to include(">Attunement<")
    end
  end

  describe "edge cases" do
    it "renders a zero count as '0' with no special-cased empty state" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include(">0<")
    end

    it "treats a nil current_user_attuned the same as false (renders the Attune/POST button)" do
      html = render_toggle(node: node, attuned: nil, count: 2)
      expect(html).to include(">Attune<")
      expect(html).to include('method="post"')
      expect(html).not_to include("bg-status-success")
    end
  end

  describe "accessibility" do
    it "submits via a real <button type=\"submit\"> so the toggle works without JavaScript" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include("<button")
      expect(html).to include('type="submit"')
    end
  end

  describe "design system compliance" do
    it "uses gaia-* / status-* tokens, not raw bg-white / text-gray-*" do
      html = render_toggle(node: node, attuned: true, count: 5)
      expect(html).not_to include("bg-white")
      expect(html).not_to match(/text-gray-\d+/)
      expect(html).to include("text-gaia-text-muted")
    end

    it "applies the success token when attuned" do
      html = render_toggle(node: node, attuned: true, count: 5)
      expect(html).to include("bg-status-success")
    end

    it "wires focus-visible:ring-2 for keyboard accessibility" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include("focus-visible:ring-2")
    end
  end
end
