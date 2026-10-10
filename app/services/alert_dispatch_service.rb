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

  # `fw_report_id_mask` — ширина contract-id на дроті ери запису (TelemetryUnpackerService): на CCM
  # це лише залишок за модулем 128, і алерт мусить так його й назвати (FW.65).
  def self.analyze_and_trigger!(telemetry_log, fw_report_id_mask: TelemetryLog::FW_REPORT_ID_MASK)
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
    # mruby-crash/OOM/unprovisioned. Фізичного tamper-каналу на дроті сьогодні немає:
    # PANIC_FLAG з HW.30 писача не має (гілка 2б нижче лише логує).
    # Сенсорна половина кадру (temp/vcap) виміряна ДО mruby і жива —
    # термоаналіз продовжуємо, зламаний лише Лоренц-статус.
    # ⛔ Сейсмічної гілки тут НЕМАЄ: вердикт `seismic_anomaly`
    # демонтовано [ARCH.102] разом із вимірювачем — сейсмічного каналу
    # на дроті не існує (див. actuator.rb / cluster.rb).
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
    # доки телеметрія несе reverted (стан, не подія — кадр щоциклу) — як ДЕДУП
    # у `create_and_dispatch_alert!`, не як виняток. Раннього `return` тут свідомо
    # немає: стан прошивки не сміє глушити пожежну гілку нижче.
    if telemetry_log.firmware_report_reverted?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :firmware_reverted,
        message_key: "firmware_reverted",
        # «re-issue лише вищою» — а вищою за ПОВНИЙ id, який дріт CCM не несе: голий залишок
        # («2» замість 130) штовхав би оператора випустити версію, яку anti-rollback 0x15 відкине.
        message_params: { did: tree.did,
                          burned_version: TelemetryLog.contract_id_label(telemetry_log.firmware_report_contract_id,
                                                                         fw_report_id_mask) }
      )
    end

    # ⛔ [FW.50 · ARCH.99] Вердикту «втрата живлення» з поля напруги тут немає і не буде: поле —
    # мВ VDDA за buck'ом BQ25570, що за конструкцією не каже про запас енергії, а живий MCU
    # нижче ~1.8 В кадру не шле — тож гілка `voltage_mv < 100` стріляла лише на нулі відмови
    # АЦП, тобто виводила CRITICAL `power_loss` із невиміру. Сигнал «мало енергії» — тиша
    # (`Tree.silent`); поріг енергії можливий лише на живому Vcap-каналі (`00_07` FW.50).

    # 2а. ПОЖЕЖА (Thermal) — температура вище біом-порога.
    # [АДАПТИВНО]: Поріг тепер залежить від біома
    # [ARCH.102] Температури, якої не міряли (NULL panic-рядка), вогонь не судить —
    # і саме тому panic-кадр доходить до свого лог-рядка нижче.
    if telemetry_log.temperature_c && telemetry_log.temperature_c >= fire_limit
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :fire_detected,
        message_key: "fire_detected",
        message_params: { temperature_c: telemetry_log.temperature_c, fire_limit: fire_limit }
      )
      return
    end

    # 2б. PANIC-КАДР — лише лог, алерту НЕМАЄ [HW.30, ⚖️ founder 2026-09-29].
    # Єдиним писачем PANIC_FLAG був TinyML-клас пилки на пʼєзо, а пʼєзо з Солдата
    # зрізано (`02_01 §6`): кадр із прапором тепер — аномалія прошивки або підробка,
    # не свідчення про ліс. `chainsaw_detected` лишився типом без писача (`HW.52`).
    # ⛔ Гілки на `bio_status_anomaly?` теж НЕМАЄ, і це не пропуск: status 2 — вердикт,
    # виведений із Z, а E.64 такі вердикти забороняє («Z = DCI-only», блок посухи
    # нижче). Акустика лише штовхала σ, тож без звуку anomaly — чистий хаос атрактора
    # (частку задають зерно й ρ(temp), не дерево); GP на ньому й так 0 за контрактом.
    # ⛔ Гілок на `acoustic_events` не заводити: з HW.30 байт завжди 0, а сентинел
    # часу 0xFE розпакувальник нейтралізує до 0 ще до цього сервісу.
    if telemetry_log.panic?
      Rails.logger.warn "⚠️ [HW.30] #{tree.did}: panic-кадр, хоча з HW.30 у Солдата немає писача паніки — " \
                        "аномалія прошивки (або підробка); алерт не піднято."
    end

    # 4. ⛔ ПОСУХИ З ПРИСТРІЙНОГО СТАТУСУ НЕМАЄ [FW.66 (Б), `03_04 §5.3`]. Гілку
    # `bio_status_stress?` → `severe_drought` знято: у ECB-ері stress — це z < 2.0
    # атрактора, тобто статус із нашого `K_seed`, і частота його росте з МОРОЗОМ (0.022 %
    # циклів за −25 °C), а не з посухою; у CCM-ері біти статусу несуть валідність виміру,
    # не біологію. Серверну Z-гілку (`attractor_destabilised`) знято ще раніше (E.64) з
    # тієї ж причини — Z здоровʼя не міряє (`05_05 §8.1`), тож не повертати жодну.
    # `severe_drought` лишився без авто-писача, як `chainsaw_detected`: страхування,
    # dClimate і `EmergencyResponseService` чекають писача з прямих сигналів (sap/VPD,
    # `00_07` E.64). ⛔ Порожній екран означає «ніхто не міряв», НІКОЛИ «посухи немає»
    # (`00_01 §1.1`).
  end

  # Публічний метод для DCI-розбіжності з InsightGeneratorService. Окремий від
  # create_and_dispatch_alert!, бо розбіжність вимагає людської перевірки й не повинна
  # тригерити автоматичну EmergencyResponseService.
  # ⚖️ [SLASH-1, делеговано 2026-09-22] Ключ — СПОСТЕРЕЖЕННЯ, не вердикт: `05_05 §6`
  # прямо відмовляє самостійній divergence у статусі доведеного шахрайства (категорія C),
  # а ключ `fraud_telemetry_detected` друкував «ФРОД» на операторському екрані й віддавав
  # слово в API. ⛔ Legacy-ключ у локалях НЕ знімати: рендер читає `message_key` з даних
  # (`EwsAlert#message`), тож історичні рядки без нього впали б на `humanize`-фолбек —
  # тобто знову «Fraud telemetry detected». Він несе той самий чесний текст, писача не має.
  # Приймає ДАТУ, а не готовий рядок. Сигнатура «будь-який текст» була ширшою
  # за реальність (єдиний продовий викликач передавав фіксований шаблон із
  # датою) — і саме та ширина впускала прозу: сирий український рядок сідав
  # усередину локалізованої рамки, даючи «FRAUD: Виявлено фрод-телеметрію»
  # англійському глядачеві. Вузька сигнатура робить це неможливим за побудовою.
  # ⛔ [ARCH.121] Латентний інстанс того самого класу «дубль ⊥ помилка»: голий `create!`, тиша —
  # лише після створення, ключ `…:fraud` не знімає `clear_silence_filter!` (той чистить
  # `…:telemetry_divergence`), а кличуть метод усередині транзакції `InsightGeneratorService`.
  # Сьогодні інертний, бо `detect_fraud?` повертає false; повертаючи детекцію — перейди на
  # форму `create_and_dispatch_alert!` (SAVEPOINT + вузьке `:taken` + тиша й на дублі).
  def self.create_fraud_alert!(tree, target_date)
    cluster = tree.cluster
    silence_key = "ews_silence:#{tree.id}:fraud"
    return if Rails.cache.exist?(silence_key)

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: :critical,
      alert_type: :telemetry_divergence,
      message_key: "telemetry_divergence_detected", message_params: { target_date: target_date.to_s }
    )

    Rails.cache.write(silence_key, true, expires_in: 30.minutes)
    Organization.invalidate_expected_yield_cache(cluster&.organization_id)
    Rails.logger.warn "⚠️ [DCI DIVERGENCE] #{tree.did}: стан пристрою ≠ сервера за #{target_date} (сигнал, не вирок)"

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
    # ⚠️ [FW.66] Без гарда `severity == :critical`: з посухою пішов останній некритичний
    # алерт цього сервісу, тож кожен виклик тут критичний, а гілка «не критичний» стала
    # станом, якого жоден писач не створює (backend #76). Повертаючи некритичний тип —
    # поверни й гард.
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

    # 🔴 ДЕДУП ⊥ ПОМИЛКА. Тиша — лише швидкий шлях; «один активний алерт типу на вузол»
    # тримає uniqueness (`[tree_id, status]` + частковий unique-index). Кадр стану, що
    # прийшов після тиші при ще активному алерті, — дубль, не збій: доти `create!` кидав
    # тут `RecordInvalid` на КОЖНОМУ такому кадрі, а виняток виносив із розпакувальника
    # кредит уже закоміченого рядка. Форма — прецедент `EwsAlert.escalate_field_audit!`:
    # SAVEPOINT (ковтання `RecordNotUnique` не отруїть транзакцію викликача) + вузьке
    # `:taken`. Rescue обіймає лише `create!`: `RecordNotUnique` з побічних дій нижче — не дедуп.
    alert = begin
      EwsAlert.transaction(requires_new: true) do
        EwsAlert.create!(
          cluster: cluster, tree: tree, severity: severity,
          alert_type: alert_type, message_key: message_key, message_params: message_params
        )
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:alert_type, :taken)

      nil
    end

    # Встановлюємо "режим тиші" на 5 хвилин для цього типу тривоги — і на дублі теж:
    # без цього кожен наступний кадр стану знову бився б об uniqueness.
    Rails.cache.write(silence_key, true, expires_in: 5.minutes)
    if alert.nil?
      Rails.logger.info "🔕 [EWS DEDUP] #{alert_type} | #{tree.did}: активний алерт цього типу вже є — дубль не створюємо, тишу поновлено."
      return
    end

    # [ІНВАЛІДАЦІЯ КЕШУ]: Критичні аномалії мають негайно оновити прогноз Оракула,
    # щоб Dashboard не показував застарілий "оптимістичний" прогноз під час катастрофи.
    Organization.invalidate_expected_yield_cache(cluster&.organization_id)

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
