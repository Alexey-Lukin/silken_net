# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::LogEntry do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # Єдиний виробник — `UnpackTelemetryWorker#broadcast_to_matrix`: він передає
  # сюди сам запис `Gateway`, `Time.current` і hex, ВЖЕ піднятий у верхній регістр
  # (`binary_data.unpack1("H*").upcase` — сам `unpack1` віддає нижній).
  def relay(uid: "SNET-Q-AABB0011", ip_address: "192.168.1.100")
    Gateway.new(uid: uid, ip_address: ip_address)
  end

  # Дробова частина ненульова СВІДОМО: комірка друкує `%L`, і на рівній секунді
  # пін не відрізнив би формат із мілісекундами від формату без них.
  # 🔴 Мікросекунди йдуть ОКРЕМИМ аргументом, не дробовою секундою: `45.123`
  # доїжджає як `45.122999999` (0.123 не представиться в двійковому Float), а
  # `%L` зрізає, не округлює, — тобто Float-форма мовчки дала б «122».
  def stamp = Time.zone.local(2024, 6, 15, 10, 30, 45, 123_000)

  # 🔴 [I18N.2] Носій ПРИСУДУ, а не поведінки: тіло рядка заморожене в
  # locale-інваріантні токени (⚖️ founder 2026-08-14), бо компонент рендериться
  # лише з Sidekiq, де локалі немає — тобто uk/lv/lt-переклади не бачив НІХТО.
  #
  # Чому окремий приклад, хоч сусідні вже пінять «BATCH_RECEIVED»: ті проходили
  # й ДО заморозки, бо `around` тримає `:en`. Вони цементують РЯДОК; цей —
  # інваріантність, і саме він червоніє, якщо хтось поверне `t()`.
  #
  # ⚠️ Ітеруємо `I18n.available_locales`, а не перелік із трьох мов: приклад
  # мусить лишатись правдивим у день, коли каталог виросте до 150 (`04_04 §8.1а`).
  #
  # ✅ Стеля знята 2026-08-14: `data-label` більше не існує в цьому рядку —
  # мітки колонок публікує СТОРІНКА як `--gaia-col-N` (⚖️ founder, `04_04 §8.1а`).
  # Компонент має НУЛЬ `t()`, тож приклад доводить інваріантність цілком.
  describe "locale-інваріантність payload'а" do
    it "рендериться ПОБАЙТОВО однаково в кожній налаштованій локалі" do
      renders = I18n.available_locales.to_h do |locale|
        [ locale, I18n.with_locale(locale) { render_component(gateway: relay, hex_payload: "DEADBEEF1234", timestamp: stamp) } ]
      end

      # Ліхтар: без нього приклад був би зелений і на однині available_locales.
      expect(renders.size).to be >= 2

      baseline = renders.values.first
      renders.each do |locale, html|
        expect(html).to eq(baseline), "рендер у #{locale} розійшовся з базовим — у payload'і локаль-залежна проза"
      end
    end

    # ⊥ Дзеркало: доводить, що механізм порівняння ЖИВИЙ. Без нього перша
    # асершн проходила б і на компоненті, який просто нічого не рендерить.
    it "містить самі токени, а не порожнечу" do
      html = I18n.with_locale(I18n.available_locales.last) { render_component(gateway: nil, hex_payload: "AA", timestamp: stamp) }

      expect(html).to include(described_class::UNKNOWN_RELAY, described_class::UNKNOWN_IP, described_class::BATCH_RECEIVED)
    end
  end

  describe "rendering" do
    let(:html) { render_component(gateway: relay, hex_payload: "DEADBEEF1234", timestamp: stamp) }

    it "renders the gateway UID" do
      expect(html).to include("SNET-Q-AABB0011")
    end

    it "displays the IP address" do
      expect(html).to include("192.168.1.100")
    end

    it "displays the hex payload" do
      expect(html).to include("DEADBEEF1234")
    end

    it "renders BATCH_RECEIVED status" do
      expect(html).to include("BATCH_RECEIVED")
    end

    it "renders the timestamp with milliseconds" do
      expect(html).to include("10:30:45.123")
    end

    it "renders as a table row" do
      expect(html).to include("<tr")
    end

    it "applies hover effect" do
      expect(html).to include("hover:bg-gaia-surface-sunken")
    end

    it "applies slide-in animation" do
      expect(html).to include("slide-in-from-left")
    end
  end

  # ⊥ Оголошений carve-out, не жива гілка. `gateway` тут НЕ буває `nil`: єдиний
  # виробник розіменовує `gateway.uid` за шість рядків до виклику, `cluster_id`
  # оголошено `NOT NULL`, а `belongs_to :cluster` обовʼязковий (виміряно).
  #
  # 🔴 **ПІДСТАВА ЗМІНИЛАСЬ 2026-08-15, і стара була б тепер брехнею.** Тут
  # стояло «гард `&.` лишається свідомо, бо броадкаст власного `rescue` не має,
  # тож виняток коштував би цілого конверта телеметрії». Той `rescue` тепер є
  # (`UnpackTelemetryWorker#broadcast_to_matrix`, UI.4), тобто ціна винятку
  # впала з «батч ніколи не розпакується» до «глядач не побачить одного кадра».
  # ⚠️ Носієм переходу мусив бути ЧИТАЧ, бо carve-out стереже ФОРМУ, а не вміст:
  # знявши дірку, я зняв і підставу гарда, і жоден гейт про це не сигналить.
  #
  # Гард `&.` лишається — але вже з ІНШОЇ підстави, вужчої й чеснішої:
  # компонент є публічним примітивом рендера (його кличуть і поза цим
  # продюсером — спека, майбутні сайти), а `UNKNOWN_RELAY` є осмисленим
  # значенням для кадру без відомого шлюзу. Тобто це вибір ДИЗАЙНУ компонента,
  # а не компенсація чужої відсутньої ізоляції.
  describe "nil gateway handling (defensive branch, unreachable from the sole producer)" do
    let(:html) { render_component(gateway: nil, hex_payload: "AABB", timestamp: stamp) }

    it "shows UNKNOWN_RELAY for nil gateway" do
      expect(html).to include("UNKNOWN_RELAY")
    end

    it "shows ?.?.?.? for nil IP" do
      expect(html).to include("?.?.?.?")
    end
  end

  describe "various hex payloads" do
    it "renders short payload" do
      html = render_component(gateway: relay, hex_payload: "FF", timestamp: stamp)
      expect(html).to include("FF")
    end

    it "renders long payload" do
      long_payload = "A" * 64
      html = render_component(gateway: relay, hex_payload: long_payload, timestamp: stamp)
      expect(html).to include(long_payload)
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(gateway: relay, hex_payload: "BEEF", timestamp: stamp) }

    it "uses text-mini for timestamp" do
      expect(html).to include("text-mini")
    end

    it "uses text-micro for IP label and status" do
      expect(html).to include("text-micro")
    end

    it "uses font-mono for data display" do
      expect(html).to include("font-mono")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-gaia-primary")
    end

    it "uses tracking-widest for status text" do
      expect(html).to include("tracking-widest")
    end
  end
end
