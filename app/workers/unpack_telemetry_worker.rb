# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job
  sidekiq_options queue: "telemetry", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. Zero-Trust Декодування
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. МЕРЕЖЕВИЙ ЯКІР (Ідентифікація за IP)
    # Згідно з прошивкою, Королева не передає свій UID у батчі,
    # тому ми знаходимо її за IP-адресою, отриманою від UDP-сокета.
    gateway = Gateway.find_by(ip_address: sender_ip)
    
    if gateway
      # Оновлюємо пульс Королеви
      gateway.mark_seen!
      Rails.logger.debug "📡 [DIM-GAL] Отримано батч від Королеви #{gateway.uid} (#{sender_ip})"
    else
      # Якщо IP змінився (наприклад, Starlink видав нову адресу),
      # ми все одно обробляємо дані дерев, бо вони автономно валідні,
      # але система має підняти тривогу для оновлення IP.
      Rails.logger.warn "⚠️ [DIM-GAL] Невідомий IP шлюзу: #{sender_ip}. Дані лісу прийнято до обробки."
    end

    # 3. ПЕРЕДАЧА В ХІРУРГІЧНЕ ВІДДІЛЕННЯ
    # TelemetryUnpackerService розріже цей моноліт на 21-байтні чанки
    # (4 байти DID + 1 байт інвертованого RSSI + 16 байтів ЧИСТИХ даних).
    # Передаємо gateway.id, щоб сервіс міг прив'язати телеметрію до конкретної Королеви.
    TelemetryUnpackerService.call(binary_payload, gateway&.id)

  rescue ArgumentError => e
    # Відсікаємо сміття ефіру
    Rails.logger.warn "🛑 [Uplink Warning] Base64 Corrupted від #{sender_ip}: #{e.message}"
    
  rescue StandardError => e
    # Ретрай для системних помилок (DB/Redis)
    Rails.logger.error "🚨 [Uplink Error] Критичний збій обробки: #{e.message}"
    raise e
  end
end
