# 00_03: TRL Matrix, HIL & Beyond-TRL-9

## 🎯 Мета

Канонічний дім **per-module TRL-матриці** (§1), принципу **TRL-Layered-Independence** (§2) та **HIL-симуляторів** (§3) — поточний стан готовності + метод його вимірювання. HIL — **програмні еквіваленти фізичного навантаження**, що дозволяють софт-доменам незалежно досягати свого *per-domain* TRL. ⚠️ HIL **НЕ «знімає» System-TRL-Lock** (той лишається обмеженим найнижчим модулем критичного шляху) — він лише декаплить per-domain прогрес. Далекогоризонтна R&D-агенда **за межами TRL 9** (Planetary Intelligence + фрактальне масштабування) винесена у [`00_01 §4`](00_01_Vision_Mission_and_Roadmap). Near-term дорожня карта (фази масштабування) — у [`00_01`](00_01_Vision_Mission_and_Roadmap).

---

## ✅ Статус

- **Поточний TRL (System):** TRL 3 — anchor/EBFC на TRL 3 (Zero-Lab **in-silico** L1-L4 завершено 2026-05-25 = аналітичний PoC; фізичний TRL 4 = breadboard Ti-coin in-vitro, Stage 2 — ще не закрито). Програмні домени TRL 6-9 (декаплінг через HIL, §3).
- **Per-domain TRL (декаплінг):** суть зняття TRL-Lock — програмні домени (Rails, Web3, Firmware, Security) рухаються до TRL 8–9 незалежно від фізичного відставання металу/хімії (anchor/EBFC **TRL 3** — Zero-Lab L1-L4 in-silico завершено 2026-05-25; фізичний TRL 4 = in-vitro Ti-coin, Stages 1-3 ще не закрито). За строгим NASA / ISO 16290 in-silico = TRL 3 (analytical PoC), TRL 4 = breadboard/component validation **у залізі** — тому «Zero-Lab gate PASSED» = «TRL 3 валідовано + GO на TRL 4», не «на TRL 4». **Канонічні per-module числа — `§1 Per-module TRL` нижче (єдиний дім; тут свідомо НЕ дублюються, щоб уникнути drift).** Оновлюється на кожному TRL Gate Event (§4.1) — тобто тоді, коли рівень справді змінюється.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_01` — Vision Mission and Roadmap](00_01_Vision_Mission_and_Roadmap) | Бізнес-візія та slashing |
| [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) | CI-гейти, що несуть рев'ю на TRL 1-4 |
| [`04_06` — Testing Guide and Coverage](04_06_Testing_Guide_and_Coverage) | §B Gap Analysis — відомі обмеження тестів + відкриті ризики |
| [`00_02` — Academic Institutions Registry](00_02_Academic_Integration_and_IP) | Фізичні валідаційні протоколи ВНЗ (TRL 1-4) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Матриця готовності Silken Net (The TRL Matrix)](#-1-матриця-готовності-silken-net-the-trl-matrix)
- [2. Принцип "TRL-Layered Independence"](#-2-принцип-trl-layered-independence)
- [3. HIL Simulators — Програмне розблокування Software TRL](#-3-hil-simulators--програмне-розблокування-software-trl)
- [4. Критерій закриття задачі та TRL Gate Events](#-4-критерій-закриття-задачі-та-trl-gate-events)
<!-- TOC:AUTO:END -->

---

## 📊 1. Матриця готовності Silken Net (The TRL Matrix)

Ми адаптували шкалу NASA TRL для кіберфізичних екосистем. Проєкт рухається від фундаментальної лабораторії до глобальної фіналізації.

### Рівні шкали (NASA/ISO 16290, 1–9)

- **TRL 1-3 (Research & Physics):** доведення базових принципів — папір, розрахунки, лабораторні пробірки.
- **TRL 4-5 (Prototyping):** MVP і макетні плати — валідація **в залізі**, перший код. ⚠️ **Симуляції / in-silico сюди НЕ входять:** за строгим NASA/ISO 16290 вони лишаються TRL 3 (та сама ригористика, що й «без TRL 10-12» ↓; Zero-Lab-підхід → [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)).
- **TRL 6-7 (Field Testing):** анкер вкручено в справжнє дерево, дані йдуть через тестову мережу (Canopy).
- **TRL 8-9 (Operational):** кваліфікована система в реальних умовах, mainnet. ⚠️ Серійне виробництво — це **MRL, не TRL**: технологія на TRL 9 не стає «технічно готовішою» від друку мільйона анкерів.
- **Beyond TRL 9 — НЕ «TRL 10-12».** Шкала закінчується на **9** і міряє виключно готовність самої ТЕХНОЛОГІЇ; масштаб, cross-biome адаптація та forest-level emergence є системною й виробничою зрілістю. Вигадувати «TRL 10-12» ми не станемо — це читалось би некомпетентно перед ESA/NASA, які тримаються 1–9. Натомість профільні шкали:
  - **SRL** (System Readiness Level) — інтеграційна зрілість: cross-biome generalization, forest-level emergence, edge self-evolution, AI-adversarial security. Стадії, якими ми її позначаємо в каноні: **`SRL:Concept`** (напрям сформульовано, часто = Q1-публікація) → **`SRL:Pilot`** (opt-in розгортання на обраних кластерах) → **`SRL:Deployed`** (поведінка за замовчанням після формальної верифікації безпеки).
  - **MRL** (Manufacturing Readiness Level) — виробнича зрілість: серійний друк SKU, заводське штампування. ⚠️ **Шкала — 1-10, наш far-horizon діапазон — 8-10**, і це не дві суперечливі цифри: перша = довжина шкали, друга = ділянка, куди веде дорожня карта (пор. `MRL:8-10` у [`01_01 §6`](01_01_Coaxial_Gyroid_Topology_and_PEEK) — 5 SKU per biome).


| Рівень | Етап | Технічний критерій (Evidence) | Лабораторія / Хаб |
|:---|:---|:---|:---|
| **TRL 1-2** | Ідея / Принцип | Математичне обґрунтування EBFC та Атрактора Лоренца. | ЧНУ (Хімія/Фізика) |
| **TRL 3-4** | Proof of Concept | **TRL 3 (in-silico, ✅ 2026-05-25):** каскад FAD→Os верифіковано **downhill +574 мВ** (PIPELINE_STATUS — це рушійна сила з літературних E°, а НЕ напруга комірки). Проєктний OCV ~0,5–0,7 В — **оцінка**, дім [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell); запас над BQ25570 cold-start 330 мВ читається з неї — хімія/CAD/кінетика. **TRL 4 (фізичний breadboard, pending):** перший Ti-coin заряджає реальний BQ25570 → 3.3V boost + транзакція в Sandbox (Stage 2). | ЧНУ (ФОТІУС) |
| **TRL 5-6** | Прототипування | Робота кластера "Солдат-Королева" в Черкаському борі (30 днів). | Silken Lab |
| **TRL 7-8** | Кваліфікація | Повна інтеграція: DID → ZK-Proof → Chainlink → Polygon. | Production (Canopy) |
| **TRL 9** | Експлуатація | Стабільна безперебійна комерційна робота повноцінного лісового кластера (**Operational Canopy**, 1000+ дерев) у mainnet + фіналізація в L1. *(Масштаб до мільйонів вузлів = SRL/виробнича зрілість, НЕ TRL — [`00_01 §4`](00_01_Vision_Mission_and_Roadmap).)* | Operational Canopy → Global Mainnet |

### Per-module TRL (канонічне джерело)

> SSOT для per-domain TRL. **System TRL = найнижчий модуль критичного шляху (01–06 build-path)** — наразі **3** (модуль 01 anchor/EBFC на TRL 3: Zero-Lab in-silico завершено, фізичний Ti-coin in-vitro pending; модуль 02 на TRL 4 — реальний breadboard CJMCU-2557 + EDLC). Оновлюється на кожному TRL Gate Event (§4.1) — тобто тоді, коли рівень справді змінюється. Канон тут.
>
> ⚖️ **Модулі 00 і 07 у таблиці НЕ рядки — ратифіковано 2026-08-09 (DOC-T.70).** Обидва вимірювали не технологію: Фундамент — візію й метод, модуль 07 — договірну, вартісну й партнерську зрілість. Тримати їх на шкалі означало щодня стверджувати те, що наступний абзац називає категорійною помилкою, і платити за це двічі: рядок `00` стояв **9** при найвищому члені **3**, рядок `07` — **5** при мінімумі **3**, тобто обидва порушували власне правило агрегату, а гейт цього не бачив за дизайном (перевіряє лише верхні межі). Їхній стан живе прозою у власних `✅ Статус`, а машинну половину тримає `TRL_NOT_APPLICABLE` у `lib/tasks/docs.rake` — **двобічний** пін: така сторінка не сміє ані бракувати TRL, ані його мати.
>
> 🔴 **Рядок = модуль документації (`01`–`06`), і нічого іншого.** NASA/ISO 16290 міряє готовність **технології** — тож організаційна, процесна й безпекова зрілість у цю таблицю не сідають: «TRL партнерств» або «TRL процесу» це категорійна помилка, а не низька оцінка. Їхній дім — [`00_07`](00_07_Action_Plan_Tracker): академічні партнерства — `UNI.*` (канон-ростер [`00_02 §1`](00_02_Academic_Integration_and_IP)), безпекова постава — `SEC.*` + [`SECURITY_ASSURANCE_CASE.md`](SECURITY_ASSURANCE_CASE), процес — сам трекер плюс девʼять required-гейтів ([`06_07 §2`](06_07_CICD_and_Runbook_Index)). Не додавай сюди рядок, під яким немає `docs/NN_*`.

| Модуль | TRL | Цільовий | Головний блокер |
|--------|-----|----------|-----------------|
| 01 Materials & EBFC | 3 | 6 | Фізичний Ti-coin in-vitro (Zero-Lab in-silico ✅; physical TRL 4 pending — ЧНУ) |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB, Pogo, PEEK; **02_04=3** — bench-гайд успадковує System-lock від анкера (нуль зібраних плат), а не власну незрілість, тож рядок стоїть вище мінімуму СВІДОМО (форма оголошення — як у рядку 06) |
| 03 Firmware | 6 | 8 | STM32 bench (silicon class C — FW.2 CCM verify + RDP/RF/300nA floor); host-half ✅ (AES/HKDF FW.1 · TinyML FW.4 · AT/CoAP FW.3/FW.56) |
| 04 Backend Rails | 8 | 9 | RSpec-хвости — ⚠️ це найближчий техборг, НЕ гейт: перехід 8→9 визначає §4.1 і він System-TRL-bound |
| 05 Web3 Pipeline | 8 | 9 | SFC-адреса після mainnet-деплою — ⚠️ найближчий техборг, НЕ гейт: 8→9 = §4.1, System-TRL-bound |
| 06 DevOps | 4 | 9 | 🔻 **5→4 при зрізі [`OPS.37`](00_07_Action_Plan_Tracker) 2026-08-29, і це чесний наслідок, а не втрата:** пʼятірку модуля ніс знятий док про платформу, яку ніколи не будували; вцілілий мінімум — [`06_01`](06_01_Deployment_Kamal_Terraform)=4, і після зрізу він НА критичному шляху, а не «fallback», тож винятку рядок більше не потребує. Гейт (переміряно 2026-08-31): **інфра ІСНУЄ** — перший `terraform apply` пройшов 56/56 (дві VM, Cloud SQL, VPC, WIF, KMS, бюджет). Не пройдено інше й саме воно тримає число: **застосунок ДЕПЛОЇВСЯ 2026-09-01, і число тримає вже НЕ це** — серія прогонів `kamal deploy -d canopy` провела ланцюг до запущеного контейнера, а boot-critical набір canopy закрито; тримає **завершений бут**, якого не було (гард відмовляє на незаведених адресах слоту), тобто трафіку не обслуговувано, і шлях end-to-end не ходили; конфіг-половина (Kamal + Terraform GCP, GHCR mirror, Upstash TLS) ✅, шлях не пройдено жодного разу |

> **Рядок модуля = агрегат (мінімум) member-TRL його під-доків** — гейтиться найнижчим під-компонентом критичного шляху, не «середнім». Окремий під-док може декларувати **вищий** member-TRL у власному `## ✅ Статус` без суперечності з рядком: це джерело (не дубль), а рядок просто бере мінімум. Приклад — **Module 02 = 4**: капсула [`02_01`](02_01_Hardware_Architecture_and_BOM) (архітектура + BOM заморожені) і шлюз Королеви [`02_05`](02_05_Queen_Hardware_and_Starlink) декларують вищі member-TRL у своїх Статусах, але агрегат гейтиться фізичними під-компонентами на TRL 4 — Pogo-pin [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface), резисторна мережа BQ25570 + EDLC-буфер [`02_03`](02_03_BQ25570_MPPT_Nano_Power) (anchor/EBFC-gated). Тож «HW=4» у матриці й «капсула вище» у 02_01 — **не drift**, а агрегат vs member.

