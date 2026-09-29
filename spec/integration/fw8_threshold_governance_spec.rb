# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.8] End-to-end coverage of cluster-configurable Lorenz thresholds via governance.
# Chain: Cluster overrides → TreeFamily defaults → Tree#effective_lorenz_thresholds
# → OtaPackagerService.threshold_config_body («ЩО СЛАТИ на пристрій»; кадр — Downlink::CommandFrame).
# 🔴 [2026-09-05] Заголовок доти називав ланкою ще й `TelemetryUnpackerService
# divergence check` — знято: DCI цей ланцюг БІЛЬШЕ НЕ читає, він судить за
# `Tree#device_lorenz_bands` (смуги, які може тримати пристрій). Обидві половини
# розведення запінені: governance — нижче, DCI — у
# `spec/services/telemetry_unpacker_service_spec.rb` («[FW.8]»).
RSpec.describe "[FW.8] Cluster-configurable Lorenz thresholds", type: :integration do
  describe "TreeFamily#effective_optimal_z_target" do
    it "returns 29.0 (global default) when optimal_z_target is unset" do
      family = build(:tree_family, biological_properties: {})
      expect(family.effective_optimal_z_target).to eq(29.0)
    end

    it "returns the per-species value when set" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      family.optimal_z_target = 27.0
      expect(family.effective_optimal_z_target).to eq(27.0)
    end

    it "validates optimal_z_target lies between critical_z_min and critical_z_max" do
      family = build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0)
      family.optimal_z_target = 50.0
      expect(family).not_to be_valid
      expect(family.errors[:optimal_z_target]).to be_present
    end
  end

  describe "Cluster#lorenz_overrides_for(scientific_name)" do
    let(:cluster) { build(:cluster) }

    it "returns all-nil hash when no overrides set" do
      expect(cluster.lorenz_overrides_for("Pinus sylvestris"))
        .to eq(min: nil, max: nil, optimal: nil)
    end

    it "returns Float values for the requested species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 6.0, "max" => 40.0, "optimal" => 30.0 }
      }
      expect(cluster.lorenz_overrides_for("Pinus sylvestris"))
        .to eq(min: 6.0, max: 40.0, optimal: 30.0)
    end

    it "returns all-nil hash for an unconfigured species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 6.0 }
      }
      expect(cluster.lorenz_overrides_for("Quercus robur"))
        .to eq(min: nil, max: nil, optimal: nil)
    end

    it "supports mixed-species clusters with different overrides per species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 6.0, "max" => 40.0 },
        "Quercus robur"    => { "min" => 4.0, "max" => 40.0, "optimal" => 25.0 }
      }
      expect(cluster.lorenz_overrides_for("Pinus sylvestris"))
        .to eq(min: 6.0, max: 40.0, optimal: nil)
      expect(cluster.lorenz_overrides_for("Quercus robur"))
        .to eq(min: 4.0, max: 40.0, optimal: 25.0)
    end

    it "validates each species' min < max" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 50.0, "max" => 5.0 }
      }
      expect(cluster).not_to be_valid
      expect(cluster.errors[:lorenz_overrides_by_species].join).to include("Pinus sylvestris")
    end

    it "validates optimal lies between min and max for each species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 2.0, "max" => 45.0, "optimal" => 50.0 }
      }
      expect(cluster).not_to be_valid
    end

    it "rejects non-Hash JSONB shape" do
      cluster.lorenz_overrides_by_species = "not-a-hash"
      expect(cluster).not_to be_valid
    end

    it "rejects unknown keys per species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 2.0, "wat" => "??" }
      }
      expect(cluster).not_to be_valid
    end

    it "rejects non-numeric values" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => "abc" }
      }
      expect(cluster).not_to be_valid
    end

    it "allows partial overrides (e.g. only min)" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 6.0 }
      }
      expect(cluster).to be_valid
    end

    # [FW.8 · ⚖️ 2026-09-29] Лише ЗВУЖЕННЯ: ширша за заводську смуга — тихий
    # грошовий важіль, якого DCI не бачить. Кожна межа — окремо, бо оверрайд
    # частковий і відсутня межа не сміє прикривати присутню.
    it "rejects an override wider than the factory band, bound by bound" do
      cluster.lorenz_overrides_by_species = { "Pinus sylvestris" => { "min" => 1.5 } }
      expect(cluster).not_to be_valid
      expect(cluster.errors[:lorenz_overrides_by_species].join).to include("'min' must be >= 2.0")

      cluster.lorenz_overrides_by_species = { "Pinus sylvestris" => { "max" => 46.0 } }
      expect(cluster).not_to be_valid
      expect(cluster.errors[:lorenz_overrides_by_species].join).to include("'max' must be <= 45.0")

      cluster.lorenz_overrides_by_species = { "Pinus sylvestris" => { "min" => 2.0, "max" => 45.0 } }
      expect(cluster).to be_valid
    end
  end

  describe "Tree#effective_lorenz_thresholds (priority chain)" do
    let(:org) { create(:organization) }
    let(:pine) do
      create(:tree_family, scientific_name: "Pinus sylvestris",
                           critical_z_min: 5.0, critical_z_max: 40.0,
                           biological_properties: { "optimal_z_target" => 27.0 })
    end
    let(:oak) do
      create(:tree_family, scientific_name: "Quercus robur",
                           critical_z_min: 8.0, critical_z_max: 38.0,
                           biological_properties: { "optimal_z_target" => 24.0 })
    end

    it "returns global defaults when neither cluster nor family has overrides" do
      tree = Tree.new(did: "SNET-AAAA0001")
      expect(tree.effective_lorenz_thresholds).to eq(
        min: Tree::GLOBAL_LORENZ_Z_MIN,
        max: Tree::GLOBAL_LORENZ_Z_MAX,
        optimal: Tree::GLOBAL_LORENZ_Z_OPTIMAL
      )
    end

    it "uses tree_family values when cluster has no overrides" do
      cluster = create(:cluster, organization: org)
      tree = create(:tree, cluster: cluster, tree_family: pine)
      expect(tree.effective_lorenz_thresholds).to eq(min: 5.0, max: 40.0, optimal: 27.0)
    end

    it "cluster per-species override takes priority over tree_family" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0, "max" => 38.0, "optimal" => 30.0 }
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: pine)
      expect(tree.effective_lorenz_thresholds).to eq(min: 6.0, max: 38.0, optimal: 30.0)
    end

    it "[mixed-species cluster] each species resolves to its own overrides; others fall through" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0, "max" => 38.0, "optimal" => 30.0 }
                                     # No override for Quercus robur — uses family defaults
                                   }
                                 })
      pine_tree = create(:tree, cluster: cluster, tree_family: pine)
      oak_tree  = create(:tree, cluster: cluster, tree_family: oak)

      expect(pine_tree.effective_lorenz_thresholds).to eq(min: 6.0, max: 38.0, optimal: 30.0)
      expect(oak_tree.effective_lorenz_thresholds).to eq(min: 8.0, max: 38.0, optimal: 24.0)
    end

    it "partial cluster override falls through to family for missing fields" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0 } # only min
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: pine)
      expect(tree.effective_lorenz_thresholds).to eq(min: 6.0, max: 40.0, optimal: 27.0)
    end

    it "returns family defaults when family has no scientific_name (override lookup impossible)" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0 }
                                   }
                                 })
      family_no_name = create(:tree_family, scientific_name: nil,
                                            critical_z_min: 5.0, critical_z_max: 40.0)
      tree = create(:tree, cluster: cluster, tree_family: family_no_name)
      expect(tree.effective_lorenz_thresholds).to eq(min: 5.0, max: 40.0, optimal: 29.0)
    end
  end

  # [FW.17 · 03_05 §2.5] Тіло 0x9A — 8 Б; кадр навколо нього (CCM сесійним
  # ключем, DID, DLFC) пінує spec/services/downlink/command_frame_spec.rb.
  describe "OtaPackagerService.threshold_config_body" do
    subject(:body) { OtaPackagerService.threshold_config_body(tree, config_version: 7) }

    let(:org) { create(:organization) }
    let(:family) do
      create(:tree_family, :scots_pine, critical_z_min: 2.0, critical_z_max: 45.0,
                                        biological_properties: { "optimal_z_target" => 29.0,
                                                                 "scientific_name" => "Pinus sylvestris" })
    end

    let(:tree) do
      cluster = create(:cluster, organization: org)
      create(:tree, cluster: cluster, tree_family: family)
    end

    it "produces an 8-byte binary body — no len, no CRC: the MIC carries integrity" do
      expect(body).to be_a(String)
      expect(body.bytesize).to eq(8)
      expect(body.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "encodes thresholds as int16 little-endian × 100" do
      z_min, z_max, z_opt = body.unpack("s<s<s<")
      expect(z_min).to eq(200)   # 2.0 × 100
      expect(z_max).to eq(4500)  # 45.0 × 100
      expect(z_opt).to eq(2900)  # 29.0 × 100
    end

    it "encodes species_id from SPECIES_ID_MAP and config_version" do
      species_id = body.byteslice(6, 1).unpack1("C")
      version    = body.byteslice(7, 1).unpack1("C")
      expect(species_id).to eq(0) # Pinus sylvestris → 0
      expect(version).to eq(7)
    end

    it "applies cluster per-species overrides over family values" do
      tree.cluster.update!(environmental_settings: {
        "lorenz_overrides_by_species" => {
          "Pinus sylvestris" => { "min" => 2.5, "max" => 44.0, "optimal" => 30.5 }
        }
      })
      z_min, z_max, z_opt = OtaPackagerService.threshold_config_body(tree).unpack("s<s<s<")
      expect(z_min).to eq(250)
      expect(z_max).to eq(4400)
      expect(z_opt).to eq(3050)
    end

    it "uses 0xFF species_id for unmapped scientific_name" do
      family.update!(scientific_name: "Sequoiadendron giganteum")
      species_id = OtaPackagerService.threshold_config_body(tree).byteslice(6, 1).unpack1("C")
      expect(species_id).to eq(OtaPackagerService::DEFAULT_SPECIES_ID)
      expect(species_id).to eq(0xFF)
    end
  end

  describe "governance-ланцюг порогів (cluster override > family > global)" do
    let(:org) { create(:organization) }
    let(:family) do
      create(:tree_family, scientific_name: "Pinus sylvestris",
                           critical_z_min: 5.0, critical_z_max: 40.0)
    end

    # 🔴 [FW.8] ⛔ Не проганяти цей приклад через
    # `TelemetryUnpackerService#check_z_divergence!`: DCI цього ланцюга не
    # споживає, а приклад став би ВАКУУМНИМ, не червоним — глобальна стеля 45
    # пропускає Z=42 і без жодного override, тож він зеленів би й зі знятою
    # родиною, і зі знятим кластером, тобто перевіряв би власну фікстуру.
    # Предмет береться НАПРЯМУ: governance-ланцюг є твердженням про те, ЩО
    # СЛАТИ на пристрій, і живе рівно тут.
    it "honours the cluster per-species override over the family band" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0, "max" => 38.0 }
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: family)

      # Ліхтар проти повторної вакуумності: смуги мусять РОЗРІЗНЯТИСЬ, інакше
      # приклад нічого не судить.
      expect(family.critical_z_max).to eq(40.0)
      expect(tree.effective_lorenz_thresholds).to include(min: 6.0, max: 38.0)
    end

    # [FW.8 · ⚖️ 2026-09-29] DCI читає не ланцюг, а ОБЛІК видачі: поки смугу
    # не видано, пристрій судить заводською, і бажана смуга кандидатом не є.
    it "DCI цей ланцюг НЕ читає — до видачі кандидат лише заводська смуга [FW.8]" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 6.0, "max" => 38.0 }
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: family)

      expect(tree.device_lorenz_bands).to eq([ Tree::DEVICE_DEFAULT_LORENZ_BAND ])
      expect(tree.device_lorenz_bands).not_to include(tree.effective_lorenz_thresholds.slice(:min, :max))
    end
  end
end
