/*
 * test_tinyml_pipeline.c — Host-based unit tests for TinyML acoustic pipeline.
 *
 * Tests the audio processing path: vibration detection → DMA → normalization →
 * inference (mocked) → event classification → acoustic_events accumulation.
 *
 * Mock Run_Inference() simulates all 4 TinyML output classes:
 *   0: Silence, 1: Wind, 2: Cavitation (xylem), 3: Chainsaw/Tamper
 *
 * Build: make -C firmware/test tinyml
 *
 * Coverage:
 *   - Normalization boundary values (0, 2047, 4095)
 *   - Confidence threshold (0.80) edge cases
 *   - All 4 event classes
 *   - acoustic_events saturation at 255 (FW.12/FW.22)
 *   - vibration_detected race condition guard (FW.11)
 *   - Emergency TX trigger on chainsaw detection
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#include "hal_mock.h"

/* ══════════════════════════════════════════════════════════════════
 * CONSTANTS (from soldier/main.c)
 * ══════════════════════════════════════════════════════════════════ */
#define CONFIDENCE_THRESHOLD  0.80f
#define AUDIO_BUFFER_SIZE     512
#define VCAP_LISTEN_THRESHOLD 2800
#define PANIC_TTL             5

/* [FW.18] Dual-threshold TinyML constants — mirror firmware/soldier/main.c §1.5а */
#define TINYML_DEFAULT_WARNING       0.60f
#define TINYML_DEFAULT_CRITICAL      0.85f
#define TINYML_THRESHOLD_MIN_VALID   0.01f
#define TINYML_THRESHOLD_MAX_VALID   0.99f
#define TINYML_WARNING_ESCALATION    3

/* TinyML event class IDs */
#define ML_CLASS_SILENCE    0
#define ML_CLASS_WIND       1
#define ML_CLASS_CAVITATION 2
#define ML_CLASS_CHAINSAW   3

/* ══════════════════════════════════════════════════════════════════
 * MOCK STATE — simulates Run_Inference() behavior
 * ══════════════════════════════════════════════════════════════════ */
static uint8_t mock_ml_event_id = 0;
static float   mock_ml_confidence = 0.0f;
static int     mock_inference_called = 0;
static int     mock_emergency_tx_called = 0;

/* Mock Run_Inference: returns predetermined class and confidence */
static uint8_t Run_Inference(float* buffer, float* confidence)
{
    (void)buffer;
    mock_inference_called++;
    *confidence = mock_ml_confidence;
    return mock_ml_event_id;
}

/* Mock Trigger_Emergency_LoRa_TX */
static void Trigger_Emergency_LoRa_TX(void)
{
    mock_emergency_tx_called++;
}

/* Reset all mocks before each test */
static void reset_mocks(void)
{
    mock_ml_event_id = 0;
    mock_ml_confidence = 0.0f;
    mock_inference_called = 0;
    mock_emergency_tx_called = 0;
}

/* ══════════════════════════════════════════════════════════════════
 * EXTRACTED PURE-LOGIC FUNCTIONS
 * ══════════════════════════════════════════════════════════════════ */

/* Normalization: 12-bit ADC raw → [0.0, 1.0] float */
static void Normalize_Audio(uint16_t* raw, float* normalized, int count)
{
    for (int i = 0; i < count; i++) {
        normalized[i] = (float)raw[i] / 4095.0f;
    }
}

/* TinyML classification pipeline (extracted from main.c Phase 1.5) */
static void Process_TinyML(
    float* audio_buffer,
    uint16_t* acoustic_events,
    int* emergency_triggered)
{
    uint8_t ml_event_id = 0;
    float ml_confidence = 0.0f;

    ml_event_id = Run_Inference(audio_buffer, &ml_confidence);

    if (ml_confidence > CONFIDENCE_THRESHOLD) {
        if (ml_event_id == ML_CLASS_CAVITATION) {
            (*acoustic_events)++;
        } else if (ml_event_id == ML_CLASS_CHAINSAW) {
            *emergency_triggered = 1;
            Trigger_Emergency_LoRa_TX();
        }
    }
}

