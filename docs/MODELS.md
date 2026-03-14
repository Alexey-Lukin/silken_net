# 🗂️ Архітектура Сутностей Silken Net

Цей документ описує структуру даних екосистеми Silken Net — децентралізованої мережі моніторингу лісів (D-MRV).

---

## 🏛️ 1. Ядро та Доступ (Core & Identity)

* **User**: Суб'єкт системи (`investor`, `forester`, `admin`, `super_admin`). Керує ролями та доступами. Підтримує `generates_token_for :api_access` з прив'язкою до `password_salt`.

* **Organization**: Юридичний чи децентралізований власник лісових активів. Об'єднує кластери, контракти та гаманці.

* **Session**: Токен доступу (Rails 8 native). Знищується при зміні пароля завдяки прив'язці до `password_salt`.

* **Identity**: OAuth2-ідентичність. Підтримує Google/Apple. Якщо є — пароль не обов'язковий.

---

## 🌲 2. Біологічний Рівень (Environment)

* **TreeFamily**: Генетичний шаблон породи. Містить біологічні константи (порогові значення `critical_z_min` / `critical_z_max` для Атрактора Лоренца).

* **Tree** (Солдат): Основний юніт моніторингу з унікальним DID (`SNET-XXXXXXXX`). Має іоністор (5.5В/0.47Ф), TinyML-модель та власний гаманець.

* **Cluster**: Геопросторовий контейнер (сектор лісу), що об'єднує дерева та шлюзи. Підтримує `active_trees_count` (counter cache) та `local_yesterday` для часового поясу аудиту.

---

## 📡 3. Апаратний Рівень (Hardware & IoT)

* **Gateway** (Королева): LoRa-шлюз із SIM7070G (Starlink/LTE). Центральний хаб, що збирає дані з дерев і передає в Цитадель. Формат UID: `SNET-Q-XXXXXXXX`.

* **HardwareKey**: Криптографічний якір. Зберігає AES-256 ключ для Zero-Trust зв'язку. Прив'язаний до `device_uid` пристрою.

* **DeviceCalibration**: Фільтр точності. Коригує дрейф сенсорів (температура, вольтаж, імпеданс).

* **TelemetryLog**: Цифрова кров Солдата. Зберігає сирі метрики: `voltage_mv`, `temperature_c`, `acoustic_events`, `lorenz_z`, `growth_points`.

* **GatewayTelemetryLog**: Діагностика Королеви. `voltage_mv`, `temperature_c`, `cellular_signal_csq`.

* **Actuator**: Виконавчий механізм шлюзу (клапан, сирена). Прив'язаний до `Gateway`.

* **ActuatorCommand**: Журнал команд. Статуси: `issued` → `sent` → `acknowledged` → `confirmed` / `failed`.

---

## 🧠 4. Інтелектуальний Рівень (Intelligence/Oracle)

* **AiInsight**: Голос Оракула (поліморфний: `Tree` або `Cluster`). Вердикти: `stress_index`, `insight_type: :daily_health_summary`. Threshold для Slashing: `stress_index >= 1.0`.

* **TinyMlModel**: Вагова матриця нейромережі для детекції аномалій на пристрої. Доставляється через OTA у 512-байтних чанках.

* **BioContractFirmware**: mruby-байткод Атрактора Лоренца. Версіонована прошивка для on-device розрахунку `growth_points`.

---

## 💰 5. Економічний Рівень (Economy & Web3)

* **Wallet**: Баланс балів росту дерева. Поріг емісії: `10,000 growth_points = 1 SCC`. Підтримує pessimistic lock при мінтингу.

* **NaasContract**: Nature-as-a-Service контракт. Статуси: `draft` → `active` → `fulfilled` / `breached`. Слешинг активується при >20% аномальних дерев.

* **ParametricInsurance**: Страховий щит кластера. Автоматичні виплати при `critical_fire`, `extreme_drought`, `insect_epidemic`. Підтримує інтеграцію з Etherisc DIP — якщо `etherisc_policy_id` присутній, система працює як Oracle, тригеруючи USDC виплати з децентралізованого пулу ліквідності замість емісії внутрішніх токенів.

* **BlockchainTransaction**: Незмінний слід у мережі Polygon. Статуси: `pending` → `sent` → `confirmed` / `failed`.

---

## 🚨 6. Рівень Дії (Action & Response)

* **EwsAlert**: Нервовий імпульс (прив'язаний до `Cluster`). Типи: `fire`, `drought`, `vandalism`, `pest_detection`, `system_fault`. Статуси: `active` / `resolved`.

* **MaintenanceRecord**: Журнал зцілення (поліморфний: `Tree` або `Gateway`). Proof of Care у полі.

* **AuditLog**: Повний журнал дій системи (поліморфний). Незмінний запис кожної операції. Кожен запис містить SHA-256 `chain_hash` (хеш попереднього запису + payload), утворюючи immutable ланцюг per organization. Поле `ipfs_cid` зберігає Content Identifier для децентралізованого архіву на IPFS/Filecoin, що забезпечує "Вічну Пам'ять" — дані доступні через Filecoin Explorer навіть після знищення серверів.
