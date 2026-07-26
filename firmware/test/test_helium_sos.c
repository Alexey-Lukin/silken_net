// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_helium_sos.c — [ARCH.34 L3] Pure-половина Helium SOS-маяка Королеви.
 *
 * Build & run: make -C firmware/test helium
 *
 * Головний вектор — БАЙТ-У-БАЙТ фікстура бекенд-спеки
 * (spec/workers/helium_sos_worker_spec.rb#sos_payload: did=0xA1B2C3D4,
 * vcap=11800, err=1, uptime=5310, flags=0 → unpack "N n C C3 C"):
 * ті самі октети, які HeliumSosWorker#decode_sos розбере на бекенді.
 * Решта — тригер-таблиця канону 02_05 §6.1, бюджет сліпоти (wrap-safe)
 * і DID-парсер uid-рядка.
 */

#include "../queen/helium_sos.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d  expected %lu got %lu\n", \
                __FILE__, __LINE__, (unsigned long)(b), (unsigned long)(a)); \
        return 1; \
    } \
} while (0)

#define ASSERT_MEM_EQ(a, b, n) do { \
    if (memcmp((a), (b), (n)) != 0) { \
        fprintf(stderr, "FAIL %s:%d  memory mismatch (%zu bytes)\n", \
                __FILE__, __LINE__, (size_t)(n)); \
        return 1; \
    } \
} while (0)

/* MAC-шов лінкується лише в adapter-TU (bench-фаза) — тут стаб, щоб TU
 * зібрався, якщо хтось потягне символ. Pure-тести його не кличуть. */
int Helium_Mac_SendSos(const uint8_t sos_frame[HELIUM_SOS_WIRE_LEN],
                       uint32_t deadline_ms)
{
    (void)sos_frame; (void)deadline_ms;
    return 0;
}

static int test_pack_backend_fixture(void) {
    /* Дзеркало sos_payload() бекенд-спеки: 11800 = 0x2E18, 5310 = 0x0014BE. */
    static const uint8_t expected[HELIUM_SOS_WIRE_LEN] = {
        0xA1, 0xB2, 0xC3, 0xD4,  /* queen_did BE   */
        0x2E, 0x18,              /* vcap_mv BE     */
        0x01,                    /* starlink_down  */
        0x00, 0x14, 0xBE,        /* uptime u24 BE  */
        0x00,                    /* flags          */
        0x00                     /* rsv            */
    };
    uint8_t out[HELIUM_SOS_WIRE_LEN];
    memset(out, 0xAA, sizeof out);
    Helium_Sos_Pack(out, 0xA1B2C3D4u, 11800u, HELIUM_ERR_STARLINK_DOWN,
                    5310u, 0u);
    ASSERT_MEM_EQ(out, expected, HELIUM_SOS_WIRE_LEN);
    printf("  test_pack_backend_fixture                                  ✅\n");
    return 0;
}

