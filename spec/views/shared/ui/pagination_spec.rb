# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::Pagination do
  let(:url_helper) { ->(page:) { "/items?page=#{page}" } }

  describe "with a middle page" do
    let(:pagy) { OpenStruct.new(page: 3, last: 10, prev: 2, next: 4) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "renders the nav element" do
      expect(html).to include("<nav")
    end

    it "displays current page and total" do
      expect(html).to include("Page 3 / 10")
    end

    it "renders a previous link" do
      expect(html).to include("← Previous")
      expect(html).to include("/items?page=2")
    end

    it "renders a next link" do
      expect(html).to include("Next →")
      expect(html).to include("/items?page=4")
    end
  end

  describe "with the first page" do
    let(:pagy) { OpenStruct.new(page: 1, last: 5, prev: nil, next: 2) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "does not render a previous link" do
      expect(html).not_to include("← Previous")
    end

    it "renders a next link" do
      expect(html).to include("Next →")
      expect(html).to include("/items?page=2")
    end

    it "displays page 1 of 5" do
      expect(html).to include("Page 1 / 5")
    end
  end

  describe "with the last page" do
    let(:pagy) { OpenStruct.new(page: 5, last: 5, prev: 4, next: nil) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "renders a previous link" do
      expect(html).to include("← Previous")
      expect(html).to include("/items?page=4")
    end

    it "does not render a next link" do
      expect(html).not_to include("Next →")
    end
  end

  describe "with a single page" do
    let(:pagy) { OpenStruct.new(page: 1, last: 1, prev: nil, next: nil) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "renders nothing when only one page exists" do
      expect(html).to be_empty
    end
  end

  describe "design system compliance" do
    let(:pagy) { OpenStruct.new(page: 2, last: 5, prev: 1, next: 3) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "uses text-gaia-text-muted for page info" do
      expect(html).to include("text-gaia-text-muted")
    end

    it "uses border-gaia-border for link styling" do
      expect(html).to include("border-gaia-border")
    end

    it "uses hover:border-gaia-primary for links" do
      expect(html).to include("hover:border-gaia-primary")
    end

    it "uses font-mono for terminal aesthetic" do
      expect(html).to include("font-mono")
    end

    it "uses text-mini for typography" do
      expect(html).to include("text-mini")
    end
  end

  describe "accessibility" do
    let(:pagy) { OpenStruct.new(page: 2, last: 5, prev: 1, next: 3) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "includes role=navigation on nav element" do
      expect(html).to include('role="navigation"')
    end

    it "includes aria-label for pagination" do
      expect(html).to include('aria-label="Pagination"')
    end

    it "includes aria-label for previous page link" do
      expect(html).to include("Go to previous page")
    end

    it "includes aria-label for next page link" do
      expect(html).to include("Go to next page")
    end

    it "includes aria-current for current page indicator" do
      expect(html).to include("aria-current")
    end
  end

  describe "with focus-visible support" do
    let(:pagy) { OpenStruct.new(page: 2, last: 5, prev: 1, next: 3) }
    let(:html) { render_component(pagy: pagy, url_helper: url_helper) }

    it "uses focus-visible ring for keyboard navigation" do
      expect(html).to include("focus-visible:ring-2")
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end

  describe "with invalid pagy object" do
    it "raises ArgumentError when pagy does not respond to :page" do
      expect { render_component(pagy: "invalid", url_helper: url_helper) }
        .to raise_error(ArgumentError, /pagy must respond to :page/)
    end
  end
end
