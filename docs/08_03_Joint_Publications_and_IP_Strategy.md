# 08_03: Спільні Публікації та Стратегія IP

## 🎯 Мета

Легітимізація технології Silken Net у світовому науковому просторі та юридичне закріплення прав на інтелектуальну власність у межах співпраці ЧНУ та Silken Net. Формування системи публікацій, що охоплює весь технологічний стек від фізики анкера до математики токеноміки.

> **Принцип партнерства:** Silken Net надає інноваційний R&D-полігон. ЧНУ надає академічну легітимність та лабораторну інфраструктуру. Обидві сторони отримують максимум при мінімальних витратах.

---

## ✅ Статус

- **Стратегічна цінність:** Наукові публікації ЧНУ + ЧДТУ (3 кафедри) + ЧІПБ = легітимізація технології + Hardware Proof для seed-раунду + Data Science валідація + RF-верифікація + акустична валідація + пожежна безпека та параметричне страхування
- **Поточний TRL:** TRL 3 — публікаційний план визначено, авторські колективи формуються
- **Пов'язані модулі:**
  - Університетські протоколи → [`08_01_University_R_and_D_Protocols`](08_01_University_R_and_D_Protocols)
  - Кіберфізична валідація → [`08_02_Cybernetic_and_Mathematical_Validation`](08_02_Cybernetic_and_Mathematical_Validation)
  - ЧДТУ Data Science → [`08_04_CHDTU_Data_Science_Collaboration`](08_04_CHDTU_Data_Science_Collaboration)
  - ЧІПБ: Пожежна безпека та SOP → [`08_05_CHIPB_Fire_Safety_Integration`](08_05_CHIPB_Fire_Safety_Integration)
  - Юніт-економіка → [`07_02_Unit_Economics_and_BOM`](07_02_Unit_Economics_and_BOM)
  - Токеноміка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)

---

## 🛑 Блокери

- **Лабораторні дані відсутні** — перша публікація можлива лише після протоколів з 08_01
- **Авторський колектив не сформований** — потрібні конкретні викладачі ЧНУ
- **Юридичне оформлення IP-договору** — до початку спільних лабораторних робіт
- **Патентна заявка на дизайн анкера** — потрібен патентний повірений

---

## 📚 1. План Публікацій (Scopus / Web of Science)

Серія фундаментальних статей для журналів рівня Q1/Q2 на перетині кіберфізики, матеріалознавства та екології:

### Стаття 1: Електрохімія та Генерація Потенціалу (Пріоритет: Перша)

**Назва (EN):** _"Streaming Potential Generation at Titanium-Xylem Interfaces: A Quantum-Chemical and Electrochemical Study of Ti-6Al-4V Gyroid Anchors in Pinus sylvestris"_

**Журнали-цілі:** *Electrochimica Acta* (Q1), *Journal of Power Sources* (Q1), *Bioelectrochemistry* (Q1)

**Авторський колектив:**
- Школа Мінаєва (ЧНУ) — квантово-хімічне моделювання
- Школа Гусака (ЧНУ) — матеріалознавча верифікація
- Архітектор (Silken Net) — дизайн експерименту та практичне застосування

**Ключові результати для публікації:**
- Квантово-хімічна модель генерації потокового потенціалу ~500 мВ
- Вплив мікрошорсткості поверхні на вихідну потужність EBFC
- ICP-MS дані вивільнення іонів Ti/Al/V (< 0.1 мкг/см²)

---

### Стаття 2: Довгострокова Біотрибокорозійна Стійкість (Пріоритет: Друга)

**Назва (EN):** _"Long-Term Bio-Tribocorrosion Resistance of TPMS Gyroid Ti-6Al-4V Implants in Simulated Xylem Sap: Accelerated Aging Protocol for Forest Bioelectronics"_

**Журнали-цілі:** *Corrosion Science* (Q1), *npj Materials Degradation* (Q1), *Acta Biomaterialia* (Q1)

**Авторський колектив:**
- Школа Гусака (ЧНУ) — модель дифузійної деградації (ефект Кіркендалла)
- Біо-хаб ЧНУ (Спрягайло/Гаврилюк) — склад ксилемного соку Pinus sylvestris
- Архітектор (Silken Net) — практичний контекст та вимоги 20-річної довговічності

**Ключові результати:**
- Математична модель деградації анкера на горизонті 20 років
- Протокол акселерованого тесту (12 тижнів @ 40°C ≈ 3–5 польових років)
- Верифікація self-healing покриття на основі мікрокапсул з 8-HQ інгібітором

---

### Стаття 3: Децентралізована Кіберфізична D-MRV

**Назва (EN):** _"Decentralized MRV at Planetary Scale: Lorenz Attractor Homeostasis Detection and Blockchain-Verified Carbon Accounting in Autonomous Forest IoT Networks"_
**Журнали:** Nature Machine Intelligence (Q1) · IEEE Internet of Things Journal (Q1) · Computers & Electronics in Agriculture (Q1)

| Автор | Внесок |
|-------|--------|
| **Порубльов І.М.** | Математична модель надійності G(V,E,P) TTL-flood relay; Monte Carlo аналіз P_delivery при відмові вузлів; калібрування PANIC_TTL та DEFAULT_TTL |
| **Ярмілко А.В.** | Аналіз відмовостійкості TTL-flood relay при стохастичних енергетичних відмовах (dependability framework); верифікація state machine Soldier |
| Косенюк Г.В. | RF link budget LoRa у лісовому масиві; FEC-схема 21-байтового пакету; Hash Method для захисту телеметрійних потоків перед blockchain записом |
| Архітектор (Silken Net) | Дизайн системи, практична імплементація |

---

### Стаття 4: Embedded Security та Dependability для Лісових Smart Implants

