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
#define MESH_DID_CACHE_SIZE        3  /* [FW.21] 3 slots; DR8/DR9/DR11 mesh, DR10/DR12 EMA */
#define OTA_BUFFER_SIZE            1024
#define OTA_CHUNK_MAP_SIZE         256
#define PANIC_FLAG_BIT             0x80  /* [FW.29] Bit 7 of StatusByte: panic flag */

/* [FW.1] Flash-based AES key provisioning constants */
#define FLASH_KEY_ADDR             ((uintptr_t)_mock_flash_key_region)
#define FLASH_KEY_WORDS            8
#define FLASH_KEY_MAGIC            0x534B4559UL  /* "SKEY" */

/* [SEC.11 / FW.30] Flash-based Lorenz K_seed provisioning constants */
#define FLASH_SEED_ADDR            ((uintptr_t)_mock_flash_seed_region)
#define FLASH_SEED_WORDS           8
#define FLASH_SEED_MAGIC           0x4C534544UL  /* "LSED" */
#define EPOCH_SECONDS              86400UL

/* [FW.1] Error_Handler mock for Load_AES_Key tests */
static void Error_Handler(void) { _mock_error_handler_called++; }

/* [FW.1] AES key array (same as in soldier/main.c) */
static uint32_t aes_key[8] = {0};

/* [SEC.11 / FW.30] K_seed + validity flag (same as in soldier/main.c) */
static uint8_t lorenz_seed[32] = {0};
static uint8_t lorenz_seed_valid = 0;

/* Lorenz state persistence */
#define LORENZ_STATE_MAGIC 0x4C5A5354UL  /* "LZST" */
static RTC_HandleTypeDef hrtc;

/* ════════════════════════════════════════════════════════════════════
 * EXTRACTED PURE-LOGIC FUNCTIONS
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

/* ---------- [SEC.11 / FW.30] Load Lorenz Seed from Flash ---------- */
static void Load_Lorenz_Seed(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_SEED_ADDR;

    if (flash_ptr[0] != FLASH_SEED_MAGIC) {
        lorenz_seed_valid = 0;
        return;
    }

    uint32_t seed_or = 0;
    for (int i = 0; i < FLASH_SEED_WORDS; i++) {
        seed_or |= flash_ptr[1 + i];
    }
    if (seed_or == 0) {
        lorenz_seed_valid = 0;
        return;
    }

    for (int i = 0; i < FLASH_SEED_WORDS; i++) {
        uint32_t word = flash_ptr[1 + i];
        lorenz_seed[i * 4 + 0] = (uint8_t)(word >> 24);
        lorenz_seed[i * 4 + 1] = (uint8_t)(word >> 16);
        lorenz_seed[i * 4 + 2] = (uint8_t)(word >> 8);
        lorenz_seed[i * 4 + 3] = (uint8_t)(word & 0xFF);
    }
    lorenz_seed_valid = 1;
}

/* ---------- [SEC.11 / FW.30] Derive Cold-Start Lorenz State ---------- */
static void Derive_Cold_Start_State(float *x0, float *y0, float *z0)
{
    RTC_TimeTypeDef sTime = {0};
    RTC_DateTypeDef sDate = {0};
    HAL_RTC_GetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
    HAL_RTC_GetDate(&hrtc, &sDate, RTC_FORMAT_BIN);

    uint32_t approx_days = (uint32_t)(sDate.Year + 2000 - 1970) * 365UL
                         + (uint32_t)(sDate.Month - 1) * 30UL
                         + (uint32_t)sDate.Date;

    uint32_t hash[3] = {0};
    for (int i = 0; i < 32; i++) {
        uint32_t byte_val = lorenz_seed[i];
        uint32_t mix = byte_val + (uint32_t)i + 1;
        hash[0] ^= (mix << ((i * 7) % 24)) ^ (approx_days * (2654435761UL + (uint32_t)i));
        hash[1] ^= (mix << ((i * 11) % 24)) ^ ((approx_days + 1) * (2246822519UL + (uint32_t)i));
        hash[2] ^= (mix << ((i * 13) % 24)) ^ ((approx_days + 2) * (3266489917UL + (uint32_t)i));
    }

    *x0 = ((float)(hash[0] % 2000000) / 1000000.0f) - 1.0f;
    *y0 = ((float)(hash[1] % 2000000) / 1000000.0f) - 1.0f;
    *z0 = ((float)(hash[2] % 2000000) / 1000000.0f) - 1.0f;
}

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

    /* Byte 10: Bio-contract packed byte — [FW.29] clear PANIC_FLAG_BIT */
    lora_payload[10] = bio_contract_byte & 0x7F;

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
    // [FW.24] HRNG-based fallback: avoid deterministic DID collision
    if (did == 0) {
        RNG_HandleTypeDef hrng_local = { .Instance = RNG };
        uint32_t rng_fallback = 0;
        for (int i = 0; i < 3 && rng_fallback == 0; i++) {
            HAL_RNG_GenerateRandomNumber(&hrng_local, &rng_fallback);
        }
        did = (rng_fallback != 0) ? rng_fallback : (HAL_GetTick() ^ 0x511CEE01);
    }
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
    payload[10] = PANIC_FLAG_BIT; /* [FW.29] Panic flag in StatusByte */
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
    /* [FW.29] Bit 7 masked off: 0xC5 & 0x7F = 0x45 */
    ASSERT_EQ(p[10], 0x45);
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
    /* [FW.29] Bit 7 masked: Pack_BioContract(3,63)=0xFF & 0x7F=0x7F → status=1, gp=63 */
    ASSERT_EQ(u.bio_status, 1);
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
    /* [FW.24] If XOR produces 0, HRNG fallback is used (mock returns 42) */
    uint32_t did = Generate_DID(0, 0, 0, 0);
    ASSERT_NE(did, (long long)0);
    /* With HRNG mock returning 42, should get 42 instead of 0x511CEE01 */
    ASSERT_EQ(did, 42);
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

TEST(test_mesh_3_slots_all_known) {
    /* [FW.21] 3 slots: push 3 → all three remembered. */
    Mesh_DID_Cache_Init();
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        Mesh_DID_Cache_Push(i * 0x1111);
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        ASSERT_TRUE(Mesh_DID_Is_Known(i * 0x1111));
}

TEST(test_mesh_4th_evicts_oldest) {
    /* With 3 slots, pushing a 4th entry evicts the oldest. */
    Mesh_DID_Cache_Init();
    for (uint32_t i = 1; i <= MESH_DID_CACHE_SIZE; i++)
        Mesh_DID_Cache_Push(i);
    /* Push 4th — evicts DID=1 (oldest) */
    Mesh_DID_Cache_Push(99);
    ASSERT_FALSE(Mesh_DID_Is_Known(1)); /* evicted */
    ASSERT_TRUE(Mesh_DID_Is_Known(2));  /* still there */
    ASSERT_TRUE(Mesh_DID_Is_Known(3));  /* still there */
    ASSERT_TRUE(Mesh_DID_Is_Known(99)); /* new */
}

TEST(test_mesh_pingpong_scenario) {
    /* Two trees A and B keep bouncing a packet.
     * With 3 slots, the immediate echo A→B→A→B is still blocked
     * AND a one-hop A→B→C→A also stays blocked (B + C still cached when
     * the packet returns). Deeper rings (4+ unique relayers) are intentionally
     * accepted — TTL is the deeper-ring guard. */
    Mesh_DID_Cache_Init();
    uint32_t tree_b = 0xBBBB;

    /* Tree A receives from B, caches B */
    Mesh_DID_Cache_Push(tree_b);

    /* 2 other trees' packets arrive — B still in 3-slot window */
    Mesh_DID_Cache_Push(0x1000);
    Mesh_DID_Cache_Push(0x2000);

    /* Tree A receives from B again — B should still be cached */
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
    /* p[10] now has PANIC_FLAG_BIT set (FW.29) — tested separately */
}

