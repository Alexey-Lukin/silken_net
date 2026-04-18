# 08_03: Спільні Публікації та Стратегія IP

## 🎯 Мета

Легітимізація технології Silken Net у світовому науковому просторі та юридичне закріплення прав на інтелектуальну власність у межах співпраці ЧНУ та Silken Net. Формування системи публікацій, що охоплює весь технологічний стек від фізики анкера до математики токеноміки.

> **Принцип партнерства:** Silken Net надає інноваційний R&D-полігон. ЧНУ надає академічну легітимність та лабораторну інфраструктуру. Обидві сторони отримують максимум при мінімальних витратах.

---

## ✅ Статус

- **Стратегічна цінність:** Наукові публікації ЧНУ = легітимізація технології + Hardware Proof для seed-раунду
- **Поточний TRL:** TRL 3 — публікаційний план визначено, авторські колективи формуються
- **Пов'язані модулі:**
  - Університетські протоколи → [`08_01_University_R_and_D_Protocols`](08_01_University_R_and_D_Protocols)
  - Кіберфізична валідація → [`8_02_Cybernetic_and_Mathematical_Validation`](8_02_Cybernetic_and_Mathematical_Validation)
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
| Архітектор (Silken Net) | Rails 8.1 специфіка, 31+ Sidekiq workers, 9-рівнева черга, Akash deployment, 10,000+ concurrent IoT nodes |

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

---

## 🎓 3. Alumni Bridge (Кадровий Резерв)

### Magister Thesis Factory

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
