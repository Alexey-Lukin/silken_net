# frozen_string_literal: true

require "base64"
require "openssl"

class UnpackTelemetryWorker
  include Sidekiq::Job
  # Використовуємо чергу uplink для пріоритетної обробки вхідних сигналів
  sidekiq_options queue: "uplink", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. ДЕКОДУВАННЯ (Extraction)
    # Отримуємо сирі байти, що прийшли через CoAP/UDP
    binary_payload = Base64.strict_decode64(encoded_payload)
    
    # 2. ІДЕНТИФІКАЦІЯ ШЛЮЗУ (The Queen Node)
    gateway = Gateway.find_by(ip_address: sender_ip)
    
    unless gateway
      Rails.logger.warn "⚠️ [Uplink] Невідоме джерело пакета: #{sender_ip}. Скидання з'єднання."
      return
    end

    gateway.mark_seen!(sender_ip)

    # 3. ДЕШИФРУВАННЯ БАТЧА (Dual-Key Logic)
    # Шукаємо ключі ідентичності для цієї Королеви
    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    
    unless key_record
      Rails.logger.error "🚨 [Security] Відсутній HardwareKey для Королеви #{gateway.uid}!"
      return
    end

    decrypted_data = attempt_decryption(binary_payload, key_record)

    unless decrypted_data
      Rails.logger.error "🛑 [Security] Критична помилка дешифрування від #{gateway.uid}. Пакет корумпований або ключ невірний."
      return
    end

    # ⚡ [СИНХРОНІЗАЦІЯ]: Трансляція розшифрованої істини в Матрицю (UI)
    broadcast_to_matrix(gateway, decrypted_data)

    # 4. ПЕРЕДАЧА В СЕРВІС РОЗПАКОВКИ
    # Конвеєр: [DID:4][RSSI:1][Payload:16] x N
    TelemetryUnpackerService.call(decrypted_data, gateway.id)

  rescue Base64::Error => e
    Rails.logger.warn "🛑 [Uplink] Корупція Base64 від #{sender_ip}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🚨 [Uplink Critical] Збій обробки батча: #{e.message}"
    raise e
  end

  private

  # Логіка "М'якої Ротації": пробуємо новий ключ, потім старий
  def attempt_decryption(payload, key_record)
    # Спроба 1: Основний (новий) ключ
    result = decrypt_aes(payload, key_record.binary_key)
    
    if result
      # Якщо новий ключ спрацював — підтверджуємо успішну ротацію (закриваємо Grace Period)
      key_record.clear_grace_period!
      return result
    end

    # Спроба 2: Попередній ключ (якщо він є у банку пам'яті)
    if key_record.binary_previous_key
      result = decrypt_aes(payload, key_record.binary_previous_key)
      if result
        Rails.logger.info "🔄 [KeyRotation] Пристрій #{key_record.device_uid} все ще використовує старий ключ."
        return result
      end
    end

    nil
  end

  def decrypt_aes(payload, key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.decrypt
    cipher.key = key
    cipher.padding = 0
    
    # Використовуємо rescue, бо при невірному ключі OpenSSL видасть помилку
    cipher.update(payload) + cipher.final
  rescue StandardError
    nil
  end

  def broadcast_to_matrix(gateway, binary_data)
    hex_payload = binary_data.unpack1("H*").upcase

    Turbo::StreamsChannel.broadcast_prepend_to(
      "telemetry_stream",
      target: "telemetry_feed",
      html: Views::Components::Telemetry::LogEntry.new(
        gateway: gateway,
        hex_payload: hex_payload,
        timestamp: Time.current
      ).call
    )
    
    Turbo::StreamsChannel.broadcast_remove_to("telemetry_stream", target: "feed_placeholder")
  end
end
