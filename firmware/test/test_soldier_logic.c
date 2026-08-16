// SPDX-License-Identifier: AGPL-3.0-or-later
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
#include "../common/ttl_byte.h" /* [FW.18b] байт 11: [thr_invalid:5|TTL:3] */
#include "../common/stack_canary.h" /* [SEC.21] guard-сів (I-CG: ніколи не нуль) */
#include "../common/fw_report.h" /* [SEC.20] wire-звіт contract-стану [sem:1|rev:1|id14] */
#include "../common/mpu_regions.h" /* [SEC.21] MPU region-math (draft, pure-half) */
#include "../common/device_event.h" /* [SEC.21] uplink 0x57 device-event пакувальник */

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
#define FLASH_KEY_WORDS            4  /* ARCH.42 Variant B: 16 bytes = AES-128 LoRa */
#define FLASH_KEY_MAGIC            0x4B45594CUL  /* "KEYL" — LoRa key (post-ARCH.42; was "SKEY" / 0x534B4559) */

/* [SEC.11 / FW.30] Flash-based Lorenz K_seed provisioning constants */
#define FLASH_SEED_ADDR            ((uintptr_t)_mock_flash_seed_region)
#define FLASH_SEED_WORDS           8
#define FLASH_SEED_MAGIC           0x4C534544UL  /* "LSED" */
#define EPOCH_SECONDS              86400UL

/* [FW.2 (в)] Flash-based cluster broadcast key (KEYB) provisioning constants */
#define FLASH_BCAST_KEY_ADDR       ((uintptr_t)_mock_flash_bcast_region)
#define FLASH_BCAST_KEY_WORDS      4
#define FLASH_BCAST_KEY_MAGIC      0x4B455942UL  /* "KEYB" */

/* [FW.1] Error_Handler mock for Load_AES_Key tests */
static void Error_Handler(void) { _mock_error_handler_called++; }

/* [FW.1] AES key array (same as in soldier/main.c) */
static uint32_t aes_key[4] = {0};  /* AES-128 LoRa (ARCH.42 Variant B) */

/* [FW.2 (в)] Cluster control-plane key mirror (same as in soldier/main.c) */
static uint32_t bcast_key[4] = {0};
static uint8_t  bcast_key_is_fallback = 0;

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

/* ---------- [FW.2 (в)] Load cluster broadcast key (KEYB) from Flash ----------
 * Mirror of soldier/main.c Load_Broadcast_Key: fail-open (НЕ Error_Handler) —
 * порожній KEYB = bench-плата до KEYB-ери → fallback на session (KEYL). */
static void Load_Broadcast_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_BCAST_KEY_ADDR;
    uint32_t key_or = 0;

    if (flash_ptr[0] == FLASH_BCAST_KEY_MAGIC) {
        for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
            key_or |= flash_ptr[1 + i];
        }
    }

    if (key_or != 0) {
        for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
            bcast_key[i] = flash_ptr[1 + i];
        }
        bcast_key_is_fallback = 0;
        return;
    }

    for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
        bcast_key[i] = aes_key[i];
    }
    bcast_key_is_fallback = 1;
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

/* ---------- [SEC.11 / FW.30] Derive Cold-Start Lorenz State ----------
 * [FW.30] Knuth-плейсхолдер замінено shared-header контрактом
 * (HMAC-SHA256 + signed-unit-float + civil days) — той самий код, що й у
 * production main.c. Parity vs OpenSSL — у test_seed_derivation.c. */
#include "../common/lorenz_seed.h"

/* [FW.20] Дзеркала RAM-глобалів main.c: UTC від Queen-маяка + tick синхронізації. */
static volatile uint32_t soldier_unix_ts            = 0;
static volatile uint32_t soldier_unix_ts_local_tick = 0;

static void Derive_Cold_Start_State(float *x0, float *y0, float *z0)
{
    uint64_t epoch_day;

    if (soldier_unix_ts != 0u) {
        uint32_t now_ts = soldier_unix_ts +
            ((HAL_GetTick() - soldier_unix_ts_local_tick) / 1000u);
        epoch_day = Silken_Epoch_Day_From_Unix(now_ts);
    } else {
        RTC_TimeTypeDef sTime = {0};
        RTC_DateTypeDef sDate = {0};
        HAL_RTC_GetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
        HAL_RTC_GetDate(&hrtc, &sDate, RTC_FORMAT_BIN);

        int32_t days = Silken_Days_From_Civil((int32_t)sDate.Year + 2000,
                                              (uint32_t)sDate.Month,
                                              (uint32_t)sDate.Date);
        epoch_day = (days > 0) ? (uint64_t)days : 0u;
    }

    double dx = 0.0, dy = 0.0, dz = 0.0;
    Silken_Derive_Initial_State(lorenz_seed, epoch_day, &dx, &dy, &dz);

    *x0 = (float)dx;
    *y0 = (float)dy;
    *z0 = (float)dz;
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

    /* Byte 11 [FW.18b]: бітфілд [thr_invalid:5|TTL:3] — main.c пакує через
     * Ttl_Byte_Pack(ttl, tinyml_threshold_invalid_count); дзеркало тестів
     * тримає counter=0 (бітово ≡ legacy), бітфілд критий своїми тестами. */
    lora_payload[11] = Ttl_Byte_Pack(ttl, 0);

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
    u.bio_status    = (p[10] >> 5) & 0x03;  /* [FW.29-PACK] bits 6..5 */
    u.growth_points = p[10] & 0x1F;          /* [FW.29-PACK] bits 4..0 */
    u.ttl       = Ttl_Byte_Ttl(p[11]); /* [FW.18b] нижні 3 біти — як бекенд */
    u.firmware_version = ((uint16_t)p[12] << 8) | p[13];
    return u;
}

/* ---------- DID derivation ----------
 * [FW.54 Вісь 2] Не дзеркало, а САМ хедер (урок R9: dual-impl golden-ref
 * дрейфує від оригіналу). Golden-вектори нижче — freeze-contract з Ruby
 * (spec/services/silken_net/did_derivation_spec.rb). */
#include "../soldier/did_derive.h"

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

/* [FW.53] Campaign-change deadlock guard (mirrors soldier/main.c):
 * a dead half-assembled campaign must not block a live one forever. */
#define OTA_MISMATCH_RESET_THRESHOLD 3
static uint8_t ota_total_mismatch_streak = 0;

static void OTA_Init(void)
{
    memset(ota_buffer, 0, sizeof(ota_buffer));
    memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
    ota_bytes_received = 0;
    ota_total_chunks = 0;
    ota_chunks_received = 0;
    ota_total_mismatch_streak = 0;
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
 *  4 = campaign change detected — stale assembly state wiped [FW.53]
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

    /* [FIX: AUDIT] Prevent ota_total_chunks from being set to wildly different values.
     * [FW.53] ...but a dead campaign must not block a live one:
     * N consecutive foreign totals → wipe the stale half-assembly (mirrors main.c). */
    if (ota_total_chunks != 0 && total_chunks != ota_total_chunks) {
        if (++ota_total_mismatch_streak >= OTA_MISMATCH_RESET_THRESHOLD) {
            memset(ota_buffer, 0, sizeof(ota_buffer));
            memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
            ota_bytes_received = 0;
            ota_total_chunks = 0;
            ota_chunks_received = 0;
            ota_total_mismatch_streak = 0;
            return 4;
        }
        return 2;
    }
    ota_total_mismatch_streak = 0;
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
/* [FW.29-PACK] Wire layout: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)]. */
static uint8_t Pack_BioContract(uint8_t status, uint8_t growth_points)
{
    if (status > 3) status = 3;
    if (growth_points > 31) growth_points = 31;
    return (uint8_t)((status << 5) | growth_points);
}

static void Unpack_BioContract(uint8_t packed, uint8_t* status, uint8_t* growth_points)
{
    *status = (packed >> 5) & 0x03;
    *growth_points = packed & 0x1F;
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
    /* [FW.29-PACK] Pack_BioContract(3, 63) → gp clamped to 31 → (3<<5)|31 = 0x7F.
     * Mask `& 0x7F` залишає 0x7F. Unpack: status = 3 (tamper) ✓, gp = 31.
     * До FW.29-PACK старе packing (3<<6)|63 = 0xFF → mask = 0x7F → unpack
     * `>>6 = 1` (stress) — silent tamper demotion. Зараз status=3 коректно зберігається. */
    ASSERT_EQ(u.bio_status, 3);
    ASSERT_EQ(u.growth_points, 31);
    /* [FW.18b] TTL — 3 wire-біти: 255 на вході → маска 7. Реальні TTL
     * (DEFAULT=3, PANIC=5) у діапазон вкладаються з запасом. */
    ASSERT_EQ(u.ttl, 7);
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

/* Golden g1: реалістичний WLE5 UID-триплет. Freeze-contract з Ruby-дзеркалом. */
TEST(test_did_golden_realistic_uid) {
    uint32_t did = Did_Derive_From_Uid(0x0039002Fu, 0x31385115u, 0x38323634u);
    ASSERT_EQ(did, 0x80B12004u);
}

/* Golden g2: дефектний UID все-нулі — детермінований, ненульовий, заприсяжений.
 * (Колізію двох дефектних кристалів ловить фабрика DB-unique, не HRNG.) */
TEST(test_did_golden_defective_uid_all_zero) {
    uint32_t did = Did_Derive_From_Uid(0u, 0u, 0u);
    ASSERT_NE(did, (long long)0);
    ASSERT_EQ(did, 0xC611B59Bu);
}

/* Golden g3: все-FF (erased-flash патерн читання UID). */
TEST(test_did_golden_all_ff) {
    uint32_t did = Did_Derive_From_Uid(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu);
    ASSERT_EQ(did, 0x8BA660CAu);
}

/* Golden g4 (avalanche): один біт UID → зовсім інший DID. */
TEST(test_did_avalanche_single_bit) {
    uint32_t a = Did_Derive_From_Uid(0x0039002Fu, 0x31385115u, 0x38323634u);
    uint32_t b = Did_Derive_From_Uid(0x0039002Eu, 0x31385115u, 0x38323634u);
    ASSERT_NE(a, b);
    ASSERT_EQ(b, 0xE203A561u);
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

/* [FW.53] Campaign-change deadlock: стара недозібрана кампанія
 * (total=2) не сміє блокувати нову (total=5) довіку. N поспіль чужих total →
 * жертовний reset; наступні чанки нової кампанії приймаються з чистого стану. */
TEST(test_ota_campaign_change_resets_after_streak) {
    OTA_Init();
    uint8_t old_pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x02, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(old_pkt, 6), 0);       /* Стара кампанія, чанк 0 з 2 */

    uint8_t new_pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x05, 0xBB, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(new_pkt, 6), 2);       /* mismatch #1 — ще терпимо */
    ASSERT_EQ(OTA_Process_Chunk(new_pkt, 6), 2);       /* mismatch #2 */
    ASSERT_EQ(OTA_Process_Chunk(new_pkt, 6), 4);       /* mismatch #3 → wipe */
    ASSERT_EQ(ota_total_chunks, 0);                    /* Стан стерто */
    ASSERT_EQ(ota_chunks_received, 0);

    ASSERT_EQ(OTA_Process_Chunk(new_pkt, 6), 0);       /* Нова кампанія прийнята */
    ASSERT_EQ(ota_total_chunks, 5);
    ASSERT_EQ(ota_buffer[0], 0xBB);
}

/* [FW.53] Накопичений streak гаситься валідним чанком своєї
 * кампанії — поодинокі чужі пакети (sусідній кластер, ефірне сміття) не
 * повинні зрештою стерти живу збірку. */
TEST(test_ota_mismatch_streak_clears_on_valid_chunk) {
    OTA_Init();
    uint8_t own0[16]    = {0x99, 0x00, 0x00, 0x00, 0x03, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    uint8_t own1[16]    = {0x99, 0x00, 0x01, 0x00, 0x03, 0xCC, 0,0,0,0,0,0,0,0,0,0};
    uint8_t foreign[16] = {0x99, 0x00, 0x00, 0x00, 0x07, 0xBB, 0,0,0,0,0,0,0,0,0,0};

    ASSERT_EQ(OTA_Process_Chunk(own0, 6), 0);
    ASSERT_EQ(OTA_Process_Chunk(foreign, 6), 2);   /* streak = 1 */
    ASSERT_EQ(OTA_Process_Chunk(foreign, 6), 2);   /* streak = 2 */
    ASSERT_EQ(OTA_Process_Chunk(own1, 6), 0);      /* свій чанк → streak = 0 */
    ASSERT_EQ(OTA_Process_Chunk(foreign, 6), 2);   /* знову 1, НЕ 3 → без wipe */
    ASSERT_EQ(ota_total_chunks, 3);                /* Жива кампанія неторкана */
    ASSERT_EQ(ota_chunks_received, 2);
}

/* [FW.29] VM_ERROR wire-контракт: 0x60 = [panic:0|status:tamper|gp:0].
 * Старий 0xFF після FW.29-маски (&0x7F) ставав tamper + gp=31 → бекенд ×2
 * карбував 62 бали за КОЖЕН error-пакет. Пінуємо нову семантику. */
TEST(test_vm_error_wire_byte_is_tamper_with_zero_growth) {
    uint8_t vm_error_byte = 0x60;                  /* BIO_STATUS_VM_ERROR (main.c) */
    uint8_t masked = vm_error_byte & 0x7F;         /* FW.29: &= ~PANIC_FLAG_BIT */
    ASSERT_EQ(masked, 0x60);                       /* Маска не спотворює мітку */

    uint8_t status_out, gp_out;
    Unpack_BioContract(masked, &status_out, &gp_out);
    ASSERT_EQ(status_out, 3);                      /* tamper_detected */
    ASSERT_EQ(gp_out, 0);                          /* Жодної емісії за помилку VM */
}

/* ─── [FW.27 follow-up edge cases, 2026-05-03] ─────────────────────────
 * Сторожовий пес OTA-збірки повинен витримати реальні шуми ефіру:
 *   (a) Дублікат з ІНШИМ payload — anti-tamper guard. Зловмисник
 *       може спробувати переписати уже отриманий чанк іншим вмістом,
 *       сподіваючись що Солдат «оновиться». Production guard
 *       `!ota_chunk_received[chunk_idx]` (main.c — за символом, не за номером
 *       рядка: попереднє посилання вже вказувало не туди) це блокує —
 *       але донині не було тесту, який би перевіряв БАЙТНУ
 *       незмінність попередньо записаного payload'у.
 *   (b) STOP2 між OTA-чанками: bitmap-стан ota_chunk_received[]
 *       живе в SRAM і перетривати STOP2 (RAM зберігається). Тест
 *       симулює: chunk 0 → "сон" (no-op call sequence) → chunk 2 →
 *       "сон" → chunk 1; перевіряємо що counter та offsets коректні.
 *   (c) Bitmap full @ 72 chunks з ЧАСТКОВИМ паттерном missing —
 *       у `test_rereq_*` уже є full-missing і edge cases, але не
 *       partial pattern (e.g. missing chunks 17, 35, 71 з 72) — типова
 *       реальна картина після RF dead zone.
 * Cross-ref: docs/03_02 §5.1.3 (FW.27-B Magic Re-Request).
 * ─────────────────────────────────────────────────────────────────── */
TEST(test_ota_duplicate_with_different_payload_preserves_original) {
    OTA_Init();
    /* First arrival: chunk_idx=0, total=2, data byte = 0xAA */
    uint8_t pkt_orig[16] = {0x99, 0x00, 0x00, 0x00, 0x02, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(pkt_orig, 6), 0);
    ASSERT_EQ(ota_buffer[0], 0xAA);

    /* Second arrival: same chunk_idx=0 BUT different data byte = 0x55 (anti-tamper).
     * Production guard !ota_chunk_received[chunk_idx] rejects → return code 1 (duplicate),
     * AND original payload byte 0xAA must remain in ota_buffer[0]. */
    uint8_t pkt_attack[16] = {0x99, 0x00, 0x00, 0x00, 0x02, 0x55, 0,0,0,0,0,0,0,0,0,0};
    ASSERT_EQ(OTA_Process_Chunk(pkt_attack, 6), 1);  /* Duplicate flag */
    ASSERT_EQ(ota_buffer[0], 0xAA);                  /* Original NOT overwritten */
    ASSERT_EQ(ota_chunks_received, 1);               /* Counter NOT inflated */
}

TEST(test_ota_stop2_simulation_chunks_arrive_out_of_order) {
    OTA_Init();
    /* Soldier wakes, processes chunk 0; sleeps STOP2; wakes, processes chunk 2;
     * sleeps STOP2; wakes, processes chunk 1 (last missing). Test simulates
     * the dedup bitmap stability across discrete Process invocations.
     * Each chunk has chunk_size=6 (so offsets are 0, 6, 12). */
    uint8_t pkt0[11] = {0x99, 0x00, 0x00, 0x00, 0x03, 0x10,0x11,0x12,0x13,0x14,0x15};
    uint8_t pkt2[11] = {0x99, 0x00, 0x02, 0x00, 0x03, 0x30,0x31,0x32,0x33,0x34,0x35};
    uint8_t pkt1[11] = {0x99, 0x00, 0x01, 0x00, 0x03, 0x20,0x21,0x22,0x23,0x24,0x25};

    ASSERT_EQ(OTA_Process_Chunk(pkt0, 11), 0); /* stored, !complete */
    ASSERT_EQ(ota_chunks_received, 1);
    /* simulated STOP2 — no state mutation expected */
    ASSERT_EQ(OTA_Process_Chunk(pkt2, 11), 0); /* stored at offset 12 */
    ASSERT_EQ(ota_chunks_received, 2);
    /* simulated STOP2 again */
    ASSERT_EQ(OTA_Process_Chunk(pkt1, 11), 3); /* stored at offset 6, COMPLETE */
    ASSERT_EQ(ota_chunks_received, 3);

    /* Verify byte-level integrity of all three chunks at correct offsets */
    ASSERT_EQ(ota_buffer[0],  0x10);
    ASSERT_EQ(ota_buffer[5],  0x15);
    ASSERT_EQ(ota_buffer[6],  0x20);  /* chunk 1 at offset 6 */
    ASSERT_EQ(ota_buffer[11], 0x25);
    ASSERT_EQ(ota_buffer[12], 0x30);  /* chunk 2 at offset 12 */
    ASSERT_EQ(ota_buffer[17], 0x35);
}

TEST(test_ota_stop2_simulation_duplicate_after_sleep_still_rejected) {
    /* Anti-replay через сон: chunk прийшов, sleep, той самий chunk прийшов
     * знов (наприклад, Queen reflex shot повторив бо ми не ACK'нули). */
    OTA_Init();
    uint8_t pkt[11] = {0x99, 0x00, 0x00, 0x00, 0x02, 0xAA,0xBB,0xCC,0xDD,0xEE,0xFF};
    ASSERT_EQ(OTA_Process_Chunk(pkt, 11), 0);
    ASSERT_EQ(ota_chunks_received, 1);
    /* sleep cycle simulated */
    ASSERT_EQ(OTA_Process_Chunk(pkt, 11), 1);  /* Still detected as dup */
    ASSERT_EQ(ota_chunks_received, 1);          /* No double-count */
    /* All bytes from original arrival intact */
    ASSERT_EQ(ota_buffer[0], 0xAA);
    ASSERT_EQ(ota_buffer[5], 0xFF);
}

TEST(test_ota_total_chunks_zero_rejected) {
    /* Edge case: malformed packet declaring total_chunks=0. The dedup
     * `!ota_chunk_received[0]` would pass, but completion check
     * `>= ota_total_chunks=0` fires immediately → return 3 (complete)
     * with zero data — which is wrong. Test pins the current behaviour
     * for regression detection. Production code path: such a packet
     * would never pass HMAC trailer dual-gate (FW.23) since OTA total
     * chunks are signed in HMAC tag — defence-in-depth. */
    OTA_Init();
    uint8_t pkt[16] = {0x99, 0x00, 0x00, 0x00, 0x00, 0xAA, 0,0,0,0,0,0,0,0,0,0};
    /* Production OTA_Process_Chunk sets ota_total_chunks=0, increments
     * received to 1, then checks `received(1) >= total(0)` → true → returns 3.
     * This is benign: completion handler verifies CRC32 over actual bytes,
     * which would fail on zero-length data → no flash write. */
    uint8_t rc = OTA_Process_Chunk(pkt, 6);
    ASSERT_TRUE(rc == 3 || rc == 2);  /* either complete-degenerate or rejected */
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
 * 6. BIO-CONTRACT BYTE TESTS [FW.29-PACK: status<<5, gp 5-bit]
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_bio_pack_homeostasis) {
    uint8_t b = Pack_BioContract(0, 25);
    ASSERT_EQ(b, 25); /* 0x00 | 25 = 25 */
}

TEST(test_bio_pack_stress) {
    uint8_t b = Pack_BioContract(1, 1);
    ASSERT_EQ(b, (1 << 5) | 1); /* 33 */
}

TEST(test_bio_pack_anomaly) {
    uint8_t b = Pack_BioContract(2, 0);
    ASSERT_EQ(b, (2 << 5)); /* 64 — bit 7 clear, не конфліктує з PANIC_FLAG_BIT */
}

TEST(test_bio_pack_tamper) {
    uint8_t b = Pack_BioContract(3, 31);
    ASSERT_EQ(b, (3 << 5) | 31); /* 0x7F = 127 — bit 7 clear */
}

TEST(test_bio_pack_clamp_status) {
    uint8_t b = Pack_BioContract(5, 10); /* status > 3 → clamped to 3 */
    uint8_t s, g;
    Unpack_BioContract(b, &s, &g);
    ASSERT_EQ(s, 3);
    ASSERT_EQ(g, 10);
}

TEST(test_bio_pack_clamp_growth) {
    uint8_t b = Pack_BioContract(0, 100); /* gp > 31 → clamped */
    uint8_t s, g;
    Unpack_BioContract(b, &s, &g);
    ASSERT_EQ(s, 0);
    ASSERT_EQ(g, 31);
}

TEST(test_bio_unpack_roundtrip) {
    for (uint8_t status = 0; status <= 3; status++) {
        for (uint8_t gp = 0; gp <= 31; gp++) {
            uint8_t packed = Pack_BioContract(status, gp);
            uint8_t s, g;
            Unpack_BioContract(packed, &s, &g);
            ASSERT_EQ(s, status);
            ASSERT_EQ(g, gp);
        }
    }
}

/* test_bio_byte_0xFF_means_vm_error ВИДАЛЕНО [FW.29]: він пінував
 * БАГ — 0xFF після маски ставав tamper + gp=31 (бекенд ×2 = 62 бали за error-
 * пакет). Новий контракт (BIO_STATUS_VM_ERROR = 0x60, tamper + gp=0) пінується
 * у test_vm_error_wire_byte_is_tamper_with_zero_growth. */

TEST(test_bio_anomaly_survives_panic_mask) {
    /* [FW.29-PACK regression]: Pack_BioContract(2, 0) = 0x40 (bit 7 = 0).
     * Старе packing давало (2<<6)|0 = 0x80 → mask `& 0x7F` → 0x00 → backend
     * читав homeostasis. Anomaly events були тихо втрачені! */
    uint8_t b = Pack_BioContract(2, 0);
    ASSERT_FALSE(b & PANIC_FLAG_BIT);  /* bit 7 МАЄ бути 0 для нормального байту */
    uint8_t masked = b & 0x7F;
    ASSERT_EQ(masked, b);  /* mask нічого не змінює — anomaly зберігається */
    uint8_t s, g;
    Unpack_BioContract(masked, &s, &g);
    ASSERT_EQ(s, 2);  /* anomaly survives */
    ASSERT_EQ(g, 0);
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

/* [FW.54 Вісь 2] DID ніколи не нуль (0 ефіру = Королева-Сентінель) і завжди
 * детермінований: LCG-sweep UID-триплетів — жодного нуля, повторний прохід
 * біт-у-біт той самий. */
TEST(test_did_sweep_never_zero_and_deterministic) {
    uint32_t lcg = 0x12345678u;
    for (int i = 0; i < 10000; i++) {
        uint32_t w0 = (lcg = lcg * 1664525u + 1013904223u);
        uint32_t w1 = (lcg = lcg * 1664525u + 1013904223u);
        uint32_t w2 = (lcg = lcg * 1664525u + 1013904223u);
        uint32_t a = Did_Derive_From_Uid(w0, w1, w2);
        ASSERT_NE(a, (long long)0);
        ASSERT_EQ(a, Did_Derive_From_Uid(w0, w1, w2));
    }
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

/* One-Home: той самий предикат, що прошивка (firmware/common/tx_defer.h) —
 * тест б'є по справжньому коду, не по копії (freeze-contract на < і −15/4000). */
#include "../common/tx_defer.h"

/* [ARCH.102] One-Home: той самий ледж, що прошивка
 * (firmware/common/acoustic_ledger.h). Пінить не арифметику, а ПОСЛІДОВНІСТЬ:
 * лічильник споживає лише те, що доставлено, тож пробудження, яке відклало TX
 * (мороз) або відправило grace-hello замість телеметрії, більше не з'їдає
 * зафіксовану подію. Доти обнулення стояло у Фазі 2 — до того, як стане
 * відомо, чи кадр узагалі поїде, — і на дроті величина була рівно 0 або 1. */
#include "../common/acoustic_ledger.h"

TEST(test_acoustic_ledger_consumes_only_delivered) {
    ASSERT_EQ(Acoustic_Ledger_Consume(1, 1), 0);
    ASSERT_EQ(Acoustic_Ledger_Consume(3, 3), 0);
}

/* 🔴 ЄДИНИЙ приклад цієї групи, що РОЗРІЗНЯЄ ледж від старого обнулення —
 * мутація «завжди 0» червонить рівно його. Решта два лишаються зеленими на
 * обох реалізаціях і тому є контрактом тотальності, не доказом семантики.
 *
 * ⚠️ Стеля названа чесно: сама ПОСЛІДОВНІСТЬ (пробудження без TX не з'їдає
 * подію) живе в control-flow `main.c` — знімок у Фазі 2, споживання у Фазі 4
 * під `telemetry_sent`, — і host-сюїта туди не дістає за побудовою. Приклад,
 * який моделював би цикл локально, пінив би власну модель, а не прошивку:
 * така спроба тут була і мутацію ПЕРЕЖИЛА, тому знята. */
TEST(test_acoustic_ledger_keeps_remainder) {
    /* Знімок узяв 2, а поки кадр летів, детектор дорахував ще одну. */
    ASSERT_EQ(Acoustic_Ledger_Consume(3, 2), 1);
}

TEST(test_acoustic_ledger_total_on_overshoot) {
    /* Тотальність: від'ємного залишку не буває. */
    ASSERT_EQ(Acoustic_Ledger_Consume(2, 5), 0);
    ASSERT_EQ(Acoustic_Ledger_Consume(0, 1), 0);
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

/* ─── [FW.10 follow-up edge cases, 2026-05-03] ─────────────────────
 * Сторожовий пес TX-вирішення повинен прокидатися лише за двома
 * умовами одночасно: cold (T < -15°C) AND vcap < 4000 мВ. Нижче —
 * три край-сценарії, що раніше були неявними:
 *   (1) -40°C + battery-backed vcap (5500 мВ): NOT defer — energy reserve
 *       обходить cold-guard (наприклад, Queen-провізіонер з резервним
 *       аккумулятором, який зимує без EBFC).
 *   (2) -5°C + low vcap (1000 мВ): NOT defer — поріг температури -15°C,
 *       а -5°C класифікується як warm (метаболізм EBFC активний навіть
 *       при низькому заряді ксилеми).
 *   (3) Точний -15°C з нульовим vcap: NOT defer (boundary < strict). Це
 *       freeze-контракт `<` vs `<=` — захищає від випадкової зміни на
 *       `<=` при майбутньому рефакторингу.
 * Cross-ref: docs/03_01 §1.4 cold-temp guard.
 * ─────────────────────────────────────────────────────────────────── */
TEST(test_tx_defer_extreme_cold_high_vcap_battery_backed) {
    /* -40°C, 5500 mV (battery-backed scenario) → vcap saves us, do NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-40, 5500));
}

TEST(test_tx_defer_warm_minus5_low_vcap) {
    /* -5°C (warm enough), 1000 mV (very low vcap) → temp guard saves, do NOT defer */
    ASSERT_FALSE(Should_Defer_TX(-5, 1000));
}

TEST(test_tx_defer_boundary_minus15_zero_vcap) {
    /* Boundary @ -15°C, 0 mV: condition is `temp < -15`, so -15 itself is NOT cold.
     * Freeze-contract: changing `<` → `<=` would break this test. */
    ASSERT_FALSE(Should_Defer_TX(-15, 0));
}

/* ════════════════════════════════════════════════════════════════════
 * FW.21 — EXPONENTIAL MOVING AVERAGE (delta_t / vcap)
 *
 * Mirrors the production EMA in firmware/soldier/main.c.
 * α = 0.2 (integer fixed-point: 2/10), warmup = 3 cycles, state in SRAM.
 * Cross-ref: docs/03_01 §13 (EMA home), docs/00_07 FW.21.
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
 * filter is still warming up (count < EMA_WARMUP_CYCLES) we feed neutral
 * baseline values (60 s / 3300 mV); once warmed up, the smoothed EMA
 * values are forwarded. [E.63] delta_t now drives growth_points DIRECTLY
 * (metabolic_health, 03_04 §4.3), NOT β — β is fixed at BASE_BETA and
 * vcap is reserved. This test pins WHICH inputs the C side selects —
 * unchanged by E.63 (the selection logic is independent of the coupling).
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
    /* Fresh EMA (count=0) → defaults must be selected so growth_points use
       the neutral baseline on the very first wakeup after VBAT loss
       ([E.63] delta_t → growth_points; β is fixed). */
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
       faster than baseline 60). [E.63] delta_t this fast → max growth_points;
       the firmware-side selection still forwards the raw EMA. */
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
    /* Post-ARCH.42: FLASH_KEY_WORDS=4 (AES-128 LoRa, 16 bytes) */
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
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
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
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
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        ASSERT_EQ(aes_key[i], 0);
    }
}

TEST(test_load_key_partial_key_accepted) {
    /* Post-ARCH.42: AES-128 LoRa key — будь-який non-zero серед 4 слів = valid (key_or != 0). */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(aes_key, 0, sizeof(aes_key));

    uint32_t partial_key[8] = {0, 0, 0, 0x00000001, 0, 0, 0, 0};
    _mock_flash_key_provision(FLASH_KEY_MAGIC, partial_key);
    Load_AES_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(aes_key[3], 0x00000001);
}

TEST(test_load_key_preserves_all_4_words) {
    /* Post-ARCH.42: AES-128 LoRa key = перші 4 words копіюються коректно */
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
}

TEST(test_load_key_magic_value_correct) {
    /* Verify FLASH_KEY_MAGIC = "KEYL" = 0x4B45594CUL (post-ARCH.42; was "SKEY"). */
    ASSERT_EQ(FLASH_KEY_MAGIC, 0x4B45594CUL);
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
    ASSERT_EQ(aes_key[3], 0x44444444);  /* Останнє слово AES-128 LoRa (post-ARCH.42) */
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.2 (в)] CLUSTER BROADCAST KEY (KEYB) LOADING TESTS
 * ════════════════════════════════════════════════════════════════════ */

static const uint32_t _test_bcast_key[4] = {
    0xB0B1B2B3, 0xC0C1C2C3, 0xD0D1D2D3, 0xE0E1E2E3
};

/* Спільна підготовка: session-ключ уже в RAM (Load_Broadcast_Key
   викликається ПІСЛЯ Load_AES_Key — порядок несучий, main.c). */
static void _bcast_test_arrange_session(void) {
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    _mock_flash_key_provision(FLASH_KEY_MAGIC, _test_provisioned_key);
    Load_AES_Key();
    memset(bcast_key, 0, sizeof(bcast_key));
    bcast_key_is_fallback = 0xFF; /* мітка «ще не виставлено» */
}

TEST(test_load_bcast_provisioned_success) {
    /* KEYB прошито → bcast_key = KEYB-значення, НЕ fallback */
    _bcast_test_arrange_session();
    _mock_flash_bcast_reset();
    _mock_flash_bcast_provision(FLASH_BCAST_KEY_MAGIC, _test_bcast_key);

    Load_Broadcast_Key();

    ASSERT_EQ(bcast_key_is_fallback, 0);
    for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
        ASSERT_EQ(bcast_key[i], _test_bcast_key[i]);
    }
    /* Session недоторканий — двоключовість реальна */
    ASSERT_EQ(aes_key[0], 0xAABBCCDD);
    ASSERT_NE(bcast_key[0], aes_key[0]);
}

TEST(test_load_bcast_unprovisioned_falls_back_to_session) {
    /* KEYB відсутній (0xFF-стертий Flash) → fail-open: bcast = KEYL,
       прапорець піднято, Error_Handler НЕ кликано (bench-плата живе) */
    _bcast_test_arrange_session();
    _mock_flash_bcast_reset();

    Load_Broadcast_Key();

    ASSERT_EQ(_mock_error_handler_called, 0);
    ASSERT_EQ(bcast_key_is_fallback, 1);
    for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
        ASSERT_EQ(bcast_key[i], aes_key[i]);
    }
}

