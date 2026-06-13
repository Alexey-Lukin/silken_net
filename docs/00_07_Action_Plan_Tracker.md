# 00_07: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати **ТІЛЬКИ незавершене** — кожен пункт як **тонкий вказівник**: `ID · пріоритет · виконавець` + 1 рядок + **→ канон-реф**. Повний опис «як має бути» живе в каноні (`00_00`→`08_02 §5`), описаний **в одному місці**; 00_07 на нього посилається, **не дублює**.

**Правило одного місця (DRY):** редагуєш канон → онови залежні пункти 00_07 (за рефами); закрив пункт → онови канон + познач тут (✅ → **§🗄️ Архів**, вказівник ID→канон). Так апдейт робиться в одному місці, а референси ведуть, де ще синхронізувати.

**Структура:** **🚦 Dashboard** (що робити зараз, за виконавцем) → **§00–§08 модуль-секції** (реєстр незробленого; **номер секції = канон-модуль першого рефа** — enforced `tracker:check` section-home guard) → **🔀 Cross-cutting** / **📌 Backlog** → **🗄️ Архів**. Документ — живий операційний інструмент.

---

> **Розмітка виконавців:**
> - 🤖 **Код/аналіз** — coding-agent може виконати самостійно (код, firmware, розрахунок, документ, тест)
> - 👤 **Операційна** — потрібен власник (hardware, зовнішні UI/дашборди, секрети, зустрічі, юрист, фізична лабораторія)
> - 🔗 **Заблоковано** — чекає іншої задачі або рішення

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Dashboard — що робити зараз (за виконавцем)](#-dashboard--що-робити-зараз-за-виконавцем)
- [§00 · Process / IaC / SSOT-tooling](#00--process--iac--ssot-tooling)
- [§01–§02 · Hardware & Lab](#0102--hardware--lab)
- [§03 · Firmware](#03--firmware)
- [§03/§05 · Безпека (Edge crypto + Web3)](#0305--безпека-edge-crypto--web3)
- [§04 · Backend / API / UI](#04--backend--api--ui)
- [§05 · Web3 / Економіка / Slashing](#05--web3--економіка--slashing)
- [§06 · Deploy / Observability / Secrets / Ops](#06--deploy--observability--secrets--ops)
- [§07 · Юридичні / Бізнес](#07--юридичні--бізнес)
- [§08 · Академічна інтеграція + External Stakeholders](#08--академічна-інтеграція--external-stakeholders)
- [Cross-cutting · Doc-drift (DOC-T) — tracker doc↔firmware↔backend reconciliation](#-cross-cutting--doc-drift-doc-t--tracker-docfirmwarebackend-reconciliation)
- [Backlog · Додаткові знахідки (не блокери)](#-backlog--додаткові-знахідки-не-блокери)
- [Backlog · Архітектурні пропозиції (довгострокові)](#-backlog--архітектурні-пропозиції-довгострокові)
- [Архів закритих пунктів (мігровано в канон)](#-архів-закритих-пунктів-мігровано-в-канон)
<!-- TOC:AUTO:END -->

---

## 🚦 Dashboard — що робити зараз (за виконавцем)

> Сортовано за **виконавцем**, потім пріоритетом. Повний опис кожного пункту — у §модулі нижче (**one place**); тут — тонкий індекс. Легенда: 🤖 AI-doable · 👤 власник · 🔗 заблоковано.

### 🤖 Machine-doable зараз (AI, non-gated)
> Великі незаблоковані 🤖-стріми поетапно закриваються (SSOT-кампанія; firmware build/dependency-hardening — FW.46 ARM build + FW.47 pin-policy + `in_silico` conda-lock). Залишок 🤖 переважно **gated** (ML-retrain, ground-truth калібрування, STM32 bench) → див. 🔗. Незаблокований 🤖-backlog ітемізується у §модулях (P2 ре-бакетинг).

### 👤 На тобі (власник)

**Перед польовим деплоєм (life-safety + security):**
- `SEC.9` **P0** — замінити master AES key (FIPS-197 vector) на криптостійкий random
- `SEC.3` **P0** — factory flashing: real `STM32_Programmer_CLI` на STM32WLE5JC bench (per-device HKDF provisioning ✅, FW.1 закрито)
- `SEC.1` **P0** — Gnosis Safe multisig для `DEFAULT_ADMIN_ROLE` SCC/SFC до mainnet

**Перед Web3 mainnet:**
- `S1.1` **P0** — GitHub Secrets (`DATABASE_PASSWORD`, `GCP_SA_KEY`, `SSH_PRIVATE_KEY`, …)
- `S3.5` **P1** — реальна SCC/SFC адреса у `subgraph.yaml` (zero-addr guard ✅ E.45; gated: post contract-deploy)
- `SOLANA_RPC_URL` mainnet **P0** — інакше USDC на Devnet; provision secret → `06_04` (refuse-to-boot guard ✅ E.47)
- `INF.4`+`INF.6` **P1** — TLS termination + CoAP Proxy verification (Akash ingress)
- `S2.1`+`S2.2`+`S2.3` **P0** (ops) — Grafana Cloud dashboards & alerts після першого `/metrics`

**Hardware TRL 4→6 (лаб/підрядники):**
- `HW.31` **P0** — Queen antenna split (868 LoRa tuned ≠ dual-band); блокує BOM Королеви
- `HW.24` **P0** — staged validation gate (SLA→Ti-coin→full anchor); блокує 100 шт DMLS
- `HW.23` **P0** — HIP postprocess spec для SLM anode; блокує перший SLM-замовлення
- `HW.22` **P1** — sterilization protocol (no EtO); блокує Stage 4 польові
- `HW.7` **P1** — BQ25570 VBAT_OV резистори; блокує PCBA freeze
- `HW.13`/`ARCH.29-MPPT` **P1** — P-V крива EBFC, 50%→65% VOC
- `HW.3` **P1** — Arrhenius accelerated aging тест; блокує seed
- `HW.25` **P1** — PTFE-GDL катодна мембрана (Zone 3)

**Academic:**
- `UNI.1` **P0** — зустріч з деканом Онищенком (ChNU FOTIUS); блокує публікації Q1
- `UNI.8` **P0** — контакт з ректоратом СЄУ; блокує MSA/B2B legal
- `UNI.13`/`UNI.14` **P0** — верифікувати посади науковців ЧМА і СЄУ (офіційні сайти)

### 🔗 Заблоковано (чекає іншого)
- `FW.2` **P0** — AES-128-CCM (backend-parser ✅; firmware emit + `CRYP_AES_CCM` verify → STM32 bench). Закриває ECB→CCM, MIC, `SEC.10` panic auth, `FW.29`. FC/nonce/cold-boot SSOT → `03_05` (📐 КАНОНІЧНЕ ДЖЕРЕЛО). NB: `FW.23` OTA auth — окремий HMAC-механізм, канонізовано в §3.4б (live-compute ✅ зашито 2026-06-11, лишився bench K_ota); FW.2 його **не** закриває
- Multi-signal slashing de-risk (`05_05 §7`) — код ✅: усі 3 прямі сигнали в `InsightGeneratorService`-евристиці (VPD-gate + sap-term + acoustic/cavitation-term; inert, ENV-calibration-gated; sap+acoustic через max() не суму). Активація → ground-truth калібрування ваг (`05_05 §8`) + ML-retrain (vpd-фіча) + firmware VPD (`HW.32`). Багатше on-device acoustic-джерело → TinyML підсилення (`Run_Inference` ✅ приземлено FW.4, §03)
- SLASH-1 deeper (B/insurance auto-route, A/B/C cause_classification, cause-driven pf uplift) → DAO/founder

## §00 · Process / IaC / SSOT-tooling

> Process-automation, Projects-V2/IaC та SSOT-tooling — канон `00_04`/`00_05`. Оперативний індекс P0/P1 — у 🚦 Dashboard.

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **P1** · 👤 · → `00_05`
- ✅ `trl_sync.yml` (GraphQL Projects v2, TRL≥5 architect-approval gate — OPS.9). · [ ] 👤 створити `PROJECT_PAT` (project:write) + тест з issues · [ ] 👤 (security) мігрувати `PROJECT_PAT` → GitHub App installation token (`GITHUB_TOKEN` не вміє Projects V2; `00_05 §2.2`)

#### OPS.2 — SSOT Integrity Guard
- **P1** · 👤 · → `00_05`
- ✅ `ssot_guard.yml` (app/models·firmware·contracts·services; `type:*` bypass). · [ ] 👤 зробити required check на `main`

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **P1** · 👤 · → `00_04 §5`, `00_05 §6`
- ✅ Shape Up template + Projects V2 kanban-mapping (R&D Cluster/Stage/Cycle + auto-routing; 4 кластери A/B/C/D). · [ ] 👤 перший betting cycle після UNI.1/UNI.8

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **P2** · 👤 · → `00_05 §5`
- ✅ семестр-мапінг (Fall/Spring + TRL milestones + 15.VI; `trl_sync.yml` стемпить `Academic Semester`). · [ ] 👤 узгодити календар з ФОТІУС (UNI.2) + створити `Academic Semester` single-select field у Projects V2

#### OPS.6 — Bootstrap scripts для GitHub Projects V2 + IaC initial sync
- **P2** · 👤 · → `00_05 §1.2/§6`
- ✅ `lib/github_bootstrap.rb` (`FIELDS` SSOT, idempotent GraphQL diff, rake `github:bootstrap`, RSpec-покрито). · [ ] 👤 запустити `bin/bootstrap_github.sh` проти живого Projects V2 при setup/fork

## §01–§02 · Hardware & Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.32 — BME280 environmental sensing + VPD confounder [ADR `02_01 §3.4`]
- **P1** · 🤖+👤 · → `02_01 §3.4`, `07_02 §1.3`
- BME280 (t°/RH/тиск, I2C за TPS22860) → VPD confounder (False-Slashing kill, `05_05 §6/§7`) + клімат-оракул (`07_01`). DCI-guard: VPD НЕ в Lorenz-Z. ✅ docs (02_01/00_01/08_02/07_02/02_03/07_01) + `03_01` SENSE + TelemetryLog cols (structure.sql, recreate+seed). ✅ (2026-06-12) wire-дім перевирішено: VPD-індекс = CCM wire-rev2 **byte 19 `vpd_index`** ([`03_05 §3.2`](03_05_Hardware_Symmetric_Crypto_and_Security) ledger; стара претензія на 21B byte 14 колідувала з gossip-freeze — знято); шкала index→kPa визначається при калібруванні. ✅ (2026-06-12) **firmware pure-модуль `firmware/common/bme280.h`** — компенсація datasheet Bosch §8.2 (`Bme280_Compensate_T/P/H`) + VPD FAO-56 Tetens (`Bme280_Vpd_Index`, формула канонізована `02_01 §3.4`); host-golden `firmware/test/test_bme280.c` (10/0 — int-шлях звірено проти незалежної float-копії §8.1, VPD hand-anchored). · [x] 🤖 VPD-gate + sap-term реалізовано (inert, ENV-calibration-gated; `04_02` / `05_05 §7`; активація `05_05 §8`) · [x] 🤖 BME280 компенсація + VPD-квантизація (pure, host-tested) · [ ] 👤 bench (I2C bring-up `bme280_forced_read`, SENSE call-site вшивається з CCM-флипом, gate-timing, VPD-калібрування) + PTFE-мембрана механіка (`02_02`)

#### HW.1 — nTop model → SLM+HIP factory (Anode Zone 1)
- **P0** · 👤 · → `01_01`, `01_02 §1.7` · ✅ ліцензія отримана
- **Контекст:** Тризонний анкер (`01_01` §1) — Zone 1 (анод, гіроїд) виготовляється SLM+HIP; Zone 3 (катодний фланець) — SLM або EBM (`01_02` §1.7); Zone 2 (PEEK-втулка) — CNC з annealing 200–250°C
- [ ] 👤 Генерація TPMS gyroid geometry (65% porosity, **тільки для Zone 1**)
- [ ] 👤 **Вертикальна орієнтація пор** (`01_01` §5.5): головна вісь TPMS-комірки паралельна осі анкера (паралельно потоку соку)
- [ ] 👤 **Градієнт розміру пор** (`01_01` §5.5): центр 300–500 µm → периферія 100–150 µm при сталій пористості 65% — параметризація nTop cell size як функція радіуса
- [ ] 👤 Окреме креслення Zone 3 (катодний фланець ∅20–30 мм)
- [ ] 👤 STL/STEP файли → передати на SLM завод (Київ/Дніпро) разом з вимогою HIP-постпроцесу (`01_02` §1.7 + HW.23)
- [ ] 👤 **Build orientation specification** (`01_02` §1.6): BD ∥ довгій осі анкера, кут до build plate 0° ± 5°, externally only support
- [ ] 👤 **Карта обмежень покриттів** (`01_02` §3.6): передати заводу інструкцію — ZnO-Ta НЕ наносити на гіроїдні стінки Zone 1
- [ ] 👤 SEM criteria для приймання партії
- [ ] 👤 µCT-сканування для верифікації градієнту розміру пор (центр 300–500 → периферія 100–150 µm) при пористості 65 ± 2%

##### Підблокер HW.1.PicoGK — Code-as-CAD Alternative (paralleled R&D track) — `01_02 §6 PicoGK`
> **Стратегія:** PicoGK (open-source SDF engine від LEAP 71) + C# як AI-агент-сумісна альтернатива nTop GUI. Усуває "GUI-blindness" coding-agents та робить геометрію Git-friendly. Не замінює nTop одразу — паралельний evaluation track.
- [ ] 👤 **Setup C# проєкту:** Visual Studio 2022 або JetBrains Rider, .NET 7+, console project
- [ ] 👤 **Build PicoGK з GitHub** (`github.com/leap71/PicoGK`) → підключити як бібліотеку
- [ ] 👤 **Промпт-template для coding-agent:** Senior C# інженер пише `Zone1Anode` клас з SDF гіроїда (формула sin(x)cos(y)+sin(y)cos(z)+sin(z)cos(x)=0), параметризованим діаметром/пор/wall thickness
- [ ] 👤 **Stage 1 SLA generation через PicoGK** (паралельно з nTop reference) — порівняти STL output на topology errors
- [ ] 👤 **Per-species CEM (5 SKU):** pine/oak/broadleaf/mangrove/tropical — параметрична генерація через зміну однієї змінної ([`00_08 §1.3`](00_08_Beyond_TRL9_Planetary_Roadmap) cross-biome generalization)
- [ ] 👤 **Migration decision gate (Q2 2026):** якщо PicoGK видає clean STL без BREP errors → почати міграцію SSOT з `.ntop` на `.cs` (Git-friendly)
- [ ] 👤 **Annular barbs SDF:** реалізувати asymmetric triangle profile h=0.3mm у C# для PEEK mechanical lock (`01_01 §4.3`, HW.26)

#### HW.2 — Dual-scale roughness spec
- **P1** · 👤 · → `01_02`
- **Опис:** Sa 0.5-5 µm, Sv 50-500 nm НЕ передана на завод
- **Блокує:** Максимальний струм EBFC, TRL 5
- [ ] 👤 Підготувати factory spec з метриками
- [ ] 👤 Передати на завод
- [ ] 👤 Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **P1** · 👤 · → `01_02`
- **Опис:** 12-тижневий тест у synthetic xylem sap
- **Блокує:** Seed раунд, whitepaper, TRL 5→6
- [ ] 👤 Синтез штучного ксилемного соку (потрібен ботанік)
- [ ] 👤 Запуск 12-тижневого тесту
- [ ] 👤 ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] 👤 EIS degradation < 50%
- [ ] 👤 **V-release Zone 1 mitigation** (відкритий конфлікт, `01_02 §2.5`): голий Ti-6Al-4V ≈ 1.12 µg/cm²/yr V (56× over target), ZnO не можна на Zone 1 → in-vitro тест chitosan-matrix бар'єру (b) ± опція V-free сплав Ti-6Al-7Nb / Ti-5Al-2.5Fe (a)

##### Підблокер HW.3.IS — In Silico FEA Aging (Stage 0, mechanics) — `00_02 §4a` Trek C
> **Стратегія:** Симуляція напружень Ti+PEEK при extreme температурах ще ДО фізичного 12-week теста. Використовуються рівняння Ляме для thick-walled cylinder (Zone 1 ↔ Zone 2 ↔ Zone 3 коаксіальний press-fit). Закриває (a) механічну цілісність PEEK creep на 20-річному horizon'і, (b) сезонні термоциклічні навантаження.
- [ ] 👤 **FEA setup:** CalculiX (open source, .NET/Python wrappers) або Code_Aster (Python) — заміна ANSYS GUI для AI-агент-сумісного workflow
- [ ] 👤 **DFT (PySCF) для іонного бар'єра:** енергія активації дифузії Ti²⁺/Ti⁴⁺/Al³⁺/V³⁺ через PEEK-матрицю → корозія НЕ отруїть ферменти за 20+ років

#### HW.4 — Self-healing coating (NEW: zone-restricted)
- **P1** · 👤 · → `01_02 §3/§3.6`
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **⚠️ Zone restriction:** Self-healing наноситься **тільки на неактивні поверхні** (зовнішня сорочка катодного фланця Zone 3, торці PEEK-втулки). НЕ наноситься на гіроїдні стінки Zone 1 (блокує DET) і не на катодну каталітичну поверхню (блокує DET до Cu T1 лаккази). Деталі — `01_02` §3.6.
- **Блокує:** 20+ років longevity claims, TRL 6
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer — ТІЛЬКИ на дозволених зонах
- [ ] 👤 Тест: 10× вищий Rct
- [ ] 👤 **Thiol-Michael interphase** (`01_02` §1a.1): тест адгезії self-healing шару при ростовому навантаженні, порівняння з простою APTES-силанізацією — додано в `01_02`

#### HW.5 — Enzyme lifespan + Gen 2.0 chemistry stack
- **P1** · 👤 · → `01_03 §1–3` (REWRITTEN 2026-05-22)
- **Опис:** Довгострокова стабільність біоелектрохімічного стеку у кислому ксилемному середовищі (pH 4.5–5.5) при повній імунологічній невидимості для CODIT-каскаду. Цільовий термін **20–25 років**.
- **Gen 2.0 baseline (REWRITTEN 2026-05-22 — одношарова FAD-GDH архітектура):** Архітектура `01_03` повністю переписана на Gen 2.0. Gen 1.0 (GOx + Catalase + глутаральдегід + PEG) **визнана нежиттєздатною** і виключена з усіх лабораторних протоколів — не використовується навіть як baseline. Новий стек:
  - **Анод (Zone 1):** одношаровий `fMWCNT + Os-полімер + dgrFAD-GDH` (деглікозильована FAD-залежна глюкозодегідрогеназа з *Glomerella cingulata* або *Aspergillus*) → не виробляє H₂O₂, O₂-незалежна, повний pH 4.0–8.0 діапазон. Каталаза не потрібна.
  - **Захисна матриця:** **Genipin-Chitosan-CNC** (геніпін як нетоксичний зшивач замість глутаральдегіду + целюлозні нанокристали 2–6% для псевдопластики проти тигмоморфогенезу).
  - **Катод (Zone 3):** Гібрид `Laccase + ZIF-nanozyme` (nCoCuCeZIF/Lac або nCuCeAuZIF/Lac) — ×10 power density, 75% активності після 10 днів, **+7.5% з 0.25 М NaCl** (vs -41.7% для чистої Laccase), резервний безферментний каталізатор при денатурації.
  - **Anti-biofouling мембрана (Шар 5):** **Nafion-g-PSBMA** (цвітеріонний полімер ковалентно прищеплений через SI-ATRP) — 8 молекул води/ланцюг, блокує абієтинову кислоту/смоли, σ(H⁺) = 45.2 мС/см, UCST winter-lock @ 5°C.
- [ ] 👤 **Gen 2.0 anode (priority):** одношаровий dgrFAD-GDH+Os electroactive layer + geniпin-chitosan-CNC матриця — `01_03` §2.1
- [ ] 👤 **Gen 2.0 cathode (priority):** Laccase + nCoCuCeZIF nanozyme гібрид на MWCNT — `01_03` §2.2
- [ ] 👤 **Цвітеріонна мембрана:** SI-ATRP синтез Nafion-g-PSBMA (контрактна синтез-лабораторія) — `01_03` §2.1 Шар 5. ⚠️ **Bottleneck:** пришивка ATRP-ініціатора потребує переведення Nafion у сульфонілхлоридну форму → вимагати досвіду з фторполімерами. Lead time 3–6 тиж. (`01_03 §3.7`)
- [ ] 👤 **Геніпін постачання:** контракт з Challenge Bioproducts (~$50–80/г, >98%, зберігати в темряві @4°C); тест cross-linking хітозану при pH 4.5 — `01_03` §2.1 Шар 4. **Найшвидший пункт — просто закупка.**
- [ ] 👤 **dgrFAD-GDH (🔴 КРИТИЧНИЙ ШЛЯХ, 4–8 тиж — пріоритет #1):** контрактна експресія у *Pichia pastoris* через B2B CRO. **Деглікозилювання gene-level (preferred):** віддати CRO ген з уже вбудованими 11 N→Q мутаціями (з L1) → *Pichia* не глікозилює → крок PNGase F не потрібен. Fallback PNGase F/endo-H — тільки native conditions (без SDS/DTT). *Pichia*, не *E. coli* (inclusion bodies). **Дія зараз:** скласти spec sheet (dgr-mutant ген, послідовність з L1) + розіслати RFQ. — `01_03` §3.7
- [ ] 👤 **ZIF-нанозим синтез:** сольвотермальний синтез nCoCuCeZIF (співпраця з нанохімією ЧНУ або НАН України, за співавторство Q1) — `01_03` §1 Катод. ⚠️ **Bottleneck:** ZIF чутливий до умов синтезу → жорстко прописати розмір 40–80 нм + SEM-контроль у T&C (макрокристали відпадуть з електрода). (`01_03 §3.7`)
- [ ] 👤 **CNC (целюлозні нанокристали):** закупка з ENERON або синтез з alpha-целюлози кислотним гідролізом
- [ ] 👤 **Поліпірол (PPy)** як опційний кополімерний підсилювач MET-стеку (паралельний з осмієвим полімером) — `01_03` §2.3
- [ ] 👤 Test 30-day stability на Ti-coins у синтетичному ксилемному соку — `01_03` §3.5
- [ ] 👤 UCST winter-lock тест PSBMA: -10°C → +25°C цикл, регідратація мембрани — `01_03` §2.1 Шар 5

##### Підблокер HW.5.IS — In Silico Stage 0 (Zero-Lab) — `01_03 §3.4`
> **Стратегія:** Computational reverse engineering хімії ДО першого Ti-monet. AlphaFold 3 + OpenMM + PySCF + scipy/numpy повністю Python-кервані → інтеграція з AI-clones. **Zero-Lab in-silico (= TRL 3) ✅ завершено (2026-05-25); фізичний TRL 4 = Ti-monet in-vitro (pending).** Q1-paper program (Стаття 1): ① Hammett mediator ✅, ② micro-solvation+speciation ✅, ④ FAD-GDH E° fix (+60→−265 мВ, Schachinger) ✅, ③ cathode λ/coupling ⏳ (Ru-fix validated: λ=0.78 vs Co ~3 eV). Then chemistry-notes backlog (↓) → draft.
- [ ] 👤 **Інфраструктура:** workstation NVIDIA RTX 4090 ($5–10K) АБО AWS p5.2xlarge / GCP g2-standard-12 ($2–5/год)
- [ ] 👤 **Joint Q1-publication з ЧНУ Мінаєвим:** "In Silico Design of Long-Lived Enzymatic Bio-Fuel Cells for Tree-Integrated Energy Harvesting" — `08_03` Стаття 28. **Текст draft-complete** (`paper/`: Methods/Results/Tables/Discussion/Abstract/Intro-40-refs/Fig2-cartoon, усі DOI ✅). Лишилось 👤: · [ ] 👤 **Fig 1** graphical-abstract (BioRender; code-schematic draft є) + **TOC-графіка** · [ ] 👤 фіналізувати cover letter (draft є) · ✅ **сабміт-ready** — publish-to-protect (UNI.3; `08_01 §2`): публікація = prior-art захист, без патентного гейту

###### 🧪 Chemistry-improvement notes (CHEM.N) — founder batch 2026-06-05, triaged + verified
> 31 triaged + verified 2026-06-06; **5 corrected-out/merged Ruthless-Pruned** (00_06 §4 — refuted/dup/relocated; **git history**: CHEM.28 epitaxial-prestress · CHEM.30 acid-ΔG · CHEM.12 done-by-② · CHEM.17 dup-of-CHEM.23 · CHEM.24 magnetic-CNT→`02_03 §1.5`); 26 active below. **+5 cathode/method notes 2026-06-06 → CHEM.32-36** (verified vs canon first: Co→Ru low-λ + cMOF already in `01_03 §3.2`; pH-protonation already in all MD scripts — batch ↓). **Full verdicts in the SSOT canon (docs/):** anode → `01_03 §3.1` · matrix → `01_03 §3.3` · cathode levers → `01_03 §3.2` · in-silico methods → `PIPELINE_STATUS` Future · aggregation → `L1 §2` · computed → `SUMMARY`/`L3`. Thin pointers below. ⚠️ = weak.

**P0 — in-pipeline (paper computes, ✅ canonized):**
- [x] CHEM.29 — Ru-λ 0.78 eV (cathode-fix) → [`SUMMARY`](protocols/ebfc/in_silico/SUMMARY.md) §Cathode
- [x] CHEM.23 — realistic mediator SO₂CF₃/CF₃ (① reframed) → `SUMMARY` §Mediator
- [x] CHEM.10 — Lys→Arg genipin-shield (LYS109/262) → [`L1`](protocols/ebfc/in_silico/L1_protein_architecture.md) §2
- [x] CHEM.20/26 — bis-Im speciation, cascade Δ −0.609 (aqua>bis-Im>chloro) → `SUMMARY` §Cluster-Continuum
- [x] CHEM.21 — FADH•-λ rescue → inner-sphere λ_i 0.39 eV → [`L3`](protocols/ebfc/in_silico/L3_quantum_chemistry.md) Nelsen-λ
- [x] cathode finalize — k_DET borderline (×1.4 lit-λ) → `SUMMARY` §Cathode
- [x] CHEM.16 — dynamic-tunneling ensemble ✅ (28b): MD-ensemble β·d = 2.02 ± 0.13 (15 frames) ≈ AF3 single-snapshot 2.05; conformational-gating 1.03× (modest) → tunnelling path **thermally robust** (validates the static §3.1). PBC fixed via mdtraj `image_molecules` (co-locates the separate FAD cofactor; `make_molecules_whole` alone insufficient) → `SUMMARY`/`L3`

**P1/P2 — Gen 2.1+ candidates (verified, deferred):**
- [ ] CHEM.11 — aggregation: 4 SASA hotspots ✅ (`L1` §2); next = polar-mut neighbor-SASA
- [x] CHEM.14 — FO-DFT t_ij rigor ✅ (24b→25): two-state Mulliken-Hush t_ij(Cu-Co) 0.00546 eV (~4× crude) + 0.18 eV site-gap → borderline **robust to coupling method**, ×10⁵ excluded → `SUMMARY` §Cathode
- [ ] CHEM.22 + CHEM.5 — COSMO-RS/MACE: ⚠️ NOT ②-closers (charged-couple / sampling-only) → QM/MM stays
- [x] CHEM.6 + CHEM.31 — enzyme-free / cMOF cathode levers (acid-pH ranked) → `01_03 §3.2`
- [ ] CHEM.8 + CHEM.2 — V-chelation: catechol safer than IP6 → Gen 2.1+ (`01_02`)
- [ ] CHEM.25 — hygroscopic IL [Ch][DHP] candidate (not baseline — drift) → Gen 2.1+
- [ ] CHEM.4 — Winter-Lock UCST tuning (acrylamide comonomer) → Gen 2.1+ membrane
- [ ] CHEM.1 — metal-free mediator: phenothiazine > TEMPO (OCV) → Gen 2.1+ pivot
- [ ] CHEM.3 — FAD-GDH@ZIF-8: ⚠️ glucose > 3.4 Å pore (needs defects) → Gen 2.1+
- [ ] CHEM.13 — rigid spacer: OPE > oligoproline (β) → Gen 2.1+ anode
- [ ] CHEM.15 — Ru/Ni-dope → subsumed by CHEM.29
- [ ] CHEM.9 — aromatic hopping: low (anode not rate-limiting + radical damage)
- [ ] CHEM.7 — de novo enzyme → Gen 3.0 moonshot (scaffold ≠ catalysis)

**Cathode-margin levers — founder batch 2026-06-06 (triaged vs canon `01_03 §3.2`):**
- [x] CHEM.32 — **Ru double-whammy: t_ij↑ NOT confirmed** (24c/24d): control Cu-Co=canon 0.00128 ✅, but Cu-Ru crude ΔSCF (×81) + FO-DFT (t_ij 0.105) both **non-physical** — frontier MOs all-Ru, no Cu-d partner (Cu-d/Ru-d energy-mismatched → no clean Cu↔Ru diabatic pair). λ↓ benefit stands (CHEM.29, ×31); the t_ij-boost is a hypothesis → CDFT constrained diabatic states (Мінаєв capstone) → `SUMMARY` §Cathode
- [ ] CHEM.33 — **oriented laccase immobilization** (His/Cys anchor → ZIF node): L3b ASSUMES T1↔ZIF proximity; random adsorption → T1 buried ~6.5 Å + arbitrary orientation → 15-20 Å → t_ij→0. 👤 experimental lever + flags a model-assumption to state in paper §3.4 → `01_03 §3.2`
- [ ] CHEM.34 — **conductive guest-host** PEDOT-in-ZIF-pores (vapour EDOT polymerisation → parallel delocalised path bypassing slow Cu-Co hops; distinct from the PEDOT:PSS matrix-additive already noted). ⚠️ ZIF-8 aperture ~3.4 Å vs EDOT → verify ingress / larger-pore ZIF. Gen 2.5 👤 → `01_03 §3.2`
- [ ] CHEM.35 — **benzimidazolate bridge** (ZIF-7/11) for enhanced Cu-Co **superexchange** t_ij (extended π vs 2-MeIm). ⚠️ trade-off: bigger ligand → longer M-M → t_ij exp-decay may offset the π-gain → testable via 24. Gen 2.x → `01_03 §3.2`
- [ ] CHEM.36 — local cathode acidity (solid-acid/Nafion on PTFE-GDL inner face): ⚠️ **mis-targeted** — boosts ORR proton supply, NOT the internal Cu-Co electron-hop site-gap bottleneck; xylem already pH ~4.5 + laccase acid-loving → marginal for the DET margin. Low

**Separate streams (not chemistry-paper):**
- [ ] CHEM.18 / CHEM.27 / CHEM.19 — cryoprotectant T-corr (firmware) / Belleville washers (hardware) / biological gasket (bio-seal) — tracked in their own modules

###### 🔬 In-silico pipeline — open computes (script audit 2026-06-06; detail → `PIPELINE_STATUS`)
> All ~37 `tools/in_silico/scripts/` audited — almost all ✅ (cached). Open work captured here so we never re-audit; closed/superseded = 21 · 21c · 29 (honest limitations-points, not work).
- [x] ✅ 🤖 **Re-run chain DONE:** 24b FO-DFT → 25 → ③ k_DET rigor: borderline **robust to coupling method** (t_ij 0.00546 ~4× crude + 0.18 eV site-gap; old ×10⁵ excluded) → `SUMMARY` §Cathode / `PIPELINE` 24b
- [x] ✅ 🤖 **②/tunnelling robustness DONE:** 34b ωB97X ②-speciation (functional-robust: aqua>bis-Im>chloro reproduced) → `SUMMARY` §Cluster-Continuum · 28b dynamic-tunnelling ensemble (β·d 2.02±0.13; image_molecules PBC)
- [ ] ✨ 🤖 **Refinements (optional, per-script additional analysis):** outer-sphere λ_o ✅ (29c → total anode λ 0.76–0.86 eV phys-end, confirms lit 0.7–0.8) · aqua/bis-Im × substituents + ωB97X for the series (21e) · real ΔG in k_ET (25 — FO-DFT scenario now uses the 0.18 eV site-gap; lit/computed-λ rows still ΔG=0) · Cu/Ce λ refinement (35; B3LYP over-estimates Co spin-crossover) · Os-complex MD ensemble (27, not just FAD) · full hydration shell + COSMO-RS/MACE probe (34) · k_cat sensitivity (30/30b) · ③-borderline R_ct in EIS ✅ (31b → band ~0.002–230 Ω). ⚠️ **λ_o (29c) is radius/ε-dominated · EIS-③ R_ct (31b) is Γ×k_DET-dominated (×10⁵ band) → both COMPUTED 2026-06-06 + confirmed INDICATIVE, not clean computes** (kinetic competition k_DET~turnover, NOT a fixed R_ct; caches `outer_sphere_lambda.json` / `cathode_det_rct.json`)
- [ ] 🧹 🤖 **Method-hygiene (founder pipeline batch 2026-06-06, verified):** (B2) pH-protonation **already done** — every MD script (10/11/12/14/15) calls `addMissingHydrogens(pH=4.5)`, 14 per-species 4.2-5.8 (note's pH-7-default premise is wrong). (B1) FAD AM1-BCC on AF3 geom **mostly OK** — antechamber/sqm geom-opts at AM1 before BCC (raw AF3 not used verbatim); optional RDKit MMFF pre-opt = minor robustness, low. (B3) DRY: `md_utils.prepare_protein` exists but 5 scripts duplicate it inline (byte-identical → safe dedup) + no shared PBC trajectory loader (28b `image_molecules` is local) → low-risk refactor (⚠️ `image_molecules` for multi-mol graph, `make_molecules_whole` for single-protein RMSD — not blanket). (B4) Apple-OpenCL fast-math precision regression test → nice-to-have for publication-grade 100+ ns (→ CUDA), not needed for current RMSD-stability claims
- [ ] 🏔️ 🔗 **Capstones (Мінаєв):** ④ protein QM-cluster E° (extend 32) · CDFT coupling (> 24b, needs PyCDFT) · QM/MM explicit-water cascade
- [ ] ⏸️ **Deferred → Стаття 2/3 / on-data:** 11 (20–50 ns MD, reviewer-grade equilibration) · 13 (D_eff model; L4 already uses lit 2e-6) · 16 (PE-drift 1%, bigger box) · 40 re-run vs Ti-coin CV/EIS when in-vitro data lands (40 already has a docstring — the audit's "missing" was a grep-filter artifact)

#### HW.6 — Resin barrier + Flush Mount Installation
- **P1** · 👤 · → `01_04 §3`
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів. **Корінь проблеми = інструмент свердління**, а не лише матеріал анкера.
- **Стратегія:** (a) Flush Mount step drilling — анкер врівень з корою, камбій не пошкоджено; (b) Microfrezing замість стандартного свердла — хірургічно чистий розріз не тригерить resinosis
- [ ] 👤 **Flush Mount step drilling** (`01_04` §3.1): тестування багатоступеневого свердла на калібрувальних колодах сосни (товщина перидерми → ширина широкої ступені)
- [ ] 👤 **Microfrezing** (`01_04` §3.3): закупити прецизійні кінцеві фрези типу MicroX (карбід вольфраму + TiN-покриття), стендовий тест на колодах vs стандартні шнекові свердла — порівняння resinosis intensity
- [ ] 👤 30° installation angle verification (узгоджено з Flush Mount)
- [ ] 👤 Hydrophilic coating test
- [ ] 👤 **Nafion-g-PSBMA анти-resin coating** (Шар 5 анодного стеку, `01_03 §2.1 Крок 5`, REWRITTEN 2026-05-22): цвітеріонний полі(сульфобетаїн метакрилат) ковалентно прищеплений до Nafion через SI-ATRP; 8 H₂O/ланцюг блокує абієтинову кислоту термодинамічно; протонна провідність зростає до 45.2 мС/см; UCST @ 5°C winter-lock. **PEG (Gen 1.0) повністю виключений** — недостатній гідратаційний шар, окислювальне розщеплення
- [ ] 👤 Hydrophobic/hydrophilic gradient test (PTFE знизу, гідрофільний верх) — додано в `01_04` §3.4
- [ ] 👤 Thermal installation test: T° нагріву (150-200°C), час витримки — додано в `01_04` §3.5 (резервний метод, тільки для нефункціоналізованих анкерів)
- [ ] 👤 FEM-моделювання теплового поля в Ti-6Al-4V анкері (λ = 6.7 W/m·K)
- [ ] 👤 **Біоміметичні покриття проти CODIT** (`01_04` §4): Zn-HAp + хітозан композит на периферійних стінках пор — лабораторний синтез та in vitro тест адгезії клітин паренхіми Pinus sylvestris (запит до біо-хабу ЧНУ, [`08_02`](08_02_Academic_Institutions_Registry))
- [ ] 👤 **PEDOT:PSS гідрогель інтерфейс** (`01_02` §1a.2, `01_04` §4.1): тонкий шар (10–50 µm) на стінках периферійних пор для модульного буферу Ti↔калюс — верифікація провідності EBFC після нанесення
- [ ] 👤 **Лігнін-покриття** (`01_04` §4.1): «свій» полімер для дерева — тест зменшення каскаду CODIT Wall 4
- [ ] 🔗 **SA reservoir — НЕ інтегрувати без верифікації** (`01_04` §4.2 caveat #2): чи не маскує екзогенна саліцилова кислота природний сигнал стресу, який вимірює Lorenz attractor (запит до біо-хабу, [`08_02`](08_02_Academic_Institutions_Registry))

#### HW.7 — BQ25570 resistors verification
- **P1** · 👤 · → `02_03`
- **Опис:** CJMCU-25570 може мати Li-Po дефолт (VBAT_OV = 4.2V замість 5.5V для supercap)
- **Блокує:** Фіналізацію схеми, PCBA production
- [ ] 👤 Виміряти 8 резисторів мультиметром
- [ ] 👤 Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] 👤 Замінити SMD резистори якщо мисматч
- [ ] 👤 Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (7 блокерів)
- **P1** · 👤 · → `02_02`
- [ ] 👤 BLOCKER-1: Матеріал напилення piн → Gold (Hard Gold, Au 0.76 µm)
- [ ] 👤 **BLOCKER-1a (NEW 2026-05-16): Hard Gold ENIG на центральній площадці анкера** (торець виводу шини Zone 1, ø 4–5 мм) — **обов'язково**, інакше золотий pogo притискається до голого Ti → гальванічна пара Ti↔Au → Rc drift > 500 мОм за 18–36 міс → cold-start fail. Передати specмапу селективного gold-plating заводу (~$0.05/анкер). Деталі — `02_02 §1.2` ⚠️ блок.
- [ ] 👤 BLOCKER-2: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
- [ ] 👤 BLOCKER-3: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
- [ ] 👤 BLOCKER-4: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression
- [ ] 👤 BLOCKER-5: Допуски соосності (XY-площина) → Lead-in chamfer
- [ ] 👤 **BLOCKER-6 (NEW 2026-05-16): 1D Tolerance Stack-Up по Z-осі** — обов'язковий розрахунок RSS або worst-case envelope для PCB→Radome→O-ring→Zone3 stack так, щоб O-ring завжди компресував 15-25% **і** Pogo Pin завжди в 50-70% страйку (0.76-1.06 мм з 1.52). Без цього ~10-30% капсул йде у брак (О-ring under-compressed → water ingress, АБО Pogo under-engaged → Cold-Start Fail). Деталі — `02_02 BLOCKER-6`. **P0** для PCBA/анкер/Радом freeze.

#### HW.9 — PCB KiCad layouts
- **P1** · 👤 · → `02_01`
- **Опис:** Soldier PCB та Queen PCB: "Не розпочато"
- [ ] 👤 Soldier PCB layout (KiCad)
- [ ] 👤 Queen PCB layout (KiCad)
- [ ] 👤 RF Keep-Out Zone verification

#### HW.11 — Conformal Coating (REVISED 2026-05-16: Sylgard відхилено через TinyML)
- **P1** · 👤 · → `02_01`, `02_02 §3.4`
- **Опис:** Раніше планувався full-potting Sylgard 184 (Shore A < 50 проти crack кварцу при -20°C). Архітектурна рецензія виявила **критичний конфлікт**: Sylgard 184 — відомий **акустичний демпфер** (3-bands attenuation 15–25 dB @ 16 kHz), який глушить п'єзодиск Soldier для TinyML-детекції бензопили та кавітації ксилеми (`03_03`).
- **Нове рішення (v3):** **Parylene C 10 µm (CVD)** для серійного виробництва — конформне покриття всіх SMD-компонентів та припою через CVD-деposition; selective masking п'єзодиска (відкрита поверхня або тонка PDMS ≤ 10 µm); внутрішній об'єм капсули — повітря (опційно desiccant). Для прототипів TRL 4–5 — acrylic conformal (Humiseal 1A33) easily reworkable. ✅ Acoustically transparent, ✅ IP67 з O-ring.
- **Блокує:** Hardware freeze, IP67 certification, TinyML функціональність
- [ ] 👤 Обрати coating: Parylene C (production) + Humiseal 1A33 (prototypes)
- [ ] 👤 Контакт з CVD-сервісом Parylene-deposition (Київ / Львів — пошукати спеціалізовані PCB-house)
- [ ] 👤 Верифікувати п'єзо-attenuation: тест 16 kHz tone з/без coating на калібрувальному стенді
- [ ] 👤 Верифікувати з кварцовим резонатором при -20°C / +60°C (Parylene Shore D ~50, м'якший за air-gap воду)

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **P1** · 👤 · → `02_03 §4`
- **Опис:** При тривалій інсоляції EBFC може генерувати напругу >5.5V → overcharge supercap → деградація/вибух
- **Блокує:** Hardware safety, TRL 5
- [ ] 👤 Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
- [ ] 👤 Додати TVS-діод або зенерівський обмежувач як backup

#### HW.13 — MPPT coefficient verification for EBFC
- **P1** · 👤 · → `02_03 §4`
- **Опис:** Поточний MPPT = 50% VOC (R_OC1=R_OC2=10MΩ) — **занадто низько для EBFC**. EBFC (GOx/Laccase) має специфічну поляризаційну криву (Міхаеліс-Ментен + Тафель), MPP лежить у діапазоні 60-70% VOC. При 50% — зона масо-транспортних обмежень ферменту
- **Рекомендація (REVISED 2026-05-16 — TI convention):** Почати з 65%, з іменуванням за TI BQ25570 datasheet SLUSBH2G §8.2.3.2: **R_OC1 = 10.0 MΩ** (нижнє плече, VOC_SAMP → GND), **R_OC2 = 5.36 MΩ** (верхнє плече, VSTOR → VOC_SAMP). Формула: V_MPP / V_OC = R_OC1 / (R_OC1 + R_OC2). ⚠️ Не плутати позначення — якщо запаяти за зворотньою конвенцією, фракція стане 35% замість 65% → знекровлення ферменту.
- **Блокує:** Max EBFC power, optimal charge speed
- [ ] 👤 Зняти повну P-V криву (потужність-напруга) EBFC
- [ ] 👤 Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
- [ ] 👤 Визначити оптимальну фракцію (починати з 65%)
- [ ] 👤 Якщо потрібно — замінити R_OC1/R_OC2 (звіряти з TI Figure 42 та `02_03 §4` SSOT Convention block)
- [ ] 👤 **Cold-start R_int** (`02_03 §1.5`): виміряти R_int EBFC (V_OC + V@15µA); якщо > 12 кΩ → cold-start oscillation-loop → серійний стек 2× EBFC (A) / паралель (B) / LTC3108 DNP-footprint (C). Не замовляти 100 PCBA без DNP-LTC3108 до перевірки.

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **P1** · 👤 · → `02_05 §Зимовий енергодефіцит`
- **Опис:** Phase 3 (Starlink Mini): 44 Wh/day consumption vs 18.75 Wh/day winter generation = -25 Wh/day deficit. 12V/20Ah LiFePO4 → 7.7 днів автономності
- **Пріоритет:** Phase 3 only (Phase 2.5 unaffected)
- [ ] 👤 Збільшити батарею до 40Ah (15 днів автономності), АБО
- [ ] 👤 Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
- [ ] 👤 Встановити 100W solar panel

#### HW.15 — BMS + VBAT decoupling для SIM7070G
- **P1** · 👤 · → `02_05 §Пікові струми SIM7070G`, `§2.2.1`
- **Опис:** SIM7070G TX peak current до 2A. Дві окремі проблеми: (1) BMS model не вказано в BOM (system-level); (2) транзієнтна просадка VBAT модему при 2A burst → brownout reboot (module-level). Тепер з обома вирішеннями.
- **Module-level fix (✅ specification зафіксовано 2026-05-16):** 5-cap tank bank біля VBAT pin SIM7070G — 470 µF aluminum polymer SP-Cap (Panasonic EEFCX0J471R) + 100 µF MLCC X7R 25V 1210 + 10 µF X7R 0805 + 100 nF X7R 0402 + 33 pF NP0 0402. Розрахункова просадка: 8 mV (margin > 35× проти 700 mV brownout). Деталі — `02_05 §2.2.1`.
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] 👤 Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [ ] 👤 PCB layout: розмістити C_BULK ≤ 10 мм від VBAT pin, HF caps впритул
- [ ] 👤 Оновити BOM (закупка 5 нових компонентів)
- [ ] 👤 Bench: фізично звірити маркування модему на прототипі = **SIM7070G** (не SIM7000G; найменування у firmware/BOM/`02_05` вже уніфіковано — лишилась лише фізична звірка)
- [ ] 🔗 Firmware: додати `AT+CPSMS` + `AT+CEDRXS` (PSM/eDRX, idle ~3 µA) у Queen flush-цикл — `03_02`

#### HW.16 — Thermal management в IP67 enclosure
- **P1** · 👤 · → `02_05 §Теплове управління IP67`
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею; розряд нижче −20°C → graphite plating damage
- ✅ Зроблено: тепловий бюджет IP67 (Phase 1/2.5 ~130мВт→ΔT<1K; Phase 3 3Вт→ΔT~4.5K; sun load +15K; sun-shade рекоменд.) + backend critical-temp гілка. Канон: `02_05 §4а`.
- [ ] 👤 Додати temperature sensor (NTC або DS18B20)
- [ ] 👤 Реалізувати hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype (Деталь 4) — REVISED 2026-05-16
- **P1** · 👤 · → `02_01 §5.2`, `01_04 §5.5`
- **Опис:** Деталь 4 (PEEK Crown / Капсула-Радом) — радіопрозорий купол ∅20–30 мм, який «насаджується» на зовнішню різьбу **Деталі 3 = Zone 3 = КАТОДНОГО ФЛАНЦЯ** (раніше документ помилково писав «Деталь 3 (Анод)» — критичний SSOT-bug, виправлено). Різьба або байонет + O-ring EPDM → IP68. Керамічна SMD-антена в ≥ 8 мм Z-clearance від Ti-фланця (`02_01 §5.3` revised — 2D ≥3мм, **3D ≥8мм** вертикально + overhang за периметр Ti). Anti-overgrowth shield: виступ ≥ 3 мм + R ≥ 5 мм + super-hydrophobic coating (Fluoropel PFC-1601V) — `01_04 §5.5`.
- **Блокує:** Ceramic antenna protection, RF performance validation, Zero-Touch Assembly validation, long-term cathode O₂ access
- [ ] 👤 KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] 👤 Визначити тип кріплення: різьба на **Деталь 3 = Катод** (НЕ Анод!) vs байонет
- [ ] 👤 Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] 👤 **HFSS-симуляція** з 3D-моделями Ti-фланця + PEEK-радома + чіп-антени (нова вимога 02_01 §5.3 revised) — VSWR < 1.8, gain ≥ −2 dBi
- [ ] 👤 Замовити PEEK прототип з виступаючим конусом ≥ 3 мм над корою + R заокруглення ≥ 5 мм (anti-overgrowth shield, `01_04 §5.5`)
- [ ] 👤 Super-hydrophobic coating: контакт із постачальником Fluoropel PFC-1601V або еквівалент, технологія nano-texturing
- [ ] 👤 Верифікувати RF performance (VSWR, КСВ) з антеною під радомом + з Ti-фланцем нижче (overhang тест)
- [ ] 👤 12-місячний польовий тест anti-overgrowth shield на тестовому дереві — фотодокументація щоквартально

#### HW.18 — Starlink DTC: ESP32-S3 vs SIM8200G-M2 WiFi co-processor
- **P2** · 👤 · → `02_05 §Starlink DTC vs Mini`
- **Опис:** Phase 3 (Starlink Mini terminal) потребує WiFi co-processor. Архітектурне рішення між ESP32-S3 та SIM8200G-M2 не прийнято
- **Пріоритет:** Phase 3 only
- ✅ Зроблено (🤖): decision memo + рекомендація **ESP32-S3** → `02_05` BLOCKER-1.
- [ ] 👤 Підтвердити рішення (рекоменд. ESP32-S3)
- [ ] 🤖 Оновити 03_02 з рішенням
- [ ] 🔗 Додати co-processor firmware до `firmware/`

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **P2** · 👤 · → `02_04 §4.2`
- **Опис:** Раз на добу вимірювати чисту VOC EBFC (при від'єднаному навантаженні) для розрізнення "дерево хворіє" vs "конденсатор деградує". Обидва стани проявляються як зростання delta_t. ADS1220 (24-bit ADC) + TPS22860 (load switch) для прецизійного duty-cycling вимірювання. Для TRL 6 достатньо вбудованого 12-біт ADC STM32
- **Пріоритет:** TRL 8+ (після базової валідації в полі)
- [ ] 🤖 Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] 👤 Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- ✅ Зроблено (🤖 verify, 2026-05-29): DCI-safe дизайн зафіксовано → `02_04 §4.2`. Попереднє «корекція моделі Лоренца» **зламало б DCI** (server-Z ≠ device-Z, бо firmware VOC не має → fraud-flag на кожному пакеті). Корекція має жити на slashing-шарі, не в Z.
- [ ] 🤖 Backend (gated): `voc_mv` колонка + VOC-корекція у `ContractHealthCheckService` (виключити hardware-confounded дерева зі slashing-підрахунку), **НЕ в `Attractor`**. Чекає firmware VOC-вимір + delivery-контракт.

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **P2** · 👤 · → `02_03 §6`
- **Опис:** Buffer Cap 100µF на лінії VOUT для LoRa TX peak. Рання специфікація вказувала танталовий конденсатор, але його струм витоку (1-10 мкА) подвоює/потроює E_sleep (1.5 мкА). Документація оновлена на MLCC X5R/X7R (виток ~десятки нА)
- ✅ Зроблено: DC bias derating (~20% @3.3V/6.3V → ~80µF ефективна, достатньо для 100мс LoRa TX піку). Канон: `02_03 §6`.
- [ ] 👤 Обрати конкретний part number: 100µF/6.3V X5R 1210 (напр. Murata GRM32ER60J107ME20)
- [ ] 👤 Додати до KiCad BOM (HW.9)

#### HW.21 — Hybrid energy R&D: TEG + Anchor stacking (post-TRL 6)
- **P3** · 👤 · → `01_03 §5`
- **Опис:** Future R&D для усунення зимового енергодефіциту без збільшення EDLC. Два **доповнювальні** (НЕ замінюючі) джерела: (a) TEG Bi₂Te₃ на стовбурі (~50–200 µW зимою при ΔT 15–25 K серцевина ↔ амбієнт), (b) послідовне з'єднання 3–4 анкерів (V_OC × 3–4 для кластерних/арктичних розгортань).
- **Пріоритет:** TRL 7+ (post field validation Phase 2.5). Поточна одно-анкерна архітектура задовольняє BQ25570 cold-start 330 мВ.
- **Не плутати з:** SolarBotanic «nano-leaves» — не інтегруємо без peer-reviewed per-node даних
- [ ] 👤 TEG: вибір модуля Bi₂Te₃ (4×4 см), стендовий тест ΔT-V кривої на тестовому стовбурі
- [ ] 👤 TEG: інтеграція з BQ25570 multi-input (можливість одночасного MPPT для EBFC + TEG)
- [ ] 👤 Stacking: 3-анкерна тестова конфігурація на одному дереві з PEEK-ізоляцією (Zone 2)
- [ ] 👤 Stacking: оцінка впливу на провіженінг (групова реєстрація DID) та Lorenz-аналітику (декомпозиція V_OC)
- [ ] 🔗 Залежить від HW.13 (P-V крива EBFC) для правильного бюджетування доповнення

#### HW.22 — Sterilization protocol (No EtO, Split-cycle + Aseptic, REVISED 2026-05-16)
- **P1** · 👤 · → `01_04 §6`
- **Опис:** Раніше — single-cycle terminal gamma 25 кГр в запакованому стані. **Виявлений архітектурний конфлікт:** PTFE-GDL мембрана (HW.25, Zone 3) зазнає chain scission при ≥10 кГр → крихкість, втрата bubble point → катод затоплюється першим дощем. Terminal gamma 25 кГр **неможлива** на готовому виробі з PTFE.
- **Нова стратегія (Split-cycle + Aseptic Assembly, `01_04 §6.3`):**
  - **ГІЛКА A — Ti-анкер з ферментами (без PTFE):** UV-C + 70% EtOH → low-dose gamma **15 кГр** (не 25) → SAL 10⁻⁶
  - **ГІЛКА B — PTFE-GDL + O-ring (окремо):** autoclave 121°C / 15 psi АБО EtO (без ферментів — EtO дозволено)
  - **ФІНАЛЬНА ЗБІРКА:** аcептична ламінація PTFE на Zone 3 у ISO Class 5 cleanroom; параметричний випуск за ISO 13408-1
- **Блокує:** Перехід від stage 3 (лабораторний прототип) до Stage 4 (польові випробування).
- [ ] 👤 ГІЛКА A: Тест активності ферментів **до та після** UV-C + 70% EtOH + **gamma 15 кГр** (не 25 кГр) — деградація ≤ 20%
- [ ] 👤 ГІЛКА B: PTFE-GDL bubble-point test до та після autoclave 121°C / EtO — Δ ≤ 5% (інтегральність мікропор)
- [ ] 👤 Фінальна збірка: ISO Class 5 cleanroom validation (particle counts, settle plates, finger dabs); bioburden ≤ 100 CFU перед F1
- [ ] 👤 CV-вимірювання EBFC-струму до/після ПОВНОГО циклу (A + B + Final) — деградація ≤ 25%
- [ ] 👤 Стерильність-тест USP <71>: TSB + FTM, 14 діб, відсутність росту фінального виробу
- [ ] 👤 LAL-тест на ендотоксини USP <85>: ≤ 0.5 EU/мл
- [ ] 👤 Обладнання: low-dose Co-60 (15 кГр) для ГІЛКИ A; autoclave або EtO chamber для ГІЛКИ B; ISO Class 5 LAF cabinet для аcептичної фінальної ламінації
- [ ] 👤 Постачальник Co-60: Чорнобиль НДІ радіаційної медицини / Київ ІРОНЦ — підтвердити можливість low-dose 15 кГр (не стандартної 25)

#### HW.23 — HIP postprocess specification for SLM anode
- **P0** · 👤 · → `01_02 §1.7 BLOCKER-3`
- **Опис:** SLM-друк створює залишкові термічні напруження та внутрішню металургійну пористість. Без HIP (Hot Isostatic Pressing) ці дефекти стануть зародками втомних тріщин при 20-річному циклічному навантаженні.
- **Параметри:** 920°C ± 20°C / 100–150 МПа Ar / 2–4 год / контрольоване охолодження
- **Блокує:** Втомну міцність, 20-річну довговічність, TRL 5
- [ ] 👤 Передати специфікацію HIP-постпроцесу на завод (Київ/Дніпро) разом зі специфікацією SLM
- [ ] 👤 Перевірити наявність HIP-обладнання у заводу-кандидата (часто окремий підрядник)
- [ ] 👤 SEM/EDS до та після HIP — підтвердити закриття внутрішніх мікропустот
- [ ] 👤 Втомні випробування (Wöhler) у синтетичному ксилемному соку — еквівалент 5+ років фретингу

#### HW.24 — Staged validation gate (SLA → Ti-coin → full anchor)
- **P0** · 👤 · → `01_01 §6.1 BLOCKER-2`
- **Опис:** Тризонний анкер — складна збірка. Передчасний перехід на DMLS-партію 100 шт. без верифікації базових принципів був методологічною помилкою. Цей блокер фіксує гейт: 100 анкерів замовляємо **тільки** після проходження двох попередніх етапів.
- [ ] 👤 **Stage 1 — SLA макети (5 шт):** друк прозорого фотополімеру (Form 3 або SLA-сервіс) для перевірки form & fit, ергономіки, Flush Mount step drilling, допусків press-fit «пластик-в-пластик»
- [ ] 👤 **Stage 2 — Ti-coins (~15 шт, ⌀10–15 мм або 10×10×1 мм):** SLM-друк + EAAE (з обов'язковим dehydrogenation bake `01_02 §1.3 Крок 5b`) → **Gen 2.0 анодний стек** (одношаровий dgrFAD-GDH + Os polymer в geniпin-chitosan-CNC матриці поверх fMWCNT, `01_03 §2.1`) + **Gen 2.0 катодний стек** (Laccase + nCoCuCeZIF nanozyme гібрид DET, `01_03 §2.2`) + **Nafion-g-PSBMA анти-resin coating** → in vitro CV/EIS у синтетичному ксилемному соку (рецептура від біо-хабу ЧНУ, [`08_02`](08_02_Academic_Institutions_Registry)). 30-day stability gate. Chloride tolerance test (0.25 М NaCl). UCST winter-lock тест (-10°C → +25°C цикл). 💡 **Electrode-дизайн:** замовити з «вушком» (отвір/виступ на краю) для кріплення потенціостат-кліпси без пошкодження активної площі (A_electrode = 2 см²). In-silico predictions для порівняння — `40_validate_vs_experiment.py` готовий. (`01_03 §3.7`)
- [ ] 👤 **Stage 3 — Full anchor (3–5 шт):** SLM+HIP анодних секцій, CNC PEEK-втулок, SLM/EBM катодних фланців, повний press-fit + EBFC у синтетичному соку
- [ ] 👤 **Stage 4 — Партія 100 шт:** після підтвердження Stage 3 — оптове замовлення для польових випробувань

#### HW.25 — PTFE-GDL membrane (Cathode)
- **P1** · 👤 · → `01_04 §5`
- **Опис:** Газодифузійний шар для катодного фланця (Zone 3) — пропускає атмосферний O₂, блокує краплі води. Без коректної специфікації катод або задихається (опір O₂), або затоплюється (flooding) при дощі/росі.
- **Параметри:** e-PTFE або d-PTFE, розмір пор 0.2–1.0 µm, товщина 20–100 µm, крайовий кут > 110°
- [ ] 👤 Закупка зразків e-PTFE / d-PTFE (Gore-Tex industrial, Donaldson, або український постачальник)
- [ ] 👤 Стендовий тест breakthrough pressure: H₂O column 30 см → 1 м (повинна витримати ≥ 1 м)
- [ ] 👤 Електрохімічний тест: ORR-струм катода з PTFE-GDL vs без — порівняння продуктивності
- [ ] 👤 12-тижневий тест з імітацією дощу/росі — резистентність до flooding
- [ ] 👤 Сумісність O-ring (EPDM vs FKM) з PTFE та pH 4.5–5.5
- [ ] 👤 Метод ламінації PTFE на катодний фланець (без клеїв — механічний обтиск по периметру)

#### HW.26 — PEEK Cold-Flow Creep: Mechanical Lock (NEW 2026-05-16)
- **P1** · 👤 · → `01_01 §4.3 BLOCKER-3`
- **Опис:** PEEK як термопласт **повзе** під постійним hoop-stress press-fit на 5–10 років. Без mechanical lock через 10 років contact pressure падає на 60% → втрата герметичності O-ring + ризик вириву Zone 3 при штормі. Mandatory complementary fix до §4.2 ΔCTE розрахунку натягу.
- **Параметри:** Annular barbs (трикутні, h=0.25-0.4mm, α=30°/β=70°) на Zone 1 та Zone 3 контактних поверхнях + DIN 471 Ti retaining ring у канавках ∅0.8×0.6mm + hex tolerance ≤ 0.05mm radial. Press-fit при T = 150°C (>T_g PEEK 143°C) для barb engagement.
- **Cost impact:** ~$0.30/анкер (negligible vs $15-18 base DMLS cost)
- **Блокує:** Long-term reliability (20+ років), TRL 7→8 gate
- [ ] 👤 Update nTop CAD-моделі: додати annular barbs на циліндричних частинах Zone 1 та Zone 3
- [ ] 👤 Update CNC-чертежі: retaining ring grooves на anchor end Zone 1 + flange end Zone 3
- [ ] 👤 Закупка DIN 471 internal retaining rings Ti grade 2 (або 316SS) у відповідних розмірах
- [ ] 👤 Update press-fit процедуру: temp 150°C (>T_g PEEK 143°C для Victrex 450G) + контрольована сила 800–1200 N
- [ ] 👤 **FEA-валідація** ANSYS LS-DYNA з visco-elastic PEEK Prony model — simulation 10y creep, residual pull-out > 200 N
- [ ] 👤 Stage 1 SLA-mock (HW.24): включити barb-detail у фотополімерну збірку для перевірки клацання

#### HW.27 — Dehydrogenation Bake: Hydrogen Embrittlement Mitigation (NEW 2026-05-16)
- **P1** · 👤 · → `01_02 §1.3`
- **Опис:** EAAE (Крок 4) генерує атомарний H через реакції Ti+HCl/H₂SO₄; ультразвукова кавітація прискорює дифузію H у кристалічну ґратку Ti. Без вакуумного відпалу між промивкою (Крок 5) та пасивацією (Крок 6) поверхневий шар TPMS-гіроїда стає brittle (TiH₂) на глибину 5–50 µm → втомне руйнування при першому ж шторм-навантаженні.
- **Параметри:** Вакуумна піч 250°C ± 25°C, 10⁻³ mbar, 3 год (range: 200–300°C / 2–4 год). Обов'язково within 2 hours of rinse (H мігрує глибше при кімнатній T).
- **Контроль:** LECO RH404 vacuum hot extraction → H content < 100 ppm (ASTM B348 grade 5 ліміт 150 ppm).
- **Блокує:** Втомну міцність TPMS-гіроїда, заявлений термін служби 20+ років, TRL 4→5
- [ ] 👤 Передати специфікацію Крок 5b заводу-підряднику (Київ/Дніпро) разом із протоколом EAAE
- [ ] 👤 Перевірити наявність вакуумної печі 200–300°C у заводу-кандидата (або стороннього subcontractor)
- [ ] 👤 LECO RH404 hot extraction analysis на тестовому купоні з кожної партії
- [ ] 👤 Втомне тестування Ti-coin Stage 2 (HW.24) — порівняння з/без dehydrogenation bake для підтвердження ефекту
- [ ] 👤 Ti-coin Stage 2 — замовити пару **bare + ZIF-coated** (chem-note triage 2026-06-06): порівняння деградації струму ізолює ZIF enzyme-stabilization → готовий «ZIF nanozyme as enzyme stabilizer» результат (→ Стаття 2 stability; доповнює, не заміняє, in-silico ET-механізм Стаття 1)

#### HW.28 — Anti-Overgrowth Shield для Zone 3 (NEW 2026-05-16)
- **P2** · 👤 · → `01_04 §5.5`
- **Опис:** Поправка Фази 4 ксилемоінтеграції — анкер **НЕ повинен** повністю поглинатися стовбуром. Лише Zone 1 (анод) інтегрується; Zone 3 (катод) має залишатися постійно експонованим атмосфері для ORR (Laccase + AuNPs + O₂). Без shield через 3–5+ років нова кора накриває PTFE-GDL → дифузія O₂ зупиняється → EBFC мертва за 2–3 додаткових роки.
- **Три захисти (complementary):** (A) виступаючий PEEK Radome conus ≥ 3 мм + R заокруглення ≥ 5 мм; (B) super-hydrophobic fluoropolymer coating (CA > 150°, Fluoropel PFC-1601V); (C) periodic forester maintenance every 5–7 років (мікрорізець для зчищення приростаючої тканини).
- **Cross-ref:** Інтегровано у HW.17 (PEEK radome prototype) + OPEX додано у `07_02`
- **Блокує:** 20-річний термін служби EBFC, OPEX-розрахунок (`07_02`)
- [ ] 👤 Update PEEK Radome CAD з виступаючим конусом — у HW.17
- [ ] 👤 Закупка/тест super-hydrophobic coating (Fluoropel PFC-1601V або аналог)
- [ ] 👤 Field protocol для forester visit: процедура зачистки приростаючої тканини без traumatic surgery
- [ ] 👤 12-місячний польовий тест на тестовому дереві (Черкаський бір)
- [ ] 👤 Update `07_02` OPEX: 1 visit / 5–7 років × $20/visit = ~$3–4/рік/анкер (форестер у Черкаському борі)

#### HW.29 — Board-to-Board Connector pair: Power Deck ↔ RF Deck (NEW 2026-05-16)
- **P1** · 👤 · → `02_01 §3.1`, `§5.3`
- **Опис:** Multi-deck PCB архітектура (Power Deck + RF Deck, standoff 8–10 мм) була специфікована у §5.3 без відповідного компонента у BOM. Без B2B-конектора RF Deck не отримує живлення 3V3 (Pogo Pins зайняті VIN_DC+GND). Тепер BOM включає Samtec FTSH header + CLT socket (1.27 мм pitch SMD, 8–10 мм stack) ~$0.85/пара.
- **Альтернатива (дорожча):** rigid-flex PCB замість двох плат + B2B (~+$1.50, але усуває механічну точку відмови).
- [ ] 👤 KiCad: place B2B footprints на обидві деки + перевірка signal integrity для 6-8 сигналів (3V3, GND, VSTOR_sense, EBFC_sense, piezo_EXTI, BQ25570 EN)
- [ ] 👤 Виміряти insertion loss + height variation на 5 зразках першої партії
- [ ] 👤 Pre-fabrication sanity check vs `HW.8 BLOCKER-6` (B2B stack height впливає на Z-tolerance envelope)

#### HW.30 — SMD Piezo + Acoustic Pad (Zero-Touch Wake) (NEW 2026-05-16)
- **P2** · 👤 · → `02_01 §6`
- **Опис:** Раніше — клеєний ∅27 мм через-отворний п'єзодиск з дротами до GPIO. **Порушення Zero-Touch §5.2:** клеєння + дроти ≠ робот pick-and-place. Pogo Pins вже зайняті VIN_DC+GND.
- **Нове рішення:** SMD-piezo (Murata 7BB-15-6L0 / TDK B-Series / Mallory MSR205P) на нижній стороні Power Deck + Bergquist Sil-Pad 1500ST (0.5–1.0 мм, Z_acoustic ≈ 1.5 МRayl ~ Ti) як coupling до Ti Zone 3. Сигнал через B2B (HW.29) до RF Deck → BAT54S → EXTI GPIO. Усе SMD; робот installs everything.
- [ ] 👤 Вибрати SMD-piezo з 3 кандидатів (Murata/TDK/Mallory), компроміс sensitivity vs пасивний voltage swing на резонансі ~4 кГц
- [ ] 👤 Acoustic coupling test: SMD-piezo + Sil-Pad + Ti-coin → подаючи 16 кГц tone через анкер → виміряти voltage spike на p'єзо vs стара ∅27 мм через-отв. архітектура
- [ ] 👤 Verify EXTI wake-on-vibration latency vs стара через-отв. baseline (target < 5 мс)
- [ ] 👤 **Interrupt-storm mitigation** (нот.5): амплітудний поріг — hardware comparator/RC АБО software fast-amplitude gate, щоб вітер/дощ/гойдання гілок НЕ будили повний аудіо-цикл → drain-захист 0.47 F supercap (поточно лише `BAT54S` voltage-clamp, без порогу; `03_03 §1.2`)
- [ ] 👤 Lifecycle test: Sil-Pad creep під 30-40% compression × 20 років (Arrhenius accelerated)

#### HW.31 — Queen Antenna Split (868 LoRa tuned ≠ dual-band)
- **P0** · 👤 · → `02_05 §7`
- ✅ Рознесено в каноні: поз.11 wideband LTE-M/NB-IoT (700–2700 МГц, Kyivstar B1/B3/B7/B8/B20, опц. LTE+GNSS combo) · поз.12 LoRa 868 **tuned** 5 dBi fiberglass omni (OD8-868/ALL.4101) — окремі RF-порти SX1262 vs SIM7070G; dual-band SMA відхилено (VSWR>2.5 @868 → −3-5 дБ EIRP). · [ ] 👤 freeze поз.11/12 у BOM Королеви при 02_05 BOM freeze

## §03 · Firmware

#### FW.2 — AES-128-ECB → AES-128-CCM (28B packet, wire-rev2) [post-ARCH.42]
- **P0** · 🤖 · → `03_05 §2.1`
- ✅ дизайн AES-128-CCM (rev1 24B → **wire-rev2 28B**, нижче) + backend-парсер (`process_ccm_chunk` + `Cryptography::LoraCcm`, OpenSSL) + firmware freeze-contract emit/decrypt + host-тести (golden-vector parity + tamper-семантика, **не залізна крипта**); FC у RTC DR15. **INERT** — флаги `FW2_CCM_ENABLED`/`TELEMETRY_CCM_ENABLED` off → ECB ще живий у проді. FC/nonce/cold-boot політика (📐 ЄДИНЕ ДЖЕРЕЛО) + CCM-пакет/wire — канон [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security). Закриває ECB→CCM/MIC/replay (BLOCKER-2/3) + SEC.10 panic + FW.29; LoRa-ключ у SE (SE050, SEC.6). 🔴 silicon `CRYP_AES_CCM` ще НЕ перевірено ↓.
- ✅ (2026-06-12) **TRL-7 monotonic FC host-half: Flash high-water** (канон [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) 📐, KV-ключ `0x14` — реєстр [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA)): nonce-унікальність через cold-boot тепер **безумовна при живому Flash-якорі** (інваріант I-HW: переданий FC < межі у Flash; було: імовірнісна HRNG, MEDIUM — лишилась тільки fallback'ом). `common/fc_hiwater.h` (STRIDE 256/MARGIN 8, epoch-край клемпиться → нову епоху дає FW.17-ротація) + wiring `main.c` за гейтом `FW2_CCM_ENABLED` (boot-кеш після спільного KV-mount'а, КЕНОЗИС-advance, **атомарний floor+advance** у `Load_Frame_Counter` — подвійний brownout не повторює nonce, сторожа-останній-рубіж у `Build_CCM` energy-gated) + сценарні host-тести (`test_flash_kv.c` секція FW.2: інваріант щоцикл, подвійний brownout, fault-injection → кеш недоторканий). SE050 monotonic counter — лише alt для L2 (не потрібен high-water). Residual = той самий bench, що FW.8/FW.17 (Flash-KV HAL-глю на кремнії).
- ✅ (2026-06-12) **WIRE-REV2 28B — ревізія ДО фліпу (founder decision):** wire-черга мала 5 претендентів без місця + 2 приховані регресії (FW.18b `thr_invalid` мовчки випав із 24B-freeze; gossip гинув від per-Soldier ключів) → формат ревізовано, поки всі три сторони ще за гейтами (нуль польової міграції). 28B: AAD `[DID:4|gossip:1|FC24:3]` (нонс байт-у-байт rev1 — replay-guard незмінний) + ciphertext 12B (+`device_z` u16×512 для FW.31 numeric DCI, +`diag [thr_invalid:5|fauna:2|fc_degraded:1]`, +`vpd_index` для HW.32) + MIC 8B без компромісу. Airtime: 24..27B коштують однаково (символьна квантизація) — перші 3B задарма, 28-й = +12 мДж/TX свідомо (дім для VPD до приходу BME280 — без другого міграційного циклу). KAT-вектори регенеровано OpenSSL-оракулом (C `ccm_kat_vectors.h` ≡ Ruby golden); `lora_ccm.h` + Soldier emit + Queen parse + `Cryptography::LoraCcm` + `process_ccm_chunk` (29B chunk) + спеки обабіч. **SSOT: [`03_05 §3.2`](03_05_Hardware_Symmetric_Crypto_and_Security) + 📒 wire-budget ledger там само** (нові претенденти на байти реєструються в ledger, НЕ в трекері). · [ ] 🤖 верифікувати `CRYP_AES_CCM` на STM32WLE5JC REVB (RM0461 §27.4; bench-атестація скриптована — RUNBOOK §2 + `02_selftest_attest.py`, PASS = дозвіл flip) → flip обидва флаги — **ЄДИНИЙ HW-залежний пункт**

#### FW.3 — Queen AT Command Blocking
- **P1** · 🟡 · → `03_02 §4`
- ✅ ring buffer + drain-loop (single-packet overwrite / emergency loss під CoAP-flush) + ✅ (FW.56) blind-вікно закрито **архітектурно** (host-рівень): pure `at_engine.h` early-exit токенайзер + `sim7070_coap.h` розмова + hex-чанки + response-driven init, host-тести `test_at_engine.c` — канон [`03_02 §4`](03_02_Queen_Gateway_Firmware).
- ✅ (2026-06-10) **UART DMA RX закрито архітектурно** — останній machine-doable пункт FW.3: байтовий polling (ORE губив запізнілі URC/`+CCOAPNMI`) → circular-DMA кільце `firmware/queen/uart_rx_ring.h` (абсолютні лічильники, double-read знімок, монотонний clamp проти IRQ-латентності, overrun-детект) + host-тести `test_uart_rx_ring.c` (гонки/wrap/overrun/інтеграція з токенайзером) + drain-гігієна (стале до команди/розмови — геть; запізнілий NMI цієї розмови — законний) — канон [`03_02 §4`](03_02_Queen_Gateway_Firmware). **FW.3 тепер чисто bench.** · [ ] 👤 bench: реальні SIM7070G таймінги (RUNBOOK 5.1/5.2) + кремній DMA-вуха (DMAMUX/NDTR/TC, межовий байт повного кільця) — DMA-частина one-command (2026-06-12): `firmware/scripts/bench/06_uart_dma_ears.py` (pyOCD attach + USB-UART-модем, RUNBOOK 5.4)

#### FW.4 — TinyML `Run_Inference()` — ✅ self-owned baseline landed (machine half); bench-confirm residual
- **P0** · 👤+🔗 · → [`03_03 §4`](03_03_TinyML_Acoustic_Inference)
- Compilation unblocked (stub fallback); реальна модель + uncomment лишаються. Блокує acoustic detection (chainsaw/cavitation/wind) + Mongabay pivot.
- **✅ Pre-closure без моделі (2026-06-10):** (1) wire `logmel.c` у ARM-build — виявилось уже закритим FW.46 (`silken_common`: `LOGMEL_USE_CMSIS` + CMSIS-DSP link, real `size`); (2) стек-⚠️ («~7KB/4 буфери») знято: **reuse-buffers** (2 кадрові буфери: RFFT руйнує вхід, power у низ work — `logmel.c`) + **QEMU-M4 нога** `firmware/scripts/qemu_logmel.sh` (golden-parity CMSIS-шляху tol 1e-3 спільним ядром з host-ctest + stack-paint high-water проти tripwire-бюджету; [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA) «друга нога», CI `firmware_arm_build`); (3) попутно знято **FPU-міф**: WLE5 БЕЗ FPU → всі ARM-збірки переведено на soft-float ([`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA) ABI-інваріант), float-DSP latency-чесність — [`03_03 §3.3`](03_03_TinyML_Acoustic_Inference).
- **✅ Self-owned baseline приземлено (2026-06-12) — машинна половина FW.4 закрита:** натреновано НАШУ модель на відкритих даних (ESC-50, per-frame 40 log-mel → 5 класів INT8: wind/chainsaw реальні, fauna-проксі ESC-50, silence/cavitation синтетичні; float 85.6% / INT8 85.4%, parity з TFLite argmax-exact) через `silken_ml.{data,models,train,export}` (config/seed/reproducibility-manifest/registry; `tools/ml/docs/baseline_model_program.md`) → `silken_net_audio_model.h` (self-contained INT8 forward pass, gemmlowp; **972 B Flash / 0 .bss / 76 B стек** — << стелі 7–15 КБ FW.26) → `main.c` call-site **розкоментовано** + `logmel.h` → host-тест `test_audio_model` (12 golden, class-exact+softmax) + увесь firmware-сьют зелений 0-регресій. Runtime-примирення TFLM↔CMSIS-NN ([`03_03 §4.1`](03_03_TinyML_Acoustic_Inference)). ML-партнерів нема → модель НАША end-to-end (ростер аспіраційний; апгрейд опційний).
- Лишається: · [ ] 🔗 ARM `arm-none-eabi-size` реальної arena (host-footprint виміряно; ARM — CI hal_check lane після board-freeze) · [ ] 🟡 bench-формальність: silicon float32-confirm CMSIS-шляху (один прогін на платі) · [ ] 👤 (опц.) польова/партнерська модель замінює header (Бушин CNN + Любченко NSGA-II + Cherkasy soundscape) — апгрейд, НЕ блокер · [ ] 🌿 FW.4-EXT (post-TRL 7): 5-й клас `fauna_activity` dawn/dusk (`03_03 §10`), залежить від UNI.11+UNI.13a; альт. ACI descriptor

#### FW.18b — OTA threshold invalid counter (production-visibility)
- **P2** · 👤 · → [`03_03 §5.4`](03_03_TinyML_Acoustic_Inference)
- **✅ Counter канонізовано ([`03_03 §5.4`](03_03_TinyML_Acoustic_Inference)):** `TinyML_Apply_Thresholds`/`Validate_Threshold` відкидає NaN/out-of-range/інверсію OTA-порогів → default (інваріант `SILENCE<WARNING<CRITICAL` збережено); saturating `tinyml_threshold_invalid_count` (DR1 `WARN_ESC`) + host-тести.
- **✅ (2026-06-10) wiring + метрика:** bit-redistribution байта 11 — бітфілд `[thr_invalid:5|TTL:3]` (One-Home `firmware/common/ttl_byte.h`; legacy-сумісно: counter=0 ⇒ бітово старий TTL; mesh-релей не чіпає лічильник origin'а) + backend маскує `mesh_ttl` і інкрементує `silkennet_tinyml_threshold_invalid_reports_total` — **без `{soldier_did}`** (cardinality budget [`06_03 §2.9`](06_03_Prometheus_Observability); DID — у warn-лозі, патерн FW.22). Freeze-contract goldens `test_soldier_logic.c` ↔ `telemetry_unpacker_service_spec.rb`. · ✅ (2026-06-12) **CCM-дім:** 24B-freeze лічильник мовчки ВИПУСКАВ (mesh_ctrl без thr_invalid — зловив wire-budget ledger) → wire-rev2 повертає його у `diag[7..3]` (28B byte 18, [`03_05 §3.2`](03_05_Hardware_Symmetric_Crypto_and_Security)); CCM-шлях бекенда інкрементує ту саму метрику.
- **✅ (2026-06-10) Grafana IaC:** stat-панель (дашборд, секція Telemetry) + alert rule `sn-alert-tinyml-threshold-invalid` (`rate(...[15m]) > 0`, warning, P1-група) → `deploy/grafana/`.
- **✅ 🤖 one-command import (2026-06-11d):** `deploy/grafana/import.rb` — авто-discovery datasource UID + folder + дашборд із правильним `inputs`-wrapper'ом + ідемпотентний upsert усіх alert rules через Alerting Provisioning API; `--dry-run` валідує артефакти без credentials. Попутно: README-curl для дашборду був неповний (голий export без wrapper'а), а `sed -i` правив трекований YAML — обидва шляхи замінено скриптом. · [ ] 👤 запустити `import.rb` із Grafana Cloud токеном + contact point/notification policy + verify на живих метриках — разом із S2.2/S2.3

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- **P1** · 🟡 · → [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)
- **✅ per-species Z-пороги канонізовано (OTA-design [`05_02 §4а`](05_02_Proof_of_Growth_Pipeline), service [`04_02`](04_02_Business_Logic_and_Services)):** Rails `build_threshold_config_block` + `effective_lorenz_thresholds` 3-tier (cluster → TreeFamily → global 2.0/45.0/29.0) + firmware parser `Soldier_Handle_CMD_SET_THRESHOLDS` (freeze-contract, `FW8_PARSER_ENABLED 0`) + host-тести; CMD `0x9A` (DOC.4).
- **✅ (2026-06-10) persist host-половина:** `firmware/common/lorenz_thresholds.h` — `Save/Load` поверх Flash-KV, ключі `0x10/0x11` за реєстром [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA); ті самі інваріанти, що парсер 0x9A (парність пінується тестом), порвана пара/power-cut/сміття → firmware-дефолти; host-тести у `test_flash_kv.c` (roundtrip · torn-pair · mixed-generation · remount+compact). Попутно знято 05_02-drift «розблокування = звільнений RTC-регістр» → Flash-KV.
- **✅ 🤖 mount + wiring зашито (2026-06-11c, разом із FW.17):** Flash-KV mount + HAL_FLASH глю у `main.c` (спільний гейт `FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED`) + wiring `Save/Load`: boot-restore після mount'а (Load → глобалки; сміття → дефолти) + КЕНОЗИС-write по dirty-флагу прийнятого 0x9A + спільний `FlashKv_Compact` у безпечній фазі. Production-dispatch 0x9A свідомо НЕ будувався (defer-ADR у `main.c`: на TRL-6 всі види на дефолтах — daily re-send був би no-op за ~5% downlink-бюджету). · [ ] 🟡 deferred TRL-7 (bench): фліп `FW8_PARSER_ENABLED 1` + верифікація HAL-глю на кремнії

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- **P2** · 🔗 · → [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)
- Будує на FW.1 (✅ per-device provisioning, закрито — не блокує). Статичний ключ при Factory Flashing → немає rotation без re-flash (GDPR/ISO 27001/NIST SP 800-57).
- **✅ (2026-06-10) дизайн + freeze-contract host-готові ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)):** ratchet = NIST SP 800-108 HMAC-KDF на pure-C SHA256 (AES-self-encrypt ескіз SUPERSEDED), ключ ніколи не летить ефіром; wire `CMD_ROTATE_KEY 0x9E` (`[target_version:u16le]+crc16`, опкод-карта DOC.4) — `firmware/common/key_ratchet.h` ↔ `Cryptography::KeyRatchet` + `OtaPackagerService.build_rotate_key_block`, **golden-KAT byte-parity C↔Ruby**; версійна дисципліна (forward-only, стрибок ≤8); persist = ЛИШЕ версія у Flash-KV `0x13` (журнал не тримає ключів; boot re-derive з K0); ACK = неявний через наявний Dual-Key Grace (decrypt новим ключем → `clear_grace_period!`); чесна модель: backward secrecy ✅, compromise-recovery = re-provision/ECDH-alt (ADR у §3.8), фізичний K0 = RDP2 → SE050-L2. **Інертний**: активація gated на FW.2 CCM (ECB-downlink без MAC не сміє командувати ротацією).
- **✅ 🤖 інтеграція написана обабіч (2026-06-11c), інертна за двома гейтами:** `key_version` колонка `HardwareKey` + ратчет-гілка `HardwareKeyService#rotate!` для Tree (`Cryptography::KeyRatchet.did_to_u32` + `advance_hex`; golden-KAT крізь повний service-шлях) + `KeyRotationDownlinkWorker` (0x9E через найкращу Queen кластера; ENV-гейт `FW17_RATCHET_DOWNLINK_ENABLED`, закрито → `RatchetGateClosedError` ДО зміни БД) + Soldier-гілка 0x9E у `main.c` (parse → `Key_Ratchet_Advance` → re-key CRYP → версія у Flash-KV 0x13 у КЕНОЗИСІ; компайл-гейт `FW17_RATCHET_ENABLED 0`) + **mount Flash-KV + HAL-глю** (спільний гейт із FW.8) + boot `Key_Ratchet_Apply`. **Бонус-знахідки:** (1) legacy `sys/key_update` слав КЛЮЧ ефіром, не мав firmware-споживача і викликав `ActuatorCommandWorker` з чужою арністю — видалено (Gateway-ротація = БД + re-provision, чесно залоговано); (2) **K_ota↔Flash-KV колізія**: FW.23 поклав K_ota на `0x0803D000` = перша сторінка канонізованого KV-регіону → mount стер би ключ; K_ota переїхав на сторінку 125 (`0x0803E800`) — main.c + `CommandBuilder` + golden-спека + канон синхронно.
- **✅ 🤖 Queen-реле написано (2026-06-12), інертне за гейтом:** `soldier_cmd_queue` (FW.20-Q2) — `firmware/queen/soldier_cmd_queue.h` (pure: валідатор спільного каркаса 0x9A/0x9E + черга 16-байтних блоків із shot-бюджетом, дедуп-refresh, round-robin) + глю в `queen/main.c` за `FW20_Q2_CMD_RELAY_ENABLED 0` (маршрутизація у `Handle_CoAP_Command` + **рефлекторний постріл** услід за uplink'ом — Солдат слухає лише ~500 мс після власного TX; маяковий слот зі старого ескізу відкинуто, ADR). Host-тести `test_soldier_cmd_queue.c` (`make cmd_queue`). Канон реле — [`03_02 §5б`](03_02_Queen_Gateway_Firmware).
- [ ] 🔗 активація після CCM-flip: фліп трьох гейтів (Soldier + Queen + backend ENV) + глибина черги під per-device CCM-батч cluster-wide ротації + bench (re-key CRYP, Flash-KV erase/program на кремнії) — e2e сценарій RUNBOOK §2.6
- [ ] 🌿 ECDH-alt — разом із SE050-L2

#### FW.20 + FW.20-S2 — Time Sync (Rails ↔ Queen ↔ Soldier)
- **P2** · 👤 · → [`03_02 §5а`](03_02_Queen_Gateway_Firmware) (канон-хаб — SSOT)
- **✅ 3-рівневий time-sync канонізовано ([`03_02 §5а`](03_02_Queen_Gateway_Firmware) — SSOT, 00_07 = лише вказівник):** CoAP envelope `0x9C` + Queen reflex-beacon + auth-flag + drift-monitor/panic-sync (`0x56`) + per-hop relay + gossip-piggyback (wire + Soldier-константи + regress-bench у §5а). FW.20 1-hop done. Лишається (deferred TRL-7, §5а.6):
  - ✅ (2026-06-12) **🤖 anti-storm журнал поколінь (4/5) + Queen TTL=2 — повний mesh-relay написано**: `common/beacon_dedup.h` (Flash-KV `0x20`, атомарний `[gen:24|window:8]`, ≤1 ретрансляція/покоління/Провідник — TTL тепер задає лише глибину) + relay вшито у RX-гілку за гейтом `FW20_MESH_RELAY_ENABLED 0` + Queen `byte9 0x81→0x82`; деталі/бенч — [`03_02 §5а`](03_02_Queen_Gateway_Firmware). Residual: чистий bench-фліп (Flash-KV HAL, спільний з FW.17/FW.8/FW.2); TTL≥3 (глибший mesh) — founder-рішення про airtime, шторм-безпечне
  - [ ] 👤 lab LSE drift-test ΔT=±60°C (термокамера; `04_lse_drift.py`, RUNBOOK §4.3)
  - ✅ (2026-06-11) **⚠️ «таймери на мертвому tick» розкладено й вирішено БЕЗ FW.49**: (а) Королева — **хибна тривога**: STOP2 у неї нема взагалі (always-on main loop), її `last_beacon_time`/tick живі; (б) Солдат — справжня пастка у трьох місцях: drift-watchdog (12 год ≈ тижні wall), cooldown (1 год), і **живий ARCH.41-C grace** (10 хв tick ≈ 1-2 год wall — телеметрія після cold-boot відкладалась у стільки ж разів) → усе переведено на **лічильники пробуджень** (FW.27-B патерн; wall-квант = цикл 26-32 с): `TIME_SYNC_{DRIFT 1440, COOLDOWN 120, GRACE 20}_WAKEUPS` + wire-поле 0x56 = wakeups×30с номінал (±20%, для Grafana-масштабу досить); SRAM-лічильники гинуть з VBAT (grace перезапускається — правильно); 7 дзеркало-тестів переписано. FW.49 wall-clock лишається для delta_t/epoch_day (там потрібні справжні секунди), НЕ для цих порогів. Cross-ref: ARCH.26, FW.49, FW.30, SEC.10/FW.29

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- **P1** · 🟡 · → [`03_05 §3.4б`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **✅ HMAC-SHA256 OTA auth канонізовано + live-compute зашито ([`03_05 §3.4б`](03_05_Hardware_Symmetric_Crypto_and_Security)):** per-cluster K_ota (HKDF info `silken-ota-hmac-v1`) → `OtaPackagerService` 4× `[0x9B]` trailer (3 печатки + version envelope seg 4; anti-replay/truncation: version_id+total_chunks у тезі) → Queen stateless relay → Soldier dual-gate (magic `RITE` + constant-time HMAC + fail-safe magic-wipe).
- **✅ 🤖 wire HMAC compute зашито (2026-06-11):** `OTA_Try_Finalize` обчислює `Silken_Hmac_Sha256_Concat(K_ota, body ‖ version_be ‖ total_be)` → `OTA_Verify_Dual_Gate` — tampered bytecode з валідним CRC32 тепер відсікається. Додано `Load_Ota_Hmac_Key` (K_ota з Protected Flash `0x0803E800` — сторінка 125; первісний `0x0803D000` колідував із Flash-KV регіоном, переїзд 2026-06-11 при FW.17-інтеграції; magic "KOTA"; fail-safe `valid=0`) + `version_id` на дроті (4-й `[0x9B]` чанк). Bonus: фіналізація з обох RX-гілок (тіло 0x99 / печатка 0x9B) — печатка приходить ПІСЛЯ тіла, раніше гинула. RSpec+host (real HMAC ≡ OpenSSL, APPLY/WAIT/REJECT) ✅.
- **✅ 🤖 factory-тракт K_ota зашито (2026-06-11b):** Гілка A (`CommandBuilder`) тепер емітує KOTA-блок `0x0803E800` (magic + 8 слів; golden-спека дзеркалить `Load_Ota_Hmac_Key`; `Session` тягне `OtaHmacKeyService.fetch_for(cluster_id)`; Tree без K_ota — відмова на validate). **Знахідка-розкол:** до цього K_ota емітувала ЛИШЕ superseded ATECC-гілка B (Slot 3) — Гілка A випускала б дерева з вічно fail-closed OTA, а канон §3.4б декларував запис як факт (claim-vs-code drift). SE-резидентний K_ota = рішення SE050-MIGRATION; поки HMAC рахує MCU — ключ у MCU Flash.
- Лишається:
  - [ ] 🟡 bench: фізичний `factory:execute` (SWD, KOTA вже у транскрипті) + e2e dual-gate на STM32 (APPLY/REJECT) — RUNBOOK §2.5.

#### FW.25 — TinyML DSP-path: Path B (log-mel) SELECTED [DECISION 2026-05-22]
- **P0** · 👤+🤖 · → [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)
- **✅ Path B (log-mel) обрано + DSP-фронтенд реалізовано self-owned** (decision matrix [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) · контракт [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference) — ML-партнера нема, контракт наш end-to-end): `Compute_LogMel` (`firmware/common/logmel.c`) + 3-way parity librosa≡stdlib≡C (`contract_hash` tripwire, `tools/ml`) + golden-vector host-тести + auto-gen таблиці (`silken_ml.codegen`). · ✅ (2026-06-11) **контракт доукомплектовано бюджет-конвертом моделі** ([`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)): arena target ≤ 10 КБ / тверда стеля 7–15 КБ (FW.26-леджер §6), INT8 обов'язковий, «топологію під стелю» — щоб партнер не натренував фізично недеплойовану модель; Path C-фолбек отримав леджер-противагу (TFLM-оверхед усередині тієї ж стелі → фолбек звузився, перед застосуванням повторити FW.26-замір). ✅ baseline приземлено (FW.4, 2026-06-12, self-owned ESC-50) → DSP-фронтенд живить реальний інференс. Лишається (опційний апгрейд):
  - [ ] 👤 ML-партнер (Бушин/Любченко) тренує 5-class CNN на §3.4 **(контракт ознак + бюджет-конверт)** (крос-чек, не гейт)
  - ✅ (2026-06-12) фактичний arena виміряно (forward-pass **972 B Flash / 0 .bss / 76 B стек** — << стелі 7–15 КБ) + inference розкоментовано (FW.4 baseline приземлено; host-тест `test_audio_model`)
  - [ ] 🌿 UNI.11+UNI.13a soundscape dataset (dawn/dusk fauna 5-й клас)
  - [ ] 🤖 fallback Path C (TFLM) — лише після повторного FW.26-заміру з TFLM-обвісом ([`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) противага)

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- **P1** · 🤖 · → [`03_03 §4.3`](03_03_TinyML_Acoustic_Inference)
- **✅ CI size-gate канонізовано ([`03_03 §4.3`](03_03_TinyML_Acoustic_Inference) + build [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)):** `make size-check` (host-проксі) + FW.46 real `arm-none-eabi-size` owned-code. · ✅ (2026-06-11) **РЕАЛЬНИЙ ARM static-RAM гейт + виміряний леджер** (канон [`03_03 §6`](03_03_TinyML_Acoustic_Inference)): compile-lane FW.46 дає `.data+.bss` обох main.c — **Soldier-TU 5 690 Б, Queen-TU 18 358 Б** — CI-крок `[FW.26] ARM static-RAM gate` (`check_ram_budget.sh --hal-objects`, per-TU бюджети 8 192/20 480; arena ляже у `.bss` і зірве гейт → свідома ревізія). Леджер: 65 536 − mruby **38 392** (FW.55-вимір, був «~4КБ»-міф) − stack 12 288 − статика ~8 000 ⇒ **СТЕЛЯ tensor arena = 7–15 КБ** — стара умова «>46KB → overflow» базувалась на міфі; Path B «~16КБ» НЕ влазить → **бриф ML-партнерам: arena target ≤ 10 КБ (INT8+prune+мала топологія)** та/або mruby `_sbrk`-кап (live ~27КБ). · ✅ (2026-06-12) **FW.4 baseline приземлено** — arena forward-pass **972 B Flash / 0 .bss / 76 B стек** << стелі 7–15 КБ (host-вимір `silken_ml.export`, INT8 per-channel); prune/кап НЕ знадобились · [ ] 🔗 ARM `arm-none-eabi-size` на повному `.elf` `.bss+.data` після HAL-link (ELF-режим гейта готовий: per-target 14 800/40 960)

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- **P2** · 🔗 · → [`03_02 §5.X`](03_02_Queen_Gateway_Firmware)
- **✅ Design B канонізовано ([`03_02 §5.X.3`](03_02_Queen_Gateway_Firmware)):** Magic Re-Request — Soldier bitmap uplink `[0x55]` (`OTA_REQ_MARKER`, DOC.4) → Queen targeted re-broadcast лише missing chunks (60-90% economy vs wave) + djb2-dedup + host-тести; beacon anti-storm журнал — ✅ реалізовано 2026-06-12 (FW.20-S2, Flash-KV `0x20` — [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)). · ✅ (2026-06-11) **«5 хв тиші» STOP2-імунно БЕЗ FW.49**: tick-різниця (мертва у STOP2, зойк запізнювався у ~6-15×) → `OTA_REREQUEST_SILENT_WAKEUPS=10` тихих пробуджень **з відкритим вухом** (≈5 хв wall при циклі 26-32 с; семантика чесніша за wall-clock — тиша лічиться лише коли справді слухали; скидання чанком і зойком; сатурація проти wrap; 6 host-тестів) — wall-clock `OTA_SILENCE_WALL` лишається опцією уточнення post-FW.49, потреби нема · [ ] 🔗 Design A (ACK-aggregation — collective recovery) залежить від ARCH.26 TDMA RX-вікна; B незалежний ✅

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- **P2** · 👤 · → [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)
- **✅ Numeric band code-staged ([`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)):** `check_z_divergence!` + `DEFAULT_DCI_EPSILON=0.001` за двома ENV-флагами (`GAIA_DCI_NUMERIC_TOLERANCE`/`_EPSILON`, default off) — `|server_z−device_z|<ε` ДОПОВНЮЄ (не заміняє) категоричний check → ловить replay з валідним StatusByte, але хибною Z-magnitude (RSpec покрито). Подвійно-gated: флаг off + `device_z` ще не у wire (21B пакет; зайде post-FW.2). · ✅ (2026-06-11) **Gate L machine-closed без заліза** (канон [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)): `|Δz|`-distribution N=10 000 зчеплених кейсів через СПРАВЖНІЙ mruby-VM ↔ справжній контракт у CRuby (`tools/firmware/dci_epsilon_sweep.sh`, генератор дзеркалить `parity_core.h`, кожна сторона ланцюжить власний хвіст) — **бітова рівність 10000/10000, payload 0 розбіжностей, max|Δz| = 0**; ARM-плече бітово-нульове за FW.55 QEMU byte-parity. Історичні «drift `<1e-12`» / «~1e-14» superseded (не відтворюються за pinned-конфігурації — явний `MRB_NO_BOXING`, FW.55-④). ε=0.001 = чиста страховка. Лишається:
  - [ ] 👤 silicon-хвіст Gate L: той самий one-command FW.55 дамп (SWD) — закриває FW.7/FW.19/FW.31 разом
  - [ ] 👤 flip-гейти D/C/P/G ([`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)): staging canary → production. ✅ (2026-06-12) Gate D wire-дім ГОТОВИЙ: `device_z` u16×512 у CCM wire-rev2 bytes 16..17 (квант-похибка 0.00098 < ε; сентинель 0xFFFF = Лоренц спав; e2e спеки `process_ccm_chunk`→numeric branch) — лишилось виміряти ≥95% покриття після CCM-фліпу

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- **P1** · 🔗 · → [`03_03 §10.3`](03_03_TinyML_Acoustic_Inference)
- **✅ Guard канонізовано ([`03_03 §10.3`](03_03_TinyML_Acoustic_Inference)):** `Fauna_Should_Sample(vcap_mv)` (≥`FAUNA_VCAP_MIN_MV` інакше skip + counter `fauna_skipped_low_vcap`) + host-тести (freeze-contract); fauna-сесія ~78.3 мДж → при V_cap≈3.5V concurrent TX = brownout. ⚠️ поріг `FAUNA_VCAP_MIN_MV=4500` мВ на сирому ADC не спрацює до конверсії FW.50 — з 2026-06-11 це **виконуване знання**: контракт «мВ, не сирий відлік» прописано на guard'і + tripwire-тест `test_fw42_raw_adc_range_always_skips_fail_closed` (raw full-scale 4095 < 4500 ⇒ fail-CLOSED: brownout неможливий, але fauna мовчить і на повному EDLC; розгейт = FW.50 конверсія у call-site, не зниження порогу). · [ ] 🔗 активація fauna-pathway після FW.4 uncomment (гейт + [`ARCH.40`-сесія](00_07_Action_Plan_Tracker) готові) · ✅ (2026-06-12) **wire-дім + метрика:** wire-rev2 виділив fauna-маркерам 2 біти `diag[2..1]` (mode+skip, 28B byte 18 — [`03_05 §3.2`](03_05_Hardware_Symmetric_Crypto_and_Security) ledger) + бекенд-лічильник `silkennet_fauna_skip_reports_total` (cardinality-патерн FW.18b, реєстр [`06_03 §2.8`](06_03_Prometheus_Observability)); інкременти живі після CCM-фліпу + FW.4 fauna-pivot (біти ставить firmware call-site при pivot'і) · [ ] 🔗 Grafana-панель — після перших живих інкрементів (мертва панель без джерела — передчасний dashboard)

#### ARCH.40 — Fauna 5-сек вікно: монолітне awake-обчислення (SRAM2 wipe)
- **P1** · 🔗 · → [`03_03 §10.2`](03_03_TinyML_Acoustic_Inference)
- **✅ Constraint канонізовано ([`03_03 §10.2`](03_03_TinyML_Acoustic_Inference)):** fauna-сесія монолітна за 1 awake (STOP2 wipe'не SRAM2 → `float[156][N_mel]` не переживе сну; 20 RTC DR зайняті) — Welford-accumulator у RAM, STOP2 лише після згортки в байт. · ✅ (2026-06-11) **freeze-contract + named-тест ДО pivot'а**: model-незалежна половина зафіксована кодом — `firmware/common/fauna_session.h` (Welford mean+M2 по 40 mel + монолітний `Fauna_Run_Session`, синхронний/завершений в одному виклику; чесний abort на збої кадру; `FaunaWelford` ~324 Б із sizeof-tripwire) + `test_fauna_sampling_no_stop2_in_session` ✅ зелений (host, `make -C firmware/test fauna`: емуляція девайс-циклу — жоден із 156 кадрів не бачить сну перед собою) + Welford ↔ two-pass еталон + стабільність на зсунутих даних. Згортка mean/var→байт (0–63) свідомо відкладена (калібрування після моделі — не передчасний канон) · [ ] 🔗 при FW.4 fauna-pivot — вживлення call-site у main.c (TIM2+DMA провайдер кадрів + `Fauna_Should_Sample` гейт + згортка в байт) — ДО Фази 5 кенозису

#### ARCH.41 — Cold-start Time Paradox (DCI)
- **P2** · 🔗 · → [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor)
- **✅ Mitigation A канонізовано ([`03_04 §2.1`](03_04_mruby_Lorenz_Attractor) + [`04_02`](04_02_Business_Logic_and_Services)):** VBAT loss → RTC epoch_day (10 957, default 2000-01-01) ≠ server (~20 585) → DCI false-positive до `CMD_TIME_SYNC`. Server-side `try_time_sync_recovery` (3 epoch_day кандидати → `time_unsynced_fallback`, не падає DCI, `TimeSyncDownlinkWorker`). Firmware-деривація — повний HMAC-parity (FW.30 exact civil-days, `lorenz_seed.h`); UTC tick-offset відстає на STOP2 → RTC-календар timebase (FW.49).
- ✅ (2026-06-11) **Mitigation B+C реалізовано обома сторонами** (канон [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor) п.2-3): **B** — sentinel `acoustic_events=0xFE` поки `soldier_unix_ts==0` (`Soldier_Acoustic_Wire_Value`: реальні 0xFE→0xFD, 0xFF=FW.22-сатурація лишається; правило обох сторін «sentinel ⇒ Лоренц з acoustic=0» — бекенд `apply_time_uncertain_sentinel!` нейтралізує ДО DCI, ставить `time_unsynced_fallback`+`TimeSyncDownlinkWorker`, alert/stress бачать 0, DCI не обходиться); **C** — grace-вікно 10 хв: Лоренц відкладено (RTC-ланцюг не отруюється stale epoch_day; після синку деривація з правильної доби), замість телеметрії hello = SYNC_REQ 0x56 (DID+Vcap байти 11..12+'S', opcode-карта [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA)); Королева на 0x56 перемотує маяк (негайний re-broadcast, ідемпотентно), OTA Reflex живий (стріляє до розбору маркера), вікно слухання 4.5 спільне. Host-тести (sentinel + hello-layout) + 3 unpacker-спеки; повна сюїта зелена. Координація rollout = pre-fleet тривіальна (один репо). · [ ] 👤 bench: e2e cold-boot день (VBAT-pull → hello → маяк → синк → перший чистий пакет) — RUNBOOK §4.5 (сусідить з FW.49 LSE/RTC §4.1)

#### FW.46 — Enterprise-grade ARM firmware build (committed, reproducible, CI cross-compile)
- **P1** · 🤖+👤 · → `03_01 §12.4`
- ✅ **Owned-code foundation** (2026-06-04, CI-gated `firmware_arm_build` зелений): відтворюваний CMake-крос-компайл того, чим **володіємо** — `cmake/arm-none-eabi.cmake` (Cortex-M4 **soft-float** — WLE5 без FPU, ABI-інваріант [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA), FPU-міф знято 2026-06-10, pinned Arm GNU + submodules `firmware/extern/`) · `logmel.c` під ARM (real `arm-none-eabi-size` ~6.3KB) · **mrbc** `bio_contract.rb`→`lorenz_bytecode.h` + drift-gate + minimal-VM harness · host↔target RFFT packing-parity · mruby minimal-gembox (double/NO_BOXING, ~117KB Flash / 0 RAM). Канон [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA). 🔴 повний HAL-лінкований `.elf` ще НЕ зібрано (board-freeze поза репо) ↓. · ✅ (2026-06-11) **HAL compile-lane**: WL-HAL завендорено pinned (`stm32wlxx-hal-driver` v1.6.0 + `cmsis-device-wl` v1.4.0, консистентна пара за CubeWL) + `firmware/hal_glue/` (owned `main.h`/`hal_conf`/`radio.h`-дзеркало + wrapper-TU з порожніми MX-заглушками — main.c незаймані) → CI крок `[FW.46] HAL compile-lane` компілює **обидва** main.c проти справжнього HAL (вперше за історію; Queen 0 warnings). **Зловлено одразу:** `__HAL_RCC_CRYP_*`→`__HAL_RCC_AES_*` (F4-стиль не існує на WL — Soldier STOP2-цикл і Queen `Restore_ECB_Mode` впали б на лінку) + 2 sign-compare. **Спостереження для HAL-фази:** (а) `Radio.Init(NULL)` + надія на `OnRxDone` = латентний баг (Semtech кличе колбеки через events-таблицю → з NULL Queen RX мертвий; реєструвати `RadioEvents_t` при інтеграції middleware); (б) ARM `-Wunused` показує ~7 wired-not-called static-функцій у Soldier (time-sync/Fauna/CMD_SET_THRESHOLDS сім'ї — call-sites чекають фаз). · [ ] 👤 board-freeze → `.ioc` (CubeMX): тіла `MX_*`/`SystemClock_Config` (пін-мапа/клок/ADC-канали/LSE — FW.49/FW.50) + SubGHz_Phy middleware (з реєстрацією RadioEvents_t!) + startup/ld → повний Soldier/Queen `.elf` + bench flash-verify · [ ] 🤖 flip FW.26 на повний `.elf` після HAL · [ ] 🤖 (optional, far-future) toolchain pin via ARM-tarball (`00_08`). Cross-ref: FW.4/FW.26/FW.19/FW.47/SEC.3/FW.55.

#### FW.49 — Tick-time ≠ wall-time у STOP2: системна семантика таймерів Soldier
- **P0** · 👤🤖 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- ✅ **Wake-source ADR вирішено** (канон [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)): `HAL_GetTick` заморожений у STOP2 → tick-`delta_t` міряв лише active-час → over-mint (фальсифікація Proof-of-Growth); лік — RTC WUT + Vcap-енергогейт (FW.50) + RTC-календар timebase. S1-foundation (`wall_time.h`) + S3-docs ✅. Лишається:
  - ✅ (2026-06-12) **S1-wiring SHIPPED (host-частина):** `Wall_Seconds_Now()` (RTC-календар → unix через FW.30 `Silken_Unix_From_Calendar`; free-running від 2000-01-01 ще до синку — дельтам досить) + `Wall_Calendar_Set` (beacon-UTC → календар: нова інверсія `Silken_Civil_From_Unix` у `wall_time.h`, roundtrip host-пара з прямою FW.30-функцією на всьому RTC-вікні 2000-2099) + **delta_t мігровано** (guard-и cold-start/назад/стрибок-епохи → baseline; RTC-маркер останнього циклу тепер wall-секунди — канон-таблиця `03_01 §2`) + **cold-start epoch_day wall-first** (`Silken_Wall_Is_Utc`-предикат; tick-екстраполяція — фолбек) + **wire `dT:2` сатурація @0xFFFF** (wall-дельти бувають добами — wrap брехав би бекенду: 200000с→3392с). «3 часові опори» (boot/beacon/request) застаріли — пороги FW.20-S2/FW.27-B ще 2026-06-11 переведені на лічильники пробуджень (wall їм не потрібен). Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA) + §2 (рядок wall-маркера). ⚠️ **bench-gated residual:** LSE/RTC clock-tree (`MX_RTC_Init`) у repo відсутній — `Wall_Seconds_Now` на кремнії поверне 0 (чесна відмова → baseline) до bring-up.
  - [ ] 🔗 **S2:** RTC-WUT-tick + Vcap-енергогейт → delta_t = справжній час перезаряду (чекає шкали ↓).
  - [ ] 👤 **bench bring-up:** LSE 32.768 кГц + `MX_RTC_Init` (календар + WUT-IRQ STOP2-wake) + верифікувати `Wall_Seconds_Now`/recharge-інтервал (RUNBOOK §3-4: `04_lse_drift.py`, `03_power_profile.py`).
  - **🔴 Відкрите (фізика — Мінаєв/bench):** шкала delta_t — L4 очікує **36-190 с**, а [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет дає **1.77 год** (P_gen=15µW); якщо реально ~1.77 год — метаболічний сигнал плоский (post-E.63: `metabolic_health(delta_t)`→growth_points майже константа; живе лише при L4-потужності EBFC). Калібрування — блокер E.63. Cross-ref: E.63, FW.50, FW.20, FW.27-B, FW.30.

#### FW.50 — Vcap ADC: raw counts використовуються як мВ (без конверсії)
- **P0** · 👤🤖 · → [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA)
- **✅ Знахідка + helper канонізовано ([`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA)):** `vcap_voltage` — сирий 12-bit ADC-відлік (канал VREFINT = VDDA за buck'ом, не Vcap EDLC) трактувався скрізь як мВ (пороги/EMA/`vcap_mv`) → RX-вікно/Vcap-енергогейт з фейкових величин. Pure-helper `Adc_Raw_To_Mv()` (factory VREFINT-cal + дільник-параметр) + host-тести (`adc_convert.h`, One-Home) ✅.
- ✅ (2026-06-12, рішення founder) **VDDA-проксі ввімкнено у call-site — глухота вилікувана:** сирий відлік ~1500 < `VCAP_LISTEN_THRESHOLD=2800` тримав вухо RX-вікна зачиненим НАЗАВЖДИ (OTA/mesh/time-sync/ротація ключа мертві на кремнії; host-тести цього не бачили — вони вже жили в мВ-семантиці). Тепер `vcap_voltage = Adc_Vdda_Mv(VREFINT, factory-cal)` = чесні мВ VDDA (≈3300 поки buck живий): вухо відкрите, fauna-гейт (4500) чесно зачинений до реального Vcap-каналу, wire/EMA/mruby — справжні одиниці. Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA); попутно знято VSTOR↔VBAT_SEC дрейф у [`02_03`](02_03_BQ25570_MPPT_Nano_Power). Лишається:
  - [ ] 👤 схемна вилка: розводка Vcap на окремий ADC-пін (цільовий тракт BQ25570 **VBAT_SEC** — [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM); дільник-номінали — [`02_03`](02_03_BQ25570_MPPT_Nano_Power): десятки МОм bleed vs TPS22860-гейт).
  - [ ] 👤 bench-калібрування (DMM-точки vs `Adc_Raw_To_Mv` — RUNBOOK §3.4).

#### FW.52 — OTA throughput by-design: 1 RX-пакет/пробудження + give-up без печатки
- **P2** · 👤🤖 · → [`03_02 §5.X.6`](03_02_Queen_Gateway_Firmware)
- **✅ Знахідка канонізована ([`03_02 §5.X.6`](03_02_Queen_Gateway_Firmware)):** повільний OTA (порядок днів-тижнів) by-design — (а) Soldier RX = 1 пакет/wake (1024 B → ~94 пробудження); (б) Queen гасить `ota_is_active` коли тіло відлунало без зібраної печатки → re-request мертвий до повторного Rails-push; (в) re-request на замороженому STOP2-tick → FW.49. **(г) DONE** — `Write_OTA_Contract_To_Flash` тіло (`flash_ota.{h,c}`, power-cut-safe magic-last, 8/8 host-тести, reuse `FlashKvOps`) → канон [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA). Лишається:
  - ✅ (2026-06-12) **обидва рішення прийнято (founder):** (а) **повільний OTA прийнято як свідомий energy-first ADR** — delta_t = економіка дерева (E.63), `break`-після-пакета = анти-vampire, OTA рідкісний, security-важіль 0x9E поза OTA; vcap-гейтований re-arm = опція перегляду лише після bench E_cycle/recharge (FW.50). (б) **мертве вікно при запізнілій печатці виявилось reliability-багом і ВИПРАВЛЕНО** — запізнілий `0x9B`-трейлер раніше лягав у пам'ять мовчки (тіло в RAM, печатка зібрана, re-request кричить у мертве вікно → весь OTA змарновано до повторного Rails-push); тепер довершення трейлера воскрешає вікно одразу у фазу печатки (pure `Ota_Late_Trailer_Resurrects`, `firmware/queen/ota_window.h` + host-тести `test_queen_logic.c`; анти-проповідь [PLAN 2.5] збережена). Канон: [`03_02 §5.X.6`](03_02_Queen_Gateway_Firmware).
  - [ ] 👤 bench: HAL_FLASH erase/program-фаза (`g_ota_flash_ops`, `main.c`) на STM32 + e2e OTA-day (включно з late-trailer сценарієм воскресіння) — RUNBOOK §2.5.

#### FW.54 — STOP2 RTC-only 300nA: SRAM2-off → RAM-стан (Flash-KV vs RTC-реклемація)
- **P2** · 🤖+👤 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- **✅ Done (канон [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA) / §2.3.1 / §2.3.2):** 300nA-режим вимикає SRAM2 retention → RAM-only стан гине (EMA/mesh-кеш виживають у RTC; delta_t wall-маркер реюзає DR1). Flash-KV host-first (`flash_kv.{h,c}`, power-cut тести) + RAM-state інвентар (§2.3.1) + RTC-headroom 3-осьова реклемація (§2.3.2: live-набір вміщується в RTC, Flash для нього не потрібен). Лишається:
  - [ ] 👤 рішення: RTC-реклемація (§2.3.2) vs Flash-KV persist vs SRAM2-retain — **свідомо відкладено до bench (founder 2026-06-12):** приймати з виміряним 300nA floor (PPK2/JS220, RUNBOOK 3.1), не з моделлю; Вісь-1 пакування DR0 — дешеве й mode-independent, але churn DR-розкладки без підтвердженої економії передчасний.
  - [ ] 👤 bench: HAL_FLASH glue + ECCD-політика + вимір 300nA + persist-roundtrip.
  - ✅ (2026-06-12) **DID-інверсія ВИРІШЕНА (founder: DID = f(UID) детермінований)** — `did_derive.h` (murmur3-fmix32 по 96-біт UID, recompute на boot, нуль неможливий — 0 ефіру = Queen Sentinel) + Ruby-дзеркало `SilkenNet::DidDerivation` (фабрика деривує DID з UID по SWD до прошивки → однопрохідний провіженінг) + golden freeze-contract обабіч (`test_soldier_logic.c` g1-g4 ↔ `did_derivation_spec.rb`). **регістр DID повернуто в пул** (перша реклемація з часів FW.2-freeze; істина розкладки — канон-таблиця `03_01 §2`); FW.24 HRNG-fallback знято — колізії/дефектні UID ловить фабрична DB-unique-перевірка до поля. Канон: [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA) (механізм) + §2 (DR-map) + §2.3.2 Вісь 2 (рішення). Було: write-once UID⊕random у DR7 → не VBAT-durable (розряд EDLC сиротив гаманець) + не відтворюваний (device-first 2 проходи). · [ ] 🔗 SEC.3: завести `DidDerivation.wire_did` у фабричний транскрипт (UID по SWD → Tree+K_seed до прошивки). Зчеплення: SEC.11/FW.30, SEC.3, HW.14.

#### FW.55 — QEMU-M4 bit-parity lane: ARM↔x86 mruby double residual → CI
- **P1** · 🤖 · → [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)
- ✅ (2026-06-07) committed-байткод на реальному Cortex-M4 код-шляху (`qemu-system-arm -M mps2-an386`, minimal-gembox `libmruby.a`, software-double `__aeabi_d*` — як на STM32WLE5JC): **зчеплені** кейси (вихід N → вхід N+1 — хаос ампліфікує ULP-дрейф) + краєві піни; гейт = **byte-exact** diff проти host-голдена. `firmware/sim/*` + `firmware/scripts/qemu_parity.sh` (єдиний вхід local+CI) + крок у `firmware_arm_build`. Закриває FW.7/FW.19 «ARM↔x86 Float drift» до тонкого silicon-confirm. Межі: ISA ≠ кремній (периферія/споживання/таймінги — клас C, bench-runbook). · ✅ (2026-06-10) розширення-нога #2: log-mel CMSIS golden-parity + stack-paint high-water (`qemu_logmel.sh`, [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)) — зроблено ДО моделі, FW.4 pre-closure; обидві ноги тепер soft-float (ABI-інваріант §12.4, FPU-міф знято) · ✅ (2026-06-11) **silicon-confirm заскриптовано** (клас C-преп): кремнієва нога `firmware/sim/wle5_bench/*` — той самий `parity_core.h`/`libmruby.a` на реальній WLE5-карті (FLASH/SRAM, LPUART1→ST-LINK VCP, голий RM0461 без HAL, нескінченні раунди) + `bench/05_parity_dump.py` (дамп ↔ host-голден, вердикт byte-exact) + **фіт-гейт 64КБ у CI**: QEMU-нога міряє heap/stack high-water mruby-прогону, `qemu_parity.sh` гейтить проти бюджету wle5-карти — «не влазить у Солдата» ловиться до кремнію ([`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)) · ✅ (2026-06-11, той самий день) **фіт-гейт зловив 4 девайс-знахідки** (гейт червоний 102400 Б → зелений 38392/52392 Б, кожен крок підтверджено CI): ① runner без arena save/restore (Солдат робить — дзеркало відновлено); ② дефолтні mruby heap-сторінки 1024 об'єкти → `MRB_CONSTRAINED_BASELINE_PROFILE` (інакше `mrb_open()` не злітає на 64КБ; пішло і в бойову збірку); ③ ноги лінкували повний newlib-dlmalloc (+24КБ роздуву) → **newlib-nano** (CubeMX-дефолт Солдата); ④ **НАЙВАЖЧЕ: mruby 4.0 дефолт = `MRB_WORD_BOXING`** — канон FW.19 «Default NO_BOXING ✓» був хибний, на 32-bit кожен Lorenz-double йшов у heap RFloat'ом (~20.5КБ транзієнту/виклик; на 64-bit host — невидимо) → явний пін `MRB_NO_BOXING`, фіт-гейт тепер = CI-enforcement FW.19. Бонус-фікс Солдата: per-wakeup `mrb_full_gc` (VM вічна → сміття копичилось до GC-порогу ≈ стелі RAM, доля висіла на reactive OOM→GC→retry). Виміряний профіль ARM32 (nano, із зонд-оверхедом ~+8Б/алокацію): boot 28.3КБ + irep 3.5КБ + кейс-транзієнт ~0.3КБ → плато sbrk 38392 Б. ⚠️ Похідне: RAM-план Солдата не сходився з виміряними ~38КБ кучі — **ревізовано 2026-06-11: леджер виведено у FW.26/[`03_03 §6`](03_03_TinyML_Acoustic_Inference)** (стеля arena 7-15КБ + ARM static-гейт) · [ ] 👤 silicon-confirm: один прогін на платі — `bench/05_parity_dump.py --plan` (flash `parity_wle5.elf` → дамп по VCP → вердикт скрипта)

#### FW.56 — Queen CoAP AT-граматика ≠ SIMCom: модем = UDP-труба, PDU будує хост
- **P1** · 🤖+👤 · → [`03_02 §4`](03_02_Queen_Gateway_Firmware)
- ✅ **CoAP-grammar fix (sim-first, канон [`03_02 §4`](03_02_Queen_Gateway_Firmware)):** SIMCom CoAP App Note ≠ firmware-припущена граматика (реально модем = UDP-труба: хост будує сирий RFC 7252 PDU, `CCOAPNEW="<ip>",<port>` + `CCOAPSEND=<cid>,<len>,"<hex>"` + URC `+CCOAPNMI`, домени через `CDNSGIP`) → `coap_pdu.h` (CON-PUT builder/parser + golden-vector з ноти) + `sim7070_coap.h` (повна розмова); FW.51 cache-clear ключується на доставку (`+CCOAPNMI` 2.xx).
- ✅ (2026-06-10) **e2e Queen-PDU ↔ backend CoAP-intake (софтом):** golden freeze-contract C-білдер ↔ Rails-парсер (включно з пін-кейсом MID=0x00FF + 0xFF у payload) + pure `CoapServerPdu` (вердикт Брами; демон = UDP-клей) + повний ланцюг PDU → `UnpackTelemetryWorker` → decrypt → unpack (`spec/integration/coap_telemetry_intake_e2e_spec.rb`). Зловив/закрив 2 продакшн-баги Брами: глобальний пошук payload-маркера (кожен 256-й `coap_mid` = фантомна доставка: ACK 2.04 без батча → FW.51 чистив кеш дарма) + Sentinel `route_queen_health` гинув на Sidekiq strict_args під broad-rescue (стаб у старій спеці це маскував). ACK-семантика тепер чесна до FW.51: 2.04 лише після enqueue, 4.04/RST → Королева тримає кеш. Канон [`03_02 §4`](03_02_Queen_Gateway_Firmware). Лишається:
  - [ ] 👤 bench: verbatim-звірка SIM7070-ноти V1.03 + реальні URC/таймінги
  - [ ] 🔗 staging-smoke (`coap_smoke.yml`): той самий шлях через реальний UDP/Ingress до задеплоєної Брами (post-deploy gate). ✅ (2026-06-12) зонди підняті з generic liveness (libcoap POST, «будь-що крім 5.xx») до **freeze-contract**: `bin/coap_smoke` (+ pure `lib/coap_smoke.rb`) звіряє відповіді байт-у-байт з golden-векторами e2e — RST на сміття, 4.04 з піном 0xFF-MID (регресія фантомної доставки: legacy-сервер тут відповідав 2.04), чесний 2.04-після-enqueue (`SNET-Q-SMOKETEST` не-hex → worker гасить як `unknown_device` без сліду в БД); loopback-довід `spec/lib/coap_smoke_spec.rb`. Лишилось 🔗: прогін проти задеплоєної Брами

## §03/§05 · Безпека (Edge crypto + Web3)

#### SEC.1 — Multisig Gnosis Safe для production admin role
- **P0** · 👤 · → [`05_03` — Admin-Role → Gnosis Safe](05_03_Tokenomics_SCC_and_SFC)
- ✅ `Deploy.s.sol` admin=Safe на genesis + `REQUIRE_SAFE_ADMIN` guard (revert якщо EOA) + last-admin guard + runbook (нічого не задеплоєно → reassign не треба). · [ ] 👤 створити Gnosis Safe (3/5|2/3) на Polygon + деплой з `ADMIN_ADDRESS=<Safe>` `REQUIRE_SAFE_ADMIN=true`

#### SEC.2 — RDP Level 2 activation timeline
- **P1** · 👤 · → [`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **✅ Процедура RDP L2 канонізована ([`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security)):** pre-flight + CubeProgrammer CLI + rollout R&D→Pilot→Mass; скриптовано `firmware/scripts/bench/01_option_bytes.sh --rdp 2` (bench RUNBOOK). RDP L2 = **необоротний** SWD-lock → OTA мусить бути верифікований ДО активації (§3.6 ⚠️). Лишається:
  - [ ] 🔗 верифікувати OTA flow end-to-end на bench ДО L2-lock
  - [ ] 👤 field batch → RDP **L1** (зворотний); L2 — лише фінальний mass-deploy

#### SEC.3 — Factory Flashing pipeline
- **P0** · 👤 · → [`03_05 §3.4`](03_05_Hardware_Symmetric_Crypto_and_Security) (+ §3.4г threat model)
- **✅ Гілка A+B Rake-tool канонізовано ([`03_05 §3.4г`](03_05_Hardware_Symmetric_Crypto_and_Security)):** `provisioning_sessions` AASM + 2-Person Rule + `factory_flashing/*` + rake `factory:flash|approve|execute` (dry-run); execute-шлях інтеграційно доведено шимом (fake `STM32_Programmer_CLI` → реальні subprocess'и: capture stdout/stderr/exit, stop-on-fail, AASM failed+transcript; RSpec). Bench-residual = фізичний SWD-флеш. Лишається:
  - [ ] 👤 real `STM32_Programmer_CLI` на STM32WLE5JC bench (post-FW.2) — runbook `firmware/scripts/bench/`
  - [ ] 👤 Bitwarden Secrets API live (`BitwardenAdapter` зараз `NotImplementedError`)
  - [ ] 🔗 real SE I²C (Гілка B) — SE050 eval-kit; `cryptoauthlib`→SE05x код-міграція → SE050-MIGRATION (legacy ATECC-патерн reusable, [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security))

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **P2** · 👤 · → [`03_05 §3.5`](03_05_Hardware_Symmetric_Crypto_and_Security)
- Zero-consumption transport: магніт→circuit open, інсталятор знімає→first power-up (~$0.05/unit). Дизайн канонізовано, у BOM ще немає (окремий механізм від piezo Zero-Power Wake). · [ ] 👤 додати Hamlin 59140-1-T-00-A + N52 магніт до BOM + оновити KiCad schematic

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **P0** · 👤 · → [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security)
- ✅ guard `Security::WeakKeyDetector` + boot-guard refuse-to-boot на FIPS-197/NIST/degenerate vectors (RSpec-покрито). ⚠️ ОКРЕМЕ від FW.1: якщо master seed базується на цьому ключі — весь derivation tree скомпрометований. · [ ] 👤 замінити seed key на crypto-random → задокументувати генерацію у vault (без коміту) → re-flash прототипи

#### SEC.12 — HRNG-IV fallback hardening (CoAP CBC IV)
- **P2** · 🔗 · → [`03_05` — HRNG Fallback](03_05_Hardware_Symmetric_Crypto_and_Security)
- ✅ (2026-05-29) fallback IV → pure `coap_iv.h#coap_fallback_iv_word` (uid×device + `queen_unix_ts`×reboot + `coap_flush_seq`×flush) + host-тести → **reuse закрито** по всіх осях. 🟡 Residual: IV передбачуваний на fallback — **low-severity** (CoAP-батч без chosen-plaintext вектора). · [ ] 🔗 повна unpredictability = key-derived IV `E_key(counter)` (AES-engine + SEC.8 restore) — bench-gated

#### SEC.14 — ATECC608B role-split re-examination (ARCH.42 honesty)
- **P2** · 👤 · → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **✅ Re-examine done — чесний trade-off канонізовано ([`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) «Роль SE: per-packet AES vs provisioning-only» + SEC.14 trade-off-таблиця там само):** перефреймовано «0.1% acceptable» → справжня вісь = tamper-resistance LoRa session-ключа (per-packet SE AES) ⟷ latency/ідіом (built-in radio-AES STM32 ~10µs + session-key у RDP-Flash, SE provisioning-only); energy active перевірено = малий (≈0.3% TX / ≈0.2% циклу Сценарію C, **НЕ вирішальний**); ATECC-agnostic щодо FW.2 nonce. Лишається:
  - [ ] 👤 обрати роль SE (per-packet vs provisioning-only) — bench eval + BOM freeze; threat-model-рішення, не тех-необхідність. Тепер **SE050**-контекст (вісь та сама) → рішення тримається у SE050-MIGRATION (One-Home)
  - [x] 🤖 (2026-06-12) cross-check проти канонічного бюджету ([`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power) Сценарій C, дзеркало [`02_01 §2`](02_01_Hardware_Architecture_and_BOM)): active ≈0.3% TX / ≈0.2% циклу / ≈3% годинного запасу — «малий» підтверджено (старе «~39 мДж TX» було deprecated +22 dBm); **знахідка-інверсія: always-on SE sleep 150 нА ≈ 3.6 мДж/год > весь запас Сценарію C (+1.4 мДж/год)** → SE обов'язково за load-switch гейтом (TPS22860-патерн) — канон [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) Power impact; стосується обох ролей, тож НЕ блокує 👤-вибір вище

#### SEC.15 — IWDG freeze у STOP2 (option byte `IWDG_STOP=0`)
- **P1** · 👤 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- ✅ Freeze-rationale + PVD-кома side-path канонізовано ([`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)); `IWDG_STOP=0`+`IWDG_STDBY=0` заскриптовано поряд з RDP — `firmware/scripts/bench/01_option_bytes.sh` + RUNBOOK §1.2.
  - [ ] 👤 застосувати на платі при factory flashing
  - [ ] 👤 bench-верифікація: сон 1 год без spurious reset (RUNBOOK §4.4)

#### SE050-MIGRATION — ATECC608B → NXP SE050 + true-DePIN ladder (2026-06-07)
- **P1** · 👤+🤖 · → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Рішення (founder):** trust-напрям = **true-DePIN** («голос дерева» — дерево підписує власні дані non-extractable Ed25519; ні backend, ні оператор не підробить). SE мусить вміти Ed25519 → **ATECC608B (P-256) → SE050** (суперсет: Ed25519/EdDSA + AES-128/256 + monotonic counters + secure storage). AES-128 LoRa СТОЇТЬ (ARCH.42; тепер свідомий вибір, не SE-constraint). Ladder: **L0 кастодіально (зараз) → L1 Queen-attest → L2 per-tree** (energy-gated). Канон-дім = `03_05 §3.7` ADR. Ціна (~$2.40-3.25 vs $0.85) — founder: не проблема.
- [x] 🤖 (2026-06-07) **Канон-дім `03_05 §3.7`**: ADR SE050+ladder · heading/callout (реверс ATECC→SE050) · Slot-1 P-256→**Ed25519** (on-chip keygen) · Status/SEC.14 naming · **AES-128-rationale One-Home-колапс ×6** («SE max 128» → реф §3.7, бо SE050 вміє 256) · legacy-banner над ATECC integration-mechanics.
- [x] 🤖 (2026-06-07) **docs-дзеркала (name+ref) DONE:** `00_00` index · `03_01` (Flash-KV path-B) · `08_01` (Ярмілко) · BOM `02_01` row 13 + `07_02` RF Deck → SE050 (cost ~$2.40-3.25).
- [ ] 🤖 **`03_05` deep mechanics → SE05x** (no-premature-canon: при eval-kit + datasheet-verify): candidate-table, `atcab_*`→`Se05x`/`sss` API-sketch, role-split table, latency/power/footprint, object-model замість 16 slots, on-chip Ed25519 keygen.
- [x] 🤖 (2026-06-07) **firmware DONE:** `soldier/queen main.c` коментарі ATECC→SE050 (name + One-Home: «SE constraint»→AES-128-вибір/§3.7) + RUNBOOK eval-kit рядок. Comment-only (zero behavior).
- [~] 🤖 (2026-06-07) **код partial:** `atecc_provisioner.rb` — SE050 header-нота + Slot-1 P-256→**Ed25519** (on-chip keygen) ✅ (comment-only, специ зелені). **Лишилось (bundled з eval-kit real-I²C):** rename `AteccProvisioner`→`SecureElementProvisioner` (+session/spec/factory refs) · SE05x emit замість `atcab_*` · DB-колонка `atecc_serial_hex`→`se_serial_hex` міграція (+structure.sql) — Гілка-B не live → ризик-кероване відкладання.
- [x] 🤖 (2026-06-07) **honesty-pass DONE** (true-DePIN наратив): `05_01` (DePIN-роль) / `04_02` (W3bstreamVerify card) / `05_03` (IoTeX row) / `06_08` — «доводить фізичний STM32» → розділено **pipeline-integrity + DID-binding (є, master-backed)** vs **physical-origin** (custodial-now / device-bound-roadmap ladder / ЗВТ-metrology). `04_02` stale механізм виправлено (`binary_key`→`derive_iotex_seed` HKDF).
- [x] 🤖 (2026-06-07) **Trust-origin ladder canon DONE** — first-class дім `05_02` (L0→L1→L2: рунги/хто-підписує/що-доводить/гейт/статус + «крипта доповнює ЗВТ+economics» + «енергія, не крипта, — гейт L2»). `03_05 §3.7` ladder злим до референсу (One-Home); honesty-рефи (05_01/04_02/05_03/06_08) перепнуто на дім; `00_06 §2` зареєстровано (ladder→05_02, SE-part→03_05 §3.7). ✅ Крок-B приклад SHA256→Ed25519-first виправлено при L1.
- [ ] 👤 **SEC.6 hardware:** eval-kit order + datasheet-verify (SE050 Ed25519/EdDSA + monotonic counters + AES-128 + I²C + active/standby струми) + SEC.14 role (per-packet vs prov-only) + mass-BOM populate **разом з load-switch гейтом SE** (TPS22860-патерн; sleep-floor розрахунок — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) Power impact).
- [~] 👤/🤖 **L1 Queen-attestation** — 🤖 **shipped (2026-06-07)**: firmware Queen software-Ed25519 (Monocypher, pinned submodule) підписує CoAP-батч (EDSK-сім'я Protected Flash; конверт One-Home `firmware/common/queen_attest.h`) + backend verify-до-decrypt у `UnpackTelemetryWorker` (nonce anti-replay за M2M-патерном; маркери `gateways.last_attested_at` + `telemetry_logs.gateway_attested`) + factory EDSK (`CommandBuilder`/`Session`; сім'я фабрично-хостова, НЕ HKDF-від-master) + попутно закрито `Load_CoAP_Key` TODO (KEYC писався бекендом, але не читався прошивкою). Parity: host C (Monocypher↔OpenSSL) ↔ RSpec (ruby `ed25519`) golden-KAT. Wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security); ladder-статус [`05_02`](05_02_Proof_of_Growth_Pipeline). · [ ] 👤 bench: EDSK-flash на кремнії + e2e attested-батч (RUNBOOK) · [ ] 🔗 HIL `queen_simulator` signed-режим (опційний e2e без заліза)
- [ ] 🔗 **L2 per-tree device-voice** (North-Star, energy-gated Scenario D / 2× anchor): on-chip Ed25519 keygen + device-keygen provisioning (не HKDF-only — ARCH.33) + Merkle-root signing (E.60) + signature-transmission (weekly ≈ 5 LoRa-frames). Post-anchor-TRL.
- Cross-ref: SEC.6, SEC.14, ARCH.42, ARCH.43 (per-device-ізоляція post-FW.2), E.60 (Merkle), FW.2, FW.23, ARCH.33 (firmware-Ed25519 feasibility), STK.4 (ЗВТ), BIZ.13 (operator-bond).

## §04 · Backend / API / UI

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### E.65 — `piezo_voltage_mv`: фантомний продакшн-шлях (сейсміка)
- **P3** · 👤 · → [`04_01 §3`](04_01_Data_Models_and_Entities)
- Колонка в усіх партиціях + btree-індекс `idx_telemetry_logs_piezo_created` + скоуп `seismic_activity (> 1500)` + рядок у `04_01` — але жоден wire-формат (21B/CCM) не несе piezo і жоден код не пише колонку → скоуп вічно порожній, індекс індексує NULL-и. П'єзо в залізі реальне ([`02_01 §3`](02_01_Hardware_Architecture_and_BOM) BOM), але його роль — акустичний тригер TinyML (audio path), не окреме mV-поле телеметрії. · [ ] 👤 рішення: reserved-під-майбутній-сенсорний-фрейм (тоді лишити + чесна примітка) vs прибрати скоуп+індекс+колонку до появи реального wire-поля

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** · 👤 · → `04_03`
- ✅ graceful degradation (Redis down → DB-backed nonce, TTL 10хв) + тести. · [ ] 👤 верифікувати Upstash multi-zone replication у production

#### S6.10 — MaintenanceRecord — лише лог
- **P3** · 🔗 · → `04_02 §Forester Guild`
- ✅ архітектурний дизайн task-assignment (bounty, scoring, `FOR UPDATE NOWAIT`, GPS/EXIF/IPFS→USDC, anti-Sybil). · [ ] 🔗 зв'язати з Forester Guild PoPhW (E.20)

#### S6.14 — peaq_signing_key: відсутня rotation policy
- **P2** · 👤 · → `04_02 §S6.14`, `06_04 §5.4`
- ✅ rotation policy (dual-key 72h, 90д) + emergency revocation runbook. · [ ] 👤 vault-store production `peaq_signing_key`

#### S6.20 — Два воркери без cron у `config/sidekiq.yml` (doc-ahead-of-code)
- **P2** · 👤 · → [`04_02 §11`](04_02_Business_Logic_and_Services)
- [`04_02 §11`](04_02_Business_Logic_and_Services) описує два воркери як cron-driven, але запису в `config/sidekiq.yml` немає → жоден шлях їх не кличе: (1) **`ClusterEntropyAnalyzerWorker`** — `silkennet_cluster_entropy_score` gauge ніколи не оновлюється → `entropy_anomaly`-алерти не спрацьовують; потрібен orchestrator-воркер (`Cluster.find_each` → `perform_async(cluster_id)`). (2) **`InsurancePayoutWorker`** — `:triggered`-страховки залипають назавжди (якщо `Dclimate::VerificationService` enqueue впав / 10 retry вичерпались) → кошти не доходять до постраждалої org; потрібен sweep-воркер по `ParametricInsurance.status_triggered`. · [ ] 👤 додати cron/orchestrator для обох (або, якщо trigger лишається ручним, прибрати «cron»-формулювання з §11)

#### TEST.1 — Test coverage: RSpec gate raised; Solidity/firmware tracked
- **P2** · 🤖 · → `04_06 §B.1`
- Скоуп + політику гейту описує `04_06 §B.3`; gap-recipe + тріаж — `04_06 §B.4`. Пороги живуть тільки в `spec/spec_helper.rb`. · [x] 🤖 (2026-06-02) **RSpec**: відфільтровано `/lib/tasks/` (ops-оркестрація; логіка в lib-движках на 100%), піднято гейт (line/branch + per-group tripwire), великий branch+line-push із тріажем `04_06 §B.4` — мертві `&.`→`.`, реальні guard/empty-state/error/anonymous-policy тести, `stub_const` для forward-looking-гілок, прибрано dead-code (`weak_key_detector`/`resilient_client`/`emergency_response`/`tracker/dashboard`/`chainlink_router_version`/policies/`hil/*` тощо). · [ ] 🤖 RSpec залишок — branch-хвіст звужується партіями (2026-06-03 Batch 2+4: codex/match+node scope+guard-edges, celo low-balance-raise + Time-window, insurance Etherisc-idempotency, codex/citation nil-type, dashboard parser-guards, blockchain_minting wallet-nil identifier, wallet toucan-no-address) + **2 dead-branch рефактори** (insurance redundant `if status_paid?` за AASM triggered→paid; rollback dead `log.tree&.` за Tree `dependent: :delete_all`) + **ReDoS-fix** `TABLE_ID_RE` (CodeQL: вкладений `(?:[…]+\s*)*` → лінійний клас). Решта домінована **defensive** (Phlex-views `&.current_user`, env/load `defined?(...)`, model-validation-dead, exhaustive-case) → лишається за §B.4 (fragile white-box заради % = анти-§A.16–17). Таксономія dead→refactor vs defensive→leave+чому + decision-матриця + worked-examples — `04_06 §B.4/§B.5`. · [ ] 🤖 **Solidity** (`contracts/`): line/func високі, forge-тести зелені; forge branch% низький — переважно forge-артефакт (рахує кожен `require` + OZ-inherited; revert-шляхи покриті `testRevert_*`); `[profile.ci]` пофікшено (optimizer був off → не компілювалось на OZ P256). Глибший branch-targeting pass deferred. · [x] 🤖 (2026-06-11) **Firmware coverage-lane**: `make -C firmware/test coverage` (gcov, інструментована перебудова `-O0 --coverage`, звіт по owned `../common`/`../queen` — і `.c`, і header-only через TU-атрибуцію) + CI-крок visibility-без-порога (ОСТАННІМ — інструментовані бінарники зірвали б size-check). Перший прогін: майже все 100%, діра у свіжому `flash_ring.c` 92% → +тест повного drain-циклу → 94% (решта defensive guards, §B.4 leave). Попутно: `clean` не прибирав 3 новіші бінарники. Mock AES/TinyML/DMA — inherent host-обмеження (`04_06 §B.1.1`), main.c міряє QEMU/bench-фаза. · [x] 🤖 (2026-06-03) test-файли: коментарі аудитовано (всі spec/) — здорові (ID-refs + WHY + wire-layout; 0 dead-code / реальних TODO); виправлено count `~20 specs` + trimmed changelog-дати `ARCH.42 (date)`. · [x] 🤖 (2026-06-12) **seed-флак ВПОЛЬОВАНО й закрито**: рецепт «diff двох fixed-seed прогонів» виконано (інструмент — `scripts/coverage_seed_diff.rb`, рецепт у шапці; gotcha: SimpleCov мержить у 10-хв вікні → чистити `.resultset.json` між прогонами). Уся сюїта мала РІВНО один флак-сайт: `sessions#current_session` (2 рядки + 2 гілки) — інтеграційна спека незворотно (`Module#prepend` в `around`) тіньовила продакшн-метод за хибною преміссою «методу нема» → решта сюїти тестувала підміну (інтегріті-дефект, не лише coverage-шум). Препенд видалено; контрольна пара прогонів — 0 флоатерів. Тріаж-таксономія + worked example — `04_06 §B.4/§B.5`.

## §05 · Web3 / Економіка / Slashing

> Мультичейн, oracle/chain-конфіг та slashing-механіка — канон `05_xx`.

#### SLASH-1 — Slashing cause_classification gate (financial-safety) 🔴
- **P0** · 🤖+👤 · → `05_05 §3/§6` (divergence `04_02 §11`)
- ✅ supporting-механіка coded + RSpec, але **INERT** (gate `SystemParameter :slash_cause_uplift_enabled`, default off → жива поведінка = baseline-лінійна): convex §3 slash-крива (`#calculate_slash_ratio`, GAMMA/PF_MAX DAO-governed) · blackout → Field Audit no-burn (`#flag_data_blackout!`) · comms-loss de-correlation `max()`-не-сума (`#combine_penalty_factor`). Канон [`05_05 §3/§6`](05_05_Slashing_and_Risk_Policy). 🔴 **формальний A/B/C `cause_classification`-gate (namesake) ще НЕ в коді** + uplift не активований. · [ ] 👤 DAO/founder перед mainnet: A/B/C cause_classification + активація uplift + tree-side `streamr_undelivered` сигнал (guarded→0) + repeat-offence вага (BIZ.13 operator-bond, `05_05 §3.1`)

#### S3.2 — dClimate Real API verification
- **P1** · 👤 · → `05_01`
- ✅ `Dclimate::VerificationService` (NASA FIRMS, FRP≥10MW, cloud fallback). · [ ] 👤 верифікувати з реальним API key у staging + e2e `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P1** · 👤 · → `05_03`
- SFC events (ForestMinted, GovernanceSlashed) у subgraph; адреса = placeholder. Zero-address fail-fast guard `subgraph/validate_addresses.sh` ✅ (раніше E.45). · [ ] 👤 замінити `0x0000…` на реальну SFC-адресу у `subgraph.yaml` (після контракт-деплою)

#### BIZ.13 — Slashing principal-agent: investor capital vs operator-bond
- **P2** · 👤+🤖 · → `05_05 §3.1`, `05_03 §Slashing`, `04_02`
- Кат-A slash зрізає інвесторський `locked_balance`, хоча недбалість — провина оператора (principal-agent). ✅ decision memo → рекомендація **hybrid operator-bond**. · [ ] 👤 DAO confirm: hybrid vs investor-slash vs pure operator-bond · [ ] 🤖 якщо operator-bond — `OperatorBond` + `ProtocolParameters` + контракт + синх `05_05 §3`/`05_03`/`04_02`

#### E.60 — Merkle CID-witness: Polygon ↔ Filecoin integrity bridge
- **P1** · 🤖 · → `05_02 §E.60`
- ✅ (2026-06-03) `Filecoin::CidGenerator` (детермін. CIDv1 raw+sha2-256→base32, golden-vector) + content-CID guard у потоці архівації AuditLog: `ArchiveService` вбудовує самоописовий `content_cid`, `VerificationService` fail-fast при розбіжності (локально vs віддалено) → детект ex-post swap. Закриває archive-swap gap для audit-архіву. · [ ] 🤖 follow-on: per-tree Merkle-witness для телеметрія-батчу (leaf_cid→`archive_root`→`mint(bytes32)`) — потребує `MerkleTree` + колонок на партиційованому `TelemetryLog` (міграція) + Solidity; worker-guard з `manual_review` саме в цьому батч-потоці. Канон `05_02 §E.60`

#### E.63 — метаболічний сигнал: розв'язано від хаосу (Option A) [2026-06-08]
- **P1** · 👤+🤖 · → `05_02`
- ✅ **Option A (founder 2026-06-08) — здоров'я розв'язано від хаосу:** Лоренц = лише status-гейт (β=`BASE_BETA` фікс), `growth_points` у гомеостазі = `metabolic_health(delta_t)` напряму; FW.5 β-перт реверсована (delta_t економічно нульовий / vcap інвертований — β не рухає z-нерухому точку z_eq=ρ−1). Код (`bio_contract.rb`+`attractor.rb`, byte-identical DCI) + тести + канон ([`03_04 §4.3`](03_04_mruby_Lorenz_Attractor) verdict · [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) L4 · [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет) + guard `growth_points_clamp_drift` + backend GP-conformance C (`check_metabolic_divergence!`, observational). Wire незмінний. Лишається:
  - [ ] 👤 bench: реальна P_ebfc (`HW.13`) + E_cycle + recharge-крива (`03_power_profile.py`, RUNBOOK §3.2-3.3)
  - [ ] 🤖 калібрування `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` (placeholder 600/7200с) під зміряну recharge-криву — per-deployment/species
  - [ ] 🔗 B на FW.2 — точна stateless GP↔delta_t (wire несе **raw** delta_t, GP з EMA-згладженого device-RTC → перерахунок лише коли CCM-кадр понесе EMA-delta_t; **wire-rev2 28B цього НЕ додав** — зареєстровано кандидатом rev3 у wire-budget ledger [`03_05 §3.2`](03_05_Hardware_Symmetric_Crypto_and_Security): рішення «замінити семантику dT-поля на EMA» vs «+2B» — за founder'ом)

#### E.64 — bio→economy signal-coupling audit (E.63-лінза) [2026-06-08]
- **P1** · 👤+🤖 · → [`05_05 §7`](05_05_Slashing_and_Risk_Policy)
- ✅ **E.63-лінза fixes (2026-06-08):** окрім delta_t (E.63), решта bio→economy слабка — фікси: **#2** anomaly ρ-relative (`z > ρ + (CRITICAL_Z_MAX−BASE_RHO)` = 45 при ρ=28; ambient-temp більше не тригерить хибну, warm-day 22%→3%; firmware+backend `anomaly_ceiling`/`homeostatic?`); **#3** stress_index conformance ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)): Z-anomaly bounded 0.6≪0.83 «Z alone never slashes», degenerate `avg_z`/weather-`temp` прибрано, `max_status≥3` лише tamper. **Throughline:** Лоренц health-оракул **декоративний** → реальна цінність DCI anti-fraud (device-Z≡server-Z); здоров'я ведуть ПРЯМІ сигнали (metabolism ✅ E.63 · sap · VPD · acoustic). Канон [`03_04 §4`](03_04_mruby_Lorenz_Attractor) · [`05_05 §7`](05_05_Slashing_and_Risk_Policy) · [`05_05 §8`](05_05_Slashing_and_Risk_Policy). Нічого не задеплоєно → correctness перед деплоєм. Лишається:
  - [ ] 🔗 real-signal activation (sap/VPD/acoustic stress_index + per-species/season пороги) — ground-truth calibration (bench, [`08_02`](08_02_Academic_Institutions_Registry)). Cross-ref: E.63, FW.8, FW.50.

## §06 · Deploy / Observability / Secrets / Ops

> Деплой, спостережуваність, секрети, DR — канон `06_xx`. (Частина цих пунктів раніше сиділа під §04 «DevOps»; тепер кожен у власному §06-домі.)

#### S1.1 — GitHub Secrets заповнення
- **P0** · 👤 · → `06_04`
- ✅ checklist + інвентаризація 4 місць секретів. · [ ] 👤 заповнити GitHub repository secrets (12 крит.: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `SSH_PRIVATE_KEY`…) → верифікувати CI

#### S1.5 — Kamal IP placeholders
- **P2** · 👤 · → `06_01`
- `192.168.0.1` / `<CANOPY_SERVER_IP>` плейсхолдери в Kamal config. · [ ] 👤 підставити реальні IP після `terraform apply` → верифікувати deploy

#### S2.1 — Верифікація метрик після deploy
- **P0** · 👤 · → `06_03`
- `/metrics` (реєстр — `06_03 §2.8`) + Alloy sidecar → Grafana Cloud налаштовано. · [ ] 👤 верифікувати збір метрик після першого Akash deploy

#### S2.4 — Observability industrial-grade hardening
- **P1** · 👤 · → [`06_03 §2.9`](06_03_Prometheus_Observability)
- **✅ Industrial-grade hardening канонізовано ([`06_03 §2.9`](06_03_Prometheus_Observability)):** `external_labels` (env/service/source/release attribution) + `queue_config`+explicit WAL (backpressure) + cardinality-budget relabel + process/runtime gauges (`sample_process_runtime!`/`sample_connection_pool!`, RSpec-covered) + CI-валідація (`alloy_config_validate` / `grafana/alloy fmt`) — конкретні значення у `config.alloy` SSOT (не дублюються). Лишається:
  - [ ] 👤 `up`-scrape alert + SLO/error-budget (§2.9 #6 — ingest availability, mint/slash success) — Grafana Cloud

#### S2.2 — Grafana Cloud dashboards
- **P0** · 👤 · → `06_03`
- ✅ dashboard IaC (секції/панелі — зведення у `deploy/grafana/README.md`) → `deploy/grafana/`. · [ ] 👤 імпортувати у Grafana Cloud (інструкції `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** · 👤 · → `06_03`
- ✅ alert rules IaC (P0/P1/P2, зведення у `deploy/grafana/README.md`) → `deploy/grafana/alerts/` + counter `silkennet_telemetry_acoustic_overflow_total`. · [ ] 👤 замінити `${DATASOURCE_UID}` + notification channel (Slack/Email/PagerDuty)

#### INF.3 — TLS termination
- **P2** · 👤 · → `06_02 §TLS термінація`
- SDL відкриває 80/443/CoAP-UDP 5683, але TLS termination не налаштовано (browsers block WS HTTPS→HTTP). · [ ] 👤 налаштувати TLS (Akash ingress або Cloudflare)

#### INF.6 — CoAP UDP smoke test через Ingress Anchor (post-deploy gate)
- **P1** · 🤖+👤 · → `06_01`, `06_02`, `06_08 §1.2`
- ✅ workflow `coap_smoke.yml` (`workflow_dispatch` + `workflow_call`). Без UDP-smoke silent UDP failure не помітний (Queen→Ingress Anchor→Akash→CoAP). ✅ (2026-06-12) зонди = freeze-contract `bin/coap_smoke` (точні байти, регресія фантомної доставки — деталі: FW.56) замість generic libcoap POST. ✅ (2026-06-12) виклик заведено post-deploy gate'ом у `deploy.yml` + `deploy-production.yml` (job `coap-smoke`, `needs: deploy` — fail валить deploy-run); поки repo Variable з host не задана, job видимо skipped (Брама не задеплоєна — не silent). · [ ] 👤 задати repo Variables `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` коли Ingress Anchor існує → gate активний · [ ] 👤 перший boundary smoke з Queen/`bin/forest_simulator`

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** · 👤+🤖 · → `06_02 §TLS термінація`
- ✅ runbook: Опція A (Cloudflare HTTPS + direct UDP CoAP) рекоменд. + pre-flight + fallback B. Cloudflare НЕ proxies UDP → CoAP потребує direct ingress. · [ ] 👤 прийняти рішення (рекоменд. A) · [ ] 🤖 якщо Akash hostname — automation у `terraform/`

#### S4.3 — Akash SDL secrets
- **P3** · 👤 · → `06_02`
- `REQUIRED_SECRET_NOT_SET` для 4 крит. змінних. · [ ] 👤 заповнити в `deploy/akash/deploy.yaml` → верифікувати startup

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** · 👤 · → `06_03`
- ✅ `RELEASE_VERSION` у deploy configs. · [ ] 👤 верифікувати Sentry release tracking

#### S5.6 — GCS bucket для Terraform state (chicken-and-egg)
- **P3** · 👤 · → `06_02 §GCS bucket`
- GCS bucket для remote TF state — вручну перед `terraform init`. · [ ] 👤 `gsutil mb` → верифікувати `terraform init`

#### S6.18 — Rails web security hardening (§8 audit)
- **P1** · 👤 · → `06_04 §2.1`
- ✅ production.rb (force_ssl/HSTS/hosts) + CSP (report-only) + security_headers.rb + session_store. · [ ] 👤 `RAILS_ALLOWED_HOSTS` у Kamal/Akash перед prod · [ ] 👤 після 1-2 тиж CSP-репортів → `CSP_ENFORCE=true`

#### PUMA-IPV6-1 — Верифікація IPv6 bind після першого Kamal-деплою
- **P1** · 👤 · → `06_05`
- Puma 8 bind `[::]:3000` dual-stack; Thruster → `127.0.0.1:3000`. · [ ] 👤 після canopy deploy: `ss -tlnp\|grep 3000` (`tcp6 [::]:3000`) + `curl` v4/v6 `/up` → задокументувати у `06_05`

#### DR.1 — Disaster Recovery drill + master-key backup
- **P1** · 👤 · → `06_06`
- ✅ DR-постуру задокументовано (`06_06`): Cloud SQL PITR + REGIONAL HA + 30×daily + restore-runbook'и + RTO/RPO. · [ ] 👤 quarterly DR-drill (PITR-clone + TF-state rollback на staging, зафіксувати факт. RTO/RPO vs цілі) · [ ] 👤 master-ключі (`RAILS_MASTER_KEY`/`PROVISIONING_MASTER_KEY`) → vault + offline-копія (незамінні, поза backup)

#### ARCH.35 — Queen Flash Ring Buffer (W25Q32 overflow tier)
- **P1** · 🔗 · → `06_08 §1.2`, `02_05 §2.1`
- CIFO 50-slot RAM cache переповнюється ~30 хв @100 Soldiers/Queen → SPI NOR W25Q32JV (4 МБ, ~$0.50, SOIC-8) як overflow tier; sector-based ring (192 слоти/сектор ≈ 197k слотів); drain Flash-first→RAM. Implementation Anchor resilience-policy на верхньому краю scaling.
- **✅ 🤖 драйвер + gated Queen-глю зашито (2026-06-11f):** `firmware/common/flash_ring.{h,c}` — sector-ring з **in-band заголовками** `[magic|seq]` + NOR-бітмапи used/consumed (ADR: замінили ескізні RTC-покажчики — ті гинуть з VBAT і розходяться зі вмістом флешу; mount-scan відновлює head/tail/count після будь-якого знеструмлення, Queen DR не витрачаються); слот = 21-байтний wire-запис батча (бітове дзеркало пакувальника); power-cut-інваріанти: дані→used-біт, сирота tombstone'иться, consume лише після send-success → **at-least-once** (дубль можливий, втрата — ні). Host-тести `test_flash_ring.c` (NOR-мок 1→0 + fault-injection: roundtrip · remount-recovery · wrap-drop durable · consume across sectors · 3 power-cut сценарії) — тест одразу зловив NOR-діру дизайну (перезапис сироти AND-ить байти). Queen-глю (gated `ARCH35_RING_ENABLED 0`): SPI W25Q32 cmd-set (PP page-aware) + спіл евікшнів і провалених flush'ів + drain-refill у CIFO (`is_active=2`) з consume після наступного send-success. Канон: `02_05 §2.1` (дім дизайну) + `06_08 §1.2` L1.
- [ ] 🔗 W25Q32 розводка (SPI + CS-пін, board-freeze `.ioc`) + bench SPI-глю → фліп `ARCH35_RING_ENABLED 1`

#### ARCH.34 — Queen-side LoRaWAN Helium SOS fallback
- **P2** · 🔗 · → `06_08 §1.2`, `02_05 §6.1`
- Helium fallback перенесено Soldier→Queen (STM32WLE5JC flash/RAM/topology несумісний). Queen: LoRaMac-node stack + OTAA join state + FCntUp persist; SOS-маяк ~12 байт (НЕ телеметрія кластера — SF12 EU868 ~51B cap) → Helium hotspot → LNS → Rails `POST /telemetry/helium`. Soldier лишається raw LoRa P2P AES-128. Implementation Anchor L3; без нього L3 fallback архітектурно неможливий. · [ ] 🔗 Queen `queen_helium_lorawan_uplink()`

## §07 · Юридичні / Бізнес

> Юридично-бізнесовий work-stream — канон `07_xx`. NB: пов'язані BIZ-айтеми за канон-домом живуть у `§05` (BIZ.13 slashing) та `§08` (BIZ.10 IP, BIZ.12 Horizon-biodiv).

#### BIZ.1 — 1 SCC = ? kg CO₂
- **P2** · 👤 · → `07_01`, `05_03`
- ✅ 2000 SCC = 1 tCO₂ (0.5 кг/SCC), carbon coefficient per-species. · [ ] 👤 сертифікація методології (Verra/Gold Standard, Post-TRL 7 → BIZ.9)

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **P1** · 👤 · → `07_01`, `08_02 §5`
- Партнер: СЄУ (Аблязов Д.Е., к.ю.н.). · [ ] 👤 юр-консультація (MiCA/ERC-3643/RWA) → MSA template (Term Sheet + Carbon Credit Purchase Agreement) → review практикуючим юристом

#### BIZ.3 — B2C ToS / Privacy Policy
- **P2** · 👤 · → `07_01`
- [ ] 👤 ToS draft + Privacy Policy (GDPR) + Cookie Policy

#### BIZ.6 — Supply chain war-zone risk mitigation
- **P1** · 👤 · → `07_02 §8.1.1`
- ✅ Contingency Plan EU Backup DMLS Hubs (4 кандидати; triggers; +~20% payback) — UA-підрядники у зоні бойових дій. · [ ] 👤 отримати quotes для порівняння (→ BIZ.8)

#### BIZ.8 — EU DMLS quotes → Frame Agreement (procurement track, extends BIZ.6)
- **P1** · 👤 · → `07_02 §8.1.1`
- BIZ.6 ✅ ідентифікував 4 EU кандидати (3D Lab PL, Materialise BE, Sauber/Lithoz, TRUMPF). · [ ] 👤 quotes у 3D Lab PL + Materialise BE → порівняльна таблиця (раніше OPS.5) · [ ] 👤 NDA+RFQ зі 3D Lab PL → sample part order (10 шт) quality benchmark → Frame Agreement (+20% premium, 30-day activation)

#### BIZ.9 — Незалежний carbon credit методолог (Verra/Gold Standard)
- **P2** · 👤 · → `07_01 §3`, `07_02 §7.3`
- Конвертація SCC utility-token → сертифіковані kg CO₂ для institutional buyers потребує independent methodology audit (Verra/Gold Standard/Puro.earth). · [ ] 👤 engagement methodologist (~$50-100k) → PDD у Verra · [ ] 🔗 залежить від HW.3 (Arrhenius) + UNI.6/UNI.7 (DFT+diffusion)

#### BIZ.11 — RWA pilot реєстрація лісової ділянки через Polygon Hadron
- **P2** · 👤+🤖 · → `07_01 §8`
- Hadron (ERC-3643) RWA-pilot: 1 ділянка з кадастром + biomass appraisal (LIDAR+ground) + Hadron compliance. · [ ] 👤 партнер-лісокористувач (post-war/Carpathian) + кадастр/biomass appraisal · [ ] 🤖 `Hadron::TokenizeForestPlotService` + KYC flow spec · [ ] 🔗 після BIZ.2 (MSA)

#### BIZ.14 — SFC Vote-Escrow during breach→slash lag (07_01 BLOCKER-7 residual)
- **P3** · 🔗 · → `07_01 §8`
- ✅ Core закрито: `SilkenForestCoin.slash()` (SLASHER_ROLE) зменшує voting power при slashing → атака «купити SFC + навмисне порушення NaaS» неможлива. 🟡 Residual: ~1–5 хв lag (`web3_critical` черга) між SCC-slash і SFC-slash — у вікні учасник технічно ще може проголосувати. · [ ] 🔗 Vote-Escrow (veToken) при `breached`-контрактах — опціонально, gated на повний DAO governance launch (BIZ.4)

#### BIZ.15 — B2B Fiat-to-Retirement SPV (corporate carbon on-ramp)
- **P2** · 👤 · → `07_01 §8`
- Корпорації з ESG-зобов'язаннями не триматимуть крипту/ключі заради ретайрменту — потрібен SPV-міст: фіат → SPV купує+ретайрить SCC → сертифікат офсету (CBAM/ISO 14064). Поточний `KlimaRetirementWorker` припускає, що клієнт уже on-chain власник SCC (нот.19). · [ ] 👤 юрисдикція SPV + ліцензія на вуглецеві активи + кастодіан крипти (СЄУ Аблязов Д., RWA/MiCA — `08_02 §5`) · [ ] 👤 бухгалтерська класифікація + сертифікат-флоу (СЄУ Ус Г.)

## §08 · Академічна інтеграція + External Stakeholders

> **Поточний стан:** Партнерство з 5+ академічними установами — ChNU (фізико-хімія + ФОТІУС), ChDTU (Data Science + RF + акустика), ChIPB-NUTSU (пожежна безпека), ChMA (біохімія + токсикологія), СЄУ (правова + економічна архітектура). UNI.1-3, UNI.8 — раніше ідентифіковані; нижче — розширення на всі 5 установ.

#### UNI.1 — Перший контакт з деканом Онищенком (ChNU FOTIUS)
- **P0** · 👤 · → `08_01`
- Блокує всю лаб-роботу, 10 публікацій, 11 магістерських. · [ ] 👤 призначити + провести зустріч

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС
- **P1** · 👤 · → `08_02`
- [ ] 👤 8 зустрічей: Супруненко (PN-verification/Convolution) · Онищенко (stochastic B&B/Petri) · Ярмілко (Embedded/ECDH) · Порубльов (Discrete Math/reliability) · Косенюк (RF/FEC/compliance) · Бушин (CNN/BSP/DMLS) · Осауленко (portfolio) · Любченко (GA/NN)

#### UNI.3 — Defensive-publication + open-license execution (IP-постава)
- **P1** · 👤🤖 · → `08_01 §2`
- ✅ Постава = **defensive-publication-first** (`08_01 §2`; патент НЕ подаємо). 🤖 Ліцензії застосовано (AGPL / CERN-OHL-S / CC-BY-SA + `/NOTICE`); disclosure готовий ([`defensive_disclosure.md`](protocols/anchor/defensive_disclosure.md)) + landscape ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)). **Стаття 1 розблокована** (publish-to-protect). Owner-дії: · [ ] 👤 TDCommons-постинг disclosure (prior-art якір) · [ ] 👤 trademark-заявка SilkenNet™/GaiaNexus™/SCC™ через TISC (UNI.15) · [ ] 👤 Кафедра-ІВ open-license + AF3 legal review (UNI.16) · [ ] 🤖 **SPDX-headers по source** (`app`/`lib`/`firmware`[крім `extern`]/`contracts`/`tools` = `AGPL-3.0-or-later`; CERN-OHL-S для hw-design-файлів) — скриптом, ідемпотентно (skip-if-present); великий механічний diff → **deferred** (plan Phase 7)

#### UNI.4 — ChNU школа Мінаєва: DFT-моделювання EBFC
- **P1** · 👤 · → `08_01 Стаття 1`, `08_03 §1`
- Квантово-хім. симуляція streaming potential на TiO₂-гіроїді + адсорбція кислот ксилеми (школа Мінаєва, світовий DFT). Ціль: Q1 *Electrochimica Acta*; блокує seed credibility. · [ ] 👤 зустріч (через декана хімії) + NDA/IP (BIZ.10) + спільний грант MES/Horizon

#### UNI.5 — ChNU школа Гусака: дифузійна деградація 20-років (Kirkendall effect)
- **P1** · 👤 · → `08_01 Стаття 2`, `08_03 §2`
- Моделювання Kirkendall на Ti-6Al-4V/xylem + Arrhenius 12-тижн (школа Гусака, diffusion-controlled corrosion). Ціль: Q1 *Corrosion Science*; 20+ years claim. Залежить HW.3. · [ ] 👤 зустріч + спільний експеримент HW.3 + co-authored paper

#### UNI.9 — ChDTU Карапетян: Data Science колаборація
- **P1** · 👤 · → `08_02 §2`
- ChDTU R-кластер для ML; А.Р. Карапетян — статистика телеметрії (anomaly/fraud), магістерські. · [ ] 👤 зустріч (ChDTU rectorat) + кафедральна тема «Statistics of Bio-IoT Telemetry» + 2-3 магістерські (2026-2027) · [ ] 🤖 SLA R-кластеру (тренування `silken_forest.marshal`, post-TRL 7)

#### UNI.10 — ChDTU Гончаров (ФЕТР): RF верифікація + EMC pre-compliance
- **P1** · 👤 · → `08_02 §2`
- А.А. Гончаров (ФЕТР): VNA + анехоїчна камера для (a) SMD-антена під PEEK (HW.17), (b) Link Budget у лісі (SF7-9, 50-250м), (c) EMC pre-compliance CE/FCC (E.11). · [ ] 👤 зустріч + RF-лаб access + VNA-вимір PEEK-кришки (1.5/2.0/2.5мм) + Link Budget field test · [ ] 🔗 залежить HW.9 + HW.17

#### UNI.11 — ChDTU Базіло+Бондаренко (ПМКТ): акустична валідація фононної лінзи
- **P2** (P1 для Mongabay) · 👤 · → `08_02 §2`, `03_03 §10`
- ПМКТ (п'єзоелектрика + акуст. метаматеріали): EIS п'єзодиска 25-150кГц (cavitation) + верифікація гіроїдного phonon lens. Ціль: Q1 *IEEE TBME*. 🌿 Mongabay: + dawn/dusk Cherkasy Soundscape Library для 5-class TinyML «Fauna» (`08_01 Стаття 24a`). · [ ] 👤 зустріч Базіло+Бондаренко + EIS-протокол + acoustic стенд (HW.1) · [ ] 🌿 dawn/dusk recordings з UNI.13a (Спрягайло-Гаврилюк): AudioMoth, 4 сезони, ≥30хв dawn+dusk/ділянку, labeled таксони

#### 🌿 UNI.13a — ChNU Біо-хаб (Спрягайло+Гаврилюк): Acoustic Biodiversity Baseline (Mongabay)
- **P1** · 👤 · → `08_01 §1/§2`, `08_01 Стаття 24a`
- Delgado et al. (Nicoya, 119 ділянок, 16k год; Mongabay 2026): dawn/dusk fauna-піки = маркер біорізноманіття (NDVI бачить покрив, не функцію). UA-аналог: **Cherkasy Soundscape Library** (4 сезони, з ЧДТУ ПМКТ UNI.11) → ground truth для 5-class TinyML (FW.4-EXT) + Q1 (Стаття 24a). · [ ] 👤 зустріч Спрягайло (проректор) + Гаврилюк (ННІ природничих) + студенти-біологи + joint methodology workshop (з ЧДТУ ПМКТ) + expedition runs (4 ділянки × 4 сезони × dawn/dusk ≈ 32 записи) · [ ] 🔗 manual labeling (комахи/птахи/амфібії 0-63) → GA-оптимізація Любченко (UNI.6/E.52-EXT) + cross-val 10-річні дані (Спрягайло) + Horizon CL6 grant (BIZ.12)

#### UNI.12 — ChIPB-NUTSU: пожежна безпека + параметричне страхування
- **P1** · 👤 · → `08_02 §3`
- ChIPB + НУЦЗУ: (1) валідація тригерів параметричного страхування (FRP/confidence з dClimate), (2) SOP для 7 EwsAlert-типів (drought/insect/vandalism/fire/seismic/fault/entropy), (3) ДСНС API. · [ ] 👤 cold contact ректорат + презентація fire-safety stack + joint SOP workshop (ARCH.31) · [ ] 🔗 залежить UNI.14 (СЄУ legal) для structuring страхування

#### UNI.13 — ChMA: біохімія EBFC + токсикологія
- **P2** · 👤 · → `08_02 §4`
- ChMA: (1) валідація dgrFAD-GDH + Laccase/ZIF-nanozyme при pH 4.5-5.5 (`01_03`), (2) токсикологія Ti/Al/V іонів, (3) геніпін cross-linking біосумісність (vs глутаральдегід). ⚠️ посади не верифіковані. · [ ] 👤 СПОЧАТКУ verify посади (сайт ChMA) → cold contact ректор → joint biochemistry protocol EBFC Gen 2.0 (HW.5)

#### UNI.14 — СЄУ: токеноміка RWA + правова архітектура
- **P1** · 👤 · → `08_02 §5`
- Розширення UNI.8. СЄУ: (1) MSA/Term Sheet (Аблязов Д., к.ю.н.), (2) KYC/AML юросіб (Hadron), (3) DAO як юрособа (cooperative/Swiss Verein), (4) ESG Accounting (Ус Г.О.). ⚠️ 7 посад потребують verify. · [ ] 👤 зустріч Чудаєва (ректор)/Аблязова Н. (UNI.8) + verify 7 посад + MoU + workshop Аблязов (MSA) + workshop Ус (ESG framework)

#### UNI.8 — Перший контакт з ректоратом СЄУ (legacy ID — see UNI.14)
- **P0** · 👤 · → `08_02 §5`
- Блокує Economic Whitepaper, Legal Framework, NaaS шаблони (`07_01` BLOCKER-1/3). · [ ] 👤 зустріч Чудаєва/Аблязова Н. + verify 7 посад + MoU СЄУ↔SilkenNet + workshops Аблязов (MSA) + Ус (ESG)

#### UNI.15 — ЧНУ TISC engagement (prior-art landscape + trademark + open-license consult)
- **P1** · 👤+🤖 · → `08_01 §2.1` · 🔗 UNI.1 (MoU)
- TISC ЧНУ (WIPO/УкрНОІВІ): (1) **prior-art landscape** (новизна Статті 1 + анти-захоплення → [`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)), (2) **торгові марки** SilkenNet™/GaiaNexus™/SCC™ (~5-10k UAH; подача — повірений УкрНОІВІ), (3) open-license UA-сумісність consult. **Патент НЕ подаємо** (defensive publication, `08_01 §2`). · [x] 🤖 prior-art landscape готовий (query-sets + CPC) · [ ] 👤 контакт TISC (Спрягайло) + auxiliary MoU + trademark-заявка + open-license sanity

#### UNI.16 — ЧНУ Кафедра ІВ engagement (юр-експертиза RWA/токеноміки + open-license)
- **P1** · 👤 · → `08_01 §2.1` · 🔗 UNI.1 (MoU)
- Кафедра ІВ ЧНУ — точковий UA-юрисдикційний review (СЄУ §1F = макро): (1) RWA ERC-3643 vs Лісовий Кодекс/ПЗФ, (2) SCC/SFC за ЗУ «Про віртуальні активи» 2022 + MiCA 2024, (3) NaaS у UA Civil Code, (4) авторське право `bio_contract.rb`/`Attractor` (як основа enforcement копілефту, не пропрієтарність), (5) **open-license review: AGPL/CERN-OHL-S/CC-BY-SA дійсність у UA + AF3 non-commercial × комерц-вимір**. Ціль: 2 меморандуми + license-sanity. · [ ] 👤 контакт зав. кафедри + workshop Аблязов (UA×MiCA) + меморандум RWA (розблок `07_01` BLOCKER-6) + меморандум SCC + open-license/AF3 review

#### UNI.17 — ChDTU Хоменко (Кафедра металорізальних верстатів): прецизійна механіка + DMLS post-processing
- **P2** · 👤 · → `08_02 §2`
- Хоменко (Заслужений винахідник, 80+ патентів): прецизійна обробка + різьба анкера для живої деревини (`01_01`/`01_02`/`02_02`, deinstall `08_02 §3 Несен`). · [ ] 👤 контакт (ChDTU rectorat) + prior-art landscape consult (UNI.15) + прототип різальної геометрії в ЧДТУ machine shop

#### UNI.18 — ЧНУ ректорат: follow-up рішення + рамковий MoU
- **P1** · 👤 · → `08_02`, `08_01`
- Зустрічі **відбулися** (Кирилюк, ректор — 6 трав. 2026; Спрягайло — 8 трав.) → очікується рішення ректорату, рамковий MoU ЧНУ↔SilkenNet **ще не підписаний**. Тиша достатньо довга для ввічливого нагадування. NB субординація: ректор делегує операційну ФОТІУС-координацію декану Онищенку (UNI.1) — НЕ маршрутизувати «теплий інтро» через декана після зустрічі з ректором. · [ ] 👤 ввічливий follow-up Кирилюк/Спрягайло + дотиснути рамковий MoU (framework — BIZ.10)

### 🌐 External Stakeholders (B2G / B2B / Cultural — non-academic outreach)

> **Поточний стан:** Зовнішні залежності виокремлені в [`08_03`](08_03_External_Stakeholders_Registry) (Cultural Layer) та [`08_03`](08_03_External_Stakeholders_Registry) (B2G/B2B Matrix). Це не операційні залежності hot-path — це outreach pool, що активується за TRL-тригерами у відповідних модулях. Імена нижче — публічна інформація; контакти живуть у gitignored CRM.

#### STK.1 — Tier 1 B2G: Дзюбенко (ДП "Ліси України") — легальний доступ до Черкаського бору
- **P1** · 👤 · → `08_03 §2.1`
- Trigger: TRL 5 у `01_01`. Заслужений лісівник + д.е.н. + проф. ЧДТУ; підпис → експериментальний полігон у держлісі (канал через `08_02 §2` ЧДТУ MoU). · [ ] 👤 verify title/contact (ChDTU rector) → first-meeting brief (NaaS+ESG/FSC) → Pilot Site MoU → координація з UNI.6 (Спрягайло) ПЗФ

#### STK.2 — Tier 1 B2G: Сегеда (ДП "Смілянське ЛГ") — еко-аудит + Геронимівка
- **P1** · 👤 · → `08_03 §2.2`
- Trigger: після STK.1. Заслужений природоохоронець у Геронимівці (центр Genesis-кластера); еко-аудит + розширення в Смілянщину. · [ ] 👤 first-contact (cross-link UNI.6 Спрягайло ПЗФ) → біосумісність (LoRaWAN+CODIT) → DAO advisory (PoG oracle validation)

#### STK.3 — Tier 1 B2G: Заслужений юрист — Legal Wrapper для SCC
- **P1** · 🔗 · → `08_03 §2.4`
- 🔗 блок: UNI.16 (Кафедра ІВ ЧНУ) + UNI.14 (СЄУ Аблязов). Перекласифікація анкера "втручання"→"науково-вимірювальний прилад" до прокуратури; кандидати через ННІ права ЧНУ (Кирилюк, `08_01 §1G`). · [ ] 👤 identify candidate (Кирилюк+Аблязов) → узгодити legal opinion з UNI.16

#### STK.4 — Tier 1 B2G: Землевпорядник (TBD) — RWA кадастр oracle
- **P2** · 👤 · → `08_03 §2.3`
- Trigger: TRL 6 у `05_02`. Сервітут під Queen-щоглу + кадастровий oracle; ім'я не верифіковане (Сіроштан — перевірити). · [ ] 👤 identify candidate (cross-ref Аблязов UNI.14)

#### STK.5 — Tier 3 Certification: Чорней (ДП "Черкасистандартметрологія") — SCC certification
- **P1** · 👤 · → `08_03 §4.1`
- Trigger: TRL 6 у `05_02`; критичний gate для CBAM-статусу SCC. Сертифікація Soldier як ЗВТ + дрейф-компенсація + audit похибки D-MRV (інакше SCC = "цифри з інтернету"). · [ ] 👤 verify Chorney status → first-meeting (SCC↔ДСТУ↔BIPM/OIML) → ЗВТ registration roadmap

#### STK.6 — Tier 4 B2B: ПрАТ "Азот" — CBAM offset + хімічний scale-up
- **P2** · 👤 · → `08_03 §5.2`
- Trigger: TRL 7 у `05_02` (live SCC mint). Першочерговий B2B SCC-клієнт (CBAM offset) + канал на scale-up осмієвих полімерів EBFC (І. Кухоль, О. Хуторний). · [ ] 👤 ESG officer cold-contact → CBAM model (`07_02`) → EBFC scale-up feasibility (`08_02 §4`)

#### STK.7 — Tier 5 Social Inclusion: Кучер (соц. сфера) — Horizon Europe Cluster 4/6
- **P2** · 👤 · → `08_03 §6.1`
- Trigger: перед великим Horizon-грантом (`07_03`). Соц. інклюзія для grant-пріоритету + кадровий резерв + Eco-Therapy 4.0 для ветеранів. · [ ] 👤 first-contact (обласна рада) → Eco-Therapy concept (deferred — потребує mobile UI `04_04`)

#### STK.8 — Cultural Tier A (Cherkasy 8 artists): pre-Genesis NFT outreach
- **P3** · 👤 · → `08_03 §11.1`
- Trigger: TRL 7 у `05_02` + Genesis onchain. 8 черкаських митців (Бабак, Теліженко, Афонін, Бондар, Іщенко, Олексенко, Касьян, Гладько); канал через А2 Теліженко (`08_02 §5`). · [ ] 👤 pre-screen (life status+active) → через А2 collective probe → Name&Likeness Release (UNI.14 Аблязов)

#### STK.9 — Cultural Tier B (National 8 artists): pre-launch outreach
- **P3** · 👤 · → `08_03 §11.2`
- Trigger: TRL 8 у `05_03`. 8 національних митців (Марчук, Чебаник, Микита, Сидоренко, Медвідь, Гуменюк, Гуйда, Ковтун) — старша когорта, зафіксувати window; hand-off PR-агентству. · [ ] 👤 verify life/health × 8 → gallery/agent кожному → pitch package (brief+animation)

#### STK.10 — Cultural Tier C (Media): Калініченко / Душок (ТРК Ільдана) — PR shield
- **P2** · 👤 · → `08_03 §11.3`
- Trigger: перед першою публічною інсталяцією. Превентивний інфо-фон проти екопанік («чіпують дерева»); Калініченко — викладач ЧНУ, міст із `08_01`. · [ ] 👤 через ЧНУ rectorat (Кирилюк `08_01 §1G`) перший контакт → документальний міні-сюжет про DMLS-друк (post-prototype)

### ⚖️ IP / Grants (BIZ — канон-дім Модуль 08)

#### BIZ.10 — Multi-party co-authorship + open-license MoU framework
- **P1** · 👤 · → `08_03`, `08_02 §3-07`
- 5-сторонній фреймворк (ChNU+ChDTU+ChIPB+ChMA+СЄУ+SilkenNet) **спрощено під open-поставою** (`08_01 §2`): tech відкрита всім → **немає патентних прав / royalty / tech-NDA до розподілу**; лишається **co-authorship + open-license acknowledgment** (AGPL/CERN-OHL-S/CC-BY-SA) + NDA **лише** для нерозкритого (ключі / production-дані). · [ ] 👤 co-authorship + open-license MoU × 5 (паралельно UNI.4-14) → Master Collaboration Agreement (юрист, не патентний повірений) · [ ] 🔗 після UNI.1/8/9/12/13

#### BIZ.16 — Naming model: codename «Gaia 2.0» vs trademark «GaiaNexus»
- **P3** · 👤 · → `08_01 §2`
- Проєкт всюди вживає codename/версію «Gaia 2.0»; founder обрав ™ «GaiaNexus» (сама trademark-заявка — UNI.3/UNI.15). **Відкрите founder-рішення:** модель найменування — rename project-wide чи codename(Gaia 2.0)+brand(GaiaNexus)-split. Масове перейменування **відкладене до рішення** (інакше One-Home cross-ref sweep довелося б робити двічі). · [ ] 👤 рішення founder про модель → (якщо rename) One-Home sweep `Gaia 2.0`↔`GaiaNexus` по docs+code

#### 🌿 BIZ.12 — Horizon Europe CLUSTER 6 заявка (Biodiversity Monitoring, Mongabay pivot)
- **P1** · 👤 · → `08_01 Стаття 24a`, `03_03 §10`
- Horizon CL6 Biodiversity Monitoring (2-6 М€, 36-48 міс); SilkenNet = єдиний планетарний D-MRV з micro-acoustic біорізноманіттям. Submission прив'язати до acceptance Статті 24a → "published research". · [ ] 👤 identify call (HORIZON-CL6-*-BIODIV) → consortium (SilkenNet coord + ЧНУ/ЧДТУ/біо-хаб + 1-2 EU: Linköping/CSIC) → submit при acceptance 24a · [ ] 🔗 E.59/FW.4-EXT (5-class TinyML) + UNI.13a (Soundscape Library)

## 🔀 Cross-cutting · Doc-drift (DOC-T) — tracker doc↔firmware↔backend reconciliation

Потребують узгодження між docs, firmware та backend. **Не блокери виконання, але блокери для аудиту і онбордингу.**

> ✅ **DOC.N namespace розведено (2026-06-03):** раніше `DOC.N` означав ТРИ різні речі → колізії (DOC.2/5/9/10/11). Тепер три окремі префікси, кожен у своєму домі:
> - **`DOC-T.N`** — цей tracker (doc↔firmware↔backend doc-drift TODO, 00_07; таблиця нижче).
> - **`DOC-R.N`** — code↔doc divergence registry ([`04_02 §11`](04_02_Business_Logic_and_Services) + `04_01 §12` дзеркало).
> - **`DOC.N`** (bare) — canon-block SSOT-home теги **всередині** канон-доків (`03_01`/`03_04`/`04_04`/`05_02`…); numbers **load-bearing** у GitHub anchor-слагах (`-docN`, на які лінкуються інші доки), тож заморожені на місці. `DOC.8` (cleanup constraint) — спільний канон-constraint у 04_01+04_02, лишається `DOC.8`.
>
> Legacy one-off audit-мітки (`DOC.21`/`DOC.33`/`DOC.9 FIX`) знейтралізовано (не реєстрові ID). Inbound item-ref resolution (`NN_NN — DOC-T.N`) тепер гейтиться `tracker:check` (`00_06 §3`) — закрило dangling `06_02 → 00_07 DOC.5`.

| ID | Невідповідність | Документи / Файли | Дія | Статус |
|----|----------------|-------------------|-----|--------|
| DOC-T.9 | Documentation `02_03` §9.3 raніше використовувала 15 mA/50 ms для LoRa TX. Виправлено на 120 mA/100 ms (~39 мДж) per SX1262 datasheet. Firmware energy accounting **не верифіковано незалежно** | `02_03`, `firmware/soldier/main.c` | Лабораторне вимірювання поточного TX (HW.x) + cross-ref у `02_03` після верифікації | ⏸️ Заблоковано лаб-стендом |
| DOC-T.10 | Реструктуризація 05/07 (Фаза 3) — відкладені misplacement-рішення: `07_01 §11` Investor Q&A (pitch/diligence — дім 00_01 vs новий pitch-doc неоднозначний); `07_03 §5` Anchor Assembly + `§6` Virtual Prototyping (operational/field-ops дім, наразі grant-bootstrap контекст — не чистий misplacement) | `07_01`, `07_03` | Призначити operational/pitch-дім + перенести (рішення founder) | 🟡 Deferred |
| DOC-T.15 | **Volatile `*.c:N` line-refs** — drift кампанія уникає (`main.c` росте → ref вказує на ХИБНИЙ зміст; FW.4-трійка цілила в `DEFAULT_TTL` замість Run_Inference). **РЕЗОЛВНУТО 2026-06-10:** усі 30 рефів прибрано — `03_02 §0` const-table (bare `main.c`; попутно −3 мертві FW.53-константи `OTA_OVERHEAD`/`OTA_FULL_CHUNK_THRESH`/`MIN_OTA_ALIGNED`, +2 заміни `OTA_COAP_HEADER_SIZE`/`OTA_COAP_MIN_FRAME`), `02_05` ×5 + `03_03` ×1 → symbol-рефи, `05_02` BLOCKER-01 marked ✅ ЗАКРИТО (FW.1 видалив hardcoded-key), `.github/copilot-instructions.md` blocker-table синхронізовано → дзеркало CLAUDE.md §12. Guard `DocsLinter.source_line_ref_drift` → **HARD** (`00_06 §3`). | `docs/**` + `.github/**` (root CLAUDE.md поза скоупом) | done; guard HARD тримає лінію | ✅ Resolved 2026-06-10 |
| DOC-T.16 | **bare-§ після whole-doc-лінка** — форма `[NN_NN](Doc) §X` (канон = `[NN_NN §X](Doc)`, `00_06 §1`); **gate-TOLERATED**: ні `bare_section_ref` (лише code-span поза лінком), ні `crossref_label_form` (лише мітка href) його не ловлять. Campaign-wide — 13 лише в Module 01. | `docs/**` | NEW guard `section_ref_after_doclink` + 1-shot all-module normalize sweep (як crossref-кампанія R1–R3), **НЕ** piecemeal per-module | 🟡 Approved (founder 2026-06-13) |
| DOC-T.17 | **Volatile Ruby `*.rb:N`/`*.rake:N` line-refs** — той самий drift-клас, що DOC-T.15 (`.c/.h`), але регекс `\.[ch]:\d+` його не ловив → накопичувалися нечуто (`*.rb:N` указує на ХИБНИЙ рядок коли файл росте). **РЕЗОЛВНУТО 2026-06-13:** `SOURCE_LINE_REF_RE` розширено на alternation `\.(?:[ch]\|rb\|rake):\d+`; sweep усіх 10 рефів (7 доків: 03_03/04_02/04_04/05_02/06_02×2/06_03×2/07_01×2) → лишено file/class (кожен поряд уже цитує symbol/ENV/worker), усі 10 файлів верифіковано як наявні; +2 спеки. Guard **HARD** (`00_06 §3`). | `docs/**` + `.github/**` | done; guard HARD тримає лінію | ✅ Resolved 2026-06-13 |

#### DOC-T.2 — Canon↔canon de-dup (SSOT single-home) [#4, 2026-05-29]
- **P2** · 🤖 · → `00_00`
- Реструктуризація 00_07 (#4) виявила факти, дубльовані у багатьох канон-доках — порушення «одна річ — одне місце». Призначити ОДИН дім + замінити решту на 1-рядковий ref (значення лишається ТІЛЬКИ в home):

| Факт | Канон-дім | Дублюється у (→ має рефати дім) |
|---|---|---|
| AES-режими per-channel (ECB→CCM / CBC 256) | `03_05 §3.7` | ~20 доків (00_01/03_01/03_02/04_02/04_03/05_01/05_02 + 08_xx) — **найбільший дубль** |
| Lorenz константи (Z 2.0/45.0/29.0 · σ10 ρ28 β8÷3 · dt0.01 · 250 iter) | `03_04 §4.1` | ✅ **05_02 «Фаза 2» зроблено** (повна ре-декларація → SSOT-ref, 2026-05-29). Решта легітимні (НЕ дубль): 04_01 self-labeled mirror Rails-конст., 03_01 firmware-doc контекст, 04_02 service-impl, 08_xx академ. верифікація |
| Tokenomics rate 10 000 GP = 1 SCC | `05_03` | 05_01/07_01/07_02/03_03 |
| Carbon 2000 SCC = 1 tCO₂ (0.5 кг) | `05_03` + `07_01` коеф. | 00_01/07_01/07_02 |
| Slashing пороги stress 0.83 / slash 0.20 | `05_05 §3` + `04_02` (ContractHealthCheckService) | 05_03/07_01 |
| Insurance pool 100 000 SCC | `05_05 §4` + `05_03` (Dynamic Tax) | 04_02/05_03 |
| delta_t baseline 60 с | `03_04` (BASELINE_DELTA_T_S) | 03_01/04_02/05_02/01_03 |
| Gyroid пористість 65% (60-70%) | `01_01` | 01_02/02_01/07_02 + 08_xx |

- [x] 🤖 Замінити справжні ПОВНІ re-statements значення на 1-рядковий ref на home (значення — лише в home). **Зроблено:** ✅ Lorenz (05_02) — єдина справжня повна ре-декларація; решта = легітимний контекст (див. аудит нижче).
- [ ] 🤖 Розширити `tracker:check` на канон↔канон: детект hardcoded-значень поза home-доком (stretch — складно без AST доків; ⚠️ ризик false-positive на колізіях чисел, див. нижче).
- 📌 08_xx-академічні згадки часто легітимний контекст (не чистий дубль) — рефати, але не видаляти контекст.
- ✅ **Lorenz-pilot (2026-05-29):** аудит «14 доків» → справжню ПОВНУ ре-декларацію канон-блоку мала ЛИШЕ `05_02 «Фаза 2»` → SSOT-ref `03_04 §4.1` (11 значень верифіковано present у home ПЕРЕД стрипом, 0 loss; метод-логіка лишена). Решта — self-labeled mirror (`04_01`) / firmware-контекст (`03_01`) / service-impl (`04_02`) / академ. верифікація (`08_xx`) — НЕ чіпати.
- ✅ **Повний аудит DOC-T.2 (2026-05-29) — де-дуп завершено:** після Lorenz **driftable ПОВНИХ ре-декларацій більше не виявлено**. AES = контекстні згадки в кожному домен-доці (не відтворення per-channel таблиці) — home `03_05 §3.7`, не чіпати. Slashing-формула — поза home не ре-декларується. Tokenomics / carbon / insurance / gyroid — контекстні згадки одного значення (не spec-блок). ⚠️ **Blind value-de-dup НЕБЕЗПЕЧНИЙ:** `02_03 "65%"` = MPPT-фракція VOC (BQ25570 R_OC divider), а НЕ gyroid-пористість — **колізія чисел**; масовий ref за значенням зіпсував би непов'язаний power-electronics факт. **Висновок:** високоцінний/безпечний де-дуп закрито; решта — легітимний контекст, рефати лише по-кейсу за явним запитом + per-fact верифікацією.

## 📌 Backlog · Додаткові знахідки (не блокери)

| # | Знахідка | Джерело | Примітка |
|---|----------|---------|----------|
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | Дизайн + реалізація |
| E.5 | CoAP listener Ruby — масштабується до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.7 | dClimate mock mode — потрібна реальна інтеграція для Production | `05_01` | Пов'язано з S3.2 |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | R&D partnership |
| E.11 | CE/FCC/EMC/IP68 certification roadmap не розпочато | `08_02` | Потребує Косенюк (RF) |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.13 | Petri Net model of Rails monolith — deadlock-free verification at 10k concurrent IoT | `08_02` | Потребує Супруненко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | Потребує Косенюк |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data | `08_03` | Blocked by UNI.1-3 |
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) — planned post-TRL 6 | `04_02` | Post-TRL 6 |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation | Legacy | Post-TRL 6, потребує E.10 (Kalman) |
| E.27 | Chaos Engineering: Chaos Mesh для Akash або kill-scripts для Kamal | Legacy | Post-TRL 7, production hardening |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.30 | InsightGenerator: кліматичні базлайни per region | `04_02` | Post-TRL 7 |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice | `03_03` | Post-TRL 8 |
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.35, EVM cancun, optimizer 200 runs, CI/production profiles. 6 test suites (`contracts/test/*.t.sol`; к-сть — `forge test`). Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски: R ≥ 0.2 мм для зняття напружень у PEEK + **annular barbs (h=0.3mm)** на Zone 1 та Zone 3 контактних поверхнях для PEEK creep mechanical lock (`01_01 §4.3`, HW.26) | `01_01` | Включити у nTop (HW.1, HW.26) |
| E.39 | **EBFC Gen 2.0 (BASELINE, REWRITTEN 2026-05-22):** dgrFAD-GDH (deglycosylated) + Laccase/ZIF-nanozyme + Genipin-Chitosan-CNC матриця + Nafion-g-PSBMA цвітеріонна мембрана. 20–25 років. Gen 1.0 (GOx+CAT+GA+PEG) виключена як нежиттєздатна. | `01_03` §1–3 | ЧНУ lab testing |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| E.41 | **Fire events delayed 48h** via dClimate satellite obscuration — **⚠️ life-safety risk**. Mitigation: Forester Guild as Fallback Oracle (E.20) + immediate local broadcast via panic TX (не чекати satellite clearance при chainsaw detection). **Пріоритет: P1** (не відкладати на Post-TRL 6) | `04_02`, `05_01` | P1: interim emergency fallback |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| E.50 | **Edge fuzzy_distance dedup function** на STM32WLE5JC: <1 мс CPU, <128 байт RAM, ціль — 30-40% TX зниження за рахунок suppression near-duplicate пакетів | `08_02` §1B (Ярмілко) | Post-TRL 7 (R&D — Ярмілко) |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1B (Порубльов) | Post-TRL 6 (Порубльов, ЧНУ) |
| E.52 | **GA-оптимізація ваг `silken_forest.marshal`** ML моделі на Akash GPU кластері — генетичний алгоритм для `InsightGeneratorService` stress_index класифікації | `08_02` §1B (Любченко) | Post-TRL 7 |
| E.53 | **VNA-вимір SMD-антени під PEEK радомом** — VSWR <1.5 на 868 МГц для 3-5 варіантів товщини PEEK (1.5/2.0/2.5 мм) у вологому/сухому стані + **3D Keep-Out з Ti-фланцем нижче** (Z-clearance 5/8/12 мм, з/без overhang за периметр Ti). Лабораторна задача (cross-ref UNI.10 ChDTU Гончаров, нова вимога `02_01 §5.3` revised) | `08_02` §2 (Гончаров) + `02_01` | P1, blocked by HW.17 + UNI.10 |
| E.54 | **SOP документи для 7 типів EwsAlert** — стандартизовані інструкції UA+EN: severe_drought, insect_epidemic, vandalism_breach, fire_detected, seismic_anomaly, system_fault, entropy_anomaly. Інтеграція як inline UI у Phlex (cross-ref ARCH.31) | `08_02 §3` | P1, joint with ChIPB-NUTSU (UNI.12) |
| E.55 | **Multi-party NDA + IP framework** для 5-сторонньої академічної співпраці (ChNU + ChDTU + ChIPB + ChMA + СЄУ + Silken Net) — base-line для всіх UNI.x публікацій | `08_03`, `08_02 §3`, `08_02 §4`, `08_02 §5` | P1, cross-ref BIZ.10 |
| 🌿 E.59 | **Mongabay biodiversity pivot — acoustic D-MRV** — стратегічний pivot Silken Net від карбонового MRV до повноцінного D-MRV біорізноманіття після Delgado et al. (Nicoya Peninsula, 119 ділянок, 16 000 год аудіо; *Mongabay News*, травень 2026). Включає: (1) FW.4-EXT 5-class TinyML модель з класом `fauna_activity`; (2) FW.25 DSP log-mel з P1→P0; (3) UNI.11+UNI.13a Cherkasy Soundscape Library (ЧДТУ ПМКТ + ЧНУ Біо-хаб); (4) 08_02 §1 Macro-Micro verification (Бушин CNN + fauna feature); (5) 08_02 §1 NSGA-II multi-objective GA (Любченко); (6) 08_01 Стаття 24a co-authored Q1 publication; (7) Horizon Europe CLUSTER 6 (Biodiversity Monitoring) grant vector; (8) AiInsight#biodiversity_trend → ForestNFT metadata "biodiversity_score"; (9) ринкова диференціація — defensible moat проти Pachama/Sylvera/NCX (тільки Silken Net має micro-acoustic verification layer) | `03_03` §10 + `08_01` §1+§2 + `08_02` §1B + `08_01` Стаття 24a | **P1 strategic** — координує FW.4-EXT, FW.25, UNI.11, UNI.13a |

## 📌 Backlog · Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Conductor nodes (Hub Trees, formerly "Sergeant"; H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard, UNFCCC) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining (monthly cycle, A/B testing) — **обмежено L2 Conductors / L3 Queens; ніколи на L1 Soldier** (compute budget paradox, [`00_08 §1.2`](00_08_Beyond_TRL9_Planetary_Roadmap) revised 2026-05-16: 0.47F supercap + STOP2 300 nA не витримує жодного gradient epoch'у) | `04_02`, [`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap) | Post-TRL 7 |
| ARCH.7 | Edge Data Fusion: transmit 2-byte λ-exponent замість 16-byte Z payload | `00_01` | Post-TRL 7 |
| ARCH.8 | Event-Triggered Reporting: heartbeat 1/day normal, continuous on anomaly | `00_01` | Post-TRL 6 |
| ARCH.9 | Network Sharding: isolate anomalous clusters to prevent storm propagation | `00_01` | Post-TRL 7 |
| ARCH.10 | Queen-to-Queen Backhaul Mesh: LoRa SF12 inter-Queen relay (Starlink fallback) | `00_01` | Post-TRL 8 |
| ARCH.11 | Energy-Aware Routing: route metric = f(hop_count, remaining_energy, bio_potential) | `00_01` | Post-TRL 7 |
| ARCH.12 | Merkle Tree state root (замість flat SHA-256) для partial verification / ISO 14064 | `05_04` | TRL 9 |
| ARCH.13 | EigenLayer AVS як альтернатива direct L1 write (~$0.01/week vs $5-15/week) | `05_04` | Research |
| ARCH.14 | Read-Only PostgreSQL Replicas для analytics та Oracle queries | `00_01`, `06_01` | Post-TRL 7 |
| ARCH.16 | Mobile app для foresters (Phase 2 roadmap) | `00_01 §4` | Post-TRL 7 |
| ARCH.17 | Bonding Curves для dynamic SCC pricing | `05_03` | TRL 9+ |
| ARCH.18 | Детерміністична Fixed-Point арифметика (Integer Math): для досягнення побітової ідентичності розрахунків (consensus) між STM32 (Soldier) та GCP/Akash (Backend), необхідно відмовитись від IEEE 754 Floating-Point. Всі вхідні дані мають множитись на 10⁶ (або 10⁸) і розраховуватись у 64-бітних цілих числах (`int64_t` у C, `Integer` у Ruby). Це усуне апаратний drift при розрахунку Атрактора Лоренца. Потребує повного переписування математики в прошивці з урахуванням ризиків переповнення буферів (overflows) під час множення великих чисел. | `03_04`, `05_02` | Post-TRL 7 |
| ARCH.19 | BSP-кластеризація IoT-графу для заміни flat TTL-mesh при масштабуванні: Binary Space Partitioning дерево на основі географічних координат Queen. Зменшує broadcast collisions та енергоспоживання. Кожна Queen знає тільки своїх сусідів | `08_02` | Post-TRL 7 |
| ARCH.20 | Petri Net PN-модель Rails моноліту: формальна верифікація відсутності deadlock при 10,000 concurrent IoT connections. Sidekiq + Puma + PostgreSQL modeling. Конволюційний метод для зменшення state space explosion у 10-100 разів | `08_02` | R&D (Супруненко, ЧНУ) |
| ARCH.22 | Arithmetic compression для LoRa payload: lambda-exponent (2 байти) замість повного Z (16 байт). Потенційна економія ~34% TX часу (21→~14 bytes). Event-Triggered Reporting: "мовчання = здоров'я" — 24× зниження трафіку. **DCI-precondition (нот.6):** λ послаблює anti-fraud (λ many-to-one → device-λ vs server-λ слабший за точний Z-cross-check) → потребує full-Z challenge sampling / Z-sentinel перед вмиканням | `08_02`, `00_01`, `00_08 §2.3` | Post-TRL 7 |
| ARCH.23 | Multi-Attribute Utility Function для автономного рішення TX на MCU: оцінка важливості поточного пакету (Vcap, delta_t, acoustic, bio_status) — відправляти лише якщо utility > threshold. Оцінка: 30-40% зниження TX | `08_02` | Post-TRL 7 (Ярмілко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.25 | Gyroid geometric validation scripts: Python/C++ верифікація 65% пористості per-slice, topological integrity mesh, capillary channel connectivity via BFS (breadth-first search). Запускається після кожного nTop build для запобігання помилкам DMLS | `08_02` | Before DMLS factory order |
| ARCH.26 | **Синхронні Вікна (TDMA) та CAD Preamble Detection — вирішення Проблеми Рандеву для mesh relay.** Поточна архітектура: Queen always-on (`Radio.Rx(LORA_RX_INFINITE)`), Soldier має лише 600 мс post-TX RX window — mesh relay між Солдатами стохастичний і ненадійний за межами прямої видимості Queen. **Три рівні рішення:** (L1) Queen always-on ✅ реалізовано; (L2) TDMA Sync Windows — Queen транслює beacon з точним часом (NTP через LTE), Солдати синхронізують RTC, кожні 15 хвилин координоване 2-секундне RX-вікно для mesh relay. Залежить від FW.20 (LoRa Time Sync); (L3) CAD — SX1262 `Radio.StartCad()` дозволяє wake на ~2 мс/секунду для детекції LoRa-преамбули без повного RX. Критично для PANIC mode: Солдат при chainsaw detection посилає довгу преамбулу (~1 сек), сусідні Провідники ловлять через CAD навіть між TDMA-вікнами. **Firmware зміни:** Soldier: CAD periodic wakeup (LPTIM або RTC sub-second alarm), beacon RX handler, RTC sync logic. Queen: beacon TX (periodic broadcast з UTC timestamp + network schedule). **Енергобюджет:** CAD wake 1/сек × 2 мс × 4.5 мА = ~9 µA середнє — допустимо для Провідників (дерева з високим vcap), неприйнятно для слабких Солдатів. Рольова диференціація: Солдат (TX-only, глухий) vs Провідник (TX+CAD, еліта з надлишком енергії). | `00_01`, `03_01`, `03_02` | Post-TRL 6 (Firmware + Queen beacon) |
| ARCH.43 | **Per-device-key ↔ opaque-relay/demux суперечність + стеля «N дерев через одну Queen».** Релей чужого пакета (`soldier/main.c` Сценарій Б: decrypt власним ключем → `TTL--` → re-encrypt) і власне demux Queen (`queen/main.c` decrypt **перед** читанням DID) опираються на **спільний** LoRa-ключ, але канон вимагає **per-device** ключ (`03_05 §3.4`, ізоляція «злам одного ≠ розкриття сусідів») + DID лежить **усередині** шифроблоку (немає cleartext air-header — Soldier шле рівно 16 B). За справжніх per-device ключів Солдат B розшифровує пакет A у сміття → релеїть сміття; Queen/backend не знають, яким ключем демультиплексувати relayed-фрейм. **Очікування «>1000 дерев пересилають через Queen, навіть недосяжні» НЕ підтримується** на 4 незалежних рівнях: (1) крипто/demux — цей пункт; (2) `DEFAULT_TTL=3` → ≤3 хопи ≈ ≤~450–600 м reach; (3) один relay-буфер (1×16 B/пробудження) + store-and-forward на наступному wake → нема агрегації, втрати/латентність множаться; (4) Queen CIFO ~100 baseline/~200 roadmap, overflow за ~30 хв при 100 без Starlink (`02_05 §2.1`) — не 1000. **Резолюція:** або cleartext addressing-шар (LoRaWAN-style DevAddr у відкритому + per-device session-key) для співіснування opaque-relay з per-device payload; або прийняти star-only на поточному TRL (mesh = страховка для одиничних stragglers у межах TTL, **не** механізм масштабування). Масштаб до тисяч = більше Queen (ARCH.1 fractal/L2 Conductor, ARCH.10 Q2Q). Залежить від ARCH.26 (рандеву) | `03_01`, `03_02`, `03_05`, `06_08` | Post-TRL 6 (addressing-шар; cross-ref ARCH.26) |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1B (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1B (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_02 §3` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `00_04` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1B (Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

## 🗄️ Архів закритих пунктів (мігровано в канон)

> Повністю завершені пункти, винесені з активного трекера 2026-05-28. Знання — у канонічних доках (стовпець «Канон»); повна історія — у git. Тримаємо лише вказівник для крос-реф цілісності (CLAUDE.md та живі пункти посилаються на ці ID).

| ID | Пункт | Канон |
|----|-------|-------|
| ARCH.42 | AES-128 LoRa — DECIDED (Variant B); SE-частина ATECC→**SE050** (true-DePIN — SE050-MIGRATION) | `03_05 §3.7` |
| SEC.6 | SE = **SE050** — ✅ RESOLVED 2026-06-07 (true-DePIN: голос дерева потребує non-extractable Ed25519 → SE050, не ATECC; soft-freeze DNP, populate post-FW.2). Деталі + усі residuals → SE050-MIGRATION | `03_05 §3.7`, §3.4 |
| SEC.10 | Emergency-TX anti-replay frame counter (DR0 packing) | `03_02`, `03_01 §2` |
| SEC.11 | Lorenz Seed Provenance (DCI hardening, K_seed HKDF) | `03_04`, `03_05 §3.4а`, `04_02`, `05_02` |
| SEC.7 | OTA image authentication — **дубль FW.23** (HMAC-SHA256 dual-gate: `OtaHmacKeyService` + `OtaPackagerService` 0x9B trailer + Queen relay + Soldier dual-gate, live-compute ✅ зашито 2026-06-11). Residuals (bench K_ota Protected Flash; ECDSA P-256 post-TRL7 migration path) тримає FW.23 — One-Home | `03_05 §3.4б` (= FW.23) |
| SEC.8 | ECB Restoration Race (Queen): restore CRYP→ECB+128B+LoRa-key після CoAP-CBC flush/downlink; `HAL_CRYP_Init` fail → RCC force-reset → `NVIC_SystemReset` (`firmware/queen/main.c`). Resolved-фікс, orphan-ID — cited by SEC.12 + RUNBOOK, бракувало archive-рядка (додано 2026-06-09) | `03_05` (розділ «ECB Restoration Race») |
| SEC.5 | Chainlink oracle-callback HMAC fail-fast: `WEB3_STRICT_MODE=true` + порожній `CHAINLINK_HMAC_SECRET` → `SecurityError` (захищає `/oracle_callbacks` від forge `oracle_status_fulfilled?` → неавторизований mint). Guard `verify_chainlink_signature!` (`oracle_callbacks_controller.rb`) + RSpec. Resolved, orphan-ID — бракувало archive-рядка (ops: provision secret pre-mainnet → S1.1/`06_04`; додано 2026-06-09) | `04_03 §5.9` |
| FW.1 | Hardcoded identical AES-key → per-device HKDF + `Load_AES_Key()` (Protected Flash `FLASH_KEY_ADDR`, magic `KEYL` + zero-key guard → refuse-boot без provisioning) — firmware CLOSED 2026-05-02 (soldier+queen `main.c` + host-тести `test_load_key_*`). Per-device ізоляція реальна з FW.2 CCM (ECB-транзит = спільний ключ, §3.1). Bench-residuals — власні items: RDP L2 → SEC.2 · factory SWD-flash → SEC.3 · weak-key boot-guard → SEC.9 | `03_05 §3.1`, §3.4а |
| FW.5 | ~~Lorenz β-пертурбація від delta_t/vcap~~ → **РЕВЕРСОВАНО [E.63]** (delta_t → growth_points напряму) | `03_04 §4.3`, E.63 |
| FW.7 | Backend Lorenz `Attractor` BigDecimal→**Float** (IEEE 754 double) — bit-identical Z з firmware mruby (BigDecimal `round(18)`/iter давав drift після 250 ітерацій); DCI parity. ✅ Закрито (BLOCKER-02, 2026-05-02; `app/services/silken_net/attractor.rb`; §5 порівняльна таблиця Firmware↔Backend). ARM↔x86 silicon-confirm → FW.55 (QEMU bit-parity CI-gated; той самий дамп закриває FW.7/FW.19 на платі) | `03_04 §5`, `05_02` |
| FW.9 | Queen CoAP batch-delivery retry-loop (`COAP_MAX_RETRIES`, `COAP_CONV_BUDGET_MS` < IWDG) у flush-sequence; ✅ Реалізовано (`firmware/queen/main.c`; host: conversation-fail `test_at_engine.c` + fail→retry→no-loss `test_fw51_*`). Кеш-on-delivery → FW.51; Flash overflow + exp-backoff → ARCH.35. Orphan-ID (cited 06_08/04_06/03_02 §4, archive-рядка бракувало 2026-06-09) | `03_02 §4`, `06_08` |
| FW.18 | TinyML confidence threshold (RTC DR13/14 dual-zone) | `03_03`, `03_01 §2`, `04_06` |
| FW.19 | mruby `build_config.rb` double-pin: НЕ `MRB_USE_FLOAT32` + NO WORD/NAN boxing → `mrb_float`=double inline (float32 → ±5-10 units на Z → bio_status зсув; word-boxing → RFloat heap-thrash на ~KB heap). ✅ Канонізовано; ⚠️ (2026-06-11, FW.55-знахідка ④) теза «дефолт = NO_BOXING» була ХИБНА для mruby 4.0 (дефолт `MRB_WORD_BOXING` — на ARM32 інваріант тихо порушувався, ~20.5КБ RFloat-транзієнту/виклик) → пін тепер ЯВНИЙ (`MRB_NO_BOXING` у `SILKEN_MIN_GEMS` + `MRB_DEFS`-дзеркала), а CI-enforcement = фіт-гейт QEMU-ноги (word-boxing на 32-bit рве heap-бюджет миттєво). ARM↔x86 silicon-confirm → FW.55 (спільний дамп) | `03_01 §12.4`, `03_04 §5` |
| FW.29 | Panic vs saturated acoustic disambiguation (PANIC_FLAG_BIT) | `03_03 §5.3` |
| FW.29-PACK | StatusByte layout collision fix (5-bit growth_points) | `03_01 §11.3`, `03_04 §4.3-5.2`, `05_02` |
| FW.30 | SEC.11 C-bridge: warm/cold → 7-arg `calculate_state` + `Load_Lorenz_Seed` (K_seed Flash `LSED`) + `Derive_Cold_Start_State` (pure-C HMAC-SHA256 `silken_sha256.h`/`lorenz_seed.h`, byte-parity vs OpenSSL — mbedTLS TODO закрито) + args[5..6] EMA→`growth_points` [E.63]; 11 host-тестів | `03_04 §6`, `03_05 §3.4а` |
| FW.21 | Soldier edge-aggregation EMA (delta_t/vcap, α=0.2 integer fixed-point) — RTC DR10 + DR12-packed (звільнило DR11 → 3-й mesh-слот); згладжує метаболічний сигнал [E.63] + меншає LoRa-трафік. ✅ Реалізовано (`firmware/soldier/main.c` `EMA_*` + host-тести). Kalman-апгрейд (noise ±8%→±1.2%) → E.10 (академічний, Косенюк) | `03_01 §13` |
| FW.22 | acoustic_events overflow: тип `uint8_t` + saturating increment (cap 255 — без uint16→uint8 ambiguity), DR0-packed (SEC.10+FW.22) + backend overflow-warning + Prometheus counter + host-тести (saturating/atomic-snapshot); 2-байт payload — optional far-future (лише якщо FW.2 CCM repack потребує >255/cycle) | `03_03 §7.1`, `03_01 §2` |
| FW.51 | Queen flush: пакування лише рахує (`packed_count`); CIFO-слоти звільняються ЛИШЕ при `send_success` (доставка, не транспорт-OK) → провал retry (LTE-діра) не губить годину телеметрії; dedup оновлює held DID; caller свідомо energy-conservative (без retry-шторму) | `03_02 §3/§4` |
| FW.53 | OTA wire-contract integrity: backend CRC32-trailer (Soldier integrity-gate) + явний `len` + CRC16-verify (Queen більше не вгадує довжину з CBC-pad → не обрізає 1..16 байт чанка); `OtaPackagerService` wire-потік; campaign-change reset (мертва кампанія не блокує живу) | `03_01 §4.6`, `04_02`, `03_02 §5` |
| FW.57 | DCI-parity latent surfaces: **F2** — Lorenz/DCI бере RAW wire-temp (не calibrated `temperature_c`; offset 5°C → server_z ~16u drift → false-fraud) для Z + `anomaly_ceiling`/`check_z_divergence!`/`try_time_sync_recovery`; calibrated лишається display/fire (`alert_dispatch` recover = `temp_c − offset`); raw стрипиться перед persist. **F4** — рукописну 3-тю Lorenz-kernel копію усунено, `attractor_spec` co-executes реальний `bio_contract.rb` у subprocess (`contract_runner.rb`, 200-fuzz). GP-parity → FW.2 | `04_02`, `03_04` |
| FW.47 | Repo-wide vendor/dependency pin-policy: firmware-native → submodule@tag (`extern/<dep>`), contracts npm + committed lock, Python `in_silico` → committed `conda-lock.yml` + CI `lock_sync` drift-gate (`in_silico_smoke.yml`); `ml` deferred (parity-self-guard). Фізичний вендоринг milestone-gated → FW.30/FW.46/FW.4 | `03_01 §12.5` |
| FW.48 | cppcheck static-analysis gate ("ruff/rubocop for C") — owned firmware C (`soldier`/`queen`/`common`/`sim`); job `firmware_lint` (ci.yml) + єдиний DRY-runner `cppcheck.sh` + Cortex-M4 платформа (`char` unsigned); gating `warning,performance,portability,style` exhaustive; `firmware/test/` свідомо виключено; MISRA advisory (gate-escalation optional far-future) | `03_01 §12.6` |
| S6.12 | TokenomicsEvaluator oracle-guards audit (KYC all-paths) | `04_02`, `05_02` |
| BIZ.4 | DAO Governance (SilkenGovernor + Timelock) | `05_06`, `07_01` |
| BIZ.5 | Патентна заявка → **ВІДХИЛЕНО** (founder 2026-06-07): defensive-publication-first замість патенту-монополії — ядро як prior art (вільне + анти-захоплення), без повіреного/PCT; SilkenNet тримає лише ™ / governance / секрети. Виконання → активні UNI.3 + BIZ.10 | `08_01 §2` |
| PUMA-RACK-1 | Idempotency write off response path (`rack.response_finished`) | `06_05 §7` |
| TRL Матриця | Per-module TRL (мігровано з 00_07) | `00_03 §1` |
| E.8 / DIFF.7 | SNR tiebreaker у Queen CIFO eviction | `03_02`, `04_06` |
| E.35 | Flash-loan defense (SilkenGovernor governance params) | `05_06` |
| E.42 | TelemetryLog cleanup `dispatched` guard | `04_02` |
| E.47 | Solana RPC production guard (raise on missing ENV) | `05_01` |
| E.49 | Celo RPC fallback cascade (ResilientClient) | `04_02`, `05_01` |
| E.62 | Dead `clusters.active_firmware_id` assoc removed | `04_01` |
| ARCH.39 | Fauna acoustic energy budget — арифм.+системна корекція (doc-fix) | `03_03 §10.x` |
| OPS.9 | CI/CD workflow hardening — 00_05 spec ↔ .github sync | `00_05 §2.2-2.6` |
| ARCH.21 | Brownout PVD → Lorenz state save в RTC | `03_01`, `08_02` |
| ARCH.28 | RTC Backup Domain allocation policy | `03_01 §2` |
| ARCH.27 | Node-role flag (Soldier/Provisioner, Flash magic) | `03_01 §1.11` |
| S2.5 | PartitionMaintenanceWorker failure alert (counter + Sentry rescue + Grafana P0) | `06_03 §2.8` |
| OBS.1 | Observability: Grafana Alloy → Grafana Cloud SaaS (self-hosted Prometheus не потрібен) | `06_03` |
| SEC.13 | peaq_did_compromised mint-skip guard + emergency revocation runbook | `06_04 §5.4` |
| DOC-T.13 | SSOT 360 R3–R4: docs:graph ref-graph + #anchor HARD-gate + dup-guard table-rows | `00_06 §3` |
| DOC-T.11 | 05/07 реструктуризація (Фази 1-2): slashing `00_01 §6` → `05_05`; governance `05_03` → `05_06` — нові канон-доми + навігаційні stubs; cross-refs re-pointed | `05_05`, `05_06` |
| DOC-T.12 | Taxonomy v3 P4: дисолюція Module 08 (7→3 доки) — `08_01` Joint Pubs/IP · `08_02` Academic Registry (5 ВНЗ, relationship-шар, інж-субстанція реферить Tier I) · `08_03` External; mesh-математика → `06_08`; ~260 inbound refs swept | `08_01`, `08_02`, `08_03`, `06_08` |
| DOC-T.14 | 03_01↔03_02 semantic overlap зведено: Queen RAM → `03_02 §9`, test-matrix → `03_02 §11`, AES-таблиця → `03_05 §6`; residual health-sentinel byte-map dup + stale 6-біт GP-cap теж усунено (03_01 → ref `03_02 §7`, cement 2026-06-08) | `03_02`, `03_05 §6` |
| DOC-T.1 | AES master-key doc contradiction («навмисно не публікується» vs «перші 4 слова = FIPS-197 Appendix B») — РЕЗОЛВНУТО (re-audit 2026-06-09): §3.1 тепер когерентний (FW.1 hardcoded-key removed → per-device HKDF + Protected Flash) + §3.1а WeakKeyDetector boot-guard. Оригінальна дія «видалити test-vector згадку» **суперседнута**: історична FIPS-197-нота лишена СВІДОМО як stop-and-escalate сигнал для аудиторів pre-FW.1 прошивки. Doc-side key-agnostic → НЕ залежав від SEC.9 key-replace (хибний «blocked»); stale line-refs (panic-map range + `main.c` AES-key block=removed) знято | `03_05 §3.1`, §3.1а |
| E.45 | SCC/SFC subgraph zero-address fail-fast guard (`subgraph/validate_addresses.sh`); real-address swap → S3.5 | `05_03` |
| OPS.5 | Projects V2 TRL field schema (1-9 + Readiness Horizon SRL/MRL; `lib/github_bootstrap.rb`); live-board bootstrap-run → OPS.6 | `00_05 §1.1` |
| E.61 | Solana micro-rewards batch payouts (Kredis-акумуляція → `transferChecked`, годинний cron, поріг-gated) | `05_01 §8`, `04_02 §10` |
| E.56 | DSP preprocessing для TinyML — RESOLVED: Path B log-mel (НЕ raw/MFCC); front-end `Compute_LogMel` | `03_03 §3.2/§3.4` |
| E.57 | TENSOR_ARENA budget — **дубль, не окремий трек** (НЕ resolved): робота й мітигація живуть в активному FW.26 | `03_03 §4.3` (active FW.26) |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Для нових знахідок — додавати у відповідну секцію + посилання на джерело docs
> 4. Раз на квартал — повний docs audit з оновленням «Top-Critical Path» секції зверху

