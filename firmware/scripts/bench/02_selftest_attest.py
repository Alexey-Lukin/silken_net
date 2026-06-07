#!/usr/bin/env python3
"""02_selftest_attest.py — [bench] крипто-атестація кремнію (FW.2 CCM + sym KAT).

Host-сторона selftest'ів уже доведена (test_ccm_selftest/test_sym_selftest:
логіка + KAT-вектори коректні) — PASS на платі означає «кремній ≡ OpenSSL»,
FAIL однозначно вказує на HAL/кремній. Цей скрипт — оркестрація дня:
прошити атестаційну збірку → зібрати UART-звіт → вердикт.

    02_selftest_attest.py --plan                  # кроки (HAL-збірка ще 👤)
    02_selftest_attest.py --port /dev/ttyUSB0     # збір звіту з UART

Вердикт-граматика звіту (узгоджена з ccm_selftest.h report()): рядки
"<name> ✅"/"<name> FAIL" + фінальний "KAT vectors failed: N".
"""

from __future__ import annotations

import argparse
import re
import sys

PLAN = """\
— план крипто-атестації —
1. HAL-збірка attest-таргета (SILKEN_WITH_HAL=ON, після CubeMX-vendoring —
   00_07 FW.46 👤): main(), що кличе Ccm_Run_Self_Test + Sym_Run_Self_Test і
   друкує звіт у UART1 (та сама грамматика, що host-runner'и).
2. firmware/scripts/bench/00_flash.sh --elf attest.elf --execute
3. 02_selftest_attest.py --port /dev/ttyUSB0  → вердикт + лог-артефакт.
4. PASS → фліп FW2_CCM_ENABLED (firmware) + TELEMETRY_CCM_ENABLED (backend) за
   чеклистом 03_05 «FW.2 flip-checklist» (3 Queen RX-правки!).
"""

FINAL_RE = re.compile(r"KAT vectors failed:\s*(\d+)")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=30.0)
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

    fails: int | None = None
    lines: list[str] = []
    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        while True:
            raw = ser.readline()
            if not raw:
                break  # тиша довша за timeout
            line = raw.decode(errors="replace").rstrip()
            lines.append(line)
            print(line)
            m = FINAL_RE.search(line)
            if m:
                fails = int(m.group(1))
                break

    if fails is None:
        print("❌ фінальний рядок звіту не прийшов — перевір прошивку/порт")
        return 2
    if fails:
        print(f"❌ кремній/HAL: {fails} KAT-векторів впало — host-сторона чиста, "
              f"дивись HAL-виклик (B0/nonce) проти RM0461")
        return 1
    print("✅ КРЕМНІЙ АТЕСТОВАНО: усі KAT PASS → дозволено FW.2 flip (чеклист 03_05)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
