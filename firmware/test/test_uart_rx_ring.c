/*
 * test_uart_rx_ring.c — [FW.3] host-тести кільця-виду поверх circular-DMA RX.
 *
 * Симулюємо рух заліза руками: «DMA» пише в буфер + знімки (wraps, ndtr)
 * відтворюють усі підлі моменти — перетин межі кільця, перезаряджений NDTR
 * із запізнілим wraps++ (IRQ-латентність), об'їзд консьюмера, переповнення
 * uint32-лічильників. Фінал — інтеграційний дим: байти модема крізь кільце
 * у At_Engine_Feed дають ту саму подію, що й пряме годування.
 *
 * Build: make -C firmware/test uart_ring
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../queen/uart_rx_ring.h"
#include "../queen/at_engine.h"

/* ════════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK (house pattern — test_at_engine.c)
 * ════════════════════════════════════════════════════════════════════ */
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    printf("  %-58s", #name); \
    name(); \
    printf(" ✅\n"); \
    tests_passed++; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_TRUE(expr) ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

/* ── «Залізо» на host: буфер + позиція пера DMA ─────────────────────── */
#define RING_SZ 8u

typedef struct {
    uint8_t  buf[RING_SZ];
    uint32_t total;   /* скільки байтів «DMA» написало від старту */
} FakeDma;

static void fake_dma_write(FakeDma *d, const uint8_t *bytes, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
        d->buf[(d->total + i) % RING_SZ] = bytes[i];
    d->total += n;
}

static uint32_t fake_wraps(const FakeDma *d) { return d->total / RING_SZ; }
static uint16_t fake_ndtr(const FakeDma *d)
{
    /* NDTR рахує вниз; рівно на межі кола залізо показує перезаряджений
     * повний розмір (мить ndtr==0 покриває окремий тест). */
    uint32_t in_lap = d->total % RING_SZ;
    return (uint16_t)(RING_SZ - in_lap);
}

/* ════════════════════════════════════════════════════════════════════ */

TEST(test_empty_ring_pops_nothing)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);
    ASSERT_EQ(Uart_Ring_Advance(&r, 0, RING_SZ), 0);
    ASSERT_FALSE(Uart_Ring_Pop(&r, &b));
}

TEST(test_simple_produce_then_pop_in_order)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);
    fake_dma_write(&d, (const uint8_t *)"abc", 3);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 3);
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'a');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'b');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'c');
    ASSERT_FALSE(Uart_Ring_Pop(&r, &b));
}

TEST(test_bytes_survive_ring_boundary)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);

    /* 6 байтів → читаємо; ще 5 → перетин межі кільця */
    fake_dma_write(&d, (const uint8_t *)"012345", 6);
    Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d));
    for (int i = 0; i < 6; i++) ASSERT_TRUE(Uart_Ring_Pop(&r, &b));

    fake_dma_write(&d, (const uint8_t *)"WXYZ!", 5);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 5);
    const char *want = "WXYZ!";
    for (int i = 0; i < 5; i++) {
        ASSERT_TRUE(Uart_Ring_Pop(&r, &b));
        ASSERT_EQ(b, (uint8_t)want[i]);
    }
}

TEST(test_ndtr_zero_means_full_lap)
{
    FakeDma d = {0};
    UartRxRing r;
    Uart_Ring_Init(&r, d.buf, RING_SZ);
    fake_dma_write(&d, (const uint8_t *)"01234567", RING_SZ);
    /* мить ПЕРЕД автоперезарядкою: wraps ще 0, NDTR показує 0 */
    ASSERT_EQ(Uart_Ring_Advance(&r, 0, 0), RING_SZ);
}

TEST(test_irq_latency_never_rewinds_visibility)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);

    /* кінець кола 0: 7 байтів видно */
    fake_dma_write(&d, (const uint8_t *)"0123456", 7);
    ASSERT_EQ(Uart_Ring_Advance(&r, 0, fake_ndtr(&d)), 7);

    /* NDTR перезарядився (новий круг), а wraps++ ще в черзі NVIC:
     * сирий знімок (0, RING_SZ) дав би wr=0 — задкування на круг */
    ASSERT_EQ(Uart_Ring_Advance(&r, 0, RING_SZ), 7);  /* clamp тримає */
    for (int i = 0; i < 7; i++) ASSERT_TRUE(Uart_Ring_Pop(&r, &b));

    /* IRQ наздогнав: той самий момент часу, чесна пара */
    fake_dma_write(&d, (const uint8_t *)"8", 1);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 1);
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, '8');
}

TEST(test_exactly_full_ring_still_readable)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);
    fake_dma_write(&d, (const uint8_t *)"ABCDEFGH", RING_SZ);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), RING_SZ);
    ASSERT_EQ(r.overruns, 0);
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'A');
}

