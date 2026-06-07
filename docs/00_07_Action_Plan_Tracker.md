# 00_07: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати **ТІЛЬКИ незавершене** — кожен пункт як **тонкий вказівник**: `ID · пріоритет · виконавець` + 1 рядок + **→ канон-реф**. Повний опис «як має бути» живе в каноні (`00_00`→`08_02 §5`), описаний **в одному місці**; 00_07 на нього посилається, **не дублює**.

**Правило одного місця (DRY):** редагуєш канон → онови залежні пункти 00_07 (за рефами); закрив пункт → онови канон + познач тут (✅ → **§🗄️ Архів**, вказівник ID→канон). Так апдейт робиться в одному місці, а референси ведуть, де ще синхронізувати.

**Структура:** **🚦 Dashboard** (що робити зараз, за виконавцем) → **§00–§08 модуль-секції** (реєстр незробленого; **номер секції = канон-модуль першого рефа** — enforced `tracker:check` section-home guard) → **🔀 Cross-cutting** / **📌 Backlog** → **🗄️ Архів**. Документ — живий операційний інструмент.

---

> **Розмітка виконавців:**
> - 🤖 **Код/аналіз** — Copilot може виконати самостійно (код, firmware, розрахунок, документ, тест)
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
- `FW.1`+`SEC.3` **P0** — provisioning ✅; залишається real `STM32_Programmer_CLI` на STM32WLE5JC bench
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
- `FW.2` **P0** — AES-128-CCM (backend-parser ✅; firmware emit + `CRYP_AES_CCM` verify → STM32 bench). Закриває ECB→CCM, MIC, `SEC.10` panic auth, `FW.29`. FC/nonce/cold-boot SSOT → `03_05` (📐 КАНОНІЧНЕ ДЖЕРЕЛО). NB: `FW.23` OTA auth — окремий HMAC-механізм, уже закрито (§3.4б); FW.2 його **не** закриває
- Multi-signal slashing de-risk (`05_05 §7`) — код ✅: усі 3 прямі сигнали в `InsightGeneratorService`-евристиці (VPD-gate + sap-term + acoustic/cavitation-term; inert, ENV-calibration-gated; sap+acoustic через max() не суму). Активація → ground-truth калібрування ваг (`05_05 §8`) + ML-retrain (vpd-фіча) + firmware VPD (`HW.32`). Багатше on-device acoustic-джерело → TinyML unblock (`Run_Inference` закоментована, §03)
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
- ✅ `lib/github_bootstrap.rb` (`FIELDS` SSOT 11 полів, idempotent GraphQL diff, rake `github:bootstrap`, 16 specs). · [ ] 👤 запустити `bin/bootstrap_github.sh` проти живого Projects V2 при setup/fork

## §01–§02 · Hardware & Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.32 — BME280 environmental sensing + VPD confounder [ADR `02_01 §3.4`]
- **P1** · 🤖+👤 · → `02_01 §3.4`, `07_02 §1.3`
- BME280 (t°/RH/тиск, I2C за TPS22860) → VPD confounder (False-Slashing kill, `05_05 §6/§7`) + клімат-оракул (`07_01`). DCI-guard: VPD НЕ в Lorenz-Z. ✅ docs (02_01/00_01/08_02/07_02/02_03/07_01) + `03_01` SENSE+packet (byte 14 VPD-індекс) + TelemetryLog cols (structure.sql, recreate+seed). · [x] 🤖 VPD-gate + sap-term реалізовано (inert, ENV-calibration-gated; `04_02` / `05_05 §7`; активація `05_05 §8`) · [ ] 👤 bench (I2C bring-up, gate-timing, VPD-калібрування) + PTFE-мембрана механіка (`02_02`)

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
> **Стратегія:** PicoGK (open-source SDF engine від LEAP 71) + C# як AI-агент-сумісна альтернатива nTop GUI. Усуває "GUI-blindness" Cursor/Claude/Copilot та робить геометрію Git-friendly. Не замінює nTop одразу — паралельний evaluation track.
- [ ] 👤 **Setup C# проєкту:** Visual Studio 2022 або JetBrains Rider, .NET 7+, console project
- [ ] 👤 **Build PicoGK з GitHub** (`github.com/leap71/PicoGK`) → підключити як бібліотеку
- [ ] 👤 **Promt template для Claude/Copilot:** Senior C# інженер пише `Zone1Anode` клас з SDF гіроїда (формула sin(x)cos(y)+sin(y)cos(z)+sin(z)cos(x)=0), параметризованим діаметром/пор/wall thickness
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
- [ ] 👤 **Joint Q1-publication з ЧНУ Мінаєвим:** "In Silico Design of Long-Lived Enzymatic Bio-Fuel Cells for Tree-Integrated Energy Harvesting" — `08_03` Стаття 28. **Текст draft-complete** (`paper/`: Methods/Results/Tables/Discussion/Abstract/Intro-40-refs/Fig2-cartoon, усі DOI ✅). Лишилось 👤: · [ ] 👤 **Fig 1** graphical-abstract (BioRender; code-schematic draft є) + **TOC-графіка** · [ ] 👤 фіналізувати cover letter (draft є) · [ ] 🛑 **сабміт ТІЛЬКИ після patent filing** (UNI.3 — embargo)

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
- [ ] 👤 Якщо потрібно — замінити R_OC1/R_OC2 (звіряти з TI Figure 42 та `02_03 §4.А` SSOT Convention block)
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

#### FW.1 — Hardcoded AES-256 Key
- **P0** · 👤 · → `03_05`, `03_01`
- ✅ per-device HKDF provisioning + Factory Flashing (раніше: один ключ на всіх → компрометація мережі). · [ ] 👤 RDP Level 2 activation як final step (bench)

#### FW.2 — AES-128-ECB → AES-128-CCM (24B packet) [post-ARCH.42]
- **P0** · 🤖 · → `03_05 §3.2`
- ✅ дизайн 24B AES-128-CCM + backend парсер + firmware freeze-contract emit/decrypt + host-тести (golden-vector parity з `Cryptography::LoraCcm`/OpenSSL — складання+tamper-семантика, **не** залізна крипта); FC у RTC DR15. **Канонічна FC/nonce/cold-boot політика — `03_05` (📐 КАНОНІЧНЕ ДЖЕРЕЛО), єдине місце.** Cold-boot nonce-унікальність імовірнісна (MEDIUM, ~N/2²⁴); reseed = HRNG retry×3 (кволий tick-fallback прибрано 2026-05-30). Закриває ECB→CCM/MIC/replay (BLOCKER-2/3) + SEC.10 panic + FW.29; узгоджено з ATECC608B Slot 0. · [ ] 🤖 верифікувати `CRYP_AES_CCM` на STM32WLE5JC REVB (RM0461 §27.4, bench) → flip `FW2_CCM_ENABLED`/`TELEMETRY_CCM_ENABLED` — **ЄДИНИЙ HW-залежний пункт** · [ ] 🔗 TRL-7: monotonic FC-counter (Flash high-water / ATECC) для безумовної nonce-унікальності · [x] ✅ DR15 resource-conflict вирішено (2026-05-30): FW.2 тримає DR15, FW.20-S2 bitmap → Flash-KV (`03_01 §2.3`)

#### FW.3 — Queen AT Command Blocking (~25 сек)
- **P1** · 🟡 · → `03_02`
- ✅ ring buffer + drain-loop закрив single-packet overwrite/emergency loss (Queen сліпа під час CoAP flush). · [ ] 🟡 переписати `Flush_Cache_To_Rails()` на UART DMA interrupt-driven — deferred (HW bench)

#### FW.4 — TinyML `Run_Inference()` — compilation unblocked, inference TBD
- **P0** · 👤+🔗 · → `03_03`
- Compilation unblocked (stub fallback); реальна модель + uncomment лишаються. Блокує acoustic detection (chainsaw/cavitation/wind) + Mongabay pivot. · [ ] 👤 тренування Path B log-mel 5-class (Бушин/Любченко) → `silken_net_audio_model.h` (заміна stub через `__has_include`) · [ ] 🔗 verify Tensor Arena (`arm-none-eabi-size`) + uncomment Run_Inference call-site (Phase 1.5) + wire `firmware/common/logmel.c` у ARM-build (`LOGMEL_USE_CMSIS` + CMSIS-DSP link; Flash +~7KB tables; ⚠️ ARM-стек ~7KB/4 буфери → bench stack-high-water vs 16KB arena+mruby, або reuse-buffers) — після моделі (DSP golden-vector тести → FW.25, One-Home) · [ ] 🌿 FW.4-EXT (post-TRL 7): 5-й клас `fauna_activity` dawn/dusk (`03_03 §10`), залежить від UNI.11+UNI.13a; альт. ACI descriptor

