# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Cluster < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :organization

  # [SEC.26/ARCH.76] `restrict_with_error`, а НЕ `nullify` — і підстава тут не «щоб діти
  # не осиротіли», а те, чим `clusters.id` насправді є: **фабрично-заморожена координата
  # юніта**. Він служить HKDF-salt для `K_ota` і `KEYB`, прошитих у кремній і незмінних
  # після RDP-lock (епохи в salt немає, тож «ротація кластерного ключа» без зміни master
  # неможлива в принципі), і водночас координатою історичних MRV-груп — Merkle-субкорені
  # групуються по ПОТОЧНОМУ `trees.cluster_id`, тож занулення зробило б `unprovable` всі
  # минулі якорі групи. Головний потерпілий від знищення рядка — не дерева, а ПРУФ і КЛЮЧ.
  #
  # Тенансі · контракт · крипто-домен · MRV-група — не чотири сутності, а чотири проєкції
  # ЦІЄЇ координати в різні моменти часу (зараз · строк дії · фабрика · момент якоря).
  #
  # ⚠️ `nullify` тут ніколи не був рішенням: він прийшов першим bulk-скафолдом, а для
  # `:gateways` був фізично невиконуваним (`gateways.cluster_id NOT NULL` → каскад мав
  # єдиний можливий вихід — `PG::NotNullViolation`). Осиротілий вузол не має екстенсіоналу:
  # заведення вимагає кластер КРИПТОГРАФІЧНО (без нього не деривується `K_ota`),
  # `decommission!`/`declare_deceased!` міняють лише AASM-статус, а «перемістити дерево в
  # інший кластер» не існує як software-операція й існувати не може — канон це робить
  # парою «decommission старого юніта + factory-provision нового з новим DID».
  has_many :trees, dependent: :restrict_with_error
  has_many :gateways, dependent: :restrict_with_error
  has_many :actuators, through: :gateways

  # [ВИПРАВЛЕНО]: Захист Фінансової Історії (Immutable Audit Trail).
  # Кластер неможливо видалити, поки в ньому є діючі NaaS-контракти чи страховки.
  # Це критично для Web3-звітності та довіри інвесторів.
  has_many :naas_contracts, dependent: :restrict_with_error
  has_many :parametric_insurances, dependent: :restrict_with_error

  # [ARCH.76] `blockchain_transactions.cluster_id` МАЄ справжній DB-FK
  # (`fk_blockchain_transactions_cluster_id`), але асоціації тут не було — тож
  # Rails не мав куди поставити `restrict`, і знищення кластера з грошовим
  # аудит-записом падало сирим `PG::ForeignKeyViolation` ПОВЗ усю драбину
  # `rescue_from`. Клас гірший за відсутній `dependent:`: той видно при читанні
  # `has_many`, цей — ні, бо декларації просто немає.
  # ⚠️ Сценарій не гіпотетичний: слеш «останнього дерева» і Celo-винагорода
  # пишуть рядок саме з `wallet: nil, cluster: …` ЗА ДИЗАЙНОМ ([ARCH.98]).
  has_many :blockchain_transactions, dependent: :restrict_with_error

  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для масових таблиць,
  # щоб уникнути OOM при видаленні кластера з мільйонами тривог та інсайтів.
  has_many :ews_alerts, dependent: :delete_all
  # Поліморфні прогнози та підсумки (Daily Health Summary)
  has_many :ai_insights, as: :analyzable, dependent: :delete_all

  # --- JSONB SETTINGS (The Biome Adaptation) ---
  # ⚠️ Ключі тут НЕ рівноцінні за живістю, і різницю видно лише звідси: `custom_fire_threshold`
  # читає `AlertDispatchService` (перша ланка `fire_limit`), `timezone` — добовий шар,
  # `lorenz_overrides_by_species` — [FW.8]; а ⛔ `seismic_sensitivity_threshold` не читає НІХТО
  # [ARCH.102] — сейсмічний вердикт знято разом із його вимірювачем. Лишається оголошеним
  # forward-контрактом (валідація й рендер чинні на випадок, коли ключ таки виставлять руками),
  # але сід його більше не заповнює: показувати чутливість неіснуючого детектора = фабрикація.
  store_accessor :environmental_settings,
                 :custom_fire_threshold,
                 :seismic_sensitivity_threshold,
                 :timezone,
                 :lorenz_overrides_by_species

  # --- ВАЛІДАЦІЇ ТА НОРМАЛІЗАЦІЯ ---
  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  validates :custom_fire_threshold, :seismic_sensitivity_threshold,
            numericality: { greater_than: 0 }, allow_nil: true

  # [FW.8] Per-species Lorenz threshold overrides for this cluster.
  # Schema: { "<scientific_name>" => { "min" => Float, "max" => Float, "optimal" => Float } }
  # A cluster may host trees of several species; each species gets its own
  # biome-adjusted overrides. Unspecified keys fall through to TreeFamily defaults.
  # Governance flow: organization-scoped admin sets overrides per species.
  validate :validate_lorenz_overrides_by_species

  normalizes :geojson_polygon, with: ->(json) { json.is_a?(Hash) ? json.deep_stringify_keys : json }

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }

  # PostGIS: знайти кластери, що містять точку (lat, lng)
  # Використовує GIST індекс — O(log n) замість O(n) JSONB-сканування
  scope :containing_point, ->(lat, lng) {
    where("ST_Contains(geo_boundary, ST_SetSRID(ST_MakePoint(?, ?), 4326))", lng.to_f, lat.to_f)
  }

  # [СИНХРОНІЗОВАНО]: Використовуємо статус :active, що відповідає скоупу unresolved в EwsAlert.
  scope :under_threat, -> {
    joins(:ews_alerts).where(ews_alerts: { status: :active, severity: :critical }).distinct
  }

  # --- МЕТОДИ (Sector Intelligence) ---

  # PostGIS: перевірка, чи точка знаходиться в межах кластера
  def contains_point?(lat, lng)
    return false unless geo_boundary_present?

    self.class.where(id: id).containing_point(lat, lng).exists?
  end

  # Чи є geometry-колонка заповнена?
  def geo_boundary_present?
    self.class.where(id: id).where.not(geo_boundary: nil).exists?
  end

  # [ОПТИМІЗАЦІЯ: Counter Cache]: Використовуємо денормалізований лічильник замість COUNT(*).
  # При 50 кластерах × 100 000+ дерев на дашборді — це різниця між 50 SQL-запитами і нулем.
  # Лічильник оновлюється через колбеки в Tree при зміні статусу або переміщенні між кластерами.
  def total_active_trees
    active_trees_count
  end

  def mapped?
    geojson_polygon.present? && geojson_polygon["coordinates"].present?
  end

  # [ARCH.84] Ридера-підстановки тут БІЛЬШЕ НЕМАЄ — `health_index` віддає сиру колонку,
  # і `nil` означає «не виміряно», окремий стан поряд із будь-яким виміряним числом.
  #
  # 🔴 Підстава герметична й не потребує міркувань про напрямок fail-safe: `1.0` —
  # ДОСЯЖНЕ ВИМІРЯНЕ значення (`stress_index == 0` → `1.0 - 0 = 1.0`, пін
  # `spec/models/cluster_spec.rb`). Доти воно ж підставлялось на порожнечу, тобто два
  # РІЗНІ факти — «бездоганний ліс» і «ми його не міряли» — були одним числом, і
  # жоден споживач не міг їх розрізнити.
  #
  # ⚠️ Колонка не знає, ЯКУ добу описує: `ClusterHealthCheckWorker` приймає довільну
  # дату, тож значення = «результат останнього прогону з тією датою, яку той узяв».
  # Прецедент форми — `ARCH.81` (`not_configured` ⊥ `unreachable`): булеве/скалярне
  # поле не вміє виразити «не знаю», тож стан робиться першокласним, а не дефолтом.
  #
  # ⛔ Предиката `health_measured?` тут свідомо НЕМА, і це не забудькуватість.
  # Вʼю мусить питати ЗНАЧЕННЯ, яке вже тримає в руках, а не дериват на моделі:
  # компонентні фікстури тут — `OpenStruct`, тож модельний предикат повертав би їм
  # `nil`, і ВИМІРЯНИЙ кластер рендерився б як невиміряний при зеленій спеці
  # (`04_06 §B.2` BP #14, сьома вісь: «мок правильний по імені, сліпий по деривації»).
  # Дім появи стану — `ApplicationComponent#measured_percent`, і він бере значення.

  # [ARCH.100] `local_yesterday` тут БІЛЬШЕ НЕМАЄ — і це не спрощення, а лік.
  # Він брав «вчора» в поясі кластера, тоді як інсайт, який усі ці читачі шукають,
  # штампується UTC-добою агрегатора. Для поясів західніше UTC−2 дати не збігались
  # НІКОЛИ, тож нічний крон читав порожню добу й видавав на неї вироки. Дім якоря —
  # `AiInsight.reporting_date`; `environmental_settings["timezone"]` лишається
  # операторськими даними, чий споживач з'явиться разом із per-tenant агрегацією.

  # [ARCH.84] Дім АГРЕГОВАНОГО здоровʼя — один на всі поверхні. Доти «середнє здоровʼя
  # кластерів» стояло ЧОТИРМА незалежними реалізаціями з ДВОМА протилежними дефолтами
  # на одну й ту саму порожнечу: `Organization#health_score` і `DashboardController`
  # віддавали **0.0** (через `nil.to_f`), а обидва методи `ContractsController` — **1.0**.
  #
  # 🔴 Повертаємо ПОКРИТТЯ, а не голе число, і це не оздоба: стан «виміряно частину»
  # створює сама відмова від підстановки. Доти NULL-ів у стійкому стані не бувало (писач
  # їх забивав), тож `AVG`, що мовчки пропускає NULL, нікому не брехав. Тепер один
  # виміряний кластер із ста дасть чесне число про ОДИН і подасть його як твердження про
  # СТО — тобто вердикт без підстави поруч. Місія проєкту зве це прямо: «правдиво ·
  # **невідбирано** · відтворювано» (`00_01 §1.1`), а мовчазний відкид невиміряних і є
  # відбір. Тому `measured`/`total` їдуть разом зі значенням, а вʼю зобовʼязана їх показати.
  #
  # ⚠️ Один запит: `COUNT(колонка)` рахує лише не-NULL, `COUNT(*)` — усі рядки, тож
  # дискримінатор уже є в SQL і другого звертання не потребує.
  HealthCoverage = Struct.new(:average, :measured, :total, keyword_init: true) do
    # «Нема чого міряти» — структурний стан, НЕ те саме, що «міряли й не вийшло».
    def no_clusters?
      total.zero?
    end

    def unmeasured?
      total.positive? && measured.zero?
    end

    def partial?
      measured.positive? && measured < total
    end
  end

  def self.health_coverage(scope = all)
    row = scope.pick(Arel.sql("AVG(clusters.health_index), COUNT(clusters.health_index), COUNT(*)"))

    # ⚠️ Середнє віддаємо СИРИМ: округлення — подача, і в кожного споживача вона своя
    # (картка портфеля показує один знак після коми, `Organization#health_score` — два).
    # Округливши тут, дім тихо зрізав би точність, якої в'ю ще потребує: спіймано
    # прикладом «87.3%», що перетворився на «87.0%».
    HealthCoverage.new(
      average: row[0]&.to_f,
      measured: row[1].to_i,
      total: row[2].to_i
    )
  end

  # Перерахунок health_index на основі даних ШІ (використовується у ClusterHealthCheckWorker)
  # $$V = 1.0 - S$$ де $S$ - stress_index з добового звіту ШІ
  #
  # [ARCH.84] Без інсайту пишемо ЯВНИЙ `nil` — «не виміряно», а не вигадане число.
  # ⛔ І це НЕ форма сусіда `ClusterEntropyAnalyzerWorker` (`return if score.nil?`):
  # той ПРОПУСКАЄ запис, тобто лишає стояти вчорашнє значення. Тут так не можна —
  # цю колонку переписує щонічний `Cluster.find_each`, тож пропуск давав би
  # понеділковий 0.42 на вівторковій темряві: підміна виміру, лише постаріла, і
  # тим небезпечніша, що правдоподібна. (Сам entropy — третій інстанс цього класу,
  # не взірець: його коментар «аналогічно health_index» видає, звідки він списаний.)
  # 🔴 [ARCH.84] Гард питає САМ ВИМІР, а не наявність інсайту — бо `stress_index`
  # легально `NULL` (`allow_nil: true` + nullable-колонка), і `nil.to_f` дав би рівно
  # `1.0`, тобто «бездоганний ліс» для стресу, якого ніхто не рахував. Доти клас
  # тримали ТРИ збіги, жоден із них не правило: кластерний писач коерсить середнє
  # через `.to_f`, порожню множину відсікає власний `return`, а рядок із `NULL` у
  # сідах має інший `insight_type` і не проходить скоуп. Перший писач, що створить
  # `daily_health_summary` без виміру, робить фабрикацію живою.
  # ⊥ Несуче саме тут, а не деінде: `Cluster.health_coverage` рахує виміряність як
  # `COUNT(health_index)`, тож підставлена одиниця пройшла б як ВИМІРЯНА — механізм
  # чесності, збудований проти цього класу, годувався б ним же.
  # ⚠️ `0.0` при цьому лишається ЗАКОННИМ входом (пін «returns 1.0 when stress_index
  # is 0» стоїть роками), тож дискримінатор — `nil`, ніколи `.zero?`/`present?`.
  def recalculate_health_index!(target_date = AiInsight.reporting_date)
    insight = ai_insights.daily_health_summary.for_date(target_date).first
    stress = insight&.stress_index
    new_value = stress ? (1.0 - stress.to_f).round(2) : nil
    update_column(:health_index, new_value)
    new_value
  end

  # Чи є критичні загрози в секторі?
  def active_threats?
    # [СИНХРОНІЗОВАНО]: Тепер назва скоупу збігається з логікою EwsAlert
    # [UI.3 08-20] `.critical` уже містить `.unresolved` (дім скоупа) — дубль умови
    # давав `status = 0 AND status = 0` у SQL.
    ews_alerts.critical.exists?
  end

  # [ВИПРАВЛЕНО]: Глибина GeoJSON (Resilient Centroid).
  # Тепер метод збирає всі пари координат незалежно від того, чи це Polygon, чи MultiPolygon.
  # [ОПТИМІЗАЦІЯ]: Мемоізація результату — при повторних викликах (UI-карта, EwsAlert#coordinates)
  # обробка масиву координат не повторюється.
  def geo_center
    return @geo_center if defined?(@geo_center)

    @geo_center = compute_geo_center
  end

  # [ВИПРАВЛЕНО: Детермінованість]: Гарантуємо порядок для фінансових звітів.
  # PostgreSQL не гарантує порядок без ORDER BY — .first може повернути різні результати
  # в різних середовищах. Завжди отримуємо найновіший активний контракт.
  def active_contract
    naas_contracts.active.order(created_at: :desc).first
  end

  # [FW.8] Per-species Lorenz overrides for trees of `scientific_name` in this cluster.
  # Returns Hash{ min:, max:, optimal: } with Float-or-nil values. Used by
  # Tree#effective_lorenz_thresholds to override TreeFamily defaults for a specific
  # biome (e.g., subarctic Pinus needs different bounds than Mediterranean Pinus).
  # Returns all-nil hash if no override is configured for that species.
  def lorenz_overrides_for(scientific_name)
    overrides = lorenz_overrides_by_species.is_a?(Hash) ? lorenz_overrides_by_species[scientific_name.to_s] : nil
    overrides = {} unless overrides.is_a?(Hash)

    {
      min:     numeric_or_nil(overrides["min"]),
      max:     numeric_or_nil(overrides["max"]),
      optimal: numeric_or_nil(overrides["optimal"])
    }
  end

  private

  def numeric_or_nil(value)
    return nil if value.nil?
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  # [FW.8] Validate per-species Lorenz overrides JSONB shape:
  #   - top-level value must be a Hash
  #   - keys must be non-empty Strings (scientific names)
  #   - per-species value must be a Hash with optional numeric min/max/optimal
  #   - if min and max are both set, min < max
  #   - if optimal is set, it lies between min and max (using each present bound)
  def validate_lorenz_overrides_by_species
    raw = lorenz_overrides_by_species
    return if raw.nil?

    unless raw.is_a?(Hash)
      errors.add(:lorenz_overrides_by_species, "must be a Hash keyed by scientific_name")
      return
    end

    raw.each do |species, bounds|
      if species.to_s.strip.empty?
        errors.add(:lorenz_overrides_by_species, "has a blank species key")
        next
      end
      unless bounds.is_a?(Hash)
        errors.add(:lorenz_overrides_by_species, "value for '#{species}' must be a Hash")
        next
      end

      min = numeric_or_nil(bounds["min"])
      max = numeric_or_nil(bounds["max"])
      optimal = numeric_or_nil(bounds["optimal"])

      bounds.each_key do |k|
        unless %w[min max optimal].include?(k.to_s)
          errors.add(:lorenz_overrides_by_species, "unknown key '#{k}' for species '#{species}'")
        end
      end

      %w[min max optimal].each do |k|
        next if bounds[k].nil?
        if numeric_or_nil(bounds[k]).nil?
          errors.add(:lorenz_overrides_by_species, "'#{k}' for species '#{species}' must be numeric")
        end
      end

      if min && max && min >= max
        errors.add(:lorenz_overrides_by_species, "'min' must be < 'max' for species '#{species}'")
      end
      if optimal && min && optimal <= min
        errors.add(:lorenz_overrides_by_species, "'optimal' must be > 'min' for species '#{species}'")
      end
      if optimal && max && optimal >= max
        errors.add(:lorenz_overrides_by_species, "'optimal' must be < 'max' for species '#{species}'")
      end
    end
  end

  public

  def compute_geo_center
    return nil unless mapped?

    # Повністю розгортаємо масив і групуємо по два значення (lng, lat)
    # Це імунітет до MultiPolygon, де вкладеність масивів глибша.
    all_points = geojson_polygon["coordinates"].flatten.each_slice(2).to_a
    return nil if all_points.empty?

    avg_lat = all_points.map(&:last).sum / all_points.size
    avg_lng = all_points.map(&:first).sum / all_points.size

    { lat: avg_lat, lng: avg_lng }
  end

  private :compute_geo_center
end
