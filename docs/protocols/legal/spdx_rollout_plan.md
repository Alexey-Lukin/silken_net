# UNI.3 — SPDX-header rollout: аудит + план (AUDIT-ONLY, нічого не виконано/відредаговано)

> **Що це:** аудит фактичного стану per-file SPDX-заголовків у репозиторії + план ідемпотентного скрипта їх проставляння — робочий вхід для founder'а перед запуском кампанії тегування.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — UNI.3 (rollout) · DOC-T.47 (MIT-виняток `contracts/`, ратифіковано).

---

Дата аудиту: 2026-07-24. Метод: `git ls-files` (трекований репозиторій — SSOT для blast-radius), НЕ raw `find`/`grep -r` (той рахує gitignored build-артефакти й submodule-вміст, що дає ілюзорно роздуті числа — див. §2).

> ⏳ **Усі лічильники файлів нижче — снепшот `git ls-files` станом на дату аудиту.** Вони дрейфують щокоміту й наведені лише для оцінки порядку blast-radius. Команди відтворення — у Додатку; **перед запуском скрипта перерахуй, не довіряй цим числам.** Стабільний факт (нуль тегованих поза `contracts/`) від дрейфу не залежить.

## 0. TL;DR

| Питання | Відповідь |
|---|---|
| Вже теговані tracked-файли | **лише `contracts/*.sol`**, усі = MIT (100% покриття цього дерева) |
| Без тегу (potential blast radius) | **~1200–1400** файлів (залежно від сірих зон, див. §4) |
| `contracts/`=MIT виняток | ✅ ПІДТВЕРДЖЕНО реальний і повний; **задокументований і ратифікований** (DOC-T.47 — `/NOTICE` + [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) вирівняні, §1) |
| `tools/cad/`=Apache/CC0 виняток | ⚠️ **ЧАСТКОВО НЕПРАВДА** — це стосується лише submodule-вмісту (чужий git, поза нашим деревом); наш власний код у `tools/cad/src` **не тегований взагалі** (§2) |
| Native hw-design файли (gerber/STEP/KiCad) | **0 існує** в репо — CERN-OHL-S-2.0-зона зараз порожня (§4) |
| Рекомендація | **DEFERRED** (Phase 7) — diff завеликий + 3 нерозв'язані scope-питання founder має вирішити ПЕРЕД будь-яким скриптом (§6) |

---

## 1. Ліцензійна мапа зон — дім, не тут

