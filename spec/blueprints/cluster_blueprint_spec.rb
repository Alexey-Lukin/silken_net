# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterBlueprint, type: :model do
  before do
    silence_broadcasts!(:tree_map)
  end

  let(:cluster) { create(:cluster, name: "Korsun Forest", region: "Cherkasy Oblast") }

  describe "default view" do
    subject(:parsed) { JSON.parse(described_class.render(cluster)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(cluster.id)
    end

    it "includes name and region" do
      expect(parsed["name"]).to eq("Korsun Forest")
      expect(parsed["region"]).to eq("Cherkasy Oblast")
    end

    # [TEST.10] Нижче — не тип, а ЗНАЧЕННЯ: обчислення, що завжди повертає
    # константу, проходило перевірку типу й тому нічого не доводило.
    it "carries the persisted health_index, not the default" do
      cluster.update!(health_index: 0.42)
      expect(parsed["health_index"]).to eq(0.42)
    end

    # `total_active_trees` читає counter_cache, а той не оновлює вже завантажений
    # обʼєкт — без `reload` приклад побачив би 0 і спокушав би «послабити назад до
    # перевірки типу», хоча правильна дія протилежна.
    it "counts the cluster's active trees" do
      2.times { create(:tree, cluster: cluster, status: :active) }
      cluster.reload
      expect(parsed["total_active_trees"]).to eq(2)
    end

    # Саме обчислення центроїда (Polygon/MultiPolygon, порожні координати,
    # мемоїзація) належить моделі й вичерпно покрите в `spec/models/cluster_spec.rb`
    # — тут тверджується лише, що поле ЕКСПОНОВАНЕ і несе значення моделі.
    it "exposes geo_center as nil for an unmapped cluster" do
      expect(parsed).to have_key("geo_center")
      expect(parsed["geo_center"]).to be_nil
    end

    # [TEST.10] Тип замість значення ховав саме те, чим цей предикат
    # відрізняється від `Tree#under_threat?`: `Cluster#active_threats?` вимагає
    # нерозвʼязану І **critical** тривогу, тож medium-тривога тут — НЕ загроза.
    it "reports active_threats false for a cluster with no alert" do
      expect(parsed["active_threats"]).to be(false)
    end

    it "reports active_threats false for an unresolved MEDIUM alert" do
      create(:ews_alert, :drought, cluster: cluster)
      expect(parsed["active_threats"]).to be(false)
    end

    it "reports active_threats true for an unresolved CRITICAL alert" do
      create(:ews_alert, :fire, cluster: cluster)
      expect(parsed["active_threats"]).to be(true)
    end
  end

  # [ARCH.84] Доти: «health_index defaults to 1.0 when unset». API більше не вигадує
  # число — невиміряний кластер їде як `null`, і це змінює клієнтський контракт
  # (`00_04 §GET /contracts/stats` описує шкалу 0..1 для сусіднього поля).
  describe "health_index carries «not measured» as null" do
    it "renders null for a cluster that has no reading yet" do
      parsed = JSON.parse(described_class.render(cluster))

      expect(parsed).to have_key("health_index")
      expect(parsed["health_index"]).to be_nil
    end

    it "still renders a measured zero as 0.0, never as null" do
      cluster.update_column(:health_index, 0.0)
      parsed = JSON.parse(described_class.render(cluster))

      expect(parsed["health_index"]).to eq(0.0)
    end
  end

  describe "total_active_trees reflects denormalized counter" do
    it "returns 0 for a cluster with no trees" do
      parsed = JSON.parse(described_class.render(cluster))
      expect(parsed["total_active_trees"]).to be(0)
    end
  end

  describe "active_threats without alerts" do
    it "returns false when no critical alerts exist" do
      parsed = JSON.parse(described_class.render(cluster))
      expect(parsed["active_threats"]).to be false
    end
  end

  describe "collection rendering" do
    let!(:clusters) { create_list(:cluster, 3) }

    it "renders an array of clusters" do
      parsed = JSON.parse(described_class.render(clusters))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed).to all(include("name", "health_index"))
    end
  end
end
