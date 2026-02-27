# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job
  sidekiq_options queue: "telemetry", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. Zero-Trust Декодування
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. МЕРЕЖЕВИЙ ЯКІР (Протокол DIM-GAL)
    if binary_payload.bytesize >= 4
      queen_uid = binary_payload[0..3].unpack1("N")
      hex_queen_uid = queen_uid.to_s(16).upcase
      
      gateway = Gateway.find_by(uid: hex_queen_uid)
      
      if gateway
        # [ПОКРАЩЕННЯ]: Якщо ми отримали дані, Королева точно жива.
        # Оновлюємо IP та ставимо мітку "seen" в одній транзакції.
        if gateway.ip_address != sender_ip
          gateway.update!(ip_address: sender_ip, last_seen_at: Time.current)
          Rails.logger.info "📡 [DIM-GAL] Королева #{hex_queen_uid} змінила позицію: #{sender_ip}"
        else
          # Навіть якщо IP той самий, оновлюємо пульс для моніторингу
          gateway.mark_seen!
        end
      end
    end

    # 3. Передача в хірургічне відділення
    # Нагадаю: TelemetryUnpackerService розріже цей моноліт на 21-байтні чанки,
    # розшифрує AES та розрахує Атрактор Лоренца для кожного Солдата.
    TelemetryUnpackerService.call(binary_payload)

  rescue ArgumentError => e
    # Відсікаємо сміття ефіру
    Rails.logger.warn "🛑 [Uplink Warning] Base64 Corrupted від #{sender_ip}: #{e.message}"
    
  rescue StandardError => e
    # Ретрай для системних помилок (DB/Redis)
    Rails.logger.error "🚨 [Uplink Error] Критичний збій обробки: #{e.message}"
    raise e
  end
end
