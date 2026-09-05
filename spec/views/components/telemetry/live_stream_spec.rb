# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telemetry::LiveStream do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # `stream_epoch` НЕ дефолтний (1) навмисно [SEC.25 Ф3]: якби епоха десь була
  # зашита константою замість того, щоб текти з організації, з одиницею це
  # лишилось би зеленим.
  let(:organization) { mock_model(Organization, id: 42, stream_epoch: 7) }

  # Стрім скоуплений організацією глядача. Пін іде по РОЗПАКОВАНОМУ імені, а не
  # по підписаному рядку (`04_06` BP #22): підпис ДЕТЕРМІНОВАНИЙ (чистий HMAC),
  # тож асершн на сам токен був би не крихким, а гіршим — він пінив би
  # `secret_key_base` і серіалізатор Turbo замість НАШОГО скоупу, і мовчки
  # порвався б на ротації ключа. До цього блоку жоден приклад цього файлу не
  # пінив підписку взагалі — ані ціль, ані сам факт.
  describe "stream scoping" do
    def subscribed_streams(markup)
      markup.scan(/signed-stream-name="([^"]+)"/).flatten
            .map { |s| Turbo::StreamsChannel.verified_stream_name(s) }
    end

    it "subscribes to the viewer's organization stream, never a global one" do
      expect(subscribed_streams(render_component(organization: organization)))
        .to eq([ "telemetry_stream_org_42_e7" ])
    end

    it "gives two organizations two different streams" do
      other = mock_model(Organization, id: 7, stream_epoch: 7)

      expect(subscribed_streams(render_component(organization: organization)))
        .not_to eq(subscribed_streams(render_component(organization: other)))
    end

    it "subscribes to nothing at all when the viewer has no organization" do
      markup = render_component(organization: nil)

      expect(markup).not_to include("turbo-cable-stream-source")
      expect(markup).to include("telemetry_feed") # сторінка лишається читабельною
    end
  end

  # [I18N.2] Сторінка — ЄДИНЕ місце, де мітка колонки ще знає локаль глядача:
  # рядок приїжджає броадкастом із Sidekiq, де локалі немає. Тому вона публікує
  # мітки як `--gaia-col-N`, а CSS підставляє їх у будь-який рядок, зокрема
  # вставлений пізніше (браузерний доказ механізму —
  # `spec/features/responsive_table_broadcast_label_spec.rb`).
  describe "публікація міток колонок" do
    it "віддає мітки в ЛОКАЛІ ГЛЯДАЧА, а не в базовій" do
      uk = I18n.with_locale(:uk) { render_component(organization: organization) }

      expect(uk).to include("--gaia-col-1: 'Час'")
      expect(uk).to include("--gaia-col-2: 'Королева / Шлюз'")
      # Ліхтар проти «опублікували, але базовою»: англійська мітка тут — дефект.
      expect(uk).not_to include("--gaia-col-1: 'Timestamp'")
    end

    it "тримає порядок публікації тим самим, що й `<thead>`" do
      # 🔴 CSS адресує колонки через `nth-child`, тож розбіжність порядку
      # мовчки переставила б мітки на мобільному — і жоден інший приклад
      # цього не побачив би: обидва набори рядків самі по собі правильні.
      html = I18n.with_locale(:uk) { render_component(organization: organization) }
      published = html.scan(/--gaia-col-\d: '([^']*)'/).flatten
      headers   = html.scan(%r{<th[^>]*>([^<]+)</th>}).flatten

      expect(published).to eq(headers)
    end

    it "оголошує таблицю опт-іном, інакше CSS-правило не застосується" do
      expect(render_component(organization: organization)).to include("gaia-labels-published")
    end
  end

  describe "rendering" do
    let(:html) { render_component(organization: organization) }


    it "displays the Neural Link Output heading" do
      expect(html).to include("Neural Link Output")
    end

    it "displays the Global Telemetry Stream title" do
      expect(html).to include("Global Telemetry Stream")
    end

    it "renders the carrier status indicator" do
      expect(html).to include("Carrier: Direct-to-Cell")
    end

    # ⚖️ [UI.1] Декоративний matrix-rain canvas знято 2026-08-14: ~16 fps
    # безперервного перемальовування = 100–300 мВт, більше за всю різницю тем.
    # Пін тримає ВІДСУТНІСТЬ, бо «прибрали» без носія повертається першим же
    # редизайном — а ефект виглядає як прикраса, не як витрата.
    it "не несе декоративного canvas — ані вузла, ані контролера" do
      expect(html).not_to include("matrix-rain")
      expect(html).not_to include("<canvas")
    end

    it "renders the telemetry_feed tbody" do
      expect(html).to include("telemetry_feed")
    end

    it "renders the placeholder row" do
      expect(html).to include("feed_placeholder")
    end

    it "shows awaiting uplink message" do
      expect(html).to include("Awaiting Starlink Uplink")
    end

    it "mentions CoAP:5683 in placeholder" do
      expect(html).to include("CoAP:5683")
    end
  end

  describe "table structure" do
    let(:html) { render_component(organization: organization) }

    it "renders table with role=table for accessibility" do
      expect(html).to include('role="table"')
    end

    it "renders Timestamp column header" do
      expect(html).to include("Timestamp")
    end

    it "renders Queen / Gateway column header" do
      expect(html).to include("Queen / Gateway")
    end

    it "renders Raw CoAP Payload column header" do
      expect(html).to include("Raw CoAP Payload")
    end

    it "renders Status column header" do
      expect(html).to include("Status")
    end
  end

  describe "visual effects" do
    let(:html) { render_component(organization: organization) }

    it "renders the spinner animation in placeholder" do
      expect(html).to include("animate-spin")
    end

    it "renders the pulsing live indicator" do
      expect(html).to include("animate-ping")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(organization: organization) }

    it "uses text-tiny for table body text" do
      expect(html).to include("text-tiny")
    end

    it "uses text-mini for labels" do
      expect(html).to include("text-mini")
    end

    it "uses tracking-widest for uppercase headings" do
      expect(html).to include("tracking-widest")
    end

    it "uses backdrop-blur for sticky header" do
      expect(html).to include("backdrop-blur-md")
    end

    # 🔴 [UI.16] НОСІЙ ПРОТИ ТИХОГО ДЕФЕКТУ, а не стильова причіпка. `display:flex`
    # на `td` знімає з елемента `display:table-cell`, а `colspan` діє ВИКЛЮЧНО на
    # table-cell — тож клітинка мовчки перестає розтягуватись на таблицю й падає
    # в ширину однієї колонки. Симптому немає: сторінка рендериться, заглушка
    # видима, просто стиснена — саме тому дефект дожив до скріншота з живого
    # canopy (2026-09-05), а не до жодного гейта.
    # ⛔ Периметр класу в дереві — НУЛЬ інстансів після фіксу, тож окремий гейт
    # стеріг би порожню множину; носій свідомо локальний, у спеці компонента,
    # який цей клас уже переживав (UI.3 — віньєтка, мертва 5,5 місяця).
    it "заглушка НЕ робить `td` флекс-контейнером — інакше `colspan` мовчки мертвий" do
      placeholder_cell = html[/<td[^>]*colspan="4"[^>]*>/]

      expect(placeholder_cell).to be_present, "клітинка-заглушка з colspan зникла — пін став вакуумним"
      expect(placeholder_cell).not_to match(/class="[^"]*\b(flex|grid|inline-flex)\b/)
    end
  end
end
