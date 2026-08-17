# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AiInsight < ApplicationRecord
  # [ARCH.46] Поріг stress_index, за якого дерево рахується критично стресованим на SLASH-шляху —
  # спільний для ТРИГЕРА (ContractHealthCheckService: >20% дерев ≥ цього) і РОЗМІРУ
  # (BlockchainBurningService#calculate_damage_ratio: damage = частка дерев ≥ цього). ⚠️ Інваріант
  # «тригер ≡ розмір» несе МЕТОД нижче, а не ця константа: константа = лише default-fallback, і
  # доки damage читав саме її, DAO-голос за `:stress_threshold` тихо розводив половини (два баги
  # поспіль на цьому місці: спершу тригер 0.83 vs damage 1.0 → 100% over-burn, потім метод vs
  # константа). Правило: обидва споживачі читають МЕТОД; константу чіпає лише `default:`.
  # Канон-дім порога — 05_06 STRESS_THRESHOLD + 05_05 §3/§7. ⚠️ НЕ плутати з `critical_stress`-scope /
  # `contract_breach?` (0.8 — ширший insurance/UI-концепт, свідомо окремий від slash-порога).
  SLASH_STRESS_THRESHOLD = 0.83

  # [GOV.1] DAO-live поріг: SystemParameter(:stress_threshold) ← ProtocolParameters.sol
  # (bounds 0.5..1.0 у ParameterSyncWorker). Обидва споживачі (тригер ContractHealthCheckService
  # + damage-сайзинг BlockchainBurningService, ARCH.46) читають ЦЕЙ метод — спільність збережена.
  def self.slash_stress_threshold
    SystemParameter.current(:stress_threshold, default: SLASH_STRESS_THRESHOLD).to_f
  end

  # [ARCH.100] Дім ДОБИ ЗВІТУ — одна доба, один вираз, обабіч запису й читання.
  # Денний інсайт є агрегатом UTC-доби (`InsightGeneratorService` ріже вікно телеметрії
  # в UTC і штампує нею `target_date`), а `for_date` шукає ТОЧНОЮ рівністю — тож писач і
  # читач не мають права називати цю добу різними виразами.
  #
  # ⚠️ Доти якорів було ДВА, і другий не міг збігтися з першим за побудовою:
  # `Cluster#local_yesterday` брав «вчора» в поясі орендаря й стояв дефолтом у шести
  # вердикт-несучих сайтах. Для будь-якого поясу західніше UTC−2 (уся Америка від
  # Сан-Паулу) о 02:00 UTC ці дати не збігаються НІКОЛИ, тож нічний крон читав порожню
  # добу — і та сама вигадана порожнеча роз'їжджалась чотирма вироками протилежного
  # знаку: `health_index = 1.0` («ідеально здоровий»), `:blackout` → Field Audit і
  # невиплачена Celo-винагорода, страховий no-data → Field Audit, `:frozen` на слешингу.
  #
  # ⛔ Не рахуй цю дату на місці. Per-tenant доба стане правдою лише тоді, коли
  # per-tenant стане САМ агрегатор — і тоді зміниться цей метод, а не його читачі.
  def self.reporting_date(now = Time.current)
    now.utc.to_date - 1
  end

  # --- ЗВ'ЯЗКИ ---
  # Прогноз/Звіт може стосуватися Cluster (Кластер), Tree (Дерево) або Organization
  belongs_to :analyzable, polymorphic: true

  # --- ТИПИ ІНСАЙТІВ (Ретроспектива та Прогноз) ---
  enum :insight_type, {
    daily_health_summary: 0,  # [РЕАЛЬНІСТЬ]: Вчорашній звіт (база для D-MRV)
    drought_probability: 1,   # [ПРОГНОЗ]: Ймовірність посухи
    carbon_yield_forecast: 2, # [ПРОГНОЗ]: Емісія токенів
    biodiversity_trend: 3     # [ПРОГНОЗ]: Стабільність Атрактора Лоренца
  }

  # [I18N.1] Людська назва РОДУ інсайту — дзеркало `User::ROLE_LABEL_SCOPE`.
  # Скоуп належить домену МОДЕЛІ, не компоненту (`04_04 §12.14`).
  INSIGHT_TYPE_LABEL_SCOPE = "oracle_visions.insight_types"

  # ОДНА деривація ключа. Fail-open: новий член enum'а рендериться сирим значенням,
  # доки мітка не доїде в локалі — і саме це червонить гейт парності.
  def self.insight_type_label(insight_type)
    value = insight_type.to_s
    I18n.t("#{INSIGHT_TYPE_LABEL_SCOPE}.#{value}", default: value)
  end

  def insight_type_label
    self.class.insight_type_label(insight_type)
  end

  # --- СТРУКТУРОВАНІ ДАНІ (The Reasoning Engine) ---
  # Використовуємо JSONB для гнучкого пояснення логіки ШІ
  # fraud_detected винесено в окрему boolean колонку для коректної типізації та швидкого пошуку
  store_accessor :reasoning, :avg_z, :max_temp, :anomaly_vector, :avg_vcap, :deviation_from_baseline
  # [ARCH.84] Покриття КЛАСТЕРНОГО агрегату — скільки живих дерев сектора реально
  # заговорило за цю добу. Без нього `stress_index` кластера з одним виміряним
  # деревом із пʼяти невідрізнимий від виміряного повністю на КОЖНОМУ машинному
  # читачі (`health_index` → комерційний `backing_asset.cluster_health`, Celo-виплата,
  # IPFS-доказ), а дискримінатор жив лише в прозі `summary`. Дзеркало
  # `Cluster.health_coverage` поверхом вище й `measurement_coverage` у в'ю.
  # ⚠️ На TREE-рядку обидва `nil` за побудовою — там пара безпредметна (дерево не
  # агрегат), і `nil` тут значить саме це, а не «не порахували».
  store_accessor :reasoning, :measured_trees, :total_trees
  store_accessor :recommendation, :action_required, :priority

  # --- ВАЛІДАЦІЇ ---
  validates :insight_type, :target_date, presence: true

  # Унікальність: Один звіт про здоров'я на об'єкт на день на джерело (Oracle Consensus)
  validates :target_date, uniqueness: {
    scope: [ :analyzable_id, :analyzable_type, :insight_type, :model_source ],
    message: "вже зафіксовано для цього об'єкта"
  }, if: :daily_health_summary?

  validates :probability_score, numericality: { in: 0.0..100.0 }, allow_nil: true
  validates :stress_index, numericality: { in: 0.0..1.0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :highly_probable, -> { where("probability_score > ?", 80.0) }
  scope :upcoming, -> { where("target_date >= ?", Time.current.utc.to_date) }
  scope :critical_stress, -> { daily_health_summary.where("stress_index >= ?", 0.8) }
  scope :for_date, ->(date) { where(target_date: date) }
  scope :fraudulent, -> { where(fraud_detected: true) }

  # Evidence Persistence: знайти інсайти, що посилаються на конкретний telemetry log
  scope :referencing_log, ->(log_id) { where("source_log_ids @> ARRAY[?]::bigint[]", log_id.to_i) }

  # [SEC.26] Тенант-скоуп: `ai_insights` не має ані `organization_id`, ані `cluster_id`
  # — належність виводиться ЛИШЕ через поліморфний `analyzable`, і гілок рівно три
  # (Cluster організації · Tree в її кластерах · сама Organization). Тому це scope на
  # моделі, а не `where` у контролері: два рукописи одного 3-гілкового OR розійшлися б
  # мовчки — зайва гілка = крос-тенант, забута = зникла ціль, і жоден тест не червоніє.
  # ⚠️ Живий споживач сьогодні ОДИН (`OracleVisionsController#index`), і форма
  # лишається модельною свідомо: вона про ЦІНУ помилки в цьому OR, а не про
  # кількість читачів.
  scope :for_organization, ->(org) {
    cluster_ids = org.clusters.select(:id)

    where(
      "(analyzable_type = 'Cluster' AND analyzable_id IN (?)) OR " \
      "(analyzable_type = 'Tree' AND analyzable_id IN (?)) OR " \
      "(analyzable_type = 'Organization' AND analyzable_id = ?)",
      cluster_ids, Tree.where(cluster_id: cluster_ids).select(:id), org.id
    )
  }

  # Full-text search in reasoning JSONB (uses tsvector GIN index).
  # The idx_ai_insights_reasoning_gin (plain JSONB GIN) only supports @> containment.
  # This scope uses the dedicated tsvector GIN index idx_ai_insights_reasoning_fts
  # for actual word-level text search on reasoning->>'description'.
  scope :search_reasoning, ->(query) {
    where(
      "to_tsvector('simple', COALESCE(reasoning->>'description', '')) @@ plainto_tsquery('simple', ?)",
      query.to_s
    )
  }

  # --- МЕТОДИ (The Lens of Truth) ---

  # Чи вважається цей стан порушенням умов контракту?
  # Використовується в Slashing Protocol
  # Порівнюємо decimal напряму — без .to_f, щоб уникнути похибки плаваючої коми
  def contract_breach?
    daily_health_summary? && stress_index.present? && stress_index >= BigDecimal("0.8")
  end

  # Візуалізація впевненості для Патрульного
  def confidence_level
    return :n_a unless probability_score

    case probability_score
    when 0.0...40.0 then :low
    when 40.0...75.0 then :medium
    else :high
    end
  end

  def forecast?
    !daily_health_summary?
  end

  # Evidence Persistence: telemetry logs, що стали підставою для цього інсайту
  # source_log_ids зберігає integer ID (перший елемент composite key партиціонованої таблиці)
  def source_logs
    return TelemetryLog.none if source_log_ids.blank?

    TelemetryLog.where(id: source_log_ids)
  end

  # Прив'язати telemetry logs як докази для інсайту
  def attach_evidence!(log_ids)
    update!(source_log_ids: (source_log_ids + Array(log_ids)).uniq)
  end
end
