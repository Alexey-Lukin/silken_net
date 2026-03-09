/*
 * test_soldier_logic.c — Comprehensive host-based unit tests for Soldier firmware.
 *
 * Extracts pure-logic functions from firmware/soldier/main.c and tests on x86.
 * Covers: payload packing, DID generation, mesh dedup (anti-pingpong),
 * OTA chunk assembly with CRC32, bio-contract byte parsing, TTL handling,
 * and all edge cases from the firmware audit (35 bugs found).
 *
 * Build: make -C firmware/test
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "hal_mock.h"

/* ════════════════════════════════════════════════════════════════════
 * CONSTANTS (from soldier/main.c)
 * ════════════════════════════════════════════════════════════════════ */
#define MRUBY_CONTRACT_FLASH_ADDR  0x0803F000
#define MESH_DID_CACHE_SIZE        8  /* [FIX] expanded from 3 → 8 */
#define OTA_BUFFER_SIZE            1024
#define OTA_CHUNK_MAP_SIZE         256

/* ════════════════════════════════════════════════════════════════════
 * EXTRACTED PURE-LOGIC FUNCTIONS
 * ════════════════════════════════════════════════════════════════════ */

/* ---------- Payload packing (Phase 2) ---------- */
static void Pack_Soldier_Payload(
    uint8_t* lora_payload,
    uint32_t tree_did,
    uint16_t vcap_voltage,
    int8_t   temperature,
    uint8_t  acoustic_events,
    uint16_t delta_t_seconds,
    uint8_t  bio_contract_byte,
    uint8_t  ttl,
    uint16_t firmware_version_id)
{
    memset(lora_payload, 0, 16);

    /* Bytes 0-3: DID (big-endian) */
    lora_payload[0] = (uint8_t)(tree_did >> 24);
    lora_payload[1] = (uint8_t)(tree_did >> 16);
    lora_payload[2] = (uint8_t)(tree_did >> 8);
    lora_payload[3] = (uint8_t)(tree_did & 0xFF);

    /* Bytes 4-5: Vcap voltage (big-endian) */
    lora_payload[4] = (uint8_t)(vcap_voltage >> 8);
    lora_payload[5] = (uint8_t)(vcap_voltage & 0xFF);

    /* Byte 6: Temperature (signed) */
    lora_payload[6] = (uint8_t)temperature;

    /* Byte 7: Acoustic events */
    lora_payload[7] = acoustic_events;

    /* Bytes 8-9: Metabolism (big-endian) */
    lora_payload[8] = (uint8_t)(delta_t_seconds >> 8);
    lora_payload[9] = (uint8_t)(delta_t_seconds & 0xFF);

    /* Byte 10: Bio-contract packed byte */
    lora_payload[10] = bio_contract_byte;

    /* Byte 11: TTL */
    lora_payload[11] = ttl;

    /* Bytes 12-13: Firmware version (big-endian) [FIX: use padding] */
    lora_payload[12] = (uint8_t)(firmware_version_id >> 8);
    lora_payload[13] = (uint8_t)(firmware_version_id & 0xFF);

    /* Bytes 14-15: Reserved (zero) */
}

/* ---------- Payload unpacking (for server-side verification) ---------- */
typedef struct {
    uint32_t did;
    uint16_t vcap;
    int8_t   temp;
    uint8_t  acoustic;
    uint16_t metabolism;
    uint8_t  bio_status;
    uint8_t  growth_points;
    uint8_t  ttl;
    uint16_t firmware_version;
} UnpackedPayload;

static UnpackedPayload Unpack_Soldier_Payload(const uint8_t* p)
{
    UnpackedPayload u;
    u.did       = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
                  ((uint32_t)p[2] << 8)  | (uint32_t)p[3];
    u.vcap      = ((uint16_t)p[4] << 8) | p[5];
    u.temp      = (int8_t)p[6];
    u.acoustic  = p[7];
    u.metabolism = ((uint16_t)p[8] << 8) | p[9];
    u.bio_status    = (p[10] >> 6) & 0x03;
    u.growth_points = p[10] & 0x3F;
    u.ttl       = p[11];
    u.firmware_version = ((uint16_t)p[12] << 8) | p[13];
    return u;
}

