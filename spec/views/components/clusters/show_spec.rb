# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Show do
  let(:cluster) { build_cluster }
  let(:gateways) { [ mock_gateway ] }
  let(:recent_alerts) { [] }
  let(:html) { render_component(cluster: cluster, gateways: gateways, recent_alerts: recent_alerts) }

  # [ARCH.84] Компонент вимагає пару покриття БЕЗ дефолту (щоб забута проводка
  # падала гучно), тож дефолт живе тут — і рівно тут він чесний: приклади нижче
  # міряють інші осі, а САМУ пару стереже власний `describe` наприкінці файлу.
  # ⚠️ `nil`/`nil` = «інсайту за добу немає», тобто рядок покриття не рендериться —
  # це і є базовий стан решти прикладів.
  # [ARCH.103] `cluster_emission` дефолтиться РЕАЛЬНИМ виміром (нуль — це вимір,
  # бо агрегат виконався), а не `nil`: на сторінці КЛАСТЕРА субʼєкт відомий завжди,
  # тож `nil`-дефолт оголошував би стан, якого в цьому компоненті не буває.
  def render_component(health_measured: nil, health_total: nil, cluster_emission: 0, **kwargs)
    super(health_measured: health_measured, health_total: health_total,
          cluster_emission: cluster_emission, **kwargs)
  end

  def build_cluster(id: 1, name: "Carpathian-Alpha", region: "Cherkasy Oblast",
                   health_index: 0.87, total_active_trees: 142, active_threats: false)
    # [TEST.12] Реальний незбережений `Cluster`. Колонки годуються як колонки
    # (`active_trees_count` — читач `total_active_trees`), а стабляться РІВНО ті три
    # методи, що ходять у БД: `active_threats?` (`ews_alerts…exists?`), `geo_center`
    # (агрегат по деревах) і `active_contract` (`naas_contracts.active…first`).
    # ⚠️ `mapped?` НЕ стабиться свідомо — він чистий (`geojson_polygon.present? && …`),
    # тож на реальному записі відповідає сам, і фікстура більше не вигадує його відповідь.
    cluster = Cluster.new(
      id: id,
      name: name,
      region: region,
      health_index: health_index,
      active_trees_count: total_active_trees,
      environmental_settings: {},
      # 🔴 Годуємо ДЖЕРЕЛО, а не відповідь: доти `mapped?` був синглтоном `true`,
      # тобто фікстура сама вирішувала, чи кластер має контур. Метод чистий
      # (`geojson_polygon.present? && …["coordinates"].present?`), тож реальна
      # колонка робить його перевірним — і заразом видно, що порожній полігон
      # (`{}`) дає `false`, чого мок не показував ніколи.
      geojson_polygon: { "type" => "Polygon", "coordinates" => [ [ [ 32.0, 49.4 ], [ 32.1, 49.4 ], [ 32.1, 49.5 ] ] ] }
    )
    allow(cluster).to receive_messages(active_threats?: active_threats, active_contract: nil, geo_center: { lat: 49.4444, lng: 32.0597 })
    cluster
  end

  # [TEST.12] Реальні незбережені записи замість `OpenStruct`. Компонент читає від
  # шлюзу рівно колонки (`uid`/`state`/`latitude`/`longitude`/`last_seen_at`), а від
  # алерту — `severity`/`created_at` плюс `dom_id`, який реальна модель віддає сама:
  # разом із моком зникають три рукописні `model_name`/`to_key`, що імітували
  # метадані фреймворку.
  def mock_gateway(uid: "QUEEN-01", state: "active", latitude: 49.4, longitude: 32.1)
    Gateway.new(uid: uid, state: state, latitude: latitude, longitude: longitude,
                last_seen_at: Time.current)
  end

  # ⚠️ `severity` — enum `{low, medium, critical}`, тож значення поза ним реальний
  # запис не приймає (`ArgumentError` просто в конструкторі). Гілка «нерозпізнана
  # тяжкість» досяжна лише стабом РИДЕРА на живому записі — форма, яку це репо вже
  # вживає для недосяжних станів; конструктор при цьому лишається валідним.
  def mock_alert(id: 1, alert_type: "fire_detected", severity: "critical")
    known = EwsAlert.severities.key?(severity.to_s)
    alert = EwsAlert.new(id: id, alert_type: alert_type, created_at: Time.current,
                         severity: known ? severity : :low)
    alert.define_singleton_method(:severity) { severity } unless known
    alert
  end

  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source for alerts" do
      expect(html).to include("turbo-cable-stream-source")
    end
  end

  describe "header" do
    it "displays the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays the region and ID" do
      expect(html).to include("Cherkasy Oblast")
    end

    it "shows nominal status when no active threats" do
      expect(html).to include("Nominal")
    end

    it "shows threat detected when active threats" do
      html = render_component(cluster: build_cluster(active_threats: true), gateways: [], recent_alerts: [])
      expect(html).to include("Threat Detected")
    end
  end

  describe "vitals panel" do
    it "displays health index as percentage" do
      expect(html).to include("87%")
    end

    # 🔴 [ARCH.84] Пара до попереднього: невиміряний ⊥ виміряний. Без другої половини
    # приклад доводив би лише «щось відрендерилось».
    it "displays «not measured» instead of a fabricated percentage when there is no reading" do
      unmeasured = render_component(cluster: build_cluster(health_index: nil), gateways: [], recent_alerts: [])

      expect(unmeasured).to include(I18n.t("ui.measurement.not_measured"))
      expect(unmeasured).not_to include("0%")
    end

    # 🔴 [ARCH.84] Трійка на ПОКРИТТЯ, і кожен член несе свою половину доказу.
    # Без другого «87%» на лісі, виміряному на пʼяту частину, невідрізнимі від
    # повного; без третього пін проходив би й на компоненті, що друкує підставу
    # ЗАВЖДИ (тоді «виміряно 5 з 5» стояло б під кожним здоровим кластером і
    # знецінило б сигнал). Дім тексту — `ui.measurement.coverage`, спільний із
    # `OracleVisions::Index`, тож пінимо його ЗНАЧЕННЯ, а не свій рядок.
    it "prints the ground under the health index when the sector was only partly measured" do
      partial = render_component(cluster: cluster, gateways: [], recent_alerts: [],
                                 health_measured: 1, health_total: 5)

      expect(partial).to include("87%")
      expect(partial).to include(I18n.t("ui.measurement.coverage", measured: 1, total: 5))
    end

    it "stays SILENT about coverage when every living tree of the sector reported" do
      full = render_component(cluster: cluster, gateways: [], recent_alerts: [],
                              health_measured: 5, health_total: 5)

      expect(full).to include("87%")
      expect(full).not_to include(I18n.t("ui.measurement.coverage", measured: 5, total: 5))
    end

    it "displays active trees count" do
      expect(html).to include("142")
    end

    it "displays gateway count" do
      expect(html).to include("1")
    end
  end

  describe "gateways table" do
    it "renders gateway UID" do
      expect(html).to include("QUEEN-01")
    end

    it "shows empty state when no gateways" do
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("No gateways deployed")
    end
  end

  describe "alerts panel" do
    it "shows empty state when no alerts" do
      expect(html).to include("No active threats")
    end

    it "renders alerts_list container for turbo prepend" do
      expect(html).to include('id="alerts_list"')
    end

    context "with active alerts" do
      let(:recent_alerts) { [ mock_alert(id: 5, alert_type: "fire_detected", severity: "critical") ] }

      it "displays the localized alert-type label, not the raw enum value" do
        expect(html).to include("Fire Detected")
        expect(html).not_to include("fire_detected")
      end

      it "uses dom_id for alert elements" do
        expect(html).to include('id="ews_alert_5"')
      end
    end
  end

  describe "geography panel" do
    it "displays region" do
      expect(html).to include("Cherkasy Oblast")
    end

    it "displays mapped status" do
      expect(html).to include("Yes")
    end

    it "includes Google Maps link" do
      expect(html).to include("google.com/maps")
    end

    it "displays mapped=No when the cluster is not mapped" do
      cl = build_cluster
      cl.geojson_polygon = {} # джерело, не відповідь: `mapped?` виводить це сам
      out = render_component(cluster: cl, gateways: [], recent_alerts: [])
      expect(out).to include("Mapped")
      expect(out).not_to include("Yes")
    end

    it "omits the centroid and map link when geo_center is nil" do
      cl = build_cluster
      cl.define_singleton_method(:geo_center) { nil }
      out = render_component(cluster: cl, gateways: [], recent_alerts: [])
      expect(out).not_to include("google.com/maps")
    end
  end

  describe "environmental settings" do
    it "renders fire threshold when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "custom_fire_threshold" => 65 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Fire Threshold")
      expect(html).to include("65°C")
    end

    it "renders seismic sensitivity when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "seismic_sensitivity_threshold" => 0.8 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Seismic Sensitivity")
      expect(html).to include("0.8")
    end

    it "renders timezone when set" do
      cluster = build_cluster
      cluster.environmental_settings = { "timezone" => "Europe/Kyiv" }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Timezone")
      expect(html).to include("Europe/Kyiv")
    end

    it "renders Environmental Config heading when settings present" do
      cluster = build_cluster
      cluster.environmental_settings = { "custom_fire_threshold" => 65 }
      html = render_component(cluster: cluster, gateways: [], recent_alerts: [])
      expect(html).to include("Environmental Config")
    end
  end

  describe "contract panel" do
    it "renders NaaS Contract heading" do
      expect(html).to include("NaaS Contract")
    end

    it "shows 'No active NaaS contract.' when no contract" do
      expect(html).to include("No active NaaS contract.")
    end

    context "with active contract" do
      it "renders contract details" do
        # 🔴 [TEST.12] Реальний `NaasContract`, і це не гігієна: `total_value` — alias
        # на `total_funding`, колонка `numeric`, тож прод друкує BigDecimal («50000.0»),
        # а не Integer. Доти пін `include("50000")` був підрядком обох форм — тобто не
        # здатен був побачити ані тип, ані ОДИНИЦЮ, яку цей рядок тепер несе (USD:
        # сусідній рядок правомірно каже «Emitted SCC», і без підпису плата за послугу
        # читалась у тій самій валюті — восьмий сайт класу, закритого в [I18N.1]).
        #
        # ⚠️ [UI.3] Контракт тепер ПЕРЕДАЄТЬСЯ, а не стабиться на кластері: доти
        # компонент діставав його сам у `initialize`, тобто спека мусила підробляти
        # DB-виклик, щоб описати екран. Стаб на `active_contract` став би тепер
        # мертвим — і мовчки, бо `nil`-гілка теж рендериться.
        contract = NaasContract.new(status: :active, total_funding: 50_000, emitted_tokens: 1200)
        html = render_component(cluster: build_cluster, gateways: [], recent_alerts: [],
                                active_contract: contract, cluster_emission: 340)
        expect(html).to include("ACTIVE")
        expect(html).to include("50000.0 USD")
        # 🔴 [ARCH.103] Дискримінатор СЕМАНТИКИ, а не наявності числа: панель друкує
        # емісію КЛАСТЕРА, тож фікстура навмисно тримає ДВА різні числа — контрактне
        # `emitted_tokens` (1200) і кластерне (340). Старий пін на 1200 пройшов би й
        # після присуду, бо не питав, ЧИЯ це величина; новий ловить регрес до колонки.
        expect(html).to include("340")
        expect(html).not_to include("1200")
      end
    end
  end

  # 🔴 [TEST.12] Два з трьох пінів цього блоку були ВАКУУМНІ — і найгірше не те,
  # що вони нічого не доводили, а те, що вони цементували поведінку, від якої код
  # СВІДОМО відмовився. `low` колись справді був `bg-emerald-500`; фікс перевів
  # його на `bg-status-info` (підстава — коментар біля `alert_severity_class`), а
  # піни лишились зелені, бо `include("bg-emerald-500")` живився ІНШИМ вузлом того
  # ж рендеру: індикатор «Nominal» у шапці малює цей клас безумовно, щойно
  # `active_threats?` хибний — а це дефолт фікстури по всьому файлу.
  #
  # Доведено мутацією, і саме вона називає периметр: зі знесеними гілками
  # `alert_severity_class` упав РІВНО ОДИН приклад із трьох (`medium`). Питання
  # тут не «чи червоніє мій пін», а «які з N не почервоніли».
  #
  # Лік — цілитись у ВУЗОЛ, а не в документ: клас severity живе на крапці
  # всередині рядка алерту, тож `css` по ній відрізняє її від шапки.
  describe "alert severity class" do
    # Крапка severity — єдиний `div.rounded-full` усередині рядка алерту
    # (`h-2 w-2 rounded-full` + сам клас тяжкості). Саме вона, а не документ:
    # шапка сторінки несе власний індикатор, і доти піни читали ЙОГО.
    def severity_dot_classes(alert)
      rendered = render_component(cluster: cluster, gateways: [], recent_alerts: [ alert ])
      Nokogiri::HTML5.fragment(rendered)
                     .css("##{ActionView::RecordIdentifier.dom_id(alert)} div.rounded-full")
                     .map { |n| n["class"].to_s }.join(" ")
    end

    it "uses warning style for medium severity" do
      expect(severity_dot_classes(mock_alert(severity: "medium"))).to include("bg-status-warning")
    end

    it "uses the INFO style for low severity — never the nominal-green of the header" do
      classes = severity_dot_classes(mock_alert(severity: "low"))

      expect(classes).to include("bg-status-info")
      expect(classes).not_to include("bg-emerald-500")
    end

    it "falls back to the neutral style for a severity outside the enum" do
      classes = severity_dot_classes(mock_alert(severity: "unknown"))

      expect(classes).to include("bg-status-neutral")
      expect(classes).not_to include("bg-emerald-500")
    end
  end

  describe "initialize guard" do
    it "raises ArgumentError when cluster does not respond to :name" do
      bad = Object.new
      expect {
        described_class.new(cluster: bad, gateways: [], recent_alerts: [],
                            health_measured: nil, health_total: nil, cluster_emission: 0)
      }.to raise_error(ArgumentError, /cluster must respond to :name/)
    end

    # 🔴 [ARCH.84] Ліхтар на РІШЕННЯ, а не на поведінку: пара покриття свідомо
    # без дефолту, бо `nil`-дефолт зробив би забуту проводку невідрізнимою від
    # «виміряно повністю» (`measurement_coverage` мовчить в обох випадках).
    # Без цього прикладу перший, кому обовʼязковий kwarg заважає, тихо додасть
    # `= nil` — і жоден інший приклад не почервоніє.
    it "refuses to render without the coverage pair — a silent default would read as full measurement" do
      expect {
        described_class.new(cluster: cluster, gateways: [], recent_alerts: [], cluster_emission: 0)
      }.to raise_error(ArgumentError, /health_measured/)
    end
  end

  describe "gateway row last_seen_at fallback" do
    # 🔴 Пін доти читав `include("—")` по ДОКУМЕНТУ, а риска є фолбеком і в
    # сусідніх поверхнях сторінки — тобто він не відрізняв «шлюз без часу» від
    # будь-якої іншої порожнечі. Цілимось у РЯДОК цього шлюзу.
    it "renders a dash when a gateway has no last_seen_at timestamp" do
      gw = mock_gateway(uid: "QUEEN-NIL", latitude: 0, longitude: 0)
      gw.last_seen_at = nil
      out = render_component(cluster: cluster, gateways: [ gw ], recent_alerts: [])

      row = Nokogiri::HTML5.fragment(out).css("*").find { |n| n.text.include?("QUEEN-NIL") && n.text.length < 200 }
      expect(row).not_to be_nil, "рядок шлюзу не знайдено — пін інакше вакуумний"
      expect(row.text).to include("—")
    end
  end
end
