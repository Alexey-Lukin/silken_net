# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job
  # Використовуємо чергу 'uplink' для пріоритетної обробки вхідних даних
  sidekiq_options queue: "uplink", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. ДЕКОДУВАННЯ (Extraction)
    # Отримуємо бінарний моноліт, закодований Sanctum у Base64
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. ІДЕНТИФІКАЦІЯ ШЛЮЗУ (The Queen Node)
    # Знаходимо Королеву за її поточною мережевою адресою
    gateway = Gateway.find_by(ip_address: sender_ip)
    
    if gateway
      # Оновлюємо пульс та підтверджуємо IP (через наш зашліфований метод)
      gateway.mark_seen!(sender_ip)
      Rails.logger.debug "🛰️ [Uplink] Батч прийнято від Королеви #{gateway.uid} (#{sender_ip})"
    else
      # Якщо шлюз не знайдено за IP, ми все одно обробляємо дані (DID дерев унікальні),
      # але логуємо аномалію для ручного втручання патрульного.
      Rails.logger.warn "⚠️ [Uplink] Невідоме джерело пакета: #{sender_ip}. Дані обробляються анонімно."
    end

    # 3. ПЕРЕДАЧА В СЕРВІС РОЗПАКОВКИ
    # Конвеєр: [DID:4][RSSI:1][Payload:16] x N
    # Передаємо gateway.id для прив'язки TelemetryLog до шлюзу
    TelemetryUnpackerService.call(binary_payload, gateway&.id)

  rescue ArgumentError => e
    # Обробка пошкоджених Base64 даних (шум в ефірі)
    Rails.logger.warn "🛑 [Uplink] Корупція даних від #{sender_ip}: #{e.message}"
    
  rescue StandardError => e
    # Ретрай для системних помилок (DB/Redis). 
    # Sidekiq спробує обробити цей батч знову.
    Rails.logger.error "🚨 [Uplink Critical] Збій обробки батча: #{e.message}"
    raise e
  end
end
