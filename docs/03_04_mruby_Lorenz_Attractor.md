# 03_04: mruby Атрактор Лоренца (Математика Хаосу та Гомеостаз)

---

## 🎯 Мета

Задокументувати повний алгоритм **Bio-Contract** — mruby-скрипту, що виконується на борту вузла **Soldier** (STM32WLE5JC) і обчислює стан гомеостазу дерева через Атрактор Лоренца. Цей документ є SSOT для:

- **Backend (`TelemetryUnpackerService`)**: сервер знає точну математичну модель і може перевіряти коректність надісланих деревом `growth_points`.
- **Proof of Growth Pipeline (05_02)**: мінтинг SCC заблокований, поки бекенд не розуміє математику, що генерує бали.
- **University R&D (08_02)**: академічна верифікація числової стабільності методу Ейлера у системі Лоренца.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — mruby-скрипт написаний, виконується у VM на мікроконтролері
- **Пов'язані модулі:**
  - Життєвий Цикл Прошивки та DMA → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - TinyML Акустичний Інференс → [`03_03_TinyML_Acoustic_Inference`](03_03_TinyML_Acoustic_Inference)
  - Апаратний AES-256 та Безпека → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)
  - Бізнес-Логіка та Сервіси → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Proof of Growth Pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

| Компонент | Стан |
|---|---|
| **mruby VM ініціалізація** (`mrb_open()` один раз при старті) | ✅ Реалізовано |
| **Байт-код (`lorenz_bytecode[]`) вбудований у Flash** | ✅ Реалізовано |
| **OTA-оновлення контракту** (MRUBY_CONTRACT_FLASH_ADDR = `0x0803F000`) | ✅ Реалізовано |
| **GC Arena save/restore** (запобігання heap fragmentation) | ✅ Реалізовано |
| **Обробка mruby виключень** (`mrb->exc` перевірка) | ✅ Реалізовано |
| **Lorenz math (σ, ρ, β, DT, ITERATIONS)** | ✅ Реалізовано |
| **Sigma/Rho clamp** (захист від вибуху) | ✅ Реалізовано |
| **Z → growth_points конвертація** | ✅ Реалізовано |
| **Bit-packing `[Status:2&#124;GrowthPoints:6]`** | ✅ Реалізовано |
| **Backend дзеркало** (`SilkenNet::Attractor` у Rails) | ✅ Реалізовано |
| **`delta_t` та `vcap` як прямі входи атрактора** | 🔴 BLOCKER — **НЕ реалізовано** (специфікація vs код розходяться) |
| **Збереження стану (x, y, z) між циклами сну** | 🔴 BLOCKER — **відсутнє** (кожен цикл — нова траєкторія) |
| **Float32 vs Float64 верифікація** | 🔴 BLOCKER — **невизначено** |
| **Коментар OPTIMAL_Z_TARGET (20.0 vs 29.0)** | 🔴 BLOCKER — **розбіжність у коді** |

---

## 🛑 Блокери

---

### 🔴 BLOCKER-1: Розбіжність Специфікації та Реалізації (delta_t / vcap)

**Опис:** Issue #191 та архітектурна специфікація визначають `delta_t` (час між пробудженнями MCU, швидкість метаболізму EBFC) та `vcap` (напруга суперконденсатора) як **вхідні параметри** атрактора. Фактична реалізація використовує інші входи:

```
Специфікація:  calculate_state(delta_t, vcap)
Реалізація:    calculate_state(chaos_seed, temp, acoustic)
```

`delta_t` і `vcap` передаються в LoRa payload (байти 8-9 та 4-5 відповідно), але **не передаються** у функцію `calculate_state`. Вони є у `firmware/soldier/main.c`, але у фазі 2 (Bit-Pack), а не фазі 3 (mruby).

**Ризик:** Proof of Growth Pipeline (05_02) описує "фізичний сигнал метаболізму як вхід хаосу". Якщо бекенд перевіряє Z-значення, він має знати **точні** входи. Незнання цього — хибна верифікація.

**Дія:** Архітектурне рішення: або оновити специфікацію (визнати поточну реалізацію правильною), або передавати `delta_t`/`vcap` у bio-contract в наступному циклі.

---

### 🔴 BLOCKER-2: Коментар vs Константа OPTIMAL_Z_TARGET

**Опис:** У `firmware/bio_contracts/bio_contract.rb`, рядок 83:

```ruby
# Розрахунок винагороди: чим ближче стан дерева до ідеалу (20.0),
deviation = (OPTIMAL_Z_TARGET - z_val).abs
```

Коментар каже `ідеал = 20.0`, але константа:
```ruby
OPTIMAL_Z_TARGET = 29.0  # рядок 64
```

