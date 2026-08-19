# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Index do
  # Component is i18n-aware. Existing assertions match the English copy.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  let(:cluster) { mock_cluster }
  let(:trees) { [ build_tree ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(cluster: cluster, trees: trees, pagy: pagy) }


  # 🔴 [TEST.12] Реальний незбережений `Cluster` — четвертий сайт того самого
  # візерунка (`00_07` UI.17): надгробок нижче звітує про конверсію `Tree`, а
  # сусідній обʼєкт лишався `OpenStruct`-ом за два рядки над ним. ⊕ Він же
  # спростовував сусідню клаузу: коментар про `under_threat?` називає стаб
  # «ЄДИНИМ, що тут вимагало б БД», і поки цей мок жив, це було неправдою.
  def mock_cluster(id: 1, name: "Carpathian-Alpha", active_trees_count: 5)
    Cluster.new(id: id, name: name, active_trees_count: active_trees_count)
  end

  # [TEST.12] Реальний незбережений `Tree`; фікстура годує ДЖЕРЕЛО заряду, не результат.
  # Доти мок клав напругу І відсоток заряду одночасно (`ARCH.99` зняв другий) — комбінація,
  # недосяжна за побудовою: на тому напруженні формула дає зовсім інший відсоток, тобто
  # прод малював ЖОВТУ смугу там, де сюїта стверджувала зелену (кольорові зони протилежні).
  # Тепер задаємо `latest_voltage_mv` (справжня колонка; `supply_voltage_mv` — проміжний
  # метод, що віддає її ЯК Є: `nil` = не виміряно, [ARCH.84] зняв тут `|| 0`), а відсоток
  # виводить модель — кожен приклад нижче обирає напруження під ту зону, яку він пінить.
  #
  # `under_threat?` стабимо свідомо — на реальному записі це запит до `ews_alerts`,
  # тобто єдине, що тут вимагало б БД.
  def build_tree(did: "SNET-00000042", status: :active, latest_voltage_mv: 5095,
                 last_seen_at: 1.minute.ago, under_threat: false)
    tree = Tree.new(
      id: 1,
      did: did,
      status: status,
      latest_voltage_mv: latest_voltage_mv,
      last_seen_at: last_seen_at
    )
    tree.define_singleton_method(:under_threat?) { under_threat }
    tree
  end

  describe "header" do
    it "displays sector matrix deployment title" do
      expect(html).to include("Sector Matrix Deployment")
    end

    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays population count" do
      expect(html).to include("Soldiers")
    end

    it "displays operational nodes count" do
      expect(html).to include("5")
      expect(html).to include("Nodes")
    end
  end

  describe "soldier node grid" do
    it "renders last 6 chars of DID" do
      expect(html).to include("000042")
    end

    it "displays tree status" do
      expect(html).to include("active")
    end

    it "displays voltage" do
      expect(html).to include("5095")
      expect(html).to include("mV")
    end

    # [ARCH.84] Носія в цієї осі не було ЗОВСІМ — фікс «0mV → не виміряно» не
    # червонив нічого, бо жоден приклад не подавав невиміряного дерева. Пара
    # обовʼязкова: сама лише поява напису не відрізняє «не виміряно» від
    # «виміряно нуль», а нуль на шині VDDA означає БРАУНАУТ, тобто найгірший
    # можливий вимір, підставлений мовчанню.
    it "says «not measured» instead of a brownout-grade 0mV for a silent node" do
      rendered = render_component(cluster: cluster, trees: [ build_tree(latest_voltage_mv: nil) ], pagy: pagy)

      expect(rendered).to include(I18n.t("ui.measurement.not_measured"))
      expect(rendered).not_to include("0mV")
    end

    it "still prints a genuinely measured zero" do
      rendered = render_component(cluster: cluster, trees: [ build_tree(latest_voltage_mv: 0) ], pagy: pagy)

      expect(rendered).to include("0mV")
    end
  end

  # 🔴 [ARCH.99] Після зняття смуги заряду ЦЕЙ LED — єдиний енергетичний сигнал
  # картки, тож піни тут стали несучими й переписані двома осями.
  # (1) Ціль — САМ елемент, не документ: `bg-emerald-500` носять ще hover-overlay
  #     (`bg-emerald-500/10`) і знята смуга, тож `include("bg-emerald-500")` був
  #     зелений за будь-якої поведінки LED (та сама вакуумність, що вбила три
  #     приклади «charge bar colors» разом зі смугою).
  # (2) Поріг — із моделі (`Tree::SILENCE_THRESHOLD`), а не «25 годин» літералом:
  #     компонент доти ніс рукописну копію правила, і спека цементувала копію.
  describe "LED indicator" do
    it "shows emerald LED for active, recently seen tree" do
      expect(html).to include("h-1.5 w-1.5 rounded-full bg-emerald-500")
    end

    it "shows red pulsing LED when under threat" do
      trees = [ build_tree(under_threat: true) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-status-danger")
      expect(rendered).to include("animate-pulse")
    end

    it "greys the LED once the node passes the shared silence threshold" do
      trees = [ build_tree(last_seen_at: (Tree::SILENCE_THRESHOLD + 1.hour).ago) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)

      expect(rendered).to include("h-1.5 w-1.5 rounded-full bg-gaia-text-subtle")
      expect(rendered).not_to include("h-1.5 w-1.5 rounded-full bg-emerald-500")
    end

    it "shows gray LED when last_seen_at is nil" do
      trees = [ build_tree(last_seen_at: nil) ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("h-1.5 w-1.5 rounded-full bg-gaia-text-subtle")
    end
  end

  # Статус іде через спільний `StatusBadge` (I18N.1, 2026-08-05). ⚠️ Приватна
  # мапа, яку він замінив, СХЛОПУВАЛА `active` і `dormant` в один клас — тобто
  # здорове й спляче дерево виглядали однаково; централізована їх розрізняє.
  # Доти піни стояли на `text-gaia-text-muted`, який носять і сусідні елементи
  # плитки, тож два з них були зелені незалежно від статусу.
  describe "status badge colors" do
    it "renders active with the success token, never danger" do
      expect(html).to include("bg-status-success")
      expect(html).not_to include("bg-status-danger")
    end

    it "renders dormant with the warning token" do
      trees = [ build_tree(status: "dormant") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
    end

    it "renders removed with the neutral token" do
      trees = [ build_tree(status: "removed") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-status-neutral")
    end

    it "renders deceased with the danger token" do
      trees = [ build_tree(status: "deceased") ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("bg-status-danger")
    end
  end

  describe "pagination" do
    it "renders without errors with pagy" do
      expect(html).to be_present
    end

    it "renders without pagination when pagy is nil" do
      rendered = render_component(cluster: cluster, trees: trees, pagy: nil)
      expect(rendered).to include("Sector Matrix Deployment")
    end
  end

  describe "multiple trees" do
    it "renders all tree nodes" do
      trees = [
        build_tree(did: "SNET-00000001"),
        build_tree(did: "SNET-00000002")
      ]
      rendered = render_component(cluster: cluster, trees: trees, pagy: pagy)
      expect(rendered).to include("000001")
      expect(rendered).to include("000002")
    end
  end

  describe "empty grid" do
    it "renders without errors when no trees" do
      rendered = render_component(cluster: cluster, trees: [], pagy: mock_pagy(count: 0, last: 1))
      expect(rendered).to include("Sector Matrix Deployment")
    end
  end

  describe "status text else branch" do
    # ⚠️ Дві поправки, і обидві несучі.
    # (1) Значення поза enum недосяжне на реальному записі (`ArgumentError` у
    #     конструкторі), тож єдиний чесний вхід — стаб самого РИДЕРА.
    # (2) Пін НЕ на клас: доти стояв `text-gaia-text`, який носять і `h2` кластера,
    #     і DID-спан, тобто був зелений незалежно від статусу. А на клас фолбеку
    #     пінити теж не можна — `bg-status-neutral` належить ще й живому `removed`,
    #     тому клас не розрізняє «фолбек» від «нормальний стан» (`04_06 §A.4` BP 20).
    #     Розрізняє лише сам текст: `StatusBadge` fail-open віддає сире значення.
    it "renders an unknown status verbatim, via the fail-open branch" do
      broken = build_tree
      allow(broken).to receive(:status).and_return("__not_a_status__")

      rendered = render_component(cluster: cluster, trees: [ broken ], pagy: pagy)
      expect(rendered).to include("__not_a_status__")
    end
  end

  describe "pagination url_helper" do
    it "renders pagination links with cluster path" do
      multi_pagy = mock_pagy(count: 50, page: 1, last: 3)
      rendered = render_component(cluster: cluster, trees: trees, pagy: multi_pagy)
      expect(rendered).to include("page=2")
    end
  end
end