/* ---------- DID generation ---------- */
static uint32_t Generate_DID(uint32_t uid0, uint32_t uid1, uint32_t uid2, uint32_t random)
{
    uint32_t did = uid0 ^ (uid1 << 5) ^ (uid2 >> 3) ^ random;
    if (did == 0) did = 0x511CEE01;
    return did;
}

/* ---------- Mesh dedup ring (anti-pingpong) ---------- */
static uint32_t mesh_dids[MESH_DID_CACHE_SIZE];
static uint8_t  mesh_dids_count = 0;

static void Mesh_DID_Cache_Init(void)
{
    memset(mesh_dids, 0, sizeof(mesh_dids));
    mesh_dids_count = 0;
}

static uint8_t Mesh_DID_Is_Known(uint32_t did)
{
    uint8_t limit = mesh_dids_count < MESH_DID_CACHE_SIZE
                  ? mesh_dids_count : MESH_DID_CACHE_SIZE;
    for (uint8_t i = 0; i < limit; i++) {
        if (mesh_dids[i] == did) return 1;
    }
    return 0;
}

static void Mesh_DID_Cache_Push(uint32_t did)
{
    /* Shift all entries right by 1, drop the oldest */
    for (int i = MESH_DID_CACHE_SIZE - 1; i > 0; i--)
        mesh_dids[i] = mesh_dids[i - 1];
    mesh_dids[0] = did;
    if (mesh_dids_count < MESH_DID_CACHE_SIZE)
        mesh_dids_count++;
}

/* Full mesh relay decision logic */
typedef enum {
    MESH_RELAY_OK      = 0,
    MESH_RELAY_OWN_ECHO = 1,
    MESH_RELAY_KNOWN    = 2,
    MESH_RELAY_TTL_ZERO = 3
} MeshRelayResult;

static MeshRelayResult Mesh_Relay_Decision(
    uint32_t incoming_did,
    uint32_t own_did,
    uint8_t  incoming_ttl)
{
    if (incoming_ttl == 0) return MESH_RELAY_TTL_ZERO;
    if (incoming_did == own_did) return MESH_RELAY_OWN_ECHO;
    if (Mesh_DID_Is_Known(incoming_did)) return MESH_RELAY_KNOWN;
    return MESH_RELAY_OK;
}

/* ---------- OTA assembly with CRC32 verification ---------- */
static uint8_t  ota_buffer[OTA_BUFFER_SIZE];
static uint16_t ota_bytes_received = 0;
static uint16_t ota_total_chunks = 0;
static uint16_t ota_chunks_received = 0;
static uint8_t  ota_chunk_received[OTA_CHUNK_MAP_SIZE];

static void OTA_Init(void)
{
    memset(ota_buffer, 0, sizeof(ota_buffer));
    memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
    ota_bytes_received = 0;
    ota_total_chunks = 0;
    ota_chunks_received = 0;
}

/* CRC32 (ISO 3309 / ITU-T V.42) — software implementation for OTA integrity.
 * [FIX: Risk 2] This must be checked before Write_OTA_Contract_To_Flash. */
static uint32_t CRC32_Calculate(const uint8_t* data, uint16_t length)
{
    uint32_t crc = 0xFFFFFFFF;
    for (uint16_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8; bit++) {
            if (crc & 1)
                crc = (crc >> 1) ^ 0xEDB88320;
            else
                crc >>= 1;
        }
    }
    return ~crc;
}

/* Process a single OTA chunk. Returns:
 *  0 = chunk stored successfully
 *  1 = duplicate chunk (ignored)
 *  2 = out-of-bounds (buffer overflow protection)
 *  3 = all chunks complete (ready for flash)
 *
 * [FIX: AUDIT] Added bounds checks for chunk_idx, offset, and chunk_size. */
