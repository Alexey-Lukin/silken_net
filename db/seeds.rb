# frozen_string_literal: true

puts "🔥 Очищення старого світу..."
TelemetryLog.destroy_all
Wallet.destroy_all
Tree.destroy_all
Gateway.destroy_all
TreeFamily.destroy_all
Cluster.destroy_all
Organization.destroy_all
TinyMlModel.destroy_all

puts "🌍 Формування нового ландшафту..."

# 1. Організації (Інвестори)
_active_bridge = Organization.create!(
  name: "ActiveBridge",
  crypto_public_address: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
  billing_email: "finance@activebridge.org"
)

_eco_future_fund = Organization.create!(
  name: "EcoFuture Fund",
  crypto_public_address: "0x89A12B3C4D5E6F7G8H9I0J1K2L3M4N5O6P7Q8R9S",
  billing_email: "investments@ecofuture.fund"
)

# 2. Кластери лісу
cherkasy_forest = Cluster.create!(
  name: "Черкаський бір",
  region: "Центральна Україна"
)

kholodny_yar = Cluster.create!(
  name: "Холодний Яр",
  region: "Центральна Україна"
)

# 3. Генетика (TreeFamily - три різні породи з різною фізикою)
pine = TreeFamily.create!(
  name: "Сосна звичайна (Pinus sylvestris)",
  baseline_impedance: 1500,
  critical_z_min: -2.5,
  critical_z_max: 2.5
)

oak = TreeFamily.create!(
  name: "Дуб звичайний (Quercus robur)",
  baseline_impedance: 2200,
  critical_z_min: -3.0,
  critical_z_max: 3.0
)

birch = TreeFamily.create!(
  name: "Береза повисла (Betula pendula)",
  baseline_impedance: 1200,
  critical_z_min: -2.0,
  critical_z_max: 2.0
)

tree_families = [ pine, oak, birch ]

puts "🧠 Компіляція Edge AI нейромереж..."
bark_beetle_model = TinyMlModel.create!(
  version: "v1.0.4-bark-beetle",
  target_pest: "Короїд (Bark Beetle)",
  binary_weights_payload: "0x" + SecureRandom.hex(128)
)

puts "📡 Розгортання Шлюзів (Королев)..."
gateways = [
  Gateway.create!(
    uid: "QUEEN-SIM7070G-001", ip_address: "10.0.0.5",
    latitude: 49.4678, longitude: 31.9753, altitude: 110.0,
    last_seen_at: Time.current, cluster: cherkasy_forest,
    config_sleep_interval_s: 3600
  ),
  Gateway.create!(
    uid: "QUEEN-SIM7070G-002", ip_address: "10.0.0.6",
    latitude: 49.4850, longitude: 31.9900, altitude: 115.0,
    last_seen_at: Time.current, cluster: cherkasy_forest,
    config_sleep_interval_s: 3600
  ),
  Gateway.create!(
    uid: "QUEEN-SIM7070G-003", ip_address: "10.0.1.5",
    latitude: 49.1415, longitude: 32.2612, altitude: 150.0,
    last_seen_at: Time.current, cluster: kholodny_yar,
    config_sleep_interval_s: 3600
  )
]

puts "🌳 Висаджуємо 100 Дерев (Солдатів) навколо Шлюзів..."

100.times do |i|
  gateway = gateways.sample
  family = tree_families.sample

  lat_offset = rand(-0.005..0.005)
  lng_offset = rand(-0.005..0.005)

  # Дерево автоматично створить собі гаманець після створення
  tree = Tree.create!(
    did: "did:silken:tree-#{1000 + i}",
    latitude: gateway.latitude + lat_offset,
    longitude: gateway.longitude + lng_offset,
    altitude: gateway.altitude + rand(-5.0..5.0),
    cluster: gateway.cluster,
    tree_family: family,
    tiny_ml_model: bark_beetle_model
  )

  # Оновлюємо вже існуючий гаманець
  if tree.wallet.present?
    tree.wallet.update!(
      balance: rand(0.0..50.0).round(2),
      crypto_public_address: "0x#{SecureRandom.hex(20)}"
    )
  end

  # Імітуємо телеметрію (з 5% шансом на аномалію)
  is_anomaly = rand(1..100) <= 5

  TelemetryLog.create!(
    tree: tree,
    queen_uid: gateway.uid,
    voltage_mv: is_anomaly ? rand(2800..3100) : rand(3600..4200),
    temperature_c: is_anomaly ? rand(45.0..65.0) : (21.5 + rand(-2.5..2.5)),
    acoustic_events: is_anomaly ? rand(50..120) : rand(0..15),
    metabolism_s: is_anomaly ? rand(1..5) : rand(10..30),
    growth_points: is_anomaly ? -0.5 : 0.5,
    mesh_ttl: rand(1..5),
    bio_status: is_anomaly ? :anomaly : :homeostasis,  # <--- ВИПРАВЛЕНО
    piezo_voltage_mv: is_anomaly ? rand(1600..2000) : rand(100..300),
    tamper_detected: false,
    z_value: is_anomaly ? rand(3.5..5.0) : rand(-1.5..1.5)
  )
end

puts "✅ Готово! Масштабну екосистему розгорнуто."
puts "📊 Статистика: #{Cluster.count} кластери, #{Organization.count} організації, #{Gateway.count} шлюзи, #{Tree.count} дерев."
