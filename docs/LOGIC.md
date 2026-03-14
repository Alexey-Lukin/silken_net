# 🌲 Silken Net: Специфікація Логічного Ядра — Gaia 2.0 (Services & Workers)

Цей документ описує архітектуру сервісів та фонових воркерів екосистеми **Silken Net** — Кіберфізичної Держави (Cyber-Physical State), що інтегрує 12 блокчейн-мереж та протоколів для trustless D-MRV.

---

## 🧠 I. Сервіси (Services) — Логічне ядро

Сервіси відповідають за складні обчислення, інтерпретацію бінарних даних та взаємодію з мультичейн-інфраструктурою.

### Ядро (Core Services)

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`SilkenNet::Attractor`** | **Математичне серце** | Реалізація атрактора Лоренца. Розраховує Z-значення з BigDecimal (18 знаків) для крос-платформної детермінованості та юридичної точності Web3-аудиту. |
| **`TelemetryUnpackerService`** | **L3 Декодер** | Розпаковує 21-байтні бінарні чанки телеметрії. Проводить калібрування сенсорів та первинний розрахунок Z-стабільності. |
| **`OtaPackagerService`** | **Кузня Оновлень** | Фрагментує прошивки та TinyML-моделі на пакети під MTU (LoRa/CoAP). Додає заголовки цілісності та маніфести. |
| **`AlertDispatchService`** | **Нервовий Центр** | Аналізує вхідні дані на предмет пожеж, вандалізму чи стресу. Приймає рішення про створення `EwsAlert`. |
| **`EmergencyResponseService`** | **Рефлектор Дії** | Визначає протокол фізичної відповіді (відкриття клапанів, сирен) на основі типу загрози в кластері. |
| **`HardwareKeyService`** | **Ключник** | Керує життєвим циклом AES-256 ключів. Реалізує протокол **Dual-Key Handshake** для безпечної ротації. |
| **`InsightGeneratorService`** | **Оракул** | Добова агрегація. Включає **AI Fraud Guard**, що перевіряє дерева на фрод через порівняння з кліматичним базлайном. |
| **`PriceOracleService`** | **Ціновий Арбітр** | Отримує ціну SCC/USDC з Uniswap V3 Quoter на Polygon. Кеш 5 хвилин, фолбек на Series A base price ($25.50). |

### Блокчейн — Polygon (Primary Chain)

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`BlockchainMintingService`** | **Скарбник** | Пакетна емісія токенів (SCC/SFC) у мережі Polygon. Guard clauses: `verified_by_iotex?`, `oracle_status == "fulfilled"`, `hadron_kyc_status == "approved"`. Оптимізовано для Gas Saving Mode (`batchMint`). |
| **`BlockchainBurningService`** | **Меч Правосуддя** | Розраховує суму вилучення та ініціює блокчейн-функцію `slash` при порушенні умов контракту. |
| **`ChainAuditService`** | **Цифровий Нотаріус** | Аудит on-chain транзакцій. Звіряє статуси `BlockchainTransaction` з реальним `totalSupply` у Polygon. Поріг дельти: 0.0001. |
| **`Etherisc::ClaimService`** | **Щит DIP** | Oracle-mode для параметричного страхування. Тригерить `triggerClaim` через Etherisc Decentralized Insurance Protocol (DIP) на Polygon для виплати USDC з децентралізованого пулу ліквідності. Усуває інфляційний тиск на внутрішню токеноміку. |

### Верифікація та Ідентичність (ZK + DID)

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`Iotex::W3bstreamVerificationService`** | **Абсолютна Істина** | Відправляє телеметрію до IoTeX W3bstream для генерації ZK-proof. Підтверджує, що дані надійшли з реального кремнію (hardware signature), а Лоренц-математика підтверджує гомеостаз. Guard clause: обов'язково перед Chainlink. |
| **`Peaq::DidRegistryService`** | **Паспорт** | Генерує peaq DID: `did:peaq:0x{SHA256[0:40]}` на основі `hardware_identifier + tree_id + created_at`. Реєструє у peaq network — self-sovereign identity для лісових активів. |
| **`Chainlink::OracleDispatchService`** | **Нервовий Імпульс** | Відправляє верифіковану телеметрію до Chainlink Functions DON (Polygon Router). Payload: peaq_did, lorenz_state, zk_proof_ref, tree_did. Guard clause: `verified_by_iotex? == true`. |