/* ══════════════════════════════════════════════════════════════════
 * [FW.18] DUAL-THRESHOLD TINYML — pure-logic extraction
 *   Mirror of firmware/soldier/main.c §1.11 helpers and Phase 1.5 zones.
 *   IEEE 754 bit-copy uint32↔float for RTC roundtrip simulation.
 * ══════════════════════════════════════════════════════════════════ */

static inline uint32_t test_float_to_uint32(float f) {
    uint32_t u; memcpy(&u, &f, sizeof(u)); return u;
}
static inline float test_uint32_to_float(uint32_t u) {
    float f; memcpy(&f, &u, sizeof(f)); return f;
}

static float TinyML_Validate_Threshold(float raw, float fallback_default) {
    if (!isfinite(raw)) return fallback_default;
    if (raw < TINYML_THRESHOLD_MIN_VALID) return fallback_default;
    if (raw > TINYML_THRESHOLD_MAX_VALID) return fallback_default;
    return raw;
}

/* Production-visibility counter mirror — see firmware/soldier/main.c §1.11
 * (`tinyml_threshold_invalid_count`). Saturates at 255, reset by SRAM init. */
static uint8_t tinyml_threshold_invalid_count = 0;

static void TinyML_Apply_Thresholds(float warn_raw, float crit_raw,
                                     float* warn_out, float* crit_out) {
    float w = TinyML_Validate_Threshold(warn_raw, TINYML_DEFAULT_WARNING);
    float c = TinyML_Validate_Threshold(crit_raw, TINYML_DEFAULT_CRITICAL);

    uint8_t warn_rejected = (w != warn_raw);
    uint8_t crit_rejected = (c != crit_raw);
    uint8_t inverted      = !(w < c);

    if (warn_rejected || crit_rejected || inverted) {
        if (tinyml_threshold_invalid_count < 255) {
            tinyml_threshold_invalid_count++;
        }
    }

    if (inverted) {
        w = TINYML_DEFAULT_WARNING;
        c = TINYML_DEFAULT_CRITICAL;
    }
    *warn_out = w;
    *crit_out = c;
}

/* Dual-threshold decision: replicates the SILENCE/WARNING/CRITICAL zones
 * from firmware/soldier/main.c (FW.18). Updates acoustic_events (uint8_t
 * with saturating increment) and warning_counter (uint8_t saturating @ 255).
 * Returns 1 if Trigger_Emergency_LoRa_TX() was called this invocation. */
static int Process_TinyML_Dual(
    uint8_t ml_event_id,
    float ml_confidence,
    float warning_threshold,
    float critical_threshold,
    uint8_t* acoustic_events,
    uint8_t* warning_counter)
{
    int emergency = 0;
    if (ml_confidence >= critical_threshold) {
        /* CRITICAL ZONE */
        if (ml_event_id == ML_CLASS_CAVITATION) {
            if (*acoustic_events < 255) (*acoustic_events)++;
        } else if (ml_event_id == ML_CLASS_CHAINSAW) {
            if (*acoustic_events < 255) (*acoustic_events)++;
            Trigger_Emergency_LoRa_TX();
            emergency = 1;
        }
        *warning_counter = 0;
    } else if (ml_confidence >= warning_threshold) {
        /* WARNING ZONE */
        if (ml_event_id == ML_CLASS_CAVITATION || ml_event_id == ML_CLASS_CHAINSAW) {
            if (*acoustic_events < 255) (*acoustic_events)++;
            if (*warning_counter < 255) (*warning_counter)++;
            if (*warning_counter >= TINYML_WARNING_ESCALATION) {
                if (ml_event_id == ML_CLASS_CHAINSAW) {
                    Trigger_Emergency_LoRa_TX();
                    emergency = 1;
                }
                *warning_counter = 0;
            }
        }
    } else {
        /* SILENCE ZONE */
        *warning_counter = 0;
    }
    return emergency;
}

/* Acoustic events saturation for payload packing (FW.12/FW.22) */
static uint8_t Saturate_Acoustic_Events(uint16_t acoustic_events)
{
    return (uint8_t)(acoustic_events > 255 ? 255 : acoustic_events);
}

/* FW.11: NVIC-guarded vibration_detected read (race condition fix) */
static uint8_t Read_And_Clear_Vibration(volatile uint8_t* vibration_detected)
{
    /* In real firmware: HAL_NVIC_DisableIRQ(EXTI0_IRQn); */
    uint8_t vib = *vibration_detected;
    *vibration_detected = 0;
    /* In real firmware: HAL_NVIC_EnableIRQ(EXTI0_IRQn); */
    return vib;
}

