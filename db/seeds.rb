# SPDX-License-Identifier: AGPL-3.0-or-later
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
  SystemParameter,
  Cluster, User, Organization
].each do |model|
  model.delete_all if ActiveRecord::Base.connection.table_exists?(model.table_name)
end

puts "🌍 Формування нового ландшафту..."

# =========================================================================
# 0. СИСТЕМНІ ПАРАМЕТРИ (Governance-Aware Protocol Constants)
# See: docs/05_03 § Governance-Aware Backend, ARCH.15
# =========================================================================
puts "⚙️  Ініціалізація системних параметрів..."

system_params = [
  # --- Lorenz Attractor (03_04) ---
  # [GOV.1] СВІДОМО НЕ сідируються: константи DCI-locked у SilkenNet::Attractor
  # (FW.7 bit-parity з прошитим firmware; zmin/zmax — per-species у TreeFamily).
  # SystemParameter-запис, якого жоден споживач не читає, був би пасткою —
  # ParameterSyncWorker ці ключі теж не синхронізує (лише tripwire-WARN).
  # ⚡ [ARCH.104] Це правило тепер ГЕЙТОВАНЕ для всього файлу, не лише для Lorenz:
  # `spec/quality/system_parameter_delivery_spec.rb` червоніє на будь-якому ключі,
  # якого не читає ні код, ні `PARAMETER_MAP`. Додаєш ручку — додай і того, хто її
  # крутить, інакше вона не «на майбутнє», а просто не існує.

  # --- Tokenomics (05_03) ---
  { key: "emission_threshold", value: "10000", value_type: "integer", category: "tokenomics",
    min_value: 1000, max_value: 100_000, description: "Growth points required to mint 1 SCC" },
  { key: "dynamic_tax_rate", value: "0.02", value_type: "decimal", category: "minting",
    min_value: 0, max_value: 0.10, description: "DAO Treasury tax rate (2% default)" },
  { key: "insurance_pool_threshold", value: "100000", value_type: "integer", category: "insurance",
    min_value: 10_000, max_value: 1_000_000, description: "SCC threshold for dynamic tax activation" },
  # [BIZ.1] CO2 equivalence: 2000 SCC = 1 tonne CO2 absorbed (D-MRV, 1 SCC = 0.5 kg CO2).
  # ⚠️ ЧИТАЧІВ У ПРОД-КОДІ НЕМА (переміряно 2026-08-26): ані KlimaDAO-retirement (той погашає
  # МОНЕТИ і курсу не читає), ані Puro.earth-паспорт, ані ESG-звіт цей ключ не споживають.
  # Ключ легальний як DAO-ручка без коду — прод-споживач прийде з carbon-registry (05_06 §7,
  # 00_07 BIZ.1). Доти голос за нього НЕ змінює нічого.
  { key: "scc_per_tonne_co2", value: "2000", value_type: "integer", category: "tokenomics",
    min_value: 100, max_value: 100_000, description: "SCC tokens equivalent to 1 tonne CO2 absorbed (2000 SCC = 1 tCO2)" },

  # --- Slashing (05_05 §3, GOV.1 — DAO-live через ProtocolParameters.sol) ---
  { key: "slash_threshold", value: "0.2", value_type: "float", category: "alerts",
    min_value: 0.05, max_value: 1.0, description: "Cluster degradation fraction that triggers the slashing checkpoint" },
  { key: "stress_threshold", value: "0.83", value_type: "float", category: "alerts",
    min_value: 0.65, max_value: 1.0, description: "RF-confidence stress threshold for slash trigger + damage sizing (ARCH.46); floor 0.65 > Z-anomaly base_stress 0.6 (E.64 §7 «Z alone never slashes» — mirror PARAMETER_MAP)" },
  { key: "slash_gamma", value: "1.3", value_type: "float", category: "alerts",
    min_value: 1.0, max_value: 3.0, description: "Convex slash curve exponent (05_05 §3)" },
  { key: "slash_penalty_factor_max", value: "2.0", value_type: "float", category: "alerts",
    min_value: 1.0, max_value: 5.0, description: "Ceiling on the slash penalty multiplier (not final ratio)" },

  # --- Pricing (04_02, S6.9) ---
  { key: "scc_fallback_price_usd", value: "25.50", value_type: "float", category: "tokenomics",
    min_value: 0.01, max_value: 1000.0, description: "SCC fallback price (USD) when Uniswap/RPC unreachable" },

  # --- Oracle Balance Thresholds (INF.22) ---
  # Мінімальні баланси Oracle wallets (у нативній валюті). Нижче — транзакції fail.
  # Рекомендується зробити configurable через ProtocolParameters для on-chain governance.
  { key: "oracle_min_balance_matic", value: "0.05", value_type: "float", category: "minting",
    min_value: 0.001, max_value: 10.0, description: "Minimum MATIC balance for Polygon MINTER Oracle wallet" },
  # [INF.22] SLASHER = окремий required-підписант з власним газ-профілем (slash ≠ mint cadence).
  # Aux (etherisc/puro/klima) свідомо НЕ сіються — activation-gated, параметр створюється при активації.
  { key: "oracle_min_balance_matic_slasher", value: "0.05", value_type: "float", category: "minting",
    min_value: 0.001, max_value: 10.0, description: "Minimum MATIC balance for Polygon SLASHER Oracle wallet" },
  { key: "oracle_min_balance_sol", value: "0.05", value_type: "float", category: "minting",
    min_value: 0.001, max_value: 10.0, description: "Minimum SOL balance for Solana Oracle wallet" },
  { key: "oracle_min_balance_celo", value: "0.05", value_type: "float", category: "minting",
    min_value: 0.001, max_value: 10.0, description: "Minimum CELO balance for Celo Oracle wallet" },
  { key: "oracle_min_balance_eth", value: "0.01", value_type: "float", category: "minting",
    min_value: 0.001, max_value: 1.0, description: "Minimum ETH balance for Ethereum L1 anchoring" },

  # --- Money-path aggregate safety (ARCH.62 / INS.2 — inert за замовчуванням) ---
  # Усі пороги 0/false = вимкнено: механізм повний у коді, активація/калібрування = 👤 DAO
  # (дзеркало slash_cause_uplift_enabled). LOCAL money-path safety — НЕ входять у on-chain
  # ProtocolParameters-sync (GOV.1 9 economic keys), ParameterSyncWorker їх не тягне.
  { key: "mint_volume_hourly_max_scc", value: "0", value_type: "integer", category: "minting",
    min_value: 0, max_value: 10_000_000_000, description: "[ARCH.62] Rolling-1h minted SCC ceiling; >0 arms the volume-anomaly alert (0=off)" },
  { key: "mint_circuit_breaker_enabled", value: "false", value_type: "boolean", category: "minting",
    description: "[ARCH.62] When true, a volume-anomaly breach holds new mint batches of that token as :pending (re-runnable; auto-releases on the Kredis flag TTL ≤1h)" },
  { key: "insurance_aggregate_payout_cap_scc", value: "0", value_type: "integer", category: "insurance",
    min_value: 0, max_value: 10_000_000_000, description: "[INS.2] 24h correlated-event cap on Internal-mint insurance payouts (0=off)" },
  { key: "insurance_reserve_adequacy_ratio", value: "0", value_type: "decimal", category: "insurance",
    min_value: 0, max_value: 1000, description: "[INS.2] Max ratio of 30d Internal insurance-mint to DAO_TREASURY reserve (0=off)" },
  # [INS.1] Майстер-прапор параметричного оракула. Доти рядка НЕ БУЛО, хоча `05_06 §7`
  # називав його серед seed-параметрів — тобто «фліп» був не тумблером, а створенням
  # запису з консолі. 🔴 І це не косметика: `SystemParameter.current` кешує ПРОМАХ
  # (`MISS_SENTINEL`) на 24 год, тож інжект повз модель лишив би прапор мертвим до доби
  # без жодної помилки. Засіяний `false` робить фліп звичайним `update` з інвалідацією.
  { key: "parametric_insurance_oracle_enabled", value: "false", value_type: "boolean", category: "insurance",
    description: "[INS.1] Kill-switch дуального оракула: false → Trigger-1 нікого не озброює й payout-воркер no-op" },
  # ⊕ Три сусіди того самого класу, виміряні разом із INS.1-прапором (2026-08-25):
  # живий читач у коді ⊥ жодного рядка в seeds. Усі три — ІНЕРТНІ ВАЖЕЛІ, чий фліп є
  # подією (DAO-активація uplift'у · перехід Solana на батчі · калібрування тиші), тож
  # «немає рядка» означало «фліп = створення запису з консолі», з тією самою
  # 24-годинною пасткою кешованого промаху. Значення дослівно дорівнюють кодовим
  # дефолтам — поведінка не змінюється, змінюється ДОСЯЖНІСТЬ важеля.
  # ⚠️ Гейт `system_parameter_delivery_spec` цю вісь не бачить за оголошеною стелею:
  # він судить «засіяне → читається», ніколи «читане → засіяне».
  { key: "slash_cause_uplift_enabled", value: "false", value_type: "boolean", category: "slashing",
    description: "[SLASH-1] DAO-активація penalty_factor-uplift; false → комбінатор причин інертний" },
  { key: "solana_batch_threshold_usdc", value: "0", value_type: "decimal", category: "minting",
    min_value: 0, max_value: 1_000_000, description: "Поріг переходу Solana-виплат з per-event на погодинні батчі (0=per-event)" },
  { key: "tree_silence_threshold_hours", value: "24", value_type: "integer", category: "alerts",
    min_value: 1, max_value: 720, description: "Скільки годин тиші дерева до field_audit-ескалації (дзеркало Tree::SILENCE_THRESHOLD)" }
]

