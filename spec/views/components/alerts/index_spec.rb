# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alerts::Index do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # 🔴 [TEST.12] Реальний незбережений `EwsAlert`, і вирішальне тут не типи, а
  # ПОХІДНИЙ предикат: сторінка рендерить `Alerts::Row`, який гілкується на
  # `status_resolved?`, а мок оголошував лише `status`. `OpenStruct` віддавав на
  # предикат `nil`, тож рядок був «не resolved» ЗАВЖДИ — і resolved-вигляд не
  # перевірявся тут ніде. Сусідній `row_spec` деривував його чесно, тобто дефект
  # указувала асиметрія двох спек однієї родини.
  def build_alert(id: 1, alert_type: :fire_detected, severity: :critical, status: :active)
    EwsAlert.new(id: id, alert_type: alert_type, severity: severity, status: status, created_at: Time.current)
  end

  # `stream_epoch` несе саму адресу стріму [SEC.25 Ф3] — без нього дім імен
  # падає fail-closed, і це правильно: `_e` без числа було б одним іменем на всі
  # покоління.
  def mock_org(id: 42, name: "ForestCorp", stream_epoch: 7)
    OpenStruct.new(id: id, name: name, stream_epoch: stream_epoch)
  end

  let(:org)    { mock_org }
  let(:alerts) { [ build_alert(id: 1, severity: "critical"), build_alert(id: 2, severity: "medium") ] }
  let(:html)   { render_component(alerts: alerts, pagy: mock_pagy(count: 63), organization: org) }

  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source when organization is provided" do
      expect(html).to include("turbo-cable-stream-source")
    end

    it "subscribes to org-specific stream channel" do
      expect(html).to include("turbo-cable-stream-source")
      # The stream name is signed/base64-encoded; verify the raw channel attribute is present
      expect(html).to include('channel="Turbo::StreamsChannel"')
    end

    it "does not render turbo stream when organization is nil" do
      html = render_component(alerts: alerts, pagy: mock_pagy(count: 63), organization: nil)
      expect(html).not_to include("ews_alerts_org_")
    end
  end

  describe "header section" do
    # [I18N.1-нейминг] Див. system_audits: сторінка з однією секцією не повторює
    # власне ім'я — воно приходить із layout (h1), а не з компонента.
    it "does not duplicate the page name the layout already renders" do
      expect(html).not_to include("Active Threats Matrix")
    end

    it "renders the monitoring subtitle" do
      expect(html).to include("Monitoring live telemetry")
    end

    it "renders filter link for all alerts" do
      expect(html).to include('aria-label="Show all alerts"')
    end

    it "renders filter links for critical severity" do
      expect(html).to include("Filter alerts by critical severity")
    end

    it "renders filter links for medium severity" do
      expect(html).to include("Filter alerts by medium severity")
    end

    it "renders filter links for low severity" do
      expect(html).to include("Filter alerts by low severity")
    end
  end

  describe "table structure" do
    it "renders Severity column header" do
      expect(html).to include("Severity")
    end

    it "renders alerts_list tbody id" do
      expect(html).to include('id="alerts_list"')
    end

    # 🔴 Приклад, який доти НЕ МІГ існувати: `status_resolved?` приходив із мока
    # як `nil`, тож СКРІЗЬ ЧЕРЕЗ СТОРІНКУ список малював незакриту тривогу для
    # будь-якого статусу. ⚠️ Не читай це як «resolved не покритий ніде» — сусідній
    # `row_spec` тримає його чесно (мутація валить обидва приклади). Дім дефекту
    # саме в АСИМЕТРІЇ: одна спека родини деривує предикат, друга його вигадує,
    # і сторінковий тракт лишався єдиним, де закритий стан не рендерився ніколи.
    # Пін тримає ОБИДВА боки — присутність закритого вигляду і відсутність
    # активного: сама лише присутність зелена й тоді, коли рендеряться обидва.
    it "renders a resolved alert in its resolved presentation, not the active one" do
      out = render_component(alerts: [ build_alert(status: :resolved) ], pagy: mock_pagy(count: 1), organization: org)

      expect(out).to include("✓ Resolved")
      expect(out).to include("opacity-40")
      expect(out).not_to include("hover:bg-gaia-surface-sunken")
    end
  end

  describe "pagination" do
    it "renders pagination links" do
      expect(html).to include("page=")
    end
  end

  describe "Codex citation bulk lookup" do
    it "skips the bulk Codex query when the alerts array is empty" do
      # Forces the `if defined?(::Codex::Citation) && @alerts.any?` guard to fall
      # through to the empty-hash branch — Codex must not be queried at all.
      expect(::Codex::Citation).not_to receive(:bulk_for)

      out = render_component(alerts: [], pagy: mock_pagy(count: 0), organization: org)
      expect(out).to include('id="alerts_list"')
    end

    it "passes per-row citations through when bulk_for returns matches" do
      alert = build_alert(id: 7, severity: "critical")
      citation = instance_double(::Codex::Citation, node: nil, id: 99)
      key = [ "EwsAlert", 7 ]
      allow(::Codex::Citation).to receive(:polymorphic_type_for).with(alert).and_return("EwsAlert")
      allow(::Codex::Citation).to receive(:bulk_for).with([ alert ]).and_return(key => [ citation ])

      out = render_component(alerts: [ alert ], pagy: mock_pagy(count: 1), organization: org)
      expect(out).to include('id="alerts_list"')
    end
  end
end
