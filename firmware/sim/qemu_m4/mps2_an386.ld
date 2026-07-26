/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * mps2_an386.ld — [FW.55] лінкер-карта QEMU mps2-an386 (Cortex-M4 SMM, AN386).
 *
 * CODE = ZBT SSRAM1 @ 0x00000000 (вектори+код+rodata+data; VMA==LMA — образ
 * вантажиться qemu -kernel напряму, без startup-копії). RAM = SSRAM2/3
 * @ 0x20000000 (heap для mruby-malloc знизу, стек згори). Це карта
 * СИМУЛЯТОРА, не STM32WLE5JC — flash-розкладка Солдата живе у 03_01.
 */
ENTRY(Reset_Handler)

MEMORY
{
  CODE (rwx) : ORIGIN = 0x00000000, LENGTH = 4M
  RAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 4M
}

SECTIONS
{
  .isr_vector : { KEEP(*(.isr_vector)) } > CODE

  .text : { *(.text*) } > CODE
  .rodata : { *(.rodata*) } > CODE

  /* libgcc unwinder посилається на ці символи навіть у чистому C */
  .ARM.exidx :
  {
    __exidx_start = .;
    *(.ARM.exidx*)
    __exidx_end = .;
  } > CODE

  .data : { *(.data*) } > CODE

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start__ = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end__ = .;
  } > CODE

  /* Heap росте від `end` (newlib _sbrk у syscalls.c) */
  .heap (NOLOAD) : { . = ALIGN(8); end = .; } > RAM

  __stack_top__ = ORIGIN(RAM) + LENGTH(RAM);
}