TEST(test_overrun_drops_all_and_counts)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);

    /* консьюмер спав, продюсер намотав понад коло: 8+3 байтів */
    fake_dma_write(&d, (const uint8_t *)"ABCDEFGHIJK", 11);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 0);
    ASSERT_EQ(r.overruns, 1);
    ASSERT_FALSE(Uart_Ring_Pop(&r, &b));

    /* життя триває: нові байти після скиду читаються чисто */
    fake_dma_write(&d, (const uint8_t *)"ok", 2);
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 2);
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'o');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'k');
    ASSERT_EQ(r.overruns, 1);
}

TEST(test_uint32_counter_wraparound_survives)
{
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);

    /* білий ящик: лічильники біля стелі uint32 (4 дні безперервного UART) */
    r.rd = r.wr_seen = 0xFFFFFFF8u;            /* кратне RING_SZ */
    d.total = 0xFFFFFFF8u;

    fake_dma_write(&d, (const uint8_t *)"abcdef", 6);
    /* wraps для wr=0xFFFFFFF8+6: (0xFFFFFFF8/8)=0x1FFFFFFF кіл + 6 у крузі */
    ASSERT_EQ(Uart_Ring_Advance(&r, 0x1FFFFFFFu, (uint16_t)(RING_SZ - 6u)), 6);
    for (int i = 0; i < 6; i++) ASSERT_TRUE(Uart_Ring_Pop(&r, &b));
    ASSERT_EQ(b, 'f');

    /* перехід лічильника через нуль: ще 4 байти (2 до межі + 2 після) */
    fake_dma_write(&d, (const uint8_t *)"ghij", 4);
    ASSERT_EQ(Uart_Ring_Advance(&r, 0x20000000u, (uint16_t)(RING_SZ - 2u)), 4);
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'g');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'h');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'i');
    ASSERT_TRUE(Uart_Ring_Pop(&r, &b)); ASSERT_EQ(b, 'j');
}

TEST(test_late_urc_survives_between_reads)
{
    /* Сценарій, заради якого все це: +CCOAPNMI прилетів, поки хост був
     * зайнятий (стара схема: ORE, байти мертві). Кільце їх тримає. */
    FakeDma d = {0};
    UartRxRing r;
    uint8_t b;
    Uart_Ring_Init(&r, d.buf, RING_SZ);

    fake_dma_write(&d, (const uint8_t *)"+NMI", 4);   /* «поки нас не було» */
    /* ...хост повернувся читати: */
    ASSERT_EQ(Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d)), 4);
    const char *want = "+NMI";
    for (int i = 0; i < 4; i++) {
        ASSERT_TRUE(Uart_Ring_Pop(&r, &b));
        ASSERT_EQ(b, (uint8_t)want[i]);
    }
}

TEST(test_integration_at_engine_sees_final_through_ring)
{
    /* Байти модема крізь кільце → токенайзер: та сама подія, що й напряму. */
    FakeDma d = {0};
    UartRxRing r;
    AtEngine e;
    uint8_t b;
    AtEvent last = AT_EVT_NONE;

    Uart_Ring_Init(&r, d.buf, RING_SZ);
    At_Engine_Reset(&e);

    const char *modem = "\r\nOK\r\n";
    /* шматками по 2 — довільна сегментація потоку, як у житті */
    for (uint32_t off = 0; off < strlen(modem); off += 2) {
        uint32_t n = strlen(modem) - off; if (n > 2) n = 2;
        fake_dma_write(&d, (const uint8_t *)modem + off, n);
        Uart_Ring_Advance(&r, fake_wraps(&d), fake_ndtr(&d));
        while (Uart_Ring_Pop(&r, &b)) last = At_Engine_Feed(&e, b);
    }
    ASSERT_EQ(last, AT_EVT_FINAL_OK);
}

int main(void)
{
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  UART RX ring host tests (FW.3, docs/03_02 §4)\n");
    printf("══════════════════════════════════════════════════════════════\n");

    RUN(test_empty_ring_pops_nothing);
    RUN(test_simple_produce_then_pop_in_order);
    RUN(test_bytes_survive_ring_boundary);
    RUN(test_ndtr_zero_means_full_lap);
    RUN(test_irq_latency_never_rewinds_visibility);
    RUN(test_exactly_full_ring_still_readable);
    RUN(test_overrun_drops_all_and_counts);
    RUN(test_uint32_counter_wraparound_survives);
    RUN(test_late_urc_survives_between_reads);
    RUN(test_integration_at_engine_sees_final_through_ring);

    printf("\n  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed ? 1 : 0;
}
