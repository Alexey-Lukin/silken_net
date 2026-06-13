# 00_02: AI-Native Engineering and TRL (Philosophy)

## 🎯 Мета

Зафіксувати **філософський каркас** методології Gaia 2.0: NASA TRL як єдину метрику прогресу, Intent-First Development, Wiki-First протокол та принцип розділення SSOT від виконання. Операційні деталі (Shape Up cycle template, кластери, betting table) винесені до [`00_04` — Shape Up Operations and RnD Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) — у цьому документі залишається тільки те, що залишається стабільним між операційними змінами.

> **Що цей документ НЕ містить:** конкретні таблиці кластерів, Betting Table процедуру, GitHub label conventions, академічний календар. Це все живе в [`00_04`](00_04_Shape_Up_Operations_and_RnD_Clusters) та [`00_05`](00_05_GitHub_Projects_and_IaC_Automation).

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — філософія імплементована та використовується як ядро проєкту.
- **Головне правило:** Ніхто (ні людина, ні ШІ) не пише **продакшн-код** і не паяє плати, доки Специфікація не затверджена у цій Wiki. **Виняток — 🚦 Validation Gate (§2 крок 2):** одноразовий **R&D-код** (Jupyter-ноутбуки, PySCF/scipy/OpenMM-скрипти) пишеться автономними агентами *до* SSOT — це і є інструмент, яким гіпотеза валідується й стає каноном. R&D-sandbox ≠ продакшн: перше дозволено до спеки (інакше Gate неможливо пройти), друге — ні.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | TRL-матриця + per-domain TRL + HIL |
| [`00_04` — Shape Up Operations and RnD Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) | Операційна реалізація: Shape Up 6+2, R&D кластери, Betting Table |
| [`00_05` — GitHub Projects and IaC Automation](00_05_GitHub_Projects_and_IaC_Automation) | Projects V2 fields, labels-as-code, workflows |
| [`04_05` — Codex Lore Module](04_05_Codex_Lore_Module) | Codex (read-only Atlas) застосовує ці ж AI-Native принципи |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Поточний backlog задач (SSOT) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Метрика Прогресу: NASA TRL (Technology Readiness Level)](#-1-метрика-прогресу-nasa-trl-technology-readiness-level)
- [2. Протокол Делегування ШІ (The AI Pipeline)](#-2-протокол-делегування-ші-the-ai-pipeline)
- [3. Intent-First Development](#-3-intent-first-development)
- [4. Три паралельні потоки (The Triple Stream)](#-4-три-паралельні-потоки-the-triple-stream)
- [5. Управління через TRL-Ready Issues](#-5-управління-через-trl-ready-issues)
<!-- TOC:AUTO:END -->

---

## 📏 1. Метрика Прогресу: NASA TRL (Technology Readiness Level)

Ми не міряємо роботу "спринтами" чи "сторі-поїнтами". Прогрес будь-якого з 8 Модулів Gaia 2.0 вимірюється виключно за рівнем технологічної готовності:

- **TRL 1-3 (Research & Physics):** Доведення базових принципів. Робота на папері, розрахунки, лабораторні пробірки. *(Головний агент: frontier-LLM + домен-експерти ЧНУ; ростер → §2).*
- **TRL 4-5 (Prototyping):** Створення MVP. Макетні плати (Breadboards), написання першого коду, симуляції. *(Головний агент: coding-agent).*
- **TRL 6-7 (Field Testing):** Анкер вкручено в справжнє дерево. Дані йдуть через тестову мережу (Canopy Environment).
- **TRL 8-9 (Planetary Scale):** Серійне виробництво. Mainnet (Polygon/Ethereum). Заводське штампування.
- **Beyond TRL 9 (Planetary Intelligence, vision) — НЕ «TRL 10-12»:** Шкала NASA/ISO 16290 закінчується на **TRL 9** і вимірює виключно **готовність самої технології**. Технологія на TRL 9 не стає «технічно готовішою» від друку 1 млн анкерів замість 100 — масштаб, cross-biome адаптація та forest-level emergence є **системною та виробничою** зрілістю, а не технологічною. Тому ми НЕ вигадуємо «TRL 10-12» (це виглядало б некомпетентно перед Horizon Europe / ESA, які суворо дотримуються 1-9), а використовуємо профільні шкали:
  - **SRL (System Readiness Level)** — інтеграційна/системна зрілість: cross-biome generalization, forest-level emergence, edge self-evolution, AI-adversarial security.
  - **MRL (Manufacturing Readiness Level, 1-10)** — виробнича зрілість: серійний друк 5 SKU, заводське штампування.
  - Деталі — [`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap) Beyond TRL 9 — Planetary Intelligence Gaps.

### Суть паралельного інжинірингу

Поки Модуль 01 (Хімія) знаходиться на TRL 3 (у лабораторії), Модуль 04 (Rails) може бути на TRL 8, готуючись приймати дані. Ми не чекаємо один одного.

> **Як ми не потрапляємо у TRL-Lock:** загальний "system TRL" обмежений найнижчим модулем, але **per-domain TRL** є незалежним. Програмні домени продовжують рухатись до TRL 8-9 через HIL-симулятори (Hardware-in-the-Loop), що імітують Soldier/Queen для backend, smart-контрактів та dashboards. Деталі — [`00_03 §HIL Simulators`](00_03_TRL_Matrix_HIL_and_Beyond).

---

## 🤖 2. Протокол Делегування ШІ (The AI Pipeline)

> **Поточний AI-ростер (знімок — ЄДИНИЙ дім, drift-tolerant).** Канон описує **ролі** (стабільні); конкретні інстанси волатильні (ростер скорочується/росте з часом), тож правити **лише цю таблицю** — решта канону реферить *роль*, не вендора. Домен-експерти (людська валідація на 🚦 Validation Gate) — ростер ВНЗ у [`08_02`](08_02_Academic_Institutions_Registry).
>
> | Роль (стабільна) | Поточні інстанси (волатильні — оновлювати ТУТ) |
> |---|---|
> | **frontier-LLM** — гіпотеза / shaping / Deep-Research | Gemini · ChatGPT/OpenAI · Claude (Opus/Sonnet/Fable) · Grok · DeepSeek |
> | **coding-agent** — spec → код в IDE/CLI | Cursor · GitHub Copilot · Codex · Claude Code |

Головний Архітектор працює у стані "пустої чаші" (кенозис). Він не пише код рутинно. Він керує потоком знань через 5 кроків (з обов'язковим Validation Gate):

1. **Ідея & Гіпотеза (The Architect + frontier-LLM):** Архітектор ставить глобальну проблему (напр. "Як отримати енергію без дротів?"). frontier-LLM виконує Deep Research і пропонує **напрям рішення**.

   > **⚠️ Критично: LLM НЕ «рахує фізику» — він пропонує гіпотезу.** LLM галюцинують одиницями, плутають константи й імітують логічні висновки. Реальні приклади, спіймані в цьому проєкті: «затоплення катода» radom'ом, мінорантні методи Піявського для хаотичного ряду, термоопік від мікрофрези на низьких обертах, хибна «мінімізація» булевої TX-логіки, премиса про «неминучу divergence Z через флоат». Якщо взяти LLM-«фізику» і забетонувати її як закон — програмуєш завод на брак.

2. **🚦 Validation Gate (ОБОВ'ЯЗКОВИЙ, перед SSOT):** Гіпотеза LLM стає «законом» ЛИШЕ після незалежної валідації одним із:
   - **аналітичні/чисельні скрипти** (Python/scipy, PySCF, OpenMM) з відтворюваними метриками;
   - **домен-експерт** (ЧНУ/ЧДТУ — Мінаєв, Гусак, Порубльов тощо);
   - **крос-перевірка** (cross-validated In-Silico report, [`PIPELINE_STATUS.md`](../protocols/ebfc/in_silico/PIPELINE_STATUS.md)).
   До проходження Gate результат маркується як **гіпотеза/draft**, а не SSOT.

3. **Єдине Джерело Істини (SSOT / GitHub Wiki):** Архітектор фіксує **валідоване** рішення у Wiki як жорстку Специфікацію (Markdown). *Це закон — але тільки після Gate.*
4. **Виконання (coding-agent / Завод):**
   - *Для коду:* Архітектор відкриває coding-agent (IDE/CLI), згодовує йому сторінку з Wiki і каже: "Напиши контролер за цією специфікацією". Жорстка специфікація **різко знижує** галюцинації, але код усе одно проходить тести/рев'ю (специфікація ≠ гарантія коректності реалізації).
   - *Для заліза:* Архітектор відправляє сторінку з Wiki на завод для друку металу.
5. **Рев'ю (The Architect — *з делегуванням*):** Архітектор перевіряє результат і піднімає рівень TRL. Для нижчих TRL (1-4) рев'ю **делегується** лідам кластерів та CI/CD-перевіркам — Архітектор втручається тільки на TRL Gates (перехід ≥5). Це усуває bottleneck "all-roads-lead-to-Architect" (див. [`00_04 §3 Async-Review Policy`](00_04_Shape_Up_Operations_and_RnD_Clusters)).

---

## 🧠 3. Intent-First Development

AI-агенти розглядаються як автономні інженерні одиниці, що діють у межах SSOT:

- **Intent-First Development:** Перехід від написання коду до формування наміру. Код є лише похідним результатом якісно описаної специфікації в Wiki.
- **Context Anchoring:** Перед початком сесії coding-agent (IDE/CLI) зобов'язаний проіндексувати відповідні сторінки Wiki через MCP для запобігання галюцинаціям.
- **Agent Handoff Protocol:** Ланцюжок передачі — Архітектор (Візія) → frontier-LLM (Shaping / гіпотеза) → **🚦 Validation Gate** (скрипти / домен-експерт) → Wiki (SSOT, лише валідоване) → coding-agent (Імплементація) → Лабораторія ЧНУ (Фізична валідація).
- **SSOT One-Home (одна річ — один дім):** кожен факт має **ОДИН** канонічний дім; решта доків **реферять**, не дублюють (інакше — тихий SSOT-дрейф). Коли тема переростає свій док, її **виносять у власну канон-сторінку** (migrate-first, zero content-loss); а спростовану/застарілу після піву гіпотезу **видаляють** (Ruthless Pruning — Git тримає історію), а не «мігрують про всяк випадок» у wiki-звалище ([`00_06 §4`](00_06_SSOT_Documentation_Standard)). Реєстр домів + restructure/prune-метод — [`00_06 §2/§4`](00_06_SSOT_Documentation_Standard). drift-лінтери (`docs:check_refs`) автоматично ловлять re-statement **конкретних owned-значень** (Lorenz β, RTC-реєстри, mint/carbon-курс — owner-only vocabulary), але **НЕ** загальне семантичне дублювання (той самий факт іншими словами) — воно лишається ручним SSOT-аудитом Архітектора у cool-down ([`00_06 §3`](00_06_SSOT_Documentation_Standard)).

---

## 🔄 4. Три паралельні потоки (The Triple Stream)

Розробка відбувається синхронно у трьох вимірах, що дозволяє уникнути простоїв софтової команди під час очікування заліза:

1. **Hardware Stream (Atoms):** Дизайн гіроїдних структур, друк Ti-6Al-4V, випробування біосумісності.
2. **Logic Stream (Bytes):** Розробка Rails-сервісів, Edge AI моделей та логіки Атрактора Лоренца.
3. **Verification Stream (Proofs):** Генерація ZK-доказів (IoTeX), налаштування DID (peaq) та оракулів (Chainlink).

> **Декаплінг через HIL:** Logic Stream і Verification Stream **не блокуються** Hardware Stream завдяки HIL-симуляторам ([`00_03 §HIL`](00_03_TRL_Matrix_HIL_and_Beyond)). Це підкреслює, що "Concurrent" у назві методології означає реальну паралельність, а не Waterfall з косметичними рев'ю.

### 4a. In Silico як HIL-аналог для Hardware Stream (Zero-Lab підхід)

Hardware Stream історично був "повільним" потоком (друк металу → лабораторія → in vitro → польові тести). Це **усувається** через два паралельні Code-as-Engineering трекі:

**Трек A — Code-as-Chemistry** ([`01_03 §3.4`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)): AlphaFold 3 + OpenMM + PySCF + scipy/numpy для EBFC ферментів та матриці. **TRL 3→4 gate PASSED (2026-05-25)** — повний статус і числа: [`PIPELINE_STATUS.md`](../protocols/ebfc/in_silico/PIPELINE_STATUS.md).
**Трек B — Code-as-CAD** ([`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)): тут **дві різні ролі**, які не можна плутати. **PicoGK (C#)** — справжній *CAD-as-code*: SDF/воксельне ядро, де AI-агент генерує геометрію (новий тип гіроїда) **з нуля** кодом. **nTop Automate** (CLI/API) — це НЕ авторинг геометрії кодом, а **headless parameter-sweep** уже створеного в GUI `.ntop`-воркфлоу: AI варіює вхідні змінні (товщина стінки, період комірки → 5 SKU за хвилини), але **базовий шаблон спершу «наклацує» GUI-інженер**. Підсумок: from-scratch generation = PicoGK; автоматизована параметризація готового шаблону = nTop Automate.

> **⚠️ «Трек C — Code-as-Mechanics» ВИДАЛЕНО:** важка механіка полімерів (в'язкопружність PEEK, Prony series, термонапруження Ti+PEEK, 20-річний creep) канонічно закріплена за **лабораторією Гусака (ЧНУ) на ANSYS LS-DYNA** ([`01_01 §4.3`](01_01_Coaxial_Gyroid_Topology_and_PEEK), [`08_02`](08_02_Academic_Institutions_Registry), [`08_01 §1F`](08_01_Joint_Publications_and_IP_Strategy)). Паралельний AI-трек на CalculiX дав би **другий, неузгоджений** результат і знецінив би роботу професорів. In-silico конвеєр Архітектора покриває лише **Хімію** (PySCF/OpenMM), **Геометрію** (CAD-as-code) та **Кінетику** (scipy) — FEA/creep лишається аутсорсною R&D-функцією ЧНУ.

| HIL для Logic/Verification | In Silico для Hardware |
|---|---|
| Симулюємо Soldier/Queen без фізичного MCU | Симулюємо EBFC без фізичних ферментів + анкер без DMLS-партії |
| Прискорює backend/contracts до TRL 8 | Прискорює Module 01 (Chemistry + CAD) до TRL 4 |
| Python/Ruby тести | Python (AlphaFold 3, OpenMM, PySCF, scipy) + C# (PicoGK) |
| coding-agent пише тести | AI пишуть симуляційні скрипти + from-scratch CAD-as-code (**PicoGK**); **nTop Automate** лише параметризує готовий GUI-шаблон |

**Архітектурний принцип — НЕ «відмова від GUI-інструментів», а headless/API-driven доступ:** проблема не в тому, що nTop/ANSYS погані (nTop — найпотужніший рушій TPMS у світі), а в тому, що AI-агент не клікає по GUI. Рішення — **керувати тими ж індустріальними гігантами через їхні офіційні Python/CLI API**, а не переписувати CAD на C# «бо так зручніше LLM»:

| Категорія | GUI-режим (для людини) | Code/API-driven (для AI-агентів) |
|---|---|---|
| Chemistry | Gaussian / ORCA (workflow GUI) | **PySCF** (Python) — справжній стандарт |
| CAD parametric / TPMS | nTop Workbench, SolidWorks | **PicoGK** (C#, from-scratch code-native) + **nTop Automate** (CLI parameter-sweep готового `.ntop`-шаблону) |
| FEA mechanical | ANSYS Workbench | **PyAnsys / PyMAPDL / PyDPF** (headless ANSYS — у Гусака, ЧНУ) |
| Molecular Dynamics | VMD, NAMD GUI | **OpenMM** (Python) — справжній стандарт |
| Кінетика | (Custom GUIs) | **scipy/numpy** analytical models (Cantera not needed for MM+Arrhenius) |

**Ефект:** In-Silico конвеєр дозволяє ідеально відшліфувати **TRL 3** (аналітичний/математичний PoC) і підготувати бездоганну хімічну/CAD-базу **перед** дорогим переходом на **TRL 4** (фізична лабораторія: перші Ti-coin + DMLS-партія — Stage 2, ще не закрито). ⚠️ За строгим NASA / ISO 16290 in-silico ≠ TRL 4 (той вимагає breadboard/component validation **у залізі**) — тому Zero-Lab «gate PASSED» означає «**TRL 3 повністю валідовано + GO-рішення фінансувати TRL 4**», а НЕ «ми вже на TRL 4» (та сама ригористика, що й «без TRL 10-12», §1). R&D-бюджет на хімію падає у 5–10 разів, на CAD-варіанти — у 10–20 разів (per-species 5 SKU генеруються за хвилини, не місяці). Канон per-module TRL — [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond). ЧНУ Мінаєв ([`08_01 §1`](08_01_Joint_Publications_and_IP_Strategy), Стаття 1) переходить з Gaussian/ORCA на PySCF для повної Python-інтеграції з Silken Net AI-pipeline.

---

## 📊 5. Управління через TRL-Ready Issues

Кожна задача в GitHub Projects маркується рівнем TRL. Задача не вважається закритою, доки її програмна реалізація не буде підтверджена:

- (a) фізичними даними або результатами лабораторних тестів, описаних у Модулі 08, **АБО**
- (b) HIL-симуляційними даними з валідною специфікацією контракту з реальним hardware, **АБО**
- (c) CI-перевірками + рев'ю від ліда кластера — **тільки для Logic/Verification стрімів (Bytes/Proofs)** (для TRL 1-4 без Архітектора, див. §2 крок 5).

> **⚠️ Корекція: для Hardware/Chemistry (Atoms) самих CI-перевірок НЕДОСТАТНЬО.** Зелений CI доводить, що **код виконується**, а не що **фізика коректна** — PySCF-скрипт може відпрацювати без помилок і видати термодинамічно абсурдний результат. Тому:
> - **Logic / Verification (Bytes / Proofs):** CI + HIL-симуляції + code review — достатньо (критерій (c)).
> - **Hardware / Chemistry (Atoms):** CI необхідний, але НЕ достатній. Вимагаються **згенеровані ТА валідовані фізичні метрики** (напр., ΔG < 0, RMSD < поріг, k_ET у літературному діапазоні), підтверджені домен-експертом або крос-перевіркою (cross-validated In-Silico report, [`PIPELINE_STATUS.md`](../protocols/ebfc/in_silico/PIPELINE_STATUS.md)) — тобто пройдений **Validation Gate** (§2 крок 2).
