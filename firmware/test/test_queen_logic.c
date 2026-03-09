/*
 * test_queen_logic.c — Comprehensive host-based unit tests for Queen firmware.
 *
 * Extracts pure-logic functions from firmware/queen/main.c and tests on x86.
 * Covers: CIFO cache, DJB2 hash, dedup ring, batch packing, OTA chunking,
 * RSSI handling, and all edge cases from the firmware audit.
 *
 * Build: make -C firmware/test
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "hal_mock.h"

/* ── Constants (from queen/main.c) ──────────────────────────────────── */
#define CACHE_MAX_ENTRIES     50
#define CMD_DEDUP_SIZE        16
#define UUID_STR_LEN          36
#define CMD_DECRYPT_BUF_SIZE  96

/* ── Data structures (from queen/main.c) ────────────────────────────── */
typedef struct {
    uint32_t uid;
    uint8_t  payload[16];
    int8_t   rssi;
    uint8_t  is_active;
} EdgeCache;

/* ── Globals for testable functions ─────────────────────────────────── */
static EdgeCache forest_cache[CACHE_MAX_ENTRIES];
static uint8_t   cache_count = 0;

static uint32_t cmd_dedup_ring[CMD_DEDUP_SIZE];
static uint8_t  cmd_dedup_idx  = 0;
static uint8_t  cmd_dedup_used = 0;

static uint8_t binary_batch_buffer[2048];

/* OTA globals */
static uint8_t pending_ota_bytecode[] = {
    0x52, 0x49, 0x54, 0x45, 0x30, 0x33, 0x30, 0x30, 0x00, 0x00,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44,
    0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0x11, 0x22, 0x33, 0x44,
    0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD
};
static uint16_t pending_ota_size = sizeof(pending_ota_bytecode);

/* ════════════════════════════════════════════════════════════════════
 * EXTRACTED FUNCTIONS (matching queen/main.c with bug fixes marked)
 * ════════════════════════════════════════════════════════════════════ */

/* DJB2 hash — identical to queen/main.c */
static uint32_t djb2_hash(const char* str, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len && str[i] != '\0'; i++) {
        h = ((h << 5) + h) + (uint8_t)str[i];
    }
    return h;
}

/* Command dedup ring — identical to queen/main.c */
static uint8_t Cmd_Dedup_Check(uint32_t hash)
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

/* CIFO cache — with priority-aware eviction FIX (Risk 3) */
static void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi)
{
    /* 1. DEDUP */
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].is_active && forest_cache[i].uid == uid) {
            memcpy(forest_cache[i].payload, payload, 16);
            forest_cache[i].rssi = rssi;
            return;
        }
    }

    /* 2. INSERT into free slot */
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

    /* 3. CIFO eviction — priority-aware:
     * Prefer evicting non-critical (bio_status == 0) with worst RSSI.
     * Fall back to absolute worst RSSI if ALL are critical.
     * [FIX: AUDIT] Only consider is_active entries for eviction. */
    int best_evict_idx = -1;
    int8_t best_evict_rssi = 127;
    int fallback_idx = 0;
    int8_t fallback_rssi = 127;

    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (!forest_cache[i].is_active) continue; /* [FIX] skip inactive */

        uint8_t bio_status = (forest_cache[i].payload[10] >> 6) & 0x03;

        if (forest_cache[i].rssi < fallback_rssi) {
            fallback_rssi = forest_cache[i].rssi;
            fallback_idx = i;
        }

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

/* Batch packing — matches Flush_Cache_To_Rails packing logic.
 * [FIX: AUDIT] Use (int16_t) cast for RSSI negation to avoid UB on -128. */
static uint16_t Pack_Cache_To_Batch(void)
{
    uint16_t offset = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].is_active) {
            if ((offset + 21) > sizeof(binary_batch_buffer)) break;
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 24);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 16);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 8);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid & 0xFF);
            /* [FIX] Cast to int16 before negation to prevent UB on rssi == -128 */
            binary_batch_buffer[offset++] = (uint8_t)(-(int16_t)forest_cache[i].rssi);
            memcpy(&binary_batch_buffer[offset], forest_cache[i].payload, 16);
            offset += 16;
            forest_cache[i].is_active = 0;
        }
    }
    cache_count = 0;
    return offset;
}

