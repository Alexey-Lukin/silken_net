# 02_06: Юніт-економіка та BOM (Unit Economics & BOM)

---

## 🎯 Мета

Зафіксувати **вартісний бік заліза**: BOM одного вузла «Soldier» і шлюзу «Queen», витратні матеріали, економіку анкера, CAPEX/OPEX кластера, модель окупності та ланцюг постачання. Документ відповідає на питання «**за скільки**» — на відміну від [`07_01`](07_01_Nature_as_a_Service_Contracts), який відповідає «**за яким договором**».

> ⚙️ **Спека-at-source лишається біля своєї підсистеми.** Тут — АГРЕГАТ і ціна: компонентні специфікації живуть у [`02_01`](02_01_Hardware_Architecture_and_BOM) (Soldier) і [`02_05`](02_05_Queen_Hardware_and_Starlink) (Queen), а цей док їх підсумовує. Рольова межа `spec-at-source → aggregate → price` — [`00_06 §2`](00_06_SSOT_Documentation_Standard); не втягуй сюди специфікацій і не розсипай звідси агрегатів.

> 🗃️ **Провенанс сторінки.** Тіло виділено з [`07_01`](07_01_Nature_as_a_Service_Contracts) 2026-08-22 (DOC-T.83) — розворот злиття DOC-T.68 фази 5, яке 2026-08-10 зсунуло ці секції на +10. Нумерацію `§1`–`§10` **відновлено**, і саме тому 48 внутрішніх самопосилань тіла знову резолвляться без жодної правки — вони весь час були написані під цю нумерацію.

---

## ✅ Статус