---

## 🛡️ 2. Принцип "TRL-Layered Independence"

Якщо Rails-модуль, токеноміка і Web3-мости готові до TRL 8, вони не повинні чекати, поки хіміки з ЧМА закінчать роботу з EBFC.

### Формулювання (Concurrent + HIL):

1. **System TRL** залишається обмеженим найнижчим модулем **критичного шляху** (01–06; §1-note) — це чесна метрика для grant заявок та regulator-комунікації ("система готова до пілоту тоді й тільки тоді, коли всі шари готові").
2. **Per-domain TRL** є **незалежним** і відстежується в §1 цього доку per-module. Software може бути TRL 8 коли Hardware TRL 4.
3. **HIL Simulators** (Hardware-in-the-Loop) — програмні генератори, які імітують поведінку реального hardware, дозволяють software-домену пройти TRL 5-8 без живої EBFC/анкера.

---

## 🧪 3. HIL Simulators — Програмне розблокування Software TRL

### 3.1 Чому це критично

Поточна політика блокувала весь TRL модулів 04 (Rails) і 05 (Web3) на TRL 4-5, попри їхню зрілість і **готовність до production**. Без HIL ці модулі лишаються заблокованими на TRL 4 суто формальністю.

### 3.2 HIL / SIL-симулятори в SilkenNet

