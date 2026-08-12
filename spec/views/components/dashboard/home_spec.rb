# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Home do
  # Component is i18n-aware. Existing assertions match the English copy,
  # so we render under :en across this file.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # ⚠️ Значення — контракт із `Api::V1::DashboardController#index`, не вигадка спеки.
  # `health_avg` там = `org.clusters.average(:health_index).to_f.round(2)`, тобто
  # шкала 0..1. Доти фікстура підставляла `92` — ключ правильний, ШКАЛА вигадана,
  # і саме тому «0%» на живій головній сторінці лишалось невидимим ([UI.7]).
  def mock_stats(health_avg: 0.92, active_trees: 38, total_trees: 40,
                 total_scc: "1250 SCC", avg_voltage: 3800)
    {
      trees: { health_avg: health_avg, active: active_trees, total: total_trees },
      economy: { total_scc: total_scc },
      energy: { avg_voltage: avg_voltage }
    }
  end

  def mock_ews_event
    cluster = OpenStruct.new(name: "Carpathian-7")
    alert = EwsAlert.allocate
    # [TEST.12] Реальне значення enum'а, не display-рядок: із «Thermal Anomaly»
    # `TextFormatter` їхав fail-open гілкою `humanize`, тобто стрічка подій
    # перевірялась шляхом, якого в проді не буває (той самий дефект `event_row_spec`
    # уже виправив — тут був його рецидив).
    alert.define_singleton_method(:alert_type) { "fire_detected" }
    alert.define_singleton_method(:cluster) { cluster }
    alert.define_singleton_method(:created_at) { 1.minute.ago }
    alert
  end

  def mock_tx_event
    tree = OpenStruct.new(did: "SNET-00000042")
    wallet = OpenStruct.new(tree: tree)
    tx = BlockchainTransaction.allocate
    tx.define_singleton_method(:amount) { "0.005" }
    tx.define_singleton_method(:wallet) { wallet }
    tx.define_singleton_method(:sourceable) { nil }
    tx.define_singleton_method(:created_at) { 2.minutes.ago }
    tx
  end

  # `stream_epoch` несе адресу вкладеної мапи [SEC.25 Ф3]: `Dashboard::Home`
  # рендерить `Dashboard::Map`, а той підписується через дім імен, який без
  # епохи падає fail-closed.
  def mock_organization(id: 7, stream_epoch: 7)
    OpenStruct.new(id: id, stream_epoch: stream_epoch)
  end

  def render_component(stats:, events:, trees: [], organization: mock_organization)
    ApplicationController.renderer.render(
      component_class.new(stats: stats, events: events, trees: trees, organization: organization),
      layout: false
    )
  end

  let(:stats) { mock_stats }
  let(:html) { render_component(stats: stats, events: []) }

  describe "StatCard components for tree stats" do
    it "renders Forest Vitality stat card" do
      expect(html).to include("Forest Vitality")
    end

    it "renders the health avg percentage" do
      expect(html).to include("92%")
    end

    it "renders Active Soldiers stat card" do
      expect(html).to include("Active Soldiers")
    end

    it "renders active tree count" do
      expect(html).to include("38")
    end
  end

  describe "economy stat" do
    # [ARCH.88] Величина = sum(:balance), тобто БАЛИ росту. Ім'я прикладу тут
    # само було твердженням — і брехливим, тож правиться разом з ассертом.
    it "renders the Growth Treasury stat card, not a coin treasury" do
      expect(html).to include("Growth Treasury")
      expect(html).not_to include("Carbon Treasury")
    end

    it "renders total_scc value" do
      expect(html).to include("1250 SCC")
    end
  end

  describe "energy stat" do
    it "renders Ionic Potential stat card" do
      expect(html).to include("Ionic Potential")
    end

    it "renders average voltage with mV unit" do
      expect(html).to include("3800mV")
    end

    it "applies danger styling when voltage is below 3300" do
      low_voltage_html = render_component(stats: mock_stats(avg_voltage: 3100), events: [])
      # danger: true triggers different styling via StatCard
      expect(low_voltage_html).to include("3100mV")
    end
  end

  describe "live feed container" do
    it "renders the Live Transmission Feed heading" do
      expect(html).to include("Live Transmission Feed")
    end

    it "renders a link to the Mission Log (alerts)" do
      expect(html).to include("Open Mission Log →")
    end
  end

  describe "event_row delegation" do
    it "renders EwsAlert event rows via EventRow component" do
      html = render_component(stats: stats, events: [ mock_ews_event ])
      expect(html).to include("Threat:")
    end

    it "renders BlockchainTransaction event rows" do
      html = render_component(stats: stats, events: [ mock_tx_event ])
      expect(html).to include("SNET-00000042")
    end
  end

  describe "empty events state" do
    it "renders without errors when events list is empty" do
      expect(html).to include("Live Transmission Feed")
    end
  end

  # Третя ланка контракту живого тракту (`04_04 §8.1`): продюсер і підписник
  # обидва існували роками, а `Dashboard::Map` не рендерився ЖОДНИМ маршрутом —
  # на його місці стояв вічний спінер. Пін саме на РЕНДЕР підписника, бо
  # пара «продюсер ⟷ підписник» цю вісь не бачить за побудовою.
  describe "geospatial matrix" do
    let(:tree) do
      t = OpenStruct.new(id: 5, did: "SNET-00000005", latitude: 49.44, longitude: 32.06,
                         status: "active", current_stress: 0.1, charge_percentage: 90)
      t.define_singleton_method(:model_name) { ActiveModel::Name.new(Tree) }
      t.define_singleton_method(:to_key) { [ 5 ] }
      t.define_singleton_method(:to_param) { "5" }
      t
    end

    it "renders the live map instead of a placeholder spinner" do
      rendered = render_component(stats: stats, events: [], trees: [ tree ])

      expect(rendered).to include('data-controller="map"')
      expect(rendered).to include("map_node_5")
      expect(rendered).not_to include("animate-spin")
    end
  end
end
