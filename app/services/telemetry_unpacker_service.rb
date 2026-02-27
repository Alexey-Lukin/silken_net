# frozen_string_literal: true

require "openssl"

class TelemetryUnpackerService
  CHUNK_SIZE = 21 # [DID:4][RSSI:1][EncryptedPayload:16]

  def self.call(binary_batch)
    new(binary_batch).perform
  end

  def initialize(binary_batch)
    @binary_batch = binary_batch
    @cipher = OpenSSL::Cipher.new("aes-256-ecb")
    @cipher.decrypt
    @cipher.padding = 0 
    @keys_cache = {} 
  end

  def perform
    # Розрізаємо бінарний моноліт на 21-байтні чанки (Протокол Королеви)
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    
    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE
      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    # 1. ІДЕНТИФІКАЦІЯ ШЛЮЗУ (Королеви)
    queen_uid_hex = chunk[0..3].unpack1("N").to_s(16).upcase
    inverted_rssi = chunk[4].unpack1("C")
    actual_rssi = -inverted_rssi
    
    # [ZERO-TRUST]: Шукаємо індивідуальний ключ шифрування Королеви
    key_record = @keys_cache[queen_uid_hex] ||= HardwareKey.find_by(device_uid: queen_uid_hex)
    
    unless key_record
      Rails.logger.error "🛑 [Zero-Trust] Ключ для Королеви #{queen_uid_hex} не знайдено!"
      return
    end

    # 2. ДЕКРИПТ ПЕЙЛОАДУ (AES-256-ECB)
    begin
      @cipher.reset
      @cipher.key = key_record.binary_key
      decrypted = @cipher.update(chunk[5..20]) + @cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      Rails.logger.error "🛑 [AES] Помилка дешифрування для Королеви #{queen_uid_hex}: #{e.message}"
      return
    end

    # 3. РОЗПАКОВКА БІО-МЕТРИКИ (16 байт Солдата)
    # N(DID), n(Vcap), c(Temp), C(Acoustic), n(Metabolism), C(Status), C(TTL), a4(Pad)
    parsed_data = decrypted.unpack("N n c C n C C a4")
    hex_did = parsed_data[0].to_s(16).upcase
    
    tree = Tree.find_by(did: hex_did)
    unless tree
      Rails.logger.warn "⚠️ [Uplink] DID #{hex_did} не знайдено в реєстрі."
      return
    end

    # 4. КАЛІБРУВАННЯ ТА НОРМАЛІЗАЦІЯ
    calibration = tree.device_calibration || DeviceCalibration.new
    status_byte = parsed_data[5]
    firmware_id = parsed_data[7].unpack1("n")

    log_attributes = {
      queen_uid: queen_uid_hex,
      rssi: actual_rssi,
      voltage_mv: (parsed_data[1] * calibration.vcap_coefficient).to_i,
      temperature_c: calibration.normalize_temperature(parsed_data[2]),
      acoustic_events: parsed_data[3],
      metabolism_s: parsed_data[4],
      growth_points: status_byte & 0x3F,
      mesh_ttl: parsed_data[6],
      firmware_version_id: (firmware_id.positive? ? firmware_id : nil),
      bio_status: interpret_status(status_byte >> 6)
    }

    # 5. МАТЕМАТИКА АТРАКТОРА (The Chaos Engine)
    # $z_{value} = f(DID, temp, acoustic)$
    log_attributes[:z_value] = SilkenNet::Attractor.calculate_z(
      parsed_data[0], # Використовуємо DID як насіння (Seed)
      log_attributes[:temperature_c],
      log_attributes[:acoustic_events]
    )

    # 6. ФІКСАЦІЯ ТА ЕКОНОМІЧНИЙ ВІДГУК
    commit_telemetry(tree, queen_uid_hex, log_attributes)

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] Критичний збій чанка: #{e.message}"
  end

  def interpret_status(code)
    case code
    when 0 then :homeostasis
    when 1 then :stress
    when 2 then :anomaly
    when 3 then :tamper_detected
    end
  end

  def commit_telemetry(tree, queen_uid, attributes)
    ActiveRecord::Base.transaction do
      # Пульс Королеви
      Gateway.find_by(uid: queen_uid)&.mark_seen!

      # Створення лога та нарахування балів
      log = tree.telemetry_logs.create!(attributes)
      tree.wallet.credit!(log.growth_points) if log.growth_points.positive?
      
      # Запуск Оракула Трівог
      AlertDispatchService.analyze_and_trigger!(log)
    end
  end
end
