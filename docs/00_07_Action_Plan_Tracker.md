# 00_07: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати **ТІЛЬКИ незавершене** — кожен пункт як **тонкий вказівник**: `ID · пріоритет · виконавець` + 1 рядок + **→ канон-реф**. Повний опис «як має бути» живе в каноні (`00_00`→`08_02 §5`), описаний **в одному місці**; 00_07 на нього посилається, **не дублює**.

**Правило одного місця (DRY):** редагуєш канон → онови залежні пункти 00_07 (за рефами); закрив пункт → онови канон + познач тут (✅ → **§🗄️ Архів**, вказівник ID→канон). Так апдейт робиться в одному місці, а референси ведуть, де ще синхронізувати.

**Структура:** **🚦 Critical Path** (P0-гейти перед мілстоунами) → **§00–§08 модуль-секції** (реєстр незробленого; **номер секції = канон-модуль першого рефа** — enforced `tracker:check` section-home guard) → **🔀 Cross-cutting** / **📌 Backlog** → **🗄️ Архів**. Документ — живий операційний інструмент.

---

> **Розмітка — дві осі (як у Projects V2: `Assigned Agent` + `Shape Up Stage`):**
> - **WHO** (хто робить *відкриту* роботу): `🤖` **Код/аналіз** — coding-agent самостійно (код/firmware/розрахунок/документ/тест) · `👤` **Операційна** — потрібен власник (hardware, фізична лабораторія, секрети, зустрічі, юрист, зовнішні UI/дашборди). Комбо `🤖+👤` — провідний перший, ОДНЕ написання.
> - **STAGE** (лайфсайкл, окремо від WHO): `⚪` **Не почато** · `🟡` **В роботі** (частково зроблено) · `🟢` **Готово-інертно** (host/код done, чекає bench-фліпу або активації за гейтом) · `🔗` **Заблоковано** (на іншу задачу/рішення) · `🌿` **Far-horizon** (post-TRL). Повністю done → **§🗄️ Архів**.