/* ══════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK (minimal, same as other test files)
 * ══════════════════════════════════════════════════════════════════ */
static int tests_run = 0, tests_failed = 0;

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        printf("    FAIL: %s:%d — expected %d, got %d\n", __func__, __LINE__, (int)(b), (int)(a)); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_FLOAT_EQ(a, b, eps) do { \
    if (fabs((double)(a) - (double)(b)) > (eps)) { \
        printf("    FAIL: %s:%d — expected %.6f, got %.6f (eps=%.6f)\n", \
               __func__, __LINE__, (double)(b), (double)(a), (double)(eps)); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        printf("    FAIL: %s:%d — condition false\n", __func__, __LINE__); \
        tests_failed++; return; \
    } \
} while(0)

#define TEST(name) static void name(void)
#define RUN(name) do { int _prev = tests_failed; tests_run++; name(); printf("  %-55s %s\n", #name, tests_failed == _prev ? "✅" : "❌"); } while(0)

/* ══════════════════════════════════════════════════════════════════
 * 1. NORMALIZATION TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_normalize_zero_raw)
{
    uint16_t raw[1] = {0};
    float normalized[1];
    Normalize_Audio(raw, normalized, 1);
    ASSERT_FLOAT_EQ(normalized[0], 0.0f, 0.0001f);
}

TEST(test_normalize_max_raw_4095)
{
    uint16_t raw[1] = {4095};
    float normalized[1];
    Normalize_Audio(raw, normalized, 1);
    ASSERT_FLOAT_EQ(normalized[0], 1.0f, 0.0001f);
}

TEST(test_normalize_midpoint_2047)
{
    uint16_t raw[1] = {2047};
    float normalized[1];
    Normalize_Audio(raw, normalized, 1);
    ASSERT_FLOAT_EQ(normalized[0], 2047.0f / 4095.0f, 0.0001f);
    ASSERT_TRUE(normalized[0] > 0.49f && normalized[0] < 0.51f);
}

TEST(test_normalize_full_buffer_512)
{
    uint16_t raw[AUDIO_BUFFER_SIZE];
    float normalized[AUDIO_BUFFER_SIZE];

    /* Fill with ramp pattern */
    for (int i = 0; i < AUDIO_BUFFER_SIZE; i++) {
        raw[i] = (uint16_t)(i * 8); /* 0, 8, 16, ..., 4088 */
    }

    Normalize_Audio(raw, normalized, AUDIO_BUFFER_SIZE);

    /* All values must be in [0.0, 1.0] */
    for (int i = 0; i < AUDIO_BUFFER_SIZE; i++) {
        ASSERT_TRUE(normalized[i] >= 0.0f && normalized[i] <= 1.0f);
    }

    /* First element */
    ASSERT_FLOAT_EQ(normalized[0], 0.0f, 0.0001f);

    /* Last element: 511*8=4088 → 4088/4095 ≈ 0.9983 */
    ASSERT_FLOAT_EQ(normalized[511], 4088.0f / 4095.0f, 0.0001f);
}

TEST(test_normalize_boundary_value_1)
{
    uint16_t raw[1] = {1};
    float normalized[1];
    Normalize_Audio(raw, normalized, 1);
    ASSERT_FLOAT_EQ(normalized[0], 1.0f / 4095.0f, 0.0001f);
}

/* ══════════════════════════════════════════════════════════════════
 * 2. CONFIDENCE THRESHOLD TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_confidence_below_threshold_no_event)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 0.79f; /* Just below 0.80 threshold */

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);    /* No event counted */
    ASSERT_EQ(emergency, 0); /* No emergency */
    ASSERT_EQ(mock_inference_called, 1);
}

TEST(test_confidence_exactly_at_threshold_no_event)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 0.80f; /* Exactly at threshold — NOT above */

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);    /* 0.80 is NOT > 0.80 → no event */
    ASSERT_EQ(emergency, 0);
}

TEST(test_confidence_just_above_threshold_event)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 0.81f; /* Just above threshold */

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 1);    /* Event counted */
    ASSERT_EQ(emergency, 0);
}