**Яка зона під якою ліцензією — має ОДИН дім:** [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) («Ліцензійна матриця») + кореневий `/NOTICE` §LICENSING; значення обох = дзеркало кореневих `LICENSE*`-файлів. **Тут мапу НЕ рестейтимо** — читай у домі (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Цей документ каже лише те, чого в домі немає: **фактичний стан тегів у файлах** і **як їх безпечно проставити**.

Для аудиту прочитано в оригіналі: `/LICENSE` (AGPL-3.0 full text), `/LICENSE-HARDWARE.txt` (CERN-OHL-S-2.0 full text), `/LICENSE-DOCS.txt` (CC-BY-SA-4.0 full text), `/NOTICE`, `/THIRD_PARTY_NOTICES`.

> **✅ `contracts/*.sol` = MIT — ратифіковано (DOC-T.47), drift закрито.** Аудит зафіксував був розбіжність: обидва SSOT-документи казали «contracts (Solidity) = AGPL», тоді як фактичний код 100%-но ніс `SPDX-License-Identifier: MIT`. **Розв'язано:** MIT для `contracts/*.sol` ухвалено як свідомий виняток (on-chain composability / audit-tooling / OpenZeppelin-consistency), `/NOTICE` і [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) обидва вирівняні на нього. Для скрипта наслідок незмінний і простий: `contracts/` — **detect-and-skip**, писати там нічого.

> **Історична нота (теж закрита):** ранній аудит зафіксував у header'і `/NOTICE` pointer на модуль 08 — розчинений 2026-07-24, його зміст злито в `07_03`. Pointer уже виправлено: `/NOTICE` вказує на [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md). Дії не потребує.

`/THIRD_PARTY_NOTICES` підтверджує bundled-залежності: CMSIS-DSP/CMSIS_6 (Apache-2.0), mruby (MIT) у `firmware/extern/`; OpenZeppelin + forge-std (MIT) у `contracts/`; LEAP71 PicoGK/ShapeKernel/LatticeLibrary (Apache-2.0) + SkiaSharp/netDxf (MIT) у `tools/cad/`. Усе це — чужий, вже правильно ліцензований upstream-код (submodule або npm/NuGet), **не наш source**. Саме він — джерело «фантомних» SPDX-тегів, що ламають наївний підрахунок (§2).

---

## 2. Фактичний стан SPDX-тегів — і чому raw `find` бреше

### 2.1 Наївний підрахунок (raw filesystem, ПОМИЛКОВИЙ метод)

```
grep -rl "SPDX-License-Identifier" . --exclude-dir=.git | wc -l   → ~1440 файлів
```
Розбивка за ідентифікаторами: переважно Apache-2.0, далі BSD-2-Clause, BSD-3-Clause, CC0-1.0, MIT.

### 2.2 Правильний підрахунок (`git ls-files` — тільки трекований код)

```
git ls-files -z | xargs -0 grep -l "SPDX-License-Identifier" | wc -l   → 21 файл
```
Розбивка: **MIT — і більше нічого** (усі — `contracts/*.sol`).

**Різниця (~1420 файлів) — це майже повністю сміття для наших цілей:**

| Джерело «фантомних» тегів | Тип | Tracked? |
|---|---|---|
| `contracts/node_modules/` (OpenZeppelin+forge-std) | npm-install, у `.gitignore` | **0 tracked** |
| `contracts/out/` (forge build output) | build-артефакт, у `.gitignore` | **0 tracked** |
| `contracts/cache/`, `crytic-export/`, `medusa-corpus-{scc,sfc}/` | forge/Slither/Medusa runtime-кеш | **0 tracked** |
| `tools/cad/extern/LEAP71_ShapeKernel`, `LEAP71_LatticeLibrary` (Apache-2.0/CC0-1.0) | **git submodule** (mode `160000` gitlink) — окремий git-репозиторій LEAP71 | **0 tracked** файлів усередині (тільки gitlink-запис) |
| `firmware/extern/*` (8 submodule: CMSIS-DSP, CMSIS_6, mruby, monocypher, cmsis-device-wl, stm32wlxx-hal-driver, subghz-phy, stm32-mw-lorawan) | **git submodule** | те саме |

**Наслідок для скрипта: якщо ітерувати через `find .` замість `git ls-files`, скрипт спробує писати в submodule-робочі-дерева й gitignored build-каталоги — прямий шлях до випадкового псування чужого коду чи безглуздого запису у файли, які наступний `forge build`/`npm ci`/`git submodule update` все одно перетре.** Це найважливіший guardrail з цього аудиту: **enumerate виключно через `git ls-files`.**

### 2.3 Звірка винятків по суті

**`contracts/` = MIT — ПІДТВЕРДЖЕНО, реально і повністю.**
Усі `.sol`-файли, що існують у трекованому дереві (root-контракти + script + тести), мають `// SPDX-License-Identifier: MIT` рядком 1, перед `pragma solidity`. 0 файлів без тегу. Приклад (`contracts/SilkenCarbonCoin.sol`):
```solidity
// SPDX-License-Identifier: MIT
pragma solidity <pinned>;   // версія — One-Home 05_03
```
Це повний, самодостатній виняток — скрипту тут нічого робити, крім detect-and-skip. Розбіжність із зонною мапою, яку аудит зафіксував, **закрита ратифікацією DOC-T.47** (§1): мапа тепер описує реальність коду, а не навпаки.

**`tools/cad/` = Apache/CC0 — ЧАСТКОВО НЕТОЧНО.**
Ці теги реальні, але живуть ВИКЛЮЧНО всередині двох git-submodules (`tools/cad/extern/LEAP71_ShapeKernel`, `LEAP71_LatticeLibrary`) — тобто в ЧУЖОМУ git-репозиторії, structurally invisible для `git ls-files` на рівні супер-проєкту (підтверджено: `git ls-files -s tools/cad/extern` показує лише 2 gitlink-записи mode `160000`, жодного окремого файлу). Наш ВЛАСНИЙ код у `tools/cad/src/` і `tools/cad/tests/` (`.cs`) — **0 файлів із SPDX-тегом взагалі**. Уявлення «в `tools/cad` уже теговано» описує submodule-вміст (правда, але нерелевантно — цей код ми ніколи не редагуємо і скрипт його ніколи не побачить через `git ls-files`), а не наш код (який насправді чистий аркуш).

**Наслідок:** ризик «перезаписати правильні теги» в `tools/cad/` **структурно дорівнює нулю** (submodule-межа = природний захист). Натомість тут ІНША задача — не «зберегти виняток», а **нове рішення**: чи наш `tools/cad/{src,tests}` отримує AGPL (як решта «tooling») чи Apache-2.0/CC0-1.0 (щоб відповідати екосистемі LEAP71, яку він розширює)? Це відкрите питання, не факт для збереження.

---

## 3. Мапінг-таблиця: дерево → SPDX-ID

> Колонка «Статус» навмисно без знаменників: «0 tagged» — стабільний факт, загальна кількість файлів у дереві дрейфує (команди → Додаток).

| Дерево | Мова / комент-синтаксис | Пропонований SPDX-ID | Статус |
|---|---|---|---|
| `app/**/*.rb` | Ruby, `#` | AGPL-3.0-or-later | 0 tagged |
| `lib/**/*.{rb,rake}` + `lib/daemons/coap_listener` | Ruby, `#` | AGPL-3.0-or-later | 0 tagged |
| `spec/**/*.rb` | Ruby, `#` | AGPL-3.0-or-later | 0 tagged — **не в явному списку founder'а, потребує підтвердження** (тести теж «код»?) |
| `scripts/**/*.rb` (top-level) | Ruby, `#` | AGPL-3.0-or-later | 0 tagged |
| `db/**/*.rb` + `db/structure.sql` | Ruby `#` / SQL `--` | AGPL-3.0-or-later | 0 tagged |
| `firmware/**/*.{c,h}` КРІМ `firmware/extern/` | C, `//` або `/* */` | AGPL-3.0-or-later | 0 tagged — **⚠️ 2 підвиди insertion-логіки, див. §5.3** |
| `firmware/{bio_contracts,mruby,scripts}/**/*.{rb,py,sh}` | Ruby/Python/sh, `#` | AGPL-3.0-or-later | 0 tagged |
| `tools/{in_silico,ml,firmware}/**/*.{py,rb,sh}` | Python/Ruby/sh, `#` | AGPL-3.0-or-later | 0 tagged |
| `contracts/**/*.sol` | Solidity, `//` перед `pragma` | **MIT** (ратифікований виняток, DOC-T.47) | **усі теговані — ГОТОВО, тільки skip-logic** |
| `tools/cad/{src,tests}/**/*.cs` + `render_gallery.sh` | C#, `//` | ✅ **РАТИФІКОВАНО [DOC-T.47]: AGPL-3.0-or-later** (наш власний код; Apache/CC0 стосується лише LEAP71-submodule за межею нашого дерева) (CLAUDE.md §2 «tools/ крім tools/cad» натякає, що cad ВЖЕ виняток — але для чого саме?) | 0 tagged — founder має вибрати ID |
| native hw-design (gerber/STEP/KiCad/.scad/.dxf) | — | CERN-OHL-S-2.0 | **0 файлів існує в репо** — зона порожня, суто «future» (`/NOTICE` сама це каже: «and any future CAD/gerbers») |
| `docs/**/*.md` | Markdown | CC-BY-SA-4.0, **рекомендація: БЕЗ per-file SPDX** | N/A за конвенцією (§4) |
| `config/**/*.yml` + `config/**/*.rb` (мінус `.enc`) | YAML/Ruby, `#` | ⚠️ **ГЕП у мапі** — не згадано в задачі взагалі | потребує рішення |
| `config/credentials/*.yml.enc` | зашифрований блоб | — | 🔴 **НІКОЛИ НЕ ЧІПАТИ** (не текст, corruption risk) |
| `terraform/**/*.tf` + `.sh` | HCL/sh | ⚠️ відкрите питання (IaC — «код» чи «deploy-конфіг»?) | не в явному списку |
| `subgraph/**/*.ts` + `.sh` | TS/sh | ⚠️ відкрите питання (окрема екосистема, The Graph) | не в явному списку |
| `bin/*` (Rails/Bundler binstubs) | Ruby | рекомендація: **EXCLUDE** (згенеровано `bundle binstubs`, не наш оригінальний твір) | — |
| `.github/**/*.yml` | YAML | рекомендація: **EXCLUDE** (CI plumbing, не «продукт») | — |
| `.claude/**`, `.kamal/**` | — | рекомендація: **EXCLUDE** (tooling-конфіг агента/деплою, не продукт) | — |
| `public/*`, `vendor/*` | HTML/keep-файли | рекомендація: **EXCLUDE** (boilerplate error-сторінки, порожні asset-плейсхолдери) | — |
| `**/*.json` (CEM-маніфести `tools/cad/cem/*.json`, tools-data, docs, contracts-config тощо) | JSON | 🔴 **СТРУКТУРНО НЕМОЖЛИВО** — строгий JSON-спек не має синтаксису коментарів; додати SPDX-рядок = зламати файл (JSON5/JSONC — поза скоупом) | **EXCLUDE завжди** |

---

## 4. Blast-radius підсумок

Рахую виключно `git ls-files`; числа — снепшот дати аудиту (відтворення → Додаток).

**«Тверде ядро» AGPL** (жодних відкритих питань, чиста код-мова, застосовна comment-syntax): `app` + `lib` + `spec` + `scripts` + `db` + `firmware` non-extern (код+скрипти) + `tools` non-cad (код+sh) ≈ **~1200 файлів**.

**«Сірі зони» (потребують founder-рішення перед тегуванням):**
- `config/` (yml+rb, мінус `.enc`) ≈ 180
- `tools/cad/{src,tests}` (.cs+.sh) ≈ 25 (ID ще не обрано)
- `terraform/` (.tf+.sh) ≈ 14
- `subgraph/` (.ts+.sh) ≈ 2 (решта json/graphql/yaml — конфіг, за замовчуванням exclude)
- `spec/` уже пораховано в ядрі вище, але формально не в явному переліку founder'а — залишаю в ядрі як найбезпечніше припущення (тести = код), проте флагую

**Разом, якщо всі сірі зони отримають «так»:** ядро + сірі ≈ **~1400 файлів отримають перший НОВИЙ рядок**.

**Вже готово (не рахується як новий diff):** `contracts/` — 100%.

**Структурно виключено назавжди** (submodule-межа / gitignored / JSON без коментарів / шифрований блоб): `firmware/extern`, `tools/cad/extern`, `contracts/{node_modules,out,cache,crytic-export,medusa-corpus-*}`, усі `*.json`, `config/credentials/*.enc`.

**Це великий diff** (~1200–1400 файлів, по одному рядку кожен, розкидані по 8+ директоріях різними мовами) → підпадає під критерій «deferred Phase 7», а не «керований» one-shot.

---

## 5. План ідемпотентного скрипта (ПЛАН, нічого не написано/запущено)

### 5.1 Enumeration — джерело істини

```
git ls-files -z | while read -d '' -r path; do ... done
```
НІКОЛИ `find .` чи `grep -r .` для enumeration — інакше зачепить submodule-робочі-дерева й gitignored build-каталоги (§2.2 — головний урок цього аудиту).

Додатково hard-exclude glob-список (belt-and-suspenders, навіть якщо `git ls-files` вже мав би це виключити):
```
*/extern/*      # submodule-межа й так природно invisible, але явний excl — страховка
*.json *.enc *.tflite *.npz *.png *.svg *.xyz *.cif *.sdf *.pdb  # дані/бінарники без SPDX-синтаксису
```

### 5.2 Detect-existing (idempotency core)

Для кожного кандидата: `head -N | grep -q "SPDX-License-Identifier"` (N=3, з запасом на shebang+magic-comment) → якщо знайдено, **skip** (навіть якщо ідентифікатор інший, ніж очікується — mismatch йде в окремий WARN-звіт для ручного review, скрипт НІКОЛИ не перезаписує/не змінює існуючий тег автоматично).

### 5.3 Per-мова insertion-логіка (комент-синтаксис + safe insertion point)

| Розширення | Синтаксис | Точка вставки |
|---|---|---|
| `.rb`, `.rake` | `# SPDX-License-Identifier: X` | Після shebang (якщо є) І після magic-comments (`# frozen_string_literal:`, `# encoding:`/`# -*- coding: -*-`) — **НІКОЛИ перед ними** (Ruby читає magic comment лише в перших 1-2 фізичних рядках; вставка перед зсуває його й тихо вимикає `frozen_string_literal`) |
| `.py` | `# SPDX-License-Identifier: X` | Після shebang (якщо є), ПЕРЕД module-docstring (docstring лишається першим *statement* — синтаксично коментарі йому не заважають) |
| `.sh` | `# SPDX-License-Identifier: X` | Після shebang (рядок 1 завжди `#!...`) |
| `.sol` | `// SPDX-License-Identifier: X` | Абсолютний рядок 1, ПЕРЕД `pragma solidity` — вже 100%-но існуюча конвенція в репо, скрипт тут no-op (усі вже теговані) |
| `.c`, `.h` (firmware, non-CubeMX, тобто `firmware/common/**`) | `// SPDX-License-Identifier: X` | Абсолютний рядок 1, ПЕРЕД існуючим `/* ... */` One-Home banner-коментарем |
| `.c`, `.h` (firmware **з CubeMX-маркерами**, `firmware/{soldier,queen}/main.c` тощо, розпізнавати за наявністю рядка `/* USER CODE BEGIN Header */`) | `//` | **ВСЕРЕДИНІ** `USER CODE BEGIN Header ... END Header` блоку (одразу після маркера-відкривача), НЕ перед ним — інакше майбутній CubeMX-regen мовчки зітре рядок, бо він поза USER CODE межами |
| `.cs` | `// SPDX-License-Identifier: X` | Рядок 1 (тільки після того, як founder обере ID, §3) |
| `.tf` | `# SPDX-License-Identifier: X` | Рядок 1 (якщо сіру зону вирішено включити) |
| `.yml`/`.yaml` | `# SPDX-License-Identifier: X` | Рядок 1, АЛЕ пропустити, якщо рядок 1 — це YAML-директива (`---`, `%YAML`) — вставити ПІСЛЯ неї |
| `.sql` | `-- SPDX-License-Identifier: X` | Рядок 1 |
| `.md`, `.json`, `.enc` | — | **НЕ чіпати** (§3/§4) |

### 5.4 Dry-run за замовчуванням

Скрипт за замовчуванням **лише друкує** `[DRY-RUN] would insert '<comment>' into <path> at line <N>` для кожного кандидата — нуль записів на диск. Реальний запис лише за explicit `--write` флагом. Окремий `--diff` режим (unified diff у stdout без запису) для review перед `--write`.

### 5.5 Per-дерево, не one-shot

Через розмір blast-radius (§4) — план: окремий invocation/PR на дерево (`app/`, потім `lib/`+`spec/`, потім `firmware/`, потім `tools/`…), НЕ один мега-коміт на ~1400 файлів. Дозволяє: (a) review-able diff per PR, (b) full-suite verify між кроками (`bin/rspec`, `make -C firmware/test`, `ruff check`, `forge test`), щоб зловити будь-яку magic-comment/CubeMX-регресію одразу, а не через ~1400 файлів разом.

### 5.6 Верифікація після тегування (обов'язкова, не «розумний» пропуск)

Після кожного per-дерева проходу: відповідний gate з CLAUDE.md §3 (`bin/rubocop`, `bin/rspec`, `make -C firmware/test` [+ `asan`], `ruff check`, `forge test`) — довести, що вставка рядка нічого не зламала (особливо: чи `frozen_string_literal` й досі активний після вставки — це легко тихо зламати, тому це не «тривіальний однорядковик», а потребує runnable-перевірки за драбинкою CLAUDE.md §4).

---

## 6. Рекомендація

**DEFERRED (Phase 7), не робити зараз.** Підстави:

1. **Diff завеликий і розкиданий**: ~1200–1400 файлів по 8+ деревах, різні мови — не «керований» one-shot.
2. **4 нерозв'язані scope-питання** мають бути вирішені founder ПЕРЕД будь-яким скриптом: (a) `config/` — включати чи ні (геп в оригінальній мапі), (b) `tools/cad/` — Apache/CC0 чи AGPL для нашого коду, (c) `terraform/`+`subgraph/` — включати чи ні, (d) `spec/` — тести теж під SPDX чи ні.
3. **CubeMX-маркер нюанс** (§5.3) у `firmware/{soldier,queen}` вимагає акуратної, протестованої insertion-логіки, не «просто echo рядок на початок файлу» — інакше тихий regen-ризик.

**Що вже НЕ блокує:** SSOT-drift «мапа каже AGPL, код каже MIT» був четвертою підставою на момент аудиту — **закритий того ж дня ратифікацією DOC-T.47** (§1). Обидва документи-доми тепер описують реальний стан коду; скрипту лишається detect-and-skip.

---

## Додаток: команди відтворення лічильників

Числа в тілі документа — снепшот; відтворюй їх цими командами (усі — від кореня репо, усі спираються на `git ls-files`):

| Що рахуємо | Команда |
|---|---|
| Усього tracked-файлів | `git ls-files \| wc -l` |
| Уже теговані (усі — `contracts/*.sol`, MIT) | `git ls-files -z \| xargs -0 grep -l SPDX-License-Identifier` |
| Наївний (помилковий) raw-підрахунок для контрасту | `grep -rl SPDX-License-Identifier . --exclude-dir=.git \| wc -l` |
| Ruby-ядро | `git ls-files app lib spec scripts db \| grep -cE '\.(rb\|rake)$'` |
| Firmware non-extern (C-код) | `git ls-files firmware \| grep -v '^firmware/extern/' \| grep -cE '\.(c\|h)$'` |
| Tools non-cad (Py/Rb/sh) | `git ls-files tools \| grep -v '^tools/cad/' \| grep -cE '\.(py\|rb\|sh)$'` |
| Наш CAD-код (сіра зона, ID не обрано) | `git ls-files tools/cad \| grep -v '^tools/cad/extern/' \| grep -c '\.cs$'` |
| Config-сіра зона | `git ls-files config \| grep -cE '\.(ya?ml\|rb)$'` |
| Terraform / subgraph сірі зони | `git ls-files terraform subgraph \| grep -cE '\.(tf\|ts\|sh)$'` |
| `spec/` з `frozen_string_literal` (magic-comment ризик §5.3) | `git ls-files spec \| grep '\.rb$' \| xargs grep -l frozen_string_literal \| wc -l` |
| Native hw-design формати (зона CERN-OHL-S порожня) | `git ls-files \| grep -ciE '\.(stl\|step\|stp\|kicad_pcb\|gbr\|dxf\|scad)$'` |
| Submodule-межі (0 tracked файлів усередині) | `git ls-files -s firmware/extern tools/cad/extern` (лише gitlink `160000`) |
