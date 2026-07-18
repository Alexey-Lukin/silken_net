# frozen_string_literal: true

# [SEC.21 L1] Device-event 0x57 — рідкісні security-події з вузла (canary-trip),
# що не є станом і не влазять у телеметрію. Королева ДЕКРИПТУЄ LoRa-кадр (щоб
# упізнати), витягує cleartext-поля і форвардить їх під ВЛАСНИМ Ed25519-підписом
# (рунг L1 драбини довіри — той самий EDSK/механізм, що QATT-батч). Rails
# верифікує gateway-origin проти Королевиного `HardwareKey.ed25519_public_key_hex`
# (той самий registry, що QATT + M2M-auth) — LoRa-ключа НЕ торкається (Rails
# per-Tree LoRa-ключа не має ні в ECB-, ні в CCM-ері by design).
#
# Trust L1-observational: подія НІКОЛИ не рухає money-path — лише ops-алерт
# (slash-виключення дзеркалять firmware_fault). Per-event device-підпис фізично
# неможливий (64B у 16B кадр, 05_02 trust-ladder) → L1 Queen-attest = правильний рівень
# назавжди. Wire-дім: firmware/common/device_event.h (§Шар 2), канон 03_05 §2.2а.
#
# Anti-replay: SHA256(Королевин sig) SETNX — кожен Королевин flush несе свіжий
# підпис (свіжий unix_ts+count), тож справжня повторна канарка НЕ глушиться
# (на відміну від Солдатового per-boot seq). Дедуп реальних подій = EwsAlert
# uniqueness [tree,type,status] (один активний canary/дерево).
class DeviceEventWorker
  include Sidekiq::Worker
  sidekiq_options queue: "uplink", retry: 2

  DEVENV_VERSION    = 0x01
  DEVENV_HEADER_LEN = 6   # [ver:1][queen_unix_ts:4][count:1]
  DEVENV_RECORD_LEN = 7   # [did:4][code:1][soldier_seq:2]
  DEVENV_SIG_LEN    = 64
  DEVENV_DOMAIN_TAG = "SLKN-QEVT1".b.freeze
  EVT_CANARY_TRIP   = 0x02
  NONCE_TTL         = 25.hours
  NONCE_PREFIX      = "silken:devevt:nonce"

  def perform(encoded_payload, gateway_uid)
    payload = Base64.strict_decode64(encoded_payload)
    return if payload.bytesize < DEVENV_HEADER_LEN + DEVENV_SIG_LEN
    return unless payload.getbyte(0) == DEVENV_VERSION

    gateway = Gateway.find_by(uid: gateway_uid.to_s.strip.upcase)
    return unless gateway

    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    return if key_record&.ed25519_public_key_hex.blank?

    sig  = payload.byteslice(-DEVENV_SIG_LEN, DEVENV_SIG_LEN)
    body = payload.byteslice(0, payload.bytesize - DEVENV_SIG_LEN)
    return unless verify_signature(gateway, key_record, sig, body)
    return if replayed?(sig)

    dispatch_records(body, gateway)
  rescue ArgumentError => e
    Rails.logger.warn "🛑 [SEC.21] Корупція Base64 device-event від #{gateway_uid.inspect}: #{e.message}"
  rescue Ed25519Crypto::SigningService::SigningError => e
    # Malformed ЗБЕРЕЖЕНИЙ pubkey (misprovisioning) — не drop-crash, лише лог
    Rails.logger.warn "🛑 [SEC.21] Битий gateway-pubkey #{gateway_uid.inspect}: #{e.message}"
  end

  private

  # L1 gateway-origin: підпис над "SLKN-QEVT1"‖uid_len‖uid‖body (дзеркало
  # прошивки device_event.h §Шар 2). verify контрольовано повертає false на
  # невалідний підпис (ловить Ed25519::VerifyError усередині) — не raise.
  def verify_signature(gateway, key_record, sig, body)
    uid = gateway.uid.to_s
    message = DEVENV_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body
    Ed25519Crypto::SigningService.verify(
      key_record.ed25519_public_key_hex, sig.unpack1("H*"), message
    )
  end

  # Anti-replay/crash-retry: той самий Королевин підпис двічі → skip.
  def replayed?(signature)
    digest = Digest::SHA256.hexdigest(signature)
    !Rails.cache.write("#{NONCE_PREFIX}:#{digest}", "1",
                       expires_in: NONCE_TTL, unless_exist: true)
  end

  def dispatch_records(body, gateway)
    count = body.getbyte(5)
    records = body.byteslice(DEVENV_HEADER_LEN, count * DEVENV_RECORD_LEN)
    # count з ПІДПИСАНОГО body довірений, але межа — захисно (битий count не
    # виведе за буфер).
    return unless records && records.bytesize == count * DEVENV_RECORD_LEN

    records.each_char.each_slice(DEVENV_RECORD_LEN) do |rec|
      r = rec.join
      dispatch_one(r[0, 4].unpack1("N"), r.getbyte(4), r[5, 2].unpack1("n"), gateway)
    end
  end

  def dispatch_one(did, code, seq, gateway)
    hex_did = format("SNET-%08X", did)
    tree = Tree.find_by(did: hex_did)
    unless tree
      Rails.logger.warn "🛡️ [SEC.21] device-event від невідомого DID #{hex_did} (gw #{gateway.uid})"
      return
    end

    # [SEC.21] Дерево мусить бути в ЕФІРІ саме цієї Королеви (її кластер).
    # L1-підпис доводить gateway-origin, але НЕ per-tree (оператор контролює
    # Королеву — 05_02 ladder): без цього guard'а Королева A підняла б
    # investor-facing critical-алерт на дереві ЧУЖОГО кластера (ops-spoof + FUD).
    # `.present?` теж відсіює cluster-less дерева — інакше `cluster: nil`-алерт
    # завалив би `AlertNotificationWorker` (cluster.organization на nil).
    unless tree.cluster_id.present? && tree.cluster_id == gateway.cluster_id
      Rails.logger.warn "🛡️ [SEC.21] device-event DID #{hex_did} поза кластером Королеви #{gateway.uid} — дроп (ops-spoof guard)"
      return
    end

    case code
    when EVT_CANARY_TRIP
      EwsAlert.create!(
        cluster: tree.cluster, tree: tree, severity: :critical,
        alert_type: :firmware_canary_trip, status: :active,
        message: "🐦 КАНАРКА: __stack_chk_fail на вузлі (переписаний кадр стека — " \
                 "потенційна атака на LoRa/AT-парсер; вузол перевтілився сам). " \
                 "DID: #{hex_did}, seq: #{seq}"
      )
    else
      # Невідомий/зарезервований код (0x01 baseline-revert їде state-report'ом)
      Rails.logger.warn "🛡️ [SEC.21] device-event code=#{code} від #{hex_did} — без обробника (реєстр device_event.h)"
    end
  rescue ActiveRecord::RecordInvalid
    # uniqueness [tree_id, alert_type, status] — активний алерт уже висить
    nil
  end
end
