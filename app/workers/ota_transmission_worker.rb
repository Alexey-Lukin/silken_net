# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  # Вимикаємо стандартний ретрай для контролю естафети
  sidekiq_options queue: "downlink", retry: false

  CHUNK_SIZE = 512
  MAX_CHUNK_RETRIES = 5 # Захист від "зациклення" на битому чанку

  def perform(queen_uid, firmware_type, record_id, start_from_chunk = 0, retry_count = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    key_record = HardwareKey.find_by!(device_uid: queen_uid)

    payload = fetch_payload(firmware_type, record_id)
    # Використовуємо .b для безпечної роботи з бінарними даними
    chunks = payload.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    total_chunks = chunks.size

    # Оновлюємо стан Королеви для дашборду патрульного
    gateway.update!(state: :updating) if gateway.respond_to?(:state)

    chunks.each_with_index do |chunk, index|
      # Resumable logic: пропускаємо те, що вже на залізі
      next if index < start_from_chunk

      encrypted_chunk = encrypt_payload(chunk, key_record.binary_key)

      begin
        Timeout.timeout(20) do
          # Формуємо URL з метаданими для шлюзу
          url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?ch=#{index}&ttl=#{total_chunks}&id=#{record_id}"

          # [СИНХРОНІЗАЦІЯ]: Використовуємо блокуючий PUT
          response = CoapClient.put(url, encrypted_chunk)

          raise "NACK: Шлюз відхилив чанк #{index}" unless response&.success?
        end

        # Pacing: даємо STM32 час на HAL_FLASH_Program
        sleep 0.4

      rescue Timeout::Error, StandardError => e
        handle_chunk_failure(queen_uid, firmware_type, record_id, index, retry_count, e.message)
        return # Перериваємо поточне виконання
      end
    end

    # Фіналізація
    gateway.update!(state: :idle) if gateway.respond_to?(:state)
    Rails.logger.info "✅ [OTA] Прошивка #{firmware_type} успішно доставлена на #{queen_uid}."
  end

  private

  def handle_chunk_failure(uid, type, record_id, index, retry_count, error)
    if retry_count < MAX_CHUNK_RETRIES
      wait_time = (retry_count + 1) * 10 # Експоненціальна пауза
      Rails.logger.warn "⏳ [OTA] Помилка чанка #{index} для #{uid}: #{error}. Ретрай #{retry_count + 1}/#{MAX_CHUNK_RETRIES} через #{wait_time}с."

      self.class.perform_in(wait_time.seconds, uid, type, record_id, index, retry_count + 1)
    else
      Rails.logger.error "🛑 [OTA] Капітуляція. Чанк #{index} не доставлено після #{MAX_CHUNK_RETRIES} спроб."
      Gateway.find_by(uid: uid)&.update!(state: :faulty)
    end
  end

  def fetch_payload(type, id)
    case type
    when "mruby"   then BioContractFirmware.find(id).binary_payload
    when "tinyml"  then TinyMlModel.find(id).binary_weights_payload
    else raise ArgumentError, "Невідомий тип OTA: #{type}"
    end
  end

  def encrypt_payload(payload, key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = key
    cipher.padding = 0

    # Прошивка очікує вирівнювання по 16 байт
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
