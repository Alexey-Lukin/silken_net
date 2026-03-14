# frozen_string_literal: true

require "securerandom"

puts "🔥 Очищення старого світу (Кенозис)..."
# Порядок враховує залежності (Foreign Keys) — від листя до кореня
[
  AuditLog, Session, Identity,
  ActuatorCommand, MaintenanceRecord,
  BlockchainTransaction, TelemetryLog, GatewayTelemetryLog, AiInsight, EwsAlert,
  Wallet, DeviceCalibration,
  Actuator, HardwareKey,
  Tree, TinyMlModel, TreeFamily,
  Gateway,
  ParametricInsurance, NaasContract,
  BioContractFirmware,
  Cluster, User, Organization
].each do |model|
  model.delete_all if ActiveRecord::Base.connection.table_exists?(model.table_name)
end

puts "🌍 Формування нового ландшафту..."

# =========================================================================
# 1. МАКРОЕКОНОМІКА ТА ЛЮДИ
# =========================================================================
active_bridge = Organization.create!(
  name: "ActiveBridge",
  crypto_public_address: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
  billing_email: "finance@activebridge.org"
)

eco_future_fund = Organization.create!(
  name: "EcoFuture Fund",
  crypto_public_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B",
  billing_email: "investments@ecofuture.fund"
)

puts "👤 Створення Патрульних..."

# [ORACLE EXECUTIONER]: Системний бот для автоматичних операцій (спалювання, мейнтенанс).
# Організація не вказана — це глобальний системний агент.
# [СИНХРОНІЗОВАНО з RBAC]: super_admin → access_level :system (повний доступ до всієї платформи).
oracle = User.find_or_create_by!(email_address: "oracle.executioner@system.silken.net") do |u|
  u.first_name = "Oracle"
  u.last_name  = "Executioner"
  u.role       = :super_admin
  u.password   = SecureRandom.hex(32)
end

# [RBAC: access_level :system] — Архітектор платформи з повним доступом до всіх організацій.
# super_admin не має прямого доступу до приватних Wallets без явного запрошення (Series D).
super_admin = User.create!(
  email_address: "admin@silken.net",
  password: "password123456",
  role: :super_admin,
  first_name: "Artem",
  last_name: "Volkov"
)

# [RBAC: access_level :organization] — Адміністратор ActiveBridge з повним доступом в межах організації.
alexey = User.create!(
  email_address: "alexey@activebridge.org",
  password: "password123456",
  role: :admin,
  organization: active_bridge,
  first_name: "Alexey",
  last_name: "Architect"
)

# [RBAC: access_level :field] — Лісничий з польовим доступом в межах організації.
forester = User.create!(
  email_address: "forester@activebridge.org",
  password: "password123456",
  role: :forester,
  organization: active_bridge,
  first_name: "Ivan",
  last_name: "Lisovyk"
)

# [RBAC: access_level :read_only] — Інвестор з доступом лише до власних ресурсів.
investor = User.create!(
  email_address: "investor@ecofuture.fund",
  password: "password123456",
  role: :investor,
  organization: eco_future_fund,
  first_name: "Maria",
  last_name: "Investor"
)

# =========================================================================
# 2. ФІЗИЧНИЙ СВІТ ТА БІОЛОГІЯ
# =========================================================================
cherkasy_forest = Cluster.create!(
  name: "Черкаський бір",
  region: "Центральна Україна",
  organization: active_bridge,
  environmental_settings: { "custom_fire_threshold" => 60, "seismic_sensitivity_threshold" => 3.5, "timezone" => "Europe/Kyiv" },
  geojson_polygon: { type: "Polygon", coordinates: [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ] }
)

amazon_sector = Cluster.create!(
  name: "Amazon Sector Alpha",
  region: "Amazonia, Brazil",
  organization: eco_future_fund,
  environmental_settings: { "timezone" => "America/Manaus" },
  geojson_polygon: { type: "Polygon", coordinates: [ [ [ -60.0, -3.0 ], [ -59.9, -3.0 ], [ -59.9, -2.9 ], [ -60.0, -2.9 ], [ -60.0, -3.0 ] ] ] }
)

# Синхронізація з межами Атрактора Лоренца
pine = TreeFamily.create!(
  name: "Сосна звичайна",
  scientific_name: "Pinus sylvestris",
  baseline_impedance: 1500,
  critical_z_min: -2.5,
  critical_z_max: 2.5,
  carbon_sequestration_coefficient: 0.8
)

