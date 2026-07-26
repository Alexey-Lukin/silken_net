#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""06_uart_dma_ears.py — [bench] FW.3 silicon-confirm: DMA-вуха UART RX-кільця.

Логіка кільця host-доведена (test_uart_rx_ring.c: гонки знімка, wrap,
overrun, інтеграція з токенайзером); тут — лише те, що може відповісти
кремній (RUNBOOK 5.4): DMAMUX-роутинг USART1_RX, поведінка NDTR/TC на
реальному DMA, межовий байт рівно-повного кільця (гонка TC-IRQ ↔
NDTR-reload).

    06_uart_dma_ears.py --plan
    06_uart_dma_ears.py --port /dev/tty.usbserial-XXX --elf <queen.elf>

Працює проти БОЙОВОГО образу Королеви: читає лише producer-сторону
(uart_rx_wraps + CNDTR) по SWD без halt — Королева always-on (без STOP2),
тож attach безпечний, а main loop і drain читача цих лічильників не
торкаються. Хост грає роль модема (USB-UART 3.3В → USART1 RX); AT-балачку
плати у відповідь скрипт ігнорує.
"""

from __future__ import annotations

import argparse
import sys
import time

SIZE = 512  # UART_RX_RING_SIZE (queen/main.c)

# RM0461 / stm32wle5xx.h: DMA1_Channel1_BASE = 0x40020008
DMA1_CCR1 = 0x40020008
DMA1_CNDTR1 = 0x4002000C
DMA1_CPAR1 = 0x40020010
DMA1_CMAR1 = 0x40020014
DMAMUX1_C0CR = 0x40020800
DMAREQ_USART1_RX = 0x11  # LL_DMAMUX_REQ_USART1_RX
USART1_RDR = 0x40013824
CCR_EN, CCR_CIRC = 1 << 0, 1 << 5

PLAN = """\
— план FW.3 DMA-вуха (RUNBOOK 5.4) —
1. Бойова прошивка Королеви (00_flash.sh). SIM7070G ВІД'ЄДНАТИ від USART1;
   замість нього USB-UART 3.3В: адаптер TX → USART1 RX Королеви (розводка —
   02_05), спільний GND. 115200 8N1.
2. ST-LINK на SWD; pyocd attach без halt (Королева always-on — main loop
   живе, нам потрібні лише producer-лічильники).
3. 06_uart_dma_ears.py --port <usb-uart> --elf <queen.elf>
   (ELF потрібен заради адрес static-символів uart_rx_wraps/uart_rx_buf;
   stripped образ → задай --addr-wraps/--addr-buf руками з map-файлу.)
4. Вердикт ✅ ROUTE/FEED/WRAP/BOUNDARY → закрити 👤 DMA-частину 00_07 FW.3;
   реальні таймінги SIM7070G — окремо, RUNBOOK 5.1/5.2 (minicom).