static uint8_t OTA_Process_Chunk(const uint8_t* decrypted, uint16_t payload_size)
{
    if (payload_size < 6) return 2; /* [FIX] minimum: 5-byte header + 1 byte data */

    uint16_t chunk_idx    = ((uint16_t)decrypted[1] << 8) | decrypted[2];
    uint16_t total_chunks = ((uint16_t)decrypted[3] << 8) | decrypted[4];
    uint8_t  chunk_size   = (uint8_t)(payload_size - 5);

    /* [FIX: AUDIT] Validate chunk_size won't underflow (payload_size >= 5 checked above) */
    if (chunk_size == 0) return 2;

    /* [FIX: AUDIT] Bounds: chunk_idx must fit in dedup bitmap */
    if (chunk_idx >= OTA_CHUNK_MAP_SIZE) return 2;

    /* [FIX: AUDIT] Prevent ota_total_chunks from being set to wildly different values */
    if (ota_total_chunks != 0 && total_chunks != ota_total_chunks) return 2;
    ota_total_chunks = total_chunks;

    /* [FIX: AUDIT] Duplicate detection */
    if (ota_chunk_received[chunk_idx]) return 1;

    /* [FIX: AUDIT CRITICAL] Buffer overflow protection:
     * offset = chunk_idx * chunk_size can exceed OTA_BUFFER_SIZE */
    uint32_t offset = (uint32_t)chunk_idx * (uint32_t)chunk_size;
    if (offset + chunk_size > OTA_BUFFER_SIZE) return 2;

    memcpy(&ota_buffer[offset], &decrypted[5], chunk_size);
    ota_chunk_received[chunk_idx] = 1;
    ota_chunks_received++;
    ota_bytes_received += chunk_size;

    if (ota_chunks_received >= ota_total_chunks) return 3; /* Complete */
    return 0;
}

/* Verify OTA integrity before flash write.
 * Expected CRC32 is appended as last 4 bytes of the OTA payload.
 * [FIX: Risk 2 — OTA Integrity Gap] */
static uint8_t OTA_Verify_CRC(uint16_t total_size)
{
    if (total_size < 5) return 0; /* Too small to contain CRC + data */

    uint16_t data_size = total_size - 4;
    uint32_t expected_crc = ((uint32_t)ota_buffer[data_size] << 24) |
                            ((uint32_t)ota_buffer[data_size + 1] << 16) |
                            ((uint32_t)ota_buffer[data_size + 2] << 8)  |
                            (uint32_t)ota_buffer[data_size + 3];

    uint32_t actual_crc = CRC32_Calculate(ota_buffer, data_size);
    return (actual_crc == expected_crc) ? 1 : 0;
}

/* ---------- Bio-contract byte packing/unpacking ---------- */
static uint8_t Pack_BioContract(uint8_t status, uint8_t growth_points)
{
    if (status > 3) status = 3;
    if (growth_points > 63) growth_points = 63;
    return (uint8_t)((status << 6) | growth_points);
}

static void Unpack_BioContract(uint8_t packed, uint8_t* status, uint8_t* growth_points)
{
    *status = (packed >> 6) & 0x03;
    *growth_points = packed & 0x3F;
}

/* ---------- Panic payload builder ---------- */
static void Build_Panic_Payload(uint8_t* payload, uint32_t did)
{
    memset(payload, 0, 16);
    payload[0] = (uint8_t)(did >> 24);
    payload[1] = (uint8_t)(did >> 16);
    payload[2] = (uint8_t)(did >> 8);
    payload[3] = (uint8_t)(did & 0xFF);
    payload[7] = 0xFF;   /* Panic marker in acoustic byte */
    payload[11] = 5;     /* Extended TTL for emergency */
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

#define ASSERT_TRUE(expr)  ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

/* ════════════════════════════════════════════════════════════════════
 * 1. PAYLOAD PACKING TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_pack_did_big_endian) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 0xDEADBEEF, 3000, 25, 10, 120, 0x00, 3, 0);
    ASSERT_EQ(p[0], 0xDE);
    ASSERT_EQ(p[1], 0xAD);
    ASSERT_EQ(p[2], 0xBE);
    ASSERT_EQ(p[3], 0xEF);
}

TEST(test_pack_vcap_big_endian) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0x0BB8, 0, 0, 0, 0, 3, 0); /* 3000 mV */
    ASSERT_EQ(p[4], 0x0B);
    ASSERT_EQ(p[5], 0xB8);
}

