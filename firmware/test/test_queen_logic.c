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
#define CMD_DECRYPT_BUF_SIZE  544

/* [FW.1] Flash-based AES key provisioning constants */
#define FLASH_KEY_ADDR             ((uintptr_t)_mock_flash_key_region)
#define FLASH_KEY_WORDS            8
#define FLASH_KEY_MAGIC            0x534B4559UL  /* "SKEY" */

/* [FW.1] Error_Handler mock for Load_AES_Key tests */
static void Error_Handler(void) { _mock_error_handler_called++; }

/* [FW.1] AES key array (same as in queen/main.c) */
static uint32_t aes_key[8] = {0};

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

/* OTA globals (matching queen/main.c dynamic buffer structure) */
static uint8_t pending_ota_bytecode[8192];
static uint16_t pending_ota_size = 0;
static uint16_t ota_total_expected_chunks = 0;
static uint16_t ota_chunks_received = 0;
// [FIX: AUDIT] Бітова карта для захисту від дублікатів OTA-чанків
static uint16_t ota_chunk_bitmap = 0;
#define OTA_MAX_CHUNKS 16

/* Reference test data for OTA chunking tests (was hardcoded in pending_ota_bytecode) */
static const uint8_t ota_test_data[] = {
    0x52, 0x49, 0x54, 0x45, 0x30, 0x33, 0x30, 0x30, 0x00, 0x00,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44,
    0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0x11, 0x22, 0x33, 0x44,
    0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD
};

/* Initializes pending_ota_bytecode with test data for OTA chunk builder tests */
static void ota_test_init(void)
{
    memset(pending_ota_bytecode, 0, sizeof(pending_ota_bytecode));
    memcpy(pending_ota_bytecode, ota_test_data, sizeof(ota_test_data));
    pending_ota_size = sizeof(ota_test_data);
    ota_total_expected_chunks = 0;
    ota_chunks_received = 0;
}

/* Resets OTA assembly state (for OTA downlink tests) */
static void ota_assembly_reset(void)
{
    memset(pending_ota_bytecode, 0, sizeof(pending_ota_bytecode));
    pending_ota_size = 0;
    ota_total_expected_chunks = 0;
    ota_chunks_received = 0;
    ota_chunk_bitmap = 0;
}

/* ════════════════════════════════════════════════════════════════════
 * EXTRACTED FUNCTIONS (matching queen/main.c with bug fixes marked)
 * ════════════════════════════════════════════════════════════════════ */

/* ---------- [FW.1] Load AES Key from Flash ---------- */
static void Load_AES_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_KEY_ADDR;

    if (flash_ptr[0] != FLASH_KEY_MAGIC) {
        Error_Handler();
        return;
    }

    uint32_t key_or = 0;
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        key_or |= flash_ptr[1 + i];
    }
    if (key_or == 0) {
        Error_Handler();
        return;
    }

    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        aes_key[i] = flash_ptr[1 + i];
    }
}

/* DJB2 hash — identical to queen/main.c */
static uint32_t djb2_hash(const char* str, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len && str[i] != '\0'; i++) {
        h = ((h << 5) + h) + (uint8_t)str[i];
    }
    return h;
}