**Ризик:** Розбіжність у 9 одиниць Z-осі. Якщо ця константа використовується в академічних публікаціях або юридичних параметричних страхових контрактах — це критична помилка документації. Бекенд і документи мають узгоджуватися.

**Дія:** Виправити коментар у `bio_contract.rb` — замінити `(20.0)` на `(29.0)`.

---

### 🔴 BLOCKER-3: Відсутність Збереження Стану (x, y, z) між Циклами STOP2

**Опис:** Кожен цикл пробудження Soldier генерує **новий** `chaos_seed` з HRNG (`HAL_RNG_GenerateRandomNumber`) і запускає 250 ітерацій Лоренца **з нуля** на основі цього зерна. Стан `(x, y, z)` **не зберігається** у RTC Backup регістрах між циклами сну.

```
Специфікація: "Збереження стану між ітераціями здійснюється у масиві байтів через RTC Backup регістри"
Реалізація:   Нова (x₀, y₀, z₀) з кожного chaos_seed при кожному пробудженні
```

**Ризик:** Система **не є** безперервним хаотичним динамічним атрактором у фізичному сенсі — це 250-кроковий знімок від випадкової початкової точки. Біологічна інтерпретація "гомеостазу" як безперервного процесу ставиться під сумнів. RTC регістри (DR0-DR10) зафіксовані для інших цілей (acoustic_events, last_wakeup_timestamp, mesh_relay, тощо) — місця для (x, y, z) не виділено.

**Дія:** Вирішити архітектурно: (A) прийняти поточну "знімкову" модель і оновити специфікацію; або (B) виділити RTC регістри (3 × float = 12 байт) для збереження стану між пробудженнями.

---

### 🔴 BLOCKER-4: Float32 vs Float64 — Невизначена Точність mruby

**Опис:** Архітектурна специфікація вказує: _"Обчислення виконуються з одинарною точністю (`Float32`) через обмеження FPU Cortex-M4."_ Однак поведінка mruby залежить від прапорів компіляції:

- **Без `MRB_USE_FLOAT`**: mruby використовує `double` (IEEE 754 double, 64-bit) — навіть на Cortex-M4, де немає апаратного double FPU. Операції виконуються програмно (libm soft-float).
- **З `MRB_USE_FLOAT`**: mruby використовує `float` (IEEE 754 single, 32-bit) — використовує апаратний FPU Cortex-M4.

Поточний `Makefile` для mruby не перевірявся в рамках цього аудиту.

**Наслідок для точності:** Після 250 ітерацій Ейлера, накопичена похибка округлення між `float32` та `double` (та BigDecimal backend) може скласти **±5-10 одиниць Z-осі**. Враховуючи зони:
- `CRITICAL_Z_MIN = 2.0`, `CRITICAL_Z_MAX = 45.0`
- Похибка ±5 одиниць може змінити `bio_status` з `0` (homeostasis) на `1` (stress) або `2` (anomaly)
- Це призведе до **хибного Slashing** або **втрати токенів**

**Дія:** (1) Верифікувати прапори компіляції mruby (шукати `MRB_USE_FLOAT` у Makefile або `mrbconf.h`). (2) Додати tolerance band у `TelemetryUnpackerService` при крос-верифікації Z-значень (наприклад, ±2.0).

---

### 🟡 BLOCKER-5: Чисельна Нестабільність Методу Ейлера при DT=0.01

**Опис:** Метод Ейлера першого порядку застосовується для інтегрування системи Лоренца:

```
x_{n+1} = x_n + dx/dt · DT
y_{n+1} = y_n + dy/dt · DT
z_{n+1} = z_n + dz/dt · DT
```

При стандартних параметрах (σ=10, ρ=28, β=8/3), DT=0.01 є прийнятним, але **не стабільним** для методу Ейлера. Характеристичні значення системи мають власні значення з від'ємними дійсними частинами ~O(σ), тому граничний безпечний крок Ейлера: `DT_max ≈ 2/|Re(λ_max)| ≈ 0.1`. DT=0.01 знаходиться в безпечній зоні, але на межі.

**Ризик:** При пертурбованих параметрах (наприклад, `acoustic=200` → `σ_eff=30.0`, що є максимально дозволеним після clamp), крок стає відносно більшим, що збільшує локальну похибку.

**Захисний механізм (вже реалізований):** Clamp σ ∈ [5, 30] та ρ ∈ [10, 50] запобігає найгіршим сценаріям.

**Дія:** Документувати як відомий компроміс. Альтернатива (RK4) потребує 4× більше обчислень — критично для EBFC-живлення. Поточний DT=0.01 прийнятний для "Proof of Growth" (не для наукових симуляцій).

