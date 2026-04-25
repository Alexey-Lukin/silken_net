# 08_04: ЧДТУ — Академічне Партнерство з Data Science та Прикладної Статистики

## 🎯 Мета

Формалізація академічної співпраці з **Черкаським державним технологічним університетом (ЧДТУ)** у сфері **Data Science, математичної статистики, методів оптимізації та інтелектуального аналізу даних**. Кафедра статистики та прикладної математики ЧДТУ під керівництвом доц. Карапетян А.Р. забезпечує академічну експертизу для обробки, аналізу та моделювання масивів біотелеметрії, які генерує мережа Silken Net.

> **Контекст:** Архітектор Silken Net (Олексій Лукін) — випускник школи-колегіуму «Берегиня» (Черкаси, 1995–2005), де Анаіт Радіківна Карапетян була його класним керівником протягом семи років. У 2023 році А.Р. Карапетян звернулась із запитом щодо можливих спільних Data Science проєктів. Silken Net — це відповідь на той запит: реальний DeepTech-полігон для наукових досліджень рівня Scopus Q1/Q2.

---

## ✅ Статус

- **Поточний TRL:** TRL 3 — контакт встановлений, формальну співпрацю не розпочато
- **Стратегічний пріоритет:** P1 — математична статистика та Data Science критичні для верифікації Proof of Growth pipeline та масштабування на мільйони дерев
- **Партнерство ЧНУ:** Фізико-хімічна верифікація (хардвер) → [`08_01_University_R_and_D_Protocols`](08_01_University_R_and_D_Protocols)
- **Партнерство ЧНУ ФОТІУС:** Кіберфізична валідація (firmware/backend) → [`08_02_Cybernetic_and_Mathematical_Validation`](08_02_Cybernetic_and_Mathematical_Validation)
- **ЧДТУ:** Data Science, статистика, оптимізація (дані/моделі) → **цей документ**

---

## 🛑 Блокери

- **Формальна зустріч із Карапетян А.Р.** — узгодження формату партнерства (кафедральна тема, студентські роботи, спільні публікації)
- **Меморандум про співпрацю** — юридичне оформлення між ЧДТУ та проєктом Silken Net
- **Доступ до обчислювальних ресурсів** — R/Python кластер для навчання та валідації моделей на масивах телеметрії

---

## 👤 1. Ключовий Науковий Партнер

### 1.1. Доц. Карапетян Анаіт Радіківна — Data Science, Оптимізація та Прикладна Статистика

**Посада:** Завідувач кафедри статистики та прикладної математики ЧДТУ (з 2022). Учений секретар Вченої ради ФІТІС.
**Науковий ступінь:** Кандидат технічних наук, доцент.
**Спеціальність:** Інформаційні технології (аспірантура ЧДТУ, 2011–2014).
**Освіта:** З відзнакою — Черкаський державний педагогічний інститут (1994), спеціальність «Математика».
**Email:** [a.karapetian@chdtu.edu.ua](mailto:a.karapetian@chdtu.edu.ua)
**Локація:** м. Черкаси, бул. Шевченка 460, корпус 1, ауд. 606.

**Наукові інтереси:**
- Методи оптимізації та інтелектуальна обробка інформації
- Функції корисності для оцінки якості та конкурентоспроможності продукції
- Публікації у фахових виданнях ЧДТУ та міжнародних журналах (Scopus, Web of Science)

**Дисципліни, які викладає (спеціальність 112 «Статистика»):**
- Вступ до фаху
- Теорія ймовірностей
- **Аналіз даних на мові R** ← пряма точка перетину зі Silken Net
- Сучасні математичні пакети та програмування

**Міжнародна активність:**
- Програма професійного розвитку академічних менеджерів від Британської Ради (2025)
- Закордонне стажування в Польщі (2026)

