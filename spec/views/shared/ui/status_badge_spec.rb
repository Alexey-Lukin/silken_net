# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::StatusBadge do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  describe "AASM state color mapping" do
    it "maps pending to warning semantic token" do
      html = render_component(status: "pending")
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "maps confirmed to success semantic token" do
      html = render_component(status: "confirmed")
      expect(html).to include("bg-status-success")
    end

    it "maps failed to danger semantic token" do
      html = render_component(status: "failed")
      expect(html).to include("bg-status-danger")
    end

    it "maps processing to warning semantic token with animation" do
      html = render_component(status: "processing")
      expect(html).to include("bg-status-warning")
      expect(html).to include("animate-pulse")
    end

    # 🔴 Несучий пін цієї осі: `active` означає ЗДОРОВʼЯ — так його вживають усі
    # п'ять живих власників (Tree · Gateway · NaasContract · Actuator ·
    # ParametricInsurance). Доти запис належав `EwsAlert`, де відкрита тривога =
    # погано, і був `danger`; дротування бейджа пофарбувало б здорове дерево,
    # живий шлюз і чинний контракт у червоне. Носія тієї колізії немає —
    # `EwsAlert#status` як показане СЛОВО зник разом з `Alerts::Badge`.
    it "maps active to the success token, never danger" do
      html = render_component(status: "active")

      expect(html).to include("bg-status-success")
      expect(html).not_to include("bg-status-danger")
    end
  end

  # 🔴 [UI.3] Ця пара стереже те, чого класовий гейт бачити не може. Гейт
  # (`spec/quality/opacity_contrast_multiplier_spec.rb`) забороняє прозорість на
  # текстовому вузлі — але він однаково зелений і тоді, коли `opacity-50` просто
  # ВИДАЛЕНО, а замінити її нічим. А видалити було не можна: прозорість тут була
  # ЄДИНИМ, що відрізняло «cancelled» від «draft» — обидва носять той самий
  # `bg-status-neutral text-status-neutral-text`. Тобто наївний фікс контрасту
  # злив би два різні стани в один вигляд, і жоден гейт не сказав би ні слова.
  describe "завершені стани — дискримінатор без кольору" do
    it "розрізняє cancelled і draft, які носять ОДИН колірний токен" do
      cancelled = render_component(status: "cancelled")
      draft = render_component(status: "draft")

      expect(cancelled).to include("line-through")
      expect(draft).not_to include("line-through")
      # Обидва мусять лишатись нейтральними — інакше «розрізнення» приїхало
      # кольором, тобто ми полагодили контраст, зламавши семантику палітри.
      expect(cancelled).to include("bg-status-neutral")
      expect(draft).to include("bg-status-neutral")
    end

    it "не глушить завершені стани прозорістю — вона множила контраст до 2.25:1" do
      %w[cancelled removed].each do |state|
        expect(render_component(status: state)).not_to include("opacity-")
      end
    end
  end

  describe "with an unknown status" do
    let(:html) { render_component(status: "unknown_state") }

    it "falls back to default styling" do
      expect(html).to include("bg-status-neutral")
      expect(html).to include("text-status-neutral-text")
    end
  end

  describe "status text rendering" do
    it "displays the status text" do
      html = render_component(status: "confirmed")
      expect(html).to include("confirmed")
    end

    # 🔴 Приклад вище НЕ здатен довести локалізацію: у базовій локалі мітка
    # дорівнює власному токену (`confirmed: confirmed`), тож він зелений і тоді,
    # коли компонент друкує сирий enum повз YAML. Доказ резолвінгу можливий лише
    # в НЕ-базовій локалі, де слово відрізняється від ключа.
    it "resolves the label through YAML, not by printing the raw enum" do
      html = I18n.with_locale(:uk) { render_component(status: "confirmed") }

      expect(html).to include("підтверджено")
      expect(html).not_to include("confirmed")
    end

    it "accepts symbol statuses" do
      html = render_component(status: :pending)
      expect(html).to include("pending")
      expect(html).to include("bg-status-warning")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(status: "pending") }

    it "includes role=status" do
      expect(html).to include('role="status"')
    end

    it "includes aria-label with status text" do
      expect(html).to include("aria-label")
      expect(html).to include("Status: pending")
    end
  end

  describe "tailwind best practices" do
    let(:html) { render_component(status: "pending") }

    it "uses semantic text-tiny instead of arbitrary text-[10px]" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[")
    end

    it "uses tracking-widest for uppercase microcopy" do
      expect(html).to include("tracking-widest")
    end

    it "accepts class override via **attrs" do
      html = render_component(status: "pending", class: "mt-2")
      expect(html).to include("mt-2")
    end
  end
end
