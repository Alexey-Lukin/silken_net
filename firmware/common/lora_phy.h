// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lora_phy.h — [FW.61] Базлайн raw-LoRa P2P PHY-профілю Soldier↔Queen
 * (One-Home: обидві прошивки, HAL-глю та host-тести компілюють ЦЕЙ набір —
 * без копій; модель airtime над ним — tools/firmware/lora_airtime.rb).
 *
 * ЧОМУ цей файл існує. Semtech-драйвер модуляції НЕ дефолтить: `RadioInit`
 * (extern/subghz-phy/radio_driver/radio.c) ставить лише таймери/IRQ і
 * `SUBGRF_SetTxParams(RFO_LP, 0, …)` — тобто НИЗЬКОПОТУЖНИЙ PA на 0 дБм;
 * справжню потужність пише виключно `RadioSetTxConfig`, а SF/BW/CR/преамбулу
 * — `RadioSetTxConfig`/`RadioSetRxConfig`. Доти baseline-виклику не було
 * ЖОДНОГО (panic-шлях не рахується: він сам живе за `ARCH26_CAD_ENABLED`,
 * який у бойовій збірці нуль). Це сусід гочі «відновлюй базлайн», а не її
 * інстанс: ВІДНОВЛЮВАТИ БУЛО НІКУДИ — базлайн не існував як стан
 * (`firmware`-скіл гоча #1, нога «б»).
 *
 * Друга половина, дорожча за потужність: `SubgRf.RxContinuous` виставляє
 * ЛИШЕ `RadioSetRxConfig`, а `RadioInit` кладе його у `false`. Отже
 * Королевине «завжди слухає» (03_02 §1 — основа Проблеми Рандеву) без
 * цього виклику є RX-SINGLE, хоч би що казав `Radio.Rx(LORA_RX_INFINITE)`.
 *
 * Дім НОМІНАЛІВ — канон 03_05 §2.1 (профіль + airtime-таблиця); дім
 * енерго-сценарію, з якого взято SF і потужність, — 02_03 §9.8 Сценарій C
 * (єдиний energy-positive: +14 дБм @ SF9, +1.4 мДж/год). Цей заголовок є
 * оголошеним ДЗЕРКАЛОМ канону для компілятора; розходження ловить
 * `ruby tools/firmware/lora_airtime.rb --assert` (HARD у docs.yml).
 *
 * ⚠️ LDRO (LowDatarateOptimize) тут НЕ константа й не наш вибір: драйвер
 * виводить його сам — `1` лише при (BW125 ∧ SF∈{11,12}) або (BW250 ∧ SF12),
 * тобто при SF9/BW125 він `0`. Будь-яка формула airtime, що вшиває LDRO=1
 * (знаменник `4·(SF−2)` замість `4·SF`), описує НЕ наш тракт.
 *
 * ⚠️ ДВА виклики ділять ОДНУ пару структур драйвера (`SubgRf.Modulation
 * Params` / `SubgRf.PacketParams`). ⛔ Але ПОРЯДОК між ними НЕ є інваріантом,
 * і доти цей коментар стверджував протилежне: `RadioSetTxConfig` не пише
 * `SubgRf.RxContinuous` взагалі (його виставляє лише `RadioSetRxConfig`), а
 * решту полів обидва пишуть ОДНАКОВО — тож переставити їх безпечно. TX-перед-RX
 * лишається КОНВЕНЦІЄЮ заради однакової форми на двох вузлах, не вимогою
 * заліза. Справжня вимога порядку одна: sync word ПЕРШИМ (він кличе SetModem
 * усередині себе).
 *
 * ⚠️ Регуляторна половина ВІДКРИТА і цим файлом не закривається: +14 дБм у
 * 5-dBi антену Королеви ≈ 19 дБм e.i.r.p., а загальні умови НКЕК для SRD у
 * 863–870 МГц звіряються окремо (00_07 ARCH.24, 👤). Тут — те, що програмує
 * прошивка; чи це дозволено в ефірі, каже той пункт.
 */

#ifndef SILKEN_LORA_PHY_H
#define SILKEN_LORA_PHY_H

#include <stdint.h>

/* ── Канал ──────────────────────────────────────────────────────────────
 * 868.0 МГц — raw-LoRa P2P (02_05 §2.1). ⛔ НЕ 868.1/.3/.5: то канали
 * LoRaWAN-детуру Королеви (ARCH.34), і саме тому після кожного детуру
 * `Radio_Reinit_RawLoRa_868MHz()` вертає PHY сюди. */
#define LORA_PHY_FREQ_HZ               868000000u

/* ── Модуляція (Semtech-кодування аргументів SetTx/SetRxConfig) ──────── */
/* datarate: SF9 — Сценарій C 02_03 §9.8 (єдиний energy-positive). */
#define LORA_PHY_SF                    9u
/* bandwidth: 0 = 125 кГц (1 = 250, 2 = 500). */
#define LORA_PHY_BW                    0u
#define LORA_PHY_BW_HZ                 125000u
/* coderate: 1 = 4/5 (2 = 4/6, 3 = 4/7, 4 = 4/8). */
#define LORA_PHY_CR                    1u
/* bandwidthAfc — FSK-поле; для LoRa драйвер його ігнорує. */
#define LORA_PHY_BW_AFC                0u

/* T_sym = 2^SF / BW. При SF9/BW125 = 4096 мкс — та сама величина, на якій
 * стоїть CAD-преамбульна математика (cad_sniff.h тримає static-assert). */
#define LORA_PHY_T_SYM_US              (((1u << LORA_PHY_SF) * 1000000u) / LORA_PHY_BW_HZ)

/* Sync word: `false` = LoRa PRIVATE (0x1424). ⛔ Не оздоба й не дефолт —
 * це ЄДИНИЙ вимір PHY, який LoRaWAN-детур міняє НЕЗВОРОТНО для нас:
 * `LoRaMac` кличе `Radio.SetPublicNetwork(true)` → у чіп їде 0x3444, а
 * `Radio.Init` скидає лише RAM-прапорець (`SubgRf.PublicNetwork`), регістр
 * не чіпаючи. `RadioSetModem` переписує слово ЛИШЕ коли `Current !=
 * Previous` — після `Init` вони рівні, тож пропускає. Отже без явного
 * виклику Королева лишилась би слухати публічним словом, а Солдати шлють
 * приватним: вуха відкриті, тракт чужий. */
#define LORA_PHY_PUBLIC_NETWORK        false

/* ── Пакет ──────────────────────────────────────────────────────────────
 * Преамбула 8 симв — вона ж ЦІЛЬ обов'язкового відновлення після
 * PANIC-TX (cad_sniff.h `CAD_PREAMBLE_DEFAULT_SYMBOLS`, 02_03 §9.10 п.4). */
#define LORA_PHY_PREAMBLE_SYMBOLS      8u
/* fixLen=0 → explicit header (довжина їде в ефір; Королева маршрутизує
 * кадри ЗА ДОВЖИНОЮ — 16B control ⊥ 30B air ⊥ climate, 03_05 §2.1). */
#define LORA_PHY_FIX_LEN               false
#define LORA_PHY_CRC_ON                true
#define LORA_PHY_IQ_INVERTED           false
#define LORA_PHY_FREQ_HOP_ON           false
#define LORA_PHY_HOP_PERIOD            0u

/* ── TX ─────────────────────────────────────────────────────────────────
 * +14 дБм — Сценарій C (02_03 §9.6/§9.8). ⛔ НЕ +22: той сценарій списано
 * (негативний енергобаланс, 02_03 §9.5). */
#define LORA_PHY_TX_POWER_DBM          14
/* timeout драйвера, мс. [transitional] 0 успадковано з panic-шляху й
 * означає «без програмного TX-таймауту» — TX закриває TxDone-IRQ. Числа
 * тут не вигадуємо: скільки має бути, каже вимір TxDone-латентності на
 * кремнії → 00_07 FW.61 (👤 radio-bench). */
#define LORA_PHY_TX_TIMEOUT_MS         0u

/* ── RX ─────────────────────────────────────────────────────────────────
 * symbTimeout=0 → `SUBGRF_SetLoRaSymbNumTimeout(0)` = символьний таймаут
 * вимкнено (потрібне саме для безперервного слухання). payloadLen для
 * LoRa-RX драйвер ігнорує (ставить `MaxPayloadLength`) — 0 як маркер. */
#define LORA_PHY_RX_SYMB_TIMEOUT       0u
#define LORA_PHY_RX_PAYLOAD_LEN        0u

/* rxContinuous — ЄДИНЕ поле профілю, що різниться між вузлами, і різниця
 * несуча:
 *   Королева — `true`: always-on listener, апаратний `SUBGRF_SetRx(0xFFFFFF)`
 *     (03_02 §1, Проблема Рандеву);
 *   Солдат — `false`: обмежене RX-вікно `Radio.Rx(LORA_RX_TIMEOUT_MS)`,
 *     бо вухо коштує енергії (02_03 §9.6). */
#define LORA_PHY_RX_CONTINUOUS_QUEEN   true
#define LORA_PHY_RX_CONTINUOUS_SOLDIER false

#endif /* SILKEN_LORA_PHY_H */
