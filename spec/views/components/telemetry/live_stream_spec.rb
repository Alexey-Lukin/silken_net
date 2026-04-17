# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::LiveStream do
  describe "rendering" do
    let(:html) { render_component }

    it "renders with fade-in animation" do
      expect(html).to include("animate-in")
    end

    it "displays the Neural Link Output heading" do
      expect(html).to include("Neural Link Output")
    end

    it "displays the Global Telemetry Stream title" do
      expect(html).to include("Global Telemetry Stream")
    end

    it "renders the carrier status indicator" do
      expect(html).to include("Carrier: Direct-to-Cell")
    end

    it "renders the matrix-rain canvas with stimulus controller" do
      expect(html).to include("matrix-rain")
    end

    it "renders the telemetry_feed tbody" do
      expect(html).to include("telemetry_feed")
    end

    it "renders the placeholder row" do
      expect(html).to include("feed_placeholder")
    end

    it "shows awaiting uplink message" do
      expect(html).to include("Awaiting Starlink Uplink")
    end

    it "mentions CoAP:5683 in placeholder" do
      expect(html).to include("CoAP:5683")
    end
  end

  describe "table structure" do
    let(:html) { render_component }

    it "renders table with role=table for accessibility" do
      expect(html).to include('role="table"')
    end

    it "renders Timestamp column header" do
      expect(html).to include("Timestamp")
    end

    it "renders Queen / Gateway column header" do
      expect(html).to include("Queen / Gateway")
    end

    it "renders Raw CoAP Payload column header" do
      expect(html).to include("Raw CoAP Payload")
    end

    it "renders Status column header" do
      expect(html).to include("Status")
    end
  end

  describe "visual effects" do
    let(:html) { render_component }

    it "renders with GPU compositing hints on canvas" do
      expect(html).to include("transform-gpu")
      expect(html).to include("will-change-transform")
    end

    it "renders the spinner animation in placeholder" do
      expect(html).to include("animate-spin")
    end

    it "renders the pulsing live indicator" do
      expect(html).to include("animate-ping")
    end

    it "renders the broadcast icon" do
      expect(html).to include("ph-broadcast")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component }

    it "uses text-tiny for table body text" do
      expect(html).to include("text-tiny")
    end

    it "uses text-mini for labels" do
      expect(html).to include("text-mini")
    end

    it "uses tracking-widest for uppercase headings" do
      expect(html).to include("tracking-widest")
    end

    it "uses backdrop-blur for sticky header" do
      expect(html).to include("backdrop-blur-md")
    end
  end
end
