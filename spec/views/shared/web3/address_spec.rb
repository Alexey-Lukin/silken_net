# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::Web3::Address do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with a valid Ethereum address" do
    let(:address) { "0x1234567890abcdef1234567890abcdef12345678" }
    let(:html) { render_component(address: address) }

    it "truncates to 0x1234…5678 format" do
      expect(html).to include("0x1234…5678")
    end

    it "includes the full address in the title attribute" do
      expect(html).to include("title=\"#{address}\"")
    end

    it "renders a clipboard copy button with aria-label" do
      expect(html).to include('data-action="clipboard#copy"')
      expect(html).to include("aria-label")
      expect(html).to include("Copy address")
    end

    it "sets the clipboard controller data attribute" do
      expect(html).to include('data-controller="clipboard"')
      expect(html).to include("data-clipboard-content-value=\"#{address}\"")
    end

    it "renders an SVG copy icon with aria-hidden" do
      expect(html).to include("<svg")
      expect(html).to include("aria-hidden")
    end

    it "includes focus ring styles on the copy button" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "with a short address" do
    let(:address) { "0x1234abcd" }
    let(:html) { render_component(address: address) }

    it "displays the full address without truncation" do
      expect(html).to include("0x1234abcd")
      expect(html).not_to include("…")
    end
  end

  describe "with a nil address" do
    let(:html) { render_component(address: nil) }

    it "displays the default fallback text" do
      expect(html).to include("NOT_PROVISIONED")
    end

    it "does not render a clipboard controller" do
      expect(html).not_to include('data-controller="clipboard"')
    end
  end

  describe "with a custom fallback" do
    let(:html) { render_component(address: nil, fallback: "N/A") }

    it "displays the custom fallback" do
      expect(html).to include("N/A")
    end
  end
end
