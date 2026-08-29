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
> антени — [`06_01` Pre-Flight](../../../docs/06_01_Deployment_Kamal_Terraform.md) /
> [`02_01 §5`](../../../docs/02_01_Hardware_Architecture_and_BOM.md) SWR-фізика);
> ESD-браслет; лог усього дня → `bench_artifacts/`.

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
| 1.3 Factory-провіжининг ключів (**SEC.9 pre-req:** `PROVISIONING_MASTER_KEY` = свіжий crypto-random, WeakKeyDetector-verified, НЕ FIPS-197 тест-вектор) | `EXECUTE=1 bin/rails factory:execute[...]` (SEC.3; шим-інтеграція вже довела софт — лишилась фізика SWD). **[FW.54] Перший live-крок = `-r32 0x1FFF7590` UID-read (wrong-board guard): звірити реальний формат виводу CLI проти `FactoryFlashing::UidReadout`** — розбіжність = чесна відмова записом; поправити regex за фактичним виводом | session → completed; UID-verify pass | AuditLog id (+ silicon_uid_hex у metadata) |
| 1.4 RDP: R&D = Level 1; **Level 2 — НЕЗВОРОТНІЙ** (SEC.2 rollout R&D→Pilot→Mass; на жертовному чипі спершу) | `01_option_bytes.sh --rdp 1 --execute` | re-power → захист активний | фото/лог |

> **⚠️ Pre-L2 hard-gate (SEC.2 × SEC.15) — bench-день палить лише L1.** RDP **Level 2** (необоротний) — НЕ цей день, а останній крок mass-deploy, і лише ПІСЛЯ того як на жертовному чипі зелені §2.5 (OTA e2e dual-gate) **і** §4.1/§4.6 (WUT reliable multi-hour wake) + §4.4 (нуль spurious reset). Причина: після L2 SWD off, OTA латає **лише mruby**, не C → C-firmware замерзає назавжди; а frozen-IWDG × L2 робить RTC-WUT **ЄДИНИМ** backstop живучості. Тому армінг WUT мусить бути **закоммічена ревʼюйована fn** (не регенерований .ioc, що CubeMX тихо перезапише) + bench-verified ДО burn — інакше реген, який вимкне WUT-IT, цеглить L2-вузол без recovery. Канон [`03_05 §3.6`](../../../docs/03_05_Hardware_Symmetric_Crypto_and_Security.md) + [`03_01 §1.10`](../../../docs/03_01_Firmware_Lifecycle_and_DMA.md).

## 2. Крипто-атестація кремнію (FW.2 CCM + sym)

