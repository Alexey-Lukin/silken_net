# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  include GeoLocatable
  # [SEC.28] Evidence-мутації входять у ланцюг аудиту (присуд власника 2026-08-14).
  # Периметр `Auditable` будувався під governance/money/hardware, і фотодоказ
  # виглядав вужчим класом — але він несе ДОКАЗОВУ БАЗУ D-MRV, тобто саме те,
  # заради чого ланцюг існує (критерій місії: «невідбирано»).
  #
  # 🔴 Вагу тут дає ПАРА властивостей, не одна: видалення незворотне
  # (`purge_later` → S3) І безслідне. Разом це множник — та сама помилка
  # авторизації коштує тут дорожче, ніж на сусідніх поверхнях, бо наслідок не
  # відновлюється й не розслідується. Слід знімає другу половину; перша
  # (м'яке видалення) свідомо відкладена до `SEC.18` — ретеншен і GDPR-стирання
  # це ОДНА політика, і вирішувати її тут означало б завести другий дім.
  #
  # ⚠️ **`include Auditable` тут свідомо НЕМА, і це не пропуск.** Concern віддає
  # рівно один метод — `record_audit_trail!`, обгортку над `record_async!`. Але
  # слід про знищення доказу мусить бути СИНХРОННИМ (інакше при зупиненому
  # Sidekiq фото зникає незворотно, а сліду не лишається взагалі — тобто
  # асинхронність відтворює рівно ту пару властивостей, проти якої SEC.28 і
  # стоїть), тож писач іде через `AuditLog.create!` — той самий прецедент, що
  # `organizations_controller#record_switch!`. Дім виклику —
  # `MaintenanceRecordPhotosController#record_audit_trail_for_purge!`;
  # включений concern був би тут мертвим кодом.
  #
  # ⚠️ Хук-форма (`after_update_commit if: :saved_change_to_X?`) до цієї осі не
  # застосовна за побудовою: зникає ВКЛАДЕННЯ, а не колонка.
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :maintainable, polymorphic: true
  belongs_to :ews_alert, optional: true
  # [E.20] Друга пара очей. ⚖️ founder 2026-08-24: акаунт атестатора живе В
  # організації власника, а незалежність купується ДОГОВОРОМ (сторонній аудитор /
  # академічний партнер, якому платить не бенефіціар) — буквальну форму
  # «організація атестатора ≠ організація власника» відкинуто виміром: читацький
  # скоуп деривується з `acting_organization!.clusters`, тож атестатор із чужої
  # орг запису не бачить, і вимагати цього означало б пробити крос-тенантне
  # читання. Машинно тут перевірний рівно ОДИН інваріант — підписант ≠ автор.
  belongs_to :attestor, class_name: "User", foreign_key: "attested_by_id", optional: true

  # Evidence Protocol (Trust Protocol) — фото до/після для аудиту Series C.
  # Variant :thumb генерується VIPS у фоні (queued job), не блокуючи запит.
  # При десятках мільйонів записів: зберігання на S3 + GCS mirror, роздача через CDN.
  #
  # ⚖️ [SEC.18, 2026-08-20] EXIF: стрип із ПОКАЗУ, оригінал ТРИМАЄМО. Мініатюра —
  # єдина поверхня показу глядачам — іде без метаданих (`strip: true`: смартфонний
  # кадр везе GPS+timestamp техніка, тобто PII повз оголошені колонки); оригінал
  # лишається НЕзачепленим свідомо — EXIF-геотег є потенційним незалежним доказом
  # «технік був на місці» (Anti-Sofa-Repair, ⚖️ UI.7), і його знищення було б
  # незворотним. Обидві половини присуду пінить власна спека (photos_exif_spec).
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 200, 200 ], saver: { strip: true }
  end

  # --- ТИПИ РОБІТ (The Intervention) ---
  # biomass_extraction (5) — Afterlife Economy: extraction of dead wood for
  # Puro.earth Biochar CORC certification. Triggers D-MRV "Biomass Passport"
  # generation via PuroEarthPassportWorker, anchoring provenance on-chain.
  enum :action_type, {
    installation: 0,      # Монтаж
    inspection: 1,        # Огляд
    cleaning: 2,          # Очищення (панелі/датчики)
    repair: 3,            # Ремонт заліза
    decommissioning: 4,   # Демонтаж
    biomass_extraction: 5  # Вилучення біомаси (Puro.earth Biochar)
  }, prefix: true

  # [I18N.1] Людська назва ДІЇ обслуговування — найбільша enum-родина дерева.
  # Скоуп належить домену МОДЕЛІ, не компоненту (`04_04 §12.14`).
  #
  # ⚠️ Мітка ≠ значення: сире значення лишається в URL-параметрі фільтра
  # (`maintenance_records_path(action_type: type)`) і в логіці
  # (`%w[repair installation].include?`) — локалізувати треба ПОКАЗ, і плутати ці
  # три роди вжитку тут особливо легко, бо вони стоять в одному файлі.
  ACTION_TYPE_LABEL_SCOPE = "maintenance.action_types"

  # ОДНА деривація ключа. Fail-open: новий член enum'а рендериться сирим значенням,
  # доки мітка не доїде в локалі — і саме це червонить гейт парності.
  def self.action_type_label(action_type)
    value = action_type.to_s
    I18n.t("#{ACTION_TYPE_LABEL_SCOPE}.#{value}", default: value)
  end

  def action_type_label
    self.class.action_type_label(action_type)
  end

  # [PERF.1(д)] Lifecycle Puro-анкера — «третя форма» (присуд founder 2026-08-20):
  # власні стани на носії хеша за прецедентом EthereumAnchor, БЕЗ грошової таблиці
  # (`blockchain_transactions` — про рух коштів; втискати туди анкер означало б
  # або отруїти `net_minted_supply`, або завести 4-й token_type на 4 доми).
  # nil = анкер не broadcast'ився. Phase 2 (REST у Puro) гейтована на :confirmed —
  # on_chain_proof не віддається в зовнішній реєстр, доки receipt не доведено.
  enum :biomass_passport_status, {
    sent: "sent",                  # broadcast пішов, receipt ще не доведено
    confirmed: "confirmed",        # receipt success — доказ справжній, Phase 2 відкрито
    failed: "failed",              # EVM revert — термінал; re-anchor = console-рішення
    manual_review: "manual_review" # poll вичерпано, доля невідома — людина на polygonscan
  }, prefix: :biomass_passport

  # Гардовані переходи (прецедент EthereumAnchor ARCH.66): with_lock + status-гард =
  # перехід рівно-раз проти гонки двох поллерів (retry-after-redeploy). confirm/fail
  # приймають і :manual_review — гардований людський вихід після console-звірки;
  # escalate лише з :sent (не ре-ескалює вже-ескальоване). block/gas НЕ зберігаємо
  # свідомо: споживача немає, доказ живе в реєстрі Puro (⊥ EthereumAnchor, де
  # компоненти читає зовнішній аудитор L1-якоря).
  def confirm_biomass_passport!
    with_lock do
      return false unless biomass_passport_sent? || biomass_passport_manual_review?

      update!(biomass_passport_status: :confirmed)
    end
  end

  def fail_biomass_passport!
    with_lock do
      return false unless biomass_passport_sent? || biomass_passport_manual_review?

      update!(biomass_passport_status: :failed)
    end
  end

  def escalate_biomass_passport!
    with_lock do
      return false unless biomass_passport_sent?

      update!(biomass_passport_status: :manual_review)
    end
  end

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }
  validates :performed_at, comparison: { less_than_or_equal_to: -> { Time.current } }

  # OpEx-метрики для unit-економіки (Series C Financial Tracking)
  validates :labor_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parts_cost,  numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Hardware State Sync
  validates :hardware_verified, inclusion: { in: [ true, false ] }

  # Afterlife Economy: biomass yield is mandatory for extraction records (D-MRV proof)
  validates :biomass_yield_kg, presence: true,
            numericality: { greater_than: 0 },
            if: :action_type_biomass_extraction?

  # Evidence Protocol: фото обов'язкові при монтажі та ремонті.
  # Виняток для системних записів несе КОЛОНКА `system_generated`, а не
  # транзієнтна ознака: валідація оголошена без `on:`, тож біжить на кожен
  # `save`, і виняток, що не переживає reload, робить запис невиправно
  # невалідним після першого ж `find` [ARCH.91].
  validate :photos_required_for_critical_actions
  # [E.20, ⚖️ founder 2026-08-24] Заявка на вилучення біомаси веде до
  # `declare_deceased!` (→ слешинг-тракт) і до НЕЗВОРОТНОЇ CORC-заявки в
  # зовнішній реєстр — тож вона мусить приходити з доказом ВІД ДВЕРЕЙ, а не
  # ловитись за три ланки звідси.
  #
  # 🔴 Умова спрацювання — «ТИП щойно став biomass», і кожна з трьох альтернатив
  # виміряно гірша. (а) Every-save форма (як у сусіда вище) зламала б Puro-тракт:
  # обидва воркери роблять `update!` на вже-створеному записі, а
  # `sidekiq_retries_exhausted` поллера кличе `escalate_biomass_passport!`
  # усередині `rescue` — `RecordInvalid` полетів би незловленим і запис завис би в
  # `:sent` назавжди. (б) `on: :create` лишає ОБХІД: `maintenance_records#update`
  # пермітить `:action_type`, тож запис створюють як `inspection` (фото не
  # потрібні) і переводять у biomass наступним запитом. (в) Заборона міняти тип
  # узагалі — ширше рішення, ніж вимагає предмет. ⊥ ARCH.91 відкинув `on: :create`
  # для ТРАНЗІЄНТНОГО accessor'а, що зникав після `find`; тут читається реальна
  # асоціація, і lock-out'у немає за побудовою: запис, який утратив фото ПІЗНІШЕ,
  # типу не міняє, тож валідація на ньому мовчить.
  validate :photo_required_for_biomass_claim
  # 🔴 [E.20] ОДНОСТОРОННІ двері, і без них замок доказу знімається одним
  # enum-полем: `biomass → inspection` вимикає і presence `biomass_yield_kg`, і
  # `evidence_locked?` — після чого фото, на якому стоїть виданий у зовнішньому
  # реєстрі CORC, знищується `purge_later` (незворотно) ТИМ САМИМ актором, проти
  # якого гейт і будувався. `action_type` клієнт-керований (`maintenance_params`),
  # `attr_readonly` на ньому немає, політики теж — тож єдиний носій правила тут.
  validate :biomass_claim_is_one_way

  # Тип вкладень — тільки зображення, max 20 МБ кожне, max 10 фото на запис
  # [I18N.4] `message:` тут СВІДОМО немає: `active_storage_validations` везе власні
  # i18n-ключі (`errors.messages.content_type_invalid` / `file_size_not_less_than` /
  # `limit_out_of_range`) у 17 локалях, включно з `uk`. Зашитий рядок їх ПЕРЕКРИВАВ —
  # тобто англієць бачив українську, — і заразом губив числа: гемове повідомлення
  # несе `%{max}` і `%{file_size}`, наше не несло. `lv`/`lt` гем не має, тож вони
  # перекриті в `config/locales/errors/{lv,lt}.yml`.
  validates :photos,
            content_type: { in: %w[image/jpeg image/png image/webp image/heic image/heif] },
            size: { less_than: 20.megabytes },
            limit: { max: 10 }

  # --- СКОУПИ ---
  scope :recent,            -> { order(performed_at: :desc) }
  scope :by_type,           ->(type) { where(action_type: type) }
  scope :hardware_verified, -> { where(hardware_verified: true) }
  # ⚠️ ДВА окремі `where.not` — див. `Tree.geolocated`: один виклик із двома
  # ключами дає ЗАПЕРЕЧЕННЯ КОНʼЮНКЦІЇ (АБО), а це доказова поверхня
  # Anti-Sofa-Repair — «є GPS» тут мусить означати обидві координати.
  scope :with_gps,          -> { where.not(latitude: nil).where.not(longitude: nil) }
  # [E.20] Черга «чекає на засвідчення» — заявки на біомасу без другої пари очей.
  # Доти такого скоупа не існувало ніде, і саме тому провал тракту адресував
  # ops-а числом у DeadSet, а не лісника, який ЩЕ МОЖЕ підписати.
  scope :awaiting_attestation, -> { where(action_type: :biomass_extraction, attested_by_id: nil) }