oak = TreeFamily.create!(
  name: "Дуб звичайний",
  scientific_name: "Quercus robur",
  baseline_impedance: 2200,
  critical_z_min: -3.0,
  critical_z_max: 3.0,
  carbon_sequestration_coefficient: 1.5
)

tree_families = [ pine, oak ]

bark_beetle_model = TinyMlModel.create!(
  version: "v1.0.4-bark-beetle",
  binary_weights_payload: SecureRandom.hex(64),
  tree_family: pine,
  is_active: true,
  target_pest: "bark_beetle"
)

# =========================================================================
# 3. ПРОШИВКА (BioContract Firmware)
# =========================================================================
puts "💾 Завантаження прошивки BioContract..."
firmware = BioContractFirmware.create!(
  version: "v2.1.0-silken",
  bytecode_payload: SecureRandom.hex(256),
  is_active: true
)

# =========================================================================
# 4. ЮРИДИЧНИЙ ШАР (Контракти та Страхування)
# =========================================================================
puts "📜 Підписання NaasContract та ParametricInsurance..."
naas_contract = NaasContract.create!(
  organization: eco_future_fund,
  cluster: cherkasy_forest,
  total_funding: 50_000.0,
  start_date: Time.current,
  end_date: 1.year.from_now,
  status: :active,
  cancellation_terms: { "early_exit_fee_percent" => 15, "burn_accrued_points" => true, "min_days_before_exit" => 30 }
)

NaasContract.create!(
  organization: active_bridge,
  cluster: amazon_sector,
  total_funding: 120_000.0,
  start_date: 1.month.ago,
  end_date: 2.years.from_now,
  status: :active
)

ParametricInsurance.create!(
  organization: eco_future_fund,
  cluster: cherkasy_forest,
  payout_amount: 150_000.0,
  threshold_value: 20.0,
  status: :active,
  trigger_event: :critical_fire
)

ParametricInsurance.create!(
  organization: active_bridge,
  cluster: amazon_sector,
  payout_amount: 200_000.0,
  threshold_value: 15.0,
  status: :active,
  trigger_event: :extreme_drought,
  token_type: :forest_coin
)

# =========================================================================
# 5. ІНФРАСТРУКТУРА (Королеви та Актуатори)
# =========================================================================
puts "📡 Розгортання Королев та Актуаторів..."
gateways = []
3.times do |i|
  uid = "SNET-Q-#{format('%08X', i + 1)}"
  gw = Gateway.create!(
    uid: uid,
    ip_address: "10.0.0.#{5 + i}",
    latitude: 49.4678 + (i * 0.01),
    longitude: 31.9753 + (i * 0.01),
    cluster: cherkasy_forest,
    config_sleep_interval_s: 3600,
    last_seen_at: Time.current,
    state: :active
  )
  # [СИНХРОНІЗОВАНО]: HardwareKey використовує aes_key_hex
  HardwareKey.create!(device_uid: uid, aes_key_hex: SecureRandom.hex(32).upcase)

  Actuator.create!(
    gateway: gw,
    name: "Система зрошення Сектор #{i + 1}",
    device_type: :water_valve,
    endpoint: "valve_#{i + 1}",
    state: :idle,
    max_active_duration_s: 300,
    estimated_mj_per_action: 150
  )
  gateways << gw
end

# Додатковий шлюз для Amazon кластера
amazon_gw = Gateway.create!(
  uid: "SNET-Q-#{format('%08X', 100)}",
  ip_address: "10.0.1.10",
  latitude: -3.05,
  longitude: -59.95,
  cluster: amazon_sector,
  config_sleep_interval_s: 1800,
  last_seen_at: Time.current,
  state: :active
)
HardwareKey.create!(device_uid: amazon_gw.uid, aes_key_hex: SecureRandom.hex(32).upcase)

fire_siren = Actuator.create!(
  gateway: amazon_gw,
  name: "Пожежна сирена Amazon",
  device_type: :fire_siren,
  endpoint: "siren_1",
  state: :idle,
  max_active_duration_s: 120,
  estimated_mj_per_action: 200
)

# =========================================================================
# 6. ДІАГНОСТИКА КОРОЛЕВ (GatewayTelemetryLog)
# =========================================================================
puts "📊 Запис діагностики Королев..."
gateways.each do |gw|
  GatewayTelemetryLog.create!(
    gateway_id: gw.id,
    queen_uid: gw.uid,
    voltage_mv: 4200,
    temperature_c: 28.5,
    cellular_signal_csq: 20
  )
end