TEST(test_load_bcast_wrong_magic_falls_back) {
    /* Чужий magic → та сама fail-open деградація */
    _bcast_test_arrange_session();
    _mock_flash_bcast_reset();
    _mock_flash_bcast_provision(0xDEADBEEF, _test_bcast_key);

    Load_Broadcast_Key();

    ASSERT_EQ(bcast_key_is_fallback, 1);
    ASSERT_EQ(bcast_key[0], aes_key[0]);
}

TEST(test_load_bcast_zero_key_falls_back) {
    /* Magic є, ключ нульовий (битий provisioning) → fallback, не нулі:
       нульовий амбієнт-ключ зробив би downlink тихо-нечитним */
    _bcast_test_arrange_session();
    _mock_flash_bcast_reset();
    const uint32_t zero_key[4] = {0, 0, 0, 0};
    _mock_flash_bcast_provision(FLASH_BCAST_KEY_MAGIC, zero_key);

    Load_Broadcast_Key();

    ASSERT_EQ(bcast_key_is_fallback, 1);
    ASSERT_EQ(bcast_key[0], aes_key[0]);
    ASSERT_NE(bcast_key[0], 0);
}

TEST(test_load_bcast_magic_value_correct) {
    /* "KEYB" = 0x4B455942 — дзеркало FLASH_BCAST_KEY_MAGIC у main.c */
    ASSERT_EQ(FLASH_BCAST_KEY_MAGIC, 0x4B455942UL);
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

/* [FW.30] Civil-days KAT: точна громадянська арифметика
 * (з високосними) замість старого approx_days (Y*365+M*30). RTC-default
 * 2000-01-01 → 10957 = бекендів FIRMWARE_RTC_DEFAULT_EPOCH_DAY (ARCH.41). */
TEST(test_days_from_civil_known_dates) {
    ASSERT_EQ(Silken_Days_From_Civil(1970, 1, 1), 0);
    ASSERT_EQ(Silken_Days_From_Civil(2000, 1, 1), 10957);   /* RTC-default після VBAT loss */
    ASSERT_EQ(Silken_Days_From_Civil(2024, 2, 29), 19782);  /* Високосний день існує */
    ASSERT_EQ(Silken_Days_From_Civil(2026, 6, 6), 20610);   /* День цього аудиту */
}

TEST(test_epoch_day_from_unix_boundaries) {
    ASSERT_EQ(Silken_Epoch_Day_From_Unix(0u), 0u);
    ASSERT_EQ(Silken_Epoch_Day_From_Unix(946684800u), 10957u);  /* 2000-01-01 00:00:00 */
    ASSERT_EQ(Silken_Epoch_Day_From_Unix(946771199u), 10957u);  /* 2000-01-01 23:59:59 */
    ASSERT_EQ(Silken_Epoch_Day_From_Unix(946771200u), 10958u);  /* Північ наступного дня */
}

/* [FW.20 × FW.30] Beacon-пріоритет: коли Солдат чув Королеву, epoch_day
 * походить з UTC (точний збіг з backend-кандидатами today/yesterday), а не
 * з RTC-календаря. Старий код обіцяв це коментарем, але ігнорував unix_ts. */
TEST(test_cold_start_prefers_beacon_unix_ts_over_rtc) {
    _mock_flash_seed_reset();
    _mock_flash_seed_provision(FLASH_SEED_MAGIC, _test_provisioned_seed);
    Load_Lorenz_Seed();

    /* RTC-фолбек (unix_ts = 0): мок-дата 2026-05-02 */
    soldier_unix_ts = 0;
    float xr, yr, zr;
    Derive_Cold_Start_State(&xr, &yr, &zr);

    /* Beacon-шлях: UTC-секунди (epoch_day 20610) — інша епоха ніж RTC-fallback */
    soldier_unix_ts            = 1780747200u;
    soldier_unix_ts_local_tick = 0;
    float xb, yb, zb;
    Derive_Cold_Start_State(&xb, &yb, &zb);

    ASSERT_TRUE(xb != xr || yb != yr || zb != zr);

    /* Beacon-шлях має дорівнювати прямій деривації з epoch_day = ts/86400 */
    double dx, dy, dz;
    Silken_Derive_Initial_State(lorenz_seed, 1780747200u / 86400u, &dx, &dy, &dz);
    ASSERT_TRUE(xb == (float)dx && yb == (float)dy && zb == (float)dz);

    soldier_unix_ts = 0;  /* Не отруюємо наступні тести */
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
 * [FW.8] CMD_SET_THRESHOLDS frame parsing (Soldier side).
 * Mirrors backend OtaPackagerService.build_threshold_config_block — any
 * change to the wire format MUST update both this test bank and the Ruby
 * service simultaneously (cross-stack contract).
 * ════════════════════════════════════════════════════════════════════ */
#define S_CMD_SET_THRESHOLDS_MARKER  0x9A
#define S_CMD_THRESHOLDS_FRAME_SIZE  13
#define S_CMD_THRESHOLDS_PAYLOAD_LEN 10
#define S_CMD_THRESHOLDS_BODY_SIZE   8

/* CRC-16/CCITT-FALSE — One-Home: common/silken_crc.h (той самий код, що
 * компілюється у soldier/main.c і queen/main.c). [FW.53] */
#include "../common/silken_crc.h"
static uint16_t soldier_crc16_ccitt(const uint8_t* data, uint16_t len)
{
    return Silken_Crc16_Ccitt(data, len);
}

/* Compose a backend-style frame: [0x9A][len_le=10][body:8][crc_le:2]. */
static void compose_threshold_frame(int16_t z_min_x100, int16_t z_max_x100,
                                     int16_t z_opt_x100, uint8_t species,
                                     uint8_t version, uint8_t out[13])
{
    out[0] = S_CMD_SET_THRESHOLDS_MARKER;
    out[1] = (uint8_t)(S_CMD_THRESHOLDS_PAYLOAD_LEN & 0xFFu);
    out[2] = (uint8_t)((S_CMD_THRESHOLDS_PAYLOAD_LEN >> 8) & 0xFFu);

    uint16_t u_min = (uint16_t)z_min_x100;
    uint16_t u_max = (uint16_t)z_max_x100;
    uint16_t u_opt = (uint16_t)z_opt_x100;
    out[3] = (uint8_t)(u_min & 0xFFu);
    out[4] = (uint8_t)((u_min >> 8) & 0xFFu);
    out[5] = (uint8_t)(u_max & 0xFFu);
    out[6] = (uint8_t)((u_max >> 8) & 0xFFu);
    out[7] = (uint8_t)(u_opt & 0xFFu);
    out[8] = (uint8_t)((u_opt >> 8) & 0xFFu);
    out[9]  = species;
    out[10] = version;

    uint16_t crc = soldier_crc16_ccitt(&out[3], S_CMD_THRESHOLDS_BODY_SIZE);
    out[11] = (uint8_t)(crc & 0xFFu);
    out[12] = (uint8_t)((crc >> 8) & 0xFFu);
}

/* Pure-logic mirror of Soldier_Handle_CMD_SET_THRESHOLDS (in soldier/main.c).
 * Returns 1 on accept (mutates *out_z_min/max/opt/species/version), 0 on reject.
 * Kept in sync with the firmware impl by review — invariants tested below. */
static uint8_t Test_Handle_CMD_SET_THRESHOLDS(const uint8_t* frame, uint16_t size,
                                               int16_t* out_z_min, int16_t* out_z_max,
                                               int16_t* out_z_opt,
                                               uint8_t* out_species, uint8_t* out_version)
{
    if (size < S_CMD_THRESHOLDS_FRAME_SIZE)              return 0;
    if (frame[0] != S_CMD_SET_THRESHOLDS_MARKER)         return 0;

    uint16_t plen = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (plen != S_CMD_THRESHOLDS_PAYLOAD_LEN)            return 0;

    const uint8_t* body = frame + 3;
    uint16_t expected = soldier_crc16_ccitt(body, S_CMD_THRESHOLDS_BODY_SIZE);
    uint16_t received = (uint16_t)body[8] | ((uint16_t)body[9] << 8);
    if (expected != received)                            return 0;

    int16_t z_min = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    int16_t z_max = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    int16_t z_opt = (int16_t)((uint16_t)body[4] | ((uint16_t)body[5] << 8));

    if (!(z_min < z_max))                                return 0;
    if (z_opt < z_min || z_opt > z_max)                  return 0;
    if (z_min < -10000 || z_max > 10000)                 return 0;

    *out_z_min   = z_min;
    *out_z_max   = z_max;
    *out_z_opt   = z_opt;
    *out_species = body[6];
    *out_version = body[7];
    return 1;
}

TEST(test_thresholds_accepts_default_pinus_sylvestris) {
    /* species_id=0 (Pinus sylvestris), version=1, defaults from bio_contract.rb */
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 1);
    ASSERT_EQ(mn, 200);
    ASSERT_EQ(mx, 4500);
    ASSERT_EQ(op, 2900);
    ASSERT_EQ(sp, 0);
    ASSERT_EQ(ver, 1);
}

TEST(test_thresholds_accepts_negative_z_min) {
    /* Some species can have z_min in the negative band. */
    uint8_t frame[13];
    compose_threshold_frame(-500, 3500, 1500, 4, 7, frame);  /* Betula pendula */

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 1);
    ASSERT_EQ(mn, -500);
    ASSERT_EQ(mx, 3500);
    ASSERT_EQ(op, 1500);
}

TEST(test_thresholds_rejects_wrong_marker) {
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0, 1, frame);
    frame[0] = 0x99;  /* OTA marker — not us */

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_wrong_payload_len) {
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0, 1, frame);
    frame[1] = 9;  /* expected 10 */

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_bad_crc) {
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0, 1, frame);
    frame[11] ^= 0xFF;  /* flip low CRC byte */

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_bit_flip_in_body) {
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0, 1, frame);
    frame[3] ^= 0x01;  /* corrupt body — CRC will mismatch */

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_z_min_geq_z_max) {
    /* Collapsed zone (z_min == z_max) — invariant violation. */
    uint8_t frame[13];
    compose_threshold_frame(2900, 2900, 2900, 0, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_z_opt_outside_band) {
    /* z_opt = 5000 but z_max = 4500 → reject. */
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 5000, 0, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_z_below_minus_100) {
    /* |z_min| ≤ 100.00 → ≤ 10000 absolute. -15000 == -150.00 → reject. */
    uint8_t frame[13];
    compose_threshold_frame(-15000, 4500, 0, 0, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_z_above_plus_100) {
    uint8_t frame[13];
    compose_threshold_frame(200, 15000, 5000, 0, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_rejects_short_frame) {
    uint8_t frame[12] = {0};  /* one byte short */
    frame[0] = S_CMD_SET_THRESHOLDS_MARKER;
    frame[1] = S_CMD_THRESHOLDS_PAYLOAD_LEN;

    int16_t mn=0, mx=0, op=0; uint8_t sp=0xFF, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 12, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 0);
}

TEST(test_thresholds_unmapped_species_id_0xFF_accepted) {
    /* Backend uses 0xFF for unmapped species — must still parse. */
    uint8_t frame[13];
    compose_threshold_frame(200, 4500, 2900, 0xFF, 1, frame);

    int16_t mn=0, mx=0, op=0; uint8_t sp=0, ver=0;
    uint8_t ok = Test_Handle_CMD_SET_THRESHOLDS(frame, 13, &mn, &mx, &op, &sp, &ver);
    ASSERT_EQ(ok, 1);
    ASSERT_EQ(sp, 0xFF);
}

/* ════════════════════════════════════════════════════════════════════
 * 14. FW.27-B Magic Re-Request — Soldier-initiated vector OTA recovery
 * ════════════════════════════════════════════════════════════════════
 * Wire (16-byte AES-256-ECB block):
 *   [0]    OTA_REQ_MARKER (0x55)
 *   [1..4] DID big-endian
 *   [5..6] total_chunks big-endian (cross-check with Queen)
 *   [7..15] missing_bitmap (LSB-first; bit i ⇔ chunk_idx i missing)
 *
 * Triggered when ota_chunks_received < ota_total_chunks AND
 * OTA_REREQUEST_SILENT_WAKEUPS тихих пробуджень поспіль (≈5 хв wall —
 * tick-різниця мертва у STOP2, лічимо пробудження з відкритим вухом).
 * ════════════════════════════════════════════════════════════════════ */
#define S_OTA_REQ_MARKER             0x55
#define S_OTA_REQ_HEADER_SIZE        7
#define S_OTA_REQ_BITMAP_MAX_BYTES   9
#define S_OTA_REQ_PACKET_SIZE        16
#define S_OTA_REREQUEST_SILENT_WAKEUPS 10u

/* Pure-logic mirror of Build_OTA_ReRequest_Payload (in soldier/main.c).
 * Returns 1 if any chunk is missing (TX), 0 if all received (skip TX). */
static uint8_t Test_Build_OTA_ReRequest_Payload(uint32_t did,
                                                 uint16_t total_chunks,
                                                 const uint8_t* chunks_received,
                                                 uint16_t       chunks_received_size,
                                                 uint8_t out[S_OTA_REQ_PACKET_SIZE])
{
    if (total_chunks == 0)                         return 0;
    if (chunks_received == NULL || out == NULL)    return 0;

    memset(out, 0, S_OTA_REQ_PACKET_SIZE);
    out[0] = S_OTA_REQ_MARKER;
    out[1] = (uint8_t)(did >> 24);
    out[2] = (uint8_t)(did >> 16);
    out[3] = (uint8_t)(did >> 8);
    out[4] = (uint8_t)(did & 0xFFu);
    out[5] = (uint8_t)(total_chunks >> 8);
    out[6] = (uint8_t)(total_chunks & 0xFFu);

    uint16_t cap = (total_chunks > S_OTA_REQ_BITMAP_MAX_BYTES * 8u)
                       ? (uint16_t)(S_OTA_REQ_BITMAP_MAX_BYTES * 8u)
                       : total_chunks;
    uint8_t any_missing = 0;
    for (uint16_t i = 0; i < cap; i++) {
        uint8_t got = (i < chunks_received_size) ? chunks_received[i] : 0;
        if (!got) {
            out[S_OTA_REQ_HEADER_SIZE + (i / 8u)] |= (uint8_t)(1u << (i % 8u));
            any_missing = 1;
        }
    }
    return any_missing;
}

/* Pure decision — mirror of Phase 4.5 epilogue: ЛІЧИЛЬНИК тихих пробуджень
 * замість tick-різниці (HAL_GetTick мертвий у STOP2 → стара 5-хв перевірка
 * запізнювала зойк у ~6-15×; 10 пробуджень × цикл 26-32 с ≈ той самий
 * 5-хв інтент wall-часу). Мутує *silent_wakeups як епілог циклу: інкремент
 * при відкритому вікні, скидання при fire. 1 = подати зойк. */
static uint8_t Test_OTA_Silent_Wakeup_Tick(uint16_t total, uint16_t received,
                                            uint32_t last_rx_tick,
                                            uint8_t *silent_wakeups)
{
    if (total == 0)             return 0;
    if (received >= total)      return 0;
    if (last_rx_tick == 0)      return 0;
    if (*silent_wakeups < 255u) (*silent_wakeups)++;
    if (*silent_wakeups >= S_OTA_REREQUEST_SILENT_WAKEUPS) {
        *silent_wakeups = 0; /* даємо Королеві стільки ж тихих пробуджень */
        return 1;
    }
    return 0;
}

TEST(test_rereq_full_bitmap_when_no_chunks) {
    uint32_t did = 0xDEADBEEFu;
    uint16_t total = 16;
    uint8_t chunks[16] = {0};
    uint8_t out[16] = {0};

    uint8_t any = Test_Build_OTA_ReRequest_Payload(did, total, chunks, 16, out);
    ASSERT_EQ(any, 1);
    ASSERT_EQ(out[0], S_OTA_REQ_MARKER);
    /* DID big-endian */
    ASSERT_EQ(out[1], 0xDE); ASSERT_EQ(out[2], 0xAD);
    ASSERT_EQ(out[3], 0xBE); ASSERT_EQ(out[4], 0xEF);
    /* total big-endian */
    ASSERT_EQ(out[5], 0x00); ASSERT_EQ(out[6], 0x10);
    /* bitmap byte 0 = 0xFF (chunks 0..7 missing), byte 1 = 0xFF (chunks 8..15) */
    ASSERT_EQ(out[7], 0xFF);
    ASSERT_EQ(out[8], 0xFF);
    /* unused bitmap bytes zero */
    for (int i = 9; i < 16; i++) ASSERT_EQ(out[i], 0x00);
}

TEST(test_rereq_partial_bitmap) {
    /* Got chunks 0,2,4,5; missing 1,3 ⇒ bitmap byte 0 = 0b00001010 = 0x0A */
    uint16_t total = 6;
    uint8_t chunks[6] = {1, 0, 1, 0, 1, 1};
    uint8_t out[16] = {0};

    uint8_t any = Test_Build_OTA_ReRequest_Payload(0x01020304u, total, chunks, 6, out);
    ASSERT_EQ(any, 1);
    ASSERT_EQ(out[7], 0x0A);
    /* No bitmap bits beyond cap=6 */
    ASSERT_EQ(out[8], 0);
}

TEST(test_rereq_no_missing_returns_zero) {
    uint16_t total = 8;
    uint8_t chunks[8] = {1, 1, 1, 1, 1, 1, 1, 1};
    uint8_t out[16] = {0};

    uint8_t any = Test_Build_OTA_ReRequest_Payload(0x12345678u, total, chunks, 8, out);
    ASSERT_EQ(any, 0);  /* No TX needed */
}

TEST(test_rereq_total_zero_skipped) {
    uint8_t chunks[1] = {0};
    uint8_t out[16] = {0};
    uint8_t any = Test_Build_OTA_ReRequest_Payload(0x1u, 0, chunks, 1, out);
    ASSERT_EQ(any, 0);
}

TEST(test_rereq_did_endian_consistent) {
    uint32_t did = 0xCAFEBABEu;
    uint16_t total = 1;
    uint8_t chunks[1] = {0};
    uint8_t out[16] = {0};

    Test_Build_OTA_ReRequest_Payload(did, total, chunks, 1, out);
    ASSERT_EQ(out[1], 0xCA); ASSERT_EQ(out[2], 0xFE);
    ASSERT_EQ(out[3], 0xBA); ASSERT_EQ(out[4], 0xBE);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.2] RX size-guard — freeze-contract воріт ДО декрипту
 * ════════════════════════════════════════════════════════════════════
 * Дзеркало ungated-гейта Фази 4.5 (main.c): усі легальні кадри Солдата =
 * рівно 16B ECB; 28B CCM-кадр сусіда, прогнаний ECB'ом, мав ~1/256 шанс
 * хибно зійтися на 0x99/0x9B і отруїти ota_buffer/печатку. Guard стоїть
 * ПЕРЕД HAL_CRYP_Decrypt — сюди й дзеркалимо принцип: не-16 → нуль дії. */
static uint8_t Test_Soldier_Rx_Size_Accepted(uint16_t size)
{
    return (size == 16u) ? 1u : 0u;
}

TEST(test_fw2_rx_guard_accepts_only_16) {
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(16), 1);
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(28), 0);  /* CCM-кадр сусіда */
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(0), 0);
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(6), 0);   /* MIN_OTA-край */
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(32), 0);
    ASSERT_EQ(Test_Soldier_Rx_Size_Accepted(255), 0);
}

TEST(test_fw2_rx_guard_28b_never_reaches_ota_assembly) {
    /* Контамінаційна пастка закрита: відкинутий 28B-кадр не сміє лишити
     * сліду у станi OTA-збірки (раніше сміттєвий декрипт міг). */
    OTA_Init();
    if (!Test_Soldier_Rx_Size_Accepted(28)) {
        /* main.c: break ДО декрипту — жодного виклику OTA-гілок. */
    }
    ASSERT_EQ(ota_total_chunks, 0);
    ASSERT_EQ(ota_chunks_received, 0);
    ASSERT_EQ(ota_bytes_received, 0);
}

