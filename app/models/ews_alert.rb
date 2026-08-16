# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # [FIX]: cluster optional — дерево може бути без кластера (одиноке дерево / тестова інсталяція)
  belongs_to :cluster, optional: true
  belongs_to :tree, optional: true
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true

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
    entropy_anomaly: 6,   # Зниження ентропії Z-розподілу (передстресовий сигнал)
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
    emergency_response_undeliverable: 15
  }, prefix: true

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

  # Перевизначення читача, а не окремий метод — щоб УСІ наявні читачі
  # (`Alerts::Row`, мейлер, `TextFormatter`, API) дістали локалізацію без
  # правок, і щоб `validates :message, presence: true` вище працювала для
  # обох шляхів сама: вона читає саме цей метод, а не колонку.
  def message
    return nil if message_key.blank?

    I18n.t(
      "#{MESSAGE_SCOPE}.#{message_key}",
      **message_params.to_h.symbolize_keys,
      default: message_key.to_s.humanize
    )
  end

  # Троттлінг WebSocket-трансляцій: не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" повідомлень при масових інцидентах.
  BROADCAST_THROTTLE_SECONDS = 5

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

  # [SLASH-1] One-Home Field-Audit ескалації, два скоупи за dedup-ключем:
  #   • cluster-level (tree: nil) — (cluster_id, :field_audit, :active, tree_id NULL):
  #     щоденні crons (freeze slash-гейта / blackout / insurance no-data) при тривалій
  #     деградації плодили дубль щодоби. Одна АКТИВНА ескалація на кластер.
  #   • per-tree ([SILENCE-1], tree: задано) — dedup тримають модельна валідація
  #     (scope [tree_id, status]) + частковий unique-index (..._unique_active_per_tree);
  #     індекси взаємовиключні (tree_id IS NULL ⊥ IS NOT NULL) → скоупи співіснують:
  #     cluster-blackout і per-tree тиша — різні сигнали, не дедупляться між собою.
  # Resolve відкриває наступну. Race-safety = часткові unique-index'и.
  # Повертає алерт або nil (dedup-skip) — виклик-сайти на nil НЕ реагують
  # (аудит-виїзд спільний, контекст лишається у їхніх логах).
  def self.escalate_field_audit!(cluster:, message_key:, message_params: {}, tree: nil)
    existing = tree ? active_tree_field_audit_for(tree) : active_cluster_field_audit_for(cluster)
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
  def self.active_cluster_field_audit_for(cluster)
    cluster.ews_alerts.critical.alert_type_field_audit.where(tree_id: nil).first
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

  # Протокол завершення інциденту
  def resolve!(user: nil, notes: "Закрито системою")
    # [СИНХРОНІЗАЦІЯ З REDIS]: Знімаємо "режим тиші", щоб Оракул знову міг
    # слухати це дерево після його відновлення.
    clear_silence_filter!

    self.resolved_at = Time.current
    self.resolver = user
    self.resolution_notes = notes

    # AASM state transition з валідацією (only from :active)
    mark_resolved!

    # [SELF-HEALING]: Атомарно закриваємо MaintenanceRecord
    close_associated_maintenance!

    true
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

  def dispatch_notifications!
    AlertNotificationWorker.perform_async(self.id)
  end

  # [COSMIC EYE / INS.1]: Планує незалежну Trigger-2-перевірку з затримкою 1 годину (орбітальний проліт)
  # для всіх 3 страхових перилів. Сервіс маршрутизує: fire → FIRMS-вердикт; не-пожежа → Field Audit.
  def schedule_satellite_verification!
    return unless requires_satellite_consensus?

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

  # [THROTTLED]: Real-time broadcast для всіх операторів організації.
  # При масових інцидентах WebSocket-канал може «лягти» від потоку оновлень.
  # Троттлінг гарантує мінімальний інтервал між некритичними broadcast.
  # nil-safe: cluster — optional. Без cluster немає org-channel і немає
  # [cluster, :alerts] stream — для одиноких дерев broadcast no-op.
  def broadcast_alert_update
    return unless cluster
    return unless should_broadcast?

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

  # Троттлінг: не частіше ніж раз на BROADCAST_THROTTLE_SECONDS.
  def should_broadcast?
    cache_key = "ews_alert_broadcast_throttle:#{id}"
    return false if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: BROADCAST_THROTTLE_SECONDS.seconds)
    true
  end
end