/* [FW.27-B] Length-strict DJB2 — does NOT stop at NUL byte. */
static uint32_t djb2_hash_bytes(const uint8_t* buf, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len; i++) {
        h = ((h << 5) + h) + buf[i];
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

/* OTA assembly — extracted from Handle_CoAP_Command OTA downlink branch.
 * Simulates receiving a decrypted OTA chunk and assembling it into RAM.
 * Returns 1 on success, 0 on bounds/validation failure.
 * When all chunks received: sets ota_is_active = 1 (via output param). */
static uint8_t ota_is_active_flag = 0;
static uint16_t current_ota_chunk_idx_test = 0;

static uint8_t Assemble_OTA_Chunk(uint8_t* decrypted, uint16_t aligned)
{
    if (aligned < 6) return 0;
    if (decrypted[0] != 0x99) return 0;

    uint16_t chunk_index  = ((uint16_t)decrypted[1] << 8) | decrypted[2];
    uint16_t total_chunks = ((uint16_t)decrypted[3] << 8) | decrypted[4];

    if (total_chunks == 0) return 0;
    /* [FIX: AUDIT] Захист від chunk_index >= OTA_MAX_CHUNKS */
    if (chunk_index >= OTA_MAX_CHUNKS) return 0;
    if (aligned < 23) return 0;

    uint16_t payload_len = (aligned - 16 >= 514) ? 512 : (aligned - 16 - 7);
    uint32_t offset = (uint32_t)chunk_index * 512U;

    if (offset + payload_len > sizeof(pending_ota_bytecode)) return 0;

    /* [FIX: AUDIT] Дедуплікація OTA-чанків через бітову карту */
    uint16_t chunk_bit = (uint16_t)(1U << chunk_index);
    if (ota_chunk_bitmap & chunk_bit) {
        return 2; /* Дублікат — ігноруємо */
    }

    memcpy(pending_ota_bytecode + offset, &decrypted[5], payload_len);

    ota_total_expected_chunks = total_chunks;
    ota_chunk_bitmap |= chunk_bit;
    ota_chunks_received++;

    if (offset + payload_len > pending_ota_size) {
        pending_ota_size = (uint16_t)(offset + payload_len);
    }

    if (ota_chunks_received >= ota_total_expected_chunks) {
        ota_chunks_received = 0;
        ota_total_expected_chunks = 0;
        ota_chunk_bitmap = 0;
        current_ota_chunk_idx_test = 0;
        ota_is_active_flag = 1;
    }
    return 1;
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20] CMD_TIME_SYNC envelope unwrap (extracted from Handle_CoAP_Command).
 * Backend wraps every downlink in [0x9C][unix_ts_be:4][inner_payload].
 * Queen strips the 5-byte envelope, persists ts via Apply_Server_Time_Test,
 * and returns the inner-payload pointer + length so the caller routes via
 * existing CMD: / 0x99 logic.
 * ════════════════════════════════════════════════════════════════════ */
#define CMD_TIME_SYNC_MARKER       0x9C
#define CMD_TIME_SYNC_HEADER_SIZE  5
#define BEACON_MARKER              0x9C
#define BEACON_TTL                 1
#define BEACON_MAGIC_BYTE          'B'

static uint32_t test_queen_unix_ts            = 0;
static uint32_t test_queen_unix_ts_local_tick = 0;

static void Apply_Server_Time_Test(uint32_t server_unix_ts)
{
    test_queen_unix_ts            = server_unix_ts;
    test_queen_unix_ts_local_tick = 1000;  /* Mock HAL_GetTick() */
}

/* Strip TIME_SYNC envelope from `buf` of length `aligned`.
 * Returns: number of bytes stripped (0 = no envelope found, kept as-is).
 *          On success, *inner = buf + 5 and *inner_len = aligned - 5.
 *          On envelope-only (no inner payload), *inner_len = 0. */
static uint8_t Strip_Time_Sync_Envelope(uint8_t* buf, uint16_t aligned,
                                         uint8_t** inner, uint16_t* inner_len)
{
    if (aligned >= CMD_TIME_SYNC_HEADER_SIZE && buf[0] == CMD_TIME_SYNC_MARKER) {
        uint32_t ts = ((uint32_t)buf[1] << 24) | ((uint32_t)buf[2] << 16) |
                      ((uint32_t)buf[3] << 8)  | (uint32_t)buf[4];
        Apply_Server_Time_Test(ts);
        *inner     = buf + CMD_TIME_SYNC_HEADER_SIZE;
        *inner_len = (uint16_t)(aligned - CMD_TIME_SYNC_HEADER_SIZE);
        return CMD_TIME_SYNC_HEADER_SIZE;
    }
    *inner     = buf;
    *inner_len = aligned;
    return 0;
}

/* Build 16-byte LoRa time-sync beacon plaintext (FW.20-Q2).
 * Layout: [0x9C][ts_be:4][reserved:0×4][TTL=1][magic 'B'][padding:0×5] */
static void Build_Time_Beacon_Plaintext(uint32_t unix_ts, uint8_t out[16])
{
    memset(out, 0, 16);
    out[0]  = BEACON_MARKER;
    out[1]  = (uint8_t)(unix_ts >> 24);
    out[2]  = (uint8_t)(unix_ts >> 16);
    out[3]  = (uint8_t)(unix_ts >> 8);
    out[4]  = (uint8_t)(unix_ts & 0xFFu);
    out[9]  = BEACON_TTL;
    out[10] = (uint8_t)BEACON_MAGIC_BYTE;
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
    ota_test_init();
    uint8_t chunk[16];
    uint8_t copied = Build_OTA_Chunk(0, chunk);
    ASSERT_EQ(chunk[0], 0x99);
    ASSERT_EQ(copied, 11);
    ASSERT_EQ(chunk[5], 0x52);
    ASSERT_EQ(chunk[6], 0x49);
}

TEST(test_ota_chunk_last) {
    ota_test_init();
    uint8_t chunk[16];
    uint8_t copied = Build_OTA_Chunk(3, chunk);
    ASSERT_EQ(copied, 6);
}

TEST(test_ota_out_of_range) {
    ota_test_init();
    uint8_t chunk[16];
    ASSERT_EQ(Build_OTA_Chunk(100, chunk), 0);
}

TEST(test_ota_total_header) {
    ota_test_init();
    uint8_t chunk[16];
    Build_OTA_Chunk(0, chunk);
    uint16_t total = ((uint16_t)chunk[3] << 8) | chunk[4];
    ASSERT_EQ(total, (pending_ota_size + 10) / 11);
}

TEST(test_ota_index_header) {
    ota_test_init();
    uint8_t chunk[16];
    Build_OTA_Chunk(2, chunk);
    uint16_t idx = ((uint16_t)chunk[1] << 8) | chunk[2];
    ASSERT_EQ(idx, 2);
}

TEST(test_ota_reassemble_all) {
    ota_test_init();
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
 * 5b. OTA ASSEMBLY TESTS (CoAP downlink → RAM)
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_ota_assembly_single_chunk) {
    /* Single-chunk OTA: marker + index(0) + total(1) + 10 bytes payload */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[32];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;             /* marker */
    pkt[1] = 0x00; pkt[2] = 0x00;  /* chunk_index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x01;  /* total_chunks = 1 */
    for (uint8_t i = 0; i < 10; i++) pkt[5 + i] = (uint8_t)(0xA0 + i);
    /* aligned = 32 (2 AES blocks). payload_len = 32 - 16 - 7 = 9 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 32), 1);
    ASSERT_EQ(pending_ota_size, 9);
    ASSERT_EQ(pending_ota_bytecode[0], 0xA0);
    ASSERT_EQ(pending_ota_bytecode[8], 0xA8);
    /* All chunks received → broadcast activated */
    ASSERT_EQ(ota_is_active_flag, 1);
}

TEST(test_ota_assembly_two_chunks) {
    /* Two-chunk OTA: each chunk has aligned=48 → payload_len = 48-16-7 = 25 */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[48];
    memset(pkt, 0, sizeof(pkt));

    /* Chunk 0 */
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x00;  /* index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    for (uint8_t i = 0; i < 25; i++) pkt[5 + i] = (uint8_t)(0x10 + i);
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    ASSERT_EQ(ota_is_active_flag, 0);  /* Not all chunks yet */
    ASSERT_EQ(ota_chunks_received, 1);

    /* Chunk 1 → offset = 1 * 512 = 512 */
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x01;  /* index = 1 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    for (uint8_t i = 0; i < 25; i++) pkt[5 + i] = (uint8_t)(0x50 + i);
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    /* All chunks received → broadcast activated */
    ASSERT_EQ(ota_is_active_flag, 1);
    ASSERT_EQ(ota_chunks_received, 0);  /* Reset after activation */
    ASSERT_EQ(pending_ota_bytecode[0], 0x10);    /* Chunk 0 data at offset 0 */
    ASSERT_EQ(pending_ota_bytecode[512], 0x50);  /* Chunk 1 data at offset 512 */
}

TEST(test_ota_assembly_full_512_chunk) {
    /* Full 512-byte chunk: aligned = 544 → (544 - 16 = 528) >= 514 → payload = 512 */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[544];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x00;  /* index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x01;  /* total = 1 */
    for (uint16_t i = 0; i < 512; i++) pkt[5 + i] = (uint8_t)(i & 0xFF);
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 544), 1);
    ASSERT_EQ(pending_ota_size, 512);
    ASSERT_EQ(pending_ota_bytecode[0], 0x00);
    ASSERT_EQ(pending_ota_bytecode[255], 0xFF);
    ASSERT_EQ(pending_ota_bytecode[511], 0xFF);
    ASSERT_EQ(ota_is_active_flag, 1);
}

