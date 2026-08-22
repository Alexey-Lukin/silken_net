# 07_03: Академічна Інтеграція, Партнери та IP

## 🎯 Мета

Звести в один дім **зовнішній науковий шар** Silken Net: реєстр академічних партнерів (5 ВНЗ — хто/кафедра → що валідує → канон-дім), план спільних публікацій (Scopus/WoS), виконавчі IP-**інструменти** (TISC · ™-заявка · UA-юр-review) і бренд-архітектуру. Сама ліцензійно-IP-**постава** живе в [`00_01 §8`](00_01_Vision_Mission_and_Roadmap) — її аудиторія все репо, не академічний шар. Інженерна субстанція deliverable'ів **живе в каноні Tier I (01–06)** і реферується звідси, а не дублюється.

> **Принцип партнерства:** Silken Net надає інноваційний R&D-полігон. Партнери надають академічну легітимність та лабораторну інфраструктуру.
>
> **Принцип реєстру (Zero-Trust / DRY):** запис = гола ланка «партнер → що валідує → канон-дім», не художній есей і не копія інженерних деталей. Жоден запис не блокує production-merge.

---

## ✅ Статус

- **Стан:** Шкала готовності тут **незастосовна** — це рівно той «TRL партнерств», який [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond) називає категорійною помилкою (DOC-T.70; попереднє число було запозичене в модуля 01). Готовність науки, на яку спирається портфель, живе у своїх домах — Zero-Lab in-silico L1-L4 ✅ (2026-05-25, аналітичний PoC) → [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell); фізичний гейт = in-vitro Ti-coin (Stage 2, pending) → [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond).
- **Партнери:** ідентифіковані, більшість pre-contract. ЧНУ — ректорські зустрічі проведено (травень 2026), канал = проректор з науки Спрягайло, очікується рішення + парасольовий MoU. Авторський колектив **не сформований** — жоден не законтрактований co-authorship-MoU; планування виходить з того, що **founder пише сам**, двері для партнерів відкриті.
- **Відкрите:** спільні публікації + defensive-publication / open-license execution (потребує MoU) → [`00_07`](00_07_Action_Plan_Tracker) (UNI.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`07_01` — Nature as a Service Contracts](07_01_Nature_as_a_Service_Contracts) | NaaS/RWA-право (Аблязов); фінансові константи |
| [`07_01` — Unit Economics and BOM](07_01_Nature_as_a_Service_Contracts) | Юніт-економіка |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Токеноміка (governance/treasury — утримуємо) |
| [`01_03` — EBFC Enzymatic Bio Fuel Cell](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) | EBFC — Мінаєв (spin-кінетика O₂) + ЧМА фарм-стабілізація (Бушуєва); DFT-редокс self-owned + TBD |
| [`01_02` — Ti 6Al 4V Metallurgy and DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) | Ti-довговічність/Kirkendall — Гусак + ЧМА токсикологія (Суховий) |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | §10 Soundscape — ПМКТ (датасет) + наш NDVI-адаптер (Sentinel-2) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Lorenz = status-гейт + DCI-anti-fraud; ground-truth-протокол → [`05_05 §8`](05_05_Slashing_and_Risk_Policy) |
| [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) | §8 Ground-Truth Z↔health протокол (партнерський ростер); Карапетян Z-калібрація |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Backend ML/DS = наш (`InsightGeneratorService`); ЧІПБ EWS/AlertDispatch |
| [`06_08` — Resilience and Failover Policy](06_08_Resilience_and_Failover_Policy) | Mesh Markov/percolation — Open Research, двері ЧНУ-ФОТІУС (§1.1) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | UNI.* / STK.* outreach-трекер |
| [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) | In-silico числа (статті реферять, не дублюють) |
| `cultural_layer.md` | Культурний шар (митці, ненумерований, поза wiki) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Відкриті передумови та критерій складу портфеля](#-відкриті-передумови-та-критерій-складу-портфеля)
- [1. Реєстр Партнерів (5 ВНЗ)](#-1-реєстр-партнерів-5-внз)
- [2. План Публікацій (Scopus / Web of Science)](#-2-план-публікацій-scopus--web-of-science)
- [3. IP-постава — дім переїхав у (00_01_Vision_Mission_and_Roadmap)](#-3-ip-постава--дім-переїхав-у-00_01-800_01_vision_mission_and_roadmap)
- [4. IP-інструменти (TISC + trademark + UA-юр-review)](#-4-ip-інструменти-tisc--trademark--ua-юр-review)
- [5. Бренд-архітектура (SilkenNet / GaiaNexus)](#-5-бренд-архітектура-silkennet--gaianexus)
<!-- TOC:AUTO:END -->

---

## 🚧 Відкриті передумови та критерій складу портфеля

> Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (UNI.*); нижче — контекст партнерства.

- **Лабораторні дані відсутні** — більшість статей §2 gated на лабораторію (мокра хімія / ICP-MS / VNA / акустичний стенд). **Виняток — Стаття 1**: суто in-silico, дані готові, **submission-ready** без лабораторії й без партнера.
- **Авторський колектив не сформований** — партнери ідентифіковані, але жоден не законтрактований co-authorship-MoU (Ярмілко = relationship-Engaged, ще не MoU; UNI.12 = «cold contact» ще не зроблено). Планування виходить з того, що founder пише сам.
- **Co-authorship + open-license MoU** — до початку спільних робіт ([`00_01 §8`](00_01_Vision_Mission_and_Roadmap)). Патентної заявки немає — defensive-publication постава живе там же.

> 🔪 **Критерій складу портфеля:** стаття лишається, лише якщо потрібна для **наукового підтвердження silken_net** — доводить, що система працює / легітимна / defensible (або знадобиться в майбутньому). **НЕ критерій** «алгоритм є в коді»: мокра хімія, лабораторна фізика й радіо-виміри за природою не в коді, і саме вони — найбільші фізичні невідомі (TRL-3-гейт anchor/EBFC). **Ключове розрізнення:** «робота потрібна» ≠ «стаття про неї потрібна» — SOP треба написати ([`00_07` ARCH.31](00_07_Action_Plan_Tracker)), юніт-економіку перерахувати ([`02_06 §7.3`](02_06_Unit_Economics_and_BOM)), але це не Q1-публікації. **Виконавець не важить** (партнери мовчать — founder робить сам); партнер вибуває з портфеля, лише якщо не лишилось **жодної** живої ланки. Вилучене git тримає — повернення коштує один `git show`.

---

## 🎓 1. Реєстр Партнерів (5 ВНЗ)

> 🔴 **Три інваріанти партнерства, відновлені 2026-08-22 з git** (жили в розчиненому реєстрі зовнішніх стейкхолдерів і зникли при прунінгу 07-23, не переїхавши нікуди — [`00_07` DOC-T.85](00_07_Action_Plan_Tracker)): **(1) жодних усних домовленостей** — будь-яка повідомленість сторонньому фіксується письмово, інакше це юридична експозиція, а не гнучкість; **(2) партнерська фіча не входить у hot-path** — жоден зовнішній запит не отримує urgent-пріоритету в чергах, бо тракт телеметрії має власників, і партнерство не є підставою їх посунути; **(3) жодна позиція цього реєстру не блокує merge коду** — стан партнерства живе в трекері (`UNI.*`/`STK.*`), а не в CI. ⊕ Рольовий бік цього ж набору («зовнішній стейкхолдер `super_admin` не отримує ніколи») стоїть окремо, у [`04_03 §3`](04_03_REST_API_v1_Reference) — це властивість РОЛІ, не партнерства, і дім у неї інший.

Кожен ВНЗ закриває окрему нішу валідації без дублювання; інженерна субстанція deliverable'ів реферить канон Tier I (01–06). Ноти-канали (медіа / арт / B2G-гейткіпери / fab-infra) позначені **(не наукова валідація)** — це суміжні виходи, не академ-валідатори.

| ВНЗ | Ніша | Інституційний якір / канал |
|---|---|---|
| **ЧНУ** | фізика/хімія/біологія + кібернетика/ПЗ/радіо (ФОТІУС) | Спрягайло (проректор з науки) — парасольовий MoU |
| **ЧДТУ** | дані/моделі, RF-виміри, акустика, прецизійна механіка | Гончаров (перший проректор) — MoU-підписант |
| **ЧІПБ** | пожежна безпека, ДСНС-міст | персональний контакт |
| **ЧМА** | біомедична валідація EBFC, токсикологія | персональний контакт |
| **СЄУ** | макроекономіка токеноміки, RWA-право, фінансовий облік | персональний контакт |

> **Режим контрактації:** лаб-MoU ЧНУ/ЧДТУ (розблокують фізичні лабораторії — ICP-MS/EIS/SEM/VNA/акустика); СЄУ/ЧІПБ/ЧМА = персональні контакти (люди з експертизою без лаб-доступу — MoU = порожній overhead).

### 1.1 ЧНУ — Черкаський національний університет

Дві площини під одним дахом: **Hard Science** (хімія/фізика/біологія, TRL 1–4) і **кібернетика/ПЗ/радіо** (ФОТІУС, TRL 3–6). Парасольовий MoU через Спрягайла — один підпис розблоковує ICP-MS/EIS/SEM-лабораторії.

| Партнер | Кафедра / профіль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| проф. **Мінаєв Б.Ф.** (+ проф. Мінаєва В.О.) | квантова хімія: spin-orbit, фотофізика, активація O₂ | **Spin-forbidden кінетика активації O₂** на біоелектродах (triplet→singlet: FAD-оксидазний анод + laccase ORR-катод) — світовий фах школи (SOC), механізм поза власним L3 → [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) | Ст. 1/28 |
| проф. **Гусак А.М.** | фізика (Wiley-монографія, UCLA-колаб.) | PEEK creep (Prony/Maxwell-Wiechert, виміряні дані) + ICP-MS-калібрація Kirkendall-моделі (наш script 51) → [`01_02 §2`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK); sheet-vs-network FEA-E homogenization (⚖️ [`00_07` HW.33](00_07_Action_Plan_Tracker) — self-own-кандидат vs школа Гусака, вісь відкрита) | Ст. 2/29 |
| доц. **Спрягайло О.В.** (проректор з науки — **інституційний якір / MoU-канал ЧНУ**) + к.б.н. **Гаврилюк М.В.** (дир. ННІ) | біо-хаб (дендрофлора/ПЗФ/екологія) + парасольовий MoU ЧНУ↔SilkenNet → [`07_01`](07_01_Nature_as_a_Service_Contracts) | *Pinus sylvestris* baseline + хім. склад ксилемного соку + dawn/dusk «Cherkasy Soundscape Library» → [`03_04`](03_04_mruby_Lorenz_Attractor), [`03_03 §10`](03_03_TinyML_Acoustic_Inference), [`01_04`](01_04_CODIT_and_Xylemointegration) | Ст. 2/24a/29 |
| доц. **Ярмілко А.В.** (ФОТІУС) | IIoT / embedded / lightweight crypto | Engaged partner (зустрічі 2026, вхід у ректорат); airtime↔CCM tradeoff = spot-check нашого self-own розрахунку (Ст.23), не незалежна валідація; SPI/DMA-консультація ([`00_07` E.9](00_07_Action_Plan_Tracker)); mesh Markov/percolation-теорія (Open Research → [`06_08`](06_08_Resilience_and_Failover_Policy)); far-horizon PQC | Ст. 23 |
| доц. **Косенюк Г.В.** (ФОТІУС) | військова радіотехніка, теорія кодування | RF impedance / Link Budget / ground-plane / 3D-діаграма з Ti-фланцем як Ground Plane — **аналітичний розрахунок + FEKO/CST** прихованої антени під PEEK ([`02_01 §5`](02_01_Hardware_Architecture_and_BOM)); фізична VNA-верифікація = Гончаров (§1.2) | Ст. 23 |
| ст.викл. **Любченко К.М.** (ФОТІУС) | нейромережі, GA, Master of Logic | Ст.24a + 2 магістерські (real-fit двері): NSGA-II 5-class TinyML tuning + циркадні пороги ([`03_03`](03_03_TinyML_Acoustic_Inference)) — метод generic (pymoo, self-generable), **опц., не load-bearing валідація** ([`00_07` FW.4](00_07_Action_Plan_Tracker)); gate = ground-truth Біо-хаб | Ст. 24a |

> Протоколи Hard-Science (Quantum-Sap, Long-Term Integrity, Homeostasis Baseline, Xylem-Sim, Steril) — already-canon: дім у [`01_01 §6.1`](01_01_Coaxial_Gyroid_Topology_and_PEEK) / [`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) / [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) / [`01_04 §6`](01_04_CODIT_and_Xylemointegration) / [`03_04`](03_04_mruby_Lorenz_Attractor) + [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md).

**Суміжні канали ЧНУ (не наукова валідація):**
- **Медіа (PR):** Михайло Калініченко (Засл. журналіст, гендиректор ТРК «Ільдана», викладач ЧНУ) + Валентина Душок (Рабцун) (директорка ТРК «Ільдана», вихід на ОДА через Спрягайла) — документальний супровід + превентивний інфо-фон проти екопанік → [`07_01`](07_01_Nature_as_a_Service_Contracts).
- **Мистецька кафедра:** Тетяна Касьян (Засл. художник України, зав. кафедри образотворчого мистецтва ЧНУ) — інституційний доступ до студентів-художників (cross-faculty мистецтво × CS).
- **Графічний дизайн:** Віктор Афонін (Засл. художник України, викладач ЧНУ — книжковий дизайн/плакат/фірмовий стиль) — брендинг платформи → [`04_04`](04_04_Phlex_UI_and_Tailwind).
- **B2G land-access:** Юрій Сегеда (Засл. природоохоронець, директор ДП «Смілянське лісове господарство» — єдиний лісовий масив із Черкасами; мешкає в с. Геронимівка, серце Черкаського бору, найближча точка до Genesis-полігону) — доступ до заказників Смілянщини + еко-аудит; ПЗФ-сумісність координується зі Спрягайлом. Дім-стан → [`00_07`](00_07_Action_Plan_Tracker) (STK.2).

### 1.2 ЧДТУ — Черкаський державний технологічний університет

Комплементарний до ЧНУ (3 академ-кафедри): **дані/моделі**, **радіоканал** (лабораторна верифікація розрахунків Косенюка) та **акустичний hardware**. Інституційний якір — перший проректор **Гончаров** (він же RF-верифікація, Ст.23; MoU-підписант).

| Партнер | Кафедра / роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| доц. **Карапетян А.Р.** (зав.) | статистика та прикл. математика (R/Data Science) | Anomaly/fraud-статистика: CUSUM/EWMA research-шар ПОВЕРХ нашого порога `FRAUD_DEVIATION_THRESHOLD` (Ст.13) + biodiversity fusion-статистика (ANOVA/permutation, Ст.24a) + ground-truth Z-калібрація ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)) → [`04_02`](04_02_Business_Logic_and_Services) | Ст. 13/24a |
| **перший проректор Гончаров А.В.** | каф. РТРС (радіотехніка / signal-processing) | **Інституційний якір ЧДТУ** (MoU-підписант) + експериментальна RF-верифікація (VNA S11, EMC pre-scan, натурний Link Budget) розрахунків Косенюка → [`02_01 §5`](02_01_Hardware_Architecture_and_BOM) | Ст. 23 |
| проф. **Базіло К.В.** + проф. **Бондаренко М.О.** | ПМКТ, акустична мехатроніка | Валідація фононної лінзи гіроїда (EIS + AE) + **калібрувальний TinyML-датасет** (польова валідність 5-class моделі — [`03_03 §4.1`](03_03_TinyML_Acoustic_Inference)); резонанс п'єзо у діапазоні фауни 0.5–12 кГц (Ст.24a) | Ст. 24/24a |

> Повний реєстр Data-Science задач (≈10 тем × методи) — research-агенда рівня публікацій; інженерні точки дотику вже в каноні (`InsightGeneratorService`, `Attractor`, `dClimate`, `ParametricInsurance`). Деталі методів — §2.2.

**Суміжні канали ЧДТУ (не наукова валідація):**
- **Fab-infra (procurement):** CNC post-DMLS механообробка (PEEK Zone 2 фрезерування, bayonet-геометрія, катод Zone 3, різальна геометрія → [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK), [`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface)) = manufacturing-крок, процес відомий, публікації нема. Джерело — ЧДТУ machine-shop **або** комерційний CNC-вендор; виконавець TBD, не контактовано.
- **Культурно-історичний контекст (⚪ conceptual):** проф. Мельниченко В. (ЧДТУ, краєзнавство; Засл. працівник культури, очільник Черкаського осередку Спілки краєзнавців) — історико-культурний контекст RWA-токенів (Холодноярські Master Nodes, скіфські городища) + вибір висот Queen-шлюзів за історичними оглядовими точками → [`05_03`](05_03_Tokenomics_SCC_and_SFC), [`02_05`](02_05_Queen_Hardware_and_Starlink).
- **B2G land-shield:** Олександр Дзюбенко (Засл. лісівник України, директор Центрального лісового офісу ДП «Ліси України» — керує держлісами Черкащини вкл. Черкаський бір; + д.е.н., проф. каф. лісового господарства ЧДТУ за сумісництвом) — легальний доступ до полігону в держлісі (перекласифікація анкера «втручання»→«науково-вимірювальний прилад» + Pilot Site MoU) + адмінміст ДП «Ліси України» ↔ ЧДТУ. Дім-стан → [`00_07`](00_07_Action_Plan_Tracker) (STK.1).

### 1.3 ЧІПБ — Черкаський інститут пожежної безпеки (ДСНС)

B2G-міст до ДСНС + академічне обґрунтування SOP реагування на кіберфізичні тривоги. Биченко — тактика гасіння / керівництво діями підрозділів → диспетчеризація + drone-розвідка; Ротар — правова компетентність ЦЗ, тактичні алгоритми → SOP-регламентація.

| Партнер | Роль | Що валідує → канон-дім |
|---|---|---|
| **Биченко А.** | диспетчеризація | Інтеграція EWS ↔ протоколи реагування ДСНС → [`04_02`](04_02_Business_Logic_and_Services) (`EwsAlert`/`AlertDispatch`) |
| **Ротар В.** | SOP | SOP-документи per alert_type (field ops) → [`04_02`](04_02_Business_Logic_and_Services); трек [`00_07` ARCH.31/UNI.12](00_07_Action_Plan_Tracker) (SOP-compliance = зворотний бік Кат-A negligence-evidence для slashing) |

### 1.4 ЧМА — Черкаська медична академія

Біомедична валідація EBFC + токсикологія Ti. ЧМА = навчальний коледж (не матеріалознавча лабораторія); інституційний доступ — персонально.

| Партнер | Роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| **Бушуєва І.В.** | фарм. технологія / регуляторика | д.фарм.н., проф. ЗДМФУ (стейкхолдер/рецензент ЧМА-програм). Технологія стабілізації активних речовин у гель-матрицях + регуляторна валідація — дотично до Genipin-Chitosan immobilization-матриці [`01_03 §2`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell); глибока EBFC-ензимологія → профільний біохімік (TBD) | Ст. 28 |
| **Суховий Г.П.** | токсикологічна хімія | к.фарм.н., доц. каф. неорганічної та токсикологічної хімії (ЗДМФУ; афіліація ЧМА з 2024). Хіміко-токсикологічний аналіз V/Al release у ксилему + Safety Margin → [`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`01_04`](01_04_CODIT_and_Xylemointegration) | Ст. 29 |
| **Глущенко А.В.** (викладач ЧМА) | фармація / фітотерапія | Фітотоксичність 8-HQ self-healing покриття (профіль: рослинні екстракти, хім. аналіз) — already-canon → [`01_02 §3`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS); Os redox polymer cross-linking (Ст.28) | Ст. 28/29 |
| **Котикова Р.** (⚪ conceptual) | фармакокінетика | Засл. працівниця фармації — пролонговане (≈5-річне) вивільнення 8-HQ self-healing мікрокапсули без вимивання → [`01_02 §3`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS); активувати за 8-HQ-валідації | — |

### 1.5 СЄУ — Східноєвропейський університет

Економіка / право (прикладний макро-стрес-тест + legal wrapper).

| Партнер | Роль | Що валідує → канон-дім |
|---|---|---|
| **Ус Г.О.** (проф. каф. економіки) | цифрова економіка / матем. моделювання | Д.е.н.; математичні методи та ІТ в економіці; цифрова економіка (2021); управління знаннями (2024) |
| **Аблязов Д.Е.** (віцепрезидент СЄУ) | комерційне право / legal-risk | к.ю.н.; господарське/комерційне право, протидія корпоративному рейдерству (2021), інвестиції → MSA/MoU/co-founder IP-carve-out ([`00_07` BIZ.2/BIZ.20](00_07_Action_Plan_Tracker)) → [`07_01`](07_01_Nature_as_a_Service_Contracts) — консультація (§4.2), не публікаційний співавтор |
| **Гедз М.Й.** (проректор з якості) | фінанси / облік криптоактивів | Д.е.н., проф. (ex-ЧДТУ); регіональна економіка, фінансовий облік криптоактивів в Україні (2025), якість/акредитація (ISO 9001) |

> **Суміжна роль — титулований юрист для Legal Wrapper SCC (особа TBD, не контактовано).** Потрібна **не для консультації** (її дає Аблязов), а для **підпису, що має вагу перед державним органом**: перекласифікація анкера з «втручання» у «науково-вимірювальний прилад» у зверненні до прокуратури — питання, де важить титул, а не лише фах. Канали пошуку: ННІ права ЧНУ (доступ через Спрягайла, §1.1) + рекомендація Аблязова. Роль канонізована тут 2026-07-26 — доти вона існувала **лише** в трекері, тобто item не мав канон-дому. Дім-стан → [`00_07`](00_07_Action_Plan_Tracker) (STK.3).

---

## 📚 2. План Публікацій (Scopus / Web of Science)

Серія фундаментальних статей для журналів рівня Q1/Q2 на перетині кіберфізики, матеріалознавства та екології. Нумерація рідка — діри = вилучені статті, номери **НЕ перевикористовуються** заради crossref-стабільності. Авторські ростери — **плановий актив, не законтрактована команда** (per-роль хеджі «TBD / опц. / не load-bearing / консультація» тримаються біля ролі).

> 🔍 **Перед сабмітом / передачею співавтору** — прогнати [`self_review_checklist`](protocols/paper/self_review_checklist.md) (citation-gate · 5-lens · anti-sycophancy · чесні межі). Тонкий self-review, рішення завжди автора.
>
> **Trade-secret + open-license (наскрізь):** код відкритий під AGPL → формат пакета та lightweight-crypto інтеграція більше НЕ secret; студентські роботи відкриваються в репозиторіях ВНЗ безперешкодно (крім реальних ключів/даних); результати — під open-license зі стандартним співавторством, **без embargo** (publish-to-protect, §3).

### 2.1 Основні публікації

#### Стаття 1: Електрон-трансферна енергетика EBFC Gen 2.0 (квантова хімія, Пріоритет: Перша)

**Назва (EN):** _"Computational Electron-Transfer Energetics of a FAD–Osmium Enzymatic Biofuel Cell: PCET Redox Potentials, Mediator Structure–Activity, ZIF-Nanozyme Direct Electron Transfer, and the Limits of Implicit-Solvation DFT"_

**Тип:** суто обчислювальна (quantum-chemistry) — ставка на **механістичну + методологічну** новизну, не «валідацію» (фізичний Ti-coin CV/EIS попереду, Stage 2). Сирий обчислювальний вердикт каскаду FADH₂→Os — uphill у кожному методі; downhill (+574 мВ) — це **верифіковані E°** (Os +309 − FAD −265 мВ SHE, Zafar 2012 + Schachinger 2023). Обчислення експонує **межу методу**, а не «валідує» — саме це й новизна.

**Журнали-цілі:** *J. Phys. Chem. B* (ACS, **primary** — enzyme catalysis + computational scope) · *Phys. Chem. Chem. Phys.* (RSC, **fallback** — дім школи Мінаєва, OA-waiver для ЧНУ) · *Bioelectrochemistry* (Elsevier, applied-backup). НЕ *J. Power Sources* / *Electrochimica Acta* (comp-only поза їх scope без експерименту).

**Авторський колектив:**
- Архітектор (Silken Net) — in-silico baseline (PySCF DFT/ΔSCF, AF3, tunneling), дизайн каскаду, draft. **Пишеться зараз** на готових результатах.
- **Мінаєв-роль:** explicit-water QM/MM редоксу — не фах школи Мінаєва (їхній = spin-orbit / активація O₂). PCM-межу закриває власний follow-up або профільна computational-electrochemistry колаборація (TBD); школа Мінаєва — потенційний co-author за **окремим** кутом (spin-forbidden кінетика активації O₂, майбутня EBFC-стаття). Ст.1 submission-ready як own in-silico (без gated-партнера).

**Foreground (сильні, чисті результати):**
- **PCET редокс-потенціал FAD** — proton thermodynamic reference відтворює E°(FAD/FADH₂) у межах ~50 mV від експ. free-flavin (script 32).
- **Mediator structure–activity (Hammett LFER ①)** — E°(Os III/II) лінійний у σ_para (нахил ≈ −0.92 eV/σ) → предиктивне правило дизайну; реалістичний оптимум = інертний **SO₂CF₃** (NO₂ деградує на циклюванні). Триангульовано DFT↔Lever↔Hammett (script 21e).
- **DET через ZIF-нанозим** — ΔSCF hopping (geom-fixed) + computed Nelsen λ: **borderline** at realistic λ (Cu-Co ~turnover, не old ×10⁵) + low-λ-metal (Ru) design rule (scripts 23/24/25/35).
- **Геометрія + through-bond tunneling** анода — глибина залягання FAD < tunneling-межі (L1 + script 28).
- **Термічна робастність** frontier-орбіталі FAD (MD→DFT ensemble, script 27).

**Методологічний внесок (це новизна, не діра):** implicit-solvation (PCM) межа декомпозована ② (script 34) у chloro-anchored bracket (реальний медіатор = chloro `[Os(dmbpy)₂(PVI)Cl]`, Zafar): differential PCM solvation [chloro +1/+2 +0.21 eV ↔ bis-Im +2/+3 +0.55 eV] + 4,4'-dimethyl ① +0.142 eV (Koopmans); [Os(H₂O)₆] benchmark +0.98 eV; chloro↔+2/+3 bracket functional-robust (ωB97X cross-check 34b/B4). Анодний λ — first-principles (29b: FADH⁻/FADH• → λ_i 0.39 eV); PCET-каскад (script 33) не flip downhill → теж PCM-межа. explicit-water QM/MM (Мінаєв) закриває залишок. Визнаний жанр (пор. JCTC implicit-solvent redox-benchmarks). Повний аудит методу — [`L3_quantum_chemistry.md`](protocols/ebfc/in_silico/L3_quantum_chemistry.md).

**Scope:** L1 (відстань/шлях) + L3 (анод) + L3b (катод DET) + сольватаційна методологія. L2 (MD-стабільність) + L4 (delta_t/EIS) → окремі майбутні EBFC-статті + predictions для Ti-coin.

**SSOT/IP:** числа — дім [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) (стаття реферить); сабміт **вільний** — publish-to-protect ([`00_01 §8`](00_01_Vision_Mission_and_Roadmap)), без патентного гейту.

#### Стаття 2: Довгострокова Біотрибокорозійна Стійкість (Пріоритет: Друга)

**Назва (EN):** _"Long-Term Bio-Tribocorrosion Resistance of TPMS Gyroid Ti-6Al-4V Implants in Simulated Xylem Sap: Accelerated Aging Protocol for Forest Bioelectronics"_

**Журнали-цілі:** *Corrosion Science* (Q1), *npj Materials Degradation* (Q1), *Acta Biomaterialia* (Q1)

**Авторський колектив:**
- Школа Гусака (ЧНУ) — Prony/Maxwell-Wiechert creep-fit PEEK по виміряних даних + калібрація Kirkendall-моделі (наш script 51) проти coin-ICP-MS
- Біо-хаб ЧНУ (Спрягайло) — склад ксилемного соку *Pinus sylvestris*
- Архітектор (Silken Net) — практичний контекст та вимоги 20-річної довговічності

**Ключові результати:** математична модель деградації анкера на 20 років; протокол акселерованого тесту (12 тижнів @ 40°C ≈ 3–5 польових років); верифікація self-healing покриття на мікрокапсулах з 8-HQ інгібітором. (Отримує ICP-MS Ti/Al/V від Статті 1.)

### 2.2 Публікації ЧДТУ (Data Science)

#### Стаття 13: Виявлення Аномалій у Масштабних Потоках Лісової Телеметрії

**Назва (EN):** _"Anomaly Detection in Large-Scale Forest Telemetry Streams"_
**Журнали:** IEEE Internet of Things Journal (Q1) · Information Sciences (Q1)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | Статистична методологія anomaly/fraud-детекції: контекстуальна (сезон/біом) + CUSUM/EWMA для replay/spoofing — research-шар поверх поточного порога `FRAUD_DEVIATION_THRESHOLD` + DCI (data-gated: флоту ще нема, System TRL 3) |
| Архітектор (Silken Net) | `insight_generator_service.rb` (fraud detection), `alert_dispatch_service.rb`, Dual Computation Integrity |

### 2.3 Міжуніверситетські Публікації (ЧНУ ФОТІУС × ЧДТУ)

> **Принцип:** де ЧНУ ФОТІУС створює алгоритм/модель — ЧДТУ статистично валідує; де ЧНУ виконує аналітичний розрахунок (RF, фільтри) — ЧДТУ (РТРС, ПМКТ) верифікує лабораторно.

#### Стаття 23: Прихована SMD-Антена LoRa у Лісовому Середовищі

**Назва (EN):** _"Concealed LoRa SMD Antenna Under PEEK Radome for EBFC-Powered Forest IoT: Impedance Matching, 3D Radiation Pattern, and VNA/EMC Verification"_

> ℹ️ Поглинула Статтю 8 (UNI.19): аналітична + експериментальна половини однієї антени зведені, Link Budget Косенюка більше не стоїть двічі. Reed-Solomon FEC (E.15 — CR 4/5 Hamming уже в кремнії SX126x) і Kalman (E.10 — продукт узяв EMA, FW.21) зняті при злитті.

**Журнали:** IEEE Transactions on Antennas and Propagation (Q1) · IEEE Antennas and Wireless Propagation Letters (Q1) · Sensors (Q1)

| Автор | Внесок |
|-------|--------|
| **Косенюк Г.В.** (ЧНУ ФОТІУС) | Аналітичний розрахунок імпедансу, FEKO/CST моделювання діаграми, LC-узгодження; Link Budget LoRa у лісі (SF=7–9, [`02_01 §5.3`](02_01_Hardware_Architecture_and_BOM)); 3D-діаграма з Ti-анкером (Zone 1 + Zone 3 фланець) як Ground Plane; CE/FCC compliance roadmap |
| **Гончаров А.В.** (ЧДТУ, перший проректор, каф. РТРС) | VNA-виміри S11 реальної зборки, натурні вимірювання path loss у лісі, EMC pre-compliance |
| **Ярмілко А.В.** (ЧНУ ФОТІУС) | Engaged-партнер (lightweight crypto / embedded; вхід у ректорат). Airtime↔CCM tradeoff = spot-check self-own розрахунку; far-horizon PQC |
| Каф. РТРС | Лабораторна інфраструктура: VNA, EMC-камера, вимірювальні стенди |
| Архітектор (Silken Net) | STM32WLE5JC RF-конфіг, PEEK-радом IoT-капсули (∅25 мм frozen, IP68 — окрема деталь, не PEEK-втулка Zone 2; ≥8 мм Z-clearance проти Ti-фланця), Ti-6Al-4V Ground Plane, firmware radio driver, EBFC Gen 2.0 як джерело (>500 мВ, <500 мкВт — [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)) |

**Тип зв'язку:** Послідовний — ЧНУ (Косенюк) розраховує → ЧДТУ (РТРС, Гончаров) верифікує на VNA/у лісі → коригування LC → серійна специфікація. ЧНУ (Ярмілко) паралельно тримає крипто-навантаження того ж кадру (CCM-MIC ↔ airtime).

**Магістерські:** «Експериментальне дослідження радіохарактеристик мікропотужних IoT LoRa 868 МГц…» (керівник Гончаров, ЧДТУ РТРС) · «Радіотехнічна оптимізація мікропотужних IoT у лісі: узгодження антенних систем» (керівник Косенюк, ЧНУ ФОТІУС).

#### Стаття 24: Фононна Лінза на Основі TPMS-Гіроїда

**Назва (EN):** _"Phononic Lens Effect in Ti-6Al-4V TPMS Gyroid Structures for Passive Acoustic Filtering in Forest Bio-IoT: Experimental Characterization and TinyML Dataset Generation"_
**Журнали:** Journal of Sound and Vibration (Q1) · Ultrasonics (Q1) · Applied Acoustics (Q1)

> ⚠️ Кавітаційні емісії = 25–150 кГц (ultrasonic); поточний audible-тракт (16 кГц ADC / Nyquist-8 кГц) їх НЕ оцифровує → ця стаття = UNI.11-канал / v3 AI-chip (майбутній ultrasonic-тракт), не поточний firmware. TinyML-клас «cavitation» reframed до low-freq structural water-stress proxy ([`03_03 §4.2`](03_03_TinyML_Acoustic_Inference)).

| Автор | Внесок |
|-------|--------|
| **Базіло К.В.** (ЧДТУ ПМКТ) | П'єзоелектрична характеризація, імпедансна спектроскопія, акустоелектроніка |
| **Бондаренко М.О.** (ЧДТУ ПМКТ) | Акустичний стенд, мікродеформації, прецизійні вимірювання АЧХ |
| Архітектор (Silken Net) | Дизайн гіроїда (TPMS, ~65–67% пористість — CEM first-pass, не зафіксована константа, [`01_01 §5.2`](01_01_Coaxial_Gyroid_Topology_and_PEEK); Ti-6Al-4V), концепт Compute-by-Geometry, TinyML pipeline |

**Тип зв'язку:** Послідовний — ЧДТУ (ПМКТ) валідує фізику фононної лінзи (firmware ADC-DMA для п'єзо-тракту — self-owned, [`03_01`](03_01_Firmware_Lifecycle_and_DMA)).

**Магістерська:** «Дослідження акустичних властивостей пористих TPMS-структур Ti-6Al-4V для пасивної фільтрації ультразвукових емісій» (керівник Базіло/Бондаренко, ЧДТУ ПМКТ).

#### 🌿 Стаття 24a: Acoustic Biodiversity Verification of Satellite Land-Cover (Mongabay)

**Назва (EN):** _"Multi-Scale Acoustic Verification of Satellite Land-Cover Through TinyML Edge AI: Distinguishing Functional Forest Ecosystems from Plantation Monocultures via Continuous Bio-IoT Soundscape Classification"_
**Назва (UA):** _«Мультимасштабна акустична верифікація супутникового лісового покриву через TinyML Edge AI…»_
**Журнали:** *Ecological Indicators* (Q1, IF ~6.3) · *Remote Sensing of Environment* (Q1, IF ~13.5) · *Methods in Ecology and Evolution* (Q1, IF ~8.0) · *Bioacoustics* (Q2)

> ⚠️ **Рамка (both/and — не заміна карбону):** «Mongabay» = історичний ярлик кампанії, НЕ зміна позиціювання. Biodiversity — **другий D-MRV вимір ПОВЕРХ карбонового ядра**: `growth_points → SCC` лишається ядром економіки; fauna = 5-й акустичний клас (поверх silence/wind/cavitation/chainsaw) + `biodiversity_score` (proposed) як метадані `ForestNFT` (proposed).

**Контекст:** Delgado et al. (Nicoya Peninsula, Costa Rica, 119 ділянок, 16 000 год аудіо; огляд *Mongabay News*, травень 2026) інструментально довів обмеження суто супутникового MRV: NDVI не розрізняє функціональну екосистему (dawn-dusk піки фауни) від монокультурної плантації (нерухомий звуковий фон). Стаття 24a переносить методологію у безперервну on-tree IoT-площину — тисячі STM32WLE5JC з `fauna_activity_index` 24/7, цифрово підписаним та anchored на Polygon SCC.

**Унікальність (відсутня в світовій літературі станом на 2026-05):**
1. Інтеграція **soundscape ecology** (Pijanowski et al. 2011; ACI Index Pieretti et al. 2011) з **embedded TinyML на суб-кілобайтному бюджеті**: INT8 forward-pass (40 log-mel → 16 → 5 класів), **972 B ваг у Flash / ~76 B стеку / ~0 .bss**, без TFLM/CMSIS-NN-рантайму ([`03_03 §4.1`](03_03_TinyML_Acoustic_Inference)) — де типова ESC-CNN потребує ~16 КБ tensor arena, що при цьому бюджеті **фізично не деплоїться** ([`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)).
2. **D-MRV pipeline** `TinyML soundscape → CoAP → Rails → Polygon SCC` — both/and (biodiversity поверх карбону). ⚠️ **Не «продакшн» і не «cryptographically доводить»:** живий шлях мінтить **оптимістично** — IoTeX/Chainlink НЕ enforced; ланка `W3bstream ZK-proof → Chainlink Oracle → mint guard` = PATH 1 ⚪ demoted/unwired, trust-origin = **L0**, anti-fraud = ex-post clawback (ще не збудований) → [`05_02`](05_02_Proof_of_Growth_Pipeline). Це архітектура-намір (North-Star), не доведений факт.
3. **Macro-Micro residual analysis:** NDVI=high & fauna=low → кандидат «green-washing»; NDVI=low & fauna=high → ранньо-стадія регенерації.

| Автор | Афіліація | Внесок |
|-------|-----------|--------|
| **Любченко К.М.** (ЧНУ ФОТІУС) | Genetic Algorithms, Edge AI | Опційний GA-tuning ваг (pymoo NSGA-II на self-owned моделі — self-generable, **НЕ** load-bearing; [`00_07` FW.4](00_07_Action_Plan_Tracker) «опц., не блокер»). Реальні двері = 2 магістерські-теми |
| **Базіло К.В.** (ЧДТУ ПМКТ) | П'єзоелектрика, EIS | Резонансні характеристики п'єзосенсора 0.5–12 кГц; калібрування АЧХ під soundscape |
| **Бондаренко М.О.** (ЧДТУ ПМКТ) | Acoustic Emission | AE-методологія для розрізнення layered soundscape від шуму; «Cherkasy Soundscape Library» |
| **Карапетян А.Р.** (ЧДТУ) | Math statistics, R | ANOVA dawn/dusk peak amplitude між ландшафтами; permutation tests для `biodiversity_trend` |
| **Спрягайло О.В.** (ЧНУ біо-хаб) | Ботаніка, фітоценологія | Польові експедиції Черкаського бору, ground-truth labeling, 10-річні дані стресу як external validation |
| **Гаврилюк М.В.** (ЧНУ біо-хаб) | Зоологія, GIS | Cross-validation soundscape ↔ обліки птахів/амфібій; GIS-інтеграція ділянок |
| Архітектор (Silken Net) | TinyML, firmware, Web3 | Path B (log-mel) обрано + DSP front-end self-owned (`Compute_LogMel`, librosa≡stdlib≡C parity; MFCC/DCT не рекомендовано для CNN-ESC — [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference)); 5-class INT8 baseline self-owned (ESC-50; per-frame FC 40→16→5 — не CNN, [`00_07` FW.4](00_07_Action_Plan_Tracker)); `AiInsight#biodiversity_trend`; `ForestNFT` metadata (proposed) |

**Тип зв'язку:** Багатошарова паралель — ЧНУ біо-хаб (ground truth) + ЧДТУ ПМКТ (hardware acoustic) ∥ ЧНУ ФОТІУС (GA — Любченко) + ЧДТУ Карапетян (статистика + fusion); архітектор інтегрує firmware+backend; усі шари на одному датасеті («Cherkasy Soundscape Library») + одній публікації.

**Cross-references:** [`03_03 §10`](03_03_TinyML_Acoustic_Inference) (архітектура 5-class) · [`00_07` UNI.11](00_07_Action_Plan_Tracker).

**Магістерські/PhD:** Спрягайло (ЧНУ біо — «Динаміка денних/сутіночних піків фауни…») · Любченко (ЧНУ ФОТІУС — «Багатоцільова генетична оптимізація 5-класової TinyML…») · Базіло/Бондаренко (ЧДТУ ПМКТ бакалавр — «Калібрувальний soundscape-датасет…») · Карапетян (ЧДТУ PhD — «Статистичні методи валідації…»).

### 2.4 Публікації ЧМА (Біохімія EBFC, Токсикологія)

#### Стаття 28: Біохімічна Валідація EBFC для Дерево-Живленого IoT

**Назва (EN):** _"Biochemical Validation of Enzymatic Bio-Fuel Cell for Tree-Powered IoT: Enzyme Immobilization Stability, Protective Matrix Optimization, and In Vitro Performance in Simulated Xylem Sap"_
**Журнали:** Biosensors and Bioelectronics (Q1) · Journal of Power Sources (Q1) · Electrochimica Acta (Q1)

| Автор | Внесок |
|-------|--------|
| **Бушуєва І.В.** (ЗДМФУ, стейкхолдер ЧМА) | Фарм-технологія стабілізації активних речовин у гель-матрицях + регуляторна валідація (дотично до Genipin-Chitosan-CNC immobilization); глибока EBFC-ензимологія (in vitro лакказа/Nafion, 30-day) → профільний біохімік/електрохімік (TBD) |
| **Мінаєв Б.Ф.** (ЧНУ) | Spin-forbidden кінетика активації O₂ на laccase ORR-катоді (SOC — світовий фах школи), механізм поза власним L3 |
| **Глущенко А.В.** (ЧМА) | Характеризація Os redox polymer стабільності + експериментальна cross-linking характеризація обраного медіатора |
| Архітектор (Silken Net) | EBFC архітектура ([`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)), interfacial oxide-DET DFT (script-53), BQ25570 Cold Start, firmware delta_t |

**Тип зв'язку:** Комплементарний — ЧНУ теоретична модель (DFT), ЧМА in vitro валідація, Silken Net системні вимоги.

> **In-silico baseline:** Zero-Lab L1-L4 PASSED (2026-05-25). Headline: L1 **d_FAD=15.998 Å** (MET viable); L3 cascade **verified +574 мВ / −0.574 eV downhill** (E°s; raw DFT uphill = method limit, декомпозовано ②); L3b cathode DET **borderline** at realistic λ; L4 recharge-model (delta_t → GP, E.63 calibration-pending). Повні числа — [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) + [`PIPELINE_STATUS.md`](protocols/ebfc/in_silico/PIPELINE_STATUS.md).

#### Стаття 29: Токсикологічна Оцінка Ti-6Al-4V Гіроїдних Анкерів

**Назва (EN):** _"Phytotoxicological Assessment of Ti-6Al-4V TPMS Gyroid Anchors for Forest Cyber-Physical Systems: Vanadium and Aluminum Ion Release, Bioaccumulation, and 20-Year Safety Modeling"_
**Журнали:** Environmental Pollution (Q1) · Science of The Total Environment (Q1) · Chemosphere (Q1)

| Автор | Внесок |
|-------|--------|
| **Суховий Г.П.** (ЧМА) | Фітотоксичність V/Al для *Pinus sylvestris*, Safety Margin, хронічна біоакумуляція |
| **Гусак А.М.** (ЧНУ) | ICP-MS вимірювання V/Al release + калібрація Kirkendall-моделі (наш script 51) проти виміряного (20-рік екстраполяція) |
| **Глущенко А.В.** (ЧМА) | Оцінка фітотоксичності 8-HQ self-healing покриття, альтернативні інгібітори |
| **Спрягайло О.В.** (ЧНУ) | Склад ксилемного соку *Pinus sylvestris*, фітоценологічний контекст Черкаського бору |
| Архітектор (Silken Net) | Ti-6Al-4V специфікація ([`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)), self-healing концепт, 20-річна цільова довговічність |

**Тип зв'язку:** Послідовний — ЧНУ (Гусак) вимірює концентрації + модель → ЧМА (Суховий) оцінює біологічний вплив + Safety Margin.

> ⚠️ **V-free напрям:** founder обрав сплав **Ti-6Al-7Nb** (V-free, [`01_02 §2.5`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)) → наратив зсувається з «чи безпечний V-release» на **design-rationale V-free + comparative 4V↔7Nb release** (дані дає Stage-2 coin ICP-MS, HW.24/HW.3). Назву/scope не переписуємо до coin-валідації (baseline ще 4V — no-premature-canon).

---

## ⚖️ 3. IP-постава — дім переїхав у [`00_01 §8`](00_01_Vision_Mission_and_Roadmap)

Ліцензійна матриця, чотири стовпи постави (defensive publication · open license · trademark · trade secret), non-assertion pledge, межа розкриття та розподіл «відкрито / утримуємо» живуть тепер у [`00_01 §8`](00_01_Vision_Mission_and_Roadmap).

**Чому не тут:** аудиторія цієї постави — кожен контрибʼютор і кожна CI-джоба, а не академічний шар. `NOTICE` називає її каноном першим рядком блоку LICENSING; на неї ж ключуються `README`, `dco.yml`, `spdx_headers.rb` і `dco_check.rb`. Критерій місії [`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap) уже декларує «невідбирано» одним із трьох несучих слів і шле по деталь саме туди — тож це возз'єднання, а не переїзд (⚖️ ратифіковано 2026-08-09).

Що лишається в цьому доці: **§4** — виконавчі IP-**інструменти** (TISC-консультація, ™-заявка через повіреного УкрНОІВІ, UA-юр-review) з власниками й послідовністю етапів; вони прив'язані до української юрисдикції та персоналій партнерського реєстру §1.5, тож живуть поруч із ними.

## 🏛️ 4. IP-інструменти (TISC + trademark + UA-юр-review)

> Під defensive-publication ([`00_01 §8`](00_01_Vision_Mission_and_Roadmap)) prior-art landscape уже готовий ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)); лишаються TISC-консультація, trademark і точковий UA-юр-review.

### 4.1 TISC — консультація (prior-art / IP / open-license)

**Що це:** Центр Підтримки Технологій та Інновацій — публічна мережа **WIPO** (координує УкрНОІВІ); academic-rate консультація.

| Сервіс TISC (консультативний) | Кейс SilkenNet |
|---|---|
| Prior-art landscape (Espacenet / PATENTSCOPE / Google Patents) | верифікація новизни Статті 1 + анти-захоплення (query-set готовий, прогін — residual → [`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)) |
| Консультація з **торгових марок** | напрям заявки SilkenNet™ / GaiaNexus™ / SCC™ (подача — повірений, ↓) |
| Консультація з **open-license** сумісності у UA-юрисдикції | AGPL / CERN-OHL-S / CC-BY-SA legal sanity |

**Подача ™** — прямий повірений УкрНОІВІ (~5-10k UAH; TISC консультативний, сам не подає).

### 4.2 UA-юр-review → Аблязов + крипто/IP-юрист TBD

**Точковий UA-юр-review:** RWA як `hadron_asset_id` vs Лісовий Кодекс/ПЗФ ([`00_07` BIZ.11](00_07_Action_Plan_Tracker)) · SCC utility-vs-security за ЗУ «Про віртуальні активи» + MiCA ([`05_03`](05_03_Tokenomics_SCC_and_SFC)) · NaaS у Civil Code + `parametric_insurance` ([`07_01`](07_01_Nature_as_a_Service_Contracts)) · AGPL-enforcement + open-license/AF3 ([`00_01 §8`](00_01_Vision_Mission_and_Roadmap)). Виконавець: **Аблязов Д.Е.** (СЄУ, персонально) + профільний крипто/IP-юрист TBD.

### 4.3 Операційна послідовність

| Етап | Дія | Власник |
|---|---|---|
| 1 | Prior-art **query-set** готовий ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)); самі пошуки ще НЕ прогнані, hit-лог порожній, висновок умовний | 🤖 residual → [`00_07`](00_07_Action_Plan_Tracker) UNI.3 |
| 2 | Заявка на ™ (прямий повірений УкрНОІВІ) — пріоритет-дата ДО disclosure-splash (squatting-guard; режими юридично незалежні, порядок = risk-management) | 👤 повірений |
| 3 | Публікація disclosure (TDCommons) + LICENSE-файли → [`defensive_disclosure.md`](protocols/anchor/defensive_disclosure.md) | 👤 + 🤖 |
| 4 | UA-юр-review (Аблязов + крипто/IP-юрист TBD) | 👤 |
| 5 | Сабміт Статті 1 (вже unblocked — publish-to-protect) | 👤 |

---

## 🌿 5. Бренд-архітектура (SilkenNet / GaiaNexus)

> **Рішення (2026-06-16, [`00_07` — BIZ.16](00_07_Action_Plan_Tracker)):** імена проєкту розведені **за висотою** — продукт vs планетарна федерація. Це модель найменування (naming), не IP-права ([`00_01 §8`](00_01_Vision_Mission_and_Roadmap)).

| Ім'я | Роль | Канонічна форма |
|---|---|---|
| **SilkenNet** / Silken Net | Лісовий net — продукт/мережа (орган №1, існує сьогодні). Код-неймспейс `SilkenNet::`; ™. | `SilkenNet` (code/™) · `Silken Net` (display) |
| **GaiaNexus** | Планетарна федерація / ноосферний апекс — нексус усіх майбутніх net-ів (far-horizon, [`00_01 §4`](00_01_Vision_Mission_and_Roadmap)); ™. | `GaiaNexus` (закрита, окрема від «X Net») |
| **SCC** / **SFC** | Токени екосистеми (Silken Carbon / Forest Coin); ™ SCC. | — |

**Конвенція найменування net-ів** (на випадок розгортання федерації — далекий горизонт, не зараз): `<Корінь> Net` (display) / `<Корінь>Net` (code/™), дзеркалить `Silken Net`/`SilkenNet`; корінь — греко-латинський домен-морфем за **геофізичною сферою** (biosphere → Silken · cryosphere → Cryo · hydrosphere → Abyssal · lithosphere → Litho · pedosphere → Myco), а **noosphere → GaiaNexus** як інтегратор. `Silken Net` — grandfathered первісток (поетичний корінь = легітимний виняток). Вузлова абстракція — `PlanetaryNode` (Збір енергії → Сенсорика → Оцифрування хаосу → Токенізація). Сиблінг-нети та їхні токени — кандидати рівня `SRL:Concept`, **свідомо НЕ канонізовані** як baseline ([`00_01 §4`](00_01_Vision_Mission_and_Roadmap)).
