# frozen_string_literal: true

require "openssl"
require "timeout"

class OtaTransmissionWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: false

  CHUNK_SIZE = 512
  MAX_CHUNK_RETRIES = 5

  def perform(queen_uid, firmware_type, record_id, start_from_chunk = 0, retry_count = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    key_record = HardwareKey.find_by!(device_uid: queen_uid)
    payload = fetch_payload(firmware_type, record_id)
    
    chunks = payload.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    total_chunks = chunks.size

    gateway.update!(state: :updating)

    chunks.each_with_index do |chunk, index|
      next if index < start_from_chunk

      # ⚡ [СИНХРОНІЗАЦІЯ]: Звітуємо про прогрес у Turbo Stream
      broadcast_progress(queen_uid, index, total_chunks)

      encrypted_chunk = encrypt_payload(chunk, key_record.binary_key)

      begin
        Timeout.timeout(20) do
          url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?ch=#{index}&ttl=#{total_chunks}&id=#{record_id}"
          response = CoapClient.put(url, encrypted_chunk)
          raise "NACK: Шлюз відхилив чанк #{index}" unless response&.success?
        end

        sleep 0.4 # Pacing для HAL_FLASH_Program
      rescue Timeout::Error, StandardError => e
        handle_chunk_failure(queen_uid, firmware_type, record_id, index, retry_count, e.message)
        return
      end
    end

    gateway.update!(state: :idle)
    # Фінальний статус: 100%
    broadcast_progress(queen_uid, total_chunks, total_chunks, status: "COMPLETE")
    Rails.logger.info "✅ [OTA] Прошивка #{firmware_type} доставлена на #{queen_uid}."
  end

  private

  def broadcast_progress(uid, current, total, status: "TRANSMITTING")
    percent = ((current.to_f / total) * 100).to_i
    
    # Відправляємо оновлення конкретно для цього пристрою
    Turbo::StreamsChannel.broadcast_replace_to(
      "ota_channel_#{uid}",
      target: "ota_progress_#{uid}",
      html: Views::Components::Firmwares::OtaProgressBar.new(
        uid: uid, 
        percent: percent, 
        current: current, 
        total: total,
        status: status
      ).call
    )
  end

  # ... твої методи fetch_payload, handle_chunk_failure, encrypt_payload залишаються без змін ...
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
    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)
    cipher.update(padded_payload) + cipher.final
  end

  def handle_chunk_failure(uid, type, record_id, index, retry_count, error)
    if retry_count < MAX_CHUNK_RETRIES
      wait_time = (retry_count + 1) * 10
      self.class.perform_in(wait_time.seconds, uid, type, record_id, index, retry_count + 1)
    else
      Gateway.find_by(uid: uid)&.update!(state: :faulty)
      broadcast_progress(uid, index, 100, status: "FAILED")
    end
  end
end
