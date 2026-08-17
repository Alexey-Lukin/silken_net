# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cluster, type: :model do
  describe "#health_index" do
    it "returns the cached health_index value from the database" do
      cluster = create(:cluster, health_index: 0.85)
      expect(cluster.health_index).to eq(0.85)
    end

    # 🔴 [ARCH.84] Доти тут стояло «returns 1.0 when health_index is nil». Пін був
    # зелений і описував справжню поведінку — хибною була сама поведінка: `1.0` це
    # ДОСЯЖНЕ ВИМІРЯНЕ значення (див. «returns 1.0 when stress_index is 0» нижче),
    # тож два різні факти мали одне число. Пін тепер доводить розрізнення, а не
    # значення: невиміряний ⊥ виміряний-ідеальний.
    it "reports «not measured» as its own state, distinct from a measured perfect 1.0" do
      unmeasured = create(:cluster, health_index: nil)
      perfect    = create(:cluster, health_index: 1.0)

      expect(unmeasured.health_index).to be_nil
      expect(unmeasured.read_attribute(:health_index)).to be_nil

      expect(perfect.health_index).to eq(1.0)
      expect(perfect.read_attribute(:health_index)).to eq(1.0)
    end

    it "treats a measured zero as measured — not as absence" do
      dead = create(:cluster, health_index: 0.0)

      expect(dead.read_attribute(:health_index)).to eq(0.0)
      expect(dead.health_index).to eq(0.0)
    end
  end

  describe "#recalculate_health_index!" do
    it "accepts a target_date parameter" do
      cluster = create(:cluster)
      result = cluster.recalculate_health_index!(Time.current.utc.to_date - 1)
      expect(result).to be_nil # немає інсайту → «не виміряно», НЕ вигадане число
    end

    # 🔴 [ARCH.84] Писач мусить писати ЯВНИЙ nil, а не пропускати запис: колонку
    # переписує щонічний `Cluster.find_each`, тож «пропустити» означало б лишити
    # вчорашнє число на сьогоднішній темряві.
    it "OVERWRITES a previously measured value with nil when the day has no insight" do
      cluster = create(:cluster, health_index: 0.42)

      expect { cluster.recalculate_health_index! }
        .to change { cluster.reload.read_attribute(:health_index) }.from(0.42).to(nil)
    end

    # [ARCH.100] Тут доти стояв `describe "#local_yesterday"` — три приклади, що пінили
    # ПЕР-КЛАСТЕРНУ добу як правильну. Вони були зелені й описували справжню поведінку
    # методу; хибною була сама поведінка, бо інсайт, який цей метод шукає, штампується
    # UTC-добою агрегатора. Пін нижче стереже те, чого ті три не питали ЖОДНОГО разу:
    # чи знаходить кластер СВІЙ інсайт, коли його пояс не UTC.
    #
    # ⚠️ Час заморожено на моменті крона: дві дати розходяться лише у вікні
    # `UTC-година < |offset|`, тож без заморозки приклад був би зелений і на старій формі.
    it "resolves its default date to the anchor the insights were WRITTEN with, whatever the cluster timezone" do
      travel_to(Time.utc(2026, 8, 13, 2, 0, 0)) do
        expect(Time.use_zone("America/Manaus") { Date.yesterday }).not_to eq(AiInsight.reporting_date)

        cluster = create(:cluster, environmental_settings: { "timezone" => "America/Manaus" })
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: AiInsight.reporting_date, stress_index: 0.4)

        expect(cluster.recalculate_health_index!).to eq(0.6)
      end
    end
  end

  describe "#total_active_trees" do
    it "returns the cached active_trees_count column value" do
      cluster = create(:cluster, active_trees_count: 42)
      expect(cluster.total_active_trees).to eq(42)
    end

    it "defaults to 0 for a new cluster" do
      cluster = create(:cluster)
      expect(cluster.total_active_trees).to eq(0)
    end
  end

  describe "#active_contract" do
    it "returns the most recently created active contract" do
      cluster = create(:cluster)
      older = create(:naas_contract, cluster: cluster, status: :active, created_at: 2.days.ago)
      newer = create(:naas_contract, cluster: cluster, status: :active, created_at: 1.day.ago)

      expect(cluster.active_contract).to eq(newer)
    end

    it "returns nil when no active contracts exist" do
      cluster = create(:cluster)
      create(:naas_contract, cluster: cluster, status: :draft)

      expect(cluster.active_contract).to be_nil
    end
  end

  describe "#geo_center" do
    it "returns nil when geojson_polygon is absent" do
      cluster = create(:cluster, geojson_polygon: nil)
      expect(cluster.geo_center).to be_nil
    end

    it "calculates centroid from Polygon coordinates" do
      polygon = {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
      cluster = create(:cluster, geojson_polygon: polygon)
      center = cluster.geo_center

      expect(center[:lng]).to be_within(0.01).of(31.94)
      expect(center[:lat]).to be_within(0.01).of(49.44)
    end

    it "memoizes the result across multiple calls" do
      polygon = {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
      cluster = create(:cluster, geojson_polygon: polygon)

      first_call = cluster.geo_center
      second_call = cluster.geo_center

      expect(first_call).to equal(second_call) # same object_id (memoized)
    end
  end

  describe "#active_threats?" do
    it "returns true when cluster has unresolved critical alerts" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :active, severity: :critical, alert_type: :fire_detected)

      expect(cluster).to be_active_threats
    end

    it "returns false when cluster has no alerts" do
      cluster = create(:cluster)
      expect(cluster).not_to be_active_threats
    end

    it "returns false when alerts are resolved" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :resolved, severity: :critical, alert_type: :fire_detected)

      expect(cluster).not_to be_active_threats
    end

    it "returns false when alerts are not critical" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :active, severity: :low, alert_type: :severe_drought)

      expect(cluster).not_to be_active_threats
    end
  end

  describe "#mapped?" do
    it "returns true when geojson_polygon has coordinates" do
      polygon = { "type" => "Polygon", "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.5 ] ] ] }
      cluster = build(:cluster, geojson_polygon: polygon)

      expect(cluster).to be_mapped
    end

    it "returns false when geojson_polygon is nil" do
      cluster = build(:cluster, geojson_polygon: nil)
      expect(cluster).not_to be_mapped
    end

    it "returns false when coordinates are missing" do
      cluster = build(:cluster, geojson_polygon: { "type" => "Polygon" })
      expect(cluster).not_to be_mapped
    end
  end

  # [ARCH.76] `blockchain_transactions.cluster_id` має справжній DB-FK, але
  # `Cluster` не оголошував `has_many` — тож Rails не мав куди поставити
  # `restrict`, і знищення кластера зі slash-аудит-записом падало сирим
  # `PG::ForeignKeyViolation` ПОВЗ усю драбину `rescue_from`.
  #
  # Клас гірший за сам ARCH.76: той видно при читанні `has_many`, цей — ні,
  # бо декларації просто НЕМА. А сценарій не гіпотетичний: «останнє дерево»
  # пише інтент саме з `wallet: nil, cluster: …` ЗА ДИЗАЙНОМ ([ARCH.98]).
  describe "destroy guard over cluster-sourced money [ARCH.76]" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "refuses politely instead of raising a raw FK violation" do
      create(:blockchain_transaction, wallet: nil, cluster: cluster,
                                      token_type: :cusd, amount: 5)

      expect { cluster.destroy }.not_to raise_error
      expect(cluster.destroyed?).to be false
      expect(cluster.errors[:base]).to be_present
    end
  end

  describe "validations" do
    it "requires name" do
      cluster = build(:cluster, name: nil)
      expect(cluster).not_to be_valid
    end

    it "requires unique name" do
      create(:cluster, name: "Unique Sector")
      duplicate = build(:cluster, name: "Unique Sector")
      expect(duplicate).not_to be_valid
    end

    it "requires region" do
      cluster = build(:cluster, region: nil)
      expect(cluster).not_to be_valid
    end
  end

  describe "normalizes :geojson_polygon" do
    it "deep-stringifies keys when given a Hash with symbol keys" do
      polygon = { type: "Polygon", coordinates: [ [ [ 31.9, 49.4 ] ] ] }
      cluster = build(:cluster, geojson_polygon: polygon)
      expect(cluster.geojson_polygon).to eq("type" => "Polygon", "coordinates" => [ [ [ 31.9, 49.4 ] ] ])
    end

    it "leaves non-Hash values unchanged" do
      cluster = build(:cluster, geojson_polygon: nil)
      expect(cluster.geojson_polygon).to be_nil
    end
  end

  describe "#geo_center with empty coordinates" do
    it "returns nil when coordinates array is empty after flattening" do
      polygon = { "type" => "Polygon", "coordinates" => [] }
      cluster = create(:cluster, geojson_polygon: polygon)
      expect(cluster.geo_center).to be_nil
    end

    it "returns nil when geojson_polygon has coordinates key but is nil value" do
      polygon = { "type" => "Polygon", "coordinates" => nil }
      cluster = create(:cluster, geojson_polygon: polygon)
      expect(cluster.geo_center).to be_nil
    end
  end

  describe ".under_threat scope" do
    it "returns clusters with active critical alerts" do
      cluster = create(:cluster)
      create(:ews_alert, cluster: cluster, status: :active, severity: :critical, alert_type: :fire_detected)

      expect(described_class.under_threat).to include(cluster)
    end

    it "does not return clusters without active critical alerts" do
      cluster = create(:cluster)

      expect(described_class.under_threat).not_to include(cluster)
    end
  end

  # =========================================================================
  # POSTGIS SPATIAL QUERIES
  # =========================================================================
  describe "PostGIS spatial queries" do
    let(:polygon) do
      {
        "type" => "Polygon",
        "coordinates" => [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ]
      }
    end

    describe "#contains_point?" do
      it "returns true for a point inside the polygon" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.contains_point?(49.45, 31.95)).to be true
      end

      it "returns false for a point outside the polygon" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.contains_point?(0, 0)).to be false
      end

      it "returns false when geo_boundary is absent" do
        cluster = create(:cluster, geojson_polygon: nil)
        expect(cluster.contains_point?(49.45, 31.95)).to be false
      end
    end

    describe ".containing_point" do
      it "returns clusters that contain the given point" do
        cluster = create(:cluster, geojson_polygon: polygon)
        _other = create(:cluster, geojson_polygon: nil)

        result = described_class.containing_point(49.45, 31.95)
        expect(result).to include(cluster)
      end

      it "returns empty when no cluster contains the point" do
        create(:cluster, geojson_polygon: polygon)
        expect(described_class.containing_point(0, 0)).to be_empty
      end
    end

    # [E.36] Тригера тут БІЛЬШЕ НЕМА — колонка `GENERATED ALWAYS ... STORED`
    # (2026-08-14). Імʼя блоку стверджувало механізм, який зник; лишити його
    # означало б навчити наступного читача шукати тригер, якого не існує.
    describe "geo_boundary (generated column)" do
      # 🔴 Нова властивість, якої тригер не мав: битий GeoJSON тепер ВІДМОВЛЯЄ
      # на записі замість тихого NULL. Пін стоїть тут, бо без нього повернення
      # толерантності (тригер, `ELSE NULL`, rescue у моделі) пройшло б зеленим —
      # сусідні приклади не розрізняють «кордону немає» і «кордон був битий».
      it "ВІДМОВЛЯЄ на битому GeoJSON, а не пише тихий NULL" do
        expect {
          create(:cluster, geojson_polygon: { "type" => "Polygon", "coordinates" => "not-an-array" })
        }.to raise_error(ActiveRecord::StatementInvalid, /GeoJSON/)
      end

      it "auto-populates geo_boundary when geojson_polygon is set" do
        cluster = create(:cluster, geojson_polygon: polygon)
        expect(cluster.geo_boundary_present?).to be true
      end

      it "sets geo_boundary to NULL when geojson_polygon is nil" do
        cluster = create(:cluster, geojson_polygon: nil)
        expect(cluster.geo_boundary_present?).to be false
      end
    end
  end

  describe "geo_center with all-empty coordinate arrays" do
    it "returns nil for polygon with only empty nested arrays" do
      polygon = { "type" => "Polygon", "coordinates" => [ [] ] }
      cluster = create(:cluster, geojson_polygon: polygon)
      expect(cluster.geo_center).to be_nil
    end
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to organization" do
      assoc = described_class.reflect_on_association(:organization)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "has many trees" do
      assoc = described_class.reflect_on_association(:trees)
      expect(assoc.macro).to eq(:has_many)
    end

    it "has many gateways" do
      assoc = described_class.reflect_on_association(:gateways)
      expect(assoc.macro).to eq(:has_many)
    end

    # [SEC.26/ARCH.76] Доти `dependent:` для trees/gateways не пінив ЖОДЕН приклад —
    # тобто мовчазна зміна каскаду не почервонила б нічого. Пінимо не декларацію, а
    # ПОВЕДІНКУ: кластер із живим залізом мусить відмовлятись помирати.
    describe "кластер із залізом незнищенний" do
      it "відмовляє в destroy, поки в кластері є дерево, і НЕ занулює його cluster_id" do
        cluster = create(:cluster)
        tree = create(:tree, cluster: cluster)

        expect(cluster.destroy).to be(false)
        expect(cluster.errors[:base]).to be_present
        expect(described_class.exists?(cluster.id)).to be(true)
        # Несуче: `nullify` тут занулив би координату, яка є HKDF-salt прошитих ключів
        # і координатою історичних MRV-груп — дерево лишилось би живим і безпруфним.
        expect(tree.reload.cluster_id).to eq(cluster.id)
      end

      it "відмовляє в destroy, поки в кластері є шлюз" do
        cluster = create(:cluster)
        gateway = create(:gateway, cluster: cluster)

        expect(cluster.destroy).to be(false)
        expect(gateway.reload.cluster_id).to eq(cluster.id)
      end

      # Дзеркало: порожній кластер видаляється — присуд забороняє не видалення,
      # а знищення координати, на яку ще посилається залізо.
      it "дозволяє destroy порожнього кластера" do
        cluster = create(:cluster)

        expect(cluster.destroy).to be_truthy
        expect(described_class.exists?(cluster.id)).to be(false)
      end
    end

    it "has many naas_contracts with restrict_with_error" do
      assoc = described_class.reflect_on_association(:naas_contracts)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:restrict_with_error)
    end

    it "has many ews_alerts with delete_all" do
      assoc = described_class.reflect_on_association(:ews_alerts)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has many ai_insights as analyzable" do
      assoc = described_class.reflect_on_association(:ai_insights)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:as]).to eq(:analyzable)
    end
  end

  # =========================================================================
  # STORE ACCESSOR VALIDATIONS
  # =========================================================================
  describe "store_accessor validations" do
    it "rejects non-numeric custom_fire_threshold" do
      cluster = build(:cluster, custom_fire_threshold: "abc")
      expect(cluster).not_to be_valid
      expect(cluster.errors[:custom_fire_threshold]).to be_present
    end

    it "rejects zero custom_fire_threshold" do
      cluster = build(:cluster, custom_fire_threshold: 0)
      expect(cluster).not_to be_valid
    end

    it "accepts positive custom_fire_threshold" do
      cluster = build(:cluster, custom_fire_threshold: 75)
      expect(cluster).to be_valid
    end

    it "rejects negative seismic_sensitivity_threshold" do
      cluster = build(:cluster, seismic_sensitivity_threshold: -1)
      expect(cluster).not_to be_valid
    end

    it "accepts nil seismic_sensitivity_threshold" do
      cluster = build(:cluster, seismic_sensitivity_threshold: nil)
      expect(cluster).to be_valid
    end
  end

  # =========================================================================
  # RECALCULATE_HEALTH_INDEX! WITH INSIGHT DATA
  # =========================================================================
  describe "#recalculate_health_index! with AiInsight" do
    it "computes health_index from AiInsight stress_index" do
      cluster = create(:cluster)
      create(:ai_insight,
             analyzable: cluster,
             insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date,
             stress_index: 0.3)

      result = cluster.recalculate_health_index!
      expect(result).to eq(0.7)
      expect(cluster.reload.health_index).to eq(0.7)
    end

    it "returns 1.0 when stress_index is 0" do
      cluster = create(:cluster)
      create(:ai_insight,
             analyzable: cluster,
             insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date,
             stress_index: 0.0)

      result = cluster.recalculate_health_index!
      expect(result).to eq(1.0)
    end

    # 🔴 [ARCH.84] Пара до сусіда згори: обидва входи дають ОДНЕ число без гарда
    # (`nil.to_f` == `0.0.to_f`), тож розрізняє їх лише сам гард. Позитивна половина
    # («виміряний нуль → 1.0») стоїть вище й лишається — без неї «не пускаємо nil»
    # не відрізнити від «не пускаємо нічого».
    # ⊥ Друга половина несуча окремо: `health_coverage` рахує виміряність як
    # `COUNT(health_index)`, тож підставлена одиниця пройшла б як ВИМІРЯНА.
    it "лишає health_index невиміряним, коли інсайт Є, а stress_index не рахували" do
      cluster = create(:cluster)
      create(:ai_insight,
             analyzable: cluster,
             insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date,
             stress_index: nil)

      expect(cluster.recalculate_health_index!).to be_nil
      expect(cluster.reload.health_index).to be_nil

      coverage = described_class.health_coverage(described_class.where(id: cluster.id))
      expect(coverage.measured).to eq(0)
      expect(coverage.total).to eq(1)
    end

    it "returns 0.0 when stress_index is 1.0 (full stress)" do
      cluster = create(:cluster)
      create(:ai_insight,
             analyzable: cluster,
             insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date,
             stress_index: 1.0)

      result = cluster.recalculate_health_index!
      expect(result).to eq(0.0)
    end
  end

  # =========================================================================
  # .alphabetical SCOPE
  # =========================================================================
  describe ".alphabetical" do
    it "orders clusters by name ascending" do
      z_cluster = create(:cluster, name: "Zeta Sector")
      a_cluster = create(:cluster, name: "Alpha Sector")

      result = described_class.alphabetical
      expect(result.first).to eq(a_cluster)
      expect(result.last).to eq(z_cluster)
    end
  end

  describe "normalizes non-Hash geojson_polygon" do
    it "passes through a string value unchanged" do
      cluster = build(:cluster, geojson_polygon: "not-a-hash")
      expect(cluster.geojson_polygon).to eq("not-a-hash")
    end
  end

  describe "#validate_lorenz_overrides_by_species" do
    it "is valid with a well-formed overrides hash" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => 2.0, "max" => 45.0, "optimal" => 29.0 }
      })
      expect(c).to be_valid
    end

    it "accepts nil / empty hash (no overrides)" do
      expect(build(:cluster, lorenz_overrides_by_species: {})).to be_valid
      expect(build(:cluster, lorenz_overrides_by_species: nil)).to be_valid
    end

    it "rejects a blank species key" do
      c = build(:cluster, lorenz_overrides_by_species: { " " => { "min" => 1.0 } })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species]).to include(/blank species key/)
    end

    it "rejects when bounds value is not a Hash" do
      c = build(:cluster, lorenz_overrides_by_species: { "Pinus sylvestris" => "bad" })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("must be a Hash")
    end

    it "rejects unknown keys inside a bounds Hash" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => 1.0, "unknown_key" => 9 }
      })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("unknown key")
    end

    it "rejects non-numeric values for min/max/optimal" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => "notanumber", "max" => 45.0 }
      })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("must be numeric")
    end

    it "rejects min >= max" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => 30.0, "max" => 10.0 }
      })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("'min' must be < 'max'")
    end

    it "rejects optimal <= min" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => 5.0, "max" => 45.0, "optimal" => 5.0 }
      })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("'optimal' must be > 'min'")
    end

    it "rejects optimal >= max" do
      c = build(:cluster, lorenz_overrides_by_species: {
        "Pinus sylvestris" => { "min" => 2.0, "max" => 45.0, "optimal" => 45.0 }
      })
      expect(c).not_to be_valid
      expect(c.errors[:lorenz_overrides_by_species].join).to include("'optimal' must be < 'max'")
    end
  end
end
