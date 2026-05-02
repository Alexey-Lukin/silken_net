# frozen_string_literal: true

class TelemetryUnpackerService < ApplicationService
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

  # --- DUAL COMPUTATION INTEGRITY ---
  # Device (mruby, Float) та Server (Ruby, Float) розраховують Z незалежно.
  # [FIX FW.7]: Backend переведено на Float (IEEE 754) — ідентично firmware mruby.
  # ВАЖЛИВО: firmware використовує chaos_seed (HRNG random), backend — tree_did (DID).
  # Це РІЗНІ входи — тому raw Z-значення завжди різні.
  # Перевірка лише категорична: device bio_status vs server healthy_z?.
  # Якщо device bio_status суперечить server Z — потенційний fraud або збій firmware.

  # DID-сентинел: Королева передає власну телеметрію з DID = 0x00000000
  QUEEN_SENTINEL_DID = "0"

  def initialize(binary_batch, gateway_id = nil)
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
  # [ВИПРАВЛЕНО: DID Prefix Mismatch]: Реконструюємо повний SNET-XXXXXXXX формат
  # із сирого uint32, щоб збігтися з Tree.did у базі (SNET- + 8 hex digits).
  def preload_trees(chunks)
    dids = chunks.map { |c| format("SNET-%08X", c[0..3].unpack1("N")) }.uniq
    @trees_cache = Tree.where(did: dids)
                       .includes(:wallet, :device_calibration, :tree_family)
                       .index_by(&:did)
  end

  def process_chunk(chunk)
    # 1. МАРШРУТИЗАЦІЯ (L2 Header від Королеви)
    # DID Солдата, який відправив пакет через LoRa
    # [ВИПРАВЛЕНО: DID Prefix Mismatch]: Реконструюємо повний SNET-XXXXXXXX формат
    raw_did = chunk[0..3].unpack1("N")
    hex_did = format("SNET-%08X", raw_did)

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
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      return
    end

    # [ОПТИМІЗАЦІЯ]: Беремо дерево з нашого Hash-кешу
    tree = @trees_cache[hex_did]
    unless tree
      Rails.logger.warn "⚠️ [Uplink] DID #{hex_did} не знайдено в реєстрі."
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
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

    # [FW.22] Firmware saturates acoustic_events at 255 (uint16 → uint8 clamped).
    # Value 255 likely indicates overflow — real count may be higher.
    # Log warning for operational awareness and future payload redesign.
    if log_attributes[:acoustic_events] == 255
      Rails.logger.warn(
        "⚠️ [Acoustic Overflow] DID #{hex_did}: acoustic_events=255 (saturated). " \
        "Real count may exceed 255 — firmware uint8 payload limit reached."
      )
      # [S2.3]: Prometheus counter for Grafana alerting on acoustic overflow
      SilkenNet::Metrics::TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL.increment
    end

    # 4. МАТЕМАТИКА АТРАКТОРА (The Chaos Engine)
    # ⚡ [ФІКСАЦІЯ ІСТИНИ]: Ми розраховуємо Z один раз тут.
    # [FIX FW.7]: Attractor використовує Float (IEEE 754) — ідентично firmware mruby.
    # Це забезпечує Dual Computation Integrity: однакова математика → однакові результати.
    # [FW.5]: delta_t (metabolism_s, секунди) і vcap (voltage_mv після калібрування)
    # передаються як soft β-perturbation — точно дзеркальне обчислення з firmware.
    log_attributes[:z_value] = SilkenNet::Attractor.calculate_z(
      parsed_data[0], # Використовуємо сирий DID як seed
      log_attributes[:temperature_c],
      log_attributes[:acoustic_events],
      log_attributes[:metabolism_s],
      log_attributes[:voltage_mv]
    )

    # 4.1 DUAL COMPUTATION INTEGRITY (Z Divergence Check)
    # Device повідомляє bio_status з власного Lorenz (Float, mruby).
    # Server розраховує Z (Float, ідентично). Порівнюємо статуси:
    # якщо device каже "homeostasis" а server Z поза межами породи — fraud flag.
    check_z_divergence!(tree, log_attributes)

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

  # [DUAL COMPUTATION INTEGRITY]: Порівнюємо device bio_status з server-derived bio_status.
  # Device (mruby, Float) та Server (Ruby, Float) розраховують Lorenz незалежно,
  # але з РІЗНИМИ seed'ами: firmware — chaos_seed (HRNG), backend — tree_did.
  # Тому raw Z-значення завжди різні. Порівнюємо лише категоричну невідповідність:
  #   - Device каже "homeostasis" (status=0) а server Z поза межами породи
  #   - Device каже "anomaly" (status=2) а server Z цілком здоровий
  # Це ловить tampered firmware або replay attacks з підставленим StatusByte.
  def check_z_divergence!(tree, attributes)
    tree_family = tree.tree_family
    return unless tree_family # Без породи — перевірка неможлива

    server_z = attributes[:z_value]
    device_bio_status = attributes[:bio_status]
    return if server_z.nil? || device_bio_status.nil?

    server_healthy = tree_family.healthy_z?(server_z)
    device_healthy = device_bio_status == :homeostasis

    # Категорична невідповідність: один каже "здоровий", інший — "ні"
    if device_healthy != server_healthy
      Rails.logger.warn(
        "🔍 [Z Divergence] DID #{tree.did}: device=#{device_bio_status}, " \
        "server_z=#{server_z}, healthy_range=#{tree_family.critical_z_min}..#{tree_family.critical_z_max}. " \
        "Dual Computation Integrity mismatch."
      )
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
    end
  end

  def commit_telemetry(tree, attributes)
    growth_points = attributes[:growth_points]

    # Транзакція фіксує телеметрію, стан дерева та побічні ефекти як єдине ціле.
    # Wallet credit та Sidekiq jobs винесено ЗА межі транзакції (див. нижче).
    log = ActiveRecord::Base.transaction do
      record = tree.telemetry_logs.create!(attributes)

      # [OBSERVABILITY]: Count successfully committed telemetry chunks
      SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL.increment

      # [СИНХРОНІЗАЦІЯ]: Оновлюємо денормалізований вольтаж для мапи без N+1
      tree.mark_seen!(record.voltage_mv)

      # [KENOSIS TITAN]: Атомарне оновлення health_streak без додаткових SELECT-ів.
      # Якщо лог здоровий — інкремент, інакше — скидання до нуля.
      update_health_streak!(tree, record)

      # [OTA MISMATCH]: Якщо дерево повідомляє firmware_version_id, що відрізняється від
      # актуальної прошивки — позначаємо дерево як fw_pending для повторної роздачі OTA.
      check_firmware_mismatch!(tree, record.firmware_version_id)

      # Аналіз аномалій Оракулом тривог
      AlertDispatchService.analyze_and_trigger!(record)

      record
    end

    # [P1-7 FIX: Phantom Sidekiq Jobs — Wiki 04_02 Audit §14]
    # perform_async виклики перенесено ПОЗА транзакцію. Якщо транзакція відкотиться
    # (напр., update_health_streak! або check_firmware_mismatch! кинуть) — jobs НЕ
    # потраплять до Redis, бо виконання не дійде до цих рядків.
    # Раніше: jobs ставились у чергу всередині transaction — при rollback TelemetryLog
    # запис не існував, але IotexVerificationWorker вже був у Redis (5 марних ретраїв
    # на web3_critical чергу).
    IotexVerificationWorker.perform_async(log.id_value, log.created_at.iso8601(6))
    StreamrBroadcastWorker.perform_async(log.id_value, log.created_at.iso8601(6))

    # [BLOCKER FIX: Database Locking — Wiki 04_01]
    # Нарахування балів у гаманець Солдата ПОЗА основною транзакцією.
    # credit! відкриває власну коротку транзакцію з pessimistic lock (SELECT ... FOR UPDATE).
    # Lock тримається лише мілісекунди замість усієї тривалості commit_telemetry.
    # growth_points записані в TelemetryLog — аудит-трейл для reconciliation при збоях.
    #
    # [DIFF.2 FIX: carbon_sequestration_coefficient]:
    # Зважуємо бали росту за коефіцієнтом секвестрації породи дерева.
    # Дуб (Quercus) акумулює вуглець швидше за Сосну (Pinus) — справедливий розподіл SCC.
    if growth_points&.positive?
      weighted_points = tree.tree_family&.weighted_growth_points(growth_points) || growth_points
      tree.wallet.credit!(weighted_points) if weighted_points.positive?
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