**Наукові профілі:** [Google Scholar](https://scholar.google.com/) | [ORCID](https://orcid.org/) | [Scopus](https://www.scopus.com/) | [Кафедра ЧДТУ](https://kstpm.chdtu.edu.ua/staff/karapetyan-anait-radikivna/)

---

## 🗺️ 2. Чому ЧДТУ є Стратегічним Партнером

### 2.1. Комплементарність з ЧНУ

Silken Net будує тристоронню академічну екосистему:

| Університет | Фокус | Рівень | Документ |
|-------------|-------|--------|----------|
| **ЧНУ ім. Б. Хмельницького** (хімія, фізика) | Хардвер: біосумісність Ti-6Al-4V, EBFC, квантова хімія | TRL 1-3 | [`08_01`](08_01_University_R_and_D_Protocols) |
| **ЧНУ ФОТІУС** (кібернетика, ПЗ) | Firmware/Backend: Lorenz valідація, Petri nets, RF | TRL 3-6 | [`08_02`](08_02_Cybernetic_and_Mathematical_Validation) |
| **ЧДТУ** (статистика, Data Science) | Дані/Моделі: статистичний аналіз, ML, оптимізація | TRL 4-8 | **цей документ** |

ЧДТУ закриває критичну прогалину: ЧНУ верифікує **хардвер** та **алгоритми**, а ЧДТУ валідує **дані** та **моделі прийняття рішень**, що ці алгоритми генерують.

### 2.2. Масштаб Data Science задач у Silken Net

Система спроєктована на **мільйони дерев**. Кожне дерево генерує 21-байтний пакет телеметрії щогодини. При масштабі 1М дерев:
- **24М пакетів/добу** → потрібна ефективна агрегація та статистичний аналіз
- **8.76 млрд записів/рік** у партиціонованій таблиці `telemetry_logs`
- Кожен запис містить: `vcap`, `temperature`, `delta_t`, `acoustic_events`, `z_value`, `growth_points`, `bio_status`

---

## 📊 3. Повний Реєстр Data Science Задач у Silken Net

### 3.1. Статистичний Аналіз Часових Рядів Біотелеметрії

**Поточний стан:** Щоденна агрегація (`DailyAggregationWorker`) обчислює середні значення `delta_t`, `vcap`, `z_value`, `temperature` по кластерах. Кластерна базова лінія через SQL `GROUP BY`.

**Код:** `app/workers/daily_aggregation_worker.rb`, `app/services/insight_generator_service.rb` (рядки 131–170)

**Відкриті задачі для ЧДТУ (рівень публікацій):**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 1 | Декомпозиція часових рядів `delta_t` (тренд + сезонність + залишок) | STL (Seasonal-Trend Loess), MSTL | Q2 |
| 2 | Прогнозування `delta_t` на 7-30 днів (засуха, хвороби) | ARIMA, SARIMA, Prophet, ETS | Q2 |
| 3 | Виявлення точок структурних змін у часових рядах `z_value` | PELT (Pruned Exact Linear Time), BOCPD | Q1 |
| 4 | Крос-кореляційний аналіз між деревами одного кластера | Кроскореляція, Granger causality | Q2 |
| 5 | Характеризація розподілів `growth_points` для різних порід дерев | Goodness-of-fit тести, QQ-plots, MLE | Q2 |
| 6 | Автокореляційний аналіз `z_value` для виявлення циклічних патернів | ACF, PACF, спектральний аналіз | Q2 |

**Мова реалізації:** R (курс Карапетян А.Р.) для дослідження та прототипування → Ruby/Rails для production.

---

### 3.2. Атрактор Лоренца — Аналіз Хаотичної Динаміки

**Поточний стан:** Lorenz ODE system (σ=10, ρ=28, β=8/3) інтегрується методом Ейлера (250 ітерацій, DT=0.01). Z-значення класифікує стан дерева: stress (Z < 2.0, status=1, ранній сигнал посухи), homeostasis (2.0 ≤ Z ≤ 45.0, status=0, здоровий хаос, OPTIMAL_Z_TARGET=29.0), anomaly (Z > 45.0, status=2, критичний стрес). Dual Computation Integrity: firmware (Float64) vs backend (Float64 для паритету, BigDecimal доступний). Деталі: [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor).

**Код:** `app/services/silken_net/attractor.rb` (121 рядок), `firmware/bio_contracts/bio_contract.rb`

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 7 | Обчислення Ляпуновських показників для Z-траєкторій | Алгоритм Вольфа, QR-декомпозиція | Q1 |
| 8 | Оцінка фрактальної розмірності атрактора per tree family | Кореляційна розмірність (Grassberger-Procaccia) | Q1 |
| 9 | Рекурентний аналіз (RQA) Z-траєкторій | Recurrence Plots, DET, LAM, ENT метрики | Q1 |
| 10 | Чутливість Z до параметрів σ, ρ, β (bifurcation analysis) | Parameter sweeps, bifurcation diagrams | Q1/Q2 |
| 11 | Реконструкція фазового простору зі скалярних Z-спостережень | Теорема Такенса, Time-delay embedding | Q1 |
| 12 | Аналіз ентропії Z-послідовностей (складність динаміки) | Approximate entropy, Sample entropy, Permutation entropy | Q2 |
| 13 | Валідація горизонту передбачуваності Z-траєкторій | Prediction error accumulation, Lyapunov time | Q2 |

---

### 3.3. Класифікація та Машинне Навчання

**Поточний стан:**
- **Random Forest** (Rumale gem, 100 estimators): бінарна класифікація stress vs healthy за 5 ознаками (`avg_temp`, `avg_vcap`, `avg_z`, `sap_deviation`, `max_acoustic`)
- **TinyML** (INT8 quantized NN): 4-класова акустична класифікація на MCU (silence/wind/cavitation/chainsaw) — **BLOCKER: модель відсутня, inference закоментований**
- **Stress Index:** гібридний (RF predict_proba + rule-based fallback), поріг слешингу: 0.83

**Код:** `lib/tasks/ai_train.rake`, `app/models/tiny_ml_model.rb`, `app/services/insight_generator_service.rb` (рядки 235–258)

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 14 | Feature engineering: похідні ознаки (rate of change, volatility, lagged values) | Temporal feature extraction | Q2 |
| 15 | Порівняння класифікаторів: RF vs XGBoost vs LightGBM vs SVM | Cross-validation, McNemar test | Q2 |
| 16 | Обробка незбалансованих класів (stress рідкісний в homeostatic лісі) | SMOTE, class weights, cost-sensitive learning | Q2 |
| 17 | Пояснюваність моделей (які ознаки визначають stress?) | SHAP values, TreeSHAP, feature importance | Q2 |
| 18 | Оптимізація порогу слешингу (0.83) через ROC/PR-криві | Youden's J, F-beta optimization | Q2 |
| 19 | Багатокласове розширення: critical/warning/normal/optimal | Ordinal classification, cumulative link models | Q2 |
| 20 | Калібрація ймовірностей моделі (predict_proba → реальна частота) | Platt scaling, isotonic regression, reliability diagrams | Q2 |
| 21 | Виявлення дрифту моделі (деградація точності з часом) | Kolmogorov-Smirnov, PSI, DDM, ADWIN | Q1/Q2 |

---

### 3.4. Виявлення Аномалій та Шахрайства (Fraud Detection)

**Поточний стан:** Відносне відхилення від кластерної базової лінії (`FRAUD_DEVIATION_THRESHOLD = 30%`) по `sap_flow` AND `temperature`. Dual Computation: firmware Z vs backend Z, divergence > 30% → fraud flag.

**Код:** `app/services/insight_generator_service.rb` (рядки 175–228), `app/services/alert_dispatch_service.rb`

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 22 | Багатовимірне виявлення аномалій | Isolation Forest, Local Outlier Factor (LOF) | Q2 |
| 23 | Відстань Махаланобіса для врахування кореляцій між ознаками | Mahalanobis distance, robust covariance | Q2 |
| 24 | Контекстуальне виявлення аномалій (сезонність + біом + порода) | Conditional anomaly detection | Q1 |
| 25 | Детекція replay/spoofing атак через статистичні тести | Sequential hypothesis testing (CUSUM, EWMA) | Q1 |
| 26 | Графові методи для виявлення скоординованих атак на кластер | Graph-based anomaly detection | Q1 |

---

### 3.5. Методи Оптимізації та Функції Корисності

**Поточний стан:** Евристичні пороги (`CRITICAL_Z_MIN=2.0`, `CRITICAL_Z_MAX=45.0`, `OPTIMAL_Z_TARGET=29.0`). Лінійний growth_points: `clamp(50 - deviation.to_i, 10, 63)`. Dynamic tax: 2% до `DAO_TREASURY` якщо `insurance_pool < 100,000 SCC`.

**Код:** `firmware/bio_contracts/bio_contract.rb`, `app/services/blockchain_minting_service.rb`, `contracts/ProtocolParameters.sol`

**Відкриті задачі для ЧДТУ (пряма компетенція Карапетян А.Р.):**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 27 | Побудова функції корисності для growth_points (нелінійна, per породу) | Multi-attribute utility theory (MAUT) | Q1/Q2 |
| 28 | Оптимізація порогових зон Лоренца per біом (тропіки vs бореальний ліс) | Bayesian optimization, grid search | Q2 |
| 29 | Функція корисності для Edge AI: коли передавати LoRa TX vs чекати | Decision theory, expected utility maximization | Q1 |
| 30 | Оптимізація параметрів токеноміки (mint rate, slash threshold) | Mechanism design, game theory | Q1 |
| 31 | Мінімізація базисного ризику параметричного страхування | Basis risk models, copula functions | Q1 |
| 32 | Оптимізація розподілу батчів batchMint (100 записів) | Combinatorial optimization, bin packing | Q2 |

---

### 3.6. Супутникові Дані та Синтез з Мікротелеметрією

**Поточний стан:** Інтеграція з dClimate (Sentinel-2 L2A знімки). NDVI обчислюється для EWS (Early Warning System). Кореляція NDVI(t) ↔ delta_t(t) — запланована, не реалізована.

**Код:** `app/services/dclimate/verification_service.rb`, `app/workers/dclimate_verification_worker.rb`

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 33 | Статистична кореляція NDVI ↔ delta_t ↔ z_value для 3+ пілотних регіонів | Pearson/Spearman, partial correlations, PCA | Q2 |
| 34 | Регресійна модель: NDVI(t+30) = f(delta_t, z_value, temp, precip) | Multiple regression, GAM, random effects | Q1/Q2 |
| 35 | Кластерний аналіз просторових патернів стресу | DBSCAN, HDBSCAN, spatial statistics (Moran's I) | Q2 |
| 36 | Геостатистична інтерполяція здоров'я лісу між анкерами | Kriging, IDW, variogram modeling | Q1 |

---

### 3.7. Калібрація Сенсорів та Обробка Сигналів

**Поточний стан:** Фільтр Калмана для `delta_t` — запланований (ЧНУ ФОТІУС, `08_02`). Калібрація апаратна: `DeviceCalibration` модель з offset/coefficient корекцією та drift detection.

**Код:** `app/models/device_calibration.rb` (84 рядки), `app/services/telemetry_unpacker_service.rb`

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 37 | Статистичний аналіз шуму сенсорів (характеризація розподілу помилок) | Allan variance, power spectral density | Q2 |
| 38 | Оптимальна частота семплювання (Найквіст vs енергозбереження) | Information-theoretic sampling, rate-distortion | Q2 |
| 39 | Робастна оцінка параметрів калібрації (стійкість до викидів) | M-estimators, Huber loss, RANSAC | Q2 |
| 40 | Адаптивна нормалізація ADC-значень per порода дерева | Z-score normalization with rolling statistics | Q2 |

---

### 3.8. Параметричне Страхування та Актуарна Аналітика

**Поточний стан:** `ParametricInsurance` модель оцінює щоденне здоров'я vs порогові значення контракту. Oracle consensus + dClimate satellite verification.

**Код:** `app/models/parametric_insurance.rb`, `app/services/parametric_insurance_evaluation_service.rb`

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 41 | Підбір розподілів збитків (Weibull, Pareto, log-normal) | MLE, QQ-plots, AIC/BIC model selection | Q2 |
| 42 | Обчислення чистої премії та loss ratio | Actuarial science, experience rating | Q2 |
| 43 | Просторово-часовий аналіз кластерів претензій | Scan statistics, space-time clustering | Q1 |
| 44 | Оцінка basis risk: індекс vs реальні збитки | Basis risk quantification, copula models | Q1 |

---

### 3.9. Моніторинг та Метрики Продуктивності

**Поточний стан:** 20 Prometheus метрик (10 counters, 8 gauges, 2 histograms). Ендпоінт `/metrics`. Grafana dashboards.

**Код:** `app/services/prometheus_collector.rb`, Sidekiq middleware

**Відкриті задачі для ЧДТУ:**

| # | Задача | Метод | Scopus рівень |
|---|--------|-------|---------------|
| 45 | Автоматичне виявлення аномалій у системних метриках | Prophet anomaly detection, STL residuals | Q2 |
| 46 | SLO-аналіз: P99 латентності мінтингу SCC | Percentile estimation, bootstrap CI | Q2 |
| 47 | Кореляція системного навантаження з якістю телеметрії | Causal inference, Granger causality | Q2 |

---

## 🎓 4. Формати Академічної Співпраці

### 4.1. Кафедральна Наукова Тема

Рекомендована тема для реєстрації на кафедрі статистики та прикладної математики ЧДТУ:

> **«Статистичні методи аналізу та прогнозування часових рядів біотелеметрії в розподілених кіберфізичних системах моніторингу лісових екосистем»**

Підтеми:
1. Стохастичний аналіз хаотичних динамічних систем (Lorenz attractor) для класифікації здоров'я біологічних об'єктів
2. Методи оптимізації функцій корисності для автономних IoT-агентів в умовах енергетичних обмежень
3. Статистичні методи виявлення аномалій та шахрайства в масивах IoT-телеметрії

### 4.2. Студентські Роботи (Дипломні та Курсові)

Повний перелік тем також відображено у [`08_03` §3](08_03_Joint_Publications_and_IP_Strategy) (Alumni Bridge).

| Рівень | Тема | Задачі з реєстру |
|--------|------|-------------------|
| **Магістерська** | Прогнозування засухи через аналіз часових рядів delta_t | #1, #2, #3, #6 |
| **Магістерська** | Побудова функції корисності для Edge AI IoT-агентів | #27, #29, #30 |
| **Магістерська** | Методи виявлення аномалій у масивах біотелеметрії | #22, #23, #24, #25 |
| **Магістерська** | Статистична кореляція супутникових та сенсорних даних | #33, #34, #35, #36 |
| **Бакалаврська** | Аналіз розподілів growth_points на мові R | #5, #14, #20 |
| **Бакалаврська** | Візуалізація атрактора Лоренца та рекурентні графіки | #9, #11, #12 |
| **Бакалаврська** | Порівняльний аналіз класифікаторів стресу дерев | #15, #16, #17 |
| **Курсова** | Описова статистика телеметрії Silken Net (R) | #5, #37, #40 |
| **Курсова** | Автокореляційний аналіз Z-значень (R) | #6, #12, #13 |

### 4.3. Спільні Публікації (Scopus / Web of Science)

Повний план публікацій (статті 11-22, авторські колективи, журнали-цілі) — у центральному документі [`08_03_Joint_Publications_and_IP_Strategy`](08_03_Joint_Publications_and_IP_Strategy):

- **Статті 11-14** — публікації виключно ЧДТУ (Карапетян + Архітектор): часові ряди, функції корисності, аномалії, хаотична динаміка
- **Статті 15-22** — міжуніверситетські (ЧНУ ФОТІУС × ЧДТУ): Lorenz верифікація + аналіз, ML-оптимізація + валідація, CNN-супутник + статистика, фільтрація + калібрація, MAUT, перколяція + страхування, часові ряди

**IP стратегія:** Спільне авторство (ЧДТУ + Silken Net). Open-source код. Дані деанонімізуються. Детальна стратегія — [`08_03` §2](08_03_Joint_Publications_and_IP_Strategy).

---

## 💻 5. Існуюча Кодова База для Data Science

Нижче наведено повний реєстр коду Silken Net, з яким працюватимуть дослідники ЧДТУ:

### 5.1. ML та Класифікація

| Компонент | Файл | Опис |
|-----------|------|------|
| Random Forest training | `lib/tasks/ai_train.rake` | Rumale RF, 100 estimators, 5 ознак → stress/healthy |
| TinyML model management | `app/models/tiny_ml_model.rb` | OTA моделі (TFLite/ONNX), drift tracking (FPR/TPR) |
| Stress Index | `app/services/insight_generator_service.rb:235-258` | Гібрид: RF predict_proba + rule-based fallback |
| AI Insights | `app/models/ai_insight.rb` | daily_health_summary, drought_probability, carbon_yield_forecast |

### 5.2. Математичне Моделювання

| Компонент | Файл | Опис |
|-----------|------|------|
| Lorenz Attractor (backend) | `app/services/silken_net/attractor.rb` | Float64, σ/ρ/β clamping, Z-classification |
| Lorenz BioContract (firmware) | `firmware/bio_contracts/bio_contract.rb` | mruby, Float, 250 ітерацій Euler |
| Protocol Parameters (on-chain) | `contracts/ProtocolParameters.sol` | 13 params: Lorenz σ/ρ/β, tokenomics, slashing |

### 5.3. Обробка Телеметрії

| Компонент | Файл | Опис |
|-----------|------|------|
| Binary unpacker | `app/services/telemetry_unpacker_service.rb` | 21-byte LoRa → structured data |
| Device calibration | `app/models/device_calibration.rb` | Offset/coefficient correction, drift detection |
| Alert dispatch | `app/services/alert_dispatch_service.rb` | Biome-aware thresholds, multi-signal fusion |
| Fraud detection | `app/services/insight_generator_service.rb:175-228` | 30% deviation, dual computation integrity |
| Daily aggregation | `app/workers/daily_aggregation_worker.rb` | PoG pipeline orchestration |
| Cluster baselines | `app/services/insight_generator_service.rb:131-170` | SQL GROUP BY: AVG(temp, sap, z) per cluster |

### 5.4. Gems для Data Science

| Gem | Версія | Використання |
|-----|--------|-------------|
| `rumale` | latest | Random Forest, classification, ML pipeline |
| `numo-narray-alt` | (dependency) | NumPy-like arrays: Numo::DFloat, Numo::Int32 |
| `groupdate` | latest | Time-series grouping (daily, weekly, monthly) |
| `prometheus-client` | latest | Metrics: histograms, counters, gauges |
| `pagy` | latest | Pagination for large telemetry queries |

---

## 🔬 6. Доступ до Даних для Досліджень

### 6.1. Симулятор (без фізичного обладнання)

```bash
bin/rails db:seed        # Gateway, Tree, HardwareKey, TreeFamily
bin/forest_simulator     # CoAP пакети від 5-15 Солдатів кожні 3-8 сек
```

Генерує реалістичну телеметрію для будь-якого дослідження без потреби в фізичних пристроях.

### 6.2. Структура TelemetryLog (головна таблиця для аналізу)

```
id | tree_id | gateway_id | voltage_mv | temperature_c | delta_t |
acoustic_events | bio_status | z_value | growth_points | rssi |
firmware_version | ttl | oracle_status | verified_by_iotex | zk_proof_ref |
created_at (partition key)
```

Партиціонована RANGE по `created_at`. Мільйони записів на добу при масштабі.

### 6.3. Експорт Даних для R

```ruby
# Rails console → CSV для R-аналізу
require "csv"

CSV.open("telemetry_export.csv", "w") do |csv|
  csv << %w[tree_id voltage_mv temperature_c delta_t
            acoustic_events bio_status z_value growth_points created_at]

  TelemetryLog.where(created_at: 1.month.ago..).select(
    :tree_id, :voltage_mv, :temperature_c, :delta_t,
    :acoustic_events, :bio_status, :z_value, :growth_points,
    :created_at
  ).find_each do |log|
    csv << [log.tree_id, log.voltage_mv, log.temperature_c,
            log.delta_t, log.acoustic_events, log.bio_status,
            log.z_value, log.growth_points, log.created_at.iso8601]
  end
end
# Результат: telemetry_export.csv — готовий для read.csv() в R
```

---

## 📋 7. Дорожня Карта Співпраці

### Фаза 1: Знайомство (Q2 2026)

- [ ] Формальна зустріч Олексій Лукін ↔ Карапетян А.Р.
- [ ] Презентація Silken Net для кафедри (демо симулятора + код)
- [ ] Узгодження формату: кафедральна тема або серія студентських робіт
- [ ] Підписання Меморандуму про співпрацю

### Фаза 2: Перші Результати (Q3-Q4 2026)

- [ ] Запуск 2-3 курсових/дипломних робіт на симульованих даних
- [ ] Описова статистика та EDA (Exploratory Data Analysis) телеметрії на R
- [ ] Перший драфт статті: time series decomposition of bio-telemetry
- [ ] Інтеграція R-скриптів аналізу в `lib/analytics/` репозиторію

### Фаза 3: Публікації (2027)

- [ ] Подання 2 статей у Scopus Q2 журнали
- [ ] Запуск магістерських досліджень (anomaly detection, utility functions)
- [ ] Крос-валідація з даними ЧНУ (фізичні лабораторні виміри EBFC ↔ телеметрія)
- [ ] Розширення на реальні дані з пілотних ділянок (Черкаський бір)

### Фаза 4: Масштабування (2028+)

- [ ] Публікації Q1 (Lorenz analysis, fraud detection)
- [ ] Спільна грантова заявка (Horizon Europe, NFDI, або вітчизняні фонди)
- [ ] Залучення PhD-студентів ЧДТУ до довготривалих досліджень

---

## 🔬 8. Міжуніверситетська Синергія: ЧДТУ ↔ ЧНУ ФОТІУС

Аналіз завдань ЧДТУ (цей документ, 47 задач) та ЧНУ ФОТІУС ([`08_02`](08_02_Cybernetic_and_Mathematical_Validation), 27 напрямів, 8 науковців) виявив **8 зон глибокого перетину**, де обидва університети працюють над спорідненими задачами з різних боків. Нижче — матриця залежностей з чітким розподілом ролей. Повні авторські колективи та журнали-цілі для кожної спільної публікації — у [`08_03` §1C](08_03_Joint_Publications_and_IP_Strategy) (статті 15-22).

### 8.1. Матриця Перетину Завдань

| # | Домен | ЧНУ ФОТІУС (08_02) | ЧДТУ (08_04) | Тип зв'язку | Спільна Публікація |
|---|-------|---------------------|--------------|-------------|-------------------|
| **I** | **Атрактор Лоренца** | Порубльов: формальна верифікація точності (Float32/64/BigDecimal), аудит BLOCKER-1/-2/-3/-4/-6, Euler vs RK4, OPTIMAL_Z_TARGET=29.0 | Задачі #7-13: Ляпуновські показники, фрактальна розмірність, RQA, ентропія, реконструкція фазового простору | **Послідовний**: ФОТІУС спочатку верифікує математичну коректність атрактора → ЧДТУ потім аналізує властивості Z-траєкторій на верифікованих даних | «Chaos-Based Tree Health Index: Formal Verification and Dynamical Analysis» (Q1) |
| **II** | **Data Mining / Аномалії** | Осауленко: DBSCAN кластеризація `telemetry_logs` за (delta_t, lorenz_z, temp), Apriori правила для EwsAlert + ParametricInsurance | Задачі #22-26: Isolation Forest, LOF, Mahalanobis, CUSUM/EWMA, графові методи | **Паралельний**: ФОТІУС — Data Mining патернів метаболізму (backend), ЧДТУ — статистичне виявлення аномалій та шахрайства | «Multi-Method Anomaly Detection in Large-Scale Forest IoT Telemetry» (Q1) |
| **III** | **ML-оптимізація** | Любченко: GA-оптимізація ваг `InsightGeneratorService` (stress_index), 50 поколінь × 100 хромосом → F1 ≈ 0.85+ | Задачі #14-21: feature engineering, RF vs XGBoost vs SVM, SHAP, SMOTE, model drift, threshold calibration | **Комплементарний**: ФОТІУС оптимізує ваги (GA), ЧДТУ оцінює якість (CV, ROC, calibration) та пояснюваність (SHAP) | «Genetic Algorithm Optimization with Statistical Validation for Forest Stress Classification» (Q1) |
| **IV** | **Супутниковий синтез** | Бушин: CNN перенавчання (Sentinel-2 → 6 класів), кореляція stress_map ↔ delta_t; Любченко: ANN + RF + GA | Задачі #33-36: статистична кореляція NDVI ↔ delta_t ↔ z_value, GAM регресія, DBSCAN просторовий, Kriging | **Комплементарний**: ФОТІУС будує CNN-класифікатор (CV/DL), ЧДТУ валідує кореляцію статистично (PCA, Moran's I, Kriging) | «Dual-Source Forest Health Verification: CNN Satellite Classification Validated by Ground-Truth IoT Sensors» (Q1) |
| **V** | **Фільтрація сигналів** | Косенюк: Kalman Filter для delta_t на MCU (< 200 байт RAM, < 50 μs), delta_t ± 1.2% → Z ± 2% | Задачі #37-40: Allan variance, Nyquist vs збереження, M-estimators, адаптивна нормалізація | **Послідовний**: ФОТІУС реалізує фільтр на MCU → ЧДТУ статистично аналізує шумові характеристики та оптимізує параметри R/Q | «Optimal Kalman Filter Parametrization for Energy-Harvesting IoT Sensor Noise Reduction» (Q2) |
| **VI** | **Функції корисності** | Осауленко: Multi-Attribute Utility для LoRa TX рішень (W_energy=0.40, W_data=0.30, W_time=0.20, W_net=0.10), TX_UTILITY_THRESHOLD=0.55 | Задачі #27-32: MAUT для growth_points, Bayesian optimization порогів, Decision theory для Edge AI, mechanism design | **Паралельний**: ФОТІУС реалізує MAUT на MCU (firmware C), ЧДТУ досліджує теоретичні основи та оптимізує функції корисності (R) | «Utility-Based Autonomous Decision-Making for Energy-Constrained Forest IoT Agents» (Q1) |
| **VII** | **Перколяція ↔ Страхування** | Порубльов + Онищенко: теорія перколяції (q_c), ланцюги Маркова (TTL-flood relay), Slashing Protocol threshold 20% | Задачі #41-44: Weibull/Pareto підбір збитків, чиста премія, space-time clustering претензій, basis risk | **Послідовний**: ФОТІУС розраховує q_c (фізика мережі) → ЧДТУ використовує q_c як параметр актуарних моделей | «Percolation-Based Parametric Insurance for IoT Forest Networks: From Network Physics to Actuarial Science» (Q1) |
| **VIII** | **Часові ряди** | Осауленко: ARIMA / Holt-Winters прогноз delta_t на 30 днів; backend Data Mining | Задачі #1-6: STL, SARIMA, Prophet, PELT change-point, крос-кореляція, ACF/PACF | **Паралельний**: ФОТІУС — прогнозна модель для PoG, ЧДТУ — повний арсенал декомпозиції та аналізу | «Statistical Analysis of Bio-Telemetry Time Series from Cyber-Physical Forest Monitoring» (Q2) |

### 8.2. Ланцюги Залежностей (Pipeline між Університетами)

Деякі задачі мають чітку послідовність «вхід → обробка → вихід», де результат одного університету є входом для іншого:

```
ЛАНЦЮГ 1: Lorenz Pipeline
  ЧНУ ФОТІУС (Порубльов)                    ЧДТУ (Карапетян)
  ┌─────────────────────────┐                ┌─────────────────────────┐
  │ Формальна верифікація:  │                │ Аналіз хаосу:           │
  │ • Float64 precision     │───────────────>│ • Ляпуновські показники │
  │ • Euler vs RK4          │  верифіковані  │ • Фрактальна розмірність│
  │ • OPTIMAL_Z_TARGET      │  Z-траєкторії  │ • RQA метрики           │
  │ • BLOCKER-1/-2/-3       │                │ • Entropy analysis      │
  └─────────────────────────┘                └─────────────────────────┘

ЛАНЦЮГ 2: ML Pipeline
  ЧНУ ФОТІУС (Любченко)                     ЧДТУ (Карапетян)
  ┌─────────────────────────┐                ┌─────────────────────────┐
  │ GA-оптимізація:         │                │ Статистична валідація:   │
  │ • Stress_index ваги     │───────────────>│ • k-fold CV + stratif.  │
  │ • F1-score fitness      │  оптимальні   │ • SHAP пояснюваність    │
  │ • Akash GPU навчання    │  ваги моделі  │ • ROC/PR криві          │
  └─────────────────────────┘                │ • Drift monitoring      │
                                             └─────────────────────────┘

ЛАНЦЮГ 3: Percolation → Insurance Pipeline
  ЧНУ ФОТІУС (Порубльов + Онищенко)         ЧДТУ (Карапетян)
  ┌─────────────────────────┐                ┌─────────────────────────┐
  │ Мережна фізика:         │                │ Актуарна наука:         │
  │ • q_c (критичний поріг) │───────────────>│ • Loss distribution fit │
  │ • Марковські ланцюги    │  q_c як вхід  │ • Pure premium calc     │
  │ • Monte Carlo sim       │  страхових    │ • Basis risk copula     │
  └─────────────────────────┘  моделей      └─────────────────────────┘

ЛАНЦЮГ 4: Signal → Statistics Pipeline
  ЧНУ ФОТІУС (Косенюк)                      ЧДТУ (Карапетян)
  ┌─────────────────────────┐                ┌─────────────────────────┐
  │ Kalman Filter на MCU:   │                │ Статистичний аналіз:    │
  │ • Q/R параметри         │───────────────>│ • Allan variance шуму   │
  │ • EMA альтернатива      │  відфільтро-  │ • Оптимальна частота    │
  │ • < 200 байт RAM        │  вані delta_t │ • M-estimators калібр.  │
  └─────────────────────────┘                └─────────────────────────┘
```

### 8.3. Завдання Виключно для ЧДТУ (без перетину з ФОТІУС)

Наступні задачі належать **виключно** до компетенції ЧДТУ і не мають паралелей у `08_02`:

| Задачі | Домен | Чому тільки ЧДТУ |
|--------|-------|------------------|
| #5, #20 | Характеризація розподілів, калібрація ймовірностей | Класична математична статистика — профіль кафедри Карапетян |
| #30 | Оптимізація токеноміки (mechanism design, game theory) | Економічна теорія ігор — не покривається інженерними кафедрами ЧНУ |
| #45-47 | Prometheus метрики: Prophet anomaly, SLO-аналіз, Granger causality | Infrastructure monitoring analytics — не входить до scope ФОТІУС |
| #19 | Ordinal classification (critical/warning/normal/optimal) | Розширення ML-моделі — статистичний метод, не GA-оптимізація |

### 8.4. Завдання Виключно для ЧНУ ФОТІУС (без перетину з ЧДТУ)

Наступні напрямки `08_02` не мають паралелей у ЧДТУ і залишаються виключно у компетенції ФОТІУС:

| Напрямок | Науковець ФОТІУС | Чому тільки ФОТІУС |
|----------|-------------------|---------------------|
| SPI/DMA оптимізація MCU | Ярмілко | Апаратна інженерія embedded systems |
| Lightweight Cryptography (ECDH, MAC) | Ярмілко | Безпека IoT-прошивки |
| Арифметичне стиснення payload | Ярмілко | Data compression на MCU |
| Petri net верифікація (firmware + Rails) | Супруненко + Онищенко | Формальні методи верифікації ПЗ |
| Convolution Method (state explosion) | Супруненко | Теоретична CS |
| RF-оптимізація SMD-антени | Косенюк | Радіотехніка / електромагнітна сумісність |
| FEC (Reed-Solomon/Hamming) | Косенюк | Теорія кодування |
| BSP-кластеризація IoT-графу | Бушин | Алгоритмічна кластеризація графів |
| Геометрична валідація гіроїда | Порубльов | Обчислювальна геометрія |
| CE/FCC/EMC сертифікація | Косенюк | Регуляторна відповідність |
| CFD-симуляції на Akash | Онищенко | Паралельне програмування |
| Master of Logic (Boolean мінімізація) | Любченко | Формальна логіка та верифікація |

### 8.5. Рекомендації щодо Координації

1. **Спільний семінар (Kickoff):** Провести одноденний семінар ЧДТУ + ЧНУ ФОТІУС з демонстрацією Silken Net (forest_simulator). Мета: взаємне знайомство команд, узгодження форматів даних, визначення спільних публікацій.

2. **Спільний датасет:** Один і той же набір симульованої телеметрії (`bin/forest_simulator`, 1 місяць, 50 дерев) використовується обома університетами як benchmark. Формат CSV — експорт через скрипт секції 6.3.

3. **Quarterly Sync:** Щоквартальна зустріч Архітектор + Карапетян (ЧДТУ) + Онищенко/Супруненко (ФОТІУС) для синхронізації результатів та планування спільних публікацій.

4. **Git-based Collaboration:** ЧДТУ R-скрипти → `lib/analytics/r/`, ФОТІУС Python/C → `lib/analytics/python/`. Обидва інтегруються через CI/CD (09_03).

5. **Потрійна Спіраль 2.0:** Модель Осауленка (08_02 §1.7) розширюється з ЧНУ → ЧНУ + ЧДТУ як наукова вершина спіралі. Два університети = ширша академічна база для грантових заявок (Horizon Europe, NFDI).

---

## 🔗 9. Пов'язані Документи

- [`08_01_University_R_and_D_Protocols`](08_01_University_R_and_D_Protocols) — ЧНУ: фізико-хімічна верифікація хардверу
- [`08_02_Cybernetic_and_Mathematical_Validation`](08_02_Cybernetic_and_Mathematical_Validation) — ЧНУ ФОТІУС: кіберфізична валідація
- [`08_03_Joint_Publications_and_IP_Strategy`](08_03_Joint_Publications_and_IP_Strategy) — стратегія публікацій та IP
- [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor) — математика атрактора Лоренца
- [`03_03_TinyML_Acoustic_Inference`](03_03_TinyML_Acoustic_Inference) — TinyML акустична класифікація
- [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline) — Proof of Growth пайплайн
- [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC) — токеноміка SCC/SFC
- [`06_03_Prometheus_Observability`](06_03_Prometheus_Observability) — метрики та моніторинг
