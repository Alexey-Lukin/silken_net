# firmware/mruby/build_config.rb — [FW.46] SilkenNet mruby build configuration.
#
# Builds:
#   `rake`                    → HOST (full `default` box) → bin/mrbc for codegen.
#   `SILKEN_MIN_HOST=1 rake`  → HOST with the MINIMAL gembox → libmruby.a for the
#                               C bytecode-VM harness (firmware/test/test_bytecode_vm.c).
#   `SILKEN_ARM_BUILD=1 rake` → arm-none-eabi (Cortex-M4F) MINIMAL libmruby.a —
#                               the firmware VM; footprint via arm-none-eabi-size.
#
# CRITICAL INVARIANTS (mruby 4.0.0 — verified against doc/mruby4.0.md + source):
#
#  • [FW.19 / FW.7] mrb_float MUST stay 64-bit double. NEVER define
#    MRB_USE_FLOAT32 (the flag is `MRB_USE_FLOAT32` in mruby ≥3.0 — the old
#    `MRB_USE_FLOAT` name is dead). float32 diverges the Lorenz Z and breaks the
#    firmware<->backend numeric-parity band (docs/03_04 §5, 00_07 FW.19).
#    Default (flag unset) → mrb_float == double. ✓
#
#  • NEVER enable MRB_WORD_BOXING / MRB_NAN_BOXING on the 32-bit MCU. On 32-bit
#    a word can't hold a 64-bit double, so word boxing has NO inline float — every
#    Lorenz double would be heap-allocated (RFloat) → GC thrash on the ~KB heap.
#    Default NO_BOXING keeps doubles inline in mrb_value (struct, ~16 B). ✓
#    (mruby 4.0.0 also moved method tables to .rodata + fixed several 32-bit
#     NO_BOXING bugs — strictly better than 3.x for this target.)

# Minimal on-device gem set. The mruby CORE already provides everything
# bio_contract.rb needs EXCEPT clamp: Float/Integer arithmetic, Numeric#abs and
# Integer#times (mrblib/numeric.rb), round (src/numeric.c), Array, the
# Comparable base. The ONLY extra is Comparable#clamp (mruby-compar-ext, used by
# growth_points). NO stdio / IO / stdlib / math — the stock `default-no-stdio`
# box is ~254 KB .text, OVER the 256 KB STM32WLE5JC Flash; this set is a fraction.
SILKEN_MIN_GEMS = lambda do |conf|
  conf.cc.defines << 'MRB_NO_STDIO'      # STM32 has no filesystem
  # [FW.55] mruby's own MCU profile: heap pages 256 objects (default 1024 ≈
  # tens of KB per page — the QEMU fit-gate caught mrb_open NOT fitting the
  # 64 KB WLE5 SRAM), no method cache, small khash. Math/ABI untouched —
  # parity dump stays byte-exact (gate re-proves on every CI run).
  conf.cc.defines << 'MRB_CONSTRAINED_BASELINE_PROFILE'
  conf.gem core: 'mruby-compar-ext'      # Comparable#clamp — the only non-core need
  # [FW.19] No MRB_USE_FLOAT32 + no MRB_WORD_BOXING/MRB_NAN_BOXING → double, inline.
end

# Host build (full default box) — produces bin/mrbc for tools/firmware/gen_bytecode.sh.
MRuby::Build.new do |conf|
  conf.toolchain
  conf.gembox 'default'
end

# Host build with the MINIMAL gembox — proves the minimal set actually RUNS the
# committed bytecode on the host (the real device VM path: mrb_load_irep).
if ENV['SILKEN_MIN_HOST'] == '1'
  MRuby::Build.new('host-min') do |conf|
    conf.toolchain
    SILKEN_MIN_GEMS.call(conf)
  end
end

# ARM cross with the MINIMAL gembox — the firmware VM; footprint via size.
if ENV['SILKEN_ARM_BUILD'] == '1'
  MRuby::CrossBuild.new('arm-none-eabi') do |conf|
    conf.toolchain :gcc

    prefix = ENV['ARM_PREFIX'] || 'arm-none-eabi-'
    conf.cc.command       = "#{prefix}gcc"
    conf.cxx.command      = "#{prefix}g++"
    conf.linker.command   = "#{prefix}gcc"
    conf.archiver.command = "#{prefix}ar"

    # WLE5 БЕЗ FPU (сімейство STM32WL) → soft-float: увесь float — __aeabi_*.
    cpu   = %w[-mcpu=cortex-m4 -mfloat-abi=soft -mthumb]
    flags = cpu + %w[-Os -ffunction-sections -fdata-sections]
    conf.cc.flags  = [ flags ]
    conf.cxx.flags = [ flags ]

    SILKEN_MIN_GEMS.call(conf)
  end
end