static int test_pack_uptime_saturates_u24(void) {
    uint8_t out[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack(out, 1u, 0u, HELIUM_ERR_LTE_DOWN, 0x01000000u, 0u);
    ASSERT_EQ(out[7], 0xFFu);
    ASSERT_EQ(out[8], 0xFFu);
    ASSERT_EQ(out[9], 0xFFu);
    /* Рівно стеля — без сатурації. */
    Helium_Sos_Pack(out, 1u, 0u, HELIUM_ERR_LTE_DOWN, 0x00FFFFFFu, 0u);
    ASSERT_EQ(out[7], 0xFFu);
    ASSERT_EQ(out[9], 0xFFu);
    printf("  test_pack_uptime_saturates_u24                             ✅\n");
    return 0;
}

static int test_should_fire_canon_gates(void) {
    /* Усі три умови канону + пауза ретрансміту — кожна поодинці глушить. */
    ASSERT_EQ(Helium_Sos_Should_Fire(30, 30, 50, 1), 1); /* усе дозріло   */
    ASSERT_EQ(Helium_Sos_Should_Fire(29, 30, 50, 1), 0); /* uplink < 30хв */
    ASSERT_EQ(Helium_Sos_Should_Fire(30, 29, 50, 1), 0); /* ретрансміт-пауза */
    ASSERT_EQ(Helium_Sos_Should_Fire(30, 30, 49, 1), 0); /* буфер < 50%   */
    ASSERT_EQ(Helium_Sos_Should_Fire(30, 30, 50, 0), 0); /* Q2Q ще дихає  */
    ASSERT_EQ(Helium_Sos_Should_Fire(0, 0, 0, 0), 0);
    ASSERT_EQ(Helium_Sos_Should_Fire(1000, 1000, 100, 1), 1);
    printf("  test_should_fire_canon_gates                               ✅\n");
    return 0;
}

static int test_error_code_choice(void) {
    /* Буфер тисне → buffer_pressure; інакше впав єдиний LTE-uplink. */
    ASSERT_EQ(Helium_Sos_Error_Code(50), HELIUM_ERR_BUFFER_PRESSURE);
    ASSERT_EQ(Helium_Sos_Error_Code(100), HELIUM_ERR_BUFFER_PRESSURE);
    ASSERT_EQ(Helium_Sos_Error_Code(49), HELIUM_ERR_LTE_DOWN);
    ASSERT_EQ(Helium_Sos_Error_Code(0), HELIUM_ERR_LTE_DOWN);
    printf("  test_error_code_choice                                     ✅\n");
    return 0;
}

static int test_blind_budget_wrap_safe(void) {
    ASSERT_EQ(Helium_Blind_Budget_Ok(1000u, 1000u + 19999u), 1);
    ASSERT_EQ(Helium_Blind_Budget_Ok(1000u, 1000u + 20000u), 0);
    /* HAL_GetTick wrap (49.7 діб): старт перед переповненням, кінець після. */
    ASSERT_EQ(Helium_Blind_Budget_Ok(0xFFFFFF00u, 0xFFFFFF00u + 5000u), 1);
    ASSERT_EQ(Helium_Blind_Budget_Ok(0xFFFFFFF0u, 0x00004E10u), 0); /* 20с рівно */
    ASSERT_EQ(Helium_Blind_Budget_Ok(0xFFFFFFF0u, 0x00000010u), 1); /* 32 мс     */
    printf("  test_blind_budget_wrap_safe                                ✅\n");
    return 0;
}

static int test_did_from_uid(void) {
    ASSERT_EQ(Helium_Did_From_Uid("SNET-Q-A1B2C3D4"), 0xA1B2C3D4u);
    ASSERT_EQ(Helium_Did_From_Uid("SNET-Q-00000001"), 0x00000001u);
    ASSERT_EQ(Helium_Did_From_Uid("UNPROV-DEADBEEF"), 0xDEADBEEFu);
    ASSERT_EQ(Helium_Did_From_Uid("snet-q-a1b2c3d4"), 0xA1B2C3D4u); /* lower hex */
    ASSERT_EQ(Helium_Did_From_Uid("SNET-Q-XYZ"), 0u);       /* не hex        */
    ASSERT_EQ(Helium_Did_From_Uid("SNET-Q-A1B2C3"), 0u);    /* короткий хвіст */
    ASSERT_EQ(Helium_Did_From_Uid("SNET-Q-A1B2C3D4E"), 0u); /* довгий хвіст  */
    ASSERT_EQ(Helium_Did_From_Uid("NODASH"), 0u);
    ASSERT_EQ(Helium_Did_From_Uid(""), 0u);
    ASSERT_EQ(Helium_Did_From_Uid(NULL), 0u);
    printf("  test_did_from_uid                                          ✅\n");
    return 0;
}

int main(void) {
    int fails = 0;
    printf("test_helium_sos — [ARCH.34] pure-половина SOS-маяка:\n");
    fails += test_pack_backend_fixture();
    fails += test_pack_uptime_saturates_u24();
    fails += test_should_fire_canon_gates();
    fails += test_error_code_choice();
    fails += test_blind_budget_wrap_safe();
    fails += test_did_from_uid();
    if (fails) {
        fprintf(stderr, "❌ test_helium_sos: %d failed\n", fails);
        return 1;
    }
    printf("✅ test_helium_sos: всі тести зелені\n");
    return 0;
}
