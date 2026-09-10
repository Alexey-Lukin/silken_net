# SE05x API Migration — Candidate Table (draft, no-premature-canon)

> **Статус: ЧЕРНЕТКА / ГІПОТЕЗА, не SSOT.** Проходить `00_06 §0` Validation Gate лише
> після silicon-confirm на eval-kit ([`00_07` — SE050-MIGRATION](../../00_07_Action_Plan_Tracker.md)).
> Жодна назва функції/сигнатура тут НЕ звірена проти реального SE05x datasheet API
> reference чи джерела Plug&Trust middleware — обидва відсутні в цьому репо (перевірено:
> нуль вендорованого SE05x SDK). Джерело — загальна конвенція публічного NXP
> Plug&Trust API, з памʼяті, без доступу до датащита чи коду мідлвари. **Кожен рядок —
> гіпотеза, що вимагає підтвердження на eval-kit.**

## Що тут НЕ повторюється (One-Home, `00_06 §2`)

Role-split (provisioning-only, SEC.14) · latency/power (paper-verified таблиця) ·
footprint · object-model (динамічна ФС 50 kB, policy per-object) — усе це вже має дім,
паперово звірене проти SE050 DS Rev 3.3 і SE051 DS Rev 1.4, і жити має **лише там**:
[`03_05 §3.7`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md). Цей файл покриває
рівно ту частину, якої там немає: **candidate-mapping для восьми конкретних
`atcab_*`-рядків, які СЬОГОДНІ емітить `SecureElementProvisioner`**
(`app/services/factory_flashing/secure_element_provisioner.rb`), плюс одна знахідка про
форму міграції, яку по-рядковий mapping ховає.

## Candidate-table: emitted statement → SE05x/Plug&Trust candidate

Ліва колонка — дослівні рядки з `secure_element_provisioner.rb#emit_statements`
(легасі ATECC, як їх сьогодні пише аудит-транскрипт). Права — гіпотеза НАЙБЛИЖЧОГО
API з двох шарів NXP middleware: низькорівневий APDU-wrapper `Se05x_API_*` і
вищий крипто-абстракційний шар `sss_*` (Plug&Trust nano-package, canon §3.7 рядок
«Host-стек»). Де шари дають різну відповідь — обидва названо.

| # | Емітований рядок (сьогодні) | Candidate SE05x/sss (ГІПОТЕЗА) | Впевненість | Нотатка |
|---|---|---|---|---|
| 1 | `atcab_init(&cfg_ateccx08a_i2c)` | `Se05x_API_SessionOpen()` / `sss_session_open()` | середня | I²C-конфіг STM32WLE5 — наш власний shim (канон §3.7: «портів під STM32WLE5 нема»), тож ця ланка НЕ з датащита — з нашого майбутнього коду |
| 2 | `atcab_read_serial_number(&serial[0])` | `Se05x_API_ReadObject()` на UID-об'єкті, АБО спеціалізований `Se05x_API_GetVersion`/UID-read виклик | низька | ATECC має виділений 9-байтний serial-регістр; чи SE05x має прямий еквівалент, а не generic read по object-ID, невідомо без Table з датащита |
| 3 | `atcab_write_zone(..., 0, ...)` # Slot 0 AES LoRa | — (N/A, і це не прогалина мапи, а канон-факт) | висока | Post-SEC.14 Slot 0 НЕ пишеться в ЖОДНІЙ гілці (§3.7 Статус) — на SE05x-стороні цей рядок просто **зникає**, не мігрує |
| 4 | `atcab_write_zone(..., 1, ecc_priv, 32)` # Ed25519 priv | `Se05x_API_WriteECKey()` з `kSE05x_ECCurve_ED25519` **БЕЗ приватного матеріалу на вході** (on-chip keygen), АБО `sss_key_store_generate_key()` | середньо-висока | Це НЕ рядок-у-рядок mapping — це зміна ФОРМИ виклику: сьогодні хост генерує ключ і пише його; на SE05x хост просить чип згенерувати й НІКОЛИ не бачить приватний біт (§3.7 «backend не знає private → непідробно»). Найважливіший рядок таблиці саме тому, що механіка, не лише імʼя, змінюється |
| 5 | `atcab_write_zone(..., 2, cert_der, ...)` # X.509 cert | `Se05x_API_WriteBinary()` / `sss_key_store_set_cert()` | середня | SE05x зберігає сертифікати як generic Binary-обʼєкти (object-model, не zone) |
| 6 | `atcab_write_zone(..., 3, ota_hmac, 32)` # K_ota HMAC | `Se05x_API_WriteSymmKey()` / `sss_key_store_set_key()` (symmetric object) | середньо-висока | HMAC-ключ — той самий клас обʼєкта, що AES-ключ у SE05x-моделі (symmetric key object), на відміну від ATECC, де вони жили в РІЗНИХ типізованих слотах |
| 7 | `atcab_lock_config_zone()` | **N/A — немає 1:1 еквівалента** | висока (щодо відсутності мапи) | Див. знахідку нижче |
| 8 | `atcab_lock_data_zone()` | **N/A — немає 1:1 еквівалента** | висока (щодо відсутності мапи) | Див. знахідку нижче |