**Назва (EN):** _"Energy-Constrained Security and Dependability in Forest Bio-IoT: Lightweight Cryptography, Arithmetic Compression, and Brownout-Resilient Firmware for Tree-Powered STM32 Nodes"_
**Журнали:** IEEE Transactions on Information Forensics and Security (Q1) · Sensors (Q2) · Journal of Network and Computer Applications (Q1)

| Автор | Внесок |
|-------|--------|
| **Ярмілко А.В.** | Lightweight crypto (ECC/SipHash); arithmetic compression; dependability framework; fuzzy dedup methodology |
| **Порубльов І.М.** | Математична реалізація `fuzzy_distance()` для бінарних пакетів |
| Архітектор (Silken Net) | Апаратна специфіка (STM32WLE5JC, BQ25570, 21-байтовий пакет, EBFC) |

**Магістерська робота (Науковий керівник — Порубльов):**
_«Аналіз накопичення похибки в хаотичних системах: BigDecimal precision для Lorenz Attractor»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

**Магістерська робота (Науковий керівник — Ярмілко):**
_«Оптимізація топології LoRa-мережі для мінімізації енерговитрат IoT-рою з нестабільним живленням»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 5: Стохастична Оптимізація та Паралельні Обчислення для Bio-IoT

**Назва (EN):** _"Stochastic Reliability of Energy-Harvesting Forest Mesh Networks and Parallel CFD Simulation of TPMS Gyroid Bioelectrodes on Decentralized Computing Infrastructure"_
**Журнали:** IEEE Transactions on Reliability (Q1) · Future Generation Computer Systems (Q1) · Applied Mathematics and Computation (Q1)

| Автор | Внесок |
|-------|--------|
| **Онищенко Б.О.** | Стохастичний B&B алгоритм Mesh-надійності; мінорантні методи on-MCU; Petri net верифікація firmware; паралельна декомпозиція CFD |
| **Порубльов І.М.** | Математична модель зваженого графа G(V,E,W); Monte Carlo симуляція відмовостійкості |
| Архітектор (Silken Net) | EBFC живлення, STM32WLE5JC специфіка, 21-байтовий пакет, Akash Network deployment |

**Магістерська робота (Науковий керівник — Онищенко):**
_«Стохастична оптимізація надійності передачі даних у самоорганізованих IoT-мережах з нестабільним живленням від відновлюваних джерел»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 6: CNN-Синтез Супутникового та Анкерного Моніторингу + BSP-Кластеризація IoT

**Назва (EN):** _"Multi-Scale Forest Digital Twin: Fusing Satellite CNN Classification with Sub-Tree EBFC Telemetry and BSP-Clustered LoRa IoT for Planetary-Scale Carbon Accounting"_
**Журнали:** Nature Machine Intelligence (Q1) · Remote Sensing of Environment (Q1) · Computers & Electronics in Agriculture (Q1)

| Автор | Внесок |
|-------|--------|
| **Бушин І.М.** | CNN-архітектура для супутникового моніторингу лісу; BSP-кластеризація IoT-графу анкерів; аудит Web/DB архітектури |
| **Порубльов І.М.** | Математична модель графу G(V,E,W) для BSP; просторова агрегація телеметрії |
| Архітектор (Silken Net) | EBFC телеметрія (delta\_t, vcap), LoRa mesh, blockchain верифікація (Chainlink → KlimaDAO) |

**Магістерська робота (Науковий керівник — Бушин):**
_«Синтез супутникових CNN-класифікацій та мікро-телеметрії біосенсорів для побудови Digital Twin лісових екосистем»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 7: Petri Net Верифікація Rails Моноліту та Метод Згортки для Planetary-Scale IoT Backend

**Назва (EN):** _"Formal Verification of a High-Concurrency Ruby on Rails IoT Backend Using Petri Net Patterns and Convolution Method: Deadlock-Free Telemetry Ingestion at Planetary Scale"_
**Журнали:** IEEE Transactions on Software Engineering (Q1) · Journal of Systems and Software (Q1) · Software & Systems Modeling (Q1)

| Автор | Внесок |
|-------|--------|
| **Супруненко О.О.** | Побудова PN-моделі Rails моноліту (Sidekiq + Puma + PostgreSQL pool); Convolution Method для state explosion redukції; аналіз вимог та SDLC-інтеграція |
| **Онищенко Б.О.** | Паралельна семантика Petri net (спільна публікація 2023); stochastic extensions для EBFC-driven availability |
| Архітектор (Silken Net) | Rails 8.1 специфіка, 36+ Sidekiq workers, 9-рівнева черга, Akash deployment, 10,000+ concurrent IoT nodes |

**Магістерська робота (Науковий керівник — Супруненко):**
_«Формальна верифікація паралельних процесів IoT-бекенду засобами мереж Петрі з методом згортки для зниження обчислювальної складності»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 8: RF-Оптимізація Прихованої SMD-Антени, FEC та Стохастична Фільтрація для Автономних Лісових IoT-Капсул

**Назва (EN):** _"Concealed Ceramic SMD Antenna Under PEEK Radome: Impedance Matching, 3D Radiation Pattern Optimization, FEC Telemetry Protection and Stochastic Kalman Filtering for EBFC-Powered Forest IoT at Scale"_
**Журнали:** IEEE Transactions on Antennas and Propagation (Q1) · IEEE Internet of Things Journal (Q1) · Sensors (Q1)