"""


def abs_pos(target, wraps_addr: int) -> tuple[int, int, int]:
    """Дзеркало Uart_Ring_Sync: wraps двічі довкола NDTR — SWD-читання так
    само не атомарні, як читання M4 між IRQ."""
    while True:
        w1 = target.read32(wraps_addr)
        nd = target.read32(DMA1_CNDTR1) & 0xFFFF
        w2 = target.read32(wraps_addr)
        if w1 == w2:
            return w2 * SIZE + (SIZE - nd), nd, w2


def settle(target, wraps_addr: int) -> tuple[int, int, int]:
    """Чекає, поки позиція перестане рухатись (хвіст DMA дописався)."""
    prev = abs_pos(target, wraps_addr)
    while True:
        time.sleep(0.05)
        cur = abs_pos(target, wraps_addr)
        if cur[0] == prev[0]:
            return cur
        prev = cur


def feed(ser, n: int) -> None:
    ser.write(bytes((i & 0xFF) for i in range(n)))
    ser.flush()


def phase_route(target, buf_addr: int) -> bool:
    ccr = target.read32(DMA1_CCR1)
    req = target.read32(DMAMUX1_C0CR) & 0xFF
    cpar = target.read32(DMA1_CPAR1)
    cmar = target.read32(DMA1_CMAR1)
    checks = [
        (f"DMAMUX C0 DMAREQ_ID = 0x{req:02X} (треба 0x11 USART1_RX)", req == DMAREQ_USART1_RX),
        ("CCR1.EN — канал увімкнено", bool(ccr & CCR_EN)),
        ("CCR1.CIRC — circular", bool(ccr & CCR_CIRC)),
        (f"CPAR1 = 0x{cpar:08X} (USART1->RDR)", cpar == USART1_RDR),
        (f"CMAR1 = 0x{cmar:08X} (uart_rx_buf)", cmar == buf_addr),
    ]
    ok = True
    for label, passed in checks:
        print(f"  {'✅' if passed else '❌'} {label}")
        ok &= passed
    return ok


def phase_boundary(target, ser, wraps_addr: int, rounds: int) -> bool:
    """Серце FW.3-residual: потік закінчується РІВНО на межовому байті
    повного кільця — TC і NDTR-reload спрацьовують без споживача поруч.
    Просідання позиції у живих семплах (NDTR вже reload, wraps++ ще в
    дорозі) — законна IRQ-латентність, у прошивці її гасить монотонний
    clamp (uart_rx_ring.h); фейл — лише якщо межовий байт загубився чи
    задвоївся у НЕРУХОМІЙ позиції."""
    ok = True
    for rnd in range(1, rounds + 1):
        pos0, _, w0 = settle(target, wraps_addr)
        to_boundary = SIZE - (pos0 % SIZE)
        feed(ser, to_boundary)
        dips = 0
        peak = pos0
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            cur, _, _ = abs_pos(target, wraps_addr)
            if cur < peak:
                dips += 1
            peak = max(peak, cur)
            if cur == pos0 + to_boundary:
                break
        pos1, nd1, w1 = settle(target, wraps_addr)
        exact = pos1 == pos0 + to_boundary
        wrapped = w1 == w0 + 1
        note = f" (IRQ-латентність спіймана у {dips} семплах — клампиться)" if dips else ""
        print(f"  раунд {rnd}: +{to_boundary}Б до межі → wraps {w0}→{w1}, "
              f"NDTR={nd1}, позиція {'точна' if exact else 'РОЗІЙШЛАСЬ'}{note}")
        if not exact:
            print(f"    ❌ очікував {pos0 + to_boundary}, кремній дає {pos1} — "
                  f"межовий байт загубився/задвоївся; неси у 00_07 FW.3")
        if not wrapped:
            print(f"    ❌ TC не дав рівно +1 wrap ({w0}→{w1})")
        ok &= exact and wrapped
    return ok


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--elf")
    p.add_argument("--target", default="stm32wle5jcix")
    p.add_argument("--rounds", type=int, default=6)
    p.add_argument("--addr-wraps", type=lambda s: int(s, 0))
    p.add_argument("--addr-buf", type=lambda s: int(s, 0))
    p.add_argument("--plan", action="store_true")
    args = p.parse_args()

    if args.plan or not args.port:
        print(PLAN)
        return 0

    try:
        import serial  # type: ignore
        from pyocd.core.helpers import ConnectHelper  # type: ignore
    except ImportError as exc:
        print(f"❌ бракує інструмента ({exc.name}) — pip install pyserial pyocd; або --plan")
        return 1

    session = ConnectHelper.session_with_chosen_probe(
        target_override=args.target, options={"connect_mode": "attach"})
    if session is None:
        print("❌ SWD-проба не знайдена — перевір ST-LINK")
        return 2

    with session, serial.Serial(args.port, args.baud, timeout=1.0) as ser:
        target = session.target
        wraps_addr, buf_addr = args.addr_wraps, args.addr_buf
        if args.elf and not (wraps_addr and buf_addr):
            from pyocd.debug.elf.symbols import ELFSymbolProvider  # type: ignore
            target.elf = args.elf
            sym = ELFSymbolProvider(target.elf)
            wraps_addr = wraps_addr or sym.get_symbol_value("uart_rx_wraps")
            buf_addr = buf_addr or sym.get_symbol_value("uart_rx_buf")
        if not (wraps_addr and buf_addr):
            print("❌ адреси uart_rx_wraps/uart_rx_buf не знайдено — "
                  "дай --elf із символами або --addr-wraps/--addr-buf з map")
            return 1

        ser.reset_input_buffer()  # AT-балачка плати нас не цікавить

        print("— ROUTE: регістри DMA/DMAMUX (init-глю на кремнії) —")
        if not phase_route(target, buf_addr):
            print("❌ роутинг не зійшовся — MX_USART1_RX_DMA_Init проти кремнію")
            return 1

        print("— FEED: зсув позиції рівно на K —")
        k = 37
        pos0, _, _ = settle(target, wraps_addr)
        feed(ser, k)
        pos1, _, _ = settle(target, wraps_addr)
        if pos1 - pos0 != k:
            print(f"❌ надіслав {k}Б, кільце зрушило на {pos1 - pos0} — "
                  f"{'немає сигналу: перевір TX→RX проводку' if pos1 == pos0 else 'байти губляться'}")
            return 2 if pos1 == pos0 else 1
        print(f"  ✅ +{k}Б ≡ +{k} позиції")

        print(f"— WRAP+BOUNDARY: межовий байт, {args.rounds} раундів —")
        if not phase_boundary(target, ser, wraps_addr, args.rounds):
            return 1

    print("✅ DMA-вуха підтверджено кремнієм: роутинг, NDTR/TC, межовий байт")
    print("   → закрити DMA-частину 👤-bench у 00_07 FW.3; таймінги SIM7070G —")
    print("   окремий рядок (RUNBOOK 5.1/5.2); SIM7070G повернути на USART1.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
