# firmware/CMakeLists.txt — [FW.46] Reproducible ARM build for SilkenNet firmware.
#
# Owned-code foundation (docs/03_01 §12.4): cross-compiles the portable code we
# own — firmware/common/logmel.c under LOGMEL_USE_CMSIS against vendored
# CMSIS-DSP — and reports a real arm-none-eabi-size footprint. The full
# HAL-linked Soldier/Queen .elf (true total FW.26 size) is gated behind
# SILKEN_WITH_HAL=OFF until the CubeMX/HAL project is vendored.
#
# ARM build (cross):
#   cmake -B build -S firmware \
#     --toolchain firmware/cmake/arm-none-eabi.cmake \
#     -DARM_TOOLCHAIN_PATH=<abs>/bin -DCMSISCORE=<abs>/CMSIS_6/CMSIS/Core
#   cmake --build build           # → `size` target prints the footprint
#
# Host FFT packing-parity (Phase 4, no board):
#   cmake -B build-host -S firmware -DSILKEN_HOST_PARITY=ON \
#     -DCMSISCORE=<abs>/CMSIS_6/CMSIS/Core -DHOST=ON
#   ctest --test-dir build-host

cmake_minimum_required(VERSION 3.16)
project(silken_firmware C ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(SILKEN_EXTERN ${CMAKE_CURRENT_SOURCE_DIR}/extern)

# CMSIS-Core (cmsis_compiler.h etc.) — consumed by CMSIS-DSP. Overridable so CI
# / the dev box can point at the pinned submodule explicitly.
if(NOT DEFINED CMSISCORE)
  set(CMSISCORE ${SILKEN_EXTERN}/CMSIS_6/CMSIS/Core CACHE PATH "CMSIS-Core Include root")
endif()

# Vendored CMSIS-DSP (pinned submodule) — defines the CMSISDSP static lib and
# PUBLIC-exports its Include + ${CMSISCORE}/Include. HOST=ON selects the scalar
# path for the host parity build.
add_subdirectory(${SILKEN_EXTERN}/CMSIS-DSP ${CMAKE_BINARY_DIR}/cmsis-dsp EXCLUDE_FROM_ALL)

# --- Owned DSP front-end (the code we author) -----------------------------
add_library(silken_common STATIC common/logmel.c)
target_include_directories(silken_common PUBLIC common)
target_compile_definitions(silken_common PUBLIC LOGMEL_USE_CMSIS)
target_compile_options(silken_common PRIVATE -Wall -Wextra -Os)
target_link_libraries(silken_common PUBLIC CMSISDSP)

# --- [L1 QATT] Ed25519 batch-attestation (Monocypher, pinned submodule) ----
# Голос Королеви: software-Ed25519 для підпису CoAP-батчів (docs/05_02 ladder
# L1; pin-policy docs/03_01 §12.5). Окрема lib, щоб ARM-lane доводив
# крос-компіляцію і `size` бачив чесний footprint.
add_library(silken_attest STATIC
  ${SILKEN_EXTERN}/monocypher/src/monocypher.c
  ${SILKEN_EXTERN}/monocypher/src/optional/monocypher-ed25519.c)
target_include_directories(silken_attest PUBLIC
  ${SILKEN_EXTERN}/monocypher/src
  ${SILKEN_EXTERN}/monocypher/src/optional
  common)
target_compile_options(silken_attest PRIVATE -Wall -Wextra -Os)

if(CMAKE_CROSSCOMPILING)
  # Real ARM footprint of everything we own + the DSP lib it pulls in.
  # Honest owned-code footprint: silken_common is logmel.c (the DSP we author).
  # CMSIS-DSP links as-needed (gc-sections) so its true contribution is measured
  # at the final HAL link, not as the whole .a — see docs/03_01 §12.4.
  add_custom_target(size ALL
    COMMAND ${CMAKE_SIZE_TOOL} $<TARGET_FILE:silken_common> $<TARGET_FILE:silken_attest>
    DEPENDS silken_common silken_attest
    VERBATIM
    COMMENT "[FW.46] arm-none-eabi-size — owned DSP code + L1 attest lib (.text/.data/.bss)")

  # --- [FW.4] QEMU-M4 log-mel leg: golden-parity + stack high-water ---------
  # The same silken_common (LOGMEL_USE_CMSIS) on the real Cortex-M4 code path
  # (soft-float = the WLE5 ABI) under qemu-system-arm mps2-an386. Shares the
  # check core with the host ctest (sim/logmel_parity_core.h); wrapper script
  # firmware/scripts/qemu_logmel.sh, CI gate next to the FW.55 parity leg.
  add_executable(logmel_m4
    sim/qemu_m4/logmel_main.c
    sim/qemu_m4/startup.c
    sim/qemu_m4/syscalls.c)
  target_include_directories(logmel_m4 PRIVATE sim)
  target_link_libraries(logmel_m4 PRIVATE silken_common m)
  target_link_options(logmel_m4 PRIVATE
    "-T${CMAKE_CURRENT_SOURCE_DIR}/sim/qemu_m4/mps2_an386.ld"
    -nostartfiles "-Wl,--gc-sections")
  set_target_properties(logmel_m4 PROPERTIES
    SUFFIX ".elf"
    LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/sim/qemu_m4/mps2_an386.ld")

  # Full HAL-linked .elf — needs the vendored CubeMX project (HAL drivers,
  # linker script, startup, system_stm32wlxx.c). Wired in the HAL phase.
  option(SILKEN_WITH_HAL "Link the full Soldier/Queen .elf (needs vendored CubeMX project)" OFF)
  if(SILKEN_WITH_HAL)
    message(STATUS "[FW.46] SILKEN_WITH_HAL=ON — full .elf build (HAL phase, docs/03_01 §12.4)")
    # add_executable(soldier soldier/main.c ...) + linker script — deferred to HAL phase.
  endif()
else()
  # Host build: FFT packing-parity harness (Phase 4) — proves the CMSIS RFFT
  # output unpacking in logmel.c matches the golden vectors, on the host, with
  # no board. Float32-vs-double numerics absorbed by the harness tolerance.
  option(SILKEN_HOST_PARITY "Build the host CMSIS log-mel packing-parity test" OFF)
  if(SILKEN_HOST_PARITY)
    enable_testing()
    add_executable(test_logmel_cmsis test/test_logmel_cmsis.c)
    target_include_directories(test_logmel_cmsis PRIVATE sim)
    target_link_libraries(test_logmel_cmsis PRIVATE silken_common m)
    add_test(NAME logmel_cmsis_packing COMMAND test_logmel_cmsis)
  endif()
endif()
