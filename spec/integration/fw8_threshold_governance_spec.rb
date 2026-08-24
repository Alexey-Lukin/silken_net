# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.8] End-to-end coverage of cluster-configurable Lorenz thresholds via governance.
# Verifies the full chain: Cluster overrides → TreeFamily defaults → Tree.effective_lorenz_thresholds
# → TelemetryUnpackerService divergence check → OtaPackagerService.build_threshold_config_block.
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
        "Pinus sylvestris" => { "min" => 1.5, "max" => 46.0, "optimal" => 30.0 }
      }
      expect(cluster.lorenz_overrides_for("Pinus sylvestris"))
        .to eq(min: 1.5, max: 46.0, optimal: 30.0)
    end

    it "returns all-nil hash for an unconfigured species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 1.5 }
      }
      expect(cluster.lorenz_overrides_for("Quercus robur"))
        .to eq(min: nil, max: nil, optimal: nil)
    end

    it "supports mixed-species clusters with different overrides per species" do
      cluster.lorenz_overrides_by_species = {
        "Pinus sylvestris" => { "min" => 1.5, "max" => 46.0 },
        "Quercus robur"    => { "min" => 4.0, "max" => 40.0, "optimal" => 25.0 }
      }
      expect(cluster.lorenz_overrides_for("Pinus sylvestris"))
        .to eq(min: 1.5, max: 46.0, optimal: nil)
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
        "Pinus sylvestris" => { "min" => 1.5 }
      }
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
                                     "Pinus sylvestris" => { "min" => 1.5, "max" => 46.0, "optimal" => 30.0 }
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: pine)
      expect(tree.effective_lorenz_thresholds).to eq(min: 1.5, max: 46.0, optimal: 30.0)
    end

    it "[mixed-species cluster] each species resolves to its own overrides; others fall through" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 1.5, "max" => 46.0, "optimal" => 30.0 }
                                     # No override for Quercus robur — uses family defaults
                                   }
                                 })
      pine_tree = create(:tree, cluster: cluster, tree_family: pine)
      oak_tree  = create(:tree, cluster: cluster, tree_family: oak)

      expect(pine_tree.effective_lorenz_thresholds).to eq(min: 1.5, max: 46.0, optimal: 30.0)
      expect(oak_tree.effective_lorenz_thresholds).to eq(min: 8.0, max: 38.0, optimal: 24.0)
    end

    it "partial cluster override falls through to family for missing fields" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 1.5 } # only min
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: pine)
      expect(tree.effective_lorenz_thresholds).to eq(min: 1.5, max: 40.0, optimal: 27.0)
    end

    it "returns family defaults when family has no scientific_name (override lookup impossible)" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 1.5 }
                                   }
                                 })
      family_no_name = create(:tree_family, scientific_name: nil,
                                            critical_z_min: 5.0, critical_z_max: 40.0)
      tree = create(:tree, cluster: cluster, tree_family: family_no_name)
      expect(tree.effective_lorenz_thresholds).to eq(min: 5.0, max: 40.0, optimal: 29.0)
    end
  end

  describe "OtaPackagerService.build_threshold_config_block" do
    subject(:block) { OtaPackagerService.build_threshold_config_block(tree, config_version: 7) }

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

    it "produces a 13-byte binary string" do
      expect(block).to be_a(String)
      expect(block.bytesize).to eq(13)
      expect(block.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "starts with CMD_SET_THRESHOLDS marker (0x9A)" do
      expect(block.bytes.first).to eq(OtaPackagerService::CMD_SET_THRESHOLDS)
      expect(OtaPackagerService::CMD_SET_THRESHOLDS).to eq(0x9A)
    end

    it "encodes payload length 10 as little-endian uint16" do
      payload_len = block.byteslice(1, 2).unpack1("v")
      expect(payload_len).to eq(10)
    end

    it "encodes thresholds as int16 little-endian × 100" do
      payload = block.byteslice(3, 10)
      z_min, z_max, z_opt = payload.unpack("s<s<s<")
      expect(z_min).to eq(200)   # 2.0 × 100
      expect(z_max).to eq(4500)  # 45.0 × 100
      expect(z_opt).to eq(2900)  # 29.0 × 100
    end

    it "encodes species_id from SPECIES_ID_MAP and config_version" do
      payload = block.byteslice(3, 10)
      species_id = payload.byteslice(6, 1).unpack1("C")
      version    = payload.byteslice(7, 1).unpack1("C")
      expect(species_id).to eq(0) # Pinus sylvestris → 0
      expect(version).to eq(7)
    end

    it "appends a valid CRC16-CCITT (XMODEM) over payload bytes 0..7" do
      payload = block.byteslice(3, 10)
      body = payload.byteslice(0, 8)
      stored_crc = payload.byteslice(8, 2).unpack1("v")
      expect(stored_crc).to eq(OtaPackagerService.crc16_ccitt(body))
    end

    it "applies cluster per-species overrides over family values" do
      tree.cluster.update!(environmental_settings: {
        "lorenz_overrides_by_species" => {
          "Pinus sylvestris" => { "min" => 1.5, "max" => 46.0, "optimal" => 30.5 }
        }
      })
      payload = OtaPackagerService.build_threshold_config_block(tree).byteslice(3, 10)
      z_min, z_max, z_opt = payload.unpack("s<s<s<")
      expect(z_min).to eq(150)
      expect(z_max).to eq(4600)
      expect(z_opt).to eq(3050)
    end

    it "uses 0xFF species_id for unmapped scientific_name" do
      family.update!(scientific_name: "Sequoiadendron giganteum")
      payload = OtaPackagerService.build_threshold_config_block(tree).byteslice(3, 10)
      species_id = payload.byteslice(6, 1).unpack1("C")
      expect(species_id).to eq(OtaPackagerService::DEFAULT_SPECIES_ID)
      expect(species_id).to eq(0xFF)
    end
  end

  describe "TelemetryUnpackerService Z divergence with cluster per-species override" do
    let(:org) { create(:organization) }
    let(:family) do
      create(:tree_family, scientific_name: "Pinus sylvestris",
                           critical_z_min: 5.0, critical_z_max: 40.0)
    end

    # ⚠️ Назва свідомо НЕ згадує `TreeFamily#healthy_z?` — цей приклад його не
    # кличе й кликати не може: предикат родини кластерних override-ів не бачить.
    # Судить тут `Tree#effective_lorenz_thresholds`, і саме його споживає сервіс.
    it "honours the cluster per-species override over the family band" do
      cluster = create(:cluster, organization: org,
                                 environmental_settings: {
                                   "lorenz_overrides_by_species" => {
                                     "Pinus sylvestris" => { "min" => 1.0, "max" => 50.0 }
                                   }
                                 })
      tree = create(:tree, cluster: cluster, tree_family: family)
      service = TelemetryUnpackerService.new("")

      # Z=42 would be unhealthy under family bounds (5..40) but healthy under cluster bounds (1..50)
      attrs = { z_value: 42.0, bio_status: :homeostasis }
      expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
      service.send(:check_z_divergence!, tree, attrs)
    end
  end
end