### Мультичейн — Паралельні Фінансові Рейки

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`Solana::MintingService`** | **Мікро-Життя** | Паралельна система мікро-платежів на Solana. USDC нагороди (0.01–0.1 USDC) за кожен пакет телеметрії. JSON RPC `simulateTransaction` (Devnet) / `sendTransaction` (Mainnet). |
| **`Celo::CommunityRewardService`** | **Голос Громади** | Відправляє 5 cUSD на гаманець організації за здоровий кластер (`stress_index ≤ 0.2`). ReFi (Regenerative Finance) модель для підтримки місцевих громад. |
| **`KlimaDao::RetirementService`** | **Очищення** | ESG-ретайрмент вуглецевих кредитів через KlimaDAO. Двокрокова атомарна транзакція: Approve → Retire. Переводить токени до `esg_retired_balance` (необоротно). |
| **`Polygon::HadronComplianceService`** | **Макро-Капітал** | KYC/KYB верифікація через Polygon Hadron Identity Platform. ERC-3643 compliance для інституційних інвесторів. Два потоки: `verify_investor!` (KYC) та `register_asset!` (RWA реєстрація). |

### Фіналізація та Збереження (Finality & Storage)

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`Ethereum::StateAnchorService`** | **Останній Суд** | Щотижневий SHA-256 state root (`total_scc + chain_hash + timestamp`) → Ethereum Mainnet. Rollup-style finality. Gas-efficient: 1 запис `bytes32` на тиждень. |
| **`Filecoin::ArchiveService`** | **Вічна Пам'ять** | Архівує AuditLog записи (chain_hash, добові зведення) до IPFS/Filecoin через Pinata API. Кожен запис отримує унікальний CID. |
| **`Filecoin::VerificationService`** | **Верифікатор Пам'яті** | Перевіряє цілісність архівних записів на IPFS шляхом порівняння chain_hash з локальною базою. |

### Потоки Даних та Індексація (Data Streams)

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`Streamr::BroadcasterService`** | **Голос Лісу** | Real-time broadcast телеметрії в Streamr P2P мережу. Payload: tree_id, peaq_did, z_value, bio_status, alerts. Non-blocking, non-critical — для живого пульсу, не для фінансового консенсусу. |
| **`TheGraph::QueryService`** | **Глобальне Бачення** | GraphQL запити до The Graph subgraph (Polygon). Індексує `CarbonMinted` events. Повертає `total_carbon_minted` для дашбордів та третіх сторін. |

### Геопросторові Утиліти

| Сервіс | Функція | Опис |
| --- | --- | --- |
| **`SilkenNet::GeoUtils`** | **Навігатор** | Haversine distance calculation (WGS-84). Використовується для proximity-based пріоритизації актуаторів. |

---

## ⚙️ II. Воркери (Workers) — Виконавчі м'язи

Асинхронні процеси Sidekiq (26 воркерів, 7 пріоритетних черг), що забезпечують масштабованість та відмовостійкість системи.

### 📡 Рівень Зв'язку (Uplink/Downlink)

1. **`UnpackTelemetryWorker`** (`uplink`, retry: 3): Вхідна точка для CoAP/UDP. Дешифрує батчі та підтверджує успішну ротацію ключів шлюзу.
2. **`GatewayTelemetryWorker`** (`uplink`, retry: 2): Діагностика "Королев" (шлюзів). Стежить за напругою батарей, температурою вузлів та сигналом зв'язку.
3. **`ActuatorCommandWorker`** (`downlink`, retry: 3): Доставка наказів на актуатори. Використовує Grace Period для вибору вірного ключа шифрування.
4. **`ResetActuatorStateWorker`** (`downlink`, retry: 3): **Кенозис**. Автоматично повертає актуатор у стан спокою після завершення часу дії наказу.
5. **`OtaTransmissionWorker`** (`downlink`, retry: false): Транслятор еволюції. Передає прошивки чанк за чанком, враховуючи час запису у Flash-пам'ять STM32.

