# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Downlink
  # [FW.60] Черга Rails→Queen downlink для poll-після-флашу (LwM2M Queue-Mode):
  # Queen сама питає `poll/<uid>` одразу після send_success — цей сервіс
  # derive'ить «що віддати» з наявного стану БД, без власної таблиці-черги.
  #
  # Пріоритет: CMD (life-safety) > 0x9E ratchet (gated FW.17) > OTA-hint >
  # time-only конверт. 0x9C у пріоритет-рядку трекера задовольняється тотожно:
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
    WORST_CASE_POLL_INTERVAL_S = 3660

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
      actuator_command_payload || key_rotation_payload || ota_hint_payload || "".b
    end

    # ── CMD (найпріоритетніший — сирена/клапан) ──────────────────────────
    # Видача в 2.05 = семантичний аналог push-успіху (Queen запитала і
    # отримує відповідь на власний свіжий NAT-pinhole). Тому тут повне дзеркало
    # success-гілки ActuatorCommandWorker: dispatch→acknowledge→mark_active→Reset-план.
    #
    # 🔴 [FW.63] Раніше тут стояло, що «втрату відповіді покриває CON-ретрансміт
    # Королеви + MID-кеш CoapGate». Це НЕПРАВДА: poll-тракт прошивки ретрансміту
    # не має (`coap_mid++` на кожну спробу, `Sim7070_Udp_Fetch` — одна розмова),
    # same-MID retry живе лише в uplink-PUT. Отже стан просувається при ПОБУДОВІ
    # відповіді, а не при її отриманні, і загублена 2.05 губить наказ назавжди —
    # причому слід БРЕШЕ: Reset через `duration_seconds` допише `confirmed`.
    def actuator_command_payload
      loop do
        command = pending_commands.first
        return nil unless command

        if command.expired?
          if command.may_fail?
            command.fail!("⏱️ Команда протермінована (TTL: #{command.expires_at})")
            # [UI.4] Fail теж мусить доїхати до UI. Поки бейдж був статичним, німий
            # fail-шлях не мав симптому; з живою підпискою він застигав би на
            # «виконується» до перезавантаження — живість, що бреше, гірша за
            # чесну статику.
            ActuatorCommandWorker.broadcast_command_state_static(command)
          end
          next
        end

        inner = "CMD:#{command.command_payload}:#{command.duration_seconds}:" \
                "#{command.actuator_id}:#{command.idempotency_token}"
        if oversized?(inner)
          if command.may_fail?
            command.fail!("Конверт понад стелю Queen (#{MAX_ENVELOPE_BYTES} Б)")
            ActuatorCommandWorker.broadcast_command_state_static(command)
          end
          next
        end

        ActiveRecord::Base.transaction do
          command.dispatch! if command.may_dispatch?
          # may_activate?-guard: друга команда на ВЖЕ активний актуатор
          # (подовження/override) — легальний потік; голий mark_active! тут
          # кидав AASM::InvalidTransition (латентна бомба ще push-воркера).
          command.actuator.mark_active! if command.actuator.may_activate?
          command.acknowledge! if command.may_acknowledge?
        end
        ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)
        ActuatorCommandWorker.broadcast_command_state_static(command)

        return inner
      rescue ActiveRecord::RecordInvalid => e
        # Невалідним може виявитись НЕ наказ: у транзакції нижче зберігається ще
        # й `actuator` (`mark_active!` — AASM `whiny_persistence`). Маркувати
        # тоді команду «невалідною» = брехати про винуватця й по одній вигасити
        # цілком доставну чергу хворого актуатора. Пропускаємо лише CMD-сходинку:
        # драбина віддасть ratchet/OTA-hint/time-only, тракт лишається живим, а
        # причина видно в логу під власним іменем.
        unless e.record.is_a?(ActuatorCommand)
          Rails.logger.error "🛑 [ARCH.75] #{e.record.class} ##{e.record.id} невалідний " \
                             "(#{e.record.errors.full_messages.first}) — CMD-сходинку пропущено"
          return nil
        end

        # 🔴 [ARCH.75] Наказ, який НЕ МОЖЕ бути збережений, не сміє вбити тракт.
        # `EmergencyResponseService` пише `insert_all` (валідації обходить) і ріже
        # тривалість за ВЛАСНОЮ константою, не за стелею актуатора — тож при
        # `max_active_duration_s < 3600` (сіди: клапан 300, сирена 120) кожна
        # пожежна команда лягає невалідною. Тоді БУДЬ-який AASM-перехід б'ється
        # об `duration_within_safety_envelope` — включно з TTL-прибиранням, тож
        # рядок не вміє навіть померти. Демон виняток ЛОВИТЬ (`rescue StandardError`
        # у `lib/daemons/coap_listener` — на відміну від `SecurityError` нижче,
        # що справді летить повз), але `reply` лишається непризначеним, тож
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
    # ARCH.57 закриваємо ручним викликом — дзеркало
    # `record_pre_dispatch_failure_audit!`, який робить те саме з тієї ж причини.
    def force_fail_unpersistable!(command, error)
      reason = error.record&.errors&.full_messages&.first || error.message
      command.update_columns(
        status: ActuatorCommand.statuses[:failed],
        error_message: "Наказ не проходить власну валідацію: #{reason}".truncate(200)
      )
      command.send(:record_pre_dispatch_failure_audit!, "unpersistable")
      ActuatorCommandWorker.broadcast_command_state_static(command)
      Rails.logger.error "🛑 [ARCH.75] Наказ ##{command.id} невалідний (#{reason}) — " \
                         "винесено з черги, poll-тракт живий"
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

      key = HardwareKey.joins(:tree)
                       .where(trees: { cluster_id: @gateway.cluster_id })
                       .where.not(previous_aes_key_hex: nil)
                       .order(:updated_at).first
      return nil unless key

      OtaPackagerService.build_rotate_key_block(key.key_version)
    end

    # ── OTA-hint (нога-2 відкривається Королевою після цього анонсу) ─────
    def ota_hint_payload
      firmware_id = @gateway.pending_firmware_id
      return nil unless firmware_id

      packages = ota_packages(firmware_id)
      return nil unless packages

      unless @gateway.updating?
        # ARCH.59-якір: watchdog ловить stuck-:updating саме за цією парою.
        @gateway.update!(state: :updating, ota_started_at: Time.current)
        # 0% лише на ПЕРШОМУ hint'і: hint повторюється кожен poll до
        # fw=-підтвердження, але Queen тримає курсор кампанії (re-hint того
        # самого fw НЕ скидає bitmap) — re-broadcast 0% пиляв би бар назад.
        # Після ребуту Королеви бар виправить перший chunk-broadcast.
        broadcast_ota_progress(0, packages.size, "TRANSMITTING")
      end

      [ OTA_HINT_MARKER, firmware_id, packages.size ].pack("CNn")
    end

    # Спостережене підтвердження доставки: Queen несе свій RAM-стан
    # «повністю зібраний contract_id» у кожному poll (0 після ребуту).
    def observe_delivered_firmware!(fw_param)
      delivered_id = fw_param.to_i
      pending_id = @gateway.pending_firmware_id
      return unless pending_id && delivered_id >= pending_id

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

    def firmware_version_label(firmware_id)
      Rails.cache.fetch("fw60/fw_version/#{firmware_id}", expires_in: 1.hour) do
        BioContractFirmware.find_by(id: firmware_id)&.version.to_s
      end
    end

    # Пакети кампанії — важке пакування кешується per (firmware, cluster):
    # той самий масив живить hint (total) і chunk-server (байти чанків).
    #
    # [FW.60/SEC.11] `OtaPackagerService.prepare` → `OtaHmacKeyService` кидає
    # `SecurityError` (< Exception, НЕ StandardError) без PROVISIONING_MASTER_KEY.
    # Це ЄДИНЕ джерело SecurityError у poll-тракті, а демон-rescue ловить лише
    # StandardError → без цього guard'а перший hint/chunk активної кампанії валив
    # би увесь CoAP-інтейк (телеметрія включно) у crash-loop. Fail-closed: nil →
    # hint пропущено (poll усе одно віддає time-only = RTC-sync Королеви живий),
    # chunk → 4.04. Rescue ЗЗОВНІ cache.fetch — nil не кешується, redeploy з
    # ключем одразу відновлює видачу.
    def ota_packages(firmware_id)
      Rails.cache.fetch("fw60/ota_packages/#{firmware_id}/#{@gateway.cluster_id}",
                        expires_in: 1.hour) do
        firmware = BioContractFirmware.find_by(id: firmware_id)
        next nil unless firmware

        OtaPackagerService.prepare(
          firmware,
          chunk_size: OtaTransmissionWorker::CHUNK_SIZE,
          cluster_id: @gateway.cluster_id
        )[:packages].to_a
      end
    rescue SecurityError => e
      Rails.logger.error "🛑 [FW.60/SEC.11] OTA fail-closed для #{@gateway.uid}: " \
                         "#{e.message.lines.first&.strip} — кампанія стоїть, інтейк живий"
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
          status == "COMPLETE" ? 100 : 0
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

    # Dual-Key Grace: доки Королева не підтвердила ротацію — старий ключ
    # (дзеркало ActuatorCommandWorker).
    def encryption_key
      return @encryption_key if defined?(@encryption_key)

      record = @gateway.hardware_key
      @encryption_key =
        if record.nil? || record.aes_key_hex.blank?
          Rails.logger.error "🛑 [FW.60] KEYC для #{@gateway.uid} відсутній — poll без відповіді"
          nil
        else
          record.binary_previous_key || record.binary_key
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
