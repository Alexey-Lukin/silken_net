# Bench Runbook — вичерпний «клас C» (те, що може відповісти лише кремній)

> **Призначення.** Усе, що в SSOT позначено *bench-gated*, зведено тут у
> скриптований день: підключив плату → пройшов розділи по порядку → закомітив
> артефакти. Софт-половини цих пунктів уже закриті host/QEMU-шарами
> (класифікація A/B/C — [`00_03 §3`](../../../docs/00_03_TRL_Matrix_HIL_and_Beyond.md));
> тут лишилась фізика. Скрипти поруч (`firmware/scripts/bench/`) — кожен має
> `--plan` (надрукувати кроки, нічого не чіпати) і чесно відмовляється без
> інструмента.
>
> **Pre-flight (твердо):** антена ПЕРЕД живленням на SX1262 (згорить без
> антени — CLAUDE.md §10); ESD-браслет; лог усього дня → `bench_artifacts/`.

## 0. Інструменти

| Інструмент | Для чого | Нотатка |
|---|---|---|
| ST-LINK/V3 + `STM32_Programmer_CLI` | flash, option bytes, RDP | SEC.3 pipeline вже скриптований (`EXECUTE=1`) |
| `pyocd` (`pip install pyocd` + `pyocd pack --install stm32wl`) | SWD-оркестрація, регістри, RTT | CMSIS-pack дає flash-алгоритм WLE5 |
| Nordic PPK2 (~$120, `pip install ppk2-api`) | µA-профілі, Vcap recharge-крива | **Floor-чесність:** роздільність ~100 нА — для атестації 300 нА STOP2 межово; підтверджувати JS220/SMU-класом |
| Joulescope JS220 / SMU (Keithley) | nA-класова стеля (FW.54 300 нА) | разова верифікація, можна позичити |
| USB-UART (3.3В) + `minicom`/`pyserial` | SIM7070G транскрипти, parity-дамп | лог = артефакт |
| Термокамера (ЧНУ?) | LSE drift ±60°C (FW.20 TRL-7) | опційний день-2 |

## 1. Прошивка + option bytes (SEC.3 / SEC.2 / SEC.15)

| Крок | Скрипт | Очікуване | Артефакт |
|---|---|---|---|
| 1.1 Перший flash `.elf` | `00_flash.sh --elf <path> --execute` | verify OK | лог CLI |
| 1.2 Option bytes: **IWDG_STOP=0** (SEC.15 — інакше IWDG-reset посеред STOP2 ≈26-32 с), IWDG_STDBY узгодити | `01_option_bytes.sh --execute` | `-ob displ` показує застосоване | дамп `-ob displ` |
| 1.3 Factory-провіжининг ключів | `EXECUTE=1 bin/rails factory:execute[...]` (SEC.3; шим-інтеграція вже довела софт — лишилась фізика SWD) | session → completed | AuditLog id |
| 1.4 RDP: R&D = Level 1; **Level 2 — НЕЗВОРОТНІЙ** (SEC.2 rollout R&D→Pilot→Mass; на жертовному чипі спершу) | `01_option_bytes.sh --rdp 1 --execute` | re-power → захист активний | фото/лог |

## 2. Крипто-атестація кремнію (FW.2 CCM + sym)

| Крок | Як | Очікуване | Закриває |
|---|---|---|---|
| 2.1 `ccm_selftest` на платі | HAL-збірка з викликом `Ccm_Run_Self_Test` → UART/RTT звіт (`02_selftest_attest.py --plan` дає кроки) | **усі KAT PASS** — тоді `HAL_CRYPEx_AESCCM_Encrypt` ≡ OpenSSL byte-exact (host-сторона вже доведена `test_ccm_selftest`) | FW.2 → фліп `FW2_CCM_ENABLED` + `TELEMETRY_CCM_ENABLED` (чеклист `03_05` flip) |
| 2.2 `sym_selftest` (ECB/CBC) | той самий runner | PASS | SEC.8 контекст-світчі |
| 2.3 FW.55 silicon-confirm | `05_parity_dump.py --plan`: `qemu_parity.sh` (голден + `parity_wle5.elf`) → `00_flash.sh --elf … --execute` → `05_parity_dump.py --port <VCP>` | вердикт скрипта: дамп ≡ host byte-exact (фіт у 64КБ вже доведено CI-гейтом) | FW.7/FW.19 остаточно; плату перешити бойовим образом |
| 2.4 L1 QATT e2e | прошити Queen EDSK-сім'ю (factory.rake Гілка A → `-w32` EDSK-блок) → flush на staging → бекенд-лог `батч атестовано` + `gateways.last_attested_at` | підпис верифікується (timing sign'а на M4 — заміряти принагідно); сім'я відсутня → legacy-батч приймається | L1 bench-residual (`00_07` SE050-MIGRATION) |

