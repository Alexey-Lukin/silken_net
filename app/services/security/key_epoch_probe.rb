# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Security
  # [FW.17 · docs/06_06 §5.8] DR після відкату БД із бекапу. Рядок `HardwareKey`
  # відстає від пристрою двома способами, і обидва тихі:
  #
  #   • епоха/версія — дерево, re-provision-нуте чи ротоване після точки бекапу,
  #     тримає ключ, якого рядок не знає: кожен кадр падає на MIC обома ключами
  #     (03_05 §3.8), алерту немає — лише лічильник MIC-фейлів;
  #   • DLFC — пристрій уже прийняв лічильники, яких бекап не бачив: команду з
  #     меншим Солдат відкидає, а кадр ротації, що перевидається ТИМ САМИМ
  #     кадром, не відкриється ніколи (03_05 §2.5).
  #
  # `probe` пробним розшифруванням захопленого кадру знаходить пару (епоха,
  # версія), яку тримає вузол: епохи й версії — малі цілі, перебір дешевий, а
  # MIC під знайденим ключем — криптографічний доказ, тож `repair!` безпечний.
  # Ключ процесу не покидає (CLAUDE §6): назовні — лише числа (e, v).
  module KeyEpochProbe
    extend Auditable

    AIR_FRAME_LEN    = 30 # [DID:4][gossip:1][FC:3][CT:14][MIC:8] — кадр в ефірі
    BATCH_RECORD_LEN = 31 # [DID:4][RSSI:1] + решта ефірного — запис батча Королеви (лог MIC-фейлу)
    DLFC_MAX         = 0xFFFF_FFFF

    Finding = Data.define(:device_uid, :epoch, :key_version)

    module_function

    # frame_hex — 30 Б ефіру або 31 Б запису батча. nil — жодна пара не відкрила.
    def probe(frame_hex, ahead: 4, max_version: 16, master_key: nil)
      frame = parse(frame_hex)
      key_record = HardwareKey.find_by!(device_uid: frame[:device_uid])
      (key_record.epoch..(key_record.epoch + ahead)).each do |epoch|
        each_version_key(frame[:device_uid], epoch, max_version, master_key) do |version, key_hex|
          return Finding.new(device_uid: frame[:device_uid], epoch: epoch, key_version: version) if opens?(frame, key_hex)
        end
      end
      nil
    end

    # Рядок → знайдена пара. Grace закривається: MIC уже довів, що вузол тримає
    # саме цей ключ, а попередній рядка — ключ давнішої, ніж вузол, точки.
    def repair!(finding, master_key: nil)
      key_record = HardwareKey.find_by!(device_uid: finding.device_uid)
      key_hex = key_hex_for(finding.device_uid, finding.epoch, finding.key_version, master_key)
      key_record.update!(epoch: finding.epoch, key_version: finding.key_version,
                         aes_key_hex: key_hex, previous_aes_key_hex: nil, rotated_at: Time.current)
      record_audit_trail!(
        action: "hardware_key_recovered",
        # Ключ без власника наш писач не створює (has_one … dependent: :destroy);
        # дерево без кластера — законний стан (optional), тоді глобальний ланцюг.
        organization_id: key_record.owner.cluster&.organization_id,
        auditable: key_record,
        metadata: { device_uid: key_record.device_uid, epoch: finding.epoch, key_version: finding.key_version }
      )
      key_record
    end

    # DLFC кожного дерева + margin (стеля u32). margin мусить перевищити число
    # команд, виданих після точки бекапу, і лишитись < 65 536 над останнім
    # прийнятим пристроєм — інакше реконструкція з 16 біт ефіру схибить.
    def bump_downlink_frame_counters!(margin:, device_uid: nil)
      raise ArgumentError, "margin мусить бути в 1..65535" unless margin.is_a?(Integer) && (1..0xFFFF).cover?(margin)

      # Підзапит, не joins: UPDATE … FROM робить назву колонки в SET двозначною.
      scope = HardwareKey.where(device_uid: Tree.select(:did))
      scope = scope.where(device_uid: device_uid) if device_uid
      scope.update_all([ "downlink_frame_counter = LEAST(downlink_frame_counter + ?, ?)", margin, DLFC_MAX ])
    end

    def parse(frame_hex)
      bytes = [ frame_hex.to_s.delete(" ") ].pack("H*")
      offset = case bytes.bytesize
      when AIR_FRAME_LEN    then 4
      when BATCH_RECORD_LEN then 5
      else raise ArgumentError, "кадр мусить мати #{AIR_FRAME_LEN} (ефір) або #{BATCH_RECORD_LEN} (запис батча) байт"
      end
      {
        device_uid:    format("SNET-%08X", bytes.byteslice(0, 4).unpack1("N")),
        did_bytes:     bytes.byteslice(0, 4),
        gossip_ts_lsb: bytes.getbyte(offset),
        frame_counter: ("\x00".b + bytes.byteslice(offset + 1, 3)).unpack1("N"),
        ciphertext:    bytes.byteslice(offset + 4, Cryptography::LoraCcm::PLAINTEXT_LEN),
        mic:           bytes.byteslice(offset + 4 + Cryptography::LoraCcm::PLAINTEXT_LEN, Cryptography::LoraCcm::TAG_LEN)
      }
    end

    def opens?(frame, key_hex)
      Cryptography::LoraCcm.decrypt(key: [ key_hex ].pack("H*"), **frame.except(:device_uid))
      true
    rescue Cryptography::LoraCcm::AuthError
      false
    end

    # K0 епохи, далі по одному кроку ратчета: advance_hex відмовляє стрибку
    # понад MAX_JUMP, тож крокуємо самі.
    def each_version_key(device_uid, epoch, max_version, master_key)
      did = Cryptography::KeyRatchet.did_to_u32(device_uid)
      key_hex = HardwareKeyService.derive_lora_key(device_uid, epoch: epoch, master_key: master_key)
      (0..max_version).each do |version|
        key_hex = Cryptography::KeyRatchet.next_key_hex(key_hex, did) if version.positive?
        yield version, key_hex
      end
    end

    def key_hex_for(device_uid, epoch, key_version, master_key)
      each_version_key(device_uid, epoch, key_version, master_key) do |version, key_hex|
        return key_hex if version == key_version
      end
    end
    private_class_method :parse, :opens?, :each_version_key, :key_hex_for
  end
end