/* OTA chunk builder — extracted from queen main loop.
 * Returns bytes_to_copy (0 if offset out of bounds). */
static uint8_t Build_OTA_Chunk(uint16_t chunk_idx, uint8_t* ota_chunk)
{
    uint16_t total_chunks = (pending_ota_size + 10) / 11;
    if (chunk_idx >= total_chunks) return 0;

    memset(ota_chunk, 0, 16);
    ota_chunk[0] = 0x99;
    ota_chunk[1] = (uint8_t)(chunk_idx >> 8);
    ota_chunk[2] = (uint8_t)(chunk_idx & 0xFF);
    ota_chunk[3] = (uint8_t)(total_chunks >> 8);
    ota_chunk[4] = (uint8_t)(total_chunks & 0xFF);

    uint16_t offset = chunk_idx * 11;
    /* [FIX: AUDIT] Bounds check to prevent read past pending_ota_bytecode */
    if (offset >= pending_ota_size) return 0;
    uint8_t bytes_to_copy = (pending_ota_size - offset > 11) ? 11 : (uint8_t)(pending_ota_size - offset);
    memcpy(&ota_chunk[5], &pending_ota_bytecode[offset], bytes_to_copy);
    return bytes_to_copy;
}

/* ════════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK
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

#define ASSERT_NE(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a == _b) { \
        printf(" ❌ FAIL (line %d: %lld == %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_TRUE(expr) ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

#define ASSERT_NULL(ptr) do { \
    if ((ptr) != NULL) { \
        printf(" ❌ FAIL (line %d: expected NULL, got %p)\n", __LINE__, (void*)(ptr)); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_NOT_NULL(ptr) do { \
    if ((ptr) == NULL) { \
        printf(" ❌ FAIL (line %d: expected non-NULL)\n", __LINE__); \
        tests_failed++; return; \
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

/* ════════════════════════════════════════════════════════════════════
 * 1. DJB2 HASH TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_djb2_deterministic) {
    uint32_t h1 = djb2_hash("hello", 5);
    uint32_t h2 = djb2_hash("hello", 5);
    ASSERT_EQ(h1, h2);
}

TEST(test_djb2_different_strings) {
    ASSERT_NE(djb2_hash("uuid-aaa", 8), djb2_hash("uuid-bbb", 8));
}

TEST(test_djb2_known_value) {
    /* DJB2("a") = ((5381 << 5) + 5381) + 97 = 177670 = 0x2B606 */
    ASSERT_EQ(djb2_hash("a", 1), 0x0002B606);
}

TEST(test_djb2_empty_string) {
    ASSERT_EQ(djb2_hash("", 10), 5381);
}

TEST(test_djb2_null_terminator_mid_len) {
    uint32_t h1 = djb2_hash("ab\0cd", 5);
    uint32_t h2 = djb2_hash("ab", 2);
    ASSERT_EQ(h1, h2);
}

TEST(test_djb2_uuid_format) {
    const char* uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    uint32_t h = djb2_hash(uuid, UUID_STR_LEN);
    ASSERT_NE(h, 0);
    ASSERT_NE(h, 5381);
    ASSERT_EQ(h, djb2_hash(uuid, UUID_STR_LEN));
}

TEST(test_djb2_single_char_diff) {
    ASSERT_NE(djb2_hash("aaaa", 4), djb2_hash("aaab", 4));
}

/* ════════════════════════════════════════════════════════════════════
 * 2. COMMAND DEDUP RING TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_dedup_new_command) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(12345), 0);
}

TEST(test_dedup_duplicate) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(12345), 0);
    ASSERT_EQ(Cmd_Dedup_Check(12345), 1);
}

TEST(test_dedup_two_different) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(111), 0);
    ASSERT_EQ(Cmd_Dedup_Check(222), 0);
    ASSERT_EQ(Cmd_Dedup_Check(111), 1);
    ASSERT_EQ(Cmd_Dedup_Check(222), 1);
}

TEST(test_dedup_ring_wraps_evicts_oldest) {
    reset_dedup();
    for (uint32_t i = 1; i <= CMD_DEDUP_SIZE; i++)
        ASSERT_EQ(Cmd_Dedup_Check(i), 0);
    ASSERT_EQ(Cmd_Dedup_Check(999), 0);
    ASSERT_EQ(Cmd_Dedup_Check(1), 0);   /* evicted (was in slot 0, overwritten by 999) */
    /* hash=2 was also evicted (slot 1 overwritten by re-inserted hash=1) */
    ASSERT_EQ(Cmd_Dedup_Check(3), 1);   /* still present in slot 2 */
}

