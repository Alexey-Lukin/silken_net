# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::Web3::Address do
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

    # 🔴 Носій правила «JS не вигадує тексту для людини»: локаль знає ЛИШЕ
    # сервер, тож обидва результати їдуть у розмітці. Доти контролер писав
    # `innerHTML = "✓"` — символ, а не слово, тобто озвучення не було взагалі
    # (у кнопки є `aria-label`, і він перекриває вміст).
    it "віддає ОБИДВА тексти результату з сервера, у локалі глядача" do
      uk = I18n.with_locale(:uk) { render_component(address: address) }

      expect(uk).to include('data-clipboard-copied-text-value="Адресу скопійовано"')
      expect(uk).to include("data-clipboard-failed-text-value=")
      # Ліхтар: англійський текст у розмітці для uk-глядача = дефект.
      expect(uk).not_to include("Address copied")
    end

    it "має окремий live-регіон для результату, а не підміну вмісту кнопки" do
      expect(html).to include('role="status"')
      expect(html).to include('aria-live="polite"')
      expect(html).to include('data-clipboard-target="status"')
    end

    # ⊥ Успіх і відмова — РІЗНІ стани: доти `showFeedback` біг у catch-гілці
    # безумовно, тож кнопка показувала «✓» навіть коли копіювання не сталося.
    it "рендерить обидві іконки сервером, щоб контролер лише перемикав їх" do
      icons = html.scan(/<svg[^>]*data-clipboard-target="(icon|check)"[^>]*>/)
      expect(icons.flatten).to contain_exactly("icon", "check")

      # 🔴 Ціль саме та, що галочка стартує СХОВАНОЮ — без цього приклад був би
      # зелений і на компоненті, що показує обидві іконки одразу.
      # ⚠️ Читаємо КЛАС, а не тег: обидві іконки несуть `aria-hidden="true"`,
      # тож підрядковий матч на «hidden» істинний завжди (спіймано власним
      # прогоном — рівно клас «токен ≠ підрядок»).
      classes_of = lambda do |target|
        html[/<svg[^>]*data-clipboard-target="#{target}"[^>]*>/][/class="([^"]*)"/, 1].split
      end

      expect(classes_of.call("check")).to include("hidden")
      expect(classes_of.call("icon")).not_to include("hidden")
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
