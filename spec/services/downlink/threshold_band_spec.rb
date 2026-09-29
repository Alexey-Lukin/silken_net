# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.8 · ⚖️ founder 2026-09-29, 03_04 §5.3] Облік смуги Лоренца на пристрої.
# Кадр в очікуваннях збирається НЕЗАЛЕЖНО, прямо примітивом CCM: виклик того
# самого `CommandFrame` був би тавтологією.
RSpec.describe Downlink::ThresholdBand do
  let(:cluster) { create(:cluster) }
  let(:family) { create(:tree_family, critical_z_min: 5.0, critical_z_max: 40.0) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: family) }
  let!(:key) { create(:hardware_key, :for_tree, tree: tree) }
  let(:now) { Time.current.change(usec: 0) }

  let(:default_band) { Tree::DEVICE_DEFAULT_LORENZ_BAND }
  let(:narrow_band) { { min: 5.0, max: 40.0 } }
  # Родина 5.0/40.0, оптимум за замовчуванням 29.0, вид без відображення, версія 1.
  let(:narrow_body) { body(500, 4000) }

  def body(z_min, z_max) = [ z_min, z_max, 2900, 0xFF, 1 ].pack("s<s<s<CC")

  def sealed(body, dlfc, key_hex: key.reload.aes_key_hex)
    Cryptography::LoraCcm.encrypt_downlink(
      key: [ key_hex ].pack("H*"), opcode: 0x9A,
      did_bytes: [ Cryptography::KeyRatchet.did_to_u32(tree.did) ].pack("N"), dlfc: dlfc, body: body
    )
  end

  def serve(at) = described_class.serve!(tree, now: at)

  def evidence(at, &) = described_class.record_evidence!(tree, received_at: at, &)

  describe ".dispatch_enabled?" do
    it "reads the ENV mirror of FW8_PARSER_ENABLED, off by default" do
      stub_const("ENV", ENV.to_h.except(described_class::GATE_ENV))
      expect(described_class.dispatch_enabled?).to be(false)

      stub_const("ENV", ENV.to_h.merge(described_class::GATE_ENV => "TRUE"))
      expect(described_class.dispatch_enabled?).to be(true)
    end
  end

  describe ".serve!" do
    it "issues the desired band once: one DLFC, the recorded body, the sealed frame" do
      expect(serve(now)).to eq(sealed(narrow_body, 1))

      tree.reload
      expect(tree.lorenz_band_pending).to eq(narrow_body)
      expect([ tree.lorenz_band_dlfc, tree.lorenz_band_key_epoch ]).to eq([ 1, 0 ])
      expect([ tree.lorenz_band_issued_at, tree.lorenz_band_served_at ]).to eq([ now, now ])
      expect(key.reload.downlink_frame_counter).to eq(1)
    end

    it "stays silent while the device already holds the desired band" do
      family.update!(critical_z_min: 2.0, critical_z_max: 45.0)

      expect(serve(now)).to be_nil
      expect(key.reload.downlink_frame_counter).to eq(0)
    end

    # Перевидача — ТОЙ САМИЙ кадр: Королева лише освіжає бюджет пострілів, а
    # Солдат на повторі Flash-KV не палить (скіл `backend` #9).
    it "re-serves the SAME frame after the reserve interval — never a new DLFC" do
      first = serve(now)

      expect(serve(now + 1.hour)).to be_nil
      expect(serve(now + described_class::RESERVE_INTERVAL)).to eq(first)
      expect(key.reload.downlink_frame_counter).to eq(1)
      expect(tree.reload.lorenz_band_served_at).to eq(now + described_class::RESERVE_INTERVAL)
    end

    it "re-issues under a new DLFC once the counter moved from under the issuance" do
      serve(now)
      key.update!(downlink_frame_counter: 5) # DR-підйом чи пізніша команда

      expect(serve(now + described_class::RESERVE_INTERVAL)).to eq(sealed(narrow_body, 6))
      expect(tree.reload.lorenz_band_dlfc).to eq(6)
    end

    # 🔴 Re-provision обнуляє DLFC у новій епосі, тож лічильник МОЖЕ знову дійти до
    # числа видачі. Перевидача тоді запечатала б під новим ключем DLFC, який уже
    # мав інше тіло, — повтор нонса CCM. Ловить це лише епоха.
    it "re-issues after a re-provision even when the counter climbed back to the same number" do
      serve(now)
      fresh = SecureRandom.hex(16).upcase
      key.update!(epoch: 1, aes_key_hex: fresh, downlink_frame_counter: 1)

      expect(serve(now + described_class::RESERVE_INTERVAL)).to eq(sealed(narrow_body, 2, key_hex: fresh))
      expect(tree.reload.lorenz_band_key_epoch).to eq(1)
    end

    it "waits out an open grace — only 0x9E rides it" do
      key.update!(previous_aes_key_hex: SecureRandom.hex(16).upcase)

      expect(serve(now)).to be_nil
      expect(key.reload.downlink_frame_counter).to eq(0)
    end

    it "treats a grace opened mid-issuance as a wait, and writes nothing" do
      allow(tree).to receive(:hardware_key).and_return(key)
      allow(key).to receive(:issue_downlink_frame_counter!).and_raise(Downlink::CommandFrame::GraceOpenError)

      expect(serve(now)).to be_nil
      expect(tree.reload.lorenz_band_pending).to be_nil
    end

    it "is silent for a tree without a key — there is nothing to seal with" do
      key.destroy!
      expect(described_class.serve!(tree.reload, now: now)).to be_nil
    end

    # Кадр першої видачі міг долетіти раніше за новий — тоді пристрій тримає саме
    # його, і DCI мусить його бачити, інакше чесний пакет став би фродом.
    it "supersedes an unproven issuance and keeps its band a DCI candidate" do
      serve(now)
      family.update!(critical_z_min: 6.0)

      expect(serve(now + 1.minute)).to eq(sealed(body(600, 4000), 2))
      expect(tree.reload.lorenz_band_held).to eq([ [ 500, 4000 ] ])
      expect(tree.device_lorenz_bands).to eq([ default_band, narrow_band, { min: 6.0, max: 40.0 } ])
    end

    context "with the narrowing guard (⚖️ 2026-09-29)" do
      it "refuses a band wider than the factory one, even when the row bypassed validation" do
        family.update_columns(critical_z_min: 1.5)

        expect(serve(now)).to be_nil
        expect(key.reload.downlink_frame_counter).to eq(0)
      end

      it "refuses a band the quantization collapses — the device's Valid would reject it" do
        family.update!(critical_z_min: 39.998, critical_z_max: 40.0, optimal_z_target: 39.999)

        expect(serve(now)).to be_nil
      end
    end
  end

  describe ".record_evidence!" do
    before { serve(now) }

    it "learns nothing from a packet that rules out no candidate" do
      evidence(now + 1.hour) { true }

      expect(tree.reload.lorenz_band_pending).to eq(narrow_body)
      expect(tree.lorenz_band_held).to eq([])
    end

    it "promotes the issuance the status confirms ALONE, and closes its own field audit" do
      alert = EwsAlert.escalate_field_audit!(cluster: cluster, tree: tree,
                                             message_key: described_class::FIELD_AUDIT_KEY,
                                             message_params: { did: tree.did })

      evidence(now + 1.hour) { |band| band == narrow_band }

      tree.reload
      expect(tree.lorenz_band_held).to eq([ [ 500, 4000 ] ])
      expect(tree.lorenz_band_pending).to be_nil
      expect([ tree.lorenz_band_dlfc, tree.lorenz_band_issued_at, tree.lorenz_band_served_at ]).to all(be_nil)
      expect(alert.reload).to be_status_resolved
      expect(serve(now + 2.days)).to be_nil # пристрій тримає бажану смугу
    end

    # Кандидатів ТРИ свідомо: із двома збіг з обома не відкидає жодного, і пін був
    # би вакуумним — код виходить раніше, ніж доходить до рішення (виміряно
    # мутацією «доводь, щойно видана серед збігів», 2026-09-29).
    it "does not promote while the status also fits another candidate — but drops the one it rules out" do
      family.update!(critical_z_min: 6.0)
      serve(now + 1.minute) # held [5.0/40.0] + видача 6.0/40.0
      superseding = { min: 6.0, max: 40.0 }

      evidence(now + 1.hour) { |band| [ superseding, default_band ].include?(band) }

      expect(tree.reload.lorenz_band_pending).to eq(body(600, 4000))
      expect(tree.lorenz_band_held).to eq([])
    end

    it "drops a held band the status rules out — and the next poll re-issues it" do
      evidence(now + 1.hour) { |band| band == narrow_band }

      evidence(now + 2.hours) { |band| band == default_band } # re-provision / порвана пара

      expect(tree.reload.lorenz_band_held).to eq([])
      expect(serve(now + 3.hours)).to eq(sealed(narrow_body, 2))
    end

    it "counts no old-band evidence inside the delivery window" do
      evidence(now + 1.hour) { |band| band == default_band }

      expect(tree.reload.lorenz_band_stale_count).to eq(0)
      expect(tree.lorenz_band_served_at).to eq(now)
    end

    it "counts old-band evidence after the window, lifts the re-serve pause, escalates on the third" do
      after_window = now + described_class::DELIVERY_WINDOW
      2.times { evidence(after_window) { |band| band == default_band } }

      expect(tree.reload.lorenz_band_stale_count).to eq(2)
      expect(tree.lorenz_band_served_at).to be_nil
      expect(tree.ews_alerts.alert_type_field_audit).to be_empty

      evidence(after_window) { |band| band == default_band }

      alert = tree.ews_alerts.alert_type_field_audit.sole
      expect(alert.message_key).to eq(described_class::FIELD_AUDIT_KEY)
      expect(alert.message_params).to include("did" => tree.did, "stale_packets" => 3)
      expect(alert.message).to include(tree.did)
    end

    it "gives a tree without a cluster no alert — nobody would see it" do
      tree.update_columns(cluster_id: nil)
      3.times { evidence(now + described_class::DELIVERY_WINDOW) { |band| band == default_band } }

      expect(tree.reload.lorenz_band_stale_count).to eq(3)
      expect(EwsAlert.where(tree: tree)).to be_empty
    end
  end
end
