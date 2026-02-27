# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  CHUNK_SIZE = 512

  def perform(queen_uid, firmware_type, record_id, start_from_chunk = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    
    # [БЕЗПЕКА]: Дістаємо індивідуальний ключ пристрою
    key_record = HardwareKey.find_by!(device_uid: queen_uid)

    payload = fetch_payload(firmware_type, record_id)
    chunks = payload.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    total_chunks = chunks.size

    # Позначаємо шлюз як такий, що перебуває в процесі оновлення
    gateway.update!(state: :updating) if gateway.respond_to?(:state)

    chunks.each_with_index do |chunk, index|
      # Пропускаємо чанки, які вже були успішно передані (якщо реалізовано resume)
      next if index < start_from_chunk

      encrypted_chunk = encrypt_payload(chunk, key_record.binary_key)

      begin
        Timeout.timeout(15) do
          url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?chunk=#{index}&total=#{total_chunks}"
          response = CoapClient.put(url, encrypted_chunk)
          
          # Перевірка підтвердження (ACK) від пристрою
          raise "NACK" unless response.success? 
        end

        # Pacing: час на запис у Flash
        sleep 0.3 

      rescue StandardError => e
        Rails.logger.error "🛑 [OTA] Помилка на чанку #{index}/#{total_chunks}: #{e.message}"
        # Замість повного ретраю можна запланувати продовження з цього ж місця
        raise e 
      end
    end

    gateway.update!(state: :idle) if gateway.respond_to?(:state)
    Rails.logger.info "✅ [OTA] Оновлення #{firmware_type} завершено для #{queen_uid}"
  end

  private

  def fetch_payload(type, id)
    case type
    when "mruby"   then BioContractFirmware.find(id).binary_payload
    when "tinyml"  then TinyMlModel.find(id).binary_weights_payload
    else raise ArgumentError, "Unknown type"
    end
  end

  def encrypt_payload(payload, key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = key
    cipher.padding = 0

    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end
end