- **Стан:** Вартісна модель зафіксована в SSOT; ціни підтверджені локальними постачальниками, RFQ-шар відкритий. Шкала готовності тут **незастосовна** — предмет вартісна економіка заліза, а не готовність технології ([`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond), DOC-T.70). Технологічну зрілість самого заліза несуть [`02_01`](02_01_Hardware_Architecture_and_BOM) і [`02_05`](02_05_Queen_Hardware_and_Starlink).
- **Відкрите:** RFQ-диспетч і vendor-контакти, replacement-OPEX bench-калібрування, Phase 3 енергобаланс Queen → [`00_07`](00_07_Action_Plan_Tracker) (BIZ.7/BIZ.17, HW.39).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`02_01` — Hardware Architecture and BOM](02_01_Hardware_Architecture_and_BOM) | Компонентна специфікація Soldier — джерело для §1 |
| [`02_02` — Blind Mate Pogo Pin Interface](02_02_Blind_Mate_Pogo_Pin_Interface) | Механіка pogo-зʼєднання (вартість інтерфейсу) |
| [`02_03` — BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) | MPPT, EDLC-буфер, енергобаланс вузла |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Компонентна специфікація Queen — джерело для §4 |
| [`01_02` — Ti-6Al-4V Metallurgy and DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) | Друк-cost анкера (дім вартості друку) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Курс SCC — SSOT токеноміки (тут лише дзеркало) |
| [`07_01` — Nature-as-a-Service Contracts](07_01_Nature_as_a_Service_Contracts) | Юридична модель NaaS і фінансові константи — друга половина того самого питання клієнта |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Відкрите: BIZ.7 (replacement OPEX), BIZ.17 (RFQ/procurement), HW.39 (Queen energy) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Специфікація апаратного забезпечення вузла "Soldier" (BOM)](#-1-специфікація-апаратного-забезпечення-вузла-soldier-bom)
- [2. Витратні матеріали та інсталяція](#-2-витратні-матеріали-та-інсталяція)
- [3. Економічний аналіз (Unit Economics) — Анкер](#-3-економічний-аналіз-unit-economics--анкер)
- [4. CAPEX: Специфікація шлюзу "Queen" (BOM)](#-4-capex-специфікація-шлюзу-queen-bom)
- [5. Економіка Кластера (100 Дерев)](#-5-економіка-кластера-100-дерев)
- [6. Операційні витрати (OPEX) та Інфраструктура](#-6-операційні-витрати-opex-та-інфраструктура)
- [7. Фінансова модель: ROI та Токеноміка](#-7-фінансова-модель-roi-та-токеноміка)
- [8. Виробничі хаби в Україні (Supply Chain)](#-8-виробничі-хаби-в-україні-supply-chain)
- [8a. Replacement OPEX та деградація обладнання (BIZ.7)](#-8a-replacement-opex-та-деградація-обладнання-biz7)
- [9. Порівняльна таблиця: Стара vs Нова Архітектура](#-9-порівняльна-таблиця-стара-vs-нова-архітектура)
- [10. Залежності та Посилання](#-10-залежності-та-посилання)
<!-- TOC:AUTO:END -->

---

## ⚙️ 1. Специфікація апаратного забезпечення вузла "Soldier" (BOM)

Нижче наведено перелік основних компонентів одного вузла «Солдат», що базується на гіроїдному анкері.

### 1.1. Компонентний склад (Wiki Baseline)

| Компонент | Матеріал / Характеристики | Примітка |
|---|---|---|
| **Тризонний анкер** | Ti-6Al-4V Grade 23 (ELI) для Zone 1/Zone 3, Medical Grade PEEK для Zone 2 | Загальна довжина ~80–120 мм. Zone 1 (анод-гіроїд) 30–50 мм. Zone 2 (PEEK-терморозрив) **50 мм** (frozen). Zone 3 (катодний фланець) **∅25 мм** (frozen, рана Ø15). Пористість гіроїда Zone 1: 60–70%. Деталі — [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK). |
| **Кріплення модуля** | Болт Titanium SHSC M6 | Крок різьби 1.00 мм для фіксації корпусу. |
| **Energy Harvesting** | BQ25570 (MPPT Nano-Power) | Прямий запуск від EBFC >500 мВ (LTC3108 видалено). |
| **Накопичувач енергії** | Supercapacitor 0.47 F / 5.5 В | До 500,000 циклів заряду/розряду. |
| **MCU & Radio** | STM32WLE5JC (LoRa-E5) | ARM Cortex-M4, LoRa 868 МГц (custom mesh), Edge AI (TinyML). |
| **Антена** | Ceramic SMD Antenna 868 МГц (LTCC) | Пайка роботом, Keep-Out Zone ≥3 мм. Альтернатива: Ignion Virtual Antenna™. Детально → [`02_01 §5`](02_01_Hardware_Architecture_and_BOM). |
| **Корпус / Радом** | PEEK Medical Grade (IP68) — окрема деталь IoT-капсули, **НЕ Zone 2** | Радіопрозорий купол (**∅25 мм** frozen), **байонет** (НЕ різьба — Z-стек-детермінізм, [`02_02 §3.5`](02_02_Blind_Mate_Pogo_Pin_Interface)) до катодного фланця Zone 3, O-ring EPDM. Захист від вандалізму та вологи. Детально → [`02_01 §5.2`](02_01_Hardware_Architecture_and_BOM). |

> **Архітектурна зміна (Pivot v2):** 4 титанові голки-електроди (система Кельвіна) та каскад LTC3108 + трансформатор 1:100 **повністю видалено**. Замінено на коаксіальну «Матрьошку» з EBFC, що напряму живить BQ25570 без проміжного підсилення.

> **Архітектурна зміна (Pivot v3):** «Матрьошка» замінена на тризонний анкер. PEEK у Zone 2 виконує одночасно три функції — електричний ізолятор, терморозрив, механічний демпфер. Деталі — [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK), [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell).

> **Архітектурна зміна (Pivot v4, 2026-05-22 — EBFC Gen 2.0 baseline):** Біохімічний стек повністю переписаний. Gen 1.0 (GOx + Catalase + глутаральдегід + PEG) визнана нежиттєздатною та виключена. **Новий baseline:** деглікозильована FAD-GDH на аноді (без H₂O₂) + Laccase/ZIF-nanozyme гібрид на катоді (×10 power density, chloride-tolerant) + Genipin-Chitosan-CNC матриця (нетоксичний зшивач + псевдопластика) + Nafion-g-PSBMA цвітеріонна мембрана (8 H₂O/ланцюг, σ = 45.2 мС/см, UCST winter-lock). Очікуваний термін служби: **20–25 років**. Деталі — [`01_03 §1–3`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell).

### 1.2. Зведений CAPEX Soldier — node-rollup (канонічний дім)

> 🏠 **One-Home: node $/Soldier живе ТУТ** (агрегація підсистем → вузол). Component-spec живе у своїх домах і **агрегується через реф, не дублюється**: електроніка (Power/RF Deck per-item) — [`02_01 §3`](02_01_Hardware_Architecture_and_BOM); анкер DMLS-друк — [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS); EBFC biochem — [`01_03 §5`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell). Cost-домен registry — [`00_06 §2`](00_06_SSOT_Documentation_Standard).

Завдяки архітектурному аудиту (відмова від LTC3108, перехід на SMD-антену та PEEK-радом) собівартість електроніки радикально знижено. Ціни — партія **1K-tier** (нижче — 50K+ scale-tier).

| Підсистема | Компоненти / Технологія | Вартість ($) |
|---|---|---|
| **Анкер Zone 1 + Zone 3 (Anode + Cathode)** | Ti-6Al-4V Grade 5. SLM+HIP друк (Zone 1) + SLM/EBM (Zone 3). Маса ~9 г сумарно (пористість гіроїда 65%). Включає Hard Gold pogo-площадку, **монолітну шину анода** ([`01_01 §1.4`](01_01_Coaxial_Gyroid_Topology_and_PEEK) — частина анодного друку, без окремого Cu-провідника) та PTFE-GDL катодну мембрану. | $20.00–$25.00 |
| **Анкер Zone 2 (PEEK-терморозрив)** | Medical Grade PEEK. ЧПУ-фрезерування з annealing 200–250°C, допуски H7/s6. Press-fit з Zone 1 і Zone 3. | $3.00 |
| **Радом (PCBA housing)** | Medical Grade PEEK купол ∅25 мм (frozen), термолиття. O-ring EPDM. IP68. Окрема деталь, **НЕ Zone 2**. | $2.50 |
| **Power Deck (PCBA)** | BQ25570 (MPPT) + EDLC Supercapacitor 0.47 F + Pogo Pins + 47µF/25V/X7R/1210 buffer cap ([`02_03 §6.1`](02_03_BQ25570_MPPT_Nano_Power)) + **LTC3108 DNP footprint** для cold-start fallback ([`02_03 §1.5`](02_03_BQ25570_MPPT_Nano_Power)) + пасивна обв'язка 0402. | $6.35 |
| **RF Deck (PCBA)** | STM32WLE5JC (LoRa SoC) + Ceramic SMD Antenna 868 МГц + TCXO (±1 ppm) + **SE05x DNP footprint** (baseline SE051C2; ідентичність-роль SEC.14 provisioning-only; SEC.6 / SE050-MIGRATION, mass-only post-FW.2 — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security); +$2.40–3.25 коли populated). | $5.80 |
| **Біоелектрохімічна функціоналізація (Gen 2.0)** | fMWCNT + Os redox polymer + **dgrFAD-GDH** (Zone 1); fMWCNT + **Laccase/nCoCuCeZIF nanozyme** гібрид (Zone 3); **Genipin-Chitosan-CNC** захисна матриця; **Nafion-g-PSBMA** цвітеріонна мембрана (SI-ATRP). Деталі — [`01_03 §5`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell). | $15.00–$24.50 (1K шт) / $5–$8 (50K+ шт) |
| **Стерилізація (no EtO)** | Гамма-опромінення Co-60 25 кГр в запакованому стані, або UV-C + 70% EtOH. Деталі — [`01_04 §6`](01_04_CODIT_and_Xylemointegration). | $0.50–$1.00 |
| **Герметизація / IP68** | O-Rings EPDM, Parylene C conformal coating PCBA (Sylgard 184 full-potting відхилено — глушить TinyML акустику, [`02_02 §3.4`](02_02_Blind_Mate_Pogo_Pin_Interface)), машинна збірка тризонного анкера. | $1.50 |
| **Разом за 1 Soldier (Gen 2.0, партія 1K):** | **Повністю автономний вузол з тризонним анкером (Gen 2.0 хімія)** | **~$54.65–$69.65** |
| **Разом за 1 Soldier (Gen 2.0, партія 50K+):** | Після scale-up: in-house ферментація + batch coating | **~$44.65–$53.15** |

### 1.3. Electronics breakdown — дім [`02_01 §3`](02_01_Hardware_Architecture_and_BOM)

> 🏠 **Component-BOM One-Home:** per-component моделі + ціни + **Electronics TOTAL живуть у [`02_01 §3`](02_01_Hardware_Architecture_and_BOM)** (component-spec дім — cost-домен registry [`00_06 §2`](00_06_SSOT_Documentation_Standard)). Тут НЕ дублюємо — §1.2 бере Electronics-підсумок (Power Deck + RF Deck) звідти; per-item розбивка (MCU/PMIC/supercap/antenna/piezo/pogo/buffer) — у домі.

> **Climate add-on (BME280 + TPS22860 gate + PTFE vent, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM)):** опційний **+$2.60/вузол** якщо populated — **НЕ** входить у baseline node-cost (§1.2), доки ADR не закрито bench'ем. Перетворює вузол на кліматичний (VPD-confounder False-Slashing kill — [`05_05 §6/§7`](05_05_Slashing_and_Risk_Policy) + NaaS клімат-оракул — [`07_01`](07_01_Nature_as_a_Service_Contracts)) → підвищує D-MRV-цінність для агро/страхового ринку.

---

## 🧪 2. Витратні матеріали та інсталяція

Для забезпечення біосумісності та стерильності монтажу використовуються:

- **Асептика:** 2% хлоргексидину біглюконат у 70% ізопропіловому спирті (стерилізація бурового каналу та інструментів) — ~5 мл / вузол.
- **Герметизація:** Силіконізований акриловий герметик (Remmers Dispertec M-6) для ізоляції точки входу (~2 г / вузол) + Parylene C conformal coating PCBA (CVD-production; Sylgard 184 full-potting відхилено — глушить TinyML акустику, [`02_02 §3.4`](02_02_Blind_Mate_Pogo_Pin_Interface)).
- **Камуфляж:** Екологічні фарби Zero-VOC на основі органічних олій — ~1 г / вузол.

---

## 💰 3. Економічний аналіз (Unit Economics) — Анкер

Використання адитивного виробництва (3D-друк) та гіроїдної структури дозволяє радикально знизити собівартість при збереженні міцності.

> 🏠 **Анкер друк-cost (SLM $/шт + HIP $/шт, за обсягом) — дім [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS);** тут — economics-контекст. ⚠️ **Розрізняти обсяг** (щоб однакове «$15–30» не плутало): серія 1K+ ≈ **$15–30/анкер повністю** (нижче); R&D-партія 100 шт = **$40–80 SLM + окремо $15–30 HIP** ([`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)); прототип-одиниця **$100–250**. Node-агрегат «Анкер Zone1+3 ~$20–25» (1K) → §1.2.

