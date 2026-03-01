# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job
  sidekiq_options queue: "uplink", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. ДЕКОДУВАННЯ (Extraction)
    binary_payload = Base64.strict_decode64(encoded_payload)
    # Готуємо HEX для візуалізації в Live Stream (Матриця)
    hex_payload = binary_payload.unpack1("H*").upcase

    # 2. ІДЕНТИФІКАЦІЯ ШЛЮЗУ (The Queen Node)
    gateway = Gateway.find_by(ip_address: sender_ip)

    if gateway
      gateway.mark_seen!(sender_ip)
      Rails.logger.debug "🛰️ [Uplink] Батч прийнято від Королеви #{gateway.uid} (#{sender_ip})"
    else
      Rails.logger.warn "⚠️ [Uplink] Невідоме джерело пакета: #{sender_ip}. Дані обробляються анонімно."
    end

    # ⚡ [СИНХРОНІЗАЦІЯ]: Трансляція в Live Telemetry Stream
    # Ми відправляємо байти в ефір Цитаделі ДО обробки, щоб Архітектор бачив "сирий" імпульс
    broadcast_to_matrix(gateway, hex_payload)

    # 3. ПЕРЕДАЧА В СЕРВІС РОЗПАКОВКИ
    # Конвеєр: [DID:4][RSSI:1][Payload:16] x N
    TelemetryUnpackerService.call(binary_payload, gateway&.id)

  rescue Base64::Error => e
    Rails.logger.warn "🛑 [Uplink] Корупція Base64 від #{sender_ip}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🚨 [Uplink Critical] Збій обробки батча: #{e.message}"
    raise e
  end

  private

  def broadcast_to_matrix(gateway, hex_payload)
    # Використовуємо SolidCable/Turbo для миттєвого оновлення UI
    Turbo::StreamsChannel.broadcast_prepend_to(
      "telemetry_stream",
      target: "telemetry_feed",
      html: Views::Components::Telemetry::LogEntry.new(
        gateway: gateway,
        hex_payload: hex_payload,
        timestamp: Time.current
      ).call
    )
    
    # Автоматично прибираємо плейсхолдер "Waiting for uplink..."
    Turbo::StreamsChannel.broadcast_remove_to("telemetry_stream", target: "feed_placeholder")
  end
end