system_params.each do |attrs|
  SystemParameter.find_or_create_by!(key: attrs[:key]) do |p|
    p.assign_attributes(attrs.merge(source: "default"))
  end
end

puts "   ⚙️  Системні параметри:   #{SystemParameter.count}"

# =========================================================================
# 1. МАКРОЕКОНОМІКА ТА ЛЮДИ
# =========================================================================
# [KYC.1] Явний approved: dev-сіди детерміновані без Sidekiq-прогону
# (у проді статус ставить HadronKycVerificationWorker на біндингу адреси).
active_bridge = Organization.create!(
  name: "ActiveBridge",
  crypto_public_address: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
  billing_email: "finance@activebridge.org",
  hadron_kyc_status: "approved"
)

eco_future_fund = Organization.create!(
  name: "EcoFuture Fund",
  crypto_public_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B",
  billing_email: "investments@ecofuture.fund",
  hadron_kyc_status: "approved"
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
  # [ARCH.102] `seismic_sensitivity_threshold` тут БІЛЬШЕ НЕ сідиться: механізму, що його
  # читає, не існує (сейсмічний вердикт знято — вимірювача немає), тож демо друкувало на
  # картці кластера чутливість детектора, якого платформа не має. Ключ лишається живим
  # forward-контрактом на моделі; сід не сміє його ВИГАДУВАТИ.
  environmental_settings: { "custom_fire_threshold" => 60, "timezone" => "Europe/Kyiv" },
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
# Z band — це гомеостатичний коридор для Lorenz Z (`SilkenNet::Attractor`).
# Lorenz Z природно сидить ~9..50 (≈ ρ−1) при ρ_eff ∈ [10, 50]; стандартний
# глобальний коридор — `Tree::GLOBAL_LORENZ_Z_MIN=2.0`, `MAX=45.0`,
# `OPTIMAL=29.0`. Per-species — звужений (`spec/factories/tree_families.rb`
# тримає той самий контракт). Сосна — ширше вікно толерантності (хвойні
# витримують ширший Z drift); дуб — вужче, центр зміщено нижче.
pine = TreeFamily.create!(
  name: "Сосна звичайна",
  scientific_name: "Pinus sylvestris",
  critical_z_min: 5.0,
  critical_z_max: 45.0,
  optimal_z_target: 29.0,
  carbon_sequestration_coefficient: 0.8
)

oak = TreeFamily.create!(
  name: "Дуб звичайний",
  scientific_name: "Quercus robur",
  critical_z_min: 8.0,
  critical_z_max: 40.0,
  optimal_z_target: 24.0,
  carbon_sequestration_coefficient: 1.5
)

tree_families = [ pine, oak ]

# [ARCH.102] Ім'я моделі називає те, що класифікатор РЕАЛЬНО вміє — пʼять акустичних класів
# (silence · wind · cavitation · chainsaw · fauna, `03_03`); виду шкідника серед них немає,
# тож `target_pest` сід свідомо НЕ заповнює (оголошена колонка без читачів, `04_01`).
pine_acoustic_model = TinyMlModel.create!(
  version: "v1.0.4-acoustic-pine",
  binary_weights_payload: SecureRandom.hex(64),
  tree_family: pine,
  is_active: true
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
  # [СИНХРОНІЗОВАНО]: HardwareKey використовує aes_key_hex.
  # Post-ARCH.42 (2026-05-23): Gateway CoAP channel — AES-256 (32 bytes / 64 hex) — без змін.
  HardwareKey.create!(device_uid: uid, aes_key_hex: SecureRandom.hex(32).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

  Actuator.create!(
    gateway: gw,
    name: "Система зрошення Сектор #{i + 1}",
    device_type: :water_valve,
    endpoint: "valve_#{i + 1}",
    state: :idle,
    # ⚠️ [ARCH.75] 300 с — ПЛЕЙСХОЛДЕР, не виміряна фізика, і він СУПЕРЕЧИТЬ
    # власному протоколу платформи: `EmergencyResponseService` просить клапану
    # 7200 с (посуха) і 14400 с (пожежа), тобто чанки по 3600 с. Доти суперечність
    # була невидима — `insert_all` обходив валідації, і накази лягали невалідними
    # й мовчки. Тепер вона гучна: аварійна відповідь на цій конфігурації НЕ
    # відправляється, а платформа пише `emergency_response_undeliverable`. Число
    # лишається до стенд-виміру реального соленоїда → `00_07` ARCH.75 / HW-домен.
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
HardwareKey.create!(device_uid: amazon_gw.uid, aes_key_hex: SecureRandom.hex(32).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

fire_siren = Actuator.create!(
  gateway: amazon_gw,
  name: "Пожежна сирена Amazon",
  device_type: :fire_siren,
  endpoint: "siren_1",
  state: :idle,
  # ⚠️ [ARCH.75] Так само плейсхолдер: протокол просить сирені 3600 с (див. ноту
  # біля клапана вище) — ця конфігурація аварійну відповідь не виконує.
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
    tiny_ml_model: family == pine ? pine_acoustic_model : nil
  )

  # Post-ARCH.42 (2026-05-23): Tree LoRa channel — AES-128 (16 bytes / 32 hex).
  HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

  # Wallet створюється через after_create в Tree, тут лише оновлюємо
  tree.wallet.update!(
    balance: rand(5000..15000),
    crypto_public_address: "0x#{SecureRandom.hex(20)}"
  )

  # Симуляція стану
  is_anomaly = rand < 0.05
  status = is_anomaly ? :anomaly : :homeostasis

  # [СИНХРОНІЗОВАНО]: Сира телеметрія (Uplink Pulse).
  # Z values відповідають реальному діапазону Lorenz attractor:
  #   homeostasis ∈ [critical_z_min, critical_z_max] (pine: 5..45, optimum 29),
  #   anomaly = поза band (тут 48.5 → понад MAX, тобто перегрів атрактора).
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
    z_value: is_anomaly ? 48.5 : 28.5,
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
    reasoning: { max_z: (is_anomaly ? 48.5 : 28.5), source: "Simulation" }
  )

  # [ARCH.84] Денормалізацію пише сам сід, як це робить `InsightGeneratorService`
  # після створення інсайту. Доти сіди створювали інсайт і НЕ писали колонку — а
  # та мала `DEFAULT 0.0`, тож розбіжність не було видно. Після зняття дефолту
  # мовчання сіда означало б «не виміряно» на кожному засіяному дереві, і
  # найгучніше — на аномальних, чий інсайт каже 0.95.
  tree.update_column(:latest_stress_index, is_anomaly ? 0.95 : 0.1)

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

  # Post-ARCH.42 (2026-05-23): Tree LoRa channel — AES-128 (16 bytes / 32 hex).
  HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

  tree.wallet.update!(
    balance: rand(2000..8000),
    crypto_public_address: "0x#{SecureRandom.hex(20)}"
  )

  # Дуб (oak): band 8..40, optimum 24 → ставимо homeostasis ~ 24.
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
    z_value: 24.0,
    rssi: -rand(55..80)
  )

  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary,
    target_date: Date.yesterday,
    average_temperature: 31.0,
    stress_index: 0.15,
    summary: "Стабільно: Тропічний вузол у нормі.",
    reasoning: { max_z: 24.0, source: "Simulation" }
  )

  # [ARCH.84] Дзеркало сіда вище: денормалізацію пише сід, не дефолт колонки.
  tree.update_column(:latest_stress_index, 0.15)
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
  message_key: "attractor_destabilised",
  message_params: { z_value: 3.4 }
)

fire_alert = EwsAlert.create!(
  cluster: amazon_sector,
  alert_type: :fire_detected,
  severity: :critical,
  status: :active,
  message_key: "fire_detected",
  message_params: { temperature_c: 63.5, fire_limit: 60 }
)

# [SLASH-1] Акустичний детект без термального сигналу — вирубка, не вогонь.
EwsAlert.create!(
  cluster: cherkasy_forest,
  tree: cherkasy_trees[7],
  alert_type: :chainsaw_detected,
  severity: :critical,
  status: :active,
  message_key: "chainsaw_detected_panic",
  message_params: { did: cherkasy_trees[7].did }
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

# [СИНХРОНІЗОВАНО]: priority обов'язковий (validates :priority, presence: true).
# Поле `executed_at` фіксується AASM `acknowledge`/`confirm` подіями у живому
# flow; seeds-варіант обходить state machine (`status: :confirmed` напряму),
# тож виставляємо мітку експліцитно — інакше UI Actuators::Show показав би
# "—" для seed-команд.
ActuatorCommand.create!(
  actuator: first_actuator,
  user: alexey,
  command_payload: "OPEN:60",
  duration_seconds: 60,
  priority: :low,
  status: :confirmed,
  sent_at: 2.hours.ago,
  executed_at: 90.minutes.ago,
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
# [I18N.1] `action:` — лише значення РЕАЛЬНИХ писачів (`record_audit_trail!`-сайти):
# доти сіди несли dot-конвенцію (`cluster.create`…), якої не пише жоден код, тож
# dev-БД брехала про можливі значення журналу.
AuditLog.create!(
  user: alexey,
  organization: active_bridge,
  action: "user_role_changed",
  auditable: alexey,
  metadata: { "from" => "forester", "to" => "admin", ip: "192.168.1.1", user_agent: "SilkenNetAdmin/1.0" }
)

AuditLog.create!(
  user: investor,
  organization: eco_future_fund,
  action: "naas_contract_to_active",
  auditable: naas_contract,
  metadata: { "from" => "draft", "to" => "active", ip: "10.0.0.1", user_agent: "Chrome/120.0" }
)

AuditLog.create!(
  user: oracle,
  organization: active_bridge,
  action: "slash_verdict_frozen",
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
  reasoning: { avg_z: 28.5, max_temp: 24.0, source: "ClusterHealthCheckWorker" }
)

AiInsight.create!(
  analyzable: cherkasy_forest,
  insight_type: :drought_probability,
  target_date: 1.week.from_now.to_date,
  probability_score: 35.0,
  summary: "Ймовірність посухи помірна. Рекомендовано моніторинг вологості ґрунту.",
  reasoning: { source: "WeatherForecastService" },
  # prediction_data: structured metric для OracleVisions::ForecastCard.
  prediction_data: { "yield_impact" => -8.5, "confidence_interval" => [ 25.0, 45.0 ] }
)

AiInsight.create!(
  analyzable: amazon_sector,
  insight_type: :daily_health_summary,
  target_date: Date.yesterday,
  stress_index: 0.45,
  summary: "Підвищений стрес через виявлену пожежу на периферії.",
  reasoning: { avg_z: 41.5, max_temp: 62.0, source: "ClusterHealthCheckWorker" }
)

# Інсайт на рівні організації
AiInsight.create!(
  analyzable: active_bridge,
  insight_type: :carbon_yield_forecast,
  target_date: 1.month.from_now.to_date,
  probability_score: 78.0,
  summary: "Прогноз: 1200 SCC токенів за наступний місяць при поточній динаміці.",
  reasoning: { source: "CarbonYieldService", projected_tokens: 1200 },
  prediction_data: { "yield_impact" => 12.0, "projected_scc" => 1200 }
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
# 17. ПІДСУМОК
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
puts "   ⚙️  Системні параметри:   #{SystemParameter.count}"
