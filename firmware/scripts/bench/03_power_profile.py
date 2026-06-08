#!/usr/bin/env python3
"""03_power_profile.py — [bench] PPK2 power-профілі: STOP2 floor / E_cycle / Vcap recharge.

Артефакти CSV → bench_artifacts/: пряме паливо для E.63 (медіана перезаряду →
калібрування DELTA_T_FAST_S/DELTA_T_SLOW_S метаболічного growth_points) і FW.54 (300 нА floor —
NB: роздільність PPK2 ~100 нА → 300 нА підтверджувати JS220/SMU).

    03_power_profile.py --mode floor|cycle|recharge [--seconds N] [--out CSV]
    03_power_profile.py --mode recharge --simulate   # синтетика для пайплайна

Залежність: pip install ppk2-api  (https://pypi.org/project/ppk2-api/)
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
import time


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", required=True, choices=["floor", "cycle", "recharge"])
    p.add_argument("--seconds", type=int, default=60)
    p.add_argument("--voltage-mv", type=int, default=3300, help="source-meter напруга")
    p.add_argument("--out", default=None, help="CSV (default: bench_<mode>_<ts>.csv)")
    p.add_argument(
        "--simulate",
        action="store_true",
        help="синтетичний потік без заліза — перевірка CSV-пайплайна, ЧЕСНО позначено",
    )
    return p.parse_args()


def sample_simulated(mode: str, seconds: int):
    """Синтетика: floor ~300 нА + шум; cycle — пік TX; recharge — RC-крива."""
    t = 0.0
    dt = 0.01
    while t < seconds:
        if mode == "floor":
            ua = 0.3 + 0.05 * math.sin(t * 7.0)
        elif mode == "cycle":
            ua = 8000.0 if 0.2 < (t % 5.0) < 0.45 else 2.1  # TX-burst у циклі
        else:  # recharge: V наближається до 5.0 В експонентою (тут — струм заряду)
            ua = 15.0 * math.exp(-t / (seconds / 4.0))
        yield t, ua
        t += dt


def sample_ppk2(args: argparse.Namespace):
    try:
        from ppk2_api.ppk2_api import PPK2_API  # type: ignore
    except ImportError:
        print("❌ ppk2-api не встановлено (pip install ppk2-api) — або --simulate")
        sys.exit(1)

    ports = PPK2_API.list_devices()
    if not ports:
        print("❌ PPK2 не знайдено на USB")
        sys.exit(1)

    ppk2 = PPK2_API(ports[0])
    ppk2.get_modifiers()
    ppk2.use_source_meter()
    ppk2.set_source_voltage(args.voltage_mv)
    ppk2.toggle_DUT_power("ON")
    ppk2.start_measuring()

    t0 = time.time()
    try:
        while (now := time.time() - t0) < args.seconds:
            raw = ppk2.get_data()
            if raw != b"":
                samples, _ = ppk2.get_samples(raw)
                for s in samples:
                    yield now, s  # µA
            time.sleep(0.01)
    finally:
        ppk2.stop_measuring()
        ppk2.toggle_DUT_power("OFF")


def main() -> int:
    args = parse_args()
    out = args.out or f"bench_{args.mode}_{int(time.time())}.csv"
    source = sample_simulated(args.mode, args.seconds) if args.simulate else sample_ppk2(args)

    n = 0
    acc_ua = 0.0
    peak_ua = 0.0
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["t_s", "current_uA", "simulated" if args.simulate else "ppk2"])
        for t, ua in source:
            w.writerow([f"{t:.4f}", f"{ua:.3f}"])
            n += 1
            acc_ua += ua
            peak_ua = max(peak_ua, ua)

    if n == 0:
        print("❌ нуль семплів")
        return 1
    mean_ua = acc_ua / n
    print(f"✅ {out}: n={n} mean={mean_ua:.3f} µA peak={peak_ua:.1f} µA "
          f"{'[SIMULATED — не bench-дані]' if args.simulate else ''}")
    if args.mode == "cycle":
        # E ≈ V × ∫I dt — груба інтеграція для швидкого погляду; точність → аналіз CSV
        e_mj = args.voltage_mv / 1000.0 * mean_ua * 1e-6 * args.seconds * 1000.0
        print(f"   E({args.seconds}s) ≈ {e_mj:.2f} мДж — порівняти з 02_03 §9 бюджетом")
    return 0


if __name__ == "__main__":
    sys.exit(main())
