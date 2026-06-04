# firmware/cmake/arm-none-eabi.cmake — CMake toolchain file for STM32WLE5JC.
#
# [FW.46] Pinned bare-metal cross-compile toolchain for the SilkenNet firmware
# ARM build. Used by the owned-code foundation (firmware/common/*.c + mruby)
# and, later, the full HAL-linked .elf (SILKEN_WITH_HAL — docs/03_01 §12.4).
#
# Recommended toolchain: Arm GNU Toolchain 13.2.Rel1 (arm-none-eabi).
#   • discovered on PATH, or
#   • pass -DARM_TOOLCHAIN_PATH=/abs/path/to/bin at configure time.
# When the CubeMX/HAL phase lands, re-pin to match the CubeIDE toolchain.
#
# STM32WLE5JC core = Arm Cortex-M4 with single-precision FPU (FPv4-SP-D16).

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Bare-metal: there is no host startup/libc to link, so build a static library
# (not an executable) for CMake's compiler probe.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# --- Locate the cross toolchain -------------------------------------------
set(_tc_prefix arm-none-eabi-)
if(DEFINED ARM_TOOLCHAIN_PATH)
  set(_tc_bin "${ARM_TOOLCHAIN_PATH}/")
else()
  set(_tc_bin "")
endif()

set(CMAKE_C_COMPILER   "${_tc_bin}${_tc_prefix}gcc")
set(CMAKE_CXX_COMPILER "${_tc_bin}${_tc_prefix}g++")
set(CMAKE_ASM_COMPILER "${_tc_bin}${_tc_prefix}gcc")
set(CMAKE_OBJCOPY      "${_tc_bin}${_tc_prefix}objcopy" CACHE FILEPATH "objcopy")
set(CMAKE_SIZE_TOOL    "${_tc_bin}${_tc_prefix}size"    CACHE FILEPATH "size")

# --- CPU / FPU ------------------------------------------------------------
set(SILKEN_CPU_FLAGS "-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb")

set(CMAKE_C_FLAGS_INIT          "${SILKEN_CPU_FLAGS} -ffunction-sections -fdata-sections -Wall -Wextra")
set(CMAKE_CXX_FLAGS_INIT        "${SILKEN_CPU_FLAGS} -ffunction-sections -fdata-sections -Wall -Wextra")
set(CMAKE_ASM_FLAGS_INIT        "${SILKEN_CPU_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${SILKEN_CPU_FLAGS} -Wl,--gc-sections")

# Search the toolchain (not the host) for libs/headers; never for programs.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