TEST(test_confidence_max_1_0)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 1.0f; /* Perfect confidence */

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 1);
}

/* ══════════════════════════════════════════════════════════════════
 * 3. EVENT CLASS TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_class_silence_no_action)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_SILENCE;
    mock_ml_confidence = 0.95f;

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);
    ASSERT_EQ(emergency, 0);
}

TEST(test_class_wind_no_action)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_WIND;
    mock_ml_confidence = 0.95f;

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);
    ASSERT_EQ(emergency, 0);
}

TEST(test_class_cavitation_increments_events)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 5; /* Pre-existing events */
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 0.90f;

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 6); /* Incremented from 5 to 6 */
    ASSERT_EQ(emergency, 0);
}

TEST(test_class_chainsaw_triggers_emergency)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CHAINSAW;
    mock_ml_confidence = 0.95f;

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);    /* Chainsaw does NOT increment acoustic_events */
    ASSERT_EQ(emergency, 1); /* Emergency TX triggered */
    ASSERT_EQ(mock_emergency_tx_called, 1);
}

TEST(test_chainsaw_below_threshold_no_emergency)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CHAINSAW;
    mock_ml_confidence = 0.50f; /* Low confidence */

    Process_TinyML(audio, &events, &emergency);

    ASSERT_EQ(events, 0);
    ASSERT_EQ(emergency, 0);
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

/* ══════════════════════════════════════════════════════════════════
 * 4. ACOUSTIC_EVENTS SATURATION (FW.12/FW.22)
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_saturation_normal_value)
{
    ASSERT_EQ(Saturate_Acoustic_Events(42), 42);
}

TEST(test_saturation_at_255)
{
    ASSERT_EQ(Saturate_Acoustic_Events(255), 255);
}

TEST(test_saturation_above_255)
{
    ASSERT_EQ(Saturate_Acoustic_Events(256), 255);
}

TEST(test_saturation_uint16_max)
{
    ASSERT_EQ(Saturate_Acoustic_Events(65535), 255);
}

TEST(test_saturation_zero)
{
    ASSERT_EQ(Saturate_Acoustic_Events(0), 0);
}

TEST(test_accumulation_then_saturation)
{
    /* Simulate multiple cavitation events and then saturate for packing */
    uint16_t events = 0;
    for (int i = 0; i < 300; i++) {
        events++;
    }
    ASSERT_EQ(events, 300); /* uint16 can hold 300 */
    ASSERT_EQ(Saturate_Acoustic_Events(events), 255); /* Saturated for uint8 payload */
}

/* ══════════════════════════════════════════════════════════════════
 * 5. VIBRATION_DETECTED RACE CONDITION GUARD (FW.11)
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_vibration_read_and_clear)
{
    volatile uint8_t vib = 1;
    uint8_t result = Read_And_Clear_Vibration(&vib);
    ASSERT_EQ(result, 1);
    ASSERT_EQ(vib, 0);
}

TEST(test_vibration_not_set)
{
    volatile uint8_t vib = 0;
    uint8_t result = Read_And_Clear_Vibration(&vib);
    ASSERT_EQ(result, 0);
    ASSERT_EQ(vib, 0);
}

TEST(test_vibration_clear_is_atomic)
{
    /* Verify that after read-and-clear, the flag is zero even if
     * "another ISR" tries to read it immediately after */
    volatile uint8_t vib = 1;
    uint8_t first = Read_And_Clear_Vibration(&vib);
    uint8_t second = Read_And_Clear_Vibration(&vib);
    ASSERT_EQ(first, 1);
    ASSERT_EQ(second, 0); /* Must be 0 — no spurious re-trigger */
}

/* ══════════════════════════════════════════════════════════════════
 * 6. MULTI-CYCLE ACCUMULATION
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_multiple_cavitation_events_accumulate)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_event_id = ML_CLASS_CAVITATION;
    mock_ml_confidence = 0.95f;

    /* Simulate 10 consecutive cavitation detections */
    for (int i = 0; i < 10; i++) {
        Process_TinyML(audio, &events, &emergency);
    }

    ASSERT_EQ(events, 10);
    ASSERT_EQ(mock_inference_called, 10);
}

