# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Downlink
  # [FW.8 · ⚖️ founder 2026-09-29, канон 03_04 §5.3] Облік смуги Лоренца на
  # пристрої: що йому видано і що він, за доказом, може тримати.
  #
  # Підтвердження ефіром немає — downlink-ревізія uplink-байтів не додала. Доказ —
  # САМОСВІДЧЕННЯ статусу: там, де смуги-кандидати дають різний категоричний
  # вердикт, `bio_status` пакета каже, котра з них чинна. Той самий рід доказу,
  # що закриває 0x9E: застосування доводить наступний аплінк.
  #
  # Видача живе з DLFC: перевидача — той самий кадр (ключ, DLFC і ЗАПИСАНЕ тіло),
  # тож Королева лише освіжає бюджет пострілів, а Солдат на повторі Flash-KV не
  # палить. Новий DLFC — коли змінилась бажана смуга або ключ чи лічильник рушили
  # з-під видачі (ротація, re-provision, DR-підйом лічильника).
  #
  # Пишуть облік двоє — демон coap (видача) і розпакувальник (доказ), тож кожен
  # запис іде під замком рядка дерева: множина `held` без нього губила б смугу
  # мовчки, а загублена смуга, яку пристрій справді тримає, — це фрод на чесному.
  module ThresholdBand
    # ENV-дзеркало прошивкового FW8_PARSER_ENABLED (default off — шлях інертний).
    # ⚫ FW.8 (2026-10-06): НЕ вмикати — фліпу прошивки не буде, цей шлях знімає
    # реалізація (Б) (`00_07` FW.66). Історія ECB-ери: вмикали б ПІСЛЯ фліпу, бо
    # вузол без парсера смуги не прийме, і кожен його пакет зі старою смугою
    # лічився б спростуванням.
    GATE_ENV = "FW8_THRESHOLDS_DOWNLINK_ENABLED"

    # Перевидача відкритої видачі — раз на добу: кадр живе в черзі Королеви, доки
    # не витратить `SOLDIER_CMD_SHOT_BUDGET` пострілів у голоси цілі або доки його
    # не витіснять новіші (`SOLDIER_CMD_QUEUE_SLOTS`, найдавніший першим), тож
    # частіша перевидача лише освіжала б бюджет і слот. Інженерний параметр, не
    # вимір. Доказ СТАРОЇ смуги після вікна доставки паузу знімає: пристрій довів,
    # що кадру не має.
    RESERVE_INTERVAL = 24.hours

    # Вікно доставки: вузол виходить в ефір за енергією (до ~18 год між циклами,
    # 03_01 — SEC.15), а нову смугу показує лише аплінк ПІСЛЯ того, за яким
    # Королева вистрілила кадр. Стара смуга всередині вікна нічого не спростовує.
    DELIVERY_WINDOW = 72.hours

    # Скільки пакетів зі старою смугою після вікна дають польовий аудит: один
    # невдало вгаданий пакет не сміє коштувати виїзду.
    STALE_ALERT_PACKETS = 3

    FIELD_AUDIT_KEY = "lorenz_band_not_applied"
    RESOLUTION_KEY  = "lorenz_band_applied"

    # Заводська смуга в x100 — ті самі 200/4500, що `FW8_DEFAULT_Z_*_X100`.
    DEFAULT_PAIR = [ Tree::GLOBAL_LORENZ_Z_MIN, Tree::GLOBAL_LORENZ_Z_MAX ].map { |z| (z * 100).round }.freeze

    module_function

    def dispatch_enabled? = ENV[GATE_ENV].to_s.downcase == "true"

    # Кадр 0x9A для дерева або nil. Новий DLFC видається лише тоді, коли пристрою
    # справді є що міняти; відкрита видача перевидається тим самим кадром.
    def serve!(tree, now: Time.current)
      key = tree.hardware_key
      # Під grace їде лише 0x9E, підписаний попереднім ключем (CommandFrame).
      return nil if key.nil? || key.previous_aes_key_hex.present?
      return nil unless admissible?(tree)

      desired = OtaPackagerService.threshold_config_body(tree)
      sealed = tree.with_lock { next_issuance(tree, key, desired, now) }
      sealed && Downlink::CommandFrame.thresholds(key, **sealed)
    rescue Downlink::CommandFrame::GraceOpenError
      nil # ротацію відкрили між перевіркою і видачею — 0x9A дочекається її кінця
    end

    # Гард «лише звуження» (⚖️ 2026-09-29) поверх інваріантів прошивки
    # (`Lorenz_Thresholds_Valid`). Ширша за дефолт смуга — тихий грошовий важіль
    # (рідше аномалія → більше балів), якого DCI не бачить, бо пристрій справді нею
    # рахує; її дає лише зміна дефолту прошивки, тобто присуд, а не оверрайд.
    # Перевіряється СКЛАДЕНИЙ ланцюг: валідації родини й оверрайду кожна бачить
    # лише свою половину. Діапазон — ще й до пакування: `pack("s<")` число поза
    # int16 мовчки загортає, і обгорнуте могло б пройти перевірку тіла.
    def admissible?(tree)
      floor, ceiling = Tree::GLOBAL_LORENZ_Z_MIN, Tree::GLOBAL_LORENZ_Z_MAX
      thresholds = tree.effective_lorenz_thresholds
      if thresholds.values.all? { |value| value.between?(floor, ceiling) }
        z_min, z_max, z_opt = OtaPackagerService.threshold_config_body(tree).unpack("s<s<s<")
        return true if z_min < z_max && z_opt.between?(z_min, z_max)
      end

      Rails.logger.error "🛑 [FW.8] #{tree.did}: смуга #{thresholds} поза дефолтом пристрою " \
                         "#{floor}..#{ceiling} або невалідна після квантизації — 0x9A не видано"
      false
    end

    # Доказ із пакета. Блок каже, чи збігся вердикт смуги зі статусом пакета;
    # кандидати перераховуються під замком зі свіжого рядка, бо демон міг видати
    # нову смугу, поки пакет чекав у черзі. Пакет, що не відкинув жодного
    # кандидата, нічого не каже.
    def record_evidence!(tree, received_at:)
      outcome = tree.with_lock do
        pending = tree.lorenz_band_pending&.unpack("s<s<")
        candidates = [ DEFAULT_PAIR, *tree.lorenz_band_held, pending ].compact.uniq
        matching = candidates.select { |pair| yield(OtaPackagerService.threshold_band(*pair)) }
        next if matching.empty? || matching.size == candidates.size

        # Видача доведена, лише коли статус підтвердив ЇЇ одну: збіг разом із
        # дефолтом чи утримуваною смугою не каже, котра з них чинна.
        next promote!(tree, pending) if pending && matching == [ pending ]

        narrow!(tree, matching, pending, received_at)
      end

      resolve_field_audit!(tree) if outcome == :promoted
      escalate!(tree) if outcome == :stale && tree.lorenz_band_stale_count >= STALE_ALERT_PACKETS
    end

    # Смуга, до якої пристрій прийде без жодної нової видачі.
    def target_pair(tree)
      tree.lorenz_band_pending&.unpack("s<s<") || tree.lorenz_band_held.first || DEFAULT_PAIR
    end

    def next_issuance(tree, key, desired, now)
      return issue!(tree, key, desired, now) if desired.unpack("s<s<") != target_pair(tree)
      return nil unless tree.lorenz_band_pending && due?(tree, now)
      return issue!(tree, key, desired, now) unless same_issuance?(tree, key)

      tree.update_columns(lorenz_band_served_at: now)
      { body: tree.lorenz_band_pending, dlfc: tree.lorenz_band_dlfc }
    end

    def due?(tree, now)
      tree.lorenz_band_served_at.nil? || tree.lorenz_band_served_at <= now - RESERVE_INTERVAL
    end

    # Перевидача тим самим кадром законна, лише поки видача — останнє, що бачив
    # цей ключ: епоха ловить re-provision (DLFC знову з нуля — інакше повтор нонса
    # CCM з іншим тілом), лічильник — будь-яку пізнішу команду чи DR-підйом, після
    # яких Солдат цей DLFC уже відкине.
    def same_issuance?(tree, key)
      tree.lorenz_band_key_epoch == key.epoch && tree.lorenz_band_dlfc == key.downlink_frame_counter
    end

    # Попередня відкрита видача переходить у `held`: її кадр міг долетіти раніше
    # за новий, і тоді пристрій тримає саме її, доки не дійде наступний.
    def issue!(tree, key, body, now)
      superseded = tree.lorenz_band_pending&.unpack("s<s<")
      dlfc = key.issue_downlink_frame_counter!
      tree.update_columns(lorenz_band_held: (tree.lorenz_band_held + [ superseded ].compact).uniq,
                          lorenz_band_pending: body, lorenz_band_dlfc: dlfc, lorenz_band_key_epoch: key.epoch,
                          lorenz_band_issued_at: now, lorenz_band_served_at: now, lorenz_band_stale_count: 0)
      Rails.logger.info "[FW.8] #{tree.did}: видано смугу #{body.unpack('s<s<')} x100 (DLFC #{dlfc})"
      { body: body, dlfc: dlfc }
    end

    def promote!(tree, pending)
      tree.update_columns(lorenz_band_held: [ pending ], lorenz_band_pending: nil, lorenz_band_dlfc: nil,
                          lorenz_band_key_epoch: nil, lorenz_band_issued_at: nil, lorenz_band_served_at: nil,
                          lorenz_band_stale_count: 0)
      :promoted
    end

    # Відкинуті утримувані смуги виходять із `held` — так видно й повернення на
    # дефолт без нашого кадру (re-provision зі свіжим журналом, порвана пара ключів
    # 0x10/0x11): бажана смуга знову відрізняється від тримуваної, і найближчий poll
    # видасть її з новим DLFC. Відкрита видача, яку статус відкинув ПІСЛЯ вікна
    # доставки, — спростована: лічильник росте, а пауза перевидачі знімається.
    def narrow!(tree, matching, pending, received_at)
      changes = {}
      held = tree.lorenz_band_held & matching
      changes[:lorenz_band_held] = held if held != tree.lorenz_band_held
      stale = pending && !matching.include?(pending) &&
              received_at >= tree.lorenz_band_issued_at + DELIVERY_WINDOW
      if stale
        changes[:lorenz_band_stale_count] = tree.lorenz_band_stale_count + 1
        changes[:lorenz_band_served_at] = nil
      end
      tree.update_columns(changes) if changes.any?
      stale ? :stale : nil
    end

    # Per-tree польовий аудит: кадр не доставлено або не застосовано — вікно не
    # виключає ТРАНСПОРТУ (під OTA-кампанією 0x9A не видається, черга Королеви
    # витісняє кадри), а на вузлі це прошивка без парсера, журнал Flash-KV не
    # змонтовано чи DLFC пристрою попереду нашого. Дедуп per-tree
    # тримає сам `escalate_field_audit!`; дерево без кластера алерту не дістає —
    # його не побачив би ніхто (скіл `backend` #47), і видачі йому не буває.
    def escalate!(tree)
      return unless tree.cluster

      params = { did: tree.did, stale_packets: tree.lorenz_band_stale_count,
                 issued_at: tree.lorenz_band_issued_at.utc.iso8601 }
      EwsAlert.escalate_field_audit!(cluster: tree.cluster, tree: tree, message_key: FIELD_AUDIT_KEY, message_params: params)
    end

    # Твердження алерту — про СИГНАЛ (статус пакетів), тож машина має право його
    # зняти, щойно сигнал показав нову смугу (скіл `backend` #61). Скоуп —
    # власний ключ: чужу per-tree ескалацію доказ смуги не спростовує.
    def resolve_field_audit!(tree)
      tree.ews_alerts.status_active.alert_type_field_audit.where(message_key: FIELD_AUDIT_KEY).find_each do |alert|
        alert.resolve!(key: RESOLUTION_KEY, params: { did: tree.did })
      end
    end
    private_class_method :target_pair, :next_issuance, :due?, :same_issuance?, :issue!, :promote!, :narrow!,
                         :escalate!, :resolve_field_audit!
  end
end
