// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_lora_phy.c — [FW.61] базлайн модуляції raw-LoRa P2P.
 *
 * ЩО САМЕ тут пінується, і чому це не тавтологія «константа дорівнює собі»:
 * тест лінкується проти СПРАВЖНЬОГО вендорського `radio.h` і кличе ті самі
 * `Lora_Phy_Apply_Tx/Rx`, які кличуть обидві прошивки. Тобто червоніє він на
 * помилці арності чи порядку аргументів — класі, який інакше видно лише
 * ARM-джобі `hal_check` у CI, тобто окремим червоним пушем без локального
 * відтворення (`firmware`-скіл гоча #13).
 *
 * ⛔ Значення профілю сюди НЕ переписані повторно з канону: їх дає
 * `lora_phy.h`, а збіг канону з ним стереже
 * `ruby tools/firmware/lora_airtime.rb --check-canon`. Тест судить ВИКЛИК,
 * гейт судить ЧИСЛА — розділення навмисне, щоб жодна половина не атестувала
 * сама себе.
 *
 * Збірка/прогін: make -C firmware/test lora_phy
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "radio.h"
#include "../common/lora_phy.h"
#include "../common/lora_phy_apply.h"

static int g_tests_run = 0;
static int g_tests_failed = 0;

#define ASSERT_EQ(actual, expected) do { \
    long long a_ = (long long)(actual); \
    long long e_ = (long long)(expected); \
    g_tests_run++; \
    if (a_ != e_) { \
        printf("  FAIL %s:%d — %s: отримано %lld, очікувано %lld\n", \
               __FILE__, __LINE__, #actual, a_, e_); \
        g_tests_failed++; \
    } \
} while (0)

/* ── Записувач викликів драйвера ────────────────────────────────────────
 * Semtech оголошує `extern const struct Radio_s Radio;` — тут ми його й
 * ВИЗНАЧАЄМО, полями-заглушками. Решта ~35 покажчиків лишаються NULL: тест
 * не кличе їх, а designated-ініціалізація C11 не вимагає перелічувати. */

typedef struct {
    int calls;
    RadioModems_t modem;
    int8_t power;
    uint32_t fdev;
    uint32_t bandwidth;
    uint32_t datarate;
    uint8_t coderate;
    uint16_t preamble_len;
    bool fix_len;
    bool crc_on;
    bool freq_hop_on;
    uint8_t hop_period;
    bool iq_inverted;
    uint32_t timeout;
} TxCapture;

typedef struct {
    int calls;
    RadioModems_t modem;
    uint32_t bandwidth;
    uint32_t datarate;
    uint8_t coderate;
    uint32_t bandwidth_afc;
    uint16_t preamble_len;
    uint16_t symb_timeout;
    bool fix_len;
    uint8_t payload_len;
    bool crc_on;
    bool freq_hop_on;
    uint8_t hop_period;
    bool iq_inverted;
    bool rx_continuous;
} RxCapture;

static TxCapture g_tx;
static RxCapture g_rx;
static int g_sync_calls;
static bool g_sync_public;
/* Порядок викликів: 'T'/'R' у хронології — саме він несе «RX останнім». */
static char g_order[8];
static size_t g_order_len;

static void note_order(char c)
{
    if (g_order_len + 1 < sizeof(g_order)) {
        g_order[g_order_len++] = c;
        g_order[g_order_len] = '\0';
    }
}

static void capture_set_public_network(bool enable)
{
    g_sync_calls++;
    g_sync_public = enable;
    note_order('S');
}

static void capture_set_tx_config(RadioModems_t modem, int8_t power, uint32_t fdev,
                                  uint32_t bandwidth, uint32_t datarate,
                                  uint8_t coderate, uint16_t preamble_len,
                                  bool fix_len, bool crc_on, bool freq_hop_on,
                                  uint8_t hop_period, bool iq_inverted, uint32_t timeout)
{
    g_tx.calls++;
    g_tx.modem = modem;
    g_tx.power = power;
    g_tx.fdev = fdev;
    g_tx.bandwidth = bandwidth;
    g_tx.datarate = datarate;
    g_tx.coderate = coderate;
    g_tx.preamble_len = preamble_len;
    g_tx.fix_len = fix_len;
    g_tx.crc_on = crc_on;
    g_tx.freq_hop_on = freq_hop_on;
    g_tx.hop_period = hop_period;
    g_tx.iq_inverted = iq_inverted;
    g_tx.timeout = timeout;
    note_order('T');
}

static void capture_set_rx_config(RadioModems_t modem, uint32_t bandwidth,
                                  uint32_t datarate, uint8_t coderate,
                                  uint32_t bandwidth_afc, uint16_t preamble_len,
                                  uint16_t symb_timeout, bool fix_len,
                                  uint8_t payload_len, bool crc_on, bool freq_hop_on,
                                  uint8_t hop_period, bool iq_inverted, bool rx_continuous)
{
    g_rx.calls++;
    g_rx.modem = modem;
    g_rx.bandwidth = bandwidth;
    g_rx.datarate = datarate;
    g_rx.coderate = coderate;
    g_rx.bandwidth_afc = bandwidth_afc;
    g_rx.preamble_len = preamble_len;
    g_rx.symb_timeout = symb_timeout;
    g_rx.fix_len = fix_len;
    g_rx.payload_len = payload_len;
    g_rx.crc_on = crc_on;
    g_rx.freq_hop_on = freq_hop_on;
    g_rx.hop_period = hop_period;
    g_rx.iq_inverted = iq_inverted;
    g_rx.rx_continuous = rx_continuous;
    note_order('R');
}

const struct Radio_s Radio = {
    .SetPublicNetwork = capture_set_public_network,
    .SetTxConfig = capture_set_tx_config,
    .SetRxConfig = capture_set_rx_config
};

static void reset_capture(void)
{
    memset(&g_tx, 0, sizeof(g_tx));
    memset(&g_rx, 0, sizeof(g_rx));
    g_sync_calls = 0;
    g_sync_public = true;   /* навмисно ХИБНЕ сім'я: зелений мусить купити виклик */
    g_order[0] = '\0';
    g_order_len = 0;
}

/* ── Тести ─────────────────────────────────────────────────────────────── */

/* Сценарій C (02_03 §9.8): +14 дБм @ SF9/BW125/CR4-5. ⛔ Не «те саме, що в
 * заголовку» — це пін на те, що ТУПЛ, який їде у драйвер, несе саме ці
 * величини у саме цих позиціях. Зсунь два аргументи місцями — заголовок
 * лишиться правдивим, а цей тест почервоніє. */
static void test_tx_baseline_tuple(void)
{
    reset_capture();
    Lora_Phy_Apply_Tx(LORA_PHY_PREAMBLE_SYMBOLS);

    ASSERT_EQ(g_tx.calls, 1);
    ASSERT_EQ(g_tx.modem, MODEM_LORA);
    ASSERT_EQ(g_tx.power, 14);
    ASSERT_EQ(g_tx.fdev, 0u);            /* FSK-поле, для LoRa мусить бути 0 */
    ASSERT_EQ(g_tx.bandwidth, 0u);       /* 0 = 125 кГц */
    ASSERT_EQ(g_tx.datarate, 9u);        /* SF9 */
    ASSERT_EQ(g_tx.coderate, 1u);        /* 1 = 4/5 */
    ASSERT_EQ(g_tx.preamble_len, 8u);
    ASSERT_EQ(g_tx.fix_len, false);      /* explicit header */
    ASSERT_EQ(g_tx.crc_on, true);
    ASSERT_EQ(g_tx.freq_hop_on, false);
    ASSERT_EQ(g_tx.hop_period, 0u);
    ASSERT_EQ(g_tx.iq_inverted, false);
    ASSERT_EQ(g_tx.timeout, 0u);   /* [transitional] без програмного TX-таймауту — FW.61 👤 */
}

/* Єдине, що ARCH.26 «останній зойк» має право змінити, — преамбула. Якщо
 * колись подовжать ще щось, цей тест назве що саме. */
static void test_panic_changes_preamble_only(void)
{
    reset_capture();
    Lora_Phy_Apply_Tx(LORA_PHY_PREAMBLE_SYMBOLS);
    TxCapture baseline = g_tx;

    reset_capture();
    Lora_Phy_Apply_Tx(973u); /* ≈4 с @ SF9 — «останній зойк», 02_03 §9.10 */

    ASSERT_EQ(g_tx.preamble_len, 973u);
    ASSERT_EQ(g_tx.power, baseline.power);
    ASSERT_EQ(g_tx.bandwidth, baseline.bandwidth);
    ASSERT_EQ(g_tx.datarate, baseline.datarate);
    ASSERT_EQ(g_tx.coderate, baseline.coderate);
    ASSERT_EQ(g_tx.crc_on, baseline.crc_on);
    ASSERT_EQ(g_tx.iq_inverted, baseline.iq_inverted);
    ASSERT_EQ(g_tx.timeout, baseline.timeout);
}

/* Відновлення після PANIC мусить бути ПОВНИМ: та сама 13-арна форма, тож
 * жоден із решти дванадцяти аргументів не може лишитись панічним. */
static void test_panic_restore_is_total(void)
{
    reset_capture();
    Lora_Phy_Apply_Tx(LORA_PHY_PREAMBLE_SYMBOLS);
    TxCapture baseline = g_tx;

    reset_capture();
    Lora_Phy_Apply_Tx(973u);
    Lora_Phy_Apply_Tx(LORA_PHY_PREAMBLE_SYMBOLS); /* restore */

    /* ⛔ НЕ memcmp по структурі: він читав би й padding-байти, тобто міг би
     * як пропустити розбіжність, так і зловити шум. Поля — поіменно, бо
     * саме ім'я поля мусить стояти в повідомленні про падіння. */
    ASSERT_EQ(g_tx.calls, 2);
    ASSERT_EQ(g_tx.modem, baseline.modem);
    ASSERT_EQ(g_tx.power, baseline.power);
    ASSERT_EQ(g_tx.fdev, baseline.fdev);
    ASSERT_EQ(g_tx.bandwidth, baseline.bandwidth);
    ASSERT_EQ(g_tx.datarate, baseline.datarate);
    ASSERT_EQ(g_tx.coderate, baseline.coderate);
    ASSERT_EQ(g_tx.preamble_len, baseline.preamble_len);
    ASSERT_EQ(g_tx.fix_len, baseline.fix_len);
    ASSERT_EQ(g_tx.crc_on, baseline.crc_on);
    ASSERT_EQ(g_tx.freq_hop_on, baseline.freq_hop_on);
    ASSERT_EQ(g_tx.hop_period, baseline.hop_period);
    ASSERT_EQ(g_tx.iq_inverted, baseline.iq_inverted);
    ASSERT_EQ(g_tx.timeout, baseline.timeout);
}

/* 🔴 Найдорожчий пін файлу: без `SetRxConfig` драйвер лишає
 * `SubgRf.RxContinuous = false` із `RadioInit`, і Королевине «завжди слухає»
 * (03_02 §1) перетворюється на RX-single при будь-якому таймауті в
 * `Radio.Rx()`. Різниця Королева/Солдат тут — не смак, а енергія. */
static void test_rx_continuous_differs_by_node(void)
{
    reset_capture();
    Lora_Phy_Apply_Rx(LORA_PHY_RX_CONTINUOUS_QUEEN);
    ASSERT_EQ(g_rx.calls, 1);
    ASSERT_EQ(g_rx.rx_continuous, true);

    reset_capture();
    Lora_Phy_Apply_Rx(LORA_PHY_RX_CONTINUOUS_SOLDIER);
    ASSERT_EQ(g_rx.rx_continuous, false);

    ASSERT_EQ(LORA_PHY_RX_CONTINUOUS_QUEEN != LORA_PHY_RX_CONTINUOUS_SOLDIER, 1);
}

/* RX-тупл у своїх позиціях: у нього 14 аргументів і ДВА з них — це
 * `preambleLen` та `symbTimeout` підряд, тобто найлегша пара для зсуву. */
static void test_rx_baseline_tuple(void)
{
    reset_capture();
    Lora_Phy_Apply_Rx(LORA_PHY_RX_CONTINUOUS_QUEEN);

    ASSERT_EQ(g_rx.calls, 1);
    ASSERT_EQ(g_rx.modem, MODEM_LORA);
    ASSERT_EQ(g_rx.bandwidth, 0u);
    ASSERT_EQ(g_rx.datarate, 9u);
    ASSERT_EQ(g_rx.coderate, 1u);
    ASSERT_EQ(g_rx.bandwidth_afc, 0u);
    ASSERT_EQ(g_rx.preamble_len, 8u);
    ASSERT_EQ(g_rx.symb_timeout, 0u);
    ASSERT_EQ(g_rx.fix_len, false);
    /* ⚠️ ОГОЛОШЕНА СЛІПОТА: `fixLen` і `payloadLen` стоять сусідами й ОБИДВА нулі,
     * тож перестановка САМЕ ЦІЄЇ пари цим файлом не ловиться за побудовою. */
    ASSERT_EQ(g_rx.payload_len, 0u);
    ASSERT_EQ(g_rx.crc_on, true);
    ASSERT_EQ(g_rx.freq_hop_on, false);
    ASSERT_EQ(g_rx.hop_period, 0u);
    ASSERT_EQ(g_rx.iq_inverted, false);
}

/* ⛔ Пін порядку TX⊥RX ЗНЯТО 2026-09-11: він пінив НЕ-інваріант, ще й із
 * хибним обґрунтуванням («rxContinuous перезапишеться»). `RadioSetTxConfig`
 * цього поля не пише взагалі, а решту обидва пишуть однаково — тож
 * перестановка нешкідлива, і червоне на ній було б покаранням за коректний
 * код (`guard-craft` #52: мутація в ОБИДВА боки). Справжній порядок —
 * sync word першим — пінить test_full_baseline_order нижче. */

/* 🔴 Найгостріший пін файлу після ревʼю 2026-09-11: sync word — ЄДИНИЙ вимір
 * PHY, який LoRaWAN-детур міняє в РЕГІСТРІ, а `Radio.Init` скидає лише в RAM.
 * `RadioSetModem` переписує слово тільки при `Current != Previous`, тобто після
 * `Init` — ніколи. Без явного виклику Королева слухала б публічним словом. */
static void test_sync_word_is_private_and_explicit(void)
{
    reset_capture();
    Lora_Phy_Apply_Sync_Word();
    ASSERT_EQ(g_sync_calls, 1);
    ASSERT_EQ(g_sync_public, false);
}

/* Порядок повного базлайну: sync word ПЕРШИМ (він кличе SetModem усередині),
 * далі TX, далі RX. */
static void test_full_baseline_order(void)
{
    reset_capture();
    Lora_Phy_Apply_Sync_Word();
    Lora_Phy_Apply_Tx(LORA_PHY_PREAMBLE_SYMBOLS);
    Lora_Phy_Apply_Rx(LORA_PHY_RX_CONTINUOUS_QUEEN);
    ASSERT_EQ(strcmp(g_order, "STR"), 0);
}

/* T_sym — похідна профілю, і на ній стоїть уся CAD-преамбульна математика.
 * Компайл-тайм дзеркало цього піна живе в cad_sniff.h (_Static_assert). */
static void test_symbol_time_derives_from_profile(void)
{
    /* ⛔ Не звіряти T_sym із власним розкриттям — то `X == X`. Пін тримає
     * ЗНАЧЕННЯ, на якому стоїть CAD-математика; компайл-тайм пару з
     * cad_sniff.h тримає _Static_assert там. */
    ASSERT_EQ(LORA_PHY_T_SYM_US, 4096u);
}

/* Частота — raw-LoRa P2P, НЕ канал LoRaWAN-детуру (ARCH.34: 868.1/.3/.5). */
static void test_channel_is_p2p_not_lorawan(void)
{
    /* 868.1/.3/.5 — канали LoRaWAN-детуру (ARCH.34); рівність нижче їх
     * виключає, тож окрема нерівність була б підмножиною цього ж піна. */
    ASSERT_EQ(LORA_PHY_FREQ_HZ, 868000000u);
}

int main(void)
{
    printf("── test_lora_phy: FW.61 базлайн модуляції raw-LoRa P2P ──\n");

    printf("test_tx_baseline_tuple\n");               test_tx_baseline_tuple();
    printf("test_rx_baseline_tuple\n");               test_rx_baseline_tuple();
    printf("test_rx_continuous_differs_by_node\n");   test_rx_continuous_differs_by_node();
    printf("test_panic_changes_preamble_only\n");     test_panic_changes_preamble_only();
    printf("test_panic_restore_is_total\n");          test_panic_restore_is_total();
    printf("test_sync_word_is_private_and_explicit\n"); test_sync_word_is_private_and_explicit();
    printf("test_full_baseline_order\n");            test_full_baseline_order();
    printf("test_symbol_time_derives_from_profile\n"); test_symbol_time_derives_from_profile();
    printf("test_channel_is_p2p_not_lorawan\n");      test_channel_is_p2p_not_lorawan();

    printf("──────────────────────────────────────────────────────────\n");
    printf("PASS: %d  FAIL: %d\n", g_tests_run - g_tests_failed, g_tests_failed);
    return g_tests_failed == 0 ? 0 : 1;
}