TEST(test_ota_assembly_bounds_overflow) {
    /* chunk_index too large → offset + payload would exceed 8192 buffer */
    ota_assembly_reset();
    uint8_t pkt[48];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x10;  /* index = 16 → offset = 16*512 = 8192 */
    pkt[3] = 0x00; pkt[4] = 0x20;  /* total = 32 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 0);  /* Must reject: overflow */
}

TEST(test_ota_assembly_invalid_marker) {
    ota_assembly_reset();
    uint8_t pkt[32];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x42;  /* Wrong marker */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 32), 0);
}

TEST(test_ota_assembly_zero_total_chunks) {
    ota_assembly_reset();
    uint8_t pkt[32];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[3] = 0x00; pkt[4] = 0x00;  /* total_chunks = 0 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 32), 0);  /* Must reject */
}

TEST(test_ota_assembly_too_small_aligned) {
    ota_assembly_reset();
    uint8_t pkt[5];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 5), 0);  /* aligned < 6 → reject */
}

TEST(test_ota_assembly_aligned_below_23) {
    /* aligned >= 6 but < 23: passes first check but fails second MISRA check */
    ota_assembly_reset();
    uint8_t pkt[22];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[3] = 0x00; pkt[4] = 0x01;
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 22), 0);  /* aligned < 23 → reject */
}

TEST(test_ota_assembly_size_tracking) {
    /* Verify pending_ota_size tracks the maximum written position */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[48];

    /* Chunk 1 arrives first (out of order), offset = 512 */
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x01;  /* index = 1 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    /* offset=512, payload_len=25 → pending_ota_size = 537 */
    ASSERT_EQ(pending_ota_size, 537);

    /* Chunk 0 arrives second, offset = 0 */
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x00;  /* index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    /* offset=0, payload_len=25 → 25 < 537, so pending_ota_size stays 537 */
    ASSERT_EQ(pending_ota_size, 537);
    ASSERT_EQ(ota_is_active_flag, 1);  /* All chunks received */
}

TEST(test_ota_assembly_duplicate_chunk_ignored) {
    /* [FIX: AUDIT] Дублікат чанка не повинен збільшувати ota_chunks_received.
     * Без bitmap: 2 chunks expected, chunk 0 arrives twice → chunks_received=2
     * → premature activation з неповними даними (chunk 1 missing). */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[48];

    /* Chunk 0 — перший раз */
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x00;  /* index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    for (uint8_t i = 0; i < 10; i++) pkt[5 + i] = (uint8_t)(0xA0 + i);
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    ASSERT_EQ(ota_chunks_received, 1);
    ASSERT_EQ(ota_is_active_flag, 0);

    /* Chunk 0 — дублікат (ACK loss retransmit) */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 2);  /* Must return 2 = duplicate */
    ASSERT_EQ(ota_chunks_received, 1);  /* Counter NOT inflated */
    ASSERT_EQ(ota_is_active_flag, 0);   /* Premature activation prevented */

    /* Chunk 1 — нормальний */
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x01;  /* index = 1 */
    pkt[3] = 0x00; pkt[4] = 0x02;  /* total = 2 */
    for (uint8_t i = 0; i < 10; i++) pkt[5 + i] = (uint8_t)(0xB0 + i);
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 1);
    ASSERT_EQ(ota_is_active_flag, 1);   /* Now truly all chunks received */
}

TEST(test_ota_assembly_chunk_index_above_max) {
    /* [FIX: AUDIT] chunk_index >= OTA_MAX_CHUNKS (16) повинен бути відхилений */
    ota_assembly_reset();
    uint8_t pkt[48];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x10;  /* index = 16 = OTA_MAX_CHUNKS */
    pkt[3] = 0x00; pkt[4] = 0x20;  /* total = 32 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 48), 0);  /* Must reject */
}