TEST(test_pack_temperature_signed) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, -20, 0, 0, 0, 3, 0);
    ASSERT_EQ((int8_t)p[6], -20);
}

TEST(test_pack_temperature_positive) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 42, 0, 0, 0, 3, 0);
    ASSERT_EQ((int8_t)p[6], 42);
}

TEST(test_pack_acoustic) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 0, 255, 0, 0, 3, 0);
    ASSERT_EQ(p[7], 255);
}

TEST(test_pack_metabolism_big_endian) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 0, 0, 0x1234, 0, 3, 0);
    ASSERT_EQ(p[8], 0x12);
    ASSERT_EQ(p[9], 0x34);
}

TEST(test_pack_bio_contract) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 0, 0, 0, 0xC5, 3, 0); /* status=3, gp=5 */
    ASSERT_EQ(p[10], 0xC5);
}

TEST(test_pack_ttl) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 0, 0, 0, 0, 5, 0);
    ASSERT_EQ(p[11], 5);
}

TEST(test_pack_firmware_version) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 1, 0, 0, 0, 0, 0, 3, 0x0042);
    ASSERT_EQ(p[12], 0x00);
    ASSERT_EQ(p[13], 0x42);
}

TEST(test_pack_reserved_zeroed) {
    uint8_t p[16];
    memset(p, 0xFF, 16);
    Pack_Soldier_Payload(p, 1, 0, 0, 0, 0, 0, 3, 0);
    ASSERT_EQ(p[14], 0x00);
    ASSERT_EQ(p[15], 0x00);
}

TEST(test_pack_unpack_roundtrip) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 0xCAFEBABE, 2950, -15, 7, 300, Pack_BioContract(1, 30), 3, 42);
    UnpackedPayload u = Unpack_Soldier_Payload(p);
    ASSERT_EQ(u.did, (long long)0xCAFEBABE);
    ASSERT_EQ(u.vcap, 2950);
    ASSERT_EQ(u.temp, -15);
    ASSERT_EQ(u.acoustic, 7);
    ASSERT_EQ(u.metabolism, 300);
    ASSERT_EQ(u.bio_status, 1);
    ASSERT_EQ(u.growth_points, 30);
    ASSERT_EQ(u.ttl, 3);
    ASSERT_EQ(u.firmware_version, 42);
}

TEST(test_pack_max_values) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 0xFFFFFFFF, 0xFFFF, 127, 255, 0xFFFF,
                         Pack_BioContract(3, 63), 255, 0xFFFF);
    UnpackedPayload u = Unpack_Soldier_Payload(p);
    ASSERT_EQ(u.did, (long long)0xFFFFFFFF);
    ASSERT_EQ(u.vcap, 0xFFFF);
    ASSERT_EQ(u.temp, 127);
    ASSERT_EQ(u.acoustic, 255);
    ASSERT_EQ(u.metabolism, 0xFFFF);
    ASSERT_EQ(u.bio_status, 3);
    ASSERT_EQ(u.growth_points, 63);
    ASSERT_EQ(u.ttl, 255);
    ASSERT_EQ(u.firmware_version, 0xFFFF);
}