- **Вартість сировини:** Порошок Ti-6Al-4V ELI коштує **$126–$147 за кг**.
- **Економія маси:** Пористість 70% знижує вагу анкера з 26.5 г до **8–9 г**. Вартість металу на виріб — **~$4.00**.
- **Вартість друку (DMLS):** При серійному виробництві (Batch Production) на принтерах Alfa-280 або Concept Laser M2 вартість одного анкера становить **$15–$30**.
- **Прототипування:** Поодинокі тестові зразки в Україні коштують **$100–$250**.

### Порівняльна ефективність гіроїдного анкера

| Показник | Суцільний циліндр | Гіроїдний анкер S-NET |
|---|---|---|
| **Фізична маса** | ~26.5 г | **~8–9 г** |
| **Модуль пружності** | 114 ГПа | **~15 ГПа** (імітує деревину) |
| **Собівартість серії** | $50–$80 | **$15–$30** |

---

## 📡 4. CAPEX: Специфікація шлюзу "Queen" (BOM)

Шлюз агрегує дані по LoRa (star-only) і відправляє їх у хмару/блокчейн. Супутниковий бекхол (Starlink) винесено в окремий "Mother Gateway" (→ [`02_05`](02_05_Queen_Hardware_and_Starlink)), тому стандартна Queen використовує енергоефективний **LTE-M / NB-IoT**.

> 🏠 **One-Home: Queen node-CAPEX живе ТУТ.** Component-spec (моделі/фази: STM32 / SIM7070G / solar / battery / MPPT…) — дім [`02_05 §7`](02_05_Queen_Hardware_and_Starlink); тут — node-rollup $. Cost-домен registry — [`00_06 §2`](00_06_SSOT_Documentation_Standard).

