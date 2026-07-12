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

  describe "fan-out per gateway" do
    let!(:gateways) { create_list(:gateway, 2, cluster: cluster) }

    it "enqueues one OtaTransmissionWorker per eligible gateway with the WORKER's signature" do
      result = call_service

      expect(result.dispatched_gateways).to eq(2)
      expect(OtaTransmissionWorker.jobs.size).to eq(2)
      enqueued_args = OtaTransmissionWorker.jobs.map { |j| j["args"] }
      gateways.each do |gw|
        expect(enqueued_args).to include([ gw.uid, "firmware", firmware.id, 0, 0 ])
      end
    end

    it "burns the cluster hiwater to firmware.id on dispatch" do
      expect { call_service }.to change { cluster.reload.ota_version_hiwater }.from(0).to(firmware.id)
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
      expect(OtaTransmissionWorker.jobs.sole["args"].first).to eq(eligible.uid)
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
      expect(OtaTransmissionWorker.jobs.sole["args"].first).to eq(gateways.min_by(&:id).uid)
    end

    it "rounds up so a small cluster still gets at least one gateway" do
      result = call_service(canary_percentage: 30) # 4 * 0.3 = 1.2 → 2

      expect(result.dispatched_gateways).to eq(2)
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
