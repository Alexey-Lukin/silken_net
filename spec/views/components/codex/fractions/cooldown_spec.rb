# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::Cooldown do
  def mock_fraction(cooldown_active:, cooldown_until: nil, seconds_until_unlocked: 0)
    OpenStruct.new(
      cooldown_active?: cooldown_active,
      cooldown_until: cooldown_until,
      seconds_until_unlocked: seconds_until_unlocked
    )
  end

  describe "when cooldown is NOT active (open state)" do
    it "renders the 'Open' pill with success tokens" do
      html = described_class.new(fraction: mock_fraction(cooldown_active: false)).call
      expect(html).to include("Open")
      expect(html).to include("bg-status-success")
      expect(html).to include("text-status-success-text")
    end
  end

  describe "when cooldown IS active (locked state)" do
    let(:until_time) { Time.current + 3.days + 5.hours }

    it "renders the 'Locked' label with warning tokens and formatted time" do
      fraction = mock_fraction(
        cooldown_active: true,
        cooldown_until: until_time,
        seconds_until_unlocked: 3.days.to_i + 5.hours.to_i
      )
      html = described_class.new(fraction: fraction).call
      expect(html).to include("Locked")
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
      expect(html).to include("3d5h")
    end

    it "formats hours-and-minutes when remaining time is less than a day" do
      fraction = mock_fraction(
        cooldown_active: true,
        cooldown_until: Time.current + 2.hours + 15.minutes,
        seconds_until_unlocked: 2.hours.to_i + 15.minutes.to_i
      )
      html = described_class.new(fraction: fraction).call
      expect(html).to include("2h15m")
    end

    it "shows 0s when seconds_until_unlocked is zero or negative" do
      fraction = mock_fraction(
        cooldown_active: true,
        cooldown_until: Time.current,
        seconds_until_unlocked: 0
      )
      html = described_class.new(fraction: fraction).call
      expect(html).to include("0s")
    end

    it "includes the ISO8601 cooldown_until in the title attribute" do
      fraction = mock_fraction(
        cooldown_active: true,
        cooldown_until: until_time,
        seconds_until_unlocked: 100_000
      )
      html = described_class.new(fraction: fraction).call
      expect(html).to include(until_time.iso8601)
    end
  end

  describe "nil fraction" do
    it "renders 'Open' when fraction is nil (cooldown_active? returns falsy)" do
      html = described_class.new(fraction: nil).call
      expect(html).to include("Open")
    end
  end

  describe "boundary formatting" do
    it "formats exactly one day as '1d0h' (day-boundary rollover)" do
      fraction = mock_fraction(
        cooldown_active: true,
        cooldown_until: Time.current + 1.day,
        seconds_until_unlocked: 1.day.to_i
      )
      html = described_class.new(fraction: fraction).call
      expect(html).to include("1d0h")
    end
  end

  describe "design system compliance" do
    it "uses status-* tokens only, never raw Tailwind colors, in either state" do
      open_html = described_class.new(fraction: mock_fraction(cooldown_active: false)).call
      locked_html = described_class.new(
        fraction: mock_fraction(cooldown_active: true, cooldown_until: Time.current, seconds_until_unlocked: 100)
      ).call
      expect(open_html).not_to include("bg-green")
      expect(locked_html).not_to include("bg-yellow")
    end
  end

  describe "accessibility" do
    it "does not render a title tooltip on the open pill (nothing to describe)" do
      html = described_class.new(fraction: mock_fraction(cooldown_active: false)).call
      expect(html).not_to include("title=")
    end
  end
end
