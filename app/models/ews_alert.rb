# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # [FIX]: cluster optional — дерево може бути без кластера (одиноке дерево / тестова інсталяція)
  belongs_to :cluster, optional: true
  belongs_to :tree, optional: true
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true
  # [E.20] «Хто зараз на гачку» ⊥ `resolver` («хто закрив»). Дві РІЗНІ ролі в часі:
  # доти схема вміла записати лише другу, тож питання адресата було структурно
  # невиразним — `escalate_field_audit!` мав дванадцять продюсерів і жодного
  # споживача, що призначає або виконує.
  belongs_to :assignee, class_name: "User", foreign_key: "assigned_to_id", optional: true

  # --- СТАТУСИ ТА РІВНІ ---
  # [СИНХРОНІЗОВАНО]: prefix: true гарантує виклики status_active? та status_resolved?
  enum :status, { active: 0, resolved: 1, ignored: 2 }, prefix: true
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    # ⛔ 1 і 4 ЗАРЕЗЕРВОВАНІ — не бери їх під новий тип: значення enum'а лягає в
    # колонку, тож переприсвоєння мовчки перейменує історичні рядки.
    # [SLASH-1] Відкриття корпусу / доведений tamper — ЄДИНИЙ позитивний Кат-A сигнал
    # (Slashing::CauseEvidence#positive_a? → необоротний slash). ⚠️ Автоматичного джерела
    # НАРАЗІ НЕМАЄ: wire status=3 = vm_error (софт-збій, НЕ tamper → firmware_fault нижче),
    # а справжня пилка їде panic→chainsaw_detected (поза A-сетом до field-validation).
    # Створюється лише вручну — Field-Audit C→A ескалація (console, 06_08 §4) — або
    # майбутнім validated-джерелом (chainsaw після DAO-ратифікації / HW tamper-канал).
    # Тип живий свідомо: ворота positive-A лишаються wired, чесно-порожні.
    vandalism_breach: 2,
    fire_detected: 3,     # Пожежа
    system_fault: 5,      # Поломка шлюзу/актуатора/сенсора
    # ⛔ [E.64-сиблінг, ⚖️ founder 2026-09-05] `entropy_anomaly` — ІСТОРИЧНИЙ ТИП.
    # Писача (`ClusterEntropyAnalyzerWorker` + `SilkenNet::EntropyCalculatorService` +
    # погодинний cron) ЗНЯТО ЦІЛКОМ; значення лишається ЛИШЕ щоб архівні рядки
    # рендерились — `#message` нижче є РЕНДЕРОМ, тож ключ `entropy_pre_stress` живий
    # у чотирьох локалях із тієї ж підстави, а не як запрошення.
    #
    # ⛔ НЕ БРАТИ його під новий кластерний детектор і не відроджувати механізм.
    # Він рахував ентропію Шеннона по Z-розподілу кластера й стверджував: «здоровий
    # ліс дає різноманітні Z, лісовий стрес їх гомогенізує». ВИМІРЯНО ПРОДОВИМИ
    # КЛАСАМИ (`SeedDerivation.initial_state` → `Attractor.calculate_z_from_state` →
    # `EntropyCalculatorService`; N=200 дерев, R=500 повторів):
    #   · ліс із НУЛЬОВОЮ біологічною різницею (ідентичні temp/acoustic, різні
    #     `K_seed`) дає H = 0.9077 ± 0.0106, 0/500 нижче порога 0.65 — тобто
    #     канонічна «здорова смуга 0.75–0.95» відтворюється самим лише КРИПТОШУМОМ
    #     ЗЕРЕН, які ми ж і призначили. Детектор міряв нас, не ліс;
    #   · канонічний синхронізований стрес (38 °C на всіх) дає H = 0.7004 ± 0.0312 і
    #     перетинає поріг лише у 5.8 % — промах у 94 % НА ВЛАСНОМУ сценарії; а те
    #     падіння, що є, іде через ρ(temp), тобто це `temperature_c`, вже наявна
    #     ПРЯМИМ стовпцем, перерахована через 250 ітерацій Лоренца й біни Шеннона
    #     (data-processing inequality — той самий присуд, що `05_05 §8.1`);
    #   · звичайна нестресова мікрокліматична різниця фальш-тригерить у 1.8 %;
    #   · саме лише тепле продовження траєкторії (48 циклів) зсуває базову лінію на
    #     −0.033 без ЖОДНОЇ зміни світу — поріг неявно припускав невідому
    #     «розігрітість» популяції, тобто був неоголошеним вільним параметром.
    # ⚠️ Запасний ужиток теж ВИМІРЯНО й ВІДКИНУТО: як детектор дубльованих зерен
    # ловить повну колізію в 29 % (розкид H 0.066–0.927), часткову — 0/500; а причину
    # й так стереже прямий UID/DID-гард на прошиванні (`03_06 §5`).
    #
    # 🔑 ЦІНА НАЗВАНА ВГОЛОС: кластерного передстресового сигналу БІЛЬШЕ НЕМАЄ —
    # ні алерту, ні gauge, ні панелі Grafana. Порожньо тут означає «ніхто не міряв»,
    # НІКОЛИ «стресу немає» (`00_01 §1.1` — тиша, оголошена процвітанням). Свідчення
    # не втрачено: `z_value` лежить у телеметрії й у Merkle-листі, тож будь-яку
    # кластерну статистику можна перерахувати по всій історії.
    # ⛔ Новий кластерний передстресовий детектор заводь ВЛАСНИМ типом і лише на
    # ПРЯМОМУ вимірі (sap-flow / VPD / ґрунтова волога — `00_07` E.64), ніколи на
    # похідній від Z: Z є DCI-печаткою, і вердикту про здоровʼя з неї не виводять.
    entropy_anomaly: 6,   # ⛔ ІСТОРИЧНИЙ — писача знято 2026-09-05, див. блок ↑
    # [SLASH-1] Аудит на місці — причина невизначена: дерево замовкло (no-data blackout),
    # freeze без прямого доказу Категорії A, або страховий кандидат чекає незалежного
    # підтвердження. Свідомо ОКРЕМИЙ від system_fault (поломка заліза/зв'язку), щоб дедуп не
    # конфлатив сигнали і freeze-алерт не накручував penalty_factor через comms_no_ack? (gap-D).
    # «Тиша замовклого дерева — теж його голос» — ескалюємо слухати, не караємо наосліп.
    field_audit: 7,
    # [ARCH.54 Шар 0] Rails сам помітив тишу шлюзу (dead-man switch,
    # GatewayStalenessSweepWorker): last_seen_at прострочив sleep-інтервал з
    # люфтом → кластер осліп, permanence-моніторинг NaaS провис. ОКРЕМИЙ від
    # system_fault (там Королева ДОПОВІЛА про свій збій; тут вона МОВЧИТЬ —
    # протилежні сигнали для тріажу лісника).
    queen_offline: 8,
    # [ARCH.34 Шар 2] Королева САМА кричить через Helium LoRaWAN, що втратила
    # всі власні uplink'и (Starlink/LTE + Q2Q) — телеметрія буферизується у
    # Flash-ринг, потрібна ескалація (виїзд). Дзеркальний до queen_offline:
    # там мовчання, тут — крик через чужі hotspot'и (06_08 §1.2 L3).
    queen_uplink_lost: 9,
    # [SLASH-1] Акустична аномалія БЕЗ термального сигналу (TinyML chainsaw/cavitation
    # → StatusByte anomaly при нормальній температурі) — вирубка, не вогонь. До спліту
    # жила у fire_detected → FIRMS бачив «ясне небо» → жертву вирубки таврував
    # rejected_fraud; тепер non-fire маршрут → Field-Audit (перевірити пеньки).
    # ⚠️ НЕ в A-сет slash'а до field-validation TinyML (клас = synthetic placeholder,
    # 03_03 §4.2) — DAO-ратифікація, Slashing::CauseEvidence лишається tamper-only.
    chainsaw_detected: 10,
    # [SLASH-1] Софт-збій прошивки пристрою: wire status=3 (BIO_STATUS_VM_ERROR —
    # mruby-crash / VM-OOM / unprovisioned). Vendor-attributable, ops-тріаж (re-flash /
    # OTA), НЕ біо-сигнал і НЕ вина оператора: не в A-сеті (vandalism_breach ↑), не в
    # comms_no_ack? whitelist (вузол ЖИВИЙ — радіо працює, зламаний лише mruby) і
    # виключений з critical_unmaintained? — не карати оператора за наш баг.
    firmware_fault: 11,
    # [SEC.20] Auto-fallback стався: вузол стер биту OTA-версію і біжить embedded
    # baseline (wire fw-report: reverted-біт). ОКРЕМИЙ від firmware_fault —
    # той транзієнтний (vm_error щоцикл, гасне сам), цей ТЕРМІНАЛЬНИЙ: вихід
    # лише через re-issue OTA з версією СТРОГО вищою за спалену (anti-rollback
    # приплив 0x15 не воскрешає стару — 03_06 §4 bump-інваріант). Різні
    # ops-дії = різні типи. Slash-виключення дзеркалять firmware_fault:
    # vendor-attributable, не A-сет, не comms_no_ack?, не critical_unmaintained?.
    firmware_reverted: 12,
    # [SEC.21] Спрацювала стек-канарка (__stack_chk_fail → reset → 0x57):
    # переписаний кадр стека на attacker-reachable парсері = потенційна
    # СПРОБА експлойту, але НЕ фізичний tamper корпусу → НЕ A-сет (доказ
    # не positive-A), не comms (вузол живий), не critical_unmaintained?
    # (виїзд не лікує софт-атаку; тріаж = security-ревізія + Field-Audit
    # ескалація вручну). Trust L0-observational (ECB без MIC) — подія
    # ніколи не рухає money-path.
    firmware_canary_trip: 13,
    # [ARCH.58] Rails загубив слід власної команди: актуатор числиться active
    # довше за вікно своєї найновішої команди (втрачена scheduled-джоба Reset,
    # крах між комітом видачі та плануванням, вичерпані ретраї). Носій СВІДОМО
    # новий, бо обидва «очевидні» кандидати отруєні: `system_fault` сидить у
    # whitelist `comms_no_ack?` І поза виключеннями `critical_unmaintained?`
    # (при активації cause-uplift дав би ПОДВІЙНИЙ штраф оператору за наш баг),
    # а cluster-level `field_audit` входить у `dark_cluster_ids` і осліпив би
    # per-tree dead-man switch на весь кластер (06_08 §1.3). Класифікація —
    # дзеркало firmware_fault: vendor-attributable, не A-сет, не comms_no_ack?
    # (радіо живе), виключений з critical_unmaintained?. Машинного resolve НЕМА
    # свідомо: фізичний стан пристрою нам невідомий, тож закрити алерт може
    # лише людина, що подивилась на залізо.
    actuator_stuck: 14,
    # [ARCH.75] Аварійна фізична відповідь НЕ БУЛА ВІДПРАВЛЕНА, бо доїхати не може:
    # або протокол просить тривалість понад фізичну стелю актуатора
    # (`Actuator#can_sustain?`), або каденс опитування шлюза довший за вікно
    # релевантності відповіді (`Downlink::PendingQueueService.reachable_within?` —
    # каденс береться з константи-дзеркала прошивки, не з конфіг-колонки шлюза).
    # Це ЄДИНИЙ алерт, який
    # свідчить про НЕ-дію: команд не створено взагалі — раніше на їх місці лягали
    # невалідні рядки, що не вміли навіть померти, і мовчали.
    # Носій СВІДОМО новий, а не `system_fault` — з тієї ж причини, що в
    # `actuator_stuck` вище, і ціна помилки тут та сама: `system_fault` сидить у
    # whitelist `comms_no_ack?` І поза виключеннями `critical_unmaintained?`
    # (`BlockchainBurningService`), тож на день активації cause-uplift оператор
    # дістав би ПОДВІЙНИЙ штраф за конфігурацію, яку задали МИ. Класифікація —
    # дзеркало `actuator_stuck`: vendor-attributable, не A-сет, не `comms_no_ack?`
    # (радіо живе), виключений з `critical_unmaintained?`. Машинного resolve НЕМА:
    # закрити може лише зміна конфігурації (стеля пристрою / каденс шлюза) або
    # присуд, що така відповідь на цьому залізі неможлива.
    emergency_response_undeliverable: 15,
    # [SLASH-1 ⚖️ 2026-09-04] НАШ slash не доїхав on-chain (RPC-збій; `ambiguous`
    # = міг піти в мемпул). Носій СВІДОМО новий, і підстава тут ГОСТРІША, ніж в
    # actuator_stuck/emergency_response_undeliverable вище: доти ця подія їхала
    # `system_fault`, тобто типом, що сидить у whitelist `comms_no_ack?` І поза
    # виключеннями `critical_unmaintained?` — отже провал НАШОГО спалення
    # створював алерт, який на наступному проході садив `penalty_factor`
    # оператора рівно на стелю (1.0 + 0.5 + 0.5 = PENALTY_FACTOR_MAX). Це той
    # самий self-ref, який уже лікували для `vandalism_breach` [P1-3], тільки
    # винуватцем була платформа. Класифікація — дзеркало `actuator_stuck`:
    # vendor-attributable (збій НАШ), не A-сет, не `comms_no_ack?` (whitelist —
    # новий тип не входить сам), виключений з `critical_unmaintained?`.
    # Машинного resolve НЕМА: закрити може лише людина, що звірила експлорер
    # (для `ambiguous` це прямий припис — 06_08 §4).
    slash_dispatch_failed: 16,

    # [SLASH-1, 2026-09-04] КЛАС «збій каналу, не приписуваний операторові» —
    # сьогодні два ключі: деградований uplink (лічильник провалених flush-розмов)
    # і слабкий CSQ. Ім'я КЛАСОВЕ навмисно: перша редакція назвала тип за ПОДІЄЮ
    # (`gateway_uplink_degraded`), і щойно до нього долучився другий ключ, ім'я
    # стало вужчим за зміст — та сама вада, за яку `fraud_*` не пішло в тип 19.
    # Вирізано з кошика
    # `system_fault`, і підстава ТУТ НОВА порівняно з трьома попередніми
    # виносами (`actuator_stuck` · `emergency_response_undeliverable` ·
    # `slash_dispatch_failed`). Ті троє вирізали тому, що винуватцем була
    # ПЛАТФОРМА. Цей — тому, що винуватця встановити НЕМОЖЛИВО: пускач є
    # сатурований лічильник провалених flush-розмов Королеви (`coap_fail`,
    # `queen_attest.h`), а він за побудовою не розрізняє, чий бік упав —
    # наш CoAP-ендпоінт чи бекхол оператора. Отже дискримінатор «ХТО
    # ПОРОДИВ подію» має третю відповідь — НЕВІДОМО, — і при незворотному
    # `slash()` вона падає на той самий бік, що й «ми»: асиметрія 05_05 §3.2
    # (`Cat-C default = freeze`) забороняє карати за невизначеність.
    # ⚠️ Доти ключ їхав як `system_fault` і годував ОБИДВА предикати одразу
    # (1.0 + 0.5 + 0.5 = PENALTY_FACTOR_MAX) — той самий подвійний штраф, що
    # тричі лікували поштучно. Виключений із `critical_unmaintained?`; у
    # ⚠️ Але в whitelist `comms_no_ack?` він ЛИШАЄТЬСЯ — поправка 2026-09-04:
    # той предикат цінує непідтвердженість СИГНАЛУ ЗВʼЯЗКУ, а не провину, тож
    # аргумент атрибуції до нього не застосовний (доводив би забагато — сусід
    # `queen_uplink_lost` так само не каже, чий бік упав). Знімається РІВНО
    # ОДИН терм: дефектом канон називає подвійний заряд, не присутність.
    comms_fault: 17,

    # [SLASH-1 2026-09-04] ⚖️ ФОРМА решти розколу: один тип на КЛАС АТРИБУЦІЇ,
    # а не на подію. `message_key` лишається носієм ПОДІЇ (перегрів ⊥ промерзання
    # ⊥ втрата живлення ⊥ відмова актуатора), `alert_type` несе те, що читають
    # предикати — ХТО ПОРОДИВ. Тип-на-ключ дав би стільки ж дискримінації за
    # більшу ціну, тож обрано родину. Сюди входять залізні відмови, чиє джерело
    # НАШЕ (енергетика вузла, корпус, актуатор) або невизначене (перегрів може
    # бути й вибором місця монтажу) — обидва боки за асиметрією 05_05 §3.2
    # падають однаково: не карати. Дзеркало `firmware_fault` на залізній осі.
    # ⚠️ `hardware_decay` (DeviceCalibration) свідомо ЛИШЕНО в `system_fault`:
    # він `medium`, тобто поза периметром за severity, і переносити його зараз
    # означало б чіпати модель без потреби — але заводячи йому critical-писача,
    # переносити ОБОВʼЯЗКОВО.
    hardware_fault: 18,

    # [SLASH-1 2026-09-04] DCI-розбіжність device-Z ⊥ server-Z. Вирізано з кошика
    # `system_fault`, і підставу дав САМ КАНОН, не новий аналіз: 05_05 §6 називає
    # дві причини divergence — whole-block replay (атакер) і розбіжність версій
    # прошивки після OTA (НАША) — і виносить вердикт «самостійна divergence →
    # категорія C (заморозка + peer-review), а НЕ автоматичний burn».
    # 🔴 Отже сигнал, оголошений НЕДОСТАТНІМ для спалення, роздував МНОЖНИК того
    # самого спалення — і то через ОБИДВА предикати: у whitelist `comms_no_ack?`
    # він потрапляв через спільний тип, хоча сигналом зв'язку не є ЗОВСІМ (це
    # трекер називав місяцями), а в `critical_unmaintained?` входив за
    # замовчуванням, хоча виїзд лісника DCI-розбіжності не лікує — лік є
    # розслідуванням, як у `firmware_fault`.
    # ⚠️ Ім'я ТИПУ навмисно описує СПОСТЕРЕЖЕННЯ, а не вердикт: канон відмовляє
    # divergence у статусі доведеного шахрайства, тож `fraud_*` у типі стверджував
    # би те, що §6 заперечує. `message_key` лишено як є — він клієнт-видимий і
    # його правка є окремим питанням (⊂ той самий клас, що підпис форфейтури).
    telemetry_divergence: 19
  }, prefix: true

  # [SLASH-1 2026-09-04] ОПЕРАЦІЙНА родина «шлюз потребує уваги» — One-Home, бо
  # кошик `system_fault` розколюється за АТРИБУЦІЄЮ і далі (05_05 §6), а читачі
  # цієї осі про атрибуцію нічого не знають. 🔴 Підстава заведена ЗНАХІДКОЮ, не
  # наперед: перший же розкол тихо звузив `Gateway#system_fault?`,
  # який питає зовсім інше — «чи їхати патрульному». Один токен, два домени:
  # предикати `penalty_factor` розводять події за ТИМ, ХТО ЇХ ПОРОДИВ, а ops-вісь
  # — за тим, чи вони видимі. Розколюючи тип далі, додай його СЮДИ тим самим комітом.
  # ⚠️ Виміряно того ж дня: у `Gateway#system_fault?` нуль викликачів поза власною
  # спекою, тож звуження живого ефекту не мало — доля самого предиката (зняти чи
  # дротувати) лишається окремим питанням, і ця константа її не вирішує.
  GATEWAY_FAULT_TYPES = %i[system_fault comms_fault hardware_fault].freeze

  # [COSMIC EYE]: Статус супутникової верифікації через dClimate.
  # Подвійний консенсус для запобігання страховому шахрайству.
  enum :satellite_status, {
    unverified: 0,      # Очікує перевірки супутником
    verified: 1,        # Підтверджено супутником (fire_confirmed)
    rejected_fraud: 2,  # Відхилено — ясне небо, без пожежі (slashing)
    inconclusive: 3     # Хмарність/кронопокрив — потрібен DAO-аудит
  }, prefix: :satellite

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРИВОГИ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :resolved
    state :ignored

    event :mark_resolved do
      transitions from: :active, to: :resolved
    end

    event :ignore do
      transitions from: :active, to: :ignored
    end

    event :reopen do
      transitions from: [ :resolved, :ignored ], to: :active
    end
  end

  # --- ВАЛІДАЦІЇ ---
  # `message_key`, а не `message`: після зняття колонки `message` — це рендер,
  # тож валідація на ньому гнала б I18n-лукап на кожен save заради того самого
  # висновку. Несе присутність саме ключ.
  validates :severity, :alert_type, :message_key, presence: true

  # [STORM PROTECTION]: Захист від каскадних дублікатів.
  # Якщо один кластер накриває задимлення, сотні дерев згенерують fire_detected.
  # Ця валідація гарантує лише одну активну тривогу на [tree_id, alert_type].
  # Підкріплено частковим унікальним індексом на рівні БД (див. міграцію).
  validates :alert_type,
            uniqueness: { scope: [ :tree_id, :status ], message: "вже є активним для цього вузла" },
            if: -> { tree_id.present? && status_active? }

  # --- ПРОЗА АЛЕРТА: ключ + параметри, рендер у момент ПОКАЗУ ---
  # Алерти народжуються у воркерах, де локалі глядача не існує. Готовий рядок,
  # записаний там, замерзав однією мовою назавжди. Тому в БД лежить те, що від
  # мови НЕ залежить: який інцидент (`message_key`) і які числа виміряно
  # (`message_params`), а фраза збирається щоразу під того, хто дивиться.
  MESSAGE_SCOPE = "alerts.messages"

  # [I18N.1] Сирий enum усередині перекладеної фрази лікується не міткою в БД
  # (заморозила б локаль продюсера), а конверсією на межі показу: параметр несе
  # ВИМІР, мітку збирає читач у локалі глядача (присуд 2026-08-20). Новий
  # named-параметр із label-домом додається сюди рядком.
  PARAM_LABEL_RESOLVERS = {
    token_type: ->(value) { BlockchainTransaction.token_type_label(value) }
  }.freeze

  # Перевизначення читача, а не окремий метод — щоб УСІ наявні читачі
  # (`Alerts::Row`, мейлер, `TextFormatter`, API) дістали локалізацію без
  # правок, і щоб `validates :message, presence: true` вище працювала для
  # обох шляхів сама: вона читає саме цей метод, а не колонку.
  #
  # ⛔ [E.64 ⚖️ 2026-09-05] `alerts.messages.attractor_destabilised` — ключ БЕЗ
  # живого писача, і його НЕ МОЖНА видаляти. Серверну Z-гілку знято, тож нових
  # рядків із цим `message_key` не зʼявиться — але історичні продові рядки
  # рендеряться САМЕ тут, і без ключа втратять текст назавжди (рендер ⊥ колонка).
  # 🔴 Носій стоїть у Ruby СВІДОМО: `i18n-tasks normalize` зʼїдає коментарі з YAML
  # (виміряно — заборона, вписана в чотири локалі, зникла з першим же прогоном),
  # а `i18n-tasks unused` тепер числить цей ключ мертвим і віддасть його
  # `remove-unused`. ⛔ **Те саме, і вже НЕ в майбутньому часі, для
  # `alerts.messages.entropy_pre_stress`:** його писача (`ClusterEntropyAnalyzerWorker`)
  # знято 2026-09-05 разом з усім трактом `entropy_anomaly`, тож обидва ключі тепер
  # в ОДНАКОВОМУ стані — живі в чотирьох локалях, мертві в очах `i18n-tasks`,
  # незамінні для архівних рядків. Заборона на видалення накриває обидва.
  # **Ключ рендера переживає свій механізм — це не борг, а память.**
  def message
    return nil if message_key.blank?

    I18n.t(
      "#{MESSAGE_SCOPE}.#{message_key}",
      **resolve_param_labels(message_params.to_h.symbolize_keys),
      default: message_key.to_s.humanize
    )
  end

  # Троттлінг WebSocket-трансляцій: не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" повідомлень при масових інцидентах.
  # --- КОЛБЕКИ (Zero-Lag Awareness) ---
  # [INF.26] Лічильник створених тривог — ОДИН дім на застосунок, а не один із 25
  # сайтів створення. Доти інкремент стояв у `DclimateVerificationWorker` ще й під
  # `if result`, тобто «Total EWS alerts» рахував лише ту підмножину, що пройшла
  # супутникову верифікацію — недолік на порядок під іменем «total».
  # ⚠️ Колбек, а не `after_create`: рахуємо те, що справді осіло в БД (rollback не
  # має інкрементувати), тим самим правилом, що й сусіди нижче.
  after_create_commit :count_created_alert

  # Сакральна асинхронність: сповіщення летять лише після COMMIT
  after_create_commit :dispatch_notifications!

  # [COSMIC EYE]: Запуск супутникової верифікації через dClimate
  after_create_commit :schedule_satellite_verification!

  # Real-time: новий алерт з'являється у стрічці кластера миттєво
  after_create_commit :broadcast_new_alert

  # Real-time broadcast: оновлюємо дашборди всіх операторів при будь-яких змінах алерту
  after_update_commit :broadcast_alert_update

  # [INF.26] Термінальний супутниковий вердикт → лічильник. Окреме імʼя, як і в
  # сусідів нижче: два `after_*_commit` з одним filter'ом злипаються в один
  # недосяжний колбек (див. блок вище).
  after_update_commit :count_satellite_verdict

  # 🔴 [UI.11] Бейдж «Threat Alerts» кешується на хвилину, і TTL там був ПРОКСІ
  # для «щось змінилось» — тимчасом момент зміни ми знаємо ТОЧНО: створення
  # алерту й перехід у `resolved`. Присуд власника 2026-08-14 — гасити кеш на
  # ЗАПИСІ, не за часом: бейдж стає точним, а кількість COUNT-запитів НЕ росте
  # (кеш живе рівно доки число чинне, а не фіксовані 60 с).
  #
  # ⚠️ Класична пастка «механізм ⊥ його пускач»: пускач у нас БУВ, а ми
  # полінгували. Звуження TTL до 5 с дало б у 12 разів більше запитів і все одно
  # лишалось би полінгом, тобто наближенням замість факту.
  #
  # `after_commit`, не `after_save`: гасити кеш до COMMIT означало б вікно, у
  # якому наступний рендер прогріє його СТАРИМ числом із незавершеної транзакції.
  #
  # 🔴 **Імена методів РІЗНІ навмисно, і це не стиль.** Перша редакція мала
  # `after_create_commit :bust…` + `after_update_commit :bust…` — ОДИН і той
  # самий метод двічі. Rails дедуплікує колбеки за парою (kind, filter), тож
  # замість двох записів лишається ОДИН, а умови обох ЗЛИВАЮТЬСЯ через AND:
  # гард вимагає бути водночас `on: :create` і `on: :update`, тобто недосяжний.
  # Колбек не спрацьовує ЖОДНОГО разу, і ніщо про це не попереджає —
  # `_commit_callbacks` показує його присутнім. Виміряно пробою: після `create`
  # значення в кеші лишалось попереднім.
  after_commit :bust_org_alert_count_cache, on: :create
  after_commit :bust_alert_count_on_status_change, on: :update

  # --- СКОУПИ ---
  scope :unresolved, -> { status_active }
  scope :critical, -> { severity_critical.unresolved }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # [ARCH.110] РЕЄСТР причин cluster-level Field-Audit, розділений ОДНИМ питанням:
  # чи цей алерт СТВЕРДЖУЄ, що кластера не чути.
  #
  # Дискримінатор несе `message_key`, а не власний `alert_type` (⚖️ 2026-08-25):
  # причини вже розрізнені ключем у КОЖНОГО продюсера, тоді як новий `critical`-тип
  # за замовчуванням увійшов би в `critical_unmaintained?` і штрафував би оператора
  # за нашу ж діагностику ([`05_05 §3.2`]).
  #
  # 🔴 Реєстр мусить лишатись ПОВНИМ: `TreeStalenessSweepWorker#dark_cluster_ids`
  # глушить per-tree dead-man switch саме за `SILENCE_ASSERTING_KEYS`, тож новий
  # некласифікований ключ тихо випав би з обох списків — і зламав би глушник у той
  # бік, якого ніхто не помітить. Повноту стереже
  # `spec/quality/cluster_field_audit_key_registry_spec.rb`.
  #
  # ⚠️ `insurance_no_data` живе САМЕ ТУТ, хоч ім'я й читається як страховий вердикт:
  # його єдиний пускач — `router.blackout?` (`активні дерева є && інсайтів немає`),
  # тобто він стверджує рівно нечутність. Класифікувати за іменем ключа — помилка.
  SILENCE_ASSERTING_KEYS = %w[
    cluster_data_blackout
    global_blackout
    insurance_no_data
  ].freeze

  # Вердикт утримано або зовнішня перешкода — про чутність кластера НЕ кажуть нічого,
  # тож глушити ними dead-man switch означало б гасити тишу грішми.
  VERDICT_HELD_KEYS = %w[
    cluster_small_sample_degradation
    slash_frozen_indeterminate_cluster
    slash_frozen_no_evidence_cluster
    slash_evasion_cluster
    insurance_candidate_armed
    obscured_critical_fire
    non_fire_peril
  ].freeze

  CLUSTER_FIELD_AUDIT_KEYS = (SILENCE_ASSERTING_KEYS + VERDICT_HELD_KEYS).freeze

  # [SLASH-1] One-Home Field-Audit ескалації, два скоупи за dedup-ключем:
  #   • cluster-level (tree: nil) — (cluster_id, :field_audit, :active, tree_id NULL,
  #     message_key): щоденні crons при тривалій деградації плодили дубль щодоби —
  #     той самий продюсер дедуплікується власним ключем і далі. 🔴 [ARCH.110]
  #     `message_key` у ключі СВІДОМО: без нього продюсер, що прийшов другим,
  #     діставав `nil`, а виклик-сайти на `nil` не реагують за побудовою — тобто
  #     після slash-freeze справжній blackout не був би записаний НІДЕ. Це
  #     протилежні за змістом вироки з різними діями людини.
  #   • per-tree ([SILENCE-1], tree: задано) — dedup тримають модельна валідація
  #     (scope [tree_id, status]) + частковий unique-index (..._unique_active_per_tree);
  #     індекси взаємовиключні (tree_id IS NULL ⊥ IS NOT NULL) → скоупи співіснують:
  #     cluster-blackout і per-tree тиша — різні сигнали, не дедупляться між собою.
  # Resolve відкриває наступну. Race-safety = часткові unique-index'и.
  # Повертає алерт або nil (dedup-skip) — виклик-сайти на nil НЕ реагують
  # (аудит-виїзд спільний, контекст лишається у їхніх логах).
  def self.escalate_field_audit!(cluster:, message_key:, message_params: {}, tree: nil)
    existing = tree ? active_tree_field_audit_for(tree) : active_cluster_field_audit_for(cluster, message_key)
    if existing
      Rails.logger.info "🔍 [SLASH-1] Field-Audit по #{tree ? "дереву #{tree.did}" : "кластеру ##{cluster.id}"} вже активний (##{existing.id}) — дубль не створюємо."
      return nil
    end

    # SAVEPOINT обов'язковий: викликач може тримати ВІДКРИТУ транзакцію
    # (ParametricInsurance#arm_candidate! — trigger! + ескалація атомарно). Без
    # requires_new програна unique-гонка отруює зовнішню транзакцію на рівні PG —
    # Ruby-rescue її не лікує, імпліцитний COMMIT тихо стає ROLLBACK і trigger!
    # зникає без жодного ексепшена.
    transaction(requires_new: true) do
      create!(cluster: cluster, tree: tree, severity: :critical, alert_type: :field_audit,
              message_key: message_key, message_params: message_params)
    end
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "🔍 [SLASH-1] Field-Audit dedup-гонку по #{tree ? "дереву #{tree.did}" : "кластеру ##{cluster.id}"} програно — активна ескалація вже існує."
    nil
  rescue ActiveRecord::RecordInvalid => e
    # [SILENCE-1] Другий гоночний шлях tree-гілки: дубль ЗАКОМІТИВСЯ між pre-check'ом
    # і create! → його ловить модельна uniqueness-валідація (RecordInvalid, не index).
    # Cluster-гілка цього шляху не має (валідація скоуплена tree_id.present?). Ловимо
    # ВУЗЬКО (лише :taken) — інший invalid = справжній баг, летить гучно.
    raise unless tree && e.record.errors.of_kind?(:alert_type, :taken)

    Rails.logger.info "🔍 [SLASH-1] Field-Audit dedup-гонку по дереву #{tree.did} програно (модельна валідація) — активна ескалація вже існує."
    nil
  end

  # Виокремлено з escalate_field_audit! (тестований шов гонки: спек стабить nil
  # при реальному дублі в БД → форсує RecordNotUnique з індексу).
  def self.active_cluster_field_audit_for(cluster, message_key)
    cluster.ews_alerts.critical.alert_type_field_audit
           .where(tree_id: nil, message_key: message_key).first
  end

  # [SILENCE-1] Per-tree дзеркало ↑. Предикат = ТОЧНО модельна валідація
  # (status_active, БЕЗ severity-фільтра) — щоб create! ніколи не бився об
  # uniqueness-валідацію повз RecordNotUnique-rescue.
  def self.active_tree_field_audit_for(tree)
    tree.ews_alerts.status_active.alert_type_field_audit.first
  end

  # =========================================================================
  # МЕТОДИ (The Lens of Truth)
  # =========================================================================

  # [I18N.1] Дім ключів resolution-записів — той самий принцип, що `message_key`:
  # у БД лежить КЛЮЧ + скалярні параметри, фраза збирається в момент показу
  # локаллю ГЛЯДАЧА. Людська нотатка резолвера — виняток за родом: це вільний
  # текст його мовою, він не локалізується жодною схемою і їде як `"text"`.
  RESOLUTION_SCOPE = "alerts.resolutions"

  # [E.20] Конфлікт претензії й спроба відпустити чуже — це РІЗНІ відповіді
  # (409 ⊥ 403), тож і винятки різні. Форма взята з сусіда `resolve!`: модель
  # КИДАЄ, контролер перекладає в код — там це вже врятувало від JSON-500 на
  # повторному кліку.
  class AlreadyAssigned < StandardError; end
  class NotAssignee < StandardError; end
  class AlertClosed < StandardError; end

  # Узяти тривогу на себе. Претензія ЛИШЕ на нічию: перехоплення чужої — це
  # диспетчерська дія, і вона свідомо не будується (residual `00_07` E.20).
  #
  # 🔴 Повтор ВЛАСНОЇ претензії — no-op, і це не косметика: `update!` тут скинув
  # би `assigned_at`, тобто ЗАМІРЯНИЙ час приєднання, заради якого колонка й
  # заводилась (Кат-A-сигнал `05_05 §2` «неприєднання Forester'а до інциденту в
  # SLA»). Другий клік по кнопці мовчки покращував би власний SLA.
  def claim!(user)
    return true if assigned_to_id == user.id
    raise AlreadyAssigned if assigned_to_id.present?
    # Гард стану живе ТУТ, а не лише в кнопці: інакше API дозволяв би «взяти»
    # вже закриту тривогу, і `assigned_at` фіксував би приєднання ПІСЛЯ
    # резолюції — тобто отруював саме ту метрику, заради якої колонка є.
    raise AlertClosed unless status_active?

    update!(assigned_to_id: user.id, assigned_at: Time.current)
  end

  # Відпустити. Право має сам виконавець АБО admin+ — інакше один хибний клік
  # замикав би тривогу на людині назавжди, тобто ми створили б стан без виходу
  # (той самий клас, що «призначений орган без адресата», проти якого пункт і
  # заведено).
  def release!(user)
    raise NotAssignee unless assigned_to_id == user.id || user.admin_or_above?

    update!(assigned_to_id: nil, assigned_at: nil)
  end

  # Протокол завершення інциденту.
  #
  # [I18N.1] `notes:` = вільний текст ЛЮДИНИ (з форми); машинні викликачі дають
  # `key:`/`params:`. Без обох — дефолтний ключ, і він деривується від наявності
  # резолвера: доти "Закрито системою" (укр. проза в БД) діставав і оператор,
  # що лишив поле порожнім, — тобто дефолт брехав про АГЕНТА закриття.
  def resolve!(user: nil, notes: nil, key: nil, params: {})
    # Знімаємо "режим тиші", щоб Оракул знову міг слухати це дерево після його
    # відновлення. ⚠️ Стор тут — `Rails.cache`, тобто Solid Cache (PostgreSQL) у
    # проді, НЕ Redis: заголовок цього коментаря казав інакше й посилав читача
    # шукати ключ не там.
    clear_silence_filter!

    self.resolved_at = Time.current
    self.resolver = user
    log_resolution(key: key || (user ? "operator_closed" : "system_closed"),
                   params: params, text: notes)

    # AASM state transition з валідацією (only from :active)
    mark_resolved!

    # [SELF-HEALING]: Атомарно закриваємо MaintenanceRecord
    close_associated_maintenance!

    true
  end

  # Додає запис у `resolution_log` (НЕ зберігає — викликач сам робить save/update!,
  # як обидва dclimate-appendери, що пишуть його разом із `satellite_status`).
  # Час — поле САМОГО запису, тож `[iso8601]`-префікси в прозі більше не потрібні.
  def log_resolution(key: nil, params: {}, text: nil)
    entry = { "at" => Time.current.utc.iso8601 }
    if text.present?
      entry["text"] = text
    else
      entry["key"] = key.to_s
      entry["params"] = params.stringify_keys if params.present?
    end
    self.resolution_log = Array(resolution_log) + [ entry ]
  end

  # Рендер для читачів (хроніка, майбутній UI): text-записи як є, key-записи —
  # локаллю глядача, fail-open на `humanize` (той самий контракт, що `#message`).
  def resolution_texts
    Array(resolution_log).map do |entry|
      entry["text"].presence ||
        I18n.t("#{RESOLUTION_SCOPE}.#{entry["key"]}",
               **resolve_param_labels((entry["params"] || {}).symbolize_keys),
               default: entry["key"].to_s.humanize)
    end
  end

  # [ВИПРАВЛЕНО]: Навігація в тумані.
  # Якщо дерево втратило GPS, ми фокусуємо патруль на центрі сили кластера.
  # nil-safe: cluster — optional (одиноке дерево / тестова інсталяція). Без
  # `cluster&.geo_center` друга гілка крашне NoMethodError при cluster == nil.
  def coordinates
    if tree&.latitude.present? && tree.longitude.present?
      [ tree.latitude, tree.longitude ]
    elsif (center = cluster&.geo_center)
      [ center[:lat], center[:lng] ]
    end
    # 🔴 [ARCH.82] `nil`, а не `[0.0, 0.0]`. Нульова точка стояла тут «щоб не
    # ламати Leaflet.js», але це не відсутність координати — це ВИГАДАНА
    # географія: (0,0) — Гвінейська затока. Обидва джерела законно порожні
    # (`trees.latitude`/`longitude` nullable — тому й існує скоуп `geolocated`;
    # `geo_center` деривується з опційного полігона), тож стан досяжний.
    #
    # Ціна була не косметична: єдиний споживач — `Dclimate::VerificationService`
    # — годує ці координати у ЗАПИТ ПРО ПОЖЕЖУ, а його вердикт лягає на алерт
    # як `satellite_status`, тобто як ДОКАЗ. Супутниковий вирок про іншу
    # півкулю гірший за відмову верифікувати. Клас — `ARCH.84`: значення, що
    # зʼявляється ЗАМІСТЬ виміру.
  end

  # Чи потребує цей інцидент негайного втручання актуаторів?
  def actionable?
    severity_critical? && (alert_type_fire_detected? || alert_type_severe_drought?)
  end

  # [COSMIC EYE / INS.1]: Чи потребує цей алерт НЕЗАЛЕЖНОГО Trigger-2-підтвердження (поза нашим AI)?
  # Страхові перили (пожежа/посуха) + chainsaw ([SLASH-1] — НЕ страховий,
  # але критичний акустичний детект вимагає незалежної перевірки). Маршрут РІЗНИЙ
  # (Dclimate::VerificationService): fire → dClimate FIRMS-супутник; не-пожежа
  # (drought/chainsaw) → Field Audit (fire-супутник не адьюдикує).
  def requires_satellite_consensus?
    alert_type_fire_detected? || alert_type_severe_drought? || alert_type_chainsaw_detected?
  end

  private

  # Обидва читачі прози (`#message`, `#resolution_texts`) конвертують named-
  # параметри в мітки ТУТ — на межі, де видно і сирий вимір, і локаль глядача.
  def resolve_param_labels(params)
    PARAM_LABEL_RESOLVERS.each do |key, resolver|
      params[key] = resolver.call(params[key]) if params.key?(key)
    end
    params
  end

  # [INF.26] Єдиний дім лічильника створених тривог. Свідомо БЕЗ гарда: рахуємо кожну
  # тривогу, що осіла в БД, незалежно від типу, кластера й подальшої долі — інакше
  # повертається рівно той дефект, який цей перенос знімає (метрика під іменем «total»,
  # що лічить одну підмножину).
  # [UI.11] ⚠️ `cluster` тут `optional: true` СВІДОМО (платформені тривоги без
  # кластера — ARCH.82), тож організації може не бути взагалі: тоді гасити
  # нічого, бо й бейджа для такого алерту не існує (він рахується
  # `org.ews_alerts`, тобто через кластери). Тихий вихід тут — не мовчазний
  # дефолт, а точне відображення того, що поза орг-скоупом лічильника немає.
  def bust_org_alert_count_cache
    org = cluster&.organization
    return if org.nil?

    Rails.cache.delete(org.alert_count_cache_key)
  end

  # Окреме імʼя, а не `if:` на спільному методі — див. коментар біля декларацій:
  # два `after_*_commit` з ОДНИМ filter'ом злипаються в один недосяжний колбек.
  def bust_alert_count_on_status_change
    bust_org_alert_count_cache if saved_change_to_status?
  end

  def count_created_alert
    SilkenNet::Metrics::EWS_ALERTS_TOTAL.increment(labels: { alert_type: alert_type.to_s })
  end

  # [INF.26] Дім лічби супутникового вердикту — ТУТ, а не на сайтах
  # `Dclimate::VerificationService`: термінальних писачів `satellite_status`
  # чотири, і `sidekiq_retries_exhausted` у `DclimateVerificationWorker` — поза
  # сервісом. `unverified` не лічимо: це початковий стан, а не вердикт.
  def count_satellite_verdict
    return unless saved_change_to_satellite_status?
    return if satellite_unverified?

    SilkenNet::Metrics::DCLIMATE_VERIFICATION_TOTAL.increment(labels: { result: satellite_status.to_s })
  end

  def dispatch_notifications!
    AlertNotificationWorker.perform_async(self.id)
  end

  # [COSMIC EYE / INS.1]: Планує незалежну Trigger-2-перевірку з затримкою 1 годину (орбітальний проліт)
  # для всіх 3 страхових перилів. Сервіс маршрутизує: fire → FIRMS-вердикт; не-пожежа → Field Audit.
  def schedule_satellite_verification!
    return unless requires_satellite_consensus?
    # 🛰️ [ARCH.118-клас, 2026-09-05] БЕЗ КОНФІГУРАЦІЇ — ЖОДНОГО enqueue, і гейт стоїть
    # саме ТУТ, а не лише в `perform`: приречена джоба, що потрапила в чергу, все одно
    # проходить retry-драбину й осідає в DeadSet. Виміряно на canopy — один прогін
    # симулятора лишив 304 заплановані верифікації в мертвий ендпоінт.
    return unless Dclimate::VerificationService.configured?

    DclimateVerificationWorker.perform_in(1.hour, self.id)
  end

  # [REAL-TIME]: Новий алерт з'являється у стрічці кластера миттєво.
  # Сторінка кластера дістає СИГНАЛ, а не готовий фрагмент, і це не стиль —
  # це єдина форма, за якої тракт взагалі коректний. Панель `Clusters::Show`
  # має власну компактну розмітку (`<div>`, три поля) і показує лише
  # НЕРОЗВʼЯЗАНІ тривоги, тоді як `Alerts::Row` — це `<tr>` на шість колонок
  # для повносторінкового списку. Тому: (1) push сюди вставляв `<tr>` усередину
  # `<div>` — структурно невалідно; (2) правильне дієслово для цієї панелі при
  # розвʼязанні тривоги — не «замінити рядок», а «прибрати й підтягнути
  # наступну», чого фіксований HTML не виражає в принципі. Refresh лишає
  # форму власникові сторінки: він переграє власний запит, дістає свій
  # `unresolved.limit(5)` — і, як побічний наслідок, рендерить у локалі
  # ГЛЯДАЧА, а не продюсера (`04_04 §8.1а`, тому цієї поверхні нема в I18N.2).
  def broadcast_new_alert
    return unless cluster

    Turbo::StreamsChannel.broadcast_refresh_later_to([ cluster, :alerts ])

    # 🔴 Сторінка списку алертів досі не бачила НОВИХ тривог узагалі: вона
    # підписана на org-стрім, а цей продюсер слав лише в cluster-стрім —
    # продюсер і підписник існували обидва, просто на різних адресах.
    # Тут теж сигнал, а не рядок: `Alerts::Index` має фільтри й пагінацію,
    # тож сліпий prepend вставив би нагору тривогу, що не відповідає
    # активному фільтру (і на другій сторінці — не в те місце).
    broadcast_org_refresh
  end

  # Осиротілий кластер (`clusters.organization_id` — nullable у схемі) уже
  # вважається реальним станом двома іншими продюсерами цієї осі: і `Tree`, і
  # `UnpackTelemetryWorker` мають `return unless org_id`. Тут його не гасив ніхто,
  # і ціна мовчазно змінилась із міграцією на дім імен: ДО — броадкаст у мертве
  # СПІЛЬНЕ імʼя `ews_alerts_org_` (те саме для всіх тенантів), ПІСЛЯ — виняток
  # усередині `after_*_commit`, тобто retry-шторм Sidekiq на вже закоміченій
  # тривозі, включно з money-шляхом, що ці тривоги створює. Fail-closed:
  # панель кластера лишається живою, org-список просто не сигналиться.
  # ⚠️ Береться сам ЗАПИС, а не `organization_id`: імʼя стріму несе ще й епоху
  # [SEC.25 Ф3], а дім імен лишається чистою функцією й у БД не ходить. Ціна —
  # один індексований SELECT (per-request/job query-cache його з'їдає).
  def broadcast_org_refresh
    organization = cluster.organization
    return if organization.blank?

    Turbo::StreamsChannel.broadcast_refresh_later_to(TurboStreams::Name.org(:alerts, organization))
  end

  # [ОПТИМІЗАЦІЯ]: Очищення Redis-блокувальника
  def clear_silence_filter!
    return unless tree_id.present?

    silence_key = "ews_silence:#{tree_id}:#{alert_type}"
    Rails.cache.delete(silence_key)
  end

  # [ВИПРАВЛЕНО]: MaintenanceRecord не має колонки status.
  # Використовуємо update_all для швидкодії — MaintenanceRecord не несе
  # фінансових зобов'язань та не має after_update колбеків, тому update_all безпечний.
  def close_associated_maintenance!
    MaintenanceRecord.where(ews_alert_id: id).update_all(
      performed_at: Time.current,
      notes: "Автозакрито через EWS Recovery Protocol"
    )
  end

  # Real-time broadcast для всіх операторів організації.
  #
  # 🔴 [UI.4, 2026-08-17] ВЛАСНОГО ТРОТЛУ ТУТ БІЛЬШЕ НЕМАЄ, і зняли його не
  # заради швидкості — він ГУБИВ сигнал. `should_broadcast?` був leading-edge:
  # перший виклик у 5-секундному вікні проходив, решта ВИКИДАЛИСЬ. Для сигналу
  # «перечитай сторінку» це втрата саме ОСТАННЬОГО оновлення, а останнє на
  # тривозі — її закриття. Досяжно двома акторами на ОДНІЙ тривозі:
  # `Dclimate::VerificationService` пише `satellite_status` (ставить ключ),
  # оператор тисне «закрити» в тому ж вікні — і його сигнал не летить нікуди.
  # Сторінка самого оператора оновлюється редиректом, тож дефект видно лише
  # чужим очам, і скаржитись нема кому.
  #
  # ⊕ Заразом він був зайвий: `broadcast_refresh_later_to` УЖЕ обгорнутий у
  # `refresh_debouncer_for(...).debounce` (turbo-rails `broadcasts.rb:70-76`),
  # ключований ІМЕНЕМ СТРІМУ і **trailing-edge** — останній виклик скасовує
  # попередній заплановий і завжди стріляє. Тобто платформа дає рівно той
  # per-stream кап, який ми намагались зробити руками, і робить це без утрат.
  # Наш ключ був ще й per-ALERT (`ews_alert_broadcast_throttle:#{id}`), тож
  # обіцяного власним коментарем захисту «від масових інцидентів» він не давав
  # ЗА ПОБУДОВОЮ: тисяча різних тривог давала тисячу сигналів.
  #
  # ⚠️ Стеля гемового дебаунсера названа чесно: він живе в `Thread.current`,
  # тож коалесує в межах ОДНОГО треда — 15 Sidekiq-тредів дадуть до 15 сигналів
  # на вікно 0,5 с. Глобального капу немає ні в нас, ні в гема; чи він потрібен —
  # питання ВИМІРЯНОГО навантаження, і воно лишається відкритим у `00_07` UI.4.
  #
  # nil-safe: cluster — optional. Без cluster немає org-channel і немає
  # [cluster, :alerts] stream — для одиноких дерев broadcast no-op.
  def broadcast_alert_update
    return unless cluster

    # Обидві поверхні дістають СИГНАЛ. Для панелі кластера причина — форма й
    # дієслово (див. `broadcast_new_alert`); для списку алертів — локаль і
    # фільтри. `Alerts::Row` несе десять `t()` ПЛЮС `TextFormatter`, тобто
    # це єдиний броадкаст-компонент у репо, чия локаль-залежність частково
    # схована в СЕРВІСІ — там, куди гейт `broadcast_payload_invariance` не
    # ходить за побудовою. А `<tr>` не можна перевести на клас-2 заглушку:
    # `<tbody>` не приймає `<turbo-frame>` (`04_04 §8.1а`). Лишався клас 1,
    # тобто ампутація прози з рядка тривоги, — або сигнал. Сигнал ще й
    # дає сторінці застосувати ВЛАСНІ фільтр і пагінацію, чого сліпий
    # replace не вміє, і знімає `citations`-запит із процесу-продюсера.
    broadcast_org_refresh
    Turbo::StreamsChannel.broadcast_refresh_later_to([ cluster, :alerts ])
  end
end