TEST(test_mixed_events_only_cavitation_counts)
{
    reset_mocks();
    float audio[AUDIO_BUFFER_SIZE] = {0};
    uint16_t events = 0;
    int emergency = 0;

    mock_ml_confidence = 0.95f;

    /* Silence */
    mock_ml_event_id = ML_CLASS_SILENCE;
    Process_TinyML(audio, &events, &emergency);

    /* Wind */
    mock_ml_event_id = ML_CLASS_WIND;
    Process_TinyML(audio, &events, &emergency);

    /* Cavitation */
    mock_ml_event_id = ML_CLASS_CAVITATION;
    Process_TinyML(audio, &events, &emergency);

    /* Chainsaw */
    mock_ml_event_id = ML_CLASS_CHAINSAW;
    Process_TinyML(audio, &events, &emergency);

    /* Only cavitation increments */
    ASSERT_EQ(events, 1);
    ASSERT_EQ(emergency, 1); /* Chainsaw triggered emergency */
    ASSERT_EQ(mock_inference_called, 4);
}

/* ══════════════════════════════════════════════════════════════════
 * 7. [FW.18] DUAL-THRESHOLD CONFIDENCE ZONES
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_dual_threshold_silence_zone_no_action)
{
    reset_mocks();
    uint8_t events = 5, warn = 2;
    int em = Process_TinyML_Dual(ML_CLASS_CAVITATION, 0.59f,
                                  TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                  &events, &warn);
    ASSERT_EQ(em, 0);
    ASSERT_EQ(events, 5);     /* Не змінено */
    ASSERT_EQ(warn, 0);       /* SILENCE → reset */
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

TEST(test_dual_threshold_warning_zone_at_boundary)
{
    /* confidence == warning_threshold → WARNING ZONE (≥, не >) */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    Process_TinyML_Dual(ML_CLASS_CAVITATION, TINYML_DEFAULT_WARNING,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(events, 1);     /* WARNING: acoustic_events++ */
    ASSERT_EQ(warn, 1);       /* WARNING: counter++ */
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

TEST(test_dual_threshold_critical_just_below_no_emergency)
{
    /* confidence 0.84 < critical 0.85 → WARNING for chainsaw, NOT Emergency */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    int em = Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.84f,
                                  TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                  &events, &warn);
    ASSERT_EQ(em, 0);
    ASSERT_EQ(events, 1);     /* Counted as WARNING */
    ASSERT_EQ(warn, 1);
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

TEST(test_dual_threshold_critical_zone_at_boundary)
{
    /* confidence == critical_threshold → CRITICAL (≥) */
    reset_mocks();
    uint8_t events = 0, warn = 2;
    int em = Process_TinyML_Dual(ML_CLASS_CHAINSAW, TINYML_DEFAULT_CRITICAL,
                                  TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                  &events, &warn);
    ASSERT_EQ(em, 1);         /* Emergency TX triggered */
    ASSERT_EQ(events, 1);
    ASSERT_EQ(warn, 0);       /* CRITICAL resets counter */
    ASSERT_EQ(mock_emergency_tx_called, 1);
}

TEST(test_dual_threshold_warning_escalation_chainsaw)
{
    /* 3 послідовних WARNING для chainsaw → ескальований Emergency TX */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    int em1 = Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                                   TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                   &events, &warn);
    ASSERT_EQ(em1, 0);
    ASSERT_EQ(warn, 1);
    int em2 = Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                                   TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                   &events, &warn);
    ASSERT_EQ(em2, 0);
    ASSERT_EQ(warn, 2);
    int em3 = Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                                   TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                   &events, &warn);
    ASSERT_EQ(em3, 1);                    /* Escalated */
    ASSERT_EQ(warn, 0);                   /* Reset after escalation */
    ASSERT_EQ(events, 3);                 /* All three counted */
    ASSERT_EQ(mock_emergency_tx_called, 1);
}

TEST(test_dual_threshold_warning_no_escalation_for_cavitation)
{
    /* Кавітація (class 2) у WARNING-зоні не ескалюється навіть при 5×.
     * Тільки chainsaw отримує fallback Emergency TX. */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    for (int i = 0; i < 5; i++) {
        Process_TinyML_Dual(ML_CLASS_CAVITATION, 0.70f,
                            TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                            &events, &warn);
    }
    ASSERT_EQ(mock_emergency_tx_called, 0);
    ASSERT_EQ(events, 5);
    /* warn буде або 2 (5%3 reset cycle), або інше значення — головне, що
     * за весь прогін Emergency TX не викликали жодного разу */
}

