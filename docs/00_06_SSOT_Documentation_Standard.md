# 00_06: SSOT Documentation Standard & Drift Prevention

## 🎯 Мета

Канонічний дім **стандарту самих SSOT-документів**: як писати й супроводжувати `docs/NN_MM_*.md`, щоб не накопичувався SSOT-drift. Фіксує doc-skeleton, реєстр канонічних домів (*одна річ — один дім*), CI-enforced drift-tooling та метод реструктуризації/виносу теми в нову сторінку. Це той стандарт, на який спирається скіл `ssot-maintenance` (він — операційний HOW, цей документ — самі правила). Зафіксовано під час §06/§07 deep-review (2026-05-29); поширюється на всі модулі.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — стандарт впроваджено та **CI-enforced** (`docs:check_refs` + `tracker:check` як HARD-гейти у `docs.yml` — єдиний дім, §3). Усі roadmap-гейти §3 реалізовані (останній — TRL range-consistency, 2026-06-03); magic-marker/ref-graph лишаються advisory/on-demand **за дизайном**, не як борг.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_05` — GitHub Projects and IaC Automation](00_05_GitHub_Projects_and_IaC_Automation) | Workflows, що ганяють ці гейти (`docs.yml`, `ssot_guard.yml`); Projects/Labels SSOT |
| [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native філософія + Wiki-First (no code until spec approved) |
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Per-module TRL matrix — канон-дім (§2 registry посилається сюди) |
| `lib/docs_linter.rb` · `lib/docs_toc.rb` · `lib/tasks/docs.rake` · `lib/wiki_link_normalizer.rb` | Engine'и drift-tooling (§3) — pure-функції, unit-tested |
| [`00_00` — SSOT Index](00_00_SSOT_Index) | Reading-order + повний реєстр сторінок |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Канонічний дім блокерів (§1) + open backlog |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Canonical doc skeleton](#-1-canonical-doc-skeleton)
- [2. Canonical-home registry (одна річ — один дім)](#-2-canonical-home-registry-одна-річ--один-дім)
- [3. Drift-prevention tooling (CI-enforced)](#-3-drift-prevention-tooling-ci-enforced)
- [4. Module-restructure / extract-to-new-page](#-4-module-restructure--extract-to-new-page)
<!-- TOC:AUTO:END -->

---

## 📐 1. Canonical doc skeleton

```
# NN_MM: Title
## 🎯 Мета
## ✅ Статус            — власний (member) TRL доку + rationale; агрегат-матриця лише в 00_03 §1; +1 рядок «відкриті → 00_07 §NN»
## 🔗 Cross-references  — ОДИН раз, угорі зразу під Статус: sibling-доки + ключові файли + 00_07-link
## 📑 Зміст             — авто-ToC між <!-- TOC:AUTO --> маркерами (h2 контенту); regen `bin/rails docs:toc`
## <Content>           — інженерна суть; поточні обмеження документуються прозою тут
```

- **Блокери — НЕ в каноні (рішення 2026-05-29).** Канон-док **не тримає** секцій `🛑 Блокери` чи `✅ Архів вирішених блокерів`. **Усі** блокери — і відкриті, і закриті — живуть **тільки в `00_07`** (відкриті → §модуль-реєстр як тонкі вказівники → канон; закриті → `00_07 §🗄️ Архів`). Канон описує дизайн і **відоме обмеження прозою в body** («як воно є»); чому member-TRL не вищий — 1 рядок у Статус із рефом `→ 00_07 §NN`. `docs:check_refs` ловить будь-яку лишкову блокер-секцію (§3).
- **Cross-references — угорі, DRY.** ОДНА секція зразу під Статус: sibling-доки + ключові файли + `00_07`-link (канонічний дім блокерів). Прибрано дубль: окремий список «Пов'язані модулі» в Статус та окрема References-секція внизу більше НЕ використовуються — це й була основна дуплікація.
- **Крос-рефи — один стандартний формат (рішення 2026-05-30).** Інлайн-посилання на канон: видима мітка веде з тим самим `NN_NN`, що й ціль href, а `§X` — **реальний номер секції** (`§4.1`, `§1A`, `§6.3`), НЕ описове слово. **Мітка ЗАВЖДИ веде з code-span `` `NN_NN` ``** — це ЄДИНИЙ дозволений діалект (HARD-enforced 2026-06-01), у трьох формах: `` [`05_05`](05_05_Slashing_and_Risk_Policy) `` (на весь док) · `` [`05_05 §3`](05_05_Slashing_and_Risk_Policy) `` (секція, `§X` = реальний номер) · `` [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) `` (directory-рядок: title ПОЗА code-span). Заборонено plain `[05_05 …](Doc)`, escaped `[05\_05\_…](Doc)`, full-name-in-codespan `` [`05_05_Full_Name`](Doc) `` — це той самий реф у другому написанні. Описовий контекст (назва концепту, напр. «Web3CircuitBreaker») — у прозі/після em-dash ПОРУЧ, не в `§`-слоті й не всередині code-span. Prose-фразовий лінк (мітка без doc-id, напр. «`[живе тут](Doc)`») — легітимний. `docs:check_refs` (§3) флагає §-мітку без заголовка, label↔href-розбіжність і не-code-span мітку: **стандартизуй реф, а не послаблюй гейт** (один формат < багато форматів). Bulk-нормалізація — `scripts/normalize_crossrefs.rb`; таксономія/аудит — `scripts/crossref_audit.rb`.
- **Статус — lean (рішення 2026-05-29).** Лише member-TRL + rationale (+ «відкриті → `00_07 §NN`»). БЕЗ build-state таблиць «Компонент | Стан» — стан компонентів живе в body + code-рефах Cross-references (інакше дубль body/00_07 → drift).
- **Без волатильних лічильників (рішення 2026-05-29).** Не хардкодити в прозі к-сть тестів / рядків коду — дрейфують на кожен коміт (у 03_01 знайдено `264` vs `511` vs `83/105` в одному доку). Рефати на джерело (`make -C firmware/test`, suite) або генерувати (як метрики `06_03 §2.8`). Spec/wire-константи (21-байт фрейм, DR0..DR19, 0.47F) — design-факти, лишаються.
- **Зміст — авто (рішення 2026-05-29).** `## 📑 Зміст` зразу під Cross-references; тіло між `<!-- TOC:AUTO:START/END -->` ГЕНЕРУЄТЬСЯ з h2-заголовків (`bin/rails docs:toc`), `docs:check_refs` падає при дрейфі. Потрібен бо Wiki не має авто-outline; ручний список заборонено (дрейф). Анкори = GitHub-слаги (`lib/docs_toc.rb`).
- **File Map** — опційно; згортається у Cross-references.

