# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationComponent, type: :view do
  # =========================================================================
  # CUSTOM_TEXT_SCALE
  # =========================================================================
  describe "CUSTOM_TEXT_SCALE" do
    it "includes custom font-size tokens" do
      expect(described_class::CUSTOM_TEXT_SCALE).to include("micro", "mini", "tiny", "compact")
    end

    it "has exactly 4 custom text scale tokens" do
      expect(described_class::CUSTOM_TEXT_SCALE.size).to eq(4)
    end
  end

  # =========================================================================
  # .merger
  # =========================================================================
  describe ".merger" do
    it "returns a TailwindMerge::Merger instance" do
      expect(described_class.merger).to be_a(TailwindMerge::Merger)
    end

    it "memoizes the merger instance" do
      merger1 = described_class.merger
      merger2 = described_class.merger
      expect(merger1).to equal(merger2)
    end
  end

  # =========================================================================
  # #tokens
  # =========================================================================
  describe "#tokens" do
    let(:component_class) do
      Class.new(described_class) do
        def initialize(classes: "")
          @classes = classes
        end

        def view_template
          div(class: tokens("base-class", @classes)) { "test" }
        end
      end
    end

    it "joins static class names" do
      component = component_class.new
      html = component.call
      expect(html).to include("base-class")
    end

    it "merges additional classes" do
      component = component_class.new(classes: "extra-class")
      html = component.call
      expect(html).to include("extra-class")
    end

    it "filters nil values from static args" do
      component_with_nil = Class.new(described_class) do
        def view_template
          div(class: tokens("a", nil, "b")) { "test" }
        end
      end

      html = component_with_nil.new.call
      expect(html).to include("a")
      expect(html).to include("b")
    end

    it "handles conditional classes" do
      component_conditional = Class.new(described_class) do
        def initialize(active:)
          @active = active
        end

        def view_template
          div(class: tokens("base", "text-gaia-primary": @active, "text-gaia-muted": !@active)) { "test" }
        end
      end

      html_active = component_conditional.new(active: true).call
      expect(html_active).to include("text-gaia-primary")
      expect(html_active).not_to include("text-gaia-muted")

      html_inactive = component_conditional.new(active: false).call
      expect(html_inactive).to include("text-gaia-muted")
      expect(html_inactive).not_to include("text-gaia-primary")
    end

    it "merges conflicting Tailwind classes (last wins via TailwindMerge)" do
      component_conflict = Class.new(described_class) do
        def view_template
          div(class: tokens("p-2 p-4")) { "test" }
        end
      end

      html = component_conflict.new.call
      # TailwindMerge resolves conflict: later class (p-4) wins over earlier (p-2)
      expect(html).to include("p-4")
      expect(html).not_to include("p-2")
    end

    it "handles empty conditional hash" do
      component_empty = Class.new(described_class) do
        def view_template
          div(class: tokens("base")) { "test" }
        end
      end

      html = component_empty.new.call
      expect(html).to include("base")
    end
  end

  # =========================================================================
  # Module inclusions
  # =========================================================================
  describe "module inclusions" do
    it "includes Phlex::HTML as base" do
      expect(described_class.ancestors).to include(Phlex::HTML)
    end

    it "includes Routes helper" do
      expect(described_class.ancestors).to include(Phlex::Rails::Helpers::Routes)
    end

    it "includes TurboStreamFrom helper" do
      expect(described_class.ancestors).to include(Phlex::Rails::Helpers::TurboStreamFrom)
    end

    it "includes TurboFrameTag helper" do
      expect(described_class.ancestors).to include(Phlex::Rails::Helpers::TurboFrameTag)
    end

    it "includes FormWith helper" do
      expect(described_class.ancestors).to include(Phlex::Rails::Helpers::FormWith)
    end

    it "includes ButtonTo helper" do
      expect(described_class.ancestors).to include(Phlex::Rails::Helpers::ButtonTo)
    end

    it "includes ActionView::RecordIdentifier" do
      expect(described_class.ancestors).to include(ActionView::RecordIdentifier)
    end
  end

  # =========================================================================
  # Delegated helpers
  # =========================================================================
  describe "delegated helpers" do
    it "responds to time_ago_in_words" do
      component = Class.new(described_class) do
        def view_template; end
      end.new

      expect(component).to respond_to(:time_ago_in_words)
    end

    it "responds to number_to_human_size" do
      component = Class.new(described_class) do
        def view_template; end
      end.new

      expect(component).to respond_to(:number_to_human_size)
    end
  end
end
