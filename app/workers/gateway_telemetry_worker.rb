# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Телеметрія шлюзів — це вхідний потік даних, аналогічний UnpackTelemetryWorker.
  # Черга uplink гарантує, що діагностика Королев (пульс, сигнал, сліди відмов)
  # не затримується за рутинними задачами в default.
  # [SIDEKIQ PRO EXPIRES_IN]: Діагностика Королев старша за 5 хвилин
  # неактуальна — нові дані вже в черзі.
  # ⚠️ У OSS-редакції (поточній) опція **інертна** — активується лише з Sidekiq Pro
  # (DOC-R.10, `04_02 §11`). 🔴 [ARCH.59, ⚖️ 2026-08-21] Тут вона лишається СВІДОМО,
  # на відміну від сусіднього `UnpackTelemetryWorker`, де її знято: там дроп коштує
  # growth_points, а тут — навпаки, ЛІКУЄ брехню. `Gateway#mark_seen!` штампує
  # `last_seen_at = Time.current`, тобто момент ВИКОНАННЯ, а не момент пакета;
  # затримана джоба «оживляє» шлюз заднім числом і сліпить dead-man switch
  # (`GatewayStalenessSweepWorker`). Тож активація Pro тут покращує чесність
  # сигналу, а не псує її — два uplink-воркери отримали ПРОТИЛЕЖНІ присуди, і це
  # не суперечність, а різна ціна дропу.
  sidekiq_options queue: "uplink", retry: 2, expires_in: 5.minutes

  # [SLASH-1 2026-09-04] One-Home мапи ключ→тип. Дім саме тут, а не в моделі:
  # `message_key` є словником ЦЬОГО воркера (гілки `health_message_key`), тож
  # модель про них не знає й знати не мусить. Ключі поза мапою лишаються
  # `system_fault` СВІДОМО — розкол кошика йде за атрибуцією й поштучно
  # (05_05 §6), а не гуртом.
  ALERT_TYPE_BY_MESSAGE_KEY = {
    "gateway_uplink_degraded" => :gateway_uplink_degraded,
    "gateway_overheat"        => :hardware_fault,
    "gateway_freezing"        => :hardware_fault,
    "gateway_hardware_fault"  => :hardware_fault
  }.freeze

  # CSQ 0-31 — нормальний діапазон (3GPP 27.007); 99 — невизначений/відсутній сигнал
  VALID_CSQ_VALUES = (0..31).freeze

  # [ARCH.54 Шар 1] Джерело stats — ПІДПИСАНИЙ health-блок QATT-v2 конверта
  # (UnpackTelemetryWorker#enqueue_envelope_health; wire-дім розкладки —
  # firmware/common/queen_attest.h). Стара милиця DID=0-псевдодерева ВБИТА:
  # вона їла CIFO-слот, ламала CCM-stride, а поля читались Солдатськими
  # окулярами (uptime персистився як voltage, cache_count — як CSQ, і
  # health мовчки дропався валідацією саме під навантаженням).
  #
  # voltage_mv / temperature_c СВІДОМО відсутні у v2-пульсі: Королева без
  # ADC-тракту — не брешемо (колонки лишаються в БД nullable до заліза).
  def perform(queen_uid, stats = {})
    # Sentry context: tag with queen UID for error correlation
    Sentry.set_tags(queen_uid: queen_uid || "unknown")

    # Підготовлюємо хеш один раз на початку, уникаючи зайвих алокацій в транзакції
    stats = stats.with_indifferent_access

    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.strip.upcase)

    # [KENOSIS TITAN]: Перевірка якості даних на рівні обробника.
    # Замінює AR-валідації, які ігноруються при insert_all на Series D масштабі.
    unless valid_gateway_stats?(stats)
      Rails.logger.warn "⚠️ [Gateway] Пакет від #{gateway.uid} відхилено: невалідні дані пульсу."
      return
    end

    # 2. ТРАНЗАКЦІЙНІСТЬ (The Integrity Loop)
    # [P0 FIX]: Sidekiq job НЕ повинен ставитись в чергу всередині транзакції.
    # EwsAlert.after_create_commit :dispatch_notifications! — enqueue після commit.
    ActiveRecord::Base.transaction do
      log = gateway.gateway_telemetry_logs.create!(
        gateway_id: gateway.id,
        uptime_min: stats[:uptime_min],
        cifo_fill: stats[:cifo_fill],
        lora_rx_drops: stats[:lora_rx_drops],
        coap_fail_count: stats[:coap_fail_count],
        cellular_signal_csq: stats[:cellular_signal_csq],
        health_flags: stats[:flags]
      )

      # mark_seen! без voltage: пульс v2 напруги не несе (нема ADC);
      # latest_voltage_mv лишається nil до залізного тракту — чесність.
      gateway.mark_seen!(new_ip: stats[:ip_address])

      # 3. АНАЛІЗ (The Diagnostic Lens)
      check_system_health(gateway, log)
    end

    Rails.logger.info "👑 [Gateway] #{gateway.uid} Pulse: up=#{stats[:uptime_min]}min, " \
                      "cifo=#{stats[:cifo_fill]}, sig=#{stats[:cellular_signal_csq] || '—'}/31"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Gateway] Спроба оновити фантомний шлюз: #{queen_uid}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Gateway Error] Збій у матриці #{gateway&.uid}: #{e.message}"
    raise e
  end

  private

  def check_system_health(gateway, log)
    # Використовуємо метод моделі для визначення деградації заліза
    return unless log.critical_fault?

    # Формуємо вердикт для патрульного
    message_key, message_params = health_message_key(gateway, log)

    # Анти-спам: активний cluster-level system_fault вже кличе патрульного —
    # кожен наступний пульс не повинен плодити дублікати (log-створення
    # щофлешу, ~щогодини; tree_id тут nil → модельна uniqueness мовчить).
    # [SLASH-1] Звуження tree_id: nil несуче: tree-scoped system_fault (fraud /
    # power-loss / hardware-decay) — чужі сигнали без авто-резолвера, і без
    # звуження один стоячий tree-алерт безстроково глушив НОВИЙ gateway-fault.
    # Стеля: залишковий конфлат з іншими cluster-level писарями (Actuator,
    # slashing-failure) розкладе типова декомпозиція кошика → 00_07 SLASH-1.
    # [SLASH-1 2026-09-04] Тип ВИВОДИТЬСЯ з ключа, а не хардкодиться: предикати
    # penalty_factor читають `alert_type` і до `message_key` сліпі за побудовою,
    # тож поки всі гілки їхали одним типом, атрибуційно-неоднозначний
    # `gateway_uplink_degraded` (лічильник провалених flush-розмов до НАШОГО CoAP —
    # не розрізняє, чий бік упав) годував ОБИДВА предикати. Класифікація типу —
    # `EwsAlert` enum. ⛔ Дедуп теж мусить бути ПО ТИПУ: спільний глушник по
    # `system_fault` ховав би новий тип за старим алертом іншого предмета.
    alert_type = ALERT_TYPE_BY_MESSAGE_KEY.fetch(message_key, :system_fault)

    return if EwsAlert.unresolved.where(alert_type: alert_type)
                      .exists?(cluster_id: gateway.cluster_id, tree_id: nil)

    EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: alert_type,
      message_key: message_key, message_params: message_params
    )

    # Notification відбувається через EwsAlert.after_create_commit :dispatch_notifications!
  end

  # Повертає пару [ключ, параметри] замість готового рядка: гілка обирає, ЩО
  # сталося, а не якими словами це сказати (дім фраз — `alerts.messages.*`).
  def health_message_key(gateway, log)
    if log.cellular_signal_csq.present? &&
       log.cellular_signal_csq < GatewayTelemetryLog::LOW_SIGNAL_THRESHOLD
      [ "gateway_weak_signal", { uid: gateway.uid, csq: log.cellular_signal_csq } ]
    elsif log.coap_fail_count.to_i >= GatewayTelemetryLog::COAP_FAIL_ALERT_THRESHOLD
      [ "gateway_uplink_degraded", { uid: gateway.uid, fail_count: log.coap_fail_count } ]
    elsif log.temperature_c.present? && log.temperature_c > GatewayTelemetryLog::OVERHEAT_THRESHOLD
      [ "gateway_overheat", { uid: gateway.uid, temperature_c: log.temperature_c } ]
    elsif log.temperature_c.present? && log.temperature_c < GatewayTelemetryLog::LOW_TEMPERATURE_THRESHOLD
      [ "gateway_freezing", { uid: gateway.uid, temperature_c: log.temperature_c } ]
    else
      [ "gateway_hardware_fault", { uid: gateway.uid } ]
    end
  end

  # [KENOSIS TITAN]: Перевірка якості даних пульсу на рівні обробника.
  # Замінює AR-валідації моделі, які ігноруються при insert_all (Series D).
  # csq nil легальний («модем не відповів» — сентинель 0xFF на дроті);
  # ненульовий мусить бути 0-31 або 99 (3GPP 27.007).
  def valid_gateway_stats?(stats)
    return false if stats[:uptime_min].nil? || stats[:cifo_fill].nil?

    csq = stats[:cellular_signal_csq]
    csq.nil? || VALID_CSQ_VALUES.cover?(csq.to_i) || csq.to_i == 99
  end
end