> **HIL vs SIL (термінологічна чистота):** *Hardware-in-the-Loop* імітує **залізо/фізику** (MCU, LoRa-мережа, EBFC-крива) — `forest_simulator`, `HilQueenSimulator`, `HilLorenzGenerator`. *Software-in-the-Loop* стабить **програмний API** (стаб-сервіси без реального заліза) — це **Web3 SIL** нижче, який раніше помилково звався «HilWebPipelineSimulator». Розрізнення важливе: SIL валідує лише логіку (TRL 5-6), HIL відтворює фізичне навантаження.

| Симулятор | Імітує | Файл | Замінює реальний компонент для |
|-----------|--------|------|-------------------------------|
| `bin/forest_simulator` | Емулює **Queen→Backend CoAP-батчі** (AES-256-**CBC**) з телеметрією Soldier'ів. ⛔ **НЕ** несе Lorenz: усі поля — `rand()`, і жодного перемикача режимів у скрипті немає (перевірено 2026-08-22). Lorenz-дзеркало живе в `HilLorenzGenerator` рядком нижче — не плутай їх, інакше рівномірний шум зарахується як Lorenz-валідація. ⚠️ Це Queen-рівень: per-Soldier LoRa-хоп — на залізі **AES-128** (ECB→CCM, [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)), а до бекенду доходить CoAP-батч (AES-256-CBC). **Два режими (див. ⚠️ нижче):** `load_test_mode` (батч кожні 3–8 сек — стрес черг) та `realistic_mode` (CIFO-точний: рідкі об'ємні батчі ~раз на годину/45 записів + packet loss + jitter мобільної мережі) | `bin/forest_simulator` (load_test існує; realistic_mode — TODO) | Локальна розробка Rails + sidekiq + Web3 pipeline |
| `HilQueenSimulator` | **CoAP→Backend рівень**: Queen-**пульс** = health-блок у ПІДПИСАНОМУ QATT-v2 конверті (ARCH.54). ⛔ Стара DID=0-псевдотелеметрія ВБИТА обабіч і дропається — не пиши декодер, що її чекає. CIFO-буфер flush, Starlink/LTE timing + мережеві відмови (timeout/розрив сесії). ⚠️ **НЕ** симулює LoRa-бік: Q2Q backhaul mesh та реакцію Soldier'ів на падіння Queen (це фізичний радіо-шар — потребує плат або окремого радіо-симулятора). | `lib/hil/queen_simulator.rb` (+ `signed:` QATT-режим — L1 e2e без заліза, `spec/integration/qatt_hil_e2e_spec.rb`; wire [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)) | Test Queen failover на рівні CoAP-intake ([`06_08 §1`](06_08_Resilience_and_Failover_Policy)) |
| **Web3 SIL — Stub Env** *(SIL, не HIL)* | peaq → IoTeX → Chainlink → Polygon → KlimaDAO → Filecoin → L1 — 12-chain mock з deterministic responses. ⚠️ **Software-in-the-Loop**, а не Hardware-in-the-Loop: стабить програмний API (web3-сервіси), не симулює залізо/фізику. ⚠️ Реалізація — НЕ окремі стаб-файли, а `simulate_*`-гілки ВСЕРЕДИНІ доменних сервісів (Polygon/Hadron, IoTeX/W3bstream) за `WEB3_STRICT_MODE=='true' || Rails.env.production?`; різниця несуча — забутий прапор дає не «відсутній сервіс», а fake-KYC approve на тій самій поверхні, що мінтить — тому **SIL**. Валідує pipeline-логіку та guard clauses (TRL 5-6), але **НЕ** Web3 реального світу (gas spikes, RPC 429/rate-limit, orphaned blocks, nonce collisions, Chainlink DON latency). НЕ достатній для TRL 7-8 — див. §3.3. | `WEB3_STRICT_MODE=false` + stub services у `app/services/web3/*_stub.rb` | Логіка pipeline + unit/integration (TRL 5-6) |
| `HilLorenzGenerator` | Lorenz-криві per tree family: температура, метаболізм, лічильник акустичних детекцій, homeostasis/stress/anomaly | `lib/hil/lorenz_generator.rb` | **Rails Attractor validation** (детерміновані фікстури, byte-identical до серверного дзеркала [SEC.11]). ⚠️ **НЕ джерело для тренування акустичної TinyML** — та модель споживає 40 log-mel кадрів ([`03_03`](03_03_TinyML_Acoustic_Inference)) і цього CSV не бачить; доти рядок обіцяв «TinyML training data» і «vibration», тобто сейсмічний вхід, якого на дроті немає [ARCH.102] |
| Anti-fraud сценарії *(іменованого гарнеса НЕМА)* | Bit-flip, replay, tamper-detection, розбіжність подвійного обчислення | ⚠️ **Клас `HilAttackerScenarios` і каталог `spec/integration/security/` не існують** (перевірено 2026-08-22) — матеріал розкиданий по `spec/integration/audit_log_chain_integrity_spec.rb`, `qatt_hil_e2e_spec.rb`, `spec/models/telemetry_log_spec.rb`, `spec/requests/api/v1/m2m_auth_controller_spec.rb`; поріг «>30%» носія в коді не має | Anti-fraud cross-checks ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)) |