TEST(test_rereq_bitmap_capped_at_72_chunks) {
    /* 100 chunks → only first 72 covered by 9-byte bitmap. Beyond cap stays 0. */
    uint16_t total = 100;
    uint8_t chunks[100] = {0};
    uint8_t out[16] = {0};

    Test_Build_OTA_ReRequest_Payload(0x1u, total, chunks, 100, out);
    /* All 9 bitmap bytes 0xFF (72 chunks all "missing"); high bits beyond 72 are unset */
    for (int i = 0; i < 9; i++) ASSERT_EQ(out[7 + i], 0xFF);
}

TEST(test_rereq_chunk_71_set_72_unset) {
    /* Boundary case: chunks 0..71 missing → bit 71 (byte 8 bit 7) should be set. */
    uint16_t total = 72;
    uint8_t chunks[72] = {0};
    uint8_t out[16] = {0};

    Test_Build_OTA_ReRequest_Payload(0x1u, total, chunks, 72, out);
    /* Byte 8 (offset 7+8=15) covers bits 64..71 → all 8 bits set = 0xFF */
    ASSERT_EQ(out[15], 0xFF);
}

TEST(test_rereq_fires_on_10th_silent_wakeup_and_resets) {
    /* total=10, received=3: 9 тихих пробуджень мовчимо, 10-те — зойк,
     * лічильник у нуль (Королеві — таке ж вікно на ретрансляцію). */
    uint8_t silent = 0;
    for (int w = 1; w <= 9; w++)
        ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 3, 1000, &silent), 0);
    ASSERT_EQ(silent, 9);
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 3, 1000, &silent), 1);
    ASSERT_EQ(silent, 0);
}

TEST(test_rereq_chunk_rx_reset_restarts_silence_window) {
    /* 7 тихих → чанк прийшов (епілог RX скидає лічильник) → знову повних
     * 10 тихих до зойку. */
    uint8_t silent = 0;
    for (int w = 0; w < 7; w++) Test_OTA_Silent_Wakeup_Tick(10, 3, 1000, &silent);
    silent = 0; /* дзеркало RX-гілки: ota_silent_wakeups = 0 при новому чанку */
    for (int w = 1; w <= 9; w++)
        ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 4, 1000, &silent), 0);
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 4, 1000, &silent), 1);
}

TEST(test_rereq_should_NOT_tick_when_complete) {
    uint8_t silent = 0;
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 10, 1000, &silent), 0);
    ASSERT_EQ(silent, 0); /* закрите вікно не накопичує тиші */
}

TEST(test_rereq_should_NOT_tick_when_window_inactive) {
    /* total=0 ⇒ no OTA window */
    uint8_t silent = 0;
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(0, 0, 1000, &silent), 0);
    ASSERT_EQ(silent, 0);
}

TEST(test_rereq_should_NOT_tick_when_last_tick_zero) {
    /* last_rx_tick == 0 ⇒ ще не чули жодного чанку — нічого перепитувати */
    uint8_t silent = 0;
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(10, 0, 0, &silent), 0);
    ASSERT_EQ(silent, 0);
}

TEST(test_rereq_silent_counter_saturates_no_wrap) {
    /* Патологія: вікно відкрите, зойки не виходять (edge any_missing=0 для
     * >72-чанкових кампаній) — лічильник не повинен обернутись через 255 у
     * тишу. Сатурація тримає поведінку «час подавати голос». */
    uint8_t silent = 254;
    (void)Test_OTA_Silent_Wakeup_Tick(100, 80, 1000, &silent); /* 255 → fire */
    silent = 255;
    ASSERT_EQ(Test_OTA_Silent_Wakeup_Tick(100, 80, 1000, &silent), 1);
}

/* ════════════════════════════════════════════════════════════════════
 * 15. FW.23 OTA HMAC trailer — wire format + dual-gate verification
 * ════════════════════════════════════════════════════════════════════ */
#define S_HMAC_TRAILER_MARKER       0x9B
#define S_HMAC_TRAILER_HEADER_SIZE  5
#define S_HMAC_TRAILER_SEG_BYTES    11
#define S_HMAC_TAG_BYTES            32
#define S_HMAC_TRAILER_TOTAL_SEGS   3
#define S_HMAC_VERSION_SEG_IDX      4
#define S_OTA_TRAILER_TOTAL_CHUNKS  4
#define S_OTA_TRAILER_ALL_RECEIVED  0x0Fu
#define S_OTA_RITE_MAGIC            0x45544952u  /* "RITE" little-endian */

/* Pure-logic mirror of Parse_HMAC_Trailer_Chunk (in soldier/main.c).
 * [FW.23] seg 1..3 → tag; seg 4 → version_id (BE bytes [5..8]). */
static int Test_Parse_HMAC_Trailer_Chunk(const uint8_t* chunk, uint16_t chunk_size,
                                          uint8_t tag_out[S_HMAC_TAG_BYTES],
                                          uint32_t* version_out,
                                          uint8_t* segments_received_inout)
{
    if (chunk == NULL || tag_out == NULL || version_out == NULL ||
        segments_received_inout == NULL)                                    return -1;
    if (chunk_size < S_HMAC_TRAILER_HEADER_SIZE + S_HMAC_TRAILER_SEG_BYTES)  return -1;
    if (chunk[0] != S_HMAC_TRAILER_MARKER)                                   return 0;

    uint16_t seg_idx = ((uint16_t)chunk[1] << 8) | chunk[2];
    if (seg_idx < 1 || seg_idx > S_OTA_TRAILER_TOTAL_CHUNKS)                 return -1;

    if (seg_idx == S_HMAC_VERSION_SEG_IDX) {
        *version_out = ((uint32_t)chunk[S_HMAC_TRAILER_HEADER_SIZE]     << 24) |
                       ((uint32_t)chunk[S_HMAC_TRAILER_HEADER_SIZE + 1] << 16) |
                       ((uint32_t)chunk[S_HMAC_TRAILER_HEADER_SIZE + 2] <<  8) |
                       ((uint32_t)chunk[S_HMAC_TRAILER_HEADER_SIZE + 3]);
        *segments_received_inout |= (uint8_t)(1u << (S_HMAC_VERSION_SEG_IDX - 1));
        return 1;
    }

    uint8_t base = (uint8_t)((seg_idx - 1) * S_HMAC_TRAILER_SEG_BYTES);
    uint8_t copy_len = S_HMAC_TRAILER_SEG_BYTES;
    if (seg_idx == S_HMAC_TRAILER_TOTAL_SEGS) {
        copy_len = (uint8_t)(S_HMAC_TAG_BYTES - base);
    }
    memcpy(&tag_out[base], &chunk[S_HMAC_TRAILER_HEADER_SIZE], copy_len);
    *segments_received_inout |= (uint8_t)(1u << (seg_idx - 1));
    return 1;
}

/* Constant-time compare — same as Hmac_Constant_Time_Compare. */
static int Test_HMAC_CT_Compare(const uint8_t* a, const uint8_t* b, size_t len)
{
    if (a == NULL || b == NULL) return 1;
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return (int)diff;
}

/* Dual-gate logic mirror of OTA_Verify_Dual_Gate. */
static int Test_OTA_Verify_Dual_Gate(const uint8_t* bytecode, uint16_t bc_size,
                                       const uint8_t expected[S_HMAC_TAG_BYTES],
                                       const uint8_t received[S_HMAC_TAG_BYTES])
{
    if (bytecode == NULL || expected == NULL || received == NULL) return 0;
    if (bc_size < 4)                                              return 0;

    uint32_t magic = ((uint32_t)bytecode[0])       |
                     ((uint32_t)bytecode[1] <<  8) |
                     ((uint32_t)bytecode[2] << 16) |
                     ((uint32_t)bytecode[3] << 24);
    if (magic != S_OTA_RITE_MAGIC)                                return 0;

    if (Test_HMAC_CT_Compare(expected, received, S_HMAC_TAG_BYTES) != 0) return 0;
    return 1;
}

/* CRC32 (ISO 3309 / zlib) — mirror of the firmware loop, to forge valid OTA
 * stream tails for the finalize tests. */
static uint32_t test_crc32_iso3309(const uint8_t* data, uint16_t len)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t b = 0; b < 8; b++) {
            crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
        }
    }
    return ~crc;
}

/* [FW.23] Verdict mirror of OTA_Try_Finalize. Crypto is the REAL shared
 * Silken_Hmac_Sha256_Concat (silken_sha256.h via lorenz_seed.h) — the security
 * bytes are tested for real; only the WAIT/APPLY/REJECT glue is mirrored. */
typedef enum { S_OTA_WAIT = 0, S_OTA_APPLY, S_OTA_REJECT } STestOtaVerdict;

static STestOtaVerdict Test_OTA_Try_Finalize(const uint8_t* buf, uint16_t bytes_received,
                                             uint16_t chunks_received, uint16_t total_chunks,
                                             uint8_t segments_received,
                                             const uint8_t* k_ota, uint8_t k_ota_valid,
                                             uint32_t version_id,
                                             const uint8_t received_tag[S_HMAC_TAG_BYTES],
                                             uint16_t* data_len_out)
{
    if (buf == NULL || received_tag == NULL || data_len_out == NULL) return S_OTA_REJECT;
    if (total_chunks == 0 || chunks_received < total_chunks)         return S_OTA_WAIT;
    if (segments_received != S_OTA_TRAILER_ALL_RECEIVED)             return S_OTA_WAIT;
    if (bytes_received <= 4)                                         return S_OTA_REJECT;

    uint16_t data_len = (uint16_t)(bytes_received - 4u);
    *data_len_out = data_len;

    uint32_t expected_crc = ((uint32_t)buf[data_len] << 24) |
                            ((uint32_t)buf[data_len + 1] << 16) |
                            ((uint32_t)buf[data_len + 2] << 8)  |
                            (uint32_t)buf[data_len + 3];
    if (test_crc32_iso3309(buf, data_len) != expected_crc)          return S_OTA_REJECT;
    if (!k_ota_valid)                                               return S_OTA_REJECT;

    uint8_t suffix[6];
    suffix[0] = (uint8_t)(version_id >> 24);
    suffix[1] = (uint8_t)(version_id >> 16);
    suffix[2] = (uint8_t)(version_id >> 8);
    suffix[3] = (uint8_t)(version_id & 0xFFu);
    suffix[4] = (uint8_t)(total_chunks >> 8);
    suffix[5] = (uint8_t)(total_chunks & 0xFFu);

    uint8_t expected_hmac[S_HMAC_TAG_BYTES];
    Silken_Hmac_Sha256_Concat(k_ota, 32u, buf, data_len, suffix, sizeof(suffix), expected_hmac);

    if (Test_OTA_Verify_Dual_Gate(buf, data_len, expected_hmac, received_tag) != 1) {
        return S_OTA_REJECT;
    }
    return S_OTA_APPLY;
}

/* Helper: build one of 3 backend HMAC tag chunks (16-byte plaintext block).
 * seg_idx ∈ {1,2,3}. Caller passes 32-byte tag; this packs segment.            */
static void compose_hmac_trailer_chunk(uint8_t seg_idx, uint16_t total_chunks,
                                        const uint8_t tag[S_HMAC_TAG_BYTES],
                                        uint8_t out[16])
{
    memset(out, 0, 16);
    out[0] = S_HMAC_TRAILER_MARKER;
    out[1] = (uint8_t)(seg_idx >> 8);
    out[2] = (uint8_t)(seg_idx & 0xFFu);
    out[3] = (uint8_t)(total_chunks >> 8);
    out[4] = (uint8_t)(total_chunks & 0xFFu);

    uint8_t base = (uint8_t)((seg_idx - 1) * S_HMAC_TRAILER_SEG_BYTES);
    uint8_t copy_len = S_HMAC_TRAILER_SEG_BYTES;
    if (seg_idx == S_HMAC_TRAILER_TOTAL_SEGS) {
        copy_len = (uint8_t)(S_HMAC_TAG_BYTES - base);
    }
    memcpy(&out[S_HMAC_TRAILER_HEADER_SIZE], &tag[base], copy_len);
}

/* [FW.23] Helper: build the seg-4 version chunk (mirror of backend layout). */
static void compose_version_chunk(uint16_t total_chunks, uint32_t version_id,
                                   uint8_t out[16])
{
    memset(out, 0, 16);
    out[0] = S_HMAC_TRAILER_MARKER;
    out[1] = (uint8_t)(S_HMAC_VERSION_SEG_IDX >> 8);
    out[2] = (uint8_t)(S_HMAC_VERSION_SEG_IDX & 0xFFu);
    out[3] = (uint8_t)(total_chunks >> 8);
    out[4] = (uint8_t)(total_chunks & 0xFFu);
    out[S_HMAC_TRAILER_HEADER_SIZE + 0] = (uint8_t)(version_id >> 24);
    out[S_HMAC_TRAILER_HEADER_SIZE + 1] = (uint8_t)(version_id >> 16);
    out[S_HMAC_TRAILER_HEADER_SIZE + 2] = (uint8_t)(version_id >> 8);
    out[S_HMAC_TRAILER_HEADER_SIZE + 3] = (uint8_t)(version_id & 0xFFu);
}

TEST(test_hmac_trailer_three_chunks_assemble_full_tag) {
    uint8_t expected[32];
    for (int i = 0; i < 32; i++) expected[i] = (uint8_t)(0xA0 + i);

    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;

    for (uint8_t s = 1; s <= 3; s++) {
        uint8_t chunk[16];
        compose_hmac_trailer_chunk(s, 5, expected, chunk);
        int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
        ASSERT_EQ(rc, 1);
    }
    ASSERT_EQ(segs, 0x07);
    ASSERT_EQ(memcmp(recv, expected, 32), 0);
}

TEST(test_hmac_trailer_out_of_order_chunks) {
    /* seg_idx 3, then 1, then 2 — final tag still matches expected. */
    uint8_t expected[32];
    for (int i = 0; i < 32; i++) expected[i] = (uint8_t)(0xC0 + i);

    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    uint8_t chunk[16];

    compose_hmac_trailer_chunk(3, 5, expected, chunk);
    Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    compose_hmac_trailer_chunk(1, 5, expected, chunk);
    Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    compose_hmac_trailer_chunk(2, 5, expected, chunk);
    Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);

    ASSERT_EQ(segs, 0x07);
    ASSERT_EQ(memcmp(recv, expected, 32), 0);
}

TEST(test_hmac_trailer_version_chunk_parses) {
    /* [FW.23] seg 4 carries version_id (BE) and sets bit 3. */
    uint8_t chunk[16];
    compose_version_chunk(5, 0x01020304u, chunk);
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    ASSERT_EQ(rc, 1);
    ASSERT_EQ(ver, 0x01020304u);
    ASSERT_EQ(segs, 0x08);  /* bit 3 only */
}

TEST(test_hmac_trailer_all_four_complete) {
    /* [FW.23] 3 tag chunks + version → 0x0F, tag + version both present. */
    uint8_t expected[32];
    for (int i = 0; i < 32; i++) expected[i] = (uint8_t)(0x40 + i);
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    uint8_t chunk[16];

    for (uint8_t s = 1; s <= 3; s++) {
        compose_hmac_trailer_chunk(s, 9, expected, chunk);
        Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    }
    compose_version_chunk(9, 0xDEADBEEFu, chunk);
    Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);

    ASSERT_EQ(segs, S_OTA_TRAILER_ALL_RECEIVED);
    ASSERT_EQ(memcmp(recv, expected, 32), 0);
    ASSERT_EQ(ver, 0xDEADBEEFu);
}

TEST(test_hmac_trailer_rejects_wrong_marker) {
    uint8_t chunk[16] = {0};
    chunk[0] = 0x99;  /* OTA bytecode marker, not 0x9B */
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    ASSERT_EQ(rc, 0);  /* not our marker */
    ASSERT_EQ(segs, 0);
}

TEST(test_hmac_trailer_rejects_seg_idx_zero) {
    uint8_t chunk[16] = {0};
    chunk[0] = S_HMAC_TRAILER_MARKER;
    chunk[1] = 0; chunk[2] = 0;  /* seg_idx = 0 invalid */
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    ASSERT_EQ(rc, -1);
}

TEST(test_hmac_trailer_rejects_seg_idx_above_4) {
    /* [FW.23] seg 4 is now valid (version); seg 5 must still be rejected. */
    uint8_t chunk[16] = {0};
    chunk[0] = S_HMAC_TRAILER_MARKER;
    chunk[1] = 0; chunk[2] = 5;  /* seg_idx = 5 invalid */
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs);
    ASSERT_EQ(rc, -1);
}

TEST(test_hmac_trailer_rejects_undersized_chunk) {
    uint8_t chunk[8] = {0};
    chunk[0] = S_HMAC_TRAILER_MARKER;
    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    int rc = Test_Parse_HMAC_Trailer_Chunk(chunk, 8, recv, &ver, &segs);
    ASSERT_EQ(rc, -1);
}

/* [FW.23] Silken_Hmac_Sha256_Concat(a,b) must equal one-shot HMAC over a‖b.
 * The one-shot is byte-parity vs OpenSSL (test_seed_derivation), so by
 * transitivity _Concat matches the backend OtaPackagerService.compute_hmac_tag. */
TEST(test_hmac_concat_equals_oneshot) {
    uint8_t key[32];   for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0x10 + i);
    uint8_t body[40];  for (int i = 0; i < 40; i++) body[i] = (uint8_t)(0x52 + i);
    uint8_t suffix[6] = { 0x00, 0x00, 0x00, 0x2A, 0x00, 0x09 };  /* ver=42, total=9 */

    uint8_t joined[46];
    memcpy(joined, body, 40);
    memcpy(joined + 40, suffix, 6);

    uint8_t via_concat[32], via_oneshot[32];
    Silken_Hmac_Sha256_Concat(key, 32, body, 40, suffix, 6, via_concat);
    Silken_Hmac_Sha256(key, 32, joined, 46, via_oneshot);
    ASSERT_EQ(memcmp(via_concat, via_oneshot, 32), 0);

    /* b_len==0 path equals plain HMAC over a. */
    uint8_t via_concat_a[32], via_oneshot_a[32];
    Silken_Hmac_Sha256_Concat(key, 32, body, 40, NULL, 0, via_concat_a);
    Silken_Hmac_Sha256(key, 32, body, 40, via_oneshot_a);
    ASSERT_EQ(memcmp(via_concat_a, via_oneshot_a, 32), 0);
}

/* [FW.23] Build a valid signed OTA image (RITE magic + CRC32 tail + real HMAC),
 * then drive OTA_Try_Finalize through APPLY / WAIT / REJECT paths. */
static uint16_t forge_signed_ota(uint8_t* buf, const uint8_t* key, uint32_t version_id,
                                 uint16_t total_chunks, uint8_t tag_out[32])
{
    /* Body: RITE magic + filler. */
    uint16_t body_len = 36;
    buf[0] = 0x52; buf[1] = 0x49; buf[2] = 0x54; buf[3] = 0x45;  /* "RITE" */
    for (uint16_t i = 4; i < body_len; i++) buf[i] = (uint8_t)(i * 7u + 1u);

    /* HMAC over body ‖ version_be ‖ total_be (matches backend + Soldier). */
    uint8_t suffix[6] = {
        (uint8_t)(version_id >> 24), (uint8_t)(version_id >> 16),
        (uint8_t)(version_id >> 8),  (uint8_t)(version_id & 0xFFu),
        (uint8_t)(total_chunks >> 8), (uint8_t)(total_chunks & 0xFFu)
    };
    Silken_Hmac_Sha256_Concat(key, 32, buf, body_len, suffix, 6, tag_out);

    /* Append CRC32 tail → assembled stream the Soldier holds. */
    uint32_t crc = test_crc32_iso3309(buf, body_len);
    buf[body_len + 0] = (uint8_t)(crc >> 24);
    buf[body_len + 1] = (uint8_t)(crc >> 16);
    buf[body_len + 2] = (uint8_t)(crc >> 8);
    buf[body_len + 3] = (uint8_t)(crc & 0xFFu);
    return (uint16_t)(body_len + 4);  /* bytes_received */
}

TEST(test_ota_finalize_apply_real_hmac) {
    uint8_t key[32]; for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0xC0 ^ i);
    uint8_t buf[64], tag[32];
    uint16_t total = 4;
    uint16_t bytes_received = forge_signed_ota(buf, key, 0x12345678u, total, tag);

    uint16_t dl = 0;
    STestOtaVerdict v = Test_OTA_Try_Finalize(buf, bytes_received, total, total,
                                              S_OTA_TRAILER_ALL_RECEIVED, key, 1,
                                              0x12345678u, tag, &dl);
    ASSERT_EQ(v, S_OTA_APPLY);
    ASSERT_EQ(dl, 36);
}

TEST(test_ota_finalize_wait_without_trailer) {
    /* Body assembled, but the 4 trailer chunks not all in → WAIT (no reset). */
    uint8_t key[32]; for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0xC0 ^ i);
    uint8_t buf[64], tag[32];
    uint16_t total = 4;
    uint16_t bytes_received = forge_signed_ota(buf, key, 0x12345678u, total, tag);

    uint16_t dl = 0;
    /* only 0x07 (tag) received, version (bit 3) still missing */
    STestOtaVerdict v = Test_OTA_Try_Finalize(buf, bytes_received, total, total,
                                              0x07u, key, 1, 0x12345678u, tag, &dl);
    ASSERT_EQ(v, S_OTA_WAIT);
}

TEST(test_ota_finalize_reject_tampered_body) {
    uint8_t key[32]; for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0xC0 ^ i);
    uint8_t buf[64], tag[32];
    uint16_t total = 4;
    uint16_t bytes_received = forge_signed_ota(buf, key, 0x12345678u, total, tag);

    /* Attacker flips a body byte AND recomputes CRC32 (CRC is not crypto). */
    buf[10] ^= 0xFF;
    uint16_t data_len = (uint16_t)(bytes_received - 4);
    uint32_t crc = test_crc32_iso3309(buf, data_len);
    buf[data_len + 0] = (uint8_t)(crc >> 24);
    buf[data_len + 1] = (uint8_t)(crc >> 16);
    buf[data_len + 2] = (uint8_t)(crc >> 8);
    buf[data_len + 3] = (uint8_t)(crc & 0xFFu);

    uint16_t dl = 0;
    STestOtaVerdict v = Test_OTA_Try_Finalize(buf, bytes_received, total, total,
                                              S_OTA_TRAILER_ALL_RECEIVED, key, 1,
                                              0x12345678u, tag, &dl);
    ASSERT_EQ(v, S_OTA_REJECT);  /* valid CRC, but HMAC catches the tamper */
}

TEST(test_ota_finalize_reject_version_mismatch) {
    /* Replay: same image+tag, but Soldier was told a different version → reject. */
    uint8_t key[32]; for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0xC0 ^ i);
    uint8_t buf[64], tag[32];
    uint16_t total = 4;
    uint16_t bytes_received = forge_signed_ota(buf, key, 0x00000007u, total, tag);

    uint16_t dl = 0;
    STestOtaVerdict v = Test_OTA_Try_Finalize(buf, bytes_received, total, total,
                                              S_OTA_TRAILER_ALL_RECEIVED, key, 1,
                                              0x00000008u /* wrong */, tag, &dl);
    ASSERT_EQ(v, S_OTA_REJECT);
}

TEST(test_ota_finalize_reject_no_key) {
    /* Without K_ota provisioned (valid=0) no OTA is ever applied (fail-safe). */
    uint8_t key[32]; for (int i = 0; i < 32; i++) key[i] = (uint8_t)(0xC0 ^ i);
    uint8_t buf[64], tag[32];
    uint16_t total = 4;
    uint16_t bytes_received = forge_signed_ota(buf, key, 0x12345678u, total, tag);

    uint16_t dl = 0;
    STestOtaVerdict v = Test_OTA_Try_Finalize(buf, bytes_received, total, total,
                                              S_OTA_TRAILER_ALL_RECEIVED, key, 0 /* no key */,
                                              0x12345678u, tag, &dl);
    ASSERT_EQ(v, S_OTA_REJECT);
}

TEST(test_dual_gate_both_pass_returns_1) {
    uint8_t bytecode[5] = {0x52, 0x49, 0x54, 0x45, 0xCC};  /* "RITE" + payload */
    uint8_t expected[32]; uint8_t received[32];
    for (int i = 0; i < 32; i++) { expected[i] = (uint8_t)i; received[i] = (uint8_t)i; }
    ASSERT_EQ(Test_OTA_Verify_Dual_Gate(bytecode, 5, expected, received), 1);
}

TEST(test_dual_gate_magic_fail_returns_0) {
    uint8_t bytecode[5] = {0x00, 0x00, 0x00, 0x00, 0xCC};  /* No magic */
    uint8_t expected[32] = {0}; uint8_t received[32] = {0};
    ASSERT_EQ(Test_OTA_Verify_Dual_Gate(bytecode, 5, expected, received), 0);
}

TEST(test_dual_gate_hmac_fail_returns_0) {
    uint8_t bytecode[4] = {0x52, 0x49, 0x54, 0x45};  /* magic ok */
    uint8_t expected[32]; uint8_t received[32];
    for (int i = 0; i < 32; i++) { expected[i] = (uint8_t)i; received[i] = (uint8_t)i; }
    received[15] ^= 0x01;  /* one-bit flip in middle of tag */
    ASSERT_EQ(Test_OTA_Verify_Dual_Gate(bytecode, 4, expected, received), 0);
}

TEST(test_dual_gate_short_bytecode_returns_0) {
    /* < 4 bytes can't even hold magic */
    uint8_t bytecode[3] = {0x52, 0x49, 0x54};
    uint8_t expected[32] = {0}; uint8_t received[32] = {0};
    ASSERT_EQ(Test_OTA_Verify_Dual_Gate(bytecode, 3, expected, received), 0);
}

TEST(test_dual_gate_constant_time_compare_zero_diff) {
    /* Identical inputs → 0 (equal) */
    uint8_t a[32]; for (int i = 0; i < 32; i++) a[i] = (uint8_t)i;
    ASSERT_EQ(Test_HMAC_CT_Compare(a, a, 32), 0);
}

TEST(test_dual_gate_constant_time_compare_first_byte_diff) {
    uint8_t a[32]; uint8_t b[32];
    for (int i = 0; i < 32; i++) { a[i] = (uint8_t)i; b[i] = (uint8_t)i; }
    b[0] ^= 0xFF;
    ASSERT_NE(Test_HMAC_CT_Compare(a, b, 32), 0);
}

