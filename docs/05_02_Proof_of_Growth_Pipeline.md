# 05_02: Пайплайн «Proof of Growth»

## 🎯 Мета

Зафіксувати повний trustless консенсусний пайплайн SilkenNet — від фізичних біосигналів дерева (Lorenz Z як DCI/anti-fraud сигнал; гомеостаз-інтерпретація — недоведена гіпотеза, ⚠️ нижче) до верифікованих on-chain активів (SilkenCarbonCoin / SCC). Включає опис прошивок Солдата й Королеви, всіх кроків верифікації (peaq DID → IoTeX ZK → Chainlink → Polygon + Solana) та відкритих блокерів.

> **⚠️ [Lorenz de-risk]** Інтерпретація «Z-координата = гомеостаз/здоров'я» — **не просто недоведена, а емпірично degenerate + temp-confounded** (E.64 paired-ensemble; вирок + докази = дім [`03_04 §4`](03_04_mruby_Lorenz_Attractor), НЕ дублюю): `stress` (z<2) був недосяжний, `anomaly` (z>45) тригерився теплим днем. **[E.63] growth_points БІЛЬШЕ не Z-похідні** (магнітуда = метаболізм `m(delta_t)`); Лоренц лишився **status-гейтом** (anomaly-поріг ρ-відносний після E.64-фіксу) + **DCI (anti-fraud) валідний незалежно**. Ground-truth-протокол Z↔health → [`05_05 §8`](05_05_Slashing_and_Risk_Policy); slashing вимагає ≥1 прямого сигналу (sap_flow / VPD / acoustic), не лише Z ([`05_05 §7`](05_05_Slashing_and_Risk_Policy)). Пайплайн нижче коректний як механіка — роль Z уже демоутнута до status+DCI.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Пайплайн повністю імплементовано.
- **Відкрите:** прямих блокерів немає (пайплайн імплементовано); залежні інтеграції (Hadron/Chainlink hybrid) трекаються в [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн (11-chain топологія) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Токеноміка (мінтинг SCC/SFC) |
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Моделі (TelemetryLog, Wallet, BlockchainTransaction) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Сервіси (Unpacker, Verification, Minting) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Lorenz SSOT (константи, DCI parity) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Огляд](#-огляд)
- [Повна Архітектурна Схема](#повна-архітектурна-схема)
- [Детальний Опис Кожного Кроку](#детальний-опис-кожного-кроку)
- [Усі Шляхи до (Guard Inventory)](#усі-шляхи-до-walletlock_and_mint-guard-inventory-doc7)
- [Схема Полів БД (Proof of Growth State Machine)](#схема-полів-бд-proof-of-growth-state-machine)
- [Змінні Середовища та Credentials](#змінні-середовища-та-credentials)
- [SEC.11 — Lorenz Seed Provenance & Dual Computation Integrity](#-sec11--lorenz-seed-provenance--dual-computation-integrity)
- [Хто контролює ВИБІРКУ — реєстр оракулів](#-хто-контролює-вибірку--реєстр-оракулів-arch111)
- [Subgraph — зовнішня читацька поверхня](#-subgraph--зовнішня-читацька-поверхня-дім-ops36)
- [Статус пайплайну](#-статус-пайплайну)
<!-- TOC:AUTO:END -->

---

## 💡 Огляд

"Proof of Growth" — це консенсусний пайплайн SilkenNet (trustless — цільовий намір; поточна модель довіри — §Модель довіри нижче), що перетворює
фізичні біосигнали дерева (Lorenz Z як DCI/anti-fraud сигнал; гомеостаз —
недоведена гіпотеза, ⚠️ §Мета) на верифіковані
on-chain активи (SilkenCarbonCoin / SCC). Пайплайн складається з двох
взаємопов'язаних частин:

1. **Firmware (Залізо + mruby)** — STM32WLE5JC Солдат обчислює Z-координату
   і пакує `status_byte` з `growth_points` на рівні дерева.
2. **Backend (Rails 8.1 + Sidekiq)** — сервер розпаковує, перевіряє, надсилає
   до peaq / IoTeX / Chainlink і мінтить токени на Polygon та Solana.

### Модель довіри пайплайну (trust model)

> **Чесна рамка** (verify-by-data 2026-06-28 → [`00_07`](00_07_Action_Plan_Tracker) ARCH.53). Мінт SCC **оптимістичний**: `growth_points` зараховуються при розпакуванні телеметрії (`credit!`), а pending-мінт створює tokenomics-шлях за порогом `available_balance ≥ EMISSION_THRESHOLD` (PATH 2, §DOC.7 нижче; **NET, не gross** — [ARCH.94]: сконвертоване лишається в `locked_balance` назавжди, тож поріг по `balance` після першого ж мінту переобирав гаманець, який змінтувати вже нічого не може). IoTeX-ZK + Chainlink-DON — це **асинхронна anti-fraud-провенанс-перевірка** (Lorenz Z = anti-fraud-сигнал, не health/gate — E.63), а **НЕ** синхронний gate перед кожним мінтом. Enforcement проти фроду = **ex-post reconcile + clawback** (device-Merkle-корінь ↔ намінтоване → `slash()`; політика [`05_05 §3.3`](05_05_Slashing_and_Risk_Policy)) — **наразі не збудований** (energy-gated L2). Trust-origin per-packet — драбина **L0** (приймається беззастережно) / **L1** (Queen-attest = soft-marker, не gate) / **L2** (per-tree device-voice, North-Star).

> **[ARCH.62] Interim defense-in-depth (поки clawback — North-Star).** Оскільки живий PATH 2 мінтить оптимістично, а ex-post clawback ще не збудований, агрегатний mint-volume detector (`Treasury::MonitorService` → gauge `silkennet_mint_volume_window_scc` + per-token inert circuit-break) обмежує blast-radius над-мінту **у вікні детекції**: per-tx guards + `MAX_SUPPLY` ловлять поодинокі аномалії, ARCH.62 — агрегатний сплеск обсягу (firmware/pipeline-баг чи зловжитий MINTER-ключ), який `chain_audit_delta` не бачить, коли DB↔chain згодні на аномальному числі. **Комплемент, не заміна** clawback (той лишається North-Star). Пороги inert-default → [`00_07` ARCH.62](00_07_Action_Plan_Tracker) + [`06_03 §2.8`](06_03_Prometheus_Observability).

**Oracle-driven gate (PATH 1) — повний trustless-ланцюг, що діє ЛИШЕ на цьому шляху (з `telemetry_log`):**

```
tree.peaq_did ≠ nil                        ← peaq Machine Identity
  && telemetry_log.verified_by_iotex       ← IoTeX W3bstream ZK-proof
    && telemetry_log.zk_proof_ref ≠ nil
      && telemetry_log.oracle_status_fulfilled?      ← Chainlink DON consensus
        → blockchain_transaction.status == :sent     ← Polygon EVM mint
          → solana micro-reward sent                 ← Solana SPL reward
```

⚠️ **PATH 1 наразі НЕ виконується у проді — ДЕМОУТНУТО [ARCH.53]** (founder-рішення 2026-07-03): on-chain `sendRequest` вилучено з `Chainlink::OracleDispatchService` (LINK-cost за callback, що не прилетить: DON Functions JS-source / consumer `fulfillRequest` / relayer відсутні; ще й tx_hash≠requestId — lookup не збігся б). Dispatch = local correlation-marker (Крок C); tokenomics-шлях (PATH 2) і `MintBatchCollector` мінтять **без** цього gate (KYC + balance + active-tree enforced; oracle — ні). Цей ланцюг — **latent-код + manual-fulfillment двері**: замикання PATH 1 **відмовлено остаточно** (founder-присуд 2026-07-19, ARCH.53 §🗄️ — Merkle-lineage [ARCH.12/MRV.1] дає аудитору сильніший доказ, ніж DON-переверифікація нашого ж обчислення); guard'и й callback-endpoint збережені.

---

## Повна Архітектурна Схема

```
╔══════════════════════════════════════════════════════════════════════╗
║  L1/L2: FIRMWARE (STM32WLE5JC)                                      ║
║                                                                      ║
║  [EBFC Аноду → BQ25570 MPPT → 0.47F EDLC Суперконденсатор]         ║
║       │ >500 mV від метаболізму глюкози дерева                      ║
║       ▼                                                              ║
║  [STM32WLE5JC SOLDIER]                                               ║
║   ФАЗА 1: SENSE                                                      ║
║     ADC → Vcap (мВ), Temp (°C), IWDG heartbeat                      ║
║     DMA 16kHz → raw_audio[512] → log-mel[40] → inference             ║
║     delta_t_seconds = tick - last_wakeup_timestamp (метаболізм EBFC) ║
║                                                                      ║
║   ФАЗА 2: mruby BioContract (on-device Lorenz) [SEC.11 + FW.6]      ║
║     ЄДИНА сигнатура (hard cutover): calculate_state(x,y,z,t,a,m,v)  ║
║       A) Warm continuation (RTC DR19 == "LZST"): (x,y,z) ← DR16-18   ║
║       B) Cold start (DR19 ≠ MAGIC, після VBAT loss):                 ║
║          K_seed (Flash) + epoch_day = unix_ts/86400                  ║
║          digest = HMAC-SHA256(K_seed, "init|" || epoch_day_be)       ║
║          (x₀,y₀,z₀) = bytes_to_signed_unit_floats(digest[0..23])    ║
║          ↳ identifier-as-key антипатерн (raw DID seed) ВИДАЛЕНО      ║
║     250 ітерацій Lorenz Euler → (x_final,y_final,z_final) → DR16-18  ║
║     bio_contract.rb :: BioContract.evaluate_and_pack → status_byte  ║
║     status_byte = [PanicFlag:1 | bio_status:2 | growth_points:5]    ║
║                    [FW.29 PANIC_FLAG_BIT | FW.29-PACK status bits 6..5 | gp bits 4..0]║
║                                                                      ║
║   ФАЗА 3: PACK + ENCRYPT                                             ║
║     Payload [16 bytes]: DID(N) Vcap(n) Temp(c) Acoustic(C)          ║
║                          Metabolism(n) StatusByte(C) TTL(C) Pad(a4) ║
║     AES-128-ECB hardware (CRYP module) → encrypted_payload[16]      ║
║     [post-ARCH.42; FW.2 target: AES-128-CCM 30B wire-rev2.1 з MIC]  ║
║     Prefix: DID[4] + RSSI_inverted[1] = L2 header (21 bytes total)  ║
║                                                                      ║
║   ФАЗА 4: LoRa TX / MESH RELAY                                       ║
║     Radio.Send(21 bytes) @ 868 MHz                                   ║
║     TTL-based multi-hop → anti-pingpong (seen-set cache 8 DIDs)     ║
║     Emergency TX якщо TinyML: chainsaw/fire detected (PANIC_TTL=5)  ║
║                                                                      ║
║  [STM32WLE5JC QUEEN + SIM7070G]                                      ║
║   LoRa RX (LORA_RX_INFINITE) → OnRxDone ISR → lora_rx_flag=1       ║
║   HAL_CRYP_Decrypt → decrypted_payload[16]                          ║
║   Process_And_Cache_Data → forest_cache[50] (CIFO EdgeCache)        ║
║   OTA Broadcast: рефлекторний постріл в ефір після кожного RX       ║
║   Queen health (DID=0): sentinel packet → GatewayTelemetryWorker    ║
║   Flush_Cache_To_Rails (кожну ~1 год + jitter):                     ║
║     binary_batch_buffer[2048] → CoAP PUT /telemetry/batch/<QUEEN_UID>║
║     via SIM7070G (LTE-M / Starlink Direct-to-Cell)                  ║
╚══════════════════════════════════════════════════════════════════════╝
        │ CoAP/UDP → port 5683 (lib/daemons/coap_listener)
        ▼
╔══════════════════════════════════════════════════════════════════════╗
║  L5: BACKEND (Rails 8.1 + Sidekiq)                                  ║
║                                                                      ║
║  [UnpackTelemetryWorker] queue: uplink (prio 1)                     ║
║    Base64 decode → AES-256-CBC decrypt (Gateway CoAP key, 32B)      ║
║    → unwrap batch → AES-128-ECB decrypt per record (Tree LoRa key)  ║
║    "Soft Key Rotation": new_key → fallback previous_key             ║
║    Gateway.find_by(uid:) → mark_seen!(new_ip:)                      ║
║    ▼                                                                 ║
║  [TelemetryUnpackerService]                                          ║
║    Chunk: [DID:4][RSSI:1][Payload:16] = 21 bytes                    ║
║    Format: "N n c C n C C a4" (unpack)                              ║
║    [SEC.10] panic? = (status_byte & 0x80); якщо panic +              ║
║      panic_counter = pad_data[2..3].unpack1("n") > 0:                 ║
║      Rails.cache.write(unless_exist:) silken:panic:nonce:DID:CTR    ║
║      → replay → log+metric+RETURN (no log, no AlertDispatch)         ║
║    DeviceCalibration: normalize ADC → фізичні одиниці               ║
║    SilkenNet::Attractor.calculate_z_from_state(x_prev,y_prev,z_prev, ║
║      temp, acust, delta_t_s, vcap_mv) → z_value [SEC.11 sole API]   ║
║      ├─ warm: (x_prev,y_prev,z_prev) ← prev TelemetryLog.lorenz_state║
║      └─ cold: SeedDerivation.initial_state(K_seed, epoch_day) ║
║              + telemetry_log.cold_start_flag = true                  ║
║    persist tail → telemetry_log.lorenz_state_x/y/z (mirror RTC)     ║
║    growth_points = (status_byte & 0x1F) * 2 (×2 upscale, FW.29-PACK)║
║    bio_status = (status_byte >> 5) & 0x03 (bits 6..5, FW.29-PACK)   ║
║    AlertDispatchService.analyze_and_trigger!(log)                    ║
║    tree.wallet.credit!(log.growth_points)                           ║
║    └──► IotexVerificationWorker.perform_async(id, created_at_iso)   ║
║                                                                      ║
║  ─────────── КРОК A: peaq DID (одноразово при Provisioning) ─────── ║
║  [ProvisioningController#register] POST /provisioning                ║
║    PeaqRegistrationWorker.perform_async(tree.id)                    ║
║    ▼ Peaq::DidRegistryService#register!                              ║
║    DID = "did:peaq:0x" + SHA256(did:id:created_at)[0:40]           ║
║    Ed25519::sign(peaq_signing_key, did_string) → proof              ║
║    POST {peaq_node_url}/did/register                                 ║
║    → tree.peaq_did saved (UNIQUE index)                              ║
║                                                                      ║
║  ─────────── КРОК B: IoTeX W3bstream ZK-Verification ────────────── ║
║  [IotexVerificationWorker] queue: web3_critical (prio 6), retry: 5  ║
║    Iotex::W3bstreamVerificationService#verify!                       ║
║    POST {iotex_w3bstream_url}/verify                                 ║
║    Body: { device_id, peaq_did, telemetry_log_id, hardware_sig,     ║
║            chaotic_data: { z_value, temp, acoustic, voltage, bio }}  ║
║    Response: { proof_id | receipt_id } → zk_proof_ref               ║
║    → log.update!(verified_by_iotex: true, zk_proof_ref:)            ║
║    → ChainlinkDispatchWorker.perform_async(id, created_at_iso)      ║
║                                                                      ║
║  ─────────── КРОК C: Chainlink Oracle Dispatch ───────────────────── ║
║  [ChainlinkDispatchWorker] queue: web3_critical (prio 6), retry: 5  ║
║    Guard: log.verified_by_iotex? == true                             ║
║    Chainlink::OracleDispatchService#dispatch!                        ║
║    dispatch! = local correlation-marker (ARCH.53 demote):           ║
║      request_id = "chainlink-req-{SecureRandom.hex(16)}"            ║
║      NO on-chain sendRequest / NO RPC (PATH 1 callback unwired)     ║
║    → log.update!(chainlink_request_id:, oracle_status: "dispatched")║
║                                                                      ║
║  ─────────── КРОК D: Oracle Callback → Minting ──────────────────── ║
║  POST /api/v1/oracle_callbacks                                       ║
║    { chainlink_request_id, success: true/false }                     ║
║    → log.update!(oracle_status: "fulfilled" | "failed")             ║
║    ├──► MintCarbonCoinWorker.perform_async (EVM Polygon SCC/SFC)    ║
║    └──► SolanaMicroRewardWorker.perform_async (Solana USDC)         ║
║                                                                      ║
║  ─────────── КРОК E: BlockchainMintingService (EVM) ─────────────── ║
║    Guard: verified_by_iotex? && oracle_status_fulfilled?             ║
║    Guard: wallet.hadron_kyc_status == "approved"                     ║
║    [batchMint path]:                                                 ║
║      eth_call dry-run → batch_dry_run_reverts?                       ║
║        ├── false → client.transact("batchMint") → Polygon Mainnet    ║
║        └── true  → fallback_to_individual_mints                      ║
║                     (кожен mint() окремо; "отруйний" запис ізольовано)║
║    [single mint path]: client.transact("mint") → Polygon Mainnet     ║
║    → blockchain_transaction.status = :sent, tx_hash saved            ║
║    → BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)   ║
║                                                                      ║
║  ─────────── КРОК F: Solana Micro-Reward (паралельно) ────────────── ║
║    Guard: verified_by_iotex? && oracle_status_fulfilled?             ║
║    POST {SOLANA_RPC_URL} sendTransaction (Ed25519-signed, base64)    ║
║    SPL Token Program: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA  ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Детальний Опис Кожного Кроку

### Firmware: Солдат (STM32WLE5JC)

**Файл:** `firmware/soldier/main.c`

#### Фаза 1 — SENSE (Збір фізичних даних)

| Сигнал | Джерело | Формат |
|--------|---------|--------|
| `vcap_voltage` | ADC → VREFINT канал | uint16 (мВ, 0–5000; ⚠️ сирий до FW.50 — [`03_01 §1.4`](03_01_Firmware_Lifecycle_and_DMA)) |
| `internal_temp` | ADC → внутрішній датчик | int8 (°C, −45..90) |
| `acoustic_events` | DMA 16 кГц → TinyML INT8 forward-pass | uint8 (0–255) |
| `delta_t_seconds` | `HAL_GetTick() - last_wakeup_timestamp` | uint32 (EBFC метаболізм) |

> **[SEC.11]** `chaos_seed = HAL_RNG_GenerateRandomNumber()` як вхід Лоренца — **видалено** (hard cutover). Початкова точка `(x₀, y₀, z₀)` тепер деривується з per-device `K_seed` (Flash) через `HMAC-SHA256(K_seed, "init|" || epoch_day_be)` лише при cold-start після VBAT loss; у норму FW.6 RTC continuation (DR16-DR18 magic `"LZST"`) пропускає re-init. HRNG залишається лише для AES IV jitter, mesh anti-pingpong та CoAP nonce. Деталі — [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning).

**TinyML класи** (`silken_net_audio_model.h`): 0=Тиша, 1=Вітер, 2=Кавітація, 3=Пилка, 4=Фауна.

#### Фаза 2 — mruby BioContract (on-device Lorenz Attractor)

**Файл:** `firmware/bio_contracts/bio_contract.rb`

**Мова:** mruby (Ruby для embedded). Компілюється в байткод `mrbc` → вбудовується
в Flash (`lorenz_bytecode[]`) або оновлюється OTA (`MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`).

**Модуль `SilkenNet::Attractor` (firmware):**
```ruby
# ─ Константи Лоренца (BASE_SIGMA/RHO/BETA, DT, ITERATIONS, SIGMA/RHO_LIMITS,
#   BASELINE_DELTA_T_S, NOMINAL_VCAP_MV) — SSOT: 03_04 §1.2, міст-константи §6.1 (firmware↔backend
#   дзеркало). Значення тут НЕ дублюються: правити ЛИШЕ в 03_04, інакше — тихий
#   DCI-дрейф device-Z vs server-Z. [E.63] β = BASE_BETA фіксований (β-пертурбація
#   ВИДАЛЕНА; метаболізм → growth_points напряму, 03_04 §4.3).

def self.calculate_z_axis(x, y, z, temp, acoustic)   # [E.63] β фікс — без delta_t/vcap
  # [SEC.11] (x, y, z) приходять як аргументи: warm — з RTC DR16-18,
  # cold — з K_seed/epoch_day (див. evaluate_and_pack нижче). DID не є входом.
  # local_sigma (acoustic), local_rho (temp): perturbation + clamp; β = BASE_BETA
  ITERATIONS.times { dx/dy/dz → Euler integration (BASE_BETA in dz) }
  z  # Ruby Float, НЕ BigDecimal
end
```

**Модуль `SilkenNet::BioContract` (firmware) — токеноміка:**
```ruby
# CRITICAL_Z_MIN/MAX, OPTIMAL_Z_TARGET — SSOT: 03_04 §4.1 + §Z→bio_status mapping.
# (firmware hardcoded у Flash; per-species OTA override — FW.8 нижче). НЕ дублювати тут.

def self.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
  # (x_prev, y_prev, z_prev): warm — з RTC DR16-18; cold — з SEC.11 K_seed/epoch_day
  z_val = Attractor.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic)  # [E.63] β фікс
  if    z_val < CRITICAL_Z_MIN  → status=1, growth_points=1  # stress
  elsif z_val > anomaly_ceiling → status=2, growth_points=0  # anomaly [E.64] ρ-відносна стеля (≈45 при ρ=28), НЕ absolute — SSOT 03_04 §4
  else                          → status=0                    # homeostasis
    # [E.63] growth_points = метаболічна жвавість m(delta_t), НЕ |29−z| — SSOT 03_04 §4.3
    growth_points = metabolic_health(delta_t_s)               # 5-bit wire (5..31)
  end
  payload_byte = (status << 5) | growth_points  # [PanicFlag:1 (FW.29) | Status:2 | GP:5]
end
```

**Точка входу з C:** `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)` → `payload_byte` (uint8_t). Сигнатура `calculate_state(seed, …)` ВИДАЛЕНА (SEC.11 hard cutover, pre-prod, no shim).

---

#### 🤖 FW.8 — OTA Sync для Per-Species Lorenz Thresholds (Дизайн)

> **Cross-ref:** [`00_07` — FW.8](00_07_Action_Plan_Tracker) — дизайн завершено ✅

**Проблема:** `CRITICAL_Z_MIN`, `CRITICAL_Z_MAX`, `OPTIMAL_Z_TARGET` hardcoded у Flash. Сосна (*Pinus sylvestris*) і дуб (*Quercus robur*) мають різний діапазон нормальної конвективної активності — один пороговий набір дає хибні anomaly alerts для одного виду при нормальному стані іншого.

**Рішення:** синхронізувати per-species пороги через OTA Config Payload — без перекомпіляції firmware.

##### 4а.1 Нова структура OTA Config Payload

Поточний OTA downlink передає лише mruby bytecode (bio_contract). Додаємо окремий **Config Block** як перший фрагмент batch:

```
OTA Batch Downlink Format (розширений):
  [CMD_TYPE:1] [PAYLOAD_LEN:2] [PAYLOAD:N]

Тип команди цього розділу (повна карта — дім нижче):
  CMD_OTA_BYTECODE    = 0x99   (mruby chunks — існуючий)
  CMD_SET_THRESHOLDS  = 0x9A   (per-species Lorenz Z пороги, FW.8)
```

> **Повна карта `CMD_TYPE`-опкодів** (`0x99..0x9F`, без колізій) — канон-дім [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA). NB: `0x9B` зайнятий `CMD_HMAC_TRAILER` (FW.23 OTA-печатка); TinyML-пороги — `0x9D` (`CMD_SET_AUDIO_THRESHOLDS`, FW.18), **не** `0x9B`.

**CMD_SET_THRESHOLDS payload (10 байт):**

```
Байти  Поле                   Тип    Опис
0–1    z_min_fixed            int16  CRITICAL_Z_MIN × 100 (наприклад, 200 = 2.0)
2–3    z_max_fixed            int16  CRITICAL_Z_MAX × 100 (наприклад, 4500 = 45.0)
4–5    z_optimal_fixed        int16  OPTIMAL_Z_TARGET × 100 (наприклад, 2900 = 29.0)
6      species_id             uint8  0=Pinus, 1=Quercus, 2=Fagus, 3=Picea, 0xFF=custom
7      config_version         uint8  Version counter (anti-replay для конфігурації)
8–9    checksum               uint16 CRC16 байтів 0..7
```

**LoRa-канал (Queen→Soldier, downlink `0x9A` — напрямок-фікс 2026-07-03):** 16B AES-128-**ECB** в обидві ери; ключ CCM-ери = cluster control-plane **KEYB** (двоключова модель — [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security); CCM належить лише uplink-телеметрії на session-KEYL). **CoAP-магістраль (Queen→Rails):** AES-256-CBC (без змін).

##### 4а.2 Firmware-persist (Flash-KV)

> Прийняті пороги firmware зберігає у **Flash-KV** — bit-layout (ключі `0x10`/`0x11`: z_min/z_max/z_opt ×100 · `species_id` · `config_version`), інваріанти «порвана/невалідна пара → firmware-дефолти» + power-cut семантика = канон-дім [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA). Код — `common/lorenz_thresholds.h` (`Save/Load`, host-готовий) + handler `0x9A` у `firmware/soldier/main.c`, виклик gated `FW8_PARSER_ENABLED 0` (deferred TRL-7 — лишається bench-фліп + HAL-глю на кремнії). RTC-підхід **відкинуто**: STM32WLE5JC має лише `DR0..DR19` (карта [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)), суміжних байтів під пороги немає. Повний статус персисту/wiring → [`00_07` — FW.8](00_07_Action_Plan_Tracker).

##### 4а.3 Backend — OtaPackagerService та TreeFamily

```ruby
# app/services/ota_packager_service.rb — [FW.8] РЕАЛІЗОВАНО (Rails-сторона)
def build_threshold_config_block(tree)
  thresholds = tree.effective_lorenz_thresholds  # 3-tier: cluster > family > global
  z_min      = (thresholds[:min]     * 100).round.to_i
  z_max      = (thresholds[:max]     * 100).round.to_i
  z_opt      = (thresholds[:optimal] * 100).round.to_i
  species_id = SPECIES_ID_MAP[tree.tree_family.scientific_name] || 0xFF
  version    = (tree.ota_config_version.to_i + 1) & 0xFF

  payload = [z_min, z_max, z_opt, species_id, version].pack("s<s<s<CC")
  crc = Digest::CRC16.checksum(payload)
  payload + [crc].pack("S<")

  [CMD_SET_THRESHOLDS].pack("C") + [payload.bytesize].pack("S<") + payload
end
```

> **Статус [FW.8]:** ✅ Rails-сторона (`build_threshold_config_block`) реалізована; firmware C-side (parser `0x9A` host-tested) + персист + gate (`FW8_PARSER_ENABLED 0`, deferred TRL-7) — §4а.2 вище. До активації Soldier використовує хардкодовані пороги (дім [`03_04 §1.2`](03_04_mruby_Lorenz_Attractor)).

##### 4а.4 Per-Species Default Thresholds

| Вид дерева | `critical_z_min` | `critical_z_max` | `optimal_z_target` | Обґрунтування |
|---|---|---|---|---|
| *Pinus sylvestris* (Сосна звичайна) | **2.0** | **45.0** | **29.0** | Базові (поточні) |
| *Quercus robur* (Дуб звичайний) | **3.0** | **42.0** | **27.0** | Нижчий піковий стрес, менша варіативність |
| *Fagus sylvatica* (Бук лісовий) | **2.5** | **43.0** | **28.0** | Помірний діапазон |
| *Picea abies* (Ялина звичайна) | **1.5** | **46.0** | **30.0** | Ширший діапазон гомеостазу |
| *Betula pendula* (Береза бородавчаста) | **2.0** | **44.0** | **28.5** | Подібна до сосни |

> **Джерело значень:** Попередні пороги (сосна). Точні значення інших видів потребують калібрування з Lorenz trajectory analysis. **Рекомендовано:** запросити ботанічний baseline від Спрягайла/Гаврилюка (ЧНУ, [`00_02`](00_02_Academic_Integration_and_IP)).

##### 4а.5 Backend Mirror (TelemetryUnpackerService)

Backend вже має `TreeFamily#critical_z_min|max|optimal_z_target` через `calculate_z` pipeline. Після реалізації FW.8, сервер також надсилає ці пороги на пристрій та верифікує що `z_value` в `TelemetryLog` відповідає тим самим порогам що використовуються firmware → Dual Computation Integrity.

---

**21-байтний пакет (binary packet format):**
```
Байти  Поле               Тип    Опис
0–3    DID (L2 header)    uint32 Апаратний ідентифікатор (SNET-XXXXXXXX raw)
4      RSSI (інвертований) uint8  -RSSI (positive byte)
────── L3 Payload (16 bytes, AES-128-ECB encrypted post-ARCH.42) ─────
5–6    Vcap               uint16 Напруга суперконденсатора (мВ)
7      Temperature         int8  Температура (зі знаком)
8      Acoustic_events    uint8  Кількість акустичних подій
9–10   Metabolism_s       uint16 Час зарядки EBFC δt (секунди)
11     StatusByte         uint8  [7]PanicFlag | [6:5]bio_status | [4:0]growth_points (FW.29-PACK)
12     Mesh TTL           uint8  Initial=5 → decrements on each hop
13–14  Firmware version   uint16 firmware_version_id (перші 2 байти Pad-поля: Pad[0]<<8|Pad[1])
15–16  Reserved pad       uint16 Pad[2:3] (нулі, зарезервовано)
```

**Шифрування:** **AES-128-ECB** апаратним модулем `CRYP` (`CRYP_KEYSIZE_128B`, post-ARCH.42 Variant B) → `HAL_CRYP_Encrypt`. **FW.2 target:** AES-128-CCM (30B wire-rev2.1 packet з 8-byte MIC + Frame Counter + device_z/diag/vpd, апаратно через `HAL_CRYPEx_AESCCM_Encrypt`; розкладка — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)).
Заголовок [DID:4][RSSI:1] передається відкрито; payload[16] зашифровано.

#### Фаза 4 — LoRa TX + Mesh

- `Radio.Send(21 bytes)` @ 868 МГц (Europe/Ukraine)
- **Mesh relay:** TTL-based (DEFAULT_TTL=3, PANIC_TTL=5)
- **Anti-pingpong:** seen-set `recent_mesh_dids[3]` у RTC Backup Registers DR8/DR9/DR11 (FW.21: shrunk 8→3; DR10 + DR12 під EMA, vcap_x10 запаковано в low 16 біт DR12)
- **Emergency TX:** якщо `ml_event_id == 3` (Пилка) → `Trigger_Emergency_LoRa_TX` з PANIC_TTL

---

### Firmware: Королева (STM32WLE5JC + SIM7070G)

**Файл:** `firmware/queen/main.c`

#### CIFO Edge Cache

```c
typedef struct {
    uint32_t uid;      // DID дерева
    uint8_t payload[16]; // Останній розшифрований payload
    int8_t rssi;
    uint8_t is_active;
} EdgeCache;

EdgeCache forest_cache[CACHE_MAX_ENTRIES]; // 50 слотів
```

**Дедуплікація:** Останній пакет від кожного DID перезаписує попередній
(тільки найсвіжіші дані).

**Queen Sentinel:** `DID == 0x00000000` → власна телеметрія Королеви →
`GatewayTelemetryWorker` (не TelemetryLog).

> **🔐 Шарувате (layered) шифрування, НЕ повторне:** два AES-шари захищають різні скоупи — немає double-encryption чи MITM. **Внутрішній (E2EE):** Soldier шифрує 16-байтовий sensor-блок своїм per-device **AES-128** (LoRa-ключ). **Зовнішній (транспорт):** Queen додає **AES-256-CBC** як обгортку CoAP-батча (Queen→Rails). CIFO-дедуплікація потребує лише **cleartext DID** (перші 4 байти), не вмісту. ⚠️ **Zero-Trust відкрите:** поточний `EdgeCache` тримає *розшифрований* inner-payload (Queen декодує внутрішній блок) — чи Queen взагалі має його торкатись, це питання відкладеного AES-пасу **FW.2** (AES-128-CCM + MIC); деталі crypto — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security).

#### CoAP Batch Flush

```
Інтервал: FLUSH_INTERVAL_MS = 3_600_000 (1 година) + jitter 0–60 с
Примусовий: cache_count >= CACHE_MAX_ENTRIES - FLUSH_HEADROOM (5 вільних слотів)

Binary batch format: [DID:4][RSSI:1][Payload:16] × N entries
Транспорт: CoAP PUT /telemetry/batch/<QUEEN_UID>
           via SIM7070G (AT+CNMP=38, LTE-M/NB-IoT)
           або Starlink Direct-to-Cell
URI-Path: third segment = queen_uid (Flash-provisioned або "UNPROV-{HEX}") → Gateway lookup
```

#### OTA Downlink

```
Rails → CoAP downlink → queen RAM assembly (pending_ota_bytecode[8192])
Queen → LoRa broadcast (рефлекторний постріл після кожного RX):
  Chunk size: 11 bytes payload + 5 bytes header = 16 bytes (1 AES block)
  Format: [0x99][index:2][total:2][bytecode:11]
  AES-128-ECB encrypted before TX (LoRa OTA reflex використовує той самий LoRa key, post-ARCH.42)
  Pacing: 60ms delay між чанками
Soldier:
  MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000
  Magic check: 0x45544952 ("RITE") → load OTA bytecode
  Else → load embedded lorenz_bytecode[]
```

---

### Крок A: peaq DID Provisioning

**[ARCH.77]** Тригер — форестерська POST-форма в браузері (не фабрика, не пристрій): межа проходить не за форматом відповіді, а за тим, хто відвантажує клієнта.

**Тригер:** `POST /provisioning` → `ProvisioningController#register`

**Файли:**
- `app/controllers/api/v1/provisioning_controller.rb`
- `app/workers/peaq_registration_worker.rb` — queue: `web3` (prio 7), retry: 5
- `app/services/peaq/did_registry_service.rb`
- `app/services/ed25519_crypto/signing_service.rb`

**Генерація DID:**
```ruby
hex_hash = SHA256("#{tree.did}:#{tree.id}:#{tree.created_at.to_i}")
peaq_did = "did:peaq:0x#{hex_hash[0, 40]}"
# Приклад: "did:peaq:0xa3f8...1e2c" (51 символ)
```

**HTTP-запит до peaq Substrate node:**
```
POST {credentials.peaq_node_url}/did/register
Content-Type: application/json
Timeout: connect=10s, read=30s

Body:
{
  "did": "did:peaq:0x{40hex}",
  "device_id": "SNET-XXXXXXXX",
  "metadata": { "type": "tree", "tree_id": ..., "cluster_id": ..., "registered_at": "ISO8601" },
  "proof": {                    ← опціонально (лише якщо peaq_signing_key є)
    "type": "Ed25519Signature2020",
    "verification_method": "did:peaq:0x...#key-1",
    "signature": "Ed25519::sign(peaq_signing_key, did_string)",
    "public_key": "Ed25519::public_key_from_seed(peaq_signing_key)"
  }
}
```

**Результат:** `tree.peaq_did` збережено в БД (UNIQUE index).
**Ідемпотентність:** `return if tree.peaq_did.present?` + `tree.with_lock`.

---

### Крок B: IoTeX W3bstream ZK-Верифікація

**Тригер:** `IotexVerificationWorker.perform_async(log.id_value, created_at_iso)`
з `TelemetryUnpackerService#commit_telemetry`

**Файли:**
- `app/workers/iotex_verification_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/iotex/w3bstream_verification_service.rb`

**Статус (Wiki 05_01):** ✅ Real — HTTP POST через W3bstream API

🔑 **ACTIVATION-GATED з 2026-09-02 [OPS.37/ARCH.118]:** тригер вище стоїть під `if Iotex::W3bstreamVerificationService.configured?` (обидва значення `IOTEX_W3BSTREAM_URL`/`IOTEX_API_KEY`, ENV-first + credentials-фолбек — один дім «чи нога жива»); обидва воркери (`IotexVerificationWorker`, `IotexBackfillWorker`) виходять WARN-ом без raise, коли нога не сконфігурована (backfill називає лічбу неверифікованих у вікні). Підстава — трейс canopy з симулятором: кожен `TelemetryLog` купував 6 падаючих виконань + щогодинний ре-арм 200 — ~85 % джоб і Redis-команд слоту, невидимих Sentry (`VerificationError` в `excluded_exceptions`); жодна deploy-поверхня значень не несе, а хост із `.env.example` (`w3bstream-api.iotex.io`) не має DNS-запису (ARCH.118). ⚠️ «✅ Real» вище — про КОД (HTTP POST існує), не про живу ногу: у проді вона активується лише провіжном обох значень, і `verified_by_iotex` доти чесно `false` — це не mint-гейт (PATH 2 оптимістичний, «Чесна рамка»).

**Payload до W3bstream:**
```json
{
  "device_id":        "SNET-XXXXXXXX",
  "peaq_did":         "did:peaq:0x{40hex}",
  "telemetry_log_id": 12345,
  "timestamp":        1720000000,
  "hardware_signature": "Ed25519(derive_iotex_seed(did), '{did}:{log_id}:{created_at.to_i}')",
  "chaotic_data": {
    "z_value":        23.4521,
    "temperature_c":  22.5,
    "acoustic_events": 3,
    "voltage_mv":     4200,
    "bio_status":     "homeostasis"
  }
}
```

**HTTP-запит:**
```
POST {credentials.iotex_w3bstream_url}/verify
Authorization: Bearer {credentials.iotex_api_key}
Content-Type: application/json
Timeout: connect=10s, read=30s
```

**Обробка відповіді:**
```ruby
zk_proof_ref = body["proof_id"] || body["receipt_id"]
raise VerificationError if zk_proof_ref.blank?
log.update!(verified_by_iotex: true, zk_proof_ref: zk_proof_ref)
ChainlinkDispatchWorker.perform_async(telemetry_log_id, created_at_iso)
```

**Ідемпотентність:** `return if log.verified_by_iotex?` в воркері.

> **`hardware_signature` чесно:** primary = **Ed25519** окремим Iotex-seed (HKDF `derive_iotex_seed`, domain separation від AES/K_seed) — це **master-backed** (L0 custodial у ladder нижче), не device-bound. SHA256-fallback існує лише для legacy/dev і **fail-closed** у production / `WEB3_STRICT_MODE` (метрика `W3BSTREAM_SIGNATURE_FALLBACK_TOTAL`, S6.13).

---

### Trust-origin ladder — L0 → L1 → L2 [📐 КАНОН trust-походження]

> **One-Home:** це канонічний дім **trust-походження телеметрії** (наскільки криптографічно доведено, що дані прийшли від реального дерева). SE/крипто-частина (SE050, slot-map) — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security); L2-механізм — §E.60 нижче; залишки/міграція — [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker). Інші доки реферять цю секцію, не дублюють ladder.

**Чесна теза:** «дані з фізичного дерева» — це **мета (true-DePIN North-Star)**, а не сьогоднішній стан. Доказ-походження сходить трьома рунгами, і **зв'язуюче обмеження — ЕНЕРГІЯ, не крипта** (дерево має афордити передати підпис).

| Рунг | Хто підписує | Що доводить | Чого НЕ доводить | Гейт | Статус |
|------|--------------|-------------|------------------|------|--------|
| **L0** custodial | backend (HKDF-derived seed — `w3bstream_verification_service`) | цілісність pipeline + прив'язка до on-chain peaq DID (master-backed) | фізичне походження (backend сам генерує підпис) | — | **зараз** |
| **L1** Queen-attestation | Королева (software-Ed25519, Monocypher; сім'я `EDSK` у Protected Flash — генерується фабричним хостом, **НЕ HKDF-від-master**, інакше backend міг би підробити; backend-verify проти `HardwareKey.ed25519_public_key_hex` — той самий ключ-реєстр, що M2M-auth) | crypto gateway-origin: дані пройшли крізь **реальну** Королеву, не підроблені backend'ом / injection; + integrity CBC-батча (до L1 він був malleable — без MAC) + anti-replay у nonce-вікні | per-tree authenticity (оператор контролює Королеву); replay після nonce-TTL-вікна | — (не gated на анкер/енергію/SE; Queen на LiFePO4) | 🟡 **shipped 2026-06-07** (firmware sign + backend verify + host/RSpec golden-parity; wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)) **+ HIL e2e soft-verified 2026-07-02** (`queen_simulator` signed-режим → повний worker-ланцюг до БД-маркерів, `spec/integration/qatt_hil_e2e_spec.rb`). **Той самий механізм атестує й окремий device-event canary-канал** (SEC.21, тег `SLKN-QEVT1` — [`03_05 §2.2а`](03_05_Hardware_Symmetric_Crypto_and_Security)), не лише телеметрійний батч. 👤 bench-residual: EDSK-flash + e2e на кремнії |
| **L2** per-tree device-voice | **дерево саме** (SE050 non-extractable Ed25519, щотижневий Merkle-корінь) | повне device-origin, **операторо-непідробне** («голос дерева») | — | анкер-TRL + енергія (1 TX ≈ 21.8 мДж SF9 +14dBm; weekly Merkle-корінь амортизує підпис ≈3.1 мДж/добу → влазить у Scenario C margin +33.6; daily-cadence = відкритий energy-⚖️ — не «39 мДж→Scenario D» [deprecated +22dBm], бо cold-boot/headroom поза цим числом; повний бюджет [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) + SE050 populate | **North-Star** (механізм = §E.60 + [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)) |

> **Крипта доповнює, не замінює:** L0–L2 доводять, що голос **дерева** і **цілий**; але **ЗВТ-метрологія** (STK.5) доводить, що голос **точний** (legal carbon) — 🏠 **внутрішній бюджет цієї точності рахує модель `tools/firmware/uncertainty_budget.rb`** (pure Ruby, `--assert` = HARD-гейт `docs.yml`; канон посилається сюди, не restate'ить числа): у робочій точці Variant C (Δt=1.77 год) комбінована `u_c ≈ 9%`, розширена `U(k=2) ≈ 18%`, і **89% дисперсії дає одна складова — `delta_t`, підсилений відображенням `m(Δt)` у ×3.0**. ⚠️ **Точність тут є функцією РОБОЧОЇ ТОЧКИ, а не лише приладу:** біля швидкого краю `U ≈ 5%`, біля повільного — `≈ 30%`, тобто енергетичний оптимум (Variant C обрано за [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power) як energy-positive) і метрологічний оптимум **не збігаються**, і це ⊥ треба назвати метрологу першим. ⛔ Ланцюг бюджету зупинено на `SCC`: крок `SCC → tCO₂` (2000:1) — облікова конвенція, не вимір, тож інструментальної невизначеності не має за побудовою. ⚠️ Дрейф-складові є **апріорними межами при нулі виміряних значень** ([ARCH.84] — писачів калібрувальних колонок у дереві немає), а **slashing** ([`05_05 §3`](05_05_Slashing_and_Risk_Policy)) робить брехню **дорогою**: у чинній Моделі A слеш падає на ту саму організацію, що фінансує кластер, тож skin-in-game дає вертикальна інтеграція, а не bond (⚫ `operator-bond`/BIZ.13 відкликано ⚖️ 2026-08-24 разом із Моделлю B — [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy)). 🔴 Третя нога при цьому **неповна**: у Моделі A бенефіціар є ще й свідком фізичної роботи, тож ціна брехні тримає лише в парі з правилом «атестатор ≠ бенефіціар», чия форма ще не обрана ([`00_07`](00_07_Action_Plan_Tracker) E.20). Трійця (origin + accuracy + skin-in-game) = довірений RWA. Жоден рунг ladder не знімає потреби у ЗВТ та економічному шарі.

> **Чому енергія, а не крипта, — гейт L2:** 21-байтний LoRa-кадр не має місця на підпис (Ed25519 = 64 Б) → per-record device-підпис неможливий; рішення — періодичний **Merkle-корінь** (§E.60), що амортизує один підпис на багато записів. Cadence голосу = скільки енергії дерево зібрало (сильніше дерево говорить частіше).

---

### 🔬 E.60 — Merkle CID-witness: bidirectional integrity bridge Polygon ↔ Filecoin

> **Статус:** ✅ leaf-рівень (2026-06-03) — `Filecoin::CidGenerator` (детермінований CIDv1: codec raw + sha2-256 → base32 multibase, golden-vector проти `ipfs add --raw-leaves --cid-version 1`) + content-CID guard у потоці архівації AuditLog: `ArchiveService` вбудовує самоописовий `content_cid`, `VerificationService` незалежно перераховує його (локально vs віддалено) і fail-fast при розбіжності → детект ex-post підміни архіву. ✅ **Фаза 1б SHIPPED 2026-07-19** — Polygon `archive_root`-нога жива (mint-anchored батч → `mint(bytes32)` → пін артефакту → стемп листя; механіка нижче). Трекер: [`00_07` — E.60](00_07_Action_Plan_Tracker).

> **🧭 Архітектурний контракт (ARCH.12 × E.60 × L2; Фаза 1а SHIPPED 2026-07-19).** Ця секція — **One-Home leaf-формули** (нижче) і структури Merkle-кореня для всіх трьох застосувань. (1) **Паралель, не вкладеність:** E.60 `archive_root` (Polygon, per-batch, archive-integrity) і тижневий `state_root` (Eth L1, [`05_04`](05_04_Ethereum_L1_State_Anchor) ARCH.12, supply-finality) — **два незалежні якорі**, що ділять ОДИН `MerkleTree` primitive + цю leaf-формулу; нуль крос-чейн зчеплення. (2) **leaf = Z** (не λ — λ many-to-one → слабший DCI, Beyond-TRL-9 [`03_04 §5`](03_04_mruby_Lorenz_Attractor)). (3) **hash = sha256** (One-Home з anchor + Filecoin CID; keccak/OZ-`MerkleProof` — upgrade-path лише за on-chain-verify споживача, YAGNI). (4) Примітив **ієрархічний** (cluster-subtree → root) — мапиться на L1/L2/L3 ([`00_07` ARCH.1](00_07_Action_Plan_Tracker)) і не впирається у scale ([`00_07`](00_07_Action_Plan_Tracker) ARCH.52). L2 device-voice clawback-policy при mismatch — [`05_05 §3.3`](05_05_Slashing_and_Risk_Policy).
>
> **✅ Фаза 1а (перший споживач = ISO-звіт/MRV.1, founder 2026-07-19):** примітив `lib/merkle_tree.rb` SHIPPED (RFC-6962 domain-sep 0x00/0x01 · promotion непарного вузла · hash-of-hex · двоярусність = композиція verify×2 у споживачах, примітив ярусів не знає) + **код-дім leaf-формули = `Mrv::TelemetryLeaf`** з піненою серіалізацією скалярів: `device_uid = tree.did` (`Tree#device_uid` НЕ існує — did під `attr_readonly`, лист не «переїжджає»), `z_value = BigDecimal#to_s("F")` (plain fixed-point, НЕ scientific-notation; NULL → JSON null — рядок ніколи не виключається), `bio_status` = сирий enum-integer (rename-proof), `created_at = utc.iso8601(6)`; `LEAF_VERSION = 1` (зміна формули = bump). Живі споживачі: Eth-L1 `state_root` ([`05_04 §Merkle`](05_04_Ethereum_L1_State_Anchor)) + mint-lineage вікна (MRV.1) + Polygon `archive_root` (Фаза 1б нижче — реюз leaf-формули 1:1, «1 batchMint = 1 батч» істинне ЗА КОНСТРУКЦІЄЮ mint-anchored осі, не перегрупуванням collector'а).
>
> **✅ Leaf-guard озброєно (2026-07-04):** `FilecoinVerificationSweepWorker` (cron 04:40 UTC, queue `low`) кличе `VerificationService#verify!` двома вибірками — свіжо-заархівовані (24h-вікно, кожен архів звірено хоч раз) + **випадкова вибірка старших** (ex-post підміна можлива будь-коли — самі свіжі не покривають threat-model). Mismatch → ERROR-лог + `silkennet_filecoin_verification_failures_total{reason=cid_mismatch|chain_hash_mismatch}` ([`06_03 §2.8`](06_03_Prometheus_Observability)); integrity-fail не «лікується» retry, gateway-флейк = unreachable (не failure). Вибірка старших — `ORDER BY RANDOM()` O(n) `[transitional]`, апгрейд-шлях TABLESAMPLE при мільйонах архівів.

**Проблема (data-integrity gap):** Раніше Filecoin/IPFS pin відбувався **після** мінту в Polygon — блокчейн-транзакція не мала криптографічного зв'язку з архівом. Зловмисник міг ex-post підмінити archive у Pinata (новий CID), і ніхто би не помітив, що SCC-token посилається на інший набір даних.

> **⚠️ Чому batch-CID НЕ може бути witness для per-device ZK-proof:** W3bstream доводить ZK-факт для **окремого** пристрою (`device_uid`, його Z). Якщо witness — це CID цілого batch (з `telemetry_log_ids` багатьох дерев), то: (а) CID змінюється, щойно в batch потрапляє будь-який інший лог; (б) per-device proof з batch-CID не доводить криптографічно, що payload **саме цього** дерева включений в архів — лише що пристрій «знав» CID.

**Рішення — Merkle-дерево (✅ Фаза 1б SHIPPED 2026-07-19, mint-anchored вісь):** батч ≔ **union lineage-вікон tx'ів одного мінт-диспатчу** (реюз MRV.1-вікон 1:1); листя = per-record CID (leaf-формула вище); корінь `archive_root` їде в `mint(bytes32)` і пінить артефакт. «1 batchMint = 1 телеметрія-батч» істинне за конструкцією — intake-шлях (Крок B, W3bstream per-log) НЕ чіпається.

**Механіка (код-доми: `Mrv::TelemetryArchiveBatchService` + `TelemetryArchiveBatchWorker` + модель `TelemetryArchiveBatch` — [`04_01`](04_01_Data_Models_and_Entities)/[`04_02`](04_02_Business_Logic_and_Services)):**
- **Побудова** (у `BlockchainMintingService`, per token-group, ПІСЛЯ KYC/SEC.13/circuit-фільтрів, ПОЗА oracle-локом): union вікон через `Mrv::LineageWindow` у **глобальному порядку `(created_at, id)`** → `archive_root = MerkleTree.root(leaf_cids)`. Batch-row + **set-once** `blockchain_transactions.archive_batch_id` для ВСІХ tx — в одній транзакції зі звіреним member-set (root-set ≡ bind-set СТРОГО): **partial-bind** (конкурент забрав частину tx між читанням членства і bind'ом) → rollback усього + до двох проходів перечитування, друга гонка поспіль → `build_failed` (fail-open); `create_or_find_by(archive_root, token_type)` → конкурентні build'и конвергують; re-dispatch групує по членству і реюзає stored root; transact-цикл — **per-підгрупою** («один on-chain виклик = один root» фізично, bisect у межах підгрупи), rescue живе пер-підгрупою (збій пізньої групи не чіпає вже-sent ранню), **dispatchable-фільтр** виключає tx у `:sent`/`:manual_review` (retry після часткової multi-групової відмови не сміє re-flip'ити їх — double-mint guard).
- **Контракти:** `mint`/`batchMint` +`bytes32 archiveRoot` **симетрично SCC + SFC** (founder-рішення 2026-07-19 — один Ruby ABI, нуль per-token гілок; SCC-alias `mintForTree` несе той самий параметр — SFC такого entry-point не має, він кластерний); події `CarbonMinted`/`ForestMinted` +**indexed** archiveRoot (topic-lookup за root) + subgraph-поле.
- **Пін** (`TelemetryArchiveBatchWorker`, первинний enqueue при створенні; backstop = `FilecoinReconcileWorker`): rebuild артефакту **З ВІКОН** (ніколи зі стемп-фільтра `archive_root` — у стемп-щілині набір був би неповний) → звірка кореня → **стемп** `telemetry_logs.{archive_root, merkle_leaf}` (raw-SQL VALUES-join; seal-guard моделі тримає AR-шлях мутацій, sweeper-нога `FilecoinVerificationSweepWorker` семплить raw-шлях) → пін JSON-артефакту (**Pinata IPFS pinning — чесно НЕ Filecoin-deal**; авторитет мосту = корінь on-chain, не hosting) → CAS-термінал. Розбіжність кореня при живих логах → стан `mismatch` (integrity-алерт + runbook [`06_08 §4`](06_08_Resilience_and_Failover_Policy); **НЕ** `manual_review` — money-периметр недоторканий); листя < leaf_count (дроп партицій) → `retention_expired`; батч без tx → `superseded`. Збій build → `build_failed`-слід (NULL-root, reason, tx_ids) БЕЗ біндингу + мінт їде zero32 (fail-open: money liveness > optional witness). **Repair-нога** (воркер на `build_failed`): пізній rebuild незабраних tx вдався → `repair!` → `pending` → пін (root off-chain-only — легально, «zero32 = без клейму»); неможливий (tx розібрані / вікна порожні) → `abandon_repair!` → `superseded` (вихід із reconcile-скоупу).
- **Семантика кореня:** root = свідок evidence-набору **ДИСПАТЧУ** (N:1): bisect-/individual-/partial-KYC-мінти несуть той самий root; вікна не-мінтованих tx у бандлі легальні; insurance/celo/burn-tx у змішаному слайсі = член батчу з порожнім внеском. `bytes32(0)` = **«без witness-клейму»** (windowless-диспатч або build-збій), НЕ «порожньо»; zero32-мінт при непорожніх персистованих вікнах = інцидент (метрика+алерт). Перерахунок root із БД ПІСЛЯ піну = діагностика, не істина (істина = артефакт + chain). `ForestMinted(root)` = MRV-witness, **НЕ carbon-клейм** (токен-семантика живе в токені).
- **Верифікація:** артефакт самоописовий (leaf-payloads + leaf_cids + per-tx window-tuples + tree_did + tax_rate + verification_instructions) → офлайн `scripts/verify_archive_bundle.rb` (сіблінг lineage-верифікатора): leaf-CID + корінь у порядку масиву + **window-binding** (кожен лист ∈ рівно одне вікно свого дерева — smuggled-leaf/overlap детекція). Issuer-asserted (чесно задекларовано в артефакті І скрипті): amount'и (growth_points у leaf v1 НЕМАЄ), повнота набору, root→ipfs_cid discovery.

**Що лишається неархівованим (чесна межа):** телеметрія поза вікнами диспатчів — дерева нижче mint-порогу, хвіст після останнього мінту, неактивні дерева. Тижневий `state_root` (гілка А) її **АНКОРИТЬ** (hash на Eth-L1, всі логи кластерів), але availability-ноги не має — впаде ретеншн, ці якорі стануть вакуумними. Weekly-archive нога = 🔗-gated founder-рішенням 2026-07-19 (свідомо чекаємо compliance-вимогу; [`00_07`](00_07_Action_Plan_Tracker) E.60-residual). (**Паралельний** якір тому самому `MerkleTree` primitive — тижневий state-root [`05_04`](05_04_Ethereum_L1_State_Anchor) ARCH.12: окремий чейн/таймскейл, не вкладений — архітектурний контракт вище. W3bstream/ZK-вісь Кроку B споживатиме той самий leaf/root — майбутній L2-рунг.)

---

### Крок C: Oracle-маркування (Chainlink demoted — ARCH.53)

**Тригер:** `ChainlinkDispatchWorker.perform_async` з `IotexVerificationWorker`

**Файли:**
- `app/workers/chainlink_dispatch_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/chainlink/oracle_dispatch_service.rb`

**Статус:** ⚪ Demoted **[ARCH.53]** — on-chain `sendRequest` вилучено (LINK-cost за callback, що не прилетить: DON-нога unwired, tx_hash≠requestId). `dispatch!` = local correlation-marker, без RPC; єдиний ENV Chainlink-родини = `CHAINLINK_HMAC_SECRET` (callback-endpoint). On-chain гілка (Router ABI registry + bytecode probe + payload-builder) воскресає з git при замиканні PATH 1. Огляд моделі довіри — «Чесна рамка» вище + [`05_01` картка №11](05_01_Multichain_Architecture).

**Guard-перевірка:**
```ruby
raise DispatchError unless @log.verified_by_iotex?
```

**Що робить:**
```ruby
request_id = "chainlink-req-#{SecureRandom.hex(16)}"  # local correlation-marker
# oracle_status — enum з prefix (oracle_status_dispatched?, oracle_status_fulfilled? тощо)
log.update!(chainlink_request_id: request_id, oracle_status: "dispatched")
```

Маркер — dedup-ключ Solana-винагород ([ARCH.51]) + idempotency-guard dispatch/callback-шляхів; тому колонка жива й після демоуту. Демоут-інваріант пінить тест: dispatch не торкається `Web3::RpcConnectionPool`.

**Ідемпотентність:** `return if log.chainlink_request_id.present?` в воркері.

---

### Крок D: Oracle Callback — ⚪ latent [ARCH.53]

**Тригер:** `POST /api/v1/oracle_callbacks` (сьогодні не прилітає — DON unwired, dispatch = local marker; endpoint live для майбутнього PATH 1 / manual-fulfillment)

**Файл:** `app/controllers/api/v1/oracle_callbacks_controller.rb`

**Авторизація:** `skip_before_action :authenticate_user!`
— машинний ендпоінт (без сесійної автентифікації).

**Пошук TelemetryLog з partition pruning** — делегуванням у One-Home, не власною арифметикою:
```ruby
log = TelemetryLog.where(chainlink_request_id: params[:chainlink_request_id])
                  .partition_pruned(params[:created_at], metric_caller: "OracleCallbacksController")
                  .order(created_at: :desc).first!
```

> 🔴 **Тут доти стояла точна рівність** (`where(created_at: Time.iso8601(params[:created_at]))`) — саме та форма, яку [`S6.16`](04_01_Data_Models_and_Entities) винищив із коду 2026-08-07: ISO-8601 несе СЕКУНДИ, колонка — мікросекунди, тож збіг можливий лише випадково, і промах на цьому шляху ТИХИЙ. Прунити вона таки прунить — не знаходить. Після зачистки коду цей приклад лишався **останнім екземпляром забороненої форми в репо**, тобто канон учив копіювати дефект. Клас на майбутнє: коли правило винищує форму, свіп мусить іти й по ПРИКЛАДАХ у доках, а не лише по `app/`.

**Успішний callback:**
```ruby
log.update!(oracle_status: "fulfilled")
MintCarbonCoinWorker.perform_async(log.id_value, log.created_at.iso8601(6))
SolanaMicroRewardWorker.perform_async(log.id_value, log.created_at.iso8601(6))
```

**Невдалий callback:**
```ruby
log.update!(oracle_status: "failed")
```

---

### Крок E: EVM Мінтинг SCC/SFC на Polygon

**Файли:**
- `app/workers/mint_carbon_coin_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/blockchain_minting_service.rb`

**Trustless Guard Clauses (oracle-гілки — лише при flow з telemetry_log):**
```ruby
raise "Security Breach: Data not verified by IoTeX"               unless telemetry_log.verified_by_iotex?
raise "Security Breach: Chainlink Oracle consensus not fulfilled"  unless telemetry_log.oracle_status_fulfilled?  # enum method
# TokenomicsEvaluatorWorker без log — оптимістичний мінт: growth_points зараховані
# credit! ДО/паралельно verify (НЕ downstream від нього), oracle-gate НЕ діє на
# tokenomics-шляху (anti-fraud = ex-post clawback) → §Модель довіри + ARCH.53.

# [KYC.1] KYC-гейт діє на ОБОХ шляхах, per-tx SKIP (S2 — не raise на весь батч;
# skipped tx лишається :pending до верифікації). Гейт = статус БЕНЕФІЦІАРА адреси:
@wallet_mapping.select { |_id, tx| !tx.wallet.kyc_approved_for_minting? }  # → skip
# Wallet#kyc_approved_for_minting?: власна адреса → власний hadron_kyc_status;
# custodial (без власної адреси, мінт на адресу організації) → успадковує
# organizations.hadron_kyc_status. Approval-шлях: біндинг/зміна crypto_public_address
# (Organization АБО Wallet) → after_commit → HadronKycVerificationWorker →
# HadronComplianceService (dev/no-key = simulate-approve; prod strict = реальний API);
# зміна адреси скидає статус у pending (KYC чіпляється до адреси, ре-верифікація).
# [ARCH.65] after_commit-enqueue разовий + retry:5 без exhausted-hook → Hadron-простій усі
# 5 = pending НАЗАВЖДИ (тихий mint-skip); HadronKycReverifyWorker cron (:50) доверифіковує
# застряглі pending (auto-heal, дім 06_08 §2.2).
```

⛔ **Преміса цього блоку СПРОСТОВАНА [ARCH.118 · ARCH.119, 2026-09-04], і механіка від того не змінилась — змінилось, що вона ЗНАЧИТЬ.** Модель була «Hadron-простій», вимір дав **неіснування вендора**: `Polygon::HadronComplianceService` є єдиним рантайм-писачем `hadron_kyc_status = "approved"`, а адресата в нього немає. Отже «auto-heal» щогодини переозброює драбину, якій нема куди дійти, і «тихий mint-skip» є не рідкісним крайовим випадком, а **постійним станом кожного custodial-бенефіціара**. Присуд про лік — [`00_07`](00_07_Action_Plan_Tracker) `ARCH.119` (⚖️ founder).

**Oracle Balance Check:**
```ruby
balance = client.get_balance(oracle_key.address)
raise "🚨 Критично низький баланс Оракула" if balance < 0.05 * (10**18)  # 0.05 MATIC
```

**Rate Limiting:**
```ruby
Sidekiq::Limiter.window("web3_rpc", 50, :second, wait: 5)  # 50 RPC/sec global
```

**Мінтинг:**
- Одиночний: `client.transact(contract, "mint", to, amount, identifier, root_arg)`
- Пакетний: `client.transact(contract, "batchMint", recipients[], amounts[], identifiers[], root_arg)`
- Dynamic Tax: 2% до `DAO_TREASURY_ADDRESS` (якщо `insurance_pool_requires_funding?`)

**Solidity ABI контракту:**
```json
[
  { "name": "mint",      "inputs": ["address to", "uint256 amount", "string treeDid", "bytes32 archiveRoot"] },
  { "name": "batchMint", "inputs": ["address[] recipients", "uint256[] amounts", "string[] treeDids", "bytes32 archiveRoot"] }
]
```

> ⚠️ **`archiveRoot` — четвертий вхід ОБОХ функцій, і доти його тут не було [ARCH.117].** Розходження стояло за пʼять рядків від власного спростування: сусідній рядок «Одиночний» уже друкував `root_arg` як четвертий аргумент виклику. Ціна обмежена (хибний селектор ревертить fail-closed — монет не втрачає), але **E.60-свідок `archiveRoot` зникав із задокументованого інтерфейсу**, тобто саме та ланка, що привʼязує мінт до архівного кореня. 🔴 **Гейт `solidity_signature_arity_check` тут PASS, і це не збій, а його оголошена форма:** він шукає токен `mint(` з типами, а JSON-запис `"name": "mint"` арності не несе взагалі — тобто **зона його сліпоти ширша, ніж називає власна шапка** (там перелічені flow-діаграми й `transact(`-сайти, JSON-ABI не названий). Після будь-якої зміни сигнатури цей блок звіряють руками.

**Rollback:** `MintingRollbackService.call(transactions:)` при вичерпанні 10 retry `BlockchainConfirmationWorker`
через `sidekiq_retries_exhausted` (~15-20 хвилин поллінгу мемпулу) — покриває **confirmation-failure** (tx застрягла в мемпул-лімбі). **[ARCH.45]** broadcast↔DB crash-window (on-chain пройшов, DB-запис впав до фіксації) — окремий клас, закритий durable intent-marker + `unsettled_within` reconcile-guard (Solana payout / burn / Etherisc; [`04_02 §4/§10`](04_02_Business_Logic_and_Services)).

---

### Крок F: Solana Мікро-Винагорода (паралельно з EVM)

**Файли:**
- `app/workers/solana_micro_reward_worker.rb` — queue: `web3` (prio 7), retry: 3
- `app/services/solana/minting_service.rb`

**Статус (Wiki 05_01):** ✅ Real — `sendTransaction` з Ed25519 підписом.

**Oracle Balance Guard:**
```ruby
verify_oracle_balance!(fee_payer_pubkey)
# raises при balance < MIN_ORACLE_BALANCE_LAMPORTS (0.05 SOL = 50M lamports)
```

**Розрахунок:**
```ruby
base  = 10_000          # 0.01 USDC у lamports
bonus = growth_points * 100   # 100 lamports / growth_point = 0.0001 USDC
total = base + bonus    # max: 10_000 + 62×100 = 16_200 lamports = 0.0162 USDC
# Stored max = 62 (Wire 5-bit max 31 × backend ×2 upscale, FW.29-PACK).
# Solana::MintingService ОЧІКУЄ growth_points у stored-діапазоні 10..62.
```

**Trustless Guards:** Ідентичні до EVM (`verified_by_iotex?` + `oracle_status_fulfilled?` — enum method).

---

## Усі Шляхи до `Wallet#lock_and_mint!` (Guard Inventory) [DOC.7]

> **Контекст:** `Wallet#lock_and_mint!(points, threshold, token_type)` — атомарна операція з `pessimistic_lock`, що конвертує `growth_points` у SCC (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)). Схема нижче перелічує **п'ять шляхів** money-тракту з їхніми guard chain'ами. ⊕ **Дротовані спостерігачі money-тракту (2026-08-29):** `sn-alert-mint-chunk-errors` — per-wallet збої, ПРОКОВТНУТІ `EvaluateTreeBatchWorker` у `rescue StandardError` (джоба звітує успіх, retry немає, DeadSet порожній); `sn-alert-lineage-root-failed` — `attach_lineage_root` упав, мінт пройшов, `telemetry_merkle_root` лишився NULL, тобто **кредит виданий без witness-клейму**. ⚠️ Другий інкрементується ЛИШЕ в `rescue`: порожнє вікно віддає `nil` і проходить БЕЗ лічби, тож його зелене НЕ означає «доказ на місці» ([`00_07`](00_07_Action_Plan_Tracker) INF.26, відкрита ⚖️ про семантику порожнього вікна). ⚠️ **Але «викликають» тут завищення, і це виміряно `grep` по `app/`+`lib/` ([ARCH.94], 2026-08-12): сам метод має РІВНО ОДНОГО викликача — `EvaluateTreeBatchWorker` (PATH 2).** PATH 1 латентний за побудовою (oracle-callback не дротований — [ARCH.53]), PATH 3 звільняє резерв, а не конвертує, PATH 4 свідомо не торкається `balance`/`locked_balance` (нижче), тож перелік описує **периметр guard'ів money-тракту**, а не множину call-site'ів. Читай його так — інакше висновок «шляхів багато, отже інваріант перевіряється в багатьох місцях» хибний: інваріант конверсії сьогодні тримає одна функція й один її викликач. Раніше зв'язок між цими шляхами був розкиданий між [`04_02 §4`](04_02_Business_Logic_and_Services) (oracle path) та різними воркерами (tokenomics path). Ця секція — єдина точка істини; будь-який новий шлях повинен бути доданий сюди.

```
                                ┌─────────────────────────────────────┐
                                │  Wallet#lock_and_mint!(points,      │
                                │                       threshold,    │
                                │                       token_type)   │
                                │  • pessimistic_lock                 │
                                │  • atomic: locked += points         │
                                │    (RESERVE — balance untouched)    │
                                │            queue MintCarbonCoinJob  │
                                └──────────────┬──────────────────────┘
                                               ▲
        ┌─────────────────────────────────────┼─────────────────────────────────────┐
        │                                      │                                      │
   PATH 1                                  PATH 2                                  PATH 3
   Oracle-driven                           Tokenomics                              Slashing recovery
   (per-telemetry, hot path)               (hourly batch)                          (after burn rollback)
        │                                      │                                      │
   ▼                                      ▼                                          ▼
   MintCarbonCoinWorker          TokenomicsEvaluatorWorker            MintingRollbackService
   (web3_critical #6)            (default #5)                         (critical #3)
        │                                      │                                      │
   GUARDS:                       GUARDS:                              GUARDS:
   ✓ verified_by_iotex?          ✓ available_balance >= threshold     ✓ original burn TX confirmed
   ✓ oracle_status_fulfilled?    ✓ kyc_status == "approved"           ✓ rollback authorized by admin
   ✓ hadron_kyc_status==approved ✓ NOT in cooldown window              ✓ idempotency by tx_hash
   ✓ chainlink_request_id match  ✗ (does NOT need oracle)              ✗ (bypasses oracle)
   (raises if any fails)         (silently skips if any fails)         (raises + Sentry capture)

        │                                      │                                      │
        └──────────────────┬───────────────────┴──────────────────┬───────────────────┘
                           │                                      │
                    PATH 4                                  PATH 5
                    Solana micro-rewards                    Manual admin (super_admin only)
                    (parallel rail, NOT SCC)                (rake task, audit-logged)
                           │                                      │
                    SolanaMicroRewardWorker                MintingAdminController
                    (web3 #7)                              (admin/super_admin)
                           │                                      │
                    GUARDS:                                GUARDS:
                    ✓ wallet.solana_address present        ✓ Pundit policy: super_admin only
                    ✓ NOT main lock_and_mint! (parallel)   ✓ Confirmation token (re-typed)
                    ✗ (calls Solana::MintingService        ✓ AuditLog entry created
                       directly, NOT lock_and_mint!)
```

> **[SEC.13] `peaq_did_compromised` mint-skip** (cross-path guard у `BlockchainMintingService`, після `lock_and_mint!`): дерево з `tree.peaq_did_compromised?` **пропускається** (SKIP, не raise — одне скомпрометоване дерево не зриває весь батч; решта мінтиться) перед on-chain mint. Підроблений peaq signing-key міг би замінтити для фейкового DID. Застосовується до Path 1 + Path 2 (обидва через `BlockchainMintingService`); дім revocation-runbook — [`06_04 §5.4`](06_04_Secrets_Checklist).

### Інваріанти для всіх шляхів

| Інваріант | Path 1 | Path 2 | Path 3 | Path 5 | Контроль |
|-----------|--------|--------|--------|--------|----------|
| Pessimistic lock на Wallet | ✅ | ✅ | ✅ | ✅ | `Wallet#lock_and_mint!` сам бере lock |
| Idempotency (повторний виклик не подвоює) | ✅ за `chainlink_request_id` | ✅ за `evaluation_period_id` | ✅ за `original_tx_hash` | ✅ за `confirmation_token` | DB unique constraint |
| `BlockchainTransaction.aasm: pending` створено | ✅ | ✅ | ✅ | ✅ | `MintCarbonCoinJob` |
| Rate limit (per wallet, anti-DoS) | ✅ Sidekiq уніфікований | ✅ cron | ⚠️ unbounded (admin-driven) | ⚠️ unbounded | Sidekiq + Pundit |
| WEB3_STRICT_MODE respected (raises на missing Web3 ENV) | ✅ | ✅ | ✅ | ✅ | shared `web3_strict_check!` |

> **PATH 4 (Solana) НЕ викликає `lock_and_mint!`** — Solana — паралельна рейка з прямим SPL Transfer без локування growth_points. growth_points і SCC mint обробляються Path 1, Solana — окрема мікро-винагорода, що не торкається balance/locked_balance. **ОБИДВА Solana-шляхи** мають власну idempotency поза цією таблицею (Wallet-lock не застосовний): **[ARCH.45] batch** (поріг > 0) — durable intent-marker (`:pending`→`:sent`, signature до broadcast) + `reconcile_in_flight` + confirm-gated Kredis-settle; **[ARCH.51] per-event** (поріг 0, default) — sign-first `:pending` intent ДО broadcast + per-telemetry reconcile (`chainlink_request_id` + `unsettled_within`; `:not_found`→`manual_review`) замість колишнього broadcast-ПОТІМ-record double-pay ([`04_02 §10`](04_02_Business_Logic_and_Services)).

> **TokenomicsEvaluatorWorker bypass [S6.12] — фактичний інваріант:** Path 2 НЕ перевіряє `verified_by_iotex?` / `oracle_status_fulfilled?`. Це **навмисно**, але обґрунтування потребує точності:
>
> - `growth_points` зараховуються у `wallet.balance` через `Wallet#credit!` у `TelemetryUnpackerService.commit_telemetry` **до** проходження пакетом IoTeX/Chainlink. Тобто upstream-перевірка для Path 2 — це **AES-256-CBC decrypt CoAP batch (Gateway key) → AES-128-ECB decrypt per-record (Tree LoRa key) + `valid_sensor_data?`** (per-packet integrity perimeter, post-ARCH.42), а **не** повний oracle pipeline.
> - Path 1 (oracle-driven mint per-telemetry) і Path 2 (hourly tokenomics aggregate) — **окремі шляхи мінтингу для тих самих growth_points**: Path 1 мінтить за конкретним verified `telemetry_log`, Path 2 агрегує накопичений `wallet.balance`. Без розмежування — циклічна залежність "не можна нарахувати tokenomics-bonus, доки oracle не підтвердив сам bonus".
> - **Hadron KYC є справжнім security perimeter Path 2** — `BlockchainMintingService` per-tx SKIP (S2; tx лишається `:pending`) для будь-якого гаманця з `!kyc_approved_for_minting?` незалежно від присутності `telemetry_log`; гейт = статус **бенефіціара** адреси (власний або успадкований від custodial-організації — [KYC.1], Крок E). Це блокує ескалацію fake-`growth_points` (з compromised AES-key) у мінт через non-KYC wallet.
> - Spec coverage: `spec/services/blockchain_minting_service_spec.rb` → context "tokenomics flow without telemetry_log [S6.12]".
> - **Залишковий ризик (документований):** компрометація per-device LoRa AES-128 ключа конкретного дерева → fake `growth_points` зараховуються `Wallet#credit!` → Path 2 щогодини мінтить SCC якщо wallet KYC-approved. Mitigation track: per-device HKDF key provisioning (FW.1 / SEC.3) + **AES-128-CCM** з 8-byte MIC + Frame Counter (FW.2 post-ARCH.42) + Hash Ratchet KDF rotation (FW.17) — обидва P0 у roadmap до польового deploy.

> **Path 3 raises замість silent-skip:** Slashing rollback — фінансово-критична операція. Беззвучне ігнорування призвело б до асиметрії "burn застосовано, mint-rollback пропущено → дисбаланс supply". Тому будь-який guard fail у Path 3 → exception + Sentry.

---

## Схема Полів БД (Proof of Growth State Machine)

```
trees
  └─ peaq_did             :string  UNIQUE    "did:peaq:0x{40hex}"

telemetry_logs  [PARTITION BY RANGE(created_at)]
  ├─ z_value              :decimal           Lorenz Z (BigDecimal 18 precision)
  ├─ growth_points        :integer           [FW.29-PACK] stored 0..62 = wire bits [4:0] (0..31) × 2 backend upscale
  ├─ bio_status           :integer enum      0=homeostasis|1=stress|2=anomaly|3=vm_error
  ├─ verified_by_iotex    :boolean  NOT NULL DEFAULT false
  ├─ zk_proof_ref         :string            "proof_id" або "receipt_id" від W3bstream
  ├─ chainlink_request_id :string  INDEX     TX hash або stub request ID
  └─ oracle_status        :enum(string)  DEFAULT "pending"
                                   pending → dispatched → fulfilled | failed
                                   Rails enum з prefix: oracle_status_pending?, oracle_status_dispatched?, oracle_status_fulfilled?, oracle_status_failed?

Partial indexes (sparse, billions of rows):
  idx_telemetry_logs_oracle_dispatched  WHERE oracle_status = 'dispatched'
  idx_telemetry_logs_oracle_fulfilled   WHERE oracle_status = 'fulfilled'
  idx_telemetry_logs_oracle_failed      WHERE oracle_status = 'failed'
  index_telemetry_logs_on_chainlink_request_id

blockchain_transactions
  ├─ chainlink_request_id :string  INDEX    Audit trail on-chain ↔ off-chain
  └─ zk_proof_ref         :string           Незмінний ZK-доказ у TX записі
```

---

## Змінні Середовища та Credentials

| Змінна | Сервіс | Обов'язкова |
|--------|--------|-------------|
| `credentials.peaq_node_url` | `Peaq::DidRegistryService` | ✅ Так |
| `credentials.peaq_signing_key` | `Peaq::DidRegistryService` (Ed25519) | ✅ Так (raises `RegistrationError` при відсутності) |
| `credentials.iotex_w3bstream_url` | `Iotex::W3bstreamVerificationService` | ✅ Так |
| `credentials.iotex_api_key` | `Iotex::W3bstreamVerificationService` | ✅ Так |
| `ENV["CHAINLINK_HMAC_SECRET"]` | `OracleCallbacksController` (callback-endpoint; dispatch-секрети вилучено — ARCH.53) | ⚠️ PROD only |
| `ENV["ORACLE_MINTER_PRIVATE_KEY"]` | `BlockchainMintingService` (MINTER_ROLE, [E.2]) | ✅ Так (dedicated-only — legacy fallback retired, INF.22) |
| `ENV["ORACLE_SLASHER_PRIVATE_KEY"]` | `BlockchainBurningService` (SLASHER_ROLE, [E.2] — окремий ключ, blast-radius) | ✅ Так (dedicated-only) |
| `ENV["ORACLE_ETHERISC/PURO/KLIMA_PRIVATE_KEY"]` | Activation-gated aux-підписанти (PuroEarth/Etherisc/Klima) — легасі спільний `ORACLE_PRIVATE_KEY` RETIRED [INF.22]: guard-tripwire відмовляє значенню під старим ім'ям | При активації шляху ([`06_04 §2.1`](06_04_Secrets_Checklist)) |
| `ENV["ALCHEMY_POLYGON_RPC_URL"]` | `Web3::RpcConnectionPool` | ✅ Так |
| `ENV["CARBON_COIN_CONTRACT_ADDRESS"]` | `BlockchainMintingService` | ✅ Так |
| `ENV["FOREST_COIN_CONTRACT_ADDRESS"]` | `BlockchainMintingService` | ✅ Так |
| `ENV["DAO_TREASURY_ADDRESS"]` | `BlockchainMintingService` (Dynamic Tax) + `Insurance::ReserveGate` (INS.2) | ✅ Так — але use-сайти fail-SILENT (E.46 rescue → tax тихо off); гучність = boot-guard `Web3NetworkGuard.address_violations` |
| `ENV["SOLANA_RPC_URL"]` | `Solana::MintingService` | ✅ Так |
| `ENV["PROVISIONING_MASTER_KEY"]` [SEC.11] | `SilkenNet::SeedDerivation`, `HardwareKeyService`, `OtaHmacKeyService` (runtime-fallback; фабрична `Session` передає ключ параметром від `MasterKeySource` — SEC.3 DI, [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning)) | ✅ Так — без неї `SecurityError` (no SecureRandom fallback ANYWHERE; pre-prod hard cutover) |

> **[ARCH.47]** `ORACLE_MINTER_PRIVATE_KEY` і `ORACLE_SLASHER_PRIVATE_KEY` мусять резолвитися в РІЗНІ адреси: однакові ключі дали б їм один Kredis-lock `lock:web3:oracle:<addr>` → mint стопорив би time-sensitive slash (а `LockTimeout` там тихо обриває burn). Під `WEB3_STRICT_MODE` `Security::Web3NetworkGuard` boot-енфорсить розділення + відмовляє значенню під retired-ім'ям `ORACLE_PRIVATE_KEY` (canon B-02 — [`00_04`](00_04_Nature_as_a_Service_Contracts); INF.22).

---

## 🔬 SEC.11 — Lorenz Seed Provenance & Dual Computation Integrity

> **Cross-ref:** дизайн і threat model — [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning); сервіс — [`04_02` — SilkenNet::SeedDerivation](04_02_Business_Logic_and_Services#silkennetseedderivation--sec11); poetics — [`03_04 §2.1` , §3 Крок 1](03_04_mruby_Lorenz_Attractor); SEC.11 в трекері — [`00_07` — SEC.11](00_07_Action_Plan_Tracker).

### Чому це частина Proof of Growth, а не суто security task

`Wallet#lock_and_mint!` карбує SCC лише коли `bio_status == homeostasis` витримує ZK-верифікацію та oracle-консенсус. До SEC.11 атакер з знанням open-source формули Лоренца та публічного DID (їде відкритим текстом у `[DID:4]` префіксі LoRa-пакета) міг **підрахувати очікуваний Z для будь-якого дерева** і підробити телеметрію з валідним `status_byte`. `check_z_divergence!` мовчав, бо порівнював категорії (homeostasis/stress/anomaly), не саму величину Z — Float vs BigDecimal drift після 250 ітерацій Ейлера робив числове порівняння неможливим. Identifier-as-key антипатерн.

### Hard cutover (pre-prod, 2026-05-02)

| Шар | Зміна | Файл / артефакт |
|-----|-------|----------|
| Schema | Нові колонки `hardware_keys.lorenz_seed_hex` (NOT NULL), `telemetry_logs.lorenz_state_x/y/z`, `telemetry_logs.cold_start_flag` | `db/migrate/20260502090000_add_lorenz_seed_provenance_columns.rb` |
| Crypto core | `SilkenNet::SeedDerivation` — HKDF-SHA256 + HMAC-SHA256 + signed-unit-float unpack; raises `SecurityError` без `PROVISIONING_MASTER_KEY` (no fallback) | `app/services/silken_net/seed_derivation.rb` |
| Provisioning | `HardwareKeyService.provision` атомарно деривує AES key + K_seed одним викликом | `app/services/hardware_key_service.rb` |
| Attractor | Sole entry-point `Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, …)`; legacy `calculate_z(seed, …)` ВИДАЛЕНО | `app/services/silken_net/attractor.rb` |
| Unpacker | Per-tree dispatch: warm tail з попереднього `TelemetryLog.lorenz_state_*`, cold start з `K_seed/epoch_day` + `cold_start_flag = true`; persist tail | `app/services/telemetry_unpacker_service.rb` |
| Firmware | mruby `bio_contract.rb` єдина сигнатура `calculate_state(x, y, z, …)`; chaos_seed та DID-as-seed видалено | `firmware/bio_contracts/bio_contract.rb` |
| Parity | Host-test OpenSSL HKDF/HMAC ↔ `silken_sha256.h` на MCU (детерміновані вектори + 100-case fuzz mirror Ruby) | `firmware/test/test_seed_derivation.c` |

### Cold-start vs Warm continuation dispatch у `TelemetryUnpackerService`

```ruby
prev_tail = tree.telemetry_logs
              .where.not(lorenz_state_x: nil)
              .order(created_at: :desc)
              .first

if prev_tail
  # Warm path (норма) — дзеркалить firmware FW.6 RTC DR16-DR18 continuation
  x0, y0, z0 = prev_tail.lorenz_state_x, prev_tail.lorenz_state_y, prev_tail.lorenz_state_z
  cold_start = false
else
  # Cold path — лише після VBAT loss / провізіонування / повного reboot
  raise MissingLorenzSeedError unless tree.hardware_key&.binary_lorenz_seed.present?
  # [ARCH.41] Доба береться з моменту ПРИЙОМУ пакета (job-аргумент
  # `received_at`, зафіксований інтейком), а НЕ з `created_at` рядка й не з
  # `Time.now`: обидві останні величини рухаються разом зі СПРОБОЮ, тож
  # Sidekiq-ретрай через межу півночі UTC дав би іншу добу → інший (x₀,y₀,z₀)
  # → категоричний DCI-мисматч на чесному дереві. Пристрій деривує зі свого
  # RTC-дня, зафіксованого в момент передачі — прийом до нього найближчий.
  epoch_day  = received_at.utc.to_i / 86_400
  # ⚠️ Метод ПОЗИЦІЙНИЙ (`initial_state(seed_bytes, epoch_day = current_epoch_day)`),
  # не kwargs — доти цей блок описував іменовані аргументи, яких він не має.
  x0, y0, z0 = SilkenNet::SeedDerivation.initial_state(
                 tree.hardware_key.binary_lorenz_seed, epoch_day
               )
  cold_start = true
end

z = SilkenNet::Attractor.calculate_z_from_state(
      x0, y0, z0, temp_c, acoustic, metabolism_s, voltage_mv
    )

telemetry_log.update!(
  z_value:         z,
  lorenz_state_x:  Attractor.last_state[:x],
  lorenz_state_y:  Attractor.last_state[:y],
  lorenz_state_z:  Attractor.last_state[:z],
  cold_start_flag: cold_start
)
```

**Інваріант:** обидві сторони (Soldier mruby + backend Ruby) стартують з **байт-ідентичного** `(x₀, y₀, z₀)` для тієї самої пари `(K_seed, epoch_day)`. Daily epoch rotation (UTC, 86400 сек) синхронізована через FW.20 `CMD_TIME_SYNC` → forward secrecy ≤ 24 год.

### Ефект на Dual Computation Integrity

**До SEC.11** — `check_z_divergence!` категоричний (3-zone homeostasis/stress/anomaly): атакер з `Z_fake = 28.0` проходив. Tolerance band = ширина категорії.

**Після SEC.11** — обидві сторони мають однакову початкову точку, тому Float vs Float drift між ARM та x86 IEEE-754 за 250 ітерацій < 1e-12 (емпірично після FW.7 closure). `check_z_divergence!` зберігає категоричну невідповідність як safety net і отримує hook для числового tolerance band (`(server_z - device_z).abs > 0.001`) — flip під feature-flag після інструментального вимірювання реального drift у польових умовах. Атакер без знання `K_seed` не може передбачити очікуваний Z → fake-телеметрія falls within `< 0.001` band з ймовірністю ~`6/45000` → детекція ≈ 99.99%.

> **Свідомо НЕ робимо** (pre-prod, no field devices, no prototypes, no firmware in flight): `POST /provisioning/upgrade_seed` field-migration endpoint, TRL4 lab-mode response з `lorenz_seed` в JSON, SecureRandom fallback в `Rails.env != production`. SEC.9 (rotation `PROVISIONING_MASTER_KEY`) — окрема задача, не блокує SEC.11.

---

## 🔭 Хто контролює ВИБІРКУ — реєстр оракулів [ARCH.111]

**Питання цієї секції не «чи можна підробити показник», а «хто обирає, які дані показник узагалі побачить».** Це дві різні властивості одного об'єкта, і відповідь на першу не каже про другу нічого. Уся доказова постава пайплайну — подвійне обчислення, attestation, DCI, незалежні свідки — стоїть проти підроблених **значень**; проти **дібраної множини** не стоїть нічого, і це не пропуск інструментів, а їхня конструкція: гейти чесності судять ТВЕРДЖЕННЯ, ніколи популяцію, з якої воно виведене. Провенанс класу й підстава — [`05_05 §7`](05_05_Slashing_and_Risk_Policy).

⛔ **Найспокусливіша хибна відповідь — «додати другий оракул».** Другий оракул із тим самим контролером вибірки незалежності не додає: він подвоює свідчення однієї дібраної множини.

| Оракул / агрегат | Хто обирає вибірку | Що саме обирається | Стеля оголошена? |
|---|---|---|---|
| **dClimate / FIRMS** (`Dclimate::VerificationService`) | **ми** | точка (`EwsAlert#coordinates`) + вікно `FIRMS_WINDOW_DAYS` довкола `alert.created_at.to_date`. Отже **хто керує моментом алерту, керує сценою**: дата деривується з того, коли МИ помітили, не коли ГОРІЛО | ✅ константа з підставою + пін на обидві межі вікна |
| **Субграф TheGraph** (`subgraph/subgraph.yaml`) | **ми** | `eventHandlers` — предмет індексу є **емісія і спалення** (`CarbonMinted`/`TokenSlashed`/`ForestMinted`/`GovernanceSlashed`) **плюс РІВНО ОДИН виняток — `ProtocolParameters.ParameterUpdated`**, і критерій його входу названий: без історії ставки поле `ProtocolFinancials.totalMintedTax`, яке індекс УЖЕ публікує, зовнішньо неперевірне. Поза вибіркою СВІДОМО: `StateRootStored`, успадковані `RoleGranted`/`RoleRevoked`, `Paused`/`Unpaused`, увесь Timelock і Governor — вони публічні on-chain і читаються будь-яким експлорером без нашої участі, тож їх невключення є чесною **межею предмета**, не приховуванням. ⚠️ Отже «закон, за яким видали гроші», видно рівно в тій частині, що годує вже опубліковане число, і не видно в решті — реєстр стоячих повноважень має власний дім [`ARCH.112`](00_07_Action_Plan_Tracker) | ✅ шапка самого `subgraph.yaml` — оголошена межа + ⛔-критерій розширення («без якого ВЖЕ ОПУБЛІКОВАНОГО числа читач не може обійтись»); ⚠️ компілятор у CI = `OPS.34` |
| **Денний зріз здоров'я** (`InsightGeneratorService`) | **ми** | UTC-доба `AiInsight.reporting_date` + популяція = кластери з ≥1 `TelemetryLog` у вікні (`prefetch_cluster_baselines`) | ✅ ARCH.84 (мовчазне дерево/кластер дістає ЯВНИЙ `nil`, а не пропуск) + ARCH.100 (One-Home дати) |
| **Знаменник частки шкоди** (`DailyHealthRouter#witnessing_trees`) | **ми** | свідки доби ⊥ усі `active`. ✅ Інстанс, що **купив цей клас** — мовчання рахувалось свідченням про виживання | ✅ [`05_05 §7`](05_05_Slashing_and_Risk_Policy) |
| **Стан пулу / податковий предикат** (`Web3::Erc20Reader`) | **ми** | МОМЕНТ семплювання балансу скарбниці: значення кешоване вікном, тож предикат `taxing?` судить не «зараз», а «коли впало перше читання у вікні» | ✅ тут; одну правду на диспатч тримає memo `taxing?` ([`05_03 §Dynamic Tax`](05_03_Tokenomics_SCC_and_SFC)) |
| **Детектор обсягу мінту** (`Treasury::MonitorService`) | **ми** | ширина ковзного вікна `MINT_VOLUME_WINDOW`. ⚠️ Отже детектор відповідає на «чи була ГОДИНА з обсягом понад стелю», ніколи на «скільки СУМАРНО»: рівномірна над-емісія трохи нижче стелі невиразна для нього **назавжди**, хоч би якою була сума | ✅ тут (дві сусідні стелі — prune-межа й самореферентність вікна — оголошені в коді) |
| **MRV-бандл** (`Mrv::LineageReportService`) | **ми** | `from`/`to` викликача + склад `credits:` (лише виміряний ріст) | ✅ `VERIFICATION_INSTRUCTIONS` називає issuer-asserted половину поіменно |
| **Архів-бандл** (`TelemetryArchiveBatchWorker`) | **ми** | множина tx диспатчу (N:1 — вікна незамінчених tx присутні легально) | ✅ `VERIFICATION_INSTRUCTIONS` |
| **IoTeX / W3bstream** | — | вибірки немає: предмет — один лог, множини не обирає ніхто | н/д (латентний тракт) |
| **Chainlink** | — | dispatch = локальний маркер [ARCH.53], callback не підключений | н/д (латентний тракт) |

🔑 **Як читати колонку «стеля»:** ✅ означає, що вибір **оголошений** — у константі з підставою, в `VERIFICATION_INSTRUCTIONS` або в цьому рядку, — а не що він правильний. Оголошення — це все, що можна зробити машинно; **винесення вибору з-під власного контролю є присудом**, і два перші ратифіковано 2026-08-27 (`ARCH.111` §🗄️): вікно FIRMS лишається нашим, але їде В ЗАПИСІ (`dclimate_ref` несе останнім сегментом те саме вікно, яким питали), а набір `eventHandlers` винесено з-під дискреції й звужено до арифметично необхідного. ⛔ **Найспокусливіша хибна відповідь названа там же: другий оракул із ТИМ САМИМ контролером вибірки незалежності не додає** — він рахує одного птаха двічі. Нові рядки цієї таблиці судяться тим самим критерієм.

---

## 🕸️ Subgraph — зовнішня читацька поверхня [дім: OPS.36]

> ⚖️ **Оголошений ДІМ субграфної поверхні (founder 2026-08-30): ЦЯ секція, не власна сторінка** — попит на окремий док не виміряний, а субграф і є зовнішнім читачем саме цього пайплайна, тож його контракт живе поруч із трактом, який він індексує. Розкидане доти по [`05_01`](05_01_Multichain_Architecture) / [`05_03`](05_03_Tokenomics_SCC_and_SFC) / [`05_04`](05_04_Ethereum_L1_State_Anchor) / [`06_07`](06_07_CICD_and_Runbook_Index) / [`06_08`](06_08_Resilience_and_Failover_Policy) зводиться сюди вказівниками; факти, що належать СУСІДНІМ домам, лишаються там: природа мінта й префікси ідентифікатора (секція «Префікси» у [`05_03`](05_03_Tokenomics_SCC_and_SFC) — токеноміка; субграф — споживач) · CI-воркфлоу `CI · Subgraph` — [`06_07 §1`](06_07_CICD_and_Runbook_Index) · межі індексу, чотири тиші і `prune`-присуд — шапка самого `subgraph/subgraph.yaml` (носій у місці дії).

🔇 **Читач власного мовчання: субграф його НЕ МАЄ ЗА ПОБУДОВОЮ, і лік тут — ОГОЛОШЕННЯ, а не новий механізм** (⚖️ founder 2026-08-30). Платформа скрізь читає тишу як відсутність, ніколи як здоровʼя — `Tree.silent` / `Tree#fresh_signal?` є буквальним носієм тієї осі ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap); шевченкове «на всіх язиках все молчить, **бо благоденствує**» і є її іменем). Але субграфний аналог механізму **структурно неможливий**: пульс мусив би приходити з мережі, у якій субграф не індексує нічого. Тому чотири тиші оголошено текстом у шапці `subgraph/subgraph.yaml` (блок 🔇) — порожній індекс до деплою (закривається сама) · `StateRootStored` (структурна назавжди — якір в ІНШІЙ мережі) · порожній `ParameterChangeEvent` ≠ нульова ставка (genesis-ера = off-chain дефолт) · відсутність TAX-рядка ≠ звільнення (вісім untaxed-каналів ⊥ пул ⊥ fail-open ⊥ дефект — **чотири причини, один вигляд**). 🔑 Портативне звідси: коли поверхня не може мати вимірювача власної тиші, чесним ліком є названий перелік того, що її мовчання НЕ означає — інакше зовнішній читач (ESG-покупець, ISO/Verra-аудитор) прочитає порожнечу як твердження.

### Subgraph vs Контракт — Повна Матриця

| Event у subgraph.yaml | Подія у контракті | Статус |
|---|---|---|
| `CarbonMinted(indexed address,uint256,indexed bytes32,string,indexed bytes32)` | `CarbonMinted` | ✅ `treeDidHash` + `archiveRoot` (обидва bytes32, обидва indexed) |
| `TokenSlashed(indexed address,uint256,bytes32)` | `TokenSlashed` | ✅ Синхронізовано (contextHash — CONTRACT.1) |
| `ForestMinted(indexed address,uint256,indexed bytes32,string,indexed bytes32)` | `ForestMinted` (SFC) | ✅ Handler додано (S3.5) |
| `GovernanceSlashed(indexed address,uint256,bytes32)` | `GovernanceSlashed` (SFC) | ✅ Handler додано (S3.5; contextHash — CONTRACT.1) |

> ✅ SFC data source в `subgraph.yaml` стоїть на живій Amoy-адресі з 2026-09-01 (`startBlock` = блок деплою; нульова адреса = fail у `CI · Subgraph` з 2026-09-03). Mainnet-cutover — [`00_07`](00_07_Action_Plan_Tracker) DEPLOY-1 Фаза 2 (ex-S3.5): `network: polygon` + адреси Фази 2 + `graph deploy` у Studio.

🛡️ **Арність цих сигнатур гейтована** — `ruby scripts/solidity_signature_arity_check.rb` (HARD, `docs.yml`) звіряє КОЖЕН переказ параметричного списку в `docs/**` проти декларації в `contracts/*.sol`. ⛔ Стеля оголошена: гейт судить **лише кількість параметрів** — типи, порядок, імена й `indexed` лишаються на очах ревʼюера. Заведено [DOC-T.89] після того, як `archiveRoot` (E.60 Фаза 1б) прожив у контрактах і `subgraph.yaml`, а канон тримав чотирипараметричну форму у **двадцяти** місцях і ставив ✅ у цій самій матриці навпроти сигнатури, якої не вживає жоден бік — таблиця, що засвідчує згоду двох артефактів, є найвищим за довірою і найнижчим за доказовістю жанром канону (guard-craft #97), тож кожен її ✅ тримається гейтом, не собою.

---

## 📌 Статус пайплайну

> **One-Home:** відкриті блокери живуть у [`00_07`](00_07_Action_Plan_Tracker), не в каноні (00_06 §1). Для цього пайплайну:
> - **FW.8** — `CRITICAL_Z_MIN/MAX` firmware-hardcoded vs server per-species (раніше тут «BLOCKER-03» — невідповідність `bio_status`/`growth_points` firmware↔backend для не-сосни). OTA-дизайн — §4а вище; трекер — [`00_07` — FW.8](00_07_Action_Plan_Tracker) (Rails-сторона ✅, firmware-парсер host-tested+gated, persist Flash-KV; bench-residual).
> - **SEC.9** — master seed key може ще містити FIPS-197 тест-вектор → crypto-random перед польовим деплоєм ([`00_07`](00_07_Action_Plan_Tracker)).

**Закриті** (design-rationale у канон-домах + git-історії):
- AES-ключ hardcoded у прошивках → ✅ **FW.1** (per-device HKDF-LoRa-ключ у Protected Flash — [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security); SEC.9 — залишковий хвіст вище).
- Lorenz Float↔BigDecimal divergence + DID-as-seed антипатерн → ✅ **FW.7** (Float-as-numeric-mirror) + **SEC.11** (K_seed-derived cold start) — дизайн у секції «SEC.11» вище.

**Висновок:** пайплайн повністю реалізовано та покрито RSpec; backend-шар готовий до Mainnet, залишкові блокери — firmware-bench (FW.8 / SEC.9), трекаються в [`00_07`](00_07_Action_Plan_Tracker).