### ⚖️ Рівень Аудиту та Токеноміки

6. **`DailyAggregationWorker`** (`low`, retry: 3, lock: :until_executed): **Хронометрист**. Диригент добового циклу (01:00 UTC). Запускає агрегацію інсайтів та подальший ланцюг аудиту. Ланцюг: → `ClusterHealthCheckWorker`.
7. **`ClusterHealthCheckWorker`** (`default`, retry: 3): **Вартовий** (02:00 UTC). Ретроспективний аудит NaaS-контрактів. Ланцюг: → `CeloRewardWorker` (здоровий) або → `BurnCarbonTokensWorker` (порушений).
8. **`TokenomicsEvaluatorWorker`** (`default`, retry: 3): **NAM-ŠID** (щогодини). Аудит балів росту та ініціація емісії SCC, якщо поріг у 10,000 балів перетнуто.
9. **`MintCarbonCoinWorker`** (`web3`, retry: 5): **NAM-TAR**. Емісійний вузол. Включає протокол атомарного ролбеку балів при критичних помилках RPC.
10. **`BurnCarbonTokensWorker`** (`critical`, retry: 5): **Екзекутор**. Негайне виконання Slashing-вироку та створення "надгробного" запису в MaintenanceRecord.
11. **`BlockchainConfirmationWorker`** (`web3`, retry: 10): **Свідок**. Поллінг `eth_get_transaction_receipt`. Підтверджує (`confirmed`) або скасовує (`failed`) транзакцію після отримання рецепту від Polygon.
12. **`InsurancePayoutWorker`** (`critical`, retry: 10): **Гарант**. Автоматичне виконання виплат за параметричним страхуванням при настанні страхових подій. Підтримує dual-mode: внутрішній мінтинг (SCC/SFC) або зовнішній Etherisc DIP claim (USDC) через `Etherisc::ClaimService`.
13. **`EcosystemHealingWorker`** (`critical`, retry: 3): **Лікар**. Критична корекція аномалій в екосистемі. Ініціює відновлювальні заходи після EWS-тривог.

### 🔗 Рівень Мультичейну (Web3 — Gaia 2.0)

14. **`IotexVerificationWorker`** (`web3`, retry: 5): **Абсолютна Істина**. Відправляє телеметрію до IoTeX W3bstream для ZK-proof генерації. Оновлює `verified_by_iotex` та `zk_proof_ref`. Ланцюг: → `ChainlinkDispatchWorker`.
15. **`ChainlinkDispatchWorker`** (`web3`, retry: 5): **Нервовий Імпульс**. Відправляє верифіковану телеметрію до Chainlink Functions DON. Guard: тільки якщо `verified_by_iotex? == true`.
16. **`PeaqRegistrationWorker`** (`web3`, retry: 5): **Паспортист**. Реєструє peaq DID для дерева (`did:peaq:0x...`). Зберігає `peaq_did` на моделі Tree.
17. **`SolanaMicroRewardWorker`** (`web3`, retry: 3): **Мікро-Життя**. Паралельні USDC мікро-платежі на Solana. Composite PK для partition pruning.
18. **`CeloRewardWorker`** (`web3`, retry: 3): **Голос Громади**. Відправляє 5 cUSD організації за здоровий кластер. ReFi incentive.
19. **`KlimaRetirementWorker`** (`web3`, retry: 3): **Очищення**. ESG carbon retirement через KlimaDAO. Handles: InsufficientBalanceError, InvalidTokenTypeError.
20. **`EthereumAnchorWorker`** (`web3`, retry: 3): **Останній Суд** (щопонеділка 03:00 UTC). Щотижневий state root → Ethereum L1. Запускається після завершення всіх нічних циклів.
21. **`HadronAssetRegistrationWorker`** (`web3`, retry: 5): **Реєстратор RWA**. Реєструє лісову ділянку як Real World Asset у Polygon Hadron.

