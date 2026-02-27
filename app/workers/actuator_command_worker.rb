# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  def perform(actuator_id, command_code, duration_seconds)
    actuator = Actuator.find(actuator_id)
    gateway = actuator.gateway
    
    # [НОВЕ]: Знаходимо запис команди для оновлення статусу
    # Ми беремо останню команду в статусі :issued або :sent
    command_record = ActuatorCommand.where(actuator: actuator, status: [:issued, :sent]).last

    # 1. ШИФРУВАННЯ (Zero-Trust)
    # Дістаємо унікальний ключ Королеви
    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    unless key_record
      Rails.logger.error "🛑 [Downlink] Ключ для Королеви #{gateway.uid} не знайдено! Відміна."
      command_record&.update!(status: :failed)
      return
    end

    raw_payload = "CMD:#{command_code}:#{duration_seconds}:#{actuator.id}"
    encrypted_payload = encrypt_payload(raw_payload, key_record.binary_key)

    begin
      # 2. ФІЗИЧНИЙ ЗАПИТ
      command_record&.update!(status: :sent)
      
      Timeout.timeout(5) do
        # Відправляємо шифрований батч на IP шлюзу
        CoapClient.put("coap://#{gateway.ip_address}/actuator", encrypted_payload)
      end

      # 3. УСПІХ
      ActiveRecord::Base.transaction do
        actuator.update!(state: :active)
        command_record&.update!(status: :acknowledged) # Якщо CoAP повернув 2.04 Changed
      end

      Rails.logger.info "⚡ [Downlink] Команда #{command_code} активована на #{gateway.uid}"

      # 4. ПЛАНУВАННЯ ЗАВЕРШЕННЯ
      ResetActuatorStateWorker.perform_in(duration_seconds.seconds, actuator_id)

    rescue Timeout::Error, StandardError => e
      Rails.logger.error "🛑 [Downlink Error] Шлюз #{gateway.uid} недоступний: #{e.message}"
      
      # Оновлюємо статус для аудиту, але дозволяємо Sidekiq зробити retry
      command_record&.update!(status: :failed)
      raise e 
    end
  end

  private

  def encrypt_payload(payload, binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = binary_key # Використовуємо індивідуальний ключ пристрою
    cipher.padding = 0 

    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