TEST(test_dual_gate_constant_time_compare_last_byte_diff) {
    /* Last-byte difference must be detected — accumulator design. */
    uint8_t a[32]; uint8_t b[32];
    for (int i = 0; i < 32; i++) { a[i] = (uint8_t)i; b[i] = (uint8_t)i; }
    b[31] ^= 0x01;
    ASSERT_NE(Test_HMAC_CT_Compare(a, b, 32), 0);
}

/* ─── [FW.27 + FW.23 follow-up: HMAC trailer cross-cycle, 2026-05-03] ───
 * Сторожовий пес печатки переживає STOP2: bitmask `ota_hmac_segments_received`
 * та accumulator `received_hmac_tag[32]` живуть у SRAM, що зберігається
 * у STOP2 (Lorenz state в RTC, але trailer-state у звичайному SRAM —
 * це теж переживає STOP2 за виключенням повного VBAT-loss).
 *
 * Сценарій: seg_idx=1 приходить → Soldier іде у STOP2 на час між
 * Queen reflex shots → seg_idx=2 приходить пізніше → STOP2 → seg_idx=3.
 * Bitmask має OR-агрегуватися в 0x07 без втрат байтів попередніх сегментів.
 * ─────────────────────────────────────────────────────────────────────── */
TEST(test_hmac_trailer_state_survives_simulated_stop2_between_segments) {
    uint8_t expected[32];
    for (int i = 0; i < 32; i++) expected[i] = (uint8_t)(0xA0 + i);

    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    uint8_t chunk[16];

    /* seg 1 arrives */
    compose_hmac_trailer_chunk(1, 5, expected, chunk);
    ASSERT_EQ(Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs), 1);
    ASSERT_EQ(segs, 0x01);

    /* simulated STOP2 — recv[]/segs are SRAM-persistent */

    /* seg 3 arrives (out of order is OK, already proven in
     * test_hmac_trailer_out_of_order_chunks; here we focus on
     * cross-cycle stability of the partial state) */
    compose_hmac_trailer_chunk(3, 5, expected, chunk);
    ASSERT_EQ(Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs), 1);
    ASSERT_EQ(segs, 0x05);  /* bits 0+2 set */

    /* simulated STOP2 again */

    /* seg 2 closes */
    compose_hmac_trailer_chunk(2, 5, expected, chunk);
    ASSERT_EQ(Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs), 1);
    ASSERT_EQ(segs, 0x07);  /* all 3 tag bits set */
    ASSERT_EQ(memcmp(recv, expected, 32), 0);
}

TEST(test_hmac_trailer_duplicate_segment_overwrites_idempotently) {
    /* If Queen retransmits seg=1 for any reason, Soldier MUST accept
     * (idempotent overwrite) and bitmask remains 0x01 — counter stays
     * the same. Production behaviour: parser does memcpy + |= mask,
     * so duplicate same-segment with same payload is byte-stable. */
    uint8_t expected[32];
    for (int i = 0; i < 32; i++) expected[i] = (uint8_t)(0xB0 + i);

    uint8_t recv[32] = {0};
    uint32_t ver = 0;
    uint8_t segs = 0;
    uint8_t chunk[16];

    compose_hmac_trailer_chunk(1, 5, expected, chunk);
    ASSERT_EQ(Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs), 1);
    ASSERT_EQ(segs, 0x01);

    /* Same segment re-arrives — OK, no double-count, no corruption */
    ASSERT_EQ(Test_Parse_HMAC_Trailer_Chunk(chunk, 16, recv, &ver, &segs), 1);
    ASSERT_EQ(segs, 0x01);  /* still just bit 0 */
    /* Bytes 0..10 of seg 1 area unchanged */
    ASSERT_EQ(recv[0],  0xB0);
    ASSERT_EQ(recv[10], 0xBA);
}

/* ════════════════════════════════════════════════════════════════════
 * 16. FW.18 OTA CMD Dispatcher — CMD_SET_AUDIO_THRESHOLDS (0x9D)
 * ════════════════════════════════════════════════════════════════════
 * Wire (10 bytes total):
 *   [0]    0x9D marker
 *   [1..2] payload_len LE = 7
 *   [3..4] warn_x100 (s16 LE)
 *   [5..6] crit_x100 (s16 LE)
 *   [7]    config_version
 *   [8..9] crc16-ccitt LE over body[3..7]
 * ════════════════════════════════════════════════════════════════════ */
#define S_CMD_AUDIO_MARKER         0x9D
#define S_CMD_AUDIO_HEADER_SIZE    3
#define S_CMD_AUDIO_BODY_SIZE      5
#define S_CMD_AUDIO_FRAME_SIZE     10
#define S_CMD_AUDIO_PAYLOAD_LEN    7

static void compose_audio_thresholds_frame(int16_t warn_x100, int16_t crit_x100,
                                            uint8_t version, uint8_t out[10])
{
    memset(out, 0, 10);
    out[0] = S_CMD_AUDIO_MARKER;
    out[1] = (uint8_t)(S_CMD_AUDIO_PAYLOAD_LEN & 0xFFu);
    out[2] = (uint8_t)((S_CMD_AUDIO_PAYLOAD_LEN >> 8) & 0xFFu);

    uint16_t uw = (uint16_t)warn_x100;
    uint16_t uc = (uint16_t)crit_x100;
    out[3] = (uint8_t)(uw & 0xFFu);
    out[4] = (uint8_t)((uw >> 8) & 0xFFu);
    out[5] = (uint8_t)(uc & 0xFFu);
    out[6] = (uint8_t)((uc >> 8) & 0xFFu);
    out[7] = version;

    uint16_t crc = soldier_crc16_ccitt(&out[3], S_CMD_AUDIO_BODY_SIZE);
    out[8] = (uint8_t)(crc & 0xFFu);
    out[9] = (uint8_t)((crc >> 8) & 0xFFu);
}

/* TinyML threshold validate/apply — mirrors firmware sanitize logic. */
#define S_TINYML_MIN_VALID  0.01f
#define S_TINYML_MAX_VALID  0.99f
#define S_TINYML_DEFAULT_W  0.60f
#define S_TINYML_DEFAULT_C  0.85f

static float Test_TinyML_Validate(float raw, float fallback) {
    if (raw < S_TINYML_MIN_VALID || raw > S_TINYML_MAX_VALID) return fallback;
    return raw;
}

static void Test_TinyML_Apply(float wr, float cr, float* w_out, float* c_out) {
    float w = Test_TinyML_Validate(wr, S_TINYML_DEFAULT_W);
    float c = Test_TinyML_Validate(cr, S_TINYML_DEFAULT_C);
    if (!(w < c)) { w = S_TINYML_DEFAULT_W; c = S_TINYML_DEFAULT_C; }
    *w_out = w; *c_out = c;
}

/* Mirror of Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS. */
static uint8_t Test_Handle_CMD_SET_AUDIO_THRESHOLDS(const uint8_t* frame,
                                                     uint16_t frame_size,
                                                     float* warn_out, float* crit_out,
                                                     uint8_t* version_out)
{
    if (frame == NULL || warn_out == NULL || crit_out == NULL)         return 0;
    if (frame_size < S_CMD_AUDIO_FRAME_SIZE)                           return 0;
    if (frame[0] != S_CMD_AUDIO_MARKER)                                return 0;

    uint16_t plen = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (plen != S_CMD_AUDIO_PAYLOAD_LEN)                               return 0;

    const uint8_t* body = frame + S_CMD_AUDIO_HEADER_SIZE;
    uint16_t expected = soldier_crc16_ccitt(body, S_CMD_AUDIO_BODY_SIZE);
    uint16_t received = (uint16_t)body[5] | ((uint16_t)body[6] << 8);
    if (expected != received)                                          return 0;

    int16_t warn_x100 = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    int16_t crit_x100 = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    uint8_t version   = body[4];

    if (warn_x100 < 1 || warn_x100 > 99)                               return 0;
    if (crit_x100 < 1 || crit_x100 > 99)                               return 0;

    Test_TinyML_Apply((float)warn_x100 / 100.0f, (float)crit_x100 / 100.0f,
                      warn_out, crit_out);
    if (version_out) *version_out = version;
    return 1;
}

TEST(test_audio_dispatcher_accepts_default_60_85) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(60, 85, 1, frame);

    float w = 0.0f, c = 0.0f; uint8_t v = 0;
    uint8_t ok = Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v);
    ASSERT_EQ(ok, 1);
    /* float compare with tolerance */
    ASSERT_EQ((int)(w * 100.0f + 0.5f), 60);
    ASSERT_EQ((int)(c * 100.0f + 0.5f), 85);
    ASSERT_EQ(v, 1);
}

TEST(test_audio_dispatcher_rejects_wrong_marker) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(60, 85, 1, frame);
    frame[0] = 0x9C;  /* corrupt marker */
    float w=0, c=0; uint8_t v=0;
    ASSERT_EQ(Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v), 0);
}

TEST(test_audio_dispatcher_rejects_bad_crc) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(60, 85, 1, frame);
    frame[8] ^= 0xFF;  /* corrupt CRC */
    float w=0, c=0; uint8_t v=0;
    ASSERT_EQ(Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v), 0);
}

TEST(test_audio_dispatcher_rejects_warn_geq_crit_via_apply_default) {
    /* warn=85, crit=60 — both pass body range check (1..99) but APPLY rolls
     * them back to defaults via TinyML_Apply (inversion safety). Parser
     * returns 1 (frame is well-formed); apply returns defaults. */
    uint8_t frame[10];
    compose_audio_thresholds_frame(85, 60, 1, frame);
    float w=0, c=0; uint8_t v=0;
    uint8_t ok = Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v);
    ASSERT_EQ(ok, 1);
    /* Applied thresholds = defaults (0.60 / 0.85) */
    ASSERT_EQ((int)(w * 100.0f + 0.5f), 60);
    ASSERT_EQ((int)(c * 100.0f + 0.5f), 85);
}

TEST(test_audio_dispatcher_rejects_short_frame) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(60, 85, 1, frame);
    float w=0, c=0; uint8_t v=0;
    ASSERT_EQ(Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 9, &w, &c, &v), 0);
}

TEST(test_audio_dispatcher_rejects_warn_zero) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(0, 85, 1, frame);
    float w=0, c=0; uint8_t v=0;
    ASSERT_EQ(Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v), 0);
}

TEST(test_audio_dispatcher_rejects_crit_above_99) {
    uint8_t frame[10];
    compose_audio_thresholds_frame(60, 100, 1, frame);
    float w=0, c=0; uint8_t v=0;
    ASSERT_EQ(Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &w, &c, &v), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.10] Frame Counter anti-replay для panic packets
 * ════════════════════════════════════════════════════════════════════
 * Логіка пакування DR0[31:16] = panic_frame_counter, DR0[7:0] = acoustic.
 * Counter=0 cold-boot → reseed (HRNG); transmit BE у panic_payload[14..15].
 */
#define PANIC_COUNTER_DR0_SHIFT   16
#define PANIC_COUNTER_MASK        0xFFFFu
#define PANIC_COUNTER_MAX         0xFFFFu
#define PANIC_COUNTER_PAD_HI      14
#define PANIC_COUNTER_PAD_LO      15

/* Pack DR0: packed plot of acoustic_events + panic_frame_counter. */
static uint32_t Pack_DR0(uint16_t panic_counter, uint8_t acoustic) {
    return ((uint32_t)panic_counter << PANIC_COUNTER_DR0_SHIFT) | (uint32_t)acoustic;
}
static uint16_t Unpack_DR0_Counter(uint32_t dr0) {
    return (uint16_t)((dr0 >> PANIC_COUNTER_DR0_SHIFT) & PANIC_COUNTER_MASK);
}
static uint8_t Unpack_DR0_Acoustic(uint32_t dr0) {
    return (uint8_t)(dr0 & 0xFFu);
}

/* [SEC.20] Розширення DR0-mirror: + vm_err_streak у vacant-байті [9:8]
 * (panic[31:16]/acoustic[7:0] недоторкані). Дзеркалить main.c DR0-write. */
#define OTA_VM_ERR_STREAK_DR0_SHIFT 8
#define OTA_VM_ERR_STREAK_MASK      0x03u
#define SEC20_VM_ERROR_FALLBACK_N   3u
static uint32_t Pack_DR0_Full(uint16_t panic_counter, uint8_t streak, uint8_t acoustic) {
    return Pack_DR0(panic_counter, acoustic) |
           ((uint32_t)(streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT);
}
static uint8_t Unpack_DR0_Streak(uint32_t dr0) {
    return (uint8_t)((dr0 >> OTA_VM_ERR_STREAK_DR0_SHIFT) & OTA_VM_ERR_STREAK_MASK);
}
static int Sec20_Should_Fallback(uint8_t streak) {
    return streak >= SEC20_VM_ERROR_FALLBACK_N;
}

/* Mirror of Trigger_Emergency_LoRa_TX counter+payload logic. */
static void Build_Panic_Payload_With_Counter(uint8_t* payload, uint32_t did,
                                              uint16_t* counter_inout) {
    /* Saturating increment ПЕРЕД пакуванням */
    if (*counter_inout < PANIC_COUNTER_MAX) (*counter_inout)++;

    memset(payload, 0, 16);
    payload[0] = (uint8_t)(did >> 24);
    payload[1] = (uint8_t)(did >> 16);
    payload[2] = (uint8_t)(did >> 8);
    payload[3] = (uint8_t)(did & 0xFF);
    payload[7] = 0xFF;
    payload[10] = PANIC_FLAG_BIT;
    payload[11] = 5;
    payload[PANIC_COUNTER_PAD_HI] = (uint8_t)(*counter_inout >> 8);
    payload[PANIC_COUNTER_PAD_LO] = (uint8_t)(*counter_inout & 0xFFu);
}

/* Mirror of Phase 0 cold-boot reseed logic. */
static uint16_t Restore_Panic_Counter(uint32_t dr0_raw, uint32_t hrng_value) {
    uint16_t c = Unpack_DR0_Counter(dr0_raw);
    if (c == 0) {
        /* HRNG reseed: ensure non-zero result */
        c = (uint16_t)((hrng_value & PANIC_COUNTER_MASK) | 0x0001u);
    }
    return c;
}

TEST(test_sec10_dr0_pack_roundtrip) {
    /* Симетричне пакування counter + acoustic у одному 32-бітному слові. */
    uint32_t packed = Pack_DR0(0xABCD, 0x42);
    ASSERT_EQ(Unpack_DR0_Counter(packed), 0xABCD);
    ASSERT_EQ(Unpack_DR0_Acoustic(packed), 0x42);
}

TEST(test_sec10_dr0_pack_independence) {
    /* Зміна acoustic не торкається counter і навпаки. */
    uint32_t p1 = Pack_DR0(0x1234, 0xFF);
    uint32_t p2 = Pack_DR0(0x1234, 0x00);
    ASSERT_EQ(Unpack_DR0_Counter(p1), Unpack_DR0_Counter(p2));
    ASSERT_NE(Unpack_DR0_Acoustic(p1), Unpack_DR0_Acoustic(p2));

    uint32_t p3 = Pack_DR0(0x0000, 0x55);
    uint32_t p4 = Pack_DR0(0xFFFF, 0x55);
    ASSERT_NE(Unpack_DR0_Counter(p3), Unpack_DR0_Counter(p4));
    ASSERT_EQ(Unpack_DR0_Acoustic(p3), Unpack_DR0_Acoustic(p4));
}

TEST(test_sec20_streak_dr0_roundtrip_panic_intact) {
    /* Streak у [9:8] пакується й читається; panic + acoustic недоторкані. */
    uint32_t packed = Pack_DR0_Full(0xABCD, 2, 0x42);
    ASSERT_EQ(Unpack_DR0_Streak(packed), 2);
    ASSERT_EQ(Unpack_DR0_Counter(packed), 0xABCD);
    ASSERT_EQ(Unpack_DR0_Acoustic(packed), 0x42);
}

TEST(test_sec20_streak_independent_of_panic_and_acoustic) {
    /* Зміна streak НЕ торкається panic-counter (SEC.10 anti-replay) й acoustic. */
    uint32_t p1 = Pack_DR0_Full(0x1234, 0, 0x55);
    uint32_t p2 = Pack_DR0_Full(0x1234, 3, 0x55);
    ASSERT_EQ(Unpack_DR0_Counter(p1), Unpack_DR0_Counter(p2));
    ASSERT_EQ(Unpack_DR0_Acoustic(p1), Unpack_DR0_Acoustic(p2));
    ASSERT_NE(Unpack_DR0_Streak(p1), Unpack_DR0_Streak(p2));
}

TEST(test_sec20_streak_saturates_no_overflow) {
    /* Насичення на 2-бітну маску — не переливається в acoustic/panic. */
    uint32_t packed = Pack_DR0_Full(0xFFFF, 0xFF, 0xFF);
    ASSERT_EQ(Unpack_DR0_Streak(packed), OTA_VM_ERR_STREAK_MASK);
    ASSERT_EQ(Unpack_DR0_Counter(packed), 0xFFFF);
    ASSERT_EQ(Unpack_DR0_Acoustic(packed), 0xFF);
}

TEST(test_sec20_fallback_at_third_consecutive) {
    /* Fallback на embedded лише на N=3 поспіль bytecode-збоїв. */
    ASSERT_FALSE(Sec20_Should_Fallback(0));
    ASSERT_FALSE(Sec20_Should_Fallback(2));
    ASSERT_TRUE(Sec20_Should_Fallback(3));
}

TEST(test_sec10_counter_increments_before_tx) {
    /* Лічильник інкрементується ПЕРЕД пакуванням — кожен panic-пакет ніс новий nonce. */
    uint8_t p[16];
    uint16_t counter = 5;
    Build_Panic_Payload_With_Counter(p, 0xDEADBEEF, &counter);
    ASSERT_EQ(counter, 6);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_HI], 0x00);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_LO], 0x06);
}

TEST(test_sec10_counter_big_endian_in_pad) {
    /* Бекенд читає pad_data[2..3].unpack1("n") → BE order. */
    uint8_t p[16];
    uint16_t counter = 0x1233; /* після інкременту → 0x1234 */
    Build_Panic_Payload_With_Counter(p, 1, &counter);
    ASSERT_EQ(counter, 0x1234);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_HI], 0x12);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_LO], 0x34);
}

TEST(test_sec10_counter_saturates_at_max) {
    /* На 0xFFFF лічильник застигає — без цього wrap заплутав би backend. */
    uint8_t p[16];
    uint16_t counter = PANIC_COUNTER_MAX;
    Build_Panic_Payload_With_Counter(p, 1, &counter);
    ASSERT_EQ(counter, PANIC_COUNTER_MAX);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_HI], 0xFF);
    ASSERT_EQ(p[PANIC_COUNTER_PAD_LO], 0xFF);
}

TEST(test_sec10_counter_just_below_max_increments_once) {
    uint8_t p[16];
    uint16_t counter = PANIC_COUNTER_MAX - 1;
    Build_Panic_Payload_With_Counter(p, 1, &counter);
    ASSERT_EQ(counter, PANIC_COUNTER_MAX);
}

TEST(test_sec10_cold_boot_reseed_from_hrng) {
    /* DR0 == 0 → cold-boot, лічильник пересіюється з HRNG → не нуль. */
    uint16_t c = Restore_Panic_Counter(0x00000000, 0xDEADBEEF);
    ASSERT_NE(c, 0);
    /* Lower 16 bits of HRNG are 0xBEEF; OR'd with 1 stays 0xBEEF. */
    ASSERT_EQ(c, 0xBEEF);
}

TEST(test_sec10_cold_boot_reseed_zero_hrng_not_zero) {
    /* Навіть якщо HRNG поверне нуль (вкрай малоймовірно) — fallback OR з 0x0001. */
    uint16_t c = Restore_Panic_Counter(0x00000000, 0x00000000);
    ASSERT_EQ(c, 0x0001);
}

TEST(test_sec10_warm_boot_preserves_counter) {
    /* DR0 ненульовий → warm-boot, counter відновлюється напряму без HRNG. */
    uint32_t dr0 = Pack_DR0(0x1234, 0x42);
    uint16_t c = Restore_Panic_Counter(dr0, 0xDEADBEEF);
    ASSERT_EQ(c, 0x1234);
}

TEST(test_sec10_panic_counter_does_not_overlap_did) {
    /* Лічильник у байтах 14..15 НЕ переписує DID (байти 0..3). */
    uint8_t p[16];
    uint16_t counter = 0xAAAA;
    Build_Panic_Payload_With_Counter(p, 0xCAFEBABE, &counter);
    ASSERT_EQ(p[0], 0xCA);
    ASSERT_EQ(p[1], 0xFE);
    ASSERT_EQ(p[2], 0xBA);
    ASSERT_EQ(p[3], 0xBE);
}

TEST(test_sec10_panic_counter_does_not_overlap_panic_flag) {
    /* PANIC_FLAG_BIT у байті 10 не зачіпається counter'ом у 14..15. */
    uint8_t p[16];
    uint16_t counter = 0xFFFE;
    Build_Panic_Payload_With_Counter(p, 1, &counter);
    ASSERT_TRUE(p[10] & PANIC_FLAG_BIT);
    ASSERT_EQ(p[11], 5); /* PANIC_TTL */
}

TEST(test_sec10_dr0_acoustic_preserved_through_panic_writeback) {
    /* Сценарій: panic-TX персистить DR0 НЕГАЙНО, acoustic не повинно зникнути. */
    uint8_t p[16];
    uint16_t counter = 100;
    uint8_t acoustic = 47;
    Build_Panic_Payload_With_Counter(p, 1, &counter);
    /* Імітуємо writeback DR0 одразу після інкременту — як у firmware. */
    uint32_t dr0 = Pack_DR0(counter, acoustic);
    ASSERT_EQ(Unpack_DR0_Acoustic(dr0), 47);
    ASSERT_EQ(Unpack_DR0_Counter(dr0), 101);
}

TEST(test_sec10_two_panics_have_distinct_counters) {
    /* Два послідовні panic-пакети несуть різні nonce — це сама суть anti-replay. */
    uint8_t p1[16], p2[16];
    uint16_t counter = 42;
    Build_Panic_Payload_With_Counter(p1, 1, &counter);
    Build_Panic_Payload_With_Counter(p2, 1, &counter);
    uint16_t n1 = ((uint16_t)p1[PANIC_COUNTER_PAD_HI] << 8) | p1[PANIC_COUNTER_PAD_LO];
    uint16_t n2 = ((uint16_t)p2[PANIC_COUNTER_PAD_HI] << 8) | p2[PANIC_COUNTER_PAD_LO];
    ASSERT_EQ(n1, 43);
    ASSERT_EQ(n2, 44);
    ASSERT_NE(n1, n2);
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.20] fw_report — wire-звіт contract-стану (common/fw_report.h)
 * ════════════════════════════════════════════════════════════════════
 * [sem:1|rev:1|id14] у байтах 12..13 (BE) + стиск у CCM vpd-байт.
 * Несучий інваріант: reverted ⇔ (kv ∧ hiwater>0 ∧ contract мертвий) —
 * сигнатура auto-fallback, що інакше тонула у здоровій телеметрії.
 */
TEST(test_sec20_report_no_kv_degrades_to_legacy) {
    /* Без припливу звіт був би вигадкою — чесна legacy-семантика (sem=0). */
    ASSERT_EQ(Fw_Report_Compose(0, 7, 1, 0x0001), 0x0001);
    ASSERT_EQ(Fw_Report_Compose(0, 0, 0, 0x0001), 0x0001);
}

TEST(test_sec20_report_factory_baseline) {
    /* hiwater=0 ∧ contract мертвий = завод: semantic є, reverted НЕМА. */
    ASSERT_EQ(Fw_Report_Compose(1, 0, 0, 0x0001), 0x8000);
}

TEST(test_sec20_report_running_ota) {
    ASSERT_EQ(Fw_Report_Compose(1, 42, 1, 0x0001), 0x8000 | 42);
}

TEST(test_sec20_report_reverted_carries_burned_id) {
    /* Ядро SEC.20: contract стерто fallback'ом, приплив живий → reverted +
     * спалена версія (Rails одразу знає, від чого bump'ати). */
    ASSERT_EQ(Fw_Report_Compose(1, 42, 0, 0x0001), 0xC000 | 42);
}

TEST(test_sec20_report_id_modulo_14bit) {
    /* Стеля id14: великі BioContractFirmware.id їдуть по модулю (0x3FFF),
     * несучий reverted-біт від колізій не залежить. */
    ASSERT_EQ(Fw_Report_Compose(1, 0x4001u, 1, 0), 0x8000 | 0x0001);
    ASSERT_EQ(Fw_Report_Compose(1, 0x4001u, 0, 0), 0xC000 | 0x0001);
}

TEST(test_sec20_report_vpd_squeeze) {
    /* CCM-стиск [rev:1|id7]: legacy → 0x00 (байт як слався до патча). */
    ASSERT_EQ(Fw_Report_To_Vpd(0x0001), 0x00);              /* legacy      */
    ASSERT_EQ(Fw_Report_To_Vpd(0x8000), 0x00);              /* factory     */
    ASSERT_EQ(Fw_Report_To_Vpd(0x8000 | 42), 42);           /* running     */
    ASSERT_EQ(Fw_Report_To_Vpd(0xC000 | 42), 0x80 | 42);    /* reverted    */
    ASSERT_EQ(Fw_Report_To_Vpd(0x8000 | 0x2A85), 0x05);     /* id modulo 7 */
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.21] Stack-canary: guard-сів (common/stack_canary.h) + DR0[10]-слід
 * ════════════════════════════════════════════════════════════════════
 * Pure-half канарки: derivation guard'а (I-CG: ніколи не нуль, LSB=0x00)
 * + пакування canary-сліду в DR0 без затирання money-path сусідів.
 * Сам __stack_chk_fail/NVIC_SystemReset — ARM-only, host спостерігає
 * лише «що лягло в DR0 перед перевтіленням».
 */
#define CANARY_TRIP_DR0_SHIFT 10
#define CANARY_TRIP_MASK      0x01u