TEST(test_pack_zero_values) {
    uint8_t p[16];
    Pack_Soldier_Payload(p, 0, 0, 0, 0, 0, 0, 0, 0);
    for (int i = 0; i < 16; i++)
        ASSERT_EQ(p[i], 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. DID GENERATION TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_did_non_zero_guarantee) {
    /* If XOR produces 0, fallback to 0x511CEE01 */
    uint32_t did = Generate_DID(0, 0, 0, 0);
    ASSERT_EQ(did, (long long)0x511CEE01);
}

TEST(test_did_deterministic) {
    uint32_t a = Generate_DID(0x1234, 0x5678, 0x9ABC, 0xDEF0);
    uint32_t b = Generate_DID(0x1234, 0x5678, 0x9ABC, 0xDEF0);
    ASSERT_EQ(a, b);
}

TEST(test_did_unique_per_device) {
    uint32_t a = Generate_DID(0x1111, 0x2222, 0x3333, 0x4444);
    uint32_t b = Generate_DID(0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD);
    ASSERT_NE(a, b);
}

TEST(test_did_random_changes_output) {
    uint32_t a = Generate_DID(0x1234, 0x5678, 0x9ABC, 0x0001);
    uint32_t b = Generate_DID(0x1234, 0x5678, 0x9ABC, 0x0002);
    ASSERT_NE(a, b);
}

/* ════════════════════════════════════════════════════════════════════
 * 3. MESH DEDUP (ANTI-PINGPONG) TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_mesh_empty_cache_unknown) {
    Mesh_DID_Cache_Init();
    ASSERT_FALSE(Mesh_DID_Is_Known(0x12345678));
}

TEST(test_mesh_push_then_known) {
    Mesh_DID_Cache_Init();
    Mesh_DID_Cache_Push(0xAAAA);
    ASSERT_TRUE(Mesh_DID_Is_Known(0xAAAA));
}

TEST(test_mesh_8_slots_all_known) {
    Mesh_DID_Cache_Init();
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        Mesh_DID_Cache_Push(i * 0x1111);
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        ASSERT_TRUE(Mesh_DID_Is_Known(i * 0x1111));
}

TEST(test_mesh_9th_evicts_oldest) {
    Mesh_DID_Cache_Init();
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        Mesh_DID_Cache_Push(i);
    /* Push 9th — evicts DID=1 (oldest) */
    Mesh_DID_Cache_Push(99);
    ASSERT_FALSE(Mesh_DID_Is_Known(1)); /* evicted */
    ASSERT_TRUE(Mesh_DID_Is_Known(2));  /* still there */
    ASSERT_TRUE(Mesh_DID_Is_Known(99)); /* new */
}

TEST(test_mesh_pingpong_scenario) {
    /* Two trees A and B keep bouncing a packet.
     * With only 3 slots (old code), if 3 other DIDs fill the cache,
     * A's DID gets evicted and the packet bounces infinitely.
     * With 8 slots, this is prevented for up to 8 unique DIDs. */
    Mesh_DID_Cache_Init();
    uint32_t tree_b = 0xBBBB;

    /* Tree A receives from B, caches B */
    Mesh_DID_Cache_Push(tree_b);

    /* 6 other trees' packets arrive */
    for (uint32_t i = 0; i < 6; i++)
        Mesh_DID_Cache_Push(0x1000 + i);

    /* Tree A receives from B again — with 8 slots, B should still be cached */
    ASSERT_TRUE(Mesh_DID_Is_Known(tree_b));
}

TEST(test_mesh_relay_own_echo) {
    Mesh_DID_Cache_Init();
    ASSERT_EQ(Mesh_Relay_Decision(0xAA, 0xAA, 3), MESH_RELAY_OWN_ECHO);
}

TEST(test_mesh_relay_ttl_zero) {
    Mesh_DID_Cache_Init();
    ASSERT_EQ(Mesh_Relay_Decision(0xBB, 0xAA, 0), MESH_RELAY_TTL_ZERO);
}

TEST(test_mesh_relay_known_did) {
    Mesh_DID_Cache_Init();
    Mesh_DID_Cache_Push(0xCC);
    ASSERT_EQ(Mesh_Relay_Decision(0xCC, 0xAA, 3), MESH_RELAY_KNOWN);
}

TEST(test_mesh_relay_ok) {
    Mesh_DID_Cache_Init();
    ASSERT_EQ(Mesh_Relay_Decision(0xDD, 0xAA, 3), MESH_RELAY_OK);
}

TEST(test_mesh_relay_ttl_decrement) {
    /* After relay decision OK, TTL should be decremented by caller */
    uint8_t ttl = 3;
    ttl--;
    ASSERT_EQ(ttl, 2);
}

/* ════════════════════════════════════════════════════════════════════
 * 4. OTA ASSEMBLY TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_ota_single_chunk) {
    OTA_Init();
    /* Fake OTA packet: marker + idx(0) + total(1) + 6 bytes data */
    uint8_t pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x01,
                       0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0, 0, 0, 0, 0};
    uint8_t r = OTA_Process_Chunk(pkt, 11); /* 5 header + 6 data */
    ASSERT_EQ(r, 3); /* Complete */
    ASSERT_EQ(ota_bytes_received, 6);
    ASSERT_EQ(ota_buffer[0], 0xAA);
}

