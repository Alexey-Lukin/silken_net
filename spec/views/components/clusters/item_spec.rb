# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Item do
  # [TEST.12] Реальний незбережений Cluster: фікстура годує ДЖЕРЕЛО, не вердикт —
  # `total_active_trees` є ридером counter-cache `active_trees_count`, тож OpenStruct
  # із готовим числом лишав деривацію неперевіреною; `model_name`/`to_key`/`to_param`
  # тепер справжні (саме їхня рукописність дозволяла `dom_id` розійтися з рендереним).
  # `health_index` — double precision, Float і в проді. Загрозна гілка — стаб САМОГО
  # ридера `active_threats?` (на незбереженому записі він чесно false).
  def mock_cluster(id: 1, name: "Carpathian-Alpha", active_threats: false,
                   total_active_trees: 42, health_index: 0.91)
    cluster = Cluster.new(id: id, name: name,
                          active_trees_count: total_active_trees, health_index: health_index)
    allow(cluster).to receive(:active_threats?).and_return(true) if active_threats
    cluster
  end

  let(:cluster) { mock_cluster }
  let(:html)    { render_component(cluster: cluster) }

  # [UI.3 08-20] Деталь-лінк несе видимий фокус-індикатор (WCAG 2.4.7): доти файл
  # мав нуль focus-visible при структурному близнюку в gateways/index із трійкою.
  describe "focus indicator" do
    it "gives the details link a visible focus ring" do
      expect(html).to include("focus-visible:ring-gaia-primary-strong")
    end
  end

  describe "header section" do
    it "renders cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders cluster ID" do
      expect(html).to include("ID: 1")
    end
  end

  describe "LED status indicator" do
    it "renders emerald LED when no active threats" do
      expect(html).to include("bg-gaia-primary-strong")
    end

    it "does not render red LED when no active threats" do
      expect(html).not_to include("bg-status-danger-accent")
    end

    it "renders red pulsing LED when cluster has active threats" do
      threat_cluster = mock_cluster(id: 2, name: "Threat-Node", active_threats: true)
      html = render_component(cluster: threat_cluster)
      expect(html).to include("bg-status-danger-accent")
    end

    it "does not render emerald LED when threats are active" do
      threat_cluster = mock_cluster(id: 2, active_threats: true)
      html = render_component(cluster: threat_cluster)
      expect(html).not_to include("bg-gaia-primary-strong")
    end
  end

  describe "stats section" do
    it "renders Trees label" do
      expect(html).to include("Trees")
    end

    it "renders tree count" do
      expect(html).to include("42")
    end

    it "renders Health label" do
      expect(html).to include("Health")
    end

    it "renders health index as percentage" do
      expect(html).to include("91%")
    end

    # 🔴 [ARCH.84] Доти цієї гілки не проходив ЖОДЕН приклад дерева: усі фікстури
    # ставили `health_index` явно, тож 500 на невиміряному кластері ловився лише
    # request-рівнем. Пін доводить стан ПРОТИ сусіда, у який він злипався, — 0%.
    it "renders «not measured» for a cluster with no reading, never 0%" do
      unmeasured = render_component(cluster: mock_cluster(health_index: nil))

      expect(unmeasured).to include(I18n.t("ui.measurement.not_measured"))
      expect(unmeasured).not_to include("0%")
    end
  end

  describe "footer link" do
    it "renders Open Matrix link" do
      expect(html).to include("Open Matrix")
    end

    it "links to the cluster path" do
      expect(html).to include("/clusters/1")
    end
  end

  # 🔴 Носій свідомого tradeoff'у, а не мікрооптимізація. `Cluster#active_threats?` б'є в БД
  # (`ews_alerts.unresolved.critical.exists?`) і НЕ мемоїзується, а цей рядок їде в циклі
  # `Clusters::Grid` — тож кожен зайвий виклик множиться на кількість кластерів на сторінці.
  # Контролер списку свідомо обрав EXISTS замість `includes` («composite index — includes не
  # потрібен»), і той розрахунок вірний рівно доти, доки запит ОДИН на рядок; доти їх було два.
  # Пін стоїть на реальному записі навмисно: `OpenStruct`-фабрика вище віддає синглтон, який
  # виклики не рахує, тож цю вісь вона виміряти не здатна за побудовою.
  describe "query discipline" do
    it "reads the DB-backed threat predicate exactly once per render" do
      real_cluster = Cluster.new(id: 1, name: "Carpathian-Alpha", health_index: 0.91, active_trees_count: 42)
      allow(real_cluster).to receive(:active_threats?).and_return(true)

      render_component(cluster: real_cluster)

      expect(real_cluster).to have_received(:active_threats?).once
    end
  end
end