---

### 🟡 BLOCKER-6: Усічення `deviation.to_i` (Truncation vs Round)

**Опис:** Розрахунок балів у зоні гомеостазу:

```ruby
deviation = (OPTIMAL_Z_TARGET - z_val).abs  # Float
reward    = 50 - deviation.to_i             # Integer (TRUNCATION, not rounding!)
growth_points = reward > 0 ? reward : 10
```

`.to_i` усікає до нуля: `0.9.to_i == 0`, `0.1.to_i == 0`. Для z ∈ (28.0, 30.0) — повна зона ±1.0 навколо OPTIMAL_Z_TARGET — `deviation.to_i` завжди `== 0`, тому `reward == 50` для всіх z у цьому інтервалі.

**Ефективна функція growth_points (зона гомеостазу):**

```
z ∈ [28.0, 30.0):  growth_points = 50  (зона "безкоштовного максимуму")
z ∈ [27.0, 28.0):  growth_points = 49  (deviation = 1..2, to_i = 1)
z ∈ [2.0, 15.0):   growth_points = max(10, 50 - deviation.to_i)
z ∈ [43.0, 45.0]:  growth_points = max(10, 36)  = 36
```

**Ризик:** Це не критична помилка, але викликає неточність у Proof of Growth — бекенд має знати про цю "зону безкоштовного максимуму".

**Дія:** Задокументувати як "by design" або замінити `.to_i` на `.round` у наступному рефакторинг-циклі.

---

### 🟡 BLOCKER-7: Нижня Межа growth_points як Мертвий Код

**Опис:**

```ruby
growth_points = reward > 0 ? reward : 10
```

Оскільки `reward = 50 - deviation.to_i` і максимальне відхилення в зоні гомеостазу (`z ∈ [2.0, 45.0]`) від OPTIMAL_Z_TARGET (29.0) не перевищує `max(29-2, 45-29) = 27`, то `reward_min = 50 - 27 = 23 > 0`. Тобто гілка `reward > 0 ? reward : 10` **ніколи не обирає** `10` у зоні гомеостазу — це мертвий код.

**Виняток:** Якщо z ∈ (-∞, 2.0) або z > 45.0 — але ці випадки вже оброблені вищими if-гілками (`status=1` або `status=2`). У блоці `else` (гомеостаз) гілка `:10` є недосяжною.

**Дія:** Задокументувати як "мертвий код захисту". Рекомендується замінити на `clamp(reward, 10, 63)` для ясності.

---

## 🧮 1. Теоретична Основа: Система Лоренца

Атрактор Лоренца — це система трьох нелінійних диференціальних рівнянь, яка описує спрощену конвекцію рідини між двома горизонтальними пластинами різної температури. Едвард Лоренц виявив у 1963 р., що навіть детермінована проста система може демонструвати хаотичну, непередбачувану поведінку.

У контексті Gaia 2.0 ця система моделює **конвекцію соку (флоему)** в дереві — циркуляцію біологічної рідини, яку дерево використовує для транспортування цукрів від коренів до листя (та навпаки).

### 1.1 Система Диференціальних Рівнянь

```
dx/dt = σ · (y - x)
dy/dt = x · (ρ - z) - y
dz/dt = x · y - β · z
```

