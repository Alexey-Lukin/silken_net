---
name: test
description: "Skill for the Test area of silken_net. 119 symbols across 7 files."
---

# Test

119 symbols | 7 files | Cohesion: 84%

## When to Use

- Working with code in `firmware/`
- Understanding how main, main, main work
- Modifying test-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `firmware/test/test_bio_contract.c` | seed_to_xyz, calculate_z_axis_from_seed, test_z_axis_normal_conditions, test_z_axis_zero_seed, test_z_axis_max_seed (+41) |
| `firmware/test/test_soldier_logic.c` | test_uint32_to_float, Test_TinyML_Validate, Test_TinyML_Apply, Test_Handle_CMD_SET_AUDIO_THRESHOLDS, Test_Load_TinyML_From_RTC_Slot (+21) |
| `firmware/test/test_ccm.c` | Build_Reference_Packet, Try_Decrypt, test_mic_tamper_detected, test_aad_did_tamper_detected, test_aad_fc_tamper_detected (+9) |
| `firmware/test/test_seed_derivation.c` | hkdf_sha256, derive_k_seed, be64_load, signed_unit_float, initial_state (+7) |
| `firmware/test/test_queen_logic.c` | djb2_hash_bytes, Cmd_Dedup_Check, Test_Should_Handle_Rerequest, Error_Handler, Load_AES_Key (+4) |
| `firmware/test/test_tinyml_pipeline.c` | Run_Inference, Trigger_Emergency_LoRa_TX, Process_TinyML, Process_TinyML_Dual, TinyML_Validate_Threshold (+1) |
| `firmware/test/test_encryption.c` | Error_Handler, Load_AES_Key, Init_CRYP_ECB, Restore_ECB_Mode_Testable, Simulate_Flush_CBC_Then_ECB (+1) |

## Entry Points

Start here when exploring this area:

- **`main`** (Function) — `firmware/test/test_bio_contract.c:568`
- **`main`** (Function) — `firmware/test/test_seed_derivation.c:267`
- **`main`** (Function) — `firmware/test/test_ccm.c:380`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `main` | Function | `firmware/test/test_bio_contract.c` | 568 |
| `main` | Function | `firmware/test/test_seed_derivation.c` | 267 |
| `main` | Function | `firmware/test/test_ccm.c` | 380 |
| `seed_to_xyz` | Function | `firmware/test/test_bio_contract.c` | 113 |
| `calculate_z_axis_from_seed` | Function | `firmware/test/test_bio_contract.c` | 119 |
| `test_z_axis_normal_conditions` | Function | `firmware/test/test_bio_contract.c` | 216 |
| `test_z_axis_zero_seed` | Function | `firmware/test/test_bio_contract.c` | 223 |
| `test_z_axis_max_seed` | Function | `firmware/test/test_bio_contract.c` | 230 |
| `test_status_byte_encoding` | Function | `firmware/test/test_bio_contract.c` | 237 |
| `test_evaluate_pack_vm_error_byte` | Function | `firmware/test/test_bio_contract.c` | 305 |
| `test_beta_precision` | Function | `firmware/test/test_bio_contract.c` | 316 |
| `test_dt_step` | Function | `firmware/test/test_bio_contract.c` | 322 |
| `test_iterations_count` | Function | `firmware/test/test_bio_contract.c` | 328 |
| `test_z_axis_deterministic` | Function | `firmware/test/test_bio_contract.c` | 334 |
| `test_z_axis_different_seeds` | Function | `firmware/test/test_bio_contract.c` | 342 |
| `test_status_stress_growth_points_is_1` | Function | `firmware/test/test_bio_contract.c` | 350 |
| `test_status_anomaly_growth_points_is_0` | Function | `firmware/test/test_bio_contract.c` | 363 |
| `test_extreme_temp_acoustic_combo` | Function | `firmware/test/test_bio_contract.c` | 412 |
| `test_z_axis_sensitivity_to_temp` | Function | `firmware/test/test_bio_contract.c` | 422 |
| `test_z_axis_sensitivity_to_acoustic` | Function | `firmware/test/test_bio_contract.c` | 430 |

## How to Explore

1. `gitnexus_context({name: "main"})` — see callers and callees
2. `gitnexus_query({query: "test"})` — find related execution flows
3. Read key files listed above for implementation details