| Крок | Як | Очікуване | Закриває |
|---|---|---|---|
| 2.1 `ccm_selftest` на платі | HAL-збірка з викликом `Ccm_Run_Self_Test` → UART/RTT звіт (`02_selftest_attest.py --plan` дає кроки) | **усі KAT PASS** — тоді двофазний WL-флоу (B0 + `HAL_CRYP_Encrypt` + `GenerateAuthTAG`; AESCCM_Encrypt у WL-HAL НЕ існує — 03_05 §2.1) ≡ OpenSSL byte-exact (host-сторона вже доведена `test_ccm_selftest`; DataType/B0/word-swap — саме те, що звіряємо) | FW.2 → фліп `FW2_CCM_ENABLED` + `TELEMETRY_CCM_ENABLED` (чеклист `03_05` flip; integration authored 2026-07-03 — фліп-день лише верифікує) |
| 2.1b e2e CCM uplink-day (ПІСЛЯ 2.1-PASS) | фліп обох firmware-гейтів на бенч-парі + backend `TELEMETRY_CCM_ENABLED=true` (staging) → Soldier шле 30B rev2.1 (session KEYL) → Queen 31B-батч → Rails `process_ccm_chunk`. **Двоключовий тракт (FW.2 (в)):** крок 1.3 пише KEYB обом (Tree стор. 125 +40; Queen — її KEYL-слот) → beacon 0x9C від Королеви ЧИТАЄТЬСЯ Солдатом (downlink на KEYB) + 0x55 re-request ЧИТАЄТЬСЯ Королевою; `bcast_key_is_fallback` через SWD = 0 | `TELEMETRY_CCM_DECRYPT_OK_TOTAL` росте; MIC-fail=0; FC-replay guard ловить повтор кадру; panic-CCM (кнопка EXTI) долітає з `PANIC_FLAG` у розшифрованому статусі; 16B-Солдат поруч → `ccm_legacy_telemetry_drops` інкремент + QATT-флаг `LEGACY_DROPS` у health (atomic-cutover видимий з wire) | FW.2 e2e + фліп-гейт (а) підтверджений живим ((б) знято ARCH.54; (в) — двоключовий тракт цього ж кроку) |
| 2.2 `sym_selftest` (ECB/CBC) | той самий runner | PASS | SEC.8 контекст-світчі |
| 2.3 FW.55 silicon-confirm | `05_parity_dump.py --plan`: `qemu_parity.sh` (голден + `parity_wle5.elf`) → `00_flash.sh --elf … --execute` → `05_parity_dump.py --port <VCP>` | вердикт скрипта: дамп ≡ host byte-exact (фіт у 64КБ вже доведено CI-гейтом) | FW.7/FW.19 + FW.31 Gate L (silicon-хвіст) остаточно; плату перешити бойовим образом |
| 2.4 L1 QATT e2e | прошити Queen EDSK-сім'ю (factory.rake Гілка A → `-w32` EDSK-блок) → flush на staging → бекенд-лог `батч атестовано` + `gateways.last_attested_at` | підпис верифікується (timing sign'а на M4 — заміряти принагідно); сім'я відсутня → legacy-батч приймається | L1 bench-residual (`00_07` SE050-MIGRATION) |
| 2.5 FW.23 OTA dual-gate e2e | K_ota вже у транскрипті factory (Гілка A KOTA-блок `0x0803E800`; крок 1.3 пише його разом з KEYL/LSED) → OTA-day: валідний bytecode → APPLY; підмінений байт тіла (валідний CRC32) → REJECT + magic-wipe; **+ late-trailer сценарій (FW.52б):** притримати 0x9B-чанки до згасання OTA-вікна → запізніла печатка воскрешає вікно у фазу печатки → APPLY (`ota_window.h` на кремнії). **+ SEC.20-половина:** (а) replay СТАРОЇ валідно-підписаної версії (version_id ≤ hiwater 0x15) → мовчазний REJECT; (б) залити bytecode, що гарантовано кидає у `calculate_state` → 3 цикли vm_error → erase contract + reset → embedded baseline живий, wire байти 12..13 несуть `reverted`-біт зі спаленою версією (Rails: `EwsAlert firmware_reverted`); re-issue тієї ж N → REJECT, N+1 → APPLY і reverted гасне | обидва вердикти + воскресіння + SEC.20 REJECT/fallback/reverted-звіт на платі ≡ host-тестам | FW.23 + FW.52 OTA-half + SEC.20 [bench:ota-day] остаточно |
| 2.6 FW.17 ротація ключа e2e — **⚠️ активація ЗАМКНЕНА двома gates поза цим bench-днем** (`03_05 §3.8`: (i) MAC-downlink — CCM-фліп НЕ дає його, downlink лишається ECB+CRC; (ii) 0x9E без DID-таргета → сусід-слухач ротується в розсинхрон). Цей крок = **лабораторна перевірка механіки на ізольованій парі**, НЕ activation | фліп трьох гейтів (`FW17_RATCHET_ENABLED` + Queen `FW20_Q2_CMD_RELAY_ENABLED` + ENV `FW17_RATCHET_DOWNLINK_ENABLED`) → `HardwareKeyService#rotate!` для Tree → Queen-реле 0x9E → Soldier re-key CRYP → uplink декриптується НОВИМ session-ключем (`clear_grace_period!` у логах); **downlink при цьому живий** (двоключова FW.2 (в): ратчет не чіпає KEYB — beacon читається і після ротації) → power-cycle: Flash-KV `0x13` версія переживає, boot re-derive `Key_Ratchet_Apply` | grace закрито без ручного втручання; після ребуту вузол на K_v (не K0); beacon post-ротації читається (KEYB недоторканий); rollback/replay-кадр мовчки відкинуто | FW.17 механіка на кремнії (активація = після MAC-downlink + 0x9E-DID, `00_07` FW.17) |

## 3. Живлення (FW.54 / FW.50 / E.63 — дані для β!)