> ⛔ **Не давай неіснуючому режиму імʼя в code-font.** Планований профіль навантаження записувався як `` `realistic_mode` `` у реєстрі ІСНУЮЧИХ артефактів — і саме іменована форма втекла в [`02_05`](02_05_Queen_Hardware_and_Starlink) вже в теперішньому часі («HIL моделює умови D2C»), тоді як у коді її немає взагалі. Іменований фантом мандрує, безіменний TODO — ні.

> **⚠️ Реалістичний профіль навантаження vs DDoS:** батч «кожні 3–8 сек» суперечить буферу CIFO ([`06_08 §1.2`](06_08_Resilience_and_Failover_Policy): flush на 45 записів **або** раз на годину) — для цього Soldier мав би передавати кілька разів на хвилину, що неможливо за енергобюджетом. Тобто 3–8 сек = `load_test_mode` (стрес черг/пропускної здатності), а НЕ реальний IoT-профіль. **`realistic_mode`** (потрібно додати) має відтворювати фізичну Queen: рідкі об'ємні батчі раз на ~годину, + мережеві умови **Starlink Direct-to-Cell**: Carrier-NAT, можливе блокування вхідного UDP (CoAP), зміна портів, високий jitter / packet loss супутникового LTE. Це тестує дефіцит з'єднань, тайм-аути long-poll та розриви TCP-сесій — справжні відмови, яких load-test не ловить. Транспортний фолбек (CoAP-over-TCP / MQTT-SN) — див. [`02_05`](02_05_Queen_Hardware_and_Starlink) + Ingress Proxy [`06_01`](06_01_Deployment_Kamal_Terraform).

