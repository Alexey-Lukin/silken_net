# frozen_string_literal: true

require "base64"

class UnpackTelemetryWorker
  include Sidekiq::Job

  # Виділяємо окрему чергу для телеметрії, щоб вона не блокувала,
  # наприклад, надсилання email-ів користувачам
  sidekiq_options queue: "telemetry", retry: 3

  def perform(encoded_payload, sender_ip)
    # 1. Відновлюємо сирий бінарний хаос з Base64
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. Передаємо в наш хірургічний сервіс
    # (Ви можете злегка модифікувати TelemetryUnpackerService, щоб він приймав і IP-адресу,
    # якщо хочете логувати IP Королеви для безпеки)
    TelemetryUnpackerService.call(binary_payload)
  rescue StandardError => e
    Rails.logger.error "Помилка розпакування в Sidekiq: #{e.message}"
    # Помилка змусить Sidekiq спробувати ще раз пізніше (завдяки retry: 3)
    raise e
  end
end