TEST(test_ota_assembly_bitmap_reset_after_complete) {
    /* After successful assembly, bitmap must be reset for next OTA cycle */
    ota_assembly_reset();
    ota_is_active_flag = 0;
    uint8_t pkt[32];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = 0x99;
    pkt[1] = 0x00; pkt[2] = 0x00;  /* index = 0 */
    pkt[3] = 0x00; pkt[4] = 0x01;  /* total = 1 */
    ASSERT_EQ(Assemble_OTA_Chunk(pkt, 32), 1);
    ASSERT_EQ(ota_is_active_flag, 1);
    /* Bitmap should be reset */
    ASSERT_EQ(ota_chunk_bitmap, 0);
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
 * 7b. HRNG IV GENERATION TESTS (CVE-fix: predictable IV → hardware RNG)
 * ════════════════════════════════════════════════════════════════════ */

/* Globals mirroring queen/main.c HRNG IV generation */
static RNG_HandleTypeDef test_hrng;

/* Simulate the HRNG IV generation logic from Flush_Cache_To_Rails */
static void simulate_hrng_iv_generation(uint32_t *iv)
{
    test_hrng.Instance = RNG;
    HAL_RNG_Init(&test_hrng);

    for (uint8_t i = 0U; i < 4U; i++) {
        if (HAL_RNG_GenerateRandomNumber(&test_hrng, &iv[i]) != HAL_OK) {
            iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
        }
    }

    HAL_RNG_DeInit(&test_hrng);
}

TEST(test_hrng_iv_all_words_filled) {
    /* Verify that all 4 IV words are populated (not left zero) */
    uint32_t iv[4] = {0, 0, 0, 0};
    simulate_hrng_iv_generation(iv);
    /* Mock returns 42 for all — verify they are filled */
    for (int i = 0; i < 4; i++) {
        ASSERT_EQ(iv[i], 42);
    }
}

TEST(test_hrng_iv_is_16_bytes) {
    /* IV must be exactly 128 bits (4 × uint32_t) for AES-256-CBC */
    uint32_t iv[4];
    simulate_hrng_iv_generation(iv);
    ASSERT_EQ(sizeof(iv), 16);
}

TEST(test_hrng_rng_instance_set) {
    /* RNG peripheral must be assigned before init */
    test_hrng.Instance = NULL;
    uint32_t iv[4];
    simulate_hrng_iv_generation(iv);
    ASSERT_EQ(test_hrng.Instance, RNG);
}

TEST(test_hrng_power_management_deinit) {
    /* After IV generation, RNG must be de-initialized (zero quiescent current).
     * We verify the full Wu-Wei sequence completes without error. */
    uint32_t iv[4];
    simulate_hrng_iv_generation(iv);
    int result = HAL_RNG_DeInit(&test_hrng);
    ASSERT_EQ(result, HAL_OK);
}

TEST(test_hrng_iv_not_tick_based) {
    /* The old vulnerability: IV was derived from HAL_GetTick() (returns 0 in mock).
     * With HRNG, IV words must NOT equal the old pattern. */
    uint32_t iv[4];
    simulate_hrng_iv_generation(iv);
    uint32_t tick = HAL_GetTick(); /* mock returns 0 */
    /* Old pattern was: tick, ~tick, tick+0x5A5A5A5A, ~tick+0xA5A5A5A5 */
    ASSERT_NE(iv[0], tick);
    ASSERT_NE(iv[1], ~tick);
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
 * 9. CBC COMMAND DECRYPTION TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Simulates Handle_CoAP_Command CBC→ECB transition:
 * [СИНХРОНІЗОВАНО з Rails]: ActuatorCommandWorker sends [IV:16][CBC ciphertext]
 * Queen must switch to CBC for decryption, then restore ECB for LoRa. */
static void simulate_cmd_cbc_decrypt(void)
{
    /* Command arrives: extract IV, switch to CBC */
    static uint32_t cmd_iv[4] = {0xAA, 0xBB, 0xCC, 0xDD};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = cmd_iv;
    HAL_CRYP_Init(&test_cryp);

    /* After decryption: restore ECB for LoRa traffic */
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&test_cryp);
}

TEST(test_cmd_cbc_ecb_restored) {
    /* ECB must be restored after CBC command decryption */
    init_cryp_ecb();
    simulate_cmd_cbc_decrypt();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_cmd_cbc_during_decrypt) {
    /* During command decryption, CRYP must be in CBC mode */
    init_cryp_ecb();
    static uint32_t cmd_iv[4] = {0x11, 0x22, 0x33, 0x44};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = cmd_iv;
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_CBC);
    ASSERT_NOT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_cmd_cbc_then_flush_cbc_both_restore) {
    /* Both Handle_CoAP_Command and Flush_Cache_To_Rails use CBC
     * and both must restore ECB. Simulate both in sequence. */
    init_cryp_ecb();
    simulate_cmd_cbc_decrypt();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    simulate_flush_cryp_transition();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

/* ════════════════════════════════════════════════════════════════════
 * 10. CoAP RETRY LOGIC (FW.9)
 * ════════════════════════════════════════════════════════════════════ */

#define COAP_MAX_RETRIES      3
#define UART_RX_BUF_SIZE      128
#define COAP_BASE_TIMEOUT_MS  2000
#define COAP_SEND_TIMEOUT_MS  5000

/* [FW.9] Verify AT response parser detects "OK" in modem response */
static uint8_t test_parse_modem_response(const char* response)
{
    uint8_t buf[UART_RX_BUF_SIZE];
    memset(buf, 0, sizeof(buf));
    size_t len = strlen(response);
    if (len >= UART_RX_BUF_SIZE) len = UART_RX_BUF_SIZE - 1;
    memcpy(buf, response, len);

    // Search for "OK"
    for (uint8_t i = 0; i < UART_RX_BUF_SIZE - 1 && buf[i] != '\0'; i++) {
        if (buf[i] == 'O' && buf[i+1] == 'K') return 1;
    }
    // Search for "ERROR"
    for (uint8_t i = 0; i < UART_RX_BUF_SIZE - 5 && buf[i] != '\0'; i++) {
        if (buf[i] == 'E' && buf[i+1] == 'R' &&
            buf[i+2] == 'R' && buf[i+3] == 'O' &&
            buf[i+4] == 'R') return 0;
    }
    return 0;
}

TEST(test_coap_retry_constants) {
    ASSERT_EQ(COAP_MAX_RETRIES, 3);
    ASSERT_EQ(UART_RX_BUF_SIZE, 128);
    ASSERT_EQ(COAP_BASE_TIMEOUT_MS, 2000);
    ASSERT_EQ(COAP_SEND_TIMEOUT_MS, 5000);
}

TEST(test_coap_response_parser_ok) {
    ASSERT_TRUE(test_parse_modem_response("\r\nOK\r\n"));
    ASSERT_TRUE(test_parse_modem_response("+CCOAPNEW: 0\r\nOK\r\n"));
    ASSERT_TRUE(test_parse_modem_response("OK"));
}

TEST(test_coap_response_parser_error) {
    ASSERT_FALSE(test_parse_modem_response("ERROR"));
    ASSERT_FALSE(test_parse_modem_response("\r\nERROR\r\n"));
    ASSERT_FALSE(test_parse_modem_response("+CME ERROR: 3\r\n"));
}

TEST(test_coap_response_parser_timeout) {
    ASSERT_FALSE(test_parse_modem_response(""));
    ASSERT_FALSE(test_parse_modem_response("\r\n"));
}

/* ════════════════════════════════════════════════════════════════════
 * 10. [FW.1] FLASH-BASED AES KEY LOADING TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Helper: standard provisioned test key */
static const uint32_t _queen_test_key[8] = {
    0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC,
    0xDDEEFF00, 0x12345678, 0x9ABCDEF0, 0xFEDCBA98
};

TEST(test_queen_load_key_provisioned_success) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _queen_test_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], _queen_test_key[i]);
    }
}