### 3.3 TRL Промоція через HIL

> ⚠️ **Колонка нижче — НЕ блокер (інакше це повернуло б TRL-Lock з §2).** Сенс HIL саме в тому, щоб **не чекати** фізичних дерев. Тому це **Physical-Equivalent Target** — той фізичний стан, який HIL-симулятор *відтворює навантаженням*, а НЕ передумова. Software досягає TRL завдяки тому, що HIL генерує еквівалентне навантаження (напр. 1000+ віртуальних дерев), а не тому, що вони є в полі.

| Per-domain TRL | Physical-Equivalent Target (НЕ блокер) | HIL, що його відтворює | Status |
|----------------|----------------------|----------------|--------|
| Software TRL 5 (Prototype validated) | ~анкер у дереві 30 днів | `bin/forest_simulator` + integration tests | ✅ Достатньо |
| Software TRL 6 (Demonstration in relevant environment) | ~LoRa-лінк у канопі | HIL Queen Simulator + staging-деплой (Kamal canopy) + multi-node forest_simulator | 🟡 Частково (HIL Queen ✅ `lib/hil/queen_simulator.rb`; лишились staging-деплой + multi-node прогін) |
| Software TRL 7 (Operational prototype) | ~pilot 100 дерев | Все HIL + chaos engineering (**аплікаційний** ✅ — `spec/integration/proof_of_growth_chaos_engineering_spec.rb`: падіння IoTeX 24h, reorg Polygon, timeout Chainlink, каскадні мультичейн-збої; **інфраструктурний** — Chaos Mesh/kill-scripts, ще ні → [`00_07`](00_07_Action_Plan_Tracker) E.27) + **реальний testnet pipeline ОБОВ'ЯЗКОВИЙ** (Polygon Amoy + Solana Devnet + Ethereum Sepolia) з реальними RPC-вузлами | 🟡 Частково (chaos engineering ✅; testnet pipeline: Amoy і Sepolia живі з 2026-09-02 — слот canopy `testnet`, контракти на обох, `StateRootAnchor` Sepolia у гарді (INF.27 закрито — §🗄️ в [`00_07`](00_07_Action_Plan_Tracker)); відкритий Devnet — дім [`00_07`](00_07_Action_Plan_Tracker) `DEPLOY-1` Фаза 2t, а мінт-тракт на testnet — роль job canopy, `OPS.37`) |
| Software TRL 8 (Production-validated) | ~1000+ дерев у полі | **HIL відтворює 1000+ віртуальних дерев** + **повний testnet stress** (Amoy/Devnet/Sepolia: gas spikes, RPC 429, nonce collisions, DON latency, orphaned blocks) + Slither/Aderyn high-severity = 0 + Halmos symbolic proofs + Medusa property-fuzz clean + multi-sig deployment dry-run. Mainnet — лише TRL 9. | 🟡 Контракти TRL 9-ready (Foundry/Slither/Aderyn/Halmos/Medusa); backend↔chain integration потребує testnet-стресу мінт-тракту — той стане можливим із роллю job на canopy, дім [`00_07`](00_07_Action_Plan_Tracker) `OPS.37` (слот і контракти вже живі: INF.27 §🗄️) |