GatewayTelemetryLog.create!(
  gateway_id: amazon_gw.id,
  queen_uid: amazon_gw.uid,
  voltage_mv: 3100,
  temperature_c: 42.0,
  cellular_signal_csq: 8
)

# =========================================================================
# 7. СОЛДАТИ (Дерева, Гаманці, Телеметрія, Інсайти)
# =========================================================================
puts "🌳 Висаджуємо 100 Солдатів у Черкаський бір..."
cherkasy_trees = []
100.times do |i|
  gateway = gateways.sample
  family = tree_families.sample
  did = "SNET-#{format('%08X', i + 1)}"

  tree = Tree.create!(
    did: did,
    latitude: gateway.latitude + rand(-0.005..0.005),
    longitude: gateway.longitude + rand(-0.005..0.005),
    cluster: cherkasy_forest,
    tree_family: family,
    tiny_ml_model: family == pine ? bark_beetle_model : nil
  )

  HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(32).upcase)

  # Wallet створюється через after_create в Tree, тут лише оновлюємо
  tree.wallet.update!(
    balance: rand(5000..15000),
    crypto_public_address: "0x#{SecureRandom.hex(20)}"
  )

  # Симуляція стану
  is_anomaly = rand < 0.05
  status = is_anomaly ? :anomaly : :homeostasis

  # [СИНХРОНІЗОВАНО]: Сира телеметрія (Uplink Pulse)
  TelemetryLog.create!(
    tree: tree,
    queen_uid: gateway.uid,
    voltage_mv: is_anomaly ? 3100 : 3800,
    temperature_c: is_anomaly ? 65.0 : 22.0,
    acoustic_events: is_anomaly ? 150 : 5,
    metabolism_s: 15,
    growth_points: is_anomaly ? 0 : 5,
    mesh_ttl: 5,
    bio_status: status,
    z_value: is_anomaly ? 4.2 : 0.1,
    rssi: -rand(60..90)
  )

  # [СИНХРОНІЗОВАНО]: Вчорашній підсумок (The Insight Oracle)
  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary,
    target_date: Date.yesterday,
    average_temperature: is_anomaly ? 45.0 : 21.0,
    stress_index: is_anomaly ? 0.95 : 0.1,
    summary: is_anomaly ? "Критично: Виявлено аномальний тепловий фон." : "Стабільно: Вузол у стані гомеостазу.",
    reasoning: { max_z: (is_anomaly ? 4.2 : 0.1), source: "Simulation" }
  )

  cherkasy_trees << tree
end

puts "🌴 Висаджуємо 20 Солдатів у Amazon Sector..."
20.times do |i|
  family = oak
  did = "SNET-#{format('%08X', 200 + i)}"

  tree = Tree.create!(
    did: did,
    latitude: amazon_gw.latitude + rand(-0.005..0.005),
    longitude: amazon_gw.longitude + rand(-0.005..0.005),
    cluster: amazon_sector,
    tree_family: family
  )

  HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(32).upcase)

  tree.wallet.update!(
    balance: rand(2000..8000),
    crypto_public_address: "0x#{SecureRandom.hex(20)}"
  )

  TelemetryLog.create!(
    tree: tree,
    queen_uid: amazon_gw.uid,
    voltage_mv: 3600,
    temperature_c: 32.0,
    acoustic_events: 3,
    metabolism_s: 20,
    growth_points: 4,
    mesh_ttl: 5,
    bio_status: :homeostasis,
    z_value: 0.2,
    rssi: -rand(55..80)
  )

  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary,
    target_date: Date.yesterday,
    average_temperature: 31.0,
    stress_index: 0.15,
    summary: "Стабільно: Тропічний вузол у нормі.",
    reasoning: { max_z: 0.2, source: "Simulation" }
  )
end

# =========================================================================
# 8. ТРИВОГИ ТА ІНЦИДЕНТИ (EwsAlert)
# =========================================================================
puts "🚨 Створення тестових тривог..."
anomaly_tree = cherkasy_trees.last

drought_alert = EwsAlert.create!(
  cluster: cherkasy_forest,
  tree: anomaly_tree,
  alert_type: :severe_drought,
  severity: :medium,
  status: :active,
  message: "Гідрологічний стрес: Z-value перевищив критичні межі Атрактора Лоренца для #{anomaly_tree.tree_family.name}."
)

EwsAlert.create!(
  cluster: cherkasy_forest,
  tree: cherkasy_trees.first,
  alert_type: :insect_epidemic,
  severity: :low,
  status: :resolved,
  resolved_at: 1.day.ago,
  resolved_by: forester.id,
  resolution_notes: "Пастки встановлено. Короїд локалізовано.",
  message: "TinyML виявив акустичний паттерн короїда."
)

