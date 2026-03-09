/*
 * test_queen_logic.c — Host-based unit tests for Queen firmware logic.
 *
 * Extracts pure-logic functions from firmware/queen/main.c and tests them
 * on x86 with gcc. No ARM toolchain or hardware required.
 *
 * Build: gcc -Wall -Wextra -I. -o test_queen test_queen_logic.c && ./test_queen
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/* ── Inline HAL mock (replaces main.h + radio.h) ──────────────────── */
#include "hal_mock.h"

/* ── Forward declarations for main.h stub ──────────────────────────── */
#define CACHE_MAX_ENTRIES 50
#define CMD_DEDUP_SIZE    16
#define UUID_STR_LEN      36
#define CMD_DECRYPT_BUF_SIZE 96

/* ── Data structures (copied from queen/main.c) ───────────────────── */
typedef struct {
    uint32_t uid;
    uint8_t payload[16];
    int8_t rssi;
    uint8_t is_active;
} EdgeCache;

static EdgeCache forest_cache[CACHE_MAX_ENTRIES];
static uint8_t cache_count = 0;

/* Dedup ring */
static uint32_t cmd_dedup_ring[CMD_DEDUP_SIZE];
static uint8_t  cmd_dedup_idx  = 0;
static uint8_t  cmd_dedup_used = 0;

/* ── Extracted functions (identical to queen/main.c) ───────────────── */

/* DJB2 hash */
static uint32_t djb2_hash(const char* str, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len && str[i] != '\0'; i++) {
        h = ((h << 5) + h) + (uint8_t)str[i];
    }
    return h;
}

/* Idempotency dedup check: 0 = new, 1 = duplicate */
uint8_t Cmd_Dedup_Check(uint32_t hash)
{
    uint8_t count = cmd_dedup_used < CMD_DEDUP_SIZE ? cmd_dedup_used : CMD_DEDUP_SIZE;
    for (uint8_t i = 0; i < count; i++) {
        if (cmd_dedup_ring[i] == hash) return 1;
    }
    cmd_dedup_ring[cmd_dedup_idx] = hash;
    cmd_dedup_idx = (cmd_dedup_idx + 1) % CMD_DEDUP_SIZE;
    if (cmd_dedup_used < CMD_DEDUP_SIZE) cmd_dedup_used++;
    return 0;
}

/* CIFO cache logic (with priority-aware eviction fix) */
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi)
{
    /* 1. DEDUP: search for existing UID */
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].is_active && forest_cache[i].uid == uid) {
            memcpy(forest_cache[i].payload, payload, 16);
            forest_cache[i].rssi = rssi;
            return;
        }
    }

    /* 2. INSERT: find free slot */
    if (cache_count < CACHE_MAX_ENTRIES) {
        for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
            if (!forest_cache[i].is_active) {
                forest_cache[i].uid = uid;
                memcpy(forest_cache[i].payload, payload, 16);
                forest_cache[i].rssi = rssi;
                forest_cache[i].is_active = 1;
                cache_count++;
                return;
            }
        }
    }

    /* 3. CIFO eviction (priority-aware):
     * Never evict critical packets (bio_status stress/anomaly/tamper in byte 10 bits[7:6]).
     * Among non-critical entries, evict the one with worst RSSI.
     * If ALL entries are critical — fall back to worst-RSSI eviction anyway.
     */
    int best_evict_idx = -1;
    int8_t best_evict_rssi = 127;

    int fallback_idx = 0;
    int8_t fallback_rssi = 127;

    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        uint8_t bio_status = (forest_cache[i].payload[10] >> 6) & 0x03;

        /* Track absolute worst RSSI as fallback */
        if (forest_cache[i].rssi < fallback_rssi) {
            fallback_rssi = forest_cache[i].rssi;
            fallback_idx = i;
        }

        /* Prefer evicting non-critical (homeostasis, status==0) with worst RSSI */
        if (bio_status == 0 && forest_cache[i].rssi < best_evict_rssi) {
            best_evict_rssi = forest_cache[i].rssi;
            best_evict_idx = i;
        }
    }

    int evict = (best_evict_idx >= 0) ? best_evict_idx : fallback_idx;

    forest_cache[evict].uid = uid;
    memcpy(forest_cache[evict].payload, payload, 16);
    forest_cache[evict].rssi = rssi;
}

/* ── Test helpers ──────────────────────────────────────────────────── */
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    printf("  %-50s", #name); \
    name(); \
    printf(" ✅ PASS\n"); \
    tests_passed++; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        printf(" ❌ FAIL (line %d: %d != %d)\n", __LINE__, (int)(a), (int)(b)); \
        tests_failed++; \
        return; \
    } \
} while(0)

#define ASSERT_NE(a, b) do { \
    if ((a) == (b)) { \
        printf(" ❌ FAIL (line %d: %d == %d)\n", __LINE__, (int)(a), (int)(b)); \
        tests_failed++; \
        return; \
    } \
} while(0)

static void reset_cache(void) {
    memset(forest_cache, 0, sizeof(forest_cache));
    cache_count = 0;
}