> **⚠️ Два рівні Web3-тестування:** детермінований **Web3 SIL** (stub env, §3.2) НЕ може давати Software TRL 8 — він валідує лише логіку (TRL 5-6). Реальні відмови Web3 (gas spikes, RPC rate-limit/429, orphaned blocks, nonce collisions, Chainlink DON latency) ловляться **тільки на справжніх testnet'ах**. Тому: **TRL 5-6** → deterministic mock; **TRL 7-8** → обов'язковий **Testnet Pipeline** (Polygon Amoy + Solana Devnet + Ethereum Sepolia, реальні RPC) **плюс mainnet із малим лімітом емісії та multi-sig на DAO-скарбниці**; **TRL 9** → зняття лімітів + передача управління DAO. ⚠️ Тут доти стояло «TRL 9 → mainnet», що прямо суперечило корекції §4 («на TRL 7-8 система ВЖЕ в mainnet») — обидві були позначені як авторитетні, і одна з них уже розповзлась у [`05_03`](05_03_Tokenomics_SCC_and_SFC). TRL 9 = **доведена робота**, не «deploy». Без testnet-стресу вихід у mainnet після моків гарантує падіння бекенду у перші години.

### 3.4 Прозорість

> HIL-симулятори **не приховують** фізичне відставання — публічний per-шар TRL живе в [`manifest.md`](manifest) §5 і **машинно гейтиться** проти §1 (`DocsLinter::MANIFEST_TRL_CLAIM`), а `README.md` несе одноабзацну чесну половину («TRL 3, gated by the anchor and the biofuel cell; zero nodes in a forest»). ⛔ Не вимагай per-рівень TRL-міток у README-таблиці стека: він їх свідомо ЗНЯВ за тим самим One-Home, і наступний прохід не має додавати їх назад. Числа тут свідомо не дублюються (One-Home — зведена матриця в §1). Це чесніше, ніж блокувати Software на TRL 3 формальністю TRL-Lock.

### 3.5 Firmware bench-незалежність: класи A/B/C + bench-as-code

> **Метод:** кожен «bench-gated» firmware-пункт класифікується за тим, *що насправді відповідає на питання* — і більшість виявляється bench-gated лише за звичкою. Присуди по item-ах живуть у [`00_07`](00_07_Action_Plan_Tracker); це — спосіб мислення.