---

## 🏠 2. Canonical-home registry (одна річ — один дім)

Кожен факт має **ОДИН** SSOT-дім; усе інше — реф, не re-statement. Дзеркало позначати: «значення тут — дзеркало SSOT, правити там».

| Факт | SSOT home |
|---|---|
| Per-module TRL матриця | `00_03 §1` (агрегат-дім). Модульний док = власний member-TRL у Статус (це джерело, не дубль); заборонено відтворювати всю матрицю поза §1 |
| Beyond-TRL-9 / SRL-MRL R&D-агенда (Planetary Intelligence gaps + фрактальне масштабування) | `00_08` |
| AES per-channel modes | `03_05 §6` (зведена channel-таблиця) + `§3.7` (ключі/ARCH.42). Firmware-доки `03_01 §9` / `03_02 §8` реферять цю таблицю, не дублюють (DOC-T.14) |
| Lorenz константи | `03_04 §4.1` |
| Tokenomics rate / slashing thresholds / insurance pool | `05_03` · `05_05 §3/§4` |
| Carbon (2000 SCC = 1 tCO₂) | `05_03` + `07_01 §3` (business view) |
| Financial constants (business) | `07_01 §3` (з рефами на 05_03/00_01) |
| Slashing penalty formula | `05_05 §3` ↔ `BlockchainBurningService` |
| Lorenz Z↔health ground-truth / de-risk протокол | `05_05 §8` (калібрує пороги §3/§7; партнерський ростер ФОТІУС/ЧНУ → `08_02`) |
| Governance / DAO params (Governor, Timelock, ProtocolParameters) | `05_06` |
| Secrets inventory | `06_04` (canonical = `config/deploy.yml env.secret`) |
| Prometheus metric registry | `06_03 §2.8` (regen з `SilkenNet::Metrics::REGISTRY`) |
| DR / backup posture | `06_06` (config SSOT = `terraform/database.tf`) |
| CI/CD workflows + runbook index | `06_07` |
| Академічний ростер (5 ВНЗ: партнер → що валідує → канон-дім) | `08_02` (Academic Institutions Registry; §1 ЧНУ [§1A Hard Science + §1B ФОТІУС], §2 ЧДТУ, §3 ЧІПБ, §4 ЧМА, §5 СЄУ) |
| MOIC-концепція кластера + план публікацій (Ст. 1–35) + IP-рамка | `08_01` (cluster head) |
| Зовнішні стейкхолдери (B2G/B2B + культурний шар) | `08_03` (External Stakeholders Registry) |
| Firmware internals split | **Soldier** RAM/tests/lifecycle + RTC reg-map → `03_01`; **Queen** deep-dive (RAM `§9` · HAL `§10` · host-tests `§11` · `#define` `§0`) → `03_02`. Кожен реферить інший, не дублює (DOC-T.14) |

