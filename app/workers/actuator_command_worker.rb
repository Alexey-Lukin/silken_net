# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  # Downlink черга, 3 спроби. Якщо ліс не на зв'язку, ми не спамимо ефір вічно.
  sidekiq_options queue: "downlink", retry: 3

  def perform(actuator_id, command_code, duration_seconds)
    actuator = Actuator.find(actuator_id)
    gateway = actuator.gateway

    # 1. Формуємо базовий Payload.
    # Наприклад: "CMD:OPEN_VALVE:7200:12"
    raw_payload = "CMD:#{command_code}:#{duration_seconds}:#{actuator.id}"

    # 2. ШИФРУВАННЯ DOWNLINK (Zero-Trust Architecture)
    # Королева має розшифрувати це своїм апаратним AES-модулем
    encrypted_payload = encrypt_payload(raw_payload)

    begin
      # 3. Фізичний запит із жорстким тайм-аутом (5 секунд)
      # Якщо Starlink або LTE-M модем Королеви поза зоною, ми не блокуємо Sidekiq
      Timeout.timeout(5) do
        CoapClient.put("coap://#{gateway.ip_address}/actuator", encrypted_payload)
      end

      # 4. ТІЛЬКИ ПІСЛЯ УСПІХУ фіксуємо Істину в базі
      actuator.update!(state: :active)

      Rails.logger.info "⚡ [Downlink] Команда #{command_code} успішно відправлена на шлюз #{gateway.uid}"

      # 5. Плануємо зворотну дію
      ResetActuatorStateWorker.perform_in(duration_seconds.seconds, actuator_id)

    rescue Timeout::Error, StandardError => e
      Rails.logger.error "🛑 [Downlink Error] Мережевий збій при зв'язку з Королевою #{gateway.uid}: #{e.message}"
      
      # Перекидаємо помилку далі. Sidekiq сам зробить retry. 
      # Актуатор при цьому залишиться у статусі :pending (встановленому у EmergencyResponseService)
      raise e
    end
  end

  private

  # Метод симетричного шифрування, сумісний з апаратним CRYP_AES_ECB у STM32WLE5JC
  def encrypt_payload(payload)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    # Використовуємо той самий ключ, що й для розпакування телеметрії
    cipher.key = TelemetryUnpackerService::RAW_AES_KEY
    cipher.padding = 0 # Контролюємо паддінг вручну для C-сумісності

    # Доповнюємо рядок нуль-байтами (\x00) до кратності 16 (вимога блоку AES)
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