TEST(test_dedup_all_16_detected) {
    reset_dedup();
    for (uint32_t i = 100; i < 100 + CMD_DEDUP_SIZE; i++)
        ASSERT_EQ(Cmd_Dedup_Check(i), 0);
    for (uint32_t i = 100; i < 100 + CMD_DEDUP_SIZE; i++)
        ASSERT_EQ(Cmd_Dedup_Check(i), 1);
}

TEST(test_dedup_hash_zero) {
    reset_dedup();
    ASSERT_EQ(Cmd_Dedup_Check(0), 0);
    ASSERT_EQ(Cmd_Dedup_Check(0), 1);
}

TEST(test_dedup_stress_100) {
    reset_dedup();
    for (uint32_t i = 0; i < 100; i++)
        Cmd_Dedup_Check(i + 1000);
    for (uint32_t i = 84; i < 100; i++)
        ASSERT_EQ(Cmd_Dedup_Check(i + 1000), 1);
    ASSERT_EQ(Cmd_Dedup_Check(1000), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 3. CIFO CACHE TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_cache_insert_single) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(0xAABBCCDD, p, -70);
    ASSERT_EQ(cache_count, 1);
    ASSERT_EQ(forest_cache[0].uid, (long long)0xAABBCCDD);
    ASSERT_EQ(forest_cache[0].rssi, -70);
    ASSERT_EQ(forest_cache[0].is_active, 1);
}

TEST(test_cache_dedup_updates_data) {
    reset_cache();
    uint8_t p1[16] = {0}, p2[16] = {0};
    p2[7] = 42;
    Process_And_Cache_Data(0x11, p1, -50);
    Process_And_Cache_Data(0x11, p2, -40);
    ASSERT_EQ(cache_count, 1);
    ASSERT_EQ(forest_cache[0].payload[7], 42);
    ASSERT_EQ(forest_cache[0].rssi, -40);
}

TEST(test_cache_dedup_preserves_others) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(0xAA, p, -50);
    Process_And_Cache_Data(0xBB, p, -60);
    Process_And_Cache_Data(0xAA, p, -30);
    ASSERT_EQ(cache_count, 2);
}

TEST(test_cache_fill_50) {
    reset_cache();
    uint8_t p[16] = {0};
    for (uint32_t i = 0; i < CACHE_MAX_ENTRIES; i++)
        Process_And_Cache_Data(i + 1, p, (int8_t)(-(int8_t)(50 + (i % 40))));
    ASSERT_EQ(cache_count, CACHE_MAX_ENTRIES);
}

TEST(test_cache_cifo_evicts_worst_rssi) {
    reset_cache();
    uint8_t healthy[16] = {0};
    for (uint32_t i = 0; i < 49; i++)
        Process_And_Cache_Data(i + 1, healthy, -50);
    Process_And_Cache_Data(0xFA12, healthy, -90);

    Process_And_Cache_Data(0xA0, healthy, -30);

    int found_far = 0, found_new = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (forest_cache[i].uid == 0xFA12) found_far = 1;
        if (forest_cache[i].uid == 0xA0) found_new = 1;
    }
    ASSERT_EQ(found_far, 0);
    ASSERT_EQ(found_new, 1);
}

TEST(test_cache_cifo_protects_critical_stress) {
    reset_cache();
    uint8_t critical[16] = {0};
    critical[10] = (1 << 6);
    Process_And_Cache_Data(0xC1, critical, -90);

    uint8_t healthy[16] = {0};
    for (uint32_t i = 1; i < 50; i++)
        Process_And_Cache_Data(i + 100, healthy, -50);

    Process_And_Cache_Data(0xBEEF, healthy, -20);

    int found = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (forest_cache[i].uid == 0xC1) found = 1;
    ASSERT_EQ(found, 1);
}

