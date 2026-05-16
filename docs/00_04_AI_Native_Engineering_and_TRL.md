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