static void reset_dedup(void) {
    memset(cmd_dedup_ring, 0, sizeof(cmd_dedup_ring));
    cmd_dedup_idx = 0;
    cmd_dedup_used = 0;
}

static void make_payload(uint8_t* buf, uint8_t bio_byte) {
    memset(buf, 0, 16);
    buf[10] = bio_byte;
}

/* ── DJB2 Hash Tests ──────────────────────────────────────────────── */

TEST(test_djb2_deterministic) {
    uint32_t h1 = djb2_hash("hello", 5);
    uint32_t h2 = djb2_hash("hello", 5);
    ASSERT_EQ(h1, h2);
}

TEST(test_djb2_different_strings) {
    uint32_t h1 = djb2_hash("uuid-aaa", 8);
    uint32_t h2 = djb2_hash("uuid-bbb", 8);
    ASSERT_NE(h1, h2);
}

TEST(test_djb2_known_value) {
    /* DJB2("a") = 5381*33 + 97 = 177670 + 97 = 177767 = 0x2B607 */
    uint32_t h = djb2_hash("a", 1);
    ASSERT_EQ(h, 0x0002B607);
}

TEST(test_djb2_empty_string) {
    uint32_t h = djb2_hash("", 10);
    ASSERT_EQ(h, 5381); /* Initial hash, no iterations */
}

/* ── Cmd Dedup Ring Tests ─────────────────────────────────────────── */

TEST(test_dedup_new_command) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(12345), 0); /* New → execute */
}

TEST(test_dedup_duplicate_command) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(12345), 0); /* New */
    ASSERT_EQ(Cmd_Dedup_Check(12345), 1); /* Duplicate */
}

TEST(test_dedup_ring_wraps) {
    reset_dedup();
    /* Fill ring with 16 unique hashes */
    for (uint32_t i = 1; i <= CMD_DEDUP_SIZE; i++) {
        ASSERT_EQ(Cmd_Dedup_Check(i), 0);
    }
    /* 17th overwrites slot 0 (which held hash=1) */
    ASSERT_EQ(Cmd_Dedup_Check(999), 0);
    /* Hash=1 should be gone now */
    ASSERT_EQ(Cmd_Dedup_Check(1), 0); /* Not found — treated as new */
}

TEST(test_dedup_16_unique_all_detected) {
    reset_dedup();
    for (uint32_t i = 100; i < 100 + CMD_DEDUP_SIZE; i++) {
        ASSERT_EQ(Cmd_Dedup_Check(i), 0);
    }
    /* All 16 should be detected as duplicates */
    for (uint32_t i = 100; i < 100 + CMD_DEDUP_SIZE; i++) {
        ASSERT_EQ(Cmd_Dedup_Check(i), 1);
    }
}

/* ── CIFO Cache Tests ─────────────────────────────────────────────── */

TEST(test_cache_insert_basic) {
    reset_cache();
    uint8_t payload[16] = {0};
    Process_And_Cache_Data(0xAABBCCDD, payload, -70);
    ASSERT_EQ(cache_count, 1);
    ASSERT_EQ(forest_cache[0].uid, 0xAABBCCDD);
    ASSERT_EQ(forest_cache[0].rssi, -70);
    ASSERT_EQ(forest_cache[0].is_active, 1);
}

TEST(test_cache_dedup_updates) {
    reset_cache();
    uint8_t payload1[16] = {0};
    uint8_t payload2[16] = {0};
    payload2[7] = 42; /* Different acoustic */

    Process_And_Cache_Data(0x11111111, payload1, -50);
    ASSERT_EQ(cache_count, 1);
    Process_And_Cache_Data(0x11111111, payload2, -40);
    ASSERT_EQ(cache_count, 1); /* No new entry */
    ASSERT_EQ(forest_cache[0].payload[7], 42); /* Updated */
    ASSERT_EQ(forest_cache[0].rssi, -40);
}

TEST(test_cache_fill_50) {
    reset_cache();
    uint8_t payload[16] = {0};
    for (uint32_t i = 0; i < CACHE_MAX_ENTRIES; i++) {
        Process_And_Cache_Data(i + 1, payload, (int8_t)(-(int8_t)(50 + (i % 40))));
    }
    ASSERT_EQ(cache_count, CACHE_MAX_ENTRIES);
}

TEST(test_cache_cifo_evicts_worst_rssi_non_critical) {
    reset_cache();
    /* Fill cache: 49 entries with RSSI=-50, 1 entry with RSSI=-90 (non-critical) */
    uint8_t healthy_payload[16] = {0};
    healthy_payload[10] = 0x00; /* bio_status = 0 (homeostasis), gp = 0 */

    for (uint32_t i = 0; i < CACHE_MAX_ENTRIES - 1; i++) {
        Process_And_Cache_Data(i + 1, healthy_payload, -50);
    }
    /* The "farthest" tree with worst RSSI */
    Process_And_Cache_Data(0xFAR, healthy_payload, -90);
    ASSERT_EQ(cache_count, CACHE_MAX_ENTRIES);

    /* Now insert a new tree — should evict DID=0xFAR (worst RSSI, non-critical) */
    uint8_t new_payload[16] = {0};
    Process_And_Cache_Data(0xNEW, new_payload, -30);

    /* Check 0xFAR is gone */
    int found_far = 0;
    int found_new = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].uid == 0xFAR) found_far = 1;
        if (forest_cache[i].uid == 0xNEW) found_new = 1;
    }
    ASSERT_EQ(found_far, 0);
    ASSERT_EQ(found_new, 1);
}

