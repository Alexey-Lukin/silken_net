# 00_06: Strategic Roadmap, TRL Matrix and HIL Simulators

## 🎯 Мета

Визначити життєвий цикл компонентів Gaia 2.0 та стратегічні етапи масштабування проєкту. Цей документ перетворює технічну складність на послідовний графік досягнення рівнів технологічної готовності (TRL) та бізнес-метрик, **і одночасно усуває проблему TRL-Lock** через концепцію Hardware-in-the-Loop (HIL) симуляторів — програмні домени продовжують рухатись до TRL 8-9 паралельно фізичним відставанням металу/хімії.

---

## ✅ Статус

- **Поточний TRL (System):** TRL 4 — обмежений найнижчим модулем (EBFC TRL 3-4).
- **Per-domain TRL (декаплінг):** Rails TRL 8, Web3 / Smart contracts TRL 8–9 (Solidity ready для mainnet), DevOps TRL 7 (Docker registry та TLS — open у [`00_08 §TRL Матриця`](00_08_Action_Plan_Tracker)), Firmware TRL 6, Security TRL 7 (Rails web layer ✅), Hardware TRL 4 (Stages 1-3 ще не закриті). **Канонічне джерело per-module TRL — `00_08 §TRL Матриця` (line ~1183-1192)**; цей рядок є снапшотом для швидкої навігації, оновлюється при кожному cool-down.
- **Пов'язані модулі:**
  - Бізнес-візія та slashing → [`00_01_Vision_Market_and_Slashing_Policy`](00_01_Vision_Market_and_Slashing_Policy)
  - AI-Native методологія (TRL philosophy) → [`00_04_AI_Native_Engineering_and_TRL`](00_04_AI_Native_Engineering_and_TRL)
  - Shape Up operations → [`00_05_Shape_Up_Operations_and_RnD_Clusters`](00_05_Shape_Up_Operations_and_RnD_Clusters)
  - GitHub Projects + IaC → [`00_07_GitHub_Projects_and_IaC_Automation`](00_07_GitHub_Projects_and_IaC_Automation)

---

## 📊 1. Матриця готовності Silken Net (The TRL Matrix)

Ми адаптували шкалу NASA TRL для кіберфізичних екосистем. Проєкт рухається від фундаментальної лабораторії до глобальної фіналізації.

| Рівень | Етап | Технічний критерій (Evidence) | Лабораторія / Хаб |
|:---|:---|:---|:---|
| **TRL 1-2** | Ідея / Принцип | Математичне обґрунтування EBFC та Атрактора Лоренца. | ЧНУ (Хімія/Фізика) |
| **TRL 3-4** | Proof of Concept | Валідація 44 мВ → 3.3V та перша транзакція в Sandbox. | ЧНУ (ФОТІУС) |
| **TRL 5-6** | Прототипування | Робота кластера "Солдат-Королева" в Черкаському борі (30 днів). | Silken Lab |
| **TRL 7-8** | Кваліфікація | Повна інтеграція: DID → ZK-Proof → Chainlink → Polygon. | Production (Canopy) |
| **TRL 9** | Експлуатація | Стабільний мінтинг SCC на мільйонах вузлів, фіналізація в L1. | Global Mainnet |

---

## 🗺️ 2. Стратегічні фази масштабування (The Roadmap)

### 🌿 Фаза 1: The Heartbeat (2024-2025) — "Доказ життя"
- **Ціль:** Довести неможливість фальсифікації біологічних даних.
- **Ключові задачі:**
    - Інтеграція **peaq DID** для ідентифікації кожного дерева.
    - Налаштування **IoTeX W3bstream** для генерації ZK-доказів гомеостазу.
    - Перший "зелений" мінтинг SCC для одного пілотного кластера.

### 🌲 Фаза 2: The Forest Mesh (2025-2026) — "Автономність"
- **Ціль:** Розгортання децентралізованої інфраструктури.
- **Ключові задачі:**
    - Масовий друк титанових анкерів (Batch Production в Україні).
    - Деплой бекенду на **Akash Network** для цензуростійкості.
    - Запуск публічного дашборду на **The Graph** для глобального аудиту вуглецю.

### 🌎 Фаза 3: The Sovereign State (2026+) — "Економіка"
- **Ціль:** Nature-as-a-Service (NaaS) як глобальний фінансовий стандарт.
- **Ключові задачі:**
    - Впровадження автоматичного страхування (Parametric Insurance) через смарт-контракти.
    - Щотижнева фіналізація стану лісів у **Ethereum L1 Mainnet**.
    - Інтеграція з **KlimaDAO** для автоматичного спалювання активів корпораціями.

---

## 🛡️ 3. Принцип "TRL-Lock" → "TRL-Layered Independence"

> **Стара формулювання (Waterfall):** *"Жоден компонент не може бути переведений у стан Production, якщо він не досяг TRL 7. Якщо апаратна частина анкера на рівні TRL 4, а софт на TRL 8 — загальний статус модуля залишається TRL 4."*

Це лінійне правило знищує сенс Concurrent Engineering. Якщо Rails-модуль, токеноміка і Web3-мости готові до TRL 8, вони не повинні чекати, поки хіміки з ЧМА закінчать роботу з EBFC.

### Нова формулювання (Concurrent + HIL):

