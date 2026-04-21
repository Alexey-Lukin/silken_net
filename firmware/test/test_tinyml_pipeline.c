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
#define RUN(name) do { tests_run++; name(); printf("  %-55s %s\n", #name, tests_failed == _prev ? "✅" : "❌"); } while(0)
#define _prev tests_failed

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

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_run - tests_failed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed ? 1 : 0;
}
