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

    update!(attested_by_id: actor.id, attested_at: Time.current)
  end

  def attested?
    attested_by_id.present?
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
end