| Клас | Що відповідає | Інструмент | Приклади (закриті цим методом) |
|------|---------------|-----------|--------------------------------|
| **A. Host-логіка** | чиста логіка + wire-контракти | `firmware/test/*` host-тести, скриптовані транскрипти, fault-injection | FW.3/FW.56 AT+CoAP розмова (скриптований SIM7070G), ARCH.28 Flash-KV (power-cut мок), SEC.3 EXECUTE (fake-CLI шим), FW.4 TinyML INT8 forward-pass (host-golden class-exact) |
| **B. ISA-семантика** | реальний машинний код таргета, без периферії | **QEMU-M4 parity lane** (`qemu-system-arm mps2-an386`, [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)) | FW.7/FW.19 ARM↔x86 double-drift → byte-exact гейт у CI (FW.55) |
| **C. Кремній/фізика** | лише плата | **bench-as-code**: `firmware/scripts/bench/` (RUNBOOK + скрипти `--plan`/`--execute`) | CCM-атестація (FW.2 KAT через SWD), 300 нА floor, Vcap recharge-крива (E.63), LSE drift, RDP, RF |
| | | | |

**Принципи:** (1) самописна модель периферії **не може** атестувати кремній (модель AES писалась би проти того ж OpenSSL — циркулярно; тому Renode-порт STM32WL відхилено — perif-моделі WL відсутні upstream, а питання класу C вони не закривають); (2) клас C **не означає «чекати»** — bench-день кодифікується наперед (runbook + скрипти + атестаційна граматика KAT-звітів), щоб залізо відповідало на вичерпний список питань за години, а артефакти лягали в репо; (3) той самий вхідний скрипт локально і в CI (патерн `cppcheck.sh`/`qemu_parity.sh`).

---

### 3.6 In Silico як HIL-аналог для Hardware Stream (Zero-Lab)