fire_alert = EwsAlert.create!(
  cluster: amazon_sector,
  alert_type: :fire_detected,
  severity: :critical,
  status: :active,
  message: "Температурний стрибок >60°C зафіксовано на периферії сектора."
)

# =========================================================================
# 9. БЛОКЧЕЙН ТРАНЗАКЦІЇ
# =========================================================================
puts "⛓️ Реєстрація блокчейн-транзакцій..."
sample_wallet = cherkasy_trees.first.wallet

BlockchainTransaction.create!(
  wallet: sample_wallet,
  amount: 10,
  token_type: :carbon_coin,
  status: :confirmed,
  blockchain_network: "evm",
  to_address: eco_future_fund.crypto_public_address,
  tx_hash: "0x#{SecureRandom.hex(32)}",
  sent_at: 2.hours.ago,
  confirmed_at: 1.hour.ago,
  block_number: 45_000_001,
  gas_price: 30_000_000_000,
  gas_used: 21_000,
  nonce: 42,
  locked_points: 500,
  notes: "Мінтинг 10 SCC за 500 балів росту."
)

BlockchainTransaction.create!(
  wallet: sample_wallet,
  amount: 5,
  token_type: :forest_coin,
  status: :pending,
  blockchain_network: "evm",
  to_address: active_bridge.crypto_public_address,
  locked_points: 250,
  notes: "Очікує підтвердження в мережі Polygon."
)

# =========================================================================
# 10. ОБСЛУГОВУВАННЯ (MaintenanceRecord)
# =========================================================================
puts "🔧 Реєстрація технічного обслуговування..."
# [СИНХРОНІЗОВАНО]: hardware_verified обов'язковий (validates inclusion: [true, false])
MaintenanceRecord.create!(
  user: forester,
  maintainable: cherkasy_trees[5],
  ews_alert: drought_alert,
  action_type: :inspection,
  performed_at: 1.day.ago,
  notes: "Візуальний огляд після тривоги посухи. Стан задовільний, листя не всохло.",
  hardware_verified: true
)

MaintenanceRecord.create!(
  user: forester,
  maintainable: gateways.first,
  action_type: :cleaning,
  performed_at: 3.days.ago,
  notes: "Очищено сонячну панель та антену від пилу та павутини. Сигнал покращено.",
  hardware_verified: false
)

# [СИНХРОНІЗОВАНО]: action_type :installation та :repair вимагають фото (Trust Protocol).
# У seeds без Active Storage використовуємо :inspection для демонстрації.
MaintenanceRecord.create!(
  user: alexey,
  maintainable: cherkasy_trees[10],
  action_type: :inspection,
  performed_at: 1.week.ago,
  notes: "Первинний огляд після встановлення сенсорного модуля STM32. DID зареєстровано.",
  hardware_verified: true,
  latitude: 49.4285,
  longitude: 32.0620
)

# =========================================================================
# 11. КОМАНДИ АКТУАТОРІВ (ActuatorCommand)
# =========================================================================
puts "⚙️ Відправка тестових команд актуаторам..."
first_actuator = Actuator.first

# [СИНХРОНІЗОВАНО]: priority обов'язковий (validates :priority, presence: true)
ActuatorCommand.create!(
  actuator: first_actuator,
  user: alexey,
  command_payload: "OPEN:60",
  duration_seconds: 60,
  priority: :low,
  status: :confirmed,
  sent_at: 2.hours.ago,
  executed_at: 2.hours.ago,
  completed_at: 1.hour.ago
)

ActuatorCommand.create!(
  actuator: fire_siren,
  ews_alert: fire_alert,
  command_payload: "ACTIVATE:120",
  duration_seconds: 120,
  priority: :high,
  status: :issued
)

# =========================================================================
# 12. АУДИТ-ЛОГИ (AuditLog)
# =========================================================================
puts "📋 Запис аудит-логів..."
AuditLog.create!(
  user: alexey,
  organization: active_bridge,
  action: "cluster.create",
  auditable: cherkasy_forest,
  metadata: { ip: "192.168.1.1", user_agent: "SilkenNetAdmin/1.0" }
)

AuditLog.create!(
  user: investor,
  organization: eco_future_fund,
  action: "naas_contract.sign",
  auditable: naas_contract,
  metadata: { ip: "10.0.0.1", user_agent: "Chrome/120.0" }
)