> **Форма пункту (стандарт — щоб трекер був однорідний):**
> - Заголовок: `#### ID — короткий заголовок`.
> - **Meta-line** (рівно один, перший рядок): `**PN** · WHO · STAGE · → канон-реф`. `PN` ∈ `P0`–`P3`; `WHO` = `🤖`/`👤` (комбо `🤖+👤`, AI-first; **НЕ** `👤+🤖`/`👤/🤖`); `STAGE` = `⚪`/`🟡`/`🟢`/`🔗`/`🌿` (рівно ОДИН, окремо від WHO); реф = канон код-спан або лінк із реальним `§X`, і **нічого після нього** (контекст типу `· ✅ ліцензія` → у Стан). Форма enforced `meta_form_violations` ([`00_06 §3`](00_06_SSOT_Documentation_Standard) — **HARD**); Module = §-секція, вже enforced.
> - **Тіло — тонкий вказівник, не копія канону.** Перший рядок тіла — **ЗАВЖДИ** `- **Стан:**` <суть/присуд + канон-pointer> (повний опис у каноні; для ⚪-пунктів — короткий опис стану «не почато»). Universal-форма (founder 2026-06-14): **НЕ** «✅ X»-лід / prose-лід / bare-checkbox-лід — однорідність трекера (enforced `verdict_lead_violations`, [`00_06 §3`](00_06_SSOT_Documentation_Standard) — **HARD** з 2026-06-14, усі 138 items на `**Стан:**`-ліді). Відкрите → `[ ]` (`[x]` done · `[~]` частково) з WHO-тегом. Bench/validation-чек-лист (runbook) лишається.
> - **Чекбокси — вертикальним списком.** Кожен residual окремим рядком `- [ ] WHO — …` (читабельність + чисті diff'и, без glue-ризику). **≥2 інлайн `· [ ]` в одному рядку — ЗАБОРОНЕНО** (HARD guard `inline_residual_runon`, [`00_06 §3`](00_06_SSOT_Documentation_Standard)); одиничний residual теж краще вертикально.
> - **Без change-history та volatile-лічильників у тілі** — «коли» тримає git (не `✅ (дата) …`-стіни), к-сть тестів/рядків дрейфує. Повністю закритий пункт → **§🗄️ Архів** (рядок `ID → канон`), не «товстий ✅».

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Critical Path — P0-гейти перед мілстоунами](#-critical-path--p0-гейти-перед-мілстоунами)
- [§00 · Process / IaC / SSOT-tooling](#00--process--iac--ssot-tooling)
- [§01–§02 · Hardware & Lab](#0102--hardware--lab)
- [§03 · Firmware](#03--firmware)
- [§03/§05 · Безпека (Edge crypto + Web3)](#0305--безпека-edge-crypto--web3)
- [§04 · Backend / API / UI](#04--backend--api--ui)
- [§05 · Web3 / Економіка / Slashing](#05--web3--економіка--slashing)
- [§06 · Deploy / Observability / Secrets / Ops](#06--deploy--observability--secrets--ops)
- [§07 · Юридичні / Бізнес](#07--юридичні--бізнес)
- [§08 · Академічна інтеграція](#08--академічна-інтеграція)
- [§08 · External Stakeholders (B2G / B2B / Cultural)](#08--external-stakeholders-b2g--b2b--cultural)
- [§08 · IP / Grants (BIZ)](#08--ip--grants-biz)
- [Cross-cutting · Doc-drift (DOC-T) — SSOT doc↔code + tracker form/tooling](#-cross-cutting--doc-drift-doc-t--ssot-doccode--tracker-formtooling)
- [Backlog (не блокери · довгострокові)](#-backlog-не-блокери--довгострокові)
- [Архів закритих пунктів (мігровано в канон)](#-архів-закритих-пунктів-мігровано-в-канон)
<!-- TOC:AUTO:END -->

---

## 🚦 Critical Path — P0-гейти перед мілстоунами

> Крос-модульний зріз **P0-блокерів** перед ключовими мілстоунами (тонкі ID-вказівники; повний опис кожного — у §модулі, **one place**). P1/P2 — у §модулях (DOC-T.24 виносить пріоритет нагору в секціях). 🤖-роботи — у 🔀 `DOC-T`.

- **Перед польовим деплоєм** (life-safety + security): `SEC.9` · `SEC.3` · `SEC.1`
- **Перед Web3 mainnet:** `S1.1` (GitHub CI secrets) · prod deploy-ENV → [`06_04`](06_04_Secrets_Checklist) (вкл. `SOLANA_RPC_URL` — інакше USDC на Devnet; guard ✅ E.47) · `S2.1`+`S2.2`+`S2.3` (Grafana після першого `/metrics`)
- **Hardware-гейт** (TRL 4→6): `HW.31` (BOM Королеви) · `HW.24` (100 DMLS) · `HW.23` (SLM-замовлення)
- **Academic:** `UNI.1` (лаб + публікації) · `UNI.8` (MSA / B2B legal)

## §00 · Process / IaC / SSOT-tooling

> Process-automation, Projects-V2/IaC та SSOT-tooling — канон `00_04`/`00_05`. P0-гейти — у 🚦 Critical Path.

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **P1** · 👤 · 🟡 · → `00_05`
- **Стан:** `trl_sync.yml` реалізовано — GraphQL Projects v2 + TRL≥5 architect-approval gate (OPS.9); чекає лише secret-provision, канон `00_05 §2.2`.
- [ ] 👤 створити `PROJECT_PAT` (project:write) + тест з issues
- [ ] 👤 (security) мігрувати `PROJECT_PAT` → GitHub App installation token (`GITHUB_TOKEN` не вміє Projects V2; `00_05 §2.2`)

#### OPS.2 — SSOT Integrity Guard
- **P1** · 👤 · 🟡 · → `00_05`
- **Стан:** `ssot_guard.yml` реалізовано (app/models·firmware·contracts·services; semantic `type:*` bypass) — `00_05 §2.3`.
- [ ] 👤 зробити required check на `main`

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **P1** · 👤 · 🟡 · → `00_04 §5`, `00_05 §6`
- **Стан:** Shape Up template + Projects V2 kanban-mapping реалізовано (R&D Cluster/Stage/Cycle + auto-routing; 4 кластери A/B/C/D) — `00_04 §5`, `00_05 §6`.
- [ ] 👤 перший betting cycle після UNI.1/UNI.8

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **P2** · 👤 · 🟡 · → `00_05 §5`
- **Стан:** семестр-мапінг реалізовано (Fall/Spring + TRL milestones + 15.VI; `trl_sync.yml` стемпить `Academic Semester`) — `00_05 §5`.
- [ ] 👤 узгодити календар з ФОТІУС (UNI.2) + створити `Academic Semester` single-select field у Projects V2

#### OPS.6 — Bootstrap scripts для GitHub Projects V2 + IaC initial sync
- **P2** · 👤 · 🟢 · → `00_05 §1.2/§6`
- **Стан:** `lib/github_bootstrap.rb` готовий (`FIELDS` SSOT, idempotent GraphQL diff, rake `github:bootstrap`, RSpec-покрито) — `00_05 §1.2/§6`.
- [ ] 👤 запустити `bin/bootstrap_github.sh` проти живого Projects V2 при setup/fork

#### OPS.7 — 00_07 → Projects V2 draft-issues sync (tracker-as-tasks IaC)
- **P3** · 🤖 · ⚪ · → `00_05 §1.2`
- **Стан:** Не почато — скрипт-парсер 00_07-пунктів (`#### ID` + meta-line + відкриті `[ ]`) → idempotent sync у Projects V2 draft-issues (поля з `lib/github_bootstrap.rb`: Module/TRL/Cluster/Appetite/SSOT Link). Спирається на канонну форму пункту (інтро 00_07) — стандартизація трекера = передумова; чернетки скрипта нема, founder відклав («як треба»). Канон `00_05 §1.2`.
- [ ] 🤖 парсер 00_07 → draft-issues (idempotent за ID; pri/executor/module → поля)
- [ ] 👤 прогін проти живого Projects V2

## §01–§02 · Hardware & Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.1 — nTop model → SLM+HIP factory (Anode Zone 1)
- **P0** · 👤 · ⚪ · → `01_01`, `01_02 §1.7`
- **Стан:** Не розпочато — фабрична генерація тризонного анкера: Zone 1 (анод-гіроїд) SLM+HIP, Zone 3 (катод-фланець) SLM/EBM, Zone 2 (PEEK) CNC + annealing 200–250°C. Канон `01_01 §1/§5.5`, `01_02 §1.6/§1.7/§3.6`. Паралельний code-as-CAD трек **PicoGK** (AI-агент-сумісна альтернатива nTop GUI, Git-friendly SDF; стек/переваги/псевдокод → `01_02 §6`). nTop-ліцензія ПЗ отримана ✅.
- [ ] 👤 Генерація TPMS gyroid geometry (65% porosity, **тільки для Zone 1**)
- [ ] 👤 **Вертикальна орієнтація пор** (`01_01` §5.5): головна вісь TPMS-комірки паралельна осі анкера (паралельно потоку соку)
- [ ] 👤 **Градієнт розміру пор** (`01_01` §5.5): центр 300–500 µm → периферія 100–150 µm при сталій пористості 65% — параметризація nTop cell size як функція радіуса
- [ ] 👤 Окреме креслення Zone 3 (катодний фланець ∅20–30 мм)
- [ ] 👤 STL/STEP файли → передати на SLM завод (Київ/Дніпро) разом з вимогою HIP-постпроцесу (`01_02` §1.7 + HW.23)
- [ ] 👤 **Build orientation specification** (`01_02` §1.6): BD ∥ довгій осі анкера, кут до build plate 0° ± 5°, externally only support
- [ ] 👤 **Карта обмежень покриттів** (`01_02` §3.6): передати заводу інструкцію — ZnO-Ta НЕ наносити на гіроїдні стінки Zone 1
- [ ] 👤 SEM criteria для приймання партії
- [ ] 👤 µCT-сканування для верифікації градієнту розміру пор (центр 300–500 → периферія 100–150 µm) при пористості 65 ± 2%
- [ ] 👤 HW.1.PicoGK: setup C# (.NET 7+, VS2022/Rider) + build PicoGK lib (`github.com/leap71/PicoGK`)
- [ ] 👤 HW.1.PicoGK: coding-agent пише `Zone1Anode` SDF-гіроїд (формула/псевдокод → `01_02 §6`)
- [ ] 👤 HW.1.PicoGK: Stage 1 SLA-gen через PicoGK ∥ nTop reference — порівняти STL на topology errors
- [ ] 👤 HW.1.PicoGK: per-species CEM 5 SKU (pine/oak/broadleaf/mangrove/tropical → [`00_08 §1.3`](00_08_Beyond_TRL9_Planetary_Roadmap))
- [ ] 👤 HW.1.PicoGK: migration gate (Q2 2026) — clean STL без BREP → SSOT `.ntop`→`.cs`
- [ ] 👤 HW.1.PicoGK: annular barbs SDF h=0.3mm для PEEK lock (`01_01 §4.3`, HW.26)

#### HW.23 — HIP postprocess specification for SLM anode
- **P0** · 👤 · ⚪ · → `01_02 §1.7`
- **Стан:** Не розпочато — HIP-постпроцес SLM-анода (920°C±20 / 100–150 МПа Ar / 2–4 год) закриває залишкові напруження + металургійну пористість (зародки втомних тріщин на 20-річному циклі). Блокує втомну міцність, довговічність (TRL 5). Канон `01_02 §1.7`.
- [ ] 👤 Передати специфікацію HIP-постпроцесу на завод (Київ/Дніпро) разом зі специфікацією SLM
- [ ] 👤 Перевірити наявність HIP-обладнання у заводу-кандидата (часто окремий підрядник)
- [ ] 👤 SEM/EDS до та після HIP — підтвердити закриття внутрішніх мікропустот
- [ ] 👤 Втомні випробування (Wöhler) у синтетичному ксилемному соку — еквівалент 5+ років фретингу

#### HW.24 — Staged validation gate (SLA → Ti-coin → full anchor)
- **P0** · 👤 · ⚪ · → `01_01 §6.1`
- **Стан:** Не розпочато — гейт «100 DMLS-анкерів лише після Stage 1 (SLA form&fit) + Stage 2 (Ti-coin in-vitro біохімія)»; передчасна 100-партія = методологічна помилка. Канон `01_01 §6.1`.
- [ ] 👤 **Stage 1 — SLA макети (5 шт):** друк прозорого фотополімеру (Form 3 або SLA-сервіс) для перевірки form & fit, ергономіки, Flush Mount step drilling, допусків press-fit «пластик-в-пластик»
- [ ] 👤 **Stage 2 — Ti-coins (~15 шт, ⌀10–15 мм або 10×10×1 мм):** SLM-друк + EAAE (з обов'язковим dehydrogenation bake `01_02 §1.3 Крок 5b`) → **Gen 2.0 анодний стек** (одношаровий dgrFAD-GDH + Os polymer в geniпin-chitosan-CNC матриці поверх fMWCNT, `01_03 §2.1`) + **Gen 2.0 катодний стек** (Laccase + nCoCuCeZIF nanozyme гібрид DET, `01_03 §2.2`) + **Nafion-g-PSBMA анти-resin coating** → in vitro CV/EIS у синтетичному ксилемному соку (рецептура від біо-хабу ЧНУ, [`08_02`](08_02_Academic_Institutions_Registry)). 30-day stability gate. Chloride tolerance test (0.25 М NaCl). UCST winter-lock тест (-10°C → +25°C цикл). 💡 **Electrode-дизайн:** замовити з «вушком» (отвір/виступ на краю) для кріплення потенціостат-кліпси без пошкодження активної площі (A_electrode = 2 см²). In-silico predictions для порівняння — `40_validate_vs_experiment.py` готовий. (`01_03 §3.7`)
- [ ] 👤 **Stage 3 — Full anchor (3–5 шт):** SLM+HIP анодних секцій, CNC PEEK-втулок, SLM/EBM катодних фланців, повний press-fit + EBFC у синтетичному соку
- [ ] 👤 **Stage 4 — Партія 100 шт:** після підтвердження Stage 3 — оптове замовлення для польових випробувань

#### HW.31 — Queen Antenna Split (868 LoRa tuned ≠ dual-band)
- **P0** · 👤 · 🟡 · → `02_05 §7`
- **Стан:** Рознесено в каноні — поз.11 wideband LTE-M/NB-IoT (700–2700 МГц, Kyivstar B1/B3/B7/B8/B20, опц. LTE+GNSS) · поз.12 LoRa 868 **tuned** 5 dBi fiberglass omni (OD8-868/ALL.4101); окремі RF-порти SX1262 vs SIM7070G, dual-band SMA відхилено (VSWR>2.5 @868 → −3-5 дБ EIRP). Канон `02_05 §7`.
- [ ] 👤 freeze поз.11/12 у BOM Королеви при 02_05 BOM freeze

#### HW.32 — BME280 environmental sensing + VPD confounder [ADR `02_01 §3.4`]
- **P1** · 👤 · 🟢 · → `02_01 §3.4`, `07_02 §1.3`
- **Стан:** BME280 (t°/RH/тиск, I2C за TPS22860) приземлено host-side — docs + `03_01` SENSE + TelemetryLog cols (structure.sql) + firmware pure-модуль `firmware/common/bme280.h` (datasheet Bosch §8.2 компенсація `Bme280_Compensate_T/P/H` + VPD FAO-56 Tetens `Bme280_Vpd_Index`, host-golden `test_bme280.c`) + VPD-gate/sap-term у backend (inert, ENV-calibration-gated). Wire: VPD = CCM wire-rev2 **byte 19 `vpd_index`** ([`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)). DCI-guard: VPD НЕ в Lorenz-Z. Канон `02_01 §3.4` (формула/шкала/bench-чеклист) · slashing-роль `05_05 §6/§7` · клімат-оракул `07_01` · калібрування ваг `05_05 §8`.
- [ ] 👤 bench: I2C bring-up `bme280_forced_read`, SENSE call-site вшивається з CCM-флипом, gate-timing, VPD-калібрування + PTFE-мембрана механіка (`02_02`)

#### HW.2 — Dual-scale roughness spec
- **P1** · 👤 · ⚪ · → `01_02`
- **Стан:** Не розпочато — dual-scale roughness spec (Sa 0.5–5 µm, Sv 50–500 nm) ще не передана на завод; блокує максимальний струм EBFC (TRL 5). Канон `01_02 §1.2/§1.5`.
- [ ] 👤 Підготувати factory spec з метриками
- [ ] 👤 Передати на завод
- [ ] 👤 Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **P1** · 🤖+👤 · ⚪ · → `01_02`
- **Стан:** Не розпочато — 12-тиж. Arrhenius-старіння у синтетичному ксилемі (ICP-MS Ti<0.1/Al<0.05/V<0.02 µg/cm², EIS<50%); відкритий конфлікт V-release Zone 1 (1.12 µg/cm²/yr, 56× over) — мітигація a/b/c. Блокує seed-раунд, whitepaper (TRL 5→6). Канон `01_02 §2/§2.5`. **In-silico precursor (HW.3.IS):** аналітичний Lamé + stress-relaxation → Ti↔PEEK press-fit виживає 20+ р ✅ та ±5% strain-cycling MD ✅ ([`SUMMARY`](protocols/ebfc/in_silico/SUMMARY.md) §HW.3.IS; strain → `01_03 §2.1`). Важка FEA/Prony → Гусак (`08_01` Стаття 2, `00_02 §4a`).
- [ ] 👤 Синтез штучного ксилемного соку (потрібен ботанік)
- [ ] 👤 Запуск 12-тижневого тесту
- [ ] 👤 ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] 👤 EIS degradation < 50%
- [ ] 👤 **V-release Zone 1 mitigation** (відкритий конфлікт, `01_02 §2.5`): голий Ti-6Al-4V ≈ 1.12 µg/cm²/yr V (56× over target), ZnO не можна на Zone 1 → in-vitro тест chitosan-matrix бар'єру (b) ± опція V-free сплав Ti-6Al-7Nb / Ti-5Al-2.5Fe (a)
- [ ] 👤 HW.3.IS: Prony-series relaxation-fit PEEK 450G (Maxwell-Wiechert, замінює 2-term E∞/τ оцінку script 50) → Гусак (`08_01` Стаття 2)
- [ ] 👤 HW.3.IS: barb-tip stress-concentration FEA → Гусак (важка механіка аутсорс, `00_02 §4a`; in-silico вже дав аналітичний Lamé-bound)
- [ ] 🤖 HW.3.IS: MD ion-permeation Ti²⁺/V³⁺ через PEEK-матрицю (MSD, класична MD як script 13) — підтвердити «корозія не отруїть ферменти 20р»; **НЕ DFT** (DFT лише single-jump NEB)

#### HW.5 — Enzyme lifespan + Gen 2.0 chemistry stack
- **P1** · 👤 · 🟡 · → `01_03 §1–3`
- **Стан:** In-progress — ціль: довгострокова стабільність біоелектрохімічного стеку у кислому ксилемі (pH 4.5–5.5) + повна імунологічна невидимість для CODIT-каскаду, термін **20–25 років**. Архітектура = Gen 2.0 (одношарова FAD-GDH; повний стек анод/матриця/катод/мембрана — канон `01_03 §1–3`; Gen 1.0 GOx+CAT+GA+PEG відкинуто як нежиттєздатна). In-silico Zero-Lab (TRL 3) ✅; фізичний Ti-coin in-vitro (TRL 4) pending.
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

#### HW.5.IS — In-Silico Stage 0 (Zero-Lab)
- **P1** · 🤖+👤 · 🟡 · → `01_03 §3.4`
- **Стан:** Zero-Lab in-silico (TRL 3) ✅ завершено (2026-05-25) — computational reverse-engineering хімії ДО Ti-coin (AlphaFold3+OpenMM+PySCF+scipy, Python→AI-clones); фізичний TRL 4 = Ti-coin in-vitro pending. Q1-paper (`08_01` Стаття 1): ①②④ ✅, ③ cathode borderline-robust (Ru λ=0.78) → текст сабміт-ready (publish-to-protect, UNI.3, `08_01 §2`). Канон `01_03 §3.4`; числа → [`SUMMARY`](protocols/ebfc/in_silico/SUMMARY.md)/[`PIPELINE_STATUS`](protocols/ebfc/in_silico/PIPELINE_STATUS.md). Хімічний working-backlog (CHEM.N + open computes) ↓.
- [ ] 👤 інфраструктура: workstation RTX 4090 ($5–10K) АБО cloud GPU (AWS p5.2xlarge / GCP g2-standard-12)
- [ ] 👤 Joint Q1-paper з Мінаєвим (`08_01` Стаття 1 — in-silico electron-transfer energetics; повна назва — дім `08_01 §1`) — текст draft-complete (`paper/`), сабміт-ready
- [ ] 👤 Fig 1 graphical-abstract (BioRender; code-draft є) + TOC-графіка
- [ ] 👤 фіналізувати cover letter (draft є)

##### 🧪 Chemistry-improvement notes (CHEM.N) — founder batch 2026-06-05, triaged + verified
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

##### 🔬 In-silico pipeline — open computes (script audit 2026-06-06; detail → `PIPELINE_STATUS`)
> All ~37 `tools/in_silico/scripts/` audited — almost all ✅ (cached). Open work captured here so we never re-audit; closed/superseded = 21 · 21c · 29 (honest limitations-points, not work).
- [x] ✅ 🤖 **Re-run chain DONE:** 24b FO-DFT → 25 → ③ k_DET rigor: borderline **robust to coupling method** (t_ij 0.00546 ~4× crude + 0.18 eV site-gap; old ×10⁵ excluded) → `SUMMARY` §Cathode / `PIPELINE` 24b
- [x] ✅ 🤖 **②/tunnelling robustness DONE:** 34b ωB97X ②-speciation (functional-robust: aqua>bis-Im>chloro reproduced) → `SUMMARY` §Cluster-Continuum · 28b dynamic-tunnelling ensemble (β·d 2.02±0.13; image_molecules PBC)
- [ ] ✨ 🤖 **Refinements (optional, per-script additional analysis):** outer-sphere λ_o ✅ (29c → total anode λ 0.76–0.86 eV phys-end, confirms lit 0.7–0.8) · aqua/bis-Im × substituents + ωB97X for the series (21e) · real ΔG in k_ET (25 — FO-DFT scenario now uses the 0.18 eV site-gap; lit/computed-λ rows still ΔG=0) · Cu/Ce λ refinement (35; B3LYP over-estimates Co spin-crossover) · Os-complex MD ensemble (27, not just FAD) · full hydration shell + COSMO-RS/MACE probe (34) · k_cat sensitivity (30/30b) · ③-borderline R_ct in EIS ✅ (31b → band ~0.002–230 Ω). ⚠️ **λ_o (29c) is radius/ε-dominated · EIS-③ R_ct (31b) is Γ×k_DET-dominated (×10⁵ band) → both COMPUTED 2026-06-06 + confirmed INDICATIVE, not clean computes** (kinetic competition k_DET~turnover, NOT a fixed R_ct; caches `outer_sphere_lambda.json` / `cathode_det_rct.json`)
- [ ] 🧹 🤖 **Method-hygiene (founder pipeline batch 2026-06-06, verified):** (B2) pH-protonation **already done** — every MD script (10/11/12/14/15) calls `addMissingHydrogens(pH=4.5)`, 14 per-species 4.2-5.8 (note's pH-7-default premise is wrong). (B1) FAD AM1-BCC on AF3 geom **mostly OK** — antechamber/sqm geom-opts at AM1 before BCC (raw AF3 not used verbatim); optional RDKit MMFF pre-opt = minor robustness, low. (B3) DRY: `md_utils.prepare_protein` exists but 5 scripts duplicate it inline (byte-identical → safe dedup) + no shared PBC trajectory loader (28b `image_molecules` is local) → low-risk refactor (⚠️ `image_molecules` for multi-mol graph, `make_molecules_whole` for single-protein RMSD — not blanket). (B4) Apple-OpenCL fast-math precision regression test → nice-to-have for publication-grade 100+ ns (→ CUDA), not needed for current RMSD-stability claims
- [ ] 🏔️ 🔗 **Capstones (Мінаєв):** ④ protein QM-cluster E° (extend 32) · CDFT coupling (> 24b, needs PyCDFT) · QM/MM explicit-water cascade
- [ ] ⏸️ **Deferred → Стаття 2/3 / on-data:** 11 (20–50 ns MD, reviewer-grade equilibration) · 13 (D_eff model; L4 already uses lit 2e-6) · 16 (PE-drift 1%, bigger box) · 40 re-run vs Ti-coin CV/EIS when in-vitro data lands (40 already has a docstring — the audit's "missing" was a grep-filter artifact)

#### HW.6 — Resin barrier + Flush Mount Installation
- **P1** · 👤 · ⚪ · → `01_04 §3`
- **Стан:** Не розпочато — резиноза блокує доступ до ферментів; корінь = інструмент свердління, не матеріал. Стратегія: (a) Flush Mount step drilling (анкер врівень, камбій цілий), (b) Microfrezing замість шнека (чистий розріз, без resinosis). Канон `01_04 §3` (+ біоміметичні покриття §4, anti-resin Nafion-g-PSBMA §3.4).
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
- **P1** · 👤 · ⚪ · → `02_03`
- **Стан:** Не розпочато — CJMCU-25570 може мати Li-Po дефолт (VBAT_OV 4.2V замість 5.5V для supercap) → перевірити/замінити 8 SMD-резисторів. Блокує фіналізацію схеми + PCBA. Канон `02_03 §4/§5` (calc + табл.) / §11 (checklist).
- [ ] 👤 Виміряти 8 резисторів мультиметром
- [ ] 👤 Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] 👤 Замінити SMD резистори якщо мисматч
- [ ] 👤 Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (7 блокерів)
- **P1** · 👤 · ⚪ · → `02_02`
- **Стан:** Не розпочато — фіналізація сліпого pogo-інтерфейсу, 7 суб-блокерів: напилення пінів Au + Hard-Gold ENIG на центральній площадці анкера (проти Ti↔Au гальванопари), spring force ~100г, байонет, O-ring/IP-клас, соосність, Z-stack tolerance (Pogo 50–70% страйк ∧ O-ring 15–25%). Канон `02_02` (§Підсумок audit + §1.2 CRITICAL центральна площадка / §3.5 Z-stack).
- [ ] 👤 HW.8.1: Матеріал напилення piн → Gold (Hard Gold, Au 0.76 µm)
- [ ] 👤 **HW.8.2 (NEW 2026-05-16): Hard Gold ENIG на центральній площадці анкера** (торець виводу шини Zone 1, ø 4–5 мм) — **обов'язково**, інакше золотий pogo притискається до голого Ti → гальванічна пара Ti↔Au → Rc drift > 500 мОм за 18–36 міс → cold-start fail. Передати specмапу селективного gold-plating заводу (~$0.05/анкер). Деталі — `02_02 §1.2` ⚠️ блок.
- [ ] 👤 HW.8.3: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
- [ ] 👤 HW.8.4: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
- [ ] 👤 HW.8.5: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression; цільовий клас IP (IP67/IP68) — затвердити (`02_02 §3.3`)
- [ ] 👤 HW.8.6: Допуски соосності (XY-площина) → Lead-in chamfer
- [ ] 👤 **HW.8.7 (NEW 2026-05-16): 1D Tolerance Stack-Up по Z-осі** — обов'язковий розрахунок RSS або worst-case envelope для PCB→Radome→O-ring→Zone3 stack так, щоб O-ring завжди компресував 15-25% **і** Pogo Pin завжди в 50-70% страйку (0.76-1.06 мм з 1.52). Без цього ~10-30% капсул йде у брак (О-ring under-compressed → water ingress, АБО Pogo under-engaged → Cold-Start Fail). Деталі — `02_02 §3.5`. **P0** для PCBA/анкер/Радом freeze.

#### HW.9 — PCB KiCad layouts
- **P1** · 👤 · ⚪ · → `02_01`
- **Стан:** Не розпочато — Soldier + Queen PCB KiCad layouts (блокується фіналізацією BOM + RF Keep-Out спекою); від HW.9 залежать HW.17/HW.20/HW.29 (B2B) + SE050 DNP-footprint. Канон `02_01 §8` (status) / §5.2–§5.3 (RF Keep-Out).
- [ ] 👤 Soldier PCB layout (KiCad)
- [ ] 👤 Queen PCB layout (KiCad)
- [ ] 👤 RF Keep-Out Zone verification

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **P1** · 👤 · ⚪ · → `02_03 §4`
- **Стан:** Не розпочато — захист від EBFC >5.5V (тривала інсоляція → overcharge supercap → деградація): верифікувати BQ25570 OV (VBAT_OV=5.5V) + TVS/zener backup. Блокує hardware safety (TRL 5). Канон `02_03 §4` (§Б Overvoltage).
- [ ] 👤 Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
- [ ] 👤 Додати TVS-діод або зенерівський обмежувач як backup

#### HW.13 — MPPT coefficient verification for EBFC
- **P1** · 👤 · ⚪ · → `02_03 §4`
- **Стан:** Не розпочато — MPPT 50% VOC занадто низько для EBFC (dgrFAD-GDH/Laccase, MPP 60–70% VOC; при 50% — масо-транспортні обмеження). Ціль 65%: R_OC1=10.0MΩ (VOC_SAMP→GND), R_OC2=5.36MΩ (VSTOR→VOC_SAMP) за TI SLUSBH2G §8.2.3.2 (⚠️ зворотна конвенція → 35%). Блокує max EBFC power. Канон `02_03 §4` (§А MPPT + anti-footgun).
- [ ] 👤 Зняти повну P-V криву (потужність-напруга) EBFC
- [ ] 👤 Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
- [ ] 👤 Визначити оптимальну фракцію (починати з 65%)
- [ ] 👤 Якщо потрібно — замінити R_OC1/R_OC2 (звіряти з TI Figure 42 та `02_03 §4` SSOT Convention block)
- [ ] 👤 **Cold-start R_int** (`02_03 §1.5`): виміряти R_int EBFC (V_OC + V@15µA); якщо > 12 кΩ → cold-start oscillation-loop → серійний стек 2× EBFC (A) / паралель (B) / LTC3108 DNP-footprint (C). Не замовляти 100 PCBA без DNP-LTC3108 до перевірки.

#### HW.15 — BMS + VBAT decoupling для SIM7070G
- **P1** · 👤 · 🟡 · → `02_05 §Пікові струми SIM7070G`, `§2.2.1`
- **Стан:** Module-level fix зафіксовано — 5-cap VBAT tank bank проти 2A-burst brownout (просадка <20mV, margin >35×; BOM поз.17–20). Лишається system-level: BMS/MPPT моделі в BOM + bench-звірка маркування SIM7070G + firmware PSM/eDRX. Канон `02_05 §2.2.1` (+ §Пікові струми).
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] 👤 Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [ ] 👤 PCB layout: розмістити C_BULK ≤ 10 мм від VBAT pin, HF caps впритул
- [ ] 👤 Оновити BOM (закупка 5 нових компонентів)
- [ ] 👤 Bench: фізично звірити маркування модему на прототипі = **SIM7070G** (не SIM7000G; найменування у firmware/BOM/`02_05` вже уніфіковано — лишилась лише фізична звірка)
- [ ] 🔗 Firmware: додати `AT+CPSMS` + `AT+CEDRXS` (PSM/eDRX, idle ~3 µA) у Queen flush-цикл — `03_02`

#### HW.17 — PEEK radome prototype (Деталь 4)
- **P1** · 👤 · ⚪ · → `02_01 §5.2`, `01_04 §5.5`
- **Стан:** Не розпочато — PEEK Radome (Деталь 4) ∅20–30мм на різьбі Zone 3 катод-фланця (НЕ анод): радіопрозорий купол + O-ring EPDM → IP68; керамічна антена ≥8мм Z-clearance + overhang за Ti-периметр (`02_01 §5.3`); anti-overgrowth shield виступ ≥3мм + R≥5мм + super-hydrophobic Fluoropel (`01_04 §5.5`). Блокує antenna protection, RF validation, Zero-Touch, cathode O₂-access. Канон `02_01 §5.2` / `01_04 §5.5`.
- [ ] 👤 KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] 👤 Визначити тип кріплення: різьба на **Деталь 3 = Катод** (НЕ Анод!) vs байонет
- [ ] 👤 Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] 👤 **HFSS-симуляція** з 3D-моделями Ti-фланця + PEEK-радома + чіп-антени (нова вимога 02_01 §5.3 revised) — VSWR < 1.8, gain ≥ −2 dBi
- [ ] 👤 Замовити PEEK прототип з виступаючим конусом ≥ 3 мм над корою + R заокруглення ≥ 5 мм (anti-overgrowth shield, `01_04 §5.5`)
- [ ] 👤 Super-hydrophobic coating: контакт із постачальником Fluoropel PFC-1601V або еквівалент, технологія nano-texturing
- [ ] 👤 Верифікувати RF performance (VSWR, КСВ) з антеною під радомом + з Ti-фланцем нижче (overhang тест)
- [ ] 👤 12-місячний польовий тест anti-overgrowth shield на тестовому дереві — фотодокументація щоквартально

#### HW.22 — Sterilization protocol (No EtO, split-cycle, botanical-level)
- **P1** · 👤 · ⚪ · → `01_04 §6`
- **Стан:** Не розпочато — terminal gamma 25 кГр неможлива (PTFE-GDL chain scission ≥10 кГр → flooding), тому **split-cycle**: ГІЛКА A (Ti+ферменти) UV-C + 70% EtOH → low-dose gamma 15 кГр; ГІЛКА B (PTFE-GDL+O-ring) автоклав/EtO; фінальна ламінація у low-bioburden ламінарі. **Рівень — ботанічний, НЕ медичний** (ціль: знищити дереворуйнівні гриби + зберегти ферменти; ❌ ISO 5 / SAL 10⁻⁶ / LAL = overkill для дерева). Блокує Stage 3→4 (польові). Канон `01_04 §6` (§6.3 pipeline / §6.5 verification).
- [ ] 👤 ГІЛКА A: тест активності ферментів до/після UV-C + 70% EtOH + gamma 15 кГр — деградація ≤ 20%
- [ ] 👤 ГІЛКА B: PTFE-GDL bubble-point до/після автоклаву/EtO — Δ ≤ 5%
- [ ] 👤 CV-вимір EBFC-струму до/після ПОВНОГО циклу (A+B+фінал) — деградація ≤ 25%
- [ ] 👤 Анти-гниль тест (*Trichoderma*/*Phanerochaete*, 14 діб) — ботанічно релевантний замість USP <71>; + low-bioburden settle plates чистого ламінара (без ISO 5)
- [ ] 👤 Обладнання: low-dose Co-60 (15 кГр) ГІЛКА A; автоклав/EtO ГІЛКА B; чистий ламінар (не ISO 5 LAF)
- [ ] 👤 Постачальник Co-60: Чорнобиль НДІ радіаційної медицини / Київ ІРОНЦ — low-dose 15 кГр (не 25)

#### HW.25 — PTFE-GDL membrane (Cathode)
- **P1** · 👤 · ⚪ · → `01_04 §5`
- **Стан:** Не розпочато — PTFE-GDL мембрана катода Zone 3 (e/d-PTFE, пори 0.2–1.0 µm, товщ. 20–100 µm, CA >110°): пропускає O₂, блокує воду — інакше катод задихається або flooding. Канон `01_04 §5`.
- [ ] 👤 Закупка зразків e-PTFE / d-PTFE (Gore-Tex industrial, Donaldson, або український постачальник)
- [ ] 👤 Стендовий тест breakthrough pressure: H₂O column 30 см → 1 м (повинна витримати ≥ 1 м)
- [ ] 👤 Електрохімічний тест: ORR-струм катода з PTFE-GDL vs без — порівняння продуктивності
- [ ] 👤 12-тижневий тест з імітацією дощу/росі — резистентність до flooding
- [ ] 👤 Сумісність O-ring (EPDM vs FKM) з PTFE та pH 4.5–5.5
- [ ] 👤 Метод ламінації PTFE на катодний фланець (без клеїв — механічний обтиск по периметру)

#### HW.27 — Dehydrogenation Bake: Hydrogen Embrittlement Mitigation (NEW 2026-05-16)
- **P1** · 👤 · ⚪ · → `01_02 §1.3`
- **Стан:** Не розпочато — вакуумний dehydrogenation bake (250°C±25 / 10⁻³ mbar / 3 год, within 2h of rinse) після EAAE: без нього brittle TiH₂ 5–50 µm → втомне руйнування. Контроль LECO RH404 H<100 ppm (ASTM B348 ліміт 150). Блокує втомну міцність гіроїда, 20+ років (TRL 4→5). Канон `01_02 §1.3` (Крок 5b) / §1.3a-C.
- [ ] 👤 Передати специфікацію Крок 5b заводу-підряднику (Київ/Дніпро) разом із протоколом EAAE
- [ ] 👤 Перевірити наявність вакуумної печі 200–300°C у заводу-кандидата (або стороннього subcontractor)
- [ ] 👤 LECO RH404 hot extraction analysis на тестовому купоні з кожної партії
- [ ] 👤 Втомне тестування Ti-coin Stage 2 (HW.24) — порівняння з/без dehydrogenation bake для підтвердження ефекту
- [ ] 👤 Ti-coin Stage 2 — замовити пару **bare + ZIF-coated** (chem-note triage 2026-06-06): порівняння деградації струму ізолює ZIF enzyme-stabilization → готовий «ZIF nanozyme as enzyme stabilizer» результат (→ Стаття 2 stability; доповнює, не заміняє, in-silico ET-механізм Стаття 1)

#### HW.29 — Board-to-Board Connector pair: Power Deck ↔ RF Deck (NEW 2026-05-16)
- **P1** · 👤 · ⚪ · → `02_01 §3.1`, `§5.3`
- **Стан:** Не розпочато — B2B-конектор Power Deck ↔ RF Deck (Samtec FTSH header + CLT socket, 1.27мм pitch SMD, 8–10мм stack, ~$0.85/пара): без нього RF Deck не отримує 3V3 (Pogo зайняті VIN_DC+GND). Альтернатива — rigid-flex (~+$1.50, усуває механічну точку відмови). Канон `02_01 §5.3` (+ BOM поз.12 §3.1).
- [ ] 👤 KiCad: place B2B footprints на обидві деки + перевірка signal integrity для 6-8 сигналів (3V3, GND, VSTOR_sense, EBFC_sense, piezo_EXTI, BQ25570 EN)
- [ ] 👤 Виміряти insertion loss + height variation на 5 зразках першої партії
- [ ] 👤 Pre-fabrication sanity check vs `HW.8.7` (B2B stack height впливає на Z-tolerance envelope)

#### HW.4 — Self-healing coating (NEW: zone-restricted)
- **P2** · 👤 · ⚪ · → `01_02 §3/§3.6`
- **Стан:** Не розпочато — 8-HQ self-healing мікрокапсули не синтезовані; наносяться **лише на неактивні поверхні** (Zone 3 сорочка, торці PEEK) — НЕ на Zone 1 гіроїд / катодну каталітичну грань (блокує DET). Блокує 20+ річні longevity-claims (TRL 6). Канон `01_02 §3/§3.6`.
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer — ТІЛЬКИ на дозволених зонах
- [ ] 👤 Тест: 10× вищий Rct
- [ ] 👤 **Thiol-Michael interphase** (`01_02` §1a.1): тест адгезії self-healing шару при ростовому навантаженні, порівняння з простою APTES-силанізацією — додано в `01_02`

#### HW.11 — Conformal Coating (Parylene C; Sylgard rejected — TinyML acoustic)
- **P2** · 👤 · 🟡 · → `02_01`, `02_02 §3.4`
- **Стан:** Рішення зафіксовано — **Parylene C 10 µm (CVD)** для серії + acrylic Humiseal 1A33 для прототипів; повний Sylgard-184 potting відхилено (акустичний демпфер 15–25 dB @ 16 kHz глушить TinyML-п'єзо). Acoustically transparent + IP67 з O-ring. Лишається вибір coating + verify. Канон `02_02 §3.4` (+ BOM `02_01 §3`).
- [ ] 👤 Обрати coating: Parylene C (production) + Humiseal 1A33 (prototypes)
- [ ] 👤 Контакт з CVD-сервісом Parylene-deposition (Київ / Львів — пошукати спеціалізовані PCB-house)
- [ ] 👤 Верифікувати п'єзо-attenuation: тест 16 kHz tone з/без coating на калібрувальному стенді
- [ ] 👤 Верифікувати з кварцовим резонатором при -20°C / +60°C (Parylene Shore D ~50, м'якший за air-gap воду)

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **P2** · 👤 · ⚪ · → `02_05 §Зимовий енергодефіцит`
- **Стан:** Не розпочато — Phase 3 (Starlink Mini) зимовий дефіцит: 44 Wh/добу спожив. vs 18.75 Wh генерації = −25 Wh/добу (LiFePO4 12V/20Ah → 7.7 днів автономності); Phase 2.5 (DTC) не зачеплено. Мітигації: 40Ah / 1-хв duty / 100W панель. Канон `02_05 §4` (§Зимовий енергодефіцит).
- [ ] 👤 Збільшити батарею до 40Ah (15 днів автономності), АБО
- [ ] 👤 Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
- [ ] 👤 Встановити 100W solar panel

#### HW.16 — Thermal management в IP67 enclosure
- **P2** · 👤 · 🟡 · → `02_05 §Теплове управління IP67`
- **Стан:** Тепловий бюджет IP67 зроблено (Phase 1/2.5 ~130мВт→ΔT<1K; Phase 3 3Вт→ΔT~4.5K; sun load +15K домінує → sun-shade) + backend critical-temp гілка (`GatewayTelemetryLog#critical_fault?`, T<−20°C → ❄️ EwsAlert) ✅. Лишається hardware зимовий charge-protect (NTC/DS18B20 + MOSFET). Канон `02_05 §4а`.
- [ ] 👤 Додати temperature sensor (NTC або DS18B20)
- [ ] 👤 Реалізувати hardware charge protection при T < 0°C

#### HW.18 — Starlink DTC: ESP32-S3 vs SIM8200G-M2 WiFi co-processor
- **P2** · 🤖+👤 · 🟡 · → `02_05 §Starlink DTC vs Mini`
- **Стан:** Decision memo зроблено — рекомендація **ESP32-S3** (~$3, near-zero sleep) над SIM8200G-M2 (5G марнується в лісі, ~20× дорожчий) для WiFi-мосту STM32→Starlink Mini (Phase 3 only). Лишається confirm + 03_02 firmware-контракт + co-proc прошивка. Канон `02_05 §Starlink DTC` (memo HW.18).
- [ ] 👤 Підтвердити рішення (рекоменд. ESP32-S3)
- [ ] 🤖 Оновити 03_02 з рішенням
- [ ] 🔗 Додати co-processor firmware до `firmware/`

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **P2** · 🤖+👤 · 🟡 · → `02_03 §12.4.2`
- **Стан:** Концепт верифіковано (DCI-safe) — добова VOC EBFC розрізняє «дерево хворіє» vs «конденсатор деградує» (обидва ростять delta_t); корекція живе на **slashing-шарі** (`ContractHealthCheckService`), НЕ в Z-математиці (інакше server-Z≠device-Z → fraud-flag щопакета). Реалізація gated на firmware VOC-вимір + delivery-контракт. TRL 8+. Канон `02_03 §12.4.2`.
- [ ] 🤖 Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] 👤 Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- [ ] 🤖 Backend (gated): `voc_mv` колонка + VOC-корекція у `ContractHealthCheckService` (виключити hardware-confounded дерева зі slashing-підрахунку), **НЕ в `Attractor`**. Чекає firmware VOC-вимір + delivery-контракт.

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **P2** · 👤 · 🟡 · → `02_03 §6`
- **Стан:** Рішення зафіксовано — MLCC замість тантала (виток 1–10µA вбивав би sleep-бюджет 1.5µA); фінал = **25V X7R 1210** (НЕ 6.3V X5R: DC bias −75…85% при 6.3V знищує ємність), 47µF для +14 dBm Сценарію C (BOM поз.9 `02_01`). Канон `02_03 §6` (§6.1 derating).
- [ ] 👤 внести фінальний part у KiCad BOM (HW.9)

#### HW.26 — PEEK Cold-Flow Creep: Mechanical Lock (NEW 2026-05-16)
- **P2** · 👤 · ⚪ · → `01_01 §4.3`
- **Стан:** Не розпочато — mechanical lock проти PEEK cold-flow creep (barbs h=0.25–0.4mm α30°/β70° + DIN 471 Ti retaining ring ∅0.8×0.6mm + hex ≤0.05mm; press-fit 150°C >T_g); без нього −60% contact pressure за 10р → втрата O-ring seal / вирив Zone 3. ~$0.30/анкер, комплементарний до §4.2 ΔCTE. Блокує 20+ річну надійність (TRL 7→8). Канон `01_01 §4.3`.
- [ ] 👤 Update nTop CAD-моделі: додати annular barbs на циліндричних частинах Zone 1 та Zone 3
- [ ] 👤 Update CNC-чертежі: retaining ring grooves на anchor end Zone 1 + flange end Zone 3
- [ ] 👤 Закупка DIN 471 internal retaining rings Ti grade 2 (або 316SS) у відповідних розмірах
- [ ] 👤 Update press-fit процедуру: temp 150°C (>T_g PEEK 143°C для Victrex 450G) + контрольована сила 800–1200 N
- [ ] 👤 **FEA-валідація** ANSYS LS-DYNA з visco-elastic PEEK Prony model — simulation 10y creep, residual pull-out > 200 N
- [ ] 👤 Stage 1 SLA-mock (HW.24): включити barb-detail у фотополімерну збірку для перевірки клацання

#### HW.28 — Anti-Overgrowth Shield для Zone 3 (NEW 2026-05-16)
- **P2** · 👤 · ⚪ · → `01_04 §5.5`
- **Стан:** Не розпочато — anti-overgrowth shield тримає Zone 3 катод відкритим атмосфері (ORR Laccase+ZIF-nanozyme): без нього за 3–5р кора накриває PTFE-GDL → O₂-дифузія стоп → EBFC мертва. Три захисти: (A) виступ PEEK Radome ≥3мм + R≥5мм, (B) super-hydrophobic coating (CA>150°, Fluoropel) або Cu-сплав, (C) forester maintenance 5–7р. Інтегровано у HW.17; OPEX → `07_02`. Канон `01_04 §5.5`.
- [ ] 👤 Update PEEK Radome CAD з виступаючим конусом — у HW.17
- [ ] 👤 Закупка/тест super-hydrophobic coating (Fluoropel PFC-1601V або аналог)
- [ ] 👤 Field protocol для forester visit: процедура зачистки приростаючої тканини без traumatic surgery
- [ ] 👤 12-місячний польовий тест на тестовому дереві (Черкаський бір)
- [ ] 👤 Update `07_02` OPEX: 1 visit / 5–7 років × $20/visit = ~$3–4/рік/анкер (форестер у Черкаському борі)

#### HW.30 — SMD Piezo + Acoustic Pad (Zero-Touch Wake) (NEW 2026-05-16)
- **P2** · 👤 · ⚪ · → `02_01 §6`
- **Стан:** Не розпочато — SMD-piezo (Murata 7BB-15-6L0 / TDK / Mallory) на нижній стороні Power Deck + Bergquist Sil-Pad 1500ST acoustic coupling до Ti Zone 3 → сигнал через B2B (HW.29) → BAT54S → EXTI; усе SMD (стара клеєна ∅27мм через-отв. з дротами порушувала Zero-Touch §5.2). Канон `02_01 §6` (+ BOM поз.5 §3.1).
- [ ] 👤 Вибрати SMD-piezo з 3 кандидатів (Murata/TDK/Mallory), компроміс sensitivity vs пасивний voltage swing на резонансі ~4 кГц
- [ ] 👤 Acoustic coupling test: SMD-piezo + Sil-Pad + Ti-coin → подаючи 16 кГц tone через анкер → виміряти voltage spike на p'єзо vs стара ∅27 мм через-отв. архітектура
- [ ] 👤 Verify EXTI wake-on-vibration latency vs стара через-отв. baseline (target < 5 мс)
- [ ] 👤 **Interrupt-storm mitigation** (нот.5): амплітудний поріг — hardware comparator/RC АБО software fast-amplitude gate, щоб вітер/дощ/гойдання гілок НЕ будили повний аудіо-цикл → drain-захист 0.47 F supercap (поточно лише `BAT54S` voltage-clamp, без порогу; `03_03 §1.2`)
- [ ] 👤 Lifecycle test: Sil-Pad creep під 30-40% compression × 20 років (Arrhenius accelerated)

#### HW.21 — Hybrid energy R&D: TEG + Anchor stacking (post-TRL 6)
- **P3** · 👤 · 🌿 · → `01_03 §6`
- **Стан:** Far-horizon (post-TRL 6) — два доповнювальні джерела проти зимового енергодефіциту: (a) TEG Bi₂Te₃ ~50–200 µW зимою (ΔT 15–25 K), (b) stacking 3–4 анкерів (V_OC ×3–4, для арктичних/кластерних). Одно-анкерна Gen 2.0 архітектура вже задовольняє BQ25570 cold-start 330 мВ → TRL 7+. NB: SolarBotanic «nano-leaves» не інтегруємо без peer-reviewed per-node даних. Канон `01_03 §6`.
- [ ] 👤 TEG: вибір модуля Bi₂Te₃ (4×4 см), стендовий тест ΔT-V кривої на тестовому стовбурі
- [ ] 👤 TEG: інтеграція з BQ25570 multi-input (можливість одночасного MPPT для EBFC + TEG)
- [ ] 👤 Stacking: 3-анкерна тестова конфігурація на одному дереві з PEEK-ізоляцією (Zone 2)
- [ ] 👤 Stacking: оцінка впливу на провіженінг (групова реєстрація DID) та Lorenz-аналітику (декомпозиція V_OC)
- [ ] 🔗 Залежить від HW.13 (P-V крива EBFC) для правильного бюджетування доповнення

## §03 · Firmware

#### FW.2 — AES-128-ECB → AES-128-CCM (28B packet, wire-rev2) [post-ARCH.42]
- **P0** · 👤 · 🟢 · → `03_05 §2.1`
- **Стан:** AES-128-CCM 28B wire-rev2 (8B AAD + 12B ciphertext + 8B MIC) — дизайн + backend-парсер (`process_ccm_chunk` / `Cryptography::LoraCcm`) + firmware freeze-contract emit/decrypt + TRL-7 monotonic FC Flash high-water (`fc_hiwater.h`, KV `0x14`) host-готові, KAT-parity з OpenSSL. **INERT** за `FW2_CCM_ENABLED` / `TELEMETRY_CCM_ENABLED` (ECB живий у проді). FC/nonce/cold-boot (📐 ЄДИНЕ ДЖЕРЕЛО) + 28B wire + budget-ledger — канон [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security). Закриває ECB→CCM/MIC/replay + SEC.10 panic + FW.29; LoRa-ключ у SE050 (SEC.6).
- [ ] 👤 bench: верифікувати `CRYP_AES_CCM` на STM32WLE5JC REVB (RM0461 §27.4; атестація скриптована — RUNBOOK §2 + `02_selftest_attest.py`) + Flash-KV HAL-глю (спільний bench з FW.8/FW.17) → flip обох гейтів = **ЄДИНИЙ HW-залежний пункт**

#### FW.4 — TinyML `Run_Inference()` — ✅ self-owned baseline landed (machine half); bench-confirm residual
- **P0** · 👤 · 🟢 · → [`03_03 §4`](03_03_TinyML_Acoustic_Inference)
- **Стан:** self-owned ESC-50 baseline приземлено (машинна половина) — `silken_net_audio_model.h` (INT8 forward-pass, gemmlowp, **972 B Flash / ~0 .bss / 76 B стек** << arena-стелі 7–15 КБ) + `Run_Inference` call-site розкоментовано + host-тест зелений; log-mel DSP (FW.25/FW.46, soft-float) живить його. Канон [`03_03 §4`](03_03_TinyML_Acoustic_Inference) (примирення TFLM↔CMSIS-NN §4.1; **silence+cavitation = синтетичні placeholder'и, НЕ field-валідовані** §4.2; точність = pipeline-integrity-метрика, run-provenance `tools/ml`). ML-партнерів нема → модель НАША end-to-end; апгрейд опційний.
- [ ] 🔗 ARM `arm-none-eabi-size` реальної arena — CI hal_check lane після board-freeze (FW.46)
- [ ] 👤 bench-формальність: silicon float32-confirm CMSIS-шляху (один прогін на платі)
- [ ] 👤 (опц.) польова/партнерська модель замінює header (Бушин CNN + Любченко NSGA-II + Cherkasy soundscape) — апгрейд, НЕ блокер
- [ ] 🌿 FW.4-EXT (post-TRL 7): 5-й клас `fauna_activity` dawn/dusk ([`03_03 §10`](03_03_TinyML_Acoustic_Inference)), залежить від UNI.11+UNI.13a

#### FW.25 — TinyML DSP-path: Path B (log-mel) SELECTED [DECISION 2026-05-22]
- **P0** · 🤖+👤 · 🟢 · → [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)
- **Стан:** Path B (log-mel) обрано + DSP-фронтенд реалізовано self-owned (ML-партнера нема, контракт наш end-to-end): `Compute_LogMel` (`firmware/common/logmel.c`) + 3-way parity librosa≡stdlib≡C (`contract_hash` tripwire) + golden-vector host-тести + auto-gen таблиці (`silken_ml.codegen`). Контракт доукомплектовано бюджет-конвертом моделі (arena target ≤ 10 КБ, тверда стеля 7–15 КБ §6, INT8 обов'язковий, «топологію під стелю»; Path C-фолбек звузився під тим самим леджером); baseline приземлено (FW.4) → DSP-фронтенд живить реальний інференс. Канон: decision-matrix [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) · контракт + бюджет-конверт [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference).
- [ ] 👤 опційний апгрейд: ML-партнер (Бушин/Любченко) тренує 5-class CNN на §3.4 (крос-чек, не гейт)
- [ ] 🌿 UNI.11+UNI.13a soundscape dataset (dawn/dusk fauna 5-й клас)
- [ ] 🤖 fallback Path C (TFLM) — лише після повторного FW.26-заміру з TFLM-обвісом ([`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) противага)

#### FW.49 — Tick-time ≠ wall-time у STOP2: системна семантика таймерів Soldier
- **P0** · 🤖+👤 · 🟡 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** wake-source ADR вирішено + S1-wiring host-shipped. `HAL_GetTick` заморожений у STOP2 (tick-`delta_t` міряв лише active-час → over-mint Proof-of-Growth); лік = RTC WUT + Vcap-енергогейт + RTC-календар timebase. Host: `Wall_Seconds_Now`/`Wall_Calendar_Set` (`wall_time.h`, civil↔unix roundtrip, free-running до синку), delta_t мігровано на wall-секунди (guard-и cold-start/назад/стрибок-епохи → baseline), cold-start epoch_day wall-first, wire `dT:2` сатурація @0xFFFF (wall-дельти бувають добами). Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA) (S1 + tick≠wall) + [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA) (wake-source ADR). ⚠️ **bench-gated residual:** LSE/RTC clock-tree (`MX_RTC_Init`) у repo відсутній — `Wall_Seconds_Now` на кремнії поверне 0 (чесна відмова → baseline) до bring-up.
- [ ] 🔗 **S2:** RTC-WUT-tick + Vcap-енергогейт → delta_t = справжній час перезаряду (чекає шкали ↓).
- [ ] 👤 **bench bring-up:** LSE 32.768 кГц + `MX_RTC_Init` (календар + WUT-IRQ STOP2-wake) + верифікувати `Wall_Seconds_Now`/recharge-інтервал (RUNBOOK §3-4: `04_lse_drift.py`, `03_power_profile.py`).
- [ ] 👤 🔴 фізика-блокер E.63 (Мінаєв/bench): шкала delta_t — L4 очікує **36-190 с**, а [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет дає **1.77 год** (P_gen=15µW); якщо ~1.77 год — метаболічний сигнал плоский (`metabolic_health(delta_t)`→GP майже константа, живе лише при L4-потужності EBFC). Cross-ref: E.63, FW.50, FW.20, FW.27-B, FW.30

#### FW.50 — Vcap ADC: raw counts використовуються як мВ (без конверсії)
- **P0** · 👤 · 🟢 · → [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** знахідка + helper канонізовано. Сирий 12-bit VREFINT-відлік (~1500; канал = VDDA за buck'ом, не Vcap EDLC) трактувався скрізь як мВ → RX-вікно (`VCAP_LISTEN_THRESHOLD=2800`) глухе НАЗАВЖДИ (OTA/mesh/time-sync/ротація мертві на кремнії) + Vcap-енергогейти з фейкових величин. Лік (рішення founder): `vcap_voltage = Adc_Vdda_Mv()` = чесні мВ VDDA (≈3300 поки buck живий) через factory VREFINT-cal (`adc_convert.h`, One-Home + host-тести); вухо відкрите, fauna-гейт (`FAUNA_VCAP_MIN_MV=4500`) чесно зачинений до живого Vcap-каналу; попутно знято VSTOR↔VBAT_SEC дрейф у [`02_03`](02_03_BQ25570_MPPT_Nano_Power). Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 схемна вилка: розводка Vcap на окремий ADC-пін (цільовий тракт BQ25570 **VBAT_SEC** — [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM); дільник-номінали — [`02_03`](02_03_BQ25570_MPPT_Nano_Power): десятки МОм bleed vs TPS22860-гейт).
- [ ] 👤 bench-калібрування (DMM-точки vs `Adc_Raw_To_Mv` — RUNBOOK §3.4).

#### FW.3 — Queen AT Command Blocking
- **P1** · 👤 · 🟢 · → `03_02 §4`
- **Стан:** Queen AT-blocking закрито архітектурно (host) — RX-кільце circular-DMA (`uart_rx_ring.h`: абс. лічильники, монотонний clamp, overrun-детект → запізнілі URC/`+CCOAPNMI` більше не гинуть в ORE) + early-exit AT-токенайзер (`at_engine.h`) + host-built CoAP PDU (`coap_pdu.h`) + оркестратор (`sim7070_coap.h`); канон [`03_02 §4`](03_02_Queen_Gateway_Firmware) (incl. FW.56-знахідка «модем = UDP-труба, не CoAP-стек»). **FW.3 — чисто bench.**
- [ ] 👤 bench: реальні SIM7070G таймінги (RUNBOOK 5.1/5.2) + кремній DMA-вуха (DMAMUX/NDTR/TC; one-command `06_uart_dma_ears.py`, RUNBOOK 5.4)

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- **P1** · 👤 · 🟢 · → [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)
- **Стан:** OTA firmware broadcast автентифіковано HMAC-SHA256 dual-gate проти ECB-без-MAC — підмінений bytecode з валідним CRC32 відсікається. Per-cluster K_ota (HKDF `silken-ota-hmac-v1`, Protected Flash стор. 125 `0x0803E800`) → `OtaPackagerService` 4× `[0x9B]` trailer (3 печатки + version-envelope; anti-replay/truncation) → Queen stateless relay → Soldier `OTA_Verify_Dual_Gate` (magic `RITE` + constant-time HMAC + fail-safe magic-wipe). Live-compute зашито обабіч: wire `OTA_Try_Finalize` (`Silken_Hmac_Sha256_Concat`, фіналізація з обох RX-гілок) + factory-тракт Гілка A `CommandBuilder` (KOTA-блок). **Знахідка-розкол:** до ревізії K_ota емітувала лише superseded ATECC-гілка B → Гілка A випускала б дерева з вічно fail-closed OTA (claim-vs-code drift, виправлено). SE-резидентний K_ota → SE050-MIGRATION. Канон [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning).
- [ ] 👤 bench: фізичний `factory:execute` (SWD, KOTA вже у транскрипті) + e2e dual-gate на STM32 (APPLY/REJECT) — RUNBOOK §2.5

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- **P1** · 🤖 · 🟢 · → [`03_03 §4.3`](03_03_TinyML_Acoustic_Inference)
- **Стан:** TENSOR_ARENA верифіковано — реальний ARM static-RAM CI-гейт `[FW.26]` (`check_ram_budget.sh --hal-objects` через FW.46 compile-lane, per-TU бюджети 8 192/20 480; arena ляже у `.bss` і зірве гейт → свідома ревізія) над виміряним RAM-леджером (mruby 38 392 — FW.55-вимір зняв «~4КБ»-міф → **стеля tensor arena ≈ 7–15 КБ**; стара умова «>46KB→overflow» була на міфі; бриф ML-партнерам arena ≤ 10 КБ). FW.4 baseline приземлено: forward-pass **972 B Flash / 0 .bss / 76 B стек** << стелі (prune/кап не знадобились). Канон леджера [`03_03 §6`](03_03_TinyML_Acoustic_Inference) + arena-оцінка [`03_03 §4.3`](03_03_TinyML_Acoustic_Inference) + build [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 🔗 ARM `arm-none-eabi-size` на повному `.elf` (`.bss+.data` після HAL-link; ELF-режим гейта готовий, per-target 14 800/40 960) — після FW.46 board-freeze

#### FW.46 — Enterprise-grade ARM firmware build (committed, reproducible, CI cross-compile)
- **P1** · 🤖+👤 · 🟢 · → [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** owned-code foundation host/CI-готова (`ci.yml › firmware_arm_build` зелений) — відтворюваний CMake крос-компайл того, чим володіємо: `cmake/arm-none-eabi.cmake` (Cortex-M4 **soft-float** — WLE5 без FPU, FPU-міф знято), `logmel.c` під ARM (~6.3KB), **mrbc** `bio_contract.rb`→`lorenz_bytecode.h` + drift-gate + minimal-VM harness, host↔target RFFT parity, mruby minimal-gembox (double + NO_BOXING-пін, ~117KB Flash). **HAL compile-lane** (`-DSILKEN_WITH_HAL=ON`): pinned WL-HAL submodules + `hal_glue/` wrapper-TU компілюють обидва `main.c` проти справжнього HAL — зловив одразу `__HAL_RCC_CRYP_*`→`__HAL_RCC_AES_*` (F4-стиль не існує на WL → Soldier STOP2-цикл + Queen `Restore_ECB_Mode` впали б на лінку). 🔴 повний HAL-лінкований `.elf` ще НЕ зібрано (board-freeze поза репо). Канон [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 board-freeze → `.ioc` (CubeMX): тіла `MX_*`/`SystemClock_Config` (пін-мапа/клок/ADC/LSE — FW.49/FW.50) + SubGHz_Phy middleware (з реєстрацією `RadioEvents_t`! зараз `Radio.Init(NULL)` — латентний баг Queen RX) + startup/ld → повний Soldier/Queen `.elf` + bench flash-verify
- [ ] 🤖 flip FW.26 на повний `.elf` після HAL
- [ ] 🤖 (optional, far-future) toolchain pin via ARM-tarball ([`00_08`](00_08_Beyond_TRL9_Planetary_Roadmap))

#### FW.55 — QEMU-M4 bit-parity lane: ARM↔x86 mruby double residual → CI
- **P1** · 👤 · 🟢 · → [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** QEMU-M4 bit-parity lane (`qemu-system-arm -M mps2-an386`, той самий `libmruby.a` + software-double `__aeabi_d*`, що піде на WLE5) ганяє committed-байткод реальним Cortex-M4 код-шляхом → **byte-exact** проти host-голдена (зчеплені кейси — хаос ампліфікує ULP), закриває FW.7/FW.19 ARM↔x86 Float-drift до тонкого silicon-confirm. Дві ноги (mruby + log-mel CMSIS, обидві soft-float) + заскриптована кремнієва нога `wle5_bench` (`05_parity_dump.py`). **64КБ фіт-гейт у CI зловив 4 девайс-знахідки** до кремнію (червоний 102400 → плато sbrk 38392 Б): ① runner arena save/restore; ② `MRB_CONSTRAINED_BASELINE_PROFILE`; ③ newlib-nano; ④ **`MRB_NO_BOXING` явний пін** — канон FW.19 «дефолт=NO_BOXING» був ХИБНИЙ (mruby 4.0 дефолт = `MRB_WORD_BOXING` → ~20.5КБ RFloat-транзієнту/виклик на ARM32), фіт-гейт тепер = CI-enforcement FW.19; + бонус per-wakeup `mrb_full_gc`. RAM-леджер виведено у FW.26 / [`03_03 §6`](03_03_TinyML_Acoustic_Inference). Канон [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA) (lane) + §12.4 (піни); межі ISA≠кремній = клас C (bench).
- [ ] 👤 silicon-confirm: один прогін на платі — `bench/05_parity_dump.py --plan` (flash `parity_wle5.elf` → дамп по VCP → вердикт скрипта)

#### FW.56 — Queen CoAP AT-граматика ≠ SIMCom: модем = UDP-труба, PDU будує хост
- **P1** · 👤 · 🟢 · → [`03_02 §4`](03_02_Queen_Gateway_Firmware)
- **Стан:** SIMCom CoAP App Note ≠ firmware-припущена граматика — реально модем = **UDP-труба**: хост будує сирий RFC 7252 PDU (`CCOAPNEW`/`CCOAPSEND` hex / URC `+CCOAPNMI`, домени через `CDNSGIP`). Три pure-шари + UART-клей (`uart_rx_ring.h` circular-DMA FW.3 / `at_engine.h` токенайзер / `coap_pdu.h` CON-PUT builder+parser golden-vector / `sim7070_coap.h` оркестратор) + host-тести. e2e Queen-PDU↔backend CoAP-intake софтом (golden C-білдер ↔ Rails-парсер + pure `CoapServerPdu` + повний ланцюг до `UnpackTelemetryWorker`). **Зловив/закрив 2 продакшн-баги Брами:** глобальний пошук payload-маркера (кожен 256-й `coap_mid` = фантомна доставка → FW.51 чистив кеш дарма) + Sentinel `route_queen_health` гинув на Sidekiq strict_args під broad-rescue; ACK-семантика тепер чесна до FW.51 (2.04 лише після enqueue, 4.04/RST → Королева тримає кеш). Канон [`03_02 §4`](03_02_Queen_Gateway_Firmware).
- [ ] 👤 bench: verbatim-звірка SIM7070-ноти V1.03 + реальні URC/таймінги
- [ ] 🔗 staging-smoke прогін проти задеплоєної Брами (`coap_smoke.yml` post-deploy gate; `bin/coap_smoke` + pure `lib/coap_smoke.rb` freeze-contract готовий — байт-звірка golden-векторів e2e: RST на сміття, 4.04 з 0xFF-MID піном, 2.04-після-enqueue; loopback-довід `coap_smoke_spec.rb`)

#### E.59 — Mongabay biodiversity D-MRV pivot (acoustic fauna) [strategic]
- **P1** · 🤖+👤 · 🟡 · → `03_03 §10`, `08_01 §1`
- **Стан:** Стратегічний pivot carbon-MRV → biodiversity D-MRV (acoustic), після Delgado et al. (Nicoya, 119 ділянок, 16000 год аудіо; Mongabay, тр. 2026). Defensible moat проти Pachama/Sylvera/NCX (єдиний micro-acoustic verification layer). Координує вже-трековані: FW.4-EXT (5-class TinyML + `fauna_activity`), FW.25 (log-mel P1→P0), UNI.11+UNI.13a (Cherkasy Soundscape Library), BIZ.12 (Horizon CLUSTER 6 grant), 08_01 Стаття 24a. Канон `03_03 §10` + `08_01 §1/§2` + `08_02 §1B`.
- [ ] 🤖 FW.4-EXT: 5-class модель з `fauna_activity` (розширення FW.4)
- [ ] 👤 AiInsight#biodiversity_trend → ForestNFT metadata "biodiversity_score" (`04_02`)
- [ ] 🔗 координація UNI.11/UNI.13a (soundscape) + BIZ.12 (Horizon) + 08_01 Стаття 24a

#### FW.18b — OTA threshold invalid counter (production-visibility)
- **P2** · 👤 · 🟢 · → [`03_03 §5.4`](03_03_TinyML_Acoustic_Inference)
- **Стан:** OTA-поріг validation + invalid-counter — `TinyML_Apply/Validate_Threshold` (NaN/out-of-range/інверсія → default; інваріант `SILENCE<WARNING<CRITICAL`) + saturating `tinyml_threshold_invalid_count` (байт 11 `[thr_invalid:5|TTL:3]`; CCM-дім `diag` byte 18) + backend-метрика `silkennet_tinyml_threshold_invalid_reports_total` (без per-DID — [`06_03 §2.9`](06_03_Prometheus_Observability)) + Grafana IaC (`deploy/grafana/`, `import.rb` ідемпотентний) — host-done + канон [`03_03 §5.4`](03_03_TinyML_Acoustic_Inference).
- [ ] 👤 запустити `deploy/grafana/import.rb` (Grafana Cloud токен + notification policy + verify на живих метриках) — разом із S2.2/S2.3

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- **P2** · 👤 · 🟢 · → [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** per-species Lorenz Z-пороги OTA — Rails `build_threshold_config_block` + `effective_lorenz_thresholds` 3-tier (cluster→family→global 2.0/45.0/29.0) + firmware parser CMD `0x9A` (freeze-contract, `FW8_PARSER_ENABLED 0`) + persist Flash-KV (`lorenz_thresholds.h`, ключі `0x10/0x11`) + mount/wiring (`main.c`, спільний гейт із FW.17) — host-done + канон OTA-design [`05_02 §4а`](05_02_Proof_of_Growth_Pipeline) / persist [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA) / service [`04_02`](04_02_Business_Logic_and_Services). Production-dispatch `0x9A` свідомо deferred (TRL-6 — усі дерева на дефолтах).
- [ ] 👤 bench: фліп `FW8_PARSER_ENABLED 1` + HAL-глю на кремнії (спільний bench з FW.17/FW.2)

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- **P2** · 👤 · 🟢 · → [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** Hash-Ratchet ротація LoRa-ключа (NIST SP 800-108 HMAC-KDF, pure-C SHA256 — ключ ніколи не летить ефіром) закриває «статичний ключ → немає ротації без re-flash» (backward secrecy; GDPR/ISO 27001/NIST SP 800-57). Freeze-contract + інтеграція написані обабіч, host-done: firmware `key_ratchet.h` ↔ `Cryptography::KeyRatchet` (golden-KAT byte-parity, wire `CMD_ROTATE_KEY 0x9E`) + Tree `HardwareKeyService#rotate!` (`key_version` колонка) + `KeyRotationDownlinkWorker` + Soldier-гілка 0x9E + Queen-реле `soldier_cmd_queue` — **інертна за двома дзеркальними гейтами** (ECB-downlink без MAC не сміє командувати ротацією). Нитка-знахідки: legacy `sys/key_update` (слав КЛЮЧ ефіром, чужа арність) видалено; K_ota↔Flash-KV колізія → K_ota на сторінку 125. Канон + ADR (K0-rederive / ECDH-alt) [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security); реле [`03_02 §5б`](03_02_Queen_Gateway_Firmware).
- [ ] 🔗 активація після CCM-flip: фліп трьох гейтів (Soldier + Queen + backend ENV) + глибина черги під per-device CCM-батч cluster-wide ротації + bench (re-key CRYP, Flash-KV erase/program на кремнії) — e2e сценарій RUNBOOK §2.6
- [ ] 🌿 ECDH-alt — разом із SE050-L2

#### FW.20 — Time Sync (Rails ↔ Queen ↔ Soldier) [+ FW.20-S2]
- **P2** · 👤 · 🟢 · → [`03_02 §5а`](03_02_Queen_Gateway_Firmware)
- **Стан:** 3-рівневий time-sync (CoAP envelope `0x9C` + reflex-beacon + auth-flag + panic-sync `0x56` + per-hop mesh-relay + anti-storm журнал `0x20` + gossip-piggyback) host-готовий, канонізовано [`03_02 §5а`](03_02_Queen_Gateway_Firmware) (SSOT — §5а явно шорткозамикає 00_07 на pointer). FW.20 1-hop done; mesh-relay **INERT** за `FW20_MESH_RELAY_ENABLED`. Tick≠wall-time у STOP2 вирішено лічильниками пробуджень (БЕЗ FW.49); TTL≥3 — founder-airtime-рішення.
- [ ] 👤 bench: lab LSE drift-test ΔT=±60°C (`04_lse_drift.py`, RUNBOOK §4.3) + Flash-KV HAL mesh-flip (спільний bench з FW.2/FW.8/FW.17)

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- **P2** · 🤖 · 🟢 · → [`03_02 §5.1`](03_02_Queen_Gateway_Firmware)
- **Стан:** Soldier RX-верифікація OTA вирішена Design B (Magic Re-Request) — Soldier bitmap-uplink `[0x55]` (`OTA_REQ_MARKER`) → Queen targeted re-broadcast лише missing chunks (60-90% economy vs wave) + djb2-dedup replay-protection + host-тести; «5 хв тиші» STOP2-імунна **без FW.49** (`OTA_REREQUEST_SILENT_WAKEUPS=10` тихих пробуджень з відкритим вухом — чесніше за мертвий STOP2-tick, що запізнювався у ~6-15×). Beacon anti-storm журнал реалізовано (FW.20-S2, Flash-KV `0x20` — [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)). Канон [`03_02 §5.1.3`](03_02_Queen_Gateway_Firmware).
- [ ] 🔗 Design A (ACK-aggregation, collective recovery) залежить від ARCH.26 TDMA RX-вікна; Design B незалежний ✅

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- **P2** · 👤 · 🟢 · → [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)
- **Стан:** Числовий DCI-band (`check_z_divergence!` + `DEFAULT_DCI_EPSILON=0.001`, два ENV-флаги default-off) ДОПОВНЮЄ категоричний check → ловить replay з валідним StatusByte, але хибною Z-magnitude. **Gate L machine-closed без заліза**: N=10 000 зчеплених кейсів mruby-VM↔CRuby = **бітова рівність 10000/10000, max|Δz|=0** (ARM-плече нульове за FW.55 QEMU byte-parity; історичні «~1e-14» superseded за pinned `MRB_NO_BOXING`) → ε=0.001 = чиста страховка. device_z wire-дім готовий (FW.2 wire-rev2 bytes 16..17, q=2⁻⁹). Канон [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor).
- [ ] 👤 silicon-хвіст Gate L: той самий one-command FW.55 дамп (SWD) — закриває FW.7/FW.19/FW.31 разом
- [ ] 👤 flip-гейти D/C/P/G (staging canary → production): виміряти ≥95% device_z-покриття після CCM-фліпу, тоді canary

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- **P2** · 🤖 · 🟢 · → [`03_03 §10.3`](03_03_TinyML_Acoustic_Inference)
- **Стан:** Brownout-guard для fauna-сесії — `Fauna_Should_Sample(vcap_mv)` (дворівнева Vcap-політика: ≥4.5V повна сесія, нижче — skip + counter `fauna_skipped_low_vcap`; fauna ~78.3 мДж ≈ 2× TX → при низькому V_cap concurrent TX = brownout) + host-тести. Поки сирий ADC не сконвертовано (FW.50), guard **fail-CLOSED** — `FAUNA_VCAP_MIN_MV=4500` > стелі VREFINT-тракту, tripwire-тест тримає інваріант ([`03_01 §1`](03_01_Firmware_Lifecycle_and_DMA) FW.50). Wire-дім: fauna-маркери = 2 біти `diag[2..1]` (28B byte 18, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) ledger) + бекенд-лічильник `silkennet_fauna_skip_reports_total` ([`06_03 §2.8`](06_03_Prometheus_Observability)). Канон [`03_03 §10.3`](03_03_TinyML_Acoustic_Inference).
- [ ] 🔗 активація fauna-pathway після FW.4 fauna-pivot (гейт + ARCH.40-сесія готові; firmware call-site ставить diag-біти при pivot'і)
- [ ] 🔗 Grafana-панель — після перших живих інкрементів (мертва панель без джерела = передчасний dashboard)

#### ARCH.40 — Fauna 5-сек вікно: монолітне awake-обчислення (SRAM2 wipe)
- **P2** · 🤖 · 🟢 · → [`03_03 §10.2`](03_03_TinyML_Acoustic_Inference)
- **Стан:** Fauna-сесія монолітна за 1 awake — STOP2 стирає SRAM2 (`float[156][N_mel]` не переживе сну, 20 RTC DR зайняті) → Welford mean+M2 у RAM, STOP2 лише після згортки в байт. Model-незалежна половина зафіксована кодом ДО pivot'а: `firmware/common/fauna_session.h` (монолітний `Fauna_Run_Session`, синхронний — STOP2 фізично не втрутиться; `FaunaWelford` ~324 Б із sizeof-tripwire) + named-тест `test_fauna_sampling_no_stop2_in_session` + Welford↔two-pass еталон. Згортка mean/var→байт (0–63) свідомо відкладена (калібрування після моделі). Канон [`03_03 §10.2`](03_03_TinyML_Acoustic_Inference).
- [ ] 🔗 при FW.4 fauna-pivot — вживлення call-site у main.c (TIM2+DMA провайдер кадрів + `Fauna_Should_Sample` гейт + згортка в байт) ДО Фази 5 кенозису

#### ARCH.41 — Cold-start Time Paradox (DCI)
- **P2** · 👤 · 🟢 · → [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor)
- **Стан:** Cold-Start Time Paradox (VBAT loss → RTC epoch_day 10 957 default 2000-01-01 ≠ server ~20 585 → DCI false-positive до `CMD_TIME_SYNC`) закрито трьома мітигаціями обома сторонами: **A** server-side `try_time_sync_recovery` (3 epoch_day кандидати → `time_unsynced_fallback`, не падає DCI, `TimeSyncDownlinkWorker`); **B** sentinel `acoustic_events=0xFE` поки `soldier_unix_ts==0` (бекенд `apply_time_uncertain_sentinel!` нейтралізує ДО DCI — DCI не обходиться); **C** grace-вікно ≈10 хв (Лоренц відкладено — RTC-ланцюг не отруюється stale epoch_day; hello = SYNC_REQ `0x56`, Королева перемотує маяк). Firmware epoch_day — exact civil-days (FW.30 `lorenz_seed.h`); UTC tick-offset → RTC-календар timebase (FW.49). Канон [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor) + [`04_02`](04_02_Business_Logic_and_Services).
- [ ] 👤 bench: e2e cold-boot день (VBAT-pull → hello → маяк → синк → перший чистий пакет) — RUNBOOK §4.5 (сусідить з FW.49 LSE/RTC §4.1)

#### FW.52 — OTA throughput by-design: 1 RX-пакет/пробудження + give-up без печатки
- **P2** · 👤 · 🟢 · → [`03_02 §5.1.6`](03_02_Queen_Gateway_Firmware)
- **Стан:** Повільний OTA (порядок днів-тижнів) прийнято founder'ом як свідомий energy-first ADR — Soldier RX = 1 пакет/wake (`break` = анти-vampire; delta_t = економіка дерева E.63; 1024 B → ~94 пробудження); vcap-гейтований re-arm = опція перегляду після bench (FW.50). Дві знахідки закрито: (б) мертве вікно при запізнілій печатці = reliability-баг, **ВИПРАВЛЕНО** (`Ota_Late_Trailer_Resurrects`, `firmware/queen/ota_window.h`, host-тести); (г) `Write_OTA_Contract_To_Flash` (`flash_ota.{h,c}`, power-cut-safe magic-last) → [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA); re-request на STOP2-tick → FW.49 / §5.1.3. Канон [`03_02 §5.1.6`](03_02_Queen_Gateway_Firmware).
- [ ] 👤 bench: HAL_FLASH erase/program-фаза (`g_ota_flash_ops`, `main.c`) на STM32 + e2e OTA-day (включно з late-trailer воскресінням) — RUNBOOK §2.5

#### FW.54 — STOP2 RTC-only 300nA: SRAM2-off → RAM-стан (Flash-KV vs RTC-реклемація)
- **P2** · 👤 · 🟢 · → [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** 300nA-режим вимикає SRAM2 retention → RAM-only стан гине (RTC DR0..DR19 виживає: EMA/mesh-кеш/Lorenz/delta_t wall-маркер). Host-готово: Flash-KV (`flash_kv.{h,c}`, power-cut тести) + RAM-state інвентар (§2.3.1, групи A/B/C) + 3-осьова RTC-реклемація (§2.3.2: дешева реклемація розміщує live-набір FW.54 у RTC — Flash для нього НЕ потрібен). **DID-інверсія ВИРІШЕНА** (founder, §7): DID = детермінований `f(96-біт UID)` murmur3-fmix32 recompute-on-boot (`did_derive.h` + Ruby-дзеркало `SilkenNet::DidDerivation`, golden g1-g4; нуль → Queen Sentinel) → **DR7 звільнено** (перша реклемація з FW.2-freeze), DID VBAT-durable, однопрохідна фабрика; стара `UID⊕random` (FW.24-fallback) сиротила гаманець при EDLC-розряді. Канон [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)/§2.3.1/§2.3.2 + DID-механізм [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 рішення: RTC-реклемація (§2.3.2) vs Flash-KV persist vs SRAM2-retain — свідомо відкладено до bench (приймати з виміряним 300nA floor PPK2/JS220, RUNBOOK 3.1, не з моделлю)
- [ ] 👤 bench: HAL_FLASH glue + ECCD-політика + вимір 300nA + persist-roundtrip
- [ ] 🔗 SEC.3: завести `DidDerivation.wire_did` у фабричний транскрипт (UID по SWD → Tree+K_seed до прошивки)

## §03/§05 · Безпека (Edge crypto + Web3)

#### SEC.1 — Multisig Gnosis Safe + PAUSER⊥admin split (production admin role)
- **P0** · 👤 · 🟢 · → [`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC)
- **Стан:** ✅ Code-complete + verified (`Deploy.t.sol` пінить матрицю ролей + закритий bypass); **нічого не задеплоєно**. Кожен economic-vector admin (SCC/SFC токени + `ProtocolParameters` + `StateRootAnchor`) = `SilkenTimelock` 48h; `pause`/`unpause`=Gnosis Safe (миттєво) — єдине правило «admin=Timelock, окрім pause». Закрито: instant-`grantRole(MINTER)` + Safe-`grantRole(GOVERNANCE_ROLE,self)`-bypass ([E.35]); `REQUIRE_SAFE_ADMIN` + last-admin guards. forge build/test/fmt зелені. Канон [`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC) (+ StateRootAnchor [`05_04`](05_04_Ethereum_L1_State_Anchor)).
- [ ] 👤 створити Gnosis Safe (3/5|2/3) на Polygon + деплой з `ADMIN_ADDRESS=<Safe>` `REQUIRE_SAFE_ADMIN=true`
- [ ] 👤 реальні зовнішні co-signer'и Safe — solo-founder: усі ключі в однієї особи = театр (HW-wallet'и + social recovery); renounce Timelock-admin + Safe-PROPOSER→`address(0)` post-DAO

#### SEC.3 — Factory Flashing pipeline
- **P0** · 👤 · 🟡 · → [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning)
- **Стан:** ✅ Rake-конвеєр (Гілки A+B) канонізовано + host-доведено: `provisioning_sessions` AASM + **authenticated 2-Person Rule** (`approve_with_credentials!`/Argon2id; console-bypass закрито кодом — guard `credentials_verified?` → сирий `approve!` падає `AASM::InvalidTransition`, RSpec-покрито) + execute-шим (real subprocess capture / stop-on-fail). bench-residual = фізичний SWD-флеш. Канон [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning) (+ §1 pipeline).
- [ ] 👤 real `STM32_Programmer_CLI` на STM32WLE5JC bench (post-FW.2) — runbook `firmware/scripts/bench/`
- [ ] 👤 Bitwarden Secrets API live (`BitwardenAdapter` зараз `NotImplementedError`)
- [ ] 🔗 real SE I²C (Гілка B) — SE050 eval-kit; `cryptoauthlib`→SE05x код-міграція → SE050-MIGRATION (legacy ATECC-патерн reusable, [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security))
- [ ] 👤 operational residual (звужено 2026-06-15 — `approve!`-bypass закрито кодом, див. Стан): лишається лише raw-SQL / object-manipulation (`update_column`/`instance_variable_set`) — будь-який in-process guard це обходить = межа §5.A access-control ([`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning); master-key=`super_admin`+MFA+HSM); full crypto-approval (per-user PKI замість пароля) — bench/future

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **P0** · 👤 · 🟡 · → [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** guard `Security::WeakKeyDetector` + fail-closed boot-guard (refuse-to-boot на FIPS-197/NIST/degenerate vectors, RSpec-покрито) не дає тест-вектору потрапити у `PROVISIONING_MASTER_KEY`. ⚠️ ОКРЕМЕ від FW.1: якщо master seed базується на цьому ключі — весь derivation tree скомпрометований.
- [ ] 👤 замінити seed key на crypto-random → задокументувати генерацію у vault (без коміту) → re-flash прототипи

#### SEC.2 — RDP Level 2 activation timeline
- **P1** · 👤 · 🟢 · → [`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** процедура RDP L2 канонізована — pre-flight + CubeProgrammer CLI + rollout R&D→Pilot→Mass; скриптовано `firmware/scripts/bench/01_option_bytes.sh --rdp 2` (bench RUNBOOK). RDP L2 = **необоротний** SWD-lock → OTA мусить бути верифікований ДО активації. ⚠️ OTA латає **лише mruby-байткод, не C-firmware** → RDP L2 заморожує C-прошивку назавжди (radio/AES/main loop невиправні post-L2); чекліст-rollback = байткод-fallback, не C-recovery. Канон [`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security).
- [ ] 🔗 верифікувати OTA flow end-to-end на bench ДО L2-lock
- [ ] 👤 field batch → RDP **L1** (зворотний); L2 — лише фінальний mass-deploy

#### SEC.15 — IWDG freeze у STOP2 (option byte `IWDG_STOP=0`)
- **P1** · 👤 · 🟢 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** freeze-rationale + PVD-кома side-path канонізовано — `IWDG_STOP=0`+`IWDG_STDBY=0` (LSI-пес лічить у STOP2 max ~32.7с → spurious reset посеред багатогодинного сну) заскриптовано поряд з RDP у `firmware/scripts/bench/01_option_bytes.sh` (RUNBOOK §1.2). Канон [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 застосувати на платі при factory flashing
- [ ] 👤 bench-верифікація: сон 1 год без spurious reset (RUNBOOK §4.4)
- [ ] 👤 bench-audit CubeMX `MX_RTC_Init` на WUT **auto-reload + IT enabled** + reliable WAKE за багатогодинний сон (не лише no-spurious-reset) — підтверджено: arming = навмисний порожній stub `firmware/hal_glue/soldier_hal_check.c` «календар/WUT FW.49 — bench» (board-freeze, не код); frozen IWDG × SEC.2 RDP-L2 → WUT = ЄДИНИЙ backstop живучості (нема watchdog/SWD recovery). Канон [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA); RTC clock-tree bring-up = FW.49
- [ ] 👤+🤖 (2026-06-15d рішення) **hard pre-L2 gate**: жоден RDP-L2 burn (× SEC.2) не відбувається, поки армінг WUT не (а) винесений у **закоммічену ревʼюйовану функцію** (не .ioc-секцію, яку CubeMX-реген тихо перезапише) і (б) **bench-верифікований на багатогодинне пробудження**. Армінг авторюється **на bench-день** (коли LSE-clock-tree реальний і період вимірюється), НЕ зараз: grep показав, що армінгу нема в коді ВЗАГАЛІ (лише no-op host-stub), і він безсенсовний без clock-tree, на якому сидить (теж FW.49/absent) → committed-fn зараз компілювалась би в CI, але CI доводить compile, не WAKE = хибна впевненість. Host-half: `soldier_hal_check.c`/`hal_mock.h` стаблять лише `BKUPRead/Write` → author-now додатково потребує host-stub `SetWakeUpTimer_IT`. Канон [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)

#### SE050-MIGRATION — ATECC608B → NXP SE050 + true-DePIN ladder (2026-06-07)
- **P1** · 🤖+👤 · 🟡 · → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** Рішення (founder) = **true-DePIN** («голос дерева»: дерево підписує власні дані non-extractable Ed25519, ні backend ні оператор не підробить) → SE: ATECC608B (P-256) → **SE050** (суперсет Ed25519/EdDSA + AES-128/256 + monotonic counters + secure storage). AES-128 LoRa стоїть (ARCH.42 — свідомий вибір, не SE-constraint). Ladder L0 кастодіально → L1 Queen-attest → L2 per-tree (energy-gated). **Host/doc-side migration done**: канон-дім ADR + Slot-1→Ed25519 + AES-128-One-Home-колапс ×6 + legacy-banner ([`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)); docs-дзеркала (00_00/03_01/08_01/BOM) + firmware-коментарі + true-DePIN honesty-pass (05_01/04_02/05_03/06_08 — pipeline-integrity vs physical-origin розділено) + trust-origin ladder first-class дім ([`05_02`](05_02_Proof_of_Growth_Pipeline)). Ціна (~$2.40-3.25 vs $0.85) — founder: не проблема.
- [~] 🤖 код partial: `atecc_provisioner.rb` SE050 header + Slot-1→**Ed25519** (on-chip keygen) ✅; **лишилось** (bundled з eval-kit real-I²C): rename `AteccProvisioner`→`SecureElementProvisioner` (+session/spec/factory refs) + SE05x emit замість `atcab_*` + DB-колонка `atecc_serial_hex`→`se_serial_hex` міграція (+structure.sql). Гілка-B не live → ризик-кероване відкладання.
- [ ] 🤖 `03_05` deep mechanics → SE05x (no-premature-canon: при eval-kit + datasheet-verify): candidate-table, `atcab_*`→`Se05x`/`sss` API, role-split, latency/power/footprint, object-model замість 16 slots, on-chip Ed25519 keygen
- [ ] 👤 SEC.6 hardware: eval-kit order + datasheet-verify (SE050 Ed25519/EdDSA + monotonic counters + AES-128 + I²C + active/standby струми) + SEC.14 role (per-packet vs prov-only) + mass-BOM populate **разом з load-switch гейтом SE** (TPS22860-патерн; sleep-floor — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) Power impact)
- [~] 🤖+👤 L1 Queen-attestation — 🤖 **shipped**: firmware Queen software-Ed25519 (Monocypher, pinned) підписує CoAP-батч (EDSK Protected Flash; конверт `firmware/common/queen_attest.h`) + backend verify-до-decrypt у `UnpackTelemetryWorker` (nonce anti-replay; маркери `gateways.last_attested_at`/`telemetry_logs.gateway_attested`) + factory EDSK + закрито `Load_CoAP_Key` TODO; parity host C↔RSpec golden-KAT. Wire [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), ladder-статус [`05_02`](05_02_Proof_of_Growth_Pipeline). Лишилось:
  - [ ] 👤 bench: EDSK-flash на кремнії + e2e attested-батч (RUNBOOK)
  - [ ] 🔗 HIL `queen_simulator` signed-режим (опційний e2e без заліза)
- [ ] 🔗 **L2 per-tree device-voice** (North-Star, energy-gated Scenario D / 2× anchor): on-chip Ed25519 keygen + device-keygen provisioning (не HKDF-only — ARCH.33) + Merkle-root signing (E.60) + signature-transmission (weekly ≈ 5 LoRa-frames). Post-anchor-TRL.
- [ ] 🔗 L2 design-gap: тижневий device-Merkle-корінь підписується ПІСЛЯ intra-week мінтингу (Queen-relay L1) → потрібен explicit reconcile (device-root vs намінтоване) → slash/clawback при mismatch, інакше L2 = ex-post доказ, не pre-mint захист (дім [`05_05`](05_05_Slashing_and_Risk_Policy) × E.60)
- Cross-ref: SEC.6, SEC.14, ARCH.42, ARCH.43 (per-device-ізоляція post-FW.2), E.60 (Merkle), FW.2, FW.23, ARCH.33 (firmware-Ed25519 feasibility), STK.4 (ЗВТ), BIZ.13 (operator-bond).

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **P2** · 👤 · ⚪ · → [`03_05 §3.5`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** Не розпочато — дизайн канонізовано, у BOM ще немає: zero-consumption transport (магніт→circuit open, інсталятор знімає→first power-up, ~$0.05/unit; окремий механізм від piezo Zero-Power Wake). ⚠️ continuous power-cut = magnet-DoS вектор на security-сенсорі → дизайн-вимога latching first-boot; self-powered → можливий Ruthless-Prune (§3.5).
- [ ] 👤 додати Hamlin 59140-1-T-00-A + N52 магніт до BOM + оновити KiCad schematic
- [ ] 👤 BOM-freeze рішення (2026-06-15 аналіз): **pull-tab = security-дефолт** (немає magnet-DoS, дешевший, one-shot за природою → домінує над герконом); геркон лише з latching first-boot, якщо потрібен «перший вдих»-наратив ([`03_05 §3.5`](03_05_Hardware_Symmetric_Crypto_and_Security))

#### SEC.14 — SE role-split re-examination — per-packet AES vs provisioning-only (ARCH.42 honesty)
- **P2** · 👤 · 🟢 · → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** re-examine done — чесний trade-off канонізовано. Справжня вісь = tamper-resistance LoRa session-ключа (per-packet SE AES) ⟷ latency/ідіом (built-in radio-AES ~10µs + session-key у RDP-Flash, SE provisioning-only), не «0.1% acceptable». Active-енергія мала, АЛЕ знахідка-інверсія: always-on SE sleep 150 нА ≈ 3.6 мДж/год > весь запас Сценарію C → SE **обов'язково за load-switch гейтом** (TPS22860, як BME280), стосується обох ролей. Тепер SE = **SE050** (вісь та сама). **Рекомендація аналізу:** дефолт **provisioning-only** (built-in radio-AES ідіоматичний для inline-LoRa ~10µs; per-device HKDF → злам 1 вузла ≠ мережа); per-packet SE AES лише для urban/high-value threat-model з імовірним фізичним доступом. Trade-off-таблиця + Power impact — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security).
- [ ] 👤 обрати роль SE (per-packet vs provisioning-only) — bench eval + BOM freeze; threat-model-рішення (не тех-необхідність) → тримається у SE050-MIGRATION (One-Home)

## §04 · Backend / API / UI

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** · 👤 · 🟢 · → `04_03`
- **Стан:** Graceful degradation реалізовано — Redis down → DB-backed nonce (Solid Cache, TTL 10хв), шлюзи не отримують 503 (`m2m_auth_controller` [S6.1] + spec). Канон `04_03` (replay-nonce M2M).
- [ ] 👤 верифікувати Upstash multi-zone replication у production

#### S6.20 — ClusterEntropy + InsurancePayout: cron-оркестратори (doc-ahead-of-code закрито)
- **P1** · 🤖+👤 · 🟢 · → [`04_02 §11`](04_02_Business_Logic_and_Services)
- **Стан:** Розрив doc-ahead-of-code закрито — обидва per-record воркери тепер cron-driven через оркестратори (host-done + RSpec): (1) `ClusterEntropySweepWorker` (`Cluster.find_each` → `ClusterEntropyAnalyzerWorker`, cron `10 * * * *`) оживив EWS-детектор ентропії (`silkennet_cluster_entropy_score` gauge + `entropy_anomaly` алерти більше не мертві); (2) `InsurancePayoutRecoveryWorker` (`ParametricInsurance.status_triggered.find_each` → `InsurancePayoutWorker`, cron `15,45 * * * *`) — страхувальна сітка для застряглих :triggered виплат (первинний тригер лишається подієвим; re-enqueue безпечний — payout ідемпотентний). Канон [`04_02 §11`](04_02_Business_Logic_and_Services).
- [ ] 👤 deploy-verify: sidekiq-scheduler підхопив обидва cron у проді (Sidekiq dashboard) + перші інкременти entropy-gauge

#### E.41 — Fire-event 48h latency (dClimate obscuration) → immediate-broadcast fallback
- **P1** · 🤖+👤 · 🟡 · → `04_02`, `05_01`
- **Стан:** ⚠️ Life-safety — dClimate satellite fire-events можуть запізнюватись ~48h (хмарна обструкція). Первинна мітигація ✅ зашита: edge chainsaw→panic-TX негайний broadcast (`03_03`/`03_01`, `PANIC_TTL=5`, `Trigger_Emergency_LoRa_TX` — urgent шлях НЕ чекає dClimate). Вторинна: Forester Guild fallback-oracle = E.20 (Post-TRL 6). P1 — не відкладати на Post-TRL 6. Канон `04_02` (AlertNotification/EWS), `05_01` (dClimate).
- [x] 🤖 verified — backend fire-alert dispatch негайний (`AlertDispatchService#create_and_dispatch_alert!` → `EwsAlert` + `EmergencyResponseService`); єдині гейти = Redis silence (5хв debounce) + SEC.10 per-DID rate-limit, **НЕ** satellite. dClimate-clearance гейтить лише ВИПЛАТУ (`InsurancePayoutWorker#satellite_verification_pending?`), не тривогу → fire-response не залежить від 48h супутникового лагу
- [ ] 🔗 Forester Guild fallback-oracle (E.20, Post-TRL 6)

#### S6.14 — peaq_signing_key: відсутня rotation policy
- **P2** · 👤 · 🟡 · → `04_02 §S6.14`, `06_04 §5.4`
- **Стан:** Rotation policy готова — dual-key grace 72h + планова ротація 90д + emergency revocation runbook. Лишається vault-store production-ключа. Канон `04_02 §S6.14`, `06_04 §5.4`.
- [ ] 👤 vault-store production `peaq_signing_key`

#### TEST.1 — Test coverage: RSpec gate raised; Solidity/firmware tracked
- **P2** · 🤖 · 🟢 · → `04_06 §B.1`
- **Стан:** RSpec gate raised — `/lib/tasks/` відфільтровано (логіка в lib-движках 100%), line/branch підняті + per-group tripwire, великий branch+line-push з тріажем (мертві `&.`→`.`, real guard/empty-state/error tests, dead-code прибрано) + 2 dead-branch рефактори + ReDoS-fix `TABLE_ID_RE`; firmware coverage-lane `make -C firmware/test coverage` (gcov, owned `../common`/`../queen`, +`flash_ring` drain-test) живий; seed-флак вполльовано (`scripts/coverage_seed_diff.rb`; справжній інтегріті-дефект `sessions#current_session` `Module#prepend` знято). Пороги — лише `spec/spec_helper.rb`. Канон `04_06 §B.1/§B.3` (gate/scope) · `04_06 §B.4/§B.5` (gap-triage + dead-vs-defensive таксономія + worked-examples).
- [ ] 🤖 RSpec залишок: branch-хвіст звужується партіями (решта домінована **defensive** — Phlex `&.current_user` / env `defined?` / model-validation-dead / exhaustive-case → leave за §B.4: fragile white-box заради % = анти-§A.16-17)
- [ ] 🤖 Solidity (`contracts/`): глибший branch-targeting pass (line/func високі, forge-тести зелені; forge branch% низький — переважно forge-артефакт: кожен `require` + OZ-inherited, revert-шляхи покриті `testRevert_*`)

#### E.65 — `piezo_voltage_mv`: фантомний продакшн-шлях (сейсміка)
- **P3** · 👤 · ⚪ · → [`04_01 §3`](04_01_Data_Models_and_Entities)
- **Стан:** Не розпочато — `piezo_voltage_mv` фантомна: колонка (всі партиції, `structure.sql`) + btree-індекс `idx_telemetry_logs_piezo_created` + скоуп `seismic_activity(>1500)` (`telemetry_log.rb`) існують, але жоден wire-формат (21B/CCM) не несе piezo і жоден код не пише колонку → скоуп вічно порожній, індекс на NULL-ах. П'єзо в залізі реальне ([`02_01 §3`](02_01_Hardware_Architecture_and_BOM)), але роль — акустичний тригер TinyML, не mV-поле. Канон [`04_01 §3`](04_01_Data_Models_and_Entities).
- [ ] 👤 рішення: reserved-під-майбутній-сенсорний-фрейм (лишити + чесна примітка) vs прибрати скоуп+індекс+колонку до появи реального wire-поля

#### S6.10 — MaintenanceRecord — лише лог
- **P3** · 🤖 · 🔗 · → `04_02 §Forester Guild`
- **Стан:** Архітектурний дизайн готовий — task-assignment matching ranger↔bounty (scoring, `FOR UPDATE NOWAIT`, GPS/EXIF/IPFS→USDC, anti-Sybil). Заблоковано на Forester Guild PoPhW (E.20). Канон `04_02 §Forester Guild`.
- [ ] 🔗 зв'язати з Forester Guild PoPhW (E.20)

## §05 · Web3 / Економіка / Slashing

> Мультичейн, oracle/chain-конфіг та slashing-механіка — канон `05_xx`.

#### SLASH-1 — Slashing cause_classification gate (financial-safety) 🔴
- **P0** · 🤖+👤 · 🟡 · → `05_05 §3/§6` (divergence `04_02 §11`)
- **Стан:** Supporting-механіка coded + RSpec, але **INERT** (gate `SystemParameter :slash_cause_uplift_enabled` off → жива поведінка baseline-лінійна): convex §3 slash-крива `#calculate_slash_ratio` · blackout→Field-Audit no-burn `#flag_data_blackout!` · comms-loss de-correlation `#combine_penalty_factor` (`max()`-не-сума). 🔴 формальний A/B/C `cause_classification`-gate (namesake) ще НЕ в коді + uplift не активований. Канон [`05_05 §3/§6`](05_05_Slashing_and_Risk_Policy).
- [ ] 👤 DAO/founder перед mainnet: A/B/C cause_classification + активація uplift + tree-side `streamr_undelivered` сигнал (guarded→0) + repeat-offence вага (BIZ.13 operator-bond, `05_05 §3.1`)

#### S3.2 — dClimate Real API verification
- **P1** · 👤 · 🟢 · → `05_01`
- **Стан:** Реалізовано — `Dclimate::VerificationService` (NASA FIRMS, FRP≥10MW, cloud fallback) + `DclimateVerificationWorker`. Лишається verify з реальним API key у staging. Канон `05_01`.
- [ ] 👤 верифікувати з реальним API key у staging + e2e `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P1** · 👤 · 🟢 · → `05_03`
- **Стан:** SFC events (ForestMinted, GovernanceSlashed) у subgraph + zero-address fail-fast guard `subgraph/validate_addresses.sh` ✅ (раніше E.45); SFC-адреса = placeholder до mainnet-деплою. Канон `05_03`.
- [ ] 👤 замінити `0x0000…` на реальну SFC-адресу у `subgraph.yaml` (після контракт-деплою)

#### E.63 — метаболічний сигнал: розв'язано від хаосу (Option A) [2026-06-08]
- **P1** · 🤖+👤 · 🟡 · → `05_02`
- **Стан:** Option A (founder) — здоров'я **розв'язано від хаосу**: Лоренц = лише status-гейт (β=`BASE_BETA` фікс), `growth_points` у гомеостазі = `metabolic_health(delta_t)` напряму (FW.5 β-перт реверсована — β не рухає z-нерухому точку z_eq=ρ−1, тому delta_t→β-сигнал виходив економічно нульовий). Код (`bio_contract.rb` + backend `attractor.rb`, byte-identical DCI) + тести + guard `growth_points_clamp_drift` + backend GP-conformance (`check_metabolic_divergence!`, observational); wire незмінний. Формула + присуд — [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor); фізична шкала delta_t — [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) L4 / [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет.
- [ ] 👤 bench: реальна P_ebfc (`HW.13`) + E_cycle + recharge-крива (`03_power_profile.py`, RUNBOOK §3.2-3.3)
- [ ] 🤖 калібрування `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` (placeholder 600/7200с) під зміряну recharge-криву — per-deployment/species
- [ ] 🔗 B (на FW.2) — точний stateless GP↔delta_t recompute (wire=raw delta_t, GP=EMA device-RTC; wire-rev2 28B не додав EMA-delta_t → rev3-кандидат у wire-budget ledger [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) — механіка [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA)

#### BIZ.13 — Slashing principal-agent: investor capital vs operator-bond
- **P2** · 🤖+👤 · 🟡 · → `05_05 §3.1`, `05_03 §Slashing`, `04_02`
- **Стан:** Кат-A slash зрізає інвесторський `locked_balance`, хоча недбалість — провина оператора (principal-agent проблема); decision memo → рекомендація **hybrid operator-bond**. Канон `05_05 §3.1`, `05_03 §Slashing`, `04_02`.
- [ ] 👤 DAO confirm: hybrid vs investor-slash vs pure operator-bond
- [ ] 🤖 якщо operator-bond — `OperatorBond` + `ProtocolParameters` + контракт + синх `05_05 §3`/`05_03`/`04_02`

#### E.60 — Merkle CID-witness: Polygon ↔ Filecoin integrity bridge
- **P2** · 🤖 · 🟢 · → `05_02 §E.60`
- **Стан:** Leaf-рівень закрито (2026-06-03) — `Filecoin::CidGenerator` (детермін. CIDv1 raw+sha2-256→base32, golden-vector) + content-CID guard: `ArchiveService` вбудовує самоописовий `content_cid`, `VerificationService` fail-fast при розбіжності → детект ex-post archive-swap. Канон `05_02 §E.60`.
- [ ] 🤖 follow-on (deferred): per-tree Merkle-witness телеметрія-батчу (leaf_cid→`archive_root`→`mint(bytes32)`) — потребує `MerkleTree` + колонки на партиційованому `TelemetryLog` (міграція) + Solidity; worker-guard з `manual_review` у цьому батч-потоці

#### E.64 — bio→economy signal-coupling audit (E.63-лінза) [2026-06-08]
- **P2** · 🤖+👤 · 🟢 · → [`05_05 §7`](05_05_Slashing_and_Risk_Policy)
- **Стан:** E.63-лінза — окрім delta_t, решта bio→economy була слабка → виправлено: **anomaly ρ-відносна** (`z > ρ + (CRITICAL_Z_MAX−BASE_RHO)`, =45 при ρ=28 — ambient-temp більше не тригерить хибну аномалію) + **stress_index conformance** (Z-anomaly bounded ≪ slash-поріг «Z alone never slashes»; degenerate `avg_z`/weather-`temp` прибрано; `max_status` слешить лише tamper). Throughline: Лоренц-оракул здоров'я **декоративний** → реальна цінність = DCI anti-fraud (device-Z≡server-Z); здоров'я ведуть ПРЯМІ сигнали (metabolism E.63 · sap · VPD · acoustic). Нічого не задеплоєно → correctness перед деплоєм. Канон [`03_04 §4`](03_04_mruby_Lorenz_Attractor) · [`05_05 §7`](05_05_Slashing_and_Risk_Policy) · [`05_05 §8`](05_05_Slashing_and_Risk_Policy).
- [ ] 🔗 real-signal activation (sap/VPD/acoustic stress_index + per-species/season пороги) — ground-truth calibration (bench, [`08_02`](08_02_Academic_Institutions_Registry)). Cross-ref: E.63, FW.8, FW.50.

## §06 · Deploy / Observability / Secrets / Ops

> Деплой, спостережуваність, секрети, DR — канон `06_xx`. (Частина цих пунктів раніше сиділа під §04 «DevOps»; тепер кожен у власному §06-домі.)

#### S1.1 — GitHub Secrets заповнення
- **P0** · 👤 · 🟢 · → `06_04`
- **Стан:** Checklist + інвентаризація 4 місць секретів ✅. Лишається заповнити GitHub repo secrets. Канон `06_04`.
- [ ] 👤 заповнити GitHub repository secrets (12 крит.: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `SSH_PRIVATE_KEY`…) → верифікувати CI

#### S2.1 — Верифікація метрик після deploy
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** `/metrics` (реєстр — `06_03 §2.8`) + Alloy sidecar → Grafana Cloud налаштовано; чекає першого Akash deploy для верифікації збору.
- [ ] 👤 верифікувати збір метрик після першого Akash deploy

#### S2.2 — Grafana Cloud dashboards
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** dashboard IaC готовий (`deploy/grafana/dashboards/`, секції/панелі — `deploy/grafana/README.md`).
- [ ] 👤 імпортувати у Grafana Cloud (інструкції `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** alert rules IaC готові (`deploy/grafana/alerts/silkennet-alerts.yaml`, P0/P1/P2; зведення `deploy/grafana/README.md`) + counter `silkennet_telemetry_acoustic_overflow_total`.
- [ ] 👤 замінити `${DATASOURCE_UID}` + notification channel (Slack/Email/PagerDuty)

#### INF.6 — CoAP UDP smoke test через Ingress Anchor (post-deploy gate)
- **P1** · 👤 · 🟢 · → `06_01`, `06_02`, `06_08 §1.2`
- **Стан:** UDP-smoke gate проти silent CoAP-failure (Queen→Ingress Anchor→Akash) — workflow `coap_smoke.yml` (`workflow_dispatch`+`workflow_call`); зонди = freeze-contract `bin/coap_smoke`/`lib/coap_smoke.rb` (точні байти, регресія фантомної доставки FW.56); виклик = post-deploy gate у `deploy.yml`+`deploy-production.yml` (job `coap-smoke`, `needs: deploy`); поки repo Variable host не задана — job skipped (не silent).
- [ ] 👤 задати repo Variables `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` коли Ingress Anchor існує → gate активний
- [ ] 👤 перший boundary smoke з Queen/`bin/forest_simulator`

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** · 🤖+👤 · 🟡 · → `06_02 §TLS термінація`
- **Стан:** runbook готовий — Опція A (Cloudflare HTTPS + direct UDP CoAP) рекоменд. + pre-flight + fallback B (Cloudflare НЕ proxies UDP → CoAP потребує direct ingress).
- [ ] 👤 прийняти рішення (рекоменд. A)
- [ ] 🤖 якщо Akash hostname — automation у `terraform/`

#### S6.18 — Rails web security hardening (§8 audit)
- **P1** · 👤 · 🟢 · → `06_04 §2.1`
- **Стан:** production.rb (force_ssl/HSTS/hosts) + CSP (report-only) + security_headers.rb + session_store.
- [ ] 👤 `RAILS_ALLOWED_HOSTS` у Kamal/Akash перед prod
- [ ] 👤 після 1-2 тиж CSP-репортів → `CSP_ENFORCE=true`

#### DR.1 — Disaster Recovery drill + master-key backup
- **P1** · 👤 · 🟢 · → `06_06`
- **Стан:** DR-постуру задокументовано (`06_06`): Cloud SQL PITR + REGIONAL HA + 30×daily + restore-runbook'и + RTO/RPO.
- [ ] 👤 quarterly DR-drill (PITR-clone + TF-state rollback на staging, зафіксувати факт. RTO/RPO vs цілі)
- [ ] 👤 master-ключі (`RAILS_MASTER_KEY`/`PROVISIONING_MASTER_KEY`) → vault + offline-копія (незамінні, поза backup)

#### S1.5 — Kamal IP placeholders
- **P2** · 👤 · ⚪ · → `06_01`
- **Стан:** Не розпочато — `192.168.0.1` / `<CANOPY_SERVER_IP>` плейсхолдери в Kamal config; підставити реальні IP після `terraform apply`. Канон `06_01`.
- [ ] 👤 підставити реальні IP після `terraform apply` → верифікувати deploy

#### S2.4 — Observability industrial-grade hardening
- **P2** · 👤 · 🟡 · → [`06_03 §2.9`](06_03_Prometheus_Observability)
- **Стан:** industrial-grade hardening канонізовано — `external_labels` (env/service/source/release attribution) + `queue_config`+explicit WAL (backpressure) + cardinality-budget relabel + process/runtime gauges (`sample_process_runtime!`/`sample_connection_pool!`, RSpec-covered; bonus-fix: pool-gauges раніше були stale) + CI-валідація (`alloy_config_validate`). Конкретні значення — `config.alloy` SSOT (не дублюються). Канон [`06_03 §2.9`](06_03_Prometheus_Observability).
- [ ] 👤 `up`-scrape alert + SLO/error-budget (§2.9 #6 — ingest availability, mint/slash success) — Grafana Cloud

#### INF.3 — TLS termination
- **P2** · 👤 · ⚪ · → `06_02 §TLS термінація`
- **Стан:** Не розпочато — SDL відкриває 80/443/CoAP-UDP 5683, але TLS termination не налаштовано (browsers block WS HTTPS→HTTP). Канон `06_02 §TLS термінація`.
- [ ] 👤 налаштувати TLS (Akash ingress або Cloudflare)

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** · 👤 · 🟢 · → `06_03`
- **Стан:** `RELEASE_VERSION` у deploy configs ✅. Лишається verify Sentry release tracking. Канон `06_03`.
- [ ] 👤 верифікувати Sentry release tracking

#### PUMA-IPV6-1 — Верифікація IPv6 bind після першого Kamal-деплою
- **P2** · 👤 · ⚪ · → `06_05`
- **Стан:** Не розпочато — Puma 8 bind `[::]:3000` dual-stack, Thruster → `127.0.0.1:3000`; верифікувати IPv6 bind після першого Kamal-деплою. Канон `06_05`.
- [ ] 👤 після canopy deploy: `ss -tlnp\|grep 3000` (`tcp6 [::]:3000`) + `curl` v4/v6 `/up` → задокументувати у `06_05`

#### ARCH.35 — Queen Flash Ring Buffer (W25Q32 overflow tier)
- **P2** · 👤 · 🟢 · → `06_08 §1.2`, `02_05 §2.1`
- **Стан:** CIFO 50-slot RAM cache переповнюється ~30 хв @100 Soldiers/Queen → SPI NOR W25Q32JV (4 МБ, ~$0.50) overflow tier: sector-ring (~197k слотів) з in-band заголовками + used/consumed бітмапи (mount-scan recovery, 0 RTC DR), at-least-once power-cut-safe. Драйвер `firmware/common/flash_ring.{h,c}` host-tested ✅; Queen-глю зашито gated `ARCH35_RING_ENABLED 0`; residual = board-freeze + bench. Канон `02_05 §2.1` (дизайн) / `06_08 §1.2` L1.
- [ ] 🔗 W25Q32 розводка (SPI + CS-пін, board-freeze `.ioc`) + bench SPI-глю → фліп `ARCH35_RING_ENABLED 1`

#### ARCH.34 — Queen-side LoRaWAN Helium SOS fallback
- **P2** · 🤖 · ⚪ · → `06_08 §1.2`, `02_05 §6.1`
- **Стан:** Не розпочато — Helium SOS fallback перенесено Soldier→Queen (STM32WLE5JC flash/RAM/topology несумісний): Queen LoRaMac-node + OTAA join + FCntUp persist; SOS-маяк ~12 байт (НЕ телеметрія — SF12 EU868 ~51B cap) → Helium hotspot → LNS → Rails `POST /telemetry/helium`; Soldier лишається raw LoRa P2P AES-128. Implementation Anchor L3. Канон `02_05 §6.1` / `06_08 §1.2`.
- [ ] 🔗 Queen `queen_helium_lorawan_uplink()`

#### S4.3 — Akash SDL secrets
- **P3** · 👤 · ⚪ · → `06_02`
- **Стан:** Не розпочато — `REQUIRED_SECRET_NOT_SET` для 4 крит. змінних Akash SDL. Канон `06_02`.
- [ ] 👤 заповнити в `deploy/akash/deploy.yaml` → верифікувати startup

#### S5.6 — GCS bucket для Terraform state (chicken-and-egg)
- **P3** · 👤 · ⚪ · → `06_02 §GCS bucket`
- **Стан:** Не розпочато — GCS bucket для remote TF state створюється вручну перед `terraform init` (chicken-and-egg). Канон `06_02 §GCS bucket`.
- [ ] 👤 `gsutil mb` → верифікувати `terraform init`

## §07 · Юридичні / Бізнес

> Юридично-бізнесовий work-stream — канон `07_xx`. NB: пов'язані BIZ-айтеми за канон-домом живуть у `§05` (BIZ.13 slashing) та `§08` (BIZ.10 IP, BIZ.12 Horizon-biodiv).

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **P1** · 👤 · ⚪ · → `07_01`, `08_02 §5`
- **Стан:** Не почато — B2B MSA template; партнер СЄУ (Аблязов Д.Е., к.ю.н.). Канон `07_01`, `08_02 §5`.
- [ ] 👤 юр-консультація (MiCA/ERC-3643/RWA) → MSA template (Term Sheet + Carbon Credit Purchase Agreement) → review практикуючим юристом

#### BIZ.6 — Supply chain war-zone risk mitigation
- **P1** · 👤 · 🟡 · → `07_02 §8.1.1`
- **Стан:** Contingency Plan EU Backup DMLS Hubs готовий (4 кандидати; triggers; +~20% payback) — UA-підрядники у зоні бойових дій. Канон `07_02 §8.1.1`.
- [ ] 👤 отримати quotes для порівняння (→ BIZ.8)

#### BIZ.8 — EU DMLS quotes → Frame Agreement (procurement track, extends BIZ.6)
- **P1** · 👤 · ⚪ · → `07_02 §8.1.1`
- **Стан:** Не почато — BIZ.6 ✅ ідентифікував 4 EU кандидати (3D Lab PL, Materialise BE, Sauber/Lithoz, TRUMPF); procurement-трек до Frame Agreement. Канон `07_02 §8.1.1`.
- [ ] 👤 quotes у 3D Lab PL + Materialise BE → порівняльна таблиця (раніше OPS.5)
- [ ] 👤 NDA+RFQ зі 3D Lab PL → sample part order (10 шт) quality benchmark → Frame Agreement (+20% premium, 30-day activation)

#### BIZ.1 — 1 SCC = ? kg CO₂
- **P2** · 👤 · 🟡 · → `07_01`, `05_03`
- **Стан:** 2000 SCC = 1 tCO₂ (0.5 кг/SCC), carbon coefficient per-species — канон `07_01`, `05_03`.
- [ ] 👤 сертифікація методології (Verra/Gold Standard, Post-TRL 7 → BIZ.9)

#### BIZ.3 — B2C ToS / Privacy Policy
- **P2** · 👤 · ⚪ · → `07_01`
- **Стан:** Не почато — B2C юр-документи (канон `07_01`).
- [ ] 👤 ToS draft + Privacy Policy (GDPR) + Cookie Policy

#### BIZ.9 — Незалежний carbon credit методолог (Verra/Gold Standard)
- **P2** · 👤 · ⚪ · → `07_01 §3`, `07_02 §7.3`
- **Стан:** Не почато — конвертація SCC utility-token → сертифіковані kg CO₂ для institutional buyers потребує independent methodology audit (Verra/Gold Standard/Puro.earth). Канон `07_01 §3`, `07_02 §7.3`.
- [ ] 👤 engagement methodologist (~$50-100k) → PDD у Verra
- [ ] 🔗 залежить від HW.3 (Arrhenius) + UNI.6/UNI.7 (DFT+diffusion)

#### BIZ.11 — RWA pilot реєстрація лісової ділянки через Polygon Hadron
- **P2** · 🤖+👤 · ⚪ · → `07_01 §8`
- **Стан:** Не почато — Hadron (ERC-3643) RWA-pilot: 1 ділянка з кадастром + biomass appraisal (LIDAR+ground) + Hadron compliance. Канон `07_01 §8`.
- [ ] 👤 партнер-лісокористувач (post-war/Carpathian) + кадастр/biomass appraisal
- [ ] 🤖 `Hadron::TokenizeForestPlotService` + KYC flow spec
- [ ] 🔗 після BIZ.2 (MSA)

#### BIZ.15 — B2B Fiat-to-Retirement SPV (corporate carbon on-ramp)
- **P2** · 👤 · ⚪ · → `07_01 §8`
- **Стан:** Не почато — корпорації з ESG-зобов'язаннями не триматимуть крипту/ключі заради ретайрменту → потрібен SPV-міст: фіат → SPV купує+ретайрить SCC → сертифікат офсету (CBAM/ISO 14064). Поточний `KlimaRetirementWorker` припускає, що клієнт уже on-chain власник SCC (нот.19). Канон `07_01 §8`.
- [ ] 👤 юрисдикція SPV + ліцензія на вуглецеві активи + кастодіан крипти (СЄУ Аблязов Д., RWA/MiCA — `08_02 §5`)
- [ ] 👤 бухгалтерська класифікація + сертифікат-флоу (СЄУ Ус Г.)

#### BIZ.14 — SFC Vote-Escrow during breach→slash lag (07_01 SFC vote-escrow residual)
- **P3** · 🤖 · 🟢 · → `07_01 §8`
- **Стан:** Core закрито — `SilkenForestCoin.slash()` (SLASHER_ROLE) зменшує voting power при slashing → атака «купити SFC + навмисне порушення NaaS» неможлива. Residual: ~1–5 хв lag (`web3_critical` черга) між SCC-slash і SFC-slash — у вікні учасник технічно ще може проголосувати. Канон `07_01 §8`.
- [ ] 🔗 Vote-Escrow (veToken) при `breached`-контрактах — опціонально, gated на повний DAO governance launch (BIZ.4)

## §08 · Академічна інтеграція

> **Поточний стан:** Партнерство з 5+ академічними установами — ChNU (фізико-хімія + ФОТІУС), ChDTU (Data Science + RF + акустика), ChIPB-NUTSU (пожежна безпека), ChMA (біохімія + токсикологія), СЄУ (правова + економічна архітектура). UNI.1-3, UNI.8 — раніше ідентифіковані; нижче — розширення на всі 5 установ.

#### UNI.1 — Перший контакт з деканом Онищенком (ChNU FOTIUS)
- **P0** · 👤 · ⚪ · → `08_01`
- **Стан:** Не почато — перший контакт з деканом Онищенком (ChNU FOTIUS); блокує всю лаб-роботу, 10 публікацій, 11 магістерських. Канон `08_01`.
- [ ] 👤 призначити + провести зустріч

#### UNI.8 — Перший контакт з ректоратом СЄУ (legacy ID — see UNI.14)
- **P0** · 👤 · ⚪ · → `08_02 §5`
- **Стан:** Не почато — перший контакт з ректоратом СЄУ; блокує Economic Whitepaper, Legal Framework, NaaS шаблони (`07_01` B2B-MSA / B2C-ToS). Канон `08_02 §5`.
- [ ] 👤 зустріч Чудаєва/Аблязова Н. + verify 7 посад + MoU СЄУ↔SilkenNet + workshops Аблязов (MSA) + Ус (ESG)

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС
- **P1** · 👤 · ⚪ · → `08_02`
- **Стан:** Не почато — 8 зустрічей з факультетом ФОТІУС (по кафедрах). Канон `08_02`.
- [ ] 👤 8 зустрічей: Супруненко (PN-verification/Convolution) · Онищенко (stochastic B&B/Petri) · Ярмілко (Embedded/ECDH) · Порубльов (Discrete Math/reliability) · Косенюк (RF/FEC/compliance) · Бушин (CNN/BSP/DMLS) · Осауленко (portfolio) · Любченко (GA/NN)

#### UNI.3 — Defensive-publication + open-license execution (IP-постава)
- **P1** · 🤖+👤 · 🟡 · → `08_01 §2`
- **Стан:** Постава = **defensive-publication-first** (`08_01 §2`; патент НЕ подаємо). Ліцензії застосовано (AGPL / CERN-OHL-S / CC-BY-SA + `/NOTICE`); disclosure готовий ([`defensive_disclosure.md`](protocols/anchor/defensive_disclosure.md)) + landscape ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)) → **Стаття 1 розблокована** (publish-to-protect).
- [ ] 👤 TDCommons-постинг disclosure (prior-art якір)
- [ ] 👤 trademark-заявка SilkenNet™/GaiaNexus™/SCC™ через TISC (UNI.15)
- [ ] 👤 Кафедра-ІВ open-license + AF3 legal review (UNI.16)
- [ ] 🤖 SPDX-headers по source (`app`/`lib`/`firmware`[крім `extern`]/`contracts`/`tools` = `AGPL-3.0-or-later`; CERN-OHL-S для hw-design) — скриптом, ідемпотентно (skip-if-present); великий механічний diff → deferred (plan Phase 7)

#### UNI.4 — ChNU школа Мінаєва: DFT-моделювання EBFC
- **P1** · 👤 · ⚪ · → `08_01 Стаття 1`, `08_03 §1`
- **Стан:** Не почато — квантово-хім. симуляція streaming potential на TiO₂-гіроїді + адсорбція кислот ксилеми (школа Мінаєва, світовий DFT); ціль Q1 *Electrochimica Acta*, блокує seed credibility. Канон `08_01 Стаття 1`, `08_03 §1`.
- [ ] 👤 зустріч (через декана хімії) + NDA/IP (BIZ.10) + спільний грант MES/Horizon

#### UNI.5 — ChNU школа Гусака: дифузійна деградація 20-років (Kirkendall effect)
- **P1** · 👤 · ⚪ · → `08_01 Стаття 2`, `08_03 §2`
- **Стан:** Не почато — моделювання Kirkendall на Ti-6Al-4V/xylem + Arrhenius 12-тижн (школа Гусака, diffusion-controlled corrosion); ціль Q1 *Corrosion Science*, 20+ years claim; залежить HW.3. Канон `08_01 Стаття 2`, `08_03 §2`.
- [ ] 👤 зустріч + спільний експеримент HW.3 + co-authored paper

#### UNI.9 — ChDTU Карапетян: Data Science колаборація
- **P1** · 🤖+👤 · ⚪ · → `08_02 §2`
- **Стан:** Не почато — ChDTU R-кластер для ML; А.Р. Карапетян — статистика телеметрії (anomaly/fraud), магістерські. Канон `08_02 §2`.
- [ ] 👤 зустріч (ChDTU rectorat) + кафедральна тема «Statistics of Bio-IoT Telemetry» + 2-3 магістерські (2026-2027)
- [ ] 🤖 SLA R-кластеру (тренування `silken_forest.marshal`, post-TRL 7)

#### UNI.10 — ChDTU Гончаров (ФЕТР): RF верифікація + EMC pre-compliance
- **P1** · 👤 · ⚪ · → `08_02 §2`
- **Стан:** Не почато — А.А. Гончаров (ФЕТР): VNA + анехоїчна камера для (a) SMD-антена під PEEK (HW.17), (b) Link Budget у лісі (SF7-9, 50-250м), (c) EMC pre-compliance CE/FCC (E.11). Канон `08_02 §2`.
- [ ] 👤 зустріч + RF-лаб access + VNA-вимір PEEK-кришки (1.5/2.0/2.5мм) + Link Budget field test
- [ ] 🔗 залежить HW.9 + HW.17

#### UNI.12 — ChIPB-NUTSU: пожежна безпека + параметричне страхування
- **P1** · 👤 · ⚪ · → `08_02 §3`
- **Стан:** Не почато — ChIPB + НУЦЗУ: (1) валідація тригерів параметричного страхування (FRP/confidence з dClimate), (2) SOP для 7 EwsAlert-типів (drought/insect/vandalism/fire/seismic/fault/entropy), (3) ДСНС API. Канон `08_02 §3`.
- [ ] 👤 cold contact ректорат + презентація fire-safety stack + joint SOP workshop (ARCH.31)
- [ ] 🔗 залежить UNI.14 (СЄУ legal) для structuring страхування

#### UNI.14 — СЄУ: токеноміка RWA + правова архітектура
- **P1** · 👤 · ⚪ · → `08_02 §5`
- **Стан:** Не почато (розширення UNI.8) — СЄУ: (1) MSA/Term Sheet (Аблязов Д., к.ю.н.), (2) KYC/AML юросіб (Hadron), (3) DAO як юрособа (cooperative/Swiss Verein), (4) ESG Accounting (Ус Г.О.). ⚠️ 7 посад потребують verify. Канон `08_02 §5`.
- [ ] 👤 зустріч Чудаєва (ректор)/Аблязова Н. (UNI.8) + verify 7 посад + MoU + workshop Аблязов (MSA) + workshop Ус (ESG framework)

#### UNI.15 — ЧНУ TISC engagement (prior-art landscape + trademark + open-license consult)
- **P1** · 👤 · 🔗 · → `08_01 §2.1`
- **Стан:** prior-art landscape готовий (query-sets + CPC, [`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)); далі TISC ЧНУ (WIPO/УкрНОІВІ) engagement — (2) торгові марки SilkenNet™/GaiaNexus™/SCC™ (~5-10k UAH; повірений УкрНОІВІ) + (3) open-license UA-сумісність consult. Патент НЕ подаємо (defensive publication, `08_01 §2.1`). Заблоковано на UNI.1 (MoU).
- [ ] 👤 контакт TISC (Спрягайло) + auxiliary MoU + trademark-заявка + open-license sanity

#### UNI.16 — ЧНУ Кафедра ІВ engagement (юр-експертиза RWA/токеноміки + open-license)
- **P1** · 👤 · 🔗 · → `08_01 §2.1`
- **Стан:** Заблоковано на UNI.1 (MoU) — Кафедра ІВ ЧНУ точковий UA-юрисдикційний review (СЄУ §1F = макро): (1) RWA ERC-3643 vs Лісовий Кодекс/ПЗФ, (2) SCC/SFC за ЗУ «Про віртуальні активи» 2022 + MiCA 2024, (3) NaaS у UA Civil Code, (4) авторське право `bio_contract.rb`/`Attractor` (основа enforcement копілефту), (5) open-license review (AGPL/CERN-OHL-S/CC-BY-SA дійсність у UA + AF3 non-commercial × комерц-вимір). Ціль: 2 меморандуми + license-sanity. Канон `08_01 §2.1`.
- [ ] 👤 контакт зав. кафедри + workshop Аблязов (UA×MiCA) + меморандум RWA (розблок `07_01` RWA-передумов) + меморандум SCC + open-license/AF3 review

#### UNI.18 — ЧНУ ректорат: follow-up рішення + рамковий MoU
- **P1** · 👤 · 🟡 · → `08_02`, `08_01`
- **Стан:** Зустрічі **відбулися** (Кирилюк, ректор — 6 трав. 2026; Спрягайло — 8 трав.) → очікується рішення ректорату, рамковий MoU ЧНУ↔SilkenNet **ще не підписаний**; тиша достатньо довга для ввічливого нагадування. NB субординація: ректор делегує операційну ФОТІУС-координацію декану Онищенку (UNI.1) — НЕ маршрутизувати «теплий інтро» через декана після зустрічі з ректором. Канон `08_02`, `08_01`.
- [ ] 👤 ввічливий follow-up Кирилюк/Спрягайло + дотиснути рамковий MoU (framework — BIZ.10)

#### UNI.11 — ChDTU Базіло+Бондаренко (ПМКТ): акустична валідація фононної лінзи
- **P2** · 👤 · ⚪ · → `08_02 §2`, `03_03 §10`
- **Стан:** Не почато (**P1 у Mongabay-пивоті**, E.59) — ПМКТ (п'єзоелектрика + акуст. метаматеріали): EIS п'єзодиска 25-150кГц (cavitation) + верифікація гіроїдного phonon lens; ціль Q1 *IEEE TBME*. Канон `08_02 §2`, `03_03 §10`.
- [ ] 👤 зустріч Базіло+Бондаренко + EIS-протокол + acoustic стенд (HW.1)
- [ ] 🌿 Mongabay: dawn/dusk Cherkasy Soundscape Library для 5-class TinyML «Fauna» (`08_01 Стаття 24a`) — recordings з UNI.13a (Спрягайло-Гаврилюк): AudioMoth, 4 сезони, ≥30хв dawn+dusk/ділянку, labeled таксони

#### 🌿 UNI.13a — ChNU Біо-хаб (Спрягайло+Гаврилюк): Acoustic Biodiversity Baseline (Mongabay)
- **P2** · 👤 · 🌿 · → `08_01 §1/§2`, `08_01 Стаття 24a`
- **Стан:** Far-horizon (Mongabay-пивот) — Delgado et al. (Nicoya, 119 ділянок, 16k год; Mongabay 2026): dawn/dusk fauna-піки = маркер біорізноманіття (NDVI бачить покрив, не функцію). UA-аналог: **Cherkasy Soundscape Library** (4 сезони, з ЧДТУ ПМКТ UNI.11) → ground truth для 5-class TinyML (FW.4-EXT) + Q1. Канон `08_01 §1/§2`, `08_01 Стаття 24a`.
- [ ] 👤 зустріч Спрягайло (проректор) + Гаврилюк (ННІ природничих) + студенти-біологи + joint methodology workshop (з ЧДТУ ПМКТ) + expedition runs (4 ділянки × 4 сезони × dawn/dusk ≈ 32 записи)
- [ ] 🔗 manual labeling (комахи/птахи/амфібії 0-63) → GA-оптимізація Любченко (UNI.6/E.52-EXT) + cross-val 10-річні дані (Спрягайло) + Horizon CL6 grant (BIZ.12)

#### UNI.13 — ChMA: біохімія EBFC + токсикологія
- **P2** · 👤 · ⚪ · → `08_02 §4`
- **Стан:** Не почато — ChMA: (1) валідація dgrFAD-GDH + Laccase/ZIF-nanozyme при pH 4.5-5.5 (`01_03`), (2) токсикологія Ti/Al/V іонів, (3) геніпін cross-linking біосумісність (vs глутаральдегід). ⚠️ посади не верифіковані. Канон `08_02 §4`.
- [ ] 👤 СПОЧАТКУ verify посади (сайт ChMA) → cold contact ректор → joint biochemistry protocol EBFC Gen 2.0 (HW.5)

#### UNI.17 — ChDTU Хоменко (Кафедра металорізальних верстатів): прецизійна механіка + DMLS post-processing
- **P2** · 👤 · ⚪ · → `08_02 §2`
- **Стан:** Не почато — Хоменко (Заслужений винахідник, 80+ патентів): прецизійна обробка + різьба анкера для живої деревини (`01_01`/`01_02`/`02_02`, deinstall `08_02 §3 Несен`). Канон `08_02 §2`.
- [ ] 👤 контакт (ChDTU rectorat) + prior-art landscape consult (UNI.15) + прототип різальної геометрії в ЧДТУ machine shop

## §08 · External Stakeholders (B2G / B2B / Cultural)

> **Поточний стан:** Зовнішні залежності виокремлені в [`08_03`](08_03_External_Stakeholders_Registry) (Cultural Layer) та [`08_03`](08_03_External_Stakeholders_Registry) (B2G/B2B Matrix). Це не операційні залежності hot-path — це outreach pool, що активується за TRL-тригерами у відповідних модулях. Імена нижче — публічна інформація; контакти живуть у gitignored CRM.

#### STK.1 — Tier 1 B2G: Дзюбенко (ДП "Ліси України") — легальний доступ до Черкаського бору
- **P1** · 👤 · ⚪ · → `08_03 §2.1`
- **Стан:** Не почато (trigger: TRL 5 у `01_01`) — Дзюбенко (ДП «Ліси України»), Заслужений лісівник + д.е.н. + проф. ЧДТУ; підпис → експериментальний полігон у держлісі (канал через `08_02 §2` ЧДТУ MoU). Канон `08_03 §2.1`.
- [ ] 👤 verify title/contact (ChDTU rector) → first-meeting brief (NaaS+ESG/FSC) → Pilot Site MoU → координація з UNI.6 (Спрягайло) ПЗФ

#### STK.2 — Tier 1 B2G: Сегеда (ДП "Смілянське ЛГ") — еко-аудит + Геронимівка
- **P1** · 👤 · ⚪ · → `08_03 §2.2`
- **Стан:** Не почато (trigger: після STK.1) — Сегеда (ДП «Смілянське ЛГ»), Заслужений природоохоронець у Геронимівці (центр Genesis-кластера); еко-аудит + розширення в Смілянщину. Канон `08_03 §2.2`.
- [ ] 👤 first-contact (cross-link UNI.6 Спрягайло ПЗФ) → біосумісність (LoRaWAN+CODIT) → DAO advisory (PoG oracle validation)

#### STK.3 — Tier 1 B2G: Заслужений юрист — Legal Wrapper для SCC
- **P1** · 👤 · 🔗 · → `08_03 §2.4`
- **Стан:** Заблоковано на UNI.16 (Кафедра ІВ ЧНУ) + UNI.14 (СЄУ Аблязов) — Заслужений юрист для Legal Wrapper SCC: перекласифікація анкера «втручання»→«науково-вимірювальний прилад» до прокуратури; кандидати через ННІ права ЧНУ (Кирилюк, `08_01 §1G`). Канон `08_03 §2.4`.
- [ ] 👤 identify candidate (Кирилюк+Аблязов) → узгодити legal opinion з UNI.16

#### STK.5 — Tier 3 Certification: Чорней (ДП "Черкасистандартметрологія") — SCC certification
- **P1** · 👤 · ⚪ · → `08_03 §4.1`
- **Стан:** Не почато (trigger: TRL 6 у `05_02`; критичний gate для CBAM-статусу SCC) — Чорней (ДП «Черкасистандартметрологія»): сертифікація Soldier як ЗВТ + дрейф-компенсація + audit похибки D-MRV (інакше SCC = «цифри з інтернету»). Канон `08_03 §4.1`.
- [ ] 👤 verify Chorney status → first-meeting (SCC↔ДСТУ↔BIPM/OIML) → ЗВТ registration roadmap

#### STK.4 — Tier 1 B2G: Землевпорядник (TBD) — RWA кадастр oracle
- **P2** · 👤 · ⚪ · → `08_03 §2.3`
- **Стан:** Не почато (trigger: TRL 6 у `05_02`) — землевпорядник для RWA-кадастр oracle: сервітут під Queen-щоглу + кадастровий oracle; ім'я не верифіковане (Сіроштан — перевірити). Канон `08_03 §2.3`.
- [ ] 👤 identify candidate (cross-ref Аблязов UNI.14)

#### STK.6 — Tier 4 B2B: ПрАТ "Азот" — CBAM offset + хімічний scale-up
- **P2** · 👤 · ⚪ · → `08_03 §5.2`
- **Стан:** Не почато (trigger: TRL 7 у `05_02`, live SCC mint) — ПрАТ «Азот»: першочерговий B2B SCC-клієнт (CBAM offset) + канал на scale-up осмієвих полімерів EBFC (І. Кухоль, О. Хуторний). Канон `08_03 §5.2`.
- [ ] 👤 ESG officer cold-contact → CBAM model (`07_02`) → EBFC scale-up feasibility (`08_02 §4`)

#### STK.7 — Tier 5 Social Inclusion: Кучер (соц. сфера) — Horizon Europe Cluster 4/6
- **P2** · 👤 · ⚪ · → `08_03 §6.1`
- **Стан:** Не почато (trigger: перед великим Horizon-грантом `07_03`) — Кучер (соц. сфера): соц. інклюзія для grant-пріоритету + кадровий резерв + Eco-Therapy 4.0 для ветеранів. Канон `08_03 §6.1`.
- [ ] 👤 first-contact (обласна рада) → Eco-Therapy concept (deferred — потребує mobile UI `04_04`)

#### STK.10 — Cultural Tier C (Media): Калініченко / Душок (ТРК Ільдана) — PR shield
- **P2** · 👤 · ⚪ · → `08_03 §11.3`
- **Стан:** Не почато (trigger: перед першою публічною інсталяцією) — Калініченко/Душок (ТРК Ільдана): превентивний інфо-фон проти екопанік («чіпують дерева»); Калініченко — викладач ЧНУ, міст із `08_01`. Канон `08_03 §11.3`.
- [ ] 👤 через ЧНУ rectorat (Кирилюк `08_01 §1G`) перший контакт → документальний міні-сюжет про DMLS-друк (post-prototype)

#### STK.8 — Cultural Tier A (Cherkasy 8 artists): pre-Genesis NFT outreach
- **P3** · 👤 · ⚪ · → `08_03 §11.1`
- **Стан:** Не почато (trigger: TRL 7 у `05_02` + Genesis onchain) — 8 черкаських митців (Бабак, Теліженко, Афонін, Бондар, Іщенко, Олексенко, Касьян, Гладько); канал через А2 Теліженко (`08_02 §5`). Канон `08_03 §11.1`.
- [ ] 👤 pre-screen (life status+active) → через А2 collective probe → Name&Likeness Release (UNI.14 Аблязов)

#### STK.9 — Cultural Tier B (National 8 artists): pre-launch outreach
- **P3** · 👤 · ⚪ · → `08_03 §11.2`
- **Стан:** Не почато (trigger: TRL 8 у `05_03`) — 8 національних митців (Марчук, Чебаник, Микита, Сидоренко, Медвідь, Гуменюк, Гуйда, Ковтун), старша когорта (зафіксувати window); hand-off PR-агентству. Канон `08_03 §11.2`.
- [ ] 👤 verify life/health × 8 → gallery/agent кожному → pitch package (brief+animation)

## §08 · IP / Grants (BIZ)

#### BIZ.10 — Multi-party co-authorship + open-license MoU framework
- **P1** · 👤 · ⚪ · → `08_03`, `08_02 §3-07`
- **Стан:** Не почато — 5-сторонній фреймворк (ChNU+ChDTU+ChIPB+ChMA+СЄУ+SilkenNet) **спрощено під open-поставою** (`08_01 §2`): tech відкрита всім → немає патентних прав / royalty / tech-NDA до розподілу; лишається co-authorship + open-license acknowledgment (AGPL/CERN-OHL-S/CC-BY-SA) + NDA лише для нерозкритого (ключі / production-дані). Канон `08_03`, `08_02 §3-07`.
- [ ] 👤 co-authorship + open-license MoU × 5 (паралельно UNI.4-14) → Master Collaboration Agreement (юрист, не патентний повірений)
- [ ] 🔗 після UNI.1/8/9/12/13

#### 🌿 BIZ.12 — Horizon Europe CLUSTER 6 заявка (Biodiversity Monitoring, Mongabay pivot)
- **P2** · 👤 · 🌿 · → `08_01 Стаття 24a`, `03_03 §10`
- **Стан:** Far-horizon — Horizon CL6 Biodiversity Monitoring (2-6 М€, 36-48 міс); SilkenNet = єдиний планетарний D-MRV з micro-acoustic біорізноманіттям. Submission прив'язати до acceptance Статті 24a → «published research». Канон `08_01 Стаття 24a`, `03_03 §10`.
- [ ] 👤 identify call (HORIZON-CL6-*-BIODIV) → consortium (SilkenNet coord + ЧНУ/ЧДТУ/біо-хаб + 1-2 EU: Linköping/CSIC) → submit при acceptance 24a
- [ ] 🔗 E.59/FW.4-EXT (5-class TinyML) + UNI.13a (Soundscape Library)

#### BIZ.16 — Naming model: codename «Gaia 2.0» vs trademark «GaiaNexus»
- **P3** · 👤 · ⚪ · → `08_01 §2`
- **Стан:** Не розпочато — відкрите founder-рішення: проєкт всюди вживає codename «Gaia 2.0»; founder обрав ™ «GaiaNexus» (заявка — UNI.3/UNI.15). Модель найменування: rename project-wide чи codename(Gaia 2.0)+brand(GaiaNexus)-split. Масове перейменування відкладене до рішення (інакше One-Home cross-ref sweep довелося б робити двічі). Канон `08_01 §2`.
- [ ] 👤 рішення founder про модель → (якщо rename) One-Home sweep `Gaia 2.0`↔`GaiaNexus` по docs+code

## 🔀 Cross-cutting · Doc-drift (DOC-T) — SSOT doc↔code + tracker form/tooling

DOC-T трекає SSOT doc-drift (узгодження docs↔код) **та** еволюцію самого tracker'а — форму пунктів і drift-guards. **Не блокери виконання, але блокери для аудиту й онбордингу.**

> **Три `DOC*`-неймспейси (кожен у своєму домі — не плутати):**
> - **`DOC-T.N`** — цей tracker (SSOT doc-drift + tracker form/tooling TODO; таблиця нижче).
> - **`DOC-R.N`** — code↔doc divergence registry ([`04_02 §11`](04_02_Business_Logic_and_Services); дзеркало `04_01 §12`).
> - **`DOC.N`** (bare) — canon-block SSOT-home теги **всередині** канон-доків (`03_01`/`03_04`/`04_04`/`05_02`…); номери **load-bearing** у GitHub anchor-слагах (`-docN`) → заморожені на місці. `DOC.8` (cleanup constraint) — спільний у 04_01+04_02.
>
> Inbound item-ref (`NN_NN — DOC-T.N`) резолвиться `tracker:check` ([`00_06 §3`](00_06_SSOT_Documentation_Standard)).

_Активних DOC-T наразі немає — усі вирішено/архівовано (§🗄️ нижче). Нові SSOT doc-drift / tracker-tooling знахідки → додавати рядком таблиці (формат — §🗄️)._

## 📌 Backlog (не блокери · довгострокові)

| ID | Опис | Джерело | Note / Milestone |
|----|------|---------|------------------|
| E.53 | **VNA-вимір SMD-антени під PEEK радомом** — VSWR <1.5 на 868 МГц для 3-5 варіантів товщини PEEK (1.5/2.0/2.5 мм) у вологому/сухому стані + **3D Keep-Out з Ti-фланцем нижче** (Z-clearance 5/8/12 мм, з/без overhang за периметр Ti). Лабораторна задача (cross-ref UNI.10 ChDTU Гончаров, нова вимога `02_01 §5.3` revised) | `08_02` §2 (Гончаров) + `02_01` | P1, blocked by HW.17 + UNI.10 |
| E.54 | **SOP документи для 7 типів EwsAlert** — стандартизовані інструкції UA+EN: severe_drought, insect_epidemic, vandalism_breach, fire_detected, seismic_anomaly, system_fault, entropy_anomaly. Інтеграція як inline UI у Phlex (cross-ref ARCH.31) | `08_02 §3` | P1, joint with ChIPB-NUTSU (UNI.12) |
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) — planned post-TRL 6 | `04_02` | Post-TRL 6 |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation | Legacy | Post-TRL 6, потребує E.10 (Kalman) |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1B (Порубльов) | Post-TRL 6 (Порубльов, ЧНУ) |
| ARCH.8 | Event-Triggered Reporting: heartbeat 1/day normal, continuous on anomaly | `00_01` | Post-TRL 6 |
| ARCH.26 | **Синхронні Вікна (TDMA) та CAD Preamble Detection — вирішення Проблеми Рандеву для mesh relay.** Поточна архітектура: Queen always-on (`Radio.Rx(LORA_RX_INFINITE)`), Soldier має лише 600 мс post-TX RX window — mesh relay між Солдатами стохастичний і ненадійний за межами прямої видимості Queen. **Три рівні рішення:** (L1) Queen always-on ✅ реалізовано; (L2) TDMA Sync Windows — Queen транслює beacon з точним часом (NTP через LTE), Солдати синхронізують RTC, кожні 15 хвилин координоване 2-секундне RX-вікно для mesh relay. Залежить від FW.20 (LoRa Time Sync); (L3) CAD — SX1262 `Radio.StartCad()` дозволяє wake на ~2 мс/секунду для детекції LoRa-преамбули без повного RX. Критично для PANIC mode: Солдат при chainsaw detection посилає довгу преамбулу (~1 сек), сусідні Провідники ловлять через CAD навіть між TDMA-вікнами. **Firmware зміни:** Soldier: CAD periodic wakeup (LPTIM або RTC sub-second alarm), beacon RX handler, RTC sync logic. Queen: beacon TX (periodic broadcast з UTC timestamp + network schedule). **Енергобюджет:** CAD wake 1/сек × 2 мс × 4.5 мА = ~9 µA середнє — допустимо для Провідників (дерева з високим vcap), неприйнятно для слабких Солдатів. Рольова диференціація: Солдат (TX-only, глухий) vs Провідник (TX+CAD, еліта з надлишком енергії). | `00_01`, `03_01`, `03_02` | Post-TRL 6 (Firmware + Queen beacon) |
| ARCH.43 | **Per-device-key ↔ opaque-relay/demux суперечність + стеля «N дерев через одну Queen».** Релей чужого пакета (`soldier/main.c` Сценарій Б: decrypt власним ключем → `TTL--` → re-encrypt) і власне demux Queen (`queen/main.c` decrypt **перед** читанням DID) опираються на **спільний** LoRa-ключ, але канон вимагає **per-device** ключ (`03_06 §1`, ізоляція «злам одного ≠ розкриття сусідів») + DID лежить **усередині** шифроблоку (немає cleartext air-header — Soldier шле рівно 16 B). За справжніх per-device ключів Солдат B розшифровує пакет A у сміття → релеїть сміття; Queen/backend не знають, яким ключем демультиплексувати relayed-фрейм. **Очікування «>1000 дерев пересилають через Queen, навіть недосяжні» НЕ підтримується** на 4 незалежних рівнях: (1) крипто/demux — цей пункт; (2) `DEFAULT_TTL=3` → ≤3 хопи ≈ ≤~450–600 м reach; (3) один relay-буфер (1×16 B/пробудження) + store-and-forward на наступному wake → нема агрегації, втрати/латентність множаться; (4) Queen CIFO ~100 baseline/~200 roadmap, overflow за ~30 хв при 100 без Starlink (`02_05 §2.1`) — не 1000. **Резолюція:** або cleartext addressing-шар (LoRaWAN-style DevAddr у відкритому + per-device session-key) для співіснування opaque-relay з per-device payload; або прийняти star-only на поточному TRL (mesh = страховка для одиничних stragglers у межах TTL, **не** механізм масштабування). Масштаб до тисяч = більше Queen (ARCH.1 fractal/L2 Conductor, ARCH.10 Q2Q). Залежить від ARCH.26 (рандеву) | `03_01`, `03_02`, `03_05`, `06_08` | Post-TRL 6 (addressing-шар; cross-ref ARCH.26) |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1B (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_02 §3` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| E.27 | Chaos Engineering: Chaos Mesh для Akash або kill-scripts для Kamal | Legacy | Post-TRL 7, production hardening |
| E.30 | InsightGenerator: кліматичні базлайни per region | `04_02` | Post-TRL 7 |
| E.50 | **Edge fuzzy_distance dedup function** на STM32WLE5JC: <1 мс CPU, <128 байт RAM, ціль — 30-40% TX зниження за рахунок suppression near-duplicate пакетів | `08_02` §1B (Ярмілко) | Post-TRL 7 (R&D — Ярмілко) |
| E.52 | **GA-оптимізація ваг `silken_forest.marshal`** ML моделі на Akash GPU кластері — генетичний алгоритм для `InsightGeneratorService` stress_index класифікації | `08_02` §1B (Любченко) | Post-TRL 7 |
| ARCH.1 | Fractal topology: L2 Conductor nodes (Hub Trees, formerly "Sergeant"; H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard, UNFCCC) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining (monthly cycle, A/B testing) — **обмежено L2 Conductors / L3 Queens; ніколи на L1 Soldier** (compute budget paradox, [`00_08 §1.2`](00_08_Beyond_TRL9_Planetary_Roadmap) revised 2026-05-16: 0.47F supercap + STOP2 300 nA не витримує жодного gradient epoch'у) | `04_02`, [`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap) | Post-TRL 7 |
| ARCH.9 | Network Sharding: isolate anomalous clusters to prevent storm propagation | `00_01` | Post-TRL 7 |
| ARCH.11 | Energy-Aware Routing: route metric = f(hop_count, remaining_energy, bio_potential) | `00_01` | Post-TRL 7 |
| ARCH.14 | Read-Only PostgreSQL Replicas для analytics та Oracle queries | `00_01`, `06_01` | Post-TRL 7 |
| ARCH.16 | Mobile app для foresters (Phase 2 roadmap) | `00_01 §4` | Post-TRL 7 |
| ARCH.18 | Детерміністична Fixed-Point арифметика (Integer Math): для досягнення побітової ідентичності розрахунків (consensus) між STM32 (Soldier) та GCP/Akash (Backend), необхідно відмовитись від IEEE 754 Floating-Point. Всі вхідні дані мають множитись на 10⁶ (або 10⁸) і розраховуватись у 64-бітних цілих числах (`int64_t` у C, `Integer` у Ruby). Це усуне апаратний drift при розрахунку Атрактора Лоренца. Потребує повного переписування математики в прошивці з урахуванням ризиків переповнення буферів (overflows) під час множення великих чисел. **Firmware-код тег цього ж рішення = `[FW.45]`** (Lorenz Integer-Math hardening, deferred until ZK-circuit milestone — `03_04`). | `03_04`, `05_02` | Post-TRL 7 |
| ARCH.19 | BSP-кластеризація IoT-графу для заміни flat TTL-mesh при масштабуванні: Binary Space Partitioning дерево на основі географічних координат Queen. Зменшує broadcast collisions та енергоспоживання. Кожна Queen знає тільки своїх сусідів | `08_02` | Post-TRL 7 |
| ARCH.22 | Arithmetic compression для LoRa payload: lambda-exponent (2 байти) замість повного Z (16 байт). Потенційна економія ~34% TX часу (21→~14 bytes). Event-Triggered Reporting: "мовчання = здоров'я" — 24× зниження трафіку. **DCI-precondition (нот.6):** λ послаблює anti-fraud (λ many-to-one → device-λ vs server-λ слабший за точний Z-cross-check) → потребує full-Z challenge sampling / Z-sentinel перед вмиканням | `08_02`, `00_01`, `00_08 §2.3` | Post-TRL 7 |
| ARCH.23 | Multi-Attribute Utility Function для автономного рішення TX на MCU: оцінка важливості поточного пакету (Vcap, delta_t, acoustic, bio_status) — відправляти лише якщо utility > threshold. Оцінка: 30-40% зниження TX | `08_02` | Post-TRL 7 (Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1B (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `00_04` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice | `03_03` | Post-TRL 8 |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| ARCH.10 | Queen-to-Queen Backhaul Mesh: LoRa SF12 inter-Queen relay (Starlink fallback) | `00_01` | Post-TRL 8 |
| ARCH.12 | Merkle Tree state root (замість flat SHA-256) для partial verification / ISO 14064 | `05_04` | TRL 9 |
| ARCH.17 | Bonding Curves для dynamic SCC pricing | `05_03` | TRL 9+ |
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.5 | CoAP listener Ruby — масштабується до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | R&D partnership |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | Потребує Косенюк |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data | `08_03` | Blocked by UNI.1-3 |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.35, EVM cancun, optimizer 200 runs, CI/production profiles. 6 test suites (`contracts/test/*.t.sol`; к-сть — `forge test`). Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.13 | EigenLayer AVS як альтернатива direct L1 write (~$0.01/week vs $5-15/week) | `05_04` | Research |
| ARCH.20 | Petri Net PN-модель Rails моноліту: формальна верифікація відсутності deadlock при 10,000 concurrent IoT connections. Sidekiq + Puma + PostgreSQL modeling. Конволюційний метод для зменшення state space explosion у 10-100 разів | `08_02` | R&D (Супруненко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.25 | Gyroid geometric validation scripts: Python/C++ верифікація 65% пористості per-slice, topological integrity mesh, capillary channel connectivity via BFS (breadth-first search). Запускається після кожного nTop build для запобігання помилкам DMLS | `08_02` | Before DMLS factory order |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1B (Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

## 🗄️ Архів закритих пунктів (мігровано в канон)

> Повністю завершені пункти. Знання — у канонічних доках (стовпець «Канон»); повна історія — у git. Тримаємо лише вказівник для крос-реф цілісності (CLAUDE.md та живі пункти посилаються на ці ID).

| ID | Пункт | Канон |
|----|-------|-------|
| ARCH.42 | AES-128 LoRa — DECIDED (Variant B); SE-частина ATECC→**SE050** (true-DePIN — SE050-MIGRATION) | `03_05 §3.7` |
| SEC.6 | SE = **SE050** — ✅ RESOLVED 2026-06-07 (true-DePIN: голос дерева потребує non-extractable Ed25519 → SE050, не ATECC; soft-freeze DNP, populate post-FW.2). Деталі + усі residuals → SE050-MIGRATION | `03_05 §3.7`, §3.4 |
| SEC.10 | Emergency-TX anti-replay frame counter (DR0 packing) | `03_02`, `03_01 §2` |
| SEC.11 | Lorenz Seed Provenance (DCI hardening, K_seed HKDF) | `03_04`, `03_06 §2`, `04_02`, `05_02` |
| SEC.7 | OTA image authentication — **дубль FW.23** (HMAC-SHA256 dual-gate: `OtaHmacKeyService` + `OtaPackagerService` 0x9B trailer + Queen relay + Soldier dual-gate, live-compute ✅ зашито 2026-06-11). Residuals (bench K_ota Protected Flash; ECDSA P-256 post-TRL7 migration path) тримає FW.23 — One-Home | `03_06 §4` (= FW.23) |
| SEC.8 | ECB Restoration Race (Queen): restore CRYP→ECB+128B+LoRa-key після CoAP-CBC flush/downlink; `HAL_CRYP_Init` fail → RCC force-reset → `NVIC_SystemReset` (`firmware/queen/main.c`). Resolved-фікс, orphan-ID — cited by SEC.12 + RUNBOOK, бракувало archive-рядка (додано 2026-06-09) | `03_05` (розділ «ECB Restoration Race») |
| SEC.12 | HRNG-IV fallback predictability — closed in SW 2026-06-15: key-derived HMAC-SHA256 IV (`coap_iv.h#coap_fallback_iv`, host-parity vs OpenSSL) → unpredictable, не лише unique; no AES-engine `E_key(ctr)` / SEC.8-restore / bench needed (pure-SW `silken_sha256.h`) | `03_05` (розділ «HRNG Fallback») |
| SEC.5 | Chainlink oracle-callback HMAC fail-fast: `WEB3_STRICT_MODE=true` + порожній `CHAINLINK_HMAC_SECRET` → `SecurityError` (захищає `/oracle_callbacks` від forge `oracle_status_fulfilled?` → неавторизований mint). Guard `verify_chainlink_signature!` (`oracle_callbacks_controller.rb`) + RSpec. Resolved, orphan-ID — бракувало archive-рядка (ops: provision secret pre-mainnet → S1.1/`06_04`; додано 2026-06-09) | `04_03 §5.9` |
| FW.1 | Hardcoded identical AES-key → per-device HKDF + `Load_AES_Key()` (Protected Flash `FLASH_KEY_ADDR`, magic `KEYL` + zero-key guard → refuse-boot без provisioning) — firmware CLOSED 2026-05-02 (soldier+queen `main.c` + host-тести `test_load_key_*`). Per-device ізоляція реальна з FW.2 CCM (ECB-транзит = спільний ключ, §3.1). Bench-residuals — власні items: RDP L2 → SEC.2 · factory SWD-flash → SEC.3 · weak-key boot-guard → SEC.9 | `03_05 §3.1`, `03_06 §2` |
| FW.5 | ~~Lorenz β-пертурбація від delta_t/vcap~~ → **РЕВЕРСОВАНО [E.63]** (delta_t → growth_points напряму) | `03_04 §4.3`, E.63 |
| FW.7 | Backend Lorenz `Attractor` BigDecimal→**Float** (IEEE 754 double) — bit-identical Z з firmware mruby (BigDecimal `round(18)`/iter давав drift після 250 ітерацій); DCI parity. ✅ Закрито (BLOCKER-02, 2026-05-02; `app/services/silken_net/attractor.rb`; §5 порівняльна таблиця Firmware↔Backend). ARM↔x86 silicon-confirm → FW.55 (QEMU bit-parity CI-gated; той самий дамп закриває FW.7/FW.19 на платі) | `03_04 §5`, `05_02` |
| FW.9 | Queen CoAP batch-delivery retry-loop (`COAP_MAX_RETRIES`, `COAP_CONV_BUDGET_MS` < IWDG) у flush-sequence; ✅ Реалізовано (`firmware/queen/main.c`; host: conversation-fail `test_at_engine.c` + fail→retry→no-loss `test_fw51_*`). Кеш-on-delivery → FW.51; Flash overflow + exp-backoff → ARCH.35. Orphan-ID (cited 06_08/04_06/03_02 §4, archive-рядка бракувало 2026-06-09) | `03_02 §4`, `06_08` |
| FW.18 | TinyML confidence threshold (RTC DR13/14 dual-zone) | `03_03`, `03_01 §2`, `04_06` |
| FW.19 | mruby `build_config.rb` double-pin: НЕ `MRB_USE_FLOAT32` + NO WORD/NAN boxing → `mrb_float`=double inline (float32 → ±5-10 units на Z → bio_status зсув; word-boxing → RFloat heap-thrash на ~KB heap). ✅ Канонізовано; ⚠️ (2026-06-11, FW.55-знахідка ④) теза «дефолт = NO_BOXING» була ХИБНА для mruby 4.0 (дефолт `MRB_WORD_BOXING` — на ARM32 інваріант тихо порушувався, ~20.5КБ RFloat-транзієнту/виклик) → пін тепер ЯВНИЙ (`MRB_NO_BOXING` у `SILKEN_MIN_GEMS` + `MRB_DEFS`-дзеркала), а CI-enforcement = фіт-гейт QEMU-ноги (word-boxing на 32-bit рве heap-бюджет миттєво). ARM↔x86 silicon-confirm → FW.55 (спільний дамп) | `03_01 §12.4`, `03_04 §5` |
| FW.29 | Panic vs saturated acoustic disambiguation (PANIC_FLAG_BIT) | `03_03 §5.3` |
| FW.29-PACK | StatusByte layout collision fix (5-bit growth_points) | `03_01 §11.3`, `03_04 §4.3-5.2`, `05_02` |
| FW.30 | SEC.11 C-bridge: warm/cold → 7-arg `calculate_state` + `Load_Lorenz_Seed` (K_seed Flash `LSED`) + `Derive_Cold_Start_State` (pure-C HMAC-SHA256 `silken_sha256.h`/`lorenz_seed.h`, byte-parity vs OpenSSL — mbedTLS TODO закрито) + args[5..6] EMA→`growth_points` [E.63]; 11 host-тестів | `03_04 §6`, `03_06 §2` |
| FW.21 | Soldier edge-aggregation EMA (delta_t/vcap, α=0.2 integer fixed-point) — RTC DR10 + DR12-packed (звільнило DR11 → 3-й mesh-слот); згладжує метаболічний сигнал [E.63] + меншає LoRa-трафік. ✅ Реалізовано (`firmware/soldier/main.c` `EMA_*` + host-тести). Kalman-апгрейд (noise ±8%→±1.2%) → E.10 (академічний, Косенюк) | `03_01 §13` |
| FW.22 | acoustic_events overflow: тип `uint8_t` + saturating increment (cap 255 — без uint16→uint8 ambiguity), DR0-packed (SEC.10+FW.22) + backend overflow-warning + Prometheus counter + host-тести (saturating/atomic-snapshot); 2-байт payload — optional far-future (лише якщо FW.2 CCM repack потребує >255/cycle) | `03_03 §7.1`, `03_01 §2` |
| FW.24 | DID HRNG-fallback (collision / defective-UID) → **знято** разом зі старою `UID⊕random`-схемою [FW.54 Вісь 2]: детермінований DID = `f(UID)` (murmur3-fmix32) робить колізію видимою на фабриці (DB-unique `trees.did`), а дефектний UID дає заприсяжений DID (golden g2) → fallback зайвий. Orphan-ID (cited `did_derive.h`/`main.c`/§7, бракувало archive-рядка) | `03_01 §7` |
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
| DOC-T.2 | Канон↔канон дубль-аудит завершено: єдина справжня ПОВНА ре-декларація (Lorenz-блок `05_02` → `03_04 §4.1`) усунена; решта = контекстні згадки під value-guard'ами; ⚠️ blind value-de-dup небезпечний (колізії чисел) → рефати per-case; auto canon↔canon value-detect deferred | `00_06 §2`, §3 |
| DOC-T.15 | Volatile `*.c`/`*.h:N` line-refs killed (30 рефів → symbol/`#define`); guard `source_line_ref_drift` HARD | `00_06 §3` |
| DOC-T.17 | Volatile Ruby `*.rb`/`*.rake:N` line-refs killed (10 рефів, 7 доків → file/class); `SOURCE_LINE_REF_RE` alternation → HARD | `00_06 §3` |
| DOC-T.18 | Tracker parser моделює STAGE окремо від WHO (`EXECUTORS`=WHO-only · `STAGES`/`Item.stage` · conformance вимагає WHO·STAGE) | `lib/tracker/dashboard.rb`, `00_06 §3` |
| DOC-T.19 | Universal `**Стан:**` form-sweep усіх 138 items §00–§08 → `inline_residual_runon` + `verdict_lead_violations` обидва HARD = трекер однорідний | `lib/tracker/dashboard.rb`, `00_06 §3` |
| DOC-T.20 | DOC-T section гомогенізовано: resolved 15/17/18/19 + DOC-T.2 → §🗄️ (вердикт DOC-T.2 canonized → `00_06 §2`), `#### `-форму знято, section-title оновлено → active DOC-T = лише open (9/10/16) | `00_07` |
| DOC-T.22 | §01-02 HW під-регіон стандартизовано (form-decision: фасетні під-блокери інлайн HW.8-стилем, standalone-програма → `####`): HW.5 Gen 2.0-блок → pointer `01_03 §1–3`; HW.1.PicoGK + HW.3.IS згорнуто інлайн; HW.5.IS → `####` (CHEM.N + in-silico = `#####` working-backlog діти, kept per no-premature-canon). Drift-fixes по нитці: HW.3.IS creep→stress-relaxation + DFT→MD-permeation + Trek-C heavy-FEA→Гусак; `00_02 §4a` reconcile (аналітичний Lamé-bound легіт, відкладає важку FEA Гусаку); Стаття 28→Стаття 1; `01_03` HW.5a→HW.5 | `00_07`, `01_03 §1–3` |
| DOC-T.21 | 18 tracker-family `[ID]` cited у коді/доках без 00_07-дому → per-ID verify resolved-in-code + §🗄️ orphan-rows (OBS.1/SEC.5/SEC.8 pattern): S6.4/6/8/9/13/15/16/17/19 · FW.6/10/16/28 · E.46 · HW.10 · INF.5/7 = resolved code-annotations; FW.45 = dup→ARCH.18 (firmware-тег) | `00_07` |
| E.45 | SCC/SFC subgraph zero-address fail-fast guard (`subgraph/validate_addresses.sh`); real-address swap → S3.5 | `05_03` |
| OPS.5 | Projects V2 TRL field schema (1-9 + Readiness Horizon SRL/MRL; `lib/github_bootstrap.rb`); live-board bootstrap-run → OPS.6 | `00_05 §1.1` |
| E.61 | Solana micro-rewards batch payouts (Kredis-акумуляція → `transferChecked`, годинний cron, поріг-gated) | `05_01 §8`, `04_02 §10` |
| E.56 | DSP preprocessing для TinyML — RESOLVED: Path B log-mel (НЕ raw/MFCC); front-end `Compute_LogMel` | `03_03 §3.2/§3.4` |
| E.57 | TENSOR_ARENA budget — **дубль, не окремий трек** (НЕ resolved): робота й мітигація живуть в активному FW.26 | `03_03 §4.3` (active FW.26) |
| S6.4 | Per-service circuit breaker (web3 `ResilientClient`/`http_client.rb`) — resolved code-annotation, orphan-home (DOC-T.21) | `04_02`, `06_08` |
| S6.6 | Anchor-gap alerting threshold 8d (`EthereumAnchorWorker`) — resolved code-annotation | `05_04` |
| S6.8 | Weekend Telemetry Blackout — behaviour rationale — resolved code-annotation | `04_02` |
| S6.9 | Governance-controlled fallback price (`ProtocolParameters.sol`) — resolved code-annotation | `05_03` |
| S6.13 | IoTeX fallback allowed only legacy/dev TRL≤5 (`W3bstreamVerificationService`) — resolved code-annotation | `05_02` |
| S6.15 | Chainlink router ABI version-lock (`chainlink_router_version.rb`) — resolved code-annotation | `05_01` |
| S6.16 | Partition pruning from ISO-8601, single home (`TelemetryLog#partition_pruned`) — resolved code-annotation | `04_01` |
| S6.17 | Mint rate from `SystemParameter` (governance-aware) (`BlockchainMintingService`) — resolved code-annotation | `05_03` |
| S6.19 | m2m nonce-fallback counter for Grafana alerting (`m2m_auth_controller`) — resolved code-annotation | `04_03`, `06_03` |
| FW.6 | isfinite() RTC Lorenz-state validation (`soldier/main.c`) — resolved code-annotation | `03_04`, `03_01` |
| FW.10 | Winter-kenosis TX gate (−15°C, ESR) (`soldier/main.c`) — resolved code-annotation | `03_01` |
| FW.16 | `Restore_ECB_Mode` error-recovery after CoAP-CBC (`queen/main.c`; ↔ SEC.8) — resolved code-annotation | `03_05` |
| FW.28 | Atomic acoustic capture (ISR↔pack window lock) (`soldier/main.c`) — resolved code-annotation | `03_03` |
| FW.45 | Integer-Math/fixed-point Lorenz hardening — **дубль, не окремий трек** (deferred): концепт = active **ARCH.18** (FW.45 = firmware-тег цього ж рішення) | `03_04` (= ARCH.18) |
| E.46 | Mint-during-RPC-fail = no slash (`BlockchainMintingService`) — resolved code-annotation | `05_05`, `04_02` |
| HW.10 | PSM + eDRX idle-power for NB-IoT/LTE-M (`queen/main.c`) — resolved code-annotation | `03_02`, `02_05` |
| INF.5 | `PROMETHEUS_ALLOWED_IPS` CIDR allowlist for /metrics — resolved code-annotation | `06_03`, `06_04` |
| INF.7 | `ALLOY_CONFIG_BASE64` manual SDL deploy encoding — resolved code-annotation | `06_02` |
| DOC-T.23 | STAGE/WHO re-audit (7 WHO fixes, open-work semantic) + meta-line form std (combo `🤖+👤`, no tails) + AI-advanceability (S6.20/E.41 advanced); NEW guard `meta_form_violations` HARD | `00_07`, `00_06 §3` |
| DOC-T.24 | Priority re-assess (P1 73→59, un-flattened by TRL-horizon/blocking-impact) + stable in-section sort by priority (P0 gates surface on top); tools `tracker_set_meta.rb` + `tracker_sort.rb` | `00_07` |
| DOC-T.25 | 🚦 Dashboard refreshed from current items (UNI.13/14 priority drift fixed; 🤖-note S6.20/E.41) — human-curated do-now roadmap. (Superseded by DOC-T.16: Dashboard → slim 🚦 Critical Path; the unused auto-render code `Tracker::Dashboard.render`/`regenerate`/`check` pruned.) | `00_07` |
| DOC-T.16 | bare-§ після whole-doc-лінка (`[NN_NN](Doc) §X` → `[NN_NN §X](Doc)`, `00_06 §1`) — NEW guard `section_ref_after_doclink` (HARD, tree-wide вкл. `docs/protocols/` relative-href) + 1-shot sweep 35 рефів / 16 доків; по нитці виправлено стале §-номери (СЄУ §1.3→§5, Cold-Start→§1.5, фін-константи §2.3→§3). Ширша protocols ref-integrity → DOC-T.26 | `00_06 §3`, `lib/docs_linter.rb` |
| DOC-T.10 | 05/07 Фаза 3 (misplacement): Investor Q&A (колишня §11-секція `07_01`) = pitch/diligence presentation-шар (переказ канону) → Ruthless-Pruned; унікальний Q8-rationale (навіщо SCC, не USDC → Slashing = trustless accountability) мігровано в `05_03` (Dual Token System). Field Assembly + Virtual Prototyping у `07_03` = легіт grant-deliverables (реферять `01_04`/`02_01`/`06_04`) — no-move | `05_03`, `07_03` |
| DOC-T.26 | docs/protocols/ canon-ref blind spot — субдерево реферить top-level канон relative-path (`../../NN_NN`), поза top-level гейтами → майбутній rename/§-collapse тихо гнив би 84 рефи (клас §1.3→§5 у protocols/). Аналіз: protocols/ ЧИСТИЙ зараз (0 dangling/stale/value-drift, 84 well-formed relative-лінки) → фікс превентивний. NEW HARD `scripts/protocols_ref_check.rb` (CI docs.yml): resolution-only (target/§/anchor/bare-prefix), reuse `file_section_dangling_refs` + `DocsGraph.anchor_set`. Option A — форму не форсимо (14 bare-mentions лишені) | `00_06 §3`, `scripts/protocols_ref_check.rb` |
| DOC-T.9 | LoRa TX energy у 02_03: стара «15mA/50ms» → datasheet-correct «118mA × 0.1s = 38.94 мДж» — **doc-drift вже виправлено** + «тривалості = оцінки-стелі, консервативно (завищені vs виміряних)»-caveat inline `02_03 §9.4` (§9.5–9.7 = нижня межа запасу). Живий залишок «лаб-вимір TX» = **НЕ doc-drift** (mis-placed у DOC-T) → bench-вимір active-cycle енергії канонічно у `firmware/scripts/bench/RUNBOOK.md §3.2` (`03_power_profile.py --mode cycle` → E.63). Resolved + redundant + 0 inbound → archived | `02_03 §9.4` (+ RUNBOOK §3.2) |