TEST(test_dual_threshold_silence_resets_counter_between_warnings)
{
    /* WARNING → WARNING → SILENCE (скидає лічильник) → WARNING → НЕ ескалюється */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(warn, 2);
    /* SILENCE — наприклад низька confidence */
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.30f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(warn, 0);     /* Reset */
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(warn, 1);     /* Тільки 1 — не ескалюємо */
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

TEST(test_dual_threshold_chainsaw_critical_resets_counter)
{
    /* WARNING-WARNING → потім різко CRITICAL → counter скидається на 0,
     * наступний WARNING починає новий рахунок з 1, не 3 */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.70f,
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(warn, 2);
    Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.95f,    /* CRITICAL */
                        TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                        &events, &warn);
    ASSERT_EQ(warn, 0);
    ASSERT_EQ(mock_emergency_tx_called, 1);
}

TEST(test_dual_threshold_silence_with_chainsaw_class_no_emergency)
{
    /* Низька confidence для chainsaw → SILENCE → НЕ Emergency, навіть для класу 3 */
    reset_mocks();
    uint8_t events = 0, warn = 0;
    int em = Process_TinyML_Dual(ML_CLASS_CHAINSAW, 0.10f,
                                  TINYML_DEFAULT_WARNING, TINYML_DEFAULT_CRITICAL,
                                  &events, &warn);
    ASSERT_EQ(em, 0);
    ASSERT_EQ(events, 0);
    ASSERT_EQ(mock_emergency_tx_called, 0);
}

/* ══════════════════════════════════════════════════════════════════
 * 8. [FW.18] THRESHOLD VALIDATION & RTC ROUNDTRIP
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_validate_threshold_in_range)
{
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(0.55f, 0.60f), 0.55f, 0.0001f);
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(0.95f, 0.60f), 0.95f, 0.0001f);
}

TEST(test_validate_threshold_below_min_falls_back)
{
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(0.005f, 0.60f), 0.60f, 0.0001f);
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(0.0f, 0.85f), 0.85f, 0.0001f);
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(-1.0f, 0.85f), 0.85f, 0.0001f);
}

TEST(test_validate_threshold_above_max_falls_back)
{
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(1.0f, 0.60f), 0.60f, 0.0001f);
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(99.0f, 0.85f), 0.85f, 0.0001f);
}

TEST(test_validate_threshold_nan_falls_back)
{
    float nan_val = (float)NAN;
    ASSERT_FLOAT_EQ(TinyML_Validate_Threshold(nan_val, 0.60f), 0.60f, 0.0001f);
}

TEST(test_apply_thresholds_cold_boot_zeros)
{
    /* RTC cold boot: read returns 0x00000000 = float 0.0f → both invalid */
    float w = 0, c = 0;
    float zero = test_uint32_to_float(0x00000000);
    TinyML_Apply_Thresholds(zero, zero, &w, &c);
    ASSERT_FLOAT_EQ(w, TINYML_DEFAULT_WARNING, 0.0001f);
    ASSERT_FLOAT_EQ(c, TINYML_DEFAULT_CRITICAL, 0.0001f);
}

TEST(test_apply_thresholds_inverted_falls_back_both)
{
    /* warn ≥ crit → invariant broken → BOTH default (atomic rollback) */
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);
    ASSERT_FLOAT_EQ(w, TINYML_DEFAULT_WARNING, 0.0001f);
    ASSERT_FLOAT_EQ(c, TINYML_DEFAULT_CRITICAL, 0.0001f);
}

TEST(test_apply_thresholds_equal_falls_back_both)
{
    /* warn == crit → no WARNING zone possible → defaults */
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.70f, 0.70f, &w, &c);
    ASSERT_FLOAT_EQ(w, TINYML_DEFAULT_WARNING, 0.0001f);
    ASSERT_FLOAT_EQ(c, TINYML_DEFAULT_CRITICAL, 0.0001f);
}

TEST(test_apply_thresholds_valid_pair_passes_through)
{
    /* Tropical forest config: WARNING=0.70, CRITICAL=0.90 — has been OTA-applied */
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.70f, 0.90f, &w, &c);
    ASSERT_FLOAT_EQ(w, 0.70f, 0.0001f);
    ASSERT_FLOAT_EQ(c, 0.90f, 0.0001f);
}