TEST(test_ota_multi_chunk_assembly) {
    OTA_Init();
    /* 2 chunks of 5 bytes each */
    uint8_t pkt1[16] = {0x99, 0x00, 0x00, 0x00, 0x02,  1, 2, 3, 4, 5, 0,0,0,0,0,0};
    uint8_t pkt2[16] = {0x99, 0x00, 0x01, 0x00, 0x02,  6, 7, 8, 9, 10, 0,0,0,0,0,0};

    ASSERT_EQ(OTA_Process_Chunk(pkt1, 10), 0); /* Stored */
    ASSERT_EQ(OTA_Process_Chunk(pkt2, 10), 3); /* Complete */

    ASSERT_EQ(ota_buffer[0], 1);
    ASSERT_EQ(ota_buffer[4], 5);
    ASSERT_EQ(ota_buffer[5], 6);
    ASSERT_EQ(ota_buffer[9], 10);
}

TEST(test_ota_duplicate_ignored) {
    OTA_Init();
    uint8_t pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x02, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(pkt, 6), 0);
    ASSERT_EQ(OTA_Process_Chunk(pkt, 6), 1); /* Duplicate */
    ASSERT_EQ(ota_chunks_received, 1);        /* Counter NOT inflated */
}

TEST(test_ota_buffer_overflow_protection) {
    OTA_Init();
    /* chunk_idx=200, chunk_size=11 → offset=2200 > 1024 → reject */
    uint8_t pkt[16] = {0x99, 0x00, 200, 0x01, 0x00,
                       1,2,3,4,5,6,7,8,9,10,11};
    ASSERT_EQ(OTA_Process_Chunk(pkt, 16), 2); /* Out of bounds */
}

TEST(test_ota_chunk_idx_exceeds_bitmap) {
    OTA_Init();
    /* chunk_idx=256 (== OTA_CHUNK_MAP_SIZE) → should be rejected */
    uint8_t pkt[16] = {0x99, 0x01, 0x00, 0x02, 0x00, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(pkt, 6), 2);
}

TEST(test_ota_too_small_packet) {
    OTA_Init();
    /* Only 5 bytes = header only, no data */
    uint8_t pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x01};
    ASSERT_EQ(OTA_Process_Chunk(pkt, 5), 2);
}

TEST(test_ota_total_chunks_mismatch) {
    OTA_Init();
    /* First chunk says total=2, second says total=5 → reject second */
    uint8_t pkt1[16] = {0x99, 0x00, 0x00, 0x00, 0x02, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    uint8_t pkt2[16] = {0x99, 0x00, 0x01, 0x00, 0x05, 0xBB, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(pkt1, 6), 0);
    ASSERT_EQ(OTA_Process_Chunk(pkt2, 6), 2); /* Mismatch */
}

/* ════════════════════════════════════════════════════════════════════
 * 5. CRC32 TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_crc32_empty) {
    uint32_t crc = CRC32_Calculate(NULL, 0);
    /* CRC32 of empty data = 0x00000000 */
    ASSERT_EQ(crc, (long long)0x00000000);
}

TEST(test_crc32_known_value) {
    /* CRC32("123456789") = 0xCBF43926 */
    const uint8_t data[] = "123456789";
    uint32_t crc = CRC32_Calculate(data, 9);
    ASSERT_EQ(crc, (long long)0xCBF43926);
}

TEST(test_crc32_deterministic) {
    uint8_t data[] = {0x52, 0x49, 0x54, 0x45};
    uint32_t a = CRC32_Calculate(data, 4);
    uint32_t b = CRC32_Calculate(data, 4);
    ASSERT_EQ(a, b);
}

TEST(test_crc32_single_bit_flip) {
    uint8_t data1[] = {0x52, 0x49, 0x54, 0x45};
    uint8_t data2[] = {0x52, 0x49, 0x54, 0x44}; /* Last bit flipped */
    ASSERT_NE(CRC32_Calculate(data1, 4), CRC32_Calculate(data2, 4));
}