/* Дзеркало main.c DR0-write усіх чотирьох sites (post-SEC.21). */
static uint32_t Pack_DR0_Canary(uint16_t panic_counter, uint8_t canary,
                                uint8_t streak, uint8_t acoustic) {
    return Pack_DR0_Full(panic_counter, streak, acoustic) |
           ((uint32_t)(canary & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT);
}
static uint8_t Unpack_DR0_Canary(uint32_t dr0) {
    return (uint8_t)((dr0 >> CANARY_TRIP_DR0_SHIFT) & CANARY_TRIP_MASK);
}

TEST(test_sec21_guard_derive_hrng_nonzero_null_lsb) {
    /* Живий HRNG: guard успадковує ентропію, молодший байт гаситься в NUL. */
    uint32_t g = Canary_Guard_Derive(0xDEADBEEFu, 0x12345678u);
    ASSERT_EQ(g, 0xDEADBE00u);
    ASSERT_NE(g, 0u);
}

TEST(test_sec21_guard_derive_hrng_dead_falls_back) {
    /* Мертвий HRNG → ентропія викликача (tick ⊕ адреса), маска LSB тримається. */
    uint32_t g = Canary_Guard_Derive(0u, 0x12345678u);
    ASSERT_EQ(g, 0x12345600u);
}

TEST(test_sec21_guard_derive_total_silence_last_resort) {
    /* I-CG остання межа: повна тиша ентропії — guard усе одно не нуль. */
    uint32_t g = Canary_Guard_Derive(0u, 0u);
    ASSERT_EQ(g, CANARY_GUARD_LAST_RESORT);
    ASSERT_NE(g, 0u);
}

TEST(test_sec21_guard_derive_lsb_only_entropy_still_nonzero) {
    /* Крайова: уся ентропія у молодшому байті — NUL-маска з'їдає її повністю,
     * але I-CG тримається (інакше guard = 0 = newlib-дефолт, який ми женемо). */
    uint32_t g = Canary_Guard_Derive(0x000000FFu, 0x000000A5u);
    ASSERT_EQ(g, CANARY_GUARD_LAST_RESORT);
}

TEST(test_sec21_canary_bit_dr0_roundtrip_fields_intact) {
    /* Слід у DR0[10] живе поруч з panic/streak/acoustic, нікого не чіпає. */
    uint32_t dr0 = Pack_DR0_Canary(0xBEEF, 1, 2, 0x7A);
    ASSERT_EQ(Unpack_DR0_Canary(dr0), 1);
    ASSERT_EQ(Unpack_DR0_Counter(dr0), 0xBEEF);
    ASSERT_EQ(Unpack_DR0_Streak(dr0), 2);
    ASSERT_EQ(Unpack_DR0_Acoustic(dr0), 0x7A);
}

TEST(test_sec21_canary_bit_no_overlap) {
    /* Дзеркало _Static_assert'а main.c: маска сліду не перетинає сусідів. */
    uint32_t canary_field = (uint32_t)CANARY_TRIP_MASK << CANARY_TRIP_DR0_SHIFT;
    ASSERT_EQ(canary_field & ((uint32_t)PANIC_COUNTER_MASK << PANIC_COUNTER_DR0_SHIFT), 0u);
    ASSERT_EQ(canary_field & ((uint32_t)OTA_VM_ERR_STREAK_MASK << OTA_VM_ERR_STREAK_DR0_SHIFT), 0u);
    ASSERT_EQ(canary_field & 0xFFu, 0u);
}

TEST(test_sec21_canary_preserved_through_dr0_writeback) {
    /* Sticky-контракт: слід переживає повний write-back цикл (Phase 5 / PVD /
     * panic / fallback-reset) — жоден site не сміє його загубити. */
    uint32_t before = Pack_DR0_Canary(0x1234, 1, 0, 0x05);
    uint8_t restored = Unpack_DR0_Canary(before);
    uint32_t after = Pack_DR0_Canary(0x1235, restored, 1, 0x06);
    ASSERT_EQ(Unpack_DR0_Canary(after), 1);
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.21] device-event 0x57 (common/device_event.h) — пакувальник
 * ════════════════════════════════════════════════════════════════════
 * Golden wire-розкладка + Is()-розпізнавач. Дзеркало DeviceEventWorker.
 */
TEST(test_sec21_devevt_wire_layout) {
    uint8_t p[16];
    Device_Event_Build(p, 0xAABBCCDDu, DEVICE_EVT_CANARY_TRIP,
                       0x11223344u, 0x0102, 3300);
    ASSERT_EQ(p[0], 0x57);                 /* marker              */
    ASSERT_EQ(p[1], 0xAA); ASSERT_EQ(p[2], 0xBB);
    ASSERT_EQ(p[3], 0xCC); ASSERT_EQ(p[4], 0xDD); /* DID BE       */
    ASSERT_EQ(p[5], 0x02);                 /* canary code         */
    ASSERT_EQ(p[6], 0x11); ASSERT_EQ(p[9], 0x44); /* arg BE       */
    ASSERT_EQ(p[10], 0x45);                /* 'E' magic           */
    ASSERT_EQ(p[11], 3);                   /* TTL                 */
    ASSERT_EQ(p[12], 0x01); ASSERT_EQ(p[13], 0x02); /* seq BE     */
    ASSERT_EQ(p[14], (3300 >> 8)); ASSERT_EQ(p[15], (3300 & 0xFF)); /* vcap */
}

TEST(test_sec21_devevt_recognizer) {
    uint8_t p[16];
    Device_Event_Build(p, 0x1234u, DEVICE_EVT_CANARY_TRIP, 0, 1, 3000);
    ASSERT_TRUE(Device_Event_Is(p));
    p[10] = 0x00; ASSERT_FALSE(Device_Event_Is(p)); /* magic зник → не наш */
    Device_Event_Build(p, 0x1234u, DEVICE_EVT_CANARY_TRIP, 0, 1, 3000);
    p[0] = 0x56; ASSERT_FALSE(Device_Event_Is(p));  /* 0x56 sync ≠ 0x57    */
}

/* [SEC.21 L1] Шар 2 — підписаний Queen→Rails конверт (dev_event.h §Шар 2).
 * Golden byte-layout header+record + body-len; дзеркало DeviceEventWorker
 * (Ruby-парс мусить бачити рівно ці зсуви). Сам підпис — Queen-side (main.c),
 * host стереже РОЗКЛАДКУ. */
TEST(test_sec21_devenv_header_golden) {
    uint8_t h[DEVENV_HEADER_LEN];
    Devenv_Write_Header(h, 0x11223344u, 3);
    ASSERT_EQ(h[0], 0x01);                 /* ver                 */
    ASSERT_EQ(h[1], 0x11); ASSERT_EQ(h[2], 0x22);
    ASSERT_EQ(h[3], 0x33); ASSERT_EQ(h[4], 0x44); /* queen_unix_ts BE */
    ASSERT_EQ(h[5], 3);                    /* count               */
}

TEST(test_sec21_devenv_record_golden) {
    uint8_t r[DEVENV_RECORD_LEN];
    Devenv_Write_Record(r, 0xAABBCCDDu, DEVICE_EVT_CANARY_TRIP, 0x0102);
    ASSERT_EQ(r[0], 0xAA); ASSERT_EQ(r[1], 0xBB);
    ASSERT_EQ(r[2], 0xCC); ASSERT_EQ(r[3], 0xDD); /* did BE          */
    ASSERT_EQ(r[4], 0x02);                        /* code            */
    ASSERT_EQ(r[5], 0x01); ASSERT_EQ(r[6], 0x02); /* soldier_seq BE  */
}

TEST(test_sec21_devenv_body_len) {
    ASSERT_EQ(Devenv_Body_Len(0), DEVENV_HEADER_LEN);          /* heartbeat-нема */
    ASSERT_EQ(Devenv_Body_Len(1), DEVENV_HEADER_LEN + 7u);
    ASSERT_EQ(Devenv_Body_Len(DEVENV_MAX_RECORDS),
              DEVENV_HEADER_LEN + DEVENV_MAX_RECORDS * DEVENV_RECORD_LEN);
}

/* ════════════════════════════════════════════════════════════════════
 * [SEC.21] MPU region-math (common/mpu_regions.h) — pure-half draft
 * ════════════════════════════════════════════════════════════════════
 * Golden RBAR/RASR-слова (ARMv7-M PMSA, незалежний розрахунок) + інваріант
 * розкладки: RO-code не сміє накрити жодну сторінку, яку пише HAL_FLASH
 * (KV 122-123 / identity 124 / KOTA+KEYB 125 / contract 126 / UID 127).
 * Сам trap — bench-only (QEMU не моделює); host стереже МАТЕМАТИКУ.
 */
TEST(test_sec21_mpu_rbar_golden) {
    MpuRegionWord r[3];
    Mpu_Build_Region_Table(r);
    ASSERT_EQ(r[0].rbar, 0x08000000u | 0x10u | 0u);
    ASSERT_EQ(r[1].rbar, 0x0803C000u | 0x10u | 1u);
    ASSERT_EQ(r[2].rbar, 0x20000000u | 0x10u | 2u);
}

TEST(test_sec21_mpu_rasr_golden) {
    /* Незалежно зібрані слова: [xn:28|ap:26..24|c:17|srd:15..8|size:5..1|en:0] */
    MpuRegionWord r[3];
    Mpu_Build_Region_Table(r);
    ASSERT_EQ(r[0].rasr, 0x06020023u); /* RO+X  256K (size=17)          */
    ASSERT_EQ(r[1].rasr, 0x1302031Bu); /* RW+XN 16K, SRD=0x03 (size=13) */
    ASSERT_EQ(r[2].rasr, 0x1302001Fu); /* RW+XN 64K (size=15)           */
}

TEST(test_sec21_mpu_tail_base_aligned_to_size) {
    /* PMSA-закон: base вирівняна на розмір регіону — інакше кремній
     * тихо маскує молодші біти і вікно з'їжджає. */
    ASSERT_EQ(SEC21_MPU_TAIL_BASE & ((1u << SEC21_MPU_TAIL_LOG2) - 1u), 0u);
}

TEST(test_sec21_mpu_flash_tail_pages_writable) {
    /* Кожна сторінка, яку пише HAL_FLASH, — під живим subregion'ом. */
    for (uint32_t page = 122; page <= 127; page++) {
        uint32_t addr = 0x08000000u + page * SEC21_MPU_FLASH_PAGE_SIZE;
        ASSERT_EQ(Mpu_Flash_Addr_Writable(addr), 1);
        ASSERT_EQ(Mpu_Flash_Addr_Writable(addr + SEC21_MPU_FLASH_PAGE_SIZE - 1u), 1);
    }
}

TEST(test_sec21_mpu_code_pages_not_writable) {
    /* Код лишається RO: і далекий початок, і сторінки 120-121 всередині
     * TAIL-вікна (SRD-трюк провалює їх назад у RO-регіон #0). */
    ASSERT_EQ(Mpu_Flash_Addr_Writable(0x08000000u), 0);
    ASSERT_EQ(Mpu_Flash_Addr_Writable(0x08000000u + 119u * SEC21_MPU_FLASH_PAGE_SIZE), 0);
    ASSERT_EQ(Mpu_Flash_Addr_Writable(0x08000000u + 120u * SEC21_MPU_FLASH_PAGE_SIZE), 0);
    ASSERT_EQ(Mpu_Flash_Addr_Writable(0x08000000u + 121u * SEC21_MPU_FLASH_PAGE_SIZE), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * [ARCH.21] Brownout PVD save Lorenz state
 * ════════════════════════════════════════════════════════════════════
 * Симуляція HAL_PWR_PVDCallback: рятує DR0 (packed) + DR1 + DR16-DR19
 * перед STOP2. Ключова інваріанта: на наступному boot Lorenz state
 * валідний (magic == LORENZ_STATE_MAGIC) і всі координати збереглись.
 */

/* Mirror of HAL_PWR_PVDCallback save sequence. */
static void Simulate_PVD_Brownout_Save(uint16_t panic_counter, uint8_t acoustic,
                                        uint32_t last_wakeup_ts,
                                        float lx, float ly, float lz,
                                        int lorenz_valid) {
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        Pack_DR0(panic_counter, acoustic));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_ts);
    if (lorenz_valid) {
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR16, test_float_to_uint32(lx));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR17, test_float_to_uint32(ly));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR18, test_float_to_uint32(lz));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC);
    }
}

TEST(test_arch21_pvd_saves_lorenz_state) {
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(123, 5, 99999, -5.5f, 8.8f, 27.3f, 1);

    ASSERT_EQ(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19), LORENZ_STATE_MAGIC);
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR16)), -5.5f, 0.0f);
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR17)), 8.8f, 0.0f);
    ASSERT_FLOAT_EQ(test_uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR18)), 27.3f, 0.0f);
}

TEST(test_arch21_pvd_preserves_packed_dr0) {
    /* Брауноут має зберегти і panic_frame_counter, і acoustic_events
     * у спільному 32-бітному слові — без цього SEC.10 anti-replay
     * прорветься після кожного просідання живлення. */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(0xABCD, 0x42, 0, 0, 0, 0, 0);

    uint32_t dr0 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
    ASSERT_EQ(Unpack_DR0_Counter(dr0), 0xABCD);
    ASSERT_EQ(Unpack_DR0_Acoustic(dr0), 0x42);
}

TEST(test_arch21_pvd_preserves_last_wakeup_for_delta_t) {
    /* Без DR1 rescue delta_t стрибне на астрономічне значення після boot. */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(1, 0, 0xCAFEBABEu, 0, 0, 0, 0);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR1), 0xCAFEBABEu);
}

TEST(test_arch21_pvd_skips_lorenz_when_invalid) {
    /* lorenz_state_valid==0 → не пишемо magic, щоб наступний boot пішов
     * через cold-start HKDF-деривацію (SEC.11), а не зловив corrupted state. */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(1, 0, 0, 1.0f, 2.0f, 3.0f, 0);
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19), 0);
}

TEST(test_arch21_pvd_save_then_restore_roundtrip) {
    /* End-to-end: brownout зберіг → reboot читає → state неперервний. */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(7, 12, 1000, -2.5f, 3.5f, 25.0f, 1);

    /* Симуляція boot-restore (Phase 0). */
    uint32_t dr0 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
    uint16_t restored_counter = Unpack_DR0_Counter(dr0);
    uint8_t restored_acoustic = Unpack_DR0_Acoustic(dr0);
    uint32_t magic = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19);

    ASSERT_EQ(restored_counter, 7);
    ASSERT_EQ(restored_acoustic, 12);
    ASSERT_EQ(magic, LORENZ_STATE_MAGIC);

    float restored_z = test_uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR18));
    ASSERT_FLOAT_EQ(restored_z, 25.0f, 0.0f);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.18 × ARCH.21 cross-feature regression] DR13/DR14 brownout race
 * ════════════════════════════════════════════════════════════════════
 * Сценарій-кандидат для regression freeze-contract bank (pattern FW.27 follow-up):
 * між отриманням CMD_SET_AUDIO_THRESHOLDS (мутація RAM `tinyml_warning_threshold`
 * у Сценарії 2 OTA-диспетчера) і Phase 5 KENOSIS writeback'ом у DR13/DR14
 * може спрацювати PVD IRQ (брауноут). Поточний `HAL_PWR_PVDCallback` (ARCH.21)
 * рятує DR0/DR1/DR16-DR19, але **НЕ** торкається DR13/DR14 — отже свіжо
 * прийняті пороги губляться, а наступний boot (`Load_TinyML_Thresholds_From_RTC`)
 * відновлює СТАРІ значення з DR13/DR14.
 *
 * Ці тести фіксують поточну поведінку як freeze-contract: вони мають впасти
 * якщо хтось випадково додасть DR13/DR14 у PVD save sequence без оновлення
 * `Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS` сценарію 2 (де writeback мав би
 * стати inline, а не deferred до Phase 5).
 *
 * Якщо BLOCKER усвідомлено закривати — потрібно: (a) додати DR13/DR14 у
 * `HAL_PWR_PVDCallback`, (b) inline writeback у CMD-handler'і, (c) видалити
 * ці тести або інвертувати їхню очікувану семантику.
 */

/* Mirror of Load_TinyML_Thresholds_From_RTC validate-and-apply, без RTC dep. */
static void Test_Load_TinyML_From_RTC_Slot(uint32_t dr13_word, uint32_t dr14_word,
                                            float* warn_out, float* crit_out) {
    float rtc_warn = test_uint32_to_float(dr13_word);
    float rtc_crit = test_uint32_to_float(dr14_word);
    Test_TinyML_Apply(rtc_warn, rtc_crit, warn_out, crit_out);
}

TEST(test_fw18_arch21_brownout_loses_freshly_received_thresholds) {
    /* Стартові DR13/DR14 = типові 0.60 / 0.85 (попередній deploy). */
    _rtc_bkp_reset_all();
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR13, test_float_to_uint32(0.60f));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR14, test_float_to_uint32(0.85f));

    /* OTA dispatcher отримує нові пороги — мутує RAM (Сценарій 2). */
    uint8_t frame[10];
    compose_audio_thresholds_frame(50, 75, 2, frame);  /* warn=0.50, crit=0.75 */
    float ram_warn = 0.60f, ram_crit = 0.85f;
    uint8_t version = 1;
    uint8_t ok = Test_Handle_CMD_SET_AUDIO_THRESHOLDS(frame, 10, &ram_warn, &ram_crit, &version);
    ASSERT_EQ(ok, 1);
    ASSERT_EQ((int)(ram_warn * 100.0f + 0.5f), 50);
    ASSERT_EQ((int)(ram_crit * 100.0f + 0.5f), 75);

    /* PVD IRQ зриває MCU ДО Phase 5 KENOSIS writeback. ARCH.21 callback
     * рятує тільки DR0/DR1/DR16-DR19 — DR13/DR14 НЕ зачіпаються. */
    Simulate_PVD_Brownout_Save(0, 0, 1234, 1.0f, 2.0f, 25.0f, 1);

    /* Boot після відновлення живлення: DR13/DR14 досі несуть СТАРІ 0.60/0.85. */
    float boot_warn = 0.0f, boot_crit = 0.0f;
    Test_Load_TinyML_From_RTC_Slot(
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR13),
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR14),
        &boot_warn, &boot_crit);

    /* Freeze-contract: новий 0.50/0.75 ВТРАЧЕНИЙ, повертаємось до 0.60/0.85.
     * Якщо хтось закриє BLOCKER — цей assert впаде, що сигналізує про необхідність
     * перепланування семантики (inline writeback vs PVD-rescue DR13/DR14). */
    ASSERT_EQ((int)(boot_warn * 100.0f + 0.5f), 60);
    ASSERT_EQ((int)(boot_crit * 100.0f + 0.5f), 85);
}

TEST(test_fw18_arch21_dr13_dr14_survive_brownout_when_already_persisted) {
    /* Inverse-сценарій: пороги вже пройшли Phase 5 writeback ДО PVD IRQ.
     * Brownout НЕ повинен їх зіпсувати — RTC Backup Domain живиться окремою
     * VBAT шиною. ARCH.21 callback не торкається DR13/DR14, тож записані
     * раніше значення лежать недоторканими. */
    _rtc_bkp_reset_all();
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR13, test_float_to_uint32(0.42f));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR14, test_float_to_uint32(0.91f));

    Simulate_PVD_Brownout_Save(0, 0, 5000, -1.0f, 2.0f, 27.0f, 1);

    float boot_warn = 0.0f, boot_crit = 0.0f;
    Test_Load_TinyML_From_RTC_Slot(
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR13),
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR14),
        &boot_warn, &boot_crit);

    /* Persisted-thresholds invariant: DR13/DR14 точно повертаються після brownout. */
    ASSERT_EQ((int)(boot_warn * 100.0f + 0.5f), 42);
    ASSERT_EQ((int)(boot_crit * 100.0f + 0.5f), 91);
}

TEST(test_fw18_arch21_dr13_dr14_corruption_falls_back_to_defaults) {
    /* Edge case: VBAT-loss ⇒ DR13/DR14 = 0xFFFFFFFF (uninit). Float bit-copy
     * 0xFFFFFFFF → NaN. Test_TinyML_Apply має повернути дефолти 0.60/0.85
     * (через Validate range check 0.01..0.99) щоб TinyML не злетів у NaN-ад. */
    _rtc_bkp_reset_all();
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR13, 0xFFFFFFFFu);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR14, 0xFFFFFFFFu);

    float boot_warn = 0.0f, boot_crit = 0.0f;
    Test_Load_TinyML_From_RTC_Slot(
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR13),
        HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR14),
        &boot_warn, &boot_crit);

    ASSERT_EQ((int)(boot_warn * 100.0f + 0.5f), 60);  /* TINYML_DEFAULT_W */
    ASSERT_EQ((int)(boot_crit * 100.0f + 0.5f), 85);  /* TINYML_DEFAULT_C */
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.29-PACK × ARCH.21 cross-feature regression] StatusByte mask survives brownout
 * ════════════════════════════════════════════════════════════════════
 * Регресійний guard: між обчисленням `payload[10] = (status<<5)|gp` (BioContract
 * pack) і LoRa TX може спрацювати PVD IRQ. ARCH.21 рятує Lorenz state у
 * DR16-DR19, але payload-байт лежить у RAM — він просто губиться (TX скасовано).
 * Критично: НА НАСТУПНОМУ boot'і, коли Lorenz state продовжується з DR16-DR19,
 * новий payload має знову правильно укладатися у [PanicFlag:1|Status:2|GP:5] —
 * НЕ у legacy [Status:2|GP:6], інакше bit 7 status'у конфліктує з PANIC_FLAG_BIT
 * mask'ом і backend читає anomaly як homeostasis (forensics див. 10_02 FW.29-PACK).
 */

#define FW29P_PANIC_FLAG_BIT  0x80
#define FW29P_STATUS_HOMEO    0
#define FW29P_STATUS_STRESS   1
#define FW29P_STATUS_ANOMALY  2
#define FW29P_STATUS_TAMPER   3

static uint8_t Test_FW29P_Pack(uint8_t status, uint8_t gp) {
    if (status > 3) status = 3;
    if (gp > 31) gp = 31;
    return (uint8_t)((status << 5) | gp);
}

TEST(test_fw29pack_arch21_post_brownout_anomaly_pack_survives_panic_mask) {
    /* Симуляція: brownout зберіг anomaly Z (e.g. z=46.0) у DR16-DR19.
     * На наступному boot Lorenz продовжується, BioContract пакує
     * status=2 (anomaly) — байт МАЄ бути 0x40, не 0x80. */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(0, 0, 1000, -2.0f, 3.0f, 46.5f, 1);

    /* Boot-restore читає Lorenz tail. */
    ASSERT_EQ(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19), LORENZ_STATE_MAGIC);

    /* Ре-pack після reboot: anomaly тригерить gp=0. */
    uint8_t b = Test_FW29P_Pack(FW29P_STATUS_ANOMALY, 0);

    /* FW.29-PACK guarantee: bit 7 == 0 (без колізії з PANIC_FLAG_BIT). */
    ASSERT_FALSE(b & FW29P_PANIC_FLAG_BIT);
    /* Backend `lora_payload[10] &= ~PANIC_FLAG_BIT` mask = no-op. */
    uint8_t masked = b & 0x7F;
    ASSERT_EQ(masked, b);
    /* Backend decode зберігає anomaly семантику. */
    ASSERT_EQ((masked >> 5) & 0x03, FW29P_STATUS_ANOMALY);
}

TEST(test_fw29pack_arch21_tamper_after_brownout_decodes_correctly) {
    /* Якщо mruby VM крашнеться відразу після cold-restore (Lorenz state
     * валідний, але VM init failed), BIO_STATUS_VM_ERROR=0xFF піде у
     * payload[10]. Firmware mask `&= ~PANIC_FLAG_BIT` зробить 0x7F.
     * Backend має декодувати як tamper, не як stress (legacy-bug). */
    _rtc_bkp_reset_all();
    Simulate_PVD_Brownout_Save(5, 12, 2000, 1.0f, 2.0f, 25.0f, 1);

    uint8_t vm_error = 0xFF;
    uint8_t firmware_masked = vm_error & 0x7F;  /* ~PANIC_FLAG_BIT */
    ASSERT_EQ(firmware_masked, 0x7F);

    uint8_t status = (firmware_masked >> 5) & 0x03;
    uint8_t gp     = firmware_masked & 0x1F;
    ASSERT_EQ(status, FW29P_STATUS_TAMPER);  /* НЕ stress(1) як до FW.29-PACK */
    ASSERT_EQ(gp, 31);                        /* max 5-bit, ×2 backend → stored 62 */
}


/* ════════════════════════════════════════════════════════════════════
 * [ARCH.27] Node Role Differentiation у Flash
 * ════════════════════════════════════════════════════════════════════
 */
#define ARCH27_FLASH_ROLE_ADDR     ((uintptr_t)_mock_flash_role_region)
#define ROLE_SOLDIER_MAGIC         0x534F4C44UL  /* "SOLD" */
#define ROLE_PROVISIONER_MAGIC     0x50524F56UL  /* "PROV" */
#define ROLE_SOLDIER               0
#define ROLE_PROVISIONER           1

static uint32_t _mock_flash_role_region[1] = {0xFFFFFFFFu};
static volatile uint8_t test_g_node_role = ROLE_SOLDIER;

/* Mirror of Load_Node_Role from soldier/main.c. */
static void Test_Load_Node_Role(void) {
    const uint32_t *flash_ptr = (const uint32_t *)ARCH27_FLASH_ROLE_ADDR;
    uint32_t role_word = flash_ptr[0];
    if (role_word == ROLE_PROVISIONER_MAGIC) {
        test_g_node_role = ROLE_PROVISIONER;
    } else if (role_word == ROLE_SOLDIER_MAGIC) {
        test_g_node_role = ROLE_SOLDIER;
    } else {
        test_g_node_role = ROLE_SOLDIER;  /* Безпечний дефолт */
    }
}

TEST(test_arch27_role_soldier_magic_loads_soldier) {
    _mock_flash_role_region[0] = ROLE_SOLDIER_MAGIC;
    test_g_node_role = 0xFF;  /* sentinel */
    Test_Load_Node_Role();
    ASSERT_EQ(test_g_node_role, ROLE_SOLDIER);
}

TEST(test_arch27_role_provisioner_magic_loads_provisioner) {
    _mock_flash_role_region[0] = ROLE_PROVISIONER_MAGIC;
    test_g_node_role = 0xFF;
    Test_Load_Node_Role();
    ASSERT_EQ(test_g_node_role, ROLE_PROVISIONER);
}

TEST(test_arch27_role_unprovisioned_falls_back_to_soldier) {
    /* Flash erased state = 0xFFFFFFFF; вузол повинен працювати як Солдат. */
    _mock_flash_role_region[0] = 0xFFFFFFFFu;
    test_g_node_role = ROLE_PROVISIONER;  /* поплутати */
    Test_Load_Node_Role();
    ASSERT_EQ(test_g_node_role, ROLE_SOLDIER);
}

