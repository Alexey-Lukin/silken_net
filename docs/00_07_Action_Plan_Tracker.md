# 00_07: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати **ТІЛЬКИ незавершене** — кожен пункт як **тонкий вказівник**: `ID · пріоритет · виконавець` + 1 рядок + **→ канон-реф**. Повний опис «як має бути» живе в каноні (`00_00`→`08_02 §5`), описаний **в одному місці**; 00_07 на нього посилається, **не дублює**.

**Правило одного місця (DRY):** редагуєш канон → онови залежні пункти 00_07 (за рефами); закрив пункт → онови канон + познач тут (✅ → **§🗄️ Архів**, вказівник ID→канон). Так апдейт робиться в одному місці, а референси ведуть, де ще синхронізувати.

**Структура:** **🚦 Critical Path** (P0-гейти перед мілстоунами) → **§00–§08 модуль-секції** (реєстр незробленого; **номер секції = канон-модуль першого рефа** — enforced `tracker:check` section-home guard; великий модуль → під-секції **`§NNa/b/c`** того ж модуля, курація за під-темою — §01a Anchor / §01b EBFC, §02a Node / §02b Gateway, §03a Firmware / §03b Edge-crypto, §08a/b/c) → **🔀 Cross-cutting** / **📌 Backlog** → **🗄️ Архів**. Документ — живий операційний інструмент.

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
- [§01a · Anchor — Geometry & Metallurgy](#01a--anchor--geometry--metallurgy)
- [§01b · EBFC — Chemistry & Bio-electrochemistry](#01b--ebfc--chemistry--bio-electrochemistry)
- [§02a · Node — Capsule & Electronics](#02a--node--capsule--electronics)
- [§02b · Gateway — Queen Hardware](#02b--gateway--queen-hardware)
- [§03a · Firmware](#03a--firmware)
- [§03b · Edge crypto](#03b--edge-crypto)
- [§04 · Backend / API / UI](#04--backend--api--ui)
- [§05 · Web3 / Економіка / Slashing](#05--web3--економіка--slashing)
- [§06 · Deploy / Observability / Secrets / Ops](#06--deploy--observability--secrets--ops)
- [§07 · Юридичні / Бізнес](#07--юридичні--бізнес)
- [§08a · Академічна інтеграція](#08a--академічна-інтеграція)
- [§08b · External Stakeholders (B2G / B2B / Cultural)](#08b--external-stakeholders-b2g--b2b--cultural)
- [§08c · IP / Grants (BIZ)](#08c--ip--grants-biz)
- [Cross-cutting · Doc-drift (DOC-T) — SSOT doc↔code + tracker form/tooling](#-cross-cutting--doc-drift-doc-t--ssot-doccode--tracker-formtooling)
- [Backlog (не блокери · довгострокові)](#-backlog-не-блокери--довгострокові)
- [Архів закритих пунктів (мігровано в канон)](#-архів-закритих-пунктів-мігровано-в-канон)
<!-- TOC:AUTO:END -->

---

## 🚦 Critical Path — P0-гейти перед мілстоунами

> Крос-модульний зріз **P0-блокерів** перед ключовими мілстоунами (тонкі ID-вказівники; повний опис кожного — у §модулі, **one place**). P1/P2 — у §модулях (DOC-T.24 виносить пріоритет нагору в секціях). 🤖-роботи — у 🔀 `DOC-T`.

- **Перед польовим деплоєм** (life-safety + security): `SEC.9` · `SEC.3` · `SEC.1` · `FW.2`-фліп (ухвала (а): CCM-cutover ДО першого field-deploy — rollback до поля = хвилини, після = SWD-візити)
- **Перед Web3 mainnet:** `S1.1` (GitHub CI secrets) · prod deploy-ENV → [`06_04`](06_04_Secrets_Checklist) (вкл. `SOLANA_RPC_URL` — інакше USDC на Devnet; guard ✅ E.47) · `S2.1`+`S2.2`+`S2.3` (Grafana після першого `/metrics`) · `E.32` (paid manual audit — HARD) · `SLASH-1` (розширення A-сету + uplift-фліп) · `BIZ.4` (Governor/Timelock активація + transfer admin) · `S3.5` (subgraph cutover)
- **Найближчий фіз-мілстоун — TRL 3→4 = Ti-coin in-vitro** (founder 2026-06-21; гроші є → блок не фінанси): вузький шлях, що **ОБХОДИТЬ** гіроїд/PEEK/press-fit/mate — `HW.24` Stage 2 (**6-alloy coin bake-off** Ø16 → EAAE → Gen 2.0 функціоналізація → CV/EIS у соку) + `HW.5` (хімія-стек) + V-release ICP-MS (`HW.3`). Канал = **гібрид commercial-lab + ЧНУ** (не чекати MoU). Канон [`01_01 §6.1`](01_01_Coaxial_Gyroid_Topology_and_PEEK)
- **Hardware-гейт** (TRL 4→6, повний анкер — після coin): `HW.1` (анкер-генерація — CAD machine-half ✅, фіз-друк → завод) · `HW.24` (staged validation SLA→coin→anchor→100) · `HW.23` (HIP postprocess) · `HW.31` (BOM Королеви)
- **Academic:** `UNI.1` (лаб + публікації) · `UNI.14` (MSA / B2B legal)

### ⛓️ Гейт-кластери — одна дія відкриває кластер (міжсекційна синергія)

> Друга вісь зрізу (доповнює мілстоун-рядки ↑): **вісім «ключів»** — вузьких дій/подій, на які трекер сходиться across секції (звірено item-by-item 2026-07-03, §02a/§02b/§03a/§03b/§04/§05/§06). Тонкі ID-вказівники; деталь у пунктах.

| 🔑 Ключ (WHO) | Відкриває (кластер) |
|---|---|
| **HW.9 KiCad PCB** (👤; сам ← BOM-фіналізація `HW.7/12/13/20` + RF Keep-Out) | `HW.17`-dimensions · `HW.29`-footprints · `HW.20`-BOM-part · SE050 DNP-footprint · `ARCH.35` W25Q32-розводка · пін-мапа → **FW.46 `.ioc`** (ланцюг до bench-дня ↓) |
| **FW.46 board-freeze** `.ioc` (👤) | повний `.elf` → увесь bench-день: `FW.2`-фліп · `FW.3/8/17/20/23/31/49/50/52/54/55` · `ARCH.26/41` · `SEC.2`-OTA-verify · `SEC.15`-WUT · `SEC.3`-SWD · `ARCH.35`-розводка · `radio_conf.h` → компіляція `radio.c` (SubGHz Шлях A ✅ 07-04: submodule+`RadioEvents_t` уже в репо — це останній radio-гейт); суміжно `ARCH.34`-firmware (LoRaMac-node ВЖЕ vendored у `extern/subghz-phy/lorawan` — лишилась glue-робота) |
| **Перший live-деплой** = секрети (`S1.1`+`INF.19`+`S4.3`) → deploy (👤) | верифікації `INF.11/12/13/14/15/16` · `PUMA-IPV6-1` · `INF.10`-фліп · `S5.2` · `S3.2`-staging · `S6.1`-Upstash · Grafana-сесія (`S2.1→S2.2→S2.3` + `S2.4`-SLO + `FW.18b` + `ARCH.54`-alert) |
| **INF.4 TLS-рішення** (👤, рекоменд. A) | `INF.3` TLS · `S6.18` `RAILS_ALLOWED_HOSTS` (публічний домен) |
| **SE051 eval-пара** замовлення (👤) | `SE050-MIGRATION` silicon-confirm + rename-каскад · `SEC.3` Гілка-B real-I²C |
| **E.20 ForestBountyService** (🤖 за founder-go) | `E.41` satellite-obscured fallback · `S6.10` task-assignment · `BIZ.13` Модель-B operator-bond · `INS.1` drought/pest Trigger-2-джерело |
| **E.63 bench-шкала** = `HW.13` P-V + recharge-крива (👤) | `E.63`-калібрування + строгість-фліп · `FW.49`-S2 · `E.64` real-signal пороги (wire-rev2.1 носій уже готовий) |
| **Downlink-wire-ревізія** MAC/FC (🤖+👤 дизайн, пост-CCM) | `FW.17`-активація (гейти i/ii) · `ARCH.43` wire-rev3 mesh-return (з `ARCH.26`-фліпом) |

## §00 · Process / IaC / SSOT-tooling

> Process-automation, Projects-V2/IaC та SSOT-tooling — канон `00_04`/`00_05`. P0-гейти — у 🚦 Critical Path.

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **P1** · 👤 · 🟢 · → `00_05`
- **Стан:** `trl_sync.yml` реалізовано — GraphQL Projects v2 + TRL≥5 architect-approval gate (OPS.9); чекає лише secret-provision, канон `00_05 §2.2`.
- [ ] 👤 створити `PROJECT_PAT` (project:write) + тест з issues
- [ ] 👤 (security) мігрувати `PROJECT_PAT` → GitHub App installation token (`GITHUB_TOKEN` не вміє Projects V2; `00_05 §2.2`)

#### OPS.2 — SSOT Integrity Guard
- **P1** · 👤 · 🟢 · → `00_05`
- **Стан:** Hard SSOT-gate **landed (2026-06-19):** `main` (branch-protection, `enforce_admins=false`) вимагає `CI passed` (ci-ok) **+ `Docs passed`** — `docs-ok` always-on aggregate у `docs.yml` (tracker:check/docs:check_refs/linter-specs/model-sync гейтяться `changes`-джобом, але `docs-ok` `if: always()`, тож надійний required-чек; path-gated `docs_check` напряму required бути не може — блокував би code-only PR). `ssot_guard.yml` (`type:*` bypass) біжить path-gated advisory поруч. Канон `06_07 §2`, `00_05 §2.3`.
- [ ] 👤 (опц.) увімкнути "Require review from Code Owners" коли зʼявиться другий рев'юер (CODEOWNERS уже на місці)

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **P1** · 👤 · 🟢 · → `00_04 §5`, `00_05 §6`
- **Стан:** Shape Up template + Projects V2 kanban-mapping реалізовано (R&D Cluster/Stage/Cycle + auto-routing; 4 кластери A/B/C/D) — `00_04 §5`, `00_05 §6`.
- [ ] 👤 перший betting cycle після UNI.1/UNI.14

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **P2** · 👤 · 🟢 · → `00_05 §5`
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

#### OPS.10 — Supply-chain CI hardening residuals (long tail; CI ~90% done)
- **P3** · 🤖+👤 · 🟢 · → `00_05`
- **Стан:** Машинна частина зацементована — SHA-pin усіх Actions + базовий Docker-образ digest-pinned (Dependabot `docker`-ecosystem) + top-level **token-permissions** least-privilege (job-рівневий write-elevation; critical `workflow_run`/`pull_request_target` untrusted-checkout прибрано → `gh api commits`) + **actionlint**-гейт (`workflow_lint`) + `harden-runner` (egress-audit) + `Sec · Scorecard` (Node-24-pined); GitHub-side звірено (secret-scanning + push-protection + CodeQL ON; стале «вимкнено/404» виправлено). Scorecard-findings оброблено: token/checkout/pin — fixed-in-code; solo-структурні (CodeReview/SAST/Fuzzing) + internal-stage false-positive — dismissed-with-reason. Політика+стан → [`00_05 §2.7`](00_05_GitHub_Projects_and_IaC_Automation); інвентар workflow → [`06_07 §1`](06_07_CICD_and_Runbook_Index). **Signed releases (2026-06-25):** GHCR-образ криптографічно підписаний Sigstore-keyless SLSA build-provenance (`actions/attest-build-provenance` у `mirror-ghcr.yml`, OIDC→Fulcio/Rekor, ефемерний ключ не на registry) → closes OpenSSF `signed_releases`; verify-процес у `SECURITY.md`. **Security assurance case (2026-06-25):** структурований `SECURITY_ASSURANCE_CASE.md` (security-claims · threat model · 6 trust-boundaries A–F + guard кожної · Saltzer-Schroeder secure-design · OWASP Top 10 (2021) countermeasure-map · чесні residuals: ECB-no-MIC/L0-custodial/RDP-L2/MFA-incomplete-S6.21/pre-mainnet) → closes OpenSSF `assurance_case`; synthesis-дім реферить canon, не дублює. Лишилися 👤-налаштування:
- [ ] 👤 require signed commits (`required_signatures`) — runbook [`06_07 §2`](06_07_CICD_and_Runbook_Index)
- [x] ✅ **OpenSSF Best Practices — `silver` earned 2026-06-25** (проєкт [13358](https://www.bestpractices.dev/projects/13358); динамічна плашка в README + `00_00` авто-рендерить рівень — markdown без змін). Passing + silver критерії всі Met (FLOSS · CI · тести · `SECURITY.md` · SAST/DAST ASan+UBSan · `crypto_*` · `input_validation` · `hardening` · `signed_releases` Sigstore build-provenance · `assurance_case` → `SECURITY_ASSURANCE_CASE.md`). Закриває Scorecard `CIIBestPractices` (→ silver-level). **Gold не цілимо** (вимагає bus-factor ≥2 maintainers — solo-структурний бар'єр, як `CodeReview`/`SAST`-Scorecard)
- [ ] 👤 (опц.) secret-scanning validity-checks + non-provider toggles · `SCORECARD_TOKEN` ([`06_04 §1.3`](06_04_Secrets_Checklist))

## §01a · Anchor — Geometry & Metallurgy

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

> 🧭 **Hardware-стек (§01a→§02b) — одна фіз-система, 4 під-секції.** Конституція [`00_00`](00_00_SSOT_Index) (Системна Карта, 8 рівнів): **The Root** — анкер (§01a) + EBFC (§01b) → **The Capsule** — вузол Soldier (§02a) → **The Veins** — Брама Queen (§02b); енергія й дані течуть угору. Поділ — для навігації; синергію тримає анкерний DAG нижче + ID-крос-рефи між секціями.

> 🧭 **Анкерний кущ — synergy map (dependency-DAG).** Анкер — система зшитих залежностями деталей; закриваємо **пакетами**, не поштучно. Обидві machine-осі зведені, критичний шлях перейшов на фізику:
>
> **✅ Machine-фундамент ЗАКРИТО** (CAD + in-silico, self-owned):
> - **Дим-фриз** — геометрія frozen (вал Ø11 · PEEK стінка 2 мм · рана Ø15 · Zone 2 50 мм · фланець Ø25 · Z-stack spacer+bayonet · O-ring 15–30 %), data-grounded Lamé+CODIT+3-spring, анти-дрейф guard `00_06 §3` (HW.33 · HW.8 · HW.26).
> - **PicoGK CAD-родина** (`tools/cad` — **лінчпін**, живить кожну стадію): 6/6 генераторів (coin → anode-v2 → barbs → Деталь 3 → Деталь 4 → Zone-2 втулка) + 2 інтеграційні assembly (capsule-end · осьовий стек) + drawing-program (HW.1).
> - **In-silico прокси фіз-тестів:** двофазна connectivity ↔ Архімед/µCT/AM-island (ARCH.25) · thermal-stress + press-fit Lamé ↔ aging (HW.3.IS) · Z-stack RSS ↔ tolerance QA (HW.8.7).
>
> **→ Фізичний критичний шлях — ціль TRL 3→4 = Ti-coin in-vitro** (founder 2026-06-21; гроші є → реальний блок не фінанси, а лаб-канал):
> - **[★ КРИТИЧНИЙ ШЛЯХ до TRL 4] Ti-coin:** HW.24 Stage 2 (**6-alloy bake-off** Ø16: 4V/7Nb/CP-Ti/β-Ti/Ta/Ti-15Zr → EAAE → Gen 2.0 стек → CV/EIS у соку) + HW.5 (хімія) + V-release ICP-MS (HW.3). **Обходить** гіроїд/PEEK/press-fit/mate. Канал = **гібрид commercial-lab + ЧНУ** (не чекати MoU). 🤖 CAD+in-silico machine-half ✅.
> - **[∥ паралельні треки — НЕ блокують coin]:** [C] завод-пакет HW.1/HW.23/HW.27/HW.2 + coating-map `01_02 §3.6` (під майбутню DMLS-партію) · Stage 1 SLA form&fit (HW.24) · mate-reconcile HW.8.8/8.9 · HW.3 Arrhenius aging.
> - **[E] Збірка — після фіз-деталей:** HW.17 (radome) · HW.25 (PTFE-GDL) · HW.28 (shield) · HW.8 (pogo bench) · HW.6 (install) · HW.22 (steril).
>
> **🔧 Bench-reconcile перед фіз-друком** — assembly mate-audit виявив незведений Z-stack (`02_02 §4.4/§4.5`): MATE-Ø skirt-vs-inboard + Z (HW.8.8) · shank-Ø press-fit (HW.8.9), цілісно в одному заході. Геом-аудит + founder-рішення → **HW.33**.

#### HW.1 — nTop model → SLM+HIP factory (Anode Zone 1)
- **P0** · 👤 · 🟡 · → `01_01`, `01_02 §1.7`
- **Стан:** Фабрична генерація тризонного анкера НЕ розпочата (Zone 1 SLM+HIP, Zone 3 SLM/EBM, Zone 2 CNC+annealing 200–250°C; канон `01_01 §1/§5.5`, `01_02 §1.6/§1.7/§3.6`). **🏁 Code-as-CAD machine-half ЗАКРИТА** — PicoGK трек (`tools/cad/`, .NET 9, primary; nTop-ліцензія є, але робота ~нуль): повна анкер-родина (coin→anode-v2-graded→ARCH.25→barbs→Деталь3→Деталь4→Zone2-втулка→осьовий-стек; 6/6 генераторів + capsule-end/axial assembly) + engineering-drawing program (DXF/CEM-tolerances Phase 0/1, `tools/cad/docs/drawings_program.md`; Phase 2 креслення → заводський контракт). Канон-методологія [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS); геометрія-аудит + sheet→network + DMLS-floor → **HW.33**; assembly-mismatch → HW.8.8/8.9. 👤-residual: фіз-друк/HIP + factory-deliverable нижче.
- [ ] 👤 Фінальна factory-ready Zone-1 gyroid STL (65% porosity; CAD-demo ✅, геом-рішення sheet/network + DMLS-floor → HW.33)
- [ ] 👤 **Градієнт розміру пор** (`01_01 §5.5`): центр 300–500 µm → периферія 100–150 µm при сталій 65% (DMLS-floor → HW.33)
- [ ] 👤 Окреме креслення Zone 3 (∅25 frozen) — Phase 2 `draw cathode_flange` (DXF/SVG + CEM tolerances), deferred до заводського контракту
- [ ] 👤 **STL + DXF-креслення** → SLM завод (Київ/Дніпро) з вимогою HIP (`01_02 §1.7` + HW.23); БЕЗ STEP (AM-бюро друкують зі STL; DXF = GD&T/приймання)
- [ ] 👤 **Build orientation spec** (`01_02 §1.6`): BD ∥ довгій осі, кут 0°±5°, externally only support
- [ ] 👤 **Карта обмежень покриттів** (`01_02 §3.6`): ZnO-Ta НЕ на гіроїдні стінки Zone 1
- [ ] 👤 SEM criteria для приймання партії
- [ ] 👤 µCT-сканування верифікації градієнту пор (центр 300–500 → периферія 100–150 µm @ 65±2%)

#### HW.23 — HIP postprocess specification for SLM anode
- **P0** · 👤 · ⚪ · → `01_02 §1.7`
- **Стан:** Не розпочато — HIP-постпроцес SLM-анода (920°C±20 / 100–150 МПа Ar / 2–4 год) закриває залишкові напруження + металургійну пористість (зародки втомних тріщин на 20-річному циклі). Блокує втомну міцність, довговічність (TRL 5). Канон `01_02 §1.7`.
- [ ] 👤 Передати специфікацію HIP-постпроцесу на завод (Київ/Дніпро) разом зі специфікацією SLM
- [ ] 👤 Перевірити наявність HIP-обладнання у заводу-кандидата (часто окремий підрядник)
- [ ] 👤 SEM/EDS до та після HIP — підтвердити закриття внутрішніх мікропустот
- [ ] 👤 Втомні випробування (Wöhler) у синтетичному ксилемному соку — еквівалент 5+ років фретингу

#### HW.24 — Staged validation gate (SLA → Ti-coin → full anchor)
- **P0** · 👤 · ⚪ · → `01_01 §6.1`
- **Стан:** Не розпочато — гейт «100 DMLS-анкерів лише після Stage 1 (SLA form&fit) + Stage 2 (Ti-coin in-vitro біохімія)»; передчасна 100-партія = методологічна помилка. **Stage 2 = найближча ціль (founder 2026-06-21): фізичний TRL 3→4** (🚦 Critical Path) — критичний шлях обходить гіроїд/PEEK/збірку; канал = **гібрид commercial-lab + ЧНУ** (не чекати MoU); coin = **6-сплавний bake-off** down-select (4V/7Nb/CP-Ti/β-Ti/Ta/Ti-15Zr, HW.3/§2.5). Канон `01_01 §6.1`.
- [ ] 👤 **Stage 1 — SLA макети (5 шт):** друк прозорого фотополімеру (Form 3 або SLA-сервіс) для перевірки form & fit, ергономіки, Flush Mount step drilling, допусків press-fit «пластик-в-пластик»
- [ ] 👤 **Stage 2 — Ti-coins (~15 шт, Ø16 disc frozen — A=2 см²/грань, `01_01 §6.1`; **6-сплавний bake-off** down-select: 4V control + 7Nb + CP-Ti + β-Ti + Ta benchmark + Ti-15Zr, §2.5; 🤖 machine-half ✅ — `cem/ti_coin.<alloy>` 6 CEM + predicted release/E `tools/in_silico` 51/50 + RFQ `procurement/anchor_alloy_rfq` + acceptance-gates `01_03 §3.5`):** SLM-друк + EAAE (з обов'язковим dehydrogenation bake `01_02 §1.3 Крок 5b`) → **Gen 2.0 анодний стек** (одношаровий dgrFAD-GDH + Os polymer в genipin-chitosan-CNC матриці поверх fMWCNT, `01_03 §2.1`) + **Gen 2.0 катодний стек** (Laccase + nCoCuCeZIF nanozyme гібрид DET, `01_03 §2.2`) + **Nafion-g-PSBMA анти-resin coating** → in vitro CV/EIS у синтетичному ксилемному соку (**канал = commercial electrochem-lab на критичному шляху + біо-хаб ЧНУ паралельно**, рецептура [`08_02`](08_02_Academic_Institutions_Registry)). 30-day stability gate. Chloride tolerance test (0.25 М NaCl). UCST winter-lock тест (-10°C → +25°C цикл). 💡 **Electrode-дизайн:** замовити з «вушком» (отвір/виступ на краю) для кріплення потенціостат-кліпси без пошкодження активної площі (A_electrode = 2 см²). In-silico predictions для порівняння — `40_validate_vs_experiment.py` готовий. (`01_03 §3.7`)
- [ ] 👤 **Stage 3 — Full anchor (3–5 шт):** SLM+HIP анодних секцій, CNC PEEK-втулок, SLM/EBM катодних фланців, повний press-fit + EBFC у синтетичному соку
- [ ] 👤 **Stage 4 — Партія 100 шт:** після підтвердження Stage 3 — оптове замовлення для польових випробувань

#### HW.33 — Anchor geometry spec audit (PicoGK-gating)
- **P1** · 🤖+👤 · 🟡 · → `01_01 §5.5`, `01_04 §3.2`, `02_02 §1.3`
- **Стан:** Гео-рішення founder + дим-фриз + машинна половина зацементовані в канон: орієнтація знята (рішення (б) — гіроїд бінеперервний, [`01_01 §5.5`](01_01_Coaxial_Gyroid_Topology_and_PEEK)) · вал **Ø11** + монолітний центр-стрижень шини ([`01_01 §1.4`](01_01_Coaxial_Gyroid_Topology_and_PEEK)/HW.34) · радіальний дим-ланцюг frozen (PEEK 2 мм → рана Ø15; осьовий Zone 2 50 / фланець Ø25; unified Lamé combined SF 5.6×, [`01_01 §4.2`](01_01_Coaxial_Gyroid_Topology_and_PEEK)). PicoGK CAD-родина ✅ COMPLETE (v2 graded 3-осі + Деталь 3/4 + capsule-end/axial-stack mate-audit; ARCH.25 connectivity-стіл topology-agnostic) → sheet→network схиляння = трек, не рішення. Анкерний-кущ synergy-DAG живе у §01a intro. Залишок (нижче) — FEA · фіз-валідація · MATE-Ø.
- [ ] 🤖+👤 **FEA пружності гіроїда — sheet-vs-network E (THE відкрита вісь)**: порозність-бік знятий (PicoGK voxel 0.1 → 67.6%≈65%; груба роздільність false-high 21–28%). Відкрита жорсткість — network@65% bending n=2 → E≈13.5 ГПа (= цільова §5.2) vs sheet stretch n≈1.3 → ~22–30 ГПа ≫ деревина → stress-shield повертається; ARCH.25 + літ по 4 осях (топологія / транспорт / механіка / друк) **схиляють до network**; + анізотропія (поперечна E_R/E_T ~0.5–1.5 ≪ поздовжня E_L, анкер горизонтальний); + стала-vs-градієнт порозність відкрита (CAD `wallParam(r)` тримає обидві). 💡 β-Ti coupling (HW.24 bake-off): низько-E сплав ~80 ГПа знижує gyroid-E → може зняти гостроту (in-silico `50`). Exact E = FEA-homogenization — **self-own-кандидат** (поверх ARCH.25-стола) АБО школа Гусака. Канон [`01_01 §5.2/§5.5/§5.6`](01_01_Coaxial_Gyroid_Topology_and_PEEK)
- [ ] 👤 фіз-валідація — µCT порозність + нанотвердомір E на купоні (post-перша-партія, HW.24)
- [ ] 👤 **MATE-Ø skirt/inboard геом-вибір** (founder, з HW.17 Radome) — capsule-end/axial-stack mate-audit лишив незведеним ([`02_02 §4.4/§4.5`](02_02_Blind_Mate_Pogo_Pin_Interface))
- [ ] 🔭 Future-lever: PEEK-стінка термічно надлишкова (combined SF 5.6× ≫ 3 → 2 мм не stress-обмежені) → тонша = менша рана / нижчий DBH-поріг; bench/FEA-gated, не зараз ([`01_01 §4.2`](01_01_Coaxial_Gyroid_Topology_and_PEEK))
- [ ] 🤖 **LatticeLibrary submodule stale** (2025-07 vs ShapeKernel 2026-06) → `dependency-update` прохід (не блокер — власний SDF не залежить)

#### HW.34 — Bus conductor realization (матеріал · ізоляція каналу · нижній спай · BOM-рядок) (NEW 2026-06-21)
- **P1** · 🤖+👤 · 🟡 · → `01_01 §1.4`, `02_02 §1.2`, `01_02 §2.5`
- **Стан:** **Monolithic adopted** (founder 2026-06-21) — шина монолітна з анодом (= сплав анода, HW.24-gated), що розв'язує колишню дихотомію «анодний вал / Cu-провідник». Спека-дім → [`01_01 §1.4`](01_01_Coaxial_Gyroid_Topology_and_PEEK) (топологія/ізоляція/термінус); термо+механіка (in-silico `54`+`55`, machine-half ✅) → [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) §HW.34 — Cu-шина домінувала б розрив (анодна кишеня ~−15°C → freeze-risk), монолітна Ti термічно невидима + механічно надійна за наявності lining'а. **Резолвлено:** матеріал (monolithic, HW.24-gated) · нижній Ti↔Cu спай (усунуто) · BOM (шина = частина анодного друку). **Відкрите** ↓. Трек повного анкера TRL 4→6 — **НЕ блокує coin** (обходить PEEK/шину).
- [x] 👤 **Матеріал — ✅ monolithic** (= сплав анода, HW.24-gated; in-silico `54`: усі реальні кандидати λ≈7 ≪ Cu). Дихотомія §1.4 знята.
- [x] 👤 **Нижній спай — ✅ усунуто** монолітністю (один метал; окремого Ti↔Cu стику немає).
- [x] 🤖 **BOM — ✅ уточнено:** шина = частина анодного друку, без окремого Cu-рядка (`07_02 §1.2`).
- [ ] 🤖+👤 **Ізоляція каналу:** lining крізь катод (PEEK-лайнер / Parylene / анодований TiO₂) — реалізація; = **також бічна опора проти втоми** (in-silico `55`)
- [ ] 👤 **Друк-vs-звар:** друкований-інтегральний стрижень vs той-самий-сплав приварений Ti-дріт (benign weld — без гальваніки)
- [x] 🤖+👤 **CAD-rod + Ø-reconcile — ✅ DONE 2026-06-22** (`tools/cad`, з founder): bore→суцільне осердя (`Zone1Anode.BuildMonolithic`, voxConstruct gotcha #9 — нічний native-abort страх знятий: solid-rod безпечний, рендер чистий) + F3→`BusRodClears` (rod+2×liner ≤ канал) + **measured rod-volume гейт** (gotcha #4; pine +34.4/oak +32.1 мм³) + CEM-родина (7 anchors rod 1.0 · cathode liner 0.15 · lock.zone1 bore→0). Дими: стрижень Ø1.0 / канал Ø1.3 / lining 0.15. 55 тестів + verify зелені
- [ ] 👤 **Shank-insertion ↔ розрив (ties HW.8.9):** інсерція = термо↔press-fit важіль; справжній розрив = зазор `L_g` (placeholder F2)

#### HW.2 — Dual-scale roughness spec
- **P1** · 👤 · ⚪ · → `01_02`
- **Стан:** Не розпочато — dual-scale roughness spec (Sa 0.5–5 µm, Sv 50–500 nm) ще не передана на завод; блокує максимальний струм EBFC (TRL 5). Канон `01_02 §1.2/§1.5`.
- [ ] 👤 Підготувати factory spec з метриками
- [ ] 👤 Передати на завод
- [ ] 👤 Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **P1** · 🤖+👤 · 🟡 · → `01_02`
- **Стан:** Фіз-тест НЕ розпочато — 12-тиж Arrhenius-старіння у синтет. ксилемі (ICP-MS Ti<0.1/V<0.02 µg/cm², EIS<50%); відкритий конфлікт V-release Zone 1 (1.12 µg/cm²/yr, 56× over) — мітигація a/b/c. Блокує seed-раунд, whitepaper (TRL 5→6). Канон `01_02 §2/§2.5`. **In-silico precursor (HW.3.IS) ✅:** аналітичний Lamé + stress-relaxation → Ti↔PEEK press-fit виживає 20+ р (combined SF 5.6× / vM 4.7×, unified thick-wall Lamé 2026-06-22) + ±5% strain-cycling MD; contact-pressure bug-fixed (R_INNER→R_INTERFACE) → P_c relaxed ≤ соку → **O-ring обов'язковий**. Числа frozen → [`THERMAL_STRESS_REPORT`](protocols/anchor/fea_aging/THERMAL_STRESS_REPORT.md) + `01_01 §4.2` (guard `00_06 §3`); strain → `01_03 §2.1`. Важка FEA/Prony → Гусак (`08_01` Стаття 2, `00_02 §4a`).
- [ ] 👤 Синтез штучного ксилемного соку (потрібен ботанік)
- [ ] 👤 Запуск 12-тижневого тесту
- [ ] 👤 ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] 👤 EIS degradation < 50%
- [ ] 👤 **V-release Zone 1 — напрям (a) V-free обрано; сплав → 6-coin bake-off** (founder 2026-06-21, `01_02 §2.5`): голий Ti-6Al-4V ≈ 1.12 µg/cm²/yr V (56× over), бар'єр на Zone 1 заборонений → V-free сплави прибирають V у джерелі. Down-select = Stage 2 coin ICP-MS (4V/7Nb/CP-Ti/β-Ti/Ta/Ti-15Zr, HW.24); 🌳 Al³⁺ теж фітотоксичний у соку → zero-Al кандидати дерево-чистіші; baseline §1 = 4V до підтвердження
- [ ] 👤 HW.3.IS: **Prony-series authoritative fit** PEEK 450G (Maxwell-Wiechert, measured creep) → Гусак (`08_01` Стаття 2) — замінює interim literature-2-term; двері відкриті
- [ ] 👤🤖 HW.3.IS: **barb-tip stress-concentration FEA** → Гусак (mesh-FEA ANSYS, `00_02 §4a`); self-own якщо Гусак мовчить (light analytical bound, Lamé вже є) — DEFERRED
- [ ] 🤖 HW.3.IS: **MD ion-permeation Ti²⁺/V³⁺ через PEEK** (класична MD) — «корозія не отруїть ферменти 20р»; НЕ DFT (лише single-jump NEB) — DEFERRED (~2-3 тиж GPU milestone)
- [ ] 🤖 HW.3.IS: (nice-to-have) **unified thick-wall Lamé** — interference-hoop (51) + thermal-mismatch (50) в ОДНУ модель; комбінований @ −30°C+max-fit може впасти ~1.4× → `THERMAL_STRESS_REPORT.md` Remaining Tasks

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

#### ARCH.25 — Gyroid geometric validation scripts (per-slice / topology / BFS connectivity)
- **P2** · 🤖 · 🟢 · → `01_02 §6`, `08_02 §1B`
- **Стан:** Машинну половину закрито self-owned (не чекаючи Порубльова/Онищенка) — двофазний топологічний аудит гіроїда (`tools/cad/Connectivity.cs`, pure-managed display-less xUnit): один flood-fill = обчислювальний прокси чотирьох лаб-тестів (open-pore/percolation/solid-island/closed-pore) + adaptive-resolution застереження + робоче вікно `wallParam` — повний design-justification у каноні [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS). Topology measured, not assumed. Партнерська CFD/польова нога pending — [`08_02 §1B`](08_02_Academic_Institutions_Registry) (Порубльов).
- [ ] 🔗 C++/CFD topological-integrity mesh + Akash GPU (ARCH.30, Онищенко) — self-own за потреби, партнер pending
- [ ] 🤖 deferred (nice-to-have): Euler-χ крос-чек · tortuosity (random-walk на percolated cluster) · voxel-cross-check на as-printed grid (не лише SDF-intent)

#### HW.4 — Self-healing coating (NEW: zone-restricted)
- **P2** · 👤 · ⚪ · → `01_02 §3/§3.6`
- **Стан:** Не розпочато — 8-HQ self-healing мікрокапсули не синтезовані; наносяться **лише на неактивні поверхні** (Zone 3 сорочка, торці PEEK) — НЕ на Zone 1 гіроїд / катодну каталітичну грань (блокує DET). Блокує 20+ річні longevity-claims (TRL 6). Канон `01_02 §3/§3.6`.
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer — ТІЛЬКИ на дозволених зонах
- [ ] 👤 Тест: 10× вищий Rct
- [ ] 👤 **Thiol-Michael interphase** (`01_02` §1a.1): тест адгезії self-healing шару при ростовому навантаженні, порівняння з простою APTES-силанізацією — додано в `01_02`

#### HW.26 — PEEK Cold-Flow Creep: Mechanical Lock (NEW 2026-05-16)
- **P2** · 👤 · 🟡 · → `01_01 §4.3`
- **Стан:** 🤖 PicoGK-геометрія SHIPPED (`MechanicalLock.cs` — asymmetric ratchet barbs + DIN-471 groove на hollow shank); 👤 bench-residual (press-fit/FEA/закупка). Mechanical lock проти PEEK cold-flow creep — три комплементарні фічі (barbs осьове утримання + DIN-471 retaining ring + hex anti-rotation; числа/геометрія/creep-таблиця — канон [`01_01 §4.3`](01_01_Coaxial_Gyroid_Topology_and_PEEK)). Барби = утримання, **НЕ ущільнення** (герметизує O-ring, `01_01 §4.2`). Без замка contact pressure падає −60% за 10р (§4.3) → втрата O-ring seal / вирив Zone 3. **Design-альтернатива (не зроблено):** helical barb = pull-out + torque-out в одній фічі, замінила б hex (§4.3 C). Блокує 20+ річну надійність.
- [ ] 👤 Update CNC-чертежі: retaining ring grooves на anchor end Zone 1 + flange end Zone 3
- [ ] 👤 Закупка DIN 471 **external** retaining rings Ti grade 2 (або 316SS) під обраний Ø shank (DIN 471 = зовнішнє, на вал; внутрішнє = DIN 472)
- [ ] 👤 Update press-fit процедуру: temp 150°C (>T_g PEEK 143°C Victrex 450G) + контрольована сила 800–1200 N
- [ ] 👤 **FEA-валідація** ANSYS LS-DYNA visco-elastic PEEK Prony — 10y creep, residual pull-out > 200 N
- [ ] 👤 Stage 1 SLA-mock (HW.24): barb-detail у фотополімерну збірку для перевірки клацання
- [ ] 👤 **Belleville/disc-spring preload** (deferred chem-note triage → tracked тут): тримає clamp force анкер↔ксилема проти 20-річного Ti creep + thermal cycle — комплементарний до barbs+DIN-471; ≠ pogo contact-spring / ≠ capsule Z-stack [`02_02 §3.5`](02_02_Blind_Mate_Pogo_Pin_Interface)

#### HW.28 — Anti-Overgrowth Shield для Zone 3 (NEW 2026-05-16)
- **P2** · 👤 · 🟡 · → `01_04 §5.5`
- **Стан:** Захист **(A) виступ-дзвін ✅ machine** (Деталь 4 `Radome.cs`, bell-rise verify-gate; HW.17); (B) coating + (C) maintenance — 👤 pending. Anti-overgrowth shield тримає Zone 3 катод відкритим атмосфері: без нього за 3–5р кора накриває PTFE-GDL → O₂-дифузія стоп → EBFC мертва. Три комплементарні захисти (A виступ-дзвін PEEK Radome + B super-hydrophobic coating / Cu-сплав + C forester maintenance; числа/матеріали/Cu-фітотокс-caveat — канон [`01_04 §5.5`](01_04_CODIT_and_Xylemointegration)). OPEX → `07_02 §6`.
- [ ] 👤 Закупка/тест super-hydrophobic coating (Fluoropel PFC-1601V або аналог; UV-деградація → Cu-сплав альтернатива, §5.5 B)
- [ ] 👤 Field protocol для forester visit: зачистка приростаючої тканини без traumatic surgery
- [ ] 👤 12-місячний польовий тест на тестовому дереві (Черкаський бір)
- [ ] 👤 Update `07_02 §6` OPEX: forester visit раз на 5–7 років (Черкаський бір)

## §01b · EBFC — Chemistry & Bio-electrochemistry

> EBFC Gen 2.0 — біоелектрохімія/хімія стека (анод dgrFAD-GDH+Os, катод Laccase/ZIF, цвітеріонна мембрана) + in-silico Zero-Lab. Канон [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell). The Root-рівень стека (огляд — §01a).

#### HW.5 — Enzyme lifespan + Gen 2.0 chemistry stack
- **P1** · 👤 · 🟡 · → `01_03 §1–3`
- **Стан:** In-progress — ціль: довгострокова стабільність біоелектрохімічного стеку у кислому ксилемі (pH 4.5–5.5) + повна імунологічна невидимість для CODIT-каскаду, термін **20–25 років**. Архітектура = Gen 2.0 (одношарова FAD-GDH; повний стек анод/матриця/катод/мембрана — канон `01_03 §1–3`; Gen 1.0 GOx+CAT+GA+PEG відкинуто як нежиттєздатна). In-silico Zero-Lab (TRL 3) ✅; фізичний Ti-coin in-vitro (TRL 4) pending.
- [ ] 👤 **Gen 2.0 anode (priority):** одношаровий dgrFAD-GDH+Os electroactive layer + genipin-chitosan-CNC матриця — `01_03` §2.1
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
> 31 triaged + verified 2026-06-06; **5 pruned** (refuted/dup/relocated → git). **+5 cathode/method notes 2026-06-06 → CHEM.32-36** (verified vs canon first: Co→Ru low-λ + cMOF already in `01_03 §3.2`; pH-protonation already in all MD scripts — batch ↓). **Full verdicts in the SSOT canon (docs/):** anode → `01_03 §3.1` · matrix → `01_03 §3.3` · cathode levers → `01_03 §3.2` · in-silico methods → `PIPELINE_STATUS` Future · aggregation → `L1 §2` · computed → `SUMMARY`/`L3`. Thin pointers below. ⚠️ = weak.

**P0 — in-pipeline (paper computes, ✅ canonized):**
- [x] CHEM.29 — Ru-λ 0.78 eV (cathode-fix) → [`SUMMARY`](protocols/ebfc/in_silico/SUMMARY.md) §Cathode
- [x] CHEM.23 — realistic mediator SO₂CF₃/CF₃ (① reframed) → `SUMMARY` §Mediator
- [x] CHEM.10 — Lys→Arg genipin-shield (LYS109/262) → [`L1`](protocols/ebfc/in_silico/L1_protein_architecture.md) §2
- [x] CHEM.20/26 — bis-Im speciation (plain bpy, cascade Δ −0.609, aqua>bis-Im>chloro) → **superseded by dimethyl 34/34b** (chloro-bracket; on dimethyl B3LYP bis-Im>aqua, ωB97X aqua>bis-Im) → `SUMMARY` §Cluster-Continuum
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
- [ ] CHEM.18 — cryoprotectant T-corr (firmware low-T compensation for the matrix cryoprotectant's effect on EBFC output; **gated on CHEM.25**) → Gen 2.1+ firmware, **NOT yet homed** (no 03_xx note exists)
- [ ] CHEM.27 — Belleville/disc-spring anchor preload (holds anchor–xylem clamp force vs 20-yr Ti creep + thermal cycle; ≠ the [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface.md) pogo-pin *contact* spring) → hardware reliability; **homed → HW.26** (anchor mechanical retention/preload; disc-spring complements barbs+DIN-471 vs 20-yr Ti creep — окремо від capsule Z-stack `02_02 §3.5`)
- [ ] CHEM.19 — biological gasket / wound bio-seal (manages the anchor–wound interface vs infection + resin flooding) → domain home [`01_04`](01_04_CODIT_and_Xylemointegration.md) (resinosis failure-mode); bio-seal *solution* **NOT yet homed**

##### 🔬 In-silico pipeline — open computes (script audit 2026-06-06; detail → `PIPELINE_STATUS`)
> All ~37 `tools/in_silico/scripts/` audited — almost all ✅ (cached). Open work captured here so we never re-audit; closed/superseded = 21 · 21c · 29 (honest limitations-points, not work).
- [x] ✅ 🤖 **Re-run chain DONE:** 24b FO-DFT → 25 → ③ k_DET rigor: borderline **robust to coupling method** (t_ij 0.00546 ~4× crude + 0.18 eV site-gap; old ×10⁵ excluded) → `SUMMARY` §Cathode / `PIPELINE` 24b
- [x] ✅ 🤖 **②/tunnelling robustness DONE:** 34b ωB97X ②-speciation (plain: aqua>bis-Im reproduced; B4 dimethyl: bracket robust, internal aqua↔bis-Im functional-sensitive) → `SUMMARY` §Cluster-Continuum · 28b dynamic-tunnelling ensemble (β·d 2.02±0.13; image_molecules PBC)
- [ ] ✨ 🤖 **Refinements (optional, per-script additional analysis):** outer-sphere λ_o ✅ (29c → total anode λ 0.76–0.86 eV phys-end, confirms lit 0.7–0.8) · aqua/bis-Im × substituents + ωB97X for the series (21e) · real ΔG in k_ET (25 — FO-DFT scenario now uses the 0.18 eV site-gap; lit/computed-λ rows still ΔG=0) · Cu/Ce λ refinement (35; B3LYP over-estimates Co spin-crossover) · Os-complex MD ensemble (27, not just FAD) · full hydration shell + COSMO-RS/MACE probe (34) · k_cat sensitivity (30/30b) · ③-borderline R_ct in EIS ✅ (31b → band ~0.002–230 Ω). ⚠️ **λ_o (29c) is radius/ε-dominated · EIS-③ R_ct (31b) is Γ×k_DET-dominated (×10⁵ band) → both COMPUTED 2026-06-06 + confirmed INDICATIVE, not clean computes** (kinetic competition k_DET~turnover, NOT a fixed R_ct; caches `outer_sphere_lambda.json` / `cathode_det_rct.json`)
- [ ] 🧹 🤖 **Method-hygiene (founder pipeline batch 2026-06-06, verified):** (B2) pH-protonation **already done** — every MD script (10/11/12/14/15) calls `addMissingHydrogens(pH=4.5)`, 14 per-species 4.2-5.8 (note's pH-7-default premise is wrong). (B1) FAD AM1-BCC on AF3 geom **mostly OK** — antechamber/sqm geom-opts at AM1 before BCC (raw AF3 not used verbatim); optional RDKit MMFF pre-opt = minor robustness, low. (B3) DRY: `md_utils.prepare_protein` exists but 5 scripts duplicate it inline (byte-identical → safe dedup) + no shared PBC trajectory loader (28b `image_molecules` is local) → low-risk refactor (⚠️ `image_molecules` for multi-mol graph, `make_molecules_whole` for single-protein RMSD — not blanket). (B4) Apple-OpenCL fast-math precision regression test → nice-to-have for publication-grade 100+ ns (→ CUDA), not needed for current RMSD-stability claims
- [ ] 🏔️ 🔗 **Capstones (Мінаєв):** ④ protein QM-cluster E° (extend 32) · CDFT coupling (> 24b, needs PyCDFT) · QM/MM explicit-water cascade
- [ ] ⏸️ **Deferred → Стаття 2/3 / on-data:** 11 (20–50 ns MD, reviewer-grade equilibration) · 13 (D_eff model; L4 already uses lit 2e-6) · 16 (PE-drift 1%, bigger box) · 40 re-run vs Ti-coin CV/EIS when in-vitro data lands (40 already has a docstring — the audit's "missing" was a grep-filter artifact)

#### HW.21 — Hybrid energy R&D: TEG + Anchor stacking (post-TRL 6)
- **P3** · 👤 · 🌿 · → `01_03 §6`
- **Стан:** Far-horizon (post-TRL 6) — два доповнювальні джерела проти зимового енергодефіциту: (a) TEG Bi₂Te₃ ~50–200 µW зимою (ΔT 15–25 K), (b) stacking 3–4 анкерів (V_OC ×3–4, для арктичних/кластерних). Одно-анкерна Gen 2.0 архітектура вже задовольняє BQ25570 cold-start 330 мВ → TRL 7+. NB: SolarBotanic «nano-leaves» не інтегруємо без peer-reviewed per-node даних. Канон `01_03 §6`.
- [ ] 👤 TEG: вибір модуля Bi₂Te₃ (4×4 см), стендовий тест ΔT-V кривої на тестовому стовбурі
- [ ] 👤 TEG: інтеграція з BQ25570 multi-input (можливість одночасного MPPT для EBFC + TEG)
- [ ] 👤 Stacking: 3-анкерна тестова конфігурація на одному дереві з PEEK-ізоляцією (Zone 2)
- [ ] 👤 Stacking: оцінка впливу на провіженінг (групова реєстрація DID) та Lorenz-аналітику (декомпозиція V_OC)
- [ ] 🔗 Залежить від HW.13 (P-V крива EBFC) для правильного бюджетування доповнення

## §02a · Node — Capsule & Electronics

> Soldier-капсула: PCB/живлення/сенсори/pogo/conformal-coating — канон [`02_01`](02_01_Hardware_Architecture_and_BOM)/[`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface)/[`02_03`](02_03_BQ25570_MPPT_Nano_Power). The Capsule-рівень стека (огляд — §01a).

#### HW.32 — BME280 environmental sensing + VPD confounder [ADR `02_01 §3.4`]
- **P1** · 👤 · 🟢 · → `02_01 §3.4`, `07_02 §1.3`
- **Стан:** BME280 (t°/RH/тиск, I2C за TPS22860) приземлено host-side — docs + `03_01` SENSE + TelemetryLog cols (structure.sql) + firmware pure-модуль `firmware/common/bme280.h` (datasheet Bosch §8.2 компенсація `Bme280_Compensate_T/P/H` + VPD FAO-56 Tetens `Bme280_Vpd_Index`, host-golden `test_bme280.c`) + VPD-gate/sap-term у backend (inert, ENV-calibration-gated). Wire: VPD = CCM wire-rev2 **byte 19 `vpd_index`** ([`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)). DCI-guard: VPD НЕ в Lorenz-Z. Канон `02_01 §3.4` (формула/шкала/bench-чеклист) · slashing-роль `05_05 §6/§7` · клімат-оракул `07_01` · калібрування ваг `05_05 §8`.
- [ ] 👤 bench: I2C bring-up `bme280_forced_read`, SENSE call-site вшивається з CCM-флипом, gate-timing, VPD-калібрування + PTFE-мембрана механіка (`02_02`)

#### HW.7 — BQ25570 resistors verification
- **P1** · 👤 · ⚪ · → `02_03`
- **Стан:** Не розпочато — CJMCU-2557 може мати Li-Po дефолт (VBAT_OV 4.2V замість 5.5V для supercap) → перевірити/замінити 8 SMD-резисторів. Блокує фіналізацію схеми + PCBA. Канон `02_03 §4/§5` (calc + табл.) / §11 (checklist).
- [ ] 👤 Виміряти 8 резисторів мультиметром
- [ ] 👤 Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] 👤 Замінити SMD резистори якщо мисматч
- [ ] 👤 Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (sub-blockers 8.1–8.9)
- **P1** · 👤 · 🟡 · → `02_02`
- **Стан:** Pogo-інтерфейс — фіналізація; **machine-вирішено:** bayonet-фіксація ✅ (детермінована Z, різьба=FAIL — `02_02 §4.3`) + Z-stack ✅ обчислено (3-spring RSS, min mitigation spacer 0.1мм + bayonet hard-stop тримає всі вікна — `02_02 §3.5`; freeze розблокував Radome/B2B/PCBA). **Spec-freeze (founder 2026-07-03):** напилення Au 0.76µm ✅ · spring ~98–100г ✅ · O-ring EPDM 70A/CS1.78/20% ✅ · **IP68 ✅** (`02_02 §3.2/§3.3`) — лишається фіз-вимір цих на bench (Rc, spring force, IP-тест) + Hard-Gold central-pad мапа заводу (8.2, Ti↔Au гальванопара `02_02 §1.2`), соосність, + 2 MATE-Ø нитки (lug/Z 8.8, shank-Ø 8.9 — mate-audit `02_02 §4.4/§4.5`). Канон `02_02`.
- [ ] 👤 HW.8.1: напилення pin ✅ spec Hard Gold Au 0.76 µm over Ni (founder 07-03) — лишається P/N при HW.9 BOM + Rc-вимір bench
- [ ] 👤 **HW.8.2: Hard Gold ENIG на центральній площадці** (торець шини Zone 1, ø 4–5 мм) — обов'язково (інакше Ti↔Au гальванопара → Rc drift → cold-start fail); передати specмапу selective gold-plating заводу. `02_02 §1.2`
- [ ] 👤 HW.8.3: сила пружини ✅ spec ~98–100 г/пін @ повний хід, Travel ≥ 1.5 мм (founder 07-03) — лишається фіз-вимір spring force + Rc bench
- [ ] 👤 HW.8.4: bayonet CAD + SLA-прототип (механізм фіксації ✅ затверджено → `02_02 §4.3`)
- [ ] 👤 HW.8.5: O-ring ✅ spec EPDM 70 Shore A, CS 1.78 мм, 20% compression + **IP68 затверджено** (founder 07-03, `02_02 §3.2/§3.3`) — лишається фіз IP-верифікація bench
- [ ] 👤 HW.8.6: Допуски соосності (XY) → Lead-in chamfer
- [ ] 👤 HW.8.7: фіз-bench QA-вимір D3+D4 + robot spacer-selection (Z-stack ✅ обчислено → `02_02 §3.5`)
- [ ] 👤 **HW.8.8: lug/Z mate reconcile** — bayonet Деталь3↔4 НЕ зведена (lug-Z 15.5 ↔ lock-groove-Z 3.5 → bayonet-Z 6.42 + RF 8<12мм); bench: lug_protrusion/lock_groove_z/lug_z цілісно + radial skirt (→ HW.17/HW.33) + HFSS Ø30. `02_02 §4.4`
- [ ] 👤 **HW.8.9: press-fit shank-Ø reconcile** — Zone 2↔3 НЕ press-fit (shank Ø9 placeholder у bore Ø11 = 1мм зазор, ~50× промах H7/s6); bench: shank-Ø під bore Ø11 H7/s6 — разом із 8.8. `02_02 §4.5`

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

#### HW.17 — PEEK radome prototype (Деталь 4)
- **P1** · 👤 · 🟡 · → `02_01 §5.2`, `01_04 §5.5`
- **Стан:** Осьова вісь розблокована (freeze 2026-06-20) — PEEK Radome (Деталь 4) **Ø25 на байонеті** Zone 3 катод-фланця (НЕ анод, НЕ різьба — §3.5 Z-stack): радіопрозорий купол + O-ring EPDM → IP68; керамічна SMD-антена з Z-clearance + overhang (`02_01 §5.2/§5.3`); інтегрований anti-overgrowth shield (`01_04 §5.5`, residual → HW.28). **PicoGK машинна половина ✅ DONE** (`CathodeFlange.cs` + `Radome.cs` + capsule-end `Assembly.cs`; числа/верифи — `tools/cad` + HW.1). **MATE-Ø кількісно виміряно** (`02_02 §4.4`): radial −2.0 / bayonet-Z 6.42 / RF 8<12 мм; skirt Ø30 ↔ inboard Ø25 Δ-кандидати — bench-вибір. Тип кріплення байонет ✅ (HW.8.4). Канон `02_01 §5.2` / `01_04 §5.5` / `02_02 §4.4`.
- [ ] 👤 KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] 👤 Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] 👤 **HFSS-симуляція** Ti-фланець + PEEK-радом + чіп-антена (`02_01 §5.3` revised; VNA → Гончаров E.53) — VSWR < 1.8, gain ≥ −2 dBi
- [ ] 👤 Замовити PEEK прототип (radome + shield-конус ≥3мм/R≥5, `01_04 §5.5`)
- [ ] 👤 Верифікувати RF performance (VSWR/КСВ) з антеною під радомом + Ti-фланцем (overhang тест)
- [ ] 👤 MATE-Ø skirt/inboard вибір (radial) + Z-reconcile (lock-groove-Z↔lug-Z) — bench разом (HW.8.8)

#### HW.29 — Board-to-Board Connector pair: Power Deck ↔ RF Deck (NEW 2026-05-16)
- **P1** · 👤 · ⚪ · → `02_01 §3.1`, `§5.3`
- **Стан:** ✅ **Конектор обрано (founder 2026-07-03): Samtec FTSH header + CLT socket** (1.27мм pitch SMD, 8–10мм stack, ~$0.85/пара) — без нього RF Deck не отримує 3V3 (Pogo зайняті VIN_DC+GND). Rigid-flex (~+$1.50) **deferred**: механічна точка відмови B2B прийнятна при TRL-3, перегляд лише якщо польова надійність вимагатиме. Лишається KiCad placement (HW.9) + фіз-вимір. Канон `02_01 §5.3` (+ BOM поз.12 §3.1).
- [ ] 👤 KiCad: place B2B footprints на обидві деки + перевірка signal integrity для 6-8 сигналів (3V3, GND, VSTOR_sense, EBFC_sense, piezo_EXTI, BQ25570 EN)
- [ ] 👤 Виміряти insertion loss + height variation на 5 зразках першої партії
- [ ] 👤 Pre-fabrication: B2B stack height (±0.15 мм) уже врахований у HW.8.7 Z-stack RSS ✅; виміряти variation на 5 зразках 1-ї партії для підтвердження ±0.15

#### HW.35 — Гілка-А навчальний breadboard-стенд (legacy 44 мВ LTC3108) (NEW 2026-07-03)
- **P2** · 👤 · 🟡 · → [`02_04`](02_04_Legacy_Breadboard_Appendix)
- **Стан:** BOM вивірений повний (4 острови: AA-дільник 44 мВ → LTC3108 + LPR6235 1:100 → CJMCU-2557 → storage cap → LoRa-E5 mini), закупівля і збірка НЕ зроблені. Продакшн-незалежний (LTC3108-каскад викинутий post-pivot — [`02_03 §1`](02_03_BQ25570_MPPT_Nano_Power)); цінність = навчальний bring-up harvester-ланцюга + жива платформа для HW.7-перевірки резисторів. Канон стенда [`02_04`](02_04_Legacy_Breadboard_Appendix).
- [ ] 👤 замовити BOM (storage-кап: 1000µF/25V алюміній + 1000µF/6.3V полімер — обидва варіанти)
- [ ] 👤 зібрати інкрементально по островах 1→4 (мультиметр на кожному; антена 868 МГц ПЕРЕД живленням Острова 4)
- [ ] 👤 зняти bring-up відео стенда для грантів (ex-E.3)

#### HW.11 — Conformal Coating (Parylene C; Sylgard rejected — TinyML acoustic)
- **P2** · 👤 · 🟡 · → `02_01`, `02_02 §3.4`
- **Стан:** Рішення зафіксовано — **Parylene C 10 µm (CVD)** для серії + acrylic Humiseal 1A33 для прототипів; повний Sylgard-184 potting відхилено (акустичний демпфер 15–25 dB @ 16 kHz глушить TinyML-п'єзо). Acoustically transparent + IP68 з O-ring (HW.8.5 ✅ 07-03). Лишається вибір coating + verify. Канон `02_02 §3.4` (+ BOM `02_01 §3`).
- [ ] 👤 Контакт з CVD-сервісом Parylene-deposition (Київ / Львів — пошукати спеціалізовані PCB-house)
- [ ] 👤 Верифікувати п'єзо-attenuation: тест 16 kHz tone з/без coating на калібрувальному стенді
- [ ] 👤 Верифікувати з кварцовим резонатором при -20°C / +60°C (Parylene Shore D ~50, м'якший за air-gap воду)

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **P2** · 🤖+👤 · 🟢 · → `02_03 §12.4.2`
- **Стан:** Концепт верифіковано (DCI-safe) — добова VOC EBFC розрізняє «дерево хворіє» vs «конденсатор деградує» (обидва ростять delta_t); корекція живе на **slashing-шарі** (`ContractHealthCheckService`), НЕ в Z-математиці (інакше server-Z≠device-Z → fraud-flag щопакета). Реалізація gated на firmware VOC-вимір + delivery-контракт. TRL 8+. Канон `02_03 §12.4.2`.
- [ ] 🤖 Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] 👤 Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- [ ] 🤖 Backend (gated): `voc_mv` колонка + VOC-корекція у `ContractHealthCheckService` (виключити hardware-confounded дерева зі slashing-підрахунку), **НЕ в `Attractor`**. Чекає firmware VOC-вимір + delivery-контракт.

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **P2** · 👤 · 🟢 · → `02_03 §6`
- **Стан:** Рішення зафіксовано — MLCC замість тантала (виток 1–10µA вбивав би sleep-бюджет 1.5µA); фінал = **25V X7R 1210** (НЕ 6.3V X5R: DC bias −75…85% при 6.3V знищує ємність), 47µF для +14 dBm Сценарію C (BOM поз.9 `02_01`). Канон `02_03 §6` (§6.1 derating).
- [ ] 👤 внести фінальний part у KiCad BOM (HW.9)

#### HW.30 — SMD Piezo + Acoustic Pad (Zero-Touch Wake) (NEW 2026-05-16)
- **P2** · 👤 · ⚪ · → `02_01 §6`
- **Стан:** Не розпочато — SMD-piezo (живі кандидати `02_01 §6`: **Mallory AST1240/AST1109** 4.0–4.1 кГц активні + **Murata PKMCS0909E4000-R1** 4.0 кГц ⚠️LTB-2027; мертві 7BB-obsolete-THT-6кГц + TDK-SMD-неіснує викинуто канон-фіксом 07-03; вибір = bench receive-V, фаворит Mallory-AST) на нижній стороні Power Deck + Bergquist Sil-Pad 1500ST acoustic coupling до Ti Zone 3 → сигнал через B2B (HW.29) → BAT54S → EXTI; усе SMD (стара клеєна ∅27мм через-отв. з дротами порушувала Zero-Touch §5.2). **🔑 Sil-Pad = 3-тя пружина Z-stack** (∥ pogo на спільному Power↔Zone3 gap, 30-40% compression + 20-р creep, HW.8.7 / `02_02 §3.5`) — compression-вікно freeze разом із Z-stack. Канон `02_01 §6` (+ BOM поз.5 §3.1).
- [ ] 👤 Вибрати SMD-piezo з 3 кандидатів (Murata/TDK/Mallory), компроміс sensitivity vs пасивний voltage swing на резонансі ~4 кГц
- [ ] 👤 Acoustic coupling test: SMD-piezo + Sil-Pad + Ti-coin → подаючи 16 кГц tone через анкер → виміряти voltage spike на p'єзо vs стара ∅27 мм через-отв. архітектура
- [ ] 👤 Verify EXTI wake-on-vibration latency vs стара через-отв. baseline (target < 5 мс)
- [ ] 👤 **Interrupt-storm mitigation** (нот.5): амплітудний поріг — hardware comparator/RC АБО software fast-amplitude gate, щоб вітер/дощ/гойдання гілок НЕ будили повний аудіо-цикл → drain-захист 0.47 F supercap (поточно лише `BAT54S` voltage-clamp, без порогу; `03_03 §1.2`)
- [ ] 👤 Lifecycle test: Sil-Pad creep під 30-40% compression × 20 років (Arrhenius accelerated)

## §02b · Gateway — Queen Hardware

> Брама (Queen): стільниковий/Starlink uplink, BMS, термал IP67, антена — канон [`02_05`](02_05_Queen_Hardware_and_Starlink). The Veins-рівень стека (огляд — §01a).

#### HW.31 — Queen Antenna Split (868 LoRa tuned ≠ dual-band)
- **P0** · 👤 · 🟢 · → `02_05 §7`
- **Стан:** Рознесено в каноні — поз.11 wideband LTE-M/NB-IoT (700–2700 МГц, Kyivstar B1/B3/B7/B8/B20, опц. LTE+GNSS) · поз.12 LoRa 868 **tuned** 5 dBi fiberglass omni (OD8-868/ALL.4101); окремі RF-порти SX1262 vs SIM7070G, dual-band SMA відхилено (VSWR>2.5 @868 → −3-5 дБ EIRP). Канон `02_05 §7`.
- [ ] 👤 freeze поз.11/12 у BOM Королеви при 02_05 BOM freeze

#### HW.15 — BMS + VBAT decoupling для SIM7070G
- **P1** · 👤 · 🟡 · → `02_05 §Пікові струми SIM7070G`, `§2.2.1`
- **Стан:** Module-level fix зафіксовано — 5-cap VBAT tank bank проти 2A-burst brownout (просадка <20mV, margin >35×; BOM поз.17–20). PSM/eDRX ✅ shipped (init-тракт Queen `main.c` [HW.10]; дім AT-граматики — [`03_02 §4`](03_02_Queen_Gateway_Firmware); live-звірка таймінгів — RUNBOOK §5.2, разом з FW.3). Лишається system-level: BMS/MPPT моделі в BOM + bench-звірка маркування SIM7070G. Канон `02_05 §2.2.1` (+ §Пікові струми).
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak — рекоменд. **JBD/Jiabaida-клас** (найменші SKU 60-120A перекривають вимогу; відкритий протокол `esphome-jbd-bms` = телеметрія); self-drain верифікувати при закупівлі за per-SKU datasheet
- [ ] 👤 Обрати MPPT: **Victron SmartSolar 75/15** (research-підтверджено 2026-07-03 по всіх осях: LiFePO4-пресет, LVD, VE.Direct, quiescent 20мА, −30…+60°C з дератингом >40°C; альт. EPEVER Tracer-AN / Renogy Rover-Li, дешевші, але quiescent/temp неверифіковані)
- [ ] 👤 PCB layout: розмістити C_BULK ≤ 10 мм від VBAT pin, HF caps впритул
- [ ] 👤 Оновити BOM (закупка 5 нових компонентів)
- [ ] 👤 Bench: фізично звірити маркування модему на прототипі = **SIM7070G** (не SIM7000G; найменування у firmware/BOM/`02_05` вже уніфіковано — лишилась лише фізична звірка)

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
- **P2** · 🤖+👤 · 🔗 · → `02_05 §Starlink DTC vs Mini`
- **Стан:** ✅ **Рішення підтверджено (founder 2026-07-03): ESP32-S3** для WiFi-мосту STM32→Starlink Mini (~$3, near-zero sleep; SIM8200G-M2 відхилено — 5G марнується в лісі, ~20× дорожчий). Phase 3 only (Starlink Mini). 03_02 firmware-контракт + co-proc прошивка = Phase-3-gated (co-proc ще не будується — порожній контракт зараз = premature). Канон `02_05 §Starlink DTC` (memo HW.18).
- [ ] 🔗 Phase 3: co-processor firmware-контракт (STM32↔ESP32-S3 UART/SPI) у `03_02` + прошивка у `firmware/` — разом при Starlink-Mini bring-up

## §03a · Firmware

#### FW.2 — AES-128-ECB → AES-128-CCM (30B packet, wire-rev2.1) [post-ARCH.42]
- **P0** · 👤 · 🟢 · → `03_05 §2.1`
- **Стан:** CCM-тракт **повністю зашитий обабіч + усі фліп-гейти вирішено** — фліп-день лишає ЛИШЕ верифікацію заліза. Wire-rev2.1 **30B** двофазним WL-флоу (`HAL_CRYPEx_AESCCM_*` у WL-HAL не існують — CI `hal_check_ccm` компілює гейтований тракт щопушу), Queen = сліпий кур'єр (`rx_route.h`, запис air+1 = 31B), backend `process_ccm_chunk`/`LoraCcm` + KAT-parity; INERT за `FW2_CCM_ENABLED`/`TELEMETRY_CCM_ENABLED` (ECB живий, бойовий .bss незмінний). **Гейти (founder 2026-07-03) — усі чотири ✅:** (а) ✅ atomic-cutover як зашито (одиниця = кластер · фліп до першого field-deploy · QATT-біти видимості вікна; ціна = star-only, Сценарій Б гейтовано → ARCH.43 mesh-вісь) · (б) ✅ знято ARCH.54 · (в) ✅ **двоключова модель** — session KEYL per-device + cluster control-plane KEYB (📐 [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security); фабрика + host-тести shipped, Gateway-KEYL-цегла закрита; замінила «спільне значення до ARCH.43») · (г) ✅ **+2B EMA-delta_t (rev2.1, друге читання — переглянуто V3+)**: контракт «wire = вхід GP» → точний stateless recompute, observational до bench (E.63). 📐 FC/nonce/cold-boot + flip-checklist — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security); фабрична деривація — [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning). Закриває ECB→CCM/MIC/replay + SEC.10 panic + FW.29; SE = ідентичність-роль, LoRa-ключ KEYL лишається у Protected Flash (SEC.14 provisioning-only ✅ 2026-07-03; SEC.6).
- [ ] 👤 bench: верифікувати CCM-двигун на STM32WLE5JC REVB (RM0461 §27.4; атестація скриптована — RUNBOOK §2.1 + 2.1b e2e uplink-day, вкл. KEYB downlink-декрипт) + Flash-KV HAL-глю (спільний bench з FW.8/FW.17) → flip трьох прапорів = **ЄДИНИЙ HW-залежний пункт**
- [ ] 🔗 при спільному фліпі з ARCH.35: ring-запис 21B → 31B (air+1, rev2.1) fmt-aware (`FLASH_RING_RECORD_SIZE`; позначено в коді Королеви)

#### FW.4 — TinyML `Run_Inference()` — ✅ self-owned baseline landed (machine half); bench-confirm residual
- **P0** · 👤 · 🟢 · → [`03_03 §4`](03_03_TinyML_Acoustic_Inference)
- **Стан:** self-owned ESC-50 baseline приземлено (машинна половина) — `silken_net_audio_model.h` (INT8 forward-pass, gemmlowp, **972 B Flash / ~0 .bss / 76 B стек** << arena-стелі 7–15 КБ) + `Run_Inference` call-site розкоментовано + host-тест зелений; log-mel DSP (FW.25/FW.46, soft-float) живить його. Канон [`03_03 §4`](03_03_TinyML_Acoustic_Inference) (примирення TFLM↔CMSIS-NN §4.1; **silence+cavitation = синтетичні placeholder'и, НЕ field-валідовані** §4.2; точність = pipeline-integrity-метрика, run-provenance `tools/ml`). ML-партнерів нема → модель НАША end-to-end; апгрейд опційний.
- [ ] 🔗 ARM `arm-none-eabi-size` реальної arena — CI hal_check lane після board-freeze (FW.46)
- [ ] 👤 bench-формальність: silicon float32-confirm CMSIS-шляху (один прогін на платі)
- [ ] 👤 (опц.) польова/партнерська модель замінює header (Бушин CNN + Любченко NSGA-II + Cherkasy soundscape) — апгрейд, НЕ блокер
- [ ] 🔗 fallback Path C (TFLM runtime) — лише після повторного FW.26-заміру з TFLM-обвісом ([`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) противага; ex-FW.25 residual)
- [ ] 🌿 FW.4-EXT (post-TRL 7): 5-й клас `fauna_activity` dawn/dusk ([`03_03 §10`](03_03_TinyML_Acoustic_Inference)), залежить від UNI.11+UNI.13a

#### FW.49 — Tick-time ≠ wall-time у STOP2: системна семантика таймерів Soldier
- **P0** · 🤖+👤 · 🟢 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** wake-source ADR вирішено + S1-wiring host-shipped. `HAL_GetTick` заморожений у STOP2 (tick-`delta_t` міряв лише active-час → over-mint Proof-of-Growth); лік = RTC WUT + Vcap-енергогейт + RTC-календар timebase. Host: `Wall_Seconds_Now`/`Wall_Calendar_Set` (`wall_time.h`, civil↔unix roundtrip, free-running до синку), delta_t мігровано на wall-секунди (guard-и cold-start/назад/стрибок-епохи → baseline), cold-start epoch_day wall-first, wire `dT:2` сатурація @0xFFFF (wall-дельти бувають добами). Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA) (S1 + tick≠wall) + [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA) (wake-source ADR). ⚠️ **bench-gated residual:** LSE/RTC clock-tree (`MX_RTC_Init`) у repo відсутній — `Wall_Seconds_Now` на кремнії поверне 0 (чесна відмова → baseline) до bring-up.
- [ ] 🔗 **S2:** RTC-WUT-tick + Vcap-енергогейт → delta_t = справжній час перезаряду (чекає шкали ↓).
- [ ] 👤 **bench bring-up:** LSE 32.768 кГц + `MX_RTC_Init` (календар + WUT-IRQ STOP2-wake) + верифікувати `Wall_Seconds_Now`/recharge-інтервал (RUNBOOK §3-4: `04_lse_drift.py`, `03_power_profile.py`).
- [ ] 👤 🔴 фізика-блокер E.63 (Мінаєв/bench): шкала delta_t — L4 очікує **36-190 с**, а [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет дає **1.77 год** (P_gen=15µW); якщо ~1.77 год — метаболічний сигнал плоский (`metabolic_health(delta_t)`→GP майже константа, живе лише при L4-потужності EBFC). Cross-ref: E.63, FW.50, FW.20, FW.27-B, FW.30

#### FW.50 — Vcap ADC: raw counts використовуються як мВ (без конверсії)
- **P0** · 👤 · 🟢 · → [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** знахідка + helper канонізовано. Сирий 12-bit VREFINT-відлік (~1500; канал = VDDA за buck'ом, не Vcap EDLC) трактувався скрізь як мВ → RX-вікно (`VCAP_LISTEN_THRESHOLD=2800`) глухе НАЗАВЖДИ (OTA/mesh/time-sync/ротація мертві на кремнії) + Vcap-енергогейти з фейкових величин. Лік (рішення founder): `vcap_voltage = Adc_Vdda_Mv()` = чесні мВ VDDA (≈3300 поки buck живий) через factory VREFINT-cal (`adc_convert.h`, One-Home + host-тести); вухо відкрите, fauna-гейт (`FAUNA_VCAP_MIN_MV=4500`) чесно зачинений до живого Vcap-каналу; попутно знято VSTOR↔VBAT_SEC дрейф у [`02_03`](02_03_BQ25570_MPPT_Nano_Power). Канон [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 схемна вилка: розводка Vcap на окремий ADC-пін (цільовий тракт BQ25570 **VBAT_SEC** — [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM); дільник-номінали — [`02_03`](02_03_BQ25570_MPPT_Nano_Power): десятки МОм bleed vs TPS22860-гейт).
- [ ] 👤 bench-калібрування (DMM-точки vs `Adc_Raw_To_Mv` — RUNBOOK §3.4).

#### FW.46 — Enterprise-grade ARM firmware build (committed, reproducible, CI cross-compile)
- **P0** · 🤖+👤 · 🟢 · → [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** owned-code foundation host/CI-готова (`ci.yml › firmware_arm_build` зелений) — відтворюваний CMake крос-компайл того, чим володіємо: `cmake/arm-none-eabi.cmake` (Cortex-M4 **soft-float** — WLE5 без FPU, FPU-міф знято), `logmel.c` під ARM (~6.3KB), **mrbc** `bio_contract.rb`→`lorenz_bytecode.h` + drift-gate + minimal-VM harness, host↔target RFFT parity, mruby minimal-gembox (double + NO_BOXING-пін, ~117KB Flash). **HAL compile-lane** (`-DSILKEN_WITH_HAL=ON`): pinned WL-HAL submodules + `hal_glue/` wrapper-TU компілюють обидва `main.c` проти справжнього HAL — зловив одразу `__HAL_RCC_CRYP_*`→`__HAL_RCC_AES_*` (F4-стиль не існує на WL → Soldier STOP2-цикл + Queen `Restore_ECB_Mode` впали б на лінку). 🔴 повний HAL-лінкований `.elf` ще НЕ зібрано (board-freeze поза репо). **P0-обґрунтування: board-freeze = пре-реквізит УСЬОГО bench-дня секції** (без повного `.elf` жоден silicon-confirm, вкл. FW.2-фліп, фізично не виконується). **Bench-carrier рішення (founder 2026-07-03):** LoRa-E5 mini (той самий WLE5JC, пін-мапа §12.4:154-197) = silicon-носій **radio-free** зрізів ДО board-freeze — 2 mini + ST-LINK-V3MINIE + FT232RL + BME280-breakout (~$80); scope чесно-звужено (parity FW.7/19/31 · CCM/sym selftest · option-bytes+RDP-L1 · factory-provisioning · Flash-KV · DMA-вуха · LSE/WUT §4). Money-path e2e (CCM/OTA/ratchet) — за SubGHz-віхою (Шлях A ↓), НЕ прискорено mini. Рукописний `hal_glue/boards/lora_e5/` задовольняє SEC.15 (WUT=committed fn) краще за .ioc. **SubGHz Шлях A ✅ (2026-07-04, founder-рішення 07-03):** submodule `stm32-mw-subghz-phy` @v1.5.0 (`extern/subghz-phy`, SHA `7dc059f3`, BSD-3-Clause) + `RadioEvents_t`-реєстрація в обох `main.c` (Queen RxDone; Soldier RxDone+CadDone ARCH.26 — латентний `Radio.Init(NULL)` Queen-RX баг закрито) + owned-stub `hal_glue/radio.h` видалено: hal_check/hal_check_ccm + `.clangd` бачать справжній Semtech `radio_driver/radio.h` (ABI-звірено; `radio.c` НЕ компілюється — потребує `radio_conf.h` з .ioc board-freeze; бонус: submodule несе `lorawan/` = LoRaMac-node для ARCH.34). Money-path bench-зрізи розблоковано (§12.5; sx126x.c для on-chip не існує — лише `radio_driver/`). Канон [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 board-freeze → `.ioc` (CubeMX): тіла `MX_*`/`SystemClock_Config` (пін-мапа/клок/ADC/LSE — FW.49/FW.50) + `radio_conf.h`/glue для компіляції `radio.c` middleware (submodule + `RadioEvents_t`-реєстрація вже ✅ — Шлях A) + startup/ld → повний Soldier/Queen `.elf` + bench flash-verify
- [ ] 👤 (паралельно, дешевше) замовити bench-carrier: 2 LoRa-E5 mini + ST-LINK-V3MINIE + FT232RL + BME280-breakout → radio-free silicon-зрізи ДО board-freeze (⚠️ Seeed RDP-L1 factory: перший flash = mass-erase, AT-firmware не повернути → 3-й mini недоторканий резерв)
- [ ] 🤖 flip FW.26 на повний `.elf` після HAL
- [ ] 🤖 (optional, far-future) toolchain pin via ARM-tarball ([`00_08`](00_08_Beyond_TRL9_Planetary_Roadmap))

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

#### FW.55 — QEMU-M4 bit-parity lane: ARM↔x86 mruby double residual → CI
- **P1** · 👤 · 🟢 · → [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** QEMU-M4 bit-parity lane (`qemu-system-arm -M mps2-an386`, той самий `libmruby.a` + software-double `__aeabi_d*`, що піде на WLE5) ганяє committed-байткод реальним Cortex-M4 код-шляхом → **byte-exact** проти host-голдена (зчеплені кейси — хаос ампліфікує ULP), закриває FW.7/FW.19 ARM↔x86 Float-drift до тонкого silicon-confirm. Дві ноги (mruby + log-mel CMSIS, обидві soft-float) + заскриптована кремнієва нога `wle5_bench` (`05_parity_dump.py`). **64КБ фіт-гейт у CI зловив 4 девайс-знахідки** до кремнію (червоний 102400 → плато sbrk 38392 Б): ① runner arena save/restore; ② `MRB_CONSTRAINED_BASELINE_PROFILE`; ③ newlib-nano; ④ **`MRB_NO_BOXING` явний пін** — канон FW.19 «дефолт=NO_BOXING» був ХИБНИЙ (mruby 4.0 дефолт = `MRB_WORD_BOXING` → ~20.5КБ RFloat-транзієнту/виклик на ARM32), фіт-гейт тепер = CI-enforcement FW.19; + бонус per-wakeup `mrb_full_gc`. RAM-леджер виведено у FW.26 / [`03_03 §6`](03_03_TinyML_Acoustic_Inference). Канон [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA) (lane) + §12.4 (піни); межі ISA≠кремній = клас C (bench).
- [ ] 👤 silicon-confirm: один прогін на платі — `bench/05_parity_dump.py --plan` (flash `parity_wle5.elf` → дамп по VCP → вердикт скрипта)

#### FW.56 — Queen CoAP AT-граматика ≠ SIMCom: модем = UDP-труба, PDU будує хост
- **P1** · 👤 · 🟢 · → [`03_02 §4`](03_02_Queen_Gateway_Firmware)
- **Стан:** SIMCom CoAP App Note ≠ firmware-припущена граматика — реально модем = **UDP-труба**: хост будує сирий RFC 7252 PDU (`CCOAPNEW`/`CCOAPSEND` hex / URC `+CCOAPNMI`, домени через `CDNSGIP`). Три pure-шари + UART-клей (`uart_rx_ring.h` circular-DMA FW.3 / `at_engine.h` токенайзер / `coap_pdu.h` CON-PUT builder+parser golden-vector / `sim7070_coap.h` оркестратор) + host-тести. e2e Queen-PDU↔backend CoAP-intake софтом (golden C-білдер ↔ Rails-парсер + pure `CoapServerPdu` + повний ланцюг до `UnpackTelemetryWorker`). **Зловив/закрив 2 продакшн-баги Брами:** глобальний пошук payload-маркера (кожен 256-й `coap_mid` = фантомна доставка → FW.51 чистив кеш дарма) + Sentinel `route_queen_health` гинув на Sidekiq strict_args під broad-rescue; ACK-семантика тепер чесна до FW.51 (2.04 лише після enqueue, 4.04/RST → Королева тримає кеш). Канон [`03_02 §4`](03_02_Queen_Gateway_Firmware).
- [ ] 👤 bench: verbatim-звірка SIM7070-ноти V1.03 + реальні URC/таймінги
- [ ] 🔗 staging-smoke прогін проти задеплоєної Брами (`coap_smoke.yml` post-deploy gate; `bin/coap_smoke` + pure `lib/coap_smoke.rb` freeze-contract готовий — байт-звірка golden-векторів e2e: RST на сміття, 4.04 з 0xFF-MID піном, 2.04-після-enqueue; loopback-довід `coap_smoke_spec.rb`)
- [ ] 🔗 регресія enqueue-before-ACK: у `coap_listener` `perform_async` МУСИТЬ передувати `socket.send(reply)` (Redis-fail → тиша → Королева тримає CIFO, FW.51) — інваріант зараз тримається лише порядком рядків + коментарем; тест вимагає винесення тіла лупа в тестовану функцію → разом з наступним рефактором демона (знахідка Opus-нори 2026-07-04)

#### FW.58 — Queen DNS-re-resolve on flush-fail (DNS-failover зараз мертвий на живій Королеві)
- **P1** · 🤖 · 🟢 · → [`03_02 §4`](03_02_Queen_Gateway_Firmware), [`06_08`](06_08_Resilience_and_Failover_Policy)
- **Стан:** Знахідка pre-deploy нори 2026-07-04 (Opus-агент, верифіковано кодом): `coap_server_ip` (CDNSGIP-кеш `COAP_SERVER_HOST`) резолвиться ЛИШЕ коли порожній і НЕ скидається при провалі відправки (`g_coap_fail_count++` без інвалідації) → жива Королева довбе мертвий IP до IWDG-ребута (~26с hang) чи циклу живлення; **зміна A-запису `api.silkennet.com` — єдиний zero-infra глобальний failover — не підхоплюється.** Фікс = після N підряд провалених flush (`g_coap_fail_count >= 3`) → `coap_server_ip[0]='\0'` → примусовий re-resolve наступного flush; host-тест на скриптованому модемі (стек FW.56: `at_engine`/`sim7070_coap`). Зробити ДО прошивки Queens (після — лише OTA-кампанія). Canon-caveats уже проставлені: [`06_02`](06_02_Akash_Network_Integration) §TLS pre-flight + failure-modes · [`06_08`](06_08_Resilience_and_Failover_Policy) крок 2. Супутньо там же вичищено фантомні `CMD_SET_BACKEND`/`QUEEN_BACKEND_HOST` (команда ніколи не існувала у firmware — doc-drift).
- [ ] 🤖 host-half: fail-triggered re-resolve + host-тест (той самий клас, що FW.56)
- [ ] 👤 bench: живий SIM7070 — A-запис фліп → Королева підхоплює без ребута (разом з FW.56-bench)

#### E.59 — Mongabay biodiversity D-MRV pivot (acoustic fauna) [strategic]
- **P1** · 🤖+👤 · 🟢 · → `03_03 §10`, `08_01 §1`
- **Стан:** Стратегічний pivot carbon-MRV → biodiversity D-MRV (acoustic), після Delgado et al. (Nicoya, 119 ділянок, 16000 год аудіо; Mongabay, тр. 2026). Defensible moat проти Pachama/Sylvera/NCX (єдиний micro-acoustic verification layer). Firmware-фундамент pivot'а вже shipped 🟢 (log-mel FW.25 → §🗄️; fauna-інфра FW.42/ARCH.40 host-done) — відкрите gated датасетом/академіками. Координує вже-трековані: FW.4-EXT (5-class TinyML + `fauna_activity`), UNI.11+UNI.13a (Cherkasy Soundscape Library), BIZ.12 (Horizon CLUSTER 6 grant), 08_01 Стаття 24a. Канон `03_03 §10` + `08_01 §1/§2` + `08_02 §1B`.
- [ ] 🔗 FW.4-EXT 5-class `fauna_activity` — дім = FW.4 (🌿-чекбокс); gated UNI.11+UNI.13a dataset
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
- [ ] 🔗 активація: гейти уточнено 2026-07-03 ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)) — (i) **MAC-downlink** (CCM-фліп НЕ знімає: FW.2 автентифікує лише uplink, downlink лишається ECB+CRC) · (ii) **0x9E без DID-таргета** (broadcast-чутність → сусід ротується в розсинхрон; додати DID-поле в кадр до активації) · (iii) ✅ конфлікт «ротація вбиває downlink» ЗНЯТО двоключовою FW.2 (в) — ратчет ротує лише session KEYL, KEYB недоторканий. Далі: фліп трьох гейтів + глибина черги + bench (re-key CRYP, Flash-KV erase/program) — e2e RUNBOOK §2.6
- [ ] 🌿 ECDH-alt — разом із SE050-L2

#### FW.20 — Time Sync (Rails ↔ Queen ↔ Soldier) [+ FW.20-S2]
- **P2** · 👤 · 🟢 · → [`03_02 §5а`](03_02_Queen_Gateway_Firmware)
- **Стан:** 3-рівневий time-sync (CoAP envelope `0x9C` + reflex-beacon + auth-flag + panic-sync `0x56` + per-hop mesh-relay + anti-storm журнал `0x20` + gossip-piggyback) host-готовий, канонізовано [`03_02 §5а`](03_02_Queen_Gateway_Firmware) (SSOT — §5а явно шорткозамикає 00_07 на pointer). FW.20 1-hop done; mesh-relay **INERT** за `FW20_MESH_RELAY_ENABLED`. Tick≠wall-time у STOP2 вирішено лічильниками пробуджень (БЕЗ FW.49); TTL≥3 — founder-airtime-рішення.
- [ ] 👤 bench: lab LSE drift-test ΔT=±60°C (`04_lse_drift.py`, RUNBOOK §4.3) + Flash-KV HAL mesh-flip (спільний bench з FW.2/FW.8/FW.17)

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- **P2** · 🤖 · 🟢 · → [`03_02 §5.1`](03_02_Queen_Gateway_Firmware)
- **Стан:** Soldier RX-верифікація OTA вирішена Design B (Magic Re-Request) — Soldier bitmap-uplink `[0x55]` (`OTA_REQ_MARKER`) → Queen targeted re-broadcast лише missing chunks (60-90% economy vs wave) + djb2-dedup replay-protection + host-тести; «5 хв тиші» STOP2-імунна **без FW.49** (`OTA_REREQUEST_SILENT_WAKEUPS=10` тихих пробуджень з відкритим вухом — чесніше за мертвий STOP2-tick, що запізнювався у ~6-15×). Beacon anti-storm журнал реалізовано (FW.20-S2, Flash-KV `0x20` — [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)). Канон [`03_02 §5.1.3`](03_02_Queen_Gateway_Firmware).
- [ ] 🔗 Design A (ACK-aggregation, collective recovery) залежить від ARCH.26 TDMA RX-вікна (host-half ✅ 2026-07-02 — слот-примітив `Tdma_Slot_For_Did` готовий; активація = bench-фліп `ARCH26_TDMA_ENABLED`); Design B незалежний ✅

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- **P2** · 👤 · 🟢 · → [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor)
- **Стан:** Числовий DCI-band (`check_z_divergence!` + `DEFAULT_DCI_EPSILON=0.001`, два ENV-флаги default-off) ДОПОВНЮЄ категоричний check → ловить replay з валідним StatusByte, але хибною Z-magnitude. **Gate L machine-closed без заліза**: N=10 000 зчеплених кейсів mruby-VM↔CRuby = **бітова рівність 10000/10000, max|Δz|=0** (ARM-плече нульове за FW.55 QEMU byte-parity; історичні «~1e-14» superseded за pinned `MRB_NO_BOXING`) → ε=0.001 = чиста страховка. device_z wire-дім готовий (FW.2 wire-rev2 bytes 16..17, q=2⁻⁹). Канон [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor).
- [ ] 👤 silicon-хвіст Gate L: той самий one-command FW.55 дамп (SWD) — закриває FW.7/FW.19/FW.31 разом
- [ ] 👤 flip-гейти D/C/P/G (staging canary → production): виміряти ≥95% device_z-покриття після CCM-фліпу, тоді canary

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- **P2** · 🤖 · 🟢 · → [`03_03 §10.3`](03_03_TinyML_Acoustic_Inference)
- **Стан:** Brownout-guard для fauna-сесії — `Fauna_Should_Sample(vcap_mv)` (дворівнева Vcap-політика: ≥4.5V повна сесія, нижче — skip + counter `fauna_skipped_low_vcap`; fauna ~78.3 мДж ≈ 2× TX → при низькому V_cap concurrent TX = brownout) + host-тести. Поки сирий ADC не сконвертовано (FW.50), guard **fail-CLOSED** — `FAUNA_VCAP_MIN_MV=4500` > стелі VREFINT-тракту, tripwire-тест тримає інваріант ([`03_01 §1`](03_01_Firmware_Lifecycle_and_DMA) FW.50). Wire-дім: fauna-маркери = 2 біти `diag[2..1]` (CCM-кадр byte 18 — offset незмінний у rev2.1, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) ledger) + бекенд-лічильник `silkennet_fauna_skip_reports_total` ([`06_03 §2.8`](06_03_Prometheus_Observability)). Канон [`03_03 §10.3`](03_03_TinyML_Acoustic_Inference).
- [ ] 🔗 активація fauna-pathway після FW.4 fauna-pivot (гейт + ARCH.40-сесія готові; firmware call-site ставить diag-біти при pivot'і)
- [ ] 🔗 Grafana-панель — після перших живих інкрементів (мертва панель без джерела = передчасний dashboard)

#### ARCH.26 — Синхронні вікна (TDMA) + CAD preamble detection (Проблема Рандеву mesh relay)
- **P2** · 👤 · 🟢 · → [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA), [`03_02 §5.1.4`](03_02_Queen_Gateway_Firmware)
- **Стан:** Рандеву-драбина host-half ПОВНА (2026-07-02): L1 Queen always-on ✅ · L2 TDMA-вікна 🟡 · L3 CAD 🟡 — обидві половини INERT за незалежними гейтами `ARCH26_TDMA_ENABLED`/`ARCH26_CAD_ENABLED`. Дім драбини + енерго-політика ролей (full-RX/нюх лише Провідник ARCH.27; PANIC = extended-preamble відправника) = [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA); wire-дім розкладки + стелі точності (±1 с, `ts_frac`-апгрейд, sync-бюджет ±10 мс) = [`03_02 §5а.2а`](03_02_Queen_Gateway_Firmware); CAD-енерго-double-bind (нюх ≠ EBFC → surplus-Провідник; baseline-пара 3 с ↔ 4 с) = [`02_03 §9.10`](02_03_BQ25570_MPPT_Nano_Power). Розблоковує: FW.27 Design A ([`03_02 §5.1.4`](03_02_Queen_Gateway_Firmware)) · ARCH.43 (рандеву-передумова) · mesh-TTL rev2-рішення ([`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) · stigmergy-зворотний шлях ([`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap)). Активація post-TRL 6.
- [ ] 👤 bench: LSE drift проти ±10 мс sync-бюджету + RTC sub-second/LPTIM wake + CAD енергопрофіль (PPK2) + фліп обох гейтів (WUT-армінг — спільний bench з FW.49/FW.20/SEC.15)

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
- **Стан:** 300nA-режим вимикає SRAM2 retention → RAM-only стан гине (RTC DR0..DR19 виживає: EMA/mesh-кеш/Lorenz/delta_t wall-маркер). Host-готово: Flash-KV (`flash_kv.{h,c}`, power-cut тести) + RAM-state інвентар (§2.3.1, групи A/B/C) + 3-осьова RTC-реклемація (§2.3.2: дешева реклемація розміщує live-набір FW.54 у RTC — Flash для нього НЕ потрібен). **DID-інверсія ВИРІШЕНА** (founder, §7): DID = детермінований `f(96-біт UID)` murmur3-fmix32 recompute-on-boot (`did_derive.h` + Ruby-дзеркало `SilkenNet::DidDerivation`, golden g1-g4; нуль → Queen Sentinel) → **DR7 звільнено** (перша реклемація з FW.2-freeze), DID VBAT-durable, однопрохідна фабрика; стара `UID⊕random` (FW.24-fallback) сиротила гаманець при EDLC-розряді. **wire_did зшито обабіч ✅ (2026-07-03):** фабричний транскрипт (`TreeResolver`: create/re-flash/bind/колізія→quarantine на `trees.silicon_uid_hex` + live wrong-board guard `-r32`-preflight до першого `-w32`) + польовий register (мертвий `last(8)`-DID → деривований, ожив double-init guard) — [`03_06 §2/§5`](03_06_Factory_Flashing_and_Key_Provisioning) + [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA). Канон [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)/§2.3.1/§2.3.2 + DID-механізм [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 рішення: RTC-реклемація (§2.3.2) vs Flash-KV persist vs SRAM2-retain — свідомо відкладено до bench (приймати з виміряним 300nA floor PPK2/JS220, RUNBOOK 3.1, не з моделлю)
- [ ] 👤 bench: HAL_FLASH glue + ECCD-політика + вимір 300nA + persist-roundtrip

#### ARCH.43 — Mesh-relay повернення: wire-rev3 addressing (post-CCM star-only)
- **P3** · 🤖+👤 · 🔗 · → [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** Звужено — FW.2 гейт (в) закрив uplink/demux-вісь двоключовою моделлю (session KEYL per-device + cluster KEYB, [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); лишається mesh-вісь. У CCM-еру Сценарій Б мертвий by construction (`#if !FW2_CCM_ENABLED`: air-кадр гине на RX-guard сусіда, TTL у ciphertext) → **star-only прийнято** (ухвала FW.2 (а)); стеля масштабу однієї Queen (TTL=3 · relay-буфер без агрегації · CIFO) + масштаб-відповідь «більше Queen» (ARCH.1/ARCH.10) = [`03_01 §1.9.1`](03_01_Firmware_Lifecycle_and_DMA). Повернення mesh = wire-rev3-клас: cleartext TTL/адресація (mesh-TTL rev2-рішення) + opaque pass-through relay без декрипту + `0x9E` DID-таргет (FW.17 gate (ii), [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)). Активація post-TRL 6, на масштаб-тригер.
- [ ] 🔗 передумови: ARCH.26 рандеву-фліп + downlink-wire-ревізія (MAC/FC, [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security))
- [ ] 🤖+👤 wire-rev3 addressing-дизайн (cleartext TTL/DID + opaque relay + DID-таргетований downlink)

## §03b · Edge crypto

#### SEC.3 — Factory Flashing pipeline
- **P0** · 🤖+👤 · 🟡 · → [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning)
- **Стан:** Rake-конвеєр (Гілки A+B) канонізовано + host-доведено: AASM + **authenticated 2-Person Rule** (console-bypass закрито guard'ом, RSpec-покрито) + execute-шим + **master-key DI ✅** (preflight-ключ від `MasterKeySource` наскрізно у всі **три** HKDF-читачі вкл. `SeedDerivation.derive_seed`; runtime = ENV-fallback; non-ENV adapter розблоковано, DI-proof спеки) + **one-pass UID→DID ✅ (FW.54, 2026-07-03)** — `TreeResolver` (24-hex UID → `wire_did` → Tree create/re-flash/bind/колізія→quarantine) + wrong-board guard у Session (preflight `-r32`, чужа плата → жодного `-w32`, навіть HardwareKey не матеріалізується). Механіка + delivery-варіанти — канон [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning) (+ §1 pipeline). bench-residual = фізичний SWD-флеш.
- [ ] 👤 real `STM32_Programmer_CLI` на STM32WLE5JC bench (post-FW.2) — runbook `firmware/scripts/bench/`; + звірити реальний `-r32`-формат виводу проти `UidReadout` (wrong-board guard, RUNBOOK 1.3)
- [ ] 🤖+👤 Bitwarden Secrets API live — 🤖 `BitwardenAdapter` імплементація+spec (зараз `NotImplementedError`; DI-pre-req ✅ знято 2026-07-02 — див. Стан) + 👤 акаунт/секрети + live-смок
- [ ] 🔗 real SE I²C (Гілка B) — SE050 eval-kit; `cryptoauthlib`→SE05x код-міграція → SE050-MIGRATION (legacy ATECC-патерн reusable, [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security))
- [ ] 👤 operational residual (звужено 2026-06-15 — `approve!`-bypass закрито кодом, див. Стан): лишається лише raw-SQL / object-manipulation (`update_column`/`instance_variable_set`) — будь-який in-process guard це обходить = межа §5.A access-control ([`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning); master-key=`super_admin`+MFA+HSM); full crypto-approval (per-user PKI замість пароля) — bench/future

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **P0** · 👤 · 🟢 · → [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** guard `Security::WeakKeyDetector` + fail-closed boot-guard (refuse-to-boot на FIPS-197/NIST/degenerate vectors, RSpec-покрито) не дає тест-вектору потрапити у `PROVISIONING_MASTER_KEY`. ⚠️ ОКРЕМЕ від FW.1: якщо master seed базується на цьому ключі — весь derivation tree скомпрометований.
- [ ] 👤 замінити seed key на crypto-random → задокументувати генерацію у vault (без коміту) → re-flash прототипи

#### SEC.2 — RDP Level 2 activation timeline
- **P1** · 👤 · 🟢 · → [`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** RDP-L2 процедура канонізована (pre-flight + CubeProgrammer CLI + R&D→Pilot→Mass rollout) + скриптовано `01_option_bytes.sh --rdp 2` (bench RUNBOOK). Незворотний SWD-lock, а OTA латає **лише mruby-байткод, не C** → C-прошивка замерзає назавжди → OTA мусить бути верифікований у полі ДО активації. Канон [`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security).
- [ ] 🔗 верифікувати OTA flow end-to-end на bench ДО L2-lock
- [ ] 👤 field batch → RDP **L1** (зворотний); L2 — лише фінальний mass-deploy

#### SEC.15 — IWDG freeze у STOP2 (option byte `IWDG_STOP=0`)
- **P1** · 🤖+👤 · 🟢 · → [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- **Стан:** freeze-rationale + PVD-кома side-path канонізовано — `IWDG_STOP=0`+`IWDG_STDBY=0` (LSI-пес лічить у STOP2 max ~32.7с → spurious reset посеред багатогодинного сну) заскриптовано поряд з RDP у `firmware/scripts/bench/01_option_bytes.sh` (RUNBOOK §1.2). Канон [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA).
- [ ] 👤 застосувати на платі при factory flashing
- [ ] 👤 bench-верифікація: сон 1 год без spurious reset (RUNBOOK §4.4)
- [ ] 👤 bench-audit `MX_RTC_Init`: WUT auto-reload + IT enabled + reliable multi-hour WAKE (не лише no-spurious-reset) — frozen IWDG × SEC.2 RDP-L2 → WUT = ЄДИНИЙ backstop живучості; clock-tree bring-up = FW.49. Деталі [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)
- [ ] 🤖+👤 **hard pre-L2 gate** (× SEC.2): жоден RDP-L2 burn, поки армінг WUT не (а) закоммічена ревʼюйована fn (не регенерований .ioc) і (б) bench-verified на багатогодинне пробудження. Код — на bench-день (LSE clock-tree absent → CI довів би лише compile, не WAKE); author-now додатково потребує host-stub `SetWakeUpTimer_IT` (`soldier_hal_check.c`/`hal_mock.h` стаблять лише `BKUPRead/Write`). Деталі [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)

#### SE050-MIGRATION — ATECC608B → NXP SE05x (baseline SE051C2) + true-DePIN ladder (2026-06-07)
- **P2** · 🤖+👤 · 🟢 · → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** **Класифікація (founder 2026-07-03): стратегічний вектор, не найближча черга** — End-Game напрям проєкту (true-DePIN); усе доступне зараз shipped, просування gated eval-kit'ом (👤 замовлення) + anchor-TRL (L2), звідси P2·🟢. Рішення (founder) = **true-DePIN** «голос дерева» (non-extractable Ed25519, що не підробить ні backend, ні оператор): ATECC608B (P-256 — не тримає голос жодного ланцюга) → **SE05x-family, baseline SE051C2 / fallback SE050C2** (founder 2026-07-02). Host/doc-half ✅ (ADR + Slot-1→Ed25519 + legacy-banner + honesty-pass) · paper-half datasheet-verify ✅ · **L1 Queen-attestation 🤖-shipped** (Ed25519 Monocypher підпис батча ↔ backend verify-до-decrypt + двофазний owner-nonce anti-replay; 4 незалежні реалізації Monocypher↔OpenSSL↔RSpec↔HIL e2e). AES-128 LoRa = вибір, не SE-constraint; soft-freeze DNP до mass post-FW.2; ціна — founder: не проблема. Повна деталь (суперсет, ціни, SE051-звірка, DPD/load-switch, eval-номенклатура, cold-boot-питання) = [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) datasheet-verify; QATT-wire + anti-replay = [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security); ladder + рунг-статуси = [`05_02`](05_02_Proof_of_Growth_Pipeline).
- [~] 🤖 код partial: SE050-header + Slot-1→**Ed25519** ✅ (`atecc_provisioner.rb`); лишилось bundled з eval-kit real-I²C: rename `AteccProvisioner`→`SecureElementProvisioner` (+session/spec/factory refs) + SE05x emit замість `atcab_*` + DB-міграція `atecc_serial_hex`→`se_serial_hex`. Гілка-B не live → ризик-кероване відкладання.
- [ ] 🤖 `03_05` deep mechanics → SE05x при eval-kit (no-premature-canon): candidate-table, `atcab_*`→`Se05x`/`sss` API, role-split, latency/power/footprint, object-model замість 16 slots
- [ ] 👤 SEC.6 hardware: звірити ціну/сток **SE051C2** → замовити eval-пару (SE051-кіт OM-SE051ARD?/Mikroe Click + **OM-SE050ARD-E** companion, НЕ -F) → silicon-confirm paper-чисел (**cold-boot заряд = головне питання** — датащит не специфікує) + SEC.14-числа обраної ролі (✅ provisioning-only 2026-07-03 — §🗄️; міряти cold-boot/T1oI2C-латентності provisioning-операцій) + mass-BOM populate разом з load-switch гейтом SE — paper-звірка/DPD/номенклатура канонізовані [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)
- [ ] 👤 L1 bench: EDSK-flash на кремнії + e2e attested-батч (RUNBOOK §2.4)
- [ ] 🔗 **L2 per-tree device-voice** (North-Star, energy-gated Scenario D / 2× anchor): on-chip Ed25519 keygen + device-keygen provisioning (не HKDF-only — ARCH.33) + Merkle-root signing (E.60; примітив = ARCH.12 Фаза-1) + signature-transmission (weekly ≈ 5 LoRa-frames). Post-anchor-TRL.
- [ ] 🔗 L2 design-gap — **підхід вирішено** (Фаза 0, deep-audit 2026-06-28), реалізація post-anchor-TRL: тижневий device-Merkle-корінь підписується ПІСЛЯ intra-week мінтингу (Queen-relay L1) → **ex-post reconcile + clawback** (device-root vs намінтоване; mismatch = positive-A tamper → наявний `slash()`); pre-mint двофазний = North-Star (energy-gated). Дім політики [`05_05 §3.3`](05_05_Slashing_and_Risk_Policy); механізм Merkle = ARCH.12 / E.60
- Cross-ref: SEC.6, SEC.14 (роль ✅ provisioning-only — §🗄️), ARCH.42, ARCH.43 (mesh-вісь; uplink-ізоляція ✅ FW.2 (в) двоключова — SE-era: KEYL лишається у Protected Flash, SE Slot 0 reserved urban-варіант; cluster KEYB у Flash як K_ota), E.60 (Merkle), FW.2, FW.23, ARCH.33 (firmware-Ed25519 feasibility), STK.4 (ЗВТ), BIZ.13 (operator-bond).

## §04 · Backend / API / UI

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** · 👤 · 🟢 · → `04_03 §1.4`
- **Стан:** Graceful degradation реалізовано — Redis down → DB-backed nonce (Solid Cache, TTL 10хв), шлюзи не отримують 503 (`m2m_auth_controller` [S6.1] + spec). Канон `04_03 §1.4` (M2M replay-nonce + graceful degradation).
- [ ] 👤 верифікувати Upstash multi-zone replication у production

#### E.41 — Fire-event 48h latency (dClimate obscuration) → immediate-broadcast fallback
- **P1** · 🤖+👤 · 🟢 · → `04_02 §11`, `05_01`
- **Стан:** ✅ **Severity-гілка shipped (2026-07-03, [E.41]-фікс):** критичний fire-алерт, затемнений хмарами/кронами → `escalate_obscured_critical_fire!` (негайний Field-Audit, `satellite_status: :inconclusive` HOLD-ить payout, fail-safe) замість сліпого 48h orbital retry (`handle_obscured_by_clouds` раніше raise'ив `OrbitalLagError` для ВСІХ severity — implementation gap `04_02 §11` закрито; non-critical → retry лишається). Дзеркало non-fire/INS.1 peril-honest. Life-safety не чекає орбіти — тривога вже пішла окремо (edge panic-TX + backend alert, **НЕ** satellite-gated). Основа: immediate-broadcast ✅ (edge chainsaw→panic-TX `PANIC_TTL=5` + backend temp/anomaly `AlertDispatchService`; dClimate гейтить лише ВИПЛАТУ, не тривогу). Канон `04_02 §11` (Dclimate/EWS), `05_01`.
- [ ] 🔗 upgrade Field-Audit → ForestBounty-дрон (фізична перевірка замість людського вердикту) — North-Star коли E.20 (`04_02 §Forester Guild` `[PLANNED]`)

#### S6.21 — MFA: TOTP second factor (claimed, not implemented)
- **P2** · 🤖+👤 · ⚪ · → `04_03 §1`
- **Стан:** Не розпочато — honesty-gap: CLAUDE.md §9 раніше заявляв «MFA: TOTP» (виправлено 2026-06-19). Реальність (`04_01` User): лише recovery-codes (10 шт., `consume_recovery_code!`) + `otp_required_for_login` булевий флаг + step-up (`current_password`) на disable — **справжнього TOTP-другого-фактора нема** (нема `rotp` gem / `otp_secret` / provisioning_uri). Білд: `rotp` + `otp_secret` (AR-encrypted) + `MfaSetupsController` (provisioning_uri/QR) + verify-on-login + recovery-rotation. Канон `04_03 §1` (Автентифікація) / `04_01` (User).
- [ ] 🤖 `rotp` + `otp_secret` (encrypted) + `MfaSetupsController` (QR/provisioning_uri) + verify-on-login
- [ ] 👤 (опц.) WebAuthn / hardware-key як сильніша альтернатива TOTP

#### E.20 — Forester Guild: ForestBountyService (PoPhW fallback oracle + ranger economy)
- **P2** · 🤖+👤 · ⚪ · → `04_02 §Forester Guild`
- **Стан:** ⏸️ **DEFER до Phase 2 (founder 2026-07-03):** YAGNI — реальної ranger-мережі нема, `ForestBountyService` без неї = код попереду реальності (guild-маркетплейс = Phase 2 «мобільний додаток для лісників», `00_01 §4`). Резервний Оракул через фізичний PoPhW (рейнджер+дрон) + bounty-економіка (GPS/EXIF/IPFS→USDC, anti-Sybil); design готовий (`04_02 §Forester Guild`). **Блокер** для S6.10 + E.41-satellite-fallback + BIZ.13-Модель-B. ⚠️ E.41-фікс OrbitalLagError НЕ чекає на E.20 (Field-Audit-ескалація незалежна — див. E.41). Enabler BIZ.13: PoPhW→operator-bond + guild-sponsor ([`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)). **Зчеплено:** E.66 `finalize_spend!`-prune (escrow-примітив, що E.20 реюзнув би) — при E.20-go воскресає з `[E.20]`-маркером.
- [ ] 🤖 `ForestBountyService` — bounty matching ranger↔alert + USDC payout
- [ ] 👤 онбординг рейнджерів Forester Guild

#### ARCH.31 — SOP-в-Phlex inline UI для EwsAlert
- **P2** · 🤖+👤 · 🔗 · → `04_02`, `08_02 §3`
- **Стан:** 8 SOP-runbook'ів (drought/epidemic/vandalism/fire/seismic/fault/entropy/**field_audit** [INS.1]) як inline-інструкції при кліку на EwsAlert у дашборді — forester отримує немедіане runbook замість пошуку в документах. 🔗 на UNI.12 (самі SOP-документи UA+EN — joint ChIPB-NUTSU; ex-E.54). Канон `04_02` (EwsAlert/EWS), `08_02 §3` (SOP-джерело). SOP-compliance = зворотний бік Кат-A negligence-evidence (no-firebreak-after-alert = недотримання fire-SOP — SLASH-1/BIZ.13 міряють саме його відсутність).
- [ ] 🔗 UNI.12 — SOP-документи (8 alert-типів × UA+EN)
- [ ] 🤖 Phlex inline-SOP компонент на EwsAlert dashboard

#### I18N.1 — alert_type i18n локалізація (усі типи × 4 мови)
- **P3** · 🤖 · 🌿 · → `04_02`, `04_04`
- **Стан:** Знахідка (INS.1, 2026-06-27) — `EwsAlert.message` (усі creator'и) + `TextFormatter#alert_title`/`#alert_icon` = **hardcoded-рядки**; `config/locales/alerts/*.yml` (uk/en/lv/lt) покривають лише UI-хром (badge/index/table-headers), БЕЗ per-alert-type value-labels чи message-ключів (`grep alert_types` → порожньо). Маркер на майбутнє вже стоїть (i18n-коментар у `TextFormatter`). Поточно безпечно (`.humanize`/hardcoded-case з `else`-fallback), але не локалізовано для 4 мов — і свідомо НЕ робили по одному типу (`field_audit` додано в ряд із 7 сиблінгами, жоден не i18n-нутий). Канон `04_02` (TextFormatter card), UI-токени `04_04`.
- [ ] 🤖 i18n-ключі per-alert-type (8 типів × 4 мови: title + icon) → `TextFormatter` через `I18n.t`; опц. `EwsAlert.message`-builder через i18n — усі типи РАЗОМ, не по одному

#### S6.10 — MaintenanceRecord — лише лог
- **P3** · 🤖 · 🔗 · → `04_02 §Forester Guild`
- **Стан:** Архітектурний дизайн готовий — task-assignment matching ranger↔bounty (scoring, `FOR UPDATE NOWAIT`, GPS/EXIF/IPFS→USDC, anti-Sybil). Заблоковано на Forester Guild PoPhW (E.20). Канон `04_02 §Forester Guild`. Ranger-scoring живить reputation-scaling operator-bond (BIZ.13 [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)).
- [ ] 🔗 зв'язати з Forester Guild PoPhW (E.20)

## §05 · Web3 / Економіка / Slashing

> Мультичейн, oracle/chain-конфіг та slashing-механіка — канон `05_xx`.

#### SLASH-1 — Slashing cause-gate (positive-A-evidence)
- **P0** · 🤖+👤 · 🟡 · → `05_05 §3.2/§6` (divergence `04_02 §11`)
- **Стан:** Positive-A-evidence cause-gate **Фаза 1 реалізована** (`BlockchainBurningService` ← `Slashing::CauseEvidence#positive_a?`): необоротний `slash()` лише за прямого доказу Кат-A (tamper), інакше `:frozen` + Field Audit (відновлює C-дефолт §2) — закрив 3 false-slash діри + латентний «daily ніколи не палив»; A-сет фази-1 свідомо КОНСЕРВАТИВНИЙ (лише tamper), повний опис [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy). **[INS.1] зацементовано:** `field_audit` alert-тип (gap-D closed — freeze/blackout → `:field_audit`, виключені з `comms_no_ack?`/`critical_unmaintained?`, freeze не накручує `penalty_factor`) + `DailyHealthRouter` (DRY спільного денного A/B-читання). **Chainsaw-спліт ВИКОНАНО (2026-07-04, founder-рішення 07-03):** `chainsaw_detected(10)` enum + `AlertDispatchService` дискримінатор acoustic-vs-thermal (anomaly без термального порога = вирубка; термальний сигнал пріоритетний) + `requires_satellite_consensus?` → non-fire маршрут dClimate у Field-Audit (знято тавро «FIRMS: ясне небо → rejected_fraud» з жертви вирубки — дзеркало INS.1 peril-honest) + PANIC-TX-маркер у повідомленні; ⚠️ **НЕ в A-сет** до field-validation TinyML (`CauseEvidence` tamper-only; synthetic placeholder `03_03 §4.2`). DB-міграція виявилась непотрібна: int-enum без CHECK-constraint, частковий unique-index `(tree_id, alert_type, status)` новий тип покриває. Дім [`05_05 §3.2/§6`](05_05_Slashing_and_Risk_Policy) (+ [`04_02 §6`](04_02_Business_Logic_and_Services); divergence `04_02 §11`). Відкрите ↓.
- [ ] 👤 DAO/founder перед mainnet (лише ПІСЛЯ field-validation TinyML): розширити A-сет (scoped-unmaintained + chainsaw) + активувати inert `penalty_factor`-uplift (`slash_cause_uplift_enabled`)
- [ ] 🤖 (secondary) tree-side `streamr_undelivered` сигнал-джерело (guarded→0) + repeat-offence вага
- [ ] 🤖 (residual) `field_audit` dedup-**ключ** — уникнути щоденних дублів cluster-level `:field_audit` при тривалій деградації (type-розділення вже знімає конфляцію з comms-fault; `system_fault` свідомо лишається на DailyAggregationWorker-блекауті + `handle_slashing_failure`)
- [ ] 🤖 (backlog) поріг «critical stress» 0.8↔0.83: slash = `AiInsight::SLASH_STRESS_THRESHOLD` (0.83), insurance = 0.8 — spread ЖИВИЙ і задокументований ([`05_05 §4`](05_05_Slashing_and_Risk_Policy), `DailyHealthRouter`; РІЗНІ концепти: insurance-кандидат vs slash-тригер); опц. уніфікувати або міграція slash-порога (+ `Rational(1,5)`-тригер) у `SystemParameter` `slash_gamma`/`slash_penalty_factor_max` (per `05_06`)

#### SEC.1 — Multisig Gnosis Safe + PAUSER⊥admin split (production admin role)
- **P0** · 👤 · 🟢 · → [`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC)
- **Стан:** Code-complete + verified (`Deploy.t.sol` пінить матрицю ролей + закритий bypass); **нічого не задеплоєно**. Кожен economic-vector admin (SCC/SFC токени + `ProtocolParameters` + `StateRootAnchor`) = `SilkenTimelock` 48h; `pause`/`unpause`=Gnosis Safe (миттєво) — єдине правило «admin=Timelock, окрім pause». Закрито: instant-`grantRole(MINTER)` + Safe-`grantRole(GOVERNANCE_ROLE,self)`-bypass ([E.35]); `REQUIRE_SAFE_ADMIN` + last-admin guards. forge build/test/fmt зелені. Канон [`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC) (+ StateRootAnchor [`05_04`](05_04_Ethereum_L1_State_Anchor)).
- [ ] 👤 створити Gnosis Safe (3/5|2/3) на Polygon + деплой з `ADMIN_ADDRESS=<Safe>` `REQUIRE_SAFE_ADMIN=true`
- [ ] 👤 реальні зовнішні co-signer'и Safe — solo-founder: усі ключі в однієї особи = театр (HW-wallet'и + social recovery); renounce Timelock-admin + Safe-PROPOSER→`address(0)` post-DAO

#### S3.2 — dClimate Real API verification
- **P1** · 👤 · 🟢 · → `05_01`
- **Стан:** Реалізовано — `Dclimate::VerificationService` (NASA FIRMS, FRP≥10MW, cloud fallback) + `DclimateVerificationWorker`. Лишається verify з реальним API key у staging. Канон `05_01`.
- [ ] 👤 верифікувати з реальним API key у staging + e2e `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P1** · 👤 · 🟢 · → `05_03`
- **Стан:** SFC events (ForestMinted, GovernanceSlashed) у subgraph + zero-address fail-fast guard `subgraph/validate_addresses.sh` ✅ (раніше E.45); SFC-адреса = placeholder до mainnet-деплою. Канон `05_03`.
- [ ] 👤 mainnet-cutover subgraph (раніше E.48): `network: polygon-amoy` → mainnet + замінити `0x0000…` на реальну SFC-адресу у `subgraph.yaml` (після контракт-деплою)

#### E.63 — метаболічний сигнал: розв'язано від хаосу (Option A) [2026-06-08]
- **P1** · 🤖+👤 · 🟢 · → `05_02`
- **Стан:** Option A (founder) — здоров'я **розв'язано від хаосу**: Лоренц = лише status-гейт (β=`BASE_BETA` фікс), `growth_points` у гомеостазі = `metabolic_health(delta_t)` напряму (FW.5 β-перт реверсована — β не рухає z-нерухому точку z_eq=ρ−1, тому delta_t→β-сигнал виходив економічно нульовий); byte-identical DCI обабіч + guard `growth_points_clamp_drift`. **Гілка B ✅ вирішено+shipped wire-rev2.1 (founder 2026-07-03, друге читання переглянуло V3+):** wire несе EMA-вхід GP (30B, контракт «wire = вхід GP») → `expected_homeostasis_gp(ema)` recompute **stateless байт-точно**, гілка observational до bench (V3+-принцип = перемикач строгості). Формула + присуд — [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor); wire-ухвала — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) ledger; механіка — [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA); фізична шкала delta_t — [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) L4 / [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power) енергобюджет.
- [ ] 👤 bench: реальна P_ebfc (`HW.13`) + E_cycle + recharge-крива (`03_power_profile.py`, RUNBOOK §3.2-3.3)
- [ ] 🤖 калібрування `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` (placeholder 600/7200с) під зміряну recharge-криву — per-deployment/species; тим самим кроком увімкнути строгість точної metabolic-гілки (observational → gate, один перемикач)

#### E.32 — Smart Contract Audit (pre-mainnet security gate)
- **P1** · 👤 · 🟢 · → `05_03`
- **Стан:** Automated-аудит повністю **gating** (CI-green) — `solidity_audit.yml`: static (Slither + Aderyn) · symbolic (Halmos, `test/symbolic/`) · property-fuzz (Medusa `test/medusa/` + Foundry invariant `test/invariant/`), усі fail-on; scope 6 deployable контрактів; Mythril знято (→ Halmos foundry-native). Roadmap [`05_03`](05_03_Tokenomics_SCC_and_SFC); CI-інвентар [`06_07 §1`](06_07_CICD_and_Runbook_Index). Лишається paid manual + runtime audit (👤) ↓.
- [ ] 👤 Hacken/Hashlock manual audit (платний) — pre-Amoy→Mainnet HARD gate
- [ ] 👤 CertiK Skynet runtime monitoring — post-mainnet deploy

#### INS.1 — Parametric insurance oracle: dead pipeline + no-data under-pay
- **P2** · 🤖+👤 · 🟢 · → [`05_05 §4`](05_05_Slashing_and_Risk_Policy)
- **Стан:** Dual-trigger oracle **SHIPPED** (minimal, INERT за kill-switch `:parametric_insurance_oracle_enabled` default off — `f6deb5ad`) — мертву `evaluate_daily_health!` (0 prod-callerів) оживлено: AI = Trigger-1 (`arm_candidate!` → `:triggered` + `field_audit`, **НЕ** payout), settlement лише за НЕЗАЛЕЖНИМ Trigger-2 (dClimate verified / Field-Audit) через `InsurancePayoutWorker#awaiting_independent_confirmation?` — закриває basis-risk/moral-hazard; no-data guard (`escalate_no_data_field_audit!` замість тихого 0 — «не карати жертву»); fire-шлях + integration-тест landed. + `DailyHealthRouter` (DRY) + `field_audit`/gap-D + insurance SLO. Філософія «почути дерева, без людського фрауду» (`00_01 §1/§2/§6`; North-Star = forest-collective `00_08 §1`). **[peril-honest routing SHIPPED]** verify-by-data (deep-audit) переписав drought-задачу: хибний-slash УЖЕ закритий SLASH-1 Cat-A гейтом; справжня діра — **Potemkin-peril** (Cosmic Eye обіцяв 3 перили, fire-FIRMS-двигун верифікує 1). `Dclimate::VerificationService` адьюдикує ЛИШЕ fire; не-пожежа (посуха/шкідник) → `escalate_non_fire_to_field_audit!` (`:inconclusive`/Field-Audit, НІКОЛИ `rejected_fraud`/slash; +insect у `requires_satellite_consensus?`/`awaiting_independent_confirmation?`) → прибрано «тавро жертви фраудом» + canon-drift (неіснуючий `dClimate.drought_index` у `05_05 §2/§4`). Дзеркало SLASH-1/E.63. `trigger_event` НЕ мертвий (= застрахований перил при створенні полісу — фабрика/`:drought` трейт; «оживлення» відкинуто verify-by-data як non-problem). 🔗 Зшито: **E.41** (satellite-obscured fire = той самий Field-Audit-клас) · **E.20/E.34** (`ForestBountyService` дрон-fallback) · **UNI.12** (Field-Audit SOP + ДСНС-API) · **S3.2** (real-API gate). Дім [`05_05 §4`](05_05_Slashing_and_Risk_Policy) (+ [`04_02 §6`](04_02_Business_Logic_and_Services) · [`07_01 §7`](07_01_Nature_as_a_Service_Contracts) · `04_01` · [`06_03 §2.8`](06_03_Prometheus_Observability) · [`05_06`](05_06_Governance_and_DAO)). Відкрите ↓.
- [ ] 🤖 (deferred, 👤-API-gated) **реальний** drought/pest Trigger-2-оракул — misroute уже закрито (peril-honest routing ↑); лишається ДЖЕРЕЛО verified-підтвердження: dClimate `drought_index`/soil-moisture (S3.2) / ДСНС-API (UNI.12) / `ForestBountyService` дрон (E.20/E.34) + acoustic-pest; чистий armed-vs-confirmed payout-gate. North-Star = голос самого лісу (sap/VPD/acoustic [`05_05 §7`](05_05_Slashing_and_Risk_Policy); forest-collective [`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap))
- [ ] 🤖 (deferred, gated) Auto-Immune Sentinel hook ([`00_08 §1.4`](00_08_Beyond_TRL9_Planetary_Roadmap) Gap #4): proactive cluster-fingerprint + decoy-DID tripwire (+ Merkle inclusion-witness ARCH.12/E.60 як крипто-доказ включення запису) як джерела незалежного підтвердження, коли money-path live + cap зросте
- [ ] 👤 активувати kill-switch `:parametric_insurance_oracle_enabled` — drought-misroute УЖЕ закрито (посуха не йде хибним slash-шляхом); лишається: без реального drought/pest Trigger-2 (↑) посуха/шкідник тримаються у Field-Audit (не авто-платяться — безпечно, але peril неповний). ⚠️ На РЕ-активації після паузи врахувати накопичений `:triggered`-backlog → `InsurancePayoutRecoveryWorker`-burst (payouts idempotent+gated, переважно HOLD post-peril-honest → load-, не money-concern)
- [ ] 🤖 (minor, doc-ahead-of-code) `trigger_event` (insured-peril, [`07_01 §5`](07_01_Nature_as_a_Service_Contracts)) задається ЛИШЕ фабрикою/`:drought`-трейтом — простежити прод-creation-шляхи `ParametricInsurance`, проставляти перил при створенні (інакше `notes:`/audit його не фіксує; аналог `forester_share` computed-not-disbursed). «Оживлення на payout» відкинуто verify-by-data (фабрика-дефолт → vacuous-тест + непокрита гілка)

#### BIZ.13 — Slashing principal-agent: investor capital vs operator-bond
- **P2** · 🤖+👤 · 🔗 · → `05_05 §3.1`, `05_03 §Slashing`, `04_02`
- **Стан:** Principal-agent (slash інвестора за провину оператора, `00_01 §6` «не карати жертву») **ЛАТЕНТНИЙ у поточній Моделі A** (ERD: `Cluster`+`NaasContract` belongs_to ОДНІЄЇ org, forester ∈ org → org інтерналізує ризик власного оператора; `forester_share` 95% обчислюється-**не**-диспенситься, doc-ahead-of-code). Зʼявляється з **guild-маркетплейсом** (Модель B: незалежні foresters ≠ інвестори — E.20). Рекомендація (deep-audit 2026-06-16, founder-схвалено): **hybrid + guild-sponsor** waterfall (holdback→operator-bond→sponsor-bond→investor-excess); guild-sponsor = соціальна застава новачка. **Фаза 2** — будувати РАЗОМ з forester-payout (greenfield) + з guild (E.20); фаза 1 = positive-A-guard (SLASH-1 §3.2, зараз). Канон [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy); service-зв'язок `04_02 §Forester Guild`.
- [ ] 👤 DAO ratify (на Модель-B перехід): hybrid+guild-sponsor + параметри (bond-sizing / holdback-% / sponsor-cap / reputation-scaling)
- [ ] 🤖 після DAO + guild-маркетплейс E.20 — `OperatorBond` + `GuildSponsorship` + `ProtocolParameters` + `BlockchainBurningService` waterfall + escrow (reuse `Wallet#lock_funds!`) + синх `05_05 §3`/`05_03`/`04_02`

#### BIZ.4 — DAO Governance mainnet-активація (SilkenGovernor + Timelock)
- **P2** · 👤 · 🟢 · → `05_06`, `07_01`
- **Стан:** Контракти + backend готові-інертно (`SilkenGovernor.sol` + `SilkenTimelock.sol` + `ProtocolParameters.sol` + `Governance::ParameterSyncWorker` — має активний daily cron, але self-skips без `PROTOCOL_PARAMETERS_CONTRACT_ADDRESS` → реально no-op до mainnet-деплою — + `SystemParameter`, Foundry+RSpec-покрито) — чекають mainnet go-live + передачу влади. Канон [`05_06`](05_06_Governance_and_DAO), [`07_01`](07_01_Nature_as_a_Service_Contracts).
- [ ] 👤 mainnet deploy Governor/Timelock + Gnosis multisig council + transfer admin-ролей → Timelock (крім `pause`, E.2) + активація on-chain governance

#### E.60 — Merkle CID-witness: Polygon ↔ Filecoin integrity bridge
- **P2** · 🤖 · 🟢 · → `05_02 §E.60`
- **Стан:** Leaf-рівень закрито (2026-06-03) — `Filecoin::CidGenerator` (детермін. CIDv1 raw+sha2-256→base32, golden-vector) + content-CID guard: `ArchiveService` вбудовує самоописовий `content_cid`, `VerificationService` fail-fast при розбіжності → детект ex-post archive-swap. **Зшито з ARCH.12** (deep-audit 2026-06-28): E.60 `archive_root` (Polygon) ‖ ARCH.12 `state_root` (Eth L1) = **паралельні** якорі, спільний `MerkleTree` primitive + Z-leaf One-Home (sha256). ⚠️ наявний `VerificationService` **dead-in-prod** (0 prod-callerів — `FilecoinArchiveWorker` кличе лише `archive!`, ніколи `verify!` → guard не озброєний). Канон `05_02 §E.60`.
- [ ] 🤖 follow-on (deferred): per-tree Merkle-witness телеметрія-батчу (leaf_cid→`archive_root`→`mint(bytes32)`) — потребує `MerkleTree` (= ARCH.12 Фаза-1 primitive) + колонки на партиційованому `TelemetryLog` (міграція) + Solidity; worker-guard з `manual_review` у цьому батч-потоці
- [ ] 🤖 озброїти dead `VerificationService` (cron / on-read verify) — наразі content-CID guard збудований, але ніколи не викликається у проді

#### E.64 — bio→economy signal-coupling audit (E.63-лінза) [2026-06-08]
- **P2** · 🤖+👤 · 🟢 · → [`05_05 §7`](05_05_Slashing_and_Risk_Policy)
- **Стан:** E.63-лінза — окрім delta_t, решта bio→economy була слабка → виправлено: **anomaly ρ-відносна** (`z > ρ + (CRITICAL_Z_MAX−BASE_RHO)`, =45 при ρ=28 — ambient-temp більше не тригерить хибну аномалію) + **stress_index conformance** (Z-anomaly bounded ≪ slash-поріг «Z alone never slashes»; degenerate `avg_z`/weather-`temp` прибрано; `max_status` слешить лише tamper). Throughline: Лоренц-оракул здоров'я **декоративний** → реальна цінність = DCI anti-fraud (device-Z≡server-Z); здоров'я ведуть ПРЯМІ сигнали (metabolism E.63 · sap · VPD · acoustic). Нічого не задеплоєно → correctness перед деплоєм. Канон [`03_04 §4`](03_04_mruby_Lorenz_Attractor) · [`05_05 §7`](05_05_Slashing_and_Risk_Policy) · [`05_05 §8`](05_05_Slashing_and_Risk_Policy).
- [ ] 🔗 real-signal activation (sap/VPD/acoustic stress_index + per-species/season пороги) — ground-truth calibration (bench, [`08_02`](08_02_Academic_Institutions_Registry)). Cross-ref: E.63, FW.8, FW.50.

#### ARCH.45 — Money-path crash-window idempotency (intent-marker + in-flight guard)
- **P2** · 🤖 · 🟢 · → [`05_02`](05_02_Proof_of_Growth_Pipeline)
- **Стан:** Закрито — code + observability + canon + adversarial code-review hardening. **Аудит перевизначив проблему:** pending-tx stranding самозагоюється через cron (`mint_batch_collector` / `insurance_payout_recovery` / `tokenomics`), тож blanket `retries_exhausted`-handler НЕ потрібен; справжня діра — idempotency на **on-chain↔DB crash-window**, де cron-self-heal сам стає механізмом подвійної дії. 3 діри закрито durable intent-marker + in-flight reconcile guard (`in_flight` для burn / `unsettled_within` для Solana+Etherisc — дзеркало EthereumAnchor DOUBLE-ANCHOR): **Solana batch double-pay** (signature до broadcast + reconcile + confirm-gated Kredis-settle; `:not_found`→`manual_review` проти RPC-лаг re-pay), **burn double-burn** (intent перед slash ПІСЛЯ positive-A gate, не для freeze; ConfirmationWorker до breach), **Etherisc double-claim** (recovery `:pending`→`manual_review`, явний live-tx lookup). + observability: slash/payout success-rate SLO counters + `sidekiq_dead_set_size` gauge + Grafana DeadSet alert. `EvaluateTreeBatch` / `TokenomicsEvaluator` / `MintBatchCollector` — idempotent-safe / cron-recovered (підтверджено, без змін). **Policy (👤 DECIDED):** reconcile/escalate, НЕ re-attempt-наосліп; повний scope (code + observability + canon). **Патерн поширено за межі money-path (2026-07-02):** QATT uplink-nonce = двофазний owner-nonce, crash-retry resume (перший не-money різновид; дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), закриття → SE050-MIGRATION §03b). Канон [`04_02 §4/§10`](04_02_Business_Logic_and_Services) · [`05_02`](05_02_Proof_of_Growth_Pipeline) · [`06_03 §2.3`](06_03_Prometheus_Observability).
- [ ] 🤖 (nice-to-have) точніша Etherisc DIP claim-status звірка (`getClaim` ABI) замість conservative recovery-`manual_review`. (ToucanBridge-хвіст знято — E.66 prune → §🗄️.)
- [ ] 🤖 (nice-to-have) EVM-mint `:processing`-orphan reconcile: non-StandardError крах між `transact("mint")` і `mark_as_sent` лишає tx у `:processing` (on-chain minted, DB ніколи не `:confirmed`). Double-mint **неможливий** — усі mint-шляхи (`MintBatchCollector`/`MintCarbonCoinWorker`) фільтрують `status: :pending`, а orphan застрягає в `:processing` → ніхто його не re-mint-ить; тому це reconciliation/observability-залишок, НЕ втрата коштів (на відміну від burn, де intent-marker закриває вікно). Дзеркало Etherisc `getClaim`-звірки.
- [~] 🤖 Chainlink «double-request» seam (A9) — **досліджено (dig 2026-06-28), відкладено**: PATH 1 (oracle-callback) **unwired** у проді → збиток A9 = лише LINK-cost (double-mint відсічений controller atomic replay-guard `WHERE oracle_status='dispatched'`; загублений request_id → 404). Глибша trust-model (by-design оптимізм) + живі сиблінги (B1/B2/PuroEarth) винесено в **ARCH.53**; intent-marker фіксити КОЛИ замкнемо PATH 1.

#### ARCH.53 — Trust-model honesty: optimistic-mint + unwired oracle PATH 1
- **P2** · 🤖+👤 · 🟢 · → [`05_02`](05_02_Proof_of_Growth_Pipeline)
- **Стан:** Verify-by-data (2026-06-28, з ARCH.45-Chainlink нори): SCC мінтить **оптимістично** на `growth_points` — IoTeX/Chainlink НЕ enforced на живому tokenomics-шляху (PATH 2 guard-free); єдиний gated PATH 1 oracle-callback **unwired** (нема DON source/consumer/relayer; tx_hash≠requestId). **By-design** (anti-fraud = ex-post clawback, не pre-mint-gate — E.63; clawback unbuilt → ARCH.12 + SE050-MIGRATION; trust-origin L0 / L1-soft-marker / L2-North-Star), але канон переобіцяв «trustless oracle-verified mint» + суперечив сам собі → **виправлено до чесної моделі довіри**: [`05_02`](05_02_Proof_of_Growth_Pipeline) (модель довіри + DOC.7) · [`05_01`](05_01_Multichain_Architecture) (Chainlink-unwired) · [`05_03`](05_03_Tokenomics_SCC_and_SFC) · [`04_02`](04_02_Business_Logic_and_Services) (Принципи Безпеки + enqueue-after-commit таксономія). **B2/PuroEarth/B1 seam-родина SHIPPED+green** (reorder / idempotency-guard / smart-guard; код+spec+git). **ДЕМОУТ ВИКОНАНО (2026-07-04, founder-рішення 07-03):** on-chain `sendRequest` вилучено (сервіс = local correlation-marker, guard-тест «жодного RPC»; `Web3::ChainlinkRouterVersion` S6.15-registry видалено з git-воскресінням; dispatch-секрети `ROUTER`/`SUBSCRIPTION_ID`/`DON_ID`/`DATA_VERSION`/`GAS_LIMIT` зрізані з Kamal+Akash SDL+Terraform — лишився `CHAINLINK_HMAC_SECRET` callback-endpoint'а); `chainlink_request_id` колонка ЖИВЕ чесно як internal dedup-ключ (Solana ARCH.51 + idempotency-guard'и — прибрати неможливо, брехню tx_hash-as-requestId знято разом з on-chain гілкою); юзер-хроніка «Verified by Chainlink Oracle» → чесний mint-текст; Chainlink знято з 🔴 Critical-Path у `05_01 §8` (+§8.3 verify-by-data: «TreasuryMonitorWorker моніторить LINK-subscription» був claim без коду). Канон-reframe: `05_01` (стек-таблиця · картка №11 · Крок 5 · ENV · матриця · §8) + `05_02` (Крок C/D + PATH 1-рамка + ENV) + `04_02` + `04_03` + `06_01`/`06_02`/`06_04`. Замкнути PATH 1 відкинуто (DON-інженерія при TRL-3 передчасна); callback-endpoint live для майбутнього PATH 1 / manual-fulfillment. Відкрите ↓.
- [ ] 🤖 (residual, low) crash-recovery hardening: B1 retry-exhaustion (>5 retry → Dead Set, recovery-крони нема; рідко + PATH 1 latent); true-concurrency double-slash — `BurnCarbonTokensWorker` без `unique_for`, in_flight `unsettled_within` guard не атомарний з intent-creation (TOCTOU; Kredis lock серіалізує on-chain, не ре-чекає) → partial-unique-index `(sourceable, unsettled)` АБО worker `unique_for`. Pre-existing ARCH.45 gap; reorder/smart-guard re-enqueue покладається на sequential in_flight (типовий випадок безпечний)
- [ ] 🤖 A9 Chainlink double-request intent-marker — КОЛИ PATH 1 замкнено (зараз latent: dispatch локальний, LINK-cost знято демоутом)

#### ARCH.52 — Money-path scale-death @ 100B дерев: queue-starvation + partition-scan hot-paths
- **P2** · 🤖+👤 · 🟢 · → [`05_02`](05_02_Proof_of_Growth_Pipeline)
- **Стан:** Code-half SHIPPED (2026-06-28); живий 👤-residual = deploy-flip (НЕ горить — TRL-3). Канон scale-hardening → [`06_08 §2.5`](06_08_Resilience_and_Failover_Policy)/[`§2.6`](06_08_Resilience_and_Failover_Policy). **(1) Queue-starvation** канонізовано як deploy-рішення [`06_08 §2.5`](06_08_Resilience_and_Failover_Policy): виділений money-path Sidekiq-процес поза uplink-strict-ланцюгом (strict ізолює лише В МЕЖАХ процесу — money-черги нижче за `uplink`-firehose голодують; weighted-черги відкинуто) + sidekiq.yml коментар-фікс. **(2) Partition-scan hot-paths** — `BlockchainConfirmationWorker` `created_at_iso` lower-bound (7 enqueue, дзеркало ARCH.50) + partial index `index_blockchain_transactions_in_flight` для pending-discovery; scope + свідомі skip'и (#3 PK-served, #4/#5 unprunable all-time aggregates, чому partial-index-а-не-created_at-вікно для reset-to-pending) → [`06_08 §2.6`](06_08_Resilience_and_Failover_Policy). [ARCH.12] майбутній weekly Merkle = ще один partition-scan hot-path (ієрархічний обов'язковий).
- [ ] 👤 deploy-flip на виділений money-path процес — КОЛИ uplink-firehose / mint-SLO breach (не зараз; TRL-3)
- [ ] 🤖 (NICE, scale-time) bench: EXPLAIN partition-elimination на hot-path запитах (потребує даних — RUNBOOK)

#### ARCH.12 — Merkle Tree state-root (partial verification / ISO 14064 / L2 device-voice foundation)
- **P2** · 🤖+👤 · 🔗 · → [`05_04`](05_04_Ethereum_L1_State_Anchor)
- **Стан:** Підвищено з backlog-рядка (deep-audit 2026-06-28). **Дві осі, не три задачі:** ARCH.12 (структура кореня) + [E.60] follow-on — обидва будують Merkle над per-record телеметрія-листям; спільний відсутній блок = Ruby `MerkleTree` primitive. Реальний сенс — носій **true-DePIN L2 «голос дерева»** ([`05_02`](05_02_Proof_of_Growth_Pipeline) trust-origin ladder + SE050-MIGRATION): 21-Б LoRa-кадр не вміщає Ed25519-підпис → періодичний Merkle-корінь амортизує підпис на багато записів. **4 рішення (founder-схвалено, Фаза 0 канонізовано):** (1) E.60 `archive_root` (Polygon) ‖ `state_root` (Eth L1) = **паралельні** якорі, спільний примітив; (2) **leaf=Z** (не λ — Beyond-TRL-9); (3) **hash=sha256** (+keccak upgrade-path); (4) примітив **ієрархічний** (cluster-subtree→root, мапиться L1/L2/L3). aggregate-хеш = `leaves[0]` → контракт `storeStateRoot(bytes32)` НЕ міняється. **Vacuity-чесність:** prod-споживача inclusion-proof немає (API/UI/subgraph/ISO-звіт — нуль; навіть E.60 `VerificationService` 0 prod-callerів) → примітив будувати з ПЕРШИМ споживачем, не раніше. Канон [`05_04`](05_04_Ethereum_L1_State_Anchor) §Merkle (drift-fix: `TelemetryLog.chain_hash` не існує) + leaf One-Home [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline) + L2 clawback [`05_05 §3.3`](05_05_Slashing_and_Risk_Policy). Cross-ref: E.60, ARCH.13 (окрема транспорт-вісь), SE050-MIGRATION (L2 device-voice), ARCH.52 (scale).
- [ ] 🤖 Фаза 1 (з першим споживачем): `MerkleTree` primitive (sha256, RFC-6962 domain-sep, ієрархічний, golden-vector) + застосування до L1 state-anchor та E.60 `archive_root` (озброєння dead `VerificationService` — дім E.60)

#### ARCH.13 — EigenLayer AVS як дешевша L1-anchor альтернатива
- **P3** · 🤖 · 🌿 · → `05_04`
- **Стан:** Scale-time cost-opt (research): EigenLayer AVS (~$0.01/тиждень) замість direct L1 write (~$5-15/тиждень) для weekly `StateRootAnchor`. **Чесна рамка:** при 1 tx/тиждень ($5-15 ≈ $260-780/рік) economics не тисне, а AVS = реальна operational-складність (operators/slashing/restaked-ETH security) → виграш на scale/gas-spikes, не на launch; direct-L1 лишається baseline. **Ортогональна вісь до ARCH.12** (deep-audit 2026-06-28): ARCH.13 = *транспорт* кореня (куди писати: direct-L1 vs AVS), ARCH.12 = *структура* кореня (що комітить: flat vs Merkle) — дві незалежні осі, не змішувати в одну роботу. Канон [`05_04`](05_04_Ethereum_L1_State_Anchor).
- [ ] 🤖 оцінити AVS feasibility + security перед mainnet anchor-arch lock-in (low urgency)

## §06 · Deploy / Observability / Secrets / Ops

> Деплой, спостережуваність, секрети, DR — канон `06_xx`.

#### S1.1 — GitHub Secrets заповнення
- **P0** · 👤 · 🟢 · → `06_04`
- **Стан:** Checklist + інвентаризація 4 місць секретів готові. **[B1/INF.19]** CI Kamal deploy тепер мапить увесь `env.secret` набір → GitHub Secrets = P0 (`§1.1`) + Web3/runtime (`§1.4`). Лишається заповнити. Канон `06_04`.
- [ ] 👤 заповнити GitHub repository secrets (повний набір — `06_04 §1.1` + §1.4) → верифікувати CI

#### S2.1 — Верифікація метрик після deploy
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** `/metrics` (реєстр — `06_03 §2.8`) + Alloy sidecar → Grafana Cloud налаштовано; з 2026-07-04 таргетів ТРИ (web/job/coap — multi-process топологія `06_03 §2.9`); чекає першого Akash deploy для верифікації збору.
- [ ] 👤 верифікувати збір метрик після першого Akash deploy (усі 3 `process`-таргети живі; job-метрики ≠ нулі)

#### S2.2 — Grafana Cloud dashboards
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** dashboard IaC готовий (`deploy/grafana/dashboards/`, секції/панелі — `deploy/grafana/README.md`).
- [ ] 👤 імпортувати у Grafana Cloud (інструкції `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** · 👤 · 🟢 · → `06_03`
- **Стан:** alert rules IaC готові (`deploy/grafana/alerts/silkennet-alerts.yaml`, P0/P1/P2; зведення `deploy/grafana/README.md`) + counter `silkennet_telemetry_acoustic_overflow_total`.
- [ ] 👤 замінити `${DATASOURCE_UID}` + notification channel (Email/PagerDuty)

#### INF.16 — Production multi-DB connection (database.yml component style)
- **P0** · 👤 · 🟢 · → `06_01`, `06_04`
- **Стан:** Machine-half ✅ — **корінь first-deploy fail.** Production `database.yml` давав host+creds лише `primary` (Rails ллє `DATABASE_URL` тільки в primary); `cache`/`queue`/`cable` лишались без host і пароля → `db:prepare` падав на першому web-boot, Solid Cache/Cable не конектились. Fix = Rails-8 component style: `POSTGRES_HOST/USER/PASSWORD` у `&default` (як dev/test), бази набору ділять creds (з INF.18-prune — 3: primary/cache/cable), override лише `database:`. Deploy мігровано `DATABASE_URL`→`POSTGRES_*` (Kamal env.secret/clear + `.kamal/secrets` + Akash web/job + `.tpl` + terraform akash + CI workflows). Canopy ізоляція через `POSTGRES_DATABASE=silken_net_canopy` (той самий інстанс). `terraform fmt` clean; config-resolve verified (prod + canopy набори). Канон `config/database.yml` + `06_04`.
- [x] 🤖 tf-ресурси canopy-баз ✅ 2026-07-04 — `database.tf` canopy-тріо (`silken_net_canopy` + `_cache`/`_cable`; queue-бази зняті INF.18-prune'ом, той самий інстанс)
- [ ] 👤 `terraform apply` canopy-баз при провіжні (ресурси готові, лишається apply)
- [ ] 👤 верифікувати `db:prepare` проходить усі 3 бази набору на першому деплої

#### INF.19 — CI Kamal secret-starvation (env-mapping) + KREDIS/POSTGRES drift [B1/H2]
- **P0** · 👤 · 🟢 · → `06_04 §1`
- **Стан:** Machine-half ✅ (commit `c3ed3019` + canon `06_04 §1.4`) — **корінь, чому перший deploy ніколи не виживав** (pre-deploy consistency audit, 8-agent). Обидва deploy-workflow передавали в `kamal deploy` лише 5 із 24 секретів; `.kamal/secrets` читає всі 24 з shell-ENV → решта інжектились порожніми → boot-crash (`RAILS_MASTER_KEY` decrypt / `PROVISIONING_MASTER_KEY` guard / oracle KeyError) або web3-strict raise. `verify-secrets` перевіряв лише 1-2 → зелений CI над зламаним деплоєм (без секретів `configured=false` → skip → шлях ніколи не біг live, тож діра не спливала). Fix: повний env-mapping в обидва workflow + `verify-secrets` гейтить повний boot-critical набір (fail-loud prod / skip-clean canopy) + warn на lazy. Супутнє: `KREDIS_REDIS_URL` виведено з усіх deploy-surface (auto-derive DB 1 з `REDIS_URL`); `RAILS_MASTER_KEY` ENV-first; H2 — Akash explicit `POSTGRES_DATABASE`. Канон `06_04 §1.4` + drift-guard.
- [ ] 👤 завести повний deploy-secret набір у GitHub Secrets (`06_04 §1.1` + §1.4) → верифікувати fail-loud `verify-secrets` + boot на першому деплої

#### INF.6 — CoAP UDP smoke test через Ingress Anchor (post-deploy gate)
- **P1** · 👤 · 🟢 · → `06_01`, `06_02`, `06_08 §1.2`
- **Стан:** UDP-smoke gate проти silent CoAP-failure (Queen→Ingress Anchor: PRIMARY-демон на анкорі / fallback socat→Akash) — workflow `coap_smoke.yml` (`workflow_dispatch`+`workflow_call`+**`schedule` кожні 30хв** — безперервний liveness анкора-SPOF, S2.4 2026-07-04); зонди = freeze-contract `bin/coap_smoke`/`lib/coap_smoke.rb` (точні байти, регресія фантомної доставки FW.56); виклик = post-deploy gate у `deploy.yml`+`deploy-production.yml` (job `coap-smoke`, `needs: deploy`); поки repo Variable host не задана — job skipped (не silent, notice-крок).
- [ ] 👤 задати repo Variables `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` коли Ingress Anchor існує → gate активний
- [ ] 👤 перший boundary smoke з Queen/`bin/forest_simulator`

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** · 🤖+👤 · 🟢 · → `06_02 §TLS термінація`
- **Стан:** ✅ **Рішення прийнято (founder 2026-07-03): Опція A — Cloudflare Proxy** (HTTPS:443 termination + direct UDP CoAP через Ingress Anchor; публічний домен `silkennet.app`). Cloudflare НЕ proxies UDP → CoAP окремим шляхом (уже в архітектурі). Розблоковує `INF.3` (TLS = Cloudflare) + `S6.18` (`RAILS_ALLOWED_HOSTS=silkennet.app`). Fallback B (Akash hostname + Let's Encrypt, домен `silkennet.com`) — лише якщо Cloudflare недоступний. Канон `06_02 §TLS термінація`.
- [ ] 👤 при деплої: Cloudflare pre-flight (9 кроків `06_02` Опція A) — акаунт/домен/Full-strict SSL/CNAME→Akash ingress/Queens на Ingress-IP:5683
- [ ] 🤖 (лише якщо fallback B) Akash hostname-operator automation `terraform/akash/hostname-operator.tf`
- [ ] 🔗 CNAME-origin lease-прив'язаний (re-lease/failover = ручний CF-крок; канонізовано `06_02` §Automation note 2026-07-04) → автоматизація (CF API/terraform) лише коли multi-provider failover стане живим

#### S6.18 — Rails web security hardening
- **P1** · 👤 · 🟢 · → `06_04 §2.1`
- **Стан:** Код готовий — production.rb (force_ssl/HSTS + host-auth з probe-exclusions `/up`/`/ready`/`/metrics`) + CSP (report-only) + security_headers.rb + session_store. `RAILS_ALLOWED_HOSTS` значення свідомо НЕ закомічено (на відміну від `APP_HOST`/`WEB3_STRICT_MODE`): порожнє → warn-and-allow (degraded, не fatal), а закомічене **неправильне** → 403 block-all. Публічний домен зафіксовано INF.4 (Опція A Cloudflare, 07-03) = **`silkennet.app`**; operator-set перед prod. Канон `06_04 §2.1`.
- [ ] 👤 `RAILS_ALLOWED_HOSTS=silkennet.app` у Kamal/Akash env.clear при деплої — інакше 403 block-all
- [ ] 👤 після 1-2 тиж CSP-репортів → `CSP_ENFORCE=true`

#### DR.1 — Disaster Recovery drill + master-key backup
- **P1** · 👤 · 🟢 · → `06_06`
- **Стан:** DR-постуру задокументовано (`06_06`): Cloud SQL PITR + REGIONAL HA + 30×daily + restore-runbook'и + RTO/RPO.
- [ ] 👤 quarterly DR-drill (PITR-clone + TF-state rollback на staging, зафіксувати факт. RTO/RPO vs цілі)
- [ ] 👤 master-ключі (`RAILS_MASTER_KEY`/`PROVISIONING_MASTER_KEY`) → vault + offline-копія (незамінні, поза backup)

#### INF.11 — `WEB3_STRICT_MODE` у deploy-конфігах (KYC fail-closed)
- **P1** · 👤 · 🟢 · → `06_04`
- **Стан:** Machine-half ✅ — `WEB3_STRICT_MODE="true"` заведено в `config/deploy.yml` env.clear + Akash `deploy.yaml`/`deploy.yaml.tpl` (web+job); canopy успадковує (Kamal `deploy.canopy.yml` env-less; canopy = `RAILS_ENV=production` → strict скрізь консистентно). `.kamal/secrets` НЕ чіпано (non-secret). Закриває READ-verified діру: Hadron KYC/RWA + oracle-callback HMAC (SEC.5) перевіряють ЛИШЕ `WEB3_STRICT_MODE=="true"` (не `Rails.env`) → без прапора відсутній credential тихо падав у `simulate_*` (fake-KYC mint). (Chainlink-dispatch вибув зі STRICT-скоупу — ARCH.53 демоут: local marker без credentials.) Канон-інвентар синхронізовано: `06_04 §2.1` · `06_02 §2.8/§6`. Лишається 👤 (deploy-gated). Канон `06_04 §2.1`.
- [ ] 👤 money-path рішення + верифікувати fail-closed на першому деплої

#### INF.12 — Deploy ENV-injection drift: код `ENV.fetch` без default ∉ deploy-декларації
- **P1** · 👤 · 🟢 · → `06_04`
- **Стан:** Machine-half ✅ — set-diff `ENV.fetch`/`credentials.dig` vs deploy закрито: 10 контракт-адрес + `POLYGON_RPC_URL`/`CELO_RPC_URL` заведено в Kamal + Akash web/job (контракт-адреси = `REQUIRED_SECRET_NOT_SET` placeholder, deploy-order → не terraform-vars); `06_04 §2.2` +`aws`/`gcs`. ⚠️ `CELO_RPC_URL` порожній → fallback Alfajores TESTNET (обходить `web3_network_guard`; E.49) → mainnet обов'язковий. Інвентар — [`06_04 §2.1`](06_04_Secrets_Checklist).
- [ ] 👤 fill contract addresses post-`forge deploy` + provision RPC / secrets

#### INF.15 — Terraform GCP `apply`-блокери (IAM ролі · firewall · tfvars · image-path)
- **P1** · 👤 · 🟢 · → `06_01`
- **Стан:** Machine-half ✅ — `iam.tf` +`storage.objectAdmin`(scoped до state-bucket)+`iam.serviceAccountUser`; firewall `allow_ssh` `count`-guard на порожній CIDR (GCP не відхиляє apply); `tfvars.example` CIDR-placeholder (не `0.0.0.0/0`); Kamal `image`→повний AR-шлях. `terraform fmt` clean, count-safe. ⚠️ provider/Kamal-behavior inferred → 👤 verify на реальному apply. Канон [`06_01`](06_01_Deployment_Kamal_Terraform).
- [ ] 👤 верифікувати `terraform apply` + Kamal push end-to-end (підтвердити inferred-пункти)

#### S4.3 — Akash SDL secrets
- **P1** · 👤 · ⚪ · → `06_02`
- **Стан:** Не розпочато — Akash = primary prod deploy → SDL (`deploy/akash/deploy.yaml`) тримає `REQUIRED_SECRET_NOT_SET` плейсхолдери (сервіси web+job+coap; **з 2026-07-04 signing-п'ятірка `ORACLE_*`×3+`ETHEREUM_ANCHOR`+`SOLANA_WALLET_KEYPAIR` = job-only** — web/coap keyless by design, `06_04 §1.1`); без них boot-crash (категорія A) — той самий prod-deploy-ENV клас, що `S1.1`. ⚠️ placeholder ≠ disabled: `REQUIRED_SECRET_NOT_SET` для `PROMETHEUS_AUTH_*` НЕ-порожній → basic-auth активна з відомим-публічним значенням (`PrometheusCollector#authorized?`), а Alloy remote_write на літерал → тихо нічого не пушить (INF.14 sibling). **B6 рекомендація:** provision реальні random `PROMETHEUS_AUTH_USER/PASSWORD` (НЕ placeholder — `REQUIRED_SECRET_NOT_SET` непорожній = known-value bypass); порожнє → skip-auth + IP-allowlist (прийнятно для internal-only Alloy scrape, але реальні creds = defense-in-depth). Канон `06_02 §2` (категорії A/B/C — boot-critical / web3 / observability) + `06_03`.
- [ ] 👤 заповнити в `deploy/akash/deploy.yaml` → верифікувати startup (real `PROMETHEUS_AUTH_*`, не placeholder; observability creds = security)
- [ ] 👤 **перший Akash-деплой = canopy-render** (founder 2026-07-04): `terraform apply -var deployment_slot=canopy -var postgres_database=silken_net_canopy` → smoke → лише потім production-render (чеклист `06_01` крок 11)

#### ARCH.54 — Queen health program: dead-man switch · QATT-v2 пульс · SOS-роздільність
- **P1** · 🤖+👤 · 🟢 · → [`06_08 §1.3`](06_08_Resilience_and_Failover_Policy), [`03_02 §7`](03_02_Queen_Gateway_Firmware), [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)
- **Стан:** Рішення №1 founder-пакета (2026-07-03: «A + 12B SOS-only + всі три шари») — **machine-half трьох шарів ✅ одним заходом**. Діагноз, що змінив рамку: DID=0-канал брехав байтами (uptime→voltage, cache→CSQ, дроп під навантаженням; циркулярний e2e), алерту «Королева мовчить» не існувало ніде, а `06_08 §1.3` описував бажане як факт. **Шар 0** — `GatewayStalenessSweepWorker` (offline→`report_fault!`+`EwsAlert(queen_offline)` анти-спам; online→`recover!`+auto-resolve; attest-lapse читає `last_attested_at`; gauge+P0-Grafana). **Шар 1** — пульс у ПІДПИСАНОМУ QATT-**v2** header'і (8B health; v1 вилучено повністю — redefine, бо флоту нема; residue 1, `SLKN-QATT2`; empty-flush heartbeat; DID=0-тракт вбитий обабіч; CSQ = нове AT-читання; golden-парність 4 реалізацій). **Шар 2** — ARCH.34 backend-half (дім деталей там). Закрив FW.2-фліп-гейт (б) by design. Канони переписані на факт (06_08 §1.2/§1.3 · 03_02 §7 · 03_05 §2.2 · 02_05 §6.1 · 04_03 · 06_04).
- [ ] 👤 Grafana Cloud: `deploy/grafana/import.rb` підхопить `sn-alert-gateway-faulty` разом з існуючим пакетом правил (та сама 👤-сесія, що FW.18b/S2.2)
- [ ] 🔗 attest-lapse: окремий alert-тип замість warn-метрики — коли L1 QATT стане mandatory (зараз L0 приймається; свідома стеля)
- [ ] 🔗 vcap/температура Королеви у health-блоці — при ADC-тракті на платі (wire має headroom: rsv-байти конверта; не брешемо нулями до заліза)
- [ ] 🌿 DePIN-місток: підписана health-історія = evidence для operator-bond/uptime-SLA (BIZ.13; не блокер)

#### INF.17 — CoAP daemon prod-процес (Queen telemetry intake)
- **P2** · 👤 · 🟢 · → `06_01`, `06_02 §1.4`, `03_02 §4`
- **Стан:** ✅ **Machine-half 2026-07-04.** Akash `coap`-сервіс (той самий образ, entrypoint→`lib/daemons/coap_listener`, boot-critical env-підмножина без money-ключів, 0.5 CPU/1 Gi; expose 5683/udp global + 9395 service-scope для Alloy) + Kamal `coap`-роль (`options.publish "5683:5683/udp"` — kamal-proxy UDP НЕ проксіює, UDP знято з `boot.proxy.publish`) + `.tpl`-дзеркало + **CI-гейт `scripts/sdl_consistency_check.rb`** (services≡deployment, static≡tpl — клас «оголошено, не залізовано» більше не повертається). 5683 **перенесено з web** (там була чорна діра — Thruster/Puma UDP не слухають). Демон: NOT-puma-thread (B7 підтверджено), embedded /metrics 9395 + лічильники межі (`enqueued`/`malformed`/`unknown_route`/`oversized` — kernel-трункейт більше не маскується під MIC-fraud) → [`06_03 §2.9`](06_03_Prometheus_Observability). Live-verified: boot-банер + graceful TERM + реальний scrape (176 серій). **Ре-гейт:** НЕ «на Queen-bring-up» — слухач потрібен на першому деплої (INF.6 smoke-зонди чекають байт-точних відповідей; без слухача gate валить пайплайн). **PRIMARY = демон на Ingress Anchor (founder-go 2026-07-04):** `compute.tf` — docker + systemd `coap-daemon` (той самий образ, `--network host`; VPC → Cloud SQL приватним IP БЕЗ Auth Proxy; секрети НЕ в metadata — `/etc/silkennet/coap.env` 0600 placeholder), bring-up пріоритет daemon (env заповнений) → socat-fallback (`AKASH_IP` set) → гучний warn; анкор e2-micro→e2-small (Rails-демон ~0.5 GB), диск 10→20 GB; Akash `coap`-сервіс лишається задеплоєним fallback'ом (перемикання = 2×systemctl). Стеля observability анкор-демона → [`06_03 §2.9`](06_03_Prometheus_Observability)(б).
- [ ] 👤 заповнити `/etc/silkennet/coap.env` на анкорі (POSTGRES_PASSWORD/REDIS_URL/RAILS_MASTER_KEY/PROVISIONING_MASTER_KEY/SENTRY_DSN) → `systemctl restart coap-daemon` → `coap_smoke` зелений
- [ ] 👤 верифікувати fallback-перемикання один раз (stop coap-daemon → start coap-relay → smoke все ще зелений через Akash-сервіс)

#### S6.14 — peaq_signing_key: rotation & revocation
- **P2** · 👤 · 🟢 · → `06_04 §5.4`, `04_02 §S6.14`
- **Стан:** Rotation policy готова — dual-key grace 72h + планова ротація 90д + emergency revocation runbook. Лишається vault-store production-ключа. Канон `06_04 §5.4` (revocation runbook) · `04_02 §S6.14` (policy + код-стан).
- [ ] 👤 vault-store production `peaq_signing_key`

#### S1.5 — Kamal IP placeholders
- **P2** · 👤 · ⚪ · → `06_01`
- **Стан:** Не розпочато — `192.168.0.1` (`config/deploy.yml`) / `<INGRESS_ANCHOR_IP>` (`config/deploy.canopy.yml`) плейсхолдери; підставити реальну Ingress Anchor IP після `terraform apply` (canopy = той самий IP, диференціюється Akash SDL env). ⚠️ той самий клас: Ingress Anchor metadata `akash-deployment-ip="AKASH_IP_NOT_SET"` → HAProxy 80/443 black-hole поки руками не оновиш + reset (з INF.17 anchor-primary metadata живить лише HTTP/S + socat-**fallback**; primary CoAP-демон від неї НЕ залежить — обидва стартап-гейти тепер sentinel-guarded, гучний logger замість тихого нестарту); нема автоматичного glue `terraform output -raw ingress_ip` → config/CI, крок лише в code-коментарі. Канон `06_01`.
- [ ] 👤 підставити реальні IP після `terraform apply` → верифікувати deploy (крок = Pre-Flight #9 `06_01` ✅ внесено 2026-07-04)
- [ ] 👤 оновити Ingress Anchor `akash-deployment-ip` metadata після Akash deploy (крок = Pre-Flight #10 `06_01` ✅ внесено; живить HTTP/S + socat-fallback, PRIMARY-демон не залежить)

#### S2.4 — Observability industrial-grade hardening
- **P2** · 👤 · 🟢 · → [`06_03 §2.9`](06_03_Prometheus_Observability)
- **Стан:** industrial-grade hardening канонізовано — `external_labels` (env/service/source/release attribution) + `queue_config`+explicit WAL (backpressure) + cardinality-budget relabel + process/runtime gauges (`sample_process_runtime!`/`sample_connection_pool!`, RSpec-covered; bonus-fix: pool-gauges раніше були stale) + CI-валідація (`alloy_config_validate`). **IaC-half §2.9 #5/#6 ✅ 2026-07-04:** `sn-alert-scrape-target-down` (per-process `min by (process) (up)` — 3 таргети, NoData→Alerting = сам Alloy впав) + `sn-alert-mint-slo-breach` (<0.8/1h, канон-ціль `06_08 §2.4`; PromQL-guard `and attempts>0` — тихий ліс ≠ breach) + dashboards `silkennet-overview.json` пройдено під 3-таргетну топологію (histogram_quantile → `sum by (le)`, голі counters → `sum(rate)`, ratio → `sum/sum`) + `sn-alert-gateway-faulty` перенесено p2-info→p0-critical (жив у неправильній групі) + smoke-schedule (`coap_smoke.yml` кожні 30хв — безперервний UDP-liveness анкора, skip-clean без Variables). Конкретні значення — `config.alloy`/`silkennet-alerts.yaml` SSOT. Канон [`06_03 §2.9`](06_03_Prometheus_Observability).
- [ ] 👤 імпорт у Grafana Cloud (`deploy/grafana/import.rb` — та сама сесія, що S2.2/S2.3) → верифікувати up-alert бачить 3 process-таргети
- [ ] 👤 SLO-пороги slash/payout/insurance — калібрувати з перших live-вікон (канон цілі поки має лише mint ≥80%; не вигадуємо)

#### INF.3 — TLS termination
- **P2** · 👤 · 🟢 · → `06_02 §TLS термінація`
- **Стан:** Розблоковано — INF.4 вирішено (Опція A Cloudflare, founder 07-03) → TLS = **Cloudflare Full-strict termination** (HTTPS:443) + direct UDP CoAP через Ingress Anchor. SDL відкриває 80/443/CoAP-UDP 5683; лишається налаштувати Cloudflare при деплої (разом з INF.4 pre-flight). Канон `06_02 §TLS термінація`.
- [ ] 👤 налаштувати Cloudflare TLS termination при деплої (INF.4 pre-flight крок)

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** · 👤 · 🟢 · → `06_03`
- **Стан:** Kamal — `env.clear` `${RELEASE_VERSION}` з CI ✅. Akash static SDL — рядок **свідомо ВІДСУТНІЙ** (2026-07-04, B1-клас: порожній-присутній ключ глушить Sentry-autodetect) → інжект реального git-SHA при деплої через Console; `.tpl` — умовний `%{ if }` + tf-var `release_version` (порожньо = рядок омітиться). Канон `06_03`.
- [ ] 👤 верифікувати Sentry release tracking (Kamal-шлях авто; Akash — після інжекту значення при деплої)

#### PUMA-IPV6-1 — Верифікація IPv6 bind після першого Kamal-деплою
- **P2** · 👤 · 🟢 · → `06_05`
- **Стан:** Конфіг готовий — Puma 8 bind `[::]:3000` dual-stack (default), Thruster → `127.0.0.1:3000`; лишається верифікувати IPv6 bind після першого Kamal-деплою. Канон `06_05`.
- [ ] 👤 після canopy deploy: `ss -tlnp\|grep 3000` (`tcp6 [::]:3000`) + `curl` v4/v6 `/up` → задокументувати у `06_05`

#### ARCH.35 — Queen Flash Ring Buffer (W25Q32 overflow tier)
- **P2** · 👤 · 🟢 · → `06_08 §1.2`, `02_05 §2.1`
- **Стан:** CIFO RAM-cache overflow tier → SPI NOR W25Q32 sector-ring (дизайн — capacity-math, in-band headers vs RTC, mount-scan recovery, power-cut-safe — `02_05 §2.1`; failover-роль L1 `06_08 §1.2`). Драйвер `firmware/common/flash_ring.{h,c}` host-tested; Queen-глю gated `ARCH35_RING_ENABLED 0`.
- [ ] 👤 W25Q32 розводка (SPI + CS-пін, board-freeze `.ioc`) + bench SPI-глю → фліп `ARCH35_RING_ENABLED 1`

#### ARCH.34 — Queen-side LoRaWAN Helium SOS fallback
- **P2** · 🤖+👤 · 🟡 · → [`06_08 §1.2`](06_08_Resilience_and_Failover_Policy), [`02_05 §6.1`](02_05_Queen_Hardware_and_Starlink)
- **Стан:** **Backend-half ✅ (2026-07-03, пакет ARCH.54):** `POST /api/v1/telemetry/helium` (`HeliumSosController`, HMAC `X-Helium-Signature` — SEC.5-патерн oracle_callbacks + Rack::Attack 30/хв) → `HeliumSosWorker` (черга alerts: 12B-wire parse, подвійна ідентичність `helium_dev_eui`↔`queen_did`-у-кадрі, ідемпотентний `EwsAlert(queen_uplink_lost)` + негайний `report_fault!`) — специ 15/15. **Wire 12B заморожено** (📐 One-Home [`06_08 §1.2`](06_08_Resilience_and_Failover_Policy)); канон-конфлікт lambda-summary vs SOS-only розрубано на SOS-only (рішення 2026-07-03; `02_05 §6.1` вичищено). Firmware-half лишається: LoRaMac-node (~30KB) + OTAA + FCntUp persist + radio-blindness hard-rule (`02_05 §6.1`).
- [ ] 🤖 Queen `queen_helium_lorawan_uplink()` — LoRaMac-node інтеграція (важка; після/разом з FW.46 board-freeze — той самий middleware-клас, що SubGHz_Phy)
- [ ] 👤 Helium Console: реєстрація Королев (DevEUI/AppEUI/AppKey) + HTTP Integration (URL + `HELIUM_WEBHOOK_SECRET` — [`06_04`](06_04_Secrets_Checklist)) + заповнити `gateways.helium_dev_eui`
- [ ] 🔗 `GatewayLoraWanCredentials` (AppKey, AR Encryption) — при живій Console-інтеграції (зараз YAGNI: інтейку досить dev_eui)

#### INF.13 — Deploy runtime config-баги (mailer host · DB pool · entrypoint · Canopy job)
- **P2** · 👤 · 🟢 · → `06_05`
- **Стан:** Machine-half ✅ — (1) mailer host `example.com` → `ENV.fetch("APP_HOST", "silkennet.com")`+https (`production.rb`), `APP_HOST` заведено в Kamal `env.clear` + Akash web/job; (2) `DB_POOL=17` для Sidekiq/job-ролі (Kamal job-env + Akash job; web лишається default-pool); (3) entrypoint Cloud-SQL-proxy readiness → fail-loud (`exit 1`, не тихий boot без БД); (4) Canopy задокументовано web-only-by-design (Sidekiq через Akash primary, не відсутня `job:`-секція). Чекає верифікації на першому реальному деплої. Канон `06_05`.
- [ ] 👤 верифікувати на першому деплої (mailer host · `DB_POOL` · entrypoint fail-loud · Canopy web-only)

#### INF.14 — Observability pipeline wiring: метрики/алерти не «доїдуть»
- **P2** · 👤 · 🟢 · → `06_03`
- **Стан:** Machine-half ✅ — (1) circuit-breaker alert поріг `gt 1`→`gt 0` (gauge=`1.0` при open через `set_circuit_breaker_gauge`; `gt 1` ніколи не firing) + коментар проти регресії; (2) `grafana/alloy` запінено `:latest`→`v1.16.3` (`deploy.yaml`/`.tpl`/`ci.yml` — CI валідує ту саму River-версію, що біжить); (3) знято stale `gaia2`-tag (BIZ.16 dissolved); (4) **2026-07-04: internal routes + multi-process scrape ✅** — web:80 `- service: alloy` (закрито ingress-403), job:9394/coap:9395 service-scope, три таргети з `process`-лейблом, embedded-експортери (`SilkenNet::MetricsExporter`), `refresh_sidekiq_gauges if Sidekiq.server?` проти потрійних серій, `DEPLOYMENT_SLOT` external-label (canopy≢production у Grafana). До цього **всі** job-інкрементовані метрики (money-path SLO, CCM/QATT-security, dead-man switch) були вічними нулями web-процесу — жоден P0-алерт не міг спрацювати. Дім механіки [`06_03 §2.9`](06_03_Prometheus_Observability). Канон `06_03`.
- [ ] 👤 верифікувати scrape ТРЬОХ таргетів на деплої (web:80 · job:9394 · coap:9395; `sum by (process)`)

#### INF.10 — Kamal-proxy healthcheck → `/ready` (readiness-gated cutover)
- **P3** · 👤 · 🟢 · → `06_01`
- **Стан:** Підготовка зацементована — schema-correct inert stub (`proxy.healthcheck.path: /ready`, звірено з kamal 2.12) у `config/deploy.yml`+canopy; first-deploy cutover-runbook → [`06_01 §Чеклист`](06_01_Deployment_Kamal_Terraform) (крок 18); проба `/ready` (DB+Redis+Kredis) → [`06_05`](06_05_Puma_Configuration). Свідомо deferred (design): на холодному старті `/ready` 503→deploy_timeout→rollback, тож bring-up на дефолтному `/up`, фліп на `/ready` коли `/ready→200`. Лишається 👤-фліп:
- [ ] 👤 розкоментувати `proxy.healthcheck.path: /ready` на першому деплої (після `/ready→200`) + верифікувати cutover

#### INF.9 — deploy.yml path-gate (infra-relevant changes only)
- **P3** · 🤖 · ⚪ · → `06_07`
- **Стан:** Не розпочато — `Deploy · Canopy` (`deploy.yml`) стріляє на КОЖЕН main CI-success; коли деплой стане живим (реальні секрети), загейтити на infra-шляхи (`terraform/**`/`Dockerfile`/`config/deploy.yml`/`.kamal/**`) тим самим changes-діфом, що `Deploy · GHCR Mirror`. Зараз premature — deploy і так no-op'иться без секретів. Канон `06_07 §1`.
- [ ] 🤖 path-gate `deploy.yml` коли deploy стане живим

#### S5.6 — GCS bucket для Terraform state (chicken-and-egg)
- **P3** · 👤 · ⚪ · → `06_02 §GCS bucket`
- **Стан:** Не розпочато — GCS bucket для remote TF state створюється вручну перед `terraform init` (chicken-and-egg). Канон `06_02 §GCS bucket`.
- [ ] 👤 `gsutil mb` → верифікувати `terraform init`

#### E.5 — CoAP listener scale ceiling (~10k вузлів)
- **P3** · 🤖 · 🌿 · → `06_01`
- **Стан:** Ruby CoAP listener (`lib/daemons/coap_listener`) масштабується до ~10k вузлів; за межею → Rust/Go Ingress Proxy (ARCH.2). Far-horizon (Series D). Дотично INF.17 (prod-процес того ж демона).

#### ARCH.2 — Ingress Proxy (Rust/Go) + Kafka (>1M packets/hour)
- **P3** · 🤖 · 🌿 · → `06_01`, `00_01`
- **Стан:** Scale-tier понад Ruby CoAP listener (E.5, ~10k вузлів): Rust/Go proxy + Kafka для >1M packets/hour. Far-horizon (Series D). Дотично INF.6 (Ingress Anchor) + E.5.

#### E.27 — Chaos Engineering (Chaos Mesh / kill-scripts)
- **P3** · 👤 · 🌿 · → `06_08`
- **Стан:** Chaos Mesh (Akash) або kill-scripts (Kamal) для відмовостійкості — post-TRL 7 production hardening. Дотично DR.1 (DR drill) + `06_08` resilience policy.

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
- [ ] 👤 NDA+RFQ зі 3D Lab PL → sample part order (10 шт) quality benchmark → Frame Agreement (+20% premium, 30-day activation). **RFQ-deliverable готовий:** sample part = Ti-coin Stage 2 (HW.24) → STL + **DXF-креслення** (`draw ti_coin`, CEM tolerances/notes — HW.1/`drawings_program.md`)

#### BIZ.17 — Procurement-workflow operational gaps (post-RFQ-layer dig)
- **P2** · 👤 · ⚪ · → `07_02 §8`
- **Стан:** RFQ-layer структура ✅ (`protocols/procurement/` — `rfq_registry` + `ebfc_chem_rfq` + `anchor_alloy_rfq`; concern-шар, `00_06 §2`); deep dig (2 Explore-сповзки) виявив 5 operational-gaps без дому + registry-maintenance — консолідовано тут. Канон `07_02 §8` (BOM/хаби) + registry.
- [ ] 👤 **DMLS vendor-scoring matrix** (lead-time × quality × price × ISO-13485) → живить BIZ.8 Frame Agreement
- [ ] 👤 **CDA/NDA шаблон** для 5-ВНЗ MoU (блокує UNI.1 → гранти; СЄУ Аблязов legal) — розширює BIZ.10
- [ ] 👤 **ESG vendor-screening** matrix (репутаційне для climate-проєкту / grant-fonds)
- [ ] 👤 **SE050 supply-timeline** (NXP availability для mass-population post-FW.2, `03_05 §3.7` / ARCH.43)
- [ ] 👤 **Синт. сік make-vs-buy** (ЧНУ pilot-stock vs synthesize, `08_02 §1`)
- [ ] 🤖 (опц.) **completeness-audit гейт** — лінтер «канон-компонент не в `rfq_registry`» (self-maintaining); ~37 stub-аркушів авторяться інкрементально (registry status-col трекає)

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

## §08a · Академічна інтеграція

> **Поточний стан:** Партнерство з 5+ академічними установами — ChNU (фізико-хімія + ФОТІУС), ChDTU (Data Science + RF + акустика), ChIPB-NUTSU (пожежна безпека), ChMA (біохімія + токсикологія), СЄУ (правова + економічна архітектура). UNI.1-3, UNI.14 — раніше ідентифіковані; нижче — розширення на всі 5 установ.

#### UNI.1 — Перший контакт з деканом Онищенком (ChNU FOTIUS)
- **P0** · 👤 · ⚪ · → `08_01`
- **Стан:** Не почато — перший контакт з деканом Онищенком (ChNU FOTIUS); блокує всю лаб-роботу, 10 публікацій, 11 магістерських. Канон `08_01`.
- [ ] 👤 призначити + провести зустріч

#### UNI.14 — СЄУ: перший контакт ректорату + токеноміка RWA / правова архітектура
- **P0** · 👤 · ⚪ · → `08_02 §5`
- **Стан:** Не почато (консолідує legacy UNI.8) — перший контакт ректорату СЄУ + СЄУ-робота: (1) MSA/Term Sheet (Аблязов Д., к.ю.н.), (2) KYC/AML юросіб (Hadron), (3) DAO як юрособа (cooperative/Swiss Verein), (4) ESG Accounting (Ус Г.О.). Блокує Economic Whitepaper / Legal Framework / NaaS-шаблони (`07_01` B2B-MSA/B2C-ToS). ⚠️ 7 посад потребують verify. Канон `08_02 §5`.
- [ ] 👤 зустріч Чудаєва (ректор)/Аблязова Н. + verify 7 посад + MoU СЄУ↔SilkenNet + workshop Аблязов (MSA) + workshop Ус (ESG framework)

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
- **Стан:** Не почато — DFT електрон-трансферна енергетика EBFC Gen 2.0 (dgrFAD-GDH/Os, Laccase-ZIF, PSBMA; школа Мінаєва, світовий DFT); ціль Q1 *Electrochimica Acta*. Стаття 1 submission-ready як defensive-pub (own in-silico, `L3_quantum_chemistry`) — Мінаєв = co-validation/co-authorship credibility, НЕ блокер (стара Gen 1.0 «streaming potential» відкинута). Канон `08_01 Стаття 1`, `08_03 §1`.
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
- [ ] 👤 зустріч + RF-лаб access + VNA-вимір PEEK-кришки (1.5/2.0/2.5 мм; ціль VSWR <1.5 @ 868 МГц, сухий/вологий стан + 3D Keep-Out з Ti-фланцем: Z-clearance 5/8/12 мм, з/без overhang — ex-E.53, вимога [`02_01 §5.3`](02_01_Hardware_Architecture_and_BOM)) + Link Budget field test
- [ ] 🔗 залежить HW.9 + HW.17

#### UNI.12 — ChIPB-NUTSU: пожежна безпека + параметричне страхування
- **P1** · 👤 · ⚪ · → `08_02 §3`
- **Стан:** Не почато — ChIPB + НУЦЗУ: (1) валідація тригерів параметричного страхування (FRP/confidence з dClimate), (2) SOP для 8 EwsAlert-типів (drought/insect/vandalism/fire/seismic/fault/entropy/field_audit [INS.1]), (3) ДСНС API. Канон `08_02 §3`.
- [ ] 👤 cold contact ректорат + презентація fire-safety stack + joint SOP workshop (ARCH.31)
- [ ] 🔗 залежить UNI.14 (СЄУ legal) для structuring страхування

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
- **Стан:** Не почато (**P1 у Mongabay-пивоті**, E.59) — ПМКТ (п'єзоелектрика + акуст. метаматеріали): EIS п'єзодиска 25-150кГц (cavitation) + верифікація гіроїдного phonon lens; ціль Q1 *IEEE TBME*. **📐 One-Home частоти кавітації (2026-07-03):** 25-150 кГц (ультразвукова AE, Tyree&Dixon 1983) = ЄДИНЕ правильне число — reframe-пас виправив drift у 4 місцях (03_03 §4.2/§1.2, 01_01 §5.4/§5.6, synthetic.py, manifest), де кавітацію хибно клали в 5-20 кГц. Поточний 16 кГц/Nyquist-8 audible-тракт її **не оцифровує** → cavitation-клас TinyML reframed до **low-freq structural water-stress proxy** (клас лишено, перейменовано наміром); справжня ultrasonic-детекція = цей UNI.11-канал / v3 AI-chip. Канон `08_02 §2`, `03_03 §10` + `03_03 §4.2` (reframe-дім).
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

## §08b · External Stakeholders (B2G / B2B / Cultural)

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

## §08c · IP / Grants (BIZ)

#### BIZ.10 — Multi-party co-authorship + open-license MoU framework
- **P1** · 👤 · ⚪ · → `08_01 §2`, `08_02 §5`
- **Стан:** Не почато — 5-сторонній фреймворк (ChNU+ChDTU+ChIPB+ChMA+СЄУ+SilkenNet) **спрощено під open-поставою** (`08_01 §2`): tech відкрита всім → немає патентних прав / royalty / tech-NDA до розподілу; лишається co-authorship + open-license acknowledgment (AGPL/CERN-OHL-S/CC-BY-SA) + NDA лише для нерозкритого (ключі / production-дані). Канон `08_01 §2` (open-license/IP-постава), `08_02 §5` (СЄУ Аблязов — legal MoU drafting).
- [ ] 👤 co-authorship + open-license MoU × 5 (паралельно UNI.4-14) → Master Collaboration Agreement (юрист, не патентний повірений)
- [ ] 🔗 після UNI.1/9/12/13/14

#### 🌿 BIZ.12 — Horizon Europe CLUSTER 6 заявка (Biodiversity Monitoring, Mongabay pivot)
- **P2** · 👤 · 🌿 · → `08_01 Стаття 24a`, `03_03 §10`
- **Стан:** Far-horizon — Horizon CL6 Biodiversity Monitoring (2-6 М€, 36-48 міс); SilkenNet = єдиний планетарний D-MRV з micro-acoustic біорізноманіттям. Submission прив'язати до acceptance Статті 24a → «published research». Канон `08_01 Стаття 24a`, `03_03 §10`.
- [ ] 👤 identify call (HORIZON-CL6-*-BIODIV) → consortium (SilkenNet coord + ЧНУ/ЧДТУ/біо-хаб + 1-2 EU: Linköping/CSIC) → submit при acceptance 24a
- [ ] 🔗 E.59/FW.4-EXT (5-class TinyML) + UNI.13a (Soundscape Library)

## 🔀 Cross-cutting · Doc-drift (DOC-T) — SSOT doc↔code + tracker form/tooling

DOC-T трекає SSOT doc-drift (узгодження docs↔код) **та** еволюцію самого tracker'а — форму пунктів і drift-guards. **Не блокери виконання, але блокери для аудиту й онбордингу.**

> **Три `DOC*`-неймспейси (кожен у своєму домі — не плутати):**
> - **`DOC-T.N`** — цей tracker (SSOT doc-drift + tracker form/tooling TODO; таблиця нижче).
> - **`DOC-R.N`** — code↔doc divergence registry ([`04_02 §11`](04_02_Business_Logic_and_Services); дзеркало `04_01 §12`).
> - **`DOC.N`** (bare) — canon-block SSOT-home теги **всередині** канон-доків (`03_01`/`03_04`/`04_04`/`05_02`…); номери **load-bearing** у GitHub anchor-слагах (`-docN`) → заморожені на місці. `DOC.8` (cleanup constraint) — спільний у 04_01+04_02.
>
> Inbound item-ref (`NN_NN — DOC-T.N`) резолвиться `tracker:check` ([`00_06 §3`](00_06_SSOT_Documentation_Standard)).

| ID | Пункт | Канон |
|----|-------|-------|

_Resolved DOC-T → §🗄️ нижче. Нові SSOT doc-drift / tracker-tooling знахідки → додавати рядком сюди._

## 📌 Backlog (не блокери · довгострокові)

| ID | Опис | Джерело | Note / Milestone |
|----|------|---------|------------------|
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | Post-TRL 4 |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation | Legacy | Post-TRL 6, потребує E.10 (Kalman) |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1B (Порубльов) | Post-TRL 6 (Порубльов, ЧНУ) |
| ARCH.8 | **Event-Triggered Reporting** («тиша = здоров'я»): heartbeat 1/добу в нормі + continuous streaming на аномалії (~24× трафік-економія). Подієвий негайний panic-TX вже існує (chainsaw → `PANIC_TTL=5`, `03_01`) — ARCH.8 = систематична cadence-політика зверху; передумови ділить з ARCH.22 (рідкий Z послаблює DCI → challenge-sampling) + cadence чіпає `delta_t`→`m(delta_t)` GP-економіку (E.63) | [`00_08 §2.3`](00_08_Beyond_TRL9_Planetary_Roadmap) + `02_03` (зимовий режим) | Post-TRL 6 |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1B (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
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
| ARCH.17 | Bonding Curves для dynamic SCC pricing | `05_03` | TRL 9+ |
| ARCH.44 | **GaiaNexus multi-net vision page** (BIZ.16 level-3, founder-deferred) — опційний повний vision/manifesto планетарної федерації (Cryo/Abyssal/Litho/Myco + ноосферна економіка). Тонка far-horizon рамка вже є ([`00_08 §3`](00_08_Beyond_TRL9_Planetary_Roadmap)); повний 17-net каталог лишається в нотатках founder'а (no-premature-canon). Будувати лише на founder go | `00_08 §3`, `08_01 §2` | Post-TRL 9 (vision; founder-gated) |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | R&D partnership |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | Потребує Косенюк |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data | `08_03` | Blocked by UNI.1-3 |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates (+ **[INS.1]** `ai_insights` — co-partition кандидат: `DailyHealthRouter` подвоює daily-read A+B) | `04_01` | >100M рядків/місяць |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| ARCH.20 | Petri Net PN-модель Rails моноліту: формальна верифікація відсутності deadlock при 10,000 concurrent IoT connections. Sidekiq + Puma + PostgreSQL modeling. Конволюційний метод для зменшення state space explosion у 10-100 разів | `08_02` | R&D (Супруненко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1B (Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

## 🗄️ Архів закритих пунктів (мігровано в канон)

> Повністю завершені пункти. Знання — у канонічних доках (стовпець «Канон»); повна історія — у git. Тримаємо лише вказівник для крос-реф цілісності (CLAUDE.md та живі пункти посилаються на ці ID).

| ID | Пункт | Канон |
|----|-------|-------|
| E.66 | Toucan bridge — ✂️ PRUNED 2026-07-04 (founder-рішення 07-03, Ruthless Prune): flow був DEAD (0 enqueue-callerів) з money-integrity дірою у failure-path (без `retries_exhausted`, несиметричний rollback, in-flight `locked>balance`) → видалено ЦІЛКОМ (`ToucanBridgeWorker` + `Toucan::BridgeService` + `Wallet#lock_for_toucan_bridge!`/`finalize_spend!` + `toucan_bridged_balance` колонка-міграція + `TOUCAN_BRIDGE_CONTRACT_ADDRESS` з Kamal/Akash + specs). SCC→TCO2 expansion воскресає з git при E.20-go — тоді ж HARD gate: симетричний rollback + інваріант `locked ≤ balance` + ARCH.49 nonce-lock | `04_02 §10` (нота), `04_01` (Wallet) |
| ARCH.42 | AES-128 LoRa — DECIDED (Variant B); SE-частина ATECC→**SE050** (true-DePIN — SE050-MIGRATION) | `03_05 §3.7` |
| SEC.6 | SE = **SE050** — ✅ RESOLVED 2026-06-07 (true-DePIN: голос дерева потребує non-extractable Ed25519 → SE050, не ATECC; soft-freeze DNP, populate post-FW.2). Деталі + усі residuals → SE050-MIGRATION | `03_05 §3.7`, §3.4 |
| SEC.4 | Shipping-mode — ✂️ RESOLVED «не потрібен» 2026-07-03 (Ruthless-Prune): factory-заряд не переживає логістику незалежно від вимикача (власний витік EDLC), cold-start з 0 В = дизайн-шлях BQ25570, вібраційного wake не існує; «перший вдих»-UX → pogo-підзарядка в день інсталяції; decision-record (pull-tab > геркон, magnet-DoS → latching first-boot) + reopen-умови збережені в каноні | `03_05 §3.5` |
| SEC.14 | SE-роль — ✅ RESOLVED 2026-07-03 (founder): **provisioning-only** design-default (SE = ідентичність/provisioning; streaming AES = вбудований radio-AES, KEYL у Protected Flash обабіч гілок; per-packet = задокументований urban/high-value варіант, SE Slot 0 reserved). Осі: load-switch cold-boot щоциклу · FW.17-ратчет MCU-side · двоключова blast-radius · latency/ідіом · L2-форма. Eval-residual (silicon-confirm чисел) → SE050-MIGRATION | `03_05 §3.7` (Статус) |
| SEC.10 | Emergency-TX anti-replay frame counter (DR0 packing) | `03_02`, `03_01 §2` |
| SEC.11 | Lorenz Seed Provenance (DCI hardening, K_seed HKDF) | `03_04`, `03_06 §2`, `04_02`, `05_02` |
| SEC.7 | OTA image authentication — **дубль FW.23** (HMAC-SHA256 dual-gate: `OtaHmacKeyService` + `OtaPackagerService` 0x9B trailer + Queen relay + Soldier dual-gate, live-compute ✅ зашито 2026-06-11). Residuals (bench K_ota Protected Flash; ECDSA P-256 post-TRL7 migration path) тримає FW.23 — One-Home | `03_06 §4` (= FW.23) |
| SEC.8 | ECB Restoration Race (Queen): restore CRYP→ECB+128B+LoRa-key після CoAP-CBC flush/downlink; `HAL_CRYP_Init` fail → RCC force-reset → `NVIC_SystemReset` (`firmware/queen/main.c`). Resolved-фікс, orphan-ID — cited by SEC.12 + RUNBOOK, бракувало archive-рядка (додано 2026-06-09) | `03_05` (розділ «ECB Restoration Race») |
| SEC.12 | HRNG-IV fallback predictability — closed in SW 2026-06-15: key-derived HMAC-SHA256 IV (`coap_iv.h#coap_fallback_iv`, host-parity vs OpenSSL) → unpredictable, не лише unique; no AES-engine `E_key(ctr)` / SEC.8-restore / bench needed (pure-SW `silken_sha256.h`) | `03_05` (розділ «HRNG Fallback») |
| SEC.5 | Chainlink oracle-callback HMAC fail-fast: `WEB3_STRICT_MODE=true` + порожній `CHAINLINK_HMAC_SECRET` → `SecurityError` (захищає `/oracle_callbacks` від forge `oracle_status_fulfilled?` → неавторизований mint). Guard `verify_chainlink_signature!` (`oracle_callbacks_controller.rb`) + RSpec. Resolved, orphan-ID — бракувало archive-рядка (ops: provision secret pre-mainnet → S1.1/`06_04`; додано 2026-06-09) | `04_03 §5.9` |
| FW.1 | Hardcoded identical AES-key → per-device HKDF + `Load_AES_Key()` (Protected Flash `FLASH_KEY_ADDR`, magic `KEYL` + zero-key guard → refuse-boot без provisioning) — firmware CLOSED 2026-05-02 (soldier+queen `main.c` + host-тести `test_load_key_*`). Per-device ізоляція реальна з FW.2 CCM (ECB-транзит = спільний ключ, §3.1). Bench-residuals — власні items: RDP L2 → SEC.2 · factory SWD-flash → SEC.3 · weak-key boot-guard → SEC.9 | `03_05 §3.1`, `03_06 §2` |
| FW.5 | ~~Lorenz β-пертурбація від delta_t/vcap~~ → **РЕВЕРСОВАНО [E.63]** (delta_t → growth_points напряму) | `03_04 §4.3`, E.63 |
| OS-RECOMPUTE | Стаття-1 cascade anchor +200→**+309** (real 4,4'-dimethyl-bpy, Zafar 2012; DF **+574 mV** downhill); recompute COMPLETE + усі RH closed (cache-vs-doc, os_complex co-write — уроки → `in-silico` skill) | `01_03 §3.4`, SUMMARY §Cascade |
| Стаття-1 pre-submission | Punch-list ✅ — 41 DOIs Crossref-verified (0 fabrications), AI-disclosure, §3.5 error-fitting; live submit-bullets (Fig1/cover/submit) лишаються в HW.5.IS open | `paper/`, `08_01 §2` |
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
| ARCH.46 | Damage-ratio 100%-over-burn (3 баги) → fixed: поріг `AiInsight::SLASH_STRESS_THRESHOLD` (тригер ≡ damage-сайзинг, не хибне `≥1.0`) + `target_date` прокинутий health-check→worker→burn + genuine-no-data → `freeze_for_field_audit!` (Кат-C, не worst-case 100%); `contractual`-форфейтура — виняток. Spin-off: INS.1 + SLASH-1 (0.8↔0.83, comms_no_ack). SHIPPED `6588bc90` | `05_05 §3` (нота + §6 divergence-(5) + §7) |
| ARCH.47 | Oracle lock-collision: mint і slash на спільному `ORACLE_PRIVATE_KEY`-fallback ділили б один Kredis-lock `lock:web3:oracle:<addr>`. Виправлено хибний rationale знахідки: lock = one-shot `SET NX EX` (raise НЕГАЙНО, НЕ «slash чекає ≤120s»); failed slash ставив `:breached` → worker-guard робив кожен retry no-op (НЕ «recover via retry» — той silent-abort = ARCH.48). Закрито address-collision clause у `Security::Web3NetworkGuard` (boot-refuse під `WEB3_STRICT_MODE`); deploy-чеклист розділених ключів — у INF.19/S1.1 | `05_02`, `07_01` |
| ARCH.48 | Silent burn-abort: `BlockchainBurningService` rescue ставило `NaasContract :breached` на БУДЬ-ЯКОМУ збої slash → worker-guard `return if status_breached?` глушив кожен retry → on-chain `slash()` тихо не транслювався (silent міс + clawback-вікно, reachable на правильно-keyed prod через RPC-лаг). Fix (3-case, code-review-hardened проти double-burn): `LockTimeout`→`:active`+retry re-slash; помилка `transact` (ambiguous broadcast)→`escalate_to_review!` `:manual_review` (in-flight `unsettled_within` блокує blind re-slash); крах після broadcast (`:sent`)→`:breached`. `:breached` ≡ slash-broadcast. Знайдено deep-trace ARCH.47 | `05_05 §3.2`, `04_02 §4` |
| ARCH.50 | Celo reward double-pay (4-й ARCH.45 сиблінг). **Хедлайн (bird's-eye Celo-аудит):** dedup `reward_already_sent?` будував вікно з ЛОГІЧНОГО `target_date`, але фільтрував по `created_at` (час запису ≠ audit-день) → запит НІКОЛИ не знаходив свій ж рядок → daily double-fire платив 10 cUSD/день **ДЕТЕРМІНОВАНО** (не лише crash; спек маскував бекдейтом). + persist-after-broadcast (#1) + pre-lock TOCTOU (#2) + revert-under-pay (#3) + deterministic-RpcError→shared-breaker blast-radius (#4). Fix (scope B): `reward_date`-колонка (логічний ключ; structure.sql напряму, без міграції) + dedup ВСЕРЕДИНІ lock + `:pending`-intent перед broadcast + `CeloConfirmationWorker` (Celo-RPC reconcile — `BlockchainConfirmationWorker` хардкоднутий на Polygon) + deterministic/ambiguous/transient rescue split (breaker-safe) + chain-prefix lock + dedicated `ORACLE_CELO_PRIVATE_KEY`. `classify_evm_receipt`→One-Home `Web3::EvmReceiptClassifier` | `05_01`, `04_02` |
| ARCH.49 | Nonce-race: `Chainlink::OracleDispatchService` (hot per-uplink) / `PuroEarth::PassportService` / `Etherisc::ClaimService` підписували EVM-tx на спільній `ORACLE_PRIVATE_KEY` base-EOA **БЕЗ** Kredis-lock (eth-gem бере nonce per-call → конкурентні підписи колізять nonce → orphan «sent-but-never-mined» tx), тоді як mint/burn/celo лок мали. Fix: обгорнути `transact` у спільний `lock:web3:oracle:#{addr}` (**той самий** key, що mint/burn → весь Polygon base-EOA серіалізовано); `LockTimeout` re-raise — Etherisc bare, Chainlink/Puro explicit перед `StandardError` (чистий retry, не `Dispatch`/`AnchoringError`). Chain-prefix #2 свідомо НЕ зроблено (challenge): Celo split (ARCH.50) уже зняв Celo↔Polygon contention; `polygon:`-prefix чіпав би й mint/burn lock-key — money-path-ризик без виграшу. Toucan/Klima той самий патерн, але DEAD (0 enqueue) → lock при активації (E.66) | `05_01`, `04_02`, `06_02` |
| ARCH.51 | Money-path idempotency consistency sweep — єдиний патерн на всю родину. **(1)** dead `BlockchainTransaction.in_flight`-scope (0 callerів) видалено (Ruthless-Prune); живий guard всюди = `unsettled_within(window)` (incl `:manual_review`) / `reconcile_in_flight` (Solana batch) / `EthereumAnchor.in_flight` (anchor). **(2)** Solana **per-event** double-pay закрито (agent re-framed REAL на default `threshold=0`, не dormant): робив broadcast-ПОТІМ-record → crash-retry → новий blockhash/signature (Solana не дедуплікує) → double-pay; fix = sign-first `:pending` intent ДО broadcast + per-telemetry reconcile (`chainlink_request_id` + `signature_status`; `:not_found`→`manual_review`), дзеркало batch. Ruthless-Prune dead `send_transfer_request`/`send_transfer_checked_request`/`dispatch_transfer`/`record_transaction!`. (insurance internal-mint double-mint + Celo-вирівнювання ARCH.50 — раніше у sweep.) Canon-drift: 5 «in_flight»-згадок (named scope + colloquial) → точні guard-терміни | `05_02`, `04_02`, `05_01`, `06_02` |
| BIZ.5 | Патентна заявка → **ВІДХИЛЕНО** (founder 2026-06-07): defensive-publication-first замість патенту-монополії — ядро як prior art (вільне + анти-захоплення), без повіреного/PCT; SilkenNet тримає лише ™ / governance / секрети. Виконання → активні UNI.3 + BIZ.10 | `08_01 §2` |
| BIZ.1 | 1 SCC ↔ CO₂: **2000 SCC = 1 tCO₂ (0.5 kg/SCC)** done + on-chain — `SystemParameter(:scc_per_tonne_co2)` + `ProtocolParameters.sol#sccPerTonneCo2()` (flat ratio, НЕ per-species). Методологічна сертифікація (Verra/Gold Standard, post-TRL 7) тримає BIZ.9 | `07_01 §3`, `05_03` |
| UNI.8 | СЄУ ректорат — перший контакт = **legacy dup**, консолідовано в живий **UNI.14** (P0; перший контакт + MSA/KYC/DAO-юрособа/ESG, блокує Economic Whitepaper/Legal/NaaS) | `08_02 §5` |
| BIZ.16 | Naming model **RESOLVED** (founder 2026-06-16): codename «Gaia 2.0» **розчинено** за висотою → **SilkenNet** (лісовий net / продукт) + **GaiaNexus** (планетарна федерація / ноосферний апекс, far-horizon); sphere-таксономія + `PlanetaryNode`-абстракція. ~66-site sweep (docs+code+contracts NatSpec+foundry fuzz-seed) + deprecated-term guard «Gaia 2.0». ™-заявка лишається UNI.3/UNI.15; повна multi-net vision-сторінка відкладена → ARCH.44 | `08_01 §2`, `00_08 §3` |
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
| DOC-T.27 | **Deep-audit §05/§06/§07/§08 complete** (deep-archival: per-item verify-canon ЧИТАННЯМ дому → cement / drift-fix / archive). **§05** (2026-06-16): 7 items code↔canon-verified, drift swept (00_01 §6.x→05_05 · batchMint 200→100 · blackout-SLA · E.7 · SLASH-1). **§06** (2026-06-16): 18 items verified (DOC-T.29 line-ref kill · 06_01 max_conn 4×3/pool-5 · 06_05 threads-ENV · 06_08 stale-ref · S1.5 · S4.3). **§07** (2026-06-22): BIZ.1 archived (SCC↔CO₂ 2000:1 done+on-chain) · BIZ.4 un-archived (mainnet DAO ≠ done) · BIZ.14 gate→BIZ.4; решта legit-legal. **§08** (2026-06-22): UNI.8→UNI.14 консолідація (+6 рефів) · UNI.4 de-drift (Gen 1.0→2.0) · Порубльов «доц.» kill · STK.1-10 clean vs 08_03 · BIZ.10 home-ref fix. Деталь по секціях — git | `00_06 §4` |
| DOC-T.22 | §01-02 HW під-регіон стандартизовано (form-decision: фасетні під-блокери інлайн HW.8-стилем, standalone-програма → `####`): HW.5 Gen 2.0-блок → pointer `01_03 §1–3`; HW.1.PicoGK + HW.3.IS згорнуто інлайн; HW.5.IS → `####` (CHEM.N + in-silico = `#####` working-backlog діти, kept per no-premature-canon). Drift-fixes по нитці: HW.3.IS creep→stress-relaxation + DFT→MD-permeation + Trek-C heavy-FEA→Гусак; `00_02 §4a` reconcile (аналітичний Lamé-bound легіт, відкладає важку FEA Гусаку); Стаття 28→Стаття 1; `01_03` HW.5a→HW.5 | `00_07`, `01_03 §1–3` |
| DOC-T.21 | 18 tracker-family `[ID]` cited у коді/доках без 00_07-дому → per-ID verify resolved-in-code + §🗄️ orphan-rows (OBS.1/SEC.5/SEC.8 pattern): S6.4/6/8/9/13/15/16/17/19 · FW.6/10/16/28 · E.46 · HW.10 · INF.5/7 = resolved code-annotations; FW.45 = dup→ARCH.18 (firmware-тег) | `00_07` |
| TEST.1 | Solidity contract coverage: низький forge `--ir-minimum` branch%/окремі line = артефакт виміру (require-reverts/`pause`/override-делегації тестовані+проходять; гейт на line/func), Governor `_cancel` func-геп закрито `test_cancel_byProposerWhilePending`. RSpec gate + firmware coverage-lane (раніше теж під TEST.1) — done | `04_06 §B.1.2`, §B.3 |
| TEST.2 | Seed-залежний telemetry-flake (order/state-pollution, не регресія): CCM-блок витікав `TELEMETRY_CCM_ENABLED` — user-`after { ENV.delete }` біжить ДО тіардауну `stub_const("ENV")` → чистить стаблений Hash → флаг лишався в реальному ENV → `chunk_size` 21→29 → 21-байтні пакети тихо скіпались → падіння в SEC.10/unpacker/CoAP-e2e (CI seed 48720). Фікс: глобальний ENV-snapshot `config.around` у `rails_helper` (закрив весь клас ENV-витоків) + `preload_trees` дзеркалить `perform`-skip коротких chunk (TypeError на обрізаному хвості) + regression-тест; урок канонізовано | `04_06 §B.2`, §B.4 |
| TEST.3 | Solidity test-hardening (закрив §B.1.2 ERC20Permit + Governor Integration): повна EIP-712 сюїта — `permit()` (happy/expired/replay/cross-chain `vm.chainId`/wrong-signer, SCC+SFC) + SFC `delegateBySig` + спільний-nonce diamond, shared helper `test/helpers/Eip712SigUtils.sol`; Governor↔SCC role-management end-to-end (DAO видає/ротує `MINTER_ROLE`/`SLASHER_ROLE` через 48h-Timelock + non-Timelock grant reverts) = pre-mainnet валідація BIZ.4. Cross-chain replay = інваріант (SCC лише Polygon), не жива загроза | `04_06 §B.1.2`, `05_06` |
| TEST.4 | Backend AASM/Wallet concurrency — won't-do (свідоме рішення, не геп): money-safety тримає Postgres pessimistic-lock (`with_lock`/`lock!` = `SELECT … FOR UPDATE`, регресію ловить mock-сюїта `wallet_spec`); AASM-переходи `BlockchainTransaction` без `requires_lock` = robustness-only self-heal, НЕ money-loss (не чіпають wallet-money); без `lock_version` multi-thread тест AASM-гонки vacuous (last-write-wins, нуль raise) + був би перший flake-схильний non-txn thread-DB файл (клас TEST.2) → не пишемо | `04_06 §B.1.3` |
| DOC-T.31 | `verification_service_spec` `#query_dclimate_api` before стаблив `credentials.dig` лише `.with(:dclimate,:api_key)` без default → ActiveStorage lazy-init (`storage.yml`) дигав `(:aws,…)` → partial-double "unexpected arguments" (падало ізольовано й на HEAD; спіймано при E.41). Фікс: `and_call_original` default перед вузьким stub. Клас TEST.2 (test-isolation) | `04_06 §A.2` |
| TEST.5 | Firmware host-сюїта під динамічним memory-safety: `make -C firmware/test asan` (re-instrumented rebuild, `coverage:`-ідіом) ганяє всі ~22 тести під ASan+UBSan (`-fsanitize=address,undefined -fno-sanitize-recover=all`); CI-крок `[TEST.5]` у `firmware_test` (gating через `ci-ok`). Закрив OpenSSF `dynamic_analysis_unsafe` (N/A не діє — везем memory-unsafe C; раніше лише статичний cppcheck + `-Wall`). `detect_leaks=0` свідомо (OpenSSL one-time-init = хибний leak; критерій цілить overwrites/UAF/UB). Suite чиста + red-proof (scratch-overflow → SIGABRT) | `04_06 §B.1.1` |
| E.45 | SCC/SFC subgraph zero-address fail-fast guard (`subgraph/validate_addresses.sh`); real-address swap → S3.5 | `05_03` |
| E.48 | The Graph subgraph на testnet `polygon-amoy` → потребує mainnet re-deploy; складено в **S3.5** (mainnet-cutover residual) — не окремий трек | `05_03` |
| DIFF.1 | `Wallet#lock_and_mint!` conversion threshold = runtime-param (governance-tunable tokenomics rate, не hardcoded) — doc↔code diff-check, no action | `04_02`, `05_06` |
| E.65 | `piezo_voltage_mv` фантом ВИДАЛЕНО (Ruthless Prune): колонка (всі партиції) + scope `seismic_activity` + btree-індекс — жоден wire-формат не ніс piezo, нічого не писало колонку. П'єзо = пасивний EXTI акустик-тригер ([`02_01 §3`](02_01_Hardware_Architecture_and_BOM)), не mV-датчик; сейсміка через `acoustic_events` | `04_01 §3` |
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
| S6.20 | ClusterEntropy + InsurancePayout cron-оркестратори (doc-ahead-of-code закрито): `ClusterEntropySweepWorker` (cron `10 * * * *` — оживив `silkennet_cluster_entropy_score` + `entropy_anomaly`) + `InsurancePayoutRecoveryWorker` (cron `15,45 * * * *` — idempotent safety-net); host-done + RSpec + `config/sidekiq.yml`. Scheduler-pickup = той самий механізм, що й решта кронів (не per-cron ризик) | `04_02 §11` |
| FW.6 | isfinite() RTC Lorenz-state validation (`soldier/main.c`) — resolved code-annotation | `03_04`, `03_01` |
| FW.10 | Winter-kenosis TX gate (−15°C, ESR) (`soldier/main.c`) — resolved code-annotation | `03_01` |
| FW.16 | `Restore_ECB_Mode` error-recovery after CoAP-CBC (`queen/main.c`; ↔ SEC.8) — resolved code-annotation | `03_05` |
| FW.28 | Atomic acoustic capture (ISR↔pack window lock) (`soldier/main.c`) — resolved code-annotation | `03_03` |
| FW.45 | Integer-Math/fixed-point Lorenz hardening — **дубль, не окремий трек** (deferred): концепт = active **ARCH.18** (FW.45 = firmware-тег цього ж рішення) | `03_04` (= ARCH.18) |
| E.46 | Mint-during-RPC-fail = no slash (`BlockchainMintingService`) — resolved code-annotation | `05_05`, `04_02` |
| HW.10 | PSM + eDRX idle-power for NB-IoT/LTE-M (`queen/main.c`) — resolved code-annotation | `03_02`, `02_05` |
| INF.5 | `PROMETHEUS_ALLOWED_IPS` CIDR allowlist for /metrics — resolved code-annotation | `06_03`, `06_04` |
| INF.18 | Solid Queue dead scaffold → **PRUNED** (founder 2026-07-04, E.66-патерн «воскресає з git»): gem+lock · `queue.yml` · `recurring.yml` · `queue_schema.rb` · `database.yml` queue-блок (4→3 бази) · terraform queue-бази (prod+canopy) · `bin/jobs` · `rails_schema.rb` — Sidekiq = єдиний job-backend (strict-drain+cron+`unique_for` зацементували; Redis лишається через Kredis → мотив «прибрати Upstash» недосяжний) | `06_01`, `04_02` |
| INF.7 | `ALLOY_CONFIG_BASE64` manual SDL deploy encoding — resolved code-annotation | `06_02` |
| DOC-T.30 | М06 канон↔deploy drift (INF.11/INF.16 sweep): `06_01` env-блоки (env.clear + §13 Web3) → one-home pointer `06_04 §2.1` (+ `POSTGRES_*`/`WEB3_STRICT_MODE`/`RELEASE_VERSION`; `RAILS_ALLOWED_HOSTS`=operator-set S6.18); Canopy-таблиця Akash-intended-vs-Kamal-workflow + DB-ізоляція (`POSTGRES_DATABASE`); `06_03` Sentry canopy=`RAILS_ENV=production` (не окремий env); `KLIMA_*_ADDRESS` doc-bug прибрано | `06_01`, `06_03`, `06_04` |
| DOC-T.23 | STAGE/WHO re-audit (7 WHO fixes, open-work semantic) + meta-line form std (combo `🤖+👤`, no tails) + AI-advanceability (S6.20/E.41 advanced); NEW guard `meta_form_violations` HARD | `00_07`, `00_06 §3` |
| DOC-T.24 | Priority re-assess (P1 73→59, un-flattened by TRL-horizon/blocking-impact) + stable in-section sort by priority (P0 gates surface on top); tools `tracker_set_meta.rb` + `tracker_sort.rb` | `00_07` |
| DOC-T.25 | 🚦 Dashboard refreshed from current items (UNI.13/14 priority drift fixed; 🤖-note S6.20/E.41) — human-curated do-now roadmap. (Superseded by DOC-T.16: Dashboard → slim 🚦 Critical Path; the unused auto-render code `Tracker::Dashboard.render`/`regenerate`/`check` pruned.) | `00_07` |
| DOC-T.16 | bare-§ після whole-doc-лінка (`[NN_NN](Doc) §X` → `[NN_NN §X](Doc)`, `00_06 §1`) — NEW guard `section_ref_after_doclink` (HARD, tree-wide вкл. `docs/protocols/` relative-href) + 1-shot sweep 35 рефів / 16 доків; по нитці виправлено стале §-номери (СЄУ §1.3→§5, Cold-Start→§1.5, фін-константи §2.3→§3). Ширша protocols ref-integrity → DOC-T.26 | `00_06 §3`, `lib/docs_linter.rb` |
| DOC-T.10 | 05/07 Фаза 3 (misplacement): Investor Q&A (колишня §11-секція `07_01`) = pitch/diligence presentation-шар (переказ канону) → Ruthless-Pruned; унікальний Q8-rationale (навіщо SCC, не USDC → Slashing = trustless accountability) мігровано в `05_03` (Dual Token System). Field Assembly + Virtual Prototyping у `07_03` = легіт grant-deliverables (реферять `01_04`/`02_01`/`06_04`) — no-move | `05_03`, `07_03` |
| DOC-T.26 | docs/protocols/ canon-ref blind spot — субдерево реферить top-level канон relative-path (`../../NN_NN`), поза top-level гейтами → майбутній rename/§-collapse тихо гнив би 84 рефи (клас §1.3→§5 у protocols/). Аналіз: protocols/ ЧИСТИЙ зараз (0 dangling/stale/value-drift, 84 well-formed relative-лінки) → фікс превентивний. NEW HARD `scripts/protocols_ref_check.rb` (CI docs.yml): resolution-only (target/§/anchor/bare-prefix), reuse `file_section_dangling_refs` + `DocsGraph.anchor_set`. Option A — форму не форсимо (14 bare-mentions лишені) | `00_06 §3`, `scripts/protocols_ref_check.rb` |
| DOC-T.28 | code→doc §-ref audit `scripts/code_doc_section_refs.rb` (app/spec/lib код-коментарі, report-only, 0 stale зараз) + 15-реф backlog виправлено → нові доми 04_02 §2/§11 (Outbox/Batch), 04_01 §7b (Codex moderation/lifecycle), 04_02 §10b (PairSelector), 03_02 §7 (Queen-Sentinel), 00_08 §1 (Beyond-TRL-9). Резолвер hardened: `heading_anchors` parent-aware літерні підсекції (Lat+Cyr → точний `§5.A`/`§4.А` резолвиться сам, без правки доку) + run-резолвер їсть `,;`+backtick → список перевіряє КОЖЕН член (`§2.9, §6`), не лише перший. NEW HARD canon-wide §-ref gate (`docs:check_refs` над усім каноном, не лише 00_07/protocols) — закрив `08_02 §1.x`-collapse / 05_03 line-number-as-section / `02_03 §4.А` Cyrillic-letter drift | `00_06 §3`, `lib/tracker/dashboard.rb` |
| DOC-T.9 | LoRa TX energy у 02_03: стара «15mA/50ms» → datasheet-correct «118mA × 0.1s = 38.94 мДж» — **doc-drift вже виправлено** + «тривалості = оцінки-стелі, консервативно (завищені vs виміряних)»-caveat inline `02_03 §9.4` (§9.5–9.7 = нижня межа запасу). Живий залишок «лаб-вимір TX» = **НЕ doc-drift** (mis-placed у DOC-T) → bench-вимір active-cycle енергії канонічно у `firmware/scripts/bench/RUNBOOK.md §3.2` (`03_power_profile.py --mode cycle` → E.63). Resolved + redundant + 0 inbound → archived | `02_03 §9.4` (+ RUNBOOK §3.2) |
| DOC-T.29 | doc→code volatile line-ref — **2 guard-сліпі діалекти** (path-form `source_line_ref_drift` бачив лише `*.c/.rb:N`): (1) Ruby-symbol `ClassName:NNN`, (2) укр-проза `(р.162)`/`(рядок 31)`. §06-аудит знайшов 18 `ClassName:NNN` (06_02/06_04) + prose (06_03 File Map + 07_01 `.sol`) — частина дуже stale (`BlockchainMintingService:107`→120, `(рядок 31)`→41, `slash()` рядок 148→155; частина випадково ще точна — мікс = доказ дрейфу). Sweep → symbol-only ref + `source_line_ref_drift` розширено (3-й/4-й діалект + `.sol`-ext; `Payload:16` wire-field НЕ FP; 02_04 breadboard «рядок 10» exempt) + 2 specs. Те саме лікування, що DOC-T.15/17 | `00_06 §3`, `lib/docs_linter.rb` |
| E.34 | dClimate fallback → ForestBountyService: вісь жива як E.20 (+ E.41 fire-fallback), дизайн канонізовано («Інтеграція з dClimate Fallback (E.34)») — беклог-рядок був дублем | `04_02 §Forester Guild` |
| E.3 | Breadboard-відео для грантів → злито чекбоксом у HW.35 (стенд Гілки-А) | [`02_04`](02_04_Legacy_Breadboard_Appendix) |
| E.53 | state_root: `total_sfc` (сума confirmed SFC-мінтів) у формулі EthereumAnchor — migration applied; `[E.53]`-теги в `04_01`/`05_01`/`05_04` = ця робота. ID був помилково перевикористаний у беклозі під VNA-вимір антени → та вісь тепер чекбокс UNI.10 | [`05_04`](05_04_Ethereum_L1_State_Anchor) |
| E.54 | state_root: `active_tree_count` (метрика покриття екосистеми) — migration applied; `[E.54]`-теги = ця робота. ID був помилково перевикористаний у беклозі під SOP-документи EwsAlert → та вісь тепер UNI.12 (контент) + ARCH.31 (inline UI) | [`05_04`](05_04_Ethereum_L1_State_Anchor) |
| FW.25 | TinyML DSP-path: Path B (log-mel) SELECTED + shipped self-owned — `Compute_LogMel` + 3-way parity + `contract_hash` tripwire + бюджет-конверт (arena ≤ 10 КБ); живить FW.4 baseline. Residual'и мігрували: Path C-fallback + опц. партнер-апгрейд + 🌿 dataset → FW.4 | [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) (decision-matrix) + [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference) (контракт) |