де:
- **x** — швидкість конвективного потоку (аналог швидкості флоеми)
- **y** — різниця температур між висхідним і низхідним потоком соку
- **z** — відхилення температурного профілю від лінійного (інтенсивність конвекції)
- **σ (sigma)** — число Прандтля (відношення в'язкості до теплопровідності соку)
- **ρ (rho)** — число Релея (різниця температур, що рухає конвекцію)
- **β (beta)** — геометричний параметр (форма конвективної клітини)

### 1.2 Базові Константи Системи

| Константа | Символ | Значення (firmware) | Значення (backend) | Фізичний зміст |
|---|---|---|---|---|
| `BASE_SIGMA` | σ | `10.0` (Float) | `"10.0".to_d` (BigDecimal) | Число Прандтля — в'язкість флоеми |
| `BASE_RHO` | ρ | `28.0` (Float) | `"28.0".to_d` (BigDecimal) | Число Релея — температурний градієнт |
| `BASE_BETA` | β | `8.0 / 3.0` (Float) | `("8.0".to_d / "3.0".to_d).round(18)` | Геометрія конвективної клітини |
| `DT` | Δt | `0.01` (Float) | `"0.01".to_d` (BigDecimal) | Крок інтегрування методу Ейлера |
| `ITERATIONS` | N | `250` | `250` | Кількість ітерацій симуляції |

> **ВАЖЛИВО:** `β = 8.0/3.0 ≈ 2.6666...` (нескінченно повторювана шістка) — точне дробове значення. Попередня помилка `BASE_BETA = 2.666` (обрізане) виправлена у `[FIX: Attractor Sync]`. Різниця між `2.666` та `2.6666...` після 250 ітерацій призводила до систематичного зміщення Z-осі та хибних рішень Slashing.

### 1.3 Класичний Атрактор Лоренца (Метелик)

При σ=10, ρ=28, β=8/3 система демонструє **дивний атрактор** — траєкторія фазового простору ніколи не замикається в петлю, але і не розходиться до нескінченності. Вона кружляє навколо двох нестійких рівноважних точок:

```
C₁ = (+√(β(ρ-1)), +√(β(ρ-1)), ρ-1) = (+8.485, +8.485, 27.0)
C₂ = (-√(β(ρ-1)), -√(β(ρ-1)), ρ-1) = (-8.485, -8.485, 27.0)
```

Значення Z-осі на атракторі знаходиться у приблизному діапазоні **z ∈ [0, 50]**, з тривалим перебуванням у районі z ≈ 25-35 (зона "здорового метелика").

---

## 🔬 2. Архітектура Bio-Contract: Вхідні Дані

### 2.1 Звідки Беруться Вхідні Параметри

```
firmware/soldier/main.c — ФАЗА 1 (SENSE)
│
├── chaos_seed   ← HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed)
│                   uint32_t, апаратна ентропія (теплові шуми)
│
├── internal_temp ← HAL_ADC_GetValue(&hadc)  [ADC, канал internal temp]
│                   int8_t, перетворений через __LL_ADC_CALC_TEMPERATURE()
│                   Діапазон: −45°C .. +90°C (STM32 internal sensor)
│
└── acoustic_events ← TinyML inference + DMA accumulator
                    uint8_t (зберігається в RTC DR0 між циклами)
                    Інкрементується при class=2 (Кавітація), TinyML confidence > 0.80

firmware/soldier/main.c — ФАЗА 3 (mruby виклик)
│
├── args[0] = mrb_fixnum_value(chaos_seed)
├── args[1] = mrb_fixnum_value((int8_t)lora_payload[6])  ← internal_temp
└── args[2] = mrb_fixnum_value(lora_payload[7])           ← acoustic_events
```

> **⚠️ УВАГА (BLOCKER-1):** `delta_t_seconds` та `vcap_voltage` **присутні у фазі 1** та записані в LoRa payload (байти 8-9 та 4-5), але **не передаються** у `calculate_state()`. Атрактор використовує `chaos_seed` (HRNG), а не `delta_t` як крок інтегрування.

### 2.2 Фізична Інтерпретація Вхідних Параметрів

| Параметр | Фізичний зміст | Вплив на Атрактор |
|---|---|---|
| `chaos_seed` (uint32, HRNG) | Апаратна ентропія — "поточний момент часу" у квантовому шумі | Визначає початкові координати (x₀, y₀, z₀) — старт траєкторії |
| `temp` (int8, °C) | Температура кристала STM32 (корельована з температурою дерева) | Збурює ρ: `ρ_eff = 28 + temp × 0.2` → змінює "теплову рушійну силу" |
| `acoustic` (uint8) | Кількість кавітаційних подій флоеми (TinyML) | Збурює σ: `σ_eff = 10 + acoustic × 0.1` → змінює "в'язкість" системи |

#### Фізичний Зміст chaos_seed (Квантовий Шум / TRNG)

`chaos_seed` — не просто "псевдовипадкове число". Це **термічний шум кремнієвого кристала** STM32WLE5JC, виміряний у конкретну мікросекунду часу.

**Фізика TRNG (True Random Number Generator):**
- Апаратний RNG STM32WLE5 вимірює **аналоговий тепловий шум** на рівні кремнієвої решітки
- Оскільки кристал STM32 перебуває всередині капсули, що інтегрована в дерево (Канал 2: Temperature Sensor корелює з температурою ксилеми), **тепловий шум кристала є прямим відображенням теплового стану дерева**
- Кожен виклик `HAL_RNG_GenerateRandomNumber()` займає ~1 мкс і повертає число, яке фізично неможливо передбачити або відтворити

**Наслідок для Атрактора:**
```c
// Перед запуском mruby VM — один мікросекундний запит до TRNG
HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);
// chaos_seed → x₀, y₀, z₀ (початкова точка на метелику)
```

Атрактор Лоренца у кожному циклі "думає", відштовхуючись від термічного шуму ксилеми дерева в цю конкретну мить. Це ідеальне злиття біологічної фізики та математики хаосу: **дерево буквально надає початковий стан своїй власній цифровій свідомості**.

---

## ⚙️ 3. Алгоритм: Крок за Кроком

### Крок 1: Генерація Початкових Координат з chaos_seed

```ruby
# Початковий стан (x₀, y₀, z₀) — "де ми стартуємо на метелику"
x₀ = ((seed % 1000) / 500.0) - 1.0          # seed mod 1000 → [0, 999] → [-1.0, +0.998]
y₀ = (((seed >> 4) % 1000) / 500.0) - 1.0   # seed >> 4 mod 1000 → [-1.0, +0.998]
z₀ = (((seed >> 8) % 1000) / 500.0) - 1.0   # seed >> 8 mod 1000 → [-1.0, +0.998]
```

**Числовий приклад:** При `chaos_seed = 0x12345678 = 305419896`:
```
seed % 1000       = 896   → x₀ = 896/500.0 - 1.0 = 0.792
(seed >> 4) % 1000= 137   → y₀ = 137/500.0 - 1.0 = -0.726
(seed >> 8) % 1000= 341   → z₀ = 341/500.0 - 1.0 = -0.318
```

> Усі початкові координати строго у (-1, 1). Перші кілька десятків ітерацій ("warm-up") атрактор "падає" на дивний атрактор з цього початкового стану.

### Крок 2: Збурення Параметрів σ та ρ (Perturbation)

```ruby
# Пертурбація: фізичні умови змінюють динамічні властивості системи
local_sigma = BASE_SIGMA + (acoustic * 0.1)   # = 10.0 + acoustic/10
local_rho   = BASE_RHO   + (temp * 0.2)       # = 28.0 + temp/5

# Clamp: захист від вибуху при екстремальних показниках
local_sigma = local_sigma.clamp(SIGMA_MIN, SIGMA_MAX)  # ∈ [5.0, 30.0]
local_rho   = local_rho.clamp(RHO_MIN, RHO_MAX)        # ∈ [10.0, 50.0]
```

**Таблиця збурення σ (вплив акустики):**

| `acoustic_events` | `local_sigma` (перед clamp) | `local_sigma` (після clamp) | Стан |
|---|---|---|---|
| 0 | 10.0 | 10.0 | Тиша, нормальна в'язкість |
| 50 | 15.0 | 15.0 | Помірна кавітація |
| 100 | 20.0 | 20.0 | Активна кавітація |
| 200 | 30.0 | 30.0 | Максимум (clamp) |
| 255 | 35.5 | 30.0 | Clamp спрацьовує |

**Таблиця збурення ρ (вплив температури):**

| `temp` (°C) | `local_rho` (перед clamp) | `local_rho` (після clamp) | Стан дерева |
|---|---|---|---|
| −45 | 19.0 | 19.0 | Глибока зима |
| 0 | 28.0 | 28.0 | Базовий стан |
| +20 | 32.0 | 32.0 | Літній режим |
| +55 | 39.0 | 39.0 | Теплова аномалія |
| +110 | 50.0 | 50.0 | Максимум (пожежа, clamp) |

> `BASE_BETA = 8.0/3.0` **не збурюється** — геометрія конвективної клітини вважається фіксованою для даної породи дерева.

### Крок 3: Числове Інтегрування (Метод Ейлера, 250 ітерацій)

```ruby
250.times do
  # Обчислення похідних (права частина системи Лоренца)
  dx = local_sigma * (y - x)           # dx/dt = σ(y - x)
  dy = x * (local_rho - z) - y         # dy/dt = x(ρ - z) - y
  dz = (x * y) - (BASE_BETA * z)       # dz/dt = xy - βz

  # Оновлення стану методом Ейлера першого порядку
  x = x + dx * DT    # x_{n+1} = x_n + (dx/dt) · 0.01
  y = y + dy * DT    # y_{n+1} = y_n + (dy/dt) · 0.01
  z = z + dz * DT    # z_{n+1} = z_n + (dz/dt) · 0.01
end

# Після 250 ітерацій (2.5 одиниць часу системи Лоренца):
return z  # Z-координата — індикатор гомеостазу
```

**Числові параметри симуляції:**
- Загальний час симуляції: `250 × DT = 250 × 0.01 = 2.5` одиниць часу системи
- Порядок похибки методу Ейлера: `O(DT²) = O(0.0001)` на крок
- Накопичена похибка за 250 кроків: `O(250 × DT²) = O(0.025)` (теоретично; хаотична система посилює)

### Крок 4: Функція `calculate_z_axis` (Повний Код)

```ruby
# firmware/bio_contracts/bio_contract.rb — SilkenNet::Attractor
def self.calculate_z_axis(seed, temp, acoustic)
  x = ((seed % 1000) / 500.0) - 1.0
  y = (((seed >> 4) % 1000) / 500.0) - 1.0
  z = (((seed >> 8) % 1000) / 500.0) - 1.0

  local_sigma = BASE_SIGMA + (acoustic * 0.1)
  local_rho   = BASE_RHO   + (temp * 0.2)

  local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN  # clamp lower
  local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX  # clamp upper
  local_rho   = RHO_MIN   if local_rho   < RHO_MIN
  local_rho   = RHO_MAX   if local_rho   > RHO_MAX

  ITERATIONS.times do
    dx = local_sigma * (y - x)
    dy = x * (local_rho - z) - y
    dz = (x * y) - (BASE_BETA * z)

    x += dx * DT
    y += dy * DT
    z += dz * DT
  end

  z  # Повертаємо чисту інтенсивність конвекції (руху соку)
end
```

---

## 🌡️ 4. Логіка Гомеостазу: Z → growth_points

### 4.1 Межі Стабільності та Їх Фізична Інтерпретація

| Константа | Значення | Фізичний зміст |
|---|---|---|
| `CRITICAL_Z_MIN` | `2.0` | Нижня межа — падіння нижче: втрата тургору, посуха |
| `CRITICAL_Z_MAX` | `45.0` | Верхня межа — стрибок вище: аномальний стрес, зовнішнє втручання |
| `OPTIMAL_Z_TARGET` | `29.0` | Ідеальна інтенсивність конвекції для максимального поглинання CO₂ |

### 4.2 Таблиця Рішень (Decision Table)

| Z-значення | Статус (`bio_status`) | Назва | growth_points | Пояснення |
|---|---|---|---|---|
| `z < 2.0` | `1` | ⚠️ Stress (Посуха) | `1` | Мінімальна генерація — дерево виживає, але не росте |
| `z > 45.0` | `2` | 🚨 Anomaly (Критичний стрес) | `0` | Емісія зупиняється повністю |
| `2.0 ≤ z ≤ 45.0` | `0` | ✅ Homeostasis (Здоровий Хаос) | `10 .. 50` | Нараховуються бали росту |

### 4.3 Функція Нарахування Балів у Зоні Гомеостазу

```
deviation      = |OPTIMAL_Z_TARGET - z|  =  |29.0 - z|
reward         = 50 - deviation.to_i
growth_points  = (reward > 0) ? reward : 10
growth_points  = clamp(growth_points, 0, 63)   ← overflow protection (6-bit space)
```

**Графік нарахування growth_points залежно від Z:**

```
growth_points
50 ┤                         ████
49 ┤                       ██    ██
45 ┤                     ██        ██
   │                   ██            ██
35 ┤                 ██                ██
   │               ██                    ██
25 ┤             ██                        ██
23 ┤           ██

10 ┤  ─────────                                ─────────
   │
 1 ┤ █
 0 ┤                                                      ████
   └─────────────────────────────────────────────────────────
   0   2   5   10   15   20   25   29   33   38   43  45   50
                          Z-вісь
```

**Числові приклади:**

| Z-значення | `deviation` | `deviation.to_i` | `reward` | `growth_points` |
|---|---|---|---|---|
| 1.5 | — | — | — | **1** (status=1, stress) |
| 2.0 | 27.0 | 27 | 23 | **23** |
| 10.0 | 19.0 | 19 | 31 | **31** |
| 20.0 | 9.0 | 9 | 41 | **41** |
| 28.5 | 0.5 | 0 | 50 | **50** ← .to_i усікає |
| 29.0 | 0.0 | 0 | 50 | **50** (ідеал) |
| 30.0 | 1.0 | 1 | 49 | **49** |
| 40.0 | 11.0 | 11 | 39 | **39** |
| 44.5 | 15.5 | 15 | 35 | **35** |
| 45.0 | 16.0 | 16 | 34 | **34** |
| 46.0 | — | — | — | **0** (status=2, anomaly) |

### 4.4 Bit-Packing: Структура Байту BioContract

```ruby
payload_byte = (status << 6) | growth_points
```

```
 Bit 7   Bit 6   Bit 5   Bit 4   Bit 3   Bit 2   Bit 1   Bit 0
┌───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐
│  S1   │  S0   │ GP5   │ GP4   │ GP3   │ GP2   │ GP1   │ GP0   │
└───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘
│◄ Status (2) ►│◄────────── Growth Points (6 bits, 0-63) ──────►│
```

| Bits [7:6] | Status | Значення |
|---|---|---|
| `00` | `0` | Гомеостаз (Healthy Chaos) |
| `01` | `1` | Стрес (Посуха / Low Turgidity) |
| `10` | `2` | Аномалія (Critical Stress) |
| `11` | `3` | Tamper (mruby VM помилка → `0xFF`) |

**Розпакування на backend:**

```ruby
# app/services/telemetry_unpacker_service.rb
growth_points = status_byte & 0x3F   # маска нижніх 6 бітів
bio_status    = status_byte >> 6      # верхні 2 біти
```

---

## 🔄 5. Подвійне Обчислення: Firmware vs Backend

Gaia 2.0 використовує **dual computation integrity verification**: Z-значення обчислюється **двічі** — на пристрої та на сервері — для виявлення маніпуляцій або збоїв.

### 5.1 Порівняльна Таблиця Реалізацій

| Параметр | Firmware (mruby) | Backend (Rails) |
|---|---|---|
| **Файл** | `firmware/bio_contracts/bio_contract.rb` | `app/services/silken_net/attractor.rb` |
| **Точність** | Ruby `Float` (IEEE 754, 64-bit або 32-bit залежно від mruby build) | `BigDecimal(18)` — "юридична точність" |
| **σ** | `10.0` (Float) | `"10.0".to_d` (BigDecimal) |
| **ρ** | `28.0` (Float) | `"28.0".to_d` (BigDecimal) |
| **β** | `8.0 / 3.0` (Float) | `("8.0".to_d / "3.0".to_d).round(18)` |
| **DT** | `0.01` (Float) | `"0.01".to_d` |
| **Clamp σ** | `if local_sigma < SIGMA_MIN` / `> SIGMA_MAX` | `.clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)` |
| **Clamp ρ** | `if local_rho < RHO_MIN` / `> RHO_MAX` | `.clamp(RHO_LIMITS.min, RHO_LIMITS.max)` |
| **Результат** | `z` (Float, необроблений) | `z.to_f.round(4)` |
| **Де використовується** | Пакується у `payload_byte` (byte 10 LoRa) | `TelemetryLog.z_value`, ZK-proof верифікація |

### 5.2 Потік Верифікації

```
[Soldier STM32]                           [Rails Backend]
firmware/bio_contracts/bio_contract.rb    app/services/silken_net/attractor.rb
       │                                           │
       │  calculate_state(seed, temp, acoustic)    │  calculate_z(seed, temp, acoustic)
       │  → z_val (Float)                          │  → z_val (BigDecimal → Float.round(4))
       │                                           │
       │  BioContract.evaluate_and_pack            │
       │  → payload_byte [Status:2|GP:6]           │
       │                                           │
       ▼                                           ▼
  lora_payload[10]  ──── LoRa → CoAP ──── TelemetryUnpackerService
                                               │
                                               ├── growth_points = payload[10] & 0x3F
                                               ├── bio_status = payload[10] >> 6
                                               └── z_server = Attractor.calculate_z(seed, temp, acoustic)
                                                   (cross-verification; IoTeX ZK-proof включає z_server)
```

### 5.3 Метод `homeostatic?` (Backend-Only)

```ruby
# Використовує межі з tree_family (налаштовуються на рівні БД для кожної породи)
def self.homeostatic?(z_value, tree_family)
  z_value.between?(tree_family.critical_z_min, tree_family.critical_z_max)
end
```

> **Важлива відмінність:** Firmware використовує **хардкодовані** межі (`CRITICAL_Z_MIN=2.0`, `CRITICAL_Z_MAX=45.0`). Backend використовує межі з **`TreeFamily`** — моделі БД, що дозволяє налаштовувати пороги для різних порід дерев. Для синхронізації необхідно, щоб `tree_family.critical_z_min == 2.0` і `tree_family.critical_z_max == 45.0` за замовчуванням.

---

## 📦 6. Точка Входу та Інтеграція з C

### 6.1 Функція-Міст (C → Ruby)

```c
// firmware/soldier/main.c — ФАЗА 3: ПЛАВКА (мруby Лоренц)
if (mrb) {
  int arena_idx = mrb_gc_arena_save(mrb);   // [FIX: mruby Heap Fragmentation]

  mrb_value args[3];
  args[0] = mrb_fixnum_value(chaos_seed);              // uint32 → Fixnum
  args[1] = mrb_fixnum_value((int8_t)lora_payload[6]); // Temp  → Fixnum
  args[2] = mrb_fixnum_value(lora_payload[7]);          // Acoustic → Fixnum

  mrb_value ruby_result = mrb_funcall_argv(
    mrb,
    mrb_top_self(mrb),
    mrb_intern_lit(mrb, "calculate_state"),  // виклик точки входу
    3, args
  );

  if (!mrb->exc) {
    lora_payload[10] = (uint8_t)mrb_fixnum(ruby_result);  // payload_byte
  } else {
    lora_payload[10] = BIO_STATUS_VM_ERROR;  // 0xFF = Tamper (2 bits) + max GP
    mrb->exc = NULL;                         // скидаємо для наступної ітерації
  }

  mrb_gc_arena_restore(mrb, arena_idx);
}
```

```ruby
# firmware/bio_contracts/bio_contract.rb — точка входу
def calculate_state(seed, temp, acoustic)
  SilkenNet::BioContract.evaluate_and_pack(seed, temp, acoustic)
end
```

### 6.2 OTA-Оновлення Bio-Contract

```c
// Перевірка: чи є у Flash оновлений байт-код?
uint32_t* flash_check = (uint32_t*)MRUBY_CONTRACT_FLASH_ADDR;  // 0x0803F000
if (*flash_check == 0x45544952) {  // "RITE" у little-endian (mruby signature)
    current_lorenz_bytecode = (uint8_t*)MRUBY_CONTRACT_FLASH_ADDR;
} else {
    current_lorenz_bytecode = (uint8_t*)lorenz_bytecode;  // вбудований у Flash
}
mrb_state *mrb = mrb_open();
if (mrb) {
    mrb_load_irep(mrb, current_lorenz_bytecode);
}
```

**Процес оновлення:**
1. Rails завантажує новий `bio_contract.rb`, компілює `mrbc` → байт-код
2. `OtaTransmissionWorker` розбиває на chunks по 11 байт із заголовком `[0x99][idx:2][total:2][data:11]`
3. Queen отримує chunks через CoAP, зберігає у `ota_buffer[1024]`
4. Queen передає chunks Soldier через LoRa Reflex Shot після кожного RX
5. Soldier збирає chunks у `ota_buffer`, перевіряє CRC32 (ISO 3309)
6. При успіху — записує у Flash (`0x0803F000`), виконує `NVIC_SystemReset()`
7. Після рестарту VM завантажує новий контракт

---

## 🔗 7. Залежності та Cross-References

### 7.1 Upstream Dependencies (Що потрібно ПЕРЕД цим модулем)

| Залежність | Статус | Посилання |
|---|---|---|
| Firmware Lifecycle (Phase 1 Sensor Acquisition) | ✅ Синхронізовано | [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA) |
| TinyML Acoustic Inference (acoustic_events) | ⚠️ `Run_Inference()` закоментовано | [03_03_TinyML_Acoustic_Inference](03_03_TinyML_Acoustic_Inference) |
| ADC Temperature Acquisition | ✅ Реалізовано | [02_03_BQ25570_MPPT_Nano_Power](02_03_BQ25570_MPPT_Nano_Power) |
| HRNG Chaos Seed | ✅ Реалізовано | [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA) |

### 7.2 Downstream Dependencies (Що блокує ЦЕЙ модуль)

| Залежність | Що потрібно | Посилання |
|---|---|---|
| Proof of Growth Pipeline | Точна математична модель для крос-верифікації Z-значень | [05_02_Proof_of_Growth_Pipeline](05_02_Proof_of_Growth_Pipeline) |
| Slashing Protocol | `CRITICAL_Z_MIN/MAX` для оцінки кластерного стресу | [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) |
| TelemetryUnpackerService | Формат `payload_byte` та `growth_points` | [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) |
| AlertDispatchService | `bio_status` для детектування stress/anomaly | [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) |
| University Cybernetics Hub | Математична верифікація числової стабільності | [08_02_Cybernetic_and_Mathematical_Validation](08_02_Cybernetic_and_Mathematical_Validation) |

---

## 📎 Пов'язані Файли

| Файл | Призначення |
|---|---|
| `firmware/bio_contracts/bio_contract.rb` | mруby скрипт Bio-Contract (SilkenNet::Attractor + SilkenNet::BioContract) |
| `firmware/soldier/main.c` (рядки 405-435) | C-код виклику mруby (фаза 3) |
| `app/services/silken_net/attractor.rb` | Rails-сервіс (BigDecimal, дзеркало firmware) |
| `app/services/telemetry_unpacker_service.rb` | Розпакування `payload_byte`, виклик `Attractor.calculate_z` |
| `firmware/test/test_soldier_logic.c` | Host-based тести (8 тестів Bio-Contract Byte) |
| `spec/services/silken_net/attractor_spec.rb` | RSpec тести Rails-дзеркала (якщо є) |