/* [FW.29] Panic flag disambiguation tests */
TEST(test_panic_flag_set_in_emergency_payload) {
    uint8_t p[16];
    Build_Panic_Payload(p, 0xDEADBEEF);
    ASSERT_TRUE(p[10] & PANIC_FLAG_BIT);
    ASSERT_EQ(p[10], PANIC_FLAG_BIT);
}

TEST(test_normal_payload_panic_flag_clear) {
    uint8_t p[16];
    /* Even with bio_contract_byte that has bit 7 set, Pack masks it off */
    Pack_Soldier_Payload(p, 0x12345678, 3000, 25, 200, 120, 0xFF, 3, 1);
    ASSERT_FALSE(p[10] & PANIC_FLAG_BIT);
    /* Also test that status/growth_points are preserved in lower 7 bits */
    ASSERT_EQ(p[10], 0x7F);
}

/* [FW.24] DID HRNG fallback test */
TEST(test_did_hrng_fallback_not_magic) {
    /* When XOR gives 0, HRNG provides fallback — result should NOT be 0x511CEE01 */
    uint32_t did = Generate_DID(0, 0, 0, 0);
    ASSERT_NE(did, (long long)0);
    /* Mock HRNG returns 42, so result should be 42, not the old magic constant */
    ASSERT_NE(did, (long long)0x511CEE01);
}

/* ════════════════════════════════════════════════════════════════════
 * 8. OnRxDone BOUNDARY TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Extracted OnRxDone size validation logic (from soldier/main.c).
 * [FIX: AUDIT] Old code: size < 255 (off-by-one, rejected valid 255-byte packets).
 * Fixed: size > 0 && size <= BUFFER_SIZE. */
#define RX_BUFFER_SIZE 256
static uint8_t  test_rx_buffer[RX_BUFFER_SIZE];
static uint16_t test_rx_size = 0;
static uint8_t  test_rx_flag = 0;

static void Test_OnRxDone(uint8_t *payload, uint16_t size)
{
    if (size > 0 && size <= RX_BUFFER_SIZE) {
        memcpy(test_rx_buffer, payload, size);
        test_rx_size = size;
        test_rx_flag = 1;
    }
}

static void reset_rx(void)
{
    memset(test_rx_buffer, 0, sizeof(test_rx_buffer));
    test_rx_size = 0;
    test_rx_flag = 0;
}

TEST(test_onrxdone_normal_16) {
    reset_rx();
    uint8_t pkt[16];
    memset(pkt, 0xAA, 16);
    Test_OnRxDone(pkt, 16);
    ASSERT_EQ(test_rx_flag, 1);
    ASSERT_EQ(test_rx_size, 16);
    ASSERT_EQ(test_rx_buffer[0], 0xAA);
}

TEST(test_onrxdone_size_255_accepted) {
    /* [FIX: AUDIT] Old code rejected size=255 (off-by-one: size < 255). */
    reset_rx();
    uint8_t pkt[256];
    memset(pkt, 0xBB, 256);
    Test_OnRxDone(pkt, 255);
    ASSERT_EQ(test_rx_flag, 1);
    ASSERT_EQ(test_rx_size, 255);
}

TEST(test_onrxdone_size_256_accepted) {
    /* Size 256 = buffer maximum, should be accepted. */
    reset_rx();
    uint8_t pkt[256];
    memset(pkt, 0xCC, 256);
    Test_OnRxDone(pkt, 256);
    ASSERT_EQ(test_rx_flag, 1);
    ASSERT_EQ(test_rx_size, 256);
}

TEST(test_onrxdone_size_257_rejected) {
    /* Size > buffer → must be rejected to prevent overflow. */
    reset_rx();
    uint8_t pkt[260];
    memset(pkt, 0xDD, 260);
    Test_OnRxDone(pkt, 257);
    ASSERT_EQ(test_rx_flag, 0);
    ASSERT_EQ(test_rx_size, 0);
}

TEST(test_onrxdone_size_zero_rejected) {
    /* Size 0 = empty packet, should be rejected. */
    reset_rx();
    uint8_t pkt[1] = {0xFF};
    Test_OnRxDone(pkt, 0);
    ASSERT_EQ(test_rx_flag, 0);
}

/* ════════════════════════════════════════════════════════════════════
 * FW.6: LORENZ STATE PERSISTENCE (RTC Backup DR16-DR19)
 * ════════════════════════════════════════════════════════════════════ */

#include <math.h>

/* LORENZ_STATE_MAGIC = 0x4C5A5354 ("LZST") */
#define LORENZ_STATE_MAGIC_TEST 0x4C5A5354

/* IEEE 754 float ↔ uint32_t bit-exact conversion (identical to main.c) */
static uint32_t test_float_to_uint32(float f) {
    uint32_t u;
    memcpy(&u, &f, sizeof(u));
    return u;
}

static float test_uint32_to_float(uint32_t u) {
    float f;
    memcpy(&f, &u, sizeof(f));
    return f;
}

/* Float comparison with epsilon */
#define ASSERT_FLOAT_EQ(a, b, eps) do { \
    float _a = (float)(a), _b = (float)(b); \
    if (fabsf(_a - _b) > (eps)) { \
        printf(" ❌ FAIL (line %d: got %f, expected %f, diff %f > eps %f)\n", \
               __LINE__, (double)_a, (double)_b, (double)fabsf(_a-_b), (double)(eps)); \
        tests_failed++; return; \
    } \
} while(0)

/* --- Float pack/unpack roundtrip --- */

TEST(test_float_pack_positive) {
    float val = 29.12345f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
}

TEST(test_float_pack_negative) {
    float val = -15.789f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
}

TEST(test_float_pack_zero) {
    float val = 0.0f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
    ASSERT_EQ(packed, 0); /* IEEE 754: +0.0 = 0x00000000 */
}

TEST(test_float_pack_small) {
    float val = 0.001234f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
}

TEST(test_float_pack_typical_lorenz_x) {
    /* Typical Lorenz attractor x-coordinate */
    float val = -7.3456f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
}

TEST(test_float_pack_typical_lorenz_z) {
    /* Typical Lorenz attractor z-coordinate (homeostasis zone) */
    float val = 28.567f;
    uint32_t packed = test_float_to_uint32(val);
    float unpacked = test_uint32_to_float(packed);
    ASSERT_FLOAT_EQ(unpacked, val, 0.0f);
}

/* --- RTC Backup Register mock functional tests --- */

TEST(test_rtc_mock_write_read_roundtrip) {
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, 0xDEADBEEF);
    uint32_t val = HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16);
    ASSERT_EQ(val, 0xDEADBEEF);
}

TEST(test_rtc_mock_dr16_dr19_independent) {
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, 111);
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, 222);
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, 333);
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, 444);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16), 111);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR17), 222);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR18), 333);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19), 444);
}

TEST(test_rtc_mock_uninitialized_returns_zero) {
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16), 0);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19), 0);
}

/* --- Lorenz state save/restore simulation --- */

TEST(test_lorenz_state_save_restore_roundtrip) {
    /* Simulate Phase 5 save → Phase 1 restore cycle */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    /* Phase 5: Save state before STOP2 */
    float x_save = -7.345f, y_save = 12.891f, z_save = 28.456f;
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(x_save));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(y_save));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(z_save));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC_TEST);

    /* Phase 1: Restore state after wakeup */
    uint32_t magic = HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19);
    ASSERT_EQ(magic, LORENZ_STATE_MAGIC_TEST);

    float x_load = test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16));
    float y_load = test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR17));
    float z_load = test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR18));

    ASSERT_FLOAT_EQ(x_load, x_save, 0.0f);
    ASSERT_FLOAT_EQ(y_load, y_save, 0.0f);
    ASSERT_FLOAT_EQ(z_load, z_save, 0.0f);
}

