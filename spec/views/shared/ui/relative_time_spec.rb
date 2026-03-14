# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::RelativeTime do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  describe "with a datetime" do
    let(:datetime) { Time.zone.parse("2026-03-14 04:00:00 UTC") }
    let(:html) { render_component(datetime: datetime) }

    it "renders a <time> tag" do
      expect(html).to include("<time")
      expect(html).to include("</time>")
    end

    it "includes the ISO 8601 datetime attribute" do
      expect(html).to include("datetime=\"#{datetime.iso8601}\"")
    end

    it "includes the full timestamp in the title attribute" do
      expect(html).to include("title=\"14.03.2026 04:00:00 UTC\"")
    end

    it "displays relative time with 'ago' suffix" do
      expect(html).to match(/ago/)
    end
  end

  describe "with a nil datetime" do
    let(:html) { render_component(datetime: nil) }

    it "renders a dash" do
      expect(html).to include("—")
    end

    it "does not render a time tag" do
      expect(html).not_to include("<time")
    end
  end

  describe "with custom CSS class" do
    let(:datetime) { 5.minutes.ago }
    let(:html) { render_component(datetime: datetime, css_class: "text-red-500") }

    it "applies the custom class" do
      expect(html).to include("text-red-500")
    end
  end
end