| # | Підсистема | Компоненти / Технологія | Вартість ($) |
|---|---|---|---|
| 1 | **MCU & LoRa (Gateway Mode)** | STM32WLE5JC + зовнішня антена 5 dBi (SMA). | $12.00 |
| 2 | **Cellular Uplink** | SIM7070G (LTE-M / NB-IoT) + eSIM (глобальний тариф) + SMA антена. | $18.50 |
| 3 | **Живлення (Solar)** | Сонячна панель 50 Вт + MPPT Victron SmartSolar 75/15 (HW.39/HW.15, 2026-07: 10 Вт + CN3791 відхилено — зимовий баланс −4.4 Вт·год/добу під кронами, [`02_05 §4`](02_05_Queen_Hardware_and_Starlink)). | $85.00 |
| 4 | **Акумулятор** | LiFePO4 12V 20 Ah + BMS (температурний захист −30 °C; 6 Ah відхилено — 7.8 днів dark-автономності проти 26). | $57.00 |
| 5 | **Корпус & Монтаж** | ABS/PC IP67 корпус + кріплення на стовбур. | $12.50 |
| — | **Разом за 1 Queen (Phase 1/2.5):** | **LTE-M / Starlink DTC; місткість — дім [`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink) (baseline ~100, стеля roadmap ~200)** | **~$185.00** |

#### 🤖 4а. Queen BOM — Phase 3 (Starlink Mini) — HW.14

> **Cross-ref:** [`00_07` — HW.14](00_07_Action_Plan_Tracker) — оновлення Unit Economics ✅

**Phase 3** застосовується для ультра-віддалених локацій (Амазонія, Тайга, Африка) де Starlink DTC (Phase 2.5) недоступний або потрібна вища пропускна здатність. Конфігурація використовує фізичний Starlink Mini термінал (20–40 Вт) з ESP32-S3 co-processor (рішення HW.18; SIM8200G-M2 відхилено — [`02_05 §Starlink DTC`](02_05_Queen_Hardware_and_Starlink)).

| # | Підсистема | Phase 1/2.5 | Phase 3 (Starlink Mini) | Δ Вартість |
|---|---|---|---|---|
| 1 | MCU & LoRa | STM32WLE5JC + SMA 5 dBi | Ідентично | — |
| 2 | Uplink | SIM7070G + eSIM ($18.50) | ESP32-S3 + WiFi (HW.18; SIM8200G-M2 відхилено) | +$15–$30 |
| 3 | Satellite Terminal | Відсутній (DTC через SIM) | **Starlink Mini** ($599 одноразово + $150/міс) | +$599 CAPEX |
| 4 | Solar | 50 Вт ($40.00) | **100 Вт** (для 25–40 Вт Starlink) | +$25.00 |
| 5 | Акумулятор | LiFePO4 12V 20 Ah ($57.00) | **LiFePO4 12V 40 Ah** | +$20.00 |
| 6 | MPPT | Victron SmartSolar MPPT 75/15 ($45.00) | Ідентично (100 Вт вхід ✅) | — |
| 7 | Корпус | IP67 ABS ($12.50) | IP67 Large ABS (Starlink + electronics) | +$25.00 |
| — | **Разом за 1 Queen (Phase 3):** | **~$185** | **~$825 + $599 Starlink = ~$1,424** | **+$1,239** |

> ⚠️ **Phase-3 $825 — не реконструюється з Δ-рядків** (сума видимих компонентів ≈ $270; історичне число, ймовірно, включало неспецифіковані аксесуари — 12→48V DC-boost, кабелі, монтаж-кіт). Перерахунок = частина Phase-3 закупки → [`00_07` — HW.14](00_07_Action_Plan_Tracker). Phase-1/2.5-колонка — жива (←§4).

> **Примітка:** $599 Starlink Mini — одноразова CAPEX для одного кластера. При розгортанні 10 кластерів у одному районі можливий sharing: 1 Starlink на 3–5 Queens через Queen-to-Queen mesh (ARCH.10, Post-TRL 8), що знижує Starlink cost до $120–$200 на кластер.

---

## 🌲 5. Економіка Кластера (100 Дерев)

Мінімальний життєздатний кластер (**MVFC — Minimum Viable Forest Cluster**) = 100 дерев «Soldier» + 1 шлюз «Queen».

### 5.1. Апаратне забезпечення (CAPEX, v4 — тризонний анкер + Gen 2.0 EBFC)

- 100 × Soldier v4 ($62 середній; діапазон $54.65–$69.65 з §1.2, партія 1K) = **$6,200**
- 1 × Queen = **$185** (§4; winter-proof 50W/20Ah — HW.39)
- *Всього CAPEX (hardware):* **$6,385**

> **Примітка про v4 BOM:** середня ціна $62/Soldier (партія 1K) включає Gen 2.0 біохімію ($15–24.50, [`01_03 §5`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)), HIP-обробку Zone 1, CNC PEEK Zone 2 з annealing 200–250°C та PTFE-GDL мембрану Zone 3. При scale-up до 50K+ Soldier падає до ~$48 (in-house ферментація) → hardware CAPEX ~$4,985. (v2 $32–35 / v3 $42.50–50 — застарілі, не використовувати у фінмоделях; повна еволюція — §9.)

### 5.2. Витратні матеріали та Інсталяція

- Асептика (хлоргексидин), екологічний камуфляж, логістика: ~$200
- Праця арбористів (буріння + монтаж 100 вузлів): ~$220
- *Всього Інсталяція:* **~$420**

### 5.3. Cluster CAPEX — Waterfall (канонічний дім)

> 🏠 **One-Home: cluster-CAPEX живе ТУТ** як derivation-водоспад — кожна сходинка тягне вхід зі свого дому, накопичений total = єдине джерело для ROI. §5а / §7 / §8a / §9 **дзеркалять** його (правити тут, [`00_06 §2`](00_06_SSOT_Documentation_Standard)). Так зміна BOM оновлює один рядок, а не сім.

| Сходинка водоспаду | Вхід (дім) | Δ (1K) | Накопичено (1K) | Δ (50K+) | Накопичено (50K+) |
|---|---|---|---|---|---|
| 100 × Soldier v4 | $62 / $48 (§1.2) | +$6,200 | $6,200 | +$4,800 | $4,800 |
| + 1 × Queen | $185 (§4) | +$185 | $6,385 (hardware) | +$185 | $4,985 (hardware) |
| + Інсталяція | $420 (§5.2) | +$420 | **$6,805** | +$420 | **$5,405** |
| **= Запуск «під ключ»** | | | **$6,805 · $68/дерево** | | **$5,405 · $54/дерево** |

> **Cluster CAPEX (v4): ~$6,805 (1K) / ~$5,405 (50K+).** (v2 $4,000 / v3 $5,100 — застарілі, не використовувати.) Realistic life-cycle (з replacements/battery) — те саме CAPEX, ширший OPEX → §8a.4.

#### 🤖 5а. Phase 3 (Starlink Mini) Cluster Economics — HW.14

> **Cross-ref:** [`00_07` — HW.14](00_07_Action_Plan_Tracker), [`02_05 §4`](02_05_Queen_Hardware_and_Starlink) Power Tree.

Для ультра-віддалених локацій де LTE-M / Starlink DTC недоступний (Phase 3):

| Стаття CAPEX | Phase 1/2.5 (v4) | Phase 3 (Starlink Mini, v4) |
|---|---|---|
| 100 × Soldier v4 ($62 ←§1.2) | $6,200 | $6,200 |
| 1 × Queen hardware | $185 | $825 (⚠️ перерахунок — примітка §4а) |
| Starlink Mini terminal | — | $599 |
| Інсталяція | $420 | $480 (складніша монтажна точка, сонячна панель) |
| **Разом CAPEX** | **$6,805** (←§5.3) | **$8,104** |
| **CAPEX на 1 дерево** | **$68** | **$81** |

**Phase 3 OPEX** (Soldier replacements ←§8a.2 one-home):

| Стаття | Phase 1/2.5 | Phase 3 |
|---|---|---|
| Зв'язок Queen (eSIM) | ~$1.50 | ~$0 (Starlink включений) |
| Starlink Residential | — | **$150/місяць** |
| Хмара / RPC | ~$5.00 | ~$5.00 |
| Амортизація Queen | ~$3.50 | ~$8.00 (складніша компонентна база) |
| Soldier replacements (←§8a.2, v4 1K) | ~$10.70 | ~$10.70 |
| **Разом OPEX** | **~$21** | **~$174/місяць** |

**Phase 3 ROI @ $0.30/SCC:**
- Дохід: ~$130/місяць (433 SCC × $0.30, ідентично Phase 1/2.5)
- Net: $130 − $174 = **−$44/місяць** 🔴 → **Phase 3 unprofitable при $0.30**
- Breakeven SCC price: $174 / 433 SCC = **$0.40/SCC**

**Phase 3 ROI @ $1.00/SCC (ReFi premium):**
- Net: $433 − $174 = **$259/місяць**
- Payback: $8,104 / $259 ≈ **~31 місяців** (vs ~16 для Phase 1/2.5 v4 — §7.3)

**Рекомендації HW.14:**
1. **Phase 3 viable лише при SCC ≥ $0.40** — вимагає ReFi premium або Blue Carbon market
2. **Starlink sharing:** розгортати ≥3 кластери на 1 Starlink термінал → Starlink cost per cluster $50/міс → breakeven $0.17/SCC ✅
3. **Duty cycling:** Starlink 1 хв/год замість 5 хв/год → OPEX ~$30/міс
4. **Альтернатива Helium Network:** ARCH.34 (Queen Helium fallback) — якщо покриття є, кратно нижчий OPEX

| Сценарій Phase 3 | OPEX/міс | Breakeven SCC | Payback @$1.00 (CAPEX $8,104) |
|---|---|---|---|
| 1 Starlink / 1 cluster (baseline) | $174 | $0.40 | ~31 міс |
| 1 Starlink / 3 clusters shared | $74 | $0.17 | ~23 міс |
| Duty cycle 1 хв/год | $30 | $0.07 | ~20 міс |

---

## 📊 6. Операційні витрати (OPEX) та Інфраструктура

Щомісячні витрати на утримання мережі зведені до мінімуму завдяки Edge AI (відправляються лише метадані атрактора, а не сирий звук).

| Стаття | Сума / міс |
|---|---|
| Зв'язок Queen (глобальна eSIM, 1NCE / Twilio) | ~$1.50 |
| Хмара / RPC (Akash Network + GCP) — телеметрія, ZK-докази | ~$5.00 |
| Амортизація (резерв на заміну пошкоджених шлюзів) | ~$3.50 |
| **Сумарний OPEX на кластер** | **~$10–$15 / місяць** |

> Soldiers не мають OPEX — вони повністю автономні (EBFC + Supercap, zero connectivity cost).

---

## 💎 7. Фінансова модель: ROI та Токеноміка

Система генерує цінність через емісію токенів **SCC (Silken Carbon/Condition Coin)**, які підтверджують гомеостаз дерева (Proof of Growth) та поглинання CO₂ (→ [`05_03`](05_03_Tokenomics_SCC_and_SFC)).

> **⚠️ SCC-rate модель (self-consistent, calibration-pending):** 10,000 growth_points = 1 SCC. Realistic — Variant C (`delta_t`≈1.77 год, рекомендований energy-positive [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)): ~13.6 пакети/добу × ~16 stored GP = ~217 GP/добу → **~8 SCC/дерево/рік**. Magnitude = f(EBFC recharge `delta_t`), placeholder до bench [E.63]; фізична стеля Δt=600s ≈ 326. Модель+гейт: `tools/firmware/scc_rate.rb`. Арбітр [`05_03`](05_03_Tokenomics_SCC_and_SFC) `MAX_SUPPLY=1B ≈ 20M дерево-років` ⇒ 50 (у діапазоні [8, 326]). ⚠️ 1 TX/год (Δt=3600s) = energy-NEGATIVE без мітигацій ([`02_03 §9.5`](02_03_BQ25570_MPPT_Nano_Power)) — НЕ baseline. Стара «~1 SCC/тиждень / 44–52 SCC/рік» брала несумісні packets×GP (24 і 50 з різних `delta_t`) — superseded.

### 7.1. Механізм накопичення growth_points та CO₂ еквівалент

Кожне пробудження Soldier надсилає 1 пакет із полем `StatusByte[4:0]` = wire growth_points (5 біт, 0–31 після [FW.29-PACK]). Бекенд ×2 upscale: stored 0–62.

| Параметр | Значення |
|---|---|
| Packets / day (Variant C, Δt≈1.77 год) | **~13.6** |
| Wire GP / packet (Variant C `delta_t`, m≈0.13) | **~8** |
| Stored GP / packet (×2 backend upscale) | **~16** |
| Stored GP / день / дерево | **~217** |
| Днів до 1 SCC (10,000 GP) | **~46 днів** |
| **Realistic продуктивність (Variant C)** | **~8 SCC/дерево/рік** (calibration-pending [E.63]; стеля Δt=600s ≈ 326) |
| **1 SCC = CO₂ еквівалент** | **0.5 кг CO₂** (2000 SCC = 1 tCO₂) — **дзеркало**, дім значення [`05_03`](05_03_Tokenomics_SCC_and_SFC) + [`07_01 §3`](07_01_Nature_as_a_Service_Contracts); при зміні правити ТАМ |
| 1 дерево / рік (~8 SCC) | **~4 кг CO₂** |
| Кластер 100 дерев / рік (~800 SCC) | **~0.4 tCO₂** |

> **CO₂ еквівалент [BIZ.1]:** `2000 SCC = 1 тонна поглиненого CO₂`. **SSOT:** [`05_03`](05_03_Tokenomics_SCC_and_SFC) + [`07_01 §3`](07_01_Nature_as_a_Service_Contracts) (on-chain `ProtocolParameters.sol#sccPerTonneCo2()` + `SystemParameter(:scc_per_tonne_co2)`) — значення в таблиці вище **дзеркало SSOT**, при зміні правити там, не тут.

> **SCC-rate модель (single-source):** `tools/firmware/scc_rate.rb` (`--assert` docs-гейт — виводить packets×GP з ОДНОГО `delta_t`, self-consistency + anti-over-mint стеля; magnitude calibration-pending [E.63]). Канон посилається сюди, не restate'ить.
>
> Детально про Lorenz attractor та формулу growth_points: [`03_04`](03_04_mruby_Lorenz_Attractor) та [`05_02`](05_02_Proof_of_Growth_Pipeline).

### 7.2. Розрахунок ROI

**Baseline: 1 SCC/тиждень/дерево** ⚠️ (**optimistic** — realistic Variant C ~8 SCC/рік (§7.1) дає РАЗ на порядок гірший payback; economics жорстко gated на bench EBFC recharge `delta_t` — числа нижче тримати як стелю-сценарій до калібрування)**, ціна $0.30/SCC, baseline OPEX $12 (§6, без replacements):**

- Кластер 100 дерев: 100 SCC/тиждень → **~433 SCC / місяць**
- Дохід кластера: 433 × $0.30 = **~$130 / місяць**
- **Payback = CAPEX (§5.3) / (дохід − OPEX)** = $6,805 / ($130 − $12) = $6,805 / $118 ≈ **~58 місяців**

```
Month  0: −$6,805  (старт)
Month 29: −$3,383  (половина шляху)
Month 57:    −$79  (майже окупився)
Month 58:    +$39  (чиста ліквідність для DAO та власників лісу)
```

> Realistic life-cycle (OPEX $21 з replacements+battery, BIZ.7) → ~61 міс — §8a.4. Повна крива по ціні SCC — §7.3.

### 7.3. Sensitivity Analysis — ROI Waterfall (канонічний дім payback)

> 🏠 **One-Home: payback-крива живе ТУТ.** Формула: **payback = CAPEX (§5.3) / (дохід − OPEX)**. Вхід: CAPEX **$6,805** (1K, ←§5.3); baseline OPEX **$12** (§6, без replacements); дохід = 433 SCC/міс × ціна. §7.2 / §8a.4 / §9 **дзеркалять** цю криву (правити тут).
>
> ⚠️ **Стеля-сценарій:** 433 SCC/міс бере **optimistic** ~52 SCC/дерево/рік; realistic Variant C = **~8 SCC/рік** (§7.1) → дохід ×~0.15, payback ×~6.5. Уся крива нижче = optimistic-стеля до bench-калібрування EBFC recharge `delta_t` [E.63]; НЕ committed-число.

| Ціна SCC | Дохід / міс | Net (−$12 OPEX) | Payback (CAPEX $6,805, 1K) |
|---|---|---|---|
| $0.15 (bear market) | $65 | $53 | ~128 місяців |
| **$0.30 (baseline)** | **$130** | **$118** | **~58 місяців** |
| $0.60 (bull market) | $260 | $248 | ~27 місяців |
| $1.00 (ReFi premium) | $433 | $421 | ~16 місяців |
| $5.00 (Blue Carbon) | $2,165 | $2,153 | ~3.2 місяці |

> **Стратегія виходу на прибутковість:** при $0.30/SCC кластер окупається ~4.8 року (baseline) / ~5 років (realistic з replacements, §8a.4). Цільовий ReFi ринок ($1–5/SCC) скорочує Payback до 3–16 місяців. Scale 50K+ (CAPEX $5,405) скорочує ще ~20%. Ключовий KPI: **growth_points/day** — прямий індикатор здоров'я лісу та швидкості монетизації.

---

## 🏗️ 8. Виробничі хаби в Україні (Supply Chain)

Проєкт спирається на локальні центри адитивних технологій для виготовлення найскладнішої частини — титанових Zone 1 та Zone 3 тризонного анкера (SLM+HIP), плюс PEEK CNC-фрезерування Zone 2.

### 8.1. DMLS-виробництво анкерів

1. **Київ (3D Metal Tech):** Основний підрядник. Досвід з медичними імплантами (ISO 13485), обладнання Concept Laser M2. Здатні друкувати партії гіроїдів із заданою пористістю.
2. **Дніпро (ALT Ukraine):** Власне виробництво принтерів Alfa-280 та лабораторія матеріалознавства. Резервний хаб.
3. **Черкаси (SVS-ARTA / Місцеві PCBA):** SMD-пайка (роботом), conformal coating Parylene C (CVD; Sylgard 184 повне заливання відхилено — глушить TinyML акустику, [`02_02 §3.4`](02_02_Blind_Mate_Pogo_Pin_Interface)), фінальна збірка (**«Marriage»**) плат із титановими анкерами та PEEK-радомами.

### 8.1.1. Contingency Plan: EU Backup DMLS Hubs (BIZ.6)

> **Ризик:** усі три первинні підрядники розташовані в Україні — зоні активних бойових дій. Логістичні ризики (блокування коридорів), енергетичні перебої (rolling blackouts впливають на DMLS-цикл — переривання друку = bad part), мобілізація персоналу. Без EU/US альтернатив проєкт уразливий до single-region collapse.

**Стратегічний принцип:** мати у backlog щонайменше **2 кваліфіковані EU-альтернативи** з підтвердженою здатністю друкувати Ti-6Al-4V Grade 23 (ELI), TPMS-гіроїди ≥60% пористості, ISO 13485 (медичні імпланти).

| Кандидат | Регіон | Технологія / Машина | Сертифікати | Статус |
|---|---|---|---|---|
| **3D Lab (Варшава, PL)** | EU-East | EOS M290, TruPrint 3000 | ISO 13485, AS9100 | 🔴 Не контактовано — **отримати quote** |
| **Materialise NV (Льовен, BE)** | EU-West | EOS M290, GE Concept Laser M2 | ISO 13485, FDA-registered | 🔴 Не контактовано — глобальний бренд, висока вартість, eta 8-12 тиж |
| **Sauber Technologies (Хінвіль, CH)** / **Lithoz GmbH (Відень, AT)** | EU-Central | EOS M400, SLM Solutions NXG | ISO 13485 | 🔴 Не контактовано — швейцарська якість, премія ~30% над UA |
| **TRUMPF Additive (Дітцинген, DE)** | EU-Central | TruPrint 3000 (in-house demo) | ISO 9001 | 🔴 Власні принтери — only buy or contract production |

**Очікуваний ціновий impact:** EU DMLS вартість анкера ~$30–$50 (vs $15–$30 в UA) — Unit Economics залишається життєздатним при ціні SCC ≥ $0.30/SCC (див. §7.2 Sensitivity Analysis), термін окупності зростає на ~20%.

**Activation triggers:**
- Якщо UA-підрядник не може гарантувати поставку >4 тижнів поспіль → activate Tier-1 EU backup (3D Lab PL).
- Якщо логістичний коридор UA→EU перерізаний (блокада/знищення інфраструктури) → 100% production у EU.
- Якщо потрібно ISO 13485 audit для медичного класу (тригер сертифікації NaaS) → Materialise або Sauber від початку.

**Дії (👤 операційні):**
- [ ] Отримати quotes від 2-3 EU підрядників (мінімальна партія 100 шт)
- [ ] Підписати NDA та framework agreement з Tier-1 кандидатом (без зобов'язання обсягу)
- [ ] Передати **PicoGK CAD-STL** (`tools/cad` `build` — анкер/катод/радом STL готові; AM-бюро друкують зі STL, **STEP не потрібен**) + factory spec (HW.1, HW.2) кожному підряднику для валідації feasibility. _DXF GD&T-креслення (Lamé-µm / datums / surface-finish / coating-restriction) готові для **монети** (`draw ti_coin`) і **катодного фланця** (`draw cathode_flange`) — обидва відкриваються AutoCAD/Fusion; анкер (Zone-1 envelope-картка) + Zone-2 втулка — Phase 2 заводського контракту (`drawings_program.md §7`). nTop — reference._
- [ ] Замовити пробну партію 10 шт у Tier-1 EU підрядника для quality benchmarking vs UA

### 8.2. Логістика

```
DMLS-завод (Київ / Дніпро) [Primary]
                 OR
DMLS-завод (Варшава / Льовен) [EU Backup, BIZ.6]
  │  Анкери (партія)
  ▼
PCBA + Збірка (Черкаси — SVS-ARTA)
  │  Зібрані вузли Soldier (повністю готові)
  ▼
Склад логістики
  │  Доставка до лісників / арбористів
  ▼
Польова інсталяція (MVFC: 100 дерев + 1 Queen)
```

---

## 🔧 8a. Replacement OPEX та деградація обладнання (BIZ.7)

> **Принцип:** Unit Economics §6 показує OPEX зв'язку та амортизацію Queen, але **не враховує польовий failure rate Soldiers** (вандалізм, falling branches, EBFC-collapse) та **деградацію LiFePO4 Queen** з часом. Ця секція додає realistic life-cycle costs.

### 8a.1. Soldier Failure Rate (Польові втрати)

**Очікувані модальності відмов:**

| Категорія | Очікувана частка | Причина |
|---|---|---|
| Mechanical (упале гілля, лесорубники, тваринна шкода) | ~50% | Незалежно від конструкції; статистика з аналогів IoT моніторингу лісів. **Dominant у Gen 2.0** |
| Tree death / cut-down | ~25% | Forester removes node |
| RF / antenna damage (Vandalism, surge) | ~15% | Знижено PEEK-радомом, але не нуль |
| EBFC degradation (Gen 2.0 enzyme lifespan) | ~5% | Цільова tail-end деградація: <1%/рік у Years 1–20 (FAD-GDH + ZIF + PSBMA → 20–25 років stable) |
| Electronics random failure (component-level) | ~5% | MTBF STM32WLE5JC > 1M годин |

**Цільовий blended annual failure rate (Years 1-3):** **<2% / рік**.
**Очікуваний failure rate (Years 4-20 з Gen 2.0 EBFC):** ~1–2% / рік (механічні втрати домінують; біохімія стабільна).

### 8a.2. Replacement OPEX

При кластері **100 дерев** та blended failure ~2% на рік (Gen 2.0 EBFC — домінують механічні втрати, не біохімія), v4 BOM:
- 2 заміна Soldier × $62 (v4 CAPEX, партія 1K) = $124 / рік (or $48 при scale-up до 50K+)
- 2 інсталяції × $2.20 (праця) = $4.40 / рік
- **Total Replacement OPEX: ~$10.70 / місяць** на кластер 100 дерев (партія 1K). При scale 50K+: ~$4.40 / місяць.

**Оновлений OPEX (доповнення до §6):**

| Стаття | Сума / міс (v4 Gen 2.0 BOM, партія 1K) | Сума / міс (scale 50K+) |
|---|---|---|
| Зв'язок Queen (eSIM) | ~$1.50 | ~$1.50 |
| Хмара / RPC | ~$5.00 | ~$5.00 |
| Амортизація Queen (заміна шлюзу) | ~$3.50 | ~$3.50 |
| **Soldier replacements (BIZ.7, ~2% annual)** | **~$10.70** | **~$4.40** |
| **Сумарний OPEX на кластер (з replacements)** | **~$20–$25 / місяць** | **~$14–$15 / місяць** |

### 8a.3. Queen LiFePO4 Battery Degradation

Технічна довідка LiFePO4 12V **20Ah** cell (BOM §4 рядок 4; 6Ah відхилено — HW.39, dark-автономність):
- **Cycle life:** ~2000 повних циклів до 80% capacity
- **Daily depth-of-discharge** Queen у нормі: **~7–9%** (20Ah дає ~3.3× запас проти добового розряду; 6Ah-варіант мав би ~25–30%)
- **Циклів на рік:** ~365 (1 cycle/day equivalent)
- **Час до 80% capacity:** при DoD <10% LiFePO4 значно перевищує 2000 циклів → lifetime стає **calendar-limited**, не cycle-limited
- **Calendar aging:** ~3% capacity/рік → ефективний lifetime до 80% при низькому DoD: **~8–10 років**

**Імплікація для OPEX:**
- Battery replacement раз на ~8–10 років: **~$45** (20Ah LiFePO4 cell) + 0.5 год інженерної праці ($25) = ~$70 / ~96–120 міс = **~$0.6–0.7/міс на кластер** (≈ wash проти 6Ah: дорожча заміна × довше життя; §8a.4 payback-зсув <1 міс)
- При жорстких умовах (-30°C зими, активний charging при низьких температурах без BMS температурного захисту — див. HW.16) lifetime скорочується → **~$1.0/міс**
- **Recommendation:** включити battery health check (`vbat_mv` через GatewayTelemetryWorker) у моніторинг, тригерити preventive replacement при capacity < 85%.

### 8a.4. Оновлена ROI модель (realistic life-cycle — OPEX дім)

> 🏠 **One-Home: realistic OPEX (replacements §8a.2 + battery §8a.3) живе ТУТ.** CAPEX ←§5.3 ($6,805 1K / $5,405 50K+); метод-крива ←§7.3. Це той самий waterfall, лише ширший OPEX (~$21 vs baseline $12).

**Baseline (v4 Gen 2.0 BOM, партія 1K, realistic OPEX):**
- Кластер 100 дерев: ~433 SCC/місяць (як §7.2)
- Дохід: 433 × $0.30 = $130 / місяць
- OPEX (з replacements + battery): ~$21 / місяць
- **Net = $130 − $21 = $109 / місяць**
- **Payback = CAPEX (§5.3) / net = $6,805 / $109 ≈ ~62 місяців** (партія 1K). Scale 50K+: $5,405 / ($130 − $15 OPEX) = $5,405 / $115 ≈ **~47 місяців**.

**При $1.00/SCC (ReFi premium):**
- Net = $433 − $21 = $412 / місяць
- **Payback: $6,805 / $412 ≈ ~17 місяців** (партія 1K) / $5,405 / $418 ≈ **~13 місяців** (scale 50K+) — premium absorbs the Gen 2.0 chemistry premium

> **Висновок BIZ.7 (v4 актуальний — Gen 2.0 EBFC):** Перехід на Gen 2.0 хімію (FAD-GDH + ZIF nanozymes + Genipin + PSBMA) додав ~$12–$20 до собівартості вузла у партії 1K, але **знизив failure rate до 2%/рік** (у Gen 1.0 очікувалося 10–15%/рік у Years 4–5 через enzyme degradation). Результат: чистий gross margin виріс на 10%, payback скоротився при $1.00/SCC до ~16 міс. Критично — **дочекатися scale-up до 50K+ шт** (in-house *Pichia pastoris* ферментація + batch coating) → біохімія падає до $5–$8/анкер, повний payback повертається до ~13 міс. Gen 2.0 — це не просто життєздатність, а **планетарна масштабованість**.

---

## 📈 9. Порівняльна таблиця: Стара vs Нова Архітектура

| Показник | v1 (LTC3108 + 4 голки + U.FL) | v2 (Матрьошка + SMD + PEEK) | v3 (Тризонний анкер + Gen 1.0 EBFC) | **v4 (Тризонний анкер + Gen 2.0 EBFC)** ⭐ Поточна |
|---|---|---|---|---|
| **Вартість вузла (партія 1K)** | ~$55–70 | ~$32–35 | ~$42.50–$50 | **~$54.65–$69.65** |
| **Вартість вузла (scale 50K+)** | — | — | — | **~$44.65–$53.15** |
| **EBFC хімія (на анкер)** | GOx+CAT+GA+PEG, $3–5 | GOx+CAT+GA+PEG, $3–5 | GOx+CAT+GA+PEG, $3–5 | **dgrFAD-GDH + ZIF/Lac + Genipin/CNC + PSBMA, $15–24.50 (1K) / $5–8 (50K+)** |
| **EBFC термін служби** | 3–5 років | 3–5 років | 3–5 років | **20–25 років** |
| **Зональна архітектура** | Моноліт 120 мм | Моноліт 120 мм | 3-zone | **3-zone (Gen 2.0 chemistry)** |
| **Тепловий міст анод-катод** | ❌ Прямий контакт | ❌ Прямий контакт | ✅ PEEK Zone 2 | **✅ PEEK Zone 2** (залишк. міст — монолітна шина, мінім., [`01_01 §1.4`](01_01_Coaxial_Gyroid_Topology_and_PEEK)) |
| **Кисневий доступ до катода** | ❌ | ❌ | ✅ Zone 3 | **✅ Zone 3 + ZIF chloride-tolerance** |
| **Anti-biofouling (resin)** | Жодний | PEG (термодинамічно недостатній) | PEG | **Nafion-g-PSBMA (8 H₂O/ланцюг, UCST winter-lock)** |
| **H₂O₂ leak у ксилему** | Так (CODIT trigger) | Так | <5% (з catalase) | **0 (FAD-GDH не виробляє)** |
| **Time для cold-start** | складно | ~0.1 с (robot) | ~0.1 с (robot) | **~0.1 с (robot)** |
| **IP68 герметизація** | Складна | Монолітна | Монолітна | **Монолітна + Hard Gold pogo** |
| **Annual failure rate (Years 4+)** | ~15% | ~12% | ~10–15% (enzyme deg) | **~2%** (механіка домінує) |
| **Payback @ $0.30/SCC** _(realistic, v4 ←§8a.4)_ | >15 міс | ~34 міс | ~52 міс | **~61 міс (1K) / ~46 міс (50K+)** |
| **Payback @ $1.00/SCC** _(realistic, v4 ←§8a.4)_ | — | ~10 міс | ~13 міс | **~16 міс (1K) / ~13 міс (50K+)** |
| **Маса вузла (electronics)** | ~45 г | ~28 г | ~32 г | **~32 г** |
| **Zero Instrumental Noise (для Lorenz)** | ❌ | ❌ | ❌ (enzyme drift maskує signal) | **✅ Всі апаратні змінні — константи** |

---

## 🔗 10. Залежності та Посилання

| Документ | Зв'язок |
|---|---|
| [`02_01`](02_01_Hardware_Architecture_and_BOM) | Детальний технічний BOM + RF & Antenna Subsystem (EDR-02-01-RF) |
| [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) | Механіка Pogo Pin з'єднання анкер ↔ PCBA |
| [`02_03`](02_03_BQ25570_MPPT_Nano_Power) | Розрахунки MPPT і живлення від EBFC + EDLC іоністор 0.47 F ([`02_03 §12`](02_03_BQ25570_MPPT_Nano_Power)) |
| [`02_05`](02_05_Queen_Hardware_and_Starlink) | Queen CAPEX та Starlink Mother Gateway |
| [`05_03`](05_03_Tokenomics_SCC_and_SFC) | Механізм мінтингу SCC, Proof of Growth (10k growth_points = 1 SCC) |
| [`07_01`](07_01_Nature_as_a_Service_Contracts) | Юридична модель NaaS |
