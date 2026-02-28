# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  # Черга downlink має вищий пріоритет, ніж телеметрія,
  # бо наказ має бути доставлений миттєво.
  sidekiq_options queue: "downlink", retry: 3

  def perform(command_id)
    command = ActuatorCommand.find(command_id)
    actuator = command.actuator
    gateway = actuator.gateway

    # 1. ЗАХИСТ ТА ПЕРЕВІРКА ГОТОВНОСТІ
    return if command.status_acknowledged?

    unless gateway.ip_address.present?
      Rails.logger.error "🛑 [Downlink] Шлюз #{gateway.uid} не має IP! Наказ скасовано."
      command.update!(status: :failed, error_message: "Gateway IP missing")
      return
    end

    # Якщо Королева зайнята оновленням, ми відкладаємо наказ (Sidekiq retry)
    if gateway.state_updating?
      Rails.logger.warn "⏳ [Downlink] Шлюз #{gateway.uid} оновлюється. Відтермінування наказу..."
      raise "Gateway Busy: Updating"
    end

    # 2. ШИФРУВАННЯ (Zero-Trust Anchor)
    # Отримуємо ключ, який ми надійно зберігаємо в HardwareKey
    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    if key_record.nil? || key_record.binary_key.blank?
      Rails.logger.error "🛑 [Downlink] Ключ для Королеви #{gateway.uid} відсутній!"
      command.update!(status: :failed, error_message: "Hardware Key missing")
      return
    end

    # Формуємо пакет згідно з протоколом прошивки main.c
    raw_payload = "CMD:#{command.command_payload}:#{command.duration_seconds}:#{actuator.id}"
    encrypted_payload = encrypt_payload(raw_payload, key_record.binary_key)

    begin
      # 3. ФІЗИЧНА ПЕРЕДАЧА (CoAP Protocol)
      command.update!(status: :sent)

      # Оновлюємо пульс Королеви перед відправкою
      gateway.mark_seen!

      Timeout.timeout(7) do # Трохи збільшили таймаут для LoRa-затримок
        url = "coap://#{gateway.ip_address}/actuator/#{actuator.endpoint}"

        # Виклик нашого CoapClient (враховуємо, що він може викинути виключення)
        CoapClient.put(url, encrypted_payload)
      end

      # 4. ПІДТВЕРДЖЕННЯ ТА ТРАНСФОРМАЦІЯ СТАНУ
      ActiveRecord::Base.transaction do
        actuator.mark_active! # Переводимо актуатор у стан :active
        command.update!(status: :acknowledged, sent_at: Time.current)
      end

      Rails.logger.info "⚡ [Downlink] Наказ #{command.id} успішно доставлено на #{gateway.uid} -> #{actuator.endpoint}"

      # Плануємо повернення в IDLE після завершення роботи (напр. закриття крана)
      ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)

    rescue Timeout::Error => e
      handle_failure(command, "Gateway Timeout (No ACK from Queen)")
      raise e # Retry для Sidekiq
    rescue StandardError => e
      handle_failure(command, e.message)
      raise e
    end
  end

  private

  def handle_failure(command, message)
    Rails.logger.error "🛑 [Downlink Error] Наказ ##{command.id} провалено: #{message}"
    command.update!(status: :failed, error_message: message.truncate(200))
  end

  def encrypt_payload(payload, binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = binary_key
    cipher.padding = 0

    # Прошивка очікує вирівнювання по 16 байт (AES block size)
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
