# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertDispatchService
  # Fallback пороги (Hardware Truths), якщо в БД нічого не вказано
  DEFAULT_FIRE_TEMP_C = 60

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
    # [FIX]: Безпечний доступ до cluster. ⚠️ Доти тут стояло «(одиноке дерево)» — ⚖️
    # 2026-07-30 це ототожнення скасовано: одиноке дерево B2C має ВЛАСНИЙ кластер із
    # одного дерева, а не NULL. Гард лишається захистом на ще-nullable колонці.
    fire_limit = cluster&.custom_fire_threshold || family.fire_resistance_rating || DEFAULT_FIRE_TEMP_C

    # 1. СОФТ-ЗБІЙ ПРОШИВКИ (wire status=3 = BIO_STATUS_VM_ERROR)
    # [SLASH-1] Раніше status=3 хибно читався «вандалізмом» (vandalism_breach →
    # positive_a? → необоротний slash жертви OTA-бага). Насправді 0b11 пише лише
    # mruby-crash/OOM/unprovisioned; фізичний tamper їде PANIC_FLAG-каналом (гейт 2б).
    # Сенсорна половина кадру (temp/acoustic/vcap) виміряна ДО mruby і жива —
    # аналіз пожежі/сейсміки продовжуємо, зламаний лише Лоренц-статус.
    if telemetry_log.bio_status_vm_error?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :firmware_fault,
        message_key: "firmware_fault", message_params: { did: tree.did }
      )
    end

    # 1б. [SEC.20] ВІДКАТ НА BASELINE (wire fw-report: reverted-біт) — вузол
    # стер биту OTA-версію і знову здоровий, але жити їй більше не судилося:
    # anti-rollback приплив (0x15) спалив слот. Термінальний стан до re-issue
    # версії СТРОГО вищої за спалену (contract_id у звіті) — 03_06 §4.
    # Uniqueness-scope [tree_id, status] тримає один активний алерт на вузол,
    # доки телеметрія несе reverted (стан, не подія — кадр щоциклу).
    if telemetry_log.firmware_report_reverted?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :firmware_reverted,
        message_key: "firmware_reverted",
        message_params: { did: tree.did, burned_version: telemetry_log.firmware_report_contract_id }
      )
    end

    # [SLASH-1] Panic-кадри свідомо несуть vcap=0 (legacy-parity обох збирачів —
    # Trigger_Emergency_LoRa_TX ECB і CCM): «втрата живлення» на них — фантом,
    # що забруднював comms_no_ack? (system_fault ∈ whitelist) і з'їдав SEC.10-ліміт.
    if telemetry_log.voltage_mv < 100 && !telemetry_log.panic?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :system_fault,
        message_key: "power_loss", message_params: { did: tree.did, voltage_mv: telemetry_log.voltage_mv }
      )
      # НЕ робимо return — продовжуємо аналіз пожежі/сейсміки,
      # бо низький вольтаж може бути розрядом батареї, а не вандалізмом.
    end

    # 2а. ПОЖЕЖА (Thermal) — температура вище біом-порога.
    # [АДАПТИВНО]: Поріг тепер залежить від біома
    if telemetry_log.temperature_c >= fire_limit
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :fire_detected,
        message_key: "fire_detected",
        message_params: { temperature_c: telemetry_log.temperature_c, fire_limit: fire_limit }
      )
      return
    end

    # 2б. ПИЛКА (Acoustic — [SLASH-1] chainsaw-спліт). Anomaly без жару = акустичний
    # хаос при нормальній температурі (TinyML chainsaw/cavitation → StatusByte anomaly),
    # не вогонь. Окремий тип веде non-fire маршрутом dClimate у Field-Audit замість
    # FIRMS-«ясне небо»-тавра rejected_fraud на жертві вирубки.
    # [SLASH-1] panic? — РЕАЛЬНА пилка: TinyML ml_event_id==3 стріляє panic-TX зі
    # status=homeostasis + PANIC_FLAG (bit 7, ОКРЕМО від status-бітів), тож гейт лише
    # на bio_status_anomaly? пропускав її повз chainsaw-маршрут у сусідню акустичну
    # гілку. anomaly? і panic? взаємовиключні на реальному дроті — обидва ведуть сюди.
    # ⚠️ Урок пережив свій інстанс: додаючи БУДЬ-ЯКУ гілку на `acoustic_events`,
    # став її ПІСЛЯ цієї — panic-кадр несе 0xFF у тому ж байті.
    if telemetry_log.panic? || telemetry_log.bio_status_anomaly?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :chainsaw_detected,
        # Два ключі, а не булевий параметр: умовний фрагмент — це ПРОЗА, і в
        # іншій мові він може стояти в іншому місці речення.
        message_key: telemetry_log.panic? ? "chainsaw_detected_panic" : "chainsaw_detected",
        message_params: { did: tree.did }
      )
      return
    end

    # 4. ПОСУХА ТА АТРАКТОР (Mathematical Homeostasis)
    # [FW.57 F2] anomaly_ceiling uses the device's RAW temp (DCI anchor), not the
    # drift-corrected temperature_c — recover raw = temperature_c − offset (exact
    # while offset == 0; alert is near-real-time so it hasn't moved). Fire/display
    # above intentionally keep the calibrated physical value.
    raw_temp = telemetry_log.temperature_c - (tree.device_calibration&.temperature_offset_c || 0.0)
    is_out_of_homeostasis = !SilkenNet::Attractor.homeostatic?(telemetry_log.z_value, family, raw_temp)

    if telemetry_log.bio_status_stress? || is_out_of_homeostasis
      key, params = if is_out_of_homeostasis
        [ "attractor_destabilised", { z_value: telemetry_log.z_value } ]
      else
        [ "hydrological_stress", {} ]
      end

      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium,
        alert_type: :severe_drought, message_key: key, message_params: params
      )
    end
  end

  # [FIX]: Публічний метод для створення fraud-алертів з InsightGeneratorService.
  # Окремий від create_and_dispatch_alert!, бо fraud вимагає manual review
  # і не повинен тригерити автоматичну EmergencyResponseService.
  # Приймає ДАТУ, а не готовий рядок. Сигнатура «будь-який текст» була ширшою
  # за реальність (єдиний продовий викликач передавав фіксований шаблон із
  # датою) — і саме та ширина впускала прозу: сирий український рядок сідав
  # усередину локалізованої рамки, даючи «FRAUD: Виявлено фрод-телеметрію»
  # англійському глядачеві. Вузька сигнатура робить це неможливим за побудовою.
  def self.create_fraud_alert!(tree, target_date)
    cluster = tree.cluster
    silence_key = "ews_silence:#{tree.id}:fraud"
    return if Rails.cache.exist?(silence_key)

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: :critical,
      alert_type: :system_fault,
      message_key: "fraud_telemetry_detected", message_params: { target_date: target_date.to_s }
    )

    Rails.cache.write(silence_key, true, expires_in: 30.minutes)
    Organization.invalidate_expected_yield_cache(cluster&.organization_id)
    Rails.logger.warn "🚨 [FRAUD ALERT] #{tree.did}: фрод-телеметрія за #{target_date}"

    # [A-1 FIX: Transactional Outbox — Wiki 04_02 §2 AlertDispatchService]
    # AlertNotificationWorker.perform_async видалено.
    # EwsAlert.after_create_commit :dispatch_notifications! вже безпечно ставить job
    # у чергу ПІСЛЯ commit транзакції. Явний виклик тут був:
    # 1) Дублюючим (подвійний enqueue)
    # 2) Небезпечним при виклику з InsightGeneratorService#perform (всередині transaction)
    alert
  end

  # `message_key` + `message_params` замість готового рядка: алерт народжується
  # у воркері, де локалі глядача не існує, тож фраза мусить збиратись у момент
  # показу (дім механізму — `EwsAlert#message`, ключі — `alerts.messages.*`).
  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message_key:, message_params: {})
    # --- ⚡ [ОПТИМІЗАЦІЯ]: SILENCE FILTER ---
    # Rails.cache замість SQL .exists?, щоб не "вбити" Postgres на кожній тривозі.
    # ⚠️ Прод-стор тут Solid Cache (PostgreSQL), НЕ Redis — заголовок казав інакше.
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
      alert_type: alert_type, message_key: message_key, message_params: message_params
    )

    # Встановлюємо "режим тиші" на 5 хвилин для цього типу тривоги
    Rails.cache.write(silence_key, true, expires_in: 5.minutes)

    # [ІНВАЛІДАЦІЯ КЕШУ]: Критичні аномалії мають негайно оновити прогноз Оракула,
    # щоб Dashboard не показував застарілий "оптимістичний" прогноз під час катастрофи.
    Organization.invalidate_expected_yield_cache(cluster&.organization_id) if severity == :critical

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
