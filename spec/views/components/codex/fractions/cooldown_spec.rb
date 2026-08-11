# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::Cooldown do
  # `codex_fractions` тримає ОДНУ колонку часу — `last_changed_at`; і
  # `cooldown_until`, і `cooldown_active?`, і `seconds_until_unlocked`
  # виводяться з неї. Тому фікстура годує джерело: подані трьома
  # незалежними полями, вони складаються в стани, яких реальний запис
  # не має (напр. «вікно активне» разом із «нуль секунд до кінця»).
  #
  # Час заморожено, бо похідне число рахується в МОМЕНТ рендеру: без
  # заморозки залишок, заданий рівно добою, доїжджає до компонента вже
  # меншим, і межа доби перекочується в попередній розряд.
  around { |ex| freeze_time { ex.run } }

  def fraction_with(remaining)
    Codex::Fraction.new(last_changed_at: Time.current - Codex::Fraction::COOLDOWN + remaining)
  end

  describe "when cooldown is NOT active (open state)" do
    it "renders the 'Open' pill with success tokens" do
      html = described_class.new(fraction: fraction_with(-1.hour)).call
      expect(html).to include("Open")
      expect(html).to include("bg-status-success")
      expect(html).to include("text-status-success-text")
    end
  end

  describe "when cooldown IS active (locked state)" do
    it "renders the 'Locked' label with warning tokens and formatted time" do
      html = described_class.new(fraction: fraction_with(3.days + 5.hours)).call
      expect(html).to include("Locked")
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
      expect(html).to include("3d5h")
    end

    it "formats hours-and-minutes when remaining time is less than a day" do
      html = described_class.new(fraction: fraction_with(2.hours + 15.minutes)).call
      expect(html).to include("2h15m")
    end

    it "includes the ISO8601 cooldown_until in the title attribute" do
      fraction = fraction_with(3.days + 5.hours)
      html = described_class.new(fraction: fraction).call
      expect(html).to include(fraction.cooldown_until.iso8601)
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
      html = described_class.new(fraction: fraction_with(1.day)).call
      expect(html).to include("1d0h")
    end
  end

  describe "guard against the intra-render race" do
    # `cooldown_active?` і `seconds_until_unlocked` кличуть `Time.current`
    # НЕЗАЛЕЖНО, тож момент розблокування може впасти між ними: предикат
    # уже сказав «активне», а залишок порахувався нулем. Реальним записом
    # цей стан не будується (умови взаємно виключні), тож єдиний чесний
    # вхід — стаб самого ридера.
    it "shows 0s when the window elapses mid-render" do
      fraction = fraction_with(1.minute)
      fraction.define_singleton_method(:seconds_until_unlocked) { |*| 0 }
      html = described_class.new(fraction: fraction).call
      expect(html).to include("0s")
    end
  end

  describe "design system compliance" do
    it "uses status-* tokens only, never raw Tailwind colors, in either state" do
      open_html = described_class.new(fraction: fraction_with(-1.hour)).call
      locked_html = described_class.new(fraction: fraction_with(1.hour)).call
      expect(open_html).not_to include("bg-green")
      expect(locked_html).not_to include("bg-yellow")
    end
  end

  describe "accessibility" do
    it "does not render a title tooltip on the open pill (nothing to describe)" do
      html = described_class.new(fraction: fraction_with(-1.hour)).call
      expect(html).not_to include("title=")
    end
  end
end