> Повний канон↔канон дубль-аудит — `00_07 DOC-T.2`.

---

## 🛡️ 3. Drift-prevention tooling (CI-enforced)

| Guard | Що ловить | Команда / місце |
|---|---|---|
| `docs:check_refs` | dangling `NN_NN` doc-links (hard) + §-section label drift (advisory) | `bin/rails docs:check_refs` (ci.yml + docs.yml) |
| `tracker:check` | 00_07: dup-IDs (**whole-file global uniqueness** — кожен item-ID унікальний across усі секції вкл. 📌 Backlog / 🗄️ Архів; реюз через `all_item_ids`, єдиний span з inbound-guard'ом — закрив DOC-T.12 #### ↔ registry-table-row 2026-06-01 + `OPS.5` §07-heading ↔ 📌-backlog-row 2026-06-03), meta-line conformance, canon-ref resolution + **§-section resolution** (a `NN_NN §X` pointer's §X must be a real heading — зловив 12 stale `§BLOCKER-N`/wrong-doc-id рефів, осиротілих blockers→00_07 sweep'ом; thread C 2026-05-31). Parser tolerant до emoji/✅-префікса і в `#### 🌿 ID`, і в table-row `\| ✅ ID \|` (раніше UNI.13a/BIZ.12 + status-prefixed backlog-рядки були невидимі усім чекам) | `bin/rails tracker:check` (ci.yml + docs.yml) |
| **section↔canon-home** | 00_07 canon-mirror One-Home: кожен `#### ` під `## §NN` має canon-ref модуля NN (`§03/§05` / `§01–§02` декларують multi-module set у заголовку; 🔀/📌/🗄️ exempt). Закрив «§06-deploy-під-§04-DevOps» drift (15 S*/INF* айтемів ховалися під §04 за nav-нотатками) при canon-mirror реструктуризації 00_07 (2026-06-01) | `bin/rails tracker:check` (HARD; `lib/tracker/dashboard.rb`) |
| **inbound 00_07 item-ref** | reference з ІНШОГО доку виду `[`00_07` — <ID>]` (directory-link на 00_07) має резолвитись у реальний item (всі `####` + table-row IDs, **усі секції** вкл. 📌/🗄️ — `all_item_ids`). `tracker:check` раніше валідував лише ВЛАСНІ рефи 00_07, не inbound → renamed/removed item тихо протухав (зловив dangling `06_02 → 00_07 DOC.5`, оголений DOC.N-namespace роботою). ID вимагає `.`/`-` сепаратора → directory-title лінк (`00_07 — Action Plan Tracker`) не FP | `bin/rails tracker:check` (HARD 2026-06-03; `lib/tracker/dashboard.rb`) |
| **prose 00_07 ID-ref** | ID, цитований у ПРОЗІ зразу після `00_07`-лінка (`→ [`00_07`](…) (S4.3, INF.4, S5.6)`), має резолвитись у реальний item. `inbound`-guard бачив лише em-dash `[`00_07` — ID]`, тож wrong-id (`S6.1` Redis замість GCS-bucket `S5.6`) і ref на ще-неіснуючий (`OBS.1` до появи рядка) тихо протухали — обидва зловлені 2026-06-03. Парсить повні ID-токени (digit-bearing → `X.*` wildcard без цифри пропускається), `/`-digit родини (`INF.3/4/6`) розкриває; token-shape-фільтр → прозові слова/`§X` не FP | `bin/rails tracker:check` (HARD 2026-06-03; `lib/tracker/dashboard.rb`) |
| `ssot_guard.yml` | protected code змінено → docs мусять оновитись | CI PR gate (00_05 §2.3) |
| regen-from-code | enumerable lists (метрики) генеруються з SSOT, не вручну | `06_03 §2.8` regen cmd |
| TRL presence | кожен док з `## ✅ Статус` декларує TRL (ловить 06_04-клас gap) | `bin/rails docs:check_refs` (hard) |
| TRL single-value | `00_03 §1` matrix-клітинки — одинарне 1-9, без діапазонів (00_05 §1.1) | `bin/rails docs:check_refs` (hard; `lib/docs_linter.rb`) |
| blocker-hygiene | канон-док не тримає `🛑 Блокери`/`✅ Архів` секцій — блокери лише в `00_07` (§1) | `bin/rails docs:check_refs` (**HARD** — sweep завершено 2026-05-30) |
| standard-conformance | кожен NN_NN-канон несе ✅ Статус + top 🔗 Cross-references + auto-ToC | `bin/rails docs:check_refs` (HARD; `lib/docs_linter.rb`) |
| ToC sync | docs з `TOC:AUTO` маркерами — зміст збігається з h2-заголовками | `bin/rails docs:check_refs` (HARD; writer `docs:toc`; engine `lib/docs_toc.rb`) |
| **RTC reg-map drift** | register availability (`DRn free/reserve`) живе лише в owner `03_01 §2`; інші доки не дублюють (зловив stale «DR15 резерв» у 03_02/00_07/03_03) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| **Lorenz-formula drift** | β-assignment (`beta = 8.0/3.0`) живе лише в owner `03_04 §4.1`; інші доки реферять, не re-declare (зловив stale σ/ρ/β у 05_01 + старому tech-00_01, розчиненому в P1b, при 05/07-реструктуризації) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| **growth_points clamp drift** | retired pre-FW.29-PACK wire-clamp `clamp(…,10,63)` (6-біт) живе лише як history в owner `03_04 §4.3`; чинний FW.29-PACK wire = `(reward / 2).clamp(5, 31)` (backend ×2 → stored 0..62). Жоден інший guard його не бачив (Lorenz знає лише β; rate-guard exempt-ить manifest), тож stale-копія тихо misstate-ила token-emission у CLAUDE.md (R8) + manifest:78 (R9). **НЕ** table-skip — дрейф жив саме у table-cell. Exempt: owner 03_04 + firmware-mirror 03_01 + standard 00_06 + tracker 00_07 | `bin/rails docs:check_refs` (HARD 2026-06-03; `lib/docs_linter.rb`) |
| **cross-ref label single-form** | КОЖНА мітка doc-id-лінка має вести з code-span `` `NN_NN` `` — один дозволений діалект (`` [`NN_NN`](Doc) ``, `` [`NN_NN §X`](Doc) ``, `` [`NN_NN` — Title](Doc) ``). Plain `[NN_NN …](Doc)`, escaped `[NN\_NN\_…](Doc)`, full-name-in-codespan `` [`NN_NN_Full`](Doc) `` = той самий реф у 2-му написанні → flagged. Prose-фраза без doc-id лишається. Звело 445 лінків у 50 доках (`scripts/normalize_crossrefs.rb`); таксономія — `scripts/crossref_audit.rb` | `bin/rails docs:check_refs` (HARD 2026-06-01; `lib/docs_linter.rb`) |
| **link label↔href mismatch** | doc-link, де visible label веде з одним `NN_NN`, а href резолвиться на ІНШИЙ доку — renamed-doc residue, який dangling-check НЕ ловить (href валідний). Зловив 00_02 §3 (текст «00_06» → файл 00_05) + residue в 03_02 після renumber'у візії-доку (visible label-ID ≠ href-ID) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| **magic-marker hex** | _(advisory)_ визначення 4-байтного ASCII-маркера (`"LZST" = 0xNNNN`) має дорівнювати BE/LE byte-packing власного імені — self-validating, без таблиці (firmware змішує endianness: `RITE`=LE, `LZST`=BE); ловить typo'd/stale magic-value (клас 9cb1d86). Hex-посилання за значенням (без сусіднього імені) не чіпається | `bin/rails docs:check_refs` (advisory 2026-05-30; `lib/docs_linter.rb`) |
| **bare §-ref → link** | code-span `NN_NN §X` поза markdown-лінком — non-standard + blind spot (`section_label_drift` валідує лише лінковані рефи). Стандартизувати у повний лінк (канонічна форма — §1). Exempt 00_00/00_06/00_07/02_06; skip fences + meta-плейсхолдери (`§NN`/`§X.Y`) | `bin/rails docs:check_refs` (HARD 2026-05-31; `lib/docs_linter.rb`) |
| **bare doc-id → link** | сиблінг bare-§ для **whole-doc** рефів: code-span `NN_NN` / `docs/NN_NN` / `NN_NN_FullName` **без** § поза лінком має бути повним лінком (канонічна форма — §1), не lone code-span (клікабельність + один формат). Ловить лише id, що резолвиться в поточний док (retired-`04_07` лишається прозою); skip fences + спани в лінках. Закрив 213-реф thread-A sweep (`scripts/linkify_bare_refs.rb`). Exempt 00_00/00_06/00_07/02_06/manifest | `bin/rails docs:check_refs` (HARD 2026-05-31; `lib/docs_linter.rb`) |
| **tokenomics/carbon rate One-Home** | mint-курс + carbon-курс — governance-змінні **параметри** → значення живе лише в home (`05_03` + business-view `07_01 §3`); re-statement деінде = silent drift при re-price (зловив дубль у 8 доках). Exempt homes + labeled-mirror `07_02` + manifest + 00_07 | `bin/rails docs:check_refs` (HARD 2026-05-31; `lib/docs_linter.rb`) |
| **#anchor resolution** | кожен `#anchor`-фрагмент у doc-лінку (intra-doc — фрагмент до власного заголовка; cross-doc — `NN_NN_Name#fragment`) резолвиться в реальний heading-слаг цілі — стале посилання тихо кидає читача на верх сторінки, а §-label-гейт його не бачить. Випущено з on-demand `docs:graph` у HARD-gate (2026-06-01), коли всі anchors стали чистими; engine той самий (`DocsGraph.dangling_anchors`, тепер fence-aware) | `bin/rails docs:check_refs` (HARD 2026-06-01; `lib/docs_graph.rb`) |
| **external doc-path** | репо-файли ПОЗА `docs/` (`.github/` workflows+configs+copilot/labels, root `README`/`CLAUDE`/`AGENTS`, **+ source-дерева** `bin`/`lib`/`app`/`firmware`/`contracts`/`spec` — code-коментарі) реферять канон-доки шляхом теж; renamed/renumbered док лишає їх stale, а in-docs гейт цього **не бачить** (blind spot, що ховав `docs/00_07_GitHub_Projects…`→00_05 + `docs/08_07_SEU…`→08_03 + source `00_08`→00_07 + `03_05`-rename residue у 8 файлах app/bin/spec). Флагає будь-який `docs/NN_NN_Name`, чий точний basename ≠ поточний док (лінтер `lib/docs_linter.rb` + його spec exempt — цитують stale-приклади як приклади) | `bin/rails docs:check_refs` (HARD 2026-06-02, source-scope 2026-06-03; `lib/docs_linter.rb`) |
| **deprecated terms (Ruthless Pruning)** | ретирований SSOT-токен не сміє повертатись в **активний** канон — enforcement-рука Ruthless Pruning (§4). Лише **однозначно** мертві рядки: HKDF `silkennet-v1-aes256`; партномер `ZP-3`/`ZP-5` (∅27 мм через-отв. п'єзо → SMD, `02_01 §3`). Ще-живий токен НЕ додається (LTC3108 виживає як DNP fallback → не guard-иться). Exempt: 02_06 (legacy-дім) · 00_06 (цитує приклади) · 00_07 (tracker) | `bin/rails docs:check_refs` (HARD 2026-06-02; `lib/docs_linter.rb`) |
| **TRL range-consistency** | per-doc member-TRL у межах **band** модуля (`00_03 §1`): (a) рядок well-formed (current ≤ target) + (b) рядок ≤ max member-TRL під-доків (рядок = min, не вище за КОЖНОГО члена) + (c) member ≤ target модуля. Перевіряє лише **верхні** межі — нижня має легітимні винятки (рядок = min критичного шляху → під-док буває нижче: 06_01 off-path, 00_03 Статус звітує System-TRL). Owner-only-vocabulary, як інші value-гейти | `bin/rails docs:check_refs` (HARD 2026-06-03; `lib/docs_linter.rb`) |
| **ref-graph audit** | _(on-demand, НЕ CI-gate)_ orphan/dead-end сторінки · in/out-degree skew · one-way (asymmetric) sibling-лінки · linked-`§X` валідація — власний ref-граф канону (GitNexus моделює код, не NN_NN-конвенцію). `#anchor`-резолюція звідси випущена у HARD-gate (рядок вище); граф лишає графовий вигляд, якого per-line гейти не дають | `bin/rails docs:graph` (`lib/docs_graph.rb`; spec `spec/lib/docs_graph_spec.rb`) |

**Правило при зміні факту:** правити лише у home (§2) → рефи лишаються чинними; будь-який новий NN_NN-док/реф — `docs:check_refs` має лишатись зеленим перед merge.

> **Чому value-guards «знають» константи (Lorenz β, RTC-реєстри, mint/carbon-курс) — і це НЕ оверінжиніринг:** це **owner-only vocabulary**, а не оракул коректності. Гейт не перевіряє, що β=8/3 *правильне* — він перевіряє, що воно не **продубльоване** поза домом (03_04 §4.1). Хардкод значення в регексі — **навмисний tripwire**: коли governance перепрайсить курс або змінять β, гейт червоніє й **примушує** свідомо оновити всі згадки, а не лишити тихий stale. Це фіча, не технічний борг. Довгостроково ці параметри стануть runtime-керованими (`ProtocolParameters`, [`05_06`](05_06_Governance_and_DAO)) — тоді guard природно еволюціонує з value-literal у reference-check. Engine-и (`lib/docs_*.rb`) — **чисті Ruby-функції без Rails-залежності** (unit-tested; rake-таска лише оркеструє I/O), тож логіка гейту не прив'язана до стеку.

> **Швидкий локальний прогін (без Rails):** `ruby scripts/docs_check.rb` ганяє `docs:check_refs` + `tracker:check` за ~0.3 с (vs ~1.2 с `bin/rails`), reuse-ячи ТІ САМІ rake-тіла (нуль дублювання — не може розійтися з CI); потрібен лише `ruby` + `rake` (default gem), без `bundle`/БД. CI-дім цих гейтів — **`docs.yml` (єдиний; дубль із `ci.yml` прибрано 2026-06-02, щоб mixed code+docs PR не ганяв їх двічі)**; `docs.yml` тригериться й на `.github/**` (щоб external-doc-path guard бачив зміни поза `docs/`). `main` наразі **без branch-protection** — при її ввімкненні позначити `docs_check` required.

**Публікація канону на Wiki:** `bin/rails wiki:sync` (dry-run за замовч.; `PUSH=1` публікує) дзеркалить `docs/NN_NN_*.md` → GitHub Wiki — нормалізує лінки (canon → bare wiki-link; non-doc repo-файли → absolute `blob/main` URL) + переносить зображення. **Ручний** запуск (рішення власника — НЕ on-merge); engine `lib/wiki_link_normalizer.rb` (unit-tested). Деталі — `lib/tasks/wiki.rake`.

> **Wiki — генерований артефакт, one-way (docs/ → Wiki), НЕ редагується вручну.** SSOT живе ТІЛЬКИ в `docs/`; правка через web-інтерфейс Wiki буде затерта наступним sync (тож drift «хтось поправив у Wiki, і воно не повернулось» не виникає — Wiki не є джерелом). Нормалізатор **обов'язковий**: сирий `git push --mirror` зламав би всі canon-лінки (напр. [`05_05`](05_05_Slashing_and_Risk_Policy) у Wiki має стати bare-сторінкою), repo-file-посилання та зображення — саме тому існує `wiki_link_normalizer.rb`, а не голий mirror. Тобто це НЕ «подвійне життя SSOT», а детермінована one-way генерація (як збірка сайту з джерела).

---

## 🔀 4. Module-restructure / extract-to-new-page

Коли SSOT-факт переростає свій док (тема ≈ пів-сторінки + розпорошена дублями по сусідах), її виносять у **власну канон-сторінку**. Метод (verified 05/07-реструктуризацією 2026-05-30: slashing `00_01 §6` → `05_05`, governance `05_03 §749` → `05_06`; та таксономічною реструктуризацією v3 2026-05-30: junk-drawer Module 00 → Foundation (Vision+Method, 00) + Tier I (Система 01–06) + Tier II (Програма 07–08)):

1. **Migrate-first:** наповнити новий дім ПОВНОЮ субстанцією + verify present ПЕРШ ніж різати джерело (zero-loss).
2. **Stub + pointer:** джерело лишає тонкий vision/ref-stub `→ новий_дім`; механіка реферить існуючі доми, не дублює.
3. **Cross-ref sweep, anchored:** масовий re-point `NN_NN §X` → новий дім, **прив'язаний до якоря** (напр. лише рядки з конкретним old-ID), щоб не зачепити однойменні внутрішні §X інших доків. Ruby-скрипт-**файл** (не inline `-e`) з dry-run + presence-check + zero-loss referrer-diff. Для wholesale-renumber — single-pass simultaneous replace (одна alternation, ordered specific→generic) проти chained-rewrite багів; spine-owner-refs не в map → виживають.
4. **Реєстр + індекс:** оновити `§2` home-registry, `00_00` reading-order, README; archival-pointer у `00_07` (DOC-row).
5. **Per-фаза gate:** `docs:check_refs` + `tracker:check` зелені; zero-loss set-diff (referrers before/after = 0 lost); `wiki:sync` dry-run.

> **Ruthless Pruning (зворотний бік zero-content-loss).** «Zero-loss» стосується **реструктуризації** (перенесення *живого* факту в новий дім), а НЕ архівного накопичення. Ключова межа — **мертвий артефакт vs живе обґрунтування**: спростовану гіпотезу, застарілу залізку чи чисту історію реалізації (напр. гіпотеза «44 мВ streaming-potential» як джерела енергії, 4 голки-електроди Кельвіна, U.FL-кабель, breadboard-каскад LTC3108→Meissner) **видаляють з активного канону**; натомість **стисле design-justification** («чому обрали X, а не Y» — 1–2 рядки + pointer) **лишається інлайн**, бо пояснює *поточний* дизайн. NB: ретирується мертва **роль**, не завжди весь компонент — LTC3108 виключено як первинний boost-каскад, але він **виживає** як DNP cold-start fallback ([`02_03 §1.5`](02_03_BQ25570_MPPT_Nano_Power)), тож лишається у каноні легітимно. Мертві ідеї роздувають контекст для LLM-агентів → ризик галюцинацій «воскреслими» концептами (Git тримає історію, цього досить). Якщо артефакт має історичну/навчальну цінність — виносять у явно марковану **legacy-appendix** сторінку (взірець — [`02_06`](02_06_Legacy_Breadboard_Appendix), яку лінтери exempt-ять і яку виключено з AI-контексту через `.aiignore`/`.cursorignore`), а не лишають у активному дереві. Повернення ретированого **імені** (лише однозначно мертвого — напр. партномер ZP-3/ZP-5; НЕ ще-живий LTC3108) замикає `DocsLinter::DEPRECATED_TERMS` (§3).
