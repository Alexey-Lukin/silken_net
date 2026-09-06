# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Спадкоємець спеки знятого `Telemetry::LogEntry` — ⛔ ЗНЯТОЇ РАЗОМ ІЗ КОМПОНЕНТОМ
# [UI.16, 2026-09-06], тож літерального шляху сюди не пишемо: канон-гейт справедливо
# читає цитований шлях спеки як обіцянку живого сторожа. Історія — в `git log`.
#
# ⚠️ Успадкована частина — САМЕ locale-інваріантність: вона є носієм присуду `04_04 §8.1а` (клас 1 обовʼязковий для
# firehose), і без неї фікс одиниці мовчки відкрив би шлях назад до `t()` у payload'і.
RSpec.describe Telemetry::BatchSummary do
  around { |ex| I18n.with_locale(:en) { ex.run } }

  def relay(uid: "SNET-Q-AABB0011", ip_address: "192.168.1.100")
    Gateway.new(uid: uid, ip_address: ip_address)
  end

  # Дробова частина ненульова СВІДОМО: комірка друкує `%L`, і на рівній секунді
  # пін не відрізнив би формат із мілісекундами від формату без них. Мікросекунди
  # йдуть ОКРЕМИМ аргументом, не дробовою секундою (Float-форма зрізає до 122).
  def stamp = Time.zone.local(2024, 6, 15, 10, 30, 45, 123_000)

  def summary(records: 12, committed: 12, statuses: { homeostasis: 12 }, panics: 0)
    TelemetryUnpackerService::Summary.new(
      records: records, committed: committed, statuses: statuses, panics: panics
    )
  end

  describe "locale-інваріантність payload'а [класс 1, 04_04 §8.1а]" do
    it "рендериться ПОБАЙТОВО однаково в кожній налаштованій локалі" do
      renders = I18n.available_locales.to_h do |locale|
        [ locale, I18n.with_locale(locale) { render_component(gateway: relay, summary: summary, timestamp: stamp) } ]
      end

      # Ліхтар: без нього приклад був би зелений і на однині available_locales.
      expect(renders.size).to be >= 2

      baseline = renders.values.first
      renders.each do |locale, html|
        expect(html).to eq(baseline), "рендер у #{locale} розійшовся з базовим — у payload'і локаль-залежна проза"
      end
    end

    # ⊥ Дзеркало: доводить, що механізм порівняння ЖИВИЙ. Без нього перша асершн
    # проходила б і на компоненті, який просто нічого не рендерить.
    it "містить самі токени, а не порожнечу" do
      html = I18n.with_locale(I18n.available_locales.last) do
        render_component(gateway: nil, summary: summary, timestamp: stamp)
      end

      expect(html).to include(described_class::UNKNOWN_RELAY, described_class::UNKNOWN_IP)
      # ⚠️ Стан пінимо МАРКЕРОМ, не текстом: слово дає `::before` з опублікованої
      # сторінкою властивості, тож `innerText`-пін тут був би вакуумним за побудовою.
      expect(html).to include('data-batch-state="ok"')
    end
  end

  describe "зміст рядка — ЗВЕДЕННЯ, а не сирий конверт [UI.16]" do
    it "показує кількість записів і не показує жодного hex-дампу" do
      html = render_component(gateway: relay, summary: summary(records: 12), timestamp: stamp)

      expect(html).to include(">12<")
      # Найдешевший пін на предмет фіксу: сирий вміст конверта сюди більше не доїжджає
      # за побудовою — компонент його не приймає в конструкторі взагалі.
      expect(described_class.instance_method(:initialize).parameters.map(&:last))
        .to contain_exactly(:gateway, :summary, :timestamp)
    end

    it "показує ВТРАЧЕНІ записи окремим числом — різниця «прийшло ⊥ прийнято» не має бути тихою" do
      html = render_component(gateway: relay, summary: summary(records: 12, committed: 9), timestamp: stamp)

      expect(html).to include("−3")
      expect(html).to include('data-batch-state="partial"')
    end

    it "виводить лічильники НЕ-гомеостазних статусів поіменно" do
      html = render_component(
        gateway: relay,
        summary: summary(records: 5, committed: 5, statuses: { homeostasis: 3, stress: 1, anomaly: 1 }),
        timestamp: stamp
      )

      expect(html).to include('data-bio-label="stress"', 'data-bio-label="anomaly"')
      expect(html).to include("·1")
      expect(html).to include('data-batch-state="attention"')
      # ⊥ Гомеостаз СВІДОМО не має власного числа: він = `records − решта`, і другий
      # вивід тієї самої величини рано чи пізно розійшовся б із першим.
      expect(html).not_to include('data-bio-label="homeostasis"')
    end

    it "паніка перебиває решту станів" do
      html = render_component(
        gateway: relay,
        summary: summary(records: 4, committed: 3, statuses: { homeostasis: 3 }, panics: 1),
        timestamp: stamp
      )

      expect(html).to include('data-batch-state="panic"')
      expect(html).not_to include('data-batch-state="partial"')
    end
  end
end
