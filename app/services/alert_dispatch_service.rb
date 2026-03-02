# frozen_string_literal: true

class AlertDispatchService
  # Fallback пороги (Hardware Truths), якщо в БД нічого не вказано
  DEFAULT_FIRE_TEMP_C = 60
  DEFAULT_SEISMIC_THRESHOLD = 200
  DEFAULT_PEST_THRESHOLD = 50

  def self.analyze_and_trigger!(telemetry_log)
    tree = telemetry_log.tree
    cluster = tree.cluster
    family = tree.tree_family

    # --- 0. АДАПТИВНІ ПОРОГИ (The Biome Adaptation) ---
    # Пожежа: беремо з кластера (біом), породи дерева або дефолт
    fire_limit = cluster.custom_fire_threshold || family.fire_resistance_rating || DEFAULT_FIRE_TEMP_C
    
    # Шкідники: коригується індексом сокоруху (чим соковитіше дерево, тим вищий фон)
    pest_limit = family.sap_flow_index ? (DEFAULT_PEST_THRESHOLD * family.sap_flow_index) : DEFAULT_PEST_THRESHOLD

    # 1. ВАНДАЛІЗМ (Zero-Trust Breach)
    if telemetry_log.bio_status_tamper_detected? || telemetry_log.voltage_mv < 100
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :vandalism_breach,
        message: "🚨 КРИТИЧНО: Втручання або втрата живлення! DID: #{tree.did}"
      )
      return 
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
    is_out_of_homeostasis = !SilkenNet::Attractor.homeostatic?(telemetry_log.z_value, family)

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

  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message:)
    # --- ⚡ [ОПТИМІЗАЦІЯ]: REDIS SILENCE FILTER ---
    # Використовуємо Rails.cache (Redis) замість SQL .exists?, щоб не "вбити" Postgres
    silence_key = "ews_silence:#{tree.id}:#{alert_type}"
    return if Rails.cache.exist?(silence_key)

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: severity,
      alert_type: alert_type, message: message
    )

    # Встановлюємо "режим тиші" на 5 хвилин для цього типу тривоги
    Rails.cache.write(silence_key, true, expires_in: 5.minutes)

    Rails.logger.warn "🚨 [EWS ALERT] #{alert_type} | #{tree.did}"

    EmergencyResponseService.call(alert) if defined?(EmergencyResponseService)
    AlertNotificationWorker.perform_async(alert.id)
  end
end