1. **System TRL** залишається обмеженим найнижчим модулем — це чесна метрика для grant заявок та regulator-комунікації ("система готова до пілоту тоді й тільки тоді, коли всі шари готові").
2. **Per-domain TRL** є **незалежним** і відстежується в `docs/00_06 §TRL Matrix` per-module. Software може бути TRL 8 коли Hardware TRL 4.
3. **HIL Simulators** (Hardware-in-the-Loop) — програмні генератори, які імітують поведінку реального hardware, дозволяють software-домену пройти TRL 5-8 без живої EBFC/анкера.

---

## 🧪 4. HIL Simulators — Програмне розблокування Software TRL

### 4.1 Чому це критично

Поточна політика блокувала весь TRL модулів 04 (Rails) і 05 (Web3) на TRL 4-5, попри те, що:

- `BlockchainMintingService` має 1092-рядкову spec з повним покриттям (`04_06 §B.1.2`).
- `TelemetryUnpackerService` 560+ рядків spec; CoAP Encryption concern, Web3CircuitBreaker concern.
- Solidity contracts: 171 тест Foundry + Slither static analysis.
- 31 Sidekiq worker, 9-рівнева черга з суворим пріоритетом.

Усе це **готове до production**. Без HIL — заблоковане TRL 4 формальністю.

### 4.2 HIL-симулятори в SilkenNet

| Симулятор | Імітує | Файл | Замінює реальний компонент для |
|-----------|--------|------|-------------------------------|
| `bin/forest_simulator` | LoRa-flow з 5–15 Soldier'ів, CoAP-пакети кожні 3–8 сек, AES-256-CBC encrypted, full Lorenz attractor curves | `bin/forest_simulator` (вже існує) | Локальна розробка Rails + sidekiq + Web3 pipeline |
| `HilQueenSimulator` | Queen self-telemetry (`DID == 0x00000000`), CIFO flush, Starlink/LTE timing | новий: `lib/hil/queen_simulator.rb` (планований) | Test Queen failover ([`00_03 §Queen Failover`](00_03_Resilience_and_Failover_Policy)) |
| `HilWebPipelineSimulator` | peaq → IoTeX → Chainlink → Polygon → KlimaDAO → Filecoin → L1 — повний 12-chain mock з deterministic responses | `WEB3_STRICT_MODE=false` + stub services у `app/services/web3/*_stub.rb` | E2E pipeline тестування + load testing на Akash |
| `HilLorenzGenerator` | mruby Lorenz curves з різних tree species, environmental conditions (temp, vibration), faulty/normal patterns | `lib/hil/lorenz_generator.rb` (планований) | TinyML training data + Rails Attractor validation |
| `HilAttackerScenarios` | Bit-flip attacks, replay attacks, hardware tamper detection, dual-computation divergence > 30% | RSpec scenarios у `spec/integration/security/` (частково існує) | Anti-fraud cross-checks ([`00_01 §6.5`](00_01_Vision_Market_and_Slashing_Policy)) |

### 4.3 TRL Промоція через HIL

| Per-domain TRL | Hardware TRL Required | HIL Equivalent | Status |
|----------------|----------------------|----------------|--------|
| Software TRL 5 (Prototype validated) | Hardware TRL 5 (анкер у дереві 30 днів) | `bin/forest_simulator` + integration tests | ✅ Достатньо |
| Software TRL 6 (Demonstration in relevant environment) | Hardware TRL 6 (LoRa mesh у канопі) | HIL Queen Simulator + Akash staging deploy + multi-node forest_simulator | 🟡 Частково (HIL Queen ще не написаний) |
| Software TRL 7 (Operational prototype) | Hardware TRL 7 (pilot 100 дерев) | Все HIL + chaos engineering + Solana/Celo testnet smoke | 🟡 Частково (chaos engineering — `proof_of_growth_chaos_engineering` integration test exists) |
| Software TRL 8 (Production-validated) | Hardware TRL 8 (1000+ дерев у полі) | Все HIL + Polygon mainnet integration tests + Slither high-severity = 0 + multi-sig deployment dry-run | 🟢 Досягнуто для smart-contracts (TRL 9 ready) |

### 4.4 Прозорість

> HIL-симулятори **не приховують** фізичне відставання — `docs/README.md` Current Stat показує **System TRL** (4) поряд із **per-domain TRL** (Rails 8, Solidity 9, EBFC 3). Це чесніше, ніж блокувати Software на TRL 4 формальністю TRL-Lock.

---

## 📅 5. Поточний фокус (Cycle Focus)

Поточний 6-тижневий цикл (Shape Up, [`00_05`](00_05_Shape_Up_Operations_and_RnD_Clusters)) зосереджений на:

- **EBFC (Module 01) TRL 4 → 6** — Stages 1-3 закрити (5 SLA-макетів → 10 Ti-monets → 3-5 повноцінних SLM+HIP анкерів).
- **ZK-Pipeline (Module 05) TRL 7 → 8** — IoTeX → Chainlink → Polygon Mainnet smoke з реальним LINK token balance.
- **HIL Queen Simulator (Module 03/04) TRL 0 → 5** — реалізація `HilQueenSimulator` для розблокування Queen failover testing без живого STM32WLE5JC.

---

## 🔗 6. Cross-ref

- `docs/00_04 §TRL` — філософська основа метрики прогресу.
- `docs/00_05 §Async-Review` — як TRL Gates інтегруються з review policy.
- `docs/00_07 §TRL Auto-Advancement` — як HIL-валідація рухає Projects V2 cards автоматично.
- `docs/04_06 §B Coverage Matrix` — як HIL виміри транслюються у RSpec/Firmware/Foundry coverage.
- `docs/08_*` — фізичні валідаційні протоколи (TRL 1-4 партнерських ВНЗ).