### 📢 Рівень Оповіщення

22. **`AlertNotificationWorker`** (`alerts`, retry: 5): **Голос Цитаделі**. Багатоканальна розсилка тривог: ActionCable (UI), Push-сповіщення та SMS (для Critical Severity).
23. **`SingleNotificationWorker`** (`alerts`, retry: 5): **Особистий Кур'єр**. Точкове сповіщення конкретного патрульного (SMS/Telegram) при призначенні завдання.

### 📦 Рівень Децентралізованого Сховища та Стрімінгу

24. **`FilecoinArchiveWorker`** (`low`, retry: 5): **Архіваріус**. Архівує AuditLog записи до IPFS/Filecoin для незнищенної довгострокової пам'яті. Запускається автоматично після `AuditLogWorker`.
25. **`AuditLogWorker`** (`low`, retry: 3): **Летописець**. Створення аудит-записів у фоновому режимі з автоматичним запуском архівації на Filecoin.
26. **`StreamrBroadcastWorker`** (`low`, retry: 3): **Голос Лісу**. Real-time broadcast телеметрії у Streamr P2P мережу. Non-critical: не блокує основний потік.

---

## 🔄 III. Ланцюг Воркерів (Worker Chaining — The Heartbeat)

```
┌─── UPLINK (real-time) ───────────────────────────────────────────────────┐
│ CoAP packet → UnpackTelemetryWorker                                      │
│   ├→ StreamrBroadcastWorker (P2P broadcast, non-blocking)                │
│   ├→ IotexVerificationWorker (ZK-proof)                                  │
│   │    └→ ChainlinkDispatchWorker (oracle dispatch)                      │
│   │         └→ MintCarbonCoinWorker (Polygon mint)                       │
│   │              └→ BlockchainConfirmationWorker (+30s polling)           │
│   ├→ SolanaMicroRewardWorker (parallel micro-payment)                    │
│   └→ AlertDispatchService → AlertNotificationWorker / ActuatorCommand    │
└──────────────────────────────────────────────────────────────────────────┘

┌─── HOURLY ───────────────────────────────────────────────────────────────┐
│ TokenomicsEvaluatorWorker                                                │
│   └→ MintCarbonCoinWorker (batch) → BlockchainConfirmationWorker         │
└──────────────────────────────────────────────────────────────────────────┘

┌─── DAILY (01:00–02:00 UTC) ──────────────────────────────────────────────┐
│ DailyAggregationWorker (01:00)                                           │
│   └→ InsightGeneratorService → AiInsight per tree                        │
│       └→ ClusterHealthCheckWorker (02:00)                                │
│           ├→ Healthy: CeloRewardWorker (5 cUSD)                          │
│           └→ Breached: BurnCarbonTokensWorker → Sovereign Slashing       │
│               └→ AuditLogWorker → FilecoinArchiveWorker (IPFS)           │
└──────────────────────────────────────────────────────────────────────────┘

┌─── WEEKLY (Monday 03:00 UTC) ────────────────────────────────────────────┐
│ EthereumAnchorWorker → Ethereum L1 State Root (bytes32)                  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 📐 IV. Математичні модулі

* **`SilkenNet::Attractor`**: Математичне серце системи. Реалізація атрактора Лоренца для визначення біологічного гомеостазу.

$$\begin{cases} \dot{x} = \sigma(y - x) \\ \dot{y} = x(\rho - z) - y \\ \dot{z} = xy - \beta z \end{cases}$$

Константи: σ = 10.0, ρ = 28.0, β = 8/3. Адаптивні параметри: акустика → σ (clamped 5–30), температура → ρ (clamped 10–50). DID дерева задає унікальні початкові умови. 250 ітерацій × 0.01 timestep. BigDecimal 18 знаків.

Використовується для ідентифікації стресу дерева через відхилення траєкторії $z$ у фазовому просторі. Верифікується ZK-proof через IoTeX W3bstream.

---

## 🛡️ V. Політика Безпеки

1. **Zero-Trust:** Кожен пакет шифрується AES-256 (Hardware-bound ключ у `HardwareKey`).
2. **Idempotency:** Всі фінансові воркери мають захист від повторного виконання (status guards / pessimistic lock).
3. **Resilience:** Система підтримує 10+ ретраїв для Web3 операцій та 3–5 для апаратних команд.
4. **BigDecimal:** Розрахунки Атрактора виконуються з 18 знаками точності для крос-платформної детермінованості вироків.
5. **ZK-Proof Guard:** Мінтинг токенів неможливий без IoTeX W3bstream верифікації (`verified_by_iotex? == true`).
6. **Chainlink Guard:** Децентралізований оракул обов'язковий перед емісією — запобігає single-point-of-failure.
7. **Hadron KYC:** Інституційні інвестори мусять пройти KYC/KYB через Polygon Hadron (ERC-3643) перед отриманням RWA-токенів.
8. **L1 Finality:** Щотижневий state root на Ethereum Mainnet — незнищенний якір усієї економіки.
9. **Immutable Archive:** SHA-256 chain_hash per organization → Filecoin/IPFS (CID) — дані доступні навіть після знищення серверів.

---

## 🏗️ VI. Архітектурні Патерни (Infrastructure Patterns)

### Базові класи та утиліти

| Компонент | Призначення |
| --- | --- |
| **`ApplicationService`** | Базовий клас для всіх сервісів. Надає `.call(...)` → `#perform` template pattern. |
| **`ApplicationWeb3Worker`** | Базовий модуль для блокчейн-воркерів. Стандартизована обробка RPC-помилок, структуроване логування, partition-pruned lookup. |