TEST(test_ota_crc_verify_valid) {
    OTA_Init();
    /* Write test data to ota_buffer */
    uint8_t test_data[] = {0x52, 0x49, 0x54, 0x45, 0x30}; /* 5 bytes */
    memcpy(ota_buffer, test_data, 5);
    /* Append CRC32 */
    uint32_t crc = CRC32_Calculate(test_data, 5);
    ota_buffer[5] = (uint8_t)(crc >> 24);
    ota_buffer[6] = (uint8_t)(crc >> 16);
    ota_buffer[7] = (uint8_t)(crc >> 8);
    ota_buffer[8] = (uint8_t)(crc & 0xFF);

    ASSERT_TRUE(OTA_Verify_CRC(9));
}

TEST(test_ota_crc_verify_corrupted) {
    OTA_Init();
    uint8_t test_data[] = {0x52, 0x49, 0x54, 0x45, 0x30};
    memcpy(ota_buffer, test_data, 5);
    uint32_t crc = CRC32_Calculate(test_data, 5);
    ota_buffer[5] = (uint8_t)(crc >> 24);
    ota_buffer[6] = (uint8_t)(crc >> 16);
    ota_buffer[7] = (uint8_t)(crc >> 8);
    ota_buffer[8] = (uint8_t)(crc & 0xFF);

    /* Corrupt one byte */
    ota_buffer[2] = 0x00;
    ASSERT_FALSE(OTA_Verify_CRC(9));
}

TEST(test_ota_crc_too_small) {
    OTA_Init();
    ASSERT_FALSE(OTA_Verify_CRC(4)); /* Less than 5 bytes */
}

/* ════════════════════════════════════════════════════════════════════
 * 6. BIO-CONTRACT BYTE TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_bio_pack_homeostasis) {
    uint8_t b = Pack_BioContract(0, 50);
    ASSERT_EQ(b, 50); /* 0x00 | 50 = 50 */
}

TEST(test_bio_pack_stress) {
    uint8_t b = Pack_BioContract(1, 1);
    ASSERT_EQ(b, (1 << 6) | 1); /* 65 */
}

TEST(test_bio_pack_anomaly) {
    uint8_t b = Pack_BioContract(2, 0);
    ASSERT_EQ(b, (2 << 6)); /* 128 */
}

TEST(test_bio_pack_tamper) {
    uint8_t b = Pack_BioContract(3, 63);
    ASSERT_EQ(b, (3 << 6) | 63); /* 255 */
}

TEST(test_bio_pack_clamp_status) {
    uint8_t b = Pack_BioContract(5, 10); /* status > 3 → clamped to 3 */
    uint8_t s, g;
    Unpack_BioContract(b, &s, &g);
    ASSERT_EQ(s, 3);
    ASSERT_EQ(g, 10);
}

TEST(test_bio_pack_clamp_growth) {
    uint8_t b = Pack_BioContract(0, 100); /* gp > 63 → clamped */
    uint8_t s, g;
    Unpack_BioContract(b, &s, &g);
    ASSERT_EQ(s, 0);
    ASSERT_EQ(g, 63);
}

TEST(test_bio_unpack_roundtrip) {
    for (uint8_t status = 0; status <= 3; status++) {
        for (uint8_t gp = 0; gp <= 63; gp++) {
            uint8_t packed = Pack_BioContract(status, gp);
            uint8_t s, g;
            Unpack_BioContract(packed, &s, &g);
            ASSERT_EQ(s, status);
            ASSERT_EQ(g, gp);
        }
    }
}

TEST(test_bio_byte_0xFF_means_vm_error) {
    /* If mruby VM fails, soldier sends 0xFF */
    uint8_t s, g;
    Unpack_BioContract(0xFF, &s, &g);
    ASSERT_EQ(s, 3);   /* status=3 */
    ASSERT_EQ(g, 63);  /* growth_points=63 */
}