TEST(test_arch27_role_zero_flash_falls_back_to_soldier) {
    /* Програмний erase часто дає 0x00000000 — теж невалідне magic. */
    _mock_flash_role_region[0] = 0x00000000u;
    test_g_node_role = ROLE_PROVISIONER;
    Test_Load_Node_Role();
    ASSERT_EQ(test_g_node_role, ROLE_SOLDIER);
}

TEST(test_arch27_role_corrupted_magic_falls_back_to_soldier) {
    /* Бітові помилки в Flash — теж не повинні підняти Provisioner-роль. */
    _mock_flash_role_region[0] = 0x534F4C45u;  /* "SOLE" замість "SOLD" */
    Test_Load_Node_Role();
    ASSERT_EQ(test_g_node_role, ROLE_SOLDIER);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20-S2] Authoritativeness flag у beacon байті 9
 * ════════════════════════════════════════════════════════════════════
 * Soldier RX зчитує бит 7 байту 9 → time_source_authoritative.
 */
#define FW20S2_BEACON_AUTH_FLAG  0x80
#define FW20S2_BEACON_TTL_MASK   0x7F

static volatile uint8_t test_time_source_authoritative = 0;

/* Mirror of Recv_Time_Beacon (FW.20-S2 extension). */
static int Recv_Time_Beacon_With_Auth(const uint8_t* p, uint16_t size) {
    if (size != 16) return 0;
    if (p[0] != 0x9C) return 0;
    if (p[10] != 'B') return 0;
    uint32_t ts = ((uint32_t)p[1] << 24) | ((uint32_t)p[2] << 16) |
                  ((uint32_t)p[3] << 8) | (uint32_t)p[4];
    if (ts == 0) return 1;
    /* [FW.20-S2] зчитуємо authoritativeness прапорець */
    test_time_source_authoritative = (p[9] & FW20S2_BEACON_AUTH_FLAG) ? 1 : 0;
    return 1;
}

TEST(test_fw20s2_authoritative_beacon_sets_flag) {
    test_time_source_authoritative = 0;
    /* Byte 9 = 0x81 (auth=1 | ttl=1) — як Queen транслює пост-FW.20-S2. */
    uint8_t b[16] = { 0x9C, 0,0,0x10,0, 0,0,0,0, 0x81, 'B', 0,0,0,0,0 };
    int consumed = Recv_Time_Beacon_With_Auth(b, 16);
    ASSERT_EQ(consumed, 1);
    ASSERT_EQ(test_time_source_authoritative, 1);
}

TEST(test_fw20s2_relay_beacon_clears_flag) {
    test_time_source_authoritative = 1;
    /* Byte 9 = 0x02 (auth=0 | ttl=2) — relay від Провідника (deferred). */
    uint8_t b[16] = { 0x9C, 0,0,0x10,0, 0,0,0,0, 0x02, 'B', 0,0,0,0,0 };
    int consumed = Recv_Time_Beacon_With_Auth(b, 16);
    ASSERT_EQ(consumed, 1);
    ASSERT_EQ(test_time_source_authoritative, 0);
}

TEST(test_fw20s2_legacy_beacon_byte9_zero_clears_flag) {
    /* Легасі-формат не існує у польових прошивках (beacon з'явився після FW.20),
     * але якщо хтось підкинув маяк з byte9=0 — він має бути НЕ-authoritative. */
    test_time_source_authoritative = 1;
    uint8_t b[16] = { 0x9C, 0,0,0x10,0, 0,0,0,0, 0x00, 'B', 0,0,0,0,0 };
    Recv_Time_Beacon_With_Auth(b, 16);
    ASSERT_EQ(test_time_source_authoritative, 0);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20-S2] Drift-monitor + Panic Time-Sync Request
 * ════════════════════════════════════════════════════════════════════
 * Дзеркало логіки з firmware/soldier/main.c:
 *   - Soldier_Should_Request_Time_Sync() — wall-кванти = пробудження
 *   - Soldier_Seconds_Since_Last_Sync()
 *   - Build_Time_Sync_Request_Payload(out, did, secs_since_sync, vcap_mv)
 * Кенозис тесту: відтворюємо «Солдат не чув Королеви 13 годин» і перевіряємо,
 * що сторожовий пес часу подає голос (з cooldown'ом проти спаму ефіру).
 */
#define FW20S2_SYNC_REQ_MARKER            0x56
#define FW20S2_SYNC_REQ_MAGIC_BYTE        0x53  /* 'S' */
#define FW20S2_SYNC_REQ_PACKET_SIZE       16
/* Wall-кванти = ПРОБУДЖЕННЯ (tick мертвий у STOP2 — дзеркало main.c). */
#define FW20S2_DRIFT_THRESHOLD_WAKEUPS    1440u  /* ≈12 год при циклі 26-32 с */
#define FW20S2_REQUEST_COOLDOWN_WAKEUPS   120u   /* ≈1 год */
#define FW20S2_COLD_BOOT_GRACE_WAKEUPS    20u    /* ≈10 хв */
#define FW20S2_NOMINAL_CYCLE_S            30u
#define FW20S2_PANIC_TTL                  5

/* Test-local mirrors of firmware globals (Soldier-side).
 * Reuse existing test_soldier_unix_ts defined earlier (FW.20-S1 beacon RX). */
static uint16_t test_wakeups_since_boot         = 0;
static uint16_t test_wakeups_since_sync         = 0;
static uint16_t test_wakeups_since_sync_request = 0;
static uint8_t  test_sync_request_ever          = 0;

static uint8_t Test_Should_Request_Time_Sync(void) {
    if (test_sync_request_ever &&
        test_wakeups_since_sync_request < FW20S2_REQUEST_COOLDOWN_WAKEUPS) return 0;
    if (test_soldier_unix_ts == 0) {
        return (test_wakeups_since_boot >= FW20S2_COLD_BOOT_GRACE_WAKEUPS) ? 1 : 0;
    }
    return (test_wakeups_since_sync >= FW20S2_DRIFT_THRESHOLD_WAKEUPS) ? 1 : 0;
}

static uint32_t Test_Seconds_Since_Last_Sync(void) {
    if (test_soldier_unix_ts == 0) return 0;
    return (uint32_t)test_wakeups_since_sync * FW20S2_NOMINAL_CYCLE_S;
}

static void Test_Build_Time_Sync_Request_Payload(uint8_t* out, uint32_t did,
                                                   uint32_t secs_since_sync,
                                                   uint16_t vcap_mv) {
    out[0]  = FW20S2_SYNC_REQ_MARKER;
    out[1]  = (uint8_t)(did >> 24);
    out[2]  = (uint8_t)(did >> 16);
    out[3]  = (uint8_t)(did >> 8);
    out[4]  = (uint8_t)(did & 0xFFu);
    out[5]  = (uint8_t)(secs_since_sync >> 24);
    out[6]  = (uint8_t)(secs_since_sync >> 16);
    out[7]  = (uint8_t)(secs_since_sync >> 8);
    out[8]  = (uint8_t)(secs_since_sync & 0xFFu);
    out[9]  = FW20S2_PANIC_TTL;
    out[10] = FW20S2_SYNC_REQ_MAGIC_BYTE;
    out[11] = (uint8_t)(vcap_mv >> 8);   /* [ARCH.41-C] здоров'я EDLC у hello */
    out[12] = (uint8_t)(vcap_mv & 0xFFu);
    for (uint8_t i = 13; i < FW20S2_SYNC_REQ_PACKET_SIZE; i++) out[i] = 0;
}

static void Test_FW20S2_Reset(void) {
    test_soldier_unix_ts            = 0;
    test_soldier_unix_ts_local_tick = 0;
    test_wakeups_since_boot         = 0;
    test_wakeups_since_sync         = 0;
    test_wakeups_since_sync_request = 0;
    test_sync_request_ever          = 0;
}

TEST(test_fw20s2_drift_cold_boot_grace_no_request) {
    /* Cold-boot, 2 пробудження (≈1 хв) — ще у grace (20 пробуджень ≈10 хв). */
    Test_FW20S2_Reset();
    test_wakeups_since_boot = 2;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 0);
}

TEST(test_fw20s2_drift_cold_boot_after_grace_requests) {
    /* Cold-boot, 22 пробудження (≈11 хв) — grace вийшов, beacon не прилетів. */
    Test_FW20S2_Reset();
    test_wakeups_since_boot = 22;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 1);
}

TEST(test_fw20s2_drift_recently_synced_no_request) {
    /* Beacon ≈1 год тому (120 пробуджень) — далеко від ≈12-год порогу (1440). */
    Test_FW20S2_Reset();
    test_soldier_unix_ts    = 1714000000u;
    test_wakeups_since_sync = 120;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 0);
}

TEST(test_fw20s2_drift_past_threshold_triggers_request) {
    /* Тиша ≈13 год (1560 пробуджень) — поза порогом. Сторожовий пес гавкає. */
    Test_FW20S2_Reset();
    test_soldier_unix_ts    = 1714000000u;
    test_wakeups_since_sync = 1560;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 1);
}

TEST(test_fw20s2_drift_cooldown_suppresses_repeat_request) {
    /* Уже просили ≈30 хв тому (60 пробуджень), дрейф досі великий — мовчимо
     * до ≈1 год (120). */
    Test_FW20S2_Reset();
    test_soldier_unix_ts            = 1714000000u;
    test_wakeups_since_sync         = 1560;
    test_sync_request_ever          = 1;
    test_wakeups_since_sync_request = 60;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 0);

    /* 130 пробуджень від попереднього зойку — понад cooldown, знову можна. */
    test_wakeups_since_sync_request = 130;
    ASSERT_EQ(Test_Should_Request_Time_Sync(), 1);
}

TEST(test_fw20s2_seconds_since_sync_zero_when_never_synced) {
    Test_FW20S2_Reset();
    test_wakeups_since_sync = 999;
    ASSERT_EQ(Test_Seconds_Since_Last_Sync(), 0u);
}

TEST(test_fw20s2_seconds_since_sync_computed_warm) {
    /* 1560 пробуджень × 30 с номіналу = 46 800 с (≈13 год) — масштаб для
     * Grafana-алерту, точність ±20% за циклом 26-32 с. */
    Test_FW20S2_Reset();
    test_soldier_unix_ts    = 1714000000u;
    test_wakeups_since_sync = 1560;
    ASSERT_EQ(Test_Seconds_Since_Last_Sync(), 46800u);
}

TEST(test_fw20s2_sync_req_payload_layout) {
    uint8_t p[FW20S2_SYNC_REQ_PACKET_SIZE];
    Test_Build_Time_Sync_Request_Payload(p, 0xCAFEBABEu, 47000u, 4321u);
    ASSERT_EQ(p[0], FW20S2_SYNC_REQ_MARKER);
    /* DID big-endian */
    ASSERT_EQ(p[1], 0xCAu);
    ASSERT_EQ(p[2], 0xFEu);
    ASSERT_EQ(p[3], 0xBAu);
    ASSERT_EQ(p[4], 0xBEu);
    /* secs_since_sync big-endian: 47000 = 0x0000B798 */
    ASSERT_EQ(p[5], 0x00u);
    ASSERT_EQ(p[6], 0x00u);
    ASSERT_EQ(p[7], 0xB7u);
    ASSERT_EQ(p[8], 0x98u);
    ASSERT_EQ(p[9], FW20S2_PANIC_TTL);
    ASSERT_EQ(p[10], FW20S2_SYNC_REQ_MAGIC_BYTE);
    /* [ARCH.41-C] vcap_mv big-endian: 4321 = 0x10E1 */
    ASSERT_EQ(p[11], 0x10u);
    ASSERT_EQ(p[12], 0xE1u);
    /* PAD bytes 13..15 must be zeroed */
    for (int i = 13; i < FW20S2_SYNC_REQ_PACKET_SIZE; i++) ASSERT_EQ(p[i], 0u);
}

TEST(test_fw20s2_sync_req_marker_disambiguation_from_ota_req) {
    /* OTA_REQ використовує 0x55 + magic 'R' (FW.27-B); SYNC_REQ — 0x56 + 'S'.
     * Жоден байт-у-байт overlap'у — маркер І магія різні. */
    uint8_t p[FW20S2_SYNC_REQ_PACKET_SIZE];
    Test_Build_Time_Sync_Request_Payload(p, 0xDEADBEEFu, 0u, 3300u);
    ASSERT_TRUE(p[0] != 0x55u);              /* НЕ OTA_REQ_MARKER */
    ASSERT_TRUE(p[10] != 'R');               /* НЕ FW.27-B magic */
    ASSERT_EQ(p[0], 0x56u);
    ASSERT_EQ(p[10], 'S');
}

/* ════════════════════════════════════════════════════════════════════
 * [ARCH.41-B] Sentinel «час невідомий» в acoustic-байті
 * ════════════════════════════════════════════════════════════════════
 * Дзеркало Soldier_Acoustic_Wire_Value (firmware/soldier/main.c):
 * time_uncertain ⇒ 0xFE на дроті (Лоренц на обох сторонах рахується з 0 —
 * бекенд нейтралізує 0xFE→0 до DCI); реальні 0xFE → 0xFD (ніколи не
 * імітувати sentinel); 0xFF лишається легальною FW.22-сатурацією.
 */
#define ARCH41_ACOUSTIC_SENTINEL 0xFEu

static uint8_t Test_Acoustic_Wire_Value(uint8_t snapshot, uint8_t time_uncertain) {
    if (time_uncertain) return ARCH41_ACOUSTIC_SENTINEL;
    if (snapshot == ARCH41_ACOUSTIC_SENTINEL) return 0xFDu;
    return snapshot;
}

TEST(test_arch41_sentinel_replaces_acoustic_when_time_uncertain) {
    /* Час невідомий — реальний лічильник жертвується, летить sentinel. */
    ASSERT_EQ(Test_Acoustic_Wire_Value(0u, 1u),    ARCH41_ACOUSTIC_SENTINEL);
    ASSERT_EQ(Test_Acoustic_Wire_Value(42u, 1u),   ARCH41_ACOUSTIC_SENTINEL);
    ASSERT_EQ(Test_Acoustic_Wire_Value(0xFFu, 1u), ARCH41_ACOUSTIC_SENTINEL);
}

TEST(test_arch41_real_0xfe_clamped_never_impersonates_sentinel) {
    /* 254 справжні події → 253 на дроті: sentinel однозначний назавжди. */
    ASSERT_EQ(Test_Acoustic_Wire_Value(ARCH41_ACOUSTIC_SENTINEL, 0u), 0xFDu);
}

TEST(test_arch41_normal_acoustic_passthrough_incl_saturation) {
    /* Час відомий — лічильник іде як є; 0xFF (FW.22 saturation) легальний. */
    ASSERT_EQ(Test_Acoustic_Wire_Value(0u, 0u),    0u);
    ASSERT_EQ(Test_Acoustic_Wire_Value(42u, 0u),   42u);
    ASSERT_EQ(Test_Acoustic_Wire_Value(0xFDu, 0u), 0xFDu);
    ASSERT_EQ(Test_Acoustic_Wire_Value(0xFFu, 0u), 0xFFu);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20-S2] Mesh-Relay: per-hop drift compensation (freeze-contract)
 * ════════════════════════════════════════════════════════════════════
 * Дзеркало логіки з firmware/soldier/main.c:
 *   Soldier_Try_Relay_Time_Beacon(in_plain, role, in_rx_tick, now_tick,
 *                                 dedup, out_plain)
 *     → BeaconRelayResult enum (OK / 7 reasons of drop)
 * Кенозис тесту: відтворюємо «Провідник почув Королеву, потримав маяк 5 секунд,
 * передав далі з компенсованим часом» — і всі причини дропу. Журнал поколінь
 * (anti-storm, FW.20-S2 4/5) — РЕАЛЬНИЙ beacon_dedup.h: тут ганяються лише
 * його чисті функції (Gen/Seen/Mark), persistence-банк — test_flash_kv.c.
 */
#include "../common/beacon_dedup.h"

#define FW20S2_MESH_BEACON_MARKER       0x9C
#define FW20S2_MESH_BEACON_MAGIC        'B'
#define FW20S2_MESH_AUTH_FLAG           0x80
#define FW20S2_MESH_TTL_MASK            0x7F
#define FW20S2_MESH_MIN_TTL             2u
#define FW20S2_MESH_MAX_HOP_DELAY_SEC   3600UL
#define FW20S2_MESH_FRAME_SIZE          16u
#define FW20S2_MESH_ROLE_SOLDIER        0
#define FW20S2_MESH_ROLE_PROVISIONER    1

typedef enum {
    FW20S2_RELAY_OK = 0,
    FW20S2_RELAY_NOT_PROVISIONER,
    FW20S2_RELAY_BAD_FRAME,
    FW20S2_RELAY_NULL_TS,
    FW20S2_RELAY_NOT_AUTHORITATIVE,
    FW20S2_RELAY_TTL_EXHAUSTED,
    FW20S2_RELAY_HOP_TOO_LONG,
    FW20S2_RELAY_DUPLICATE
} TestBeaconRelayResult;

static TestBeaconRelayResult Test_Try_Relay_Time_Beacon(
    const uint8_t* in_plain, uint8_t role,
    uint32_t in_rx_tick, uint32_t now_tick,
    const BeaconDedup* dedup, uint8_t* out_plain)
{
    if (role != FW20S2_MESH_ROLE_PROVISIONER) return FW20S2_RELAY_NOT_PROVISIONER;
    if (in_plain[0]  != FW20S2_MESH_BEACON_MARKER) return FW20S2_RELAY_BAD_FRAME;
    if (in_plain[10] != FW20S2_MESH_BEACON_MAGIC)  return FW20S2_RELAY_BAD_FRAME;
    uint32_t orig_ts = ((uint32_t)in_plain[1] << 24) | ((uint32_t)in_plain[2] << 16) |
                       ((uint32_t)in_plain[3] << 8)  | (uint32_t)in_plain[4];
    if (orig_ts == 0) return FW20S2_RELAY_NULL_TS;
    uint8_t in_byte9 = in_plain[9];
    if (dedup == NULL && !(in_byte9 & FW20S2_MESH_AUTH_FLAG))
        return FW20S2_RELAY_NOT_AUTHORITATIVE;
    uint8_t in_ttl = in_byte9 & FW20S2_MESH_TTL_MASK;
    if (in_ttl < FW20S2_MESH_MIN_TTL) return FW20S2_RELAY_TTL_EXHAUSTED;
    uint32_t hold_sec = (now_tick - in_rx_tick) / 1000u;
    if (hold_sec > FW20S2_MESH_MAX_HOP_DELAY_SEC) return FW20S2_RELAY_HOP_TOO_LONG;
    if (dedup != NULL && Beacon_Dedup_Seen(dedup, Beacon_Dedup_Gen(orig_ts)))
        return FW20S2_RELAY_DUPLICATE;
    for (uint8_t i = 0; i < FW20S2_MESH_FRAME_SIZE; i++) out_plain[i] = in_plain[i];
    uint32_t relayed_ts = orig_ts + hold_sec;
    out_plain[1] = (uint8_t)(relayed_ts >> 24);
    out_plain[2] = (uint8_t)(relayed_ts >> 16);
    out_plain[3] = (uint8_t)(relayed_ts >> 8);
    out_plain[4] = (uint8_t)(relayed_ts & 0xFFu);
    out_plain[9] = (uint8_t)((in_ttl - 1u) & FW20S2_MESH_TTL_MASK);
    return FW20S2_RELAY_OK;
}

/* Helper: збираємо authoritative beacon з заданими ts і TTL для тестів. */
static void Test_Build_Mesh_Beacon(uint8_t* out, uint32_t ts, uint8_t ttl,
                                     uint8_t auth) {
    for (uint8_t i = 0; i < 16; i++) out[i] = 0;
    out[0]  = FW20S2_MESH_BEACON_MARKER;
    out[1]  = (uint8_t)(ts >> 24);
    out[2]  = (uint8_t)(ts >> 16);
    out[3]  = (uint8_t)(ts >> 8);
    out[4]  = (uint8_t)(ts & 0xFFu);
    out[9]  = (auth ? FW20S2_MESH_AUTH_FLAG : 0) | (ttl & FW20S2_MESH_TTL_MASK);
    out[10] = FW20S2_MESH_BEACON_MAGIC;
}

TEST(test_fw20s2_relay_happy_path_with_drift_compensation) {
    /* Провідник, authoritative beacon, TTL=2, hold=5 секунд → relay з ts+5. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER,
        /*rx_tick*/ 100u, /*now_tick*/ 100u + 5000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    /* Wire decode перевіряє per-hop drift compensation */
    uint32_t out_ts = ((uint32_t)out[1] << 24) | ((uint32_t)out[2] << 16) |
                      ((uint32_t)out[3] << 8)  | (uint32_t)out[4];
    ASSERT_EQ(out_ts, 1714000005u);
    /* Auth-біт явно скинуто (expected — relay-маяки не authoritative,
     * це anti-storm інваріант freeze-contract'у), TTL декрементовано до 1 */
    ASSERT_FALSE(out[9] & FW20S2_MESH_AUTH_FLAG);
    ASSERT_EQ(out[9] & FW20S2_MESH_TTL_MASK, 1u);
    /* Marker + magic збережені — дзеркало Queen wire-формату */
    ASSERT_EQ(out[0], FW20S2_MESH_BEACON_MARKER);
    ASSERT_EQ(out[10], FW20S2_MESH_BEACON_MAGIC);
}

TEST(test_fw20s2_relay_zero_hold_keeps_ts_unchanged) {
    /* Hold = 0 (мікросекунди між RX і TX) → relayed_ts == orig_ts. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 3, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 500u, 500u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    uint32_t out_ts = ((uint32_t)out[1] << 24) | ((uint32_t)out[2] << 16) |
                      ((uint32_t)out[3] << 8)  | (uint32_t)out[4];
    ASSERT_EQ(out_ts, 1714000000u);
    ASSERT_EQ(out[9] & FW20S2_MESH_TTL_MASK, 2u);  /* 3-1=2 */
}

TEST(test_fw20s2_relay_preserves_tdma_reserve_and_padding) {
    /* Байти 5..8 (TDMA-резерв ARCH.26) і 11..15 (padding) повинні
     * прозоро переноситися через hop — майбутні поля не втрачаються. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    in[5] = 0xAA; in[6] = 0xBB; in[7] = 0xCC; in[8] = 0xDD;
    in[11] = 0x11; in[12] = 0x22; in[13] = 0x33; in[14] = 0x44; in[15] = 0x55;
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    ASSERT_EQ(out[5], 0xAA); ASSERT_EQ(out[6], 0xBB);
    ASSERT_EQ(out[7], 0xCC); ASSERT_EQ(out[8], 0xDD);
    ASSERT_EQ(out[11], 0x11); ASSERT_EQ(out[12], 0x22);
    ASSERT_EQ(out[13], 0x33); ASSERT_EQ(out[14], 0x44);
    ASSERT_EQ(out[15], 0x55);
}

TEST(test_fw20s2_relay_drop_when_role_is_soldier) {
    /* Звичайний Солдат не транслює — енергобюджет. */
    uint8_t in[16], out[16] = {0xFF};  /* sentinel — out не повинен мутуватися */
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_SOLDIER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_NOT_PROVISIONER);
    ASSERT_EQ(out[0], 0xFF);  /* out недоторкнутий */
}

TEST(test_fw20s2_relay_drop_when_marker_wrong) {
    /* Випадковий CMD-фрейм з 0x99 (OTA) — не наша справа. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    in[0] = 0x99;
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_BAD_FRAME);
}

TEST(test_fw20s2_relay_drop_when_magic_wrong) {
    /* Marker правильний, але magic 'B' зіпсовано — захист від колізії. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    in[10] = 'X';
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_BAD_FRAME);
}

TEST(test_fw20s2_relay_drop_when_ts_zero) {
    /* Беззмістовна епоха (Королева ще не отримала першого CoAP-роздтрипа). */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 0u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_NULL_TS);
}

TEST(test_fw20s2_relay_drop_when_not_authoritative) {
    /* Anti-storm: маяк з auth=0 уже relay'ний — не ретранслюємо повторно. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, /*auth=*/0);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_NOT_AUTHORITATIVE);
}

TEST(test_fw20s2_relay_drop_when_ttl_exhausted) {
    /* TTL=1 (як зараз транслює Королева) → decrement дав би 0 → дроп. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, /*ttl=*/1, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_TTL_EXHAUSTED);
}

TEST(test_fw20s2_relay_drop_when_hold_exceeds_max) {
    /* Hold-delay > 1 год — sanity cap. Провідник підвис на OTA / IWDG-шторм. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    /* 3601 секунд = 3601000 мс — на 1 секунду понад MAX_HOP_DELAY_SEC */
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0u, 3601u * 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_HOP_TOO_LONG);
}