## Знахідка: «lock» не мігрує рядок-у-рядок — модель незворотності інша

Рядки 7–8 не мають кандидата, і це не прогалина мого пошуку — це наслідок уже
записаного в каноні факту («**policy per-object**», §3.7 datasheet-verify таблиця),
доведений до кінця. ATECC608B має ДВІ глобальні необоротні операції в кінці
провіжн-послідовності: `atcab_lock_config_zone()` замикає ПОЛІТИКУ всіх 16 слотів
одразу, `atcab_lock_data_zone()` замикає ЗАПИС у всі слоти одразу — і саме ця пара
є підставою `03_06 §1`-рядка «⚠️ Після цього кроку ключі НЕ можуть бути ні
прочитані, ні переписані».

SE05x-об'єктна модель не має такого глобального перемикача. У Plug&Trust кожен
обʼєкт (ключ, сертифікат, лічильник) отримує **власну** access-policy бітову
маску **в момент створення** (write/generate-виклик), а не постфактум. Отже
міграція цих двох рядків — не переклад назви, а **зміна ФОРМИ**: замість двох
викликів наприкінці послідовності буде по одному policy-аргументу всередині
КОЖНОГО з викликів №4–6 вище (і, ймовірно, №2 — якщо UID-об'єкт теж підлягає
policy). Кількість точок, де незворотність фіксується, зростає з 2 до N;
аудит-транскрипт (`AuditLog`), що сьогодні читає рівно два «lock»-рядки як доказ
завершення провіжну, доведеться перечитати на N policy-аргументів, розкиданих по
записах, а не на два фінальні маркери. **Це найдорожча відкрита нитка цього
документа** — вона стосується не лише API, а й форми доказу «провіжн
завершено», яку зараз несе `03_06 §1` крок 5.

## Що лишається відкритим для eval-kit / реального SDK

- Точна назва й сигнатура кожного `Se05x_API_*`/`sss_*` виклику вище — з реального
  API reference (SE05x Plug&Trust middleware, після 👤-замовлення eval-kit).
- Чи UID-читання (рядок 2) взагалі є окремим викликом, чи частиною `SessionOpen`.
- Точна форма access-policy бітової маски для рядків 4–6 (яка каже «Read: never,
  Write: on-chip-only» — аналог сьогоднішнього `❌ never` у канон-таблиці §3.7).
- Чи `AuditLog`-транскрипт (`SecureElementProvisioner#provision`) потребує зміни
  формату запису під розподілену (N-точкову) незворотність, чи досить зібрати їх
  постфактум в один блок для читабельності аудиту.

**Related:** [`00_07` — SE050-MIGRATION](../../00_07_Action_Plan_Tracker.md) (residual
«`03_05` deep mechanics → SE05x при eval-kit») · [`03_05 §3.7`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md)
(role-split/latency/power/object-model — дім) · [`03_06 §1`](../../03_06_Factory_Flashing_and_Key_Provisioning.md)
(провіжн-послідовність, one-home) · `app/services/factory_flashing/secure_element_provisioner.rb`
(джерело лівої колонки).
