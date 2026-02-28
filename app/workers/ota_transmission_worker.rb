# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  # Вимикаємо стандартний ретрай, бо ми реалізуємо власну "розумну" естафету чанків
  sidekiq_options queue: "downlink", retry: false

  CHUNK_SIZE = 512

  def perform(queen_uid, firmware_type, record_id, start_from_chunk = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    
    # [ZERO-TRUST]: Дістаємо індивідуальний ключ пристрою
    key_record = HardwareKey.find_by!(device_uid: queen_uid)

    payload = fetch_payload(firmware_type, record_id)
    chunks = payload.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    total_chunks = chunks.size

    # Позначаємо шлюз як такий, що перебуває в процесі оновлення
    gateway.update!(state: :updating) if gateway.respond_to?(:state)

    chunks.each_with_index do |chunk, index|
      # Пропускаємо чанки, які вже були успішно передані (Resumable OTA)
      next if index < start_from_chunk

      encrypted_chunk = encrypt_payload(chunk, key_record.binary_key)

      begin
        Timeout.timeout(15) do
          url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?chunk=#{index}&total=#{total_chunks}"
          
          # [УВАГА]: Переконайся, що твій CoapClient дійсно чекає на ACK
          # і повертає об'єкт response, який має метод success?. 
          # Стандартний UDP Socket у Ruby є асинхронним (Fire-and-Forget).
          response = CoapClient.put(url, encrypted_chunk)
          
          raise "NACK (Gateway rejected chunk)" unless response&.success? 
        end

        # Pacing: час на стирання/запис сторінки Flash-пам'яті (0x0803F000)
        sleep 0.3 

      rescue Timeout::Error, StandardError => e
        Rails.logger.error "🛑 [OTA] Обрив на чанку #{index}/#{total_chunks} для #{queen_uid}: #{e.message}"
        
        # [СМАРТ-РЕТРАЙ]: Замість того, щоб падати, ми ставимо в чергу продовження з поточного індексу
        # Даємо мережі 10 секунд на стабілізацію перед наступною спробою
        self.class.perform_in(10.seconds, queen_uid, firmware_type, record_id, index)
        
        # Виходимо з поточного виконання (Кенозис стану)
        return 
      end
    end

    # Якщо цикл завершився без помилок
    gateway.update!(state: :idle) if gateway.respond_to?(:state)
    Rails.logger.info "✅ [OTA] Еволюція #{firmware_type} (v.#{record_id}) успішно завершена для #{queen_uid}."
  end

  private

  def fetch_payload(type, id)
    case type
    when "mruby"   then BioContractFirmware.find(id).binary_payload
    when "tinyml"  then TinyMlModel.find(id).binary_weights_payload
    else raise ArgumentError, "Невідомий тип прошивки: #{type}"
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