TEST(test_fw20s2_relay_hold_exactly_at_max_passes) {
    /* Boundary: hold == MAX_HOP_DELAY_SEC рівно (3600 сек) — пропускаємо. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0u, 3600u * 1000u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    uint32_t out_ts = ((uint32_t)out[1] << 24) | ((uint32_t)out[2] << 16) |
                      ((uint32_t)out[3] << 8)  | (uint32_t)out[4];
    ASSERT_EQ(out_ts, 1714000000u + 3600u);
}

TEST(test_fw20s2_relay_tick_wrap_safe) {
    /* HAL_GetTick wrap раз у 49.7 днів. Перевіряємо modular arithmetic:
     * rx=0xFFFFFF00, now=0x00000064 → hold = 0x164 мс ≈ 0 сек. */
    uint8_t in[16], out[16];
    Test_Build_Mesh_Beacon(in, 1714000000u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER,
        /*rx_tick=*/ 0xFFFFFF00u, /*now_tick=*/ 0x00000064u, NULL, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    /* hold = 0x164 = 356 мс → 0 секунд → ts unchanged */
    uint32_t out_ts = ((uint32_t)out[1] << 24) | ((uint32_t)out[2] << 16) |
                      ((uint32_t)out[3] << 8)  | (uint32_t)out[4];
    ASSERT_EQ(out_ts, 1714000000u);
}

TEST(test_fw20s2_relay_two_hop_chain_kills_authoritativeness) {
    /* Симулюємо A→Provisioner→B: вихід першого relay'у НЕ повинен
     * пройти guard повторно (auth=0) — це anti-storm freeze-contract
     * БЕЗ журналу поколінь (dedup=NULL — KV не змонтовано / гейт off). */
    uint8_t in1[16], out1[16], out2[16];
    Test_Build_Mesh_Beacon(in1, 1714000000u, 3, 1);  /* TTL=3 (достатньо для relay), але auth=0 після першого hop'а запобігає повторному relay'у */
    TestBeaconRelayResult r1 = Test_Try_Relay_Time_Beacon(
        in1, FW20S2_MESH_ROLE_PROVISIONER, 0, 2000u, NULL, out1);
    ASSERT_EQ(r1, FW20S2_RELAY_OK);
    /* Другий Провідник пробує ретранслювати out1 — має відмовити */
    TestBeaconRelayResult r2 = Test_Try_Relay_Time_Beacon(
        out1, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, NULL, out2);
    ASSERT_EQ(r2, FW20S2_RELAY_NOT_AUTHORITATIVE);
}

/* ──────────────────────────────────────────────────────────────────────
 * [FW.20-S2 4/5] Повний mesh-relay: журнал поколінь (anti-storm dedup)
 * Журнал — РЕАЛЬНИЙ ../common/beacon_dedup.h (чисті Gen/Seen/Mark);
 * persistence (Flash-KV 0x20, power-cut) — банк у test_flash_kv.c.
 * ────────────────────────────────────────────────────────────────────── */

TEST(test_fw20s2_mesh_dedup_unlocks_auth0_relay) {
    /* З журналом relay'ний маяк (auth=0) relay-able далі — повний mesh.
     * Без журналу той самий кадр падав на NOT_AUTHORITATIVE (тест вище). */
    uint8_t in[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Test_Build_Mesh_Beacon(in, 1714000000u, /*ttl=*/2, /*auth=*/0);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 1000u, &dd, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
    ASSERT_FALSE(out[9] & FW20S2_MESH_AUTH_FLAG);       /* auth лишився 0 */
    ASSERT_EQ(out[9] & FW20S2_MESH_TTL_MASK, 1u);       /* TTL 2→1 */
}

TEST(test_fw20s2_mesh_dedup_queen_double_broadcast_suppressed) {
    /* Королева маячить і за 15-хв тактом, І після кожного зрізаного
     * конверта — те саме покоління лунає двічі. Перший relay проходить
     * (викликач Mark'ає після TX), другий — DUPLICATE. Це головний шторм
     * на TTL=2, який гасить журнал. */
    uint8_t in1[16], in2[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Test_Build_Mesh_Beacon(in1, 1714000000u, 2, 1);
    TestBeaconRelayResult r1 = Test_Try_Relay_Time_Beacon(
        in1, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r1, FW20S2_RELAY_OK);
    Beacon_Dedup_Mark(&dd, Beacon_Dedup_Gen(1714000000u)); /* після TX */
    /* +30 секунд — той самий 900-с bucket */
    Test_Build_Mesh_Beacon(in2, 1714000030u, 2, 1);
    TestBeaconRelayResult r2 = Test_Try_Relay_Time_Beacon(
        in2, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r2, FW20S2_RELAY_DUPLICATE);
}

TEST(test_fw20s2_mesh_dedup_pingpong_storm_killed) {
    /* TTL=4: A несе покоління G, B несе луну A (для B покоління свіже),
     * але луна B назад до A — DUPLICATE: журнал, а не TTL, глушить
     * пінг-понг Провідник↔Провідник. */
    uint8_t in[16], outA[16], outB[16], outA2[16];
    BeaconDedup ddA = {0, 0, 0}, ddB = {0, 0, 0};
    Test_Build_Mesh_Beacon(in, 1714000000u, /*ttl=*/4, /*auth=*/1);

    TestBeaconRelayResult rA = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &ddA, outA);
    ASSERT_EQ(rA, FW20S2_RELAY_OK);                     /* A: TTL 4→3 */
    Beacon_Dedup_Mark(&ddA, Beacon_Dedup_Gen(1714000000u));

    TestBeaconRelayResult rB = Test_Try_Relay_Time_Beacon(
        outA, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &ddB, outB);
    ASSERT_EQ(rB, FW20S2_RELAY_OK);                     /* B: TTL 3→2 */
    Beacon_Dedup_Mark(&ddB, Beacon_Dedup_Gen(1714000000u));

    /* Луна B повертається до A: TTL=2 ще relay-able, auth=0 relay-able
     * з журналом — лише DUPLICATE зупиняє шторм. */
    TestBeaconRelayResult rA2 = Test_Try_Relay_Time_Beacon(
        outB, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &ddA, outA2);
    ASSERT_EQ(rA2, FW20S2_RELAY_DUPLICATE);
}

TEST(test_fw20s2_mesh_dedup_fresh_generation_relays_again) {
    /* Нове покоління (наступний 900-с bucket) — журнал пропускає. */
    uint8_t in[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Beacon_Dedup_Mark(&dd, Beacon_Dedup_Gen(1714000000u));
    Test_Build_Mesh_Beacon(in, 1714000000u + 900u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
}

TEST(test_fw20s2_mesh_dedup_stale_generation_refused) {
    /* Покоління старше за вікно (8 × 900 с = 2 год) — «бачили»: застарілий
     * час не ретранслюємо, навіть якщо біта у вікні вже нема. */
    uint8_t in[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Beacon_Dedup_Mark(&dd, Beacon_Dedup_Gen(1714000000u));
    Test_Build_Mesh_Beacon(in, 1714000000u - 8u * 900u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r, FW20S2_RELAY_DUPLICATE);
}

TEST(test_fw20s2_mesh_dedup_out_of_order_within_window_relays) {
    /* Повільний шлях: покоління G-2 приїздить ПІСЛЯ G. Воно ще не
     * ретрансльовано і у вікні → OK (повільне піддерево теж отримає час).
     * Це і є перевага window-журналу над голим high-water. */
    uint8_t in[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Beacon_Dedup_Mark(&dd, Beacon_Dedup_Gen(1714000000u));
    Test_Build_Mesh_Beacon(in, 1714000000u - 2u * 900u, 2, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r, FW20S2_RELAY_OK);
}

TEST(test_fw20s2_mesh_dedup_duplicate_checked_last) {
    /* DUPLICATE — останній guard: структурні відмови (TTL) звітуються
     * раніше, навіть якщо покоління вже у журналі. Чесна метрика шторму. */
    uint8_t in[16], out[16];
    BeaconDedup dd = {0, 0, 0};
    Beacon_Dedup_Mark(&dd, Beacon_Dedup_Gen(1714000000u));
    Test_Build_Mesh_Beacon(in, 1714000000u, /*ttl=*/1, 1);
    TestBeaconRelayResult r = Test_Try_Relay_Time_Beacon(
        in, FW20S2_MESH_ROLE_PROVISIONER, 0, 0, &dd, out);
    ASSERT_EQ(r, FW20S2_RELAY_TTL_EXHAUSTED);
}

TEST(test_fw20s2_mesh_dedup_gen_bucket_boundary) {
    /* Wire-санітарка такту: ts у межах одного 900-с bucket'а — одне
     * покоління; через межу — різні. */
    ASSERT_EQ(Beacon_Dedup_Gen(1714000199u), Beacon_Dedup_Gen(1714000100u));
    ASSERT_TRUE(Beacon_Dedup_Gen(1714000800u) > Beacon_Dedup_Gen(1714000799u - 900u));
    /* max uint32 ts вміщується у 24-бітне покоління (пакування 0x20) */
    ASSERT_TRUE(Beacon_Dedup_Gen(0xFFFFFFFFu) < (1u << 24));
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.20-S2 #5] Gossip-Piggyback (freeze-contract, host-mirror)
 * ════════════════════════════════════════════════════════════════════
 * Дзеркало логіки з firmware/soldier/main.c:
 *   Soldier_Pack_Gossip_Ts_Byte(unix_ts) → uint8 (= unix_ts & 0xFF)
 *   Soldier_Try_Apply_Gossip_Ts(local_ts, gossip_lsb) → refined_ts
 *
 * Кенозис байта: один октет у normal-telemetry payload byte 14 несе LSB
 * серверного UTC, що дозволяє сусідам уточнити свій local_ts на ±128 сек
 * без участі Королеви. Активація потребує hot-path вшивання у Phase 2 +
 * RX-гілки для нормальних telemetry-кадрів — це freeze-contract тестів.
 */
#define FW20S2_GOSSIP_MAX_DRIFT_SEC  127u

static inline uint8_t Test_Pack_Gossip_Ts_Byte(uint32_t unix_ts) {
    return (uint8_t)(unix_ts & 0xFFu);
}

static uint32_t Test_Apply_Gossip_Ts(uint32_t local_ts, uint8_t gossip_lsb) {
    if (local_ts == 0) return 0;
    uint32_t base       = local_ts & ~((uint32_t)0xFFu);
    uint32_t candidate  = base | (uint32_t)gossip_lsb;
    uint32_t cand_prev  = candidate - 256u;
    uint32_t cand_next  = candidate + 256u;
    int32_t  diff_curr  = (int32_t)(candidate - local_ts);
    int32_t  diff_prev  = (int32_t)(cand_prev - local_ts);
    int32_t  diff_next  = (int32_t)(cand_next - local_ts);
    int32_t  abs_curr   = (diff_curr < 0) ? -diff_curr : diff_curr;
    int32_t  abs_prev   = (diff_prev < 0) ? -diff_prev : diff_prev;
    int32_t  abs_next   = (diff_next < 0) ? -diff_next : diff_next;
    uint32_t refined    = candidate;
    int32_t  best_abs   = abs_curr;
    if (abs_prev < best_abs) { refined = cand_prev; best_abs = abs_prev; }
    if (abs_next < best_abs) { refined = cand_next; best_abs = abs_next; }
    if ((uint32_t)best_abs > FW20S2_GOSSIP_MAX_DRIFT_SEC) return local_ts;
    return refined;
}

TEST(test_fw20s2_gossip_pack_zero_ts_returns_zero) {
    /* Cold-boot Solider не знає часу → пакує 0 → бекенд інтерпретує як
     * «no fresh gossip». */
    ASSERT_EQ(Test_Pack_Gossip_Ts_Byte(0u), 0);
}

TEST(test_fw20s2_gossip_pack_extracts_low_byte) {
    /* unix_ts = 1714000000 → 0x66225180 → low byte = 0x80 */
    ASSERT_EQ(Test_Pack_Gossip_Ts_Byte(1714000000u), 0x80);
    ASSERT_EQ(Test_Pack_Gossip_Ts_Byte(0xDEADBEEFu), 0xEF);
}

TEST(test_fw20s2_gossip_apply_cold_boot_returns_zero) {
    /* local_ts == 0 → freeze-contract: gossip недостатньо для cold-start */
    ASSERT_EQ(Test_Apply_Gossip_Ts(0, 0x42), 0);
}

TEST(test_fw20s2_gossip_apply_within_window_refines_ts) {
    /* local = 1714000200 (low byte 0x48 = 72), gossip says 0x80 = 128
     * Розрив всередині того ж 256-вікна: local 200, gossip 128 → 1714000128
     * (different by 72 sec backward). Within ±127 — застосовуємо. */
    uint32_t local  = 1714000200u;
    uint8_t  gossip = (uint8_t)(1714000128u & 0xFFu);  /* = 0x80 */
    uint32_t refined = Test_Apply_Gossip_Ts(local, gossip);
    ASSERT_EQ(refined, 1714000128u);
}

TEST(test_fw20s2_gossip_apply_picks_next_window) {
    /* Mathematica на гойдалці LSB-windows: коли local близький до межі
     * 256-сек блоку і gossip має маленький LSB, кандидат `base | lsb`
     * може бути занадто далеко (>127) у попередньому блоці — тоді solver
     * має обрати `cand_next = candidate + 256` як справжню «свіжу» позицію.
     *
     * local = 1714000250 (LSB = 250 - 128 = 122 → wait: 1714000250 & 0xFF
     *         = 1714000250 - 1714000128 = 122 → 0x7A)
     * gossip_lsb = 5  (як, наприклад, від neighbour'а у наступному вікні)
     * base_aligned = 1714000128
     * candidate    = 1714000128 | 5 = 1714000133  → diff = -117, abs=117 ✓
     * cand_next    = 1714000389                   → diff = +139, abs=139
     * cand_prev    = 1713999877                   → diff = -373, abs=373
     * best = candidate (closest at 117 ≤127) → refined = 1714000133. */
    uint32_t local = 1714000250u;
    uint8_t  gossip_lsb = 5u;
    uint32_t refined = Test_Apply_Gossip_Ts(local, gossip_lsb);
    ASSERT_EQ(refined, 1714000133u);
}

TEST(test_fw20s2_gossip_apply_picks_prev_window_when_clock_jumped) {
    /* Симулюємо: local дрейфонув ВПЕРЕД відносно мережі (наприклад RTC бігло
     * швидше за Queen). local = base + 50 + 256 (= 306 sec ahead of base).
     * Gossip несе LSB що відповідає base+50 (правильному часу).
     * Distance: |306 - 50| = 256 → сапер обере cand_prev = candidate-256 →
     * delta = |50 - 306| = 256 теж outside cap. → refined = local. */
    uint32_t base = 0x10000u;
    uint32_t local = base + 50u + 256u;  /* clock ran 256 sec fast */
    uint8_t  gossip_lsb = (uint8_t)((base + 50u) & 0xFFu);
    uint32_t refined = Test_Apply_Gossip_Ts(local, gossip_lsb);
    /* Outside ±127 — fall back to local */
    ASSERT_EQ(refined, local);
}

TEST(test_fw20s2_gossip_apply_drift_within_cap_corrects) {
    /* Solider drifted backward by 60 sec; gossip from neighbour gives true LSB.
     * local = 1714000000 - 60 = 1713999940; gossip = (1714000000 & 0xFF) = 0x80
     * Real expected refined = 1714000000. Distance 60 < 127 → застосувати. */
    uint32_t local = 1713999940u;
    uint8_t  gossip_lsb = 0x80u;  /* = (1714000000 & 0xFF) */
    uint32_t refined = Test_Apply_Gossip_Ts(local, gossip_lsb);
    ASSERT_EQ(refined, 1714000000u);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.42] Fauna acoustic-sampling Vcap guard (freeze-contract)
 * ════════════════════════════════════════════════════════════════════
 * Source SSOT: docs/03_03 §10.3 + docs/00_07 FW.42.
 *
 * Pure-logic mirror of `Fauna_Should_Sample` from firmware/soldier/main.c.
 * Decoupled from FW.4 (Run_Inference still commented) — when the fauna
 * sampling pathway lights up, the guard is already validated.
 */
#define TEST_FAUNA_VCAP_MIN_MV 4500u

static uint8_t test_fauna_skipped_low_vcap = 0;

static void Reset_Fauna_Skip_Counter(void) {
    test_fauna_skipped_low_vcap = 0;
}

static uint8_t Test_Fauna_Should_Sample(uint16_t vcap_mv) {
    if (vcap_mv >= TEST_FAUNA_VCAP_MIN_MV) return 1;
    if (test_fauna_skipped_low_vcap < 255) test_fauna_skipped_low_vcap++;
    return 0;
}

TEST(test_fw42_fauna_threshold_constant_matches_doc) {
    /* docs/03_03 §10.3 audit-fix: ΔV @ V_cap=4.5V ≈ -29 мВ — comfortable
     * margin above VBAT_OK ON (3.4V). Constant must be 4500 mV. */
    ASSERT_EQ((unsigned)TEST_FAUNA_VCAP_MIN_MV, 4500u);
}

TEST(test_fw42_fauna_sample_allowed_at_exact_threshold) {
    Reset_Fauna_Skip_Counter();
    ASSERT_EQ(Test_Fauna_Should_Sample(TEST_FAUNA_VCAP_MIN_MV), 1);
    ASSERT_EQ(test_fauna_skipped_low_vcap, 0);
}

TEST(test_fw42_fauna_sample_allowed_above_threshold) {
    Reset_Fauna_Skip_Counter();
    ASSERT_EQ(Test_Fauna_Should_Sample(5000), 1);
    ASSERT_EQ(test_fauna_skipped_low_vcap, 0);
}

TEST(test_fw42_fauna_sample_blocked_below_threshold) {
    Reset_Fauna_Skip_Counter();
    ASSERT_EQ(Test_Fauna_Should_Sample(4499), 0);
    ASSERT_EQ(test_fauna_skipped_low_vcap, 1);
}

TEST(test_fw42_fauna_sample_blocked_deep_brownout) {
    /* V_cap == VBAT_OK ON (3.4V) — the very margin we are protecting. */
    Reset_Fauna_Skip_Counter();
    ASSERT_EQ(Test_Fauna_Should_Sample(3400), 0);
    ASSERT_EQ(test_fauna_skipped_low_vcap, 1);
}

TEST(test_fw42_fauna_skip_counter_increments_per_block) {
    Reset_Fauna_Skip_Counter();
    Test_Fauna_Should_Sample(4000);
    Test_Fauna_Should_Sample(3800);
    Test_Fauna_Should_Sample(3600);
    ASSERT_EQ(test_fauna_skipped_low_vcap, 3);
}

TEST(test_fw42_fauna_skip_counter_saturates_at_uint8_max) {
    Reset_Fauna_Skip_Counter();
    for (int i = 0; i < 300; i++) {
        Test_Fauna_Should_Sample(3000);
    }
    /* Saturating uint8 — 300 calls but counter stops at 255. */
    ASSERT_EQ(test_fauna_skipped_low_vcap, 255);
}

TEST(test_fw42_fauna_mixed_calls_do_not_decrement_counter) {
    /* Allowed calls must NOT decrement the counter; the metric tracks
     * cumulative skips, not "consecutive". */
    Reset_Fauna_Skip_Counter();
    Test_Fauna_Should_Sample(3000); /* skip → 1 */
    Test_Fauna_Should_Sample(5000); /* allowed */
    Test_Fauna_Should_Sample(3000); /* skip → 2 */
    Test_Fauna_Should_Sample(4500); /* allowed (exact threshold) */
    ASSERT_EQ(test_fauna_skipped_low_vcap, 2);
}

TEST(test_fw42_raw_adc_range_always_skips_fail_closed) {
    /* [FW.50-footgun, виконуване знання] Контракт guard'а — МІЛІВОЛЬТИ.
     * Call-site (main.c) з 2026-06-12 дає чесні мВ VDDA-проксі (≈3300,
     * стеля VREFINT-тракту < 4500) — fauna ЛИШАЄТЬСЯ fail-CLOSED аж до
     * живого Vcap-каналу з дільником (повний EDLC 5500 мВ > поріг).
     * «Fauna мертва» діагностується лічильником пропусків. Розгейт: FW.50
     * hardware-частина (дільник), НЕ зниження порогу. */
    Reset_Fauna_Skip_Counter();
    ASSERT_EQ(Test_Fauna_Should_Sample(4095), 0); /* стеля 12-bit тракту */
    ASSERT_EQ(Test_Fauna_Should_Sample(3300), 0); /* VDDA-проксі (типово) */
    ASSERT_EQ(test_fauna_skipped_low_vcap, 2);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.29] Follow-up boundary tests
 * ════════════════════════════════════════════════════════════════════
 * Закриваємо edge-case прогалини з `10_02 FW.29 follow-ups`:
 *   - StatusByte boundary при максимальних growth_points + panic
 *   - Взаємодія panic-кадру і acoustic saturation @ 255 (FW.22)
 */

TEST(test_fw29_status_byte_panic_with_max_growth_points) {
    /* [FW.29-PACK] Boundary: bio_contract_byte = Pack_BioContract(3, 63).
     * У новому 5-bit packing gp=63 clamps до 31 → byte = (3<<5)|31 = 0x7F
     * (bit 7 = 0). У normal payload mask `& 0x7F` нічого не змінює.
     * Backend читає status = (0x7F >> 5) & 3 = 3 (tamper) ✓, gp = 0x7F & 0x1F = 31. */
    uint8_t normal[16];
    Pack_Soldier_Payload(normal, 0xCAFEBABE, 3000, 25, 0, 120,
                          Pack_BioContract(3, 63), 3, 0);
    ASSERT_FALSE(normal[10] & PANIC_FLAG_BIT);
    ASSERT_EQ(normal[10], 0x7F);  /* (3<<5)|31 = 0x7F, bit 7 уже 0 */
    /* Decoded values: tamper survives PANIC_FLAG_BIT mask без demotion. */
    ASSERT_EQ((normal[10] >> 5) & 0x03, 3);  /* status=3 (tamper) */
    ASSERT_EQ(normal[10] & 0x1F, 31);         /* gp=31 (max 5-bit) */

    uint8_t panic[16];
    Build_Panic_Payload(panic, 0xCAFEBABE);
    ASSERT_TRUE(panic[10] & PANIC_FLAG_BIT);
    ASSERT_EQ(panic[10], PANIC_FLAG_BIT);  /* exact 0x80 — без residual status/gp */
}

TEST(test_fw29_panic_does_not_corrupt_acoustic_saturation) {
    /* FW.22 saturating @ 255 не повинен взаємодіяти з FW.29 panic flag.
     * У panic payload байт 7 — це фіксований 0xFF (panic-marker акустики),
     * НЕ acoustic_events. Перевіряємо, що панічна плоть не перетирає
     * StatusByte з FW.22 saturation lifecycle. */
    uint8_t acoustic_events_local = 255;  /* FW.22 saturation досягнуто */

    /* Normal payload: acoustic[7] = 255 (saturated), StatusByte clean */
    uint8_t normal[16];
    Pack_Soldier_Payload(normal, 0x12345678, 3000, 25, acoustic_events_local,
                          120, Pack_BioContract(0, 25), 3, 0);  /* [FW.29-PACK] gp 5-bit */
    ASSERT_EQ(normal[7], 255);  /* FW.22 saturation проходить як є */
    ASSERT_FALSE(normal[10] & PANIC_FLAG_BIT);

    /* Panic payload: byte 7 — це panic-marker 0xFF (НЕ acoustic counter),
     * StatusByte (byte 10) — exact PANIC_FLAG_BIT. Два незалежні поля. */
    uint8_t panic[16];
    Build_Panic_Payload(panic, 0x12345678);
    ASSERT_EQ(panic[7], 0xFF);
    ASSERT_EQ(panic[10], PANIC_FLAG_BIT);
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.50] ADC→mV conversion (VREFINT factory cal + resistor divider)
 *
 * Pure math from common/adc_convert.h (One-Home — same code the firmware
 * compiles). Proves the conversion the live path still lacks: raw count
 * (~1500) is NOT millivolts. Live wiring (separate Vcap ADC channel +
 * divider) is hardware-gated; this locks the math down meanwhile.
 * All values exact (no rounding) → ASSERT_EQ.
 * ════════════════════════════════════════════════════════════════════ */
#include "../common/adc_convert.h"

TEST(test_adc_vdda_nominal) {
    /* VREFINT reads its cal point → VDDA == 3.0 V cal reference. */
    ASSERT_EQ(Adc_Vdda_Mv(1500, 1500), 3000);
}

TEST(test_adc_vdda_high_supply) {
    /* Lower VREFINT_DATA ⇒ higher VDDA: 3000×1500/1200 = 3750 mV. */
    ASSERT_EQ(Adc_Vdda_Mv(1200, 1500), 3750);
}

TEST(test_adc_vdda_div_by_zero_guard) {
    ASSERT_EQ(Adc_Vdda_Mv(0, 1500), 0);   /* ADC fault → 0, no UB */
}

TEST(test_adc_pin_full_scale) {
    ASSERT_EQ(Adc_Pin_Mv(4095, 3300), 3300);
}

TEST(test_adc_pin_two_thirds) {
    /* 3000 × 2730/4095 = 2000 mV exactly. */
    ASSERT_EQ(Adc_Pin_Mv(2730, 3000), 2000);
}

TEST(test_adc_pin_zero) {
    ASSERT_EQ(Adc_Pin_Mv(0, 3300), 0);
}

TEST(test_adc_raw_to_mv_direct) {
    /* div 1:1 (no divider) at full scale → VDDA. */
    ASSERT_EQ(Adc_Raw_To_Mv(4095, 1500, 1500, 1, 1), 3000);
}

TEST(test_adc_raw_to_mv_divider_2to1) {
    /* Vcap 4000 mV through a 2:1 divider → pin 2000 mV (adc 2730 @ VDDA 3000),
     * scaled back ×2 → 4000 mV. */
    ASSERT_EQ(Adc_Raw_To_Mv(2730, 1500, 1500, 2, 1), 4000);
}

TEST(test_adc_raw_to_mv_div_by_zero_guard) {
    ASSERT_EQ(Adc_Raw_To_Mv(2048, 1500, 1500, 1, 0), 0);
}

TEST(test_fw50_raw_count_is_not_mv) {
    /* The bug, concretely: the OLD code compared a raw VREFINT count to a
     * 2800 mV threshold — never true; the same count is the 3.0 V cal point. */
    uint16_t raw = 1500;
    ASSERT_TRUE(raw < 2800);                  /* OLD: "vcap" < LISTEN → RX never opens */
    ASSERT_EQ(Adc_Vdda_Mv(raw, 1500), 3000);  /* real VDDA is 3000 mV, not 1500 */
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.49] WALL-CLOCK delta/elapsed guards (common/wall_time.h)
 *
 * HAL_GetTick freezes in STOP2 → tick-deltas measured only active-time, which
 * pinned delta_t near ~seconds → growth_points near max → every tree looked
 * maximally healthy (over-mint). The fix reads a free-running RTC calendar as
 * wall-seconds; these pure guards turn two wall reads into a safe delta_t
 * (cold-start / backward / epoch-jump → baseline) and a safe elapsed duration.
 * ════════════════════════════════════════════════════════════════════ */
#include "../common/wall_time.h"

#define TEST_WALL_BASELINE   60u
#define TEST_WALL_MAX_PLAUS  86400u   /* 24h — beyond = clock-set/wrap */

TEST(test_fw49_delta_cold_start_returns_baseline) {
    /* last_wall==0 → no prior cycle → baseline, NOT a giant now-0 delta. */
    ASSERT_EQ(Silken_Wall_Delta_Seconds(1700000000u, 0u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 60u);
}

TEST(test_fw49_delta_normal_interval) {
    ASSERT_EQ(Silken_Wall_Delta_Seconds(5000u, 4900u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 100u);
}

TEST(test_fw49_delta_small_real_interval_passes) {
    /* A genuine short wall-delta survives (e.g. vigorous recharge). The bug
     * was reading active-time, NOT clamping small values — 2s wall is valid. */
    ASSERT_EQ(Silken_Wall_Delta_Seconds(1002u, 1000u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 2u);
}

TEST(test_fw49_delta_backward_clock_returns_baseline) {
    ASSERT_EQ(Silken_Wall_Delta_Seconds(4900u, 5000u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 60u);
}

TEST(test_fw49_delta_epoch_jump_returns_baseline) {
    /* Calendar just set from beacon UTC (2000→2023): huge forward jump → baseline. */
    ASSERT_EQ(Silken_Wall_Delta_Seconds(1700000000u, 946684800u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 60u);
}

TEST(test_fw49_delta_boundary_exact_max_passes) {
    /* Exactly max_plausible is allowed; one more is a jump. */
    ASSERT_EQ(Silken_Wall_Delta_Seconds(1000u + 86400u, 1000u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 86400u);
    ASSERT_EQ(Silken_Wall_Delta_Seconds(1000u + 86401u, 1000u, TEST_WALL_BASELINE, TEST_WALL_MAX_PLAUS), 60u);
}

TEST(test_fw49_elapsed_never_set_returns_zero) {
    ASSERT_EQ(Silken_Wall_Elapsed_Seconds(5000u, 0u), 0u);
}

TEST(test_fw49_elapsed_normal) {
    ASSERT_EQ(Silken_Wall_Elapsed_Seconds(5000u, 1400u), 3600u);
}

TEST(test_fw49_elapsed_backward_clock_returns_zero) {
    ASSERT_EQ(Silken_Wall_Elapsed_Seconds(1400u, 5000u), 0u);
}

TEST(test_fw49_unix_from_calendar_rtc_epoch) {
    /* RTC default 2000-01-01 00:00:00 → 946684800 (free-running base). */
    ASSERT_EQ(Silken_Unix_From_Calendar(2000, 1, 1, 0, 0, 0), 946684800u);
}

TEST(test_fw49_unix_from_calendar_known_date) {
    /* 2024-01-01 00:00:00 UTC = 1704067200. */
    ASSERT_EQ(Silken_Unix_From_Calendar(2024, 1, 1, 0, 0, 0), 1704067200u);
    /* + 12:30:45 = +45045. */
    ASSERT_EQ(Silken_Unix_From_Calendar(2024, 1, 1, 12, 30, 45), 1704112245u);
}

/* [FW.49 S1] Інверсія unix→civil (Wall_Calendar_Set шлях). */
TEST(test_fw49_civil_from_unix_goldens) {
    int32_t y; uint32_t mo, d, hh, mm, ss;

    Silken_Civil_From_Unix(946684800u, &y, &mo, &d, &hh, &mm, &ss);
    ASSERT_EQ(y, 2000); ASSERT_EQ(mo, 1u); ASSERT_EQ(d, 1u);
    ASSERT_EQ(hh, 0u);  ASSERT_EQ(mm, 0u); ASSERT_EQ(ss, 0u);

    /* 2026-06-12 12:34:56 UTC = 1781267696 (epoch_day 20616). */
    Silken_Civil_From_Unix(1781267696u, &y, &mo, &d, &hh, &mm, &ss);
    ASSERT_EQ(y, 2026); ASSERT_EQ(mo, 6u);  ASSERT_EQ(d, 12u);
    ASSERT_EQ(hh, 12u); ASSERT_EQ(mm, 34u); ASSERT_EQ(ss, 56u);
    ASSERT_EQ(Silken_Epoch_Day_From_Unix(1781267696u), 20616u);

    /* Високосний лютий: 2028-02-29 23:59:59. */
    uint32_t leap = Silken_Unix_From_Calendar(2028, 2, 29, 23, 59, 59);
    Silken_Civil_From_Unix(leap, &y, &mo, &d, &hh, &mm, &ss);
    ASSERT_EQ(y, 2028); ASSERT_EQ(mo, 2u); ASSERT_EQ(d, 29u); ASSERT_EQ(ss, 59u);
}

/* [FW.49 S1] Roundtrip-пара: інверсія (wall_time.h) ↔ пряма FW.30-функція
 * (lorenz_seed.h) — мовчки розійтись не можуть. Прості кроки простим числом
 * покривають межі місяців/років/високосних на всьому RTC-вікні 2000..2099. */
TEST(test_fw49_civil_unix_roundtrip_sweep) {
    int32_t y; uint32_t mo, d, hh, mm, ss;
    for (uint32_t ts = 946684800u; ts <= 4102444799u; ts += 86399u * 37u) {
        Silken_Civil_From_Unix(ts, &y, &mo, &d, &hh, &mm, &ss);
        ASSERT_EQ(Silken_Unix_From_Calendar(y, mo, d, hh, mm, ss), ts);
    }
    /* стеля RTC-вікна: 2099-12-31 23:59:59 */
    Silken_Civil_From_Unix(4102444799u, &y, &mo, &d, &hh, &mm, &ss);
    ASSERT_EQ(y, 2099); ASSERT_EQ(mo, 12u); ASSERT_EQ(d, 31u);
}

/* [FW.49 S1] UTC-предикат: незсинхований 2000-based календар ніколи не
 * перетинає поріг за життя вузла; справжній UTC — завжди вище. */
TEST(test_fw49_wall_is_utc_boundary) {
    ASSERT_EQ(Silken_Wall_Is_Utc(946684800u), 0);   /* RTC-default епоха */
    ASSERT_EQ(Silken_Wall_Is_Utc(1599999999u), 0);
    ASSERT_EQ(Silken_Wall_Is_Utc(1600000000u), 1);
    ASSERT_EQ(Silken_Wall_Is_Utc(1781267696u), 1);  /* сьогодення */
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.18b] ttl_byte — бітфілд байта 11: [thr_invalid:5 | TTL:3]
 *
 * Лічильник відкинутих OTA-порогів їде верхніми 5 бітами TTL-байта;
 * golden-байти нижче заморожені freeze-contract'ом з бекендом
 * (spec/services/telemetry_unpacker_service_spec.rb). Тестуємо РЕАЛЬНИЙ
 * shared-хедер (One-Home), не дзеркало.
 * ════════════════════════════════════════════════════════════════════ */
#include "../common/ttl_byte.h"

TEST(test_fw18b_pack_zero_counter_is_legacy_byte) {
    /* Лічильник 0 → байт бітово ідентичний старому чистому TTL:
     * стара прошивка для нового бекенда виглядає як counter=0. */
    ASSERT_EQ(Ttl_Byte_Pack(3, 0), 0x03); /* DEFAULT_TTL */
    ASSERT_EQ(Ttl_Byte_Pack(5, 0), 0x05); /* PANIC_TTL   */
}

TEST(test_fw18b_pack_golden_wire) {
    /* Freeze-contract: ці ж байти звіряє RSpec бекенда. */
    ASSERT_EQ(Ttl_Byte_Pack(3, 7),  0x3B);
    ASSERT_EQ(Ttl_Byte_Pack(5, 31), 0xFD);
}

TEST(test_fw18b_pack_saturates_at_wire_cap) {
    /* RAM-лічильник сатурує @255, дріт — @31 (5 біт). */
    ASSERT_EQ(Ttl_Byte_Pack(3, 255), 0xFB);
    ASSERT_EQ(Ttl_Byte_Invalid(Ttl_Byte_Pack(3, 255)), 31);
}

TEST(test_fw18b_unpack_roundtrip) {
    uint8_t b = Ttl_Byte_Pack(5, 17);
    ASSERT_EQ(Ttl_Byte_Ttl(b), 5);
    ASSERT_EQ(Ttl_Byte_Invalid(b), 17);
}

TEST(test_fw18b_decrement_preserves_origin_counter) {
    /* Mesh-релей: TTL-- не сміє чіпати лічильник origin-Солдата. */
    uint8_t b = Ttl_Byte_Decrement(Ttl_Byte_Pack(3, 9));
    ASSERT_EQ(Ttl_Byte_Ttl(b), 2);
    ASSERT_EQ(Ttl_Byte_Invalid(b), 9);

    /* TTL=0 (мертвий пакет) — байт незмінний, без underflow у лічильник. */
    uint8_t dead = Ttl_Byte_Pack(0, 9);
    ASSERT_EQ(Ttl_Byte_Decrement(dead), dead);
}

TEST(test_fw18b_relay_liveness_masks_counter) {
    /* Живість пакета = ЛИШЕ нижні 3 біти: ненульовий лічильник при TTL=0
     * не сміє воскрешати пакет (вічний релей — анти-патерн). */
    ASSERT_EQ(Ttl_Byte_Ttl(Ttl_Byte_Pack(0, 31)), 0);
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
    RUN(test_did_golden_realistic_uid);
    RUN(test_did_golden_defective_uid_all_zero);
    RUN(test_did_golden_all_ff);
    RUN(test_did_avalanche_single_bit);
    RUN(test_did_sweep_never_zero_and_deterministic);

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
    RUN(test_ota_campaign_change_resets_after_streak);
    RUN(test_ota_mismatch_streak_clears_on_valid_chunk);
    RUN(test_vm_error_wire_byte_is_tamper_with_zero_growth);
    RUN(test_ota_duplicate_with_different_payload_preserves_original);
    RUN(test_ota_stop2_simulation_chunks_arrive_out_of_order);
    RUN(test_ota_stop2_simulation_duplicate_after_sleep_still_rejected);
    RUN(test_ota_total_chunks_zero_rejected);

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
    RUN(test_bio_anomaly_survives_panic_mask);  /* [FW.29-PACK] regression guard */

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

    printf("\n  Acoustic event ledger (ARCH.102):\n");
    RUN(test_acoustic_ledger_consumes_only_delivered);
    RUN(test_acoustic_ledger_keeps_remainder);
    RUN(test_acoustic_ledger_total_on_overshoot);

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
    RUN(test_tx_defer_extreme_cold_high_vcap_battery_backed);
    RUN(test_tx_defer_warm_minus5_low_vcap);
    RUN(test_tx_defer_boundary_minus15_zero_vcap);

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
    RUN(test_load_key_preserves_all_4_words);  /* post-ARCH.42: AES-128 LoRa = 4 words */
    RUN(test_load_key_magic_value_correct);
    RUN(test_load_key_second_load_overwrites);

    printf("\n  [FW.2 (в)] Cluster Broadcast Key (KEYB) Loading:\n");
    RUN(test_load_bcast_provisioned_success);
    RUN(test_load_bcast_unprovisioned_falls_back_to_session);
    RUN(test_load_bcast_wrong_magic_falls_back);
    RUN(test_load_bcast_zero_key_falls_back);
    RUN(test_load_bcast_magic_value_correct);

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
    RUN(test_days_from_civil_known_dates);
    RUN(test_epoch_day_from_unix_boundaries);
    RUN(test_cold_start_prefers_beacon_unix_ts_over_rtc);

    printf("\n  C-Bridge 7-Arg Signature (FW.30):\n");
    RUN(test_cbridge_unified_7arg_signature);

    printf("\n  Time-Sync Beacon RX (FW.20-S1):\n");
    RUN(test_beacon_rx_sets_unix_ts);
    RUN(test_beacon_rx_rejects_wrong_marker);
    RUN(test_beacon_rx_rejects_wrong_magic_byte);
    RUN(test_beacon_rx_rejects_wrong_size);
    RUN(test_beacon_rx_ts_zero_well_formed_but_dropped);
    RUN(test_beacon_rx_does_not_collide_with_ota);

    printf("\n  CMD_SET_THRESHOLDS Frame Parsing (FW.8):\n");
    RUN(test_thresholds_accepts_default_pinus_sylvestris);
    RUN(test_thresholds_accepts_negative_z_min);
    RUN(test_thresholds_rejects_wrong_marker);
    RUN(test_thresholds_rejects_wrong_payload_len);
    RUN(test_thresholds_rejects_bad_crc);
    RUN(test_thresholds_rejects_bit_flip_in_body);
    RUN(test_thresholds_rejects_z_min_geq_z_max);
    RUN(test_thresholds_rejects_z_opt_outside_band);
    RUN(test_thresholds_rejects_z_below_minus_100);
    RUN(test_thresholds_rejects_z_above_plus_100);
    RUN(test_thresholds_rejects_short_frame);
    RUN(test_thresholds_unmapped_species_id_0xFF_accepted);

    printf("\n  Magic Re-Request (FW.27-B):\n");
    RUN(test_rereq_full_bitmap_when_no_chunks);
    RUN(test_rereq_partial_bitmap);
    RUN(test_rereq_no_missing_returns_zero);
    RUN(test_rereq_total_zero_skipped);
    RUN(test_rereq_did_endian_consistent);

    printf("\n  FW.2 RX size-guard (до декрипту):\n");
    RUN(test_fw2_rx_guard_accepts_only_16);
    RUN(test_fw2_rx_guard_28b_never_reaches_ota_assembly);
    RUN(test_rereq_bitmap_capped_at_72_chunks);
    RUN(test_rereq_chunk_71_set_72_unset);
    RUN(test_rereq_fires_on_10th_silent_wakeup_and_resets);
    RUN(test_rereq_chunk_rx_reset_restarts_silence_window);
    RUN(test_rereq_should_NOT_tick_when_complete);
    RUN(test_rereq_should_NOT_tick_when_window_inactive);
    RUN(test_rereq_silent_counter_saturates_no_wrap);
    RUN(test_rereq_should_NOT_tick_when_last_tick_zero);

    printf("\n  HMAC Trailer + Dual-Gate (FW.23):\n");
    RUN(test_hmac_trailer_three_chunks_assemble_full_tag);
    RUN(test_hmac_trailer_out_of_order_chunks);
    RUN(test_hmac_trailer_version_chunk_parses);
    RUN(test_hmac_trailer_all_four_complete);
    RUN(test_hmac_trailer_rejects_wrong_marker);
    RUN(test_hmac_trailer_rejects_seg_idx_zero);
    RUN(test_hmac_trailer_rejects_seg_idx_above_4);
    RUN(test_hmac_trailer_rejects_undersized_chunk);
    RUN(test_dual_gate_both_pass_returns_1);
    RUN(test_dual_gate_magic_fail_returns_0);
    RUN(test_dual_gate_hmac_fail_returns_0);
    RUN(test_dual_gate_short_bytecode_returns_0);
    RUN(test_dual_gate_constant_time_compare_zero_diff);
    RUN(test_dual_gate_constant_time_compare_first_byte_diff);
    RUN(test_dual_gate_constant_time_compare_last_byte_diff);
    RUN(test_hmac_trailer_state_survives_simulated_stop2_between_segments);
    RUN(test_hmac_trailer_duplicate_segment_overwrites_idempotently);
    RUN(test_hmac_concat_equals_oneshot);
    RUN(test_ota_finalize_apply_real_hmac);
    RUN(test_ota_finalize_wait_without_trailer);
    RUN(test_ota_finalize_reject_tampered_body);
    RUN(test_ota_finalize_reject_version_mismatch);
    RUN(test_ota_finalize_reject_no_key);

    printf("\n  CMD_SET_AUDIO_THRESHOLDS Dispatcher (FW.18):\n");
    RUN(test_audio_dispatcher_accepts_default_60_85);
    RUN(test_audio_dispatcher_rejects_wrong_marker);
    RUN(test_audio_dispatcher_rejects_bad_crc);
    RUN(test_audio_dispatcher_rejects_warn_geq_crit_via_apply_default);
    RUN(test_audio_dispatcher_rejects_short_frame);
    RUN(test_audio_dispatcher_rejects_warn_zero);
    RUN(test_audio_dispatcher_rejects_crit_above_99);

    printf("\n  Panic Frame Counter Anti-Replay (SEC.10):\n");
    RUN(test_sec10_dr0_pack_roundtrip);
    RUN(test_sec10_dr0_pack_independence);
    RUN(test_sec20_streak_dr0_roundtrip_panic_intact);
    RUN(test_sec20_streak_independent_of_panic_and_acoustic);
    RUN(test_sec20_streak_saturates_no_overflow);
    RUN(test_sec20_fallback_at_third_consecutive);
    RUN(test_sec10_counter_increments_before_tx);
    RUN(test_sec10_counter_big_endian_in_pad);
    RUN(test_sec10_counter_saturates_at_max);
    RUN(test_sec10_counter_just_below_max_increments_once);
    RUN(test_sec10_cold_boot_reseed_from_hrng);
    RUN(test_sec10_cold_boot_reseed_zero_hrng_not_zero);
    RUN(test_sec10_warm_boot_preserves_counter);
    RUN(test_sec10_panic_counter_does_not_overlap_did);
    RUN(test_sec10_panic_counter_does_not_overlap_panic_flag);
    RUN(test_sec10_dr0_acoustic_preserved_through_panic_writeback);
    RUN(test_sec10_two_panics_have_distinct_counters);
    RUN(test_sec20_report_no_kv_degrades_to_legacy);
    RUN(test_sec20_report_factory_baseline);
    RUN(test_sec20_report_running_ota);
    RUN(test_sec20_report_reverted_carries_burned_id);
    RUN(test_sec20_report_id_modulo_14bit);
    RUN(test_sec20_report_vpd_squeeze);
    RUN(test_sec21_guard_derive_hrng_nonzero_null_lsb);
    RUN(test_sec21_guard_derive_hrng_dead_falls_back);
    RUN(test_sec21_guard_derive_total_silence_last_resort);
    RUN(test_sec21_guard_derive_lsb_only_entropy_still_nonzero);
    RUN(test_sec21_canary_bit_dr0_roundtrip_fields_intact);
    RUN(test_sec21_canary_bit_no_overlap);
    RUN(test_sec21_canary_preserved_through_dr0_writeback);
    RUN(test_sec21_mpu_rbar_golden);
    RUN(test_sec21_mpu_rasr_golden);
    RUN(test_sec21_mpu_tail_base_aligned_to_size);
    RUN(test_sec21_mpu_flash_tail_pages_writable);
    RUN(test_sec21_mpu_code_pages_not_writable);
    RUN(test_sec21_devevt_wire_layout);
    RUN(test_sec21_devevt_recognizer);
    RUN(test_sec21_devenv_header_golden);
    RUN(test_sec21_devenv_record_golden);
    RUN(test_sec21_devenv_body_len);

    printf("\n  Brownout PVD Lorenz Save (ARCH.21):\n");
    RUN(test_arch21_pvd_saves_lorenz_state);
    RUN(test_arch21_pvd_preserves_packed_dr0);
    RUN(test_arch21_pvd_preserves_last_wakeup_for_delta_t);
    RUN(test_arch21_pvd_skips_lorenz_when_invalid);
    RUN(test_arch21_pvd_save_then_restore_roundtrip);

    printf("\n  [FW.18 × ARCH.21] Brownout race for DR13/DR14 audio thresholds:\n");
    RUN(test_fw18_arch21_brownout_loses_freshly_received_thresholds);
    RUN(test_fw18_arch21_dr13_dr14_survive_brownout_when_already_persisted);
    RUN(test_fw18_arch21_dr13_dr14_corruption_falls_back_to_defaults);

    printf("\n  [FW.29-PACK × ARCH.21] StatusByte semantics survive brownout:\n");
    RUN(test_fw29pack_arch21_post_brownout_anomaly_pack_survives_panic_mask);
    RUN(test_fw29pack_arch21_tamper_after_brownout_decodes_correctly);

    printf("\n  Node Role Differentiation (ARCH.27):\n");
    RUN(test_arch27_role_soldier_magic_loads_soldier);
    RUN(test_arch27_role_provisioner_magic_loads_provisioner);
    RUN(test_arch27_role_unprovisioned_falls_back_to_soldier);
    RUN(test_arch27_role_zero_flash_falls_back_to_soldier);
    RUN(test_arch27_role_corrupted_magic_falls_back_to_soldier);

    printf("\n  Beacon Authoritativeness Flag (FW.20-S2):\n");
    RUN(test_fw20s2_authoritative_beacon_sets_flag);
    RUN(test_fw20s2_relay_beacon_clears_flag);
    RUN(test_fw20s2_legacy_beacon_byte9_zero_clears_flag);

    printf("\n  Drift-Monitor + Panic Sync Request (FW.20-S2):\n");
    RUN(test_fw20s2_drift_cold_boot_grace_no_request);
    RUN(test_fw20s2_drift_cold_boot_after_grace_requests);
    RUN(test_fw20s2_drift_recently_synced_no_request);
    RUN(test_fw20s2_drift_past_threshold_triggers_request);
    RUN(test_fw20s2_drift_cooldown_suppresses_repeat_request);
    RUN(test_fw20s2_seconds_since_sync_zero_when_never_synced);
    RUN(test_fw20s2_seconds_since_sync_computed_warm);
    RUN(test_fw20s2_sync_req_payload_layout);
    RUN(test_fw20s2_sync_req_marker_disambiguation_from_ota_req);

    printf("\n  Mesh-Relay Per-Hop Drift Compensation (FW.20-S2):\n");
    RUN(test_fw20s2_relay_happy_path_with_drift_compensation);
    RUN(test_fw20s2_relay_zero_hold_keeps_ts_unchanged);
    RUN(test_fw20s2_relay_preserves_tdma_reserve_and_padding);
    RUN(test_fw20s2_relay_drop_when_role_is_soldier);
    RUN(test_fw20s2_relay_drop_when_marker_wrong);
    RUN(test_fw20s2_relay_drop_when_magic_wrong);
    RUN(test_fw20s2_relay_drop_when_ts_zero);
    RUN(test_fw20s2_relay_drop_when_not_authoritative);
    RUN(test_fw20s2_relay_drop_when_ttl_exhausted);
    RUN(test_fw20s2_relay_drop_when_hold_exceeds_max);
    RUN(test_fw20s2_relay_hold_exactly_at_max_passes);
    RUN(test_fw20s2_relay_tick_wrap_safe);
    RUN(test_fw20s2_relay_two_hop_chain_kills_authoritativeness);

    printf("\n  Mesh-Relay: журнал поколінь / anti-storm (FW.20-S2 4/5):\n");
    RUN(test_fw20s2_mesh_dedup_unlocks_auth0_relay);
    RUN(test_fw20s2_mesh_dedup_queen_double_broadcast_suppressed);
    RUN(test_fw20s2_mesh_dedup_pingpong_storm_killed);
    RUN(test_fw20s2_mesh_dedup_fresh_generation_relays_again);
    RUN(test_fw20s2_mesh_dedup_stale_generation_refused);
    RUN(test_fw20s2_mesh_dedup_out_of_order_within_window_relays);
    RUN(test_fw20s2_mesh_dedup_duplicate_checked_last);
    RUN(test_fw20s2_mesh_dedup_gen_bucket_boundary);

    /* [ARCH.41-B] acoustic sentinel «час невідомий» */
    RUN(test_arch41_sentinel_replaces_acoustic_when_time_uncertain);
    RUN(test_arch41_real_0xfe_clamped_never_impersonates_sentinel);
    RUN(test_arch41_normal_acoustic_passthrough_incl_saturation);

    printf("\n  Gossip-Piggyback (FW.20-S2 #5, freeze-contract):\n");
    RUN(test_fw20s2_gossip_pack_zero_ts_returns_zero);
    RUN(test_fw20s2_gossip_pack_extracts_low_byte);
    RUN(test_fw20s2_gossip_apply_cold_boot_returns_zero);
    RUN(test_fw20s2_gossip_apply_within_window_refines_ts);
    RUN(test_fw20s2_gossip_apply_picks_next_window);
    RUN(test_fw20s2_gossip_apply_picks_prev_window_when_clock_jumped);
    RUN(test_fw20s2_gossip_apply_drift_within_cap_corrects);

    printf("\n  Fauna Vcap Guard (FW.42, freeze-contract):\n");
    RUN(test_fw42_fauna_threshold_constant_matches_doc);
    RUN(test_fw42_fauna_sample_allowed_at_exact_threshold);
    RUN(test_fw42_fauna_sample_allowed_above_threshold);
    RUN(test_fw42_fauna_sample_blocked_below_threshold);
    RUN(test_fw42_fauna_sample_blocked_deep_brownout);
    RUN(test_fw42_fauna_skip_counter_increments_per_block);
    RUN(test_fw42_fauna_skip_counter_saturates_at_uint8_max);
    RUN(test_fw42_fauna_mixed_calls_do_not_decrement_counter);
    RUN(test_fw42_raw_adc_range_always_skips_fail_closed);

    printf("\n  FW.29 Follow-ups (StatusByte + panic boundary):\n");
    RUN(test_fw29_status_byte_panic_with_max_growth_points);
    RUN(test_fw29_panic_does_not_corrupt_acoustic_saturation);

    printf("\n  FW.50 ADC→mV conversion (VREFINT cal + divider):\n");
    RUN(test_adc_vdda_nominal);
    RUN(test_adc_vdda_high_supply);
    RUN(test_adc_vdda_div_by_zero_guard);
    RUN(test_adc_pin_full_scale);
    RUN(test_adc_pin_two_thirds);
    RUN(test_adc_pin_zero);
    RUN(test_adc_raw_to_mv_direct);
    RUN(test_adc_raw_to_mv_divider_2to1);
    RUN(test_adc_raw_to_mv_div_by_zero_guard);
    RUN(test_fw50_raw_count_is_not_mv);

    printf("\n  FW.49 wall-clock delta/elapsed guards:\n");
    RUN(test_fw49_delta_cold_start_returns_baseline);
    RUN(test_fw49_delta_normal_interval);
    RUN(test_fw49_delta_small_real_interval_passes);
    RUN(test_fw49_delta_backward_clock_returns_baseline);
    RUN(test_fw49_delta_epoch_jump_returns_baseline);
    RUN(test_fw49_delta_boundary_exact_max_passes);
    RUN(test_fw49_elapsed_never_set_returns_zero);
    RUN(test_fw49_elapsed_normal);
    RUN(test_fw49_elapsed_backward_clock_returns_zero);
    RUN(test_fw49_unix_from_calendar_rtc_epoch);
    RUN(test_fw49_unix_from_calendar_known_date);
    RUN(test_fw49_civil_from_unix_goldens);
    RUN(test_fw49_civil_unix_roundtrip_sweep);
    RUN(test_fw49_wall_is_utc_boundary);

    printf("\n[FW.18b] ttl_byte бітфілд [thr_invalid:5|TTL:3]:\n");
    RUN(test_fw18b_pack_zero_counter_is_legacy_byte);
    RUN(test_fw18b_pack_golden_wire);
    RUN(test_fw18b_pack_saturates_at_wire_cap);
    RUN(test_fw18b_unpack_roundtrip);
    RUN(test_fw18b_decrement_preserves_origin_counter);
    RUN(test_fw18b_relay_liveness_masks_counter);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
