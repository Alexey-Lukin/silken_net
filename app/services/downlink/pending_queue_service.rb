# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Downlink
  # [FW.60] Черга Rails→Queen downlink для poll-після-флашу (LwM2M Queue-Mode):
  # Queen сама питає `poll/<uid>` одразу після send_success — цей сервіс
  # derive'ить «що віддати» з наявного стану БД, без власної таблиці-черги.
  #
  # Пріоритет: CMD (life-safety) > 0x9E ratchet (gated FW.17) > OTA-hint >
  # 0x9A смуга Лоренца (gated FW.8) > time-only конверт. 0x9C у пріоритет-рядку
  # трекера задовольняється тотожно:
  # CoapEncryption вшиває [0x9C][ts:4] у КОЖЕН конверт — будь-яка відповідь
  # (включно з порожньою time-only) синхронізує RTC Королеви.
  #
  # OTA їде окремим stateless chunk-server'ом (`ota/<uid>?v=&ch=`): Queen
  # єдина знає свій bitmap, тож веде прогрес сама; Rails персистить лише
  # таргет кампанії (gateways.pending_firmware_id — canary-когорту пише
  # Ota::DeploymentDispatcherService) і спостерігає доставку через
  # `fw=<contract_id>` у poll-query (RAM-стан Королеви: 0 після ребуту →
  # повторний hint → безпечний idempotent re-fetch).
  class PendingQueueService
    include CoapEncryption

    # Дзеркало firmware CMD_DECRYPT_BUF_SIZE (544) + IV 16: конверт понад цю
    # стелю Queen мовчки відкине ще до decrypt (03_02 §5 «Вхідні перевірки»).
    MAX_ENVELOPE_BYTES = 560

    OTA_HINT_MARKER = 0x9F # [0x9F][firmware_id:4 BE][total_packages:2 BE]

    # [ARCH.75] Найгірше очікування downlink'а — дзеркало прошивки:
    # `FLUSH_INTERVAL_MS` 3600000 + `FLUSH_JITTER_MAX_MS` 60000 (`firmware/queen/main.c`).
    # 🔴 **Чому НЕ `gateways.config_sleep_interval_s`:** прошивка тієї колонки не читає
    # ВЗАГАЛІ (нуль згадок у `firmware/`), і downlink'а, який доніс би її до Королеви,
    # не існує — це Rails-side переконання без носія. Порівнювати з ним вікно доставки
    # означало б міряти вигадану величину: шлюз, провіжінений на 3600, і шлюз із 300
    # флашать ОДНАКОВО, за компайл-тайм таймером. ⚠️ Це стеля ЗВЕРХУ для таймерної
    # ноги; нижньої межі каденсу не існує взагалі — таймерний флаш сам гейтований
    # `cache_count > 0 || ed25519_ready`, тож мовчазна legacy-Королева не флашить
    # ніколи. Тобто «вкладаємось» тут = «не можемо довести, що НЕ вкладемось».
    # ⚠️ І це таймер, а не весь інтервал між poll'ами: `last_flush_time` ставиться
    # ПІСЛЯ `Flush_Cache_To_Rails()`, усередині якого й живе poll, тож до 3660 с
    # додається тривалість флашу (`FLUSH_SESSION_BUDGET_S` нижче). Сьогоднішні вікна
    # мають запас; гілку «скоротити таймер для сирени» ратифіковано (⚖️ FW.64
    # 2026-09-28: 600 000 мс → 660 с, парою з прошивкою й разом з ARCH.75) — і тоді
    # цей член лишає сирені 900 − 660 − 190 = 50 с на реле.
    WORST_CASE_POLL_INTERVAL_S = 3660

    # [FW.64] Тривалість самого флашу — член, якого таймер вище не несе: номінально
    # десятки секунд, за сумою бюджетів таймаутів `queen/main.c` — до ≈ 190 с (звірено
    # адверсарним рев'ю 2026-09-27). ⚠️ Оцінка зверху з бюджетів, не вимір: реальну
    # тривалість дає стенд [bench:queen-cadence]. Читачі — сирена (коментар вище) і вікно
    # живості `Gateway.liveness_window_for`, де цей член АДИТИВНИЙ, а не частка таймера.
    FLUSH_SESSION_BUDGET_S = 190

    # Чи встигне downlink доїхати за `seconds` — питання ПЛАТФОРМИ, не пристрою.
    def self.reachable_within?(seconds)
      WORST_CASE_POLL_INTERVAL_S <= seconds.to_i
    end

    def self.poll_reply(gateway:, query:)
      new(gateway).poll_reply(query)
    end

    def self.ota_chunk_reply(gateway:, query:)
      new(gateway).ota_chunk_reply(query)
    end

    def initialize(gateway)
      @gateway = gateway
    end

    # → envelope-байти ([IV:16][AES-256-CBC KEYC]) або nil (нема ключа —
    # CoapGate відповість 4.04, Queen не почне decrypt сміття).
    def poll_reply(query)
      return nil unless encryption_key

      observe_delivered_firmware!(query["fw"])
      observe_delivered_command!(query["cmd"])

      envelope(next_inner_payload)
    end

    # Stateless chunk-server: ?v=<firmware_id>&ch=<n> → конверт із чанком.
    # nil → 4.04 (чужа/завершена версія, ch поза межами — Queen перечитає hint).
    def ota_chunk_reply(query)
      return nil unless encryption_key

      firmware_id = query["v"].to_i
      chunk_index = query["ch"].to_i
      return nil unless firmware_id.positive? && firmware_id == @gateway.pending_firmware_id

      packages = ota_packages(firmware_id)
      return nil unless packages && chunk_index < packages.size

      SilkenNet::Metrics::OTA_CHUNKS_SENT_TOTAL.increment(
        labels: { firmware_version: firmware_version_label(firmware_id) }
      )
      broadcast_ota_progress(chunk_index + 1, packages.size, "TRANSMITTING")
      envelope(packages[chunk_index])
    end

    private

    # Пріоритет-драбина. Кожна сходинка повертає inner-байти або nil.
    def next_inner_payload
      actuator_command_payload || key_rotation_payload || ota_hint_payload || thresholds_payload || "".b
    end

    # ── CMD (найпріоритетніший — сирена/клапан) ──────────────────────────
    # [FW.63] Видача в 2.05 НЕ є доказом доставки (poll-тракт прошивки
    # ретрансміту не має — `coap_mid++` на кожну спробу, `Sim7070_Udp_Fetch` —
    # одна розмова; same-MID retry живе лише в uplink-PUT). Тому тут — лише
    # `dispatch!` (issued→sent); acknowledge!/mark_active!/Reset-план ЧЕКАЮТЬ
    # `observe_delivered_command!` нижче — дзеркало вже наявного `fw=`-патерну.
    # `:sent` лежить у скоупі `.pending`, тож недоставлена команда re-serve'иться
    # на наступному poll'і тим самим `inner` (той самий idempotency_token) —
    # безпечно, бо `Cmd_Dedup_Check` на Королеві вже унеможливлює подвійне
    # виконання повторно доставленого токена. Протерміновується вона так само,
    # як і раніше — TTL-гілка нижче на статус `:sent` сліпа.
    def actuator_command_payload
      loop do
        command = pending_commands.first
        return nil unless command

        if command.expired?
          # [FW.60] `pending_commands` віддає лише `.pending` = [:issued, :sent],
          # а подія `fail` приймає їх НАДмножину `from:` — тут `may_fail?`
          # завжди true. Гард знято як мертву гілку (FW.60 тріаж `04_06 §B.4` 2026-09-09).
          command.fail!("⏱️ Команда протермінована (TTL: #{command.expires_at})")
          # [UI.4] Fail теж мусить доїхати до UI. Поки бейдж був статичним, німий
          # fail-шлях не мав симптому; з живою підпискою він застигав би на
          # «виконується» до перезавантаження — живість, що бреше, гірша за
          # чесну статику.
          ActuatorCommandWorker.broadcast_command_state_static(command)
          # [FW.64] Аварійний наказ, що протух у черзі, — не-дія, і вона мусить свідчити
          # про себе алертом, а не лише бейджем (для наказу оператора — лише бейдж).
          EmergencyResponseService.report_expired(command)
          next
        end

        inner = "CMD:#{command.command_payload}:#{command.duration_seconds}:" \
                "#{command.actuator_id}:#{command.idempotency_token}"
        if oversized?(inner)
          # [FW.60] Той самий доказ, що вище — `may_fail?` тут завжди true.
          command.fail!("Конверт понад стелю Queen (#{MAX_ENVELOPE_BYTES} Б)")
          ActuatorCommandWorker.broadcast_command_state_static(command)
          next
        end

        # [FW.60 case 3, тріаж `04_06 §B.4` 2026-09-09] `pending_commands.first` — без `FOR
        # UPDATE`. Гард нижче НЕДОСЯЖНИЙ сьогодні: єдиний прод call-site цього
        # сервісу — однопроцесний однопотоковий `lib/daemons/coap_listener`
        # (наступний датаграм читається лише ПІСЛЯ повного коміту цієї
        # транзакції), тож двох одночасних `pending_commands.first` не існує
        # СТРУКТУРНО — не Rails request-per-thread (тут нема Puma/контролера
        # взагалі), а серіалізація самим демоном. Стеля — день, коли CoAP-інтейк
        # перестане бути одним процесом: гарантію дає ОТОЧЕННЯ, не цей код, і
        # тоді гард прокинеться без жодної зміни тут (скіл `backend` #85).
        command.dispatch! if command.may_dispatch?
        ActuatorCommandWorker.broadcast_command_state_static(command)

        return inner
      rescue ActiveRecord::RecordInvalid => e
        # [FW.63] Єдиний запис тут — сам `command` (`dispatch!`); `actuator` цей
        # метод більше не чіпає (mark_active! переїхав у observe_delivered_command!),
        # тож `e.record` завжди `ActuatorCommand` — дублювати перевірку не треба.
        # `EmergencyResponseService` пише `insert_all` (валідації обходить); з ARCH.75
        # він відсіює актуатори за стелею ДО запису, тож невалідним рядок тут стає,
        # коли стелю актуатора знизили вже ПІСЛЯ запису (той самий клас, що
        # `force_close_unpersistable!`). Тоді БУДЬ-який AASM-перехід б'ється
        # об `duration_within_safety_envelope` — включно з TTL-прибиранням, тож
        # рядок не вміє навіть померти. Демон виняток ЛОВИТЬ (`rescue StandardError`
        # у `lib/daemons/coap_listener`; `SecurityError` < Exception летів би повз,
        # але його джерело — OTA-пакування — з coap винесено), та `reply` лишається непризначеним, тож
        # `socket.send` не відбувається: poll БЕЗ ВІДПОВІДІ назавжди, і разом із
        # CMD мертві ratchet, OTA-hint і time-sync шлюза. Force-fail через `update_columns`
        # (дзеркало `dispatch_to_edge!`) — єдиний спосіб винести такий рядок із
        # черги. Виміряно, не виведено. Політика чанкування — ⚖️ в ARCH.75.
        force_fail_unpersistable!(command, e)
        next
      end
    end

    # `update_columns` свідомо: рядок невалідний, тож будь-який шлях через
    # валідації (`fail!`, `update!`) кинув би той самий виняток удруге. Ланцюг
    # ARCH.57 закриваємо ручним викликом `record_forced_failure_audit!`.
    # `echoed:` [FW.63] — наказ, чию доставку луна вже довела: причина каже це прямо
    # й називає той запис, що не пройшов валідацію (актуатор на `mark_active!`, наказ
    # на `acknowledge!`), — хворий актуатор не записується провиною наказу.
    def force_fail_unpersistable!(command, error, echoed: false)
      # Стан ДО виносу — з БД, а не з `echoed`: невалідний `:sent` фейлиться й на TTL/oversize.
      from = command.status_in_database
      reason = error.record&.errors&.full_messages&.first || error.message
      culprit = error.record.is_a?(Actuator) ? "запис актуатора невалідний" : "наказ не проходить власну валідацію"
      message = echoed ? "Луна підтвердила доставку, але #{culprit}: #{reason}" : "Наказ не проходить власну валідацію: #{reason}"
      command.update_columns(status: ActuatorCommand.statuses[:failed], error_message: message.truncate(200))
      command.send(:record_forced_failure_audit!, echoed ? "echo_unpersistable" : "unpersistable", from: from)
      ActuatorCommandWorker.broadcast_command_state_static(command)
      tag = echoed ? "[FW.63] Луна наказу" : "[ARCH.75] Наказ"
      Rails.logger.error "🛑 #{tag} ##{command.id}: #{message} (#{error.record.class}) — винесено з черги, poll-тракт живий"
    end

    def pending_commands
      ActuatorCommand.joins(:actuator)
                     .where(actuators: { gateway_id: @gateway.id })
                     .pending.by_priority
    end

    # ── 0x9E ratchet (gated FW.17 — той самий guard, що KeyRotationDownlinkWorker) ──
    # Джерело derivable: tree-ключ кластера в Dual-Key Grace
    # (previous_aes_key_hex ≠ NULL = ротація не підтверджена Солдатом).
    def key_rotation_payload
      return nil unless HardwareKeyService.ratchet_dispatch_enabled?

      # [FW.17] Ротацією є лише grace ратчета (версія ≥ 1). Grace після re-provision
      # (версія 0, нова епоха — 03_05 §3.8) закриває MIC, а не 0x9E, і з версії 0
      # `CommandFrame.rotate_key` кадру не будує — без цього фільтра такий grace
      # валив би poll-деривацію всього кластера. Той самий клас — grace без
      # виданого DLFC (0 — рядок до міграції 2026-09-29): Солдат DLFC 0 не прийме,
      # тож кадру в такого grace немає, а виняток тут глушив би весь кластер.
      key = HardwareKey.joins(:tree)
                       .where(trees: { cluster_id: @gateway.cluster_id })
                       .where.not(previous_aes_key_hex: nil)
                       .where(key_version: 1.., downlink_frame_counter: 1..)
                       .order(:updated_at).first
      return nil unless key

      # Адресний CCM-кадр під ПОПЕРЕДНІМ ключем вузла (03_05 §2.5); на кожному
      # poll — той самий кадр, тож Королева його лише освіжає, а не множить.
      Downlink::CommandFrame.rotate_key(key)
    end

    # ── OTA-hint (нога-2 відкривається Королевою після цього анонсу) ─────
    def ota_hint_payload
      firmware_id = @gateway.pending_firmware_id
      return nil unless firmware_id

      packages = ota_packages(firmware_id)
      return nil unless packages

      unless @gateway.updating?
        # ARCH.59-якір: watchdog ловить stuck-:updating саме за цією парою.
        # ⚠️ `ota_started_at` тут НЕ перезаписується, якщо його вже поставив
        # диспетчер: якір міряє вік КАМПАНІЇ, а не вік передачі, інакше шлюз,
        # що поллить рідко, щоразу обнуляв би власний годинник і не старів ніколи.
        @gateway.update!(state: :updating, ota_started_at: @gateway.ota_started_at || Time.current)
        # 0% лише на ПЕРШОМУ hint'і: hint повторюється кожен poll до
        # fw=-підтвердження, але Queen тримає курсор кампанії (re-hint того
        # самого fw НЕ скидає bitmap) — re-broadcast 0% пиляв би бар назад.
        # Після ребуту Королеви бар виправить перший chunk-broadcast.
        broadcast_ota_progress(0, packages.size, "TRANSMITTING")
      end

      [ OTA_HINT_MARKER, firmware_id, packages.size ].pack("CNn")
    end

    # ── 0x9A смуга Лоренца (gated FW.8, ⚖️ founder 2026-09-29) ──────────
    # НИЖЧЕ OTA-hint свідомо: hint живе до `fw=`, тобто лише поки Королева сама
    # качає образ, а видача смуги лишається відкритою тижнями — доказ її
    # застосування рідкісний (03_04 §5.3), тож вище за hint вона морила б OTA.
    # Один кадр на poll; першим — дерево, якому найдовше не видавали. Що видати
    # і коли перевидати, вирішує Downlink::ThresholdBand.
    def thresholds_payload
      return nil unless Downlink::ThresholdBand.dispatch_enabled?

      now = Time.current
      Tree.where(cluster_id: @gateway.cluster_id, status: %i[active dormant])
          .includes(:cluster, :tree_family, :hardware_key)
          .order(Arel.sql("lorenz_band_served_at ASC NULLS FIRST"), :id)
          .each do |tree|
        frame = Downlink::ThresholdBand.serve!(tree, now: now)
        return frame if frame
      end
      nil
    end

    # Спостережене підтвердження доставки: Queen несе свій RAM-стан
    # «повністю зібраний contract_id» у кожному poll (0 після ребуту).
    def observe_delivered_firmware!(fw_param)
      delivered_id = fw_param.to_i
      pending_id = @gateway.pending_firmware_id
      return unless pending_id && delivered_id >= pending_id

      # [FW.60 case 4, тріаж `04_06 §B.4` 2026-09-09] `pending_id` — голий bigint без FK:
      # застосунок сьогодні не має ЖОДНОГО кодового шляху видалення
      # BioContractFirmware (виміряно — нуль destroy/delete у app/+lib/,
      # `resources :firmwares` без :destroy), але оператор у `rails console`
      # може стерти рядок будь-якої миті (нема `before_destroy`-guard) — тож
      # `find_by` НЕ на `find`, а фолбек нижче лишається LEAVE, не dead code.
      # Пін — spec «dangling pending_firmware_id…».
      firmware = BioContractFirmware.find_by(id: pending_id)
      # [ARCH.59] `ota_started_at: nil` — якір ЗНІМАЄТЬСЯ на завершенні, і доти
      # його не чистив ніхто (нуль call-sites). Без цього поле пережило б власну
      # кампанію й показувало б час давно закритої OTA, а watchdog у
      # `GatewayStalenessSweepWorker` читає саме пару «стан + якір».
      @gateway.update!(
        pending_firmware_id: nil,
        ota_started_at: nil,
        firmware_version: firmware&.version || @gateway.firmware_version,
        state: @gateway.updating? ? :idle : @gateway.state
      )
      broadcast_ota_progress(0, 0, "COMPLETE")
    end

    # [FW.63] Спостережене підтвердження CMD — дзеркало observe_delivered_firmware!
    # вище. Королева тримає RAM-токен останньої УСПІШНО обробленої команди (нове
    # виконання АБО дедуп-збіг повтору — обидва означають «конверт доїхав і
    # Cmd_Dedup_Check його побачив») і несе його в КОЖНОМУ наступному poll'і, доки
    # не заступить новий. Ідемпотентно за побудовою: `status_sent`-звуження саме
    # й робить повторний echo безпечним no-op'ом (команда вже поза `:sent` після
    # першого acknowledge!, `find_by` просто не знайде її вдруге).
    def observe_delivered_command!(cmd_token)
      return if cmd_token.blank?

      command = ActuatorCommand.joins(:actuator)
                               .where(actuators: { gateway_id: @gateway.id })
                               .status_sent
                               .find_by(idempotency_token: cmd_token)
      return unless command

      # may_activate?-guard: друга команда на ВЖЕ активний актуатор
      # (подовження/override) — легальний потік; голий mark_active! тут
      # кидав би AASM::InvalidTransition (латентна бомба ще push-воркера).
      # Обидва записи — ОДНА транзакція: RecordInvalid на `acknowledge!` інакше лишав би
      # актуатор `active` без жодного підтвердженого наказу, а свіп безпеки такого не
      # бачить за побудовою — у нього немає вікна (адверсарне рев'ю 2026-09-27).
      ActiveRecord::Base.transaction do
        command.actuator.mark_active! if command.actuator.may_activate?
        command.acknowledge! if command.may_acknowledge?
      end
      return unless command.status_acknowledged?

      ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)
      ActuatorCommandWorker.broadcast_command_state_static(command)
    rescue ActiveRecord::RecordInvalid => e
      # [FW.63] Луна вже ДОВЕЛА доставку, тож повторна видача нічого не додає. Лишений
      # `:sent`, наказ стояв би головою `.pending` на КОЖНОМУ poll'і (`may_dispatch?` —
      # false, ревалідації немає), Королева дедупила б і знову несла той самий токен, і
      # решта наказів шлюзу голодувала б до його TTL (пожежний полив — 2 год; адверсарне
      # рев'ю FW.64, 2026-09-27). Тож виносимо — тим самим force-fail, що й невалідний
      # наказ при видачі; активацію транзакція вище вже відкотила. На відміну від dispatch!
      # тут пишеться ще й `actuator`, тож причину веде той запис, що впав.
      # ⚠️ Стеля: `failed` тут не бреше про фізику лише доти, доки актуаторної прошивки немає
      # (Королева ACTION не виконує — 03_02 §6). З її появою доставлений наказ працюватиме
      # без Reset і без STOP у БД, і цей вихід мусить ще й ставити override-STOP (00_07
      # ARCH.58, нога першого actuator-hardware). Людський слід для EWS-наказу — ключ
      # «отримано, але не записано» (⚖️ делеговано 2026-09-28, 00_07 FW.63).
      force_fail_unpersistable!(command, e, echoed: true)
      EmergencyResponseService.report_unrecorded(command)
    end

    def firmware_version_label(firmware_id)
      Rails.cache.fetch("fw60/fw_version/#{firmware_id}", expires_in: 1.hour) do
        BioContractFirmware.find_by(id: firmware_id)&.version.to_s
      end
    end

    # Пакети кампанії: той самий масив живить hint (total) і chunk-server (байти).
    # ⛔ Тут лише ЧИТАННЯ: coap-процес master-key не має (SEC.22), тож пакують
    # писачі `Ota::PackageStore` — диспетчер і OTA-сторож. Промах → nil: hint
    # пропущено (poll однаково віддає time-only — RTC-sync Королеви живий),
    # chunk → 4.04, і сторож прогріває на найближчому проході.
    def ota_packages(firmware_id)
      packages = Ota::PackageStore.read(firmware_id, @gateway.cluster_id)
      return packages if packages

      Rails.logger.error "🛑 [FW.60] OTA-пакунки #{firmware_id}/cluster #{@gateway.cluster_id} " \
                         "не прогріто — #{@gateway.uid} чекає на OTA-сторожа"
      nil
    end

    # [SEC.20] Живий producer OTA-прогрес-бара (push-воркер superseded FW.60):
    # hint = старт, chunk-fetch = прогрес, fw= у poll'і = завершення.
    # Підписники: Gateways::Show + Firmwares::Index (04_04 §8).
    # Rescue-ізоляція: ми в синхронному reply-шляху coap-демона — збій
    # cable-транспорту не сміє вбити конверт (UI-декорація ≠ доставка).
    def broadcast_ota_progress(current, total, status)
      percent =
        if total.positive?
          ((current.to_f / total) * 100).to_i
        else
          # [FW.60] Єдиний виклик з не-позитивним `total` — жорстко
          # `(0, 0, "COMPLETE")` з `observe_delivered_firmware!` нижче: хінт і
          # чанк-фетч завжди несуть `packages.size`, а той має структурну
          # підлогу > 0 (`gateways.cluster_id` NOT NULL → трейлер печатки OTA
          # (`OtaPackagerService#sealed?`) додається завжди). «Хінт з
          # НУЛЬ чанків» — мертва гілка (FW.60 тріаж `04_06 §B.4` 2026-09-09).
          100
        end

      Turbo::StreamsChannel.broadcast_replace_to(
        TurboStreams::Name.gateway_ota(@gateway),
        target: Firmwares::OtaProgressBar.dom_id(@gateway.uid),
        html: Firmwares::OtaProgressBar.new(
          uid: @gateway.uid, percent: percent,
          current: current, total: total, status: status
        ).call
      )
    rescue StandardError => e
      Rails.logger.warn "⚠️ [SEC.20] OTA-прогрес broadcast не пройшов для #{@gateway.uid}: #{e.message}"
    end

    def envelope(inner)
      encrypted = coap_encrypt(inner, encryption_key)
      return encrypted unless oversized_envelope?(encrypted)

      Rails.logger.error "🛑 [FW.60] Конверт #{encrypted.bytesize} Б > стелі " \
                         "#{MAX_ENVELOPE_BYTES} Б для #{@gateway.uid} — відповідаю time-only"
      coap_encrypt("".b, encryption_key)
    end

    # Ключ, який Королева тримає зараз (у Dual-Key Grace — попередній):
    # один дім обох напрямків — HardwareKey#coap_binary_key.
    def encryption_key
      return @encryption_key if defined?(@encryption_key)

      record = @gateway.hardware_key
      @encryption_key =
        if record.nil? || record.aes_key_hex.blank?
          Rails.logger.error "🛑 [FW.60] KEYC для #{@gateway.uid} відсутній — poll без відповіді"
          nil
        else
          record.coap_binary_key
        end
    end

    def oversized?(inner)
      # envelope 5 Б + zero-pad до 16 + IV 16.
      iv_and_ct = 16 + ((inner.bytesize + TIME_SYNC_HEADER_SIZE + 15) / 16) * 16
      iv_and_ct > MAX_ENVELOPE_BYTES
    end

    def oversized_envelope?(encrypted) = encrypted.bytesize > MAX_ENVELOPE_BYTES
  end
end
