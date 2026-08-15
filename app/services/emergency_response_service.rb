# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EmergencyResponseService
  # [ARCH.75] Протокол фізичної відповіді за типом загрози — одна таблиця, бо всі
  # три величини кроку читаються разом: ЩО зробити, ЯК ДОВГО і ДОКИ це ще має сенс.
  #
  # `relevance` — вікно РЕЛЕВАНТНОСТІ, не вікно доставки. Воно відповідає на питання
  # «доки ця фізична відповідь ще має сенс», і диктує його фізика події, а не
  # транспорт: евакуаційна сирена через годину після пожежі — шум, а полив під час
  # посухи через шість годин так само корисний. Доставність — ОКРЕМЕ питання
  # (`deliverable?` нижче). Доти обидва були одним фіксованим числом 15 хв, тобто
  # TTL був вироком, а не строком: Королева питає `poll/<uid>` лише після власного
  # флашу (кеш 45/50 АБО таймер година+джиттер), тож у рідкому кластері вся аварійна
  # відповідь гинула протермінованою, не виконавшись жодного разу.
  #
  # 🚨 ПОРЯДОК КРОКІВ = ПОРЯДОК ВИДАЧІ. Обидві пожежні команди `high`, тож
  # `ActuatorCommand.by_priority` (`priority DESC, created_at ASC`) розводить їх за
  # `created_at`, а кожен крок робить власний `insert_all` зі своїм `Time.current`.
  # Королева ж дренажує лише `QUEEN_POLL_MAX_PER_FLUSH` = 3 накази за флаш. Доти
  # клапан диспетчеризувався першим, і сирена ставала п'ятою — за чотирма чанками
  # поливу, тобто з'їжджала на наступний флаш і гинула першою. Пряма інверсія
  # власного інваріанта моделі «Ієрархія Виживання: сирена має витіснити полив».
  # Сирена йде ПЕРШОЮ.
  #
  # ⚖️ Форму ратифіковано founder 2026-08-15; самі величини `relevance` — присуд про
  # фізику, а не вимір, тож лишаються переглядними → [`00_07`] ARCH.75.
  PROTOCOLS = {
    severe_drought: [
      { device_type: "water_valve", payload: "OPEN_VALVE", duration: 7200, relevance: 6.hours }
    ],
    fire_detected: [
      { device_type: "fire_siren", payload: "ACTIVATE_SIREN", duration: 3600, relevance: 15.minutes },
      { device_type: "water_valve", payload: "OPEN_VALVE", duration: 14400, relevance: 2.hours }
    ],
    insect_epidemic: [
      { device_type: "water_valve", payload: "OPEN_VALVE", duration: 3600, relevance: 6.hours }
    ],
    seismic_anomaly: [
      { device_type: "seismic_beacon", payload: "ACTIVATE_BEACON", duration: 1800, relevance: 30.minutes }
    ]
  }.freeze

  def self.call(ews_alert)
    cluster = ews_alert.cluster
    return unless cluster

    protocol = PROTOCOLS[ews_alert.alert_type.to_sym]
    if protocol.nil?
      Rails.logger.info "ℹ️ [Emergency] Тип тривоги #{ews_alert.alert_type} обробляється лише сповіщенням людей."
      return
    end

    # Знаходимо всі працездатні актуатори в секторі (Кластері).
    # 🔴 Живість шлюза питаємо ОДНИМ домом — `Gateway.online` / `Gateway#online?`.
    # Доти тут стояло рукописне `1.hour.ago..`: при провіжінених 3600 с чесне вікно
    # предиката = 72 хв, тож аварійна відповідь мовчки ПРОПУСКАЛА шлюз, який решта
    # застосунку бачить справним. ⚠️ Попередні знахідки цього класу всі були у
    # в'ю-шарі, і саме тому цей екземпляр пережив їхні свіпи — периметр пошуку
    # мусить бути `last_seen_at` по всьому `app/`, не лише по `app/views/`.
    # 🔴 Набір беремо ОДНИМ запитом і розкладаємо за типом у памʼяті, а не
    # скоупимо по разу на крок протоколу. Виграш не в кроках (їх одиниці, і росту
    # там не буде — це не дані, а таблиця), а в тому, що `deliverable?` питає шлюз
    # КОЖНОГО актуатора: без `preload(:gateway)` ось ЦЕ росло б із флотом.
    available_actuators = Actuator.joins(:gateway)
                                  .preload(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(state: [ :idle, :active ])
                                  .merge(Gateway.online)
                                  .to_a

    if available_actuators.empty?
      Rails.logger.warn "⚠️ [Emergency] Кластер #{cluster.name}: Не знайдено доступних інструментів відгуку."
      return
    end

    by_device_type = available_actuators.group_by(&:device_type)

    protocol.each do |step|
      dispatch_commands(
        by_device_type.fetch(step[:device_type], []), step[:payload],
        duration: step[:duration], relevance: step[:relevance], alert: ews_alert
      )
    end
  end

  private_class_method def self.dispatch_commands(actuators, command_code, duration:, relevance:, alert:)
    return if actuators.empty?

    # [FIX-3]: Пріоритезація — спершу активуємо актуатори ближчих шлюзів
    ordered_actuators = prioritize_by_proximity(actuators, alert)

    # Розбиваємо тривалість на серії по `ActuatorCommand::MAX_DURATION_S` —
    # протокольна стеля ОДНОГО наказу (дім — модель).
    chunks = duration_chunks(duration)

    # [ARCH.75] Придатність питаємо ДО запису. `insert_all` нижче обходить валідації,
    # тож «команду не видано» і «в БД лежить невалідний рядок» — різні речі, і лише
    # перша з них чесна. Відсіяний актуатор дістає власний гучний алерт; сусіди по
    # кластеру, які доставку витримують, свої накази отримують.
    deliverable = ordered_actuators.select { |actuator| deliverable?(actuator, chunks.max, relevance, alert) }
    return if deliverable.empty?

    now = Time.current
    # 📈 Денормалізація: organization_id для broadcast без N+1
    org_id = alert.cluster.organization_id
    attrs = deliverable.flat_map do |actuator|
      chunks.map do |chunk_duration|
        {
          actuator_id: actuator.id,
          ews_alert_id: alert.id,
          command_payload: command_code,
          duration_seconds: chunk_duration,
          status: ActuatorCommand.statuses[:issued],
          # 🛡️ Idempotency: UUID для кожної команди (дедуплікація на STM32)
          idempotency_token: SecureRandom.uuid,
          # 🚦 Priority: EWS-команди завжди high (критичне реагування)
          priority: ActuatorCommand.priorities[:high],
          # ⏱️ TTL = вікно релевантності кроку (див. PROTOCOLS)
          expires_at: now + relevance,
          # 📈 Денормалізація organization_id
          organization_id: org_id,
          created_at: now,
          updated_at: now
        }
      end
    end

    begin
      # [FW.60] Без push-enqueue: insert_all обходить dispatch_to_edge!, але
      # команди (:issued) вже в .pending — Королева забере їх власним poll'ом
      # (Downlink::PendingQueueService, CMD найпріоритетніший). Push-ретраї
      # в CGNAT-діру fail!'или б сирену ДО першого poll'а.
      ActuatorCommand.insert_all(attrs)
    rescue StandardError => e
      Rails.logger.error "🛑 [Emergency Error] Масове створення наказів провалене: #{e.message}"
    end
  end

  # [ARCH.75] Дві НЕЗАЛЕЖНІ причини не доїхати, і кожна мусить зупинити запис:
  #
  # (1) **Фізична стеля пристрою.** Наказ понад `max_active_duration_s` лягав у БД
  #     невалідним і далі не міг ні виконатись, ні померти — кожен AASM-перехід
  #     бився об `duration_within_safety_envelope`, включно з TTL-прибиранням.
  #     Наслідок був перевернутий: аварійна відповідь працювала рівно доти, доки
  #     стелю лишали НЕ оголошеною, тобто колонка безпеки й вимикала безпеку.
  #
  # (2) **Каденс поллу.** Наказ, чиє вікно релевантності коротше за інтервал
  #     опитування, протермінується раніше, ніж його взагалі спитають. Джерело —
  #     `Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S` (дзеркало
  #     прошивки), а НЕ `gateways.config_sleep_interval_s`: ту колонку прошивка не
  #     читає ВЗАГАЛІ, downlink'а для неї не існує, тож порівняння з нею було б
  #     виміром вигаданої величини — шлюзи з 300 і з 3600 флашать однаково.
  #     ⚠️ Стеля ЗВЕРХУ: нижньої межі каденсу не існує (мовчазна legacy-Королева
  #     не флашить ніколи), тож «вкладаємось» = «не можемо довести, що ні».
  #     🔴 **Наслідок відомий і ратифікований** (⚖️ 2026-08-15): при годинному каденсі
  #     сирена (15 хв) і маяк (30 хв) недоставні ЗАВЖДИ. Платформа каже це вголос —
  #     один раз на актуатор, доки алерт не закрито, — замість імітувати відповідь;
  #     механізм, якого бракує, заведено окремо → `00_07` FW.64 (подієвий флаш).
  private_class_method def self.deliverable?(actuator, chunk_duration, relevance, alert)
    unless actuator.can_sustain?(chunk_duration)
      report_undeliverable(alert, actuator, "emergency_response_over_ceiling",
                           chunk_s: chunk_duration, limit_s: actuator.max_active_duration_s)
      return false
    end

    unless Downlink::PendingQueueService.reachable_within?(relevance)
      report_undeliverable(alert, actuator, "emergency_response_too_slow",
                           relevance_min: (relevance.to_i / 60.0).round,
                           cadence_min: (Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S / 60.0).round)
      return false
    end

    true
  end

  # Гучна відмова замість тихого невалідного рядка. Дедуп по ПАРІ
  # (`message_key`, `actuator_id`) — дзеркало `ActuatorSafetySweepWorker`: на кластері
  # кілька актуаторів, тож cluster-scoped guard глушив би сусідів, а дві РІЗНІ причини
  # на одному пристрої є двома різними фактами й обидва мусять бути видні.
  # `actuator_id` у тексті не інтерполюється — він тут ключ ідентичності, не вимір.
  private_class_method def self.report_undeliverable(alert, actuator, key, **measurements)
    return if undeliverable_alert_exists?(alert.cluster_id, key, actuator)

    EwsAlert.create!(
      cluster_id: alert.cluster_id,
      severity: :critical,
      alert_type: :emergency_response_undeliverable,
      message_key: key,
      message_params: { name: actuator.name, endpoint: actuator.endpoint,
                        actuator_id: actuator.id, **measurements }
    )
  rescue StandardError => e
    # 🔴 `StandardError`, а НЕ `ActiveRecordError`, і межа тут виміряна: ERS біжить
    # ПОЗА транзакцією (`telemetry_unpacker_service` свідомо виніс `AlertDispatchService`
    # за неї), тож `EwsAlert.create!` виконує свої `after_create_commit` СИНХРОННО —
    # `AlertNotificationWorker.perform_async` і Turbo-броадкаст, тобто Redis. Блимання
    # Redis не є `ActiveRecordError`, отже вужчий rescue пропускав би виняток нагору
    # й забирав відповідь решти актуаторів — рівно те, що цей rescue обіцяє не
    # допустити, і саме тоді, коли Sidekiq під навантаженням пожежі.
    Rails.logger.error "🛑 [ARCH.75] Алерт про недоставну відповідь не створено: #{e.message}"
  end

  private_class_method def self.undeliverable_alert_exists?(cluster_id, key, actuator)
    EwsAlert.unresolved.alert_type_emergency_response_undeliverable
            .where(cluster_id: cluster_id, message_key: key)
            .where("message_params ->> 'actuator_id' = ?", actuator.id.to_s)
            .exists?
  end

  # Розбиваємо загальну тривалість на частини по протокольній стелі одного наказу
  private_class_method def self.duration_chunks(total_duration)
    max = ActuatorCommand::MAX_DURATION_S
    return [ total_duration ] if total_duration <= max

    full_chunks = total_duration / max
    remainder = total_duration % max

    chunks = Array.new(full_chunks, max)
    chunks << remainder if remainder > 0
    chunks
  end

  # Сортуємо актуатори за відстанню їхнього шлюзу до дерева-джерела тривоги.
  # Сорт у памʼяті, а не в SQL: набір уже завантажений (`preload(:gateway)` вище),
  # тож ORDER BY означав би ДРУГИЙ запит на кожен крок протоколу — саме той повтор
  # у циклі, який тут і ловився. Семантика збережена дослівно, включно з NULLS LAST:
  # шлюз без координат їде в хвіст, а не вважається найближчим.
  private_class_method def self.prioritize_by_proximity(actuators, alert)
    tree = alert.tree
    # latitude-перевірка вже гарантує tree non-nil (short-circuit) → longitude без &.
    return actuators unless tree&.latitude.present? && tree.longitude.present?

    actuators.sort_by do |actuator|
      gateway = actuator.gateway
      if gateway&.latitude.nil? || gateway.longitude.nil?
        Float::INFINITY
      else
        (gateway.latitude - tree.latitude)**2 + (gateway.longitude - tree.longitude)**2
      end
    end
  end
end
