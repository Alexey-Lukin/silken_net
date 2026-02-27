# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job

  # Виділяємо окрему чергу для телеметрії (найвищий пріоритет)
  sidekiq_options queue: "telemetry", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. Відновлюємо сирий бінарний хаос з Base64
    # strict_decode64 падає, якщо є зайві символи/перенесення рядків. Це наш Zero-Trust фільтр.
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. МЕРЕЖЕВИЙ ЯКІР (Протокол DIM-GAL)
    # Читаємо перші 4 байти (32-бітне ціле 'N'), щоб дізнатися UID Королеви.
    # Оновлюємо її IP-адресу, щоб Downlink (ActuatorCommandWorker) знав, куди стріляти командами.
    if binary_payload.bytesize >= 4
      queen_uid = binary_payload[0..3].unpack1("N")
      hex_queen_uid = queen_uid.to_s(16).upcase
      
      gateway = Gateway.find_by(uid: hex_queen_uid)
      
      # Оновлюємо IP тільки якщо він змінився, щоб не смикати базу даремно (Zero Lag)
      if gateway && gateway.ip_address != sender_ip
        gateway.update!(ip_address: sender_ip)
        Rails.logger.info "📡 [DIM-GAL] Маршрут до Королеви #{hex_queen_uid} оновлено: новий IP -> #{sender_ip}"
      end
    end

    # 3. Передаємо криптографічний моноліт у наш хірургічний сервіс
    TelemetryUnpackerService.call(binary_payload)

  rescue ArgumentError => e
    # Якщо Base64 пошкоджений ефіром або це атака (сміттєві дані),
    # strict_decode64 кине ArgumentError. Retry тут не допоможе. 
    # Ховаємо помилку, щоб не забивати чергу мертвими задачами.
    Rails.logger.warn "🛑 [Uplink Warning] Відкинуто пошкоджений або шкідливий пакет від #{sender_ip}: #{e.message}"
    
  rescue StandardError => e
    # Якщо впала база даних (Deadlock) або проблема з розшифровкою,
    # прокидаємо помилку далі. Sidekiq спробує ще раз.
    Rails.logger.error "🚨 [Uplink Error] Помилка обробки телеметрії від #{sender_ip}: #{e.message}"
    raise e
  end
end
