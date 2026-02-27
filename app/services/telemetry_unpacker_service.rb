# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  RAW_AES_KEY = [
    0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
    0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D
  ].pack("N8").freeze

  CHUNK_SIZE = 21

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
    @cipher.key = RAW_AES_KEY
    @cipher.padding = 0 
  end

  def perform
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE
      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    queen_uid, inverted_rssi = chunk[0..4].unpack("NC")
    actual_rssi = -inverted_rssi
    encrypted_payload = chunk[5..20]

    begin
      @cipher.reset 
      decrypted = @cipher.update(encrypted_payload) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 [AES] Помилка розшифровки для Королеви #{queen_uid.to_s(16).upcase}: #{e.message}"
      return
    end

    # N - DID, n - Vcap, c - Temp, C - Acoustic, n - Time, C - Bio, C - TTL, a4 - Pad
    parsed_data = decrypted.unpack("N n c C n C C a4")

    # [АЛІГНЕМЕНТ З НОВОЮ МОДЕЛЛЮ]
    # Готуємо атрибути для створення TelemetryLog
    status_byte = parsed_data[5]
    status_code = status_byte >> 6

    log_attributes = {
      queen_uid: queen_uid.to_s(16).upcase,
      rssi: actual_rssi,
      voltage_mv: parsed_data[1],        # Раніше vcap_voltage
      temperature_c: parsed_data[2],     # Раніше temperature
      acoustic_events: parsed_data[3],   # Раніше acoustic
      metabolism_s: parsed_data[4],      # Раніше delta_t
      growth_points: status_byte & 0x3F,
      mesh_ttl: parsed_data[6]           # Раніше ttl
    }

    # Мапимо статус на enum та tamper_detected
    case status_code
    when 0 then log_attributes[:bio_status] = :homeostasis
    when 1 then log_attributes[:bio_status] = :stress
    when 2 then log_attributes[:bio_status] = :anomaly
    when 3 then log_attributes[:tamper_detected] = true
    end

    hex_did = parsed_data[0].to_s(16).upcase
    tree = Tree.find_by(did: hex_did)

    unless tree
      Rails.logger.warn("⚠️ [СИСТЕМНИЙ ШУМ] DID #{hex_did} не знайдено.")
      return
    end

    ActiveRecord::Base.transaction do
      log = tree.telemetry_logs.create!(log_attributes)
      tree.wallet.increment!(:balance, log.growth_points) if log.growth_points > 0
      AlertDispatchService.analyze_and_trigger!(log)
    end

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] #{e.message}"
  end
end
