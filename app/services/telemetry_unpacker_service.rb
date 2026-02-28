# frozen_string_literal: true

class TelemetryUnpackerService
  CHUNK_SIZE = 21 # [DID:4][RSSI:1][DecryptedPayload:16]

  def self.call(binary_batch, gateway_id = nil)
    new(binary_batch, gateway_id).perform
  end

  def initialize(binary_batch, gateway_id)
    @binary_batch = binary_batch
    @gateway = Gateway.find_by(id: gateway_id)
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
    # 1. МАРШРУТИЗАЦІЯ (Дані додані Королевою)
    # Перші 4 байти — це DID самого дерева (Солдата), а не шлюзу!
    hex_did = chunk[0..3].unpack1("N").to_s(16).upcase
    
    # RSSI інвертовано на Королеві для уникнення проблем зі знаком
    inverted_rssi = chunk[4].unpack1("C")
    actual_rssi = -inverted_rssi
    
    # 2. РОЗПАКОВКА БІО-МЕТРИКИ (16 байт ЧИСТОГО пейлоаду від Солдата)
    # N(DID), n(Vcap), c(Temp), C(Acoustic), n(Metabolism), C(Status), C(TTL), a4(Pad)
    payload = chunk[5..20]
    parsed_data = payload.unpack("N n c C n C C a4")
    
    tree = Tree.find_by(did: hex_did)
    unless tree
      Rails.logger.warn "⚠️ [Uplink] DID #{hex_did} не знайдено в реєстрі Черкаського бору."
      return
    end

    # 3. КАЛІБРУВАННЯ ТА НОРМАЛІЗАЦІЯ
    calibration = tree.device_calibration || DeviceCalibration.new
    status_byte = parsed_data[5]
    firmware_id = parsed_data[7].unpack1("n")

    log_attributes = {
      # Використовуємо UID відомої Королеви (якщо вона знайдена)
      queen_uid: @gateway&.uid, 
      rssi: actual_rssi,
      # Використовуємо метод normalize_voltage, який ми викували раніше
      voltage_mv: calibration.normalize_voltage(parsed_data[1]),
      temperature_c: calibration.normalize_temperature(parsed_data[2]),
      acoustic_events: parsed_data[3],
      metabolism_s: parsed_data[4],
      growth_points: status_byte & 0x3F,
      mesh_ttl: parsed_data[6],
      firmware_version_id: (firmware_id.positive? ? firmware_id : nil),
      bio_status: interpret_status(status_byte >> 6)
    }

    # 4. МАТЕМАТИКА АТРАКТОРА (The Chaos Engine)
    # z_value = f(DID, temp, acoustic)
    log_attributes[:z_value] = SilkenNet::Attractor.calculate_z(
      parsed_data[0], # Використовуємо DID з самого пейлоаду як насіння (Seed)
      log_attributes[:temperature_c],
      log_attributes[:acoustic_events]
    )

    # 5. ФІКСАЦІЯ ТА ЕКОНОМІЧНИЙ ВІДГУК
    commit_telemetry(tree, log_attributes)

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] Критичний збій чанка для DID #{hex_did}: #{e.message}"
  end

  def interpret_status(code)
    case code
    when 0 then :homeostasis
    when 1 then :stress
    when 2 then :anomaly
    when 3 then :tamper_detected
    end
  end

  def commit_telemetry(tree, attributes)
    ActiveRecord::Base.transaction do
      # Створення лога та нарахування балів
      log = tree.telemetry_logs.create!(attributes)
      tree.wallet.credit!(log.growth_points) if log.growth_points.positive?
      
      # Запуск Оракула Тривог
      AlertDispatchService.analyze_and_trigger!(log)
    end
  end
end