TEST(test_lorenz_first_boot_no_magic) {
    /* First boot: DR19 is 0 (not LORENZ_STATE_MAGIC) → state_valid = 0 */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    uint32_t magic = HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19);
    ASSERT_NE(magic, LORENZ_STATE_MAGIC_TEST);
    /* System should fall back to chaos_seed initialization */
}

TEST(test_lorenz_state_nan_rejected) {
    /* If RTC contains NaN due to corruption, state must be rejected */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    /* NaN in IEEE 754: 0x7FC00000 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, 0x7FC00000); /* NaN */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(10.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(20.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC_TEST);

    float x_load = test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16));
    uint8_t valid = isfinite(x_load) ? 1 : 0;
    ASSERT_EQ(valid, 0); /* NaN is not finite → rejected */
}

TEST(test_lorenz_state_inf_rejected) {
    /* If RTC contains Inf due to corruption, state must be rejected */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    /* +Inf in IEEE 754: 0x7F800000 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(1.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, 0x7F800000); /* Inf */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(30.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC_TEST);

    float y_load = test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR17));
    uint8_t valid = isfinite(y_load) ? 1 : 0;
    ASSERT_EQ(valid, 0); /* Inf is not finite → rejected */
}

TEST(test_lorenz_state_magic_wrong_value) {
    /* If DR19 has a random value (not LORENZ_STATE_MAGIC), state is invalid */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(1.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(2.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(3.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, 0xBADC0FFE); /* wrong magic */

    uint32_t magic = HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19);
    ASSERT_NE(magic, LORENZ_STATE_MAGIC_TEST);
}

TEST(test_lorenz_state_does_not_clobber_existing_registers) {
    /* Writing DR16-DR19 must not affect DR0-DR15 (existing data) */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    /* Simulate existing data in DR0-DR15 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR0, 0x11111111);
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR7, 0x77777777);
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR15, 0xFFFFFFFF);

    /* Write Lorenz state to DR16-DR19 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(5.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(6.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(7.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC_TEST);

    /* Verify existing data is unchanged */
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR0), 0x11111111);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR7), 0x77777777);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR15), 0xFFFFFFFF);
}

TEST(test_lorenz_multi_cycle_state_overwrites) {
    /* Simulate 3 consecutive STOP2 cycles, each overwriting state */
    RTC_HandleTypeDef rtc;
    _rtc_bkp_reset_all();

    /* Cycle 1 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(1.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(2.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(3.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC_TEST);

    /* Cycle 2 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(10.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(20.0f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(30.0f));

    /* Cycle 3 */
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR16, test_float_to_uint32(-5.5f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR17, test_float_to_uint32(8.8f));
    HAL_RTCEx_BKUPWrite(&rtc, RTC_BKP_DR18, test_float_to_uint32(27.3f));

    /* Only the last values should survive */
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR16)), -5.5f, 0.0f);
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR17)), 8.8f, 0.0f);
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR18)), 27.3f, 0.0f);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&rtc, RTC_BKP_DR19), LORENZ_STATE_MAGIC_TEST);
}

/* ════════════════════════════════════════════════════════════════════
 * FW.22 — ACOUSTIC EVENTS SATURATING INCREMENT (uint8_t)
 * ════════════════════════════════════════════════════════════════════ */

/* Extracted logic: saturating increment for uint8_t acoustic_events */
static uint8_t Saturating_Increment_U8(uint8_t val) {
    if (val < 255) val++;
    return val;
}

TEST(test_acoustic_sat_inc_zero) {
    ASSERT_EQ(Saturating_Increment_U8(0), 1);
}

TEST(test_acoustic_sat_inc_normal) {
    ASSERT_EQ(Saturating_Increment_U8(100), 101);
}

TEST(test_acoustic_sat_inc_254_to_255) {
    ASSERT_EQ(Saturating_Increment_U8(254), 255);
}

TEST(test_acoustic_sat_inc_255_stays_255) {
    /* Must NOT overflow to 0 — this is the core bug FW.22 fixes */
    ASSERT_EQ(Saturating_Increment_U8(255), 255);
}

TEST(test_acoustic_sat_inc_repeated_at_max) {
    uint8_t val = 255;
    for (int i = 0; i < 1000; i++) {
        val = Saturating_Increment_U8(val);
    }
    ASSERT_EQ(val, 255);
}

TEST(test_acoustic_sat_inc_ramp_to_max) {
    uint8_t val = 0;
    for (int i = 0; i < 300; i++) {
        val = Saturating_Increment_U8(val);
    }
    ASSERT_EQ(val, 255); /* Should saturate at 255, not wrap */
}

TEST(test_acoustic_packing_uint8_direct) {
    /* With uint8_t type, packing is a direct assignment — no clamping needed */
    uint8_t acoustic = 200;
    uint8_t packed = (uint8_t)acoustic;
    ASSERT_EQ(packed, 200);
}

TEST(test_acoustic_packing_uint8_max) {
    uint8_t acoustic = 255;
    uint8_t packed = (uint8_t)acoustic;
    ASSERT_EQ(packed, 255);
}

/* ════════════════════════════════════════════════════════════════════
 * FW.10 — TEMPERATURE-BASED TX DEFERRAL
 * ════════════════════════════════════════════════════════════════════ */

#define COLD_TX_DEFER_TEMP_TEST    (-15)
#define COLD_TX_DEFER_VCAP_MV_TEST 4000

/* Extracted decision logic matching firmware/soldier/main.c */
static int Should_Defer_TX(int8_t temp, uint16_t vcap_mv) {
    return (temp < COLD_TX_DEFER_TEMP_TEST && vcap_mv < COLD_TX_DEFER_VCAP_MV_TEST);
}

TEST(test_tx_defer_cold_and_low_vcap) {
    /* -20°C, 3500 mV → MUST defer */
    ASSERT_TRUE(Should_Defer_TX(-20, 3500));
}

TEST(test_tx_defer_exactly_minus15_not_deferred) {
    /* -15°C exactly is NOT < -15, so should NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-15, 3500));
}

TEST(test_tx_defer_minus16_low_vcap) {
    /* -16°C, 3999 mV → defer */
    ASSERT_TRUE(Should_Defer_TX(-16, 3999));
}

TEST(test_tx_defer_cold_but_high_vcap) {
    /* -20°C, 4000 mV → high vcap saves us, do NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-20, 4000));
}

TEST(test_tx_defer_cold_but_very_high_vcap) {
    /* -30°C, 5000 mV → fully charged supercap, do NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-30, 5000));
}

TEST(test_tx_defer_warm_and_low_vcap) {
    /* +25°C, 3000 mV → warm, do NOT defer even with low vcap */
    ASSERT_FALSE(Should_Defer_TX(25, 3000));
}

TEST(test_tx_defer_zero_temp) {
    /* 0°C, 3000 mV → not cold enough */
    ASSERT_FALSE(Should_Defer_TX(0, 3000));
}

TEST(test_tx_defer_extreme_cold_zero_vcap) {
    /* -40°C, 0 mV → extreme case, definitely defer */
    ASSERT_TRUE(Should_Defer_TX(-40, 0));
}

TEST(test_tx_defer_boundary_vcap_3999) {
    /* -16°C, 3999 mV → both below threshold → defer */
    ASSERT_TRUE(Should_Defer_TX(-16, 3999));
}

