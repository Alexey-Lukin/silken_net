# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Tree < ApplicationRecord
  include AASM
  include Firmwareable
  include GeoLocatable
  include NormalizeIdentifier

  # Polymorphic identifier для UI/serializers (наприклад, MaintenanceRecord з
  # maintainable: Tree | Gateway). Дозволяє писати `record.maintainable.display_identifier`
  # замість `&.try(:did) || &.try(:uid)` duck-typing у 3 callsites.
  alias_attribute :display_identifier, :did

  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model, optional: true
  belongs_to :tree_family, counter_cache: true

  has_one :wallet, dependent: :destroy

  # Zero-Trust: DID дерева є ключем до його апаратного шифру
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :did, dependent: :destroy

  has_one :device_calibration, dependent: :destroy

  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для швидкодії без OOM
  has_many :telemetry_logs, dependent: :delete_all

  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для масових таблиць,
  # щоб уникнути OOM при видаленні дерева з мільйонами записів.
  has_many :ews_alerts, dependent: :delete_all
  # [UI.3] Прелоадибельне дзеркало `EwsAlert.unresolved` — існує рівно заради
  # `#under_threat?`, який їде в циклі на двох сторінках. `includes(:ews_alerts)`
  # тут НЕ рятує: `.unresolved` на завантаженій асоціації будує НОВУ relation і
  # б'є в БД повз прелоад, тож без цієї асоціації кожен рядок платив свій EXISTS.
  # ⛔ Не міняти на дубль умови в Ruby (`any?(&:status_active?)`): лямбда КЛИЧЕ
  # скоуп, тобто правило лишається в одному домі — `EwsAlert.unresolved`.
  # `dependent:` свідомо немає — знищення веде батьківська асоціація вище.
  # rubocop:disable Rails/HasManyOrHasOneDependent -- відсутність свідома й
  # пояснена вище: це відфільтрована ПРОЄКЦІЯ тієї самої таблиці, знищенням якої
  # відає батьківська асоціація.
  has_many :unresolved_ews_alerts, -> { unresolved }, class_name: "EwsAlert", inverse_of: :tree
  # rubocop:enable Rails/HasManyOrHasOneDependent
  has_many :maintenance_records, as: :maintainable, dependent: :delete_all
  has_many :ai_insights, as: :analyzable, dependent: :delete_all

  # --- ДЕЛЕГУВАННЯ ---
  delegate :name, to: :tree_family, prefix: true

  # [FW.8] Global Lorenz defaults — match firmware/bio_contracts/bio_contract.rb
  # BioContract::CRITICAL_Z_MIN/MAX/OPTIMAL_Z_TARGET. Used as final fallback when
  # neither cluster override nor tree_family per-species value is set.
  GLOBAL_LORENZ_Z_MIN     = 2.0
  GLOBAL_LORENZ_Z_MAX     = 45.0
  GLOBAL_LORENZ_Z_OPTIMAL = 29.0

  # --- СТАН (The Lifecycle) ---
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :dormant
    state :removed
    state :deceased

    # Дерево входить у зимовий сон / суху фазу
    event :suspend do
      transitions from: :active, to: :dormant
    end

    # Пробудження після зимового сну / відновлення
    event :reactivate do
      transitions from: :dormant, to: :active
    end

    # Списання дерева (деінсталяція обладнання)
    event :decommission do
      transitions from: [ :active, :dormant ], to: :removed
    end

    # Біологічна смерть дерева
    event :declare_deceased do
      transitions from: [ :active, :dormant ], to: :deceased
    end
  end

  # ⛔ [ARCH.99, присуд founder 2026-08-13 — варіант A] Констант шкали заряду тут
  # БІЛЬШЕ НЕМА, і повертати їх не можна без живого Vcap-каналу (`00_07` FW.50).
  # Причина не в числах: `latest_voltage_mv` — це мВ VDDA, а BQ25570 стабілізує ту
  # шину на 3.3 В від VSTOR ≥ 3.4 В аж до 5.5 на іоністорі (`02_03 §7`), тож вона
  # за КОНСТРУКЦІЄЮ не несе інформації про запас енергії — buck існує рівно щоб
  # сховати напругу сховища від MCU. Будь-яка шкала «скільки лишилось» на цьому
  # вході є фабрикацією, хай би які межі їй дати.
  # Дім сигналу «мало енергії» = МОВЧАННЯ: `Tree.silent` + `TreeStalenessSweepWorker`
  # (нижче порога `VBAT_UV` BQ25570 просто знеструмлює MCU — низький запас у цій
  # архітектурі спостережуваний ЛИШЕ як тиша, ніколи як низьке число).

  # Дефолтний поріг тиші — ОДИН дім на скоуп і предикат [transitional до bench,
  # рантайм веде `TreeStalenessSweepWorker` через SystemParameter].
  SILENCE_THRESHOLD = 24.hours

  # Zero-Trust: Формат DID відповідає апаратній специфікації STM32 (uint32_t → 8 hex digits)
  DID_FORMAT = /\ASNET-[0-9A-F]{8}\z/

  # --- ВАЛІДАЦІЇ ---
  normalize_identifier :did
  validates :did, presence: true, uniqueness: true,
            format: { with: DID_FORMAT, message: :must_match_hardware_format }
  # DID входить у Merkle leaf-формулу (Mrv::TelemetryLeaf) — зміна після створення
  # зробила б історичні листи невідтворюваними (якорені корені «попливли» б).
  attr_readonly :did

  # [FW.54/SEC.3] Кремнієвий паспорт (96-біт STM32 UID, три %08X-слова у
  # порядку регістрів): DID деривується з нього (SilkenNet::DidDerivation),
  # а збережений оригінал відрізняє re-flash того самого чипа від
  # birthday-колізії DID двох різних чипів (03_01 §7 → quarantine).
  # nil = legacy-дерево, створене до one-pass провіженінгу.
  normalize_identifier :silicon_uid_hex
  validates :silicon_uid_hex, uniqueness: true, allow_nil: true,
            format: { with: SilkenNet::DidDerivation::UID_HEX_FORMAT, allow_nil: true }

  # 🕰️ [SLASH-1] Момент переходу статусу — носій `dead_count` для розміру вироку.
  # `before_save`, а НЕ commit-хук: колонка мусить лягти ТИМ САМИМ UPDATE, що й
  # статус, інакше вони розходяться фізично (той самий клас, що денормалізований
  # `active_trees_count`, який обходять `update_all`/`update_column`).
  # Пишемо на КОЖНУ зміну статусу, не лише термінальну: ім'я колонки це й означає,
  # а читач однаково гейтується `status IN (removed, deceased)` — обидва стани
  # термінальні (в aasm-блоці нижче подій `from:` для них немає), тож після смерті
  # колонка більше не рухається.
  before_save :stamp_status_changed_at, if: :will_save_change_to_status?
  # --- КОЛБЕКИ ---
  after_create :build_default_wallet
  after_create :ensure_calibration

  # [Counter Cache]: Підтримка денормалізованого лічильника active_trees_count у Cluster.
  # Використовуємо after_commit для гарантії видимості змін іншими транзакціями.
  after_create_commit :increment_cluster_active_trees_count, if: -> { active? && cluster_id.present? }
  after_destroy_commit :decrement_cluster_active_trees_count, if: -> { active? && cluster_id.present? }
  after_update_commit :update_cluster_active_trees_count, if: -> { saved_change_to_status? || saved_change_to_cluster_id? }

  # ⚡ [ТРИГЕР СМЕРТІ]: Якщо дерево гине або зникає — ініціюємо фінансову відплату (Slashing)
  after_update_commit :trigger_slashing_protocol, if: -> { saved_change_to_status? && (removed? || deceased?) }

  # ⚡ [ГЕОПРОСТОРОВА МАТРИЦЯ]: Оновлюємо вузол на мапі лише при зміні гео-даних або статусу.
  # [ВИПРАВЛЕНО: Broadcast Storm]: Раніше стріляло на КОЖЕН update (включаючи mark_seen!/voltage),
  # що генерувало 10K+ WebSocket-повідомлень/годину при масовій телеметрії.
  # Тепер — тільки при зміні координат, статусу або voltage_mv (UI-релевантні зміни).
  after_update_commit :broadcast_map_update, if: :map_relevant_change?

  # --- СКОУПИ (The Watchers) ---
  # `Tree.active` автогенерується `enum :status, { active: 0, ... }`, не дублюємо.
  # ⚠️ ДВА окремі `where.not`, не один із двома ключами: другий дає
  # `NOT (lat IS NULL AND lng IS NULL)`, тобто АБО — запис з однією координатою
  # вважався б геолокованим. Дім поняття — `GeoLocatable#geolocated?` (обидва
  # поля), і `broadcast_map_update` гейтується так само, тож напів-координатне
  # дерево скоуп віддавав, а броадкаст по ньому мовчки не робив нічого.
  scope :geolocated, -> { where.not(latitude: nil).where.not(longitude: nil) }

  # [SILENCE-1] Аномальна тиша: active-дерево, що ВЖЕ виходило в ефір, але мовчить
  # довше порога. Поза скоупом свідомо: last_seen_at NULL («мовчання ненародженого» —
  # beginless range робить SQL-відкидання NULL семантикою, не випадковістю), dormant
  # (свідомо приспане) і removed/deceased (легітимно мовчазні — інакше sweeper ганяв би
  # Field Audit на кладовище). Рантайм-поріг веде TreeStalenessSweepWorker через
  # SystemParameter; дефолт 24h [transitional] до bench-калібрування (00_07 SILENCE-1:
  # delta_t навмисно варіативний, поріг НЕ виводиться з конфіга). Стеля: індексу на
  # last_seen_at нема — на тисячах рядків seq-scan дешевий, scale → індекс.
  scope :silent, ->(threshold = SILENCE_THRESHOLD) { active.where(last_seen_at: ...threshold.ago) }
  # ⛔ [SLASH-1, 2026-08-25] Тут стояв `scope :critical_stress` — знято як мертву гілку
  # (нуль викликачів поза власною спекою). Ніс ТРИ пастки одночасно, і кожна коштувала б
  # першому ж читачеві: сирий `0.8` замість DAO-live `AiInsight.slash_stress_threshold`
  # (дефолт `0.83`) · СТРОГЕ `>` там, де обидва живі споживачі порога беруть `>=` ·
  # `joins(:ai_insights)` без `.distinct`, тож дерево з N інсайтами поверталось би N разів
  # — рівно та лічба РЯДКІВ замість ДЕРЕВ, яка вже роздувала спалення 813 → 2000 SCC
  # [ARCH.46]. Дротувати не стали: поверхня без споживача, дотягнута до правильної форми,
  # лишається без споживача, але вже виглядає санкціонованою.

  # --- МЕТОДИ (Intelligence) ---

  # [ВИПРАВЛЕНО: Фантомна Луна + Race Condition]:
  # GREATEST гарантує детермінованість при одночасних пакетах від різних наземних станцій Starlink
  def mark_seen!(voltage_mv = nil)
    now = Time.current

    sql = if voltage_mv
      [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?), latest_voltage_mv = ?", now, now, voltage_mv ]
    else
      [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?)", now, now ]
    end

    self.class.where(id: id).update_all(sql)

    # Синхронізуємо in-memory стан без reload (як update_columns) для швидкодії на hot path
    self.last_seen_at = now
    self.latest_voltage_mv = voltage_mv if voltage_mv
    # [ВИПРАВЛЕНО: Broadcast Storm]: Видалено broadcast_map_update з hot path телеметрії.
    # mark_seen! викликається для КОЖНОГО пакету (мільйони на годину).
    # Мапа оновлюється через after_update_commit :broadcast_map_update лише при
    # зміні координат або статусу (map_relevant_change?).
  end

  # Останній вердикт Оракула
  # [ВИПРАВЛЕНО: N+1 TreeBlueprint#current_stress]:
  # Читаємо денормалізовану колонку latest_stress_index замість запиту до ai_insights —
  # це усуває N+1 при серіалізації TreeBlueprint :index та Dashboard::MapNode.
  #
  # 🔴 [ARCH.84] Колонку читаємо ЯК Є: `nil` = «не виміряно», окремий СТАН, і саме
  # тут стояла ридер-підстановка. `.to_f` виглядав форматуванням, а був нею: він
  # перетворював порожнечу на `0.0` — найкращий можливий показник стресу, — тож
  # знята з колонки `DEFAULT 0.0` без цього рядка не змінила б нічого.
  # ⛔ Не повертати `.to_f`/`|| 0`: розрізняти «бездоганне» від «не міряли» —
  # робота споживача, і кожен робить це по-своєму (`04_01 §2`).
  def current_stress
    latest_stress_index&.to_f
  end

  # [UI.3] Ціна виклику залежить від того, чи прелоаджено асоціацію: без прелоаду
  # `.any?` вироджується в той самий `SELECT 1 … LIMIT 1`, що й колишній
  # `.exists?` (одинична сторінка нічого не втратила), а з прелоадом коштує НУЛЬ.
  # Тобто рядок один, а сторінка-цикл платить рівно стільки, скільки її контролер
  # попросив (`04_04 §6` — «все, що показує в'ю, вантажить контролер»).
  def under_threat?
    unresolved_ews_alerts.any?
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ЖИВЛЕННЯ ВУЗЛА (шина VDDA, звітована прошивкою)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # [ОПТИМІЗАЦІЯ: N+1 Загроза]: Тепер беремо значення прямо з таблиці trees.
  # Це сира напруга шини — діагностична (просідання = близькість брауноуту), і
  # НЕ похідна: жодного «відсотка заряду» з неї вивести не можна (див. ⛔ вище).
  #
  # [ARCH.84] ⛔ Не повертати `|| 0` — це ридер-підстановка, і вона тут коштувала
  # дорожче за звичайну: **нуль мВ на цій шині означає браунаут**, тобто вузол, що
  # ніколи не виходив в ефір, друкувався найгіршим МОЖЛИВИМ виміром. Форма зняття
  # дослівно та сама, що в сусіда `current_stress` рядком вище; `nil` = не виміряно,
  # а рендерить його `ApplicationComponent#measured_value`.
  def supply_voltage_mv
    latest_voltage_mv
  end

  # [ARCH.99] Рядковий бік сигналу тиші — ОДИН дім замість рукописних копій
  # у в'ю. ⚠️ Свідомо НЕ дзеркало `scope :silent`: той відкидає `last_seen_at IS
  # NULL` («мовчання ненародженого» — sweeper не має гнати Field Audit на вузол,
  # який ще не виходив в ефір), а глядачеві «жодного пакета» і «пакетів давно» —
  # однакова відсутність свіжого сигналу. Різниця названа, не випадкова.
  def fresh_signal?(threshold = SILENCE_THRESHOLD)
    last_seen_at.present? && last_seen_at >= threshold.ago
  end

  # Останній рядок телеметрії ОДНОГО дерева — сторінка вузла (`trees#show`).
  # 🔴 **Тільки для одиничного дерева, і межа несуча:** у циклі по флоту цей метод
  # вироджується в N+1 (`ORDER BY created_at DESC LIMIT 1` на кожне дерево, по всіх
  # партиціях), і саме так він і жив у прогнозі врожаю [PERF.1]. Питання «останній
  # рядок на КОЖНЕ дерево набору» має власний дім — `TelemetryLog.latest_per_tree`
  # (один `DISTINCT ON` на батч). ⚠️ Мемоїзація тут розрахована на життя одного
  # запиту; на довгоживучому обʼєкті вона застаріє мовчки.
  def latest_telemetry_log
    @latest_telemetry_log ||= telemetry_logs.order(created_at: :desc).first
  end

  # ⚡ [ГЕОПРОСТОРОВА МАТРИЦЯ]: Трансляція вузла в Stimulus контролер.
  # Стрім скоуплений організацією ВЛАСНИКА дерева — голий `"geospatial_matrix"`
  # роздавав би координати й DID чужого флоту кожному, хто відкрив дашборд
  # (той самий клас, що SEC.25 на телеметрії). ⚠️ Тут доти стояло, що дерево без
  # кластера — «звичайний стан» через `dependent: :nullify` з боку Cluster; ⚖️ присуд
  # 2026-07-30 це скасував: каскад став `restrict_with_error`, і безкластерне дерево
  # не є станом предметної області. Гард нижче лишається як defense-in-depth (колонка
  # ще nullable), але читати його як штатну гілку більше не можна.
  def broadcast_map_update
    return unless latitude.present? && longitude.present?

    # Сам ЗАПИС, а не `organization_id`: імʼя несе ще й епоху [SEC.25 Ф3], а дім
    # імен лишається чистою функцією й у БД не ходить.
    organization = cluster&.organization
    return unless organization # осиротіле дерево: краще без live-вузла, ніж у глобальний ефір

    Turbo::StreamsChannel.broadcast_replace_to(
      TurboStreams::Name.org(:map, organization),
      target: Dashboard::MapNode.dom_id(id),
      html: Dashboard::MapNode.new(tree: self).call
    )
  end

  # [FW.8] Effective Lorenz thresholds with three-level priority chain (governance):
  #   1. Cluster-level per-species override (cluster.lorenz_overrides_for(scientific_name))
  #      — a cluster may host trees of several species; each species gets its own
  #        biome-adjusted overrides set by org admin.
  #   2. TreeFamily per-species value
  #   3. Global default (BioContract::CRITICAL_Z_MIN/MAX/OPTIMAL_Z_TARGET)
  #
  # Returns Hash{ min:, max:, optimal: } of Float values.
  #
  # 🔴 РОЛЬ ЦЬОГО МЕТОДУ — «ЩО СЛАТИ на пристрій», і саме тому DCI його НЕ вживає
  # (див. `#device_lorenz_thresholds`). Доти докстрінг називав другим споживачем
  # `TelemetryUnpackerService`, тобто судження про ЦІЛІСНІСТЬ обчислення бралось
  # за БАЖАНИМИ порогами, яких пристрій не має.
  #
  # ⚠️ «Роль одна» — про ЦЕЙ метод, не про родинну смугу взагалі: судити за
  # `tree_family.critical_z_*` лишається легітимним у БІО-питанні, і там це живе
  # (`AlertDispatchService` → `Attractor.homeostatic?` → `severe_drought`). Розвели
  # не «сервер проти родини», а два РІЗНІ питання: «чи збіглись обчислення» ⊥ «чи
  # дерево поза своєю нормою».
  #
  # SSOT consumed by:
  #   - OtaPackagerService#build_threshold_config_block (CMD_SET_THRESHOLDS 0x9A)
  #     ⚠️ Споживач СПЛЯЧИЙ: у `app/`/`lib/` викликача в нього нема, тракт
  #     доставки не дротований (`03_01`: «у downlink pipeline не передається»).
  #     Тобто сьогодні цей ланцюг (cluster override → family → global) не має
  #     жодного ЖИВОГО продового читача — його вмикає bench-нога FW.8, не код.
  def effective_lorenz_thresholds
    family    = tree_family
    overrides = cluster && family&.scientific_name ? cluster.lorenz_overrides_for(family.scientific_name) : {}

    {
      min:     overrides[:min]     || family&.critical_z_min&.to_f || GLOBAL_LORENZ_Z_MIN,
      max:     overrides[:max]     || family&.critical_z_max&.to_f || GLOBAL_LORENZ_Z_MAX,
      optimal: overrides[:optimal] || family&.effective_optimal_z_target || GLOBAL_LORENZ_Z_OPTIMAL
    }
  end

  # [FW.8] Пороги, за якими судить САМ ПРИСТРІЙ — друга роль, свідомо розведена з
  # `#effective_lorenz_thresholds` («що слати»). Єдиний споживач — категоричний
  # DCI (`TelemetryUnpackerService#check_z_divergence!`).
  #
  # 🔴 Чому це не те саме: пристрій рахує `bio_status` за ЗАШИТИМИ
  # `BioContract::CRITICAL_Z_MIN/MAX` — per-species значення до вердикту не
  # доходять жодним шляхом, тож сервер, який судив за ними, порівнював не два
  # обчислення, а дві КОНФІГУРАЦІЇ. Механізм, обидві половини розриву з
  # виміряними частотами, два рукави наслідку і ⚖️ ціна звуження — ОДИН дім,
  # `03_04 §5.3`; тут їх свідомо не дублюємо.
  #
  # Значення — дзеркало firmware-констант (`GLOBAL_LORENZ_Z_*`, той самий блок
  # угорі файлу). ⛔ Не «покращувати» його до per-species, доки прошивка їх
  # справді не читатиме: сьогодні це зробить DCI знову неправдивим.
  # Подія перегляду — bench-нога FW.8 (`FW8_PARSER_ENABLED 1` + HAL-глю) І
  # доставка порогів у сам mruby-контракт; доти тут чесна константа.
  def device_lorenz_thresholds
    { min: GLOBAL_LORENZ_Z_MIN, max: GLOBAL_LORENZ_Z_MAX, optimal: GLOBAL_LORENZ_Z_OPTIMAL }
  end

  private

  # [ВИПРАВЛЕНО: Broadcast Storm]: Визначаємо, чи зміна є релевантною для оновлення мапи.
  # Широкомовлення лише при зміні координат, статусу або latest_voltage_mv (іконка батареї).
  # Це скорочує кількість WebSocket-повідомлень з ~10K/годину до ~100/годину.
  # 🔴 [ARCH.84] Множина тригерів = множина КОЛОНОК, які маркер справді рендерить
  # (`Dashboard::MapNode`: lat · lng · status · stress). Доти вона розходилась з
  # payload'ом ОБАБІЧ, і обидві розбіжності тихі:
  #
  # (а) `latest_stress_index` тут НЕ БУЛО — тобто чесний колір стресу не
  #     оновлювався наживо ЖОДНОГО разу, і глядач із відкритим дашбордом бачив
  #     учорашній колір до повного перезавантаження;
  # (б) `latest_voltage_mv` БУВ — хоч [ARCH.99] прибрав `data-charge` з маркера,
  #     тож механізм, збудований саме щоб скоротити броадкасти (Broadcast Storm,
  #     ~10K→~100/год), перемальовував вузол на величину, якої більше не малює.
  #
  # ⚠️ Самої правки тут НЕ ДОСИТЬ: писачі стресу йдуть `update_column`/`update_all`,
  # які колбеків не пускають узагалі — тому `InsightGeneratorService` фаєрить
  # броадкаст ЯВНО. Дві причини були незалежні, і фікс однієї не дав би нічого.
  def map_relevant_change?
    saved_change_to_latitude? || saved_change_to_longitude? ||
      saved_change_to_status? || saved_change_to_latest_stress_index?
  end

  def build_default_wallet
    create_wallet!(balance: 0, organization: cluster&.organization)
  end

  def ensure_calibration
    create_device_calibration! unless device_calibration
  end

  # [SLASH-1] UTC-час переходу. Час береться UTC свідомо: читач порівнює його з
  # `AiInsight.reporting_date`, а той — UTC-доба; узяти `Time.zone` означало б
  # відтворити SLASH-1 («два різні моменти читання того самого якоря»), лише
  # координатою часового поясу.
  def stamp_status_changed_at
    self.status_changed_at = Time.current.utc
  end

  def trigger_slashing_protocol
    return unless cluster&.organization

    org_id = cluster.organization_id
    contract_ids = cluster.naas_contracts.active.pluck(:id)
    return if contract_ids.empty?

    # Bulk Slashing: один виклик Redis замість N окремих perform_async
    BurnCarbonTokensWorker.perform_bulk(
      contract_ids.map { |contract_id| [ org_id, contract_id, id ] }
    )

    Rails.logger.warn "🚨 [Ecosystem Breach] Дерево #{did} зафіксовано як #{status}. Сигнал на вилучення токенів відправлено."
  end

  # =========================================================================
  # COUNTER CACHE: active_trees_count на Cluster
  # =========================================================================

  def increment_cluster_active_trees_count
    Cluster.where(id: cluster_id).update_all("active_trees_count = active_trees_count + 1")
  end

  def decrement_cluster_active_trees_count
    Cluster.where(id: cluster_id).where("active_trees_count > 0").update_all("active_trees_count = active_trees_count - 1")
  end

  # Counter cache sync на cluster.active_trees_count. Покриває всі дельти:
  #   * status change (active ↔ dormant/removed/deceased) → swap counter same cluster
  #   * cluster change на active tree → decrement old, increment new
  #   * both change → decrement old, conditionally increment new
  #   * cluster: nil → A → increment A (after_create_commit handles initial set)
  # `saved_change_to_*` повертає `[before, after]` коли поле змінилось,
  # nil — якщо без змін. Прямо використовуємо before-значення замість
  # ручного fallback на `*_before_type_cast` (Rails enum віддавав би
  # integer там, де AASM/saved_change віддає string — старий шлях мав
  # подвійний `|| 0` workaround).
  def update_cluster_active_trees_count
    was_active =
      if saved_change_to_status?
        saved_change_to_status.first == "active"
      else
        active?
      end

    old_cluster_id =
      if saved_change_to_cluster_id?
        saved_change_to_cluster_id.first
      else
        cluster_id
      end

    # Декремент: дерево було активним і прив'язаним до кластера.
    if was_active && old_cluster_id
      Cluster
        .where(id: old_cluster_id)
        .where("active_trees_count > 0")
        .update_all("active_trees_count = active_trees_count - 1")
    end

    # Інкремент: дерево зараз активне і прив'язане до кластера.
    if active? && cluster_id
      Cluster
        .where(id: cluster_id)
        .update_all("active_trees_count = active_trees_count + 1")
    end
  end
end