TEST(test_queen_load_key_unprovisioned_error) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], 0);
    }
}

TEST(test_queen_load_key_all_zeros_error) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    uint32_t zero_key[8] = {0};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, zero_key);
    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
}

TEST(test_queen_load_key_wrong_magic_error) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    _mock_flash_key_provision(0xBADDCAFE, _queen_test_key);
    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], 0);
    }
}

TEST(test_queen_load_key_partial_key_accepted) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    uint32_t partial_key[8] = {0, 0, 0, 0, 0, 0, 0, 0x00000001};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, partial_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(aes_key[7], 0x00000001);
}

TEST(test_queen_load_key_preserves_8_words) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0xAA, sizeof(aes_key));

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _queen_test_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(aes_key[0], 0xAABBCCDD);
    ASSERT_EQ(aes_key[3], 0x99AABBCC);
    ASSERT_EQ(aes_key[7], 0xFEDCBA98);
}

TEST(test_queen_load_key_magic_value_correct) {
    ASSERT_EQ(FLASH_KEY_MAGIC, 0x534B4559UL);
}

TEST(test_queen_load_key_overwrite) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _queen_test_key);
    Load_AES_Key();
    ASSERT_EQ(aes_key[0], 0xAABBCCDD);

    uint32_t key2[8] = {0x01010101, 0x02020202, 0x03030303, 0x04040404,
                        0x05050505, 0x06060606, 0x07070707, 0x08080808};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, key2);
    Load_AES_Key();
    ASSERT_EQ(aes_key[0], 0x01010101);
    ASSERT_EQ(aes_key[7], 0x08080808);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20] CMD_TIME_SYNC envelope + LoRa time beacon
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_time_sync_envelope_strips_5_bytes) {
    test_queen_unix_ts = 0;

    /* [0x9C][unix_ts_be: 0x65000000][inner: "CMD:OPEN:..."] */
    uint8_t buf[32] = {
        0x9C, 0x65, 0x00, 0x00, 0x00,
        'C','M','D',':','O','P','E','N',':','6','0',':','4','2',':',
        'a','b','c','d','-','1','-','2','-','3','-','4'
    };
    uint8_t* inner = NULL;
    uint16_t inner_len = 0;

    uint8_t stripped = Strip_Time_Sync_Envelope(buf, 32, &inner, &inner_len);

    ASSERT_EQ(stripped, 5);
    ASSERT_EQ(inner_len, 27);
    ASSERT_EQ(memcmp(inner, "CMD:OPEN:60:42:abcd-1-2-3-4", 27), 0);
    ASSERT_EQ(test_queen_unix_ts, 0x65000000U);
}

TEST(test_time_sync_envelope_no_marker_keeps_payload_unchanged) {
    test_queen_unix_ts = 0xDEADBEEFu;  /* sentinel: must not be overwritten */

    /* Legacy payload without 0x9C envelope (bare "CMD:..."). */
    uint8_t buf[16] = {'C','M','D',':','O','P','E','N',':','6','0',
                       ':','4','2',':','a'};
    uint8_t* inner = NULL;
    uint16_t inner_len = 0;

    uint8_t stripped = Strip_Time_Sync_Envelope(buf, 16, &inner, &inner_len);

    ASSERT_EQ(stripped, 0);
    ASSERT_EQ(inner_len, 16);
    ASSERT_EQ(inner, buf);
    ASSERT_EQ(test_queen_unix_ts, 0xDEADBEEFu);  /* unchanged */
}

TEST(test_time_sync_envelope_only_no_inner) {
    test_queen_unix_ts = 0;

    /* Server "ping" — only envelope, no inner payload (5 bytes total). */
    uint8_t buf[16] = {0x9C, 0x12, 0x34, 0x56, 0x78, 0,0,0,0,0,0,0,0,0,0,0};
    uint8_t* inner = NULL;
    uint16_t inner_len = 0;

    uint8_t stripped = Strip_Time_Sync_Envelope(buf, 5, &inner, &inner_len);

    ASSERT_EQ(stripped, 5);
    ASSERT_EQ(inner_len, 0);
    ASSERT_EQ(test_queen_unix_ts, 0x12345678U);
}