#### FW.18b — OTA threshold invalid counter (production-visibility)
- **P2** · 🔗 · → `03_03 §5`
- ✅ saturating counter `tinyml_threshold_invalid_count` (відкидає NaN/out-of-range/інверсію OTA payload) + 7 host-тестів. · [ ] 🔗 wiring до LoRa packet (перерозподіл бітів) · [ ] 🔗 backend Prometheus `tinyml_threshold_invalid_total{soldier_did}` + Grafana

#### FW.7 — Float vs BigDecimal divergence (TRL 6 mitigation)
- **P1** · 👤 · → `03_04 §5`
- ✅ backend `Attractor` BigDecimal→Float (IEEE 754 — DCI **категорично** однакові Z; raw drift ~1e-14 реальний mruby-VM↔CRuby, FW.46). ⚠️ ARM↔x86 Float drift лишається; категоричний tolerance band компенсує для TRL 6, строгий consensus → `ARCH.18`. · [ ] 👤 bench-verify (flag `MRB_USE_FLOAT32`=double вже пінено `build_config.rb` — FW.19/FW.46)

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- **P1** · 🟡 · → `03_01 §2`, `04_01`, `04_02`
- ✅ Rails + firmware-парсер `Soldier_Handle_CMD_SET_THRESHOLDS` (freeze-contract, `FW8_PARSER_ENABLED 0`) + 12 host-тестів (firmware 2.0/45.0 vs backend per-species `TreeFamily`). · [ ] 🟡 deferred TRL-7: активувати `FW8_PARSER_ENABLED 1` після FW.21 звільнить RTC register

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- **P2** · 🔗 · → `03_05 §3`
- Після FW.1. Статичний ключ при Factory Flashing → немає rotation без re-flash (GDPR/ISO 27001/NIST SP 800-57). Рішення: Hash Ratchet KDF (`CMD:ROTATE_KEY` → `K_current`→`K_next` AES-KDF, PFS). · [ ] 🔗 дизайн протоколу + CoAP command + cluster ACK + Flash/RTC storage + ECDH alt

#### FW.19 — Float32 vs Float64 mruby compile flags
- **P2** · 🤖+👤 · → `03_04 §5`
- ✅ tolerance band «by design» (категорична `check_z_divergence!`). **Флаг — `MRB_USE_FLOAT32`** (перейменовано з `MRB_USE_FLOAT` у mruby ≥3.0; стара назва мертва — verified `doc/mruby4.0.md`). Без нього = double (потрібно), з ним = float32 → ±5-10 units на Z → bio_status зсув. · [x] 🤖 (FW.46) `firmware/mruby/build_config.rb` пінить double (НЕ ставить `MRB_USE_FLOAT32`) + boxing-інваріант (НЕ вмикати WORD/NAN boxing на 32-bit) — `03_01 §12.4` · [ ] 👤 bench-verify на STM32WLE5JC REVB

#### FW.20 + FW.20-S2 — Time Sync (Rails ↔ Queen ↔ Soldier)
- **P2** · 👤+🟡 · → `03_02 §5а` (канон-хаб)
- TRL-6 P2 (`Derive_Cold_Start_State` ±12год толер.); TRL-7 блокер (ARCH.26 TDMA, HMAC nonce, fire ±1с). ✅ FW.20 1-hop Done; FW.20-S2 4/5 Done. · [ ] 👤 lab drift-test ΔT=±60°C (термокамера, TRL-7) · [ ] 🟡 (4/5) anti-storm dedup bitmap → Flash-KV store (DR15 зайнято FW.2 CCM FC; `03_01 §2.3 ARCH.28`). Cross-ref: ARCH.26, FW.30, SEC.10/FW.29

#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- **P2** · 👤 · → `03_01 §2`, `08_02`
- ✅ `EmaState` + 4 функції (`EMA_Update`/`Get_DeltaT_Sec`/`Get_Vcap_Mv`/`Is_Warmed_Up`) + RTC DR10+DR12 (звільнено DR11) + 102 host-тести (EMA на MCU зменшує LoRa-трафік). · [ ] 👤 інтегрувати з Kalman filter design (E.10 — Косенук)

#### FW.22 — acoustic_events payload overflow (uint16 → uint8 truncation)
- **P2** · 🔗 · → `03_03 §7.1`
- ✅ тип `uint8_t` + saturating increment (cap 255) + backend overflow-warning + Prometheus counter + 8 тестів. · [ ] 🔗 АБО 2 байти в payload (перепакування — FW.2 CCM)

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- **P1** · 🟡 · → `03_05 §3.4б`
- ✅ HMAC-SHA256 OTA auth: `OtaHmacKeyService` (HKDF `silken-ota-hmac-v1`) + `OtaPackagerService` (`[0x9B]` trailer) + Queen relay + Soldier dual-gate (magic `RITE` + constant-time HMAC) + 30 RSpec/17 host. · [ ] 🟡 mbedTLS HMAC compute на STM32 HASH (lab, analog FW.30)

#### FW.25 — TinyML DSP-path: Path B (log-mel) SELECTED [DECISION 2026-05-22]
- **P0** · 👤+🤖 · → `03_03 §3.2/§3.4`
- Choice gate закрито: **Path B (log-mel + 2D-CNN)** baseline (Path A провалює fauna layered soundscape; Path C +5-10KB arena на 64KB SRAM; ESC-консенсус log-mel — Salamon&Bello/BirdNET; CMSIS-DSP вже в стеку; Mongabay → fauna-ready). Контракт §3.4 **self-owned** (ML-партнера нема) + локально верифікований. · [x] 🤖 ✅ §3.4 виправлено (latent DC-removal + periodic-Hann баги) + `silken_ml` оракул (librosa ≡ pure-stdlib, parity 1e-6) — `tools/ml` · [x] 🤖 ✅ `Compute_LogMel` (`firmware/common/logmel.c`; host radix-2 / ARM `arm_rfft_fast_f32`, **НЕ** `arm_mfcc_f32`) + golden-vector host-тести (`test_logmel.c`, tol 1e-3, 6/6) + auto-gen таблиці (`silken_ml.codegen`) · [ ] 👤 ML-партнер тренує на §3.4 (крос-чек, не гейт) · [ ] 🔗 verify TENSOR_ARENA (~15-30KB, FW.26) + inference тести — після моделі · [ ] 🌿 UNI.11+UNI.13a dataset dawn/dusk · [ ] 🤖 fallback Path C (TFLM) — потребує re-verify arena

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- **P1** · 🤖 · → `03_03 §4.3`, `04_06`
- ✅ CI gate `make size-check` (host `.bss+.data`<51200B; soldier 2.5K/queen 12.4K). **FW.46:** real `arm-none-eabi-size` активний для owned-коду (logmel ~6.3KB; mruby ~117KB Flash / 0 static RAM — `03_01 §12.4`); повний `.elf` size (з tensor arena) — після HAL-vendoring + моделі. Точний arena невідомий (~16KB оцінка, Path B §3.2 ~15-30KB); >46KB → stack overflow при Lorenz. · [ ] 🤖 повний `.elf` `.bss+.data` після FW.4 модель + `-DSILKEN_WITH_HAL=ON` · [ ] 🤖 якщо >46KB — INT8 quantization/prune

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- **P2** · 🔗 · → `03_02 §5`
- ✅ Дизайн B (Magic Re-Request): Soldier bitmap uplink `[0x55]` → Queen targeted re-broadcast (60-90% economy) + 22 host-тести (Soldier у STOP2 пропускає chunk). Дизайн A (ACK-aggregation) — з ARCH.26. · [ ] 🔗 Дизайн A залежить від ARCH.26 (TDMA RX-вікно); B незалежний

