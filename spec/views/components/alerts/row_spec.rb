# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [TEST.12] Конвертовано з `EwsAlert.allocate` + define_singleton_method на
# РЕАЛЬНИЙ незбережений запис. Найгостріше, що ховала підробка: `#message` — це
# НЕ колонка, а рендер (`I18n.t("alerts.messages.#{message_key}", **params)`,
# fail-open на `humanize`). Мок віддавав готовий рядок, тож увесь локалізаційний
# тракт компонента не перевірявся ЖОДНОГО разу — а саме на ньому стоїть правило
# «параметр несе ВИМІР, ніколи фрагмент фрази» (`backend` #14).
#
# `allocate` заразом підробляв і enum-предикати (`status_resolved?`), тобто
# найтонше місце: рядок `"resolved"` проходив там, де модель приймає лише
# значення власного enum.
RSpec.describe Alerts::Row do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # Реальні типи, нуль БД: `EwsAlert.new` дає справжні enum-предикати й справжній
  # `#message`, а `dom_id` бере `to_key` з самої моделі.
  def build_alert(id: 7, severity: :medium, alert_type: :fire_detected, status: :active,
                  cluster_name: "Carpathian-7", tree_did: "SNET-DEADBEEF",
                  message_key: "fire_detected", message_params: { temperature_c: 61, fire_limit: 55 })
    EwsAlert.new(
      id: id, severity: severity, alert_type: alert_type, status: status,
      message_key: message_key, message_params: message_params,
      created_at: Time.current,
      cluster: Cluster.new(name: cluster_name),
      tree: tree_did && Tree.new(did: tree_did)
    )
  end

  describe "DOM ID" do
    it "uses dom_id format for the row id" do
      html = render_component(alert: build_alert(id: 42))
      expect(html).to include('id="ews_alert_42"')
    end
  end

  describe "severity badge" do
    # [UI.3] Пін на ПУЛЬС знято 2026-08-19 — не як послаблення, а тому що він
    # цементував дефект: рух на вузлі з текстом робив підпис нечитабельним, а
    # розрізняв `critical` уже власний фон. Носій ПЕРЕНЕСЕНО на статичну ознаку.
    it "renders critical severity with its own danger surface, statically" do
      html = render_component(alert: build_alert(severity: :critical))
      expect(html).to include("bg-status-danger")
      expect(html).not_to include("animate-pulse")
    end

    it "renders medium severity with warning styles" do
      html = render_component(alert: build_alert(severity: :medium))
      expect(html).to include("bg-status-warning")
    end

    it "renders low severity with emerald styles" do
      html = render_component(alert: build_alert(severity: :low))
      expect(html).to include("bg-status-info")
    end

    it "includes aria-label for accessibility" do
      html = render_component(alert: build_alert(severity: :critical))
      expect(html).to include("aria-label")
      expect(html).to include("Severity")
    end
  end

  describe "alert content" do
    let(:html) { render_component(alert: build_alert) }

    # [I18N.1] Мітка типу тепер із `alerts.types.*` через TextFormatter —
    # раніше тут був locale-сліпий `.humanize` ("Fire detected").
    it "displays the localised alert type label" do
      expect(html).to include("Fire Detected")
    end

    it "displays cluster and tree source" do
      expect(html).to include("Carpathian-7")
      expect(html).to include("SNET-DEADBEEF")
    end

    # `#message` — РЕНДЕР, не колонка: текст збирається з `message_key` +
    # `message_params` через I18n. Мок віддавав готовий рядок, тож цей тракт не
    # перевірявся ніколи — а на ньому стоїть правило «параметр несе ВИМІР».
    it "renders the message from its key and measured params" do
      expect(html).to include("Temperature 61")
      expect(html).to include("55")
    end
  end

  describe "resolved state" do
    let(:html) { render_component(alert: build_alert(status: :resolved)) }

    it "shows resolved indicator instead of action button" do
      expect(html).to include("Resolved")
    end

    # 🔴 [UI.3] Тут стояло `include("opacity-40")` — тобто сюїта ВИМАГАЛА дефекту:
    # прозорість на `<tr>` множить контраст кожного нащадка (16.10:1 → **2.46:1**
    # у світлій темі, 19.05:1 → 3.58:1 у темній, поріг 4.5:1). Пін не був
    # надлишковим — він був носієм хвороби, і зняти її, не переписавши його,
    # неможливо.
    #
    # Ціль тепер — те, що справді відрізняє закритий рядок: власний фон замість
    # hover-фону сусіда. Пара «має sunken ⊥ не має hover:sunken» несуча, бо
    # `hover:bg-gaia-surface-sunken` містить той самий підрядок, тож пін лише на
    # `bg-gaia-surface-sunken` був би зелений і на АКТИВНОМУ рядку.
    it "позначає закритий рядок власним фоном, а не прозорістю" do
      expect(html).to include("bg-gaia-surface-sunken")
      expect(html).not_to include("hover:bg-gaia-surface-sunken")
      expect(html).not_to include("opacity-")
    end
  end

  describe "active state" do
    # [UI.6] Гасити тривогу може лише forester+, тож приклади, що пінять кнопку,
    # ведуть саме такого актора. Видимість для нижчої ролі — окрема група нижче.
    let(:html) { render_component(alert: build_alert(status: :active), current_user: build_stubbed(:user, :forester)) }

    it "renders the resolve button" do
      expect(html).to include("Acknowledge")
    end

    it "includes hover transition styles" do
      expect(html).to include("hover:bg-gaia-surface-sunken")
    end
  end

  # [UI.6] Список тривог відкритий УСІМ ролям (гард стоїть лише на `#resolve`), тож
  # investor бачив бойову кнопку, тиснув її — і turbo-submission мовчки вмирала в
  # JSON-403. Це найбуденніша точка класу: кнопка на кожному нерозвʼязаному рядку
  # головного операційного розділу.
  describe "роле-фільтр дії [UI.6]" do
    def render_for(actor)
      render_component(alert: build_alert(status: :active), current_user: actor)
    end

    it "ховає Acknowledge від investor" do
      html = render_for(build_stubbed(:user, :investor))

      expect(html).to include("Carpathian-7")   # рядок сам відрендерився
      expect(html).not_to include("Acknowledge")
    end

    it "без актора звужується fail-CLOSED" do
      html = render_for(nil)

      expect(html).to include("Carpathian-7")
      expect(html).not_to include("Acknowledge")
    end
  end

  # ⚠️ [TEST.12] Вхід НЕДОСЯЖНИЙ, і це оголошено, а не замовчано: `enum :severity`
  # має рівно три члени (`low`/`medium`/`critical`), тож `"unknown"` реальний
  # `EwsAlert` мати не може — `new` на ньому кидає `ArgumentError`. Отже `else`-гілка
  # бейджа є ГАРДОМ (ловить `nil`/сире значення), а не станом, який побачить
  # користувач; параметр `severity:` тут працює як стаб РИДЕРА, не як легальний стан.
  # ⊕ Пін лишається розрізнимим (на відміну від `04_06 §A.4` BP 20): `bg-status-neutral`
  # не належить жодному з трьох живих severity, тож він таки говорить про фолбек.
  describe "severity badge else branch" do
    # 🔴 Доти сюди подавали `severity: "unknown"` — значення ПОЗА enum, на якому
    # реальна модель кидає ArgumentError, тобто гілку перевіряли входом, неможливим
    # у проді. Досяжна вона рівно одним чесним входом — `nil` (незбережений запис
    # до валідації), і саме він тепер тут.
    it "renders the neutral fallback for an alert whose severity is not set yet" do
      html = render_component(alert: build_alert(severity: nil))
      expect(html).to include("bg-status-neutral")
    end
  end
end
