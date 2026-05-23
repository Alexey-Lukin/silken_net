# frozen_string_literal: true

require "securerandom"
require "openssl"

class HardwareKeyService
  # Gateway CoAP channel (Queen ↔ Rails): AES-256-CBC.
  COAP_KEY_SIZE_BYTES = 32
  COAP_HKDF_INFO      = "silken-aes-256-device-key"

  # Tree LoRa channel (Soldier ↔ Queen): AES-128-CCM (post-ARCH.42 Variant B, 2026-05-23).
  # Узгоджено з ATECC608B Secure Element apparatної AES-engine constraint.
  LORA_KEY_SIZE_BYTES = 16
  LORA_HKDF_INFO      = "silken-aes-128-lora-key"

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
  #   1. PROVISIONING_MASTER_KEY (встановлюється в env, прошивається при Factory Flashing)
  #   2. device_uid (унікальний серійник STM32)
  #
  # [SEC.11] Provisioning тепер також деривує Lorenz K_seed через
  # SilkenNet::SeedDerivation і зберігає його разом із AES ключем.
  # Метод повертає AES hex (для backwards-compat з існуючими callers);
  # K_seed читається з створеного `HardwareKey.lorenz_seed_hex`.
  #
  # Ключ НІКОЛИ не передається по мережі.
  def self.provision(device)
    device_uid  = device.respond_to?(:did) ? device.did : device.uid
    new_hex_key = derive_key_for(device)
    lorenz_seed = SilkenNet::SeedDerivation.derive_seed(device_uid)

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
  def self.derive_key_for(device)
    device_uid = device.respond_to?(:did) ? device.did : device.uid
    if device.is_a?(Tree) || device.respond_to?(:did)
      derive_lora_key(device_uid)
    else
      derive_device_key(device_uid)
    end
  end

  # Tree LoRa AES-128 key — post-ARCH.42 Variant B (16 bytes).
  # HKDF info: "silken-aes-128-lora-key". Узгоджено з ATECC608B SE Slot 0.
  def self.derive_lora_key(device_uid)
    hkdf_derive(device_uid, info: LORA_HKDF_INFO, length: LORA_KEY_SIZE_BYTES)
  end

  # Iotex W3bstream Ed25519 seed (post-ARCH.42) — derived on-demand для signature
  # attestation. Returns 64-char HEX (32 bytes). Domain-separated from AES/Lorenz keys.
  def self.derive_iotex_seed(device_uid)
    hkdf_derive(device_uid, info: IOTEX_HKDF_INFO, length: IOTEX_SEED_SIZE_BYTES)
  end

  # Gateway CoAP AES-256 key — без змін після ARCH.42 (32 bytes).
  # HKDF info: "silken-aes-256-device-key". Зберігається у Queen Protected Flash.
  #
  # [SEC.11] Always requires PROVISIONING_MASTER_KEY — there is no
  # SecureRandom fallback. Without master_key the backend would generate
  # values that do NOT match firmware HKDF derivation → silent system
  # breakage. Tests pin a stable value in spec/rails_helper.rb.
  def self.derive_device_key(device_uid)
    hkdf_derive(device_uid, info: COAP_HKDF_INFO, length: COAP_KEY_SIZE_BYTES)
  end

  # Private HKDF helper — shared by both LoRa та CoAP derivation paths.
  def self.hkdf_derive(device_uid, info:, length:)
    master_key = ENV["PROVISIONING_MASTER_KEY"]

    if master_key.blank?
      raise SecurityError,
            "PROVISIONING_MASTER_KEY ENV is required. Backend cannot derive " \
            "device AES key without it (would silently diverge from firmware " \
            "HKDF). See SEC.11 in docs/00_08_Action_Plan_Tracker.md."
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
  def rotate!
    key_record = HardwareKey.find_by!(device_uid: @device_uid)

    # ⚡ [ЗАХИСТ ВІД ПОДВІЙНОЇ РОТАЦІЇ]: Якщо попередній ключ ще присутній,
    # це означає, що пристрій не підтвердив отримання нового ключа.
    # Повторна ротація затре old_key і ми назавжди втратимо доступ.
    if key_record.previous_aes_key_hex.present?
      raise RotationPendingError, "Ротація заблокована для #{@device_uid}: пристрій ще не підтвердив попередню ротацію. " \
            "Дочекайтесь першого пакету на новому ключі або очистіть Grace Period вручну."
    end

    # ⚡ [ЗАГАРТУВАННЯ]: Зберігаємо поточний ключ як попередній.
    # Post-ARCH.42 (2026-05-23): rotate генерує ключ ТОЇ САМОЇ довжини, що поточний
    # (Tree LoRa AES-128 = 16 bytes / 32 hex; Gateway CoAP AES-256 = 32 bytes / 64 hex).
    old_key = key_record.aes_key_hex
    byte_len = old_key.length / 2  # 16 для Tree LoRa, 32 для Gateway CoAP
    new_hex_key = SecureRandom.hex(byte_len).upcase

    # ⚡ [АТОМАРНІСТЬ]: Оновлення БД та постановка Downlink в чергу відбуваються
    # в одній транзакції. Якщо Redis/Sidekiq недоступний — транзакція відкочується,
    # і ключ у базі залишається незмінним.
    HardwareKey.transaction do
      key_record.update!(
        previous_aes_key_hex: old_key, # "Подушка безпеки"
        aes_key_hex: new_hex_key,
        rotated_at: Time.current
      )

      # Надсилаємо Downlink ВСЕРЕДИНІ транзакції.
      # ВАЖЛИВО: цей пакет має бути зашифрований OLD_KEY,
      # бо дерево ще не знає про NEW_KEY!
      trigger_key_update_downlink(new_hex_key, old_key)
    end

    Rails.logger.warn "🔄 [Zero-Trust] Ротація для #{@device_uid} активована. Старий ключ збережено як резервний."
    new_hex_key
  end

  private

  def trigger_key_update_downlink(new_key_hex, encryption_key)
    return unless @device.respond_to?(:ip_address) || @device.respond_to?(:gateway)
    target_ip = @device.respond_to?(:ip_address) ? @device.ip_address : @device.gateway.ip_address

    # Формуємо команду для STM32.
    # Воркер має використати 'encryption_key' для шифрування цієї команди.
    ActuatorCommandWorker.perform_async(
      @device_uid,
      "sys/key_update",
      { key: new_key_hex }.to_json,
      { use_key: encryption_key } # Передаємо конкретний ключ для цього завдання
    )
  end
end