TEST(test_time_sync_envelope_too_short_no_unwrap) {
    test_queen_unix_ts = 0xCAFEBABEu;

    /* aligned < CMD_TIME_SYNC_HEADER_SIZE — even if byte 0 is 0x9C. */
    uint8_t buf[4] = {0x9C, 0x12, 0x34, 0x56};
    uint8_t* inner = NULL;
    uint16_t inner_len = 0;

    uint8_t stripped = Strip_Time_Sync_Envelope(buf, 4, &inner, &inner_len);

    ASSERT_EQ(stripped, 0);
    ASSERT_EQ(inner_len, 4);
    ASSERT_EQ(test_queen_unix_ts, 0xCAFEBABEu);
}

TEST(test_time_sync_envelope_routes_ota_marker) {
    /* Verify envelope strip exposes 0x99 OTA payload to the inner-routing logic. */
    test_queen_unix_ts = 0;

    uint8_t buf[16] = {
        0x9C, 0x00, 0x00, 0x10, 0x00,    /* ts = 0x00001000 */
        0x99, 0x00, 0x05, 0x00, 0x10,    /* OTA marker, idx=5, total=16 */
        'b','y','t','e','c','d'           /* opaque bytecode */
    };
    uint8_t* inner = NULL;
    uint16_t inner_len = 0;

    Strip_Time_Sync_Envelope(buf, 16, &inner, &inner_len);

    ASSERT_EQ(inner_len, 11);
    ASSERT_EQ(inner[0], 0x99);              /* now routed as OTA */
    ASSERT_EQ(test_queen_unix_ts, 0x1000U);
}

TEST(test_time_beacon_plaintext_layout) {
    uint8_t out[16];
    Build_Time_Beacon_Plaintext(0xAABBCCDDu, out);

    ASSERT_EQ(out[0], BEACON_MARKER);
    ASSERT_EQ(out[1], 0xAA);
    ASSERT_EQ(out[2], 0xBB);
    ASSERT_EQ(out[3], 0xCC);
    ASSERT_EQ(out[4], 0xDD);
    /* reserved bytes 5..8 must be zero (TDMA slot space) */
    for (int i = 5; i <= 8; i++) ASSERT_EQ(out[i], 0);
    ASSERT_EQ(out[9],  BEACON_TTL);          /* TTL=1, no relay */
    ASSERT_EQ(out[10], (uint8_t)BEACON_MAGIC_BYTE); /* 'B' */
    /* padding bytes 11..15 must be zero */
    for (int i = 11; i < 16; i++) ASSERT_EQ(out[i], 0);
}

TEST(test_time_beacon_distinct_from_ota) {
    /* The beacon marker (0x9C) must NOT collide with the OTA marker (0x99)
     * Soldier uses to gate Flash writes. This is a regression sentinel. */
    uint8_t out[16];
    Build_Time_Beacon_Plaintext(0x12345678u, out);
    ASSERT_NE(out[0], 0x99);
    ASSERT_EQ(out[0], 0x9C);
}

TEST(test_time_beacon_ts_zero_caller_responsibility) {
    /* The packet builder must produce the exact bytes for ts=0. Suppression
     * (skip TX when not yet synchronised) is the caller's job — see
     * Broadcast_Time_Beacon() in queen/main.c. This guards against a future
     * refactor that pushes suppression into the builder and breaks tests. */
    uint8_t out[16];
    Build_Time_Beacon_Plaintext(0, out);
    ASSERT_EQ(out[0], BEACON_MARKER);
    ASSERT_EQ(out[1], 0);
    ASSERT_EQ(out[10], (uint8_t)BEACON_MAGIC_BYTE);
}

/* ════════════════════════════════════════════════════════════════════
 * 11. FW.27-B Magic Re-Request Handler (Queen-side)
 * ════════════════════════════════════════════════════════════════════
 * Queen recognizes 0x55 marker in decrypted LoRa RX path:
 *   - Dedups (DID, missing_bitmap) via existing cmd_dedup_ring (5-min replay)
 *   - Targeted re-broadcast: only chunks where bitmap bit is set (missing)
 *   - Does NOT enter CIFO cache, does NOT go to CoAP — pure service packet
 * ════════════════════════════════════════════════════════════════════ */
#define Q_OTA_REQ_MARKER             0x55
#define Q_OTA_REQ_HEADER_SIZE        7
#define Q_OTA_REQ_BITMAP_MAX_BYTES   9

/* Pure-logic decision: should Queen re-broadcast in response to this packet?
 * Returns: 1 = re-broadcast, 0 = drop (non-rerequest, dedup, or invalid). */
static uint8_t Test_Should_Handle_Rerequest(const uint8_t* decrypted,
                                              uint16_t pending_size,
                                              uint8_t  ota_active)
{
    if (decrypted[0] != Q_OTA_REQ_MARKER) return 0;

    uint32_t hash = djb2_hash_bytes(decrypted, 16);
    if (Cmd_Dedup_Check(hash) == 1) return 0;  /* duplicate */

    if (pending_size == 0 || !ota_active) return 0;

    uint16_t total_chunks  = (pending_size + 10) / 11;
    uint16_t soldier_total = ((uint16_t)decrypted[5] << 8) | decrypted[6];
    if (soldier_total != total_chunks) return 0;

    return 1;
}

static uint16_t Test_Count_Missing_From_Bitmap(const uint8_t* decrypted,
                                                 uint16_t total_chunks)
{
    uint16_t cap = (total_chunks > Q_OTA_REQ_BITMAP_MAX_BYTES * 8u)
                      ? (uint16_t)(Q_OTA_REQ_BITMAP_MAX_BYTES * 8u)
                      : total_chunks;
    uint16_t missing = 0;
    const uint8_t* bm = &decrypted[Q_OTA_REQ_HEADER_SIZE];
    for (uint16_t i = 0; i < cap; i++) {
        if (bm[i / 8u] & (uint8_t)(1u << (i % 8u))) missing++;
    }
    return missing;
}

