# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ota::DeploymentDispatcherService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:firmware) { create(:bio_contract_firmware) }

  def call_service(cluster_id: cluster.id, canary_percentage: 100, fw: firmware)
    described_class.call(
      firmware: fw,
      organization: organization,
      cluster_id: cluster_id,
      canary_percentage: canary_percentage
    )
  end

  before { OtaTransmissionWorker.clear }

  describe "per-gateway targeting (FW.60 poll-тракт)" do
    let!(:gateways) { create_list(:gateway, 2, cluster: cluster) }

    it "persists pending_firmware_id per eligible gateway and never push-enqueues" do
      result = call_service

      expect(result.dispatched_gateways).to eq(2)
      gateways.each do |gw|
        expect(gw.reload.pending_firmware_id).to eq(firmware.id)
      end
      # [FW.60] push-fan-out superseded: доставку тягне Королева через poll.
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "burns the cluster hiwater to firmware.id on dispatch" do
      expect { call_service }.to change { cluster.reload.ota_version_hiwater }.from(0).to(firmware.id)
    end

    # [ARCH.59] Якір ставиться при ТАРГЕТИНГУ, не на першому hint'і — інакше
    # шлюз, якому hint не пішов ЖОДНОГО разу, лишається з `ota_started_at IS
    # NULL`, і третя нога `GatewayStalenessSweepWorker#stuck_ota_scope` не
    # бачить його за побудовою (її часова межа не матчить NULL).
    it "stamps the campaign anchor so an unannounced target can age out" do
      call_service

      gateways.each do |gw|
        expect(gw.reload.ota_started_at).to be_present
      end
    end

    it "activates the firmware (feeds latest_tree_firmware_id / mismatch detection)" do
      call_service(canary_percentage: 25)

      firmware.reload
      expect(firmware.is_active).to be(true)
      expect(firmware.rollout_percentage).to eq(25)
    end
  end

  describe "anti-rollback guard (Rails mirror of Soldier Flash-KV 0x15, strictly >)" do
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "skips a cluster whose hiwater already reached firmware.id" do
      cluster.update!(ota_version_hiwater: firmware.id)

      result = call_service

      expect(result.dispatched?).to be(false)
      expect(result.skipped_clusters.map(&:reason)).to eq([ "rollback" ])
      expect(OtaTransmissionWorker.jobs).to be_empty
      expect(firmware.reload.is_active).to be(false)
    end

    it "burns the slot at dispatch: re-issuing the SAME firmware is rejected (fix = new record)" do
      expect(call_service.dispatched?).to be(true)

      OtaTransmissionWorker.clear
      second = call_service

      expect(second.dispatched?).to be(false)
      expect(second.skipped_clusters.map(&:reason)).to eq([ "rollback" ])
      expect(OtaTransmissionWorker.jobs).to be_empty
    end

    it "does not lower hiwater when a newer campaign already passed" do
      firmware # матеріалізуємо лінивий let ПЕРШИМ — newer мусить мати БІЛЬШИЙ id
      newer = create(:bio_contract_firmware)
      cluster.update!(ota_version_hiwater: newer.id)

      call_service

      expect(cluster.reload.ota_version_hiwater).to eq(newer.id)
    end
  end

  describe "eligibility filter" do
    it "skips gateways without ip_address, in maintenance/faulty/updating" do
      create(:gateway, cluster: cluster, ip_address: nil)
      create(:gateway, cluster: cluster, state: :maintenance)
      create(:gateway, cluster: cluster, state: :faulty)
      create(:gateway, cluster: cluster, state: :updating)
      eligible = create(:gateway, cluster: cluster, state: :idle)

      result = call_service

      expect(result.dispatched_gateways).to eq(1)
      expect(eligible.reload.pending_firmware_id).to eq(firmware.id)
      expect(Gateway.where.not(id: eligible.id).pluck(:pending_firmware_id)).to all(be_nil)
    end

    it "does NOT burn hiwater for a cluster with zero eligible gateways" do
      create(:gateway, cluster: cluster, ip_address: nil)

      result = call_service

      expect(result.dispatched?).to be(false)
      expect(result.skipped_clusters.map(&:reason)).to eq([ "no_gateways" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
      expect(firmware.reload.is_active).to be(false)
    end
  end

  describe "canary cohort (per-cluster, stable first-N-by-id)" do
    let!(:gateways) { create_list(:gateway, 4, cluster: cluster) }

    it "takes ceil(count * pct / 100) gateways, lowest ids first" do
      result = call_service(canary_percentage: 25)

      expect(result.dispatched_gateways).to eq(1)
      expect(gateways.min_by(&:id).reload.pending_firmware_id).to eq(firmware.id)
      expect(gateways.max_by(&:id).reload.pending_firmware_id).to be_nil
    end

    it "rounds up so a small cluster still gets at least one gateway" do
      result = call_service(canary_percentage: 30) # 4 * 0.3 = 1.2 → 2

      expect(result.dispatched_gateways).to eq(2)
    end
  end

  describe "oversized-firmware gate (FW.60 — дзеркало Queen OTA_MAX_CHUNKS=16)" do
    let!(:gateway) { create(:gateway, cluster: cluster) }
    let(:oversized) { create(:bio_contract_firmware, bytecode_payload: "01" * 9_000) } # 9 КБ binary ≥ 18 чанків

    it "rejects the campaign BEFORE burning hiwater or targeting gateways" do
      result = call_service(fw: oversized)

      expect(result.dispatched?).to be(false)
      expect(result.skipped_clusters.map(&:reason)).to eq([ "oversized_firmware" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
      expect(gateway.reload.pending_firmware_id).to be_nil
      expect(oversized.reload.is_active).to be(false)
    end

    it "passes a firmware that fits the 16-chunk assembly ceiling" do
      expect(call_service.dispatched?).to be(true)
    end
  end

  describe "targeting scope" do
    it "whole-forest (nil cluster_id) covers every org cluster but never foreign orgs" do
      second_cluster = create(:cluster, organization: organization)
      create(:gateway, cluster: cluster)
      create(:gateway, cluster: second_cluster)
      foreign_cluster = create(:cluster) # інша організація
      create(:gateway, cluster: foreign_cluster)

      result = call_service(cluster_id: nil)

      expect(result.dispatched_gateways).to eq(2)
      expect(foreign_cluster.reload.ota_version_hiwater).to eq(0)
    end

    it "mixed forest: stale cluster skipped, fresh cluster dispatched" do
      stale = create(:cluster, organization: organization, ota_version_hiwater: firmware.id)
      create(:gateway, cluster: stale)
      create(:gateway, cluster: cluster)

      result = call_service(cluster_id: nil)

      expect(result.dispatched?).to be(true)
      expect(result.dispatched_gateways).to eq(1)
      expect(result.skipped_clusters.map(&:id)).to eq([ stale.id ])
    end
  end
end
