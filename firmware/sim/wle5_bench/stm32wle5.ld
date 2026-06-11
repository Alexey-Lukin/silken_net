/*
 * stm32wle5.ld — [FW.55] лінкер-карта РЕАЛЬНОГО STM32WLE5JC (bench-нога,
 * RUNBOOK 2.3). FLASH 256K @ 0x08000000, SRAM 64K @ 0x20000000 (SRAM1+SRAM2
 * суцільно). На відміну від mps2_an386.ld (карта симулятора, VMA==LMA) тут
 * справжній flash: .data має LMA у flash і копіюється startup'ом.
 *
 * Parity-runner — НЕ Soldier: бойова flash-розкладка (OTA 0x0803F000,
 * K_ota 0x0803E800) тут не діє; після дампу плату перешити бойовим образом.
 */
ENTRY(Reset_Handler)

/* One-Home розміру стек-резерву: _sbrk-ліміт (syscalls.c читає адресу цього
 * символа як число) + фіт-гейт у qemu_parity.sh (sed по цьому рядку). 12К —
 * над QEMU-виміряним високим слідом mruby VM; гейт ловить дрейф. */
__stack_reserve__ = 12288;

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
  .isr_vector : { KEEP(*(.isr_vector)) } > FLASH

  .text : { *(.text*) } > FLASH
  .rodata : { *(.rodata*) } > FLASH

  /* libgcc unwinder посилається на ці символи навіть у чистому C */
  .ARM.exidx :
  {
    __exidx_start = .;
    *(.ARM.exidx*)
    __exidx_end = .;
  } > FLASH

  .data :
  {
    . = ALIGN(4);
    __data_start__ = .;
    *(.data*)
    . = ALIGN(4);
    __data_end__ = .;
  } > RAM AT> FLASH
  __data_load__ = LOADADDR(.data);

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start__ = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end__ = .;
  } > RAM

  /* Heap росте від `end` (newlib _sbrk у syscalls.c) до стек-резерву */
  .heap (NOLOAD) : { . = ALIGN(8); end = .; } > RAM

  __stack_top__ = ORIGIN(RAM) + LENGTH(RAM);
}