| Автор | Внесок |
|-------|--------|
| **Косенюк Г.В.** | VSWR/КСВ оптимізація SMD-антени під PEEK-радомом (Деталь 4); 3D-діаграма спрямованості з Ti-анкером як Ground Plane; Link Budget LoRa у лісі (SF=7–9 балансування, → `02_01` §5.3); Reed-Solomon FEC для 21-байтового пакету; Kalman/EMA фільтри для delta\_t Edge AI; CE/FCC compliance roadmap |
| **Ярмілко А.В.** | Lightweight cryptography integration (AES-256-ECB для LoRa Soldier→Queen, AES-256-CBC для CoAP batch Queen→Rails, HAL\_CRYP); firmware архітектура SPI/DMA для фільтрованих сигналів |
| Архітектор (Silken Net) | EBFC-джерело живлення (>500 мВ, <500 мкВт), STM32WLE5JC RF-конфігурація, 21-байтовий пакет, IP68 механічна специфікація (Деталь 4 — PEEK Crown) |

**Магістерська робота (Науковий керівник — Косенюк):**
_«Радіотехнічна оптимізація мікропотужних IoT-пристроїв у лісовому середовищі: узгодження антенних систем, завадостійке кодування та стохастична фільтрація сигналів EBFC-джерел»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 9: Управління Мультидисциплінарним R&D-Портфелем та Data Mining для Екосистемного IoT

**Назва (EN):** _"Portfolio Optimization and Adaptive Decision-Making in Multi-Disciplinary Deep-Tech Startups: Cluster Analysis, Non-Coercive Interaction Theory, Triple Helix Architecture and Multi-Attribute Edge AI for Planetary-Scale Forest IoT"_
**Журнали:** International Journal of Project Management (Q1) · Technological Forecasting and Social Change (Q1) · IEEE Transactions on Industrial Informatics (Q1)

| Автор | Внесок |
|-------|--------|
| **Осауленко І.А.** | Кластерний аналіз R&D-портфеля; теорія несилової взаємодії для мультидисциплінарних команд; Потрійна спіраль ЧНУ–ActiveBridge–держава; Multi-Attribute Utility Function для Edge AI TX-рішень; DBSCAN/Apriori Data Mining телеметрії |
| **Супруненко О.О.** | Петрі-нетна формалізація Shape Up SDLC; аналіз вимог як вхід для кластеризації R&D-задач |
| Архітектор (Silken Net) | Специфіка 'Silken Net' як кейс-стаді; Shape Up 6-тижневі цикли; firmware STM32WLE5JC архітектура; backend Rails 8.1 Data Mining pipeline |

**Магістерська робота (Науковий керівник — Осауленко):**
_«Методи кластерного аналізу та теорії прийняття рішень в управлінні мультидисциплінарними R&D-портфелями кіберфізичних стартапів: на прикладі IoT-платформи лісового моніторингу»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

### Стаття 10: Генетичні Алгоритми, Синтез Супутникових Даних та Логічна Верифікація для Автономного Лісового IoT

**Назва (EN):** _"Genetic Algorithm-Optimized Neural Networks for EBFC Time-Series Prediction on Constrained MCU, Multi-Source Satellite-Anchor Data Fusion and Boolean Logic Minimization for Autonomous Forest Bio-IoT"_
**Журнали:** Neural Networks (Q1) · IEEE Transactions on Neural Networks and Learning Systems (Q1) · Computers & Electronics in Agriculture (Q1)

| Автор | Внесок |
|-------|--------|
| **Любченко К.М.** | GA-оптимізація backend ML `InsightGeneratorService` (stress_index classification); ансамблевий класифікатор Sentinel-2 (ANN + RF + GA); Master of Logic — мінімізація ДНФ умов TX; формальна верифікація Solana bio\_contract.rs |
| **Бушин І.М.** | CNN-синтез супутникових знімків (спільний вектор: Sentinel-2 + анкери); BSP-кластеризація просторового розподілу аномалій |
| **Ярмілко А.В.** | Firmware OTA-деплой оптимізованих ваг нейромережі; інтеграція мінімальних ДНФ у C-код STM32WLE5JC |
| Архітектор (Silken Net) | Специфіка EBFC delta\_t як вхідного сигналу; Akash training pipeline; Solana bio\_contract.rs специфікація; OTA-механізм (512B chunks) |

**Магістерська робота (Науковий керівник — Любченко):**
_«Генетичні алгоритми для навчання нейронних мереж в умовах обмежених ресурсів мікроконтролерів: синтез супутникових та бортових сенсорних даних для прогнозування екологічного стану лісових екосистем»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net; очікуваний старт: після TRL 4)_

---

## 📊 1B. Публікації ЧДТУ (Data Science, Радіотехніка та Акустика)

> **Контекст:** ЧДТУ забезпечує академічну експертизу за трьома напрямами: Data Science (доц. Карапетян А.Р., кафедра статистики), радіофізика та EMC-верифікація (Декан Гончаров А., ФЕТР, кафедра радіотехніки), акустична мехатроніка та приладобудування (проф. Базіло К.В., проф. Бондаренко М.О., кафедра ПМКТ). Повний реєстр задач — у [`08_04`](08_04_CHDTU_Data_Science_Collaboration).

### Стаття 11: Декомпозиція Часових Рядів Біотелеметрії

**Назва (EN):** _"Time Series Decomposition of Bio-Telemetry from IoT Forest Monitoring"_
**Журнали:** Sensors (Q1, MDPI) · Environmental Monitoring and Assessment (Q2)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | STL/MSTL декомпозиція delta_t; ARIMA/SARIMA/Prophet прогнозування; ACF/PACF аналіз Z-траєкторій |
| Архітектор (Silken Net) | Дизайн системи, структура TelemetryLog, forest_simulator як джерело даних |

**Задачі з реєстру 08_04:** #1 (STL декомпозиція), #2 (прогнозування delta_t), #6 (автокореляційний аналіз)

---

### Стаття 12: Функції Корисності для Автономного Edge AI