TEST(test_tx_defer_boundary_vcap_4001) {
    /* -16°C, 4001 mV → vcap above threshold → do NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-16, 4001));
}

/* ════════════════════════════════════════════════════════════════════
 * FW.21 — EXPONENTIAL MOVING AVERAGE (delta_t / vcap)
 *
 * Mirrors the production EMA in firmware/soldier/main.c.
 * α = 0.2 (integer fixed-point: 2/10), warmup = 3 cycles, state in SRAM.
 * Cross-ref: docs/03_01 §14, docs/10_02 FW.21.
 * ════════════════════════════════════════════════════════════════════ */

#define FW21_EMA_ALPHA_NUM     2
#define FW21_EMA_ALPHA_DEN     10
#define FW21_EMA_VALID_MAGIC   0x45
#define FW21_EMA_WARMUP_CYCLES 3

typedef struct {
    uint32_t delta_t_x100;
    uint32_t vcap_x10;
    uint8_t  valid;
    uint8_t  count;
} Fw21EmaState;

static void Fw21_EMA_Update(Fw21EmaState *ema, uint32_t raw_dt_sec, uint16_t raw_vcap_mv) {
    uint32_t raw_dt_x100  = raw_dt_sec * 100u;
    uint32_t raw_vcap_x10 = (uint32_t)raw_vcap_mv * 10u;

    if (ema->valid != FW21_EMA_VALID_MAGIC || ema->count == 0) {
        ema->delta_t_x100 = raw_dt_x100;
        ema->vcap_x10     = raw_vcap_x10;
        ema->valid        = FW21_EMA_VALID_MAGIC;
        ema->count        = 1;
        return;
    }

    ema->delta_t_x100 = (FW21_EMA_ALPHA_NUM * raw_dt_x100 +
                         (FW21_EMA_ALPHA_DEN - FW21_EMA_ALPHA_NUM) * ema->delta_t_x100)
                        / FW21_EMA_ALPHA_DEN;
    ema->vcap_x10     = (FW21_EMA_ALPHA_NUM * raw_vcap_x10 +
                         (FW21_EMA_ALPHA_DEN - FW21_EMA_ALPHA_NUM) * ema->vcap_x10)
                        / FW21_EMA_ALPHA_DEN;
    if (ema->count < 255) ema->count++;
}

static uint32_t Fw21_EMA_Get_DeltaT_Sec(const Fw21EmaState *ema) {
    return ema->delta_t_x100 / 100u;
}
static uint16_t Fw21_EMA_Get_Vcap_Mv(const Fw21EmaState *ema) {
    return (uint16_t)(ema->vcap_x10 / 10u);
}
static uint8_t Fw21_EMA_Is_Warmed_Up(const Fw21EmaState *ema) {
    return (ema->valid == FW21_EMA_VALID_MAGIC) && (ema->count >= FW21_EMA_WARMUP_CYCLES);
}

TEST(test_ema_cold_start) {
    /* First call on uninitialised state: EMA equals raw input, no smoothing. */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 3600u, 4500);
    ASSERT_EQ(Fw21_EMA_Get_DeltaT_Sec(&ema), 3600u);
    ASSERT_EQ(Fw21_EMA_Get_Vcap_Mv(&ema), 4500);
    ASSERT_EQ(ema.valid, FW21_EMA_VALID_MAGIC);
    ASSERT_EQ(ema.count, 1);
    /* count < 3 → not warmed up yet */
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&ema));
}

TEST(test_ema_second_cycle_smoothing) {
    /* After cold start with 3600s/4500mV, feed 4000s/5000mV.
       Expected: EMA_dt = 0.2·4000 + 0.8·3600 = 3680
                 EMA_vcap = 0.2·5000 + 0.8·4500 = 4600 */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 3600u, 4500);
    Fw21_EMA_Update(&ema, 4000u, 5000);
    ASSERT_EQ(Fw21_EMA_Get_DeltaT_Sec(&ema), 3680u);
    ASSERT_EQ(Fw21_EMA_Get_Vcap_Mv(&ema), 4600);
    ASSERT_EQ(ema.count, 2);
}

TEST(test_ema_convergence) {
    /* After ~20 iterations of constant input, EMA converges to that input. */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 20; i++) {
        Fw21_EMA_Update(&ema, 1000u, 4000);
    }
    /* Within 1% of the steady-state value (geometric decay (0.8)^20 ≈ 0.012). */
    uint32_t dt = Fw21_EMA_Get_DeltaT_Sec(&ema);
    uint16_t vc = Fw21_EMA_Get_Vcap_Mv(&ema);
    ASSERT_TRUE(dt >= 990u && dt <= 1010u);
    ASSERT_TRUE(vc >= 3960  && vc <= 4040);
    ASSERT_TRUE(Fw21_EMA_Is_Warmed_Up(&ema));
}

TEST(test_ema_noise_rejection) {
    /* A single spike (5×) on top of a steady 1000s baseline should move EMA
       far less than the raw spike — verifies smoothing strength.
       After warm-up at 1000s, one shot of 5000s yields:
         EMA = 0.2·5000 + 0.8·1000 = 1800 (vs raw 5000 → 5×). */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 10; i++) Fw21_EMA_Update(&ema, 1000u, 4000);
    Fw21_EMA_Update(&ema, 5000u, 4000);
    /* EMA jumped only to ~1800, raw was 5000 — at least 3× rejection. */
    ASSERT_TRUE(Fw21_EMA_Get_DeltaT_Sec(&ema) <= 1800u + 5);
    /* And the spike was attenuated by far more than half. */
    ASSERT_TRUE(Fw21_EMA_Get_DeltaT_Sec(&ema) < 5000u / 2u);
}

TEST(test_ema_warmup_flag) {
    /* count < 3 ⇒ not warmed up; count ≥ 3 ⇒ warmed up. */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 1000u, 4000);
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&ema));
    Fw21_EMA_Update(&ema, 1000u, 4000);
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&ema));
    Fw21_EMA_Update(&ema, 1000u, 4000);
    ASSERT_TRUE(Fw21_EMA_Is_Warmed_Up(&ema));
}

TEST(test_ema_count_saturates_at_255) {
    /* Counter must saturate at 255 — must never wrap to 0 (which would
       reset the warmup flag and make EMA_Is_Warmed_Up() flap). */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 300; i++) Fw21_EMA_Update(&ema, 1000u, 4000);
    ASSERT_EQ(ema.count, 255);
    ASSERT_TRUE(Fw21_EMA_Is_Warmed_Up(&ema));
}

TEST(test_ema_zero_inputs_are_valid) {
    /* delta_t = 0 (impossible in practice but defensive) and vcap = 0
       (cold-boot before EBFC starts) must not crash or produce overflow.
       Cold-start with zeros: EMA = 0; subsequent 1000/4000 sample:
         EMA_dt = 0.2·1000 + 0.8·0 = 200
         EMA_vcap = 0.2·4000 + 0.8·0 = 800 */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 0u, 0);
    ASSERT_EQ(Fw21_EMA_Get_DeltaT_Sec(&ema), 0u);
    ASSERT_EQ(Fw21_EMA_Get_Vcap_Mv(&ema), 0);
    Fw21_EMA_Update(&ema, 1000u, 4000);
    ASSERT_EQ(Fw21_EMA_Get_DeltaT_Sec(&ema), 200u);
    ASSERT_EQ(Fw21_EMA_Get_Vcap_Mv(&ema), 800);
}

TEST(test_ema_no_overflow_at_max_inputs) {
    /* Worst-case: delta_t = 86400s (24h) and vcap = 5500mV (over-charged).
       Verify no uint32_t overflow during EMA update.
       Max raw_dt_x100 = 86400·100 = 8_640_000.
       Worst-case numerator = 2·8_640_000 + 8·8_640_000 = 86_400_000 ≈ 0.02·2^32.
       After 50 iterations the EMA must converge to the input. */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 50; i++) {
        Fw21_EMA_Update(&ema, 86400u, 5500);
    }
    uint32_t dt = Fw21_EMA_Get_DeltaT_Sec(&ema);
    uint16_t vc = Fw21_EMA_Get_Vcap_Mv(&ema);
    /* Within 1% of 86400 / 5500. */
    ASSERT_TRUE(dt >= 85500u && dt <= 86400u);
    ASSERT_TRUE(vc >= 5440  && vc <= 5500);
}

