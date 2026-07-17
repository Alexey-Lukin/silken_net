# 07_03: Трекер Грантових Заявок (Стратегічне Фінансування)

## 🎯 Мета

Зафіксувати стратегію залучення децентралізованого капіталу (Grants, Donations) та партнерств у екосистемі Web3/DePIN. Цей документ слугує оперативним трекером для поданих заявок, визначає ролі кожного фонду в архітектурі SilkenNet та фокусує команду на виконанні KPI для отримання наступних траншів.

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — заявки подано до 7 екосистем; чекаємо відповідей. ⚠️ Заявки подані від фіз-особи (Oleksii Lukin); milestone-acceptance / отримання коштів гейтовані на інкорпорацію юр-особи-заявника ([`00_07` BIZ.20](00_07_Action_Plan_Tracker))
- **Готові артефакти:** Технічна документація Wiki, BOM, демо Attractor, збірна інструкція.
- **Відкрите:** відповіді від 7 грантових екосистем — зовнішнє очікування (активного трекер-айтема немає; дія народжується з відповіді). Підготовка Horizon/EF-заявок → [`00_07`](00_07_Action_Plan_Tracker) BIZ.12 (академ-гейти UNI.1/UNI.14).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн (EF/IoTeX grant теми) |
| [`07_01` — Nature as a Service Contracts](07_01_Nature_as_a_Service_Contracts) | NaaS value-prop |
| [`07_02` — Unit Economics and BOM](07_02_Unit_Economics_and_BOM) | Unit economics для заявок |
| [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) | академічні гранти |
| [`08_01` — Joint Publications and IP Strategy](08_01_Joint_Publications_and_IP_Strategy) | Twin-pack / Horizon консорціум backbone (§1G) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | BIZ.12, UNI.1/UNI.14 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Карта Стратегічних Грантів (Ecosystem Matrix)](#-1-карта-стратегічних-грантів-ecosystem-matrix)
- [2. Деталізація Цінності (Value Proposition per Partner)](#-2-деталізація-цінності-value-proposition-per-partner)
- [3. Модель Public Goods Funding (Giveth.io)](#-3-модель-public-goods-funding-givethio)
- [4. Артефакти для Milestone 1 (Grant Deliverables)](#-4-артефакти-для-milestone-1-grant-deliverables)
- [5. Інструкція Монтажу Анкера (Field Assembly Guide)](#-5-інструкція-монтажу-анкера-field-assembly-guide)
- [6. Інструменти для Паралельної Розробки (Virtual Prototyping)](#-6-інструменти-для-паралельної-розробки-virtual-prototyping)
- [7. Дорожня Карта Фінансування (Funding Roadmap)](#-7-дорожня-карта-фінансування-funding-roadmap)
- [8. Академічні Гранти (Horizon Europe & Ethereum Foundation)](#-8-академічні-гранти-horizon-europe--ethereum-foundation)
- [9. Грантова Дипломатія (Cross-chain Grant Strategy)](#-9-грантова-дипломатія-cross-chain-grant-strategy)
<!-- TOC:AUTO:END -->

---

## 🛰️ 1. Карта Стратегічних Грантів (Ecosystem Matrix)

| Екосистема | Категорія гранту | Роль у SilkenNet | Статус |
|---|---|---|---|
| **peaq** | DePIN / Machine Rewards | Machine DID для кожного "Солдата" | Подано |
| **IoTeX** | Halo / W3bstream | ZK-proofs для верифікації телеметрії | Подано |
| **Chainlink** | BUILD / Social Impact | Оракули для мінтингу та Slashing | Подано |
| **Filecoin** | Green Data / Storage | Незмінний архів телеметрії лісу | Подано |
| **Giveth.io** | Public Goods / ReFi | Донати від спільноти + GIVmatching | Подано ✅ Активний |
| **Solana** | DePIN Track | Мікро-винагороди у USDC за гомеостаз | Подано |
| **Polygon** | Hadron (Institutional) | KYC-compliance для Carbon Credits | Подано |

---

## 🛠️ 2. Деталізація Цінності (Value Proposition per Partner)

### 🆔 peaq (The Identity Provider)

- **Навіщо їм ми:** Найбільший у світі живий флот "Машин" (дерев), що мають суверенний DID
- **Наш запит:** Грант на інтеграцію `peaq-pallet-did` у наш бекенд та підтримку "Economy of Things"

### 🧮 IoTeX (The Verification Layer)

- **Навіщо їм ми:** Складний кейс для W3bstream — верифікація біологічного гомеостазу через ZK-SNARKs
- **Наш запит:** Технічна підтримка для розгортання zkVM логіки Атрактора Лоренца

### 🌉 Chainlink (The Truth Bridge)

- **Навіщо їм ми:** Демонстрація Chainlink Functions як критичної ланки між IoT та On-chain фінансами
- **Наш запит:** Доступ до програми BUILD та субсидування Gas-витрат для оракулів

### 🧊 Filecoin (The Eternal Memory)

- **Навіщо їм ми:** Величезні масиви "зелених даних" (Environmental Data), що мають зберігатися вічно для аудиту вуглецевих кредитів
- **Наш запит:** Грант на зберігання даних та статус "Verified Client"

---

## 🌱 3. Модель Public Goods Funding (Giveth.io)

**Статус:** ✅ Профіль активний. Очікуємо донатів від спільноти та GIVmatching-раундів.

На відміну від інвестиційних грантів, **Giveth.io** дозволяє залучати капітал від спільноти, яка вірить у збереження природи.

**Стратегія:**
- Профіль: **"Черкаський Бір — SilkenNet"** (з фото реального Черкаського бору та прив'язкою до локації)
- **GIVpower:** Механіка "GIVmatching" — кожен донат у раунді подвоюється протоколом
- **Комунікація:** Публікації progress updates (монтаж анкерів, перші дані, університетська R&D)
- **Цільовий збір:** Закупівля першої партії 100 титанових анкерів (після ліцензії nTop + DMLS-виробника)

**Чому Giveth важливий:** Навіть при малих сумах донатів, присутність на Giveth сигналізує климатичним фондам (Celo, KlimaDAO, Gitcoin), що проєкт "живий" та має підтримку спільноти. Це підвищує шанси на отримання більших грантів.

---

## 📋 4. Артефакти для Milestone 1 (Grant Deliverables)

Для успішного проходження першого етапу (Milestone Acceptance) більшість фондів вимагає:

| Артефакт | Статус | Де знайти |
|---|---|---|
| **GitHub Repository** (відкритий код — AGPL-3.0 / CERN-OHL-S / CC-BY-SA; defensive-publication, [`08_01 §2`](08_01_Joint_Publications_and_IP_Strategy)) | ✅ Готово | github.com/Alexey-Lukin/silken_net |
| **Technical Wiki** (архітектурна документація) | ✅ Готово | wiki цього репозиторію |
| **Demo** (Lorenz Attractor візуалізація) | ✅ Готово | згідно Wiki 03_04 |
| **BOM & Unit Economics** | ✅ Готово | wiki 07_02 |
| **Assembly Instructions** (інструкція монтажу анкера) | ✅ Написано | нижче в цьому документі |
| **R&D Protocol** (університетська верифікація) | 🟡 Формується | wiki 08_01 |
| **Breadboard Video** (демо енергетичного каскаду) | 🔴 Потрібно записати | — |

> **Ключовий інсайт:** Наявність **технічної документації та мануалу з монтажу** переводить проєкт із категорії "гола ідея" в категорію "продукт на стадії впровадження". Це критично для оцінки фондами (Gitcoin/Giveth) та кліматичними організаціями.

---

## 🔧 5. Інструкція Монтажу Анкера (Field Assembly Guide)

> **Канон процедури встановлення — [`01_04 §3`](01_04_CODIT_and_Xylemointegration) (Flush Mount + Microfrezing).** Ця секція — спрощений польовий **grant-deliverable** для арбористів/волонтерів (15-хв чек-лист), а не заміна хірургічного протоколу. ⚠️ Свердління нижче — **fallback-режим** для польових умов без прецизійного інструменту ([`01_04 §3.4`](01_04_CODIT_and_Xylemointegration)); канон рекомендує **microfrezing** (свердло тригерить resinosis — [`01_04 §3.3`](01_04_CODIT_and_Xylemointegration)), а при свердлінні **обов'язкові** anti-resin стратегії (Nafion-g-PSBMA).

> Документ написаний для арбористів та волонтерів без технічного бекграунду. Мета: за 15 хвилин встановити повністю функціональний Soldier-вузол на живому дереві.

### Що потрібно (BOM для монтажу)

- Гіроїдний анкер (Ti-6Al-4V, 120 мм) — 1 шт.
- Капсула електроніки (PCB з BQ25570 + STM32WLE5JC) — 1 шт.
- Дриль із свердлом 8 мм (або спеціальний дриль-адаптер)
- Торцевий ключ М6
- Силіконовий герметик (для заповнення зазору між корою та анкером)

### Кроки монтажу

**Крок 1: Вибір точки на дереві**
- Висота від землі: 1.2–1.5 м (на рівні грудей)
- Орієнтація: сторона, що виходить на північ (менше прямого сонця = менше теплових стресів)
- Уникати: місць із ознаками грибка, механічних пошкоджень, близькості до основних коренів

**Крок 2: Буріння отвору**
- Кут: 90° до осі стовбура (строго горизонтально)
- Глибина: 120 мм (довжина анкера)
- Діаметр: 7.5–8 мм (анкер закручується із зусиллям)

**Крок 3: Монтаж анкера**
- Вставити гіроїд заокругленим кінцем у отвір
- Закрутити ключем М6 до упору (не перетягувати — момент < 5 Нм)
- Нанести силіконовий герметик навколо зовнішнього краю (захист від проникнення комах)

**Крок 4: Підключення капсули**
- Накрутити пластикову капсулу на шляпу анкера (аналогічно кришці на пляшку)
- Pogo Pins автоматично встановлять контакт із анодом та катодом
- Закрутити до клацання O-Ring ущільнювача (IP68 захист)

**Крок 5: Перевірка**
- LED на капсулі моргне синім через 15–30 хвилин після монтажу (перший LoRa TX після зарядки суперконденсатора до 3.4V)
- Якщо LED не блимає за 1 годину → перевірити орієнтацію анкера та контакти Pogo Pin

---

## 💻 6. Інструменти для Паралельної Розробки (Virtual Prototyping)

> **Канон dev/prototyping toolchain** (LTspice, KiCad, Wokwi, Proteus, STM32CubeIDE, ST-LINK-V3MINIE) — [`02_01 §7`](02_01_Hardware_Architecture_and_BOM) (Development Toolchain). **Управління секретами** при деплої (Bitwarden/1Password, окремий vault per-середовище) — [`06_04`](06_04_Secrets_Checklist). Тут не дублюємо — SSOT тримає один дім; для грантів ці інструменти потрібні лише як deliverable-чекліст (вище §4).

---

## 🗺️ 7. Дорожня Карта Фінансування (Funding Roadmap)

```
Зараз:     Чекаємо відповідей грантів + донати Giveth
           │
           ▼
Q2 2026:   Перший транш → Закупівля компонентів (деталі для прототипу)
           → Тестова партія 100 анкерів (Київ/Дніпро DMLS)
           │
           ▼
Q3 2026:   Розгортання першого кластера (Черкаський бір, 10–20 дерев)
           → Перші дані телеметрії → Перший SCC-мінт
           → R&D звіт ЧНУ (протокол «Long-Term Integrity»)
           │
           ▼
Q4 2026:   Seed-раунд (climate/deeptech фонди)
           → Дані + університетська верифікація + перший SCC = strong pitch
           │
           ▼
2027:      Scale-out: 1,000 дерев → NaaS-контракти → Carbon Credits
```

---

## 🏛️ 8. Академічні Гранти (Horizon Europe & Ethereum Foundation)

> **Стратегічний рівень:** Web3-екосистемні гранти (секції 1-7) покривають технічну інфраструктуру. Horizon Europe та Ethereum Foundation гранти легітимізують проєкт для інституційних інвесторів та ESG-регуляторів ЄС.

### Horizon Europe CLUSTER 6 (Climate, Energy, Mobility)

| Параметр | Деталі |
|---|---|
| **Програма** | Horizon Europe CLUSTER 6 — Biodiversity Monitoring, Digital Twins |
| **Тип** | Research and Innovation Action (RIA) або EIC Pathfinder/Accelerator |
| **Орієнтовний бюджет** | €3–5M на 4 роки |
| **Вимоги до консорціуму** | Мін. 3 країни ЄС; Ukraine є асоційованою країною (partial eligibility) |
| **Статус** | Не подано — потребує підготовки |
| **Академічний лідер консорціуму** | **ЧНУ (Спрягайло О.В., проректор з науки)** — координація консорціуму (ЧНУ/ЧДТУ/СЄУ + ActiveBridge + лісові господарства); Triple Helix модель. ⚠️ Перепризначено 2026-07-17 (UNI.19): попередня носійка ролі мала **0 публікаційних ланок** у портфелі — роль потребувала наукового тилу |
| **Парасоль ЧНУ (інституційний)** | **В.о. ректора Кирилюк Є.М.** (директор ННІ економіки і права) — підпис парасольового MoU ЧНУ↔Silken Net, ко-PI WP-Bioeconomy; **проректор з науки Спрягайло О.В.** — ко-PI WP-Biodiversity, регіональний contact з Черкаською ОДА, ПЗФ-сумісність pilot'у. Деталі: [`08_02 §1A`](08_02_Academic_Institutions_Registry), [`08_01 §1G`](08_01_Joint_Publications_and_IP_Strategy). |

**Структура консорціуму для Horizon Europe:**

```
WP1 Coordination & Dissemination → ЧНУ (Спрягайло О.В. — координація) + СЄУ (Гедз М.) + ЧНУ парасоль (Кирилюк Є.М.)
WP2 Hardware & Materials          → ЧНУ (Гусак, Мінаєв) + ЧМА (токсикологія) + Silken Net
WP3 Firmware & Edge AI            → ЧНУ ФОТІУС (Порубльов, Ярмілко) + ЧДТУ (Карапетян)
WP4 D-MRV Methodology             → СЄУ (Гедз М.) + ЧДТУ (Карапетян) + ЧНУ біо-хаб (Спрягайло — ground truth)
WP5 Legal & Compliance            → СЄУ (Аблязов Д., Ус Г.) + ЧНУ біо-хаб (Спрягайло — ПЗФ-сумісність)
WP6 Industrial Design             → СЄУ (Денисенко, Теліженко)
WP7 Bioeconomy & Tokenized Markets → ЧНУ ректорат (Кирилюк Є.М.) + СЄУ (Чудаєва) — теоретична рамка SCC/NaaS
WP8 Biodiversity Baseline (Cluster 6) → ЧНУ біо-хаб (Спрягайло, Гаврилюк) + ЧДТУ ПМКТ (Базіло, Бондаренко) — Cherkasy Soundscape Library
WP9 Exploitation & IPR            → ActiveBridge + Silken Net
```

> **Twin-pack publication backbone (cross-ref [`08_01 §1G`](08_01_Joint_Publications_and_IP_Strategy)):** **Стаття 34** (Кирилюк ↔ синергетика порогового гейта Лоренца) обґрунтовує **WP7**; **Стаття 35** (Кирилюк ↔ Спрягайло біоекономіка) і **Стаття 24a** (Спрягайло ↔ Mongabay) — **WP8**. Подання до журналу Q1 за 2–3 місяці до Horizon-deadline переводить заявку з категорії «концепт» у «published research» (вирішальне для evaluators).

**Зв'язок з кодбейсом:** Horizon Europe вимагає Open Science — `StateRootAnchor.sol` (публічна верифікація), Filecoin-архів телеметрії, The Graph subgraph (публічний доступ до даних).

### Ethereum Foundation Academic Grants

| Параметр | Деталі |
|---|---|
| **Програма** | Ethereum Foundation Academic Grants Round |
| **Тип** | Research grant до $150K |
| **Фокус** | ZK-proofs, DePIN, on-chain verifiable data, public goods |
| **Статус** | Не подано |
| **Академічний лідер** | **Архітектор (Silken Net)** — тема заявки (ZK-proofs W3bstream на STM32WLE5JC) = наш власний технічний домен, не академічний. Академ-співавтори за потреби: ФОТІУС (Порубльов — Lorenz/DCI-математика, Ярмілко — embedded-крипто) ⚖️ при підготовці подачі |

**Тема заявки:** _"Trustless D-MRV: IoTeX W3bstream ZK-proofs for biological homeostasis verification on STM32WLE5JC edge devices"_ — пов'язано з `IotexVerificationWorker`, `Iotex::W3bstreamVerificationService` та [`05_02`](05_02_Proof_of_Growth_Pipeline).

> **Детально про консорціум та грантову стратегію:** [`08_02 §5`](08_02_Academic_Institutions_Registry) (СЄУ; консорціум-лідерство → Спрягайло, §8 вище).

## 🗺️ 9. Грантова Дипломатія (Cross-chain Grant Strategy)

> Стратегічний протокол подачі грантових заявок: кому, про кого і як розповідати для максимального результату на технічних дзвінках (Technical Due Diligence).

### Загальне Позиціонування

SilkenNet = **Modular DePIN Stack** (агностична інфраструктура). Не "кидаємо" одну мережу заради іншої — кожна вирішує свій шар. Це усуває звинувачення в "зраді" і позиціонує як **Системного Архітектора**, а не "шукача грантів".

> Відповідь на питання "Чому ви подалися до конкурентів?":
> *"SilkenNet — це інфраструктурний проєкт планетарного масштабу. Ми збираємо найкращий технологічний стек у світі: хтось вирішує швидкість транзакцій, хтось — ідентичність машин, хтось — вічне зберігання даних."*

---

### Шпаргалка по Аудиторії

| Грантодавець | Наш Статус для Них | Про кого КАЗАТИ | Про кого МОВЧАТИ |
|---|---|---|---|
| **Solana Foundation** | "High-Speed DePIN Execution Layer" | Chainlink (оракули), IoTeX (верифікація заліза) | peaq, Ethereum (конкуренти за "найкращу мережу") |
| **peaq / IoTeX** | "Machine Economy / DePIN Infrastructure" | Один про одного, Filecoin (зберігання біо-даних) | Solana як "основний дім" (вони хочуть власні L2) |
| **Chainlink** | "Cross-chain Oracle Consumer" | ВСІХ — Chainlink "Швейцарія", їм вигідне охоплення всіх мереж | — (немає ворогів) |
| **Ethereum Foundation (ESP)** | "Public Good / ReFi" | Filecoin, Chainlink, ReFi-спільнота | Solana "вона краща" — EF цінує ідеологію, а не швидкість |
| **Climate.biz / KlimaDAO** | "ReFi Natural Capital Protocol" | IoTeX (trustless hardware data), Filecoin (незмінний аудит) | Фінансові спекуляції, "швидкі гроші" |
| **Filecoin / Protocol Labs** | "DePIN Data Archive (Hardware-to-IPFS)" | Ethereum, IoTeX | Суто фінансові проєкти без реальних даних |
| **Polygon / Hadron** | "RWA Natural Capital (ERC-3643)" | IoTeX ZK-proof, Chainlink oracle | — |

---

### Elevator Pitch по Аудиторії (Дипломатична версія)

| Кому | Ключова фраза |
|---|---|
| **Solana** | *"Solana — наш Execution Layer для Proof of Growth мікроплатежів. Chainlink доставляє ZK-дані з IoTeX в наші Solana смарт-контракти."* |
| **peaq / IoTeX** | *"Кожне дерево отримує peaq Machine DID при провізіонінгу. IoTeX W3bstream верифікує кожен пакет телеметрії. Filecoin архівує всі дані назавжди."* |
| **Chainlink** | *"Ми розгортаємося на Solana, Polygon та Ethereum одночасно. Chainlink Functions — наш єдиний trusted міст між IoTeX ZK-proof і смарт-контрактами на всіх мережах."* |
| **Ethereum Foundation** | *"SilkenNet — Public Good планетарного масштабу. Щотижневий SHA-256 State Root anchoring на Ethereum L1 гарантує незмінність даних про ліс на десятки років."* |
| **Filecoin / Protocol Labs** | *"Кожен день AuditLogWorker архівує терабайти біо-телеметрії в IPFS/Filecoin. Через 10 років будь-який аудитор може перевірити кожну секунду життя кожного дерева."* |
