# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = =====================================================================
# ⛔ ПРОДОВИЙ ЗАПОБІЖНИК — цей файл РУЙНІВНИЙ і на `production` не їде
# = =====================================================================
# `lib/tasks/governance.rake` каже це від народження («Production must NOT call
# it under any circumstance»), але носія в тій заяви не було — а `06_01` крок 7
# доти приписував `db:setup`, який `db:seed` у себе ВКЛЮЧАЄ. Два доми канону
# стверджували протилежне, і в день деплою переміг би рунбук.
#
# 🔴 Чому саме тут, а не в рунбуку: захищена НЕ ТА половина. `db:schema:load`
# оголошено як `task load: [:load_config, :check_protected_environments]` і на
# продовій базі воно впаде саме; `db:seed` — як `task seed: :load_config`, тобто
# без гарда взагалі. Отже `delete_all` по 27 моделях нижче пройшов би на живій
# базі без єдиного запитання. Носій мусить стояти в місці ДІЇ.
#
# Слот, а не `Rails.env`: canopy біжить із `RAILS_ENV=production` свідомо
# (загартований рантайм), і саме на ньому демо-дані ДОРЕЧНІ — розрізняє їх лише
# `DEPLOYMENT_SLOT` (`config/deployment_slot.rb`, INF.27).
if SilkenNet::DeploymentSlot.current == "production"
  abort <<~MSG
    ⛔ `db:seed` заблоковано на слоті `production`.

    Цей файл починається з `delete_all` по 27 моделях і сіє ДЕМО-дані
    (~150 дерев, фальшиві :confirmed мінти, що годують `net_minted_supply`,
    користувачів із відомим паролем, живі сесії, ланки в SHA-256 аудит-ланцюгу).

    Що робити натомість:
      · продовий bootstrap → `bin/rails governance:bootstrap` (oracle_executioner +
        `governance:seed_parameters`; ідемпотентно; його ж кличе `.kamal/hooks/post-deploy`)
      · склад TreeFamily реального розгортання — `governance:bootstrap` сіє ОДНУ родину
        (*Pinus sylvestris*, числа оголошено провізорними; ⚖️ `00_07` OPS.38 2026-09-03), не тут
      · демо-сівба доречна на `canopy` — вона проходить цей гард
  MSG
end

# ⛔ Файловий спліт `db/seeds/*.rb` («системне ⊥ демо») ВІДХИЛЕНО виміром 2026-09-01:
# пʼять гейтів прибиті до шляху `db/seeds.rb` і парсять його як ТЕКСТ
# (`seeds_production_guard_spec` · `system_parameter_delivery_spec` ·
# `governance_bounds_sync.rb` · `spdx_headers_spec` · `offering_lexicon_check.rb`), тож
# спліт перетворює просту задачу на мас-кампанію при нульовому виграші — склад
# продового bootstrap вирішує rake-таска (`00_07` OPS.38), не другий сід-файл.

