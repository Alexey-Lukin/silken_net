# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  # Приймаємо лише ID наказу. Це унеможливлює Race Conditions.
  def perform(command_id)
    command = ActuatorCommand.find(command_id)
    actuator = command.actuator
    gateway = actuator.gateway

    # Якщо команда вже успішно виконана (наприклад, випадковий дубль Sidekiq)
    return if command.status_acknowledged?

    # 1. ШИФРУВАННЯ (Zero-Trust)
    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    unless key_record
      Rails.logger.error "🛑 [Downlink] Ключ для Королеви #{gateway.uid} не знайдено!"
      command.update!(status: :failed)
      return
    end

    raw_payload = "CMD:#{command.command_payload}:#{command.duration_seconds}:#{actuator.id}"
    encrypted_payload = encrypt_payload(raw_payload, key_record.binary_key)

    begin
      # 2. ФІЗИЧНИЙ ЗАПИТ
      command.update!(status: :sent)
      
      Timeout.timeout(5) do
        # Використовуємо endpoint актуатора (напр. /actuator/valve_1)
        url = "coap://#{gateway.ip_address}/actuator/#{actuator.endpoint}"
        CoapClient.put(url, encrypted_payload)
      end

      # 3. УСПІХ (Синхронізація станів)
      ActiveRecord::Base.transaction do
        actuator.mark_active! # Використовуємо наш новий метод з моделі Actuator
        command.update!(status: :acknowledged)
      end

      Rails.logger.info "⚡ [Downlink] Наказ #{command.id} активовано на #{gateway.uid} (#{actuator.endpoint})"

      # 4. ПЛАНУВАННЯ ЗАВЕРШЕННЯ
      # Через вказаний час воркер переведе актуатор назад у стан :idle
      ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)

    rescue Timeout::Error, StandardError => e
      Rails.logger.error "🛑 [Downlink Error] Шлюз #{gateway.uid} не відповів: #{e.message}"
      
      # Оновлюємо статус, але кидаємо помилку далі, щоб Sidekiq зробив retry.
      # Оскільки ми шукаємо по find(command_id), наступний retry успішно знайде цю команду.
      command.update!(status: :failed)
      raise e 
    end
  end

  private

  def encrypt_payload(payload, binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = binary_key 
    cipher.padding = 0 

    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
