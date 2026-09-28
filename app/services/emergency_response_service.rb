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
  # `ActuatorCommand.by_priority` (`priority DESC, created_at ASC, id ASC`) розводить їх за
  # `created_at`, а кожен крок робить власний `insert_all` зі своїм `Time.current`.
  # Королева ж дренажує лише `QUEEN_POLL_MAX_PER_FLUSH` = 3 накази за флаш. Доти
  # клапан диспетчеризувався першим, і сирена ставала п'ятою — за чотирма чанками
  # поливу, тобто з'їжджала на наступний флаш і гинула першою. Пряма інверсія
  # власного інваріанта моделі «Ієрархія Виживання: сирена має витіснити полив».
  # Сирена йде ПЕРШОЮ.
  #
  # ⚖️ Форму ратифіковано founder 2026-08-15, а самі величини `relevance` —
  # 2026-08-20 (сирена 15 хв · пожежний полив 2 год · посушливий полив 6 год).
  # Це присуд про фізику, а не вимір, тож перегляд при бенчі/залізі є зміною
  # ПІДПИСАНОГО значення, не вільною правкою — дім `04_02 §7`.
  PROTOCOLS = {
    severe_drought: [
      { device_type: "water_valve", payload: "OPEN_VALVE", duration: 7200, relevance: 6.hours }
    ],
    fire_detected: [
      { device_type: "fire_siren", payload: "ACTIVATE_SIREN", duration: 3600, relevance: 15.minutes },
      { device_type: "water_valve", payload: "OPEN_VALVE", duration: 14400, relevance: 2.hours }
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

    # Знаходимо всі актуатори сектора (Кластера) — ОДНИМ запитом, із розкладкою за
    # типом у памʼяті. Виграш не в кроках протоколу (їх одиниці, і росту там не
    # буде — це таблиця, не дані), а в тому, що придатність питає шлюз КОЖНОГО
    # актуатора: без `preload(:gateway)` ось ЦЕ росло б із флотом.
    #
    # 🔴 [ARCH.75] Фільтр придатності стоїть у ПАМʼЯТІ, а не в `WHERE`, і це не
    # стиль: порожній результат мусить розрізняти ДВА стани, а SQL-фільтр зливає їх
    # в один. «Заліза цього роду в кластері немає» (закупити й встановити) ⊥
    # «залізо є, але недосяжне» (полагодити звʼязок або пристрій) — це різні дії
    # людини, а платформа доти відповідала на обидва одним `logger.warn`, тобто
    # приписувала операторові власну недоробку. Той самий клас, що вже коштував у
    # `Notifications::DeliveryChannels`: станів ТРИ, а не два.
    #
    # 🔴 Живість шлюза питаємо ОДНИМ домом — `Gateway#online?` (SQL-двійник
    # `Gateway.online` тут більше не потрібен, бо набір уже в памʼяті). Доти стояло
    # рукописне `1.hour.ago..`: при провіжінених 3600 с чесне вікно предиката = 72 хв,
    # тож аварійна відповідь мовчки ПРОПУСКАЛА шлюз, який решта застосунку бачить
    # справним. ⚠️ Попередні знахідки цього класу всі були у вʼю-шарі, і саме тому
    # цей екземпляр пережив їхні свіпи — периметр пошуку мусить бути `last_seen_at`
    # по всьому `app/`, не лише по `app/views/`.
    cluster_actuators = Actuator.joins(:gateway)
                                .preload(:gateway)
                                .where(gateways: { cluster_id: cluster.id })
                                .to_a

    by_device_type = cluster_actuators.select { available?(_1) }.group_by(&:device_type)

    protocol.each do |step|
      serving = by_device_type.fetch(step[:device_type], [])

      # 🔴 [ARCH.75] Крок без жодного придатного актуатора — це НЕ-ДІЯ, і вона мусить
      # свідчити про себе так само гучно, як недоставний наказ. Доти мовчали ОБИДВІ її
      # форми, і друга гірша за першу, бо виглядає як успіх: кластер із клапаном, але
      # без сирени, виконував пожежний протокол НАПОЛОВИНУ — полив їхав, евакуаційний
      # сигнал не існував, а слід був невідрізнимий від повного успіху. Дедуп тут
      # ключується на ТИПІ пристрою, не на актуаторі: актуатора може не бути взагалі.
      if serving.empty?
        report_step_unserved(ews_alert, step[:device_type], cluster_actuators)
        next
      end

      dispatch_commands(
        serving, step[:payload],
        duration: step[:duration], relevance: step[:relevance], alert: ews_alert
      )
    end
  end

  # [FW.64] Фактичне протухання EWS-наказу в черзі шлюзу — той самий гучний слід, що й решта
  # не-дій, і через той самий писач (дедуп по парі ключ + актуатор, rescue-межа). Кличе
  # poll-тракт, коли натрапляє на протухлий наказ у голові черги, — НЕ в мить протухання:
  # свіпера за часом немає, тож слід чекає наступного poll'а, а шлюз, що перестав флашити,
  # до наказу не дійде ніколи (його добиває прибиральник `faulty`-шлюзу під алертом самого
  # шлюзу). Свідчення про ФАКТ, а не прогноз найгіршого випадку, тож доречне за будь-якої
  # гілки ⚖️ FW.64.
  def self.report_expired(command)
    return unless command.ews_alert

    # Наказ, що вже пішов у poll-відповідь (`sent_at` є), протух без echo: видачу було, а
    # доставку не підтверджено — «не дочекався видачі» про нього брехало б (адверсарне
    # рев'ю 2026-09-27). Echo, чиє підтвердження не збереглось, сюди НЕ потрапляє: такий
    # наказ `Downlink::PendingQueueService` виносить force-fail'ом одразу (FW.63), і цей
    # ключ («доставку НЕ підтверджено») про нього був би неправдою.
    key = command.sent_at ? "emergency_response_unconfirmed" : "emergency_response_expired"
    report_undeliverable(command.ews_alert, command.actuator, key, per_event: true,
                         relevance_min: ((command.expires_at - command.created_at) / 60.0).round)
  end

  # Придатність = робочий стан пристрою І живий шлюз. Дві НЕЗАЛЕЖНІ причини
  # недоступності, і саме тому звіт нижче рахує їх окремо. Шлюз на обслуговуванні
  # сюди свідомо НЕ входить: його відмова поактуаторна (`deliverable?`), інакше
  # частково обслужений крок лишав би такий клапан без наказу мовчки.
  # ⚠️ `Actuator#offline?` (стан самого пристрою) ⊥ `Gateway#online?` (тиша шлюза) —
  # одне слово, два доми; плутати їх тут коштувало б мовчазного пропуску.
  private_class_method def self.fit?(actuator) = actuator.idle? || actuator.active?
  private_class_method def self.available?(actuator) = fit?(actuator) && actuator.gateway.online?

  private_class_method def self.dispatch_commands(actuators, command_code, duration:, relevance:, alert:)
    return if actuators.empty?

    # Розбиваємо тривалість на серії по `ActuatorCommand::MAX_DURATION_S` —
    # протокольна стеля ОДНОГО наказу (дім — модель).
    chunks = duration_chunks(duration)

    # [ARCH.75] Придатність питаємо ДО запису. `insert_all` нижче обходить валідації,
    # тож «команду не видано» і «в БД лежить невалідний рядок» — різні речі, і лише
    # перша з них чесна. Відсіяний актуатор дістає власний гучний алерт; сусіди по
    # кластеру, які доставку витримують, свої накази отримують.
    deliverable = actuators.select { |actuator| deliverable?(actuator, chunks.max, alert) }
    return if deliverable.empty?

    now = Time.current
    # 📈 Денормалізація: organization_id для broadcast без N+1
    org_id = alert.cluster.organization_id
    # 🔁 Round-robin: спершу перший чанк КОЖНОГО актуатора, потім другий. Рядки кроку
    # ділять один `created_at`, тож черга шлюзу розводить їх за `id` (tie-break
    # `ActuatorCommand.by_priority`), тобто за порядком вставки. Actuator-major вставка
    # віддавала перший флаш (≤ 3 накази) чанкам одного клапана, що накладаються (пожежний
    # займав 3 з 4 слотів), а сусід на тому ж шлюзі чекав наступного флашу — до години.
    attrs = chunks.flat_map do |chunk_duration|
      deliverable.map do |actuator|
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
      return
    end

    warn_if_not_guaranteed(deliverable, relevance, alert)
  end

  # [ARCH.75] Дві причини ВІДМОВИ конкретному пристрою, і кожна зупиняє запис:
  #
  # (1) **Фізична стеля пристрою.** Наказ понад `max_active_duration_s` лягав у БД
  #     невалідним і далі не міг ні виконатись, ні померти — кожен AASM-перехід
  #     бився об `duration_within_safety_envelope`, включно з TTL-прибиранням.
  #     Наслідок був перевернутий: аварійна відповідь працювала рівно доти, доки
  #     стелю лишали НЕ оголошеною, тобто колонка безпеки й вимикала безпеку.
  #
  # (2) **Шлюз на обслуговуванні** (⚖️ founder 2026-09-27): свіп тиші його свідомо не судить,
  #     тож наказ за ним, якщо шлюз змовкне ПІСЛЯ запису, помер би без жодного сліду.
  #     Відмова ПОАКТУАТОРНА, як і стеля: доти фільтр стояв на рівні кроку, і частково
  #     обслужений крок лишав такий клапан без наказу мовчки (адверсарне рев'ю 2026-09-27).
  #
  # Каденс поллу запису НЕ зупиняє — це попередження, `warn_if_not_guaranteed` нижче.
  private_class_method def self.deliverable?(actuator, chunk_duration, alert)
    unless actuator.can_sustain?(chunk_duration)
      report_undeliverable(alert, actuator, "emergency_response_over_ceiling",
                           chunk_s: chunk_duration, limit_s: actuator.max_active_duration_s)
      return false
    end

    if actuator.gateway.maintenance?
      report_undeliverable(alert, actuator, "emergency_response_gateway_maintenance")
      return false
    end

    true
  end

  # (3) **Каденс поллу — ПОПЕРЕДЖЕННЯ, не відмова** (⚖️ founder 2026-09-27, FW.64). Наказ, чиє
  #     вікно релевантності коротше за інтервал опитування, може протермінуватися раніше, ніж
  #     його спитають, — вчасну доставку не гарантовано. Джерело —
  #     `Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S` (дзеркало
  #     прошивки), а НЕ `gateways.config_sleep_interval_s`: ту колонку прошивка не
  #     читає ВЗАГАЛІ, downlink'а для неї не існує, тож порівняння з нею було б
  #     виміром вигаданої величини — шлюзи з 300 і з 3600 флашать однаково.
  #     ⚠️ Стеля ЗВЕРХУ: нижньої межі каденсу не існує (мовчазна legacy-Королева
  #     не флашить ніколи), тож «вкладаємось» = «не можемо довести, що ні».
  #     Доти (⚖️ 2026-08-15) сирену (15 хв) відмовляли наперед на підставі «недоставна
  #     ЗАВЖДИ», а переміряно: не гарантовано, а не неможливо — за ІНШОЮ Королевою перший poll
  #     приходить до 900 с приблизно в чверті фаз. Тож наказ пишеться best-effort, а людина
  #     дістає попередження ОДРАЗУ — але ПІСЛЯ успішного `insert_all` (інакше «поставлено в
  #     чергу» брехало б при збої запису) і з дедупом по ПОДІЇ (актуатор + тривога): стоячий
  #     алерт першої пожежі не сміє глушити попередження другої (адверсарне рев'ю 2026-09-27).
  #     Фактичне протухання звітує `report_expired`; механізм, якого бракує, — `00_07` FW.64.
  #     Решту серії цей гейт не судить, і це присуд (⚖️ founder 2026-09-27, FW.64): k-й
  #     наказ черги шлюзу доїжджає НЕ РАНІШЕ за ⌈k/3⌉-й флаш (≤ 3 poll-и на флаш; пізніше —
  #     за чужих наказів у черзі чи збою poll'а), а для одного клапана на шлюзі без живої сирени відмова
  #     наперед забирала б єдиний чанк, що продовжує полив (1–3 видаються разом і, доки не
  #     серіалізовані, накладаються — `04_02 §7` ⛔ (3)) — тож хвіст пишеться best-effort, а
  #     фактичне протухання звітує `report_expired`. ⚠️ Стеля: за таймерного режиму наказ із
  #     k ≥ 7 протухає при вікні 2 год ПЕВНО (третій флаш > 7 200 с), а не в гіршому разі —
  #     Rails режиму шлюзу не знає (кеш-флаш великого кластера приходить раніше).
  private_class_method def self.warn_if_not_guaranteed(actuators, relevance, alert)
    return if Downlink::PendingQueueService.reachable_within?(relevance)

    cadence_min = (Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S / 60.0).round
    actuators.each do |actuator|
      report_undeliverable(alert, actuator, "emergency_response_too_slow", per_event: true,
                           relevance_min: (relevance.to_i / 60.0).round, cadence_min: cadence_min)
    end
  end

  # Гучна відмова замість тихого невалідного рядка. Дедуп по ПАРІ
  # (`message_key`, `actuator_id`) — дзеркало `ActuatorSafetySweepWorker`: на кластері
  # кілька актуаторів, тож cluster-scoped guard глушив би сусідів, а дві РІЗНІ причини
  # на одному пристрої є двома різними фактами й обидва мусять бути видні.
  # `actuator_id` у тексті не інтерполюється — він тут ключ ідентичності, не вимір.
  # `per_event:` — для ФАКТІВ і ПОПЕРЕДЖЕНЬ однієї тривоги (протухання, «не гарантовано»):
  # дедуп ще й по `ews_alert_id`, бо відмова за стелею — стан пристрою, а ці сліди — про
  # подію, і стоячий алерт першої пожежі глушив би другу (адверсарне рев'ю 2026-09-27).
  private_class_method def self.report_undeliverable(alert, actuator, key, per_event: false, **measurements)
    dedup = { actuator_id: actuator.id }
    dedup[:ews_alert_id] = alert.id if per_event
    record_undeliverable(alert, key, dedup: dedup,
                                     params: { name: actuator.name, endpoint: actuator.endpoint, **measurements })
  end

  # [ARCH.75] Не-дія цілого КРОКУ протоколу. Дедуп ключується на `device_type`, бо
  # актуатора, на який можна було б послатись, може не існувати взагалі — і саме це
  # й розводить два стани, які доти були одним мовчанням.
  #
  # ⚠️ `device_type` їде в `message_params` СИРИМ токеном, і причина СИЛЬНІША за «дому
  # назв немає» (дім зʼявився — `Actuator::DEVICE_TYPE_LABEL_SCOPE`, і UI на нього
  # переведено): тут значення є **ключем ІДЕНТИЧНОСТІ** — саме по ньому дедуплікується
  # алерт (`message_params ->> 'device_type'`), тож локалізована назва зробила б дедуп
  # залежним від мови процесу, який писав рядок. А підставити `I18n.t` у params не можна
  # й за загальним правилом: фраза застигла б мовою сервера, тоді як `EwsAlert#message`
  # рендериться в момент ПОКАЗУ. Отже людина бачить у цьому алерті технічний токен —
  # свідомий залишок, і його ціна названа: щоб зняти його, `EwsAlert#message` мусив би
  # вміти перекладати ТИПІЗОВАНІ параметри, а це зміна контракту моделі → ⚖️ в `00_07` I18N.1.
  private_class_method def self.report_step_unserved(alert, device_type, cluster_actuators)
    installed = cluster_actuators.select { _1.device_type == device_type }

    if installed.empty?
      record_undeliverable(alert, "emergency_response_no_actuator", dedup: { device_type: device_type }, params: {})
      return
    end

    # Причини рахуються НЕЗАЛЕЖНО й свідомо можуть перетинатись: пристрій у сервісі
    # за мовчазним шлюзом — це два факти про нього, а не половина одного, тож сума
    # лічильників має право перевищити `installed`. Формулювання ключа це поважає.
    record_undeliverable(
      alert, "emergency_response_all_unavailable",
      dedup: { device_type: device_type },
      params: { installed: installed.size,
                silent_gateway: installed.count { !_1.gateway.online? },
                out_of_service: installed.count { !fit?(_1) } }
    )
  end

  # Один писач на обидві осі дедупу (актуатор ⊥ тип пристрою) — щоб rescue-межа,
  # куплена виміром нижче, існувала в ОДНОМУ екземплярі, а не копіювалась разом
  # із кожним новим родом не-дії.
  private_class_method def self.record_undeliverable(alert, key, dedup:, params:)
    return if undeliverable_alert_exists?(alert.cluster_id, key, dedup)

    EwsAlert.create!(
      cluster_id: alert.cluster_id,
      severity: :critical,
      alert_type: :emergency_response_undeliverable,
      message_key: key,
      message_params: { **dedup, **params }
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

  # Дедуп — набір полів, бо осей три: `actuator_id` (відмова конкретному пристрою) ⊥
  # `device_type` (крок, який нема кому виконати) ⊥ `actuator_id` + `ews_alert_id` (факт чи
  # попередження ОДНІЄЇ тривоги). Імʼя кожного поля йде bind-параметром у сам оператор
  # `->>`, тож нова вісь не приносить ані другого запиту, ані склеєного SQL.
  private_class_method def self.undeliverable_alert_exists?(cluster_id, key, dedup)
    dedup.reduce(EwsAlert.unresolved.alert_type_emergency_response_undeliverable
                         .where(cluster_id: cluster_id, message_key: key)) do |scope, (field, value)|
      scope.where("message_params ->> ? = ?", field.to_s, value.to_s)
    end.exists?
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
end
