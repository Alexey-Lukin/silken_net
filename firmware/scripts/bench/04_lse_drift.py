#!/usr/bin/env python3
"""04_lse_drift.py — [bench] LSE/RTC drift проти host-годинника (FW.49/FW.20).

pyOCD читає RTC-календар (TR/DR/SSR) через SWD без зупинки ядра і порівнює
з host time.time() (NTP-синхронізованим). Вихід — CSV t_host vs t_rtc →
drift ppm. Кімнатний прогін = FW.49 sanity; у термокамері ±60°C = FW.20 TRL-7.

    04_lse_drift.py --hours 24 [--out CSV]
    04_lse_drift.py --plan        # лише кроки, без заліза

Залежність: pip install pyocd && pyocd pack --install stm32wl
"""

from __future__ import annotations

import argparse
import csv
import sys
import time

# RM0461: RTC base 0x4000_2800; зсуви регістрів календаря
RTC_BASE = 0x40002800
RTC_TR = RTC_BASE + 0x00  # год/хв/сек BCD
RTC_DR = RTC_BASE + 0x04  # дата BCD
RTC_SSR = RTC_BASE + 0x28  # sub-second (down-counter)

PLAN = """\
— план LSE-drift вимірювання —
1. pyocd pack --install stm32wl            # CMSIS-pack (flash-алгоритм + регістри)
2. Підключити ST-LINK SWD; живлення плати від PPK2/LDO (НЕ міряти струм одночасно
   з SWD-сесією — дебаг-домен тягне мА і вбиває floor-вимір).
3. Скрипт раз на --interval c читає RTC_TR/DR/SSR (читання TR заморожує
   shadow-реєстри до читання DR — читаємо парою) і пише CSV поруч із host-часом.
4. Δ(t_rtc − t_host) лінійно фітиться → ppm; |ppm| > бюджету кварца+laod caps →
   дивись load-капи LSE (FW.49 bench bring-up).
"""


def bcd(v: int) -> int:
    return (v >> 4) * 10 + (v & 0x0F)


def rtc_seconds(tr: int, dr: int) -> int:
    """TR/DR BCD → секунди доби + груба дата (для drift достатньо монотонності)."""
    sec = bcd(tr & 0x7F)
    minute = bcd((tr >> 8) & 0x7F)
    hour = bcd((tr >> 16) & 0x3F)
    day = bcd(dr & 0x3F)
    return ((day * 24 + hour) * 60 + minute) * 60 + sec


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--hours", type=float, default=24.0)
    p.add_argument("--interval", type=float, default=60.0)
    p.add_argument("--out", default=None)
    p.add_argument("--plan", action="store_true")
    args = p.parse_args()

    if args.plan:
        print(PLAN)
        return 0

    try:
        from pyocd.core.helpers import ConnectHelper  # type: ignore
    except ImportError:
        print("❌ pyocd не встановлено (pip install pyocd) — або --plan")
        return 1

    out = args.out or f"bench_lse_drift_{int(time.time())}.csv"
    with ConnectHelper.session_with_chosen_probe(
        target_override="stm32wle5jcix"
    ) as session, open(out, "w", newline="") as fh:
        target = session.target
        w = csv.writer(fh)
        w.writerow(["t_host_unix", "rtc_day_seconds", "rtc_ssr"])

        t_end = time.time() + args.hours * 3600.0
        while time.time() < t_end:
            tr = target.read32(RTC_TR)  # freeze shadow
            dr = target.read32(RTC_DR)  # release shadow
            ssr = target.read32(RTC_SSR)
            w.writerow([f"{time.time():.3f}", rtc_seconds(tr, dr), ssr])
            fh.flush()
            time.sleep(args.interval)

    print(f"✅ {out} — фіт ppm: numpy.polyfit(t_host, t_rtc−t_rtc[0], 1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