| Крок | Скрипт | Очікуване/Артефакт |
|---|---|---|
| 3.1 STOP2 floor | `03_power_profile.py --mode floor` (PPK2 source-meter) | CSV; ціль ~300 нА RTC-only (`03_01 §1.10`); **300 нА підтвердити JS220/SMU** (PPK2 floor). Цей вимір = вхід відкладеного FW.54-рішення RAM-стану (RTC-реклемація vs Flash-KV vs SRAM2-retain) — приймати з числом, не з моделлю |
| 3.2 Active-цикл енергія | `03_power_profile.py --mode cycle` | E_cycle мДж — прямий вхід у E.63 (повний SENSE→TX) |
| 3.3 **Vcap recharge-крива** | `03_power_profile.py --mode recharge` | CSV кривої = медіана delta_t → калібрування `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` (E.63 метаболічний growth_points, `03_04 §4.3`) |
| 3.4 Vcap ADC калібрування | DMM vs `Adc_Raw_To_Mv` після розводки дільника | таблиця точок (FW.50) |

## 4. Час/RTC (FW.49 / FW.20)

| Крок | Скрипт | Очікуване |
|---|---|---|
| 4.1 LSE bring-up | за `00_07` FW.49 bench-блоком (`SystemClock_Config` LSE + `MX_RTC_Init` календар/WUT) | RTC цокає 1 Гц, WUT будить зі STOP2; `Wall_Seconds_Now()` > 0 (free-running від 2000-01-01 до синку — до bring-up чесно повертає 0), delta_t/recharge-інтервали wall-чесні (FW.49 S1-wiring уже в коді) |
| 4.2 Drift кімнатний | `04_lse_drift.py --hours 24` (pyOCD читає RTC TR/DR vs NTP) | ppm у CSV |
| 4.3 Drift ±60°C | той самий скрипт у термокамері (TRL-7, FW.20) | ppm(T) крива |
| 4.4 IWDG 1 год сну | сон 1 год після §1.2 | **нуль** spurious reset (SEC.15) |
| 4.5 ARCH.41 cold-boot e2e день | VBAT-pull (повний дрейн EDLC) → перший boot: grace-вікно (Лоренц мовчить) + hello `SYNC_REQ 0x56` (DID+Vcap) → Queen перемотує маяк → синк → перший чистий пакет | до синку acoustic-байт = sentinel `0xFE` (бекенд `time_unsynced_fallback`, DCI не отруєний); після — sentinel зникає, epoch_day правильна без серверного вгадування (`03_04 §2.1` B+C) |
| 4.6 **WUT reliable multi-hour wake** (SEC.15 — понад §4.4) | сон кілька годин × N циклів | вузол НАДІЙНО прокидається кожен цикл (не лише no-spurious-reset): WUT auto-reload + IT = ЄДИНИЙ backstop під frozen-IWDG; **армінг = закоммічена ревʼюйована fn, не регенерований .ioc** — pre-req будь-якого RDP-L2 (gate §1) |

## 5. Модем SIM7070G (FW.3 / FW.56)

