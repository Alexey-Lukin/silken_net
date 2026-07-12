# frozen_string_literal: true

require "rails_helper"

RSpec.describe Downlink::PendingQueueService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster, state: :idle) }
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  before { Rails.cache.clear }

  def decrypt_inner(envelope, key: key_record.binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc").decrypt
    cipher.key = key
    cipher.iv = envelope.byteslice(0, 16)
    cipher.padding = 0
    plain = cipher.update(envelope.byteslice(16, envelope.bytesize)) + cipher.final
    expect(plain.getbyte(0)).to eq(0x9C) # time-sync конверт завжди перший
    plain.byteslice(5, plain.bytesize)
  end

  def poll(query = {})
    described_class.poll_reply(gateway: gateway, query: query)
  end

  describe "порожня черга" do
    it "віддає time-only конверт (32 Б): кожен poll = RTC-sync Королеви" do
      envelope = poll

      expect(envelope.bytesize).to eq(32)
      expect(decrypt_inner(envelope).bytes).to all(eq(0))
    end

    it "без KEYC → nil (CoapGate відповість 4.04, Queen не почне decrypt)" do
      key_record.destroy!

      expect(poll).to be_nil
    end

    it "шифрує СТАРИМ ключем у Dual-Key Grace (Королева ще не підтвердила ротацію)" do
      key_record.update!(previous_aes_key_hex: "ee" * 32)

      envelope = poll

      expect { decrypt_inner(envelope, key: key_record.binary_previous_key) }.not_to raise_error
    end
  end

  describe "CMD (найпріоритетніший)" do
    let(:actuator) { create(:actuator, gateway: gateway) }
    let!(:command) { create(:actuator_command, actuator: actuator) }

    before { allow(ActuatorCommandWorker).to receive(:broadcast_command_state_static) }

    it "видає CMD-рядок у форматі воркера і проводить повний success-lifecycle" do
      inner = decrypt_inner(poll)

      expected = "CMD:#{command.command_payload}:#{command.duration_seconds}:" \
                 "#{command.actuator_id}:#{command.idempotency_token}"
      expect(inner.byteslice(0, expected.bytesize)).to eq(expected)

      command.reload
      expect(command.status).to eq("acknowledged")
      expect(actuator.reload.state).to eq("active")
      expect(ResetActuatorStateWorker.jobs.sole["args"]).to eq([ command.id ])
    end

    it "друга видача бере НАСТУПНУ команду (перша вже acknowledged)" do
      second = create(:actuator_command, actuator: actuator)

      first_inner = decrypt_inner(poll)
      second_inner = decrypt_inner(poll)

      expect(first_inner).to include(command.idempotency_token)
      expect(second_inner).to include(second.idempotency_token)
    end

    it "протермінована команда фейлиться і пропускається (не блокує чергу)" do
      command.update_columns(expires_at: 1.minute.ago)

      inner = decrypt_inner(poll)

      expect(inner.bytes).to all(eq(0))
      expect(command.reload.status).to eq("failed")
    end

    it "CMD понад стелю конверта Queen фейлиться гучно, не тихо ріжеться" do
      # command_payload text — валідацію обходимо update_columns, як робив би
      # майбутній ширший формат; стеля = MAX_ENVELOPE_BYTES (560).
      command.update_columns(command_payload: "A" * 600)

      inner = decrypt_inner(poll)

      expect(inner.bytes).to all(eq(0))
      expect(command.reload.status).to eq("failed")
      expect(command.error_message).to include("стелю")
    end

    it "чужа команда (інший gateway) не видається" do
      command.update!(actuator: create(:actuator, gateway: create(:gateway, cluster: cluster)))

      expect(decrypt_inner(poll).bytes).to all(eq(0))
    end
  end

  describe "0x9E ratchet (gated FW.17)" do
    let!(:tree) { create(:tree, cluster: cluster) }
    let!(:tree_key) do
      create(:hardware_key, :for_tree, tree: tree, key_version: 3,
             previous_aes_key_hex: "cd" * 16)
    end

    it "мовчить, поки FW17-гейт зачинений (той самий guard, що воркер)" do
      allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(false)

      expect(decrypt_inner(poll).bytes).to all(eq(0))
    end

    it "derivable з Dual-Key Grace: незавершена ротація → 0x9E(key_version)" do
      allow(HardwareKeyService).to receive(:ratchet_dispatch_enabled?).and_return(true)

      inner = decrypt_inner(poll)

      expected = OtaPackagerService.build_rotate_key_block(3)
      expect(inner.byteslice(0, expected.bytesize)).to eq(expected)
    end
  end

  describe "OTA-hint + chunk-server" do
    let(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

    before { gateway.update!(pending_firmware_id: firmware.id) }

    it "hint [0x9F][fw_id:4][total:2] + state=:updating з ota_started_at (ARCH.59-якір)" do
      inner = decrypt_inner(poll)

      expect(inner.getbyte(0)).to eq(0x9F)
      fw_id, total = inner.byteslice(1, 6).unpack("Nn")
      expect(fw_id).to eq(firmware.id)
      expect(total).to be > 0
      expect(gateway.reload.state).to eq("updating")
      expect(gateway.ota_started_at).to be_present
    end

    it "CMD пріоритетніший за OTA-hint" do
      actuator = create(:actuator, gateway: gateway)
      create(:actuator_command, actuator: actuator)
      allow(ActuatorCommandWorker).to receive(:broadcast_command_state_static)

      expect(decrypt_inner(poll).byteslice(0, 4)).to eq("CMD:")
    end

    it "chunk-server віддає чанк за (v, ch) і nil поза межами/на чужу версію" do
      packages = OtaPackagerService.prepare(
        firmware, chunk_size: OtaTransmissionWorker::CHUNK_SIZE, cluster_id: cluster.id
      )[:packages].to_a

      fetched = described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => "0" }
      )
      expect(decrypt_inner(fetched).byteslice(0, packages[0].bytesize)).to eq(packages[0])

      expect(described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => firmware.id.to_s, "ch" => packages.size.to_s }
      )).to be_nil
      expect(described_class.ota_chunk_reply(
        gateway: gateway, query: { "v" => (firmware.id + 99).to_s, "ch" => "0" }
      )).to be_nil
    end

    it "спостережене підтвердження: fw=<pending> глушить кампанію і ставить версію" do
      decrypt_inner(poll) # hint → updating

      poll({ "fw" => firmware.id.to_s })

      gateway.reload
      expect(gateway.pending_firmware_id).to be_nil
      expect(gateway.state).to eq("idle")
      expect(gateway.firmware_version).to eq(firmware.version)
    end

    it "fw=0 (ребут Королеви) НЕ глушить кампанію — hint повторюється (idempotent re-fetch)" do
      2.times { expect(decrypt_inner(poll({ "fw" => "0" })).getbyte(0)).to eq(0x9F) }

      expect(gateway.reload.pending_firmware_id).to eq(firmware.id)
    end
  end
end