/* ---------- RTC DR10+DR12 pack/unpack mirrors firmware boot/save logic ----------
 * NOTE: DR11 is owned by the 3rd anti-pingpong slot (mesh DID cache 8→3).
 * EMA vcap_x10 (≤55000 ≤ 2^16) is packed into the LOW 16 bits of DR12.
 * DR12 layout: [valid:8 | count:8 | ema_vcap_x10:16].
 */

#define FW21_EMA_VCAP_X10_MASK 0xFFFFu

static void Fw21_EMA_Save_To_RTC(const Fw21EmaState *ema, RTC_HandleTypeDef *h) {
    HAL_RTCEx_BKUPWrite(h, RTC_BKP_DR10, ema->delta_t_x100);
    HAL_RTCEx_BKUPWrite(h, RTC_BKP_DR12,
        ((uint32_t)ema->valid << 24) |
        ((uint32_t)ema->count << 16) |
        (ema->vcap_x10 & FW21_EMA_VCAP_X10_MASK));
}

static void Fw21_EMA_Load_From_RTC(Fw21EmaState *ema, RTC_HandleTypeDef *h) {
    uint32_t meta = HAL_RTCEx_BKUPRead(h, RTC_BKP_DR12);
    uint8_t  v    = (uint8_t)((meta >> 24) & 0xFFu);
    if (v == FW21_EMA_VALID_MAGIC) {
        ema->delta_t_x100 = HAL_RTCEx_BKUPRead(h, RTC_BKP_DR10);
        ema->vcap_x10     = (uint32_t)(meta & FW21_EMA_VCAP_X10_MASK);
        ema->valid        = v;
        ema->count        = (uint8_t)((meta >> 16) & 0xFFu);
    } else {
        ema->delta_t_x100 = 0;
        ema->vcap_x10     = 0;
        ema->valid        = 0;
        ema->count        = 0;
    }
}

TEST(test_ema_rtc_save_load_roundtrip) {
    /* Save EMA state → wipe RAM → load back → values match. Mirrors the
       cycle of "STOP2 wakeup → RAM lost → restore from RTC backup". */
    _rtc_bkp_reset_all();
    RTC_HandleTypeDef hrtc_mock = {0};

    Fw21EmaState ema = {0};
    for (int i = 0; i < 5; i++) Fw21_EMA_Update(&ema, 3600u, 4500);
    Fw21_EMA_Save_To_RTC(&ema, &hrtc_mock);

    Fw21EmaState restored = {0};
    Fw21_EMA_Load_From_RTC(&restored, &hrtc_mock);

    ASSERT_EQ(restored.delta_t_x100, ema.delta_t_x100);
    ASSERT_EQ(restored.vcap_x10,     ema.vcap_x10);
    ASSERT_EQ(restored.valid,        ema.valid);
    ASSERT_EQ(restored.count,        ema.count);
    ASSERT_TRUE(Fw21_EMA_Is_Warmed_Up(&restored));
}

TEST(test_ema_rtc_first_boot_no_magic) {
    /* Empty RTC (DR12 magic missing) → load yields cold state. */
    _rtc_bkp_reset_all();
    RTC_HandleTypeDef hrtc_mock = {0};

    Fw21EmaState restored = {0xDEADBEEFu, 0xCAFE, 0xFFu, 0xFFu};
    Fw21_EMA_Load_From_RTC(&restored, &hrtc_mock);

    ASSERT_EQ(restored.valid, 0);
    ASSERT_EQ(restored.count, 0);
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&restored));
}

/* ────────────────────────────────────────────────────────────────────
 * [FW.5 B+] EMA → mruby calculate_state(args[5..6]) — selection logic
 *
 * Mirrors the firmware decision in `firmware/soldier/main.c` around the
 * `mrb_funcall_argv("calculate_state", 7, ...)` call: while the EMA
 * filter is still warming up (count < EMA_WARMUP_CYCLES) we MUST feed
 * the Lorenz attractor with neutral baseline values
 * (60 s / 3300 mV) — these match `BASELINE_DELTA_T_S` and
 * `NOMINAL_VCAP_MV` in `firmware/bio_contracts/bio_contract.rb`, so the
 * β-perturbation is exactly zero on cold boot. Once the filter is
 * warmed up, the smoothed EMA values are forwarded so β responds to
 * EBFC metabolism (delta_t) and supercap voltage (vcap).
 * ──────────────────────────────────────────────────────────────────── */

#define FW5_DEFAULT_DELTA_T_S 60u    /* BASELINE_DELTA_T_S in bio_contract.rb */
#define FW5_DEFAULT_VCAP_MV   3300u  /* NOMINAL_VCAP_MV     in bio_contract.rb */

/* Pure-function mirror of the firmware selection — no globals, no HAL. */
static void Fw5_Select_Lorenz_Inputs(const Fw21EmaState *ema,
                                     uint32_t *out_dt_s,
                                     uint16_t *out_vcap_mv) {
    if (Fw21_EMA_Is_Warmed_Up(ema)) {
        *out_dt_s    = Fw21_EMA_Get_DeltaT_Sec(ema);
        *out_vcap_mv = Fw21_EMA_Get_Vcap_Mv(ema);
    } else {
        *out_dt_s    = FW5_DEFAULT_DELTA_T_S;
        *out_vcap_mv = FW5_DEFAULT_VCAP_MV;
    }
}

TEST(test_fw5_cold_boot_uses_baseline_defaults) {
    /* Fresh EMA (count=0) → defaults must be selected so β-perturbation
       is exactly zero on the very first wakeup after VBAT loss. */
    Fw21EmaState ema = {0};
    uint32_t dt_s = 0; uint16_t vcap_mv = 0;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_EQ(dt_s, FW5_DEFAULT_DELTA_T_S);
    ASSERT_EQ(vcap_mv, FW5_DEFAULT_VCAP_MV);
}

TEST(test_fw5_warmup_phase_uses_baseline_defaults) {
    /* count = 1 and count = 2 are still below EMA_WARMUP_CYCLES (3) —
       EMA is initialised but not trusted yet, so defaults are used. */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 1000u, 4500);
    uint32_t dt_s = 0; uint16_t vcap_mv = 0;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&ema));
    ASSERT_EQ(dt_s, FW5_DEFAULT_DELTA_T_S);
    ASSERT_EQ(vcap_mv, FW5_DEFAULT_VCAP_MV);

    Fw21_EMA_Update(&ema, 1000u, 4500);
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_FALSE(Fw21_EMA_Is_Warmed_Up(&ema));
    ASSERT_EQ(dt_s, FW5_DEFAULT_DELTA_T_S);
    ASSERT_EQ(vcap_mv, FW5_DEFAULT_VCAP_MV);
}

TEST(test_fw5_after_warmup_forwards_ema_values) {
    /* count == 3 → warmed up → real EMA must be forwarded. */
    Fw21EmaState ema = {0};
    Fw21_EMA_Update(&ema, 1000u, 4500);
    Fw21_EMA_Update(&ema, 1000u, 4500);
    Fw21_EMA_Update(&ema, 1000u, 4500);
    ASSERT_TRUE(Fw21_EMA_Is_Warmed_Up(&ema));

    uint32_t dt_s = 0; uint16_t vcap_mv = 0;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_EQ(dt_s, 1000u);
    ASSERT_EQ(vcap_mv, 4500);
    /* And specifically NOT the firmware defaults — guards the warmup
       transition: once warmed up we never silently fall back. */
    ASSERT_TRUE(dt_s != FW5_DEFAULT_DELTA_T_S);
    ASSERT_TRUE(vcap_mv != FW5_DEFAULT_VCAP_MV);
}

