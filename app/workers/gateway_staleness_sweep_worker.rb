# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.54 Шар 0] Dead-man switch Королеви: Rails сам детектить тишу шлюзу,
# не покладаючись на здатність хворого кричати (heartbeat/SOS — Шари 1-2,
# вони ЗБАГАЧУЮТЬ, а цей sweeper — первинний permanence-сторож NaaS).
#
# Канон: 06_08 §1.3 (Queen Health Heartbeat → Rails). Тиша = last_seen_at
# прострочив config_sleep_interval_s з люфтом 1.2 (скоуп Gateway.offline —
# One-Home порога, той самий, що online?/дашборд).
#
# Три обов'язки за один прохід:
#   1. offline + робочий стан → report_fault! + EwsAlert(queen_offline)
#      (критичний: кластер осліп, емісія його дерев без нагляду).
#   2. faulty + знову online → recover! + resolve відповідного алерту
#      (симетрія: тиша скінчилась — лісник не їде дарма).
#   3. attest-lapse спостереження: QATT-Королева (є ed25519 pubkey), батчі
#      ходять (online), а підписи зникли > ATTEST_LAPSE_HOURS — можлива
#      підміна прошивки/деградація L1. Поки лише метрика+лог (алерт-тип
#      додамо, коли L1 стане mandatory — свідома стеля, 00_07 ARCH.54).
#   4. [ARCH.59] Королева, залипла в `:updating` → finish_update! + алерт.
#   5. [ARCH.75] накази до `faulty`-Королеви → `failed` (див. нижче).
class GatewayStalenessSweepWorker
  include Sidekiq::Job
  # alerts(2): народжує life-safety сигнали EWS — вище за critical(3)-slash
  # у strict-дренажі; сам прохід — кілька легких запитів.
  sidekiq_options queue: "alerts", retry: 2

  ATTEST_LAPSE_HOURS = 24

  # [ARCH.59] Вікно живої OTA-кампанії — ВИВЕДЕНЕ, не зі стелі, і формула
  # перерахунку тут навмисно, бо образ росте: Королева тягне
  # `QUEEN_OTA_FETCH_PER_FLUSH` = **4** чанки за флаш, флаш ≈ година, чанк 512 B
  # (`OtaPackagerService::COAP_MTU`). Поточний bytecode ≈ 2.3 КБ = 5 чанків ≈ 2
  # флаші ≈ 2 год, тож 24 год — приблизно 12× запас і покриває образ до ~48 KB.
  # ⛔ Стеля названа: НИЖНЬОЇ межі каденсу флашу не існує взагалі (таймерна нога
  # гейтована `cache_count > 0 || ed25519_ready` — ARCH.75), тож на мовчазній
  # legacy-Королеві жодне вікно не є «достатнім». Це вікно відмови від кампанії,
  # а не обіцянка, що за нього вона встигне.
  OTA_STUCK_MARGIN = 24.hours

  def perform
    flagged   = flag_silent_gateways
    recovered = recover_returned_gateways
    lapsed    = observe_attest_lapse
    released  = release_stuck_ota_gateways
    # ⚠️ ПІСЛЯ `flag_silent_gateways` навмисно: Королева, що замовкла в цьому ж
    # проході, мусить лишити по собі термінований наказ ТИМ САМИМ проходом —
    # інакше він живе зайвий цикл крону. Порядок запінений прикладом.
    reaped    = reap_undeliverable_commands

    SilkenNet::Metrics::GATEWAYS_FAULTY.set(Gateway.faulty.count)
    SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED.set(lapsed)

    Rails.logger.info(
      "👑 [ARCH.54] Staleness sweep: flagged=#{flagged} recovered=#{recovered} " \
      "attest_lapsed=#{lapsed} ota_released=#{released} cmd_reaped=#{reaped}"
    )
  end

  private

  # Мовчазні шлюзи у робочих станах → faulty + алерт. Свідомо ПОЗА скоупом:
  # maintenance (людина вже знає) і last_seen_at IS NULL (шлюз зареєстрований,
  # але ще ніколи не виходив в ефір — «мовчання ненародженого» ≠ деградація;
  # стеля позначена: field-інсталяція без першого зв'язку лишається невидимою
  # до першого mark_seen!).
  def flag_silent_gateways
    count = 0
    Gateway.offline.where.not(last_seen_at: nil)
           .where(state: [ :idle, :active, :updating ])
           .includes(:cluster).find_each do |gateway|
      gateway.report_fault!
      create_offline_alert(gateway)
      SilkenNet::Metrics::GATEWAYS_OFFLINE_TOTAL.increment
      count += 1
    end
    count
  end

  # [ARCH.59] Четвертий обов'язок: Королева, що залипла в `:updating`.
  #
  # 🔴 **Симптом, яким цей клас відкрили, ПОМЕР — і лік від того змінився.** Пункт
  # казав «`:updating` блокує ВСІ downlink включно з сиреною»; це було правдою в
  # push-еру, коли гейт `raise "Gateway Busy: Updating"` стояв у
  # `ActuatorCommandWorker`. Той воркер FW.60 зняв із тракту (нуль enqueuer'ів), а
  # ЖИВИЙ poll-тракт (`Downlink::PendingQueueService`) на цей стан не дивиться
  # взагалі — CMD видається як звичайно. Тож сирена й полив сьогодні НЕ страждають.
  #
  # Реальний наслідок тихіший і не самолікується: `Gateway.ota_deployable`
  # виключає `updating`, а вийти зі стану можна лише через `observe_delivered_firmware!`
  # — тобто через звіт Королеви, який уже не прийде. Замкнена петля: шлюз назавжди
  # випадає з МАЙБУТНІХ OTA-кампаній, і ніхто не дізнається, бо він online, а
  # `flag_silent_gateways` вимагає `Gateway.offline`.
  #
  # ⚠️ Тому НЕ `report_fault!`, як приписував пункт: `faulty` стоїть у тому ж
  # списку виключень `ota_deployable`, тобто міняв би одну блокуючу причину на
  # іншу. Вихід — `finish_update!` (стан не стверджує успіху: `firmware_version`
  # лишається старою), а кампанія знімається, бо «не автоматизувати мовчки» —
  # ратифікований дефолт сусіднього ⚖️ цього ж пункту: повторний деплой ухвалює
  # людина, побачивши алерт.
  def release_stuck_ota_gateways
    count = 0

    stuck_ota_scope.includes(:cluster).find_each do |gateway|
      abandoned_firmware_id = gateway.pending_firmware_id
      started_at = gateway.ota_started_at

      ActiveRecord::Base.transaction do
        # ⚠️ Умова несуча: нога (3) ловить шлюз, якому стан НЕ виставляли, і
        # `finish_update!` там кинув би `AASM::InvalidTransition` — rescue нижче
        # проковтнув би його, кампанія лишилась би висіти, а прохід рахувався б
        # виконаним. Знімати треба таргет, а стан чіпати лише там, де він є.
        gateway.finish_update! if gateway.updating?
        gateway.update!(ota_started_at: nil, pending_firmware_id: nil)
        create_ota_stuck_alert(gateway, abandoned_firmware_id, started_at)
      end
      count += 1
    rescue ActiveRecord::ActiveRecordError, AASM::InvalidTransition => e
      # Rescue НА ЗАПИС (дзеркало ActuatorSafetySweepWorker): одна проблемна
      # Королева не сміє обірвати прохід для решти флоту.
      Rails.logger.error "🛑 [ARCH.59] Шлюз #{gateway.uid} не звільнено з :updating: #{e.message}"
    end

    count
  end

  # ТРИ предикати, і вони ловлять три РІЗНІ поломки — межу між ними легко
  # стерти, а вона несуча.
  #
  # (1) `anchored` — передача почалась і не дійшла: живий, штатний випадок.
  #
  # (2) `anchorless` — backstop проти стану, якого живий код не створює:
  #     `Downlink::PendingQueueService` пише стан і якір ОДНИМ `update!`, тож
  #     `updating` без `ota_started_at` є аномалією за побудовою; єдиний писач,
  #     що так умів, — `OtaTransmissionWorker` (push-ера, нуль enqueuer'ів).
  #     Часова межа тут по `updated_at`, бо іншого якоря в такого рядка немає.
  #     ⚠️ Доти цей коментар приписував саме сюди клас «затаргечений-але-не-
  #     анонсований» — неправда: обидві ноги вище вимагають `state: :updating`,
  #     тобто бачать лише тих, кому стан УЖЕ виставили.
  #
  # (3) `unannounced` — власне «затаргечений, але не анонсований» [ARCH.59]:
  #     кампанія записана диспетчером, а hint не пішов ЖОДНОГО разу, тож стану
  #     немає й не буде. Три відомі причини сходяться сюди однаково — шлюз без
  #     `hardware_key` (`ota_deployable` ключа не питає, а `poll_reply` без KEYC
  #     виходить ДО hint'а), Королева, що не поллить (CGNAT/мертва), і dangling
  #     `pending_firmware_id` (bigint без FK → `ota_packages` віддає nil).
  #     Якір — той самий `ota_started_at`, який тепер ставить диспетчер.
  # [ARCH.75] Пʼятий обовʼязок: наказ, який уже НЕМОЖЛИВО доставити, дістає
  # термінальний стан — і поза poll-трактом.
  #
  # 🔴 Чому це взагалі потрібно: термінатор СПРОЄКТОВАНИЙ і МЕРТВИЙ.
  # `ActuatorCommandWorker` несе `sidekiq_retries_exhausted`, який ставить
  # `failed` — але FW.60 зняв push-тракт, і живих enqueuerʼів того воркера нуль
  # (єдиний `perform_async` у дереві живе всередині коментаря). Хук у проді не
  # викликається жодного разу; зеленим його тримає сюїта, що смикає воркер
  # руками. Лишається poll-тракт, а він матеріалізує кінець наказу рівно в
  # момент видачі — тобто тоді, коли Королева ПРИХОДИТЬ. На тій, що не прийде
  # більше ніколи, наказ лежав би `pending` вічно.
  #
  # 🔴 Ціна була не бухгалтерська: контролер тримає 409 на `live_pending`, а
  # наказ від ЛЮДИНИ не має `expires_at` взагалі (писачів TTL рівно два —
  # `EmergencyResponseService` і STOP safety-свіпа), тож `scope :expired` його
  # не матчить ніколи. Один клік по Королеві, що потім померла, назавжди
  # відрізав форестера від цього актуатора.
  #
  # ⚖️ Дискримінатор — ПОДІЯ, не час (присуд founder 2026-08-17): наказ мертвий,
  # коли його Королева оголошена `faulty`. Часовий поріг завів би друге
  # непідписане число поруч із відкритим ⚖️ про `relevance`, а цей сигнал уже
  # ратифікований і рахується сусідніми ногами.
  #
  # 🔒 Свіп по СТАНУ, а не гачок на `report_fault!`: шляхів у `faulty` два —
  # нога (1) вище і `HeliumSosWorker`, — тож гачок на один був би N−1 із N.
  # ⚠️ Стеля названа: Королева вміє ПОВЕРТАТИСЬ (нога 2), тож наказ, поданий за
  # хвилину до обриву звʼязку, згорить, хоч пристрій ожив би згодом. Це
  # свідомий обмін — «висить вічно й блокує канал» гірше за «згорів при обриві»,
  # а для протокольних наказів чесний строк дає їхній власний `expires_at`.
  def reap_undeliverable_commands
    count = 0

    ActuatorCommand.pending.joins(actuator: :gateway).merge(Gateway.faulty).find_each do |command|
      command.fail!("🛑 [ARCH.75] Королева недосяжна (faulty) — наказ не буде доставлено")
      ActuatorCommandWorker.broadcast_command_state_static(command)
      count += 1
    rescue ActiveRecord::ActiveRecordError, AASM::InvalidTransition => e
      # Rescue НА ЗАПИС (дзеркало ніг 1 і 4): один проблемний наказ не сміє
      # обірвати прохід для решти флоту.
      Rails.logger.error "🛑 [ARCH.75] Наказ ##{command.id} не термінований: #{e.message}"
    end

    count
  end

  def stuck_ota_scope
    anchored = Gateway.where(state: :updating).where(ota_started_at: ...OTA_STUCK_MARGIN.ago)
    anchorless = Gateway.where(state: :updating, ota_started_at: nil)
                        .where(updated_at: ...OTA_STUCK_MARGIN.ago)
    unannounced = Gateway.where.not(pending_firmware_id: nil)
                         .where.not(state: :updating)
                         .where(ota_started_at: ...OTA_STUCK_MARGIN.ago)

    Gateway.where(id: anchored)
           .or(Gateway.where(id: anchorless))
           .or(Gateway.where(id: unannounced))
  end

  # Дедуп по `message_params ->> 'uid'`, а не по кластеру: тип `system_fault`
  # ділять девʼять писачів, тож cluster-scoped guard глушив би чужі сигнали
  # (конвенція вже жива в `Treasury::MonitorService` — дедуп по парі
  # `message_key` + параметр ідентичності).
  def create_ota_stuck_alert(gateway, firmware_id, started_at)
    return if ota_stuck_alert_exists?(gateway)

    # `medium`, не `critical`: провалена OTA-кампанія не є life-safety подією
    # (сирена й полив їдуть poll-трактом незалежно від цього стану — див. вище),
    # а `critical` тут розбавляв би чергу справжніх аварій. ⚠️ Рівнів рівно три
    # (`low`/`medium`/`critical`) — `:warning` в цьому enum'і не існує.
    EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :medium,
      alert_type: :system_fault,
      message_key: "queen_ota_stuck",
      message_params: {
        uid: gateway.uid,
        stuck_for_h: started_at ? ((Time.current - started_at) / 3600).round : OTA_STUCK_MARGIN.in_hours.round,
        firmware_id: firmware_id.to_i
      }
    )
  end

  # ⚠️ Дедуп ключується на КОЛОНЦІ `message_key` (не на JSONB-предикаті): у
  # `where("… ? …")` знак питання Rails прийняв би за bind-плейсхолдер, і умова
  # зламалась би тихо.
  def ota_stuck_alert_exists?(gateway)
    EwsAlert.unresolved.alert_type_system_fault
            .where(cluster_id: gateway.cluster_id, message_key: "queen_ota_stuck")
            .where("message_params ->> 'uid' = ?", gateway.uid)
            .exists?
  end

  def recover_returned_gateways
    count = 0
    Gateway.online.faulty.includes(:cluster).find_each do |gateway|
      gateway.recover!
      resolve_comms_alerts(gateway)
      count += 1
    end
    count
  end

  # Дедуп по кластеру: EwsAlert-валідація uniqueness тримає лише tree_id-алерти
  # (tree_id тут nil), тому анти-спам guard — руками. Стеля: друга Королева
  # того ж кластера, що впала ПІД активним алертом першої, окремого алерту не
  # отримає (uid — у message; кластер сьогодні ~1 Queen). cluster_id завжди
  # present — Gateway#belongs_to :cluster обов'язковий.
  def create_offline_alert(gateway)
    return if EwsAlert.unresolved.alert_type_queen_offline
                      .exists?(cluster_id: gateway.cluster_id)

    silent_for = ((Time.current - gateway.last_seen_at) / 60).round
    EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: :queen_offline,
      message_key: "queen_silent",
      message_params: { uid: gateway.uid, silent_for_min: silent_for,
                        last_seen_at: gateway.last_seen_at.utc.iso8601 }
    )
  end

  # Резолвимо ОБИДВА comms-типи: dead-man switch (ми помітили тишу) і Helium-SOS
  # (Королева крикнула через чужі hotspot'и, ARCH.34). Обидва стверджують одне —
  # «Королева без uplink» — і обидва спростовує той самий факт: вона знову в ефірі.
  # До цього queen_uplink_lost не мав резолвера ЖОДНОГО (HeliumSosWorker обіцяв
  # «sweeper-recovery після повернення батчів», але sweeper фільтрував лише
  # queen_offline) → лишався активним вічно й латчив comms_no_ack? назавжди.
  # resolve! без `user:` — машинний шлях (дискримінатор gap-E: див.
  # BlockchainBurningService#critical_unmaintained?).
  def resolve_comms_alerts(gateway)
    EwsAlert.unresolved
            .where(alert_type: [ :queen_offline, :queen_uplink_lost ])
            .where(cluster_id: gateway.cluster_id).find_each do |alert|
      alert.resolve!(key: "gateway_returned",
                     params: { uid: gateway.uid,
                               seen_at: gateway.last_seen_at.utc.iso8601 }) # online ⇒ present
    end
  end

  # QATT-джерело правди: HardwareKey#ed25519_public_key_hex (той самий
  # реєстр, що верифікація конверта). last_attested_at нарешті отримує
  # читача (до ARCH.54 колонка була write-only).
  def observe_attest_lapse
    lapsed = Gateway.online.joins(:hardware_key)
                    .where.not(hardware_keys: { ed25519_public_key_hex: [ nil, "" ] })
                    .where(last_attested_at: [ nil, ...ATTEST_LAPSE_HOURS.hours.ago ])
    lapsed.find_each do |gateway|
      Rails.logger.warn(
        "👑 [ARCH.54] Attest-lapse: #{gateway.uid} online, але QATT-підпису нема " \
        "з #{gateway.last_attested_at&.utc&.iso8601 || 'ніколи'} — перевірити EDSK/прошивку."
      )
    end
    lapsed.count
  end
end
