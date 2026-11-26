#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""07_ktr_stand.py — [bench:ktr-home] домашній стенд датчика пілота П3 (FW.70 · HW.54).

Шле консолі логера `M` раз на --interval секунд і пише кожен рядок `#M,…` у CSV поруч із
часом Mac і номером ВІКНА консолі. Плата без ключів після вікна (≤ 10 хв) скидається й
відкриває нове з банером `#S,…`; кожен старт заново калібрує АЦП, тож зсув нуля між вікнами
може скакнути — звідси колонка `segment`, і роздільність рахується ВСЕРЕДИНІ вікон. Нове вікно
чекає першого байта лише 5 с — тож на банер скрипт шле `M` одразу. Процедура, підключення й
прохід — docs/protocols/hardware/ktr_home_stand_sheet.md.

    07_ktr_stand.py --plan
    07_ktr_stand.py --port /dev/cu.usbserial-XXX --interval 10 --minutes 60 --out noise.csv
    07_ktr_stand.py --port /dev/cu.usbserial-XXX --interval 2 --count 5 --out step_05.csv

Підсумок у кінці (і на Ctrl-C): рядки, рядки з кодом ≠ 0, вікна, середнє показу й σ ВСЕРЕДИНІ
вікон після віднімання тренду кожного (присуд founder-а 2026-11-26, аркуш §1 А) — у відліках; у мкм перераховує
масштаб проходу головкою (аркуш §3 крок 3), а роздільність — 2σ.

Залежність: pip install pyserial (Python 3.9 теж — пряму рахує сам скрипт)
"""

from __future__ import annotations

import argparse
import csv
import math
import statistics
import sys
import time
from pathlib import Path

FIELDS = ("host_unix", "segment", "board_s", "reading", "rc", "exc_sum", "wiper_sum", "t_centi")
SILENCE_S = 20.0   # стільки без жодного `#M` — підказати RST (плата з ключами закриває консоль)

PLAN = """\
— план домашнього стенда KTR (аркуш docs/protocols/hardware/ktr_home_stand_sheet.md) —
1. Плата mini БЕЗ ключів, образ логера soldier_lora_e5 (RUNBOOK 2.1 з цим таргетом — не самотест), живлення USB-C; FT232RL на TX2/RX2
   (J1-13/14), 115200 8N1.
2. Датчик: верх доріжки → резистор 330 Ом → PA0 (J1-17), і окремим проводом верх → PB4 (J1-21);
   повзунок → PB3 (J1-20); низ → GND.
3. RST, банер `#S,…`; `M` руками протягом 5 с — код 0, показ рухається зі штоком (аркуш §3 крок 1).
4. Година шуму:   07_ktr_stand.py --port <порт> --interval 10 --minutes 60 --out noise.csv
5. Прохід головкою, на кожній точці: --interval 2 --count 5 --out step_<точка>.csv
6. Морозилка:     --interval 30 --minutes <кімната + морозилка + кімната> --out freezer.csv
"""


def parse_m(line: str) -> dict | None:
    """«#M,<секунди>,<показ|NA>,<код>,<збудження>,<повзунок>,<°C×100|NA>» → поля; інакше None."""
    p = line.strip().split(",")
    if len(p) != 7 or p[0] != "#M":
        return None
    try:
        return {
            "board_s": int(p[1]),
            "reading": None if p[2] == "NA" else int(p[2]),
            "rc": int(p[3]),
            "exc_sum": int(p[4]),
            "wiper_sum": int(p[5]),
            "t_centi": None if p[6] == "NA" else int(p[6]),
        }
    except ValueError:
        return None


def good(r: dict) -> bool:
    return r["rc"] == 0 and r["reading"] is not None


def detrended_sigma(rows: list[dict]) -> float | None:
    """σ показу всередині вікон: у кожному вікні (≥ 3 добрих рядки) віднімається власна пряма
    показ ↔ час Mac, залишки зводяться разом (ступенів свободи — рядки мінус 2 на вікно)."""
    ss, dof = 0.0, 0
    for seg in sorted({r["segment"] for r in rows}):
        pts = [(r["host_unix"], r["reading"]) for r in rows if r["segment"] == seg and good(r)]
        if len(pts) < 3:
            continue
        mx = statistics.fmean(p[0] for p in pts)
        my = statistics.fmean(p[1] for p in pts)
        sxx = sum((x - mx) ** 2 for x, _ in pts)
        if sxx == 0:
            continue
        slope = sum((x - mx) * (y - my) for x, y in pts) / sxx   # пряма найменших квадратів
        ss += sum((y - my - slope * (x - mx)) ** 2 for x, y in pts)
        dof += len(pts) - 2
    return math.sqrt(ss / dof) if dof > 0 else None