Hardware Stream історично був «повільним» (друк металу → лабораторія → in vitro → поле). Це усувається двома паралельними Code-as-Engineering треками: **Трек A — Code-as-Chemistry** ([`01_03 §3.4`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)) і **Трек B — Code-as-CAD** ([`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)).

🔑 **У треку B дві РІЗНІ ролі, які не можна плутати:** **PicoGK** (C#) — справжній CAD-as-code, де агент пише детермінований генератор геометрії (CEM-методологія — *алгоритм, НЕ генеративний ML*); **nTop Automate** — це headless parameter-sweep уже створеного в GUI шаблону, тобто базовий `.ntop` спершу «наклацує» інженер. From-scratch generation = PicoGK; автоматизована параметризація готового шаблону = nTop Automate.

> ⚖️ **«Трек C — Code-as-Mechanics» ВИДАЛЕНО, і підстава не технічна.** Важка механіка полімерів (в'язкопружність PEEK, Prony series, термонапруження Ti+PEEK, 20-річний creep) канонічно закріплена за лабораторією ЧНУ на ANSYS LS-DYNA ([`01_01 §4.3`](01_01_Coaxial_Gyroid_Topology_and_PEEK) · [`00_02`](00_02_Academic_Integration_and_IP)). Паралельний AI-трек на CalculiX дав би **другий, неузгоджений** результат і знецінив би роботу професорів. Наш конвеєр покриває хімію, геометрію, кінетику та **легкий closed-form mechanics-bound** (аналітичний Lamé, БЕЗ mesh) — швидку оцінку-границю, що ЯВНО відкладає авторитетну mesh-FEA і Prony-fit до партнера.

**Архітектурний принцип — НЕ «відмова від GUI», а headless/API-driven доступ.** Проблема не в тому, що nTop чи ANSYS погані (nTop — найпотужніший TPMS-рушій у світі), а в тому, що агент не клікає по GUI. Рішення — керувати тими самими індустріальними інструментами через їхні офіційні Python/CLI API, а не переписувати CAD «бо так зручніше LLM»:

| Категорія | GUI-режим (для людини) | Code/API-driven (для агентів) |
|---|---|---|
| Chemistry | Gaussian / ORCA | **PySCF** (Python) — галузевий стандарт |
| CAD parametric / TPMS | nTop Workbench, SolidWorks | **PicoGK** (C#, from-scratch) + **nTop Automate** (sweep готового шаблону) |
| FEA mechanical | ANSYS Workbench | **PyAnsys / PyMAPDL / PyDPF** (headless — у партнера) |
| Molecular Dynamics | VMD, NAMD GUI | **OpenMM** (Python) — галузевий стандарт |
| Кінетика | (Custom GUIs) | **scipy/numpy** analytical models |

**Ефект і його межа:** конвеєр дозволяє відшліфувати TRL 3 і підготувати хімічну/CAD-базу ПЕРЕД дорогим переходом на TRL 4, збиваючи R&D-бюджет на хімію в 5–10 разів, а на CAD-варіанти — в 10–20. ⚠️ Але за строгим NASA/ISO 16290 in-silico ≠ TRL 4 (§1 вище), тож «Zero-Lab gate PASSED» означає «TRL 3 повністю валідовано + GO фінансувати TRL 4», а НЕ «ми вже на TRL 4».

---

## 📊 4. Критерій закриття задачі та TRL Gate Events

Кожна задача несе рівень TRL; відкритий залишок живе в [`00_07`](00_07_Action_Plan_Tracker), поточні рівні — у §1 вище. Задача не вважається закритою, доки її реалізація не буде підтверджена:

- (a) фізичними даними або результатами лабораторних тестів — партнерський/лабораторний шар живе у [`00_02`](00_02_Academic_Integration_and_IP), **АБО**
- (b) HIL-симуляційними даними з валідною специфікацією контракту з реальним hardware, **АБО**
- (c) детермінованими CI-гейтами — **тільки для Logic/Verification стрімів (Bytes/Proofs)** і тільки для TRL 1-4. Периметр гейтів = девʼять required-чеків branch-protection ([`06_07 §2`](06_07_CICD_and_Runbook_Index)); окремого ритуалу схвалення на цьому рівні немає, бо рев'ювер і власник — одна особа.

> **⚠️ Корекція: для Hardware/Chemistry (Atoms) самих CI-перевірок НЕДОСТАТНЬО.** Зелений CI доводить, що **код виконується**, а не що **фізика коректна** — PySCF-скрипт може відпрацювати без помилок і видати термодинамічно абсурдний результат. Тому:
> - **Logic / Verification (Bytes / Proofs):** CI + HIL-симуляції + рев'ю діфу — достатньо (критерій (c)).
> - **Hardware / Chemistry (Atoms):** CI необхідний, але НЕ достатній. Вимагаються **згенеровані ТА валідовані фізичні метрики** (напр., ΔG < 0, RMSD < поріг, k_ET у літературному діапазоні), підтверджені домен-експертом або крос-перевіркою (cross-validated In-Silico report, [`PIPELINE_STATUS.md`](protocols/ebfc/in_silico/PIPELINE_STATUS.md)) — тобто пройдений **🚦 Validation Gate** ([`00_06 §5`](00_06_SSOT_Documentation_Standard)).

### 4.1 TRL Gate Events — де підняття рівня НЕ автоматичне

**Чотири** переходи вимагають свідомого рішення власника, а не зеленого CI — і першим стоїть той, що перед проєктом просто зараз (System TRL = 3):

- **3 → 4** *(Atoms, найближчий)* — замикає **підписаний фізичний лаб-звіт (in-vitro)**; in-silico сам по собі дає лише TRL 3. Деталь і чому «апрув» тут не Git-approve — абзацом нижче.
- **4 → 5** — з лабораторії до pilot: потребує HIL-валідації (§3 **вище**).
- **6 → 7** — вихід у canopy environment: реальний LoRa-лінк і реальний CoAP-інтейк, не симулятор.
- **8 → 9** — **зняття «тренувальних коліс»:** передача повного управління контрактами від Multi-sig (`Gnosis Safe`) до децентралізованого DAO (`SilkenGovernor` + Timelock) + зняття штучних лімітів емісії, за **доведеної стабільної безперебійної роботи повноцінного комерційного кластера** (Operational Canopy, 1000+ дерев) без втручання. Масштаб до мільйонів вузлів — це SRL/виробнича зрілість **поза** TRL ([`00_01 §4`](00_01_Vision_Mission_and_Roadmap)).

Для **Atoms** гейт **3 → 4** замикає підписаний фізичний лаб-звіт (in-vitro): in-silico сам по собі дає лише TRL 3 (🚦 Validation Gate → [`00_06 §5`](00_06_SSOT_Documentation_Standard)). Академічний «апрув» тут — це підписаний лабораторний протокол (PDF/Markdown), а не Git-approve: науковці-партнери не оперують GitHub.

> **⚠️ Корекція:** мінтинг SCC — **НЕ перемикач**, який вмикають на TRL 9. Він керується Guard Clauses: живий периметр = KYC (`hadron_kyc`); oracle-гілка (`verified_by_iotex` + `oracle_status_fulfilled`) = latent PATH 1, замикання відмовлено (ARCH.53 §🗄️ — superseded by Merkle-lineage) ([`05_02`](05_02_Proof_of_Growth_Pipeline) / [`00_01 §5`](00_01_Vision_Mission_and_Roadmap)). На TRL 7-8 система **вже** в mainnet — з малим лімітом емісії та multi-sig на DAO-скарбниці. TRL 9 = доведена стабільна комерційна робота + децентралізація, а не «deploy» і не «мільйони вузлів».