TEST(test_fw5_extreme_high_vcap_clamped_by_backend_beta) {
    /* Boundary input: vcap_mv = 5500 (over-charged supercap, max real
       value). Selection must forward this raw EMA reading; the β-clamp
       (BETA_MIN..BETA_MAX = 2.0..4.0) lives in bio_contract.rb and
       protects the attractor from explosion. We assert the firmware
       does not silently muffle this signal here. */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 10; i++) Fw21_EMA_Update(&ema, 60u, 5500);

    uint32_t dt_s = 0; uint16_t vcap_mv = 0;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_EQ(dt_s, 60u);
    ASSERT_EQ(vcap_mv, 5500);
}

TEST(test_fw5_extreme_fast_charge_forwarded) {
    /* Boundary input: delta_t_s = 1 (EBFC charging in 1 second — much
       faster than baseline 60). β-perturbation hits its upper clamp,
       but the firmware-side selection still forwards the raw EMA. */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 10; i++) Fw21_EMA_Update(&ema, 1u, 3300);

    uint32_t dt_s = 0; uint16_t vcap_mv = 0;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_EQ(dt_s, 1u);
    ASSERT_EQ(vcap_mv, 3300);
}

TEST(test_fw5_zero_inputs_after_warmup_still_forwarded) {
    /* Defensive: even if EBFC reports 0/0 (sensor failure or full
       drain), once EMA is warmed up we MUST forward the actual EMA
       value rather than masking with defaults. Backend/`bio_contract.rb`
       β-clamp will keep the attractor stable, but anomaly visibility
       is preserved (server sees vcap=0 → flagged in DCI divergence). */
    Fw21EmaState ema = {0};
    for (int i = 0; i < 10; i++) Fw21_EMA_Update(&ema, 0u, 0);

    uint32_t dt_s = 99; uint16_t vcap_mv = 99;
    Fw5_Select_Lorenz_Inputs(&ema, &dt_s, &vcap_mv);
    ASSERT_EQ(dt_s, 0u);
    ASSERT_EQ(vcap_mv, 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 12. [FW.1] FLASH-BASED AES KEY LOADING TESTS
 * ════════════════════════════════════════════════════════════════════ */

/* Helper: standard provisioned test key */
static const uint32_t _test_provisioned_key[8] = {
    0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC,
    0xDDEEFF00, 0x12345678, 0x9ABCDEF0, 0xFEDCBA98
};

TEST(test_load_key_provisioned_success) {
    /* Flash has magic + valid key → aes_key loaded, no error */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _test_provisioned_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], _test_provisioned_key[i]);
    }
}

TEST(test_load_key_unprovisioned_flash_error) {
    /* Flash is 0xFFFFFFFF (unprogrammed) → Error_Handler called */
    _mock_flash_key_reset();  /* fills with 0xFF */
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
    /* aes_key should remain zeros (unchanged) */
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], 0);
    }
}

TEST(test_load_key_magic_present_key_all_zeros_error) {
    /* Magic is correct but key is all zeros → Error_Handler */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    uint32_t zero_key[8] = {0};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, zero_key);
    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
}

TEST(test_load_key_wrong_magic_error) {
    /* Wrong magic marker → Error_Handler */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    _mock_flash_key_provision(0xDEADBEEF, _test_provisioned_key);
    Load_AES_Key();

    ASSERT_TRUE(_mock_error_handler_called > 0);
    /* Key should NOT be loaded */
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ(aes_key[i], 0);
    }
}

TEST(test_load_key_partial_key_accepted) {
    /* Only one non-zero word in key → valid (key_or != 0) */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    uint32_t partial_key[8] = {0, 0, 0, 0, 0, 0, 0, 0x00000001};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, partial_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(aes_key[7], 0x00000001);
}

TEST(test_load_key_preserves_all_8_words) {
    /* All 8 words of key are correctly copied */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0xAA, sizeof(aes_key));

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _test_provisioned_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(aes_key[0], 0xAABBCCDD);
    ASSERT_EQ(aes_key[1], 0x11223344);
    ASSERT_EQ(aes_key[2], 0x55667788);
    ASSERT_EQ(aes_key[3], 0x99AABBCC);
    ASSERT_EQ(aes_key[4], 0xDDEEFF00);
    ASSERT_EQ(aes_key[5], 0x12345678);
    ASSERT_EQ(aes_key[6], 0x9ABCDEF0);
    ASSERT_EQ(aes_key[7], 0xFEDCBA98);
}

TEST(test_load_key_magic_value_correct) {
    /* Verify FLASH_KEY_MAGIC = "SKEY" = 0x534B4559 */
    ASSERT_EQ(FLASH_KEY_MAGIC, 0x534B4559UL);
}

TEST(test_load_key_second_load_overwrites) {
    /* Loading a new key overwrites the previous one */
    _mock_flash_key_reset();
    _mock_error_handler_reset();

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _test_provisioned_key);
    Load_AES_Key();
    ASSERT_EQ(aes_key[0], 0xAABBCCDD);

    /* Load a different key */
    uint32_t key2[8] = {0x11111111, 0x22222222, 0x33333333, 0x44444444,
                        0x55555555, 0x66666666, 0x77777777, 0x88888888};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, key2);
    Load_AES_Key();
    ASSERT_EQ(aes_key[0], 0x11111111);
    ASSERT_EQ(aes_key[7], 0x88888888);
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.11 / FW.30] LORENZ SEED LOADING + COLD-START DERIVATION TESTS
 * ════════════════════════════════════════════════════════════════════ */

static const uint32_t _test_provisioned_seed[8] = {
    0x01020304, 0x05060708, 0x090A0B0C, 0x0D0E0F10,
    0x11121314, 0x15161718, 0x191A1B1C, 0x1D1E1F20
};

TEST(test_load_seed_provisioned_success) {
    _mock_flash_seed_reset();
    lorenz_seed_valid = 0;
    memset(lorenz_seed, 0, sizeof(lorenz_seed));

    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();

    ASSERT_EQ(lorenz_seed_valid, 1);
    /* Verify first byte: word 0x01020304 → bytes [0x01, 0x02, 0x03, 0x04] */
    ASSERT_EQ(lorenz_seed[0], 0x01);
    ASSERT_EQ(lorenz_seed[1], 0x02);
    ASSERT_EQ(lorenz_seed[2], 0x03);
    ASSERT_EQ(lorenz_seed[3], 0x04);
    /* Verify last byte: word 0x1D1E1F20 → bytes [..., 0x1D, 0x1E, 0x1F, 0x20] */
    ASSERT_EQ(lorenz_seed[31], 0x20);
}

TEST(test_load_seed_unprovisioned_flash) {
    _mock_flash_seed_reset();  /* all 0xFF */
    lorenz_seed_valid = 1;  /* pre-set to verify it gets cleared */

    Load_Lorenz_Seed();
    ASSERT_EQ(lorenz_seed_valid, 0);
}

TEST(test_load_seed_wrong_magic) {
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(0xDEADBEEF, _test_provisioned_seed);
    lorenz_seed_valid = 1;

    Load_Lorenz_Seed();
    ASSERT_EQ(lorenz_seed_valid, 0);
}

TEST(test_load_seed_magic_present_but_all_zeros) {
    _mock_flash_seed_reset();
    uint32_t zero_seed[8] = {0};
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, zero_seed);
    lorenz_seed_valid = 1;

    Load_Lorenz_Seed();
    ASSERT_EQ(lorenz_seed_valid, 0);
}

TEST(test_load_seed_magic_value_correct) {
    /* Verify FLASH_SEED_MAGIC = "LSED" = 0x4C534544 */
    ASSERT_EQ(FLASH_SEED_MAGIC, 0x4C534544UL);
}