TEST(test_apply_thresholds_partial_corruption_one_default)
{
    /* warn corrupted (out of range) → warn=default; crit valid → crit kept,
     * but if default warn (0.60) ≥ crit valid (0.55) → BOTH default */
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(99.0f, 0.95f, &w, &c);
    /* warn=0.60 (default), crit=0.95 (valid). 0.60 < 0.95 → kept as is. */
    ASSERT_FLOAT_EQ(w, TINYML_DEFAULT_WARNING, 0.0001f);
    ASSERT_FLOAT_EQ(c, 0.95f, 0.0001f);
}

TEST(test_threshold_rtc_roundtrip_bit_exact)
{
    /* Save → Load via uint32 bit-copy (mirrors RTC_BKP_DR13/DR14 path) */
    float original_warn = 0.62f;
    float original_crit = 0.88f;
    uint32_t saved_w = test_float_to_uint32(original_warn);
    uint32_t saved_c = test_float_to_uint32(original_crit);
    /* simulate STOP2 + restore */
    float loaded_w = test_uint32_to_float(saved_w);
    float loaded_c = test_uint32_to_float(saved_c);
    ASSERT_FLOAT_EQ(loaded_w, original_warn, 0.0f);   /* bit-exact */
    ASSERT_FLOAT_EQ(loaded_c, original_crit, 0.0f);

    /* Apply with realistic inputs from RTC roundtrip */
    float w_applied = 0, c_applied = 0;
    TinyML_Apply_Thresholds(loaded_w, loaded_c, &w_applied, &c_applied);
    ASSERT_FLOAT_EQ(w_applied, 0.62f, 0.0001f);
    ASSERT_FLOAT_EQ(c_applied, 0.88f, 0.0001f);
}

/* ══════════════════════════════════════════════════════════════════
 * 9. [FW.18 — production-visibility] Threshold Invalid Counter
 *    Tracks how often TinyML_Apply_Thresholds rejected OTA payload
 *    (NaN, out-of-range, pair inversion). Backend piggybacks on
 *    telemetry → Grafana panel "OTA threshold corruption rate".
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_invalid_count_valid_pair_no_increment)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.55f, 0.85f, &w, &c);
    ASSERT_EQ(tinyml_threshold_invalid_count, 0);
}

TEST(test_invalid_count_increments_on_inversion)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);  /* warn > crit */
    ASSERT_EQ(tinyml_threshold_invalid_count, 1);
}

TEST(test_invalid_count_increments_on_nan_warn)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    float nan_val = (float)NAN;
    TinyML_Apply_Thresholds(nan_val, 0.85f, &w, &c);
    ASSERT_EQ(tinyml_threshold_invalid_count, 1);
}

TEST(test_invalid_count_increments_on_out_of_range_crit)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.55f, 99.0f, &w, &c);  /* crit > MAX_VALID */
    ASSERT_EQ(tinyml_threshold_invalid_count, 1);
}

TEST(test_invalid_count_increments_on_cold_boot_zeros)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    float zero = test_uint32_to_float(0x00000000);  /* RTC fresh boot */
    TinyML_Apply_Thresholds(zero, zero, &w, &c);
    /* Both raw=0 → below MIN_VALID → both rejected. Counter +1 (one call). */
    ASSERT_EQ(tinyml_threshold_invalid_count, 1);
}

TEST(test_invalid_count_accumulates_across_calls)
{
    tinyml_threshold_invalid_count = 0;
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.55f, 0.85f, &w, &c);    /* valid → 0 */
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);    /* inverted → 1 */
    TinyML_Apply_Thresholds(0.60f, 0.85f, &w, &c);    /* valid → 1 */
    TinyML_Apply_Thresholds((float)NAN, 0.85f, &w, &c); /* NaN → 2 */
    ASSERT_EQ(tinyml_threshold_invalid_count, 2);
}

TEST(test_invalid_count_saturates_at_255)
{
    tinyml_threshold_invalid_count = 254;
    float w = 0, c = 0;
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);  /* +1 → 255 */
    ASSERT_EQ(tinyml_threshold_invalid_count, 255);
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);  /* would be 256 → clamp */
    ASSERT_EQ(tinyml_threshold_invalid_count, 255);
    TinyML_Apply_Thresholds(0.90f, 0.50f, &w, &c);  /* still 255 */
    ASSERT_EQ(tinyml_threshold_invalid_count, 255);
}

