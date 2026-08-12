# SPDX-License-Identifier: AGPL-3.0-or-later
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

    it "includes the display typography tokens" do
      expect(described_class::CUSTOM_TEXT_SCALE).to include("display-sm", "display-md", "display-lg")
    end

    it "has exactly 7 custom text scale tokens (4 terminal + 3 display)" do
      expect(described_class::CUSTOM_TEXT_SCALE.size).to eq(7)
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
  # #format_object — рендеровність типу (04_04 §2, ARCH.89)
  #
  # Phlex формалізує в текст ЛИШЕ Float та Integer; на все інше його
  # `format_object` віддає nil, і вузол виходить ПОРОЖНІМ без помилки.
  # Три половини контракту, і кожна має власну мутацію:
  #   · Numeric ДРУКУЄТЬСЯ       — зняття `when Numeric` червонить (1)
  #   · Enumerable МОВЧИТЬ       — зняття `when Enumerable` червонить (2)
  #   · решта типів ГУЧНА        — зняття `unrenderable!` червонить (3)
  # =========================================================================
  describe "#format_object" do
    let(:bare) do
      Class.new(described_class) do
        def initialize(value) = @value = value
        def view_template = div { @value }
      end
    end

    def render_bare(value) = bare.new(value).call[%r{<div>(.*)</div>}m, 1]

    # (1) Друкується — саме той рід, який Phlex не перелічив.
    it "renders BigDecimal, the type every decimal column returns" do
      expect(render_bare(BigDecimal("12.5"))).to eq("12.5")
    end

    it "renders BigDecimal without trailing schema zeros" do
      # numeric(24,6) віддає 13013.000000 — на екрані має бути число, не «13013.000000».
      expect(render_bare(BigDecimal("13013.000000"))).to eq("13013.0")
    end

    it "renders Rational, the other Numeric Phlex omits" do
      expect(render_bare(Rational(1, 3))).to eq("1/3")
    end

    # Не-регресія: типи, які Phlex умів друкувати сам, лишились незмінними.
    it "leaves the natively formatted types untouched" do
      expect(render_bare(12.5)).to eq("12.5")
      expect(render_bare(12)).to eq("12")
      expect(render_bare("ok")).to eq("ok")
      expect(render_bare(:active)).to eq("active")
    end

    it "keeps nil silent — an absent value is not a defect" do
      expect(render_bare(nil)).to eq("")
    end

    # (2) Межа: колекція — це штатний залишок ітерації (`div { rows.each … }`),
    # а не значення. Без цієї гілки гучними стають 105 законних прикладів.
    it "stays silent on a collection — that is an iteration remainder, not a value" do
      expect { render_bare([]) }.not_to raise_error
      expect(render_bare([ 1, 2 ])).to eq("")
      expect(render_bare({ a: 1 })).to eq("")
    end

    # (3) Гучність: типи, що виглядають як значення й зникають безслідно.
    it "raises on a date or time — silent loss has no symptom of its own" do
      expect { render_bare(Date.new(2026, 8, 12)) }.to raise_error(Phlex::ArgumentError, /Date/)
      expect { render_bare(Time.current) }.to raise_error(Phlex::ArgumentError, /Time/)
    end

    it "raises on a boolean" do
      expect { render_bare(true) }.to raise_error(Phlex::ArgumentError, /TrueClass/)
    end

    it "names the remedy in the message, not just the offence" do
      expect { render_bare(Date.current) }
        .to raise_error(Phlex::ArgumentError, /to_fs|l\(value/)
    end

    # Прод не падає через формат — там тиша лишається тишею (fail-soft).
    it "stays silent in production instead of raising" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect { render_bare(Date.current) }.not_to raise_error
      expect(render_bare(Date.current)).to eq("")
    end

    # Другий вхід Phlex: `plain()` іде через __text__, не __implicit_output__.
    it "covers plain() as well, which is a different Phlex entry point" do
      via_plain = Class.new(described_class) do
        def initialize(value) = @value = value
        def view_template = div { plain(@value) }
      end
      expect(via_plain.new(BigDecimal("12.5")).call).to include("<div>12.5</div>")
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
