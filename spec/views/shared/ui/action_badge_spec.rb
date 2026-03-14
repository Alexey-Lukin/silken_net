# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::ActionBadge do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "action pattern matching" do
    it "maps delete actions to destructive (danger) style" do
      html = render_component(action: "delete_user")
      expect(html).to include("bg-status-danger")
      expect(html).to include("text-status-danger-text")
    end

    it "maps update actions to mutative (warning) style" do
      html = render_component(action: "update_firmware")
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "maps create actions to creative (active) style" do
      html = render_component(action: "create_tree")
      expect(html).to include("bg-status-active")
      expect(html).to include("text-status-active-text")
    end

    it "maps unknown actions to neutral style" do
      html = render_component(action: "login")
      expect(html).to include("bg-status-neutral")
      expect(html).to include("text-status-neutral-text")
    end
  end

  describe "rendering" do
    let(:html) { render_component(action: "create_node") }

    it "displays the action text" do
      expect(html).to include("create_node")
    end

    it "uses text-mini instead of arbitrary text-[9px]" do
      expect(html).to include("text-mini")
      expect(html).not_to include("text-[")
    end

    it "includes tracking-widest for uppercase microcopy" do
      expect(html).to include("tracking-widest")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(action: "delete_tree") }

    it "includes role=status" do
      expect(html).to include('role="status"')
    end

    it "includes aria-label with action text" do
      expect(html).to include("Action: delete_tree")
    end
  end

  describe "with class override" do
    let(:html) { render_component(action: "login", class: "ml-2") }

    it "accepts additional classes" do
      expect(html).to include("ml-2")
    end
  end
end
