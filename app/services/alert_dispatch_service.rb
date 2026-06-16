# frozen_string_literal: true

class AlertDispatchService
  # Fallback пороги (Hardware Truths), якщо в БД нічого не вказано
  DEFAULT_FIRE_TEMP_C = 60
  DEFAULT_SEISMIC_THRESHOLD = 200
  DEFAULT_PEST_THRESHOLD = 50

  # [SEC.10]: Per-DID rate limiting для emergency/panic alert creation.
  # Захист від replay attack та injection forged panic packets.
  # Максимум MAX_ALERTS_PER_DID_PER_WINDOW критичних алертів від одного DID
  # за DID_RATE_LIMIT_WINDOW. Перевищення → лог + ігнорування.
  MAX_ALERTS_PER_DID_PER_WINDOW = 5
  DID_RATE_LIMIT_WINDOW = 1.minute

  def self.analyze_and_trigger!(telemetry_log)
    tree = telemetry_log.tree
    cluster = tree.cluster
    family = tree.tree_family

    # --- 0. АДАПТИВНІ ПОРОГИ (The Biome Adaptation) ---
    # Пожежа: беремо з кластера (біом), породи дерева або дефолт
    # [FIX]: Безпечний доступ до cluster — дерево може бути без кластера (одиноке дерево)
    fire_limit = cluster&.custom_fire_threshold || family.fire_resistance_rating || DEFAULT_FIRE_TEMP_C

    # Шкідники: коригується індексом сокоруху (чим соковитіше дерево, тим вищий фон)
    pest_limit = family.sap_flow_index ? (DEFAULT_PEST_THRESHOLD * family.sap_flow_index) : DEFAULT_PEST_THRESHOLD

    # 1. ВАНДАЛІЗМ (Zero-Trust Breach)
    # [ВИПРАВЛЕНО]: Розділено логіку тампера та низького вольтажу.
    # Якщо корпус відкрито — дані скомпрометовані, подальший аналіз безглуздий.
    # Якщо ж вольтаж впав через розряд батареї (без тампера) — дерево все ще
    # може горіти, тому ми фіксуємо тривогу, але НЕ перериваємо аналіз.
    if telemetry_log.bio_status_tamper_detected?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :vandalism_breach,
        message: "🚨 КРИТИЧНО: Втручання в корпус пристрою! DID: #{tree.did}"
      )
      return
    end

    if telemetry_log.voltage_mv < 100
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :system_fault,
        message: "🚨 КРИТИЧНО: Втрата живлення (#{telemetry_log.voltage_mv} мВ)! DID: #{tree.did}"
      )
      # НЕ робимо return — продовжуємо аналіз пожежі/сейсміки,
      # бо низький вольтаж може бути розрядом батареї, а не вандалізмом.
    end

    # 2. ПОЖЕЖА або ПИЛКА (Thermal and Acoustic Chaos)
    # [АДАПТИВНО]: Поріг тепер залежить від біома
    if telemetry_log.temperature_c >= fire_limit || telemetry_log.bio_status_anomaly?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :fire_detected,
        message: "🔥 КАТАСТРОФА: Температура #{telemetry_log.temperature_c}°C (Поріг: #{fire_limit}). Ризик пожежі/вирубки!"
      )
      return
    end

    # 3. ЗЕМЛЕТРУС (Seismic Pulse)
    if telemetry_log.acoustic_events >= DEFAULT_SEISMIC_THRESHOLD
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :seismic_anomaly,
        message: "🌋 СЕЙСМІКА: Аномальний резонанс (#{telemetry_log.acoustic_events}). DID: #{tree.did}"
      )
    end

    # 4. ПОСУХА ТА АТРАКТОР (Mathematical Homeostasis)
    # [FW.57 F2] anomaly_ceiling uses the device's RAW temp (DCI anchor), not the
    # drift-corrected temperature_c — recover raw = temperature_c − offset (exact
    # while offset == 0; alert is near-real-time so it hasn't moved). Fire/display
    # above intentionally keep the calibrated physical value.
    raw_temp = telemetry_log.temperature_c - (tree.device_calibration&.temperature_offset_c || 0.0)
    is_out_of_homeostasis = !SilkenNet::Attractor.homeostatic?(telemetry_log.z_value, family, raw_temp)

    if telemetry_log.bio_status_stress? || is_out_of_homeostasis
      msg = is_out_of_homeostasis ? "🌀 АТРАКТОР: Дестабілізація (Z: #{telemetry_log.z_value})." : "💧 ПОСУХА: Гідрологічний стрес."

      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium,
        alert_type: :severe_drought, message: msg
      )
    end

    # 5. ШКІДНИКИ (The Silent Eaters - Updated Logic)
    # [ПІДСТУПНІСТЬ]: Тригеримо загрозу навіть БЕЗ біо-стресу, якщо шум аномальний
    if telemetry_log.acoustic_events > pest_limit && telemetry_log.acoustic_events < DEFAULT_SEISMIC_THRESHOLD
      pest_severity = telemetry_log.bio_status_stress? ? :medium : :low

      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: pest_severity,
        alert_type: :insect_epidemic,
        message: "🪲 БІО-ЗАГРОЗА: Акустична активність шкідників (#{telemetry_log.acoustic_events})."
      )
    end
  end

  # [FIX]: Публічний метод для створення fraud-алертів з InsightGeneratorService.
  # Окремий від create_and_dispatch_alert!, бо fraud вимагає manual review
  # і не повинен тригерити автоматичну EmergencyResponseService.
  def self.create_fraud_alert!(tree, message)
    cluster = tree.cluster
    silence_key = "ews_silence:#{tree.id}:fraud"
    return if Rails.cache.exist?(silence_key)

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: :critical,
      alert_type: :system_fault,
      message: "🚨 ФРОД: #{message}"
    )

    Rails.cache.write(silence_key, true, expires_in: 30.minutes)
    Rails.cache.delete("oracle_expected_yield_24h")
    Rails.logger.warn "🚨 [FRAUD ALERT] #{tree.did}: #{message}"

    # [A-1 FIX: Transactional Outbox — Wiki 04_02 §2 AlertDispatchService]
    # AlertNotificationWorker.perform_async видалено.
    # EwsAlert.after_create_commit :dispatch_notifications! вже безпечно ставить job
    # у чергу ПІСЛЯ commit транзакції. Явний виклик тут був:
    # 1) Дублюючим (подвійний enqueue)
    # 2) Небезпечним при виклику з InsightGeneratorService#perform (всередині transaction)
    alert
  end

  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message:)
    # --- ⚡ [ОПТИМІЗАЦІЯ]: REDIS SILENCE FILTER ---
    # Використовуємо Rails.cache (Redis) замість SQL .exists?, щоб не "вбити" Postgres
    silence_key = "ews_silence:#{tree.id}:#{alert_type}"
    return if Rails.cache.exist?(silence_key)

    # --- 🛡️ [SEC.10]: Per-DID Rate Limiting ---
    # Захист від replay/injection атак: не більше MAX_ALERTS_PER_DID_PER_WINDOW
    # критичних алертів від одного DID за DID_RATE_LIMIT_WINDOW.
    # Зловмисник може replay-ити panic packets → множинні false alarms.
    # Time-bucketed key: автоматично скидається кожну хвилину.
    # Note: Read/write has a small race window, acceptable because:
    # (1) alert dispatch is typically serial within telemetry processing,
    # (2) per-type silence filter (5 min) provides additional protection.
    if severity == :critical
      time_bucket = Time.current.to_i / DID_RATE_LIMIT_WINDOW.to_i
      rate_key = "ews_did_rate:#{tree.did}:#{time_bucket}"
      current_count = (Rails.cache.read(rate_key) || 0).to_i

      if current_count >= MAX_ALERTS_PER_DID_PER_WINDOW
        Rails.logger.warn "🛡️ [SEC.10] Per-DID rate limit exceeded for #{tree.did}: " \
                          "#{current_count}/#{MAX_ALERTS_PER_DID_PER_WINDOW} critical alerts in #{DID_RATE_LIMIT_WINDOW}. " \
                          "Suppressed: #{alert_type}"
        return
      end

      Rails.cache.write(rate_key, current_count + 1, expires_in: DID_RATE_LIMIT_WINDOW * 2)
    end

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: severity,
      alert_type: alert_type, message: message
    )

    # Встановлюємо "режим тиші" на 5 хвилин для цього типу тривоги
    Rails.cache.write(silence_key, true, expires_in: 5.minutes)

    # [ІНВАЛІДАЦІЯ КЕШУ]: Критичні аномалії мають негайно оновити прогноз Оракула,
    # щоб Dashboard не показував застарілий "оптимістичний" прогноз під час катастрофи.
    Rails.cache.delete("oracle_expected_yield_24h") if severity == :critical

    Rails.logger.warn "🚨 [EWS ALERT] #{alert_type} | #{tree.did}"

    EmergencyResponseService.call(alert) if defined?(EmergencyResponseService)

    # [A-1 FIX: Transactional Outbox — Wiki 04_02 §2 AlertDispatchService]
    # AlertNotificationWorker.perform_async видалено.
    # EwsAlert.after_create_commit :dispatch_notifications! вже безпечно ставить job
    # у чергу ПІСЛЯ commit транзакції. Явний виклик тут був:
    # 1) Дублюючим (подвійний enqueue)
    # 2) Небезпечним при виклику з TelemetryUnpackerService#commit_telemetry (всередині transaction)
  end
end