# =========================================================================
# КОЛБЕКИ (The Healing Protocol)
# =========================================================================

# [ВИПРАВЛЕНО]: Ми відмовилися від heal_ecosystem! всередині моделі.
# Замість цього запускаємо асинхронний воркер, що гарантує 100% доставку
# змін статусу навіть при тимчасових збоях бази даних.
after_create_commit :trigger_ecosystem_healing!

# [UI.4] Третій продюсер стрічки подій дашборда — дописаний за зразком
# `EwsAlert#broadcast_org_refresh` і `BlockchainTransaction#broadcast_ledger_signal`,
# бо саме з цих трьох доменів `fetch_recent_events` збирає стрічку, а два з них
# сигналили вже, і лише обслуговування мовчало. ОДНА реєстрація на обидві події:
# `after_create_commit` + `after_update_commit` з тим самим іменем фільтра не дають
# двох колбеків — ActiveSupport ключує їх ІМЕНЕМ, і друга реєстрація тихо заміщає
# першу (виміряно на `_commit_callbacks`, `blockchain_transaction.rb`).
after_commit :broadcast_maintenance_signal, on: %i[create update]

  # =========================================================================
  # МЕТОДИ
  # =========================================================================

  # OpEx-вартість одного запису для звітності Series C.
  # Базова ставка 50 $/год — override через ENV для регіональних ринків.
  LABOR_RATE_PER_HOUR = ENV.fetch("PATROL_LABOR_RATE", 50).to_f

  # 🔴 [ARCH.103] Повертає `nil`, коли бодай один доданок не введено — і це не
  # прискіпливість, а буквальне читання власного імені: «Total» СТВЕРДЖУЄ повноту,
  # тож сума з невідомим доданком не є total. Доти обидва `.to_f` перетворювали
  # «не введено» на нуль, метод не повертав `nil` ЖОДНОГО разу, і кожна nil-перевірка
  # на виклику була марною — звідси й `$0.00` на трьох поверхнях там, де технік
  # просто не заповнював поле (обидва nullable, обидва `allow_nil: true`, форма
  # пропонує їх без `required:`).
  # ⚠️ Ціна ЗАНИЖЕННЯ, а не завищення: це unit-economics Series C, тож вигаданий
  # нуль тихо здешевлював кожен запис без даних — а занижена оцінка гірша за
  # відсутню, бо виглядає як вимір.
  # ⛔ Відкинута альтернатива — «сумувати наявні, відсутнє рахувати нулем»: вона
  # домислює, що порожнє поле означає «не було», і робить це МОВЧКИ. Технік, який
  # хоче зафіксувати «запчастин не було», вводить `0` — форма приймає (`min: 0`),
  # і тоді `$0.00` є чесним виміром, а не заповнювачем.
  def total_cost
    return nil if labor_hours.nil? || parts_cost.nil?

    (labor_hours.to_f * LABOR_RATE_PER_HOUR) + parts_cost.to_f
  end

  # [UI.6] Дім правила «хто може мутувати цей запис»: автор або admin+.
  #
  # Правило доти жило приватним методом контролера, тож UI дістати його не міг — і саме
  # тому кнопки `verify`/`edit`/«×» рендерились кожному, хто відкрив сторінку. Тут воно
  # доступне ОБОМ споживачам (гард і компонент), тобто не форкається; роль-формулу теж
  # не форкає — кличе `User#admin_or_above?` ([`04_03 §3`](04_03_REST_API_v1_Reference)).
  #
  # ⚠️ Про тенансі цей предикат мовчить СВІДОМО: приналежність тримає асоціативний скоуп
  # у викликача (`acting_organization!.clusters` → `set_record`), і це канонічний поділ
  # двох ідіомів — предикат відповідає на «роль × авторство», асоціація на «чиє це».
  # Отже викликач ЗОБОВ'ЯЗАНИЙ дістати запис org-скоупленим запитом: adminʼу чужої
  # організації цей метод скаже `true`, бо про організацію його не питали.
  def mutable_by?(actor)
    return false if actor.blank?

    actor.admin_or_above? || user_id == actor.id
  end

  # [SEC.28] Дім умови «фото цього запису Є ДОКАЗОМ», і читачів у неї ТРИ: валідація,
  # що вимагає фото; гард, що забороняє їх знищувати; і кнопка, яка через це не
  # рендериться. Порізно вони розійшлися б ТИХО — запис лишався б валідним, утративши
  # рівно те, чим доводиться.
  #
  # ⚖️ Присуд founder: доказ не має СТРОКУ зберігання — він має ГАРД. Форма взята з
  # ратифікованої доктрини гаманця (`Wallet#guard_mrv_evidence!` — «грошові докази
  # незнищенні, off-board = деактивація»), бо питання те саме, лише носій інший.
  def evidence_backed?
    return false if system_generated?

    action_type_repair? || action_type_installation?
  end

  # 🔴 [E.20, 2026-08-24] ДРУГЕ питання, яке доти вело той самий предикат — і саме
  # тому вимога фото для `biomass_extraction` без цього розколу була б ТЕАТРОМ:
  # `guard_evidence_purge!` читає `evidence_backed?`, а biomass туди не входить,
  # тож доказ, обовʼязковий на вході, знімався б наступним кліком (`purge_later`,
  # незворотно). Питання РІЗНІ:
  #   • `evidence_backed?` — «чи фото обовʼязкові на КОЖЕН save» (валідація);
  #   • `evidence_locked?` — «чи фото цього запису НЕЗНИЩЕННІ» (гард + кнопка).
  # ⛔ Не зливати назад і ⛔ не додавати `biomass_extraction` у предикат вище:
  # валідація там оголошена БЕЗ `on:`, а обидва Puro-воркери роблять `update!` на
  # вже-створеному записі — вимога поїхала б на кожен їхній save і завісила б
  # паспорт у `:sent` назавжди (механіка — [ARCH.91] + картка воркера `04_02 §11`).
  # Для biomass доказ вимагається ОДИН раз, на створенні (`on: :create` вище).
  # ⚠️ Власного `system_generated`-гарда тут НЕ ТРЕБА: `evidence_backed?` уже його
  # несе, а biomass-заявка системною бути не може за побудовою (валідація нижче не
  # має винятку). Додати його означало б завести гілку, якої ніщо не досягає.
  def evidence_locked?
    evidence_backed? || action_type_biomass_extraction?
  end

  # [E.20] «Атестатор ≠ бенефіціар» у машинній частині. ⚖️ founder 2026-08-24:
  # незалежність тримає ДОГОВІР, а код стереже єдине, що взагалі може стерегти —
  # що підписав НЕ той, хто написав. Це слабший інваріант, ніж «інша організація»,
  # і канон каже це прямо, замість вдавати сильніший ([`04_01 §7`]).
  class SelfAttestation < StandardError; end

  # Ідемпотентно: повтор тим самим атестатором не зсуває `attested_at` — інакше
  # другий клік переписував би ЧАС засвідчення, тобто саме те, що робить запис
  # доказом. Дзеркало `EwsAlert#claim!`, і з тієї ж підстави.
  def attest!(actor)
    return true if attested_by_id == actor.id
    raise SelfAttestation if actor.id == user_id

    # 🔴 [E.20] Підпис — ПУСКАЧ обох незворотних дій, а не лише їхній дозвіл.
    # Доти паспорт ставив у чергу `EcosystemHealingWorker` безумовно, тож атестатор
    # мав рівно стільки часу, скільки живе джоба (≈7–10 хв до DeadSet) — дедлайн, що
    # селектує підпис не дивлячись. Тепер порядок природний: спершу друга пара
    # очей, потім вихід у зовнішній реєстр.
    #
    # ⚖️ [E.20, 2026-08-25] Сюди ж переїхало ОГОЛОШЕННЯ СМЕРТІ. `declare_deceased!`
    # термінальний (подій `from: :deceased` немає) і тим самим переходом смикає
    # `trigger_slashing_protocol` — тобто з заявки його виконувала одна людина
    # одним рядком форми. Дерево, яке вже мовчить, не може заперечити за себе,
    # тож незворотне тут ставить незалежний свідок, не автор заявки.
    # Смерть і підпис — в ОДНІЙ транзакції: заатестована заявка, що не змінила
    # статус дерева, стверджувала б виконану дію, якої не сталося.
    transaction do
      update!(attested_by_id: actor.id, attested_at: Time.current)
      maintainable.declare_deceased! if action_type_biomass_extraction? && !maintainable.deceased?
    end

    # Поза транзакцією СВІДОМО: enqueue до коміту дає джобу, яка не бачить рядка.
    PuroEarthPassportWorker.perform_async(id) if action_type_biomass_extraction?
    true
  end

  def attested?
    attested_by_id.present?
  end

  # [E.20] Дім питання «де зараз заявка на CORC», і він ОДИН, бо читачів троє:
  # сторінка запису, рядок реєстру й блупринт. `biomass_passport_status` сам по
  # собі на це не відповідає — його `nil` не розрізняє «підпису ще немає» від
  # «підпис є, а заявка не пішла», а це два РІЗНІ адресати: перше лікує інший
  # лісник, друге — оператор.
  #
  # 🔴 Порожній паспорт при наявному підписі НЕ є транзієнтним станом «джоба в
  # дорозі», і поріг тут не потрібен: `PuroEarthPassportWorker` вичерпує ретраї за
  # ≈7–10 хв і осідає в DeadSet, після чого `biomass_passport_status` не зміниться
  # НІКОЛИ без консольного re-enqueue. Тобто «не подано» правдиве в обох випадках,
  # і вигаданий таймер лише додав би третю відповідь на те саме питання.
  def biomass_claim_state
    return nil unless action_type_biomass_extraction?
    return :awaiting_attestation unless attested?
    return :not_filed if biomass_passport_status.blank?

    biomass_passport_status.to_sym
  end

  # [I18N.1] Мітка стану заявки — дзеркало `ACTION_TYPE_LABEL_SCOPE`, і з тієї ж
  # підстави: показують її ДВА компоненти (сторінка запису й рядок реєстру), тож
  # скоуп належить домену МОДЕЛІ. Інакше другий компонент тягнув би абсолютний
  # ключ із чужого скоупу — тобто заводив би мітці другий дім.
  BIOMASS_CLAIM_STATE_LABEL_SCOPE = "maintenance.biomass_claim_states"

  # Fail-open, як у сусіда: новий стан рендериться сирим токеном, доки мітка не
  # доїде в локалі — і саме це червонить гейт парності.
  def self.biomass_claim_state_label(state)
    value = state.to_s
    I18n.t("#{BIOMASS_CLAIM_STATE_LABEL_SCOPE}.#{value}", default: value)
  end

  def biomass_claim_state_label
    state = biomass_claim_state
    state && self.class.biomass_claim_state_label(state)
  end

  # [E.20] Ратифікована форма незалежності — акаунт У організації власника плюс
  # ДОГОВІР. Підписант поза нею це не порушення (super_admin рятує орг з одним
  # лісником від глухого кута), але це СЛАБША форма, ніж ратифікована, — і доти
  # вона не була видима ніде: у полі лежить лише `attested_by_id`. Поверхня
  # мусить її ПОКАЗУВАТИ, а не ховати ([`04_01 §7`]).
  def attested_outside_owner_organization?
    return false unless attested?

    attestor.organization_id != user.organization_id
  end

  # [UI.7, ⚖️ 2026-08-20] Дім питання «чи залізо ПІДТВЕРДИЛО обслуговування» —
  # єдиний канал, якого технік НЕ контролює: пульс самого вузла, не телефон і не
  # поле форми. Доти `verify` ставив `hardware_verified: true` БЕЗУМОВНО під
  # коментарем «STM32 відповів новим пульсом» — тобто прапорець був
  # самоатестацією другого кліку, а коментар описував механізм, якого не було.
  # Критерій: вузол вийшов в ефір ПІСЛЯ performed_at (обидва maintainable-типи
  # несуть `last_seen_at`). Предикат на моделі, не в контролері — `insert_all`
  # валідацій не питає, тож писач мусить мати змогу спитати ТЕ САМЕ до запису
  # (та сама підстава, що `Actuator#can_sustain?`).
  def hardware_pulse_confirmed?
    return false if performed_at.blank?

    pulse = maintainable&.last_seen_at
    pulse.present? && pulse > performed_at
  end

