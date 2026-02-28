# frozen_string_literal: true

class TelemetryUnpackerService
  # [DID:4][RSSI:1][Payload:16] = 21 байт
  CHUNK_SIZE = 21 

  def self.call(binary_batch, gateway_id = nil)
    new(binary_batch, gateway_id).perform
  end

  def initialize(binary_batch, gateway_id)
    @binary_batch = binary_batch
    @gateway = Gateway.find_by(id: gateway_id)
  end

  def perform
    return if @binary_batch.blank?

    # Розрізаємо бінарний моноліт на 21-байтні чанки
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)
    
    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE
      process_chunk(chunk)
    end
  end

  private

  def process_chunk(chunk)
    # 1. МАРШРУТИЗАЦІЯ (L2 Header від Королеви)
    # DID Солдата, який відправив пакет через LoRa
    hex_did = chunk[0..3].unpack1("N").to_s(16).upcase
    
    # RSSI (якість сигналу в точці прийому Королевою)
    inverted_rssi = chunk[4].unpack1("C")
    actual_rssi = -inverted_rssi
    
    # 2. РОЗПАКОВКА БІО-МЕТРИКИ (L3 Payload)
    # Формат: DID(N), Vcap(n), Temp(c), Acoustic(C), Metabolism(n), Status(C), TTL(C), Pad(a4)
    payload = chunk[5..20]
    parsed_data = payload.unpack("N n c C n C C a4")
    
    tree = Tree.find_by(did: hex_did)
    unless tree
      Rails.logger.warn "⚠️ [Uplink] DID #{hex_did} не знайдено в реєстрі."
      return
    end

    # 3. КАЛІБРУВАННЯ ТА НОРМАЛІЗАЦІЯ
    calibration = tree.device_calibration || tree.build_device_calibration
    status_byte = parsed_data[5]
    
    # firmware_id лежить у перших двох байтах Pad (a4)
    firmware_id = parsed_data[7][0..1].unpack1("n")

    log_attributes = {
      queen_uid: @gateway&.uid, 
      rssi: actual_rssi,
      voltage_mv: calibration.normalize_voltage(parsed_data[1]),
      temperature_c: calibration.normalize_temperature(parsed_data[2]),
      acoustic_events: parsed_data[3],
      metabolism_s: parsed_data[4],
      growth_points: status_byte & 0x3F, # Нижні 6 біт — бали росту
      mesh_ttl: parsed_data[6],
      firmware_version_id: (firmware_id.positive? ? firmware_id : nil),
      bio_status: interpret_status(status_byte >> 6) # Верхні 2 біти — статус
    }

    # 4. МАТЕМАТИКА АТРАКТОРА (The Chaos Engine)
    # Використовуємо DID як насіння для розрахунку стабільності Z
    log_attributes[:z_value] = SilkenNet::Attractor.calculate_z(
      parsed_data[0], 
      log_attributes[:temperature_c],
      log_attributes[:acoustic_events]
    )

    # 5. ФІКСАЦІЯ ТА ЕКОНОМІЧНИЙ ВІДГУК
    commit_telemetry(tree, log_attributes)

  rescue StandardError => e
    Rails.logger.error "🛑 [Telemetry Error] DID #{hex_did || 'UNKNOWN'}: #{e.message}"
  end

  def interpret_status(code)
    # Відповідає enum :bio_status у моделі TelemetryLog
    case code
    when 0 then :homeostasis
    when 1 then :stress
    when 2 then :anomaly
    when 3 then :tamper_detected
    end
  end

  def commit_telemetry(tree, attributes)
    # Транзакція гарантує, що ми не нарахуємо бали без лога (або навпаки)
    ActiveRecord::Base.transaction do
      log = tree.telemetry_logs.create!(attributes)
      
      # Нарахування балів у гаманець Солдата
      tree.wallet.credit!(log.growth_points) if log.growth_points.positive?
      
      # Аналіз аномалій Оракулом тривог
      AlertDispatchService.analyze_and_trigger!(log)
    end
  end
end
