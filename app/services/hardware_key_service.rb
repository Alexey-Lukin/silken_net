# frozen_string_literal: true

require "securerandom"

class HardwareKeyService
  # 32 байти = 256 біт для AES-256
  KEY_SIZE_BYTES = 32 

  def self.provision(device, manual_key_hex = nil)
    new(device).provision(manual_key_hex)
  end

  def self.rotate(device_uid)
    # Знаходимо пристрій (Солдата або Королеву)
    device = Tree.find_by(did: device_uid) || Gateway.find_by(uid: device_uid)
    raise "Пристрій #{device_uid} не знайдено" unless device

    new(device).rotate!
  end

  def initialize(device)
    @device = device
    @device_uid = device.respond_to?(:did) ? device.did : device.uid
  end

  # =========================================================================
  # 1. ПРОПИСКА (The Initial Handshake)
  # =========================================================================
  def provision(manual_key_hex = nil)
    # Використовуємо HEX для консистентності з нашою моделлю HardwareKey
    hex_key = manual_key_hex || SecureRandom.hex(KEY_SIZE_BYTES).upcase

    HardwareKey.transaction do
      key_record = HardwareKey.find_or_initialize_by(device_uid: @device_uid)
      key_record.update!(
        aes_key_hex: hex_key
      )
    end

    Rails.logger.info "🔐 [Zero-Trust] Якір для #{@device_uid} зафіксовано."
    hex_key
  end

  # =========================================================================
  # 2. РОТАЦІЯ (The Entropy Pulse)
  # =========================================================================
  def rotate!
    # Використовуємо метод моделі для генерації та збереження
    key_record = HardwareKey.find_by!(device_uid: @device_uid)
    new_hex_key = key_record.rotate_key!

    # [СИНХРОНІЗАЦІЯ]: Сповіщаємо пристрій про зміну ключа.
    # Це має бути Downlink команда, зашифрована ЩЕ СТАРИМ КЛЮЧЕМ,
    # або через спеціальний OTA-канал.
    trigger_key_update_downlink(new_hex_key)

    Rails.logger.warn "🔄 [Zero-Trust] Ключ #{@device_uid} оновлено. Ефір сповіщено."
    new_hex_key
  end

  private

  def trigger_key_update_downlink(new_key_hex)
    # Якщо пристрій — Солдат, команда йде через його Королеву
    # Якщо Королева — напряму.
    # ActuatorCommandWorker.perform_async(...) або специфічний воркер
    return unless @device.respond_to?(:ip_address) || @device.respond_to?(:gateway)

    target_ip = @device.respond_to?(:ip_address) ? @device.ip_address : @device.gateway.ip_address
    
    # ПЛАН: Відправляємо нативний CoAP PUT запит на ендпоінт /sys/key
    # CoapClient.put("coap://#{target_ip}/sys/key", new_key_hex)
  end
end