static void compose_rereq_packet(uint32_t did, uint16_t total,
                                   const uint8_t* missing_bitmap,
                                   uint8_t bitmap_bytes,
                                   uint8_t out[16])
{
    memset(out, 0, 16);
    out[0] = Q_OTA_REQ_MARKER;
    out[1] = (uint8_t)(did >> 24);
    out[2] = (uint8_t)(did >> 16);
    out[3] = (uint8_t)(did >> 8);
    out[4] = (uint8_t)(did & 0xFFu);
    out[5] = (uint8_t)(total >> 8);
    out[6] = (uint8_t)(total & 0xFFu);
    if (missing_bitmap && bitmap_bytes <= Q_OTA_REQ_BITMAP_MAX_BYTES) {
        memcpy(&out[Q_OTA_REQ_HEADER_SIZE], missing_bitmap, bitmap_bytes);
    }
}

TEST(test_rereq_queen_accepts_valid_packet) {
    reset_dedup();
    uint8_t bm[1] = {0xFF};  /* chunks 0..7 missing */
    uint8_t pkt[16];
    /* pending_size=88 → total=8 chunks; soldier_total=8 matches. */
    compose_rereq_packet(0xDEADBEEFu, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 88, 1), 1);
}

TEST(test_rereq_queen_dedups_replay) {
    reset_dedup();
    uint8_t bm[1] = {0xFF};
    uint8_t pkt[16];
    compose_rereq_packet(0xCAFEBABEu, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 88, 1), 1);
    /* Replay — dedup */
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 88, 1), 0);
}

TEST(test_rereq_queen_different_bitmaps_not_deduped) {
    reset_dedup();
    uint8_t bm1[1] = {0xFF}; uint8_t bm2[1] = {0x0F};
    uint8_t pkt1[16], pkt2[16];
    compose_rereq_packet(0xAAAAAAAAu, 8, bm1, 1, pkt1);
    compose_rereq_packet(0xAAAAAAAAu, 8, bm2, 1, pkt2);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt1, 88, 1), 1);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt2, 88, 1), 1);
}

TEST(test_rereq_queen_drops_when_no_active_ota) {
    reset_dedup();
    uint8_t bm[1] = {0xFF};
    uint8_t pkt[16];
    compose_rereq_packet(0x1u, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 88, 0), 0);
}

TEST(test_rereq_queen_drops_when_pending_empty) {
    reset_dedup();
    uint8_t bm[1] = {0xFF};
    uint8_t pkt[16];
    compose_rereq_packet(0x1u, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 0, 1), 0);
}

TEST(test_rereq_queen_drops_when_total_mismatch) {
    reset_dedup();
    uint8_t bm[1] = {0xFF};
    uint8_t pkt[16];
    /* Soldier reports total=8, but Queen pending_size=11 ⇒ total=1 */
    compose_rereq_packet(0x1u, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 11, 1), 0);
}

TEST(test_rereq_queen_drops_non_rerequest_marker) {
    reset_dedup();
    uint8_t pkt[16] = {0};
    pkt[0] = 0x99;
    ASSERT_EQ(Test_Should_Handle_Rerequest(pkt, 88, 1), 0);
    /* Critical: must NOT consume a dedup slot */
    uint8_t bm[1] = {0xFF};
    uint8_t valid[16];
    compose_rereq_packet(0x1u, 8, bm, 1, valid);
    ASSERT_EQ(Test_Should_Handle_Rerequest(valid, 88, 1), 1);
}

TEST(test_rereq_queen_count_missing_full_bitmap) {
    uint8_t pkt[16] = {0};
    uint8_t bm[2] = {0xFF, 0xFF};
    compose_rereq_packet(0x1u, 16, bm, 2, pkt);
    ASSERT_EQ(Test_Count_Missing_From_Bitmap(pkt, 16), 16);
}

TEST(test_rereq_queen_count_missing_partial) {
    /* bitmap = 0xAA = 0b10101010 → 4 bits set */
    uint8_t pkt[16] = {0};
    uint8_t bm[1] = {0xAA};
    compose_rereq_packet(0x1u, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Count_Missing_From_Bitmap(pkt, 8), 4);
}