TEST(test_cache_cifo_protects_critical_packets) {
    reset_cache();
    /* Fill cache:
     * Entry 0: RSSI=-90 but CRITICAL (stress, status=1 → byte10 bits[7:6] = 01 → 0x40)
     * Entries 1-49: RSSI=-50, non-critical (status=0)
     */
    uint8_t critical_payload[16] = {0};
    critical_payload[10] = (1 << 6); /* status=stress, growth_points=0 */
    Process_And_Cache_Data(0xCRIT, critical_payload, -90);

    uint8_t healthy_payload[16] = {0};
    healthy_payload[10] = 0x00;
    for (uint32_t i = 1; i < CACHE_MAX_ENTRIES; i++) {
        Process_And_Cache_Data(i + 100, healthy_payload, -50);
    }
    ASSERT_EQ(cache_count, CACHE_MAX_ENTRIES);

    /* Insert a new entry — should evict a non-critical -50 entry, NOT the critical -90 one */
    uint8_t new_payload[16] = {0};
    Process_And_Cache_Data(0xBEEF, new_payload, -20);

    /* Critical packet must survive */
    int found_crit = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].uid == 0xCRIT) found_crit = 1;
    }
    ASSERT_EQ(found_crit, 1);
}

TEST(test_cache_cifo_fallback_when_all_critical) {
    reset_cache();
    /* Fill cache entirely with critical packets */
    uint8_t critical_payload[16] = {0};
    critical_payload[10] = (2 << 6); /* status=anomaly */

    for (uint32_t i = 0; i < CACHE_MAX_ENTRIES; i++) {
        Process_And_Cache_Data(i + 1, critical_payload, (int8_t)(-(int8_t)(50 + i)));
    }
    ASSERT_EQ(cache_count, CACHE_MAX_ENTRIES);

    /* Even if all critical, eviction must still work (fallback to worst RSSI) */
    uint8_t new_payload[16] = {0};
    Process_And_Cache_Data(0xDEAD, new_payload, -10);

    /* The one with worst RSSI (uid=50, rssi=-99) should be evicted */
    int found_dead = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].uid == 0xDEAD) found_dead = 1;
    }
    ASSERT_EQ(found_dead, 1);
}

/* ── Batch Packing Test ───────────────────────────────────────────── */

TEST(test_batch_packing_21_bytes) {
    reset_cache();
    uint8_t payload[16];
    memset(payload, 0xAA, 16);
    Process_And_Cache_Data(0x01020304, payload, -85);

    /* Pack like Flush_Cache_To_Rails does */
    uint8_t binary_batch_buffer[2048];
    uint16_t offset = 0;

    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].is_active) {
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 24);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 16);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 8);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid & 0xFF);
            binary_batch_buffer[offset++] = (uint8_t)(-forest_cache[i].rssi);
            memcpy(&binary_batch_buffer[offset], forest_cache[i].payload, 16);
            offset += 16;
        }
    }

    ASSERT_EQ(offset, 21); /* One 21-byte record */
    ASSERT_EQ(binary_batch_buffer[0], 0x01); /* DID byte 0 */
    ASSERT_EQ(binary_batch_buffer[1], 0x02);
    ASSERT_EQ(binary_batch_buffer[2], 0x03);
    ASSERT_EQ(binary_batch_buffer[3], 0x04);
    ASSERT_EQ(binary_batch_buffer[4], 85); /* RSSI inverted: -(-85)=85 */
    ASSERT_EQ(binary_batch_buffer[5], 0xAA); /* Payload byte 0 */
}

/* ── Entry point ──────────────────────────────────────────────────── */

int main(void)
{
    printf("\n🏰 Queen Firmware — Host-Based Unit Tests\n");
    printf("══════════════════════════════════════════\n\n");

    printf("  DJB2 Hash:\n");
    RUN(test_djb2_deterministic);
    RUN(test_djb2_different_strings);
    RUN(test_djb2_known_value);
    RUN(test_djb2_empty_string);

    printf("\n  Command Dedup Ring:\n");
    RUN(test_dedup_new_command);
    RUN(test_dedup_duplicate_command);
    RUN(test_dedup_ring_wraps);
    RUN(test_dedup_16_unique_all_detected);

    printf("\n  CIFO Cache:\n");
    RUN(test_cache_insert_basic);
    RUN(test_cache_dedup_updates);
    RUN(test_cache_fill_50);
    RUN(test_cache_cifo_evicts_worst_rssi_non_critical);
    RUN(test_cache_cifo_protects_critical_packets);
    RUN(test_cache_cifo_fallback_when_all_critical);

    printf("\n  Batch Packing:\n");
    RUN(test_batch_packing_21_bytes);

    printf("\n══════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);

    return tests_failed > 0 ? 1 : 0;
}