#### FW.30 — SEC.11 C-bridge gap: `main.c` mruby виклик не оновлено
- **P1** · 🔗 · → `03_04`
- ✅ warm/cold paths → єдиний 7-arg `calculate_state`; `Load_Lorenz_Seed()` (K_seed Flash, magic `LSED`) + `Derive_Cold_Start_State()` (placeholder hash, TODO mbedTLS lab) + 11 host-тестів. (SEC.11 cutover зламав стару C-bridge сигнатуру → `BIO_STATUS_VM_ERROR`; новий bytecode не OTA-деплоївся до фіксу.) · [ ] 🔗 після FW.30 — FW.5 B+ (EMA delta_t/vcap як args[5..6]) незалежний

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- **P2** · 👤+🤖 · → `03_04 §7.1`
- Після SEC.11 byte-identical `(x₀,y₀,z₀)` + ідентична Float math (drift ARM↔x86 <1e-12). check лишається категоричним; числовий `|Δz|<ε` (ε=0.001) готовий до flip → числовий fraud-detect (replay з правильним status, неправильним Z magnitude). · [ ] 👤 lab: однакові тест-вектори STM32 vs x86, `|Δz|` distribution (N=10k) · [ ] 🤖 оновити `03_04 §BLOCKER-2` з drift+ε (lab-blocked: STM32WLE5JC REVB; ε=0.001 default)

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- **P1** · 🔗 · → `03_03 §10.3`
- ✅ `Fauna_Should_Sample(vcap_mv)` (≥FAUNA_VCAP_MIN_MV інакше skip + counter `fauna_skipped_low_vcap`) + 8 host-тестів. Fauna-сесія ~78.3мДж (×20 audit-fix); при V_cap≈3.5V просадка ~37мВ → concurrent TX = brownout. · [ ] 🔗 активація: виклик у fauna-pathway після FW.4 uncomment · [ ] 🤖 Prometheus "fauna skip rate" — після FW.4

#### ARCH.40 — Fauna 5-сек вікно: монолітне awake-обчислення (SRAM2 wipe)
- **P1** · 🔗 · → `03_03 §10.2`
- ✅ Doc-fix вкочено: fauna-сесія монолітна за 1 awake (SRAM2 wipe не зберігає float[156][N_mel] між STOP2; DR15 не вміщає).
- [ ] 🔗 при FW.4 fauna-pivot — unit-тест `test_fauna_sampling_no_stop2_in_session()`

#### ARCH.41 — Cold-start Time Paradox (DCI)
- **P2** · 🔗 · → `03_04 §2.1`
- VBAT loss → RTC `epoch_day` розходиться з сервером (cold-derive 10957 = RTC-default 2000-01-01 vs chained ≈20585) → категоричний DCI false-positive до `CMD_TIME_SYNC`. **Mitigation A** (server-side: 3 epoch_day кандидати → `time_unsynced_fallback`, не падати DCI) ✅ реалізовано → `04_02` (`try_time_sync_recovery`). **Знахідка:** firmware-деривація тепер повний HMAC-parity з backend (`lorenz_seed.h`, FW.30 закрито) + кандидат виправлено 10951→10957 (стара цифра була артефактом leap-less формули).
- [ ] 🔗 (B/C) після стабілізації A, координований firmware rollout: **B** Soldier sentinel `acoustic_events=0xFE` на cold-boot; **C** defer-first-uplink grace «hello» (DID+Vcap+TIME_REQ, без Lorenz state)

#### FW.46 — Enterprise-grade ARM firmware build (committed, reproducible, CI cross-compile)
- **P1** · 🤖+👤 · → `03_01 §12.4`
- **Owned-code foundation ✅ (2026-06-04):** відтворюваний CMake-крос-компайл того, що ми володіємо, + CI gate `firmware_arm_build` (перша реальна крос-компіляція main-line firmware C). Повний HAL-`.elf` — окремий 👤-крок (CubeMX поза репо). · [x] 🤖 CMake + `cmake/arm-none-eabi.cmake` (Cortex-M4F, pinned Arm GNU 13.2.Rel1) + pinned submodules CMSIS-DSP/CMSIS_6/mruby (`firmware/extern/`) · [x] 🤖 `logmel.c` крос-компілюється під ARM (`LOGMEL_USE_CMSIS` + CMSIS-DSP), real `arm-none-eabi-size` ~6.3KB · [x] 🤖 **mrbc bytecode** (`bio_contract.rb` → `lorenz_bytecode.h` — був placeholder-stub!) + drift-gate (light `check_bytecode.py` + deep `gen_bytecode.sh --check`) + minimal-VM harness (`run_bytecode_vm.sh` ганяє реальний байткод) · [x] 🤖 host↔target `arm_rfft_fast_f32` packing-parity (`test_logmel_cmsis`, worst Δ 7.6e-6) · [x] 🤖 mruby minimal gembox (double, NO_BOXING) крос-зібрано — ~117KB Flash / 0 RAM (`03_01 §12.4`) · [ ] 👤 STM32 HAL vendoring (CubeMX export) → `-DSILKEN_WITH_HAL=ON` → повний Soldier/Queen `.elf` + bench flash-verify · [ ] 🤖 flip FW.26 на повний `.elf` після HAL · [x] 🤖 verify `firmware_arm_build` зелений ✅ (2026-06-04, CI run 26948600632 — `firmware_arm_build` + `firmware_test` + `firmware_ram_budget` усі success на push ca90fa6; перший fresh-submodule-checkout прогін у CI підтвердив, що CI-only-validated концерн знято) · [ ] 🤖 (optional hardening) пін toolchain у CI через ARM-tarball замість apt (reproducible-build attestation — far-future, `00_08`). Cross-ref: FW.4 (logmel wiring), FW.26 (size), FW.19 (mruby double), FW.47 (submodule audit), SEC.3 (`.bin`).

#### FW.47 — Repo-wide vendor-via-submodule audit (dependency hygiene)
- **P2** · 🤖+👤 · → `03_01 §12.5`
- FW.46 завендорив CMSIS-DSP/CMSIS_6/mruby як pinned submodules; FW.47 — аудит решти vendor-поверхні + єдина pin-політика ([`03_01 §12.5`](03_01_Firmware_Lifecycle_and_DMA)). · [x] 🤖 інвентар + pin-стратегія ✅ (2026-06-04 — повний інвентар: firmware-native + OpenSSL host-dep + contracts; конвенція `extern/<dep>`@tag) · [x] 👤 рішення per-dep ✅ (FW.47, 2026-06-04): contracts=**npm-keep** (`npm ci`+committed lock відтворювано); firmware-native=**submodule@tag**-конвенція; toolchain-pin=**far-future**. Фізичний вендоринг milestone-gated: mbedTLS → [`00_07` — FW.30](00_07_Action_Plan_Tracker), STM32 HAL → [`00_07` — FW.46](00_07_Action_Plan_Tracker) (`-DSILKEN_WITH_HAL=ON`), CMSIS-NN → [`00_07` — FW.4](00_07_Action_Plan_Tracker) · [x] 🤖 Python conda envs ✅ (2026-06-04): `in_silico` запінено committed `conda-lock.yml` (multi-platform versions+hashes) + CI job `lock_sync` гейтить lock↔`environment.yml` (`--check-input-hash`); `ml` свідомо deferred (parity-self-guards)

#### FW.48 — cppcheck static-analysis gate (enterprise "ruff/rubocop for C")
- **P2** · 🤖 · → `03_01 §12.6`
- ✅ (2026-06-06) cppcheck-гейт owned firmware C (`soldier`+`queen`+`common`) — job `firmware_lint` (apt cppcheck, ubuntu-24.04) + єдиний runner `firmware/scripts/cppcheck.sh` (DRY: CI=локаль) + кастомна Cortex-M4 платформа (`char` unsigned). Gating `warning,performance,portability,style` exhaustive. · [x] 🤖 інфра (platform/runner/документовані suppressions) + real-фікси (мертва гілка `(5+uid_len)>2048`, const-correctness, variable-scope) + обґрунтовані inline-suppress (radio RxDone, HAL weak-symbol callback) → gate green + host-тести 0-fail · [x] 🤖 verify `firmware_lint` зелений ✅ (CI run 27070579139 на push cea7e89 — job `firmware_lint` success) · [x] 🤖 `firmware/test/` досліджено → свідомо НЕ гейтимо (знахідки = const-шум на тест-локалах + навмисні boundary/clamp/overflow-патерни, 0 реальних багів) · [ ] 🤖 (optional, deferred) MISRA-as-gate (apt-addon). Cross-ref: FW.46, `03_01 §12.6`.

