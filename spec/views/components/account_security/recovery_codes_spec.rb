# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [S6.21] Одноразовий reveal recovery-набору. Фікстура — plain Array<String>
# (компонент читає рівно це; жодних дериваційних полів — OpenStruct не потрібен).
# Одноразовість показу — контракт КОНТРОЛЕРА (session-маркер), її тримає
# request-спека mfa_flow_spec; тут — розмітка, локаль і токен-дисципліна.
RSpec.describe AccountSecurity::RecoveryCodes, type: :view do
  let(:codes) { %w[a1b2c3d4 e5f6a7b8 c9d0e1f2] }
  let(:html) { render_component(codes: codes) }

  describe "rendering" do
    it "renders every code from the set" do
      # Ліхтар на популяцію: пін «кожен код у тілі» вакуумний на порожньому наборі.
      expect(codes.size).to be > 1
      codes.each { |code| expect(html).to include(code) }
    end

    it "renders the codes as list items in mono type" do
      expect(html.scan("<li").size).to eq(codes.size)
      expect(html).to include("font-mono")
    end

    it "shows the one-time warning in an alert region" do
      expect(html).to include('role="alert"')
      expect(html).to include("This is the only time these codes are shown.")
    end

    it "links back to account security with an exact href" do
      expect(html).to include(%(href="/account_security"))
    end
  end

  describe "i18n" do
    # Свідок механізму живе в НЕ-базовій локалі: en-текст і сирий ключ надто
    # легко сплутати, а негативна половина ловить регресію на fail-open.
    it "resolves the warning through the locale file" do
      uk_html = I18n.with_locale(:uk) { render_component(codes: codes) }
      expect(uk_html).to include("Ці коди показуються лише один раз.")
      expect(uk_html).not_to include("This is the only time")
    end
  end

  describe "edge cases" do
    it "renders the chrome even for an empty set (malformed stored JSON)" do
      empty_html = render_component(codes: [])
      expect(empty_html).to include('role="alert"')
      expect(empty_html.scan("<li").size).to eq(0)
    end
  end

  describe "design system compliance" do
    it "uses gaia design tokens, not the raw palette of unmigrated neighbours" do
      expect(html).to include("text-gaia-text-strong")
      expect(html).to include("bg-gaia-surface")
      expect(html).not_to include("text-emerald-500")
      expect(html).not_to include("bg-black")
    end

    it "keeps the visible focus ring on the only interactive element" do
      expect(html).to include("focus-visible:ring-gaia-primary-strong")
    end
  end
end
