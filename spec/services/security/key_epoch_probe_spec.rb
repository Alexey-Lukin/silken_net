# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.17 · docs/06_06 §5.8] DR ключів дерев після відкату БД: рядок відстає від
# пристрою епохою чи версією ратчета, і кожен кадр падає на MIC обома ключами.
RSpec.describe Security::KeyEpochProbe, type: :service do
  let(:master) { "dr-probe-master" }
  let(:tree) { create(:tree) }
  let!(:key_record) { create(:hardware_key, :for_tree, tree: tree) }
  let(:did_u32) { Cryptography::KeyRatchet.did_to_u32(tree.did) }

  # Ключ, який вузол справді тримає: K0 епохи, просунутий ратчетом на version кроків.
  def device_key_hex(epoch:, version:)
    key = HardwareKeyService.derive_lora_key(tree.did, epoch: epoch, master_key: master)
    version.times { key = Cryptography::KeyRatchet.next_key_hex(key, did_u32) }
    key
  end

  # Запис батча, як його друкує лог MIC-фейлу: [DID][RSSI][gossip][FC24][CT][MIC].
  def captured_record(key_hex, fc: 77, gossip: 0x11)
    ct, mic = Cryptography::LoraCcm.encrypt(key: [ key_hex ].pack("H*"), did_bytes: [ did_u32 ].pack("N"),
                                            frame_counter: fc, gossip_ts_lsb: gossip, plaintext: "\x01".b * 14)
    ([ did_u32 ].pack("N") + [ 0x42, gossip ].pack("CC") + [ fc ].pack("N").byteslice(1, 3) + ct + mic).unpack1("H*")
  end

  describe ".probe" do
    it "finds the newer epoch a tree was re-provisioned into after the backup point" do
      finding = described_class.probe(captured_record(device_key_hex(epoch: 2, version: 0)), master_key: master)
      expect(finding).to have_attributes(device_uid: tree.did, epoch: 2, key_version: 0)
    end

    it "finds ratchet versions the restored row lost within the same epoch" do
      finding = described_class.probe(captured_record(device_key_hex(epoch: 0, version: 3)), master_key: master)
      expect(finding).to have_attributes(epoch: 0, key_version: 3)
    end

    it "reads the 30-byte air frame as well as the 31-byte batch record" do
      record = [ captured_record(device_key_hex(epoch: 1, version: 1)) ].pack("H*")
      air = record.byteslice(0, 4) + record.byteslice(5..)
      expect(described_class.probe(air.unpack1("H*"), master_key: master)).to have_attributes(epoch: 1, key_version: 1)
    end

    it "returns nil when no candidate key opens the frame" do
      expect(described_class.probe(captured_record(SecureRandom.hex(16).upcase), master_key: master)).to be_nil
    end

    it "refuses a record of neither the air nor the batch length" do
      expect { described_class.probe("00" * 29, master_key: master) }.to raise_error(ArgumentError, /30.*31/)
    end

    it "stays inside the declared window — an epoch past AHEAD is not claimed" do
      expect(described_class.probe(captured_record(device_key_hex(epoch: 5, version: 0)), ahead: 4, master_key: master))
        .to be_nil
    end
  end

  describe ".repair!" do
    it "moves the row onto the proven key, closes the grace and audits the act without key material" do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silkennet.com",
                                  first_name: "Oracle", last_name: "Executioner")
      key_record.update!(previous_aes_key_hex: "CD" * 16)
      finding = described_class::Finding.new(device_uid: tree.did, epoch: 2, key_version: 1)

      expect { described_class.repair!(finding, master_key: master) }.to change { AuditLogWorker.jobs.size }.by(1)

      expect(key_record.reload).to have_attributes(epoch: 2, key_version: 1, previous_aes_key_hex: nil,
                                                   aes_key_hex: device_key_hex(epoch: 2, version: 1))
      attrs = AuditLogWorker.jobs.last["args"].first
      expect(attrs["action"]).to eq("hardware_key_recovered")
      expect(attrs["metadata"].values.join).not_to include(key_record.aes_key_hex)
    end
  end

  describe ".repair! for a tree without a cluster" do
    it "still repairs, writing the act into the global chain" do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silkennet.com",
                                  first_name: "Oracle", last_name: "Executioner")
      tree.update!(cluster: nil)
      finding = described_class::Finding.new(device_uid: tree.did, epoch: 1, key_version: 0)

      described_class.repair!(finding, master_key: master)

      expect(key_record.reload.epoch).to eq(1)
      expect(AuditLogWorker.jobs.last["args"].first["organization_id"]).to be_nil
    end
  end

  describe ".bump_downlink_frame_counters!" do
    it "raises every tree row by the margin, caps at u32 and leaves Queens alone" do
      key_record.update!(downlink_frame_counter: 10)
      near_ceiling = create(:hardware_key, :for_tree, downlink_frame_counter: 0xFFFF_FFF0)
      queen = create(:hardware_key, :for_gateway)

      described_class.bump_downlink_frame_counters!(margin: 1024)

      expect(key_record.reload.downlink_frame_counter).to eq(1034)
      expect(near_ceiling.reload.downlink_frame_counter).to eq(0xFFFF_FFFF)
      expect(queen.reload.downlink_frame_counter).to eq(0)
    end

    it "raises a single tree when DID is named" do
      other = create(:hardware_key, :for_tree, downlink_frame_counter: 3)

      described_class.bump_downlink_frame_counters!(margin: 100, device_uid: tree.did)

      expect(key_record.reload.downlink_frame_counter).to eq(100)
      expect(other.reload.downlink_frame_counter).to eq(3)
    end

    it "refuses a margin the Soldier's 16-bit reconstruction could not bridge" do
      expect { described_class.bump_downlink_frame_counters!(margin: 65_536) }.to raise_error(ArgumentError, /1\.\.65535/)
    end
  end
end