puts "🔥 Очищення старого світу (Кенозис)..."
# Порядок враховує залежності (Foreign Keys) — від листя до кореня.
# ⛔ Перелік мусить накривати УСІ AR-моделі дерева, а не лише ті, що сід сіє:
# `delete_all` не бачить рядка, записаного кимось іншим, і той рядок валить не
# себе, а КОРІНЬ. Три позиції з нижчезазначеною підставою:
#   · `ProvisioningSession` — `operator_id`/`supervisor_id` це FK на `users`, тож
#     будь-який прогін `factory:flash` робив наступний `db:seed` фатальним на
#     `User.delete_all` (тому стоїть у листі, ПЕРЕД користувачами);
#   · `TelemetryArchiveBatch` — на нього дивиться `blockchain_transactions.archive_batch_id`,
#     тож зноситься ПІСЛЯ транзакцій;
#   · `EthereumAnchor` — FK не має в жоден бік, позиція вільна.
[
  AuditLog, Session, ProvisioningSession,
  ActuatorCommand, MaintenanceRecord,
  BlockchainTransaction, TelemetryArchiveBatch,
  TelemetryLog, GatewayTelemetryLog, AiInsight, EwsAlert,
  Wallet, DeviceCalibration,
  Actuator, HardwareKey,
  Tree, TinyMlModel, TreeFamily,
  Gateway,
  ParametricInsurance, NaasContract,
  BioContractFirmware, EthereumAnchor,
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
  { key: "slash_alert_max_age_hours", value: "0", value_type: "integer", category: "alerts",
    min_value: 0, max_value: 8760,
    description: "[SLASH-1] Нижня межа віку алерту для critical_unmaintained? (0=без межі). Без неї алерт довільної давнини садить penalty_factor на КОЖНОМУ майбутньому вироку — латч, чий один із трьох маршрутів зняв gap-E. Число калібрується разом із вагою repeat-offence." },
  { key: "slash_cause_uplift_enabled", value: "false", value_type: "boolean", category: "alerts",
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

# 🔴 Демо-пароль відомий ЛИШЕ локально. Слот `canopy` біжить із `RAILS_ENV=production`
# й публічно доступний крізь Cloudflare, а цей файл лежить у публічному репо — тож
# літеральний пароль на будь-якому не-local середовищі є super_admin-логіном для
# кожного, хто вміє читати git (виміряно на живому canopy 2026-09-02: сід дійшов до
# кінця, `admin@silkennet.com` приймав `password123456`). На canopy демо-користувачі
# лишаються (дані, ролі, орг-скоуп), але з невідомим паролем; вхід власника — ЙОГО
# super_admin, а пароль будь-якому демо-акаунту видає reset-лінк із `rails runner`
# (`generate_token_for(:password_reset)`), бо пошта на canopy свідомо скіпана.
# ⛔ Демо-користувачів на canopy НЕ видаляти, а РОТУВАТИ: `maintenance_records`/`audit_logs`
# тримають `restrict_with_error`, а `oracle.executioner` — системний актор money-аудиту;
# ротація на випадкові паролі дає той самий ефект без зносу демо-даних (2026-09-02).
DEMO_PASSWORD = Rails.env.local? ? "password123456" : SecureRandom.hex(24)

puts "👤 Створення Патрульних..."

# [ORACLE EXECUTIONER]: Системний бот для автоматичних операцій (спалювання, мейнтенанс).
# Організація не вказана — це глобальний системний агент.
# [СИНХРОНІЗОВАНО з RBAC]: super_admin → access_level :system (повний доступ до всієї платформи).
oracle = User.find_or_create_by!(email_address: User::ORACLE_EXECUTIONER_EMAIL) do |u|
  u.first_name = "Oracle"
  u.last_name  = "Executioner"
  u.role       = :super_admin
  u.password   = SecureRandom.hex(32)
end

# [RBAC: access_level :system] — Архітектор платформи з повним доступом до всіх організацій.
# super_admin не має прямого доступу до приватних Wallets без явного запрошення (Series D).
super_admin = User.create!(
  email_address: "admin@silkennet.com",
  password: DEMO_PASSWORD,
  role: :super_admin,
  first_name: "Artem",
  last_name: "Volkov"
)

# [RBAC: access_level :organization] — Адміністратор ActiveBridge з повним доступом в межах організації.
alexey = User.create!(
  email_address: "alexey@activebridge.org",
  password: DEMO_PASSWORD,
  role: :admin,
  organization: active_bridge,
  first_name: "Alexey",
  last_name: "Architect"
)

# [RBAC: access_level :field] — Лісничий з польовим доступом в межах організації.
forester = User.create!(
  email_address: "forester@activebridge.org",
  password: DEMO_PASSWORD,
  role: :forester,
  organization: active_bridge,
  first_name: "Ivan",
  last_name: "Lisovyk"
)

# [RBAC: access_level :read_only] — Замовник з доступом лише до власних ресурсів.
subscriber = User.create!(
  email_address: "subscriber@ecofuture.fund",
  password: DEMO_PASSWORD,
  role: :subscriber,
  organization: eco_future_fund,
  first_name: "Maria",
  last_name: "Subscriber"
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
  # 🔥 `custom_fire_threshold` — ПЕРША ланка `AlertDispatchService#fire_limit`
  # (кластер → `TreeFamily#fire_resistance_rating` → `DEFAULT_FIRE_TEMP_C`), і вона
  # перекриває обидві наступні. Значення дорівнює платформному дефолту 60 °C свідомо:
  # це біом-ПІН, а не розходження. Наслідок для телеметрії названо в §7 біля
  # `temperature_c` — там число мусить триматись під цим порогом, інакше кадр
  # класифікується пожежею незалежно від того, що каже його власний коментар.
  environmental_settings: { "custom_fire_threshold" => 60, "timezone" => "Europe/Kyiv" },
  # 🗺️ Полігон лежить УСЕРЕДИНІ лісу, не на річці. OSM relation 3779329 «Черкаський бір»
  # (natural=wood): bbox lat 49.2326..49.5531, lon 31.4616..31.9417. Доти тут стояв квадрат
  # 31.9..32.0 — східніше східної межі бору, тобто Дніпро й місто: мапа дашборда садила
  # сто Солдатів у воду (виміряно на живому canopy 2026-09-02, скріншот власника).
  # Координати шлюзів (§5) і дерев (§7) деривуються від цього ж прямокутника — один дім.
  geojson_polygon: { type: "Polygon", coordinates: [ [ [ 31.74, 49.35 ], [ 31.86, 49.35 ], [ 31.86, 49.46 ], [ 31.74, 49.46 ], [ 31.74, 49.35 ] ] ] }
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
  # ⚖️ [DOC-T.89, 2026-08-26] Було `:forest_coin` — демо роздавало 200k ГОЛОСІВ одній
  # організації за страховий випадок, і моделювало захоплення DAO як норму.
  # 🔴 Присуд лишається, але тримає його ТЕПЕР інша, сильніша підстава: вибору більше
  # немає взагалі — `ParametricInsurance` оголошує `enum :token_type, { carbon_coin: 0 }`,
  # тобто SFC із цієї моделі вилучено, і `:forest_coin` тут просто не існує як значення.
  # (Первісна причина — «quorum рахується від `totalSupply`» — мертва з того ж дня:
  # `SilkenGovernor` рахує quorum від СТЕЛІ емісії `QUORUM_BASE`, не від обігу.)
  token_type: :carbon_coin
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
    # Усередині полігону кластера (§2, OSM-межі бору) — крок ~1 км по NE у сосновому масиві.
    latitude: 49.395 + (i * 0.01),
    longitude: 31.80 + (i * 0.01),
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
# 🔇 [SILENCE-1] Індекси навмисних мовчунок. `Tree.silent` — це active-дерево, що ВЖЕ
# виходило в ефір і замовкло довше за `Tree::SILENCE_THRESHOLD` (24 год); NULL-мітка в
# скоуп свідомо НЕ входить («мовчання ненародженого»). Доти жодне засіяне дерево не мало
# `last_seen_at` взагалі, тож вісь тиші не мала в демо ЖОДНОГО зі своїх двох станів —
# ані свіжого сигналу, ані тиші, — а вона несуча: мовчазне дерево виключається зі
# знаменника слешингу й підбирається `TreeStalenessSweepWorker` у Field Audit.
# Індекси вибрані з вільних: 0 несе грошовий тракт (§9), 5 і 10 — обслуговування (§10),
# 7 — пилку (§8), останній — тривогу посухи (§8). Мовчунка в будь-якому з них зробила б
# сусідній сюжет самосуперечливим.
silent_tree_indexes = [ 3, 42 ]
cherkasy_measured_trees = 0
100.times do |i|
  gateway = gateways.sample
  family = tree_families.sample
  did = "SNET-#{format('%08X', i + 1)}"
  is_silent = silent_tree_indexes.include?(i)
  # Момент останнього почутого пакета: для мовчунки — минуле, і рівно ним датований
  # її `TelemetryLog` (дві мітки про ОДНУ подію не мають права розходитись).
  last_heard_at = is_silent ? 73.hours.ago : Time.current

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

  # Wallet створюється через after_create в Tree, тут лише оновлюємо.
  #
  # 💰 ОДИНИЦЯ `balance` — БАЛИ РОСТУ, не монети (`04_01 §6`; курс `emission_threshold`
  # вище: 10 000 балів = 1 SCC). Аліас `scc_balance` на цій колонці — депрекований
  # ренейм, не конверсія [ARCH.88].
  #
  # 🔑 [KYC.1] Демо мусить показувати ОБИДВІ гілки `Wallet#kyc_approved_for_minting?`:
  #   · custodial (адреси НЕМА) → статус успадковується від організації, а мінт їде
  #     на її адресу (`lock_and_mint!` бере `organization.crypto_public_address`);
  #   · власна адреса → читається ВЛАСНИЙ статус гаманця, і org-схвалення його НЕ
  #     перекриває.
  # ⛔ Тому власна адреса виставляється РАЗОМ зі статусом одним `update!`:
  # `reset_hadron_kyc_on_address_change` скидає в `pending` рівно тоді, коли явного
  # статусу в тому самому записі немає. Доти сід давав власну адресу ВСІМ і статусу не
  # ставив — тобто з ~120 гаманців мінтити не міг ЖОДЕН (`BlockchainMintingService`
  # відсіював їх усі), і кожен рядок ще й ставив у чергу `HadronKycVerificationWorker`.
  self_custodial = (i % 25).zero?
  if self_custodial
    tree.wallet.update!(
      balance: rand(5000..15000),
      crypto_public_address: "0x#{SecureRandom.hex(20)}",
      hadron_kyc_status: "approved"
    )
  else
    tree.wallet.update!(balance: rand(5000..15000))
  end

  # Симуляція стану
  is_anomaly = rand < 0.05
  status = is_anomaly ? :anomaly : :homeostasis
  # Напруга шини цього пакета — ОДИН вираз на два записи (`TelemetryLog.voltage_mv` і
  # денормалізований `trees.latest_voltage_mv`): два літерали розійшлись би тихо, і база
  # суперечила б сама собі про ОДИН вимір.
  packet_voltage_mv = is_anomaly ? 3100 : 3800

  # [СИНХРОНІЗОВАНО]: Сира телеметрія (Uplink Pulse).
  # Z values відповідають реальному діапазону Lorenz attractor:
  #   homeostasis ∈ [critical_z_min, critical_z_max] (pine: 5..45, optimum 29),
  #   anomaly = поза band (тут 48.5 → понад MAX, тобто перегрів атрактора).
  #
  # 🔥 `temperature_c` аномалії — 41 °C, і число тут НЕСУЧЕ. Доти стояло 65 °C, тобто
  # ВИЩЕ за `fire_limit` цього кластера (60 °C, §2), а пожежна гілка
  # `AlertDispatchService` стоїть ПЕРШОЮ і робить `return` — отже кожен «дестабілізований
  # атрактор» демо живий код класифікував би як `fire_detected`/`critical`. Хибним було
  # саме число: 65 °C на стовбурі є пожежею за власним означенням платформи, хай би який
  # поріг із трьох ланок спрацював.
  # ⚠️ І чесно про те, що НЕ змінилось: кадр із `bio_status: :anomaly` навіть під порогом
  # веде в АКУСТИЧНУ гілку (`chainsaw_detected`), а не в `attractor_destabilised` —
  # той medium-алерт народжується лише зі stress-кадру — і з 2026-09-05 ЛИШЕ з нього
  # (E.64: серверну гілку «Z поза обвідною» знято, а сам stress недосяжний за ρ-clamp). Сюжет «дестабілізація» демо тримає окремим EwsAlert у §8.
  # ⊕ Добове середнє інсайту нижче поїхало слідом (45 → 38 °C): середнє, ВИЩЕ за кожен
  # свій замір, є станом, якого світ не має.
  TelemetryLog.create!(
    tree: tree,
    queen_uid: gateway.uid,
    voltage_mv: packet_voltage_mv,
    temperature_c: is_anomaly ? 41.0 : 22.0,
    acoustic_events: is_anomaly ? 150 : 5,
    metabolism_s: 15,
    growth_points: is_anomaly ? 0 : 5,
    mesh_ttl: 5,
    bio_status: status,
    z_value: is_anomaly ? 48.5 : 28.5,
    rssi: -rand(60..90),
    created_at: last_heard_at
  )

  # 🔊 [ARCH.109] Канал «вузол чули» має право писати ЛИШЕ той, хто його справді почув.
  # Сід створює сам уплінк рядком вище, тож підстава є — і мітка йде РІВНО поруч із ним,
  # ніколи з обслуговування (людський артефакт `mark_seen!` не кличе: `00_01 §1.1`).
  # `voltage_mv` = мВ шини VDDA, діагностика просідання, а НЕ запас іоністора [ARCH.99].
  if is_silent
    # `mark_seen!` за побудовою клемпить мітку в NOW (`GREATEST(COALESCE(…), now)`) —
    # МИНУЛИМ моментом ним не напишеш, тож пара йде прямо, тим самим уплінком.
    tree.update_columns(last_seen_at: last_heard_at, latest_voltage_mv: packet_voltage_mv)
  else
    tree.mark_seen!(packet_voltage_mv)
  end

  cherkasy_trees << tree

  # 🔇 Мовчунка добового агрегату не потрапляє: вона не виходила в ефір за звітну добу.
  # Тому ані інсайту, ані `latest_stress_index` — і саме це робить пару
  # `measured_trees`/`total_trees` кластерного рядка (§13) справжнім числом, а не 100/100.
  next if is_silent

  cherkasy_measured_trees += 1

  # [СИНХРОНІЗОВАНО]: Вчорашній підсумок (The Insight Oracle).
  # 📅 [ARCH.100] Доба звіту — ОДИН дім, `AiInsight.reporting_date`. Доти сід називав її
  # власним виразом (`Date.yesterday`), і збігався той із писачем лише поки `Time.zone`
  # дорівнює UTC; будь-який інший пояс розвів би писача й читача (`for_date` шукає
  # ТОЧНОЮ рівністю), а промах тут ТИХИЙ — порожня вибірка не є помилкою.
  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary,
    target_date: AiInsight.reporting_date,
    average_temperature: is_anomaly ? 38.0 : 21.0,
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
end

puts "🌴 Висаджуємо 20 Солдатів у Amazon Sector..."
# Один вираз напруги на два записи — дзеркало сіда Черкас (див. `packet_voltage_mv`).
amazon_packet_voltage_mv = 3600
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

  # [KYC.1] Тропічний сектор — весь custodial (власної адреси немає), тож mint-гейт
  # читає статус організації-власниці. Розбір обох гілок предиката — у сіді Черкас вище.
  tree.wallet.update!(balance: rand(2000..8000))

  # Дуб (oak): band 8..40, optimum 24 → ставимо homeostasis ~ 24.
  TelemetryLog.create!(
    tree: tree,
    queen_uid: amazon_gw.uid,
    voltage_mv: amazon_packet_voltage_mv,
    temperature_c: 32.0,
    acoustic_events: 3,
    metabolism_s: 20,
    growth_points: 4,
    mesh_ttl: 5,
    bio_status: :homeostasis,
    z_value: 24.0,
    rssi: -rand(55..80)
  )

  # [ARCH.109] Дзеркало сіда вище: мітку «чули» ставить той самий уплінк, що й рядком вище.
  tree.mark_seen!(amazon_packet_voltage_mv)

  AiInsight.create!(
    analyzable: tree,
    insight_type: :daily_health_summary,
    target_date: AiInsight.reporting_date,
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
puts "📜 Кодекс Черкащини: реальні ліси з db/seeds/codex (координати з OSM)..."
# [UI.19, 2026-09-03] Перший читач кодексу (`db/seeds/codex/README.md`). Береться лише те, що
# кодекс має по-справжньому: назва й координати з OSM-провенансом (коментар біля кожної пари в
# самому YAML). Пороги родин НЕ вигадуються — та сама сосна/дуб, що вище (⚖️ OPS.38); квадрат
# ±0.02° навколо центроїда = ДЕМО-екстент, не межа обʼєкта. Кожен ліс: одна Королева, вісім
# Солдатів з одним кадром гомеостазу — щоб мапа показувала ГЕОГРАФІЮ, а не вигаданий сигнал.
codex_ecosystems = YAML.safe_load_file(Rails.root.join("db/seeds/codex/nodes/ecosystems.yml")).index_by { |node| node["slug"] }
codex_forests = [
  [ "kholodnyi-yar",  oak ],  # дубрава Холодного Яру
  [ "kaniv-reserve",  oak ],  # грабово-дубові ліси Канівських круч
  [ "irdynske-bog",   pine ], # болотні соснові ліси Ірдиня
  [ "tyasmyn-canyon", oak ]   # дубово-грабові схили каньйону
]
codex_trees = []
codex_forests.each_with_index do |(slug, family), idx|
  node = codex_ecosystems.fetch(slug)
  lat = node.fetch("latitude").to_f
  lon = node.fetch("longitude").to_f
  d = 0.02
  cluster = Cluster.create!(
    name: node.fetch("title_uk"),
    region: "Центральна Україна",
    organization: active_bridge,
    environmental_settings: { "custom_fire_threshold" => 60, "timezone" => "Europe/Kyiv" },
    geojson_polygon: { type: "Polygon", coordinates: [ [ [ lon - d, lat - d ], [ lon + d, lat - d ], [ lon + d, lat + d ], [ lon - d, lat + d ], [ lon - d, lat - d ] ] ] }
  )
  gw_uid = "SNET-Q-#{format("%08X", 0x10 + idx)}"
  gw = Gateway.create!(
    uid: gw_uid,
    ip_address: "10.0.1.#{5 + idx}",
    latitude: lat,
    longitude: lon,
    cluster: cluster,
    config_sleep_interval_s: 3600,
    last_seen_at: Time.current,
    state: :active
  )
  HardwareKey.create!(device_uid: gw_uid, aes_key_hex: SecureRandom.hex(32).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)

  8.times do |i|
    did = "SNET-#{format("%08X", 300 + (idx * 8) + i)}"
    tree = Tree.create!(
      did: did,
      latitude: lat + rand(-0.008..0.008),
      longitude: lon + rand(-0.008..0.008),
      cluster: cluster,
      tree_family: family,
      tiny_ml_model: family == pine ? pine_acoustic_model : nil
    )
    HardwareKey.create!(device_uid: did, aes_key_hex: SecureRandom.hex(16).upcase, lorenz_seed_hex: SecureRandom.hex(32).upcase)
    tree.wallet.update!(balance: rand(2000..8000))
    TelemetryLog.create!(
      tree: tree,
      queen_uid: gw_uid,
      voltage_mv: 3800,
      temperature_c: 18.0,
      acoustic_events: 2,
      metabolism_s: 20,
      growth_points: 4,
      mesh_ttl: 5,
      bio_status: :homeostasis,
      z_value: family == pine ? 29.0 : 24.0,
      rssi: -rand(55..80)
    )
    tree.mark_seen!(3800)
    codex_trees << tree
  end
end
puts "   📜 Кодекс-ліси: #{codex_forests.size} кластери · #{codex_trees.size} дерев"

puts "🚨 Створення тестових тривог..."
anomaly_tree = cherkasy_trees.last

drought_alert = EwsAlert.create!(
  cluster: cherkasy_forest,
  tree: anomaly_tree,
  alert_type: :severe_drought,
  severity: :medium,
  status: :active,
  # ⛔ [E.64 ⚖️ 2026-09-05] `attractor_destabilised` СЮДИ НЕ ПОВЕРТАТИ: серверну
  # Z-гілку знято, продовий писач такого ключа більше не створює, і сід малював би
  # демо-глядачеві стан, якого система не породжує (клас «фікстура пінить недосяжне»).
  # ⚠️ Чесно про цей рядок: він пишеться ПРЯМО, в обхід `AlertDispatchService`, і
  # живого авто-писача перил посухи сьогодні не має ЖОДНОГО (канон 00_04 §2) — рядок
  # існує, щоб демо мало medium-алерт для UI, а не щоб зображати досяжний стан.
  message_key: "hydrological_stress",
  message_params: {}
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
# 💰 ДВІ ОДИНИЦІ НА ОДНОМУ РЯДКУ, і з імені колонки жодна не видна:
#   `locked_points` = БАЛИ росту (та сама шкала, що `wallets.balance`/`locked_balance`);
#   `amount`, `esg_retired_balance` = МОНЕТИ SCC (лише до них застосовне `×10**18`).
# Курс — `emission_threshold`, засіяний у §0 цього ж файлу: 10 000 балів = 1 SCC.
# ⛔ Доти обидва рядки несли 500 і 250 балів на 10 і 5 монет, тобто курс 50:1 — у 200
# разів дешевший за протокольний, і та сама вигадка стояла в `notes`, які рендерить
# `BlockchainTransactions::Show`. Демо навчало рівно тієї помилки, на виправлення якої
# грошовий тракт витратив місяць.
sample_wallet = cherkasy_trees.first.wallet

# 🔴 Фейковий реєстр §9 — ЛИШЕ на локальних середовищах (`Rails.env.local?`), і межа несуча:
# на canopy (`RAILS_ENV=production`, testnet-слот) ці рядки не демо, а ХИБНЕ СВІДЧЕННЯ.
# `ChainAuditService` рахує `net_minted_supply` (Σ confirmed mint − Σ confirmed burn) і звіряє
# з `totalSupply()` живого SCC на Amoy: сід дав би 10 − 4 = 6 SCC у базі проти 0 у ланцюгу →
# `critical: true` назавжди, і `SystemAuditsController` показував би «фрод» на стейджингу,
# який нікого не мінтив; той самий 6 SCC поїхав би в payload L1-якоря на Sepolia. Реальні
# рядки на canopy пише сам тракт (`TokenomicsEvaluatorWorker` → `lock_and_mint!`), коли
# бігає симулятор [OPS.37 / DR.1 drill]. ⚠️ Дискримінатор — `Rails.env.local?`, як у
# `DEMO_PASSWORD` вище, НЕ слот: обидва деплой-слоти біжать `production`, а dev/test —
# єдині середовища, де вигадана грошова історія доречна.
if Rails.env.local?

# Скільки МОНЕТ цей гаманець уже погасив у KlimaDAO (див. ESG-рядок нижче).
esg_retired_scc = 4

# Гаманець-носій грошового тракту дістає ВЛАСНІ числа, бо решта флоту їх не має:
#   · `locked_balance` = рівно сума `locked_points` обох мінт-рядків нижче. Інакше база
#     суперечить сама собі: транзакції стверджують заблоковані бали на гаманці, де
#     заблоковано нуль, — а `available_balance = balance − locked_balance` є ЄДИНИМ
#     носієм double-spend-гарда, і при `locked_balance = 0` він у демо невидимий;
#   · ⛔ DB-CHECK `wallets_balance_invariants` вимагає `locked_balance <= balance`,
#     тож баланс мусить накривати заблоковане;
#   · `esg_retired_balance` — МОНЕТИ, і рухає його рівно `KlimaDao::RetirementService`
#     (балансових колонок він не чіпає взагалі, [ARCH.95] вісь 3).
sample_wallet.update!(
  balance: 200_000,
  locked_balance: 150_000,
  esg_retired_balance: esg_retired_scc
)

# --- ЕМІСІЯ (`direction: :mint` — дефолт колонки) ---
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
  locked_points: 100_000,
  notes: "Мінтинг 10 SCC за 100 000 балів росту."
)

BlockchainTransaction.create!(
  wallet: sample_wallet,
  amount: 5,
  # ⚖️ [DOC-T.89] `carbon_coin`, не `forest_coin`: правил емісії SFC не існує ніде, тож
  # growth-мінт другого токена демо вигадувало б. Курс — той самий, що в сусіда вище.
  token_type: :carbon_coin,
  status: :pending,
  blockchain_network: "evm",
  to_address: active_bridge.crypto_public_address,
  locked_points: 50_000,
  notes: "Очікує підтвердження в мережі Polygon."
)

# --- ВИЛУЧЕННЯ З ОБІГУ (`direction: :burn`) ---
# 🔴 [ARCH.95] Напрямок несе КОЛОНКА `direction` — ані `sourceable_type`, ані знак
# `amount` (слеш пишеться ДОДАТНИМ). Доти сіди не мали жодного burn-рядка, тож
# `net_minted_supply` ніколи не заходила у власну другу гілку: ані дискримінатор
# напрямку, ані мінусовий рендер `signed_amount` [ARCH.103] не мали на чому спрацювати,
# а стрічка друкувала б спалення емісією й ніхто б цього в демо не побачив.
# Родів вилучення ДВА, і розрізняє їх `sourceable`, а не напрямок.

# (1) SLASH-інтент — форма `BlockchainBurningService#create_slash_intent!`.
# `sourceable: NaasContract` відповідає на ВУЖЧЕ питання «цей burn є СЛЕШЕМ» (база
# розміру, `05_05 §3`); модельний інваріант `slash_intent_must_be_a_burn` не дасть
# записати цей `sourceable` без `direction: :burn`.
# ⚠️ `:pending`, а не `:sent`, і це не дрібниця: контракт переходить у `:breached` рівно
# тоді, коли інтент дістає `tx_hash`, — а обидва засіяні NaaS-контракти лишаються
# `:active`. Отже депіктується стан «інтент створено, broadcast ще не було».
BlockchainTransaction.create!(
  wallet: sample_wallet,
  sourceable: naas_contract,
  amount: 2,
  token_type: :carbon_coin,
  direction: :burn,
  status: :pending,
  blockchain_network: "evm",
  to_address: eco_future_fund.crypto_public_address,
  notes: "🚨 SLASHING: Кошти вилучено. Причина: degradation_checkpoint."
)

# (2) ESG-ПОГАШЕННЯ — форма `KlimaDao::RetirementService#create_retirement_transaction`.
# ⛔ `sourceable` тут НЕМА свідомо: погашення слешем не є, і саме ця відсутність робила
# стару деривацію напрямку хибною. `:confirmed` — щоб burn-гілка `net_minted_supply`
# (вона рахує ЛИШЕ підтверджені) справді працювала; запас монет гаманця після цього
# рядка = 10 − 4 = 6 SCC, тобто гард `retirable_scc` лишається несуперечливим.
BlockchainTransaction.create!(
  wallet: sample_wallet,
  amount: esg_retired_scc,
  token_type: :carbon_coin,
  direction: :burn,
  status: :confirmed,
  blockchain_network: "evm",
  # Плейсхолдер адреси `KLIMA_RETIREMENT_CONTRACT` — сід не вигадує чужу справжню.
  to_address: "0x#{SecureRandom.hex(20)}",
  tx_hash: "0x#{SecureRandom.hex(32)}",
  sent_at: 40.minutes.ago,
  confirmed_at: 30.minutes.ago,
  notes: "🌿 ESG Retirement via KlimaDAO: #{esg_retired_scc} SCC погашено для вуглецевої нейтральності."
)

end # Rails.env.local? — фейковий реєстр §9 (див. підставу над `if`)

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
  # GPS огляду = координати самого дерева (форестер стояв біля вузла), не центр міста.
  latitude: cherkasy_trees[10].latitude,
  longitude: cherkasy_trees[10].longitude
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

# ⏱️ Наказ, породжений ТРИВОГОЮ, несе TTL — інакше він живий вічно. `scope :live_pending`
# матчить `expires_at IS NULL OR expires_at > now`, а контролер тримає на ньому 409: без
# цього рядка засіяна сирена назавжди відрізала форестера від власного актуатора, і
# `scope :expired` такий труп не бачить ніколи. 15 хв — вікно релевантності кроку
# `fire_siren` з `EmergencyResponseService::PROTOCOLS`, тобто число не вигадане тут.
ActuatorCommand.create!(
  actuator: fire_siren,
  ews_alert: fire_alert,
  command_payload: "ACTIVATE:120",
  duration_seconds: 120,
  priority: :high,
  status: :issued,
  expires_at: 15.minutes.from_now
)

# =========================================================================
# 12. АУДИТ-ЛОГИ (AuditLog)
# =========================================================================
puts "📋 Запис аудит-логів..."
# [I18N.1] `action:` — лише значення РЕАЛЬНИХ писачів (`record_audit_trail!`-сайти):
# доти сіди несли dot-конвенцію (`cluster.create`…), якої не пише жоден код, тож
# dev-БД брехала про можливі значення журналу.
#
# 🔴 [ARCH.57] Актор запису живе у ВЛАСНИХ колонках `ip_address`/`user_agent`, не в
# `metadata`. Це не форматування: обидві входять у `chain_payload`, тобто в ланцюговий
# хеш, і саме тому tamper по актору через `update_all` видно `verify_chain_integrity`;
# плюс `scope :by_ip` фільтрує колонку. Доти сід клав ті самі факти всередину JSONB —
# журнал ставав неперевірним по актору, а фільтр по IP не знаходив нічого.
# ⊕ Ключі `metadata` — рядки в усіх трьох рядках: `chain_payload_from_row` сортує ключі
# для детермінізму, тож мішанина символів і рядків в одному JSONB нічого не «економить».
AuditLog.create!(
  user: alexey,
  organization: active_bridge,
  action: "user_role_changed",
  auditable: alexey,
  ip_address: "192.168.1.1",
  user_agent: "SilkenNetAdmin/1.0",
  metadata: { "from" => "forester", "to" => "admin" }
)

AuditLog.create!(
  user: subscriber,
  organization: eco_future_fund,
  action: "naas_contract_to_active",
  auditable: naas_contract,
  ip_address: "10.0.0.1",
  user_agent: "Chrome/120.0",
  metadata: { "from" => "draft", "to" => "active" }
)

# Системний бот працює без HTTP-запиту, тож `ip_address`/`user_agent` тут порожні —
# і це стан, а не прогалина: писача-людини в цього рядка немає.
AuditLog.create!(
  user: oracle,
  organization: active_bridge,
  action: "slash_verdict_frozen",
  auditable: naas_contract,
  metadata: { "source" => "DailyAggregationWorker", "trees_evaluated" => 100 }
)

# =========================================================================
# 13. AI ІНСАЙТИ НА РІВНІ КЛАСТЕРА
# =========================================================================
puts "🧠 Генерація AI інсайтів для кластерів..."
# 🔴 [ARCH.84] Кластерний рядок — АГРЕГАТ, і він зобов'язаний нести власне ПОКРИТТЯ:
# `measured_trees`/`total_trees` (форма `InsightGeneratorService#aggregate_cluster!`).
# Без цієї пари `stress_index` кластера, порахований по двох деревах зі ста, машинному
# читачеві невідрізнимий від порахованого повністю — а читачі тут не косметичні
# (`health_index` → комерційний `backing_asset.cluster_health`, Celo-виплата, IPFS-доказ).
# Числа беруться з реального прогону сіда, не з голови: дві мовчунки §7 у добовий агрегат
# не входять, тож пара тут ЩОСЬ розрізняє, а не декорує рівністю 100/100.
AiInsight.create!(
  analyzable: cherkasy_forest,
  insight_type: :daily_health_summary,
  target_date: AiInsight.reporting_date,
  stress_index: 0.12,
  summary: "Сектор #{cherkasy_forest.name}: Оброблено #{cherkasy_measured_trees} вузлів. Стан стабільний.",
  reasoning: {
    avg_z: 28.5, max_temp: 24.0, source: "ClusterHealthCheckWorker",
    measured_trees: cherkasy_measured_trees, total_trees: cherkasy_forest.trees.active.count
  }
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
  target_date: AiInsight.reporting_date,
  stress_index: 0.45,
  summary: "Підвищений стрес через виявлену пожежу на периферії.",
  reasoning: {
    avg_z: 41.5, max_temp: 62.0, source: "ClusterHealthCheckWorker",
    measured_trees: amazon_sector.trees.active.count, total_trees: amazon_sector.trees.active.count
  }
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
# 15. ДЕНОРМАЛІЗАЦІЯ (counter cache + health_index)
# =========================================================================
puts "🔄 Синхронізація денормалізованих колонок..."
Cluster.find_each do |cluster|
  active_count = cluster.trees.active.count
  cluster.update_column(:active_trees_count, active_count)
end

# [ARCH.84] `health_index` пише сід — рівно як `ClusterHealthCheckWorker` після добового
# агрегату. Доти колонка лишалась NULL на ОБОХ кластерах, тобто кожна комерційна поверхня
# рендерила «не виміряно», а `Cluster.health_coverage` віддавала 0 з 2 — при тому, що
# кластерні `daily_health_summary` у §13 уже стояли. ⛔ Кличемо метод моделі, а не пишемо
# число: він єдиний знає, що `nil` (немає виміру) ≠ `1.0` (виміряний ідеал), і бере добу
# з `AiInsight.reporting_date` — того самого дому, яким §13 штампує `target_date` [ARCH.100].
Cluster.find_each(&:recalculate_health_index!)

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
puts "         subscriber (read_only):     #{User.role_subscriber.count}"
puts "   🌲 Кластери:            #{Cluster.count}"
puts "   🧬 Породи дерев:        #{TreeFamily.count}"
puts "   🌳 Дерева:              #{Tree.count}"
puts "   📡 Шлюзи (Queens):      #{Gateway.count}"
puts "   ⚙️  Актуатори:           #{Actuator.count}"
puts "   🎛️  Накази актуаторам:   #{ActuatorCommand.count}"
puts "   🧠 TinyML моделі:       #{TinyMlModel.count}"
puts "   📐 Калібрування:        #{DeviceCalibration.count}"
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