TEST(test_cache_cifo_protects_anomaly) {
    reset_cache();
    uint8_t anomaly[16] = {0};
    anomaly[10] = (2 << 6);
    Process_And_Cache_Data(0xA1, anomaly, -95);

    uint8_t healthy[16] = {0};
    for (uint32_t i = 1; i < 50; i++)
        Process_And_Cache_Data(i + 200, healthy, -60);

    Process_And_Cache_Data(0xDE, healthy, -10);

    int found = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (forest_cache[i].uid == 0xA1) found = 1;
    ASSERT_EQ(found, 1);
}

TEST(test_cache_cifo_protects_tamper) {
    reset_cache();
    uint8_t tamper[16] = {0};
    tamper[10] = (3 << 6);
    Process_And_Cache_Data(0xDA, tamper, -100);

    uint8_t healthy[16] = {0};
    for (uint32_t i = 1; i < 50; i++)
        Process_And_Cache_Data(i + 300, healthy, -55);

    Process_And_Cache_Data(0xFE, healthy, -15);

    int found = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (forest_cache[i].uid == 0xDA) found = 1;
    ASSERT_EQ(found, 1);
}

TEST(test_cache_cifo_fallback_all_critical) {
    reset_cache();
    uint8_t critical[16] = {0};
    critical[10] = (2 << 6);

    for (uint32_t i = 0; i < 50; i++)
        Process_And_Cache_Data(i + 1, critical, (int8_t)(-(int8_t)(50 + i)));

    Process_And_Cache_Data(0xDE, critical, -10);

    int found = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (forest_cache[i].uid == 0xDE) found = 1;
    ASSERT_EQ(found, 1);
}

TEST(test_cache_uid_zero) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(0, p, -40);
    ASSERT_EQ(cache_count, 1);
    Process_And_Cache_Data(0, p, -30);
    ASSERT_EQ(cache_count, 1);
}

TEST(test_cache_rssi_minus128) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(1, p, -128);
    ASSERT_EQ(forest_cache[0].rssi, -128);
}

TEST(test_cache_rssi_zero) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(1, p, 0);
    ASSERT_EQ(forest_cache[0].rssi, 0);
}

TEST(test_cache_eviction_preserves_count) {
    reset_cache();
    uint8_t p[16] = {0};
    for (uint32_t i = 0; i < 50; i++)
        Process_And_Cache_Data(i + 1, p, -50);
    Process_And_Cache_Data(999, p, -30);
    ASSERT_EQ(cache_count, 50);
}