def summary(rows: list[dict]) -> str:
    vals = [r["reading"] for r in rows if good(r)]
    temps = [r["t_centi"] for r in rows if r["t_centi"] is not None]
    out = [f"рядків {len(rows)}, із кодом ≠ 0: {len(rows) - len(vals)}, вікон {len({r['segment'] for r in rows})}"]
    if vals:
        out.append(f"середнє показу {statistics.fmean(vals):.1f}")
    s = detrended_sigma(rows)
    if s is not None:
        out.append(f"σ всередині вікон після тренду {s:.2f} відліків (роздільність = 2σ × мкм/відлік)")
    if temps:
        out.append(f"температура {min(temps) / 100:.2f}…{max(temps) / 100:.2f} °C")
    return "; ".join(out)


def run(ser, writer, fh, args, rows: list[dict]) -> int:
    start = time.time()
    stop_at = start + args.minutes * 60.0 if args.minutes is not None else None
    count_deadline = start + max(60.0, 3.0 * args.interval * args.count) if args.count else None
    segment, next_send, last_m, warned, buf = 0, 0.0, start, False, b""
    while True:
        now = time.time()
        if args.count is not None and sum(good(r) for r in rows) >= args.count:
            return 0
        if stop_at is not None and now >= stop_at:
            return 0
        if count_deadline is not None and now >= count_deadline:
            print(f"❌ за {count_deadline - start:.0f} с не набралось {args.count} рядків із кодом 0")
            return 3
        if now >= next_send:
            ser.write(b"M\n")
            next_send = now + args.interval
        if not warned and now - last_m > max(SILENCE_S, 2.5 * args.interval):
            print("⚠️  плата мовчить — натисни RST (плата з ключами після вікна консоль закриває)")
            warned = True
        buf += ser.read(256)
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("ascii", "replace").strip()
            if line.startswith("#S,"):
                segment += 1             # нове вікно: новий старт, нове калібрування АЦП
                next_send = 0.0          # перший байт — протягом 5 с
                print(f"— вікно {segment}: {line}")
                continue
            if line.startswith("ERR,M") or line == "?":
                print(f"❌ плата відповіла «{line}» на M — образ без датчика чи старіший за команду M: "
                      "проший soldier_lora_e5 із цього дерева")
                return 2
            m = parse_m(line)
            if m is None:
                continue
            last_m, warned = time.time(), False
            m["host_unix"], m["segment"] = last_m, segment
            rows.append(m)
            writer.writerow([f"{last_m:.3f}" if k == "host_unix" else ("NA" if m[k] is None else m[k])
                             for k in FIELDS])
            fh.flush()
            print(line)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--interval", type=float, default=10.0, help="секунд між `M`")
    p.add_argument("--minutes", type=float, help="тривалість прогону")
    p.add_argument("--count", type=int, help="або: стільки рядків `#M` із кодом 0, і стоп")
    p.add_argument("--out", default="ktr_stand.csv")
    p.add_argument("--force", action="store_true", help="перезаписати наявний CSV")
    p.add_argument("--plan", action="store_true")
    args = p.parse_args()

    if args.plan or not args.port:
        print(PLAN)
        return 0
    if args.minutes is None and args.count is None:
        print("❌ потрібен --minutes або --count")
        return 1
    if Path(args.out).exists() and not args.force:
        print(f"❌ {args.out} уже є — інше --out або --force")
        return 1

    try:
        import serial  # type: ignore
    except ImportError:
        print("❌ pyserial не встановлено (pip install pyserial) — або --plan")
        return 1

    rows: list[dict] = []
    rc = 0
    with serial.Serial(args.port, args.baud, timeout=0.2) as ser, open(args.out, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(FIELDS)
        try:
            rc = run(ser, writer, fh, args, rows)
        except KeyboardInterrupt:
            print("\n— перервано (Ctrl-C)")
            rc = 130
    print(f"{'✅' if rc == 0 else '⚠️ '} {args.out}: {summary(rows)}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