## 3. Живлення (FW.54 / FW.50 / E.63 — дані для β!)

| Крок | Скрипт | Очікуване/Артефакт |
|---|---|---|
| 3.1 STOP2 floor | `03_power_profile.py --mode floor` (PPK2 source-meter) | CSV; ціль ~300 нА RTC-only (`03_01 §1.10`); **300 нА підтвердити JS220/SMU** (PPK2 floor) |
| 3.2 Active-цикл енергія | `03_power_profile.py --mode cycle` | E_cycle мДж — прямий вхід у E.63 (повний SENSE→TX) |
| 3.3 **Vcap recharge-крива** | `03_power_profile.py --mode recharge` | CSV кривої = медіана delta_t → калібрування `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` (E.63 метаболічний growth_points, `03_04 §4.3`) |
| 3.4 Vcap ADC калібрування | DMM vs `Adc_Raw_To_Mv` після розводки дільника | таблиця точок (FW.50) |

## 4. Час/RTC (FW.49 / FW.20)

| Крок | Скрипт | Очікуване |
|---|---|---|
| 4.1 LSE bring-up | за `00_07` FW.49 bench-блоком (`SystemClock_Config` LSE + `MX_RTC_Init` календар/WUT) | RTC цокає 1 Гц, WUT будить зі STOP2 |
| 4.2 Drift кімнатний | `04_lse_drift.py --hours 24` (pyOCD читає RTC TR/DR vs NTP) | ppm у CSV |
| 4.3 Drift ±60°C | той самий скрипт у термокамері (TRL-7, FW.20) | ppm(T) крива |
| 4.4 IWDG 1 год сну | сон 1 год після §1.2 | **нуль** spurious reset (SEC.15) |

## 5. Модем SIM7070G (FW.3 / FW.56)

| Крок | Як | Очікуване |
|---|---|---|
| 5.1 **Verbatim-звірка ноти** | роздобути SIM7070_…_CoAP(S)_Application Note **V1.03** (Techship/SIMCom; публічні дзеркала 403) і звірити проти `03_02 §4` | граматика збігається АБО оновити `at_engine`-транскрипти |
| 5.2 Живі транскрипти | minicom-лог: ATE0/AT/CNMP/CPSMS/CEDRXS + CDNSGIP + CCOAPNEW/SEND/DEL | лог ≡ скриптовані транскрипти `test_at_engine.c` (URC-порядки, таймінги) |
| 5.3 e2e PUT → Rails | повний flush на staging CoAP-intake | `+CCOAPNMI` 2.xx; запис у `TelemetryLog` |
| 5.4 UART DMA RX | наступна ітерація FW.3 (зараз байтовий polling) | — |

## 6. Решта фізики (по item-ах 00_07)

- **HW-AES-KEY/SEC.6:** SE050 eval kit (SEC.14 роль SE — рішення при BOM freeze; SE = SE050 — 03_05 §3.7 / 00_07 SE050-MIGRATION) + live SE05x I²C.
- **BME280** I2C bring-up + gate-timing (VPD).
- **Flash-KV на кремнії:** `HAL_FLASH_*` glue + ECCD-політика читання + erase-час vs LoRa RX (`03_01 §2.3` bench-residual).
- **`Write_OTA_Contract_To_Flash`** — ✅ логіка готова (`flash_ota.c`, host-тест 8/8 `make -C firmware/test flash_ota`, power-cut-safe magic-last); 👤 на bench: HAL_FLASH erase/program-фаза (`g_ota_flash_ops`, main.c) на реальній STM32 + e2e OTA-day.
- **BQ25570 VBAT_OV** резистори (HW, [`02_03`](../../../docs/02_03_BQ25570_MPPT_Nano_Power.md)): формулу можна звірити аналітично+Monte-Carlo до плати; на bench — DMM-замір порога OV проти 5.5 В EDLC-стелі.
- **RF:** діаграма/дальність 868 МГц (HW.31 антени), mesh TTL у полі.
- **П'єзо interrupt-storm поріг** (`03_03 §1.2`) — комп/RC-поріг рішення.

## Вихідний критерій дня

Кожен рядок вище → ✅/❌ + артефакт у `bench_artifacts/<date>/` + оновлення
відповідного item-а в `00_07` (присуди, числа — у канон-доми: енергія →
`02_03`, час → `03_01 §1.10`, крипто-фліп → `03_05`).
