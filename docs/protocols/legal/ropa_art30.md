# RoPA — Records of Processing Activities (GDPR Art.30(1))

> **Що це:** робоча чернетка реєстру processing-активностей SilkenNet за **GDPR Art.30(1)** (Records of Processing Activities, «RoPA») — внутрішній compliance-документ для DPO/юриста, переформатований із наявного data-inventory в структуру, яку вимагає стаття. Джерело колонкового рівня — PII-реєстр [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) (2026-08-19); друге джерело — [`b2c_tos_privacy`](b2c_tos_privacy.md) §B.3 (категорії даних × правова підстава) і §D.3 (субпроцесори).
> **Concern-шар** (як [`b2c_tos_privacy`](b2c_tos_privacy.md) / [`b2b_readiness`](../business/b2b_readiness.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-08-20.** Спирається на реальну схему БД і на зовнішнє право — обидва рухаються незалежно від цього документа; перед використанням звіряй колонковий рівень проти [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) (One-Home) і правовий рівень з юристом.
> **⚠️ Не юридична порада.** Робочий вхід у платну консультацію з DPO/юристом (профільний GDPR/крипто-юрист — TBD, [`00_02 §4.2`](../../00_02_Academic_Integration_and_IP.md)), не її заміна. **Це чернетка — показувати наглядовому органу на запит МОЖНА лише після юридичного review**, не в поточному вигляді.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — **SEC.18** (RoPA-чекбокс; сусідні відкриті ⚖️ цього ж пункту — retention-періоди, DSAR-tooling, Art.27-представник, anchor-geo DPIA — цей документ їх СТРУКТУРУЄ, не вирішує).

---

**Статус:** DRAFT v0.1, 2026-08-20 — перше переформатування наявного data-inventory ([`b2c_tos_privacy`](b2c_tos_privacy.md) §B.3 + §D.3) у структуру Art.30(1), за колонковим SSOT [`04_01 §11`](../../04_01_Data_Models_and_Entities.md). Юридичний review **не відбувався**. Сім processing-активностей нижче виведені з реального коду (модель-за-моделлю, не з бізнес-наративу) — де факт не підтверджено прямою звіркою з репо, стоїть `[TBD]`, а не здогад.

## 0. Як читати цей реєстр (guardrails)

**Це реєстр КОНТРОЛЕРА (Art.30(1)), не процесора (Art.30(2)).** У всіх ідентифікованих потоках даних SilkenNet діє як контролер, ніколи як processor-за-інструкцією третьої сторони (мапа ролей → [`b2c_tos_privacy §D.1`](b2c_tos_privacy.md): (1) власні B2C/облікові дані, (2) B2B verified-fact продукт — контролер ВЛАСНОГО output, не processor покупця, (3) відносно власних інфраструктурних вендорів) — тож окремий Art.30(2)-реєстр сьогодні не потрібен.

**Placeholder-конвенція** — та сама, що [`b2c_tos_privacy`](b2c_tos_privacy.md) §0: `[TBD: ...]` = юридичний або операційний факт ще не визначений, публікувати як є не можна.

**⚖️-позначка** = відкрите питання з домом у [`00_07`](../../00_07_Action_Plan_Tracker.md) SEC.18 (чи сусідньому item, названому явно). Цей документ його **структурує під Art.30**, не вирішує — ретеншен-числа, consent-механізм, персону EU-представника тут навмисно НЕ вписано.

**🔴** = знахідка, зроблена ПІД ЧАС побудови цього реєстру (пряма звірка з кодом), яка раніше не мала явного дому в жодному прочитаному документі — зафіксована тут з посиланням, куди її нести далі, не вирішена мовчки.

**Правова підстава (Art.6)** у дужках у колонці (b) кожної активності — вже вирішений факт, перенесений з [`b2c_tos_privacy §B.3`](b2c_tos_privacy.md), не нове рішення цього документа.

---

## 1. (a) Контролер — назва, контакти, представник, DPO

**Юридична форма-оператор уже визначена — нової інкорпорації не потрібно.** SilkenNet розміщується під **operational-vehicle**: наявною українською компанією, Дія.City-резидентом, співзасновником якої є засновник SilkenNet (тришар-присуд — [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md), повна матриця — [`entity_structure`](entity_structure.md), дім стану `00_07` BIZ.20). Відкритими лишаються **дві окремі речі** — не «чи існує юрособа»:

1. **Конкретні реквізити.** Повна юридична назва, код ЄДРПОУ, юридична адреса, контактний email для DSAR/скарг. `[TBD: заповнюється при фіналізації реквізитів]` — той самий плейсхолдер, що [`b2c_tos_privacy`](b2c_tos_privacy.md) §A.1/§A.14/§B.1/§B.18.
2. **⚖️ Чи operational-vehicle є ПРАВИЛЬНИМ GDPR-контролером саме для B2C-поверхні.** Це екстраполяція, не підтверджений факт ([`b2c_tos_privacy §B.1`](b2c_tos_privacy.md)): тришар-присуд явно називає operational-vehicle named counterparty лише для **B2B**-контексту (MSA/гранти/anchor-install liability-щит); controller-роль саме для **B2C** Privacy Policy там окремо не названа. До юридичного підтвердження — найкраще доступне робоче припущення (той самий актор де-факто визначає мету й засоби B2C-обробки), не остаточна відповідь. Дім — `00_07` BIZ.20/UNI.16.

**Представник у ЄС (Art.27):** `[TBD — ще не призначений]` ([`b2c_tos_privacy §B.12`](b2c_tos_privacy.md); чекбокс — `00_07` SEC.18). Обовʼязковість **уже активна**: систематичний EU-таргетинг ратифіковано як чинний намір (⚖️ 2026-08-23, `00_07` SEC.18), тож він більше не виводиться з мовних локалей `lt`/`lv` — ті лишаються одним із факторів EDPB Guidelines 3/2018, а не підставою (той самий факт паралельно важить у securities-аналізі, BIZ.22, і там оголошений намір теж підсилює висновок).

**DPO (Art.37):** не потрібен сьогодні — жоден із трьох тригерів Art.37(1) не виконується на поточному pre-revenue/ранньому B2B-етапі ([`b2c_tos_privacy §B.13`](b2c_tos_privacy.md)). Внутрішній privacy-контакт: `[TBD]`. Переглянути при появі великомасштабної EU-бази або систематичного моніторингу *людей* (не дерев — межа названа в §2.3 нижче).

**Спільні контролери (joint controllers):** не ідентифіковано.

---

## 2. Реєстр processing-активностей — (b)–(g)

Сім активностей нижче покривають усі PII-таблиці [`04_01 §11`](../../04_01_Data_Models_and_Entities.md). Категорії даних у кожній (c) цитують той реєстр дослівно замість повторного класифікування — One-Home лишається там.

### 2.1 Облік користувачів і автентифікація

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Створення й адміністрування облікового запису; вхід (email/Argon2id-пароль); безпека сесії; відновлення пароля; MFA (TOTP, [S6.21](../../00_07_Action_Plan_Tracker.md) — механізм з 2026-08-20). *(Art.6(1)(b) — виконання договору; безпека сесії — Art.6(1)(f) легітимний інтерес, [`b2c_tos_privacy §B.3`](b2c_tos_privacy.md))* |
| **(c) Субʼєкти + дані** | Зареєстровані користувачі (усі ролі). → [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) рядки `users` (PII ядро: `email_address`/`first_name`/`last_name`/`telegram_chat_id`/`push_token`; + `role`/`otp_*`/`recovery_codes`/`locale`/`password_digest`) і `sessions` (PII слід входу: `ip_address`/`user_agent`, `validates presence` — заповнені завжди). |
| **(d) Отримувачі** | Внутрішньо — сам застосунок. Інфраструктурні процесори: **GCP Cloud SQL** (Postgres, `europe-west1`), **Akash Network** (цільовий compute самого застосунку після pivot — mainnet ще НЕ задіяний, TRL5), **Upstash** (Redis — сесії/черги), **Sentry** (error tracking, `send_default_pii = false`), GHCR (образи, не персональні дані). |
| **(e) Треті країни** | Залежить від резидентства користувача. UA (контролер) без adequacy decision від ЄК → SCC-2021 як backup-механізм для US-вендорів (Sentry), поряд із DPF де застосовно ([`b2c_tos_privacy §B.10`](b2c_tos_privacy.md)). Akash — регіон провайдера непередбачуваний (permissionless-маркетплейс, `00_07` SEC.23). |
| **(f) Зберігання** | ⚖️ `[TBD — 00_07 SEC.18(а), retention-policy не формалізована]`. Механізм там, де він є: `sessions` **не** append-only — найдешевша половина erasure (рядок стирається); `generates_token_for`-токени мають власний access-TTL (password_reset 15 хв, email_verification 24 год, api_access 30 днів) — це TTL токена, не data-retention. |
| **(g) TOM** | Специфічно тут (baseline — §3): Argon2id пароль-хеш; AR-encryption `otp_secret`; httponly+secure(prod)+`SameSite=Lax` сесійний cookie (14 днів); **salt-bound session invalidation** — `session[:ps]` (хвіст `password_salt`) знецінює всі активні сесії при зміні пароля; TOTP MFA (S6.21). |

### 2.2 Організації та NaaS B2B-контракти

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Адміністрування облікового запису організації; життєвий цикл NaaS-контракту (`draft→active→fulfilled/breached/cancelled`); білінгова комунікація; KYC бенефіціара для custodial-мінту. *(Art.6(1)(b) договір + Art.6(1)(c) юридичний обовʼязок — KYC де застосовно)* |
| **(c) Субʼєкти + дані** | Контактні особи/персонал організації — здебільшого overlap із субʼєктами §2.1 (той самий `User` належить організації). → [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) рядок `organizations`: `billing_email` (**умовний PII** — ФОП/одноосібний власник = так, ТОВ = ні; трактується як PII за замовчуванням), `crypto_public_address` (псевдонімна), `hadron_kyc_status`. `naas_contracts` несе фінансові/контрактні поля організації, не індивідуальний PII — окрім потенційно `cancellation_terms` (jsonb, стеля — §4). |
| **(d) Отримувачі** | **Polygon Hadron** (KYC/compliance-процесор, `app/services/polygon/hadron_compliance_service.rb`) — з нашого коду йде лише `crypto_public_address` + `chain: "polygon"`, не імʼя/документи напряму; чи Hadron окремо збирає KYC-документи від бенефіціара **поза нашим кодом** — не підтверджено цим реєстром, `[TBD verify]`. Той самий DB-хостинг, що §2.1. |
| **(e) Треті країни** | Hadron (Polygon Labs) — юрисдикція/регіон обробки не верифіковано цим реєстром, `[TBD]`. |
| **(f) Зберігання** | ⚖️ `[TBD — 00_07 SEC.18(а)]`. NaaS-контракт як фінансовий документ імовірно підпадає під обліковий/податковий retention (аналогічно [`b2c_tos_privacy §B.8`](b2c_tos_privacy.md) — «розумний період для юридичних/облікових цілей»); точний строк не визначено. |
| **(g) TOM** | `EthAddressValidatable` (формат-валідація адрес); `Auditable`-концерн на зміну `stream_epoch` (ARCH.57); `restrict_with_error` на каскадне видалення (захист фінансової цілісності й аудит-слідів). |

### 2.3 Моніторинг лісу — телеметрія дерев і кластерів

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Екологічний/росто-вий моніторинг (D-MRV); Proof-of-Growth для нарахування growth points/SCC-токена ([`00_04 §3`](../../00_04_Nature_as_a_Service_Contracts.md)); тривоги раннього попередження (EWS). *(Art.6(1)(b) — надання самої послуги моніторингу)* |
| **(c) Субʼєкти + дані** | **Дерево не є субʼєктом даних** — фізіологічна телеметрія (напруга EBFC, Z-показник Атрактора Лоренца, температура/вологість/тиск/VPD/акустичні події) сама по собі персональних даних не несе ([`03_04 §6.3`](../../03_04_mruby_Lorenz_Attractor.md) — canon-підстава «у дерев немає GDPR-даних»). **Крайовий випадок — межа, не вирішення:** гранулярна геолокація вузла (`Tree.latitude/longitude`) + межі кластера (`Cluster.geo_boundary`, PostGIS) у поєднанні з кадастровими/земельно-реєстровими записами теоретично може пере-ідентифікувати малого/сімейного власника ділянки (той самий принцип, що smart-meter-дані). ⚖️ **DPIA Art.35 написано 2026-08-21** ([`dpia_art35.md`](dpia_art35.md)) — 3 з 9 EDPB WP248-критеріїв зійшлись (location + systematic monitoring + innovative tech); ⚠️ обовʼязок ще НЕ закритий: оцінка залишкового ризику й висновок про Art.36 — 👤, `00_07` SEC.18. |
| **(d) Отримувачі** | B2B-покупці верифікованих D-MRV-даних — SilkenNet лишається контролером ВЛАСНОГО verified-fact продукту, не процесором покупця, окремий Art.28 DPA тут юридично не потрібен ([`b2c_tos_privacy §D.1`](b2c_tos_privacy.md) п.2). Внутрішньо — той самий DB-хостинг, що §2.1. |
| **(e) Треті країни** | Сирі координати анкера без огрублення/агрегації в жодному B2B-продукті не публікуються без окремої юридичної підстави ([`b2c_tos_privacy §B.7`](b2c_tos_privacy.md)) — design-намір; технічний мітигаційний механізм ще не впроваджено (той самий чекбокс). |
| **(f) Зберігання** | 🔴 **Механізм, не строк — і механізм тут негативний.** `telemetry_logs` (RANGE-партиції по місяцях) не мають retention/pruning: `PartitionMaintenanceWorker` лише СТВОРЮЄ нові партиції, `DETACH`/`DROP PARTITION` у репо нуль — партицій стає +1 щомісяця **назавжди** ([`04_01 §11`](../../04_01_Data_Models_and_Entities.md), архітектурна таблиця, принцип «Партиціонування по місяцях»). Не GDPR-специфічний факт сам по собі, але прямо визначає (f): технічної підлоги, яка сама стирала б телеметрію за строком, сьогодні немає. |
| **(g) TOM** | `GeoLocatable` WGS-84 range-валідація; hot-path **без** AR-валідацій за дизайном (KENOSIS) — перевірка лише в `TelemetryUnpackerService.valid_sensor_data?`, свідомий вибір (`CLAUDE.md §6`); `organizations.data_region` — GDPR-residency вісь у схемі, **валідована, але фізичне шардування БД за регіоном ще не автоматизоване** (декларація, не діючий механізм — [`b2c_tos_privacy`](b2c_tos_privacy.md) прямий код-греп). |

### 2.4 Записи обслуговування з фотодоказами (Proof of Care)

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Фіксація фізичної дії лісника/техніка в полі (монтаж/огляд/очищення/ремонт/демонтаж/вилучення біомаси); Evidence Protocol для критичних дій (`repair`/`installation` вимагають фото). *(Art.6(1)(b) — виконання договору моніторингу)* |
| **(c) Субʼєкти + дані** | Користувач, що виконав дію (`belongs_to :user`); потенційно треті особи/майно, випадково в кадрі. `MaintenanceRecord.latitude/longitude` (GPS патрульного В МОМЕНТ дії — окремі координати від Tree-геолокації §2.3), `notes` (вільний текст — стеля §4: зміст не класифіковано), `performed_at`. **Фотододатки** (`has_many_attached :photos`, ≤20МБ, JPEG/PNG/WebP/HEIC/HEIF, до 10 шт.). 🔴 **Знахідка цього реєстру, звужена присудом ⚖️ 2026-08-20 (SEC.18):** EXIF стрипається лише з ПОКАЗОВОГО variant'а (`:thumb`, `saver: { strip: true }`), а **оригінал зберігається з метаданими СВІДОМО** — гео-тег є потенційним незалежним доказом «технік був на місці». Тобто керованого шару геолокації в оригіналі й далі немає, і це trade-off, а не пропуск — HEIC/HEIF і сучасний смартфонний JPEG за замовчуванням вбудовують GPS-координати й timestamp зйомки у файлові метадані. Тобто окрім заявлених `latitude`/`longitude`-полів сам файл може нести **другий, неконтрольований шар геолокації**. Не канонізовано в жодному прочитаному відкритому пункті — фіксується тут, не вирішується. |
| **(d) Отримувачі** | Active Storage — **AWS S3** (`config/storage.yml`, primary, регіон за замовчуванням `eu-central-1`, server-side encryption AES256) + **Google Cloud Storage** (DR-дзеркало, `production_mirror` пише в обидва одночасно, регіон не зафіксований у файлі). 🔴 **Жоден із цих двох процесорів не входить у реєстр субпроцесорів [`b2c_tos_privacy §D.3`](b2c_tos_privacy.md)** (там лише GCP Cloud SQL/Akash/Alchemy/Upstash/Grafana/Sentry/GHCR) — див. §6. |
| **(e) Треті країни** | S3 `eu-central-1` = ЄС (default, ENV-перевизначувано); GCS-бакет регіон не заданий цим файлом — `[TBD verify]` (імовірно узгоджений із GCP-проєктом `europe-west1`, [`06_01`](../../06_01_Deployment_Kamal_Terraform.md), не підтверджено). |
| **(f) Зберігання** | 🔴 **Механізм, не строк — і механізм тут «незнищенно» (присуд SEC.28, 2026-08-19).** Фото не видаляються нікому (`purge_later` заблоковано доктриною `MaintenanceRecord#evidence_backed?`, дзеркало `Wallet#guard_mrv_evidence!`); виправлення — лише додаванням нового кадру. Ретеншен-строк свідомо не введено: «скільки зберігати доказ» дому в репо не має взагалі ([`04_01`](../../04_01_Data_Models_and_Entities.md) MaintenanceRecord) → ⚖️ `[TBD — 00_07 SEC.18]`. |
| **(g) TOM** | `photos_required_for_critical_actions` (валідація на кожен `save`, не лише `create`); ідентичність-слід при спробі знищення (`filename`/`byte_size`/`checksum`/`content_type` у синхронний `AuditLog.create!`, SEC.28); S3 server-side encryption AES256 at rest; `system_generated`-провенанс-колонка не приймається з клієнтського payload. |

### 2.5 Аудит-слід (`AuditLog`)

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Незмінний tamper-evident журнал привілейованих дій — money-переходи, slash-вердикти, role-зміни, ключова ротація, статуси контрактів/команд. *(Art.6(1)(c) — юридичний обовʼязок фінансового/compliance-аудиту)* |
| **(c) Субʼєкти + дані** | Користувач-ініціатор дії (людський актор) АБО системний бот (`oracle_executioner`, не субʼєкт даних). → [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) рядок `audit_logs`, 🔴 **PII в APPEND-ONLY**: `ip_address`, `user_agent`, `user_id`, `action`, `metadata` (jsonb — стеля §4, зміст не класифіковано). |
| **(d) Отримувачі** | Внутрішньо (сам застосунок, console-читання глобального ланцюга). Для **money/MRV-записів** (`archive: true`, MRV.1) — додатково **Pinata** (`api.pinata.cloud`, IPFS/Filecoin pinning-шлюз, `Filecoin::ArchiveService`) — 🔴 **публічна децентралізована мережа, не контрактний процесор**, і теж відсутня в [`b2c_tos_privacy §D.3`](b2c_tos_privacy.md), див. §6. Пінується `content_attrs` (id/org_id/action/`chain_hash`/auditable-посилання/`created_at`) + **`metadata` (jsonb) цілком** + добове зведення телеметрії кластера. `ip_address`/`user_agent` напряму НЕ пінюються (лишаються лише всередині `chain_hash` — SHA-256-дайджест, необоротний), а зміст `metadata` з 2026-08-25 має **оголошену стелю** (`AuditLog::ARCHIVED_METADATA_KEYS` + відмова `Filecoin::ArchiveService` на межі піна, DPIA захід M6): у пін їдуть лише декларовані ключі money-тракту, тож `[TBD verify]` звузився з «чи будь-коли несе PII» до вмісту одного вільнотекстового `error` (текст чужого RPC/винятку) — судяться КЛЮЧІ, ніколи ЗНАЧЕННЯ. Привілейовані записи з `archive: false` (ключі/ролі/актуатори) свідомо не пінюються публічно (ARCH.57 — «security-метадані не на публічний IPFS»). |
| **(e) Треті країни** | IPFS/Filecoin (Pinata) — глобальна публічна мережа без юрисдикційного контролю за визначенням; відкрита вісь, не покрита SCC-2021/DPA-механізмом (не застосовний до permissionless-мережі). |
| **(f) Зберігання** | 🔴 **Механізм: назавжди за дизайном, erasure — лише псевдонімізацією.** `before_update` дозволяє мутацію лише архівних полів (`ARCHIVAL_MUTABLE_COLUMNS`); `before_destroy` завжди `raise` (ARCH.57). Erasure ядра людини можлива лише через псевдонімізацію поля зі збереженням хеш-ланцюга (`AnonymizeUserService`) — сам сервіс досі відкритий пункт (ARCH.57(4), над яким стоїть SEC.18). |
| **(g) TOM** | Tamper-evident SHA-256 hash-ланцюг (`chain_hash` = попередній + canonical payload, timestamp/actor у ланцюзі); `before_update`/`before_destroy` DB-рівневі бекстопи; `verify_chain_integrity`. |

### 2.6 Сповіщення (email · SMS · push · Telegram)

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Доставка сервісних сповіщень про дерево/кластер користувача (не маркетинг) — тривоги (пожежа/вандалізм/EWS), відновлення пароля, облікові повідомлення. *(Art.6(1)(b) — доставка сервісних сповіщень про ВАШЕ дерево, [`b2c_tos_privacy §B.3`](b2c_tos_privacy.md))* |
| **(c) Субʼєкти + дані** | Користувачі організації (переважно ролі admin/forester). → [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) рядок `users`: `telegram_chat_id`, `push_token`, `email_address`, `locale`. (`phone_number` знято 2026-08-20 разом зі SMS-каналом — ⚖️ ARCH.78: PII без цілі processing, Art. 5(1)(c) data-minimization.) |
| **(d) Отримувачі** | **Email** — вихідний SMTP-релей (ENV-керований: `SMTP_ADDRESS`/`PORT`/`USER_NAME`/`PASSWORD`; ARCH.60 machine-half shipped 2026-08-04, `mail_transport_check.rb` boot-guard). Конкретний ESP-вендор (Postmark/SES/Mailgun/SendGrid/Resend — будь-який, дизайн навмисно vendor-agnostic) **ще не обрано** → `[TBD]`. **SMS** — ⚖️ **відкинуто присудом 2026-08-20 (ARCH.78):** канал знято з дерева разом із `users.phone_number` (Twilio-адаптер не буде збудований; отримувача-субпроцесора не існує). **Push** — 🔴 **не задеплоєно:** `FcmClient` не існує в коді (нуль gem-залежностей); `SingleNotificationWorker` пише лише `warn "Канал не сконфігуровано"` (ARCH.60/ARCH.78 — брехливий-лог машинну половину закрито 2026-08-04, транспорт — ⚖️-gated E.20). **Telegram** — ✅ **задротовано 2026-08-20** (ця сама знахідка RoPA-свіпу → ARCH.60): `Notifications::TelegramTransport` шле `chat_id` + текст алерта (локаллю отримувача) у **Telegram Bot API** — тобто Telegram Messenger Inc. став ОТРИМУВАЧЕМ цих даних; рядок субпроцесора → [`b2c_tos_privacy §D.3`](b2c_tos_privacy.md), DPA-статус 🔴 не верифіковано (D.4-список). Канал opt-in (порожній `chat_id` = не шлеться), config-гейт `TELEGRAM_BOT_TOKEN` (без токена канал чесно вимкнено). |
| **(e) Треті країни** | Залежить від майбутнього ESP-вибору → `[TBD]`. |
| **(f) Зберігання** | N/A для самого акту доставки (не персистується окремо від полів `User`, покритих §2.1); базові поля → ⚖️ `[TBD SEC.18(а)]`. |
| **(g) TOM** | `filter_parameters` скраб `telegram_chat_id`/`push_token` з логів (рядок `phone_number` у скрабі лишено defense-in-depth — параметр міг би прийти ззовні й потрапити в лог unpermitted-повідомленням) (той самий allow-list, що §2.1, розширений Sentry); `spec/quality/no_self_attesting_logs_spec.rb` — гейт проти логу, що стверджує недоставлену дію (ARCH.78; точність журналу — Art.5(1)(d) accuracy, не PII-безпека per se). |

### 2.7 Web3-гаманці та KYC/AML (Hadron custodial)

| Art.30(1) | Зміст |
|---|---|
| **(b) Цілі** | Облік гаманця для нарахування growth points/SCC/USDC/cUSD ([`00_04 §3`](../../00_04_Nature_as_a_Service_Contracts.md)); KYC/AML-верифікація бенефіціара перед мінтом. *(Art.6(1)(b) виплата нагород + Art.6(1)(c) юридичний обовʼязок — KYC де застосовно, [`b2c_tos_privacy §B.3`](b2c_tos_privacy.md))* |
| **(c) Субʼєкти + дані** | Власник гаманця (індивідуальний landowner з власною адресою) АБО бенефіціар організації (custodial-успадкування статусу). → [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) рядок `wallets`/`organizations`, **псевдонімні**: `crypto_public_address` (Polygon/Ethereum, EIP-55), `solana_public_address` (Base58), `hadron_kyc_status`. ⚠️ Стане PII-ядром (не лише псевдонімним) у мить, коли зʼявиться пряма виплата рейнджеру/людині — адреса отримувача-людини вже персональна; сьогодні `wallets.tree_id` `NOT NULL` — гаманець завжди належить дереву, не людині. |
| **(d) Отримувачі** | **Polygon Hadron** (той самий KYC-процесор, що §2.2, тепер з боку індивідуального гаманця: `verify_investor!` шле `crypto_public_address` + `chain: "polygon"`). **Alchemy** (RPC-провайдер Polygon/Ethereum, `ALCHEMY_POLYGON_RPC_URL`/`ALCHEMY_ETHEREUM_RPC_URL`) — фіксує **IP-адресу запиту разом із гаманець-адресою при кожному RPC-виклику** (задокументована галузева практика; IP = персональні дані за CJEU *Breyer*, [`b2c_tos_privacy §B.6`](b2c_tos_privacy.md); вже занесено в `00_07` SEC.23). |
| **(e) Треті країни** | Hadron (Polygon Labs) + Alchemy — обидва ймовірно US-based, регіон обробки не верифіковано цим реєстром. SCC-2021 backup-механізм за замовчуванням ([`b2c_tos_privacy §B.10`](b2c_tos_privacy.md)); DPA-статус обох — verify напряму ([`b2c_tos_privacy §D.3`](b2c_tos_privacy.md)/§D.4). |
| **(f) Зберігання** | 🔴 **Механізм: незворотно за дизайном блокчейну.** On-chain SCC/USDC/cUSD-транзакції публічні й незворотні (Polygon/Solana/Celo) — видалення облікового запису не стирає вже здійснені мінтинги ([`b2c_tos_privacy §A.9`](b2c_tos_privacy.md)). Off-chain `wallets`-запис (баланс/статус) живе, доки існує дерево/акаунт — точний строк ⚖️ `[TBD SEC.18]`; `guard_mrv_evidence!` додатково блокує DESTROY гаманця з settled/in-flight tx (грошові докази незнищенні). |
| **(g) TOM** | `EthAddressValidatable`; `kyc_approved_for_minting?` gate (per-tx SKIP на будь-якому non-KYC гаманці, [KYC.1]); `WEB3_STRICT_MODE`/`Rails.env.production?` belt-and-suspenders fail-closed на відсутні Hadron-креденшели (симуляція вимкнена в prod — забутий прапор ≠ fake-KYC mint); `guard_mrv_evidence!` destroy-guard. |

---

## 3. Загальні технічні й організаційні заходи (baseline на всі активності)

Специфічні (g)-рядки вище **доповнюють** цей baseline, не повторюють його:

- **Argon2id** — memory-hard пароль-хешування (Password Hashing Competition winner), стійкий до GPU/ASIC-атак.
- **AR-encryption at-rest** — `hardware_keys`, `users.otp_secret`; ключі з ENV (`ACTIVE_RECORD_ENCRYPTION_*`), **не** `credentials.yml.enc` (SEC.22 — інакше вертає runtime-залежність від `RAILS_MASTER_KEY`).
- **`filter_parameters`** — PII-скраб логів: `email`/`telegram_chat_id`/`push_token`/`first_name`/`last_name`/`recovery_codes` (+ `phone_number` як defense-in-depth після зняття колонки) (+ секрети/ключі), той самий список успадковує Sentry.
- **Sentry** — `send_default_pii = false` + defense-in-depth редакція секретів/PII у breadcrumbs і stack-trace (`config/initializers/sentry.rb`).
- **Zero-Network-Exposure ключів** — апаратні AES-ключі не покидають Ruby-процес (`HardwareKey#cached_binary_key`, in-process LRU, без Redis-serialize).
- **Salt-bound сесії** — `session[:ps]` (хвіст `password_salt`) знецінює всі активні сесії при зміні пароля.
- **Сесійний cookie** — httponly + secure(prod) + `SameSite=Lax`, 14-денний TTL.
- **`organizations.data_region`** — GDPR-residency вісь у схемі (`eu-west`/`eu-central`/`us-east`/`us-west`/`ap-southeast`), **валідована, фізичне шардування БД за регіоном ще не автоматизоване** — сьогодні декларація, не діючий механізм.

---

## 4. Стелі цього реєстру

Той самий caveat, що [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) саме собою заявляє — RoPA успадковує його один-в-один, не приховує:

- **Класифікація — декларація людини, не regex-вивід.** Кожен рядок вище несе підставу; повнота реєстру залежить від людського рев'ю, а не механічного свіпу.
- **JSONB-поля непрозорі за побудовою.** `ai_insights.reasoning`/`summary` та інші jsonb/text-стовпці можуть містити довільний вміст, який жодна автоматика не класифікує — якщо туди колись потрапить PII, цей реєстр цього не побачить, доки хтось не прочитає вміст руками. ⊕ **Виняток — `audit_logs.metadata`, і саме тому, що він єдиний їде в НЕЗВОРОТНИЙ публічний пін:** його ключі оголошено переліком (DPIA захід M6, 2026-08-25), тож нове поле туди не потрапляє мовчки. Непрозорість лишається на рівні ЗНАЧЕНЬ, не полів.
- **Вільні тексти приладу не видно.** `maintenance_records.notes`, повідомлення тривог (`EwsAlert`/`AiInsight`) — та сама стеля.
- **EXIF-метадані ОРИГІНАЛУ фотододатка зберігаються свідомо** (§2.4) — присуд ⚖️ 2026-08-20: показовий variant іде без метаданих, оригінал лишається доказом присутності. Носій — `spec/models/maintenance_record_photos_exif_spec.rb`.
- **Цей документ не має власного mutation-гейту.** Носій колонкового рівня — `spec/quality/pii_register_spec.rb` (на [`04_01 §11`](../../04_01_Data_Models_and_Entities.md)); зміна там **не** пропагується сюди автоматично — ручна синхронізація при наступному review.

---

## 5. Мапа секція ↔ `00_07`-трек

Той самий прийом, що [`b2c_tos_privacy §D.0`](b2c_tos_privacy.md): репо-роадмап-код винесено «поза тіло» реєстру, щоб не засмічувати документ, який колись піде юристу.

| Секція цього документа | `00_07`-трек |
|---|---|
| §1 Контролер (реквізити + controller-role) | `BIZ.20` (тришар) → [`entity_structure`](entity_structure.md) |
| §1 EU-представник (Art.27) | `SEC.18` (чекбокс) |
| §2.1 Облік/автентифікація — MFA | `S6.21` |
| §2.2 Організації/NaaS — custodial KYC | `KYC.1`, `BIZ.20` |
| §2.3 Моніторинг лісу — anchor-geo DPIA | ✅ **виконано як документ 2026-08-21** → [`dpia_art35.md`](dpia_art35.md) (цей реєстр став його джерелом операцій обробки); `SEC.18` тримає 👤-залишок — оцінка залишкового ризику + Art.36 |
| §2.4 Maintenance-фото — незнищенність | `SEC.28` (закрито 2026-08-19) |
| §2.4 Maintenance-фото — EXIF | `SEC.18` (⚖️ 2026-08-20: стрип із показу, оригінал зберігається як доказ присутності) |
| §2.5 Аудит-слід — append-only ↔ erasure | `SEC.18` (`ARCH.57` вичерпано й заархівовано 08-21) |
| §2.5 Аудит-слід — Pinata поза реєстром (🔴 знахідка) | без ID — див. §6 нижче |
| §2.6 Сповіщення — стан каналів (email ✅ · Telegram ✅ · push ⚖️ · SMS відкинуто) | `ARCH.60` (поглинув `ARCH.78` 08-21) |
| §2.7 Web3/KYC — Alchemy IP+wallet | `SEC.23` |
| Усі §2.x — retention-строки | `SEC.18` (а) |
| Усі §2.x — DSAR self-serve tooling | ✅ **відвантажено** (експорт Art.15/20 + erasure Art.17 зі step-up, ⚖️ 2026-08-21); у `SEC.18` лишається ФОРМА стирання там, де запис незнищенний (аудит-ланцюг ⊥ оригінали фото) |
| Усі §2.x — outbound breach-notification 72h | `SEC.18` (чекбокс gap-pass §00b) |

Повний трекер — [`00_07`](../../00_07_Action_Plan_Tracker.md).

---

## 6. Знахідки — субпроцесори поза [`b2c_tos_privacy §D.3`](b2c_tos_privacy.md)

Реєстр субпроцесорів у `b2c_tos_privacy` §D.3 називає себе «повним переліком інфраструктурних вендорів» (§B.11). Пряма звірка з кодом під час побудови цього RoPA виявила **три реальні процесори, відсутні там**:

1. **Polygon Hadron** (`app/services/polygon/hadron_compliance_service.rb`) — отримує гаманець-адресу (`crypto_public_address`) для KYC/compliance-перевірки бенефіціара (§2.2, §2.7). Реальний, живий HTTP-виклик у production/`WEB3_STRICT_MODE` (не заглушка).
2. **Pinata / IPFS-Filecoin** (`app/services/filecoin/archive_service.rb`, `api.pinata.cloud`) — публічно пінує `AuditLog.metadata` для money/MRV-записів (§2.5) — з 2026-08-25 лише **декларовані** ключі (DPIA захід M6; зміст значень і далі не класифікується). Це не «процесор» у звичному сенсі — публічна permissionless-мережа без юрисдикційного контролю, що ще гостріше, ніж типовий DPA-gap.
3. **AWS S3 + Google Cloud Storage** (`config/storage.yml`, ActiveStorage primary + DR-дзеркало) — приймають фотододатки `MaintenanceRecord` (§2.4), включно з їхніми EXIF-метаданими.

Це не виправлено в цьому документі (поза мандатом задачі — редагувати `b2c_tos_privacy.md` тут не входило) — фіксується як вхід у наступний review того файлу.

---

## Джерела / Cross-references

- [`04_01 §11`](../../04_01_Data_Models_and_Entities.md) — PII-реєстр, One-Home колонкового рівня для всіх (c)-клітинок вище.
- [`b2c_tos_privacy`](b2c_tos_privacy.md) §B.3 (категорії даних × правова підстава), §B.6–§B.13 (ролі/transfers/DPO/Art.27), §D.1–§D.4 (controller/processor-мапа, субпроцесор-реєстр), §A.1/§A.9/§A.14 (контролер, on-chain незворотність, контакти).
- [`b2b_readiness`](../business/b2b_readiness.md) §2.1 (RoPA gap-analysis, звідки цей документ виводиться), §2.2 (DPIA anchor-geo мапінг), §2.6 (GDPR-стандарт ↔ трекер-мапа).
- [`03_04 §6.3`](../../03_04_mruby_Lorenz_Attractor.md) — canon-підстава «дерево не є субʼєктом даних».
- [`entity_structure`](entity_structure.md) — тришар-матриця operational-vehicle/IP-owner/token-контур (BIZ.20).
- [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) — IP-розподіл, canon-джерело тришар-присуду.
- [`00_04 §3`](../../00_04_Nature_as_a_Service_Contracts.md) — фінансові константи (growth points/SCC), не переказані тут.
- [`00_02 §4.2`](../../00_02_Academic_Integration_and_IP.md) — UA-юр-review контакти.
- `/NOTICE` — ліцензійні зони (для повноти пакета, не PII-релевантно).
- [`00_07`](../../00_07_Action_Plan_Tracker.md) — `SEC.18`, `SEC.23`, `SEC.28`, `ARCH.57`, `ARCH.60`, `ARCH.78`, `S6.21`, `KYC.1`, `BIZ.20`, `UNI.16` (повна мапа секція↔трек — §5).
- Прямі code-звірки (сесія 2026-08-20): `config/initializers/{sentry,session_store,filter_parameter_logging}.rb`, `config/storage.yml`, `config/environments/production.rb`, `config/deploy.yml`, `app/models/{identity,organization,user,wallet}.rb`, `app/services/polygon/hadron_compliance_service.rb`, `app/services/filecoin/archive_service.rb`, `app/workers/{audit_log_worker,filecoin_archive_worker,single_notification_worker}.rb`, `app/services/notifications/delivery_channels.rb`.