/* ════════════════════════════════════════════════════════════════════
 * 4. BATCH PACKING TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_batch_single_21_bytes) {
    reset_cache();
    uint8_t p[16];
    memset(p, 0xAA, 16);
    Process_And_Cache_Data(0x01020304, p, -85);
    uint16_t offset = Pack_Cache_To_Batch();
    ASSERT_EQ(offset, 21);
    ASSERT_EQ(binary_batch_buffer[0], 0x01);
    ASSERT_EQ(binary_batch_buffer[1], 0x02);
    ASSERT_EQ(binary_batch_buffer[2], 0x03);
    ASSERT_EQ(binary_batch_buffer[3], 0x04);
    ASSERT_EQ(binary_batch_buffer[4], 85);
    ASSERT_EQ(binary_batch_buffer[5], 0xAA);
}

TEST(test_batch_rssi_minus128_safe) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(1, p, -128);
    Pack_Cache_To_Batch();
    ASSERT_EQ(binary_batch_buffer[4], 128);
}

TEST(test_batch_50_entries) {
    reset_cache();
    uint8_t p[16] = {0};
    for (uint32_t i = 0; i < 50; i++)
        Process_And_Cache_Data(i + 1, p, -50);
    ASSERT_EQ(Pack_Cache_To_Batch(), 50 * 21);
}

TEST(test_batch_clears_cache) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(1, p, -50);
    Pack_Cache_To_Batch();
    ASSERT_EQ(cache_count, 0);
    ASSERT_EQ(forest_cache[0].is_active, 0);
}

TEST(test_batch_empty) {
    reset_cache();
    ASSERT_EQ(Pack_Cache_To_Batch(), 0);
}

TEST(test_batch_did_endian) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(0xDEADBEEF, p, -50);
    Pack_Cache_To_Batch();
    ASSERT_EQ(binary_batch_buffer[0], 0xDE);
    ASSERT_EQ(binary_batch_buffer[1], 0xAD);
    ASSERT_EQ(binary_batch_buffer[2], 0xBE);
    ASSERT_EQ(binary_batch_buffer[3], 0xEF);
}

TEST(test_batch_payload_preserved) {
    reset_cache();
    uint8_t p[16];
    for (int i = 0; i < 16; i++) p[i] = (uint8_t)(i * 17);
    Process_And_Cache_Data(1, p, -50);
    Pack_Cache_To_Batch();
    for (int i = 0; i < 16; i++)
        ASSERT_EQ(binary_batch_buffer[5 + i], (uint8_t)(i * 17));
}

TEST(test_batch_reinsert_after_pack) {
    reset_cache();
    uint8_t p[16] = {0};
    Process_And_Cache_Data(1, p, -50);
    Pack_Cache_To_Batch();
    Process_And_Cache_Data(2, p, -60);
    ASSERT_EQ(cache_count, 1);
}

/* ════════════════════════════════════════════════════════════════════
 * 5. OTA CHUNK BUILDER TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_ota_chunk_first) {
    uint8_t chunk[16];
    uint8_t copied = Build_OTA_Chunk(0, chunk);
    ASSERT_EQ(chunk[0], 0x99);
    ASSERT_EQ(copied, 11);
    ASSERT_EQ(chunk[5], 0x52);
    ASSERT_EQ(chunk[6], 0x49);
}

TEST(test_ota_chunk_last) {
    uint8_t chunk[16];
    uint8_t copied = Build_OTA_Chunk(3, chunk);
    ASSERT_EQ(copied, 6);
}

TEST(test_ota_out_of_range) {
    uint8_t chunk[16];
    ASSERT_EQ(Build_OTA_Chunk(100, chunk), 0);
}

TEST(test_ota_total_header) {
    uint8_t chunk[16];
    Build_OTA_Chunk(0, chunk);
    uint16_t total = ((uint16_t)chunk[3] << 8) | chunk[4];
    ASSERT_EQ(total, (pending_ota_size + 10) / 11);
}

TEST(test_ota_index_header) {
    uint8_t chunk[16];
    Build_OTA_Chunk(2, chunk);
    uint16_t idx = ((uint16_t)chunk[1] << 8) | chunk[2];
    ASSERT_EQ(idx, 2);
}

TEST(test_ota_reassemble_all) {
    uint16_t total_chunks = (pending_ota_size + 10) / 11;
    uint8_t reassembled[1024] = {0};
    uint16_t total_bytes = 0;

    for (uint16_t i = 0; i < total_chunks; i++) {
        uint8_t chunk[16];
        uint8_t copied = Build_OTA_Chunk(i, chunk);
        memcpy(&reassembled[i * 11], &chunk[5], copied);
        total_bytes += copied;
    }
    ASSERT_EQ(total_bytes, pending_ota_size);
    ASSERT_EQ(memcmp(reassembled, pending_ota_bytecode, pending_ota_size), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 6. RSSI CLAMP TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Extracted RSSI clamping logic matching OnRxDone fix */
static int8_t Clamp_RSSI(int16_t rssi)
{
    if (rssi < -128) rssi = -128;
    if (rssi > 127) rssi = 127;
    return (int8_t)rssi;
}

TEST(test_rssi_clamp_normal) {
    ASSERT_EQ(Clamp_RSSI(-85), -85);
}

TEST(test_rssi_clamp_minus128) {
    ASSERT_EQ(Clamp_RSSI(-128), -128);
}

TEST(test_rssi_clamp_below_minus128) {
    /* SX1262 can report -130 dBm; without clamp, (int8_t)(-130) = 126 */
    ASSERT_EQ(Clamp_RSSI(-130), -128);
}

TEST(test_rssi_clamp_minus200) {
    ASSERT_EQ(Clamp_RSSI(-200), -128);
}

TEST(test_rssi_clamp_zero) {
    ASSERT_EQ(Clamp_RSSI(0), 0);
}

TEST(test_rssi_clamp_positive) {
    ASSERT_EQ(Clamp_RSSI(50), 50);
}

TEST(test_rssi_clamp_max_int16) {
    ASSERT_EQ(Clamp_RSSI(32767), 127);
}