private

# СИГНАЛ, а не рядок: стрічка дашборда — похідний міжсутнісний рейтинг, тож
# `prepend` дав би неправильне ДІЄСЛОВО (кап-3 на тип і зріз-8 не шануються), а
# заміна контейнера тягла б locale-залежний payload у стрім, спільний для всіх
# глядачів організації (`04_04 §8.1б`).
#
# ⚠️ Організація береться від АВТОРА запису, і це не довільний вибір: стрічка
# скоупить обслуговування саме так (`where(users: { organization_id: org.id })`).
# Поліморфний `maintainable` дав би ІНШУ множину — тобто сигнал, що не збігається
# з тим, що сторінка показує. Береться org-ЗАПИС, бо імʼя несе `stream_epoch`.
def broadcast_maintenance_signal
  owner = user&.organization
  # Fail-closed без тиші: `TurboStreams::Name.org` на `nil` кинув би `ArgumentError`,
  # який власний `rescue` нижче зʼїв би у WARN — рядок лишився б німим так само,
  # лише без сліду.
  return if owner.blank?

  Turbo::StreamsChannel.broadcast_refresh_later_to(TurboStreams::Name.org(:maintenance, owner))
rescue StandardError => e
  # `commit_records` має `ensure` без `rescue`, тож виняток UI-декорації пролетів би
  # нагору з `create!`/`update!` — тут це вбило б подання запису обслуговування
  # 👤-оператором у полі, заради оновлення чужого екрана.
  Rails.logger.warn "📡 [UI.4] broadcast_maintenance_signal ##{id}: #{e.message}"