| Крок | Як | Очікуване |
|---|---|---|
| 5.1 **Verbatim-звірка ноти** | роздобути SIM7070_…_CoAP(S)_Application Note **V1.03** (Techship/SIMCom; публічні дзеркала 403) і звірити проти `03_02 §4`. AT Manual V1.03 + TCPUDP-нота V1.02 вже звірені посторінково (FW.60-розвідка 2026-07-12, `03_02 §4`) — residual лише CoAP(S)-нота | граматика збігається АБО оновити `at_engine`-транскрипти |
| 5.2 Живі транскрипти | minicom-лог: ATE0/AT/CNMP/CPSMS/CEDRXS + CDNSGIP + CCOAPNEW/SEND/DEL | лог ≡ скриптовані транскрипти `test_at_engine.c` (URC-порядки, таймінги) |
| 5.3 e2e PUT → Rails | повний flush на staging CoAP-intake; вердикт з боку Брами — `bin/coap_smoke --host <staging>` (freeze-contract semantic smoke, INF.6: ловить phantom-delivery, не лише liveness) | `+CCOAPNMI` 2.xx; запис у `TelemetryLog`; smoke зелений |
| 5.4 DMA-вуха кремнію | `06_uart_dma_ears.py --plan`: USB-UART замість модема + pyOCD attach (producer-лічильники wraps/NDTR по SWD; логіка кільця host-доведена `test_uart_rx_ring.c`) | вердикт ✅ ROUTE/FEED/WRAP/BOUNDARY: DMAMUX-роутинг USART1_RX, TC = рівно +1 wrap, межовий байт повного кільця не губиться/не двоїться |
| 5.5 **FW.58 DNS-failover** | на живому SIM7070 фліп A-запису `api.silkennet.com` (staging DNS) під час активної Королеви; спостерігати re-resolve після N=3 підряд провалів flush (без IWDG-ребута) | `coap_server_ip` оновлюється на новий IP, flush відновлюється; host-дім `test_fw58_reresolve_predicate` |
| 5.6 **HW.15 marking-звірка** | фізично прочитати маркування чипа модема на прототипі | = **SIM7070G** (не SIM7000G) — найменування у firmware/BOM/`02_05` уніфіковано, лишилась фіз-звірка |
| 5.7 **FW.60 poll-downlink live** | Rails ставить pending CMD (`Downlink::PendingQueueService`) → повний flush → після `send_success` Королева сама `GET poll/<uid>` сирим CA\*-трактом (`sim7070_udp.h`; механіка [`03_02 §4а`](../../../docs/03_02_Queen_Gateway_Firmware.md)) | verbatim URC-порядок `CAOPEN → '>' → CASEND → +CADATAIND → CARECV(≤1459 Б) → CACLOSE` ≡ host-транскриптам (**довгий CARECV-буфер = модемна невідома** — головне, що міряємо); CMD доставлено, UUID-дедуп тримає; кожен poll несе `[0x9C][ts:4]` → RTC-sync задарма |

## 6. Решта фізики (по item-ах 00_07)

> **Сеанс-реєстр [DOC-T.34 ①] — SSOT bench-сеансів.** Один сеанс = один зв'язний
> блок стенд-роботи; 00_07-item, чия bench-робота належить сеансу, несе тег
> `[bench:slug]` на відповідному чекбоксі. Симетрію тримає `tracker:check`
> (`bench_tag_violations`, двосторонньо: кожен тег ∈ реєстр, кожен item реєстру
> тегнутий). Плануєш стенд-день → `grep '\[bench:slug\]' docs/00_07_*` дає повний
> зріз across секції. Нова сесія = новий рядок тут + теги на items.

| Сеанс | Секції RUNBOOK | 00_07-items |
|---|---|---|
| [bench:flash-kv] | §6 (bullet «Flash-KV на кремнії» ↓) | FW.2 · FW.8 · FW.17 · FW.20 · FW.54 |
| [bench:parity-dump] | §2.3 | FW.55 |
| [bench:lse-rtc-wut] | §4 | FW.49 · FW.20 · ARCH.41 · ARCH.26 · SEC.15 |
| [bench:coap] | §5 (+ §6 VBAT-droop) | FW.3 · FW.56 · FW.58 · FW.60 · HW.15 |
| [bench:ota-day] | §2.5 (+ §6 `Write_OTA_Contract_To_Flash`) | FW.23 · FW.52 · SEC.20 |
| [bench:acoustic] | §6 (bullet «Acoustic 16 kHz стенд» ↓) | HW.11 · HW.30 |
| [bench:mpu-trap] | §6 (bullet «MPU-активація на кремнії» ↓) | SEC.21 |
| [bench:queen-cadence] | §5 (+ §6 VBAT-droop) | FW.64 |

