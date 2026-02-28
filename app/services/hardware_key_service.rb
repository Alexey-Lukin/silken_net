# frozen_string_literal: true

require "securerandom"

class HardwareKeyService
  # Довжина ключа для AES-256
  KEY_SIZE = 32 

  def self.provision(device, manual_key = nil)
    new(device).provision(manual_key)
  end

  def self.rotate(device_uid)
    key = HardwareKey.find_by!(device_uid: device_uid)
    new(key.device_identity).rotate!
  end

  def initialize(device)
    @device = device
    @device_uid = device.respond_to?(:did) ? device.did : device.uid
  end

  # =========================================================================
  # 1. ПРОПИСКА (Key Minting)
  # =========================================================================
  def provision(manual_key = nil)
    # Якщо ключ не передано (напр. при монтажі через мобільний додаток),
    # генеруємо нову порцію ентропії.
    raw_key = manual_key || SecureRandom.random_bytes(KEY_SIZE)

    HardwareKey.transaction do
      # Видаляємо старий ключ, якщо він був (перевстановлення)
      HardwareKey.where(device_uid: @device_uid).destroy_all

      HardwareKey.create!(
        device_uid: @device_uid,
        binary_key: raw_key,
        key_type: :aes_256_ecb,
        status: :active
      )
    end

    Rails.logger.info "🔐 [Zero-Trust] Сформовано новий якір для пристрою #{@device_uid}."
    raw_key
  end

  # =========================================================================
  # 2. РОТАЦІЯ (Entropy Refresh)
  # =========================================================================
  def rotate!
    new_key = SecureRandom.random_bytes(KEY_SIZE)
    
    key_record = HardwareKey.find_by!(device_uid: @device_uid)
    key_record.update!(binary_key: new_key, rotated_at: Time.current)

    # ПЛАН: Тут ми маємо ініціювати Downlink-команду через CoAP,
    # щоб дерево дізналося про свій новий ключ.
    # CoapClient.put(@device.gateway.ip_address, "key_update", new_key)

    Rails.logger.warn "🔄 [Zero-Trust] Ключ пристрою #{@device_uid} ротовано."
    new_key
  end

  # =========================================================================
  # 3. ВАЛІДАЦІЯ (Handshake)
  # =========================================================================
  def self.fetch_binary_key(device_uid)
    # Отримуємо ключ безпосередньо для TelemetryUnpackerService.
    # Нагадаю: у моделі HardwareKey поле binary_key МАЄ бути зашифрованим (Rails 7+ encrypts).
    HardwareKey.find_by(device_uid: device_uid, status: :active)&.binary_key
  end
end
