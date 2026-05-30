# 00_06: SSOT Documentation Standard & Drift Prevention

## 🎯 Мета

Канонічний дім **стандарту самих SSOT-документів**: як писати й супроводжувати `docs/NN_MM_*.md`, щоб не накопичувався SSOT-drift. Фіксує doc-skeleton, реєстр канонічних домів (*одна річ — один дім*), CI-enforced drift-tooling та метод реструктуризації/виносу теми в нову сторінку. Це той стандарт, на який спирається скіл `ssot-maintenance` (він — операційний HOW, цей документ — самі правила). Зафіксовано під час §06/§07 deep-review (2026-05-29); поширюється на всі модулі.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — стандарт впроваджено та **CI-enforced** (`docs:check_refs` + `tracker:check` як HARD-гейти у `docs.yml`/`ci.yml`). Відкриті — TRL range-consistency guard (roadmap) → [00_07](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [00_05_GitHub_Projects_and_IaC_Automation](00_05_GitHub_Projects_and_IaC_Automation) | Workflows, що ганяють ці гейти (`docs.yml`, `ssot_guard.yml`); Projects/Labels SSOT |
| [00_02_AI_Native_Engineering_and_TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native філософія + Wiki-First (no code until spec approved) |
| [00_03_TRL_Matrix_HIL_and_Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Per-module TRL matrix — канон-дім (§2 registry посилається сюди) |
| `lib/docs_linter.rb` · `lib/docs_toc.rb` · `lib/tasks/docs.rake` · `lib/wiki_link_normalizer.rb` | Engine'и drift-tooling (§3) — pure-функції, unit-tested |
| [00_00_SSOT_Index](00_00_SSOT_Index) | Reading-order + повний реєстр сторінок |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | Канонічний дім блокерів (§1) + open backlog |

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
- **Крос-рефи — один стандартний формат (рішення 2026-05-30).** Інлайн-посилання на канон: видима мітка веде з тим самим `NN_NN`, що й ціль href, а `§X` — **реальний номер секції** (`§4.1`, `§1A`, `§6.3`), НЕ описове слово. Приклад секції — `` [`05_05 §3`](05_05_Slashing_and_Risk_Policy) ``; на весь док — `` [`05_05`](05_05_Slashing_and_Risk_Policy) `` без `§`. Описовий контекст (назва концепту/концерну, напр. «Web3CircuitBreaker», «Q2Q Mesh») — у прозі ПОРУЧ, не в `§`-слоті. `docs:check_refs` (§3) флагає і §-мітку без відповідного заголовка в цілі, і label↔href-розбіжність: **стандартизуй реф, а не послаблюй гейт** (один формат < багато форматів + боротьба з лінтером).
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
| AES per-channel modes | `03_05 §3.7` |
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

> Повний канон↔канон дубль-аудит — `00_07 DOC.2`.

---

## 🛡️ 3. Drift-prevention tooling (CI-enforced)

| Guard | Що ловить | Команда / місце |
|---|---|---|
| `docs:check_refs` | dangling `NN_NN` doc-links (hard) + §-section label drift (advisory) | `bin/rails docs:check_refs` (ci.yml + docs.yml) |
| `tracker:check` | 00_07: dup-IDs, meta-line conformance, canon-ref resolution | `bin/rails tracker:check` (ci.yml + docs.yml) |
| `ssot_guard.yml` | protected code змінено → docs мусять оновитись | CI PR gate (00_05 §2.3) |
| regen-from-code | enumerable lists (метрики) генеруються з SSOT, не вручну | `06_03 §2.8` regen cmd |
| TRL presence | кожен док з `## ✅ Статус` декларує TRL (ловить 06_04-клас gap) | `bin/rails docs:check_refs` (hard) |
| TRL single-value | `00_03 §1` matrix-клітинки — одинарне 1-9, без діапазонів (00_05 §1.1) | `bin/rails docs:check_refs` (hard; `lib/docs_linter.rb`) |
| blocker-hygiene | канон-док не тримає `🛑 Блокери`/`✅ Архів` секцій — блокери лише в `00_07` (§1) | `bin/rails docs:check_refs` (**HARD** — sweep завершено 2026-05-30) |
| standard-conformance | кожен NN_NN-канон несе ✅ Статус + top 🔗 Cross-references + auto-ToC | `bin/rails docs:check_refs` (HARD; `lib/docs_linter.rb`) |
| ToC sync | docs з `TOC:AUTO` маркерами — зміст збігається з h2-заголовками | `bin/rails docs:check_refs` (HARD; writer `docs:toc`; engine `lib/docs_toc.rb`) |
| **RTC reg-map drift** | register availability (`DRn free/reserve`) живе лише в owner `03_01 §2`; інші доки не дублюють (зловив stale «DR15 резерв» у 03_02/00_07/03_03) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| **Lorenz-formula drift** | β-assignment (`beta = 8.0/3.0`) живе лише в owner `03_04 §4.1`; інші доки реферять, не re-declare (зловив stale σ/ρ/β у 05_01 + старому tech-00_01, розчиненому в P1b, при 05/07-реструктуризації) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| **link label↔href mismatch** | doc-link, де visible label веде з одним `NN_NN`, а href резолвиться на ІНШИЙ доку — renamed-doc residue, який dangling-check НЕ ловить (href валідний). Зловив 00_02 §3 (текст «00_06» → файл 00_05) + residue в 03_02 після renumber'у візії-доку (visible label-ID ≠ href-ID) | `bin/rails docs:check_refs` (HARD 2026-05-30; `lib/docs_linter.rb`) |
| TRL range-consistency | _(roadmap)_ per-doc member-TRL у межах діапазону модуля `00_03 §1` | — |

**Правило при зміні факту:** правити лише у home (§2) → рефи лишаються чинними; будь-який новий NN_NN-док/реф — `docs:check_refs` має лишатись зеленим перед merge.

**Публікація канону на Wiki:** `bin/rails wiki:sync` (dry-run за замовч.; `PUSH=1` публікує) дзеркалить `docs/NN_NN_*.md` → GitHub Wiki — нормалізує лінки (canon → bare wiki-link; non-doc repo-файли → absolute `blob/main` URL) + переносить зображення. **Ручний** запуск (рішення власника — НЕ on-merge); engine `lib/wiki_link_normalizer.rb` (unit-tested). Деталі — `lib/tasks/wiki.rake`.

---

## 🔀 4. Module-restructure / extract-to-new-page

Коли SSOT-факт переростає свій док (тема ≈ пів-сторінки + розпорошена дублями по сусідах), її виносять у **власну канон-сторінку**. Метод (verified 05/07-реструктуризацією 2026-05-30: slashing `00_01 §6` → `05_05`, governance `05_03 §749` → `05_06`; та таксономічною реструктуризацією v3 2026-05-30: junk-drawer Module 00 → Foundation (Vision+Method, 00) + Tier I (Система 01–06) + Tier II (Програма 07–08)):

1. **Migrate-first:** наповнити новий дім ПОВНОЮ субстанцією + verify present ПЕРШ ніж різати джерело (zero-loss).
2. **Stub + pointer:** джерело лишає тонкий vision/ref-stub `→ новий_дім`; механіка реферить існуючі доми, не дублює.
3. **Cross-ref sweep, anchored:** масовий re-point `NN_NN §X` → новий дім, **прив'язаний до якоря** (напр. лише рядки з конкретним old-ID), щоб не зачепити однойменні внутрішні §X інших доків. Ruby-скрипт-**файл** (не inline `-e`) з dry-run + presence-check + zero-loss referrer-diff. Для wholesale-renumber — single-pass simultaneous replace (одна alternation, ordered specific→generic) проти chained-rewrite багів; spine-owner-refs не в map → виживають.
4. **Реєстр + індекс:** оновити `§2` home-registry, `00_00` reading-order, README; archival-pointer у `00_07` (DOC-row).
5. **Per-фаза gate:** `docs:check_refs` + `tracker:check` зелені; zero-loss set-diff (referrers before/after = 0 lost); `wiki:sync` dry-run.
