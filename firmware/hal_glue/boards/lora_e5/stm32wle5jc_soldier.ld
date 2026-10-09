/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * stm32wle5jc_soldier.ld — [FW.46 ⚖️ 2026-10-06] лінкер-карта образу Солдата для
 * bench-carrier LoRa-E5 mini (STM32WLE5JC). Похідна від шаблону cmsis-device-wl
 * (Source/Templates/gcc/linker/STM32WLE5XX_FLASH.ld, Apache-2.0 —
 * firmware/extern/cmsis-device-wl/LICENSE.md): ті самі імена символів, яких чекає
 * вендорний startup_stm32wle5xx.s (_sidata · _sdata · _edata · _sbss · _ebss · _estack).
 * Змінено дві речі:
 *  · FLASH — лише сторінки 0..121 (0x08000000..0x0803CFFF, 244 КБ). Сторінки 122..127 —
 *    дані вузла: журнал Flash-KV, ідентичність, кластер (KPUB/KEYB), контракт OTA
 *    (docs/03_01 §2.3, «Розміщення»). Образ, що виріс би туди, стер би їх першою ж
 *    прошивкою; так лінкер упаде раніше.
 *  · RAM — SRAM1 + SRAM2 суцільно (64 КБ), як у карти FW.55 (firmware/sim/wle5_bench):
 *    купа (newlib _sbrk, soldier_lora_e5.c) росте від `end` до стек-резерву.
 */
ENTRY(Reset_Handler)

/* Стек-резерв — сусід виміру FW.55 (QEMU-нога: високий слід mruby VM під 12 КБ), плюс
 * пік Ed25519-печатки ≈ 2 КБ (03_06 §4) лягає в той самий запас. _sbrk читає АДРЕСУ
 * цього символа як число. */
__stack_reserve__ = 12288;

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 244K
  RAM   (rw)  : ORIGIN = 0x20000000, LENGTH = 64K   /* коду в RAM немає — без x (лише атрибут
                                                       лінкера; виконання з SRAM на кремнії знімає
                                                       MPU — SEC.21) */
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .isr_vector :
  {
    . = ALIGN(8);
    KEEP(*(.isr_vector))
    . = ALIGN(8);
  } > FLASH

  .text :
  {
    . = ALIGN(8);
    *(.text)
    *(.text*)
    *(.glue_7)
    *(.glue_7t)
    *(.eh_frame)
    KEEP (*(.init))
    KEEP (*(.fini))
    . = ALIGN(8);
    _etext = .;
  } > FLASH

  .rodata :
  {
    . = ALIGN(8);
    *(.rodata)
    *(.rodata*)
    . = ALIGN(8);
  } > FLASH

  /* READONLY (binutils ≥ 2.38, як у шаблоні): GCC позначає ці секції записуваними, і без
   * нього сегмент FLASH дістає прапор W — лінкер попереджає про RWX. */
  .ARM.extab (READONLY) : { *(.ARM.extab* .gnu.linkonce.armextab.*) } > FLASH

  .ARM (READONLY) :
  {
    __exidx_start = .;
    *(.ARM.exidx*)
    __exidx_end = .;
  } > FLASH

  .preinit_array (READONLY) :
  {
    PROVIDE_HIDDEN (__preinit_array_start = .);
    KEEP (*(.preinit_array*))
    PROVIDE_HIDDEN (__preinit_array_end = .);
  } > FLASH

  .init_array (READONLY) :
  {
    PROVIDE_HIDDEN (__init_array_start = .);
    KEEP (*(SORT(.init_array.*)))
    KEEP (*(.init_array*))
    PROVIDE_HIDDEN (__init_array_end = .);
  } > FLASH

  .fini_array (READONLY) :
  {
    PROVIDE_HIDDEN (__fini_array_start = .);
    KEEP (*(SORT(.fini_array.*)))
    KEEP (*(.fini_array*))
    PROVIDE_HIDDEN (__fini_array_end = .);
  } > FLASH

  _sidata = LOADADDR(.data);

  .data :
  {
    . = ALIGN(8);
    _sdata = .;
    *(.data)
    *(.data*)
    . = ALIGN(8);
    _edata = .;
  } > RAM AT> FLASH

  .bss (NOLOAD) :
  {
    . = ALIGN(8);
    _sbss = .;
    __bss_start__ = _sbss;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(8);
    _ebss = .;
    __bss_end__ = _ebss;
  } > RAM

  /* Купа росте від `end` (newlib _sbrk) до стек-резерву. */
  .heap (NOLOAD) :
  {
    . = ALIGN(8);
    PROVIDE ( end = . );
    PROVIDE ( _end = . );
  } > RAM

  .ARM.attributes 0 : { *(.ARM.attributes) }
}

/* Статика, що з'їла стек-резерв, — помилка лінку, а не стек, що мовчки топче .bss. */
ASSERT(end + __stack_reserve__ <= _estack, "[FW.46] статика не лишає стек-резерву під 64 КБ SRAM")
