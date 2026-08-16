# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "securerandom"
require "openssl"

class HardwareKeyService
  include Auditable

  # Gateway CoAP channel (Queen ↔ Rails): AES-256-CBC.
  COAP_KEY_SIZE_BYTES = 32
  COAP_HKDF_INFO      = "silken-aes-256-device-key"

  # Tree LoRa channel (Soldier ↔ Queen): AES-128-CCM (post-ARCH.42 Variant B, 2026-05-23).
  # AES-128 = свідомий вибір ARCH.42, не SE-constraint (SE = SE050 — 03_05 §3.7).
  LORA_KEY_SIZE_BYTES = 16
  LORA_HKDF_INFO      = "silken-aes-128-lora-key"

  # [FW.2 гейт (в), двоключова модель] Cluster control-plane ключ (KEYB):
  # спільний AES-128 кластера для downlink-broadcast Королеви (OTA/beacon/
  # команди — один TX на всіх → один ключ by construction) + uplink 0x55/0x56.
  # Per-cluster з тієї ж причини, що K_ota (OtaHmacKeyService — broadcast за
  # визначенням; cluster = природна одиниця ізоляції). Соло-домен info-string;
  # ротація = re-provision (FW.17-ратчет цього ключа не торкається).
  # Прошивається: Tree → KEYB-слот (стор. 125), Gateway → її KEYL-слот
  # (Королева живе цим ключем як єдиним LoRa-ключем). Канон: 03_05 §2.1 (в).
  BROADCAST_KEY_SIZE_BYTES = 16
  BROADCAST_HKDF_INFO      = "silken-aes-128-broadcast-key"

  # Iotex W3bstream Ed25519 attestation seed (post-ARCH.42). Окремий 32-byte seed
  # для підпису telemetry attestation, derived через HKDF з різним info-string
  # для domain separation з AES (LoRa) та Lorenz K_seed. До ARCH.42 використовував
  # ту саму змінну, що AES-256 ключ (key-reuse антипаттерн, тепер виправлено).
  IOTEX_SEED_SIZE_BYTES = 32
  IOTEX_HKDF_INFO       = "silken-ed25519-iotex-v1"

  # Backwards-compat aliases (CoAP keys — поточний default до повного code-side rollout).
  KEY_SIZE_BYTES = COAP_KEY_SIZE_BYTES
  HKDF_INFO      = COAP_HKDF_INFO

  # Помилка подвійної ротації: пристрій ще не підтвердив попереднє оновлення ключа.
  class RotationPendingError < StandardError; end

  # [FW.17] Ratchet-ротація Tree-ключа замкнена, поки LoRa-downlink не
  # автентифікований (FW.2 CCM): підроблений 0x9E у ECB-флоті двигає версію
  # вперед → desync → вузол глухне. Дзеркало firmware FW17_RATCHET_ENABLED.
  class RatchetGateClosedError < StandardError; end

  # ENV-гейт диспатчу ратчет-ротації (default off — інертний шлях, 03_05 §3.8).
  FW17_GATE_ENV = "FW17_RATCHET_DOWNLINK_ENABLED"

  def self.ratchet_dispatch_enabled?
    ENV[FW17_GATE_ENV].to_s.downcase == "true"
  end

  # =========================================================================
  # ПРОВІЗІОНУВАННЯ (Zero-Trust Key Derivation, post-ARCH.42)
  # =========================================================================
  # [P0 BLOCKER FIX + ARCH.42]: Замість генерації випадкового ключа та передачі
  # через мережу, використовуємо HKDF (HMAC-based Key Derivation Function) для
  # деривації однакового AES ключа на обох сторонах (бекенд + прошивка).
  #
  # Post-ARCH.42 (2026-05-23, Variant B) — два різні info-strings за device type:
  #   • Tree   → derive_lora_key  (16 bytes, info "silken-aes-128-lora-key")
  #   • Gateway → derive_device_key (32 bytes, info "silken-aes-256-device-key")
  #
  # Обидві сторони знають:
  #   1. Master key: явний `master_key:` параметр (фабричний конвеєр несе
  #      його від FactoryFlashing::MasterKeySource — SEC.3 DI) або
  #      PROVISIONING_MASTER_KEY з env (runtime-fallback; прошивається при
  #      Factory Flashing)
  #   2. device_uid (унікальний серійник STM32)
  #
  # [SEC.11] Provisioning тепер також деривує Lorenz K_seed через
  # SilkenNet::SeedDerivation і зберігає його разом із AES ключем.
  # Метод повертає AES hex (для backwards-compat з існуючими callers);
  # K_seed читається з створеного `HardwareKey.lorenz_seed_hex`.
  #
  # Ключ НІКОЛИ не передається по мережі.
  def self.provision(device, master_key: nil)
    device_uid  = device.respond_to?(:did) ? device.did : device.uid
    new_hex_key = derive_key_for(device, master_key: master_key)
    lorenz_seed = SilkenNet::SeedDerivation.derive_seed(device_uid, master_key: master_key)

    HardwareKey.create!(
      device_uid: device_uid,
      aes_key_hex: new_hex_key,
      lorenz_seed_hex: lorenz_seed
    )

    new_hex_key
  end

  # Post-ARCH.42 (2026-05-23): обираємо derivation за device type.
  #   Tree    → LoRa AES-128 (16 bytes)
  #   Gateway → CoAP AES-256 (32 bytes)
  def self.derive_key_for(device, master_key: nil)
    device_uid = device.respond_to?(:did) ? device.did : device.uid
    if device.is_a?(Tree) || device.respond_to?(:did)
      derive_lora_key(device_uid, master_key: master_key)
    else
      derive_device_key(device_uid, master_key: master_key)
    end
  end

  # Tree LoRa AES-128 key — post-ARCH.42 Variant B (16 bytes).
  # HKDF info: "silken-aes-128-lora-key". AES-128 = вибір (SE = SE050 — 03_05 §3.7).
  def self.derive_lora_key(device_uid, master_key: nil)
    hkdf_derive(device_uid, info: LORA_HKDF_INFO, length: LORA_KEY_SIZE_BYTES, master_key: master_key)
  end

  # [FW.2 гейт (в)] Cluster control-plane ключ (KEYB) — salt-домен той самий,
  # що K_ota ("cluster:<id>"), info-string власний. Повертає 32-hex (16 байт).
  def self.derive_broadcast_key(cluster_id, master_key: nil)
    raise ArgumentError, "cluster_id is required" if cluster_id.blank?

    hkdf_derive("cluster:#{cluster_id}", info: BROADCAST_HKDF_INFO,
                length: BROADCAST_KEY_SIZE_BYTES, master_key: master_key)
  end

  # Iotex W3bstream Ed25519 seed (post-ARCH.42) — signed on EVERY uplink by
  # W3bstreamVerificationService (via IotexVerificationWorker, up to 5× on retry),
  # so each call re-touched the PROVISIONING_MASTER_KEY crown-jewel through HKDF.
  # [SEC.22] Memoize the ENV-path derivation in-process (mirror
  # HardwareKey#cached_binary_key): a cache hit touches no master key. Safe because
  # the ENV master key is boot-immutable — rotation = fleet re-flash + redeploy →
  # restart clears DERIVED_KEY_CACHE, so a cached seed never diverges from a fresh
  # one. An explicit master_key: (SEC.3 DI / factory) bypasses the cache — it must
  # not share the (info, uid) slot with a different root, and is never a hot path.
  # Returns 64-char HEX (32 bytes). Domain-separated from AES/Lorenz keys.
  def self.derive_iotex_seed(device_uid, master_key: nil)
    derive = -> { hkdf_derive(device_uid, info: IOTEX_HKDF_INFO, length: IOTEX_SEED_SIZE_BYTES, master_key: master_key) }
    return derive.call unless master_key.nil?

    DERIVED_KEY_CACHE.getset("#{IOTEX_HKDF_INFO}\x00#{device_uid}", &derive)
  end

  # Gateway CoAP AES-256 key — без змін після ARCH.42 (32 bytes).
  # HKDF info: "silken-aes-256-device-key". Зберігається у Queen Protected Flash.
  #
  # [SEC.11] Always requires a master key — the explicit `master_key:`
  # param (factory pipeline, SEC.3 DI), else the PROVISIONING_MASTER_KEY
  # ENV fallback; there is no SecureRandom fallback. Without it the
  # backend would generate values that do NOT match firmware HKDF
  # derivation → silent system breakage. Tests pin a stable value in
  # spec/rails_helper.rb.
  def self.derive_device_key(device_uid, master_key: nil)
    hkdf_derive(device_uid, info: COAP_HKDF_INFO, length: COAP_KEY_SIZE_BYTES, master_key: master_key)
  end

  # Private HKDF helper — shared by both LoRa та CoAP derivation paths.
  # `master_key:` = ключ від Session/MasterKeySource (SEC.3 DI); nil → ENV.
  def self.hkdf_derive(device_uid, info:, length:, master_key: nil)
    master_key ||= ENV["PROVISIONING_MASTER_KEY"]

    if master_key.blank?
      raise SecurityError,
            "PROVISIONING_MASTER_KEY ENV is required. Backend cannot derive " \
            "device AES key without it (would silently diverge from firmware " \
            "HKDF). See SEC.11 in docs/00_07_Action_Plan_Tracker.md."
    end

    derived = OpenSSL::KDF.hkdf(
      master_key,
      salt: device_uid.to_s,
      info: info,
      length: length,
      hash: "SHA256"
    )

    derived.unpack1("H*").upcase
  end
  private_class_method :hkdf_derive

  def self.rotate(device_uid)
    device = Tree.find_by(did: device_uid) || Gateway.find_by(uid: device_uid)
    raise "Пристрій #{device_uid} не знайдено" unless device

    new(device).rotate!
  end

  def initialize(device)
    @device = device
    @device_uid = device.respond_to?(:did) ? device.did : device.uid
  end

  # =========================================================================
  # РОТАЦІЯ (The Dual-Key Handshake)
  # =========================================================================
  # Два шляхи за типом пристрою:
  #   • Tree   → [FW.17] Hash-Ratchet: ключ НІКОЛИ не летить ефіром — backend
  #     деривує K_{v+1} (Cryptography::KeyRatchet, дзеркало key_ratchet.h),
  #     а в ефір іде лише `CMD_ROTATE_KEY 0x9E [target_version]`. Гейт:
  #     FW17_RATCHET_DOWNLINK_ENABLED (фліп після FW.2 CCM).
  #   • Gateway → випадковий новий CoAP AES-256 ключ; доставка = фізичний
  #     re-provision (SEC.3 Factory Flashing) — CoAP-downlink ключа не існує
  #     (legacy "sys/key_update" видалено: він не мав firmware-споживача і
  #     суперечив принципу §3.8 «ключ не летить ефіром»).
  # ACK обох шляхів — неявний Dual-Key Grace: перший uplink, що декриптнувся
  # новим ключем, → clear_grace_period!.
  def rotate!
    key_record = HardwareKey.find_by!(device_uid: @device_uid)

    # ⚡ [ЗАХИСТ ВІД ПОДВІЙНОЇ РОТАЦІЇ]: Якщо попередній ключ ще присутній,
    # це означає, що пристрій не підтвердив отримання нового ключа.
    # Повторна ротація затре old_key і ми назавжди втратимо доступ.
    if key_record.previous_aes_key_hex.present?
      raise RotationPendingError, "Ротація заблокована для #{@device_uid}: пристрій ще не підтвердив попередню ротацію. " \
            "Дочекайтесь першого пакету на новому ключі або очистіть Grace Period вручну."
    end

    new_hex_key = if @device.is_a?(Tree)
      rotate_tree_via_ratchet!(key_record)
    else
      rotate_gateway_random!(key_record)
    end

    # Audit-збій (Redis down на enqueue) не сміє валити ВЖЕ успішну ротацію:
    # retry впреться в RotationPendingError (guard вище), а не в подвійний advance.
    begin
      record_rotation_audit!(key_record)
    rescue StandardError => e
      Rails.logger.warn "📋 [ARCH.57] rotation-audit enqueue провалено для #{@device_uid}: #{e.message}"
    end

    new_hex_key
  end

  private

  # [ARCH.57] Ротація = привілейований security-акт → chain-only (archive: false —
  # key-метадані НЕ на публічний IPFS; сам ключ у metadata не потрапляє ніколи).
  # Пристрій без кластера → org=nil → глобальний ланцюг (свідомо: краще запис
  # у global-chain, ніж жодного).
  def record_rotation_audit!(key_record)
    record_audit_trail!(
      action: "hardware_key_rotated",
      organization_id: @device.cluster&.organization_id,
      auditable: key_record,
      metadata: {
        device_uid: @device_uid,
        device_type: @device.class.name,
        mode: @device.is_a?(Tree) ? "ratchet" : "random_reprovision",
        key_version: key_record.key_version
      }
    )
  end

  # [FW.17] Tree: один ратчет-крок вперед. Інкремент по одному — target у
  # кадрі абсолютний, тож пропущена команда доганяється наступною; стрибки
  # понад MAX_JUMP неможливі за побудовою.
  def rotate_tree_via_ratchet!(key_record)
    unless self.class.ratchet_dispatch_enabled?
      raise RatchetGateClosedError,
            "[FW.17] Ratchet-ротація #{@device_uid} відхилена: #{FW17_GATE_ENV} вимкнено. " \
            "ECB-downlink без MAC не сміє командувати ротацією — фліп після FW.2 CCM (03_05 §3.8)."
    end

    old_key = key_record.aes_key_hex
    target_version = key_record.key_version + 1
    new_hex_key = Cryptography::KeyRatchet.advance_hex(
      old_key,
      Cryptography::KeyRatchet.did_to_u32(@device_uid),
      from: key_record.key_version,
      to: target_version
    )

    # ⚡ [ARCH.59]: коміт БД-ротації, і ЛИШЕ потім enqueue 0x9E. Спільна
    # транзакція відкочувала ключ разом із версією — тобто в бік, якого тракт
    # лікувати НЕ вміє: без `previous_aes_key_hex` Grace-декрипту нема за що
    # вхопитись, вузол німіє, а Sidekiq бачив job ще до коміту (phantom-job).
    # Після коміту відмова падає в бік із backstop'ом: Grace-вікно робить
    # незавершену ротацію видимою `Downlink::PendingQueueService
    # #key_rotation_payload`, тож 0x9E добере наступний poll Королеви.
    # Виняток НЕ ковтаємо — кадр не поїхав, і повтор упреться в
    # RotationPendingError, а не в подвійний advance.
    key_record.update!(
      previous_aes_key_hex: old_key, # "Подушка безпеки" до першого uplink'а на K_{v+1}
      aes_key_hex: new_hex_key,
      key_version: target_version,
      rotated_at: Time.current
    )
    KeyRotationDownlinkWorker.perform_async(@device_uid, target_version)

    Rails.logger.warn "🔄 [FW.17] Ratchet-ротація #{@device_uid} → v#{target_version}. " \
                      "Старий ключ у Grace до першого пакета на новому."
    new_hex_key
  end

  # Gateway: випадковий ключ тієї самої довжини. Без downlink'а — новий ключ
  # доїжджає лише фізичним re-provision (SEC.3); до того часу Queen шле на
  # старому, і Grace-декрипт на бекенді тримає канал живим.
  def rotate_gateway_random!(key_record)
    old_key = key_record.aes_key_hex
    new_hex_key = SecureRandom.hex(old_key.length / 2).upcase

    key_record.update!(
      previous_aes_key_hex: old_key,
      aes_key_hex: new_hex_key,
      rotated_at: Time.current
    )

    Rails.logger.warn "🔄 [Zero-Trust] Ротація для #{@device_uid} активована. " \
                      "Старий ключ у Grace; доставка нового — re-provision (SEC.3)."
    new_hex_key
  end
end