/* ══════════════════════════════════════════════════════════════════
 * MAIN
 * ══════════════════════════════════════════════════════════════════ */
int main(void)
{
    int _prev = 0;

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  SilkenNet Firmware — TinyML Pipeline Unit Tests\n");
    printf("══════════════════════════════════════════════════════════════\n");

    printf("\n  Audio Normalization:\n");
    RUN(test_normalize_zero_raw);
    RUN(test_normalize_max_raw_4095);
    RUN(test_normalize_midpoint_2047);
    RUN(test_normalize_full_buffer_512);
    RUN(test_normalize_boundary_value_1);

    printf("\n  Confidence Threshold (0.80):\n");
    RUN(test_confidence_below_threshold_no_event);
    RUN(test_confidence_exactly_at_threshold_no_event);
    RUN(test_confidence_just_above_threshold_event);
    RUN(test_confidence_max_1_0);

    printf("\n  Event Classes (4 classes):\n");
    RUN(test_class_silence_no_action);
    RUN(test_class_wind_no_action);
    RUN(test_class_cavitation_increments_events);
    RUN(test_class_chainsaw_triggers_emergency);
    RUN(test_chainsaw_below_threshold_no_emergency);

    printf("\n  Acoustic Events Saturation (FW.12/FW.22):\n");
    RUN(test_saturation_normal_value);
    RUN(test_saturation_at_255);
    RUN(test_saturation_above_255);
    RUN(test_saturation_uint16_max);
    RUN(test_saturation_zero);
    RUN(test_accumulation_then_saturation);

    printf("\n  Vibration Race Condition Guard (FW.11):\n");
    RUN(test_vibration_read_and_clear);
    RUN(test_vibration_not_set);
    RUN(test_vibration_clear_is_atomic);

    printf("\n  Multi-Cycle Accumulation:\n");
    RUN(test_multiple_cavitation_events_accumulate);
    RUN(test_mixed_events_only_cavitation_counts);

    printf("\n  [FW.18] Dual-Threshold Confidence Zones:\n");
    RUN(test_dual_threshold_silence_zone_no_action);
    RUN(test_dual_threshold_warning_zone_at_boundary);
    RUN(test_dual_threshold_critical_just_below_no_emergency);
    RUN(test_dual_threshold_critical_zone_at_boundary);
    RUN(test_dual_threshold_warning_escalation_chainsaw);
    RUN(test_dual_threshold_warning_no_escalation_for_cavitation);
    RUN(test_dual_threshold_silence_resets_counter_between_warnings);
    RUN(test_dual_threshold_chainsaw_critical_resets_counter);
    RUN(test_dual_threshold_silence_with_chainsaw_class_no_emergency);

    printf("\n  [FW.18] Threshold Validation & RTC Roundtrip:\n");
    RUN(test_validate_threshold_in_range);
    RUN(test_validate_threshold_below_min_falls_back);
    RUN(test_validate_threshold_above_max_falls_back);
    RUN(test_validate_threshold_nan_falls_back);
    RUN(test_apply_thresholds_cold_boot_zeros);
    RUN(test_apply_thresholds_inverted_falls_back_both);
    RUN(test_apply_thresholds_equal_falls_back_both);
    RUN(test_apply_thresholds_valid_pair_passes_through);
    RUN(test_apply_thresholds_partial_corruption_one_default);
    RUN(test_threshold_rtc_roundtrip_bit_exact);

    printf("\n  [FW.18] OTA Threshold Invalid Counter (production-visibility):\n");
    RUN(test_invalid_count_valid_pair_no_increment);
    RUN(test_invalid_count_increments_on_inversion);
    RUN(test_invalid_count_increments_on_nan_warn);
    RUN(test_invalid_count_increments_on_out_of_range_crit);
    RUN(test_invalid_count_increments_on_cold_boot_zeros);
    RUN(test_invalid_count_accumulates_across_calls);
    RUN(test_invalid_count_saturates_at_255);

    (void)_prev;

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_run - tests_failed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed ? 1 : 0;
}
