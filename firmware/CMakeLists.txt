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

  # [FW.46] HAL compile-lane — перший справжній компайл soldier/queen main.c
  # проти PINNED stm32wlxx-hal-driver + cmsis-device-wl + subghz-phy
  # (firmware/extern/). Це ще НЕ повний .elf: тіла MX_*-init згенерує .ioc на
  # board-freeze (👤, wrapper-TU у hal_glue/ докладають порожні заглушки в той
  # самий TU) — але всі виклики/типи/HAL-API обох main.c верифікуються
  # компілятором у CI. Уже зловив: __HAL_RCC_CRYP_* (F4-стиль) ≠ WL
  # __HAL_RCC_AES_*. [Шлях A] radio.h тепер СПРАВЖНІЙ Semtech-header із
  # stm32-mw-subghz-phy @v1.5.0 (owned-стаб hal_glue/radio.h видалено);
  # radio.c/radio_driver.c НЕ компілюються (потребують radio_conf.h — .ioc).
  # Повний link (startup/ld/radio middleware .c) — HAL-фаза. docs/03_01 §12.4.
  option(SILKEN_WITH_HAL "HAL compile-lane: soldier/queen main.c vs vendored WL HAL" OFF)
  if(SILKEN_WITH_HAL)
    message(STATUS "[FW.46] SILKEN_WITH_HAL=ON — HAL compile-lane (docs/03_01 §12.4)")
    if(NOT DEFINED SILKEN_MRUBY_ARM_INC)
      # build-generated include (mruby/presym/…) — народжується ARM-збіркою mruby
      set(SILKEN_MRUBY_ARM_INC ${SILKEN_EXTERN}/mruby/build/arm-none-eabi/include
          CACHE PATH "mruby ARM build include dir")
    endif()
    add_library(hal_check OBJECT
      hal_glue/soldier_hal_check.c
      hal_glue/queen_hal_check.c)
    target_include_directories(hal_check PRIVATE
      hal_glue common
      ${SILKEN_EXTERN}/subghz-phy/radio_driver
      ${SILKEN_EXTERN}/cmsis-device-wl/Include
      ${SILKEN_EXTERN}/stm32wlxx-hal-driver/Inc
      ${CMSISCORE}/Include
      ${SILKEN_EXTERN}/mruby/include
      ${SILKEN_MRUBY_ARM_INC}
      ${SILKEN_EXTERN}/monocypher/src
      ${SILKEN_EXTERN}/monocypher/src/optional)
    # MRB_*-defines — дзеркало SILKEN_MIN_GEMS (One-Home: firmware/mruby/build_config.rb)
    target_compile_definitions(hal_check PRIVATE
      STM32WLE5xx USE_HAL_DRIVER
      MRB_NO_STDIO MRB_CONSTRAINED_BASELINE_PROFILE MRB_NO_BOXING)
    target_compile_options(hal_check PRIVATE -Wall -Wextra -Os)

    # [FW.2] CCM compile-варіант: ті самі два TU з -DFW2_CCM_ENABLED=1 —
    # гейтований CCM-тракт (двофазний CRYP-флоу, B0, GenerateAuthTAG,
    # 29B-flush, CCM RX-гілки) компілюється проти справжнього WL-HAL.
    # Раніше цей код НЕ бачив залізного HAL ніколи (гейт вирізав його і з
    # compile-lane) — саме так пережив рев'ю неіснуючий у WL
    # HAL_CRYPEx_AESCCM_Encrypt (знахідка 2026-07-03). Окремий таргет, щоб
    # [FW.26] RAM-гейт міряв БОЙОВИЙ hal_check (гейти 0), не фліпнутий.
    # + ARCH34_HELIUM_ENABLED=1: Queen KV-mount/Bind_Nvm-обв'язка (гейтована
    # гілка ARCH.34, HAL_FLASH_*) бачить WL-HAL цією ж лінзою.
    # + ARCH35_RING_ENABLED=1: гейтована ARCH.35 flash-ring-обв'язка (6 #if-блоків
    # у main.c, W25Q32 SPI) теж крос-компілюється цією лінзою — інакше дрейф
    # flash_ring.h API від stale call-sites = compile-fail лише при фліпі на bench
    # (queen_hal_check.c #include'ить main.c цілком; OBJECT-lib = compile-only, тож
    # RAM-гейт [FW.26] на БОЙОВОМУ hal_check не зачеплено).
    # + SEC21_MPU_ENABLED=1: гейтований Silken_Mpu_Apply (MPU->RBAR/RASR/CTRL,
    # CMSIS core) компілюється обабіч; реальний MemManage-trap — bench.
    # + ARCH26_CAD_ENABLED=1: гейтована CAD-гілка Солдата (ARCH.26 L3 —
    # StartCad-нюх, SetTxConfig extended-preamble, OnCadDone-реєстрація)
    # компілюється проти справжнього Semtech radio.h. Стеля: link-бомбу НЕ
    # ловить (OBJECT-lib compile-only) — справжній link-guard = FW.46 full-.elf.
    add_library(hal_check_ccm OBJECT
      hal_glue/soldier_hal_check.c
      hal_glue/queen_hal_check.c)
    target_include_directories(hal_check_ccm PRIVATE
      hal_glue common
      ${SILKEN_EXTERN}/subghz-phy/radio_driver
      ${SILKEN_EXTERN}/cmsis-device-wl/Include
      ${SILKEN_EXTERN}/stm32wlxx-hal-driver/Inc
      ${CMSISCORE}/Include
      ${SILKEN_EXTERN}/mruby/include
      ${SILKEN_MRUBY_ARM_INC}
      ${SILKEN_EXTERN}/monocypher/src
      ${SILKEN_EXTERN}/monocypher/src/optional)
    target_compile_definitions(hal_check_ccm PRIVATE
      STM32WLE5xx USE_HAL_DRIVER
      MRB_NO_STDIO MRB_CONSTRAINED_BASELINE_PROFILE MRB_NO_BOXING
      FW2_CCM_ENABLED=1
      ARCH34_HELIUM_ENABLED=1
      ARCH35_RING_ENABLED=1
      SEC21_MPU_ENABLED=1
      ARCH26_CAD_ENABLED=1)
    target_compile_options(hal_check_ccm PRIVATE -Wall -Wextra -Os)

    # [ARCH.34] LoRaMac-node compile-lane: vendored MAC (EU868/ClassA профіль
    # queen/lorawan_glue/lorawan_conf.h) + owned glue + adapter крос-компілюються
    # проти ARM/WL-HAL. Link-фаза (radio.c + startup) = board-freeze; host-smoke
    # цієї ж збірки — firmware/test helium_mac_smoke (справжній JoinRequest на
    # стаб-радіо). Submodule = НАШ форк v2.6.2-silken.1 (SF11/12 symbol-time
    # UB-фікс RegionCommonComputeSymbolTimeLoRa; upstream-PR — 00_07 ARCH.34).
    # ДЗЕРКАЛО: цей TU-список = LORAWAN_SRCS у firmware/test/Makefile —
    # міняєш тут → синкни там (інакше host-smoke ≠ ARM-lane).
    set(LORAWAN_MW ${SILKEN_EXTERN}/stm32-mw-lorawan)
    add_library(lorawan_mac_check OBJECT
      ${LORAWAN_MW}/Mac/LoRaMac.c
      ${LORAWAN_MW}/Mac/LoRaMacAdr.c
      ${LORAWAN_MW}/Mac/LoRaMacClassB.c
      ${LORAWAN_MW}/Mac/LoRaMacCommands.c
      ${LORAWAN_MW}/Mac/LoRaMacConfirmQueue.c
      ${LORAWAN_MW}/Mac/LoRaMacCrypto.c
      ${LORAWAN_MW}/Mac/LoRaMacParser.c
      ${LORAWAN_MW}/Mac/LoRaMacSerializer.c
      ${LORAWAN_MW}/Mac/Region/Region.c
      ${LORAWAN_MW}/Mac/Region/RegionCommon.c
      ${LORAWAN_MW}/Mac/Region/RegionEU868.c
      ${LORAWAN_MW}/Crypto/soft-se.c
      ${LORAWAN_MW}/Crypto/cmac.c
      ${LORAWAN_MW}/Crypto/lorawan_aes.c
      ${LORAWAN_MW}/LmHandler/LmHandler.c
      ${LORAWAN_MW}/LmHandler/NvmDataMgmt.c
      ${LORAWAN_MW}/LmHandler/Packages/LmhpCompliance.c
      ${LORAWAN_MW}/LmHandler/Packages/LmhpPackagesRegistration.c
      ${LORAWAN_MW}/Utilities/utilities.c
      queen/lorawan_glue/soft_timer.c
      queen/lorawan_glue/systime.c
      queen/lorawan_glue/lora_info.c
      queen/lorawan_glue/helium_mac.c
      common/flash_kv.c)
    target_include_directories(lorawan_mac_check PRIVATE
      queen/lorawan_glue queen common
      ${LORAWAN_MW}/Mac ${LORAWAN_MW}/Mac/Region ${LORAWAN_MW}/Crypto
      ${LORAWAN_MW}/LmHandler ${LORAWAN_MW}/LmHandler/Packages
      ${LORAWAN_MW}/Utilities
      ${SILKEN_EXTERN}/subghz-phy/radio_driver
      ${SILKEN_EXTERN}/cmsis-device-wl/Include
      ${SILKEN_EXTERN}/stm32wlxx-hal-driver/Inc
      ${CMSISCORE}/Include)
    target_compile_definitions(lorawan_mac_check PRIVATE
      STM32WLE5xx USE_HAL_DRIVER)
    target_compile_options(lorawan_mac_check PRIVATE -Wall -Wextra -Os
      -Wno-unused-parameter)
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
