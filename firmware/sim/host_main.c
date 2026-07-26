// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * host_main.c — [FW.55] host-голден біт-parity прогону (x86/арх dev-бокса).
 * Той самий Parity_Run, що й на QEMU-M4 — дамп цього бінаря є еталоном,
 * з яким CI порівнює ARM-дамп byte-exact.
 *
 * Build/run: firmware/scripts/qemu_parity.sh
 */
#include <stdio.h>

#include "parity_core.h"

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    return Parity_Run();
}