- **HW-AES-KEY/SEC.6:** SE05x eval-пара (baseline **SE051C2**, companion OM-SE050ARD-E — 03_05 §3.7 / 00_07 SE050-MIGRATION; роль SE ✅ provisioning-only 2026-07-03) + live SE05x I²C: **cold-boot заряд + T1oI2C-латентності provisioning-операцій** (датащит не специфікує — головне питання) + **замір SE sleep-floor за load-switch гейтом** (TPS22860-патерн — SEC.14 cross-check 2026-06-12: always-on 150 нА ≈ 3.6 мДж/год > весь запас Сценарію C, гейт обов'язковий).
- **MPU-активація на кремнії** (`[bench:mpu-trap]`, SEC.21): реальний MemManage-trap — QEMU mps2 регіони моделює недостовірно, тож host-golden покриває лише RBAR/RASR-математику; на стенді перевіряється сам trap плюс TEX/C/B/S-tuning.
- **Каденс Королеви під pending-CMD** (`[bench:queen-cadence]`, FW.64): на реальному lease підтвердити, що скорочений каденс не зʼїдає енергобюджет і не ламає CIFO-дедуп — вікно кешу коротшає.
- **BME280** I2C bring-up — forced-mode read транспорту в коді ще НЕМА (`bme280.h` = лише компенсація+VPD-математика, host-golden `test_bme280.c`): написати I2C-глю → live read + gate-timing (VPD) + точка калібрування `Bme280_Vpd_Index`→kPa (формула+квант канонізовані `02_01 §3.4`).
- **Flash-KV на кремнії** (ОДНЕ HAL-глю відкриває П'ЯТЬ freeze-contract'ів): `HAL_FLASH_*` glue + ECCD-політика читання + erase-час vs LoRa RX (`03_01 §2.3` bench-residual). Споживачі журналу: `0x10/0x11` Z-пороги (FW.8) · `0x13` key-version (FW.17) · `0x14` FC high-water (FW.2 nonce-якір) · `0x15` OTA version-hiwater (SEC.20 anti-replay — тому §2.5 [bench:ota-day] залежить від цього ж глю) · `0x20` beacon-dedup поколінь (FW.20-S2). Фліпи після верифікації: `FW8_PARSER_ENABLED` · `FW17_RATCHET_ENABLED` (+ §2.6) · `FW20_MESH_RELAY_ENABLED`; persist-roundtrip через power-cycle на кожен ключ.
- **ARCH.35 W25Q32 sector-ring** (gated board-freeze; BOM Queen поз.16 🟡 — W25Q32JV специфіковано, розводки ще нема): розводка SPI+CS у `.ioc` → bench SPI-глю (драйвер+power-cut host-доведені `flash_ring.c`) → фліп `ARCH35_RING_ENABLED 1`; перевірка drain Flash-first→RAM при переповненні CIFO.
- **`Write_OTA_Contract_To_Flash`** — ✅ логіка готова (`flash_ota.c`, host-suite `make -C firmware/test flash_ota` зелена, power-cut-safe magic-last); 👤 на bench: HAL_FLASH erase/program-фаза (`g_ota_flash_ops`, main.c) на реальній STM32 + e2e OTA-day.
- **BQ25570 VBAT_OV** резистори (HW, [`02_03`](../../../docs/02_03_BQ25570_MPPT_Nano_Power.md)): формулу можна звірити аналітично+Monte-Carlo до плати; на bench — DMM-замір порога OV проти 5.5 В EDLC-стелі + HW.12 зовн. clamp (TVS/zener) overcharge-тест.
- **HW.15 VBAT-droop @ 2A burst** (acceptance `02_05 §2.2.1`): осцилограф на VBAT-піні SIM7070G під час LTE-M TX burst → просадка **< 20 мВ** (5-cap tank bank поз.17–20 тримає; brownout-поріг 3.0 В, margin >35×). Без цього замір — brownout-лотерея першого деплою.
- **RF:** діаграма/дальність 868 МГц (HW.31 антени), mesh TTL у полі.
- **П'єзо interrupt-storm поріг** (`03_03 §1.2`, HW.30 cb-4/5) — ⚖️ hardware comparator/RC **vs** software amplitude-gate; якщо SW → поріг калібрується на [bench:acoustic]-ризі (cb-5, post-coupling).
- **Acoustic 16 kHz стенд** (спільний день HW.11 + HW.30, той самий Ti-coin + 16 kHz tone на тому самому п'єзо): HW.11 coating-attenuation з/без (`02_02 §3.4`) + HW.30 SMD-piezo+Sil-Pad voltage-spike vs стара ∅27мм через-отв. (`02_01 §6`) — один стенд-день, спільний rig.

## Вихідний критерій дня

Кожен рядок вище → ✅/❌ + артефакт у `bench_artifacts/<date>/` + оновлення
відповідного item-а в `00_07` (присуди, числа — у канон-доми: енергія →
`02_03`, час → `03_01 §1.10`, крипто-фліп → `03_05`).