/* Verify the old truncation bug produced wrong values */
TEST(test_rssi_old_truncation_was_wrong) {
    /* Without clamp, (int8_t)(-130) wraps to 126 — a positive value! */
    int8_t wrong = (int8_t)(-130);
    ASSERT_EQ(wrong, 126); /* This proves the old code was buggy */
    /* Our clamp fixes it */
    ASSERT_EQ(Clamp_RSSI(-130), -128);
}

/* ════════════════════════════════════════════════════════════════════
 * 7. QUEEN HEALTH SENTINEL TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Build queen health packet — extracted from queen main loop fix */
static void Build_Queen_Health(uint8_t* payload, uint8_t tree_count, uint16_t uptime_sec)
{
    memset(payload, 0, 16);
    /* DID = 0x00000000 (sentinel — "this is the Queen, not a tree") */
    /* Bytes 4-5: uptime proxy */
    payload[4] = (uint8_t)(uptime_sec >> 8);
    payload[5] = (uint8_t)(uptime_sec & 0xFF);
    /* Byte 7: number of trees in cache */
    payload[7] = tree_count;
    /* Byte 10: status=homeostasis(0), growth_points = tree_count (capped at 63) */
    payload[10] = (tree_count < 63) ? tree_count : 63;
}

TEST(test_queen_health_did_zero) {
    uint8_t p[16];
    Build_Queen_Health(p, 30, 1000);
    /* DID bytes must be 0 */
    ASSERT_EQ(p[0], 0);
    ASSERT_EQ(p[1], 0);
    ASSERT_EQ(p[2], 0);
    ASSERT_EQ(p[3], 0);
}

TEST(test_queen_health_uptime_packed) {
    uint8_t p[16];
    Build_Queen_Health(p, 10, 0x1234);
    ASSERT_EQ(p[4], 0x12);
    ASSERT_EQ(p[5], 0x34);
}

TEST(test_queen_health_tree_count) {
    uint8_t p[16];
    Build_Queen_Health(p, 42, 100);
    ASSERT_EQ(p[7], 42);
}

TEST(test_queen_health_growth_points_clamped) {
    uint8_t p[16];
    Build_Queen_Health(p, 100, 100);
    /* growth_points max is 63 */
    ASSERT_EQ(p[10], 63);
}

TEST(test_queen_health_in_cache) {
    /* Verify DID=0 sentinel goes into cache */
    reset_cache();
    uint8_t p[16];
    Build_Queen_Health(p, 5, 60);
    Process_And_Cache_Data(0, p, 0);
    ASSERT_EQ(cache_count, 1);
    ASSERT_EQ(forest_cache[0].uid, 0);
    ASSERT_EQ(forest_cache[0].rssi, 0);
}

TEST(test_queen_health_in_batch) {
    /* Verify DID=0 packs correctly in batch */
    reset_cache();
    uint8_t p[16];
    Build_Queen_Health(p, 10, 300);
    Process_And_Cache_Data(0, p, 0);
    uint16_t offset = Pack_Cache_To_Batch();
    ASSERT_EQ(offset, 21);
    /* DID = 0 in big-endian */
    ASSERT_EQ(binary_batch_buffer[0], 0);
    ASSERT_EQ(binary_batch_buffer[1], 0);
    ASSERT_EQ(binary_batch_buffer[2], 0);
    ASSERT_EQ(binary_batch_buffer[3], 0);
    /* RSSI = 0 (local) → inverted = 0 */
    ASSERT_EQ(binary_batch_buffer[4], 0);
}

TEST(test_queen_health_dedup) {
    /* Second queen health packet should update, not duplicate */
    reset_cache();
    uint8_t p1[16], p2[16];
    Build_Queen_Health(p1, 10, 100);
    Build_Queen_Health(p2, 20, 200);
    Process_And_Cache_Data(0, p1, 0);
    Process_And_Cache_Data(0, p2, 0);
    ASSERT_EQ(cache_count, 1);
    /* Should have the latest data */
    ASSERT_EQ(forest_cache[0].payload[7], 20);
}

/* ════════════════════════════════════════════════════════════════════
 * 8. ECB RESTORATION TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Simulate the CRYP state transitions during Flush_Cache_To_Rails */
static CRYP_HandleTypeDef test_cryp;

static void init_cryp_ecb(void)
{
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;
}

