# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alerts::Index do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # 🔴 [SEC.31] Цей пін стереже не компонент, а ПІДСТАВУ чужого реєстрового рядка.
  # `browser_contour_registry` оголошує гілку `alerts#index` недосяжною саме тому,
  # що фільтр не може подати значення поза enum'ом — тобто недосяжність тримається
  # на ВІДНОШЕННІ двох множин, і жоден приклад доти його не перевіряв. Правка, що
  # додасть у фільтр значення, якого enum не має, зробить ту підставу хибною
  # мовчки: реєстр лишиться зеленим, бо він судить форму рядка, не його правду.
  # ⚠️ Чесна межа: розходження в бік «зайве у фільтрі» ламає й сам рендер, тож
  # клас частково ГУЧНИЙ. Цінність піна не в тому, що дефект був би тихим, а в
  # тому, що він називає ПРИЧИНУ (решта прикладів упали б як обвал рендера) і
  # стереже підставу чужого рядка — на випадок, коли розійдеться інший бік:
  # enum звузиться, а фільтр лишиться повним.
  let(:html)   { render_component(alerts: alerts, pagy: mock_pagy(count: 63), organization: org) }
  let(:alerts) { [ build_alert(id: 1, severity: "critical"), build_alert(id: 2, severity: "medium") ] }
  let(:org)    { mock_org }

  it "не пропонує severity, якої модель не знає" do
    expect(described_class::FILTER_SEVERITIES).to all(satisfy { |s| EwsAlert.severities.key?(s) })
  end

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
      # [UI.3] Доти дискримінатором тут стояла `opacity-40` — і вона ж була
      # дефектом (2.46:1). Роль перебрав власний фон; пара «має sunken ⊥ не має
      # hover:sunken» лишається двобічною, як і задумано вище.
      expect(out).to include("bg-gaia-surface-sunken")
      expect(out).not_to include("hover:bg-gaia-surface-sunken")
    end
  end

  describe "pagination" do
    it "renders pagination links" do
      expect(html).to include("page=")
    end
  end
end
