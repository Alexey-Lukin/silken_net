# frozen_string_literal: true

require "securerandom"

puts "🔥 Очищення старого світу (Кенозис)..."
# Використовуємо delete_all для швидкості, якщо база велика
[TelemetryLog, Wallet, BlockchainTransaction, EwsAlert, AiInsight, 
 Tree, Gateway, HardwareKey, TreeFamily, Cluster, NaasContract, 
 Organization, TinyMlModel, User, Session].each(&:delete_all)

puts "🌍 Формування нового ландшафту..."

# 1. Організації (Інвестори)
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

# 2. Користувачі (Патрульні та Адміни)
puts "👤 Створення Патрульних..."
alexey = User.create!(
  email_address: "alexey@activebridge.org",
  password: "password123", # В реальності використовувати ENV
  role: :admin,
  organization: active_bridge,
  first_name: "Alexey",
  last_name: "Architect"
)

# 3. Кластери лісу
cherkasy_forest = Cluster.create!(
  name: "Черкаський бір",
  region: "Центральна Україна",
  organization: active_bridge,
  geojson_polygon: { type: "Polygon", coordinates: [[[31.9, 49.4], [32.0, 49.4], [32.0, 49.5], [31.9, 49.5], [31.9, 49.4]]] }
)

# 4. Генетика (Фізичні константи)
pine = TreeFamily.create!(name: "Сосна звичайна", baseline_impedance: 1500, critical_z_min: -2.5, critical_z_max: 2.5)
oak = TreeFamily.create!(name: "Дуб звичайний", baseline_impedance: 2200, critical_z_min: -3.0, critical_z_max: 3.0)
tree_families = [pine, oak]

# 5. Edge AI
bark_beetle_model = TinyMlModel.create!(
  version: "v1.0.4-bark-beetle",
  binary_weights_payload: SecureRandom.hex(64)
)

# 6. Шлюзи (Королеви) та Zero-Trust Ключі
puts "📡 Розгортання Королев та Крипто-щита..."
gateways = []
3.times do |i|
  uid = "QUEEN-SIM7070G-#{format('%03d', i+1)}"
  gw = Gateway.create!(
    uid: uid, ip_address: "10.0.0.#{5+i}",
    latitude: 49.4678 + (i * 0.01), longitude: 31.9753 + (i * 0.01),
    cluster: cherkasy_forest, config_sleep_interval_s: 3600,
    last_seen_at: Time.current
  )
  # Створюємо унікальний HardwareKey для кожної Королеви
  HardwareKey.create!(device_uid: uid, aes_key_hex: SecureRandom.hex(32).upcase)
  gateways << gw
end

# 7. Контракт NaaS (Юридична зшивка)
puts "📜 Підписання NaasContract..."
NaasContract.create!(
  organization: eco_future_fund,
  cluster: cherkasy_forest,
  total_funding: 50_000.0,
  start_date: Time.current,
  end_date: 1.year.from_now,
  status: :active
)

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

  # Створюємо ключ для кожного дерева
  HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(32).upcase)

  # Імітуємо наповнення гаманця
  tree.wallet.update!(balance: rand(10..1000), crypto_public_address: "0x#{SecureRandom.hex(20)}")

  # 8. Телеметрія (Синхронізація з новими полями)
  is_anomaly = rand < 0.05
  status = is_anomaly ? :anomaly : :homeostasis
  
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
    tamper_detected: (rand < 0.01), # 1% шанс вандалізму
    z_value: is_anomaly ? 4.2 : 0.1,
    rssi: -rand(60..90)
  )
end

puts "✅ [PROJECT SILKEN NET] Екосистему ініціалізовано."
puts "🌍 Об'єкти ActiveBridge активовані."