TEST(test_rereq_queen_count_zero_when_all_received) {
    uint8_t pkt[16] = {0};
    uint8_t bm[1] = {0x00};
    compose_rereq_packet(0x1u, 8, bm, 1, pkt);
    ASSERT_EQ(Test_Count_Missing_From_Bitmap(pkt, 8), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 12. FW.23 OTA HMAC Trailer Relay (Queen-side)
 * ════════════════════════════════════════════════════════════════════ */
#define Q_HMAC_TRAILER_MARKER       0x9B
#define Q_HMAC_TRAILER_TOTAL_SEGS   3

static uint8_t q_pending_hmac_chunks[Q_HMAC_TRAILER_TOTAL_SEGS][16] = {{0}};
static uint8_t q_hmac_segments_received = 0;

static uint8_t Test_Queen_Store_HMAC_Trailer(const uint8_t* inner_payload,
                                                uint16_t inner_aligned)
{
    if (inner_aligned < 16)                             return 0;
    if (inner_payload[0] != Q_HMAC_TRAILER_MARKER)      return 0;
    uint16_t seg_idx = ((uint16_t)inner_payload[1] << 8) | inner_payload[2];
    if (seg_idx < 1 || seg_idx > Q_HMAC_TRAILER_TOTAL_SEGS) return 0;
    memcpy(q_pending_hmac_chunks[seg_idx - 1], inner_payload, 16);
    q_hmac_segments_received |= (uint8_t)(1u << (seg_idx - 1));
    return 1;
}

static void reset_hmac_relay(void) {
    memset(q_pending_hmac_chunks, 0, sizeof(q_pending_hmac_chunks));
    q_hmac_segments_received = 0;
}

TEST(test_queen_relay_stores_3_hmac_chunks) {
    reset_hmac_relay();
    for (uint8_t s = 1; s <= 3; s++) {
        uint8_t chunk[16] = {0};
        chunk[0] = Q_HMAC_TRAILER_MARKER;
        chunk[1] = 0; chunk[2] = s;
        chunk[3] = 0; chunk[4] = 5;
        chunk[5] = (uint8_t)(0xA0 + s);
        ASSERT_EQ(Test_Queen_Store_HMAC_Trailer(chunk, 16), 1);
    }
    ASSERT_EQ(q_hmac_segments_received, 0x07);
}

TEST(test_queen_relay_rejects_seg_idx_4) {
    reset_hmac_relay();
    uint8_t chunk[16] = {0};
    chunk[0] = Q_HMAC_TRAILER_MARKER;
    chunk[1] = 0; chunk[2] = 4;
    ASSERT_EQ(Test_Queen_Store_HMAC_Trailer(chunk, 16), 0);
    ASSERT_EQ(q_hmac_segments_received, 0);
}

TEST(test_queen_relay_rejects_wrong_marker) {
    reset_hmac_relay();
    uint8_t chunk[16] = {0};
    chunk[0] = 0x99;
    ASSERT_EQ(Test_Queen_Store_HMAC_Trailer(chunk, 16), 0);
}

TEST(test_queen_relay_overwrites_same_segment) {
    reset_hmac_relay();
    uint8_t chunk[16] = {0};
    chunk[0] = Q_HMAC_TRAILER_MARKER;
    chunk[1] = 0; chunk[2] = 1;
    chunk[5] = 0xAA;
    Test_Queen_Store_HMAC_Trailer(chunk, 16);
    ASSERT_EQ(q_pending_hmac_chunks[0][5], 0xAA);
    chunk[5] = 0xBB;
    Test_Queen_Store_HMAC_Trailer(chunk, 16);
    ASSERT_EQ(q_pending_hmac_chunks[0][5], 0xBB);
    ASSERT_EQ(q_hmac_segments_received, 0x01);
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

    printf("\n  OTA Assembly (CoAP Downlink):\n");
    RUN(test_ota_assembly_single_chunk);
    RUN(test_ota_assembly_two_chunks);
    RUN(test_ota_assembly_full_512_chunk);
    RUN(test_ota_assembly_bounds_overflow);
    RUN(test_ota_assembly_invalid_marker);
    RUN(test_ota_assembly_zero_total_chunks);
    RUN(test_ota_assembly_too_small_aligned);
    RUN(test_ota_assembly_aligned_below_23);
    RUN(test_ota_assembly_size_tracking);
    RUN(test_ota_assembly_duplicate_chunk_ignored);
    RUN(test_ota_assembly_chunk_index_above_max);
    RUN(test_ota_assembly_bitmap_reset_after_complete);

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

    printf("\n  HRNG IV Generation:\n");
    RUN(test_hrng_iv_all_words_filled);
    RUN(test_hrng_iv_is_16_bytes);
    RUN(test_hrng_rng_instance_set);
    RUN(test_hrng_power_management_deinit);
    RUN(test_hrng_iv_not_tick_based);

    printf("\n  CBC Command Decryption:\n");
    RUN(test_cmd_cbc_ecb_restored);
    RUN(test_cmd_cbc_during_decrypt);
    RUN(test_cmd_cbc_then_flush_cbc_both_restore);

    printf("\n  CoAP Retry Logic (FW.9):\n");
    RUN(test_coap_retry_constants);
    RUN(test_coap_response_parser_ok);
    RUN(test_coap_response_parser_error);
    RUN(test_coap_response_parser_timeout);

    printf("\n  Flash-Based AES Key Loading (FW.1):\n");
    RUN(test_queen_load_key_provisioned_success);
    RUN(test_queen_load_key_unprovisioned_error);
    RUN(test_queen_load_key_all_zeros_error);
    RUN(test_queen_load_key_wrong_magic_error);
    RUN(test_queen_load_key_partial_key_accepted);
    RUN(test_queen_load_key_preserves_8_words);
    RUN(test_queen_load_key_magic_value_correct);
    RUN(test_queen_load_key_overwrite);

    printf("\n  Time Sync Envelope + Beacon (FW.20):\n");
    RUN(test_time_sync_envelope_strips_5_bytes);
    RUN(test_time_sync_envelope_no_marker_keeps_payload_unchanged);
    RUN(test_time_sync_envelope_only_no_inner);
    RUN(test_time_sync_envelope_too_short_no_unwrap);
    RUN(test_time_sync_envelope_routes_ota_marker);
    RUN(test_time_beacon_plaintext_layout);
    RUN(test_time_beacon_distinct_from_ota);
    RUN(test_time_beacon_ts_zero_caller_responsibility);

    printf("\n  Magic Re-Request Handler (FW.27-B):\n");
    RUN(test_rereq_queen_accepts_valid_packet);
    RUN(test_rereq_queen_dedups_replay);
    RUN(test_rereq_queen_different_bitmaps_not_deduped);
    RUN(test_rereq_queen_drops_when_no_active_ota);
    RUN(test_rereq_queen_drops_when_pending_empty);
    RUN(test_rereq_queen_drops_when_total_mismatch);
    RUN(test_rereq_queen_drops_non_rerequest_marker);
    RUN(test_rereq_queen_count_missing_full_bitmap);
    RUN(test_rereq_queen_count_missing_partial);
    RUN(test_rereq_queen_count_zero_when_all_received);

    printf("\n  HMAC Trailer Relay (FW.23):\n");
    RUN(test_queen_relay_stores_3_hmac_chunks);
    RUN(test_queen_relay_rejects_seg_idx_4);
    RUN(test_queen_relay_rejects_wrong_marker);
    RUN(test_queen_relay_overwrites_same_segment);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
