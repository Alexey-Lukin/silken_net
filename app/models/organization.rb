# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Organization < ApplicationRecord
  include EthAddressValidatable
  # [ARCH.57] Ротація епохи стрімів — привілейована дія того ж роду, що ротація
  # ключа (`HardwareKeyService`, уже в ланцюгу): вона знецінює видані токени й
  # перезавантажує кожного глядача організації. Слід обовʼязковий.
  include Auditable

  # --- ЗВ'ЯЗКИ (The Web of Responsibility) ---
  # [ВИПРАВЛЕНО: Захист Користувачів]:
  # Ми не видаляємо людей разом з організацією, щоб зберегти аудит-логи (MaintenanceRecords)
  has_many :users, dependent: :restrict_with_error

  # Фінансові контракти (Nature-as-a-Service)
  has_many :naas_contracts, dependent: :restrict_with_error

  # Лісові масиви, якими володіє або керує організація
  # [SEC.26/ARCH.76, ⚖️ 2026-07-30] `restrict_with_error`, а не `destroy` — інакше
  # присуд про незнищенність кластера відтворював би ARCH.76 на рівень вище: кластер із
  # залізом тепер відмовляє (`throw :abort` → `false`), але `destroy_all` у каскаді на
  # `false` НЕ реагує й іде далі, тож `DELETE` організації бився б об реальний FK
  # `clusters.organization_id` — сирий `ActiveRecord::InvalidForeignKey` повз усю
  # драбину `rescue_from`. Тобто це не «ще одне обмеження», а умова несуперечливості
  # каскаду. Узгоджено з рештою родини (`users` · `naas_contracts` · `audit_logs`).
  has_many :clusters, dependent: :restrict_with_error

  # [ARCH.57] Compliance-журнал переживає організацію: delete_all стирав
  # integrity-chain разом із Org (carbon-registry вимагає незнищенність).
  # Узгоджено з users/naas_contracts — Org з журналом не видаляється.
  has_many :audit_logs, dependent: :restrict_with_error

  # Прямий доступ до всіх дерев, шлюзів та тривог через кластери
  has_many :trees, through: :clusters
  has_many :gateways, through: :clusters
  has_many :ews_alerts, through: :clusters

  # ⚡ [ВИПРАВЛЕНО: The Join Abyss]: Пряма магістраль до фінансових ресурсів.
  # Денормалізований зв'язок через organization_id у wallets замість 4-рівневого JOIN
  # (Organization → Clusters → Trees → Wallets). Це критично для total_carbon_points.
  has_many :wallets, dependent: :nullify

  # Логотип організації (The Brain Map)
  #
  # Тип і розмір валідуються [SEC.27]: `logo` — єдине вкладення з живим
  # upload-шляхом (`settings_controller` кладе `:logo` у `permit`), тож без
  # цього будь-який org-admin клав би у сховище довільний блоб довільного
  # розміру. SVG свідомо поза allow-list: Rails віддає його `attachment`,
  # а не inline, але сам список тримаємо рівно з тих типів, які vips
  # обробляє як растр — логотипу вектор не потрібен, він іде через `url_for`
  # без variant'а.
  has_one_attached :logo
  validates :logo,
            content_type: { in: %w[image/jpeg image/png image/webp] },
            size: { less_than: 5.megabytes }

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :billing_email, with: ->(e) { e.strip.downcase }

  # [ВИПРАВЛЕНО: EIP-55 Checksum Preservation]:
  # Прибираємо downcase, щоб не зруйнувати контрольну суму гаманця для Web3-провайдерів
  normalizes :crypto_public_address, with: ->(a) { a.strip }

  # [UI.7] «Не обрано» приїжджає з форми порожнім РЯДКОМ, а `allow_nil` нижче
  # покриває лише `nil` — тож без цього рядка намір «скинути мову» був
  # невиразимий, і кожне збереження налаштувань організації без обраної локалі
  # давало 422. Колонка — звичайний varchar, тож типового касту blank→nil (як у
  # integer-enum'а чи numeric-поля) тут не відбувається ні на якому щаблі.
  normalizes :locale, with: ->(l) { l.presence }

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :billing_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Валідація гаманця для Web3 операцій (Polygon/Ethereum)
  # Тепер валідація дозволяє змішаний регістр (A-F)
  validates_eth_address :crypto_public_address, presence: true, uniqueness: true

  # [KYC.1] KYC чіпляється до АДРЕСИ-бенефіціара (custodial-мінт іде сюди, коли
  # wallet без власної адреси): зміна адреси = новий суб'єкт верифікації →
  # статус скидається у pending і верифікація йде заново (Hadron / dev-simulate).
  HADRON_KYC_STATUSES = %w[pending approved rejected].freeze
  validates :hadron_kyc_status, inclusion: { in: HADRON_KYC_STATUSES }

  before_update :reset_hadron_kyc_on_address_change
  after_commit :enqueue_hadron_kyc_verification, if: :saved_change_to_crypto_public_address?

  # Пороги тривоги та AI-чутливість (The Brain Map)
  validates :alert_threshold_critical_z, numericality: { greater_than: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :ai_sensitivity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  # --- Data Residency (Зона 4: GDPR/Sharding) ---
  SUPPORTED_DATA_REGIONS = %w[eu-west eu-central us-east us-west ap-southeast].freeze
  validates :data_region, inclusion: { in: SUPPORTED_DATA_REGIONS }, allow_nil: true

  # [I18N.1] Мова, якою організація отримує ПОШТУ. Це не дубль `users.locale`:
  # `AlertMailer` шле на `billing_email` — скриньку, за якою може не стояти
  # жоден User-запис, тож локаль користувача сюди не підходить у принципі.
  # `nil` = «не обрано» → базова локаль. Перелік деривується з єдиного дому.
  validates :locale, inclusion: { in: ->(_org) { I18n.available_locales.map(&:to_s) } }, allow_nil: true

  # --- БІЗНЕС-ЛОГІКА (Value Extraction) ---

  # Кешований лічильник дерев для масштабування (уникає повільного COUNT на мільйонах записів)
  def cached_trees_count
    Rails.cache.fetch("organization_#{id}_trees_count", expires_in: 1.hour) do
      trees.count
    end
  end

  # Дім ключа кешу прогнозу Оракула — і причина, чому дім, а не рядок на місці.
  # Ключ був рукописним у чотирьох місцях; коли tenant-isolation додав `_org_`,
  # переїхав лише той, що ЧИТАЄ, а три інвалідатори лишились на старому імені —
  # тобто скидали ключ, якого вже не існує, і застарілий прогноз переживав
  # критичну тривогу цілу годину. Скоупінг має ТРИ половини: запит, ключ і ті,
  # хто цей ключ скидає (`00_07` SEC.25; сиблінг SEC.16-бейджа).
  def self.expected_yield_cache_key(org_id) = "oracle_expected_yield_24h_org_#{org_id}"

  # Fail-closed на порожньому `org_id`. ⚠️ Обґрунтування переписано ⚖️ 2026-07-30: доти
  # тут стояло «дерево без кластера — звичайний стан (`dependent: :nullify`)», а каскад
  # став `restrict_with_error` і безкластерне дерево більше не є станом домену. No-op
  # лишається правильним, але з іншої причини — метод беруть і зі шляхів, де організація
  # легально невідома, і виняток там був би гучнішим за користь.
  def self.invalidate_expected_yield_cache(org_id)
    return if org_id.blank?

    Rails.cache.delete(expected_yield_cache_key(org_id))
  end

  # [SEC.25 Ф3] Стріми, які ротація гасить tombstone'ом — і `:map` тут ВІДСУТНІЙ
  # свідомо, це не пропуск.
  #
  # 🔴 `broadcast_refresh_to` у стрім мапи вбив би Leaflet у кожного ЧЕСНОГО
  # глядача дашборда. `DashboardLayout` вмикає morph глобально, а
  # `#geospatial_map_canvas` навмисно без `data-turbo-permanent` (той атрибут
  # пробували й зняли — див. `dashboard/map.rb`). Морф лишає сам вузол на місці,
  # але зносить його дітей, яких немає в серверному HTML, — тобто панелі Leaflet;
  # `disconnect()` при цьому НЕ спрацьовує (вузол не видалявся), тож
  # `map_controller` не переініціалізується ніколи, і мапа лишається сірим
  # прямокутником до жорсткого перезавантаження.
  # 🔴 [UI.11, 2026-08-17] ЦЯ ПІДСТАВА БІЛЬШЕ НЕ ЧИННА, і рядок лишається саме
  # тому, що виключення чинне з ІНШИХ причин. Полотно тепер оголошує себе
  # непрозорим для морфу (`turbo:before-morph-element` + `preventDefault()` у
  # `map_controller#connect`), тож морф його НЕ зносить — виміряно браузером
  # (7 панелей до і після; носій — `dashboard_browser_smoke_spec`). Отже
  # аргумент «морф вбив би Leaflet» відпав, а виключення `:map` тримається на
  # тому, що НИЖЧЕ. **Повернення `:map` у `TOMBSTONE_KINDS` — рішення SEC.25,
  # не наслідок цього фіксу; сюди його не приймали.**
  # Дашборд refresh-сигналів не отримує за всю історію репо, і ротація не має
  # ставати першим.
  #
  # Наслідок, названий чесно: після bump'а відкритий дашборд перестає діставати
  # живі вузли мапи мовчки, до наступної навігації. Відкликання це не послаблює
  # (стара адреса мертва для продюсерів однаково) — страждає лише живість.
  # [UI.11] Дім ключа кешу бейджа тривог — ОДИН, бо його читає сайдбар
  # (`BaseController#ews_alert_count_cached`), а гасить модель
  # (`EwsAlert#bust_org_alert_count_cache`). Два рукописні рядки розійшлися б
  # мовчки: бейдж просто лишався б застарілим, і жоден гейт цього не бачить —
  # застарілий кеш не є помилкою.
  def alert_count_cache_key = "ews_alert_count_unresolved/org/#{id}"

  TOMBSTONE_KINDS = %i[telemetry alerts].freeze

  # [SEC.25 Ф3] Відкликати всі раніше видані імена стрімів організації.
  #
  # Ручний ops-важіль: автоматичного тригера немає й не вигадується. Членство в
  # цьому дереві незмінне (шляху, що міняв би `users.organization_id`, не існує),
  # тож єдиний реальний привід — підозра на злив підписаного імені. Перемикання
  # контексту адміном сюди НЕ входить: воно перезавантажило б усю організацію
  # заради гігієни одного глядача (`04_03 §3.1`).
  #
  # Порядок несучий: спершу bump, потім tombstone. Навпаки — і релоуд відрендерив
  # би ще СТАРУ епоху, тобто глядач осів би на адресі, яку ми щойно кинули.
  def rotate_stream_epoch!
    previous = stream_epoch
    increment!(:stream_epoch)
    broadcast_stream_tombstone!(previous)
    record_audit_trail!(
      action: "stream_epoch_rotated",
      organization_id: id,
      metadata: { from: previous, to: stream_epoch }
    )
    stream_epoch
  end

  # Штовхнути ПОПЕРЕДНЮ адресу на перезавантаження. Окремий публічний метод, а не
  # приватний хвіст ротації, і причина не стилістична: tombstone доїжджає лише до
  # ПІДКЛЮЧЕНИХ у ту мить сокетів. Solid Cable ставить точку приєднання нової
  # підписки на поточний максимум (`add_channel`), тож backlog не реплеїться —
  # вкладка, що спала під час bump'а, після реконекту ре-підпишеться на мертве
  # імʼя з ще не перезавантаженого DOM і виглядатиме `connected`, будучи глухою.
  # Отже повторний виклик — не crash-recovery, а штатна дія оператора, і вона
  # мусить мати ІМʼЯ, а не жити інструкцією в коментарі.
  #
  # Ідемпотентний: refresh не несе payload, тож зайвий сигнал коштує релоуду, а
  # не розходження стану.
  def broadcast_stream_tombstone!(epoch)
    TOMBSTONE_KINDS.each do |kind|
      Turbo::StreamsChannel.broadcast_refresh_to(TurboStreams::Name.org_at(kind, id, epoch))
    end
  end

  # Кількість кластерів організації.
  # 🔴 `.size`, а не `.count`: обидва дають те саме число, але `.count` шле SQL
  # ЗАВЖДИ — навіть коли асоціація вже завантажена через `includes`. У реєстрі
  # кланів це рядок-у-циклі, тож поруч стояв дбайливий `.includes(:clusters)`,
  # який не діяв, і preload лише додавав запит. `.size` бере завантажений масив.
  def total_clusters
    clusters.size
  end

  # Загальна законтрактована сума за всіма контрактами.
  # Та сама пара, що вище: `sum(:колонка)` — це SQL-агрегат повз preload,
  # блокова форма підсумовує вже завантажені записи. `.to_f` поелементно, бо
  # `total_funding` nullable, і на голому `&:` порожня сума впала б на `nil`.
  def total_contracted
    naas_contracts.sum { |contract| contract.total_funding.to_f }
  end

  # Загальний обсяг фінансування за активними контрактами
  def active_tokens_count
    naas_contracts.active.sum(:total_funding)
  end

  # Загальний вуглецевий баланс організації (сума всіх гаманців дерев)
  # [ОПТИМІЗАЦІЯ]: Використовуємо прямий зв'язок (один SELECT замість 4-рівневого JOIN)
  def total_carbon_points
    wallets.sum(:balance)
  end

  # Перевірка наявності активних загроз через скоуп EwsAlert
  def under_threat?
    ews_alerts.unresolved.critical.exists?
  end

  # [ОПТИМІЗАЦІЯ: N+1 Kill]: Агрегований показник здоров'я всього фонду організації
  # health_index — денормалізована колонка в clusters, оновлюється ClusterHealthCheckWorker
  # раз на добу після звіту Оракула. Тому AVG виконується на кешованих значеннях.
  #
  # [ARCH.84] Обчислення живе в One-Home `Cluster.health_coverage`; тут лишається
  # доменне ім'я. ⚠️ Доти цей метод мав ДВА взаємовиключні дефолти на дві форми
  # «нічого»: `return 1.0 if clusters.empty?` (нема чого міряти → ідеально) і
  # `nil.to_f` на всіх-NULL (не змогли виміряти → **0.0**, тобто мертвий ліс).
  # Обидва вигадані, і призначені задом наперед.
  def health_coverage
    Cluster.health_coverage(clusters)
  end

  # `nil` = міряти або нема чого, або не вийшло; що саме — питай `health_coverage`.
  # Два знаки — власна подача цього методу, не властивість дому обчислення.
  def health_score
    health_coverage.average&.round(2)
  end

  private

  # [KYC.1] Явний одночасний сет статусу (verify-воркер / seeds) має пріоритет.
  def reset_hadron_kyc_on_address_change
    return unless will_save_change_to_crypto_public_address?
    return if will_save_change_to_hadron_kyc_status?

    self.hadron_kyc_status = "pending"
  end

  def enqueue_hadron_kyc_verification
    HadronKycVerificationWorker.perform_async("Organization", id)
  end
end