#### FW.49 — Tick-time ≠ wall-time у STOP2: системна семантика таймерів Soldier
- **P0** · 👤🤖 · → [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)
- **Знахідка:** `HAL_GetTick` (SysTick) заморожений у STOP2 (`HAL_SuspendTick`+WFI), але ВСЯ часова семантика Soldier стоїть на ньому: (а) `delta_t_seconds` (DR1) — ПЕРВИННИЙ біосигнал метаболізму (вхід β-пертурбації → growth_points → токеноміка) міряє лише active-час (~секунди), не wall-інтервал між пробудженнями (L4 in-silico очікує 36–190 с фізичного інтервалу заряду); (б) FW.27-B re-request «5 хв тиші» = ~500 wake-циклів; (в) FW.20-S2 drift-watchdog 12 год / cooldown 1 год / grace 10 хв — фактично ніколи не спрацюють; (г) beacon drift-компенсація `(tick_now−tick_sync)` занижена. Host-тести сліпі (mock tick монотонний). Wake-source циклу (RTC wakeup timer? VBAT_OK EXTI?) ніде в repo не визначений — `MX_RTC_Init` живе лише у майбутньому CubeMX-проєкті.
- [ ] 👤 рішення wake-source (RTC wakeup vs VBAT_OK EXTI) — визначає механіку фікса · [ ] 🤖 `Wall_Seconds_Now()` на RTC-календарі (LSE йде у STOP2) + міграція delta_t/re-request/drift-таймерів + host-тести з «стрибаючим» mock-часом · [ ] 👤 bench-верифікація delta_t проти реального інтервалу заряду EDLC

