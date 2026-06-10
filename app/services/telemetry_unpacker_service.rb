# frozen_string_literal: true

class TelemetryUnpackerService < ApplicationService
  # [DID:4][RSSI:1][Payload:16] = 21 байт — ECB transitional format (pre-FW.2)
  CHUNK_SIZE     = 21
  ECB_CHUNK_SIZE = 21

  # [FW.2] CCM 25-byte chunk = Queen-prepended RSSI(1) + 24B LoRa air format
  # ([DID:4][FC:4 BE] AAD + [ciphertext:8] + [MIC:8]).
  # Enabled via ENV `TELEMETRY_CCM_ENABLED=true`; defaults to ECB so the
  # production wire format is unchanged until firmware ships CCM emission.
  CCM_CHUNK_SIZE             = 25
  CCM_SENSOR_PAYLOAD_FORMAT  = "n c C n C C" # Vcap(2BE) Temp(i8) Acoustic(u8) dt(2BE) Status(u8) MeshCtrl(u8)
  CCM_FC_NONCE_TTL           = 25.hours
  CCM_FC_NONCE_KEY_PREFIX    = "silken:ccm:fc"

  # --- КОНСТАНТИ ЕВОЛЮЦІЇ (The Immutable Offsets) ---
  # Формат: DID(N), Vcap(n), Temp(c), Acoustic(C), Metabolism(n), Status(C), TTL(C), Pad(a4)
  PAYLOAD_FORMAT = "N n c C n C C a4"
  FIRMWARE_PAD_INDEX = 7 # Індекс елемента a4 у розпакованому масиві

  # [SEC.10] Frame Counter anti-replay для panic packets.
  # PANIC_FLAG_BIT = бит 7 у status_byte (firmware FW.29). Soldier
  # інкрементує `panic_frame_counter` (uint16) перед кожним
  # Trigger_Emergency_LoRa_TX і пакує його BE у байти 14..15 LoRa
  # пейлоаду — це останні 2 байти 4-байтного PAD a4. Перші 2 байти PAD
  # тримають firmware_version_id (FW.22).
  PANIC_FLAG_BIT             = 0x80
  PANIC_NONCE_TTL            = 25.hours       # Трохи довше за 24h replay-вікно
  PANIC_NONCE_KEY_PREFIX     = "silken:panic:nonce"

  # --- МЕЖІ РЕАЛЬНОСТІ (Sanity Bounds) ---
  # Виключаємо сенсорний шум: ADC глюки, що виходять за межі фізики
  SAFE_VOLTAGE_RANGE = (0..5000)      # 0 - 5В
  SAFE_TEMP_RANGE    = (-45..90)      # Від арктичних до тропічних пожеж

  # --- DUAL COMPUTATION INTEGRITY ---
  # [SEC.11] Device (mruby, Float) and Server (Ruby, Float) both start
  # the Lorenz attractor from byte-identical (x₀, y₀, z₀) derived from
  # per-tree K_seed via SilkenNet::SeedDerivation (HKDF-SHA256 →
  # HMAC-SHA256 → signed-unit-float unpack). The DID is no longer an
  # attractor input — it is purely an identifier. With identical inputs
  # raw Z values are numerically comparable, and `check_z_divergence!`
  # asserts that |server_z − device_z| stays inside a tight tolerance
  # band on top of the categorical bio_status check.

  # [ARCH.41] Firmware RTC-default epoch_day after VBAT loss.
  # STM32WLE5JC RTC resets to 2000-01-01 00:00:00 UTC → day 10_957 since
  # Unix epoch (946_684_800 / 86_400 = 10_957 exactly).
  # [ARCH.41] Was 10_951 — an artifact of the firmware's old
  # leap-less approximation (Y*365 + M*30 + D). The firmware now derives
  # epoch_day via exact civil-days arithmetic (firmware/common/lorenz_seed.h
  # `Silken_Days_From_Civil`, host-test-pinned: 2000-01-01 → 10_957), so the
  # recovery candidate must match the real value.
  FIRMWARE_RTC_DEFAULT_EPOCH_DAY = 10_957

  # DID-сентинел: Королева передає власну телеметрію з DID = 0x00000000
  QUEEN_SENTINEL_DID = "0"

  # [L1 QATT] gateway_attested: батч пройшов Ed25519-верифікацію Королеви
  # (UnpackTelemetryWorker) — прапор протягується у кожен TelemetryLog-рядок.
  def initialize(binary_batch, gateway_id = nil, gateway_attested: false)
    @binary_batch = binary_batch
    @gateway = Gateway.find_by(id: gateway_id)
    @gateway_attested = gateway_attested
    @trees_cache = {}
    @latest_firmware_id = nil
  end

  def perform
    return if @binary_batch.blank?

    chunk_size = active_chunk_size
    chunks = @binary_batch.b.scan(/.{1,#{chunk_size}}/m)

    # ⚡ [ОПТИМІЗАЦІЯ N+1]: Спершу витягуємо всі DID з батчу
    preload_trees(chunks)

    chunks.each do |chunk|
      next if chunk.bytesize < chunk_size
      if ccm_enabled?
        process_ccm_chunk(chunk)
      else
        process_chunk(chunk)
      end
    end
  end

  private

  # Створюємо Hash-мапу DID -> Tree для миттєвого доступу без N+1 запитів
  # [ВИПРАВЛЕНО: DID Prefix Mismatch]: Реконструюємо повний SNET-XXXXXXXX формат
  # із сирого uint32, щоб збігтися з Tree.did у базі (SNET- + 8 hex digits).
  # [SEC.11] Eager-load `hardware_key` так само як `wallet`/`device_calibration`/
  # `tree_family` — нам потрібен `binary_lorenz_seed` для per-tree seed dispatch
  # без додаткового N+1 за пакет.
  def preload_trees(chunks)
    dids = chunks.map { |c| format("SNET-%08X", c[0..3].unpack1("N")) }.uniq
    @trees_cache = Tree.where(did: dids)
                       .includes(:wallet, :device_calibration, :tree_family, :hardware_key)
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

    # [SEC.10] Frame Counter anti-replay для panic packets.
    # Соломонова сторожа панічного каналу: panic_frame_counter (BE у байтах
    # 14..15 = pad_data[2..3]) інкрементується soldier'ом перед кожним
    # emergency TX. Тут ми ловимо повторюваний nonce через Redis SETNX —
    # replay одного «chainsaw detected» = false fire alert + евакуація +
    # втрата довіри до системи. Поза-panic пакети нічого не платять
    # (counter-перевірка пропускається).
    if (status_byte & PANIC_FLAG_BIT).nonzero?
      panic_counter = pad_data[2..3].to_s.unpack1("n").to_i
      if panic_counter.positive? && panic_replayed?(hex_did, panic_counter)
        Rails.logger.warn(
          "🛡️ [SEC.10] Panic replay rejected for #{hex_did}: counter=#{panic_counter} " \
          "already seen within #{PANIC_NONCE_TTL.inspect} window."
        )
        SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL.increment
        return
      end
    end

    bio_status = interpret_status((status_byte >> 5) & 0x03) # bits 6..5 — статус (FW.29-PACK)

    log_attributes = {
      queen_uid: @gateway&.uid,
      rssi: actual_rssi,
      voltage_mv: calibration.normalize_voltage(parsed_data[1]),
      temperature_c: calibration.normalize_temperature(parsed_data[2]),
      lorenz_temperature_c: parsed_data[2], # [FW.57 F2] raw wire temp — DCI anchor (stripped pre-persist)
      acoustic_events: parsed_data[3],
      metabolism_s: parsed_data[4],
      # [FW.29-PACK] Wire-формат байту 10: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
      # Wire growth_points (0..31) ×2 upscale щоб stored growth_points
      # залишалося у звичному 0..62 діапазоні (≤1.6% resolution loss vs
      # legacy 0..63). Так зберігається tokenomic invariant
      # (`Wallet#lock_and_mint!` поріг 10000 SCC), а wire-байт виправлено
      # під дизайн з docs/03_01 §1.6 і docs/03_05 §FW.2.
      growth_points: emission_eligible_growth_points(status_byte, bio_status),
      mesh_ttl: parsed_data[6],
      firmware_version_id: (firmware_id.positive? ? firmware_id : nil),
      bio_status: bio_status
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
    # [SEC.11] Server starts from byte-identical (x₀,y₀,z₀) the firmware
    # used — derived from per-tree K_seed via SilkenNet::SeedDerivation
    # (cold start) or chained from the previous TelemetryLog tail (warm
    # continuation). Persists the trajectory tail so the next packet
    # can chain. No DID-as-seed fallback — every tree is provisioned
    # with K_seed at registration time.
    server_z, lorenz_xyz, cold_start = compute_server_z(tree, log_attributes)
    log_attributes[:z_value]         = server_z
    log_attributes[:lorenz_state_x]  = lorenz_xyz[0]
    log_attributes[:lorenz_state_y]  = lorenz_xyz[1]
    log_attributes[:lorenz_state_z]  = lorenz_xyz[2]
    log_attributes[:cold_start_flag] = cold_start

    # 4.1 DUAL COMPUTATION INTEGRITY (Z Divergence Check)
    # Device повідомляє bio_status з власного Lorenz (Float, mruby).
    # Server розраховує Z (Float, ідентично). Порівнюємо статуси:
    # якщо device каже "homeostasis" а server Z поза межами породи — fraud flag.
    check_z_divergence!(tree, log_attributes)
    check_metabolic_divergence!(tree, log_attributes, status_byte)

    # 5. ФІКСАЦІЯ ТА ЕКОНОМІЧНИЙ ВІДГУК
    commit_telemetry(tree, log_attributes)

  rescue MissingLorenzSeedError
    # [SEC.11] Provisioning pre-condition — must propagate so the caller
    # (UnpackTelemetryWorker) retries or alerts operators.
    raise
  rescue StandardError => e
    # [BROAD RESCUE]: Додано логування стеку викликів для дебагу в продакшені
    trace = e.backtrace.first(5).join("\n")
    Rails.logger.error "🛑 [Telemetry Error] DID #{hex_did || 'UNKNOWN'}: #{e.message}\n#{trace}"
  end

  # [FW.2] AES-128-CCM 25-byte chunk path. Activated via
  # `TELEMETRY_CCM_ENABLED=true`. Chunk layout:
  #
  #   [DID:4][RSSI:1][FrameCounter:4 BE][ciphertext:8][MIC:8]
  #
  # Queen prepends RSSI(1) to the 24B LoRa air packet — RSSI is NOT
  # covered by the CCM MIC (it's receiver-side metadata), DID and
  # FrameCounter form the 8-byte AAD which IS authenticated.
  def process_ccm_chunk(chunk)
    raw_did       = chunk[0..3].unpack1("N")
    hex_did       = format("SNET-%08X", raw_did)
    actual_rssi   = -chunk[4].unpack1("C")
    did_bytes     = chunk[0..3]
    frame_counter = chunk[5..8].unpack1("N")
    ciphertext    = chunk[9..16]
    mic           = chunk[17..24]

    # Queen sentinel — see ECB path. In CCM mode the Queen does not
    # encrypt its own self-telemetry as a fake Soldier (different key
    # domain). If it ever needs to, route via the dedicated CoAP
    # endpoint instead. Until then, drop silently.
    if raw_did.zero?
      Rails.logger.info "👑 [CCM] Drop Queen sentinel packet on CCM path — use CoAP self-telemetry channel instead."
      return
    end

    tree = @trees_cache[hex_did]
    unless tree
      Rails.logger.warn "⚠️ [CCM Uplink] DID #{hex_did} не знайдено в реєстрі."
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      return
    end

    aes_key = tree.hardware_key&.binary_key
    if aes_key.nil? || aes_key.bytesize != 16
      Rails.logger.warn "🛑 [CCM] DID #{hex_did}: missing/invalid LoRa AES-128 key (expected 16 bytes, got #{aes_key&.bytesize.inspect})."
      SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL.increment
      return
    end

    begin
      plaintext = Cryptography::LoraCcm.decrypt(
        key: aes_key,
        did_bytes: did_bytes,
        frame_counter: frame_counter,
        ciphertext: ciphertext,
        mic: mic
      )
    rescue Cryptography::LoraCcm::AuthError => e
      Rails.logger.warn "🛡️ [CCM] DID #{hex_did} fc=#{frame_counter} MIC verification failed: #{e.message}"
      SilkenNet::Metrics::TELEMETRY_CCM_MIC_FAIL_TOTAL.increment
      return
    end

    if frame_counter_replayed?(hex_did, frame_counter)
      Rails.logger.warn "🛡️ [FW.2] DID #{hex_did}: frame_counter=#{frame_counter} already seen within #{CCM_FC_NONCE_TTL.inspect} window."
      SilkenNet::Metrics::TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL.increment
      return
    end

    SilkenNet::Metrics::TELEMETRY_CCM_DECRYPT_OK_TOTAL.increment

    sensor   = plaintext.unpack(CCM_SENSOR_PAYLOAD_FORMAT)
    vcap_mv, temp_c, acoustic, delta_t_s, status_byte, mesh_ctrl = sensor

    unless SAFE_VOLTAGE_RANGE.cover?(vcap_mv) && SAFE_TEMP_RANGE.cover?(temp_c)
      Rails.logger.warn "📡 [CCM Sensor Noise] DID #{hex_did}: vcap=#{vcap_mv} temp=#{temp_c} — out of physical bounds."
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      return
    end

    calibration = tree.device_calibration || tree.build_device_calibration

    # mesh_ctrl bitfield = [ttl:4 (high nibble) | fw_version_epoch_nibble:4 (low nibble)].
    # 4-bit version nibble is an OTA-managed epoch stamp; full
    # firmware_version_id reconstruction needs OTA epoch config which is
    # not landed yet — record the nibble verbatim and skip the
    # check_firmware_mismatch! comparison on the CCM path.
    mesh_ttl     = (mesh_ctrl >> 4) & 0x0F
    fw_nibble    = mesh_ctrl & 0x0F
    bio_status   = interpret_status((status_byte >> 5) & 0x03)

    log_attributes = {
      queen_uid: @gateway&.uid,
      rssi: actual_rssi,
      voltage_mv: calibration.normalize_voltage(vcap_mv),
      temperature_c: calibration.normalize_temperature(temp_c),
      lorenz_temperature_c: temp_c, # [FW.57 F2] raw wire temp — DCI anchor (stripped pre-persist)
      acoustic_events: acoustic,
      metabolism_s: delta_t_s,
      growth_points: emission_eligible_growth_points(status_byte, bio_status),
      mesh_ttl: mesh_ttl,
      firmware_version_id: (fw_nibble.positive? ? fw_nibble : nil),
      bio_status: bio_status
    }

    if acoustic == 255
      SilkenNet::Metrics::TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL.increment
    end

    server_z, lorenz_xyz, cold_start = compute_server_z(tree, log_attributes)
    log_attributes[:z_value]         = server_z
    log_attributes[:lorenz_state_x]  = lorenz_xyz[0]
    log_attributes[:lorenz_state_y]  = lorenz_xyz[1]
    log_attributes[:lorenz_state_z]  = lorenz_xyz[2]
    log_attributes[:cold_start_flag] = cold_start

    check_z_divergence!(tree, log_attributes)
    check_metabolic_divergence!(tree, log_attributes, status_byte)
    commit_telemetry(tree, log_attributes)

  rescue MissingLorenzSeedError
    raise
  rescue StandardError => e
    trace = e.backtrace.first(5).join("\n")
    Rails.logger.error "🛑 [CCM Telemetry Error] DID #{hex_did || 'UNKNOWN'}: #{e.message}\n#{trace}"
  end

  def valid_sensor_data?(data)
    voltage = data[1]
    temp = data[2]
    SAFE_VOLTAGE_RANGE.cover?(voltage) && SAFE_TEMP_RANGE.cover?(temp)
  end

  # [FW.2] Per-DID Frame Counter replay guard. Same SETNX pattern as the
  # SEC.10 panic counter — reject exact FC repeats inside a 25h window.
  # Firmware emits monotonic FC (`RTC_BKP_DR2`), so within the TTL a
  # duplicate means either LoRa mesh retransmission (benign, but we drop
  # to keep tokenomics idempotent) or an active replay attack.
  def frame_counter_replayed?(hex_did, frame_counter)
    nonce_key = "#{CCM_FC_NONCE_KEY_PREFIX}:#{hex_did}:#{frame_counter}"
    inserted = Rails.cache.write(nonce_key, "1", expires_in: CCM_FC_NONCE_TTL, unless_exist: true)
    !inserted
  end

  def ccm_enabled?
    ENV["TELEMETRY_CCM_ENABLED"].to_s.downcase == "true"
  end

  def active_chunk_size
    ccm_enabled? ? CCM_CHUNK_SIZE : ECB_CHUNK_SIZE
  end

  # [SEC.10] Panic Frame Counter anti-replay. Atomic SETNX через Rails.cache
  # (Redis у production). Повертає `true` коли nonce-ключ вже існує (це replay
  # від уже-баченого counter'а), `false` коли ключ свіжий і ми його щойно
  # встановили. TTL 25h гарантує, що nonce переживає 24-годинне replay-вікно
  # і ще трохи. Cold-boot вузла не зламає цей захист — firmware пересіє
  # panic_frame_counter з HRNG (range 0x0001..0xFFFF), тож імовірність
  # зіткнення з живим nonce попереднього втілення ≈ 1/65535.
  def panic_replayed?(hex_did, counter)
    nonce_key = "#{PANIC_NONCE_KEY_PREFIX}:#{hex_did}:#{counter}"
    # write returns false on Redis if `unless_exist: true` and key already exists.
    # Rails.cache (RedisCacheStore) supports the `unless_exist:` option for SETNX.
    inserted = Rails.cache.write(nonce_key, "1", expires_in: PANIC_NONCE_TTL, unless_exist: true)
    !inserted
  end

  # [SEC.11] Single K_seed-derived path. The tree MUST have a
  # provisioned `HardwareKey.binary_lorenz_seed` (asserted on save and
  # required by the model). Returns:
  #   [server_z (Float), lorenz_xyz (Array<Float>), cold_start (Boolean)]
  #
  # * Cold start (`previous` is nil): derive (x₀,y₀,z₀) for today's
  #   epoch_day from K_seed via SilkenNet::SeedDerivation.
  # * Warm continuation: use the previous TelemetryLog tail directly.
  #
  # Raises `MissingLorenzSeedError` if the tree's HardwareKey is missing
  # `lorenz_seed_hex` — this is a system invariant (no field migration,
  # no legacy devices, see SEC.11 hard-cutover decision).
  class MissingLorenzSeedError < StandardError; end

  # [FW.57 F2] The Lorenz/DCI temperature is the device's RAW wire reading (what
  # firmware packed Z from), NOT the drift-corrected `temperature_c` (physical/
  # display). They coincide while `temperature_offset_c == 0` (today), but a
  # future temp drift-calibration would make `temperature_c` diverge → server_z
  # would chaotically miss device_z (a 5°C offset shifts Z by up to ~16 units)
  # and false-flag fraud on every calibrated node. Z + anomaly_ceiling use this;
  # the calibrated value is persisted for physical/display only. 00_07 — FW.57.
  def lorenz_temperature(attributes)
    attributes[:lorenz_temperature_c] || attributes[:temperature_c]
  end

  def compute_server_z(tree, log_attributes)
    seed_bytes = tree.hardware_key&.binary_lorenz_seed
    raise MissingLorenzSeedError, "Tree #{tree.did} has no provisioned K_seed" if seed_bytes.nil?

    previous = previous_lorenz_state_for(tree)
    cold_start = previous.nil?
    x0, y0, z0 = previous || SilkenNet::SeedDerivation.initial_state(seed_bytes)

    z_rounded, x_final, y_final, z_final = SilkenNet::Attractor.calculate_z_from_state(
      x0, y0, z0,
      lorenz_temperature(log_attributes),
      log_attributes[:acoustic_events],
      log_attributes[:metabolism_s],
      log_attributes[:voltage_mv]
    )

    [ z_rounded, [ x_final, y_final, z_final ], cold_start ]
  end

  # Most recent persisted Lorenz tail for this tree, or nil if the
  # device has not sent a packet yet (cold start). We avoid loading
  # whole rows — pluck the three columns and reuse them as the next
  # iteration's initial state.
  def previous_lorenz_state_for(tree)
    row = tree.telemetry_logs
              .where.not(lorenz_state_x: nil, lorenz_state_y: nil, lorenz_state_z: nil)
              .order(created_at: :desc)
              .limit(1)
              .pluck(:lorenz_state_x, :lorenz_state_y, :lorenz_state_z)
              .first
    return nil if row.nil?
    return nil if row.any? { |v| v.nil? || !v.finite? }
    row
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

  # [FW.29] Емісія дозволена лише для homeostasis/stress —
  # канон 04_01/05_02: anomaly зупиняє емісію, tamper їй не довіряє.
  # Захист від wire-байтів, де status=anomaly/tamper приходить із ненульовими
  # gp-бітами: бітфліп у ECB-блоці або firmware VM_ERROR. Старий VM_ERROR
  # (0xFF→0x7F після FW.29-маски) декодувався як tamper + gp=31 → ×2 = 62
  # бали за кожен error-пакет. Firmware-сторона виправлена (VM_ERROR=0x60,
  # gp=0); цей гейт — defense-in-depth для старих прошивок і бітфліпів.
  EMISSION_ELIGIBLE_STATUSES = %i[homeostasis stress].freeze

  def emission_eligible_growth_points(status_byte, bio_status)
    return 0 unless EMISSION_ELIGIBLE_STATUSES.include?(bio_status)

    (status_byte & 0x1F) * 2
  end

  # [E.63/E.64 DCI] Structural conformance for the growth_points wire field —
  # defense-in-depth twin of check_z_divergence! for the metabolic channel
  # (E.63 made delta_t drive growth_points directly on-device, out of the
  # Z-divergence net). Structural ONLY: the wire dT carries the RAW delta_t but
  # firmware packs GP from the EMA-smoothed delta_t (device-only RTC state), so
  # the exact GP↔delta_t recompute is deferred to FW.2 (wire to carry EMA dT) —
  # 00_07 E.63. Here we enforce what is stateless-knowable: firmware
  # guarantees homeostasis → GP ∈ [GP_HOMEO_MIN..GP_HOMEO_MAX], stress → GP_STRESS
  # (anomaly/tamper already zeroed upstream). A violation ⇒ a corrupt ECB block
  # (no MIC in the transitional frame), a forged StatusByte, or stale firmware.
  # Observational (fraud metric, never drops the packet) — same posture as
  # check_z_divergence!.
  def check_metabolic_divergence!(tree, attributes, status_byte)
    wire_gp = status_byte & 0x1F

    conformant =
      case attributes[:bio_status]
      when :homeostasis
        wire_gp.between?(SilkenNet::Attractor::GP_HOMEO_MIN, SilkenNet::Attractor::GP_HOMEO_MAX)
      when :stress
        wire_gp == SilkenNet::Attractor::GP_STRESS
      else
        true # anomaly/tamper GP already neutralised by emission_eligible_growth_points
      end
    return if conformant

    Rails.logger.warn(
      "🔍 [Metabolic Divergence] DID #{tree.did}: status=#{attributes[:bio_status]}, " \
      "wire_growth_points=#{wire_gp} outside the firmware-guaranteed band. " \
      "Structural growth_points conformance violation."
    )
    SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
  end

  # [DUAL COMPUTATION INTEGRITY] [SEC.11] Both server and device now
  # iterate the Lorenz attractor from byte-identical (x₀, y₀, z₀)
  # derived from per-tree K_seed via SilkenNet::SeedDerivation, with the
  # same Float64 kernel. So the raw Z values are numerically comparable.
  # We catch two failure modes:
  #   1. Categorical mismatch — device claims `homeostasis` but server Z
  #      is outside the species/cluster healthy band (or vice versa).
  #      Detects tampered firmware or replay with a forged StatusByte.
  #   2. Numeric divergence — |server_z − device_z| larger than the
  #      tolerance band. Detects a corrupted attractor input on either
  #      side (e.g. wrong K_seed flashed, drift in the silken_sha256 port, etc.).
  # Device Z is reconstructed from the bio_status nibble + growth_points
  # only categorically (the 21-byte packet does not carry raw Z), so the
  # numeric check is a forward-looking hook — kept here behind a metric
  # that surfaces the magnitude even when it is within tolerance.
  # [FW.8] Use Tree#effective_lorenz_thresholds (cluster override >
  # tree_family > global default) so divergence stays consistent with
  # the thresholds firmware was provisioned with.
  # [FW.31] Numeric tolerance band lives behind two ENV feature flags —
  # disabled by default to preserve current categorical behaviour:
  #   - `GAIA_DCI_NUMERIC_TOLERANCE=true` — enables the numeric branch.
  #   - `GAIA_DCI_NUMERIC_EPSILON` (Float, default `0.001`) — the
  #     allowed absolute drift between server_z and the reported
  #     device_z BEFORE flagging fraud.
  # The numeric branch fires only when `attributes[:device_z]` is
  # present (currently never — the LoRa packet does not carry raw Z).
  # Will become active once a future packet revision (post-FW.2 CCM
  # transition) embeds device_z explicitly. Lab measurement on real
  # STM32WLE5JC vs GCP x86-64 must inform the final ε value.
  DEFAULT_DCI_EPSILON = 0.001

  def check_z_divergence!(tree, attributes)
    server_z = attributes[:z_value]
    device_bio_status = attributes[:bio_status]
    return if server_z.nil? || device_bio_status.nil?

    thresholds = tree.effective_lorenz_thresholds
    # [E.64] ρ-відносна стеля аномалії (дзеркало firmware bio_contract.rb): ambient-temp
    # не дає хибний DCI-mismatch. homeostasis = z ≥ min (absolute) і ≤ ρ-relative ceiling.
    ceiling = SilkenNet::Attractor.anomaly_ceiling(lorenz_temperature(attributes), thresholds[:max])
    server_healthy = server_z >= thresholds[:min] && server_z <= ceiling
    device_healthy = device_bio_status == :homeostasis

    # [FW.31] Optional numeric drift check (feature-flagged, default off).
    # Runs IN ADDITION to the categorical check below — never replaces it.
    # When the device packet does carry a raw Z value (future packet
    # revision), drift > ε is treated as a fraud signal even if the
    # categorical buckets agree (catches systematic Z offset attacks).
    if numeric_dci_tolerance_enabled? && attributes[:device_z].present?
      drift = (server_z.to_f - attributes[:device_z].to_f).abs
      if drift > numeric_dci_epsilon
        Rails.logger.warn(
          "🔍 [Z Divergence Numeric] DID #{tree.did}: " \
          "server_z=#{server_z}, device_z=#{attributes[:device_z]}, " \
          "drift=#{drift}, ε=#{numeric_dci_epsilon}. Numeric DCI mismatch."
        )
        SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      end
    end

    if device_healthy != server_healthy
      # [ARCH.41] Before flagging fraud on a warm-start packet, attempt
      # cold-start re-derivation with three epoch_day candidates. A VBAT-loss
      # cold-boot uses firmware's RTC default (≈day 10951) as epoch_day instead
      # of today's, producing a different (x₀,y₀,z₀) that diverges from the
      # server's warm-start chain. If any candidate matches categorically,
      # the packet is legitimate — mark time_unsynced_fallback and request RTC
      # correction via TimeSyncDownlinkWorker instead of counting fraud.
      if !attributes[:cold_start_flag] &&
          try_time_sync_recovery(tree, attributes, thresholds, device_healthy)
        return
      end

      Rails.logger.warn(
        "🔍 [Z Divergence] DID #{tree.did}: device=#{device_bio_status}, " \
        "server_z=#{server_z}, healthy_range=#{thresholds[:min]}..#{thresholds[:max]}. " \
        "Dual Computation Integrity mismatch."
      )
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
    end
  end

  # [ARCH.41] Attempt cold-start re-derivation with three epoch_day candidates
  # to recover from VBAT-loss mismatch (firmware boots with stale RTC default).
  # Returns true and mutates +attributes+ when a candidate matches categorically,
  # preventing a false-positive fraud increment for a legitimate node that simply
  # hasn't received CMD_TIME_SYNC yet.
  #
  # Side effects on match:
  #   * sets attributes[:time_unsynced_fallback] = true
  #   * enqueues TimeSyncDownlinkWorker for the tree's cluster
  def try_time_sync_recovery(tree, attributes, thresholds, device_healthy)
    seed_bytes = tree.hardware_key&.binary_lorenz_seed
    return false if seed_bytes.nil?

    today = SilkenNet::SeedDerivation.current_epoch_day
    candidates = [ today, today - 1, FIRMWARE_RTC_DEFAULT_EPOCH_DAY ]

    temp     = lorenz_temperature(attributes)
    acoustic = attributes[:acoustic_events]
    delta_t  = attributes[:metabolism_s]
    vcap     = attributes[:voltage_mv]

    candidates.each do |epoch_day|
      x0, y0, z0 = SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)
      z_candidate, = SilkenNet::Attractor.calculate_z_from_state(x0, y0, z0, temp, acoustic, delta_t, vcap)
      # [E.64] ρ-відносна стеля (як у check_z_divergence!) — temp вже визначено вище.
      candidate_healthy = z_candidate >= thresholds[:min] &&
        z_candidate <= SilkenNet::Attractor.anomaly_ceiling(temp, thresholds[:max])

      next unless candidate_healthy == device_healthy

      attributes[:time_unsynced_fallback] = true
      Rails.logger.info(
        "[ARCH.41] DID #{tree.did}: epoch_day=#{epoch_day} cold-start candidate matched — " \
        "time_unsynced_fallback set, CMD_TIME_SYNC queued."
      )
      TimeSyncDownlinkWorker.perform_async(tree.cluster_id) if tree.cluster_id.present?
      return true
    end

    false
  end

  # [FW.31] Feature-flag — defaults to false so production behaviour
  # is unchanged until the lab measurement of real ARM↔x86 Float drift
  # confirms a safe ε.
  def numeric_dci_tolerance_enabled?
    ENV["GAIA_DCI_NUMERIC_TOLERANCE"].to_s.downcase == "true"
  end

  # [FW.31] Allowed absolute drift `|server_z - device_z|` before fraud
  # is flagged. ENV override falls back to `DEFAULT_DCI_EPSILON` when
  # the value is missing or fails Float coercion.
  def numeric_dci_epsilon
    raw = ENV["GAIA_DCI_NUMERIC_EPSILON"]
    return DEFAULT_DCI_EPSILON if raw.blank?

    Float(raw)
  rescue ArgumentError, TypeError
    DEFAULT_DCI_EPSILON
  end

  def commit_telemetry(tree, attributes)
    # [L1 QATT] Походження батча (Queen-attestation) — на кожному рядку:
    # downstream (mint-гейти майбутніх рунгів, fraud-аналіз, UI) бачить,
    # чи запис приїхав під валідним підписом Королеви. Єдина точка для
    # обох шляхів (ECB process_chunk + CCM process_ccm_chunk).
    attributes[:gateway_attested] = @gateway_attested

    growth_points = attributes[:growth_points]

    # Транзакція фіксує телеметрію та стан дерева як єдине ціле.
    # Wallet credit, Sidekiq jobs та alert dispatch винесено ЗА межі транзакції (див. нижче).
    log = ActiveRecord::Base.transaction do
      # [FW.57 F2] :lorenz_temperature_c is a transient DCI input (raw wire temp),
      # not a column — strip it before persisting (calibrated temperature_c stays).
      record = tree.telemetry_logs.create!(attributes.except(:lorenz_temperature_c))

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

      record
    end

    # [BUG FIX: Phantom Sidekiq Jobs via EmergencyResponseService]:
    # AlertDispatchService.analyze_and_trigger! виноситься ЗА межі транзакції.
    # Всередині транзакції EmergencyResponseService.call → ActuatorCommand.insert_all
    # → ActuatorCommandWorker.perform_async — воркери потрапляли в Redis ДО commit.
    # При rollback TelemetryLog актуаторні команди вже в черзі, але записів немає.
    # EwsAlert не має FK до TelemetryLog, тому його створення поза транзакцією безпечне:
    # найгірший випадок — пропущений алерт (acceptable), а не phantom job (небезпечно).
    AlertDispatchService.analyze_and_trigger!(log)

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

    # [Codex Phase 5 — Discovery hook]
    # Fire-and-forget probes for each user actively observing this tree.
    # Cheap Redis SMEMBERS; empty when nobody is watching → zero Sidekiq
    # cost. Failures (Redis down, Sidekiq misconfig) are swallowed —
    # Discovery is cosmetic, must never block uplink finalisation.
    enqueue_codex_discovery_probes(tree, log)
  end

  # [Codex Phase 5] Fans the Discovery probe out to one Sidekiq job per
  # active observer. PresenceTracker rescues internally → returns [].
  def enqueue_codex_discovery_probes(tree, log)
    return unless defined?(::Codex::PresenceTracker)

    observers = ::Codex::PresenceTracker.observers_for_tree(tree.id)
    return if observers.empty?

    payload = {
      "tree_id"          => tree.id,
      "trigger_ref_type" => "TelemetryLog",
      "trigger_ref_id"   => log.id_value
    }
    observers.each do |user_id|
      ::Codex::DiscoveryProbeWorker.perform_async(user_id, "telemetry_observation", payload)
    end
  rescue StandardError => e
    Rails.logger.warn "[TelemetryUnpacker] codex hook failed: #{e.class}: #{e.message}"
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
    # Ключі — String: Sidekiq strict_args відкидає Symbol-ключі ArgumentError'ом,
    # який broad rescue process_chunk мовчки ковтав — Sentinel-телеметрія
    # гинула на реальному wire-шляху (ловить e2e spec/integration/
    # coap_telemetry_intake_e2e_spec.rb; HIL :direct маскував stringify_keys).
    GatewayTelemetryWorker.perform_async(
      @gateway.uid,
      {
        "voltage_mv" => parsed_data[1],           # Vcap Королеви (2 байти, мілівольти)
        "temperature_c" => parsed_data[2],        # Температура корпусу Королеви (1 байт)
        "cellular_signal_csq" => parsed_data[3]   # CSQ модему (1 байт, використовує поле Acoustic)
      }
    )
    Rails.logger.info "👑 [Sentinel] Королева #{@gateway.uid} повідомляє: #{parsed_data[1]}mV, #{parsed_data[2]}°C, CSQ=#{parsed_data[3]}"
  end
end
