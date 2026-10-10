# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ota::DeploymentDispatcherService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:firmware) { create(:bio_contract_firmware) }

  # ⚖️ [FW.66 S4] Гард ери читає останній пульс КОЖНОГО шлюзу когорти, і без пульсу відмовляє —
  # тож шлюз цієї спеки народжується з пульсом. Фабрика контракту — ECB, тож дефолтний пульс теж.
  def queen(ccm: false, **attrs)
    create(:gateway, **attrs).tap { |gw| pulse!(gw, ccm: ccm) }
  end

  def pulse!(gateway, ccm: false, at: Time.current)
    create(:gateway_telemetry_log, gateway: gateway, created_at: at,
                                   health_flags: ccm ? GatewayTelemetryLog::HFLAG_CCM_ERA : 0)
  end

  def call_service(cluster_id: cluster.id, canary_percentage: 100, fw: firmware)
    described_class.call(
      firmware: fw,
      organization: organization,
      cluster_id: cluster_id,
      canary_percentage: canary_percentage
    )
  end


  describe "per-gateway targeting (FW.60 poll-тракт)" do
    let!(:gateways) { Array.new(2) { queen(cluster: cluster) } }

    it "persists pending_firmware_id per eligible gateway and never push-enqueues" do
      result = call_service

      expect(result.dispatched_gateways).to eq(2)
      gateways.each do |gw|
        expect(gw.reload.pending_firmware_id).to eq(firmware.id)
      end
      # [FW.60] push-fan-out superseded: доставку тягне Королева через poll.
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

    # [FW.60 · SEC.22] coap, що віддаватиме чанки, master-key не має і сам не
    # пакує — тож пакунки кампанії мусять лежати готовими до першого poll'а.
    it "packages the campaign for the coap reader in the process that holds the key" do
      call_service

      expect(Ota::PackageStore.read(firmware.id, cluster.id)).to eq(
        OtaPackagerService.prepare(firmware, chunk_size: OtaChunkable::CHUNK_SIZE,
                                             cluster_id: cluster.id)[:packages].to_a
      )
    end

    it "burns nothing when packaging fails — the same version stays dispatchable" do
      allow(OtaSealKeyService).to receive(:signing_key_for)
        .and_raise(SecurityError, "PROVISIONING_MASTER_KEY ENV is required")

      expect { call_service }.to raise_error(SecurityError)
      expect(cluster.reload.ota_version_hiwater).to eq(0)
      gateways.each { |gw| expect(gw.reload.pending_firmware_id).to be_nil }
    end
  end

  describe "anti-rollback guard (Rails mirror of Soldier Flash-KV 0x15, strictly >)" do
    let!(:gateway) { queen(cluster: cluster) }

    it "skips a cluster whose hiwater already reached firmware.id" do
      cluster.update!(ota_version_hiwater: firmware.id)

      result = call_service

      expect(result.dispatched?).to be(false)
      expect(result.skipped_clusters.map(&:reason)).to eq([ "rollback" ])
      expect(firmware.reload.is_active).to be(false)
    end

    it "burns the slot at dispatch: re-issuing the SAME firmware is rejected (fix = new record)" do
      expect(call_service.dispatched?).to be(true)

      second = call_service

      expect(second.dispatched?).to be(false)
      expect(second.skipped_clusters.map(&:reason)).to eq([ "rollback" ])
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
      queen(cluster: cluster, ip_address: nil)
      queen(cluster: cluster, state: :maintenance)
      queen(cluster: cluster, state: :faulty)
      queen(cluster: cluster, state: :updating)
      eligible = queen(cluster: cluster, state: :idle)

      result = call_service

      expect(result.dispatched_gateways).to eq(1)
      expect(eligible.reload.pending_firmware_id).to eq(firmware.id)
      expect(Gateway.where.not(id: eligible.id).pluck(:pending_firmware_id)).to all(be_nil)
    end

    it "does NOT burn hiwater for a cluster with zero eligible gateways" do
      queen(cluster: cluster, ip_address: nil)

      result = call_service

      expect(result.dispatched?).to be(false)
      expect(result.skipped_clusters.map(&:reason)).to eq([ "no_gateways" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
      expect(firmware.reload.is_active).to be(false)
    end
  end

  describe "canary cohort (per-cluster, stable first-N-by-id)" do
    let!(:gateways) { Array.new(4) { queen(cluster: cluster) } }

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
    let!(:gateway) { queen(cluster: cluster) }
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

    # [FW.67] 2 КБ влазить у стелю Королеви (4 CoAP-чанки), але не в ota_buffer Солдата
    # (183 LoRa-чанки > 93) — збирання стало б на 93, і кампанія палила б hiwater даремно.
    it "rejects a campaign that fits the Queen but not the Soldier assembly ceiling" do
      too_big_for_soldier = create(:bio_contract_firmware, bytecode_payload: "01" * 2_000)
      result = call_service(fw: too_big_for_soldier)

      expect(result.skipped_clusters.map(&:reason)).to eq([ "oversized_firmware" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
    end

    # [FW.67] Стеля перезапиту 0x55 (72 чанки) — гейт, а не лише пін: у рої чанк понад неї,
    # пропущений першим проходом, не добирається, і збирання стає, хоч `ota_buffer` (93) його вмістив би.
    it "rejects a campaign that fits ota_buffer but not the 0x55 re-request bitmap" do
      past_rerequest = create(:bio_contract_firmware, bytecode_payload: "01" * 800) # 73 LoRa-чанки
      queen(cluster: cluster)

      expect(call_service(fw: past_rerequest).skipped_clusters.map(&:reason)).to eq([ "oversized_firmware" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
    end

    # ⚖️ [FW.66 S4 · FW.67] Справжній контракт CCM-ери мусить вкладатися в УСІ стелі OTA без
    # підйому — інакше ратифікована драбина FW.67 вимагає підняти ту стелю тією ж ревізією
    # (00_07 FW.67). Байткод і стелю бітмапи перезапиту 0x55 пін читає з прошивки.
    it "fits the real CCM-era contract under the Queen, Soldier and 0x55 re-request ceilings" do
      header = Rails.root.join("firmware/common/ccm_bytecode.h").read
      hex = header[header.index("{")..header.rindex("}")].scan(/0x(\h{2})/).join
      rereq = Rails.root.join("firmware/common/ota_rerequest_wire.h").read
      rereq_cap = rereq[/#define OTA_REQ_BITMAP_MAX_BYTES\s+(\d+)u/, 1].to_i * 8
      ccm = create(:bio_contract_firmware, bytecode_payload: hex, wire_era: "ccm")

      manifest = OtaPackagerService.prepare(ccm, chunk_size: OtaChunkable::CHUNK_SIZE)[:manifest]

      expect(rereq_cap).to eq(described_class::SOLDIER_REREQUEST_MAX_CHUNKS)
      expect(manifest[:lora_total_chunks]).to be <= rereq_cap
      expect(manifest[:lora_total_chunks]).to be <= described_class::SOLDIER_MAX_LORA_CHUNKS
      expect(manifest[:total_chunks]).to be <= described_class::QUEEN_MAX_BYTECODE_CHUNKS
    end

    it "mirrors the Soldier's ota_buffer — the ceiling is read off firmware/soldier/main.c" do
      soldier = Rails.root.join("firmware/soldier/main.c").read

      expect(soldier).to match(/^uint8_t ota_buffer\[#{described_class::SOLDIER_OTA_BUFFER_BYTES}\];/)
      expect(described_class::SOLDIER_MAX_LORA_CHUNKS).to eq(93)
    end
  end

  # ⚖️ [FW.66 S4, 2026-10-10 — врізка 03_04 §7.3] Контракт чужої ери на вузлі — три vm_error,
  # відкат і спалена версія; гард судить когорту ДО спалення hiwater.
  describe "wire-era guard (contract era ⟷ the cohort's Queen pulse)" do
    let(:ccm_firmware) { create(:bio_contract_firmware, wire_era: "ccm") }

    it "rejects an era mismatch before burning hiwater or targeting anyone" do
      gw = queen(cluster: cluster) # ECB-пульс

      result = call_service(fw: ccm_firmware)

      expect(result.skipped_clusters.map(&:reason)).to eq([ "wire_era_mismatch" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
      expect(gw.reload.pending_firmware_id).to be_nil
    end

    it "fails closed on a Queen that has sent no pulse yet" do
      create(:gateway, cluster: cluster)

      expect(call_service.skipped_clusters.map(&:reason)).to eq([ "no_era_pulse" ])
      expect(cluster.reload.ota_version_hiwater).to eq(0)
    end

    it "dispatches a CCM contract to a CCM cohort" do
      queen(cluster: cluster, ccm: true)

      expect(call_service(fw: ccm_firmware).dispatched_gateways).to eq(1)
    end

    it "reads the era from the LATEST pulse (a Queen flipped to CCM is CCM)" do
      gw = create(:gateway, cluster: cluster)
      pulse!(gw, at: 2.hours.ago)
      pulse!(gw, ccm: true, at: 1.hour.ago)

      expect(call_service(fw: ccm_firmware).dispatched_gateways).to eq(1)
    end

    it "asks a pulse only of the canary cohort, not of the gateways it leaves out" do
      first = queen(cluster: cluster)
      create(:gateway, cluster: cluster) # поза когортою 25 % і без пульсу

      result = call_service(canary_percentage: 25)

      expect(result.dispatched_gateways).to eq(1)
      expect(first.reload.pending_firmware_id).to eq(firmware.id)
    end

    # Печатка й KEYB — на кластер: кампанію чує кожен Солдат, що чує будь-яку Королеву когорти.
    it "refuses on a mismatch anywhere in the cluster, even outside the canary cohort" do
      queen(cluster: cluster)              # у когорті 25 % — ECB, як контракт
      queen(cluster: cluster, ccm: true)   # поза когортою — CCM

      expect(call_service(canary_percentage: 25).skipped_clusters.map(&:reason)).to eq([ "wire_era_mismatch" ])
    end

    # Пульс пишеться лише з підписаного конверта, а `last_seen_at` рухає кожен батч.
    it "treats a pulse older than the liveness window before last_seen_at as no pulse" do
      gw = create(:gateway, cluster: cluster)
      pulse!(gw, at: (Gateway::LIVENESS_WINDOW_S + 3600).seconds.ago)
      gw.update_column(:last_seen_at, Time.current)

      expect(call_service.skipped_clusters.map(&:reason)).to eq([ "no_era_pulse" ])
    end
  end

  describe "targeting scope" do
    it "whole-forest (nil cluster_id) covers every org cluster but never foreign orgs" do
      second_cluster = create(:cluster, organization: organization)
      queen(cluster: cluster)
      queen(cluster: second_cluster)
      foreign_cluster = create(:cluster) # інша організація
      queen(cluster: foreign_cluster)

      result = call_service(cluster_id: nil)

      expect(result.dispatched_gateways).to eq(2)
      expect(foreign_cluster.reload.ota_version_hiwater).to eq(0)
    end

    it "mixed forest: stale cluster skipped, fresh cluster dispatched" do
      stale = create(:cluster, organization: organization, ota_version_hiwater: firmware.id)
      queen(cluster: stale)
      queen(cluster: cluster)

      result = call_service(cluster_id: nil)

      expect(result.dispatched?).to be(true)
      expect(result.dispatched_gateways).to eq(1)
      expect(result.skipped_clusters.map(&:id)).to eq([ stale.id ])
    end
  end
end