#### FW.50 — Vcap ADC: raw counts використовуються як мВ (без конверсії)
- **P0** · 👤🤖 · → [`03_01 §3`](03_01_Firmware_Lifecycle_and_DMA)
- **Знахідка:** `vcap_voltage = HAL_ADC_GetValue()` (канал VREFINT) — сирий 12-bit відлік (~1500) скрізь трактується як мВ: пакування байтів 4-5, пороги `VCAP_LISTEN_THRESHOLD=2800`/`COLD_TX_DEFER=4000`/`FAUNA=4500` мВ, EMA, `vcap_mv` у mruby. На залізі RX-вікно (>2800) не відкриється ніколи, β-пертурбація з фейкових значень. Плюс: VREFINT міряє VDDA (за buck'ом — константа), НЕ Vcap EDLC; для Vcap потрібен дільник на окремий ADC-канал (hardware, `02_01`/`02_03`).
- [ ] 👤 схемна вилка: дільник Vcap→ADC pin (узгодити з `02_03` BQ25570) · [ ] 🤖 pure-helper `Adc_Raw_To_Mv()` (VREFINT-калібрування з factory cal @0x1FFF75AA + divider math) + host-тести · [ ] 👤 bench-калібрування

#### FW.51 — Queen: телеметрія-батч губиться при провалі CoAP-send
- **P2** · 🤖 · → [`03_02 §6`](03_02_Queen_Gateway_Firmware)
- **Знахідка:** `Flush_Cache_To_Rails` звільняє CIFO-слоти (`is_active=0, cache_count=0`) ПІД ЧАС пакування — до підтвердження send. Усі 3 retry впали (LTE-діра) → година телеметрії лісу зникає мовчки. Фікс host-testable: звільняти слоти лише після `send_success`, інакше лишити кеш на наступну спробу (увага: новіші пакети тим часом оновлюють слоти — узгодити з дедуплікацією).
- [ ] 🤖 deferred-clear + host-тест «fail→retry-наступним-циклом без втрати»

#### FW.52 — OTA throughput by-design: 1 RX-пакет/пробудження + give-up без печатки
- **P2** · 👤 · → [`03_02 §5`](03_02_Queen_Gateway_Firmware)
- **Знахідка (design-спостереження):** (а) Soldier RX-вікно обробляє МАКСИМУМ один пакет за wake-цикл (усі сценарії → `break`) — OTA на 1024B = ~98 чанків ≈ 98 пробуджень; (б) Queen гасить `ota_is_active=0`, якщо тіло відлунало до прибуття HMAC-печатки (CoAP-порядок не гарантує) — а re-request обслуговується лише при `ota_is_active==1` → мертвий OTA до повторного Rails-push; (в) Soldier шле re-request лише раз на «5 хв» tick-часу (див. FW.49). Разом: дні-тижні на один OTA. Можливо acceptable (energy-first), але рішення має бути СВІДОМИМ.
- [ ] 👤 рішення: прийняти повільний OTA як design або 🤖 re-arm RX у межах вікна при активній OTA-збірці (енергогейт vcap) + Queen: тримати `ota_is_active` до печатки/таймаута

#### FW.53 — OTA wire-contract integrity (CRC32-trailer + явний CoAP len + CRC16-verify)
- **P0** · 🤖 · → [`03_01 §4.6`](03_01_Firmware_Lifecycle_and_DMA)
- ✅ OTA був зламаний end-to-end **двома** шарами: (1) бекенд НЕ додавав CRC32, який Soldier вимагає останніми 4 байтами зібраного перед Flash → кожен OTA гинув на integrity-gate; (2) Queen вгадувала довжину чанка з CBC zero-padding (формула `aligned−16−7`) → систематично обрізала 1..16 байт кожного чанка (повний 512B→500B), а CRC16 від бекенду не перевірявся. · [x] 🤖 `OtaPackagerService` будує wire-потік `bytecode + zero-pad + CRC32(BE)`, вирівняний на LoRa-MTU (Soldier рахує отримане як MTU×chunks → CRC32 лягає в кінець останнього чанка); HMAC над padded bytecode (дзеркало Soldier dual-gate) · [x] 🤖 CoAP-формат `[0x99][idx:2][total:2][len:2][bytecode:len][crc16:2]` + CRC16-verify (One-Home `firmware/common/silken_crc.h`, спільний Soldier/Queen/тести) · [x] 🤖 Soldier+Queen OTA campaign-change reset (мертва недозібрана кампанія більше не блокує живу) · [x] 🤖 host-тести (повний-512 не обрізано, CRC16-mismatch/lying-len reject) + rspec packager/integration. Cross-ref: FW.23 (HMAC trailer), FW.27-B (re-request), FW.52.

## §03/§05 · Безпека (Edge crypto + Web3)

#### SEC.1 — Multisig Gnosis Safe для production admin role
- **P0** · 👤 · → `05_03 §Admin-Role`
- ✅ `Deploy.s.sol` admin=Safe на genesis + `REQUIRE_SAFE_ADMIN` guard + runbook (нічого не задеплоєно → reassign не треба). · [ ] 👤 створити Gnosis Safe (3/5|2/3) на Polygon + деплой з `ADMIN_ADDRESS=<Safe>` `REQUIRE_SAFE_ADMIN=true`

#### SEC.2 — RDP Level 2 activation timeline
- **P1** · 🤖+👤 · → `03_05 §3.6`
- ✅ процедура активації RDP L2 (pre-flight + CubeProgrammer CLI + rollout R&D→Pilot→Mass). · [ ] 🤖 верифікувати OTA flow end-to-end · [ ] 👤 перейти на RDP L1 для field batch

#### SEC.3 — Factory Flashing pipeline
- **P0** · 👤 · → `03_05 §3.4` (+ §3.4г threat model)
- ✅ Гілка A+B Rake-tool: `provisioning_sessions` AASM + 2-Person Rule + `factory_flashing/*` + rake `factory:flash|approve|execute` (dry-run) + 63 specs. · [ ] 👤 real `STM32_Programmer_CLI` на bench (post-FW.2) · [ ] 👤 Bitwarden Secrets API live (`BitwardenAdapter` зараз `NotImplementedError`) · [ ] 🔗 real `cryptoauthlib` I²C — після SEC.6 ATECC608B PCBA

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **P2** · 👤 · → `03_05`
- Zero-consumption transport: магніт→circuit open, інсталятор знімає→first power-up (~$0.05/unit). Дизайн approved, BOM ні. · [ ] 👤 додати Hamlin 59140-1-T-00-A + N52 магніт до BOM + оновити KiCad schematic

#### SEC.7 — OTA image автентифікація (cross-ref FW.23)
- **P1** · 🔗 · → `03_05 §3.4б`
- ✅ HMAC-SHA256 dual-gate (OtaHmacKeyService + OtaPackagerService + Soldier dual-gate + Queen relay). · [ ] 🟡 mbedTLS HMAC compute на STM32 HASH (lab) · [ ] 🔗 Ed25519 key pair (Post-TRL 7)

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **P0** · 👤 · → `03_05 §3.1а`
- ✅ guard `Security::WeakKeyDetector` + boot-guard refuse-to-boot на FIPS-197/NIST/degenerate vectors (30 specs). ⚠️ ОКРЕМЕ від FW.1: якщо master seed базується на цьому ключі — весь derivation tree скомпрометований. · [ ] 👤 замінити seed key на crypto-random → задокументувати генерацію у vault (без коміту) → re-flash прототипи

#### SEC.12 — HRNG-IV fallback hardening (CoAP CBC IV)
- **P2** · 🔗 · → `03_05 §HRNG Fallback`
- ✅ (2026-05-29) fallback IV → pure `coap_iv.h#coap_fallback_iv_word` (uid×device + `queen_unix_ts`×reboot + `coap_flush_seq`×flush) + 4 host-тести → **reuse закрито** по всіх осях. 🟡 Residual: IV передбачуваний на fallback — **low-severity** (CoAP-батч без chosen-plaintext вектора). · [ ] 🔗 повна unpredictability = key-derived IV `E_key(counter)` (AES-engine + SEC.8 restore) — bench-gated

#### SEC.14 — ATECC608B role-split re-examination (ARCH.42 honesty)
- **P2** · 🤖+👤 · → `03_05 §3.7`
- ✅ (2026-06-02) Чесний trade-off поданий у `03_05 §3.7` (новий підрозділ «Роль SE: per-packet AES vs provisioning-only») + §3.4 Гілка B вказівник. Перефреймовано «0.1% acceptable» → справжня вісь: tamper-resistance LoRa session-ключа (Варіант B: ключ не лишає ASIC → forces per-packet) ⟷ latency/ідіом (built-in radio-AES STM32 ~10µs + session-key у RDP-Flash, ATECC provisioning-only). Energy-аргумент перевірено = малий (≈70µJ/пакет ≈ 0.2% LoRa-TX ~39мДж per `02_03` / десяті % wake-budget vs 0.47F EDLC ≈7Дж), тому **НЕ вирішальний**. Уточнення всередині Варіанту B, **не** перегляд ARCH.42; ATECC-agnostic щодо FW.2 nonce-fix. · [x] 🤖 re-examine + чесно подати trade-off у `03_05 §3.7` ✅ · [ ] 👤/🤖 обрати роль SE (per-packet vs provisioning-only) при bench eval + BOM freeze — рішення про threat model, не технічна необхідність · [ ] 🤖 (optional) cross-check `02_01 §2` power-budget + `03_01` wake-energy для точної % величини

#### SEC.15 — IWDG у STOP2: option byte `IWDG_STOP` обов'язковий при factory flashing
- **P1** · 👤 · → [`03_05 §3.4г`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Знахідка:** IWDG (LSI) за замовчуванням НЕ зупиняється у STOP2; max timeout ~32.7 с (LSI 32k / presc 256 / reload 4095). Будь-який сон довший ≈26-32 с → IWDG-reset посеред STOP2 → втрата SRAM (mruby VM, ota_buffer, warning_counter) кожен цикл + марнування енергії на повний reboot. Лік — option byte **IWDG_STOP=0** (freeze у Stop) при заводській прошивці; у repo/SEC.3 pipeline це ніде не зафіксовано. Дотично: PVD-кома (`HAL_PWR_PVDCallback`) теж спить у STOP2 — без замороженого IWDG «кома» не довша за watchdog-період; а після PVD-wake можливий `HAL_Delay`-hang (tick suspended) → IWDG-reset як фактичний механізм відновлення — задокументувати як свідомий шлях.
- [ ] 👤 додати `IWDG_STOP` (+ узгодити `IWDG_STDBY`) у SEC.3 factory flashing option-bytes чеклист поруч із RDP (SEC.2) · [ ] 👤 bench-верифікація: сон 1 год без spurious reset

## §04 · Backend / API / UI

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** · 👤 · → `04_03`
- ✅ graceful degradation (Redis down → DB-backed nonce, TTL 10хв) + тести. · [ ] 👤 верифікувати Upstash multi-zone replication у production

#### S6.10 — MaintenanceRecord — лише лог
- **P3** · 🔗 · → `04_02 §Forester Guild`
- ✅ архітектурний дизайн task-assignment (bounty, scoring, `FOR UPDATE NOWAIT`, GPS/EXIF/IPFS→USDC, anti-Sybil). · [ ] 🔗 зв'язати з Forester Guild PoPhW (E.20)

#### S6.14 — peaq_signing_key: відсутня rotation policy
- **P2** · 👤 · → `04_02 §S6.14`, `06_04 §5.4`
- ✅ rotation policy (dual-key 72h, 90д) + emergency revocation runbook. · [ ] 👤 vault-store production `peaq_signing_key`

#### TEST.1 — Test coverage: RSpec gate raised; Solidity/firmware tracked
- **P2** · 🤖 · → `04_06 §B.1`
- Скоуп + політику гейту описує `04_06 §B.3`; gap-recipe + тріаж — `04_06 §B.4`. Пороги живуть тільки в `spec/spec_helper.rb`. · [x] 🤖 (2026-06-02) **RSpec**: відфільтровано `/lib/tasks/` (ops-оркестрація; логіка в lib-движках на 100%), піднято гейт (line/branch + per-group tripwire), великий branch+line-push із тріажем `04_06 §B.4` — мертві `&.`→`.`, реальні guard/empty-state/error/anonymous-policy тести, `stub_const` для forward-looking-гілок, прибрано dead-code (`weak_key_detector`/`resilient_client`/`emergency_response`/`tracker/dashboard`/`chainlink_router_version`/policies/`hil/*` тощо). · [ ] 🤖 RSpec залишок — branch-хвіст звужується партіями (2026-06-03 Batch 2+4: codex/match+node scope+guard-edges, celo low-balance-raise + Time-window, insurance Etherisc-idempotency, codex/citation nil-type, dashboard parser-guards, blockchain_minting wallet-nil identifier, wallet toucan-no-address) + **2 dead-branch рефактори** (insurance redundant `if status_paid?` за AASM triggered→paid; rollback dead `log.tree&.` за Tree `dependent: :delete_all`) + **ReDoS-fix** `TABLE_ID_RE` (CodeQL: вкладений `(?:[…]+\s*)*` → лінійний клас). Решта домінована **defensive** (Phlex-views `&.current_user`, env/load `defined?(...)`, model-validation-dead, exhaustive-case) → лишається за §B.4 (fragile white-box заради % = анти-§A.16–17). Таксономія dead→refactor vs defensive→leave+чому + decision-матриця + worked-examples — `04_06 §B.4/§B.5`. · [ ] 🤖 **Solidity** (`contracts/`): line/func високі, forge-тести зелені; forge branch% низький — переважно forge-артефакт (рахує кожен `require` + OZ-inherited; revert-шляхи покриті `testRevert_*`); `[profile.ci]` пофікшено (optimizer був off → не компілювалось на OZ P256). Глибший branch-targeting pass deferred. · [ ] 🤖 **Firmware** (`firmware/test/`): host-тести зелені (`make -C firmware/test`); НЕ gcov-інструментовано; mock AES/TinyML/DMA — inherent host-обмеження (`04_06 §B.1.1`). · [x] 🤖 (2026-06-03) test-файли: коментарі аудитовано (всі spec/) — здорові (ID-refs + WHY + wire-layout; 0 dead-code / реальних TODO); виправлено count `~20 specs` + trimmed changelog-дати `ARCH.42 (date)`. · [ ] 🤖 seed-флак: кілька line/branch плавають між прогонами (гейт має маржу); точний hunt = diff двох fixed-seed прогонів.

## §05 · Web3 / Економіка / Slashing

> Мультичейн, oracle/chain-конфіг та slashing-механіка — канон `05_xx`.

#### SLASH-1 — Slashing cause_classification gate (financial-safety) 🔴
- **P0** · 🤖+👤 · → `05_05 §3/§6` (divergence `04_02 §11`)
- ✅ (2026-05-29) blackout → Field Audit, НЕ burn: `ContractHealthCheckService#flag_data_blackout!` (cluster-wide empty → `system_fault` alert, contract :active, no burn; 10 specs). · [x] 🤖 (2026-06-03) de-correlate penalty signals: comms-correlated (no-ack/Streamr-gap, спільний root-cause «вузол offline») через `max()`, НЕ суму — `BlockchainBurningService#calculate_penalty_factor`, INERT за `SystemParameter` до DAO-confirm (ваги/принцип → `05_05 §3/§6`) · [x] 🤖 penalty-формула §3 `damage_ratio^GAMMA × min(pf,2.0)` у `BlockchainBurningService` (✅ `#calculate_slash_ratio`, GAMMA/PF_MAX через `SystemParameter`, 8 specs) · [ ] 👤 DAO/founder-confirm перед mainnet (BIZ.13 operator-bond, `05_05 §3.1`)

#### S3.2 — dClimate Real API verification
- **P1** · 👤 · → `05_01`
- ✅ `Dclimate::VerificationService` (NASA FIRMS, FRP≥10MW, cloud fallback). · [ ] 👤 верифікувати з реальним API key у staging + e2e `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P1** · 👤 · → `05_03`
- SFC events (ForestMinted, GovernanceSlashed) у subgraph; адреса = placeholder. Zero-address fail-fast guard `subgraph/validate_addresses.sh` ✅ (раніше E.45). · [ ] 👤 замінити `0x0000…` на реальну SFC-адресу у `subgraph.yaml` (після контракт-деплою)

#### BIZ.13 — Slashing principal-agent: investor capital vs operator-bond
- **P2** · 👤+🤖 · → `05_05 §3.1`, `05_03 §Slashing`, `04_02 §1.2`
- Кат-A slash зрізає інвесторський `locked_balance`, хоча недбалість — провина оператора (principal-agent). ✅ decision memo → рекомендація **hybrid operator-bond**. · [ ] 👤 DAO confirm: hybrid vs investor-slash vs pure operator-bond · [ ] 🤖 якщо operator-bond — `OperatorBond` + `ProtocolParameters` + контракт + синх `05_05 §3`/`05_03`/`04_02`

#### E.60 — Merkle CID-witness: Polygon ↔ Filecoin integrity bridge
- **P1** · 🤖 · → `05_02 §E.60`
- ✅ (2026-06-03) `Filecoin::CidGenerator` (детермін. CIDv1 raw+sha2-256→base32, golden-vector) + content-CID guard у потоці архівації AuditLog: `ArchiveService` вбудовує самоописовий `content_cid`, `VerificationService` fail-fast при розбіжності (локально vs віддалено) → детект ex-post swap. Закриває archive-swap gap для audit-архіву. · [ ] 🤖 follow-on: per-tree Merkle-witness для телеметрія-батчу (leaf_cid→`archive_root`→`mint(bytes32)`) — потребує `MerkleTree` + колонок на партиційованому `TelemetryLog` (міграція) + Solidity; worker-guard з `manual_review` саме в цьому батч-потоці. Канон `05_02 §E.60`

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
- **P1** · 🤖+👤 · → `06_03 §2.9`
- ✅ `external_labels` (env/service/source/release) у `config.alloy` — атрибуція prod/canopy + Akash multi-provider. · [x] 🤖 CI-валідація `config.alloy` ✅ (`grafana/alloy fmt`, CI job `alloy_config_validate`) · [x] 🤖 process/runtime метрики ✅ (9 gauges: RSS/GC/threads/Puma; `sample_process_runtime!` + sample_connection_pool! wired; 13 specs) · [x] 🤖 `queue_config`/WAL tune + cardinality budget ✅ (2026-06-04, `config.alloy` — relabel `labeldrop` per-identity + queue_config + explicit WAL; → `06_03 §2.9` #2/#4) · [ ] 👤 `up`-scrape alert + SLO/error-budget

#### S2.2 — Grafana Cloud dashboards
- **P0** · 👤 · → `06_03`
- ✅ dashboard IaC (5 секцій, 15 панелів) → `deploy/grafana/`. · [ ] 👤 імпортувати у Grafana Cloud (інструкції `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** · 👤 · → `06_03`
- ✅ 13 alert rules IaC (5P0/5P1/3P2) → `deploy/grafana/alerts/` + counter `silkennet_telemetry_acoustic_overflow_total`. · [ ] 👤 замінити `${DATASOURCE_UID}` + notification channel (Slack/Email/PagerDuty)

#### INF.3 — TLS termination
- **P2** · 👤 · → `06_02 §TLS термінація`
- SDL відкриває 80/443/CoAP-UDP 5683, але TLS termination не налаштовано (browsers block WS HTTPS→HTTP). · [ ] 👤 налаштувати TLS (Akash ingress або Cloudflare)

#### INF.6 — CoAP UDP smoke test через Ingress Anchor (post-deploy gate)
- **P1** · 🤖+👤 · → `06_01 §6`, `06_02`, `06_08 §1.2`
- ✅ workflow `coap_smoke.yml` (`workflow_call` від `deploy.yml`) — 🟡 ще не required gate. Без UDP-smoke silent UDP failure не помітний (Queen→Ingress Anchor→Akash→CoAP). · [ ] 👤 активувати як required post-deploy gate (`needs: coap-smoke`) · [ ] 👤 перший boundary smoke з Queen/`bin/forest_simulator`

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
- CIFO 50-slot RAM cache переповнюється ~30 хв @100 Soldiers/Queen → SPI NOR W25Q32JV (4 МБ, ~$0.50, SOIC-8) як overflow tier; sector-based ring (~199k слотів ≈ 7 діб); pointers RTC DR20-21; drain Flash-first→RAM. Implementation Anchor resilience-policy на верхньому краю scaling. · [ ] 🔗 firmware ring-buffer + W25Q32 у Queen BOM (`02_05 §2.1`/§BOM)

#### ARCH.34 — Queen-side LoRaWAN Helium SOS fallback
- **P2** · 🔗 · → `06_08 §1.2`, `02_05 §6.1`
- Helium fallback перенесено Soldier→Queen (STM32WLE5JC flash/RAM/topology несумісний). Queen: LoRaMac-node stack + OTAA join state + FCntUp persist; SOS-маяк ~12 байт (НЕ телеметрія кластера — SF12 EU868 ~51B cap) → Helium hotspot → LNS → Rails `POST /telemetry/helium`. Soldier лишається raw LoRa P2P AES-128. Implementation Anchor L3; без нього L3 fallback архітектурно неможливий. · [ ] 🔗 Queen `queen_helium_lorawan_uplink()`

## §07 · Юридичні / Бізнес

> Юридично-бізнесовий work-stream — канон `07_xx`. NB: пов'язані BIZ-айтеми за канон-домом живуть у `§05` (BIZ.13 slashing) та `§08` (BIZ.5/10 IP, BIZ.12 Horizon-biodiv).

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

#### UNI.3 — IP договір з ЧНУ + patent filing (критичний шлях Статті 1)
- **P0** · 👤 · → `08_03`, `08_01 §2.1`
- 🛑 **Filing ПЕРЕД сабмітом Статті 1** (розкриває cascade/PCET механізм — embargo `08_01 §2`). Synergy-claims **draft готовий** ([`protocols/anchor/patent_claims_draft.md`](protocols/anchor/patent_claims_draft.md)) + пошукові запити ([`prior_art_queries.md`](protocols/anchor/prior_art_queries.md)). · [ ] 👤 юр-оформлення IP-договору ЧНУ + підпис · [ ] 👤 TISC ЧНУ: прогнати patentability-пошук (Sets 1-5; no-date/full-text/broad) · [ ] 👤 Кафедра ІВ: claims 1-9 → формальний UA/PCT формат · [ ] 👤 UkrNOIVI пріоритетна заявка → дата пріоритету (розблоковує сабміт)

#### UNI.4 — ChNU школа Мінаєва: DFT-моделювання EBFC
- **P1** · 👤 · → `08_01 §1.1`, `08_03 §1`
- Квантово-хім. симуляція streaming potential на TiO₂-гіроїді + адсорбція кислот ксилеми (школа Мінаєва, світовий DFT). Ціль: Q1 *Electrochimica Acta*; блокує seed credibility. · [ ] 👤 зустріч (через декана хімії) + NDA/IP (BIZ.10) + спільний грант MES/Horizon

#### UNI.5 — ChNU школа Гусака: дифузійна деградація 20-років (Kirkendall effect)
- **P1** · 👤 · → `08_01 §1.2`, `08_03 §2`
- Моделювання Kirkendall на Ti-6Al-4V/xylem + Arrhenius 12-тижн (школа Гусака, diffusion-controlled corrosion). Ціль: Q1 *Corrosion Science*; 20+ years claim. Залежить HW.3. · [ ] 👤 зустріч + спільний експеримент HW.3 + co-authored paper

#### UNI.9 — ChDTU Карапетян: Data Science колаборація
- **P1** · 👤 · → `08_02 §2`
- ChDTU R-кластер для ML; А.Р. Карапетян — статистика телеметрії (anomaly/fraud), магістерські. · [ ] 👤 зустріч (ChDTU rectorat) + кафедральна тема «Statistics of Bio-IoT Telemetry» + 2-3 магістерські (2026-2027) · [ ] 🤖 SLA R-кластеру (тренування `silken_forest.marshal`, post-TRL 7)

#### UNI.10 — ChDTU Гончаров (ФЕТР): RF верифікація + EMC pre-compliance
- **P1** · 👤 · → `08_02 §2`
- А.А. Гончаров (ФЕТР): VNA + анехоїчна камера для (a) SMD-антена під PEEK (HW.17), (b) Link Budget у лісі (SF7-9, 50-250м), (c) EMC pre-compliance CE/FCC (E.11). · [ ] 👤 зустріч + RF-лаб access + VNA-вимір PEEK-кришки (1.5/2.0/2.5мм) + Link Budget field test · [ ] 🔗 залежить HW.9 + HW.17

#### UNI.11 — ChDTU Базіло+Бондаренко (ПМКТ): акустична валідація фононної лінзи
- **P2** (P1 для Mongabay) · 👤 · → `08_02 §2`, `03_03 §10`
- ПМКТ (п'єзоелектрика + акуст. метаматеріали): EIS п'єзодиска 25-150кГц (cavitation) + верифікація гіроїдного phonon lens. Ціль: Q1 *IEEE TBME*. 🌿 Mongabay: + dawn/dusk Cherkasy Soundscape Library для 5-class TinyML «Fauna» (`08_01 §24a`). · [ ] 👤 зустріч Базіло+Бондаренко + EIS-протокол + acoustic стенд (HW.1) · [ ] 🌿 dawn/dusk recordings з UNI.13a (Спрягайло-Гаврилюк): AudioMoth, 4 сезони, ≥30хв dawn+dusk/ділянку, labeled таксони

#### 🌿 UNI.13a — ChNU Біо-хаб (Спрягайло+Гаврилюк): Acoustic Biodiversity Baseline (Mongabay)
- **P1** · 👤 · → `08_01 §1.3/§2`, `08_01 §24a`
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

#### UNI.15 — ЧНУ TISC engagement (патентний захист анкера + торгові марки)
- **P1** · 👤+🤖 · → `08_01 §2.1` · 🔗 UNI.1 (MoU)
- TISC ЧНУ (WIPO/УкрНОІВІ) замість комерц. бюро (~$3-8k): prior art search (гіроїд Ti-6Al-4V+PEEK у Espacenet/PATENTSCOPE), UA→PCT→EU/US консультації, ТМ (SilkenNet™/Gaia 2.0™/SCC™), ~5-10k UAH. Подачу робить патентний повірений (TISC порадить кандидата). · [ ] 🤖 зібрати prior-art query-set (коаксіальний гіроїд, EBFC mediator, LoRa mesh) · [ ] 👤 контакт TISC (Спрягайло) + auxiliary MoU + prior art search + знайти повіреного + UA utility model → PCT (12міс, post-TRL 6)

#### UNI.16 — ЧНУ Кафедра ІВ engagement (юридична експертиза RWA + токеноміки)
- **P1** · 👤 · → `08_01 §2.1` · 🔗 UNI.1 (MoU)
- Кафедра ІВ ЧНУ — точковий UA-юрисдикційний review (СЄУ §1F = макро): (1) RWA ERC-3643 vs Лісовий Кодекс/ПЗФ, (2) SCC/SFC за ЗУ «Про віртуальні активи» 2022 + MiCA 2024, (3) NaaS у UA Civil Code, (4) авторське право на `bio_contract.rb`/`Attractor`. Ціль: 2 меморандуми. · [ ] 👤 контакт зав. кафедри + workshop з Аблязовим (UA×MiCA) + меморандум RWA (розблок `07_01` BLOCKER-6) + меморандум SCC-класифікація + sui generis NaaS review

#### UNI.17 — ChDTU Хоменко (Кафедра металорізальних верстатів): прецизійна механіка + DMLS post-processing
- **P2** · 👤 · → `08_02 §2`
- Хоменко (Заслужений винахідник, 80+ патентів): прецизійна обробка + різьба анкера для живої деревини (`01_01`/`01_02`/`02_02`, deinstall `08_02 §3 Несен`) + патентний аудит. · [ ] 👤 контакт (ChDTU rectorat) + патентний аудит (UNI.15) + прототип різальної геометрії в ЧДТУ machine shop

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
- 🔗 блок: UNI.16 (Кафедра ІВ ЧНУ) + UNI.14 (СЄУ Аблязов). Перекласифікація анкера "втручання"→"науково-вимірювальний прилад" до прокуратури; кандидати через ННІ права ЧНУ (Кирилюк, `08_01 §1.4`). · [ ] 👤 identify candidate (Кирилюк+Аблязов) → узгодити legal opinion з UNI.16

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
- **P3** · 👤 · → `08_03 §2.1`
- Trigger: TRL 7 у `05_02` + Genesis onchain. 8 черкаських митців (Бабак, Теліженко, Афонін, Бондар, Іщенко, Олексенко, Касьян, Гладько); канал через А2 Теліженко (`08_02 §5`). · [ ] 👤 pre-screen (life status+active) → через А2 collective probe → Name&Likeness Release (UNI.14 Аблязов)

#### STK.9 — Cultural Tier B (National 8 artists): pre-launch outreach
- **P3** · 👤 · → `08_03 §2.2`
- Trigger: TRL 8 у `05_03`. 8 національних митців (Марчук, Чебаник, Микита, Сидоренко, Медвідь, Гуменюк, Гуйда, Ковтун) — старша когорта, зафіксувати window; hand-off PR-агентству. · [ ] 👤 verify life/health × 8 → gallery/agent кожному → pitch package (brief+animation)

#### STK.10 — Cultural Tier C (Media): Калініченко / Душок (ТРК Ільдана) — PR shield
- **P2** · 👤 · → `08_03 §2.3`
- Trigger: перед першою публічною інсталяцією. Превентивний інфо-фон проти екопанік («чіпують дерева»); Калініченко — викладач ЧНУ, міст із `08_01`. · [ ] 👤 через ЧНУ rectorat (Кирилюк `08_01 §1.4`) перший контакт → документальний міні-сюжет про DMLS-друк (post-prototype)

### ⚖️ IP / Grants (BIZ — канон-дім Модуль 08)

#### BIZ.5 — Patent application
- **P1** · 👤 · → `08_03`
- [ ] 👤 engagement з патентним адвокатом → патентна заявка на дизайн анкера

#### BIZ.10 — Multi-party IP Contract + NDA framework
- **P1** · 👤 · → `08_03`, `08_02 §3-07`
- 5-сторонній фреймворк (ChNU+ChDTU+ChIPB+ChMA+СЄУ+SilkenNet): bilateral NDA, IP-договір спільного авторства, патентні права, royalty. · [ ] 👤 патентний повірений (UA+EU) → bilateral NDA × 5 (паралельно UNI.4-14) → Master IP Framework Agreement · [ ] 🔗 після UNI.1/8/9/12/13

#### 🌿 BIZ.12 — Horizon Europe CLUSTER 6 заявка (Biodiversity Monitoring, Mongabay pivot)
- **P1** · 👤 · → `08_01 §24a`, `03_03 §10`
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
| DOC-T.1 | Документація AES master key суперечлива: `03_05` лінія 531-537 каже «навмисно не публікується», а лінія 538 натякає що перші 4 слова збігаються з FIPS-197 Appendix B test vector. Скоординувати після SEC.9 (заміна seed key) | `03_05`, `firmware/soldier/main.c:66-67` | Після SEC.9 видалити test-vector згадку, оновити обидва параграфи | ⏸️ Заблоковано SEC.9 |
| DOC-T.9 | Documentation `02_03` §9.3 raніше використовувала 15 mA/50 ms для LoRa TX. Виправлено на 120 mA/100 ms (~39 мДж) per SX1262 datasheet. Firmware energy accounting **не верифіковано незалежно** | `02_03`, `firmware/soldier/main.c` | Лабораторне вимірювання поточного TX (HW.x) + cross-ref у `02_03` після верифікації | ⏸️ Заблоковано лаб-стендом |
| DOC-T.10 | Реструктуризація 05/07 (Фаза 3) — відкладені misplacement-рішення: `07_01 §11` Investor Q&A (pitch/diligence — дім 00_01 vs новий pitch-doc неоднозначний); `07_03 §5` Anchor Assembly + `§6` Virtual Prototyping (operational/field-ops дім, наразі grant-bootstrap контекст — не чистий misplacement) | `07_01`, `07_03` | Призначити operational/pitch-дім + перенести (рішення founder) | 🟡 Deferred |
| DOC-T.11 | Реструктуризація 05/07 (Фази 1-2, 2026-05-30): slashing `00_01 §6` → `05_05`; governance `05_03 §749-905` → `05_06` — нові канон-доми; cross-refs re-pointed; `00_06 §2` / `00_00` / README синхронізовано (навігація: `00_01 §6` stub + `05_03 §Governance` stub) | `05_05`, `05_06`, `00_01`, `05_03` | — (виконано) | ✅ Done |
| DOC-T.12 | Taxonomy v3 P4 (2026-05-30): дисолюція Module 08 (7→3 доки). `08_03 Joint Pubs/IP`→**`08_01`**; `08_02 Cyber/Math`+`08_01 University`+`08_04-07`→**new `08_02` Academic Institutions Registry** (5 ВНЗ — relationship-шар; інженерна субстанція реферить Tier I 01–06, zero-loss verified); `07_05 External`→**`08_03`**. ~260 inbound refs swept; genuinely-novel mesh-математика → Open Research `06_08` (percolation/Markov). `00_00`/README/CLAUDE/`ssot-maintenance` skill синхронізовано | `08_01`, `08_02`, `08_03`, `06_08` | — (виконано) | ✅ Done |
| DOC-T.14 | **03_01 ↔ 03_02 semantic overlap** (виявлено `content_dup_audit.rb --near`, ≥88%): Queen RAM-budget, host-test-matrix, per-channel AES-таблиця дубльовані в обох firmware-доках — і вже тихо розійшлись (RAM: неузгоджений підсумок + stale pre-FW.3 буфери; test-matrix відстала на FW.1/FW.20/FW.20-S2/FW.27-B; AES nonce-клітинка + порядок рядків) | `03_01`, `03_02`, `03_05 §6` | ✅ Зведено (2026-06-03): Queen RAM → ref `03_02 §9`, Queen test-matrix → ref `03_02 §11`, AES-таблиця (обидва доки) → ref `03_05 §6`. 03_01 лишив Soldier RAM/тести + ECB-restore/HRNG impl-код; 03_02 лишив CRYP transition-діаграми | ✅ Done |

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
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.28, EVM cancun, optimizer 200 runs, CI/production profiles. 178 тестів у 6 test suites. Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
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
| E.50 | **Edge fuzzy_distance dedup function** на STM32WLE5JC: <1 мс CPU, <128 байт RAM, ціль — 30-40% TX зниження за рахунок suppression near-duplicate пакетів | `08_02` §1.3 (Vector 1, Ярмілко) | Post-TRL 7 (R&D — Ярмілко) |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1.2 (Vector 2) | Post-TRL 6 (Порубльов, ЧНУ) |
| E.52 | **GA-оптимізація ваг `silken_forest.marshal`** ML моделі на Akash GPU кластері — генетичний алгоритм для `InsightGeneratorService` stress_index класифікації | `08_02` §1.6 (Любченко) | Post-TRL 7 |
| E.53 | **VNA-вимір SMD-антени під PEEK радомом** — VSWR <1.5 на 868 МГц для 3-5 варіантів товщини PEEK (1.5/2.0/2.5 мм) у вологому/сухому стані + **3D Keep-Out з Ti-фланцем нижче** (Z-clearance 5/8/12 мм, з/без overhang за периметр Ti). Лабораторна задача (cross-ref UNI.10 ChDTU Гончаров, нова вимога `02_01 §5.3` revised) | `08_02` §1.3 + `02_01` | P1, blocked by HW.17 + UNI.10 |
| E.54 | **SOP документи для 7 типів EwsAlert** — стандартизовані інструкції UA+EN: severe_drought, insect_epidemic, vandalism_breach, fire_detected, seismic_anomaly, system_fault, entropy_anomaly. Інтеграція як inline UI у Phlex (cross-ref ARCH.31) | `08_02 §3` | P1, joint with ChIPB-NUTSU (UNI.12) |
| E.55 | **Multi-party NDA + IP framework** для 5-сторонньої академічної співпраці (ChNU + ChDTU + ChIPB + ChMA + СЄУ + Silken Net) — base-line для всіх UNI.x публікацій | `08_03`, `08_02 §3`, `08_02 §4`, `08_02 §5` | P1, cross-ref BIZ.10 |
| 🌿 E.59 | **Mongabay biodiversity pivot — acoustic D-MRV** — стратегічний pivot Silken Net від карбонового MRV до повноцінного D-MRV біорізноманіття після Delgado et al. (Nicoya Peninsula, 119 ділянок, 16 000 год аудіо; *Mongabay News*, травень 2026). Включає: (1) FW.4-EXT 5-class TinyML модель з класом `fauna_activity`; (2) FW.25 DSP log-mel з P1→P0; (3) UNI.11+UNI.13a Cherkasy Soundscape Library (ЧДТУ ПМКТ + ЧНУ Біо-хаб); (4) 08_02 §1 Macro-Micro verification (Бушин CNN + fauna feature); (5) 08_02 §1 NSGA-II multi-objective GA (Любченко); (6) 08_01 Стаття 24a co-authored Q1 publication; (7) Horizon Europe CLUSTER 6 (Biodiversity Monitoring) grant vector; (8) AiInsight#biodiversity_trend → ForestNFT metadata "biodiversity_score"; (9) ринкова диференціація — defensible moat проти Pachama/Sylvera/NCX (тільки Silken Net має micro-acoustic verification layer) | `03_03` §10 + `08_01` §1.3+§2 + `08_02` §1.5+§1.8 + `08_01` Стаття 24a | **P1 strategic** — координує FW.4-EXT, FW.25, UNI.11, UNI.13a |

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
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1.2 (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1.4 (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_02 §3` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `00_04` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1.1 (Vector 2, Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

## 🗄️ Архів закритих пунктів (мігровано в канон)

> Повністю завершені пункти, винесені з активного трекера 2026-05-28. Знання — у канонічних доках (стовпець «Канон»); повна історія — у git. Тримаємо лише вказівник для крос-реф цілісності (CLAUDE.md та живі пункти посилаються на ці ID).

| ID | Пункт | Канон |
|----|-------|-------|
| ARCH.42 | ATECC608B AES-128 vs AES-256 — DECIDED (Variant B) | `03_05 §3.7` |
| SEC.6 | ATECC608B Secure Element — оцінка інтеграції | `03_05 §3.7`, §3.4 |
| SEC.10 | Emergency-TX anti-replay frame counter (DR0 packing) | `03_02`, `03_01 §2` |
| SEC.11 | Lorenz Seed Provenance (DCI hardening, K_seed HKDF) | `03_04`, `03_05 §3.4а`, `04_02`, `05_02` |
| FW.5 | Lorenz β-пертурбація від delta_t/vcap (Variant B+) | `03_04`, `05_02` |
| FW.18 | TinyML confidence threshold (RTC DR13/14 dual-zone) | `03_03`, `03_01 §2`, `04_06` |
| FW.29 | Panic vs saturated acoustic disambiguation (PANIC_FLAG_BIT) | `03_03 §5.3` |
| FW.29-PACK | StatusByte layout collision fix (5-bit growth_points) | `03_01 §11.5`, `03_04 §4.3-5.2`, `05_02` |
| S6.12 | TokenomicsEvaluator oracle-guards audit (KYC all-paths) | `04_02`, `05_02` |
| BIZ.4 | DAO Governance (SilkenGovernor + Timelock) | `05_06`, `07_01` |
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

