#!/usr/bin/env python3
"""05_parity_dump.py — [bench] FW.55 silicon-confirm: parity-дамп плати ↔ host-голден.

QEMU-нога вже довела byte-exact ARM↔x86 на ISA-рівні + фіт у 64КБ SRAM
(клас B, 03_01 §12.7); тут — останнє «той самий дамп на кремнії» (клас C,
RUNBOOK 2.3). Плата стрімить раунди нескінченно (PARITY-BEGIN → C-лінії →
PARITY-COMPLETE → heap/stack звіт) — скрипт чіпляється за перший BEGIN,
тож порядок із reset'ом плати неважливий.

    05_parity_dump.py --plan                       # кроки
    05_parity_dump.py --port /dev/tty.usbmodemXXX  # дамп + вердикт

Голден: firmware/build-sim/host.txt (народжує qemu_parity.sh — host-нога
працює і без локального qemu). byte-exact → FW.7/FW.19/FW.55 остаточно.
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GOLDEN = REPO / "firmware" / "build-sim" / "host.txt"

PLAN = """\
— план FW.55 silicon-confirm (RUNBOOK 2.3) —
1. firmware/scripts/qemu_parity.sh — host-голден (build-sim/host.txt) +
   parity_wle5.elf; працює і без локального qemu.
2. firmware/scripts/bench/00_flash.sh --elf firmware/build-sim/parity_wle5.elf --execute
3. 05_parity_dump.py --port /dev/tty.usbmodem*  (ST-LINK VCP NUCLEO-WL55JC, 115200)
4. byte-exact → ✅ silicon-confirm у 00_07 FW.55 (FW.7/FW.19 остаточно);
   плату перешити бойовим образом (00_flash.sh) — parity-runner займає flash.
"""


def collect_round(ser) -> tuple[list[str], list[str]] | None:
    """Чекає PARITY-BEGIN, збирає C-лінії до PARITY-COMPLETE + фіт-звіт після.

    None = тиша довша за timeout (немає прошивки/не той порт). Фолт на платі
    видно як PARITY-ABORT у потоці — раунд переривається з вердиктом 2.
    """
    cases: list[str] = []
    fit: list[str] = []
    in_round = False
    while True:
        raw = ser.readline()
        if not raw:
            return None
        line = raw.decode(errors="replace").rstrip()
        print(line)
        if line.startswith("PARITY-BEGIN"):
            cases.clear()
            in_round = True
            continue
        if not in_round:
            continue
        if line.startswith("PARITY-ABORT"):
            print("❌ плата зловила фолт/VM-збій посеред раунду — дивись маркер вище")
            sys.exit(2)
        if line.startswith("C"):
            cases.append(line)
            continue
        if line.startswith("PARITY-COMPLETE"):
            for _ in range(2):  # PARITY-STACK + PARITY-HEAP одразу після
                raw2 = ser.readline()
                if not raw2:
                    break
                line2 = raw2.decode(errors="replace").rstrip()
                print(line2)
                if line2.startswith("PARITY-"):
                    fit.append(line2)
            return (cases, fit)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=120.0,
                   help="на РЯДОК; кейс на 16 МГц soft-double — секунди")
    p.add_argument("--golden", type=Path, default=GOLDEN)
    p.add_argument("--plan", action="store_true")
    args = p.parse_args()

    if args.plan or not args.port:
        print(PLAN)
        return 0

    try:
        import serial  # type: ignore
    except ImportError:
        print("❌ pyserial не встановлено (pip install pyserial) — або --plan")
        return 1

    if not args.golden.exists():
        print(f"❌ голден відсутній: {args.golden} — спершу firmware/scripts/qemu_parity.sh")
        return 1
    golden = [ln for ln in args.golden.read_text().splitlines() if ln.startswith("C")]

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        round_ = collect_round(ser)

    if round_ is None:
        print("❌ маркери не прийшли — перевір порт/прошивку (00_flash.sh) і baud")
        return 2
    cases, fit = round_

    if cases != golden:
        print(f"❌ КРЕМНІЙ ≠ host: дамп розійшовся ({len(cases)} ↔ {len(golden)} ліній) — "
              f"це знахідка рівня FW.7/FW.19, неси diff у 00_07:")
        sys.stdout.writelines(difflib.unified_diff(
            golden, cases, "host_golden", "wle5_silicon", lineterm=""))
        print()
        return 1

    fit_note = ("; " + ", ".join(fit)) if fit else ""
    print(f"✅ КРЕМНІЙ ≡ host: {len(cases)} зчеплених кейсів byte-exact{fit_note}")
    print("   → silicon-confirm здобуто: ✅ FW.55 (закриває FW.7/FW.19 остаточно) у 00_07;")
    print("   → плату перешити бойовим образом (00_flash.sh).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
