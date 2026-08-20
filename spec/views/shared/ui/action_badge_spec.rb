# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.1] Дім міток дії аудиту — `ActionBadge.label` (рендерер і є дім мапи,
# прецедент breadcrumb-сегментів). Свідки живуть у НЕ-базовій локалі: en-мітки
# літералів побайтово дорівнюють humanize, тож англійський пін механізму не
# бачить за побудовою.
RSpec.describe Views::Shared::UI::ActionBadge do
  describe ".label" do
    it "resolves a literal action from the locale home (uk)" do
      I18n.with_locale(:uk) do
        expect(described_class.label("user_role_changed")).to eq("Роль користувача змінено")
      end
    end

    it "falls open to humanize on an unknown action" do
      expect(described_class.label("future_unknown_action")).to eq("Future unknown action")
    end

    it "renders a naas transition through the shared status home (uk)" do
      I18n.with_locale(:uk) do
        expect(described_class.label("naas_contract_to_cancelled")).to eq("Контракт → скасовано")
      end
    end

    # 🔴 Дискримінатор вибору дому: стани НАКАЗІВ мають ВЛАСНІ мітки, і на
    # `confirmed` вони РОЗХОДЯТЬСЯ зі спільним bag'ом («завершено» ⊥
    # «підтверджено») — тож цей пін червоніє, якщо actuator-родину повести
    # через StatusBadge (частковий резолв, пастка I18N.1).
    it "renders an actuator transition through the COMMAND state home (uk)" do
      I18n.with_locale(:uk) do
        expect(described_class.label("actuator_to_confirmed")).to eq("Наказ → завершено")
      end
    end

    it "renders the blockchain to-form through the shared status home (uk)" do
      I18n.with_locale(:uk) do
        expect(described_class.label("blockchain_tx_to_failed")).to eq("Транзакція → збій")
      end
    end

    it "resolves the event form via metadata to-state (uk)" do
      I18n.with_locale(:uk) do
        expect(described_class.label("blockchain_tx_confirm", metadata: { "to" => "confirmed" }))
          .to eq("Транзакція → підтверджено")
      end
    end

    it "falls open to the raw event suffix when metadata is absent" do
      I18n.with_locale(:uk) do
        expect(described_class.label("blockchain_tx_confirm")).to eq("Транзакція → confirm")
      end
    end
  end

  describe "style" do
    def badge_html(action, metadata: nil)
      render_component(action: action, metadata: metadata)
    end

    it "colours a transition by its END state (failed → destructive)" do
      expect(badge_html("actuator_to_failed")).to include("bg-status-danger")
    end

    it "colours a fulfilling transition as creative" do
      expect(badge_html("naas_contract_to_fulfilled")).to include("bg-status-active")
    end

    it "colours an intermediate transition as mutative" do
      expect(badge_html("blockchain_tx_to_sent")).to include("bg-status-warning")
    end

    # Доти підрядкові CRUD-регекси клали slash-вердикти в neutral — найгучніша
    # дія журналу була найтихішим бейджем.
    it "colours a slash verdict as destructive" do
      expect(badge_html("slash_verdict_burn")).to include("bg-status-danger")
    end

    it "falls open to neutral on an unknown action" do
      expect(badge_html("future_unknown_action")).to include("bg-status-neutral")
    end
  end

  # Хром бейджа — піни, успадковані з попередньої редакції спеки (та стояла
  # цілком на вигаданих CRUD-діях і переписана, але ЦІ осі — не про дії).
  describe "badge chrome" do
    let(:html) { render_component(action: "user_role_changed") }

    it "includes role=status" do
      expect(html).to include('role="status"')
    end

    it "uses text-mini instead of arbitrary text-[9px]" do
      expect(html).to include("text-mini")
      expect(html).not_to include("text-[")
    end

    it "includes tracking-widest for uppercase microcopy" do
      expect(html).to include("tracking-widest")
    end

    it "accepts additional classes through tokens-merge" do
      expect(render_component(action: "user_role_changed", class: "ml-2")).to include("ml-2")
    end
  end

  describe "accessible name" do
    # aria-label знято свідомо: видимий текст САМ є локалізованою міткою, а
    # aria-label над локалізованим видимим текстом перекриває accessible name.
    it "carries no aria-label — the visible label IS the accessible name" do
      expect(render_component(action: "user_role_changed")).not_to include("aria-label")
    end
  end
end
