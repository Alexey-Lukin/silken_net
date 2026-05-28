# 00_04: AI-Native Engineering and TRL (Philosophy)

## 🎯 Мета

Зафіксувати **філософський каркас** методології Gaia 2.0: NASA TRL як єдину метрику прогресу, Intent-First Development, Wiki-First протокол та принцип розділення SSOT від виконання. Операційні деталі (Shape Up cycle template, кластери, betting table) винесені до [`00_05_Shape_Up_Operations_and_RnD_Clusters`](00_05_Shape_Up_Operations_and_RnD_Clusters) — у цьому документі залишається тільки те, що залишається стабільним між операційними змінами.

> **Що цей документ НЕ містить:** конкретні таблиці кластерів, Betting Table процедуру, GitHub label conventions, академічний календар. Це все живе в [`00_05`](00_05_Shape_Up_Operations_and_RnD_Clusters) та [`00_07`](00_07_GitHub_Projects_and_IaC_Automation).

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — філософія імплементована та використовується як ядро проєкту.
- **Головне правило:** Ніхто (ні людина, ні ШІ) не пише код і не паяє плати, доки Специфікація не затверджена у цій Wiki.
- **Пов'язані модулі:**
  - Операційна реалізація (Shape Up, R&D кластери, Betting Table) → [`00_05_Shape_Up_Operations_and_RnD_Clusters`](00_05_Shape_Up_Operations_and_RnD_Clusters)
  - Стратегічна дорожня карта та TRL матриця → [`00_06_Strategic_Roadmap_and_HIL_Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators)
  - GitHub Projects + IaC automation → [`00_07_GitHub_Projects_and_IaC_Automation`](00_07_GitHub_Projects_and_IaC_Automation)

---

## 📏 1. Метрика Прогресу: NASA TRL (Technology Readiness Level)

Ми не міряємо роботу "спринтами" чи "сторі-поїнтами". Прогрес будь-якого з 8 Модулів Gaia 2.0 вимірюється виключно за рівнем технологічної готовності:

- **TRL 1-3 (Research & Physics):** Доведення базових принципів. Робота на папері, розрахунки, лабораторні пробірки. *(Головний агент: Gemini + Вчені ЧНУ).*
- **TRL 4-5 (Prototyping):** Створення MVP. Макетні плати (Breadboards), написання першого коду, симуляції. *(Головний агент: Cursor/Copilot).*
- **TRL 6-7 (Field Testing):** Анкер вкручено в справжнє дерево. Дані йдуть через тестову мережу (Canopy Environment).
- **TRL 8-9 (Planetary Scale):** Серійне виробництво. Mainnet (Polygon/Ethereum). Заводське штампування.
- **TRL 10-12 (Planetary Intelligence, vision):** Шкала NASA закінчується на TRL 9 («Actual system proven in operational environment»). Silken Net **розширює її** до TRL 10–12, оскільки ціль проєкту — **не просто IoT-продукт**, а **самоорганізована кібер-екосистема планетарного масштабу** (forest-level emergence, edge self-evolution, cross-biome generalization, AI-adversarial security). Деталі — [`00_06 §7`](00_06_Strategic_Roadmap_and_HIL_Simulators) Beyond TRL 9 — Planetary Intelligence Gaps.

### Суть паралельного інжинірингу

Поки Модуль 01 (Хімія) знаходиться на TRL 3 (у лабораторії), Модуль 04 (Rails) може бути на TRL 8, готуючись приймати дані. Ми не чекаємо один одного.

> **Як ми не потрапляємо у TRL-Lock:** загальний "system TRL" обмежений найнижчим модулем, але **per-domain TRL** є незалежним. Програмні домени продовжують рухатись до TRL 8-9 через HIL-симулятори (Hardware-in-the-Loop), що імітують Soldier/Queen для backend, smart-контрактів та dashboards. Деталі — [`00_06 §HIL Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators).

---

## 🤖 2. Протокол Делегування ШІ (The AI Pipeline)

Головний Архітектор працює у стані "пустої чаші" (кенозис). Він не пише код рутинно. Він керує потоком знань через 4 кроки:

1. **Ідея & Фізика (The Architect + Gemini):** Архітектор ставить глобальну проблему (напр. "Як отримати енергію без дротів?"). Gemini (LLM) виконує Deep Research, рахує фізику і видає рішення.
2. **Єдине Джерело Істини (SSOT / GitHub Wiki):** Архітектор бере рішення від Gemini і фіксує його тут, у Wiki, у вигляді жорсткої Специфікації (Markdown). *Це закон.*
3. **Виконання (Cursor / Copilot / Завод):**
   - *Для коду:* Архітектор відкриває Cursor (IDE), згодовує йому сторінку з Wiki і каже: "Напиши контролер за цією специфікацією". Cursor генерує 100% точний код без галюцинацій, бо має жорсткі рамки.
   - *Для заліза:* Архітектор відправляє сторінку з Wiki на завод для друку металу.
4. **Рев'ю (The Architect — *з делегуванням*):** Архітектор перевіряє результат і піднімає рівень TRL. Для нижчих TRL (1-4) рев'ю **делегується** лідам кластерів та CI/CD-перевіркам — Архітектор втручається тільки на TRL Gates (перехід ≥5). Це усуває bottleneck "all-roads-lead-to-Architect" (див. [`00_05 §3 Async-Review Policy`](00_05_Shape_Up_Operations_and_RnD_Clusters)).

---

## 🧠 3. Intent-First Development

AI-агенти розглядаються як автономні інженерні одиниці, що діють у межах SSOT:

- **Intent-First Development:** Перехід від написання коду до формування наміру. Код є лише похідним результатом якісно описаної специфікації в Wiki.
- **Context Anchoring:** Перед початком сесії AI-агент (Cursor / Windsurf / Claude Code) зобов'язаний проіндексувати відповідні сторінки Wiki через MCP для запобігання галюцинаціям.
- **Agent Handoff Protocol:** Ланцюжок передачі — Архітектор (Візія) → Gemini (Shaping / Специфікація) → Wiki (SSOT) → Cursor / Copilot (Імплементація) → Лабораторія ЧНУ (Фізична валідація).

---

## 🔄 4. Три паралельні потоки (The Triple Stream)

Розробка відбувається синхронно у трьох вимірах, що дозволяє уникнути простоїв софтової команди під час очікування заліза:

1. **Hardware Stream (Atoms):** Дизайн гіроїдних структур, друк Ti-6Al-4V, випробування біосумісності.
2. **Logic Stream (Bytes):** Розробка Rails-сервісів, Edge AI моделей та логіки Атрактора Лоренца.
3. **Verification Stream (Proofs):** Генерація ZK-доказів (IoTeX), налаштування DID (peaq) та оракулів (Chainlink).

> **Декаплінг через HIL:** Logic Stream і Verification Stream **не блокуються** Hardware Stream завдяки HIL-симуляторам ([`00_06 §HIL`](00_06_Strategic_Roadmap_and_HIL_Simulators)). Це підкреслює, що "Concurrent" у назві методології означає реальну паралельність, а не Waterfall з косметичними рев'ю.

### 4a. In Silico як HIL-аналог для Hardware Stream (Zero-Lab підхід)

Hardware Stream історично був "повільним" потоком (друк металу → лабораторія → in vitro → польові тести). Це **усувається** через два паралельні Code-as-Engineering трекі:

**Трек A — Code-as-Chemistry** (`01_03 §3.4`): AlphaFold 3 + OpenMM + PySCF + scipy/numpy для EBFC ферментів та матриці. **TRL 3→4 gate PASSED (2026-05-25)** — повний статус і числа: [`PIPELINE_STATUS.md`](../protocols/ebfc/in_silico/PIPELINE_STATUS.md).
**Трек B — Code-as-CAD** (`01_02 §6 PicoGK`): PicoGK + C# для гіроїдної топології через SDF/вокселі.
**Трек C — Code-as-Mechanics** (планується): FEA-симуляція напружень Ti+PEEK при +40°C/-30°C через open-source CalculiX або Code_Aster з Python wrapper'ами (закриває питання PEEK creep та механічної цілісності 20-річного horizon'у).

| HIL для Logic/Verification | In Silico для Hardware |
|---|---|
| Симулюємо Soldier/Queen без фізичного MCU | Симулюємо EBFC без фізичних ферментів + анкер без DMLS-партії |
| Прискорює backend/contracts до TRL 8 | Прискорює Module 01 (Chemistry + CAD + Mechanics) до TRL 4 |
| Python/Ruby тести | Python (AlphaFold 3, OpenMM, PySCF, scipy) + C# (PicoGK) + Python (CalculiX) |
| Cursor/Copilot пишуть тести | AI-clones пишуть симуляційні скрипти + CAD-як-код + FEA-меші |

**Архітектурний принцип "AI-агенти сліпі у GUI":** Cursor/Claude/Copilot не можуть клікати по нодах nTop, ANSYS Workbench, SolidWorks. Це **блокер AI-Native Engineering**. Усі CAD/FEA/chemistry інструменти Silken Net мігрують на **text-based code-driven API**:

| Категорія | GUI-only (legacy) | Code-driven (Silken Net target) |
|---|---|---|
| Chemistry | Gaussian / ORCA (workflow GUI) | **PySCF** (Python) |
| CAD parametric | nTop, SolidWorks, Fusion 360 | **PicoGK** (C#) |
| FEA mechanical | ANSYS Workbench, Abaqus | **CalculiX / Code_Aster** (Python wrappers) |
| Molecular Dynamics | VMD, NAMD GUI | **OpenMM** (Python) |
| Кінетика | (Custom GUIs) | **scipy/numpy** analytical models (Cantera not needed for MM+Arrhenius) |

**Ефект:** Module 01 (Hardware) **досяг TRL 4** (Zero-Lab gate PASSED 2026-05-25) **до** першого Ti-monet чи DMLS-партії. R&D-бюджет на хімію падає у 5–10 разів, на CAD-варіанти — у 10–20 разів (per-species 5 SKU генеруються за хвилини, не місяці). ЧНУ Мінаєв (`08_01 §1.1`) переходить з Gaussian/ORCA на PySCF для повної Python-керос інтеграції з Silken Net AI-pipeline.

---

## 📊 5. Управління через TRL-Ready Issues

Кожна задача в GitHub Projects маркується рівнем TRL. Задача не вважається закритою, доки її програмна реалізація не буде підтверджена:

- (a) фізичними даними або результатами лабораторних тестів, описаних у Модулі 08, **АБО**
- (b) HIL-симуляційними даними з валідною специфікацією контракту з реальним hardware, **АБО**
- (c) CI-перевірками + рев'ю від ліда кластера (для TRL 1-4 без Архітектора, див. §2 крок 4).

---

## 🔗 6. Cross-ref

- `docs/00_05_Shape_Up_Operations_and_RnD_Clusters` — операційний template 6+2 циклу, кластери, Betting Table.
- `docs/00_06_Strategic_Roadmap_and_HIL_Simulators` — TRL Matrix + per-domain TRL + HIL-симулятори.
- `docs/00_07_GitHub_Projects_and_IaC_Automation` — Projects V2 fields, labels (IaC), workflows.
- `docs/00_08_Action_Plan_Tracker` — поточний backlog задач.
- `docs/04_05_Codex_Lore_Module` — як Codex (read-only Atlas) використовує ці ж принципи для гейміфікаційного шару.
