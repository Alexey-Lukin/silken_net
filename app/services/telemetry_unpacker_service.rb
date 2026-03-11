# frozen_string_literal: true

class TelemetryUnpackerService
  # [DID:4][RSSI:1][Payload:16] = 21 байт
  CHUNK_SIZE = 21

  # --- КОНСТАНТИ ЕВОЛЮЦІЇ (The Immutable Offsets) ---
  # Формат: DID(N), Vcap(n), Temp(c), Acoustic(C), Metabolism(n), Status(C), TTL(C), Pad(a4)
  PAYLOAD_FORMAT = "N n c C n C C a4"
  FIRMWARE_PAD_INDEX = 7 # Індекс елемента a4 у розпакованому масиві

  # --- МЕЖІ РЕАЛЬНОСТІ (Sanity Bounds) ---
  # Виключаємо сенсорний шум: ADC глюки, що виходять за межі фізики
  SAFE_VOLTAGE_RANGE = (0..5000)      # 0 - 5В
  SAFE_TEMP_RANGE    = (-45..90)      # Від арктичних до тропічних пожеж

  # DID-сентинел: Королева передає власну телеметрію з DID = 0x00000000
  QUEEN_SENTINEL_DID = "0"

  def self.call(binary_batch, gateway_id = nil)
    new(binary_batch, gateway_id).perform
  end

  def initialize(binary_batch, gateway_id)
    @binary_batch = binary_batch
    @gateway = Gateway.find_by(id: gateway_id)
    @trees_cache = {}
    @latest_firmware_id = nil
  end

  def perform
    return if @binary_batch.blank?

    # Розрізаємо бінарний моноліт на 21-байтні чанки
    chunks = @binary_batch.b.scan(/.{1,#{CHUNK_SIZE}}/m)

    # ⚡ [ОПТИМІЗАЦІЯ N+1]: Спершу витягуємо всі DID з батчу
    preload_trees(chunks)

    chunks.each do |chunk|
      next if chunk.bytesize < CHUNK_SIZE
      process_chunk(chunk)
    end
  end

  private

  # Створюємо Hash-мапу DID -> Tree для миттєвого доступу без N+1 запитів
  def preload_trees(chunks)
    dids = chunks.map { |c| c[0..3].unpack1("N").to_s(16).upcase }.uniq
    @trees_cache = Tree.where(did: dids)
                       .includes(:wallet, :device_calibration, :tree_family)
                       .index_by(&:did)
  end

  def process_chunk(chunk)
    # 1. МАРШРУТИЗАЦІЯ (L2 Header від Королеви)
    # DID Солдата, який відправив пакет через LoRa
    raw_did = chunk[0..3].unpack1("N")
    hex_did = raw_did.to_s(16).upcase

    # RSSI (якість сигналу в точці прийому Королевою)
    inverted_rssi = chunk[4].unpack1("C")
    actual_rssi = -inverted_rssi

    # 2. РОЗПАКОВКА БІО-МЕТРИКИ (L3 Payload)
    payload = chunk[5..20]
    parsed_data = payload.unpack(PAYLOAD_FORMAT)

    # [СЕНТИНЕЛ]: DID = 0x00000000 — це "нульовий" пакет Королеви з її власною телеметрією.
    # Маршрутизуємо дані в GatewayTelemetryWorker замість створення TelemetryLog.
    if raw_did.zero? && @gateway
      route_queen_health(parsed_data)
      return
    end

    # [СЕНСОРНИЙ ШУМ]: Перевірка на "адекватність" значень перед коммітом
    unless valid_sensor_data?(parsed_data)
      Rails.logger.warn "📡 [Sensor Noise] Пакет від #{hex_did} відхилено: аномальні показники ADC."
      return
    end

    # [ОПТИМІЗАЦІЯ]: Беремо дерево з нашого Hash-кешу
    tree = @trees_cache[hex_did]
    unless tree
      Rails.logger.warn "⚠️ [Uplink] DID #{hex_did} не знайдено в реєстрі."
      return
    end

    # 3. КАЛІБРУВАННЯ ТА НОРМАЛІЗАЦІЯ
    calibration = tree.device_calibration || tree.build_device_calibration
    status_byte = parsed_data[5]

    # firmware_id лежить у перших двох байтах Pad (a4)
    # [МАГІЯ PAD]: Використовуємо константи для безпечного доступу
    pad_data = parsed_data[FIRMWARE_PAD_INDEX]
    firmware_id = pad_data[0..1].unpack1("n")

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
    # ⚡ [ФІКСАЦІЯ ІСТИНИ]: Ми розраховуємо Z один раз тут.
    # Оскільки Attractor тепер використовує BigDecimal, ми отримуємо
    # детермінований результат, який зберігається як єдина істина.
    log_attributes[:z_value] = SilkenNet::Attractor.calculate_z(
      parsed_data[0], # Використовуємо сирий DID як seed
      log_attributes[:temperature_c],
      log_attributes[:acoustic_events]
    )

    # 5. ФІКСАЦІЯ ТА ЕКОНОМІЧНИЙ ВІДГУК
    commit_telemetry(tree, log_attributes)

  rescue StandardError => e
    # [BROAD RESCUE]: Додано логування стеку викликів для дебагу в продакшені
    trace = e.backtrace.first(5).join("\n")
    Rails.logger.error "🛑 [Telemetry Error] DID #{hex_did || 'UNKNOWN'}: #{e.message}\n#{trace}"
  end

  def valid_sensor_data?(data)
    voltage = data[1]
    temp = data[2]
    SAFE_VOLTAGE_RANGE.cover?(voltage) && SAFE_TEMP_RANGE.cover?(temp)
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

      # [СИНХРОНІЗАЦІЯ]: Оновлюємо денормалізований вольтаж для мапи без N+1
      tree.mark_seen!(log.voltage_mv)

      # [KENOSIS TITAN]: Атомарне оновлення health_streak без додаткових SELECT-ів.
      # Якщо лог здоровий — інкремент, інакше — скидання до нуля.
      update_health_streak!(tree, log)

      # Нарахування балів у гаманець Солдата
      tree.wallet.credit!(log.growth_points) if log.growth_points.positive?

      # [OTA MISMATCH]: Якщо дерево повідомляє firmware_version_id, що відрізняється від
      # актуальної прошивки — позначаємо дерево як fw_pending для повторної роздачі OTA.
      check_firmware_mismatch!(tree, log.firmware_version_id)

      # Аналіз аномалій Оракулом тривог
      AlertDispatchService.analyze_and_trigger!(log)

      # [IoTeX W3bstream]: Відправляємо телеметрію на ZK-верифікацію
      IotexVerificationWorker.perform_async(log.id_value, log.created_at.iso8601(6))

      # [Streamr]: Транслюємо сиру телеметрію в P2P-мережу для «прямого ефіру» лісу.
      # Працює паралельно з IoTeX — Streamr для присутності, IoTeX для фінансового консенсусу.
      StreamrBroadcastWorker.perform_async(log.id_value, log.created_at.iso8601(6))
    end
  end

  # [KENOSIS TITAN]: Денормалізований лічильник "одужання" (Anti-Flapping).
  # Замінює N+1 запит tree.telemetry_logs.recent.limit(3) у recovery_confirmed?.
  # Атомарний SQL запобігає race conditions при одночасних пакетах від різних Королев.
  # In-memory синхронізація безпечна — метод викликається лише всередині транзакції
  # commit_telemetry, де дерево гарантовано існує (аналогічно mark_seen!).
  def update_health_streak!(tree, log)
    if log.healthy?
      Tree.where(id: tree.id).update_all("health_streak = health_streak + 1")
      tree.health_streak += 1
    else
      Tree.where(id: tree.id).update_all(health_streak: 0)
      tree.health_streak = 0
    end
  end

  # [OTA MISMATCH DETECTION]: Перевіряємо, чи прошивка дерева актуальна.
  # Якщо дерево повідомляє firmware_version_id, що відрізняється від найновішої
  # активної BioContractFirmware для типу Tree, — позначаємо дерево для OTA-оновлення.
  # Кешуємо latest_firmware_id на рівні батчу (1 SQL-запит на весь пакет).
  def check_firmware_mismatch!(tree, reported_firmware_id)
    return if reported_firmware_id.blank?

    latest_id = latest_tree_firmware_id
    return if latest_id.nil?
    return if reported_firmware_id == latest_id

    # Дерево працює на застарілій прошивці — позначаємо як fw_pending
    # (тільки якщо не вже в процесі оновлення)
    return unless tree.firmware_fw_idle? || tree.firmware_fw_completed? || tree.firmware_fw_failed?

    Tree.where(id: tree.id).update_all(firmware_update_status: :fw_pending)
    Rails.logger.info "🔄 [OTA Mismatch] Дерево #{tree.did}: firmware #{reported_firmware_id} != latest #{latest_id}. Позначено fw_pending."
  end

  # Lazy-кешований ID останньої активної прошивки для дерев (1 запит на весь батч)
  def latest_tree_firmware_id
    return @latest_firmware_id if defined?(@latest_firmware_id_loaded)

    @latest_firmware_id_loaded = true
    @latest_firmware_id = BioContractFirmware.active
                                             .where(target_hardware_type: "Tree")
                                             .order(id: :desc)
                                             .pick(:id)
  end

  # [СЕНТИНЕЛ КОРОЛЕВИ]: Маршрутизація "нульового" пакета з власною телеметрією Королеви
  # до GatewayTelemetryWorker. Формат Payload однаковий: Vcap(2B), Temp(1B), Acoustic→CSQ(1B).
  def route_queen_health(parsed_data)
    GatewayTelemetryWorker.perform_async(
      @gateway.uid,
      {
        voltage_mv: parsed_data[1],           # Vcap Королеви (2 байти, мілівольти)
        temperature_c: parsed_data[2],         # Температура корпусу Королеви (1 байт)
        cellular_signal_csq: parsed_data[3]    # CSQ модему (1 байт, використовує поле Acoustic)
      }
    )
    Rails.logger.info "👑 [Sentinel] Королева #{@gateway.uid} повідомляє: #{parsed_data[1]}mV, #{parsed_data[2]}°C, CSQ=#{parsed_data[3]}"
  end
end