AuditLog.create!(
  user: oracle,
  organization: active_bridge,
  action: "slashing.evaluate",
  auditable: naas_contract,
  metadata: { source: "DailyAggregationWorker", trees_evaluated: 100 }
)

# =========================================================================
# 13. AI ІНСАЙТИ НА РІВНІ КЛАСТЕРА
# =========================================================================
puts "🧠 Генерація AI інсайтів для кластерів..."
AiInsight.create!(
  analyzable: cherkasy_forest,
  insight_type: :daily_health_summary,
  target_date: Date.yesterday,
  stress_index: 0.12,
  summary: "Кластер у стані гомеостазу. Середній рівень стресу мінімальний.",
  reasoning: { avg_z: 0.15, max_temp: 24.0, source: "ClusterHealthCheckWorker" }
)

AiInsight.create!(
  analyzable: cherkasy_forest,
  insight_type: :drought_probability,
  target_date: 1.week.from_now.to_date,
  probability_score: 35.0,
  summary: "Ймовірність посухи помірна. Рекомендовано моніторинг вологості ґрунту.",
  reasoning: { source: "WeatherForecastService" }
)

AiInsight.create!(
  analyzable: amazon_sector,
  insight_type: :daily_health_summary,
  target_date: Date.yesterday,
  stress_index: 0.45,
  summary: "Підвищений стрес через виявлену пожежу на периферії.",
  reasoning: { avg_z: 1.2, max_temp: 62.0, source: "ClusterHealthCheckWorker" }
)

# Інсайт на рівні організації
AiInsight.create!(
  analyzable: active_bridge,
  insight_type: :carbon_yield_forecast,
  target_date: 1.month.from_now.to_date,
  probability_score: 78.0,
  summary: "Прогноз: 1200 SCC токенів за наступний місяць при поточній динаміці.",
  reasoning: { source: "CarbonYieldService", projected_tokens: 1200 }
)

# =========================================================================
# 14. СЕСІЇ КОРИСТУВАЧІВ
# =========================================================================
puts "🔑 Створення тестових сесій..."
Session.create!(
  user: alexey,
  ip_address: "192.168.1.1",
  user_agent: "Mozilla/5.0 SilkenNetAdmin/1.0"
)

Session.create!(
  user: forester,
  ip_address: "10.0.0.50",
  user_agent: "SilkenNetMobile/2.0 Android"
)

# =========================================================================
# 15. ОНОВЛЕННЯ COUNTER CACHE
# =========================================================================
puts "🔄 Синхронізація counter cache..."
Cluster.find_each do |cluster|
  active_count = cluster.trees.active.count
  cluster.update_column(:active_trees_count, active_count)
end

# =========================================================================
# 16. ПІДСУМОК
# =========================================================================
puts ""
puts "✅ [PROJECT SILKEN NET] Екосистему ініціалізовано."
puts "   📊 Організації:         #{Organization.count}"
puts "   👤 Користувачі:         #{User.count}"
puts "      🔑 RBAC розподіл:"
puts "         super_admin (system):       #{User.role_super_admin.count}"
puts "         admin (organization):       #{User.role_admin.count}"
puts "         forester (field):           #{User.role_forester.count}"
puts "         investor (read_only):       #{User.role_investor.count}"
puts "   🌲 Кластери:            #{Cluster.count}"
puts "   🧬 Породи дерев:        #{TreeFamily.count}"
puts "   🌳 Дерева:              #{Tree.count}"
puts "   📡 Шлюзи (Queens):      #{Gateway.count}"
puts "   ⚙️  Актуатори:           #{Actuator.count}"
puts "   📜 NaaS контракти:      #{NaasContract.count}"
puts "   🛡️  Страховки:           #{ParametricInsurance.count}"
puts "   🚨 EWS тривоги:         #{EwsAlert.count}"
puts "   🧠 AI інсайти:          #{AiInsight.count}"
puts "   ⛓️  Блокчейн TX:         #{BlockchainTransaction.count}"
puts "   💰 Гаманці:             #{Wallet.count}"
puts "   🔧 Обслуговування:      #{MaintenanceRecord.count}"
puts "   📋 Аудит-логи:          #{AuditLog.count}"
puts "   💾 Прошивки:            #{BioContractFirmware.count}"
puts "   📊 Діагностика Queens:  #{GatewayTelemetryLog.count}"
puts "   📡 Телеметрія:          #{TelemetryLog.count}"
puts "   🔐 Апаратні ключі:      #{HardwareKey.count}"
puts "   🔑 Сесії:               #{Session.count}"