end

  def trigger_ecosystem_healing!
    # Викликаємо "М'яз зцілення" (NAM-ŠID Healing).
    # Він обробить і логіку актуаторів, і закриття EwsAlert із вірними префіксами (status_resolved?).
    EcosystemHealingWorker.perform_async(self.id)
  end

  # Trust Protocol: ремонт і монтаж без фото — не proof of care, а просто слова.
  # Платформа камери не має, тому її власні записи звільнені — і саме тому
  # `system_generated` не входить у `maintenance_params`: інакше клієнт знімав
  # би з себе Evidence Protocol одним полем форми.
  def photos_required_for_critical_actions
    return unless evidence_backed?
    return if photos.any?

    errors.add(:photos, :required_for_action_type)
  end

  # [E.20] Заявка на вилучення біомаси — єдина дія, що виходить у ЗОВНІШНІЙ реєстр
  # незворотно, тож доказ вимагається від дверей. Системні записи звільнені тією ж
  # колонкою, що й сусід: платформа камери не має.
  # ⛔ Винятку для `system_generated` тут НЕМА, і це не пропуск, а протилежність
  # сусідові: платформа камери не має (тому її записи звільнені від Evidence
  # Protocol) — отже вона й НЕ МОЖЕ подавати заявку, що виходить у зовнішній
  # реєстр. Скопійований виняток був би дірою з виглядом однорідності: гейт
  # паспортного воркера системних записів не звільняє, тож звільнений тут запис
  # усе одно помер би там — лише пізніше й тихіше.
  def photo_required_for_biomass_claim
    return unless action_type_biomass_extraction?
    # Лише в мить, коли запис СТАЄ заявкою на біомасу — на створенні або на зміні
    # типу. Пізніші `update!` Puro-воркерів сюди не входять за побудовою.
    return unless new_record? || action_type_changed?
    return if photos.any?

    errors.add(:photos, :required_for_biomass_claim)
  end

  def biomass_claim_is_one_way
    return unless action_type_changed?
    return unless action_type_was == "biomass_extraction"

    errors.add(:action_type, :biomass_claim_is_final)
  end
end
