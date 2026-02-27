# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  # Константа розміру пакета від Королеви (Queen UID + RSSI + Encrypted Payload)
  CHUNK_SIZE = 21

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
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
    # 1. Ідентифікація Королеви (Gateway)
    queen_uid_hex = chunk[0..3].unpack("N").first.to_s(16).upcase
    inverted_rssi = chunk[4].unpack("C").first
    actual_rssi = -inverted_rssi
    
    # [ЗМІНА]: Динамічний пошук ключа для конкретної Королеви (Zero-Trust)
    key_record = HardwareKey.find_by(device_uid: queen_uid_hex)
    unless key_record
      Rails.logger.error "🛑 [Zero-Trust] Ключ для Королеви #{queen_uid_hex} не знайдено! Пакет ігнорується."
      return
    end

    encrypted_payload = chunk[5..20]

    begin
      @cipher.reset
      @cipher.key = key_record.binary_key # Використовуємо ключ з бази
      decrypted = @cipher.update(encrypted_payload) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 [AES] Помилка розшифровки для Королеви #{queen_uid_hex}: #{e.message}"
      return
    end

    # N - DID, n - Vcap, c - Temp, C - Acoustic, n - Time, C - Bio, C - TTL, a4 - Pad
    parsed_data = decrypted.unpack("N n c C n C C a4")

    # Пошук Дерева-Солдата
    hex_did = parsed_data[0].to_s(16).upcase
    tree = Tree.find_by(did: hex_did)

    unless tree
      Rails.logger.warn("⚠️ [СИСТЕМНИЙ ШУМ] DID #{hex_did} не знайдено.")
      return
    end

    # [НОВЕ]: Застосування Калібрування (Лінза Істини)
    calibration = tree.device_calibration || DeviceCalibration.new(temperature_offset_c: 0, impedance_offset_ohms: 0, vcap_coefficient: 1.0)
    
    status_byte = parsed_data[5]
    status_code = status_byte >> 6

    # [АЛІГНЕМЕНТ З НОВОЮ МОДЕЛЛЮ ТА КАЛІБРУВАННЯМ]
    log_attributes = {
      queen_uid: queen_uid_hex,
      rssi: actual_rssi,
      voltage_mv: (parsed_data[1] * calibration.vcap_coefficient).to_i, # Калібрована напруга
      temperature_c: calibration.normalize_temperature(parsed_data[2]),  # Калібрована температура
      acoustic_events: parsed_data[3],
      metabolism_s: parsed_data[4],
      growth_points: status_byte & 0x3F,
      mesh_ttl: parsed_data[6]
    }

    case status_code
    when 0 then log_attributes[:bio_status] = :homeostasis
    when 1 then log_attributes[:bio_status] = :stress
    when 2 then log_attributes[:bio_status] = :anomaly
    when 3 then log_attributes[:tamper_detected] = true
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