**Назва (EN):** _"Utility Functions for Autonomous Decision-Making in Energy-Constrained IoT"_
**Журнали:** Expert Systems with Applications (Q1) · Decision Support Systems (Q1)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | MAUT для growth_points (нелінійна, per породу); Bayesian optimization порогів Лоренца; Decision theory для LoRa TX; mechanism design токеноміки |
| Архітектор (Silken Net) | bio_contract.rb специфіка, ProtocolParameters.sol, InsightGeneratorService |

**Задачі з реєстру 08_04:** #27 (MAUT growth_points), #29 (Edge AI utility), #30 (mechanism design токеноміки)

---

### Стаття 13: Виявлення Аномалій у Масштабних Потоках Лісової Телеметрії

**Назва (EN):** _"Anomaly Detection in Large-Scale Forest Telemetry Streams"_
**Журнали:** IEEE Internet of Things Journal (Q1) · Information Sciences (Q1)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | Isolation Forest, LOF; контекстуальне виявлення аномалій (сезонність + біом); CUSUM/EWMA для replay/spoofing; графові методи для скоординованих атак |
| Архітектор (Silken Net) | insight_generator_service.rb (fraud detection), alert_dispatch_service.rb, Dual Computation Integrity |

**Задачі з реєстру 08_04:** #22 (Isolation Forest), #24 (контекстуальні аномалії), #25 (replay detection), #26 (графові методи)

---

### Стаття 14: Ляпуновські Показники та Рекурентний Аналіз Lorenz-Based Tree Health Index

**Назва (EN):** _"Lyapunov Exponents and Recurrence Analysis of Lorenz-Based Tree Health Index"_
**Журнали:** Chaos, Solitons & Fractals (Q1) · Nonlinear Dynamics (Q1)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | Алгоритм Вольфа (Ляпуновські показники), фрактальна розмірність (Grassberger-Procaccia), RQA (DET, LAM, ENT), реконструкція фазового простору (теорема Такенса) |
| Архітектор (Silken Net) | Lorenz Attractor специфіка (σ=10, ρ=28, β=8/3), silken_net/attractor.rb, bio_contract.rb |

**Задачі з реєстру 08_04:** #7 (Ляпуновські показники), #8 (фрактальна розмірність), #9 (RQA)

---

## 🤝 1C. Міжуніверситетські Публікації (ЧНУ ФОТІУС × ЧДТУ)