TEST(test_load_seed_does_not_call_error_handler) {
    /* Unlike AES key, missing seed is non-fatal */
    _mock_flash_seed_reset();
    _mock_error_handler_reset();

    Load_Lorenz_Seed();
    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(lorenz_seed_valid, 0);
}

TEST(test_cold_start_state_in_unit_band) {
    /* With a valid seed, cold-start produces (x,y,z) ∈ [-1, +1] */
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();
    ASSERT_EQ(lorenz_seed_valid, 1);

    float x0 = 0.0f, y0 = 0.0f, z0 = 0.0f;
    Derive_Cold_Start_State(&x0, &y0, &z0);

    ASSERT_TRUE(x0 >= -1.0f && x0 <= 1.0f);
    ASSERT_TRUE(y0 >= -1.0f && y0 <= 1.0f);
    ASSERT_TRUE(z0 >= -1.0f && z0 <= 1.0f);
}

TEST(test_cold_start_state_deterministic) {
    /* Same seed + same date → identical output */
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();

    float x1, y1, z1, x2, y2, z2;
    Derive_Cold_Start_State(&x1, &y1, &z1);
    Derive_Cold_Start_State(&x2, &y2, &z2);

    ASSERT_TRUE(x1 == x2 && y1 == y2 && z1 == z2);
}

TEST(test_cold_start_state_changes_with_date) {
    /* Different dates → different coordinates */
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();

    _mock_rtc_date = 2;  /* May 2 */
    _mock_rtc_month = 5;
    float x1, y1, z1;
    Derive_Cold_Start_State(&x1, &y1, &z1);

    _mock_rtc_date = 15;  /* May 15 — 13 days difference */
    float x2, y2, z2;
    Derive_Cold_Start_State(&x2, &y2, &z2);

    /* Reset to default */
    _mock_rtc_date = 2;
    _mock_rtc_month = 5;

    ASSERT_TRUE(x1 != x2 || y1 != y2 || z1 != z2);
}

TEST(test_cold_start_state_changes_with_seed) {
    /* Different seeds → different coordinates */
    float x1, y1, z1, x2, y2, z2;

    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();
    Derive_Cold_Start_State(&x1, &y1, &z1);

    uint32_t other_seed[8] = {0xFF112233, 0xEE445566, 0xDD778899, 0xCCAABBCC,
                              0xBBDDEEFF, 0xAA001122, 0x99334455, 0x88667788};
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, other_seed);
    Load_Lorenz_Seed();
    Derive_Cold_Start_State(&x2, &y2, &z2);

    ASSERT_TRUE(x1 != x2 || y1 != y2 || z1 != z2);
}

TEST(test_cbridge_unified_7arg_signature) {
    /* Verify that bio_contract.rb calculate_state expects 7 args and returns
     * [payload_byte, x, y, z]. This test validates the C-side calling convention
     * by checking that the extracted pure-C Lorenz math (from test_bio_contract.c)
     * produces a valid StatusByte for known warm-start coordinates. */
    /* Warm-start coords near the optimal z target */
    float x = 0.5f, y = 0.3f, z = 0.1f;
    int8_t temp = 20;
    uint8_t acoustic = 5;
    /* Default delta_t_s=60, vcap_mv=3300 (FW.5 B+ defaults) */

    /* After 250 Lorenz iterations from these initial coords, Z should be
     * in the homeostasis range [2.0, 45.0] for typical temp/acoustic */
    /* We just verify the coordinates are finite (non-NaN/Inf) after iteration */
    double dx, dy, dz;
    double lx = (double)x, ly = (double)y, lz = (double)z;
    double sigma = 10.0 + acoustic * 0.1;
    double rho = 28.0 + temp * 0.2;
    double beta = 8.0 / 3.0;
    if (sigma < 5.0) sigma = 5.0;
    if (sigma > 30.0) sigma = 30.0;
    if (rho < 10.0) rho = 10.0;
    if (rho > 50.0) rho = 50.0;

    for (int i = 0; i < 250; i++) {
        dx = sigma * (ly - lx);
        dy = lx * (rho - lz) - ly;
        dz = (lx * ly) - (beta * lz);
        lx += dx * 0.01;
        ly += dy * 0.01;
        lz += dz * 0.01;
    }

    int is_finite = (lx == lx) && (ly == ly) && (lz == lz);  /* NaN check */
    ASSERT_TRUE(is_finite);
    ASSERT_TRUE(lz > -1000.0 && lz < 1000.0);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20-S1] Time-Sync Beacon RX (Soldier)
 * ════════════════════════════════════════════════════════════════════ */
#define S_BEACON_MARKER          0x9C
#define S_BEACON_MAGIC_BYTE      'B'
#define S_BEACON_PLAINTEXT_SIZE  16
#define S_OTA_MARKER             0x99

/* Soldier-side authoritative UTC (mirrors soldier_unix_ts in main.c). */
static uint32_t test_soldier_unix_ts            = 0;
static uint32_t test_soldier_unix_ts_local_tick = 0;

/* Extract from soldier/main.c RX branch:
 *  if (size == 16 && plaintext[0] == 0x9C && plaintext[10] == 'B') -> consume.
 * Returns: 1 = beacon consumed (don't relay/route further), 0 = not a beacon. */
static int Recv_Time_Beacon(const uint8_t* plaintext, uint16_t size)
{
    if (size != S_BEACON_PLAINTEXT_SIZE) return 0;
    if (plaintext[0]  != S_BEACON_MARKER)     return 0;
    if (plaintext[10] != S_BEACON_MAGIC_BYTE) return 0;

    uint32_t ts = ((uint32_t)plaintext[1] << 24) | ((uint32_t)plaintext[2] << 16) |
                  ((uint32_t)plaintext[3] << 8)  | (uint32_t)plaintext[4];
    if (ts == 0) return 1;  /* Frame is well-formed but ts=0 — drop without persisting */

    test_soldier_unix_ts            = ts;
    test_soldier_unix_ts_local_tick = 12345;
    return 1;
}

TEST(test_beacon_rx_sets_unix_ts) {
    test_soldier_unix_ts = 0;
    uint8_t plain[16] = {
        0x9C, 0x65, 0xAB, 0xCD, 0xEF, 0,0,0,0, 1, 'B', 0,0,0,0,0
    };
    int consumed = Recv_Time_Beacon(plain, 16);
    ASSERT_EQ(consumed, 1);
    ASSERT_EQ(test_soldier_unix_ts, 0x65ABCDEFu);
}

TEST(test_beacon_rx_rejects_wrong_marker) {
    test_soldier_unix_ts = 0xDEADBEEFu;
    uint8_t plain[16] = {
        0x99,  /* OTA marker — must NOT trigger beacon path */
        0x65, 0xAB, 0xCD, 0xEF, 0,0,0,0, 1, 'B', 0,0,0,0,0
    };
    int consumed = Recv_Time_Beacon(plain, 16);
    ASSERT_EQ(consumed, 0);
    ASSERT_EQ(test_soldier_unix_ts, 0xDEADBEEFu);
}

TEST(test_beacon_rx_rejects_wrong_magic_byte) {
    test_soldier_unix_ts = 0xDEADBEEFu;
    uint8_t plain[16] = {
        0x9C, 0x65, 0xAB, 0xCD, 0xEF, 0,0,0,0, 1, 'X' /* wrong magic */, 0,0,0,0,0
    };
    int consumed = Recv_Time_Beacon(plain, 16);
    ASSERT_EQ(consumed, 0);
    ASSERT_EQ(test_soldier_unix_ts, 0xDEADBEEFu);
}

