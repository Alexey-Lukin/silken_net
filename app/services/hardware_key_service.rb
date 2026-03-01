# frozen_string_literal: true

require "securerandom"

class HardwareKeyService
  KEY_SIZE_BYTES = 32

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
    
    # ⚡ [ЗАГАРТУВАННЯ]: Зберігаємо поточний ключ як попередній
    old_key = key_record.aes_key_hex
    new_hex_key = SecureRandom.hex(KEY_SIZE_BYTES).upcase

    HardwareKey.transaction do
      key_record.update!(
        previous_aes_key_hex: old_key, # "Подушка безпеки"
        aes_key_hex: new_hex_key,
        rotated_at: Time.current
      )
    end

    # Надсилаємо Downlink. 
    # ВАЖЛИВО: цей пакет має бути зашифрований OLD_KEY, 
    # бо дерево ще не знає про NEW_KEY!
    trigger_key_update_downlink(new_hex_key, old_key)

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