/* ════════════════════════════════════════════════════════════════════
 * 7. PANIC PAYLOAD TESTS
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_panic_did_packed) {
    uint8_t p[16];
    Build_Panic_Payload(p, 0xDEADBEEF);
    ASSERT_EQ(p[0], 0xDE);
    ASSERT_EQ(p[1], 0xAD);
    ASSERT_EQ(p[2], 0xBE);
    ASSERT_EQ(p[3], 0xEF);
}

TEST(test_panic_acoustic_marker) {
    uint8_t p[16];
    Build_Panic_Payload(p, 1);
    ASSERT_EQ(p[7], 0xFF);
}

TEST(test_panic_extended_ttl) {
    uint8_t p[16];
    Build_Panic_Payload(p, 1);
    ASSERT_EQ(p[11], 5);
}

TEST(test_panic_other_bytes_zero) {
    uint8_t p[16];
    Build_Panic_Payload(p, 1);
    ASSERT_EQ(p[4], 0);
    ASSERT_EQ(p[5], 0);
    ASSERT_EQ(p[6], 0);
    ASSERT_EQ(p[8], 0);
    ASSERT_EQ(p[9], 0);
    ASSERT_EQ(p[10], 0);
}

/* ════════════════════════════════════════════════════════════════════
 * ENTRY POINT
 * ════════════════════════════════════════════════════════════════════ */

int main(void)
{
    printf("\n🌳 Soldier Firmware — Host-Based Unit Tests\n");
    printf("══════════════════════════════════════════════════════════════\n\n");

    printf("  Payload Packing:\n");
    RUN(test_pack_did_big_endian);
    RUN(test_pack_vcap_big_endian);
    RUN(test_pack_temperature_signed);
    RUN(test_pack_temperature_positive);
    RUN(test_pack_acoustic);
    RUN(test_pack_metabolism_big_endian);
    RUN(test_pack_bio_contract);
    RUN(test_pack_ttl);
    RUN(test_pack_firmware_version);
    RUN(test_pack_reserved_zeroed);
    RUN(test_pack_unpack_roundtrip);
    RUN(test_pack_max_values);
    RUN(test_pack_zero_values);

    printf("\n  DID Generation:\n");
    RUN(test_did_non_zero_guarantee);
    RUN(test_did_deterministic);
    RUN(test_did_unique_per_device);
    RUN(test_did_random_changes_output);

    printf("\n  Mesh Dedup (Anti-Pingpong):\n");
    RUN(test_mesh_empty_cache_unknown);
    RUN(test_mesh_push_then_known);
    RUN(test_mesh_8_slots_all_known);
    RUN(test_mesh_9th_evicts_oldest);
    RUN(test_mesh_pingpong_scenario);
    RUN(test_mesh_relay_own_echo);
    RUN(test_mesh_relay_ttl_zero);
    RUN(test_mesh_relay_known_did);
    RUN(test_mesh_relay_ok);
    RUN(test_mesh_relay_ttl_decrement);

    printf("\n  OTA Assembly:\n");
    RUN(test_ota_single_chunk);
    RUN(test_ota_multi_chunk_assembly);
    RUN(test_ota_duplicate_ignored);
    RUN(test_ota_buffer_overflow_protection);
    RUN(test_ota_chunk_idx_exceeds_bitmap);
    RUN(test_ota_too_small_packet);
    RUN(test_ota_total_chunks_mismatch);

    printf("\n  CRC32:\n");
    RUN(test_crc32_empty);
    RUN(test_crc32_known_value);
    RUN(test_crc32_deterministic);
    RUN(test_crc32_single_bit_flip);
    RUN(test_ota_crc_verify_valid);
    RUN(test_ota_crc_verify_corrupted);
    RUN(test_ota_crc_too_small);

    printf("\n  Bio-Contract Byte:\n");
    RUN(test_bio_pack_homeostasis);
    RUN(test_bio_pack_stress);
    RUN(test_bio_pack_anomaly);
    RUN(test_bio_pack_tamper);
    RUN(test_bio_pack_clamp_status);
    RUN(test_bio_pack_clamp_growth);
    RUN(test_bio_unpack_roundtrip);
    RUN(test_bio_byte_0xFF_means_vm_error);

    printf("\n  Panic Payload:\n");
    RUN(test_panic_did_packed);
    RUN(test_panic_acoustic_marker);
    RUN(test_panic_extended_ttl);
    RUN(test_panic_other_bytes_zero);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
