// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lora_phy_apply.h — [FW.61] ЄДИНИЙ шов, яким базлайн `lora_phy.h`
 * потрапляє у Semtech-драйвер. Соядат, Королева і host-тест кличуть ЦІ дві
 * функції — не свої копії тринадцяти аргументів.
 *
 * ЧОМУ окремий файл, а не ті самі рядки в `lora_phy.h`: той заголовок
 * СВІДОМО не знає про `Radio` — його включає `cad_sniff.h`, який компілюють
 * host-тести без жодного драйвера. Тут же `radio.h` потрібен, тож шов
 * винесено: pure-половина лишається pure, а залежність від вендора живе в
 * одному файлі, який включають тільки ті, хто справді програмує радіо.
 *
 * ⚠️ Порядок СЕРЕД TX/RX — конвенція, не інваріант: `RadioSetTxConfig`
 * `SubgRf.RxContinuous` не чіпає, а решту полів обидва пишуть однаково.
 * ⛔ Несучий порядок рівно один: **sync word ПЕРШИМ** — він кличе SetModem
 * усередині себе, і саме він відновлює те, що LoRaWAN-детур лишив у регістрі.
 */

#ifndef SILKEN_LORA_PHY_APPLY_H
#define SILKEN_LORA_PHY_APPLY_H

#include <stdbool.h>
#include <stdint.h>

#include "radio.h"
#include "lora_phy.h"

/*
 * Sync word — окремий виклик, бо він НЕ є аргументом ані TX-, ані
 * RX-конфігу, а drift сюди приходить ззовні: `RadioSetPublicNetwork(false)`
 * пише приватне слово БЕЗУМОВНО, тоді як `RadioSetModem` пропускає запис при
 * `Current == Previous` — рівно той стан, який лишає по собі `Radio.Init`.
 * ⛔ Кликати ПЕРШИМ у boot-і й у поверненні вух після LoRaWAN-детуру: без
 * нього решта профілю бездоганна, а приймач слухає чужу мережу.
 */
static inline void Lora_Phy_Apply_Sync_Word(void)
{
    Radio.SetPublicNetwork(LORA_PHY_PUBLIC_NETWORK);
}

/*
 * TX-половина базлайну. Змінних аргументів ДВА, і природа в них різна.
 * Потужність — стала РОЛІ (`LORA_PHY_TX_POWER_DBM_SOLDIER` ⊥ `_QUEEN`,
 * ⚖️ 2026-09-24): кожен вузол передає одне й те саме число завжди, як RX-
 * половина — свій `rx_continuous`. Преамбула — стала СТАНУ: ARCH.26 «останній
 * зойк» подовжує її, а відновлення передає сюди `LORA_PHY_PREAMBLE_SYMBOLS`.
 * Решта одинадцять не мають другого написання ніде в дереві — саме це й
 * робить відновлення повним за побудовою (`firmware`-скіл гоча #1, нога «в»:
 * часткове відновлення читалось як повне).
 */
static inline void Lora_Phy_Apply_Tx(int8_t tx_power_dbm, uint16_t preamble_symbols)
{
    Radio.SetTxConfig(MODEM_LORA, tx_power_dbm, 0u,
                      LORA_PHY_BW, LORA_PHY_SF, LORA_PHY_CR,
                      preamble_symbols, LORA_PHY_FIX_LEN, LORA_PHY_CRC_ON,
                      LORA_PHY_FREQ_HOP_ON, LORA_PHY_HOP_PERIOD, LORA_PHY_IQ_INVERTED,
                      LORA_PHY_TX_TIMEOUT_MS);
}

/*
 * RX-половина. `rx_continuous` різниться між вузлами і це не смак:
 * Королева — `true` (always-on listener, 03_02 §1), Солдат — `false`
 * (обмежене вікно, бо вухо коштує енергії). ⛔ Без цього виклику драйвер
 * лишає `SubgRf.RxContinuous = false` із `RadioInit`, і `Radio.Rx()` дає
 * RX-SINGLE незалежно від переданого таймауту.
 */
static inline void Lora_Phy_Apply_Rx(bool rx_continuous)
{
    Radio.SetRxConfig(MODEM_LORA, LORA_PHY_BW, LORA_PHY_SF, LORA_PHY_CR,
                      LORA_PHY_BW_AFC, LORA_PHY_PREAMBLE_SYMBOLS, LORA_PHY_RX_SYMB_TIMEOUT,
                      LORA_PHY_FIX_LEN, LORA_PHY_RX_PAYLOAD_LEN, LORA_PHY_CRC_ON,
                      LORA_PHY_FREQ_HOP_ON, LORA_PHY_HOP_PERIOD, LORA_PHY_IQ_INVERTED,
                      rx_continuous);
}

/*
 * Ефірний час кадру за ЦИМ профілем, мс. Рахує сам драйвер (`RadioTimeOnAir`,
 * формула Semtech з цілочисельним ceil) — тож власної копії числа в прошивці
 * немає; наша модель тієї самої формули для канону — tools/firmware/lora_airtime.rb
 * (16 Б → 165 мс, 30 Б → 227 мс). Преамбула — аргумент, бо PANIC-кадр Солдата
 * летить із власною (`cad_sniff.h`), і чекати він мусить саме її.
 */
static inline uint32_t Lora_Phy_Time_On_Air_Ms(uint16_t preamble_symbols, uint8_t payload_len)
{
    return Radio.TimeOnAir(MODEM_LORA, LORA_PHY_BW, LORA_PHY_SF, LORA_PHY_CR,
                           preamble_symbols, LORA_PHY_FIX_LEN, payload_len, LORA_PHY_CRC_ON);
}

/*
 * [FW.61] ЄДИНИЙ спосіб послати кадр: шле й повертає, скільки мс радіо ним ще
 * зайняте (ефір + `LORA_PHY_TX_GUARD_MS`). Викликач МУСИТЬ відчекати цей час
 * перш ніж дати радіо БУДЬ-ЯКУ наступну команду — Send, Rx, SetTxConfig, Sleep.
 * `Radio.Send` асинхронний: він лише пише буфер і `SetTx`, а кадр летить ще
 * 165 мс (16 Б @ SF9). Наступна команда посеред ефіру обриває кадр — `SetRx`
 * перемикає чіп на прийом, `Sleep` гасить його, а новий `Send` переписує буфер,
 * з якого модем ще читає. ⛔ Сталої паузи замість цього часу не ставити
 * (FW.61, 2026-09-27: паузи 60/100 мс проти 165-мс кадру обривали кадри на
 * всіх TX-сайтах обох вузлів, а телеметрія Солдата йшла прямо в `Radio.Rx`
 * Фази 4.5) — латентно до board-freeze, бо хост-стаб `Radio` і compile-only
 * ARM-лейн ефіру не мають (`firmware`-скіл гоча #20).
 * `warn_unused_result` — носій у мить дії: викликати шов і не чекати не можна
 * мовчки; голий `Radio.Send(` у main.c червонить `make -C firmware/test lora_phy`.
 */
__attribute__((warn_unused_result))
static inline uint32_t Lora_Phy_Send(uint8_t *buf, uint8_t len, uint16_t preamble_symbols)
{
    Radio.Send(buf, len);
    return Lora_Phy_Time_On_Air_Ms(preamble_symbols, len) + LORA_PHY_TX_GUARD_MS;
}

#endif /* SILKEN_LORA_PHY_APPLY_H */