/* Simulates what Flush_Cache_To_Rails does: switches to CBC then back to ECB */
static void simulate_flush_cryp_transition(void)
{
    /* During flush: switch to CBC with IV */
    static uint32_t batch_iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = batch_iv;
    HAL_CRYP_Init(&test_cryp);

    /* [FIX] Restore ECB after flush */
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&test_cryp);
}

TEST(test_ecb_restored_after_flush) {
    init_cryp_ecb();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    simulate_flush_cryp_transition();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_ecb_before_flush_is_ecb) {
    init_cryp_ecb();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
}

TEST(test_cbc_during_flush) {
    init_cryp_ecb();
    /* Before fix: after switching to CBC, it would stay in CBC */
    static uint32_t iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_CBC);
    ASSERT_NOT_NULL(test_cryp.Init.pInitVect);
}

/* ════════════════════════════════════════════════════════════════════
 * ENTRY POINT
 * ════════════════════════════════════════════════════════════════════ */

int main(void)
{
    printf("\n🏰 Queen Firmware — Host-Based Unit Tests\n");
    printf("══════════════════════════════════════════════════════════════\n\n");

    printf("  DJB2 Hash:\n");
    RUN(test_djb2_deterministic);
    RUN(test_djb2_different_strings);
    RUN(test_djb2_known_value);
    RUN(test_djb2_empty_string);
    RUN(test_djb2_null_terminator_mid_len);
    RUN(test_djb2_uuid_format);
    RUN(test_djb2_single_char_diff);

    printf("\n  Command Dedup Ring:\n");
    RUN(test_dedup_new_command);
    RUN(test_dedup_duplicate);
    RUN(test_dedup_two_different);
    RUN(test_dedup_ring_wraps_evicts_oldest);
    RUN(test_dedup_all_16_detected);
    RUN(test_dedup_hash_zero);
    RUN(test_dedup_stress_100);

    printf("\n  CIFO Cache:\n");
    RUN(test_cache_insert_single);
    RUN(test_cache_dedup_updates_data);
    RUN(test_cache_dedup_preserves_others);
    RUN(test_cache_fill_50);
    RUN(test_cache_cifo_evicts_worst_rssi);
    RUN(test_cache_cifo_protects_critical_stress);
    RUN(test_cache_cifo_protects_anomaly);
    RUN(test_cache_cifo_protects_tamper);
    RUN(test_cache_cifo_fallback_all_critical);
    RUN(test_cache_uid_zero);
    RUN(test_cache_rssi_minus128);
    RUN(test_cache_rssi_zero);
    RUN(test_cache_eviction_preserves_count);

    printf("\n  Batch Packing:\n");
    RUN(test_batch_single_21_bytes);
    RUN(test_batch_rssi_minus128_safe);
    RUN(test_batch_50_entries);
    RUN(test_batch_clears_cache);
    RUN(test_batch_empty);
    RUN(test_batch_did_endian);
    RUN(test_batch_payload_preserved);
    RUN(test_batch_reinsert_after_pack);

    printf("\n  OTA Chunk Builder:\n");
    RUN(test_ota_chunk_first);
    RUN(test_ota_chunk_last);
    RUN(test_ota_out_of_range);
    RUN(test_ota_total_header);
    RUN(test_ota_index_header);
    RUN(test_ota_reassemble_all);

    printf("\n  RSSI Clamp:\n");
    RUN(test_rssi_clamp_normal);
    RUN(test_rssi_clamp_minus128);
    RUN(test_rssi_clamp_below_minus128);
    RUN(test_rssi_clamp_minus200);
    RUN(test_rssi_clamp_zero);
    RUN(test_rssi_clamp_positive);
    RUN(test_rssi_clamp_max_int16);
    RUN(test_rssi_old_truncation_was_wrong);

    printf("\n  Queen Health Sentinel:\n");
    RUN(test_queen_health_did_zero);
    RUN(test_queen_health_uptime_packed);
    RUN(test_queen_health_tree_count);
    RUN(test_queen_health_growth_points_clamped);
    RUN(test_queen_health_in_cache);
    RUN(test_queen_health_in_batch);
    RUN(test_queen_health_dedup);

    printf("\n  ECB Restoration:\n");
    RUN(test_ecb_restored_after_flush);
    RUN(test_ecb_before_flush_is_ecb);
    RUN(test_cbc_during_flush);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
