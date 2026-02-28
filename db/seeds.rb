# frozen_string_literal: true

require "securerandom"

puts "🔥 Очищення старого світу (Кенозис)..."
# Порядок враховує залежності (Foreign Keys)
[
  Session, TelemetryLog, AiInsight, EwsAlert, BlockchainTransaction,
  Wallet, ActuatorCommand, Actuator, HardwareKey, Tree, TinyMlModel,
  TreeFamily, ParametricInsurance, NaasContract, Cluster, User, Organization
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
  crypto_public_address: "0x#{SecureRandom.hex(20)}",
  billing_email: "investments@ecofuture.fund"
)

puts "👤 Створення Патрульних..."
alexey = User.create!(
  email_address: "alexey@activebridge.org",
  password: "password123",
  role: :admin,
  organization: active_bridge,
  first_name: "Alexey",
  last_name: "Architect"
)

# =========================================================================
# 2. ФІЗИЧНИЙ СВІТ ТА БІОЛОГІЯ
# =========================================================================
cherkasy_forest = Cluster.create!(
  name: "Черкаський бір",
  region: "Центральна Україна",
  organization: active_bridge,
  geojson_polygon: { type: "Polygon", coordinates: [ [ [ 31.9, 49.4 ], [ 32.0, 49.4 ], [ 32.0, 49.5 ], [ 31.9, 49.5 ], [ 31.9, 49.4 ] ] ] }
)

# Синхронізація з межами Атрактора Лоренца
pine = TreeFamily.create!(name: "Сосна звичайна", baseline_impedance: 1500, critical_z_min: -2.5, critical_z_max: 2.5)
oak = TreeFamily.create!(name: "Дуб звичайний", baseline_impedance: 2200, critical_z_min: -3.0, critical_z_max: 3.0)
tree_families = [ pine, oak ]

bark_beetle_model = TinyMlModel.create!(
  version: "v1.0.4-bark-beetle",
  binary_weights_payload: SecureRandom.hex(64)
)

# =========================================================================
# 3. ЮРИДИЧНИЙ ШАР (Контракти та Страхування)
# =========================================================================
puts "📜 Підписання NaasContract та ParametricInsurance..."
NaasContract.create!(
  organization: eco_future_fund,
  cluster: cherkasy_forest,
  total_funding: 50_000.0,
  start_date: Time.current,
  end_date: 1.year.from_now,
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

# =========================================================================
# 4. ІНФРАСТРУКТУРА (Королеви та Актуатори)
# =========================================================================
puts "📡 Розгортання Королев та Актуаторів..."
gateways = []
3.times do |i|
  uid = "QUEEN-SIM7070G-#{format('%03d', i+1)}"
  gw = Gateway.create!(
    uid: uid,
    ip_address: "10.0.0.#{5+i}",
    latitude: 49.4678 + (i * 0.01),
    longitude: 31.9753 + (i * 0.01),
    cluster: cherkasy_forest,
    config_sleep_interval_s: 3600,
    last_seen_at: Time.current
  )
  # [СИНХРОНІЗОВАНО]: HardwareKey використовує aes_key_hex
  HardwareKey.create!(device_uid: uid, aes_key_hex: SecureRandom.hex(32).upcase)

  Actuator.create!(
    gateway: gw,
    name: "Система зрошення Сектор #{i+1}",
    device_type: :water_valve,
    endpoint: "valve_#{i+1}",
    state: :idle
  )
  gateways << gw
end

# =========================================================================
# 5. СОЛДАТИ (Дерева, Гаманці, Телеметрія, Інсайти)
# =========================================================================
puts "🌳 Висаджуємо 100 Солдатів..."
100.times do |i|
  gateway = gateways.sample
  family = tree_families.sample
  did = "DID-TREE-#{format('%04d', i+1)}"

  tree = Tree.create!(
    did: did,
    latitude: gateway.latitude + rand(-0.005..0.005),
    longitude: gateway.longitude + rand(-0.005..0.005),
    cluster: cherkasy_forest,
    tree_family: family,
    tiny_ml_model: bark_beetle_model
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
    z_value: is_anomaly ? 4.2 : 0.1, # 4.2 - вихід за межі Атрактора
    rssi: -rand(60..90)
  )

  # [СИНХРОНІЗОВАНО]: Вчорашній підсумок (The Insight Oracle)
  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary, # Обов'язкове поле
    target_date: Date.yesterday,        # Замість analyzed_date
    average_temperature: is_anomaly ? 45.0 : 21.0,
    stress_index: is_anomaly ? 0.95 : 0.1,
    summary: is_anomaly ? "Критично: Виявлено аномальний тепловий фон." : "Стабільно: Вузол у стані гомеостазу.",
    reasoning: { max_z: (is_anomaly ? 4.2 : 0.1), source: "Simulation" }
  )
end

puts "✅ [PROJECT SILKEN NET] Екосистему ініціалізовано."
