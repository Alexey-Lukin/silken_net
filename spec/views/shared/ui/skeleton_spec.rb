# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::Skeleton do
  def bones(html) = html.scan("animate-pulse").length

  describe "коробка — не його" do
    # 🔴 Доти тут стояв пін «wraps in a container with design system border and
    # surface background» — тобто спека ЦЕМЕНТУВАЛА власну картку скелетона, яка й
    # не збігалась ні з одним вмістом (Δh до +171, `spec/features/skeleton_box_spec.rb`).
    # Носія перенесено на протилежне: хром дає власник через свій `PANEL`.
    it "renders no border, surface or padding of its own" do
      container = render_component(lines: 3)[/<div[^>]*role="status"[^>]*>/]

      expect(container).not_to match(/\b(border|bg-|p-\d|px-|py-|shadow)/)
    end

    it "accepts extra classes from the caller" do
      expect(render_component(class: "mt-8")).to include("mt-8")
    end
  end

  describe "кістка" do
    it "is capped at the container width, so a fixed-width bone never overflows a narrow column" do
      expect(render_component(variant: :balance).scan(/class="([^"]*animate-pulse[^"]*)"/).flatten)
        .to all(include("max-w-full"))
    end

    it "shares one vocabulary with the broadcast stubs that cannot render the component" do
      expect(render_component).to include(described_class::BONE)
    end
  end

  describe "розмір оголошує виклик" do
    it "renders the requested number of lines" do
      expect(bones(render_component(lines: 5))).to eq(5)
    end

    it "renders the balance shape: label, hero figure, value row, footnote" do
      html = render_component(variant: :balance)

      expect(bones(html)).to eq(4)
      expect(html).to include("h-18")
    end
  end

  describe "доступність" do
    it "announces loading via role=status" do
      html = render_component

      expect(html).to include('role="status"')
      expect(html).to include("Loading")
    end

    # Клас 2 (`04_04 §8.1а`): payload броадкасту мусить бути однаковим у будь-якій
    # локалі — тож декоративний режим не сміє кликати `t()` узагалі.
    it "renders byte-identically in every locale when decorative" do
      renders = I18n.available_locales.map do |locale|
        I18n.with_locale(locale) { described_class.new(variant: :balance, decorative: true).call }
      end

      expect(renders.uniq.size).to eq(1)
      expect(renders.first).to include('aria-hidden="true"')
      expect(renders.first).not_to include("role=")
    end
  end
end
