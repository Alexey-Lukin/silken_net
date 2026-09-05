# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TelemetryUnpackerService < ApplicationService
  # [DID:4][RSSI:1][Payload:16] = 21 байт — ECB transitional format (pre-FW.2)
  CHUNK_SIZE     = 21
  ECB_CHUNK_SIZE = 21

  # [FW.2 wire-rev2] CCM 29-byte chunk = Queen-prepended RSSI(1) + 28B LoRa
  # air format ([DID:4][gossip:1][FC:3 BE] AAD + [ciphertext:12] + [MIC:8]).
  # Enabled via ENV `TELEMETRY_CCM_ENABLED=true`; defaults to ECB so the
  # production wire format is unchanged until firmware ships CCM emission.
  # Rev2 rationale + повна розкладка: docs/03_05 wire-budget ledger.
  CCM_CHUNK_SIZE             = 31 # wire-rev2.1: air 30B + Queen |RSSI| (E.63 (г))
  # Vcap(2BE) Temp(i8) Acoustic(u8) dt(2BE, RAW) Status(u8) MeshCtrl(u8)
  # DeviceZ(2BE ×512, 0xFFFF=none) Diag(u8) VpdIndex(u8)
  # EmaDeltaT(2BE — «wire = вхід GP», E.63 (г): stateless recompute)
  CCM_SENSOR_PAYLOAD_FORMAT  = "n c C n C C n C C n"
  CCM_DEVICE_Z_NONE          = 0xFFFF
  CCM_DEVICE_Z_SCALE         = 512.0
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

  # [PERF.1] Вікно ШВИДКОГО ШЛЯХУ пошуку хвоста Лоренца — параметр ПРУНІНГУ,
  # не поріг тиші. Число partition-shaped: партиції `telemetry_logs` місячні
  # (`04_01 §0`), тож 30 діб торкаються щонайбільше двох місячних листів.
  # Виміряно EXPLAIN'ом на порожній test-БД: без межі Merge Append по 9 листах
  # (cost 1.39..73.74), з межею — по 3 (cost 0.43..24.53); `telemetry_logs_default`
  # не прунить НІКОЛИ, тож одна проба — постійна підлога, а решта росте
  # +1 щомісяця (retention/detach-політики не існує).
  # ⚠️ Свідомо НЕ дорівнює порогу тиші дерева (`Tree.silent`, 24h [transitional]):
  # той відповідає «чи дерево живе», цей — «де дешевше шукати першим». Промах
  # вікна коштує один зайвий запит, ніколи — іншої відповіді.
  LORENZ_TAIL_FAST_WINDOW = 30.days

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

  # [ARCH.41-B] Wire-sentinel «час невідомий»: Soldier без жодного beacon'а
  # (cold-boot після VBAT-loss / Королева мовчить) шле 0xFE замість
  # acoustic-лічильника, а Лоренц НА ПРИСТРОЇ рахується з acoustic=0 —
  # дзеркальна нейтралізація тут (до DCI) тримає паритет. Реальні 254
  # неможливі (firmware клампить у 0xFD); 255 лишається FW.22-сатурацією.
  # Дім: 03_04 §2.1; firmware-дзеркало — Soldier_Acoustic_Wire_Value.
  ACOUSTIC_TIME_UNCERTAIN_SENTINEL = 0xFE

  # DID-сентинел: Королева передає власну телеметрію з DID = 0x00000000
  QUEEN_SENTINEL_DID = "0"

  # [L1 QATT] gateway_attested: батч пройшов Ed25519-верифікацію Королеви
  # (UnpackTelemetryWorker) — прапор протягується у кожен TelemetryLog-рядок.
  # [ARCH.41] `received_at` — момент ПРИЙОМУ пакета, привезений із job-аргументів
  # (`UnpackTelemetryWorker`), тобто стабільний між Sidekiq-ретраями. Він є єдиним
  # чесним якорем доби для cold-start деривації Лоренца: і `Time.now.utc`, і
  # `telemetry_log.created_at` рухаються разом зі СПРОБОЮ, а пристрій деривує зі
  # свого RTC-дня, зафіксованого в момент передачі. `nil` ⇒ «зараз» (bench/HIL).
  def initialize(binary_batch, gateway_id = nil, gateway_attested: false, received_at: nil)
    @binary_batch = binary_batch
    @gateway = Gateway.find_by(id: gateway_id)
    @gateway_attested = gateway_attested
    @received_at = received_at
    @trees_cache = {}
    @latest_firmware_id = nil
  end

  def perform
    return if @binary_batch.blank?

    chunk_size = active_chunk_size
    chunks = @binary_batch.b.scan(/.{1,#{chunk_size}}/m)

    # ⚡ [ОПТИМІЗАЦІЯ N+1]: Спершу витягуємо всі DID з батчу
    preload_trees(chunks, chunk_size)

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
  def preload_trees(chunks, chunk_size)
    # Дзеркалимо guard із #perform: обрізаний хвостовий chunk (коротший за
    # chunk_size) там пропускається, тож і тут не витягуємо з нього DID — на
    # коротшому за uint32 `unpack1("N")` дає nil, і `format` впав би TypeError
    # ще до того, як perform встиг би його скіпнути.
    dids = chunks.filter_map do |c|
      next if c.bytesize < chunk_size

      format("SNET-%08X", c[0..3].unpack1("N"))
    end.uniq
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

    # [ARCH.54] DID = 0x00000000 у батчі — БІЛЬШЕ НЕ легальний запис:
    # пульс Королеви живе у підписаному header'і QATT-v2 конверта
    # (UnpackTelemetryWorker#enqueue_envelope_health), не псевдодеревом у
    # телеметрії. Стара милиця персистила uptime як voltage і cache_count
    # як CSQ (Солдатські окуляри) — 28B-запис з нулем тут = спуф/легасі.
    if raw_did.zero?
      Rails.logger.info "👑 [ARCH.54] Drop DID=0 запису на ECB-шляху — health їде QATT-v2 конвертом."
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

    # [FW.29] PanicFlag (біт 7 StatusByte) — єдина надійна ознака панічного
    # пакета на дроті (acoustic=255 колізує з FW.22-сатурацією). Персистимо
    # на записі: панічність queryable + relayed_via_mesh? знає стартовий TTL.
    panic = status_byte.anybits?(PANIC_FLAG_BIT)

    # [SEC.10] Frame Counter anti-replay для panic packets.
    # Соломонова сторожа панічного каналу: panic_frame_counter (BE у байтах
    # 14..15 = pad_data[2..3]) інкрементується soldier'ом перед кожним
    # emergency TX. Тут ми ловимо повторюваний nonce через Redis SETNX —
    # replay одного «chainsaw detected» = false fire alert + евакуація +
    # втрата довіри до системи. Поза-panic пакети нічого не платять
    # (counter-перевірка пропускається).
    if panic
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
      # [FW.18b] Байт 11 — бітфілд [thr_invalid:5 | TTL:3], One-Home
      # firmware/common/ttl_byte.h. Стара прошивка (чистий TTL ≤ 5) дає
      # ті самі нижні біти і counter=0 — маска backward-сумісна.
      mesh_ttl: parsed_data[6] & 0x07,
      firmware_version_id: (firmware_id.positive? ? firmware_id : nil),
      bio_status: bio_status,
      panic: panic
    }

    # [ARCH.41-B] sentinel 0xFE → нейтралізація ДО DCI + CMD_TIME_SYNC.
    apply_time_uncertain_sentinel!(tree, log_attributes, hex_did)

    # [FW.18b] Верхні 5 біт TTL-байта — saturating лічильник відкинутих
    # OTA-порогів (03_03 §5.4). Метрика без per-DID мітки (cardinality
    # budget 06_03 §2.9, патерн FW.22) — конкретне дерево і значення
    # лічильника атрибутуються warn-логом.
    threshold_invalid = (parsed_data[6] >> 3) & 0x1F
    if threshold_invalid.positive?
      SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL.increment
      Rails.logger.warn(
        "🎚️ [FW.18b] #{hex_did}: відкинуті OTA-пороги TinyML — лічильник #{threshold_invalid}" \
        "#{threshold_invalid == 31 ? ' (wire-сатурація, реальне значення може бути більшим)' : ''}"
      )
    end

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

  # [FW.2 wire-rev2.1] AES-128-CCM 31-byte chunk path. Activated via
  # `TELEMETRY_CCM_ENABLED=true`. Chunk layout:
  #
  #   [DID:4][RSSI:1][gossip_ts_lsb:1][FrameCounter:3 BE][ciphertext:14][MIC:8]
  #
  # Queen prepends RSSI(1) to the 30B LoRa air packet — RSSI is NOT
  # covered by the CCM MIC (it's receiver-side metadata); DID, gossip byte
  # and FrameCounter form the 8-byte AAD which IS authenticated. The
  # gossip byte is addressed to neighbouring Soldiers (FW.20-S2 #5) —
  # backend only authenticates it, no server-side consumption.
  def process_ccm_chunk(chunk)
    raw_did       = chunk[0..3].unpack1("N")
    hex_did       = format("SNET-%08X", raw_did)
    actual_rssi   = -chunk[4].unpack1("C")
    did_bytes     = chunk[0..3]
    gossip_ts_lsb = chunk[5].unpack1("C")
    frame_counter = ("\x00".b + chunk[6..8]).unpack1("N")
    ciphertext    = chunk[9..22]
    mic           = chunk[23..30]

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
        gossip_ts_lsb: gossip_ts_lsb,
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
    vcap_mv, temp_c, acoustic, delta_t_s, status_byte, mesh_ctrl,
      device_z_raw, diag_byte, vpd_index, ema_delta_t_s = sensor

    unless SAFE_VOLTAGE_RANGE.cover?(vcap_mv) && SAFE_TEMP_RANGE.cover?(temp_c)
      Rails.logger.warn "📡 [CCM Sensor Noise] DID #{hex_did}: vcap=#{vcap_mv} temp=#{temp_c} — out of physical bounds."
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      return
    end

    calibration = tree.device_calibration || tree.build_device_calibration

    # mesh_ctrl bitfield = [ttl:4 (high nibble) | fw_version_epoch_nibble:4 (low nibble)].
    # Low-nibble = C-image epoch (compile-time, bytecode-OTA її не міняє) —
    # contract-версію несе vpd-байт (SEC.20, нижче), нібл лишається транзієнтом.
    mesh_ttl     = (mesh_ctrl >> 4) & 0x0F
    bio_status   = interpret_status((status_byte >> 5) & 0x03)

    # [SEC.20] vpd-байт тимчасово (до BME280/HW.32 → rev3) несе contract-звіт
    # [reverted:1 | id7] — складаємо у спільні 16 біт fw_report-семантики
    # (semantic-біт ставимо самі: CCM-прошивка з патчем шле звіт завжди),
    # щоб TelemetryLog-хелпери працювали однаково для обох ер.
    fw_report = TelemetryLog::FW_REPORT_SEMANTIC_BIT |
                (vpd_index.anybits?(0x80) ? TelemetryLog::FW_REPORT_REVERTED_BIT : 0) |
                (vpd_index & 0x7F)

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
      firmware_version_id: fw_report,
      bio_status: bio_status,
      # [FW.29] PanicFlag — той самий StatusByte їде і в CCM-плейні
      # (Soldier_Build_CCM_LoRa_Packet приймає status_byte як є).
      panic: status_byte.anybits?(PANIC_FLAG_BIT)
    }

    # [FW.31 Gate D] device_z з шифртексту (wire-rev2 bytes 16..17,
    # фіксована точка ×512): живить numeric DCI-гілку check_z_divergence!.
    # Сентинель 0xFFFF = «Лоренц цього циклу не рахувався» (ARCH.41-C
    # grace) → атрибут відсутній, numeric branch чесно пропускається.
    # Транзієнт як lorenz_temperature_c — стрипається перед persist.
    if device_z_raw != CCM_DEVICE_Z_NONE
      log_attributes[:device_z] = device_z_raw / CCM_DEVICE_Z_SCALE
    end

    # [E.63 (г)] EMA-delta_t з шифртексту (wire-rev2.1 bytes 20..21) —
    # контракт «wire = вхід GP»: живить точний stateless recompute у
    # check_metabolic_divergence!. Транзієнт (не персистить, KENOSIS) —
    # server-side EMA-аналітику покриває raw dT (03_01 §13.6 / E.37).
    log_attributes[:ema_delta_t_s] = ema_delta_t_s

    # [FW.18b] diag-байт (wire-rev2 byte 18): [thr_invalid:5 | fauna_mode:1 |
    # fauna_skip:1 | fc_degraded:1] — дзеркало Pack_FW2_Diag (lora_ccm.h).
    # Той самий cardinality-патерн, що ECB-шлях: метрика без per-DID мітки,
    # конкретне дерево — у warn-лозі.
    threshold_invalid = (diag_byte >> 3) & 0x1F
    if threshold_invalid.positive?
      SilkenNet::Metrics::TINYML_THRESHOLD_INVALID_REPORTS_TOTAL.increment
      Rails.logger.warn(
        "🎚️ [FW.18b] #{hex_did}: відкинуті OTA-пороги TinyML — лічильник #{threshold_invalid}" \
        "#{threshold_invalid == 31 ? ' (wire-сатурація, реальне значення може бути більшим)' : ''}"
      )
    end
    if diag_byte.anybits?(0x02) # fauna_skip [FW.42]
      SilkenNet::Metrics::FAUNA_SKIP_REPORTS_TOTAL.increment
      Rails.logger.warn "🦉 [FW.42] #{hex_did}: fauna-сесію пропущено через низький Vcap (брауноут-захист)."
    end
    if diag_byte.anybits?(0x01) # fc_degraded [FW.2 I-HW]
      SilkenNet::Metrics::FW2_FC_DEGRADED_REPORTS_TOTAL.increment
      Rails.logger.warn "🛡️ [FW.2] #{hex_did}: інваріант FC high-water втрачено (Flash відмовляє) — nonce-гарантія деградована."
    end

    # [HW.32] Калібрований VPD у цьому байті ще не живе (шкала index→kPa
    # прийде з BME280; vpd-колонка чекає) — до того байт несе SEC.20-звіт ↑.

    # [ARCH.41-B] sentinel 0xFE → нейтралізація ДО DCI + CMD_TIME_SYNC.
    apply_time_uncertain_sentinel!(tree, log_attributes, hex_did)

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
  # (Solid Cache / PostgreSQL у production — НЕ Redis; `unless_exist: true` там
  # атомарний, [ARCH.105]). Повертає `true` коли nonce-ключ вже існує (це replay
  # від уже-баченого counter'а), `false` коли ключ свіжий і ми його щойно
  # встановили. TTL 25h гарантує, що nonce переживає 24-годинне replay-вікно
  # і ще трохи. Cold-boot вузла не зламає цей захист — firmware пересіє
  # panic_frame_counter з HRNG (range 0x0001..0xFFFF), тож імовірність
  # зіткнення з живим nonce попереднього втілення ≈ 1/65535.
  def panic_replayed?(hex_did, counter)
    nonce_key = "#{PANIC_NONCE_KEY_PREFIX}:#{hex_did}:#{counter}"
    # write returns false if `unless_exist: true` and the key already exists.
    # Rails.cache is Solid Cache (PostgreSQL) in production, and its `unless_exist:`
    # is a genuine SET NX [ARCH.105] — do not read "Redis" into this path.
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

  # [ARCH.41] Доба для cold-start деривації. One-Home: обидва боки тракту
  # (тут і `try_time_sync_recovery`) мусять називати добу ОДНАКОВО, інакше
  # recovery шукав би збіг з іншою сіткою днів, ніж основний шлях.
  # ⚠️ `current_epoch_day` лишається фолбеком лише для викликів БЕЗ прийому
  # (bench/HIL/спеки) — у проді обидва enqueuer'и передають мітку явно.
  def derivation_epoch_day
    return SilkenNet::SeedDerivation.current_epoch_day if @received_at.nil?

    @received_at.utc.to_i / 86_400
  end

  def compute_server_z(tree, log_attributes)
    seed_bytes = tree.hardware_key&.binary_lorenz_seed
    raise MissingLorenzSeedError, "Tree #{tree.did} has no provisioned K_seed" if seed_bytes.nil?

    previous = previous_lorenz_state_for(tree)
    cold_start = previous.nil?
    # 🔴 [ARCH.41] Доба деривації береться з моменту ПРИЙОМУ, не з моменту
    # ОБРОБКИ. Доти тут стояв `initial_state(seed_bytes)` без другого аргументу, тобто дефолт
    # `current_epoch_day` = `Time.now.utc`: Sidekiq-ретрай через межу півночі UTC
    # давав ІНШИЙ день → іншу стартову точку (x₀,y₀,z₀) → категоричний DCI-мисматч
    # на ЧЕСНОМУ дереві. ⚠️ І саме тут його нікому зловити: `try_time_sync_recovery`
    # (ARCH.41-A) гейтований `!cold_start_flag`, а це — гілка cold_start.
    x0, y0, z0 = previous || SilkenNet::SeedDerivation.initial_state(seed_bytes, derivation_epoch_day)

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
  # [PERF.1] Пошук ДВОКРОКОВИЙ, і це оптимізація прунінгу, а НЕ зміна семантики:
  # обмежене вікно питається першим, безмежний фолбек стоїть за ним, тож метод
  # повертає рівно той самий рядок, що й доти. Якщо в вікні щось є — воно й є
  # найновішим узагалі (вікно прилягає до «зараз»), тож фолбек іде лише коли
  # дерево мовчало довше за вікно або не говорило ніколи.
  #
  # 🔴 Варіант із `00_07 PERF.1` («просто додати нижню межу `2.months.ago`»)
  # СВІДОМО не реалізовано — він міняв би поведінку DCI, а не лише вартість:
  # мовчазне дерево ставало б cold-start'ом, тоді як прошивка вирішує cold-start
  # ВИКЛЮЧНО за маркером RTC (`DR19 == LORENZ_STATE_MAGIC`, firmware/soldier/main.c),
  # без жодної часової компоненти — тобто доки живий VBAT, пристрій тягне теплий
  # ланцюг після скільки завгодно довгої тиші, і серверне вікно розсинхронізувало б
  # їх однобічно. Канон каже те саме прямим текстом: cold-derive належить дереву,
  # у якого НЕМАЄ історії (`03_04 §2.1`). Плюс `2.months` було б ДРУГИМ порогом
  # тиші в системі, у 60 разів більшим за наявний `Tree.silent` (SILENCE-1, сам
  # ще не відкалібрований).
  def previous_lorenz_state_for(tree)
    # ⚠️ `where.not` із кількома ключами дає ЗАПЕРЕЧЕННЯ КОН'ЮНКЦІЇ, тобто
    # `x IS NOT NULL OR y IS NOT NULL OR z IS NOT NULL` (видно в EXPLAIN), а не
    # «всі три непорожні». Лишено свідомо: трійка пишеться атомарно, а частковий
    # рядок мусить дати cold-start (його ловить finite-гард нижче), НЕ мовчазне
    # продовження з давнішого хвоста через розрив ланцюга.
    # rubocop:disable Rails/WhereNotWithMultipleConditions -- АБО-семантика тут
    # СВІДОМА й пояснена вище: частковий рядок мусить дати cold-start.
    scope = tree.telemetry_logs
                .where.not(lorenz_state_x: nil, lorenz_state_y: nil, lorenz_state_z: nil)
    # rubocop:enable Rails/WhereNotWithMultipleConditions

    row = lorenz_tail_row(scope.where(created_at: LORENZ_TAIL_FAST_WINDOW.ago..)) ||
          lorenz_tail_row(scope)

    return nil if row.nil?
    return nil if row.any? { |v| v.nil? || !v.finite? }
    row
  end

  def lorenz_tail_row(scope)
    scope.order(created_at: :desc)
         .limit(1)
         .pluck(:lorenz_state_x, :lorenz_state_y, :lorenz_state_z)
         .first
  end

  def interpret_status(code)
    # Відповідає enum :bio_status у моделі TelemetryLog.
    # [SLASH-1] Код 3 = BIO_STATUS_VM_ERROR (софт-збій прошивки), НЕ tamper:
    # mruby pack_status_byte повертає лише 0..2, фізичний tamper їде PANIC_FLAG.
    case code
    when 0 then :homeostasis
    when 1 then :stress
    when 2 then :anomaly
    when 3 then :vm_error
    end
  end

  # [FW.29] Емісія дозволена лише для homeostasis/stress —
  # канон 04_01/05_02: anomaly зупиняє емісію, vm_error їй не довіряє.
  # Захист від wire-байтів, де status=anomaly/vm_error приходить із ненульовими
  # gp-бітами: бітфліп у ECB-блоці або firmware VM_ERROR. Старий VM_ERROR
  # (0xFF→0x7F після FW.29-маски) декодувався як status=3 + gp=31 → ×2 = 62
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
  # (anomaly/vm_error already zeroed upstream). A violation ⇒ a corrupt ECB block
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
        true # anomaly/vm_error GP already neutralised by emission_eligible_growth_points
      end

    if conformant
      # [E.63 (г), wire-rev2.1] ТОЧНА гілка: кадр несе EMA-delta_t — САМЕ те
      # число, що з'їла metabolic_health на пристрої (контракт «wire = вхід
      # GP», Soldier Фаза-3) → stateless recompute мусить збігтися БАЙТ-точно.
      # OBSERVATIONAL до bench-калібрування порогів (placeholder 600/7200 —
      # 03_04 §4.3): warn + метрика, мінт НЕ гейтиться (клас z-DCI: ловить
      # баги/десинк, не anti-fraud — консистентну брехню обома полями CCM+MIC
      # однаково не ловить). ECB-шлях ema не несе (nil) — гілка скипається.
      ema = attributes[:ema_delta_t_s]
      return if ema.nil? || attributes[:bio_status] != :homeostasis

      expected_gp = SilkenNet::Attractor.expected_homeostasis_gp(ema)
      return if wire_gp == expected_gp

      Rails.logger.warn(
        "🔍 [Metabolic Divergence · exact] DID #{tree.did}: wire_gp=#{wire_gp} ≠ " \
        "recompute(ema=#{ema}s)=#{expected_gp}. Contract «wire = вхід GP» broken " \
        "(threshold desync / EMA-state corruption / firmware bug)."
      )
      SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL.increment
      return
    end

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
  # [FW.8] Судимо за `Tree#device_lorenz_thresholds` — порогами, ЧИННИМИ НА
  # ПРИСТРОЇ, а не за бажаними per-species.
  # ⛔ Не повертати сюди `effective_lorenz_thresholds` під підставою «щоб
  # розходження лишалось консистентним із порогами, якими провіженили прошивку»:
  # прошивку ними НЕ провіженять, тож для родини з `critical_z_min > 2.0` чесний
  # пакет дає категоричний mismatch і P0-алерт на НЕВИННОМУ дереві.
  # Механізм, виміри й подія повернення per-species — `03_04 §5.3`.
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

    thresholds = tree.device_lorenz_thresholds
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

    # [ARCH.41] Та сама доба, що й у cold-derive (`derivation_epoch_day`) — інакше
    # recovery шукав би збіг на ІНШІЙ сітці днів, ніж основний шлях, і «today−1»
    # перестав би означати сусідню добу того самого прийому.
    today = derivation_epoch_day
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

  # [ARCH.41-B] Явний sentinel «час невідомий» з прошивки (acoustic = 0xFE).
  # На відміну від recovery (ARCH.41-A, детектив постфактум) — це голос самого
  # Солдата: «мій epoch_day застарілий». Нейтралізуємо acoustic до 0 ДО DCI
  # (пристрій рахував Лоренц з 0 — дзеркало Soldier_Acoustic_Wire_Value),
  # ставимо time_unsynced_fallback і одразу просимо CMD_TIME_SYNC. Побічний
  # виграш нейтралізації: ML-фіча `max_acoustic` бачить 0, а не фальшиві 254
  # «події» — і це не про один інсайт, а про ВИБІРКУ: те саме число осідає в
  # `AiInsight#reasoning`, з якого тренується модель (`ai_train.rake`), тож
  # ненейтралізований сентинел ставав би піком акустики в тренувальних даних.
  # DCI при цьому НЕ обходиться —
  # sentinel не може служити маскою для підробленого Z (fraud-логіка жива).
  def apply_time_uncertain_sentinel!(tree, attributes, hex_did)
    return unless attributes[:acoustic_events] == ACOUSTIC_TIME_UNCERTAIN_SENTINEL

    attributes[:acoustic_events] = 0
    attributes[:time_unsynced_fallback] = true
    Rails.logger.info(
      "🕰️ [ARCH.41-B] DID #{hex_did}: acoustic sentinel 0xFE — Soldier ще не чув " \
      "beacon'а (cold-boot після VBAT-loss?). Лоренц з acoustic=0; CMD_TIME_SYNC у чергу."
    )
    TimeSyncDownlinkWorker.perform_async(tree.cluster_id) if tree.cluster_id.present?
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
      # [FW.31] :device_z (wire-rev2) — той самий транзієнт-клас: вхід numeric
      # DCI, серверна істина z_value вже зберігається окремо.
      record = tree.telemetry_logs.create!(attributes.except(:lorenz_temperature_c, :device_z, :ema_delta_t_s))

      # [СИНХРОНІЗАЦІЯ]: Оновлюємо денормалізований вольтаж для мапи без N+1
      tree.mark_seen!(record.voltage_mv)

      # ⛔ [ARCH.84, ⚖️ 2026-08-16] Тут стояв `update_health_streak!` — `UPDATE trees`
      # на КОЖЕН chunk, поверх `mark_seen!` того ж рядка, з row-lock до кінця
      # транзакції. Знято разом з усією anti-flapping-петлею: єдиний її читач мав
      # закривати біо-тривоги, а критерій не спростовував власний тригер (розбір —
      # `TelemetryLog` §знято + `00_07` ARCH.84).

      # [OTA MISMATCH]: Якщо дерево повідомляє firmware_version_id, що відрізняється від
      # актуальної прошивки — позначаємо дерево як fw_pending для повторної роздачі OTA.
      check_firmware_mismatch!(tree, record.firmware_version_id)

      record
    end

    # [OBSERVABILITY / INF.26] Лічимо ЗАКОМІЧЕНІ чанки — і саме тому інкремент стоїть
    # ПІСЛЯ транзакції, а не всередині неї. Prometheus-реєстр не транзакційний: інкремент
    # усередині блоку переживає `ROLLBACK`, тож лічильник із докстрінгом «processed» рахував
    # би й ті чанки, яких у БД не існує. Це та сама межа, за якою вище винесено credit,
    # Sidekiq-джоби й alert-dispatch — метрика просто не була в тому переліку.
    SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL.increment

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
    # (напр., `check_firmware_mismatch!` кине) — jobs НЕ
    # потраплять до Redis, бо виконання не дійде до цих рядків.
    # Раніше: jobs ставились у чергу всередині transaction — при rollback TelemetryLog
    # запис не існував, але IotexVerificationWorker вже був у Redis (5 марних ретраїв
    # на web3_critical чергу).
    # [OPS.37 / ARCH.118] The external leg is ACTIVATION-GATED (`configured?` — one home):
    # unconfigured ⇒ no job at all, because a job that can only raise buys executions (6) and
    # ~30 Redis commands per record for nothing (Upstash bills per command, INF.28). Streamr's
    # twin leg stood here until ⚖️ 2026-09-03 — REMOVED, not gated (05_01 §1): an observer that
    # gates nothing and needs its own broker node in the stack duplicates our witness, adds none.
    IotexVerificationWorker.perform_async(log.id_value, log.created_at.iso8601(6)) if Iotex::W3bstreamVerificationService.configured?

    # [BLOCKER FIX: Database Locking — Wiki 04_01]
    # Нарахування балів у гаманець Солдата ПОЗА основною транзакцією.
    # credit! відкриває власну коротку транзакцію з pessimistic lock (SELECT ... FOR UPDATE).
    # Lock тримається лише мілісекунди замість усієї тривалості commit_telemetry.
    # growth_points записані в TelemetryLog — аудит-трейл для reconciliation при збоях.
    #
    # [DIFF.2 FIX: carbon_sequestration_coefficient]:
    # Зважуємо бали росту за коефіцієнтом секвестрації породи дерева.
    # Дуб (Quercus) акумулює вуглець швидше за Сосну (Pinus) — справедливий розподіл SCC.
    # ⚠️ [OPS.33] Захист несе ВНУТРІШНІЙ гард: при нулі `weighted_growth_points`
    # теж дає нуль, тож зовнішній — коротке замикання (уникає підняття
    # `tree_family`), а не друга лінія оборони. Знімати внутрішній, спираючись
    # на зовнішній, не можна: зважування може дати нуль і з ненульового входу.
    if growth_points.positive?
      weighted_points = tree.tree_family&.weighted_growth_points(growth_points) || growth_points
      tree.wallet.credit!(weighted_points) if weighted_points.positive?
    end
  end

  # [OTA MISMATCH DETECTION]: Перевіряємо, чи прошивка дерева актуальна.
  # [SEC.20] Порівнюємо ЛИШЕ звіти нової семантики (semantic-біт): вони несуть
  # contract-id по модулю 14 біт. Legacy-кадри везуть C-image константу, яку
  # bytecode-OTA не міняє — старе пряме порівняння з BioContractFirmware.id
  # було яблуками-з-грушами (вічний fw_pending після першої ж кампанії).
  # Кешуємо latest_firmware_id на рівні батчу (1 SQL-запит на весь пакет).
  def check_firmware_mismatch!(tree, reported_firmware_id)
    return if reported_firmware_id.blank?
    return unless reported_firmware_id.anybits?(TelemetryLog::FW_REPORT_SEMANTIC_BIT)

    latest_id = latest_tree_firmware_id
    return if latest_id.nil?
    reported_contract = reported_firmware_id & TelemetryLog::FW_REPORT_ID_MASK
    return if reported_contract == (latest_id & TelemetryLog::FW_REPORT_ID_MASK)

    return unless tree.firmware_fw_idle? || tree.firmware_fw_completed? || tree.firmware_fw_failed?

    # 🔴 [ARCH.85] СПОСТЕРЕЖНЕ, ще не дієве — присуд власника 2026-08-14.
    #
    # Цей тракт не біг ЖОДНОГО разу: писальників `target_hardware_type` у `app/`
    # було нуль до фіксу форми завантаження прошивки, тож `latest_tree_firmware_id`
    # завжди віддавав `nil` і виконання виходило рядком вище. Щойно хтось
    # задеплоїть типований реліз, перший в історії прогін відбудеться ОДРАЗУ в
    # полі, на гарячому шляху телеметрії, і при хибній деривації позначив би
    # `fw_pending` весь флот — а downlink-ретрансміту в цього стану немає
    # (`FW.63`). Клас «інертне детонує в день активації».
    #
    # ⚠️ Прапорця-перемикача тут свідомо НЕМА: забутий прапорець стає тихо
    # вимкненим захистом (прецедент INF.11 — Hadron був єдиний flag-only, і це
    # захарднили). Замість нього — гілка, що ПИШЕ спостереження й не міняє
    # стану. Дієвий рядок (`update_all(firmware_update_status: :fw_pending)`)
    # знято, а не закоментовано: закоментований код гниє мовчки, а `git log -S`
    # його віддає. Повертати — ПІСЛЯ того, як цей лічильник покаже правдоподібні
    # числа на живому флоті.
    #
    # ⚠️ Стрілка тут вела в `ARCH.85`, а той у §🗄️ і цієї умови НЕ несе: реф
    # резолвився ідеально, зміст помер. Живий дім тригера — `00_07` ARCH.59
    # (residual `fw_pending`-споживача), і саме там його треба питати.
    Rails.logger.info(
      "🔄 [ARCH.85 OTA Mismatch · спостереження] Дерево #{tree.did}: " \
      "contract #{reported_contract} != latest #{latest_id}. Стан НЕ змінено."
    )
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
end