### Web3 Utility Layer (`app/services/web3/`)

| Утиліта | Призначення |
| --- | --- |
| **`Web3::HttpClient`** | Централізований HTTP-клієнт для всіх зовнішніх API (IPFS, IoTeX, Streamr, Hadron, The Graph, peaq, Solana). Уніфіковані таймаути, автоматичний SSL, lazy JSON parsing. |
| **`Web3::RpcConnectionPool`** | Thread-safe кешування `Eth::Client` інстансів per-thread. Запобігає повторним TCP/TLS handshakes у Sidekiq-потоках. Підтримує `fallback:` URL для testnet. |
| **`Web3::WeiConverter`** | BigDecimal-based конвертація між human-readable та wei (ERC-20, 18 decimals). Запобігає втраті точності у фінансових операціях. |

### Виділені сервіси NaasContract

| Сервіс | Призначення |
| --- | --- |
| **`ContractHealthCheckService`** | Перевірка здоров'я кластера відносно порогу NaasContract (20% критичних дерев). Ініціює Slashing Protocol при порушенні. |
| **`ContractTerminationService`** | Дострокове розірвання NaasContract з розрахунком пропорційного повернення та штрафу. |

### Model Concerns

| Concern | Моделі | Призначення |
| --- | --- | --- |
| **`GeoLocatable`** | Tree, Gateway, MaintenanceRecord | Уніфікована валідація WGS-84 координат (latitude -90..90, longitude -180..180). |
| **`NormalizeIdentifier`** | Tree, Gateway, HardwareKey | Нормалізація UID/DID через Rails `normalizes` DSL (strip + upcase). |
| **`CoapEncryption`** | Downlink workers | Централізоване AES-256-CBC шифрування для CoAP-пакетів з випадковим IV. |

> **Статус документа:** Актуально.
> **Версія системи:** Gaia 2.0 (Cyber-Physical State).