> **Принцип:** Де ЧНУ ФОТІУС створює алгоритм або модель — ЧДТУ статистично валідує та розширює. Де ЧНУ ФОТІУС виконує аналітичний розрахунок (RF, фільтри) — ЧДТУ (ФЕТР, ПМКТ) верифікує лабораторно. 10 зон перетину ідентифіковано у [`08_04` §8](08_04_CHDTU_Data_Science_Collaboration#8-міжуніверситетська-синергія-чдту--чну-фотіус).

### Стаття 15: Хаотичний Індекс Здоров'я Дерев — Формальна Верифікація та Динамічний Аналіз

**Назва (EN):** _"Chaos-Based Tree Health Index: Formal Verification and Dynamical Analysis"_
**Журнали:** Chaos, Solitons & Fractals (Q1) · Nonlinear Dynamics (Q1)

| Автор | Внесок |
|-------|--------|
| **Порубльов І.М.** (ЧНУ ФОТІУС) | Формальна верифікація Float64 precision, Euler vs RK4, OPTIMAL_Z_TARGET=29.0, аудит BLOCKER-1/-2/-3 |
| **Карапетян А.Р.** (ЧДТУ) | Ляпуновські показники, фрактальна розмірність, RQA, ентропія, реконструкція фазового простору |
| Архітектор (Silken Net) | Lorenz Attractor специфіка, Dual Computation Integrity |

**Тип зв'язку:** Послідовний — ФОТІУС верифікує математичну коректність → ЧДТУ аналізує властивості Z-траєкторій на верифікованих даних

---

### Стаття 16: Мультиметодне Виявлення Аномалій у Масштабній Лісовій IoT-Телеметрії

**Назва (EN):** _"Multi-Method Anomaly Detection in Large-Scale Forest IoT Telemetry"_
**Журнали:** IEEE Internet of Things Journal (Q1) · Knowledge-Based Systems (Q1)

| Автор | Внесок |
|-------|--------|
| **Осауленко І.А.** (ЧНУ ФОТІУС) | DBSCAN кластеризація telemetry_logs, Apriori правила для EwsAlert + ParametricInsurance |
| **Карапетян А.Р.** (ЧДТУ) | Isolation Forest, LOF, Mahalanobis, CUSUM/EWMA, графові методи |
| Архітектор (Silken Net) | InsightGeneratorService, fraud detection pipeline |

**Тип зв'язку:** Паралельний — ФОТІУС: Data Mining патернів метаболізму, ЧДТУ: статистичне виявлення аномалій

---

### Стаття 17: Генетична Оптимізація зі Статистичною Валідацією для Класифікації Стресу Лісу

**Назва (EN):** _"Genetic Algorithm Optimization with Statistical Validation for Forest Stress Classification"_
**Журнали:** Neural Networks (Q1) · Pattern Recognition (Q1)

| Автор | Внесок |
|-------|--------|
| **Любченко К.М.** (ЧНУ ФОТІУС) | GA-оптимізація ваг InsightGeneratorService (stress_index), 50 поколінь × 100 хромосом |
| **Карапетян А.Р.** (ЧДТУ) | k-fold CV, SHAP пояснюваність, ROC/PR криві, drift monitoring |
| Архітектор (Silken Net) | InsightGeneratorService, ai_train.rake, Akash GPU навчання |

**Тип зв'язку:** Комплементарний — ФОТІУС оптимізує ваги (GA), ЧДТУ оцінює якість та пояснюваність (SHAP)

---

### Стаття 18: Дводжерельна Верифікація Здоров'я Лісу — CNN-Супутник та IoT-Сенсори

**Назва (EN):** _"Dual-Source Forest Health Verification: CNN Satellite Classification Validated by Ground-Truth IoT Sensors"_
**Журнали:** Remote Sensing of Environment (Q1) · Nature Machine Intelligence (Q1)

| Автор | Внесок |
|-------|--------|
| **Бушин І.М.** (ЧНУ ФОТІУС) | CNN перенавчання Sentinel-2 → 6 класів, кореляція stress_map ↔ delta_t |
| **Любченко К.М.** (ЧНУ ФОТІУС) | ANN + RF + GA ensemble класифікатор |
| **Карапетян А.Р.** (ЧДТУ) | Статистична кореляція NDVI ↔ delta_t ↔ z_value, GAM регресія, Moran's I, Kriging |
| Архітектор (Silken Net) | dClimate інтеграція, EWS pipeline, CoAP telemetry |

**Тип зв'язку:** Комплементарний — ФОТІУС будує CNN-класифікатор, ЧДТУ валідує кореляцію статистично

---

### Стаття 19: Оптимальна Параметризація Фільтра Калмана для Шумозниження IoT-Сенсорів

**Назва (EN):** _"Optimal Kalman Filter Parametrization for Energy-Harvesting IoT Sensor Noise Reduction"_
**Журнали:** IEEE Sensors Journal (Q1) · Measurement (Q1)

| Автор | Внесок |
|-------|--------|
| **Косенюк Г.В.** (ЧНУ ФОТІУС) | Kalman Filter реалізація на MCU (< 200 байт RAM, < 50 μs), delta_t ± 1.2% → Z ± 2% |
| **Карапетян А.Р.** (ЧДТУ) | Allan variance шуму, оптимальна частота семплювання, M-estimators калібрація |
| Архітектор (Silken Net) | STM32WLE5JC специфіка, BQ25570 MPPT, EBFC delta_t сигнал |

**Тип зв'язку:** Послідовний — ФОТІУС реалізує фільтр на MCU → ЧДТУ оптимізує параметри Q/R

---

### Стаття 20: Автономне Прийняття Рішень на Основі Корисності для Енергообмежених Лісових IoT-Агентів

**Назва (EN):** _"Utility-Based Autonomous Decision-Making for Energy-Constrained Forest IoT Agents"_
**Журнали:** International Journal of Project Management (Q1) · Expert Systems with Applications (Q1)

| Автор | Внесок |
|-------|--------|
| **Осауленко І.А.** (ЧНУ ФОТІУС) | Multi-Attribute Utility для LoRa TX (W_energy=0.40, W_data=0.30), firmware C реалізація |
| **Карапетян А.Р.** (ЧДТУ) | MAUT для growth_points, Bayesian optimization порогів, Decision theory, mechanism design |
| Архітектор (Silken Net) | bio_contract.rb, firmware TX-рішення, ProtocolParameters.sol |

**Тип зв'язку:** Паралельний — ФОТІУС реалізує MAUT на MCU, ЧДТУ досліджує теоретичні основи та оптимізує

---

### Стаття 21: Перколяційне Параметричне Страхування для IoT-Лісових Мереж

**Назва (EN):** _"Percolation-Based Parametric Insurance for IoT Forest Networks: From Network Physics to Actuarial Science"_
**Журнали:** Insurance: Mathematics and Economics (Q1) · IEEE Transactions on Reliability (Q1)

| Автор | Внесок |
|-------|--------|
| **Порубльов І.М.** (ЧНУ ФОТІУС) | Теорія перколяції (q_c), ланцюги Маркова (TTL-flood relay) |
| **Онищенко Б.О.** (ЧНУ ФОТІУС) | Стохастичний B&B, Monte Carlo симуляція |
| **Карапетян А.Р.** (ЧДТУ) | Weibull/Pareto підбір збитків, чиста премія, space-time clustering, basis risk copula |
| Архітектор (Silken Net) | ParametricInsurance модель, Slashing Protocol (threshold 20%), oracle consensus |

**Тип зв'язку:** Послідовний — ФОТІУС розраховує q_c (фізика мережі) → ЧДТУ використовує q_c як параметр актуарних моделей

> **Розширення (ЧІПБ):** Стаття 25 у [`08_05`](08_05_CHIPB_Fire_Safety_Integration) §4 додає QRA-обґрунтування threshold_value та юридичну валідацію тригерів (Зобенко, ЧІПБ), а стаття 27 — предиктивну fire model delta_t → FWI (Куліца, ЧІПБ). Три статті утворюють повну вертикаль: мережна фізика (21) → страхова математика (25) → пожежна модель (27).

---

### Стаття 22: Статистичний Аналіз Часових Рядів Біотелеметрії з Кіберфізичного Моніторингу Лісу

**Назва (EN):** _"Statistical Analysis of Bio-Telemetry Time Series from Cyber-Physical Forest Monitoring"_
**Журнали:** Computers & Electronics in Agriculture (Q1) · Environmental Modelling & Software (Q1)

| Автор | Внесок |
|-------|--------|
| **Осауленко І.А.** (ЧНУ ФОТІУС) | ARIMA / Holt-Winters прогноз delta_t на 30 днів; backend Data Mining pipeline |
| **Карапетян А.Р.** (ЧДТУ) | STL/MSTL, SARIMA, Prophet, PELT change-point, крос-кореляція, ACF/PACF |
| Архітектор (Silken Net) | DailyAggregationWorker, telemetry_logs партиціювання, forest_simulator |

**Тип зв'язку:** Паралельний — ФОТІУС: прогнозна модель для PoG, ЧДТУ: повний арсенал декомпозиції та аналізу

---

### Стаття 23: Експериментальна Верифікація Прихованої SMD-Антени LoRa у Лісовому Середовищі

**Назва (EN):** _"Experimental Verification of Concealed LoRa SMD Antenna Under PEEK Radome in Forest Environment: VNA Measurements, Field Propagation Tests and EMC Pre-Compliance"_
**Журнали:** IEEE Transactions on Antennas and Propagation (Q1) · IEEE Antennas and Wireless Propagation Letters (Q1) · Sensors (Q1)

| Автор | Внесок |
|-------|--------|
| **Косенюк Г.В.** (ЧНУ ФОТІУС) | Аналітичний розрахунок імпедансу, FEKO/CST моделювання діаграми спрямованості, LC-узгодження, Link Budget |
| **Гончаров А.** (ЧДТУ ФЕТР) | VNA-виміри S11 реальної зборки, натурні вимірювання path loss у лісі, EMC pre-compliance тестування |
| Кафедра радіотехніки ФЕТР | Лабораторна інфраструктура: VNA, EMC-камера, вимірювальні стенди |
| Архітектор (Silken Net) | STM32WLE5JC RF-конфігурація, PEEK-радом (IP68), Ti-6Al-4V Ground Plane, firmware radio driver |

**Тип зв'язку:** Послідовний — ЧНУ (Косенюк) розраховує аналітично → ЧДТУ (ФЕТР) верифікує експериментально → коригування LC-ланцюга → серійна специфікація

**Магістерська робота (Науковий керівник — Гончаров, ЧДТУ ФЕТР):**
_«Експериментальне дослідження радіохарактеристик мікропотужних IoT-пристроїв LoRa 868 МГц у лісовому середовищі з прихованою антенною системою»_

---

### Стаття 24: Фононна Лінза на Основі TPMS-Гіроїда для Акустичного Bio-IoT Сенсингу

**Назва (EN):** _"Phononic Lens Effect in Ti-6Al-4V TPMS Gyroid Structures for Passive Acoustic Filtering in Forest Bio-IoT: Experimental Characterization and TinyML Dataset Generation"_
**Журнали:** Journal of Sound and Vibration (Q1) · Ultrasonics (Q1) · Applied Acoustics (Q1)

| Автор | Внесок |
|-------|--------|
| **Базіло К.В.** (ЧДТУ ПМКТ) | П'єзоелектрична характеризація, імпедансна спектроскопія, акустоелектроніка |
| **Бондаренко М.О.** (ЧДТУ ПМКТ) | Акустичний стенд, мікродеформації, прецизійні вимірювання АЧХ |
| **Ярмілко А.В.** (ЧНУ ФОТІУС) | SPI/DMA pipeline для ADC 16 кГц, firmware інтеграція п'єзосенсора |
| **Карапетян А.Р.** (ЧДТУ) | Статистична характеризація розподілів acoustic_events, класифікаційний аналіз |
| Архітектор (Silken Net) | Дизайн гіроїда (TPMS, 65% пористість, Ti-6Al-4V), концепт Compute-by-Geometry, TinyML pipeline |

**Тип зв'язку:** Послідовний — ЧДТУ (ПМКТ) валідує фізику фононної лінзи → ЧНУ (Ярмілко) оптимізує firmware DMA → ЧДТУ (Карапетян) статистично аналізує результати

**Магістерська робота (Науковий керівник — Базіло або Бондаренко, ЧДТУ ПМКТ):**
_«Дослідження акустичних властивостей пористих TPMS-структур зі сплаву Ti-6Al-4V для пасивної фільтрації ультразвукових емісій біологічних об'єктів»_

---

## 📊 1D. Публікації ЧІПБ (Пожежна Безпека, Параметричне Страхування та SOP)

> **Контекст:** ЧІПБ забезпечує академічну експертизу у валідації тригерів параметричного страхування, розробці SOP для фізичного реагування, предиктивному моделюванні пожеж та актуарному обґрунтуванні блокчейн-оракулів. Повний реєстр задач — у [`08_05_CHIPB_Fire_Safety_Integration`](08_05_CHIPB_Fire_Safety_Integration).

### Стаття 25: Наукове Обґрунтування Тригерів Параметричного Страхування для IoT-Лісових Мереж

**Назва (EN):** _"Scientific Validation of Parametric Insurance Triggers for Autonomous Forest IoT Networks: Quantitative Risk Assessment and Actuarial Modeling of Fire, Drought, and Pest Events"_
**Журнали:** Insurance: Mathematics and Economics (Q1) · Natural Hazards and Earth System Sciences (Q1) · Journal of Risk and Insurance (Q1)

| Автор | Внесок |
|-------|--------|
| **Зобенко Н.** (ЧІПБ) | QRA для 3 trigger_events, юридичне обґрунтування threshold_value, градація слешингу |
| **Куліца О.** (ЧІПБ) | Предиктивна модель поширення вогню, delta_t → FWI, калібрування FIRE_FRP_THRESHOLD_MW |
| **Карапетян А.Р.** (ЧДТУ) | Weibull/Pareto loss distribution, basis risk copula, space-time clustering |
| **Порубльов І.М.** (ЧНУ ФОТІУС) | Теорія перколяції (q_c), ланцюги Маркова для TTL-mesh |
| Архітектор (Silken Net) | ParametricInsurance модель, Etherisc DIP Oracle, ContractHealthCheckService |

**Тип зв'язку:** Послідовний (4 ланки) — ФОТІУС (q_c мережі) → ЧДТУ (статистичні моделі) → ЧІПБ (QRA + fire model) → Архітектор (on-chain integration)

---

### Стаття 26: Інтеграція Кіберфізичних Систем Раннього Попередження з Протоколами Фізичного Реагування ДСНС

**Назва (EN):** _"Bridging Cyber-Physical Early Warning Systems with Physical Emergency Response Protocols: SOP Design for IoT-Monitored Forest Ecosystems"_
**Журнали:** International Journal of Disaster Risk Reduction (Q1) · Safety Science (Q1) · Fire Safety Journal (Q1)

| Автор | Внесок |
|-------|--------|
| **Биченко А.** (ЧІПБ) | Протокол конверсії EwsAlert → ДСНС dispatch, інтеграція з «Пульт-112», drone reconnaissance |
| **Ротар В.** (ЧІПБ) | 7 SOP-документів per alert_type, протоколи для форестерів та патрулів |
| **Несен І.** (ЧІПБ) | Протокол екстракції анкера, інструмент деінсталяції, post-extraction SOP |
| Архітектор (Silken Net) | EmergencyResponseService, EwsAlert, ActuatorCommand, PANIC_TTL firmware |

---

### Стаття 27: Предиктивне Моделювання Лісових Пожеж через Мікро-Телеметрію Біосенсорів

**Назва (EN):** _"Predictive Forest Fire Modeling Through Micro-Telemetry of Bio-Fuel Cell Sensors: Linking Sap Flow Dynamics to Fire Weather Index"_
**Журнали:** International Journal of Wildland Fire (Q1) · Fire Technology (Q1) · Environmental Modelling & Software (Q1)

| Автор | Внесок |
|-------|--------|
| **Куліца О.** (ЧІПБ) | Модель delta_t → FWI, фізика горіння лісової підстилки, time-to-ignition per forest type |
| **Карапетян А.Р.** (ЧДТУ) | STL декомпозиція delta_t, SARIMA прогнозування засухи, кореляція NDVI ↔ delta_t |
| **Косенюк Г.В.** (ЧНУ ФОТІУС) | Kalman Filter delta_t на MCU (< 200 байт RAM), стохастична фільтрація |
| Архітектор (Silken Net) | EBFC delta_t специфіка, dClimate Cosmic Eye, AlertDispatchService |

**Тип зв'язку:** Послідовний — ФОТІУС фільтрує сигнал (Kalman) → ЧДТУ аналізує тренд (SARIMA) → ЧІПБ будує предиктивну fire model

---

## ⚖️ 2. Розподіл Інтелектуальної Власності (IP Framework)

### Власність Silken Net (Архітектора)

| Об'єкт IP | Форма захисту | Статус |
|---|---|---|
| Дизайн коаксіального гіроїдного анкера (Ti-6Al-4V + PEEK) | Патент (utility model) | Очікує подачі |
| Алгоритм Lorenz Attractor для tree homeostasis | Авторське право (код) | Захищено git commit history |
| Архітектура 12-chain Proof of Growth pipeline | Авторське право + trade secret | Захищено |
| TinyML аудіо-класифікаційна модель (4-class: Silence/Wind/Cavitation/Chainsaw; `silken_net_audio_model.h`) | Авторське право | Захищено |
| Форматування 21-байтового пакету телеметрії | Trade secret | Захищено |

### Права ЧНУ (Академічний Партнер)

| Право | Деталі |
|---|---|
| Використання лабораторних даних для дисертацій | Необмежено |
| Включення результатів у навчальну програму ФОТІУС | Необмежено |
| Подача грантів МОН на основі спільних досліджень | Погоджується з Silken Net |
| Участь у міжнародних проєктах (Horizon EU, NATO Science) | Погоджується з Silken Net |
| Публікації від імені ЧНУ (зі Silken Net як co-author) | Вільно |

### Що Silken Net НЕ передає ЧНУ

- Права на комерційну експлуатацію системи (монетизація SCC/SFC)
- Доступ до production API та blockchain ключів
- Права на ліцензування технології третім сторонам

### Права ЧДТУ (Академічний Партнер — 3 кафедри)

| Право | Деталі |
|---|---|
| Використання симульованих та деанонімізованих даних для досліджень | Необмежено (всі 3 кафедри) |
| Включення результатів у навчальну програму відповідних кафедр | Необмежено |
| Подача грантів на основі спільних досліджень | Погоджується з Silken Net |
| Участь у міжнародних проєктах (Horizon EU, NFDI) | Погоджується з Silken Net |
| Публікації від імені ЧДТУ (зі Silken Net як co-author) | Вільно |
| R-скрипти аналізу → open-source в `lib/analytics/r/` | Спільне авторство (Карапетян) |
| RF-вимірювальні дані → `lib/measurements/rf/` | Спільне авторство (Гончаров / ФЕТР) |
| Акустичні калібрувальні дані → `lib/datasets/acoustic_training/` | Спільне авторство (Базіло, Бондаренко / ПМКТ) |

### Що Silken Net НЕ передає ЧДТУ

- Права на комерційну експлуатацію системи (монетизація SCC/SFC)
- Доступ до production API, blockchain ключів та raw production телеметрії
- Права на ліцензування технології або моделей третім сторонам

---

## 🎓 3. Alumni Bridge (Кадровий Резерв)

### Magister Thesis Factory (ЧНУ)

Gaia 2.0 стає офіційним **полігоном для магістерських робіт** студентів ФОТІУС та природничих факультетів ЧНУ:

| Напрям | Тема магістерської | Науковий керівник |
|---|---|---|
| Комп'ютерні науки | "Оптимізація топології LoRa-мережі для мінімізації енерговитрат IoT-рою" | Ярмілко |
| Прикладна математика | "Аналіз накопичення похибки в хаотичних системах: BigDecimal precision для Lorenz Attractor" | Порубльов |
| Хімія наноматеріалів | "Квантово-хімічне моделювання електрохімічної активності Ti-6Al-4V в рослинних рідинах" | Мінаєв |
| Матеріалознавство | "Прискорений тест трибокорозійної стійкості TPMS-гіроїдів у симульованому ксилемному середовищі" | Гусак |
| Екологія | "Базова лінія гомеостазу Pinus sylvestris Черкаського бору для кіберфізичного моніторингу" | Спрягайло/Гаврилюк |
| Прикладна математика | "Стохастична оптимізація надійності передачі даних у самоорганізованих IoT-мережах з нестабільним живленням" | Онищенко |
| Комп'ютерні науки | "Синтез супутникових CNN-класифікацій та мікро-телеметрії біосенсорів для Digital Twin лісових екосистем" | Бушин |
| Комп'ютерні науки | "Формальна верифікація паралельних процесів IoT-бекенду засобами мереж Петрі з методом згортки" | Супруненко |
| Радіотехніка | "Радіотехнічна оптимізація мікропотужних IoT-пристроїв у лісовому середовищі" | Косенюк |
| Управління проєктами | "Методи кластерного аналізу та теорії прийняття рішень в управлінні R&D-портфелями кіберфізичних стартапів" | Осауленко |
| Прикладна математика | "Генетичні алгоритми для оптимізації ML-моделей класифікації стресу лісу" | Любченко |

### Студентські Роботи ЧДТУ (Карапетян А.Р.)

Кафедра статистики та прикладної математики ЧДТУ забезпечує окремий потік студентських робіт на базі Silken Net:

| Рівень | Тема | Задачі з реєстру 08_04 |
|--------|------|------------------------|
| **Магістерська** | "Прогнозування засухи через аналіз часових рядів delta_t" | #1, #2, #3, #6 |
| **Магістерська** | "Побудова функції корисності для Edge AI IoT-агентів" | #27, #29, #30 |
| **Магістерська** | "Методи виявлення аномалій у масивах біотелеметрії" | #22, #23, #24, #25 |
| **Магістерська** | "Статистична кореляція супутникових та сенсорних даних" | #33, #34, #35, #36 |
| **Бакалаврська** | "Аналіз розподілів growth_points на мові R" | #5, #14, #20 |
| **Бакалаврська** | "Візуалізація атрактора Лоренца та рекурентні графіки" | #9, #11, #12 |
| **Бакалаврська** | "Порівняльний аналіз класифікаторів стресу дерев" | #15, #16, #17 |
| **Курсова** | "Описова статистика телеметрії Silken Net (R)" | #5, #37, #40 |
| **Курсова** | "Автокореляційний аналіз Z-значень (R)" | #6, #12, #13 |

### Студентські Роботи ЧДТУ ФЕТР (Гончаров А., кафедра радіотехніки)

| Рівень | Тема |
|--------|------|
| **Магістерська** | "Експериментальне дослідження радіохарактеристик LoRa 868 МГц IoT-пристроїв у лісовому середовищі з прихованою антенною системою" |
| **Бакалаврська** | "Вимірювання та аналіз path loss LoRa-сигналу у вологому лісі при різних Spreading Factor" |
| **Бакалаврська** | "EMC pre-compliance тестування мікропотужних IoT-пристроїв ISM 868/915 МГц" |

### Студентські Роботи ЧДТУ ПМКТ (Базіло К.В., Бондаренко М.О.)

| Рівень | Тема |
|--------|------|
| **Магістерська** | "Дослідження акустичних властивостей пористих TPMS-структур зі сплаву Ti-6Al-4V для пасивної фільтрації ультразвукових емісій" |
| **Бакалаврська** | "Характеризація п'єзоелектричних перетворювачів для детекції кавітаційних емісій у рослинній тканині" |
| **Бакалаврська** | "Створення калібрувального акустичного датасету для навчання TinyML моделей класифікації звуків лісу" |

**Strategic value:** Кожен магістрант — потенційний member команди розгортання Silken Net в Україні та світі. Університет готує кадри, проєкт отримує кваліфіковану робочу силу.

---

## 🚀 4. Стратегія "Повернення Випускника як CTO"

### Чому це працює

Університети живуть **рейтингами та історіями успіху своїх випускників**. Випускник, який:
- Створює кіберфізичну систему планетарного масштабу (D-MRV)
- Залучає Web3-фінансування (peaq, IoTeX, Chainlink, Filecoin)
- Приносить готовий R&D-полігон та перспективу Scopus-публікацій

...є **мрією будь-якої кафедри**. Ти приходиш не просити — ти приходиш **пропонувати партнерство** від імені сучасного deep-tech сектору.

### Твоя Нова Позиція

| Старий фрейм | Новий фрейм |
|---|---|
| "Студент іде до викладача за допомогою" | "CTO міжнародного проєкту пропонує університету R&D-партнерство" |
| "Прошу допомоги з технічним питанням" | "Пропоную готовий полігон для досліджень + Scopus-публікації" |
| "Я використовую ваші знання" | "Ми разом створюємо першу кіберфізичну D-MRV систему в Україні" |
| "Це мій стартап" | "Це глобальна D-MRV платформа — Черкаси стають точкою відліку" |

### Ключове Повідомлення для ЧНУ

> *"Я ваш випускник 2011 року. Тоді ви вчили мене програмуванню автоматизованих систем — "біомедичній кібернетиці". Сьогодні я показую вам Silken Net: систему, де Ti-6Al-4V гіроїд (bio) + STM32 Lorenz Attractor (cybernetics) + 12-chain blockchain (planetary scale) = найвищий прояв того, чому ви мене вчили. Я більше не сиджу за партою. Я сиджу за пультом управління лісовою екосистемою. І мені потрібні ваші мізки для R&D-верифікації цього пристрою. Давайте разом зробимо Черкаси центром планетарного моніторингу лісів."*