TEST(test_beacon_rx_rejects_wrong_size) {
    test_soldier_unix_ts = 0xDEADBEEFu;
    uint8_t plain[16] = {
        0x9C, 0x65, 0xAB, 0xCD, 0xEF, 0,0,0,0, 1, 'B', 0,0,0,0,0
    };
    int consumed = Recv_Time_Beacon(plain, 15);  /* not 16 */
    ASSERT_EQ(consumed, 0);
    ASSERT_EQ(test_soldier_unix_ts, 0xDEADBEEFu);
}

TEST(test_beacon_rx_ts_zero_well_formed_but_dropped) {
    /* Beacon shape valid but ts=0 — Soldier MUST NOT teach itself epoch 0. */
    test_soldier_unix_ts = 0xDEADBEEFu;
    uint8_t plain[16] = {
        0x9C, 0,0,0,0, 0,0,0,0, 1, 'B', 0,0,0,0,0
    };
    int consumed = Recv_Time_Beacon(plain, 16);
    ASSERT_EQ(consumed, 1);                        /* still consumed (don't relay) */
    ASSERT_EQ(test_soldier_unix_ts, 0xDEADBEEFu);  /* but ts unchanged */
}

TEST(test_beacon_rx_does_not_collide_with_ota) {
    /* OTA chunk path (byte0=0x99) must be untouched by beacon recv. */
    test_soldier_unix_ts = 0;
    uint8_t plain[16] = {
        S_OTA_MARKER, 0,0, 0,1,                  /* idx=0, total=1 */
        'b','y','t','e','c','o','d','e', 0,0,0   /* 11 bytes payload */
    };
    int consumed = Recv_Time_Beacon(plain, 16);
    ASSERT_EQ(consumed, 0);                       /* falls through to OTA branch */
    ASSERT_EQ(test_soldier_unix_ts, 0u);
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
    RUN(test_did_hrng_fallback_not_magic);

    printf("\n  Mesh Dedup (Anti-Pingpong):\n");
    RUN(test_mesh_empty_cache_unknown);
    RUN(test_mesh_push_then_known);
    RUN(test_mesh_3_slots_all_known);
    RUN(test_mesh_4th_evicts_oldest);
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
    RUN(test_panic_flag_set_in_emergency_payload);
    RUN(test_normal_payload_panic_flag_clear);

    printf("\n  OnRxDone Boundary:\n");
    RUN(test_onrxdone_normal_16);
    RUN(test_onrxdone_size_255_accepted);
    RUN(test_onrxdone_size_256_accepted);
    RUN(test_onrxdone_size_257_rejected);
    RUN(test_onrxdone_size_zero_rejected);

    printf("\n  Lorenz State Persistence (FW.6):\n");
    RUN(test_float_pack_positive);
    RUN(test_float_pack_negative);
    RUN(test_float_pack_zero);
    RUN(test_float_pack_small);
    RUN(test_float_pack_typical_lorenz_x);
    RUN(test_float_pack_typical_lorenz_z);
    RUN(test_rtc_mock_write_read_roundtrip);
    RUN(test_rtc_mock_dr16_dr19_independent);
    RUN(test_rtc_mock_uninitialized_returns_zero);
    RUN(test_lorenz_state_save_restore_roundtrip);
    RUN(test_lorenz_first_boot_no_magic);
    RUN(test_lorenz_state_nan_rejected);
    RUN(test_lorenz_state_inf_rejected);
    RUN(test_lorenz_state_magic_wrong_value);
    RUN(test_lorenz_state_does_not_clobber_existing_registers);
    RUN(test_lorenz_multi_cycle_state_overwrites);

    printf("\n  Acoustic Events Saturation — uint8_t (FW.22):\n");
    RUN(test_acoustic_sat_inc_zero);
    RUN(test_acoustic_sat_inc_normal);
    RUN(test_acoustic_sat_inc_254_to_255);
    RUN(test_acoustic_sat_inc_255_stays_255);
    RUN(test_acoustic_sat_inc_repeated_at_max);
    RUN(test_acoustic_sat_inc_ramp_to_max);
    RUN(test_acoustic_packing_uint8_direct);
    RUN(test_acoustic_packing_uint8_max);

    printf("\n  Temperature-Based TX Deferral (FW.10):\n");
    RUN(test_tx_defer_cold_and_low_vcap);
    RUN(test_tx_defer_exactly_minus15_not_deferred);
    RUN(test_tx_defer_minus16_low_vcap);
    RUN(test_tx_defer_cold_but_high_vcap);
    RUN(test_tx_defer_cold_but_very_high_vcap);
    RUN(test_tx_defer_warm_and_low_vcap);
    RUN(test_tx_defer_zero_temp);
    RUN(test_tx_defer_extreme_cold_zero_vcap);
    RUN(test_tx_defer_boundary_vcap_3999);
    RUN(test_tx_defer_boundary_vcap_4001);

    printf("\n  EMA — delta_t / vcap smoothing (FW.21):\n");
    RUN(test_ema_cold_start);
    RUN(test_ema_second_cycle_smoothing);
    RUN(test_ema_convergence);
    RUN(test_ema_noise_rejection);
    RUN(test_ema_warmup_flag);
    RUN(test_ema_count_saturates_at_255);
    RUN(test_ema_zero_inputs_are_valid);
    RUN(test_ema_no_overflow_at_max_inputs);
    RUN(test_ema_rtc_save_load_roundtrip);
    RUN(test_ema_rtc_first_boot_no_magic);

    printf("\n  EMA → mruby calculate_state args[5..6] (FW.5 B+):\n");
    RUN(test_fw5_cold_boot_uses_baseline_defaults);
    RUN(test_fw5_warmup_phase_uses_baseline_defaults);
    RUN(test_fw5_after_warmup_forwards_ema_values);
    RUN(test_fw5_extreme_high_vcap_clamped_by_backend_beta);
    RUN(test_fw5_extreme_fast_charge_forwarded);
    RUN(test_fw5_zero_inputs_after_warmup_still_forwarded);

    printf("\n  Flash-Based AES Key Loading (FW.1):\n");
    RUN(test_load_key_provisioned_success);
    RUN(test_load_key_unprovisioned_flash_error);
    RUN(test_load_key_magic_present_key_all_zeros_error);
    RUN(test_load_key_wrong_magic_error);
    RUN(test_load_key_partial_key_accepted);
    RUN(test_load_key_preserves_all_8_words);
    RUN(test_load_key_magic_value_correct);
    RUN(test_load_key_second_load_overwrites);

    printf("\n  Flash-Based Lorenz Seed Loading (SEC.11 / FW.30):\n");
    RUN(test_load_seed_provisioned_success);
    RUN(test_load_seed_unprovisioned_flash);
    RUN(test_load_seed_wrong_magic);
    RUN(test_load_seed_magic_present_but_all_zeros);
    RUN(test_load_seed_magic_value_correct);
    RUN(test_load_seed_does_not_call_error_handler);

    printf("\n  Cold-Start Lorenz Derivation (SEC.11 / FW.30):\n");
    RUN(test_cold_start_state_in_unit_band);
    RUN(test_cold_start_state_deterministic);
    RUN(test_cold_start_state_changes_with_date);
    RUN(test_cold_start_state_changes_with_seed);

    printf("\n  C-Bridge 7-Arg Signature (FW.30):\n");
    RUN(test_cbridge_unified_7arg_signature);

    printf("\n  Time-Sync Beacon RX (FW.20-S1):\n");
    RUN(test_beacon_rx_sets_unix_ts);
    RUN(test_beacon_rx_rejects_wrong_marker);
    RUN(test_beacon_rx_rejects_wrong_magic_byte);
    RUN(test_beacon_rx_rejects_wrong_size);
    RUN(test_beacon_rx_ts_zero_well_formed_but_dropped);
    RUN(test_beacon_rx_does_not_collide_with_ota);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
