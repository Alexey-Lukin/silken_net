#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""02_selftest_attest.py — [bench] крипто-атестація кремнію (FW.2 CCM + sym KAT).

Host-сторона selftest'ів уже доведена (test_ccm_selftest/test_sym_selftest:
логіка + KAT-вектори коректні) — PASS на платі означає «кремній ≡ OpenSSL»,
FAIL однозначно вказує на HAL/кремній.

Шлях звіту — той, що має прошивка: POST у `firmware/soldier/main.c`
(`#if defined(CCM_SELFTEST)`) кладе результат у два глобали,
`g_ccm_selftest_failed` і `g_sym_selftest_failed`, а UART-виводу Солдат не має
зовсім.

    02_selftest_attest.py --plan                       # кроки дня
    02_selftest_attest.py --elf soldier.elf [--sn SN]  # прочитати глобали через SWD
    02_selftest_attest.py --self-check                 # перевірити парсер на еталонному виводі

Значення глобала: -1 = startup відпрацював, а POST ні (плата не дійшла до нього),
0 = PASS, N > 0 = N KAT-векторів упало. Збірку без -DCCM_SELFTEST видає відсутність
символу в .elf, не значення.

Чому mode=UR, а не HOTPLUG: Солдат майже весь час у STOP2, а DBG_STOP прошивка не
вмикає — у сні SWD до нього не достукається. SRAM переживає скид, а UR зупиняє ядро
на векторі скиду ДО startup, тож читаємо значення, яке POST лишив у попередньому
прогоні. Тому: живлення → дати завантажитись (POST іде першим у main) → скрипт.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys

PLAN = """\
— план крипто-атестації —
1. Бенч-збірка .elf Солдата з -DCCM_SELFTEST: на LoRa-E5 mini — таргет soldier_lora_e5,
   кроки збірки — RUNBOOK 2.1 (повний .elf плати вузла — board-freeze, 00_07 FW.46).
2. firmware/scripts/bench/00_flash.sh --elf soldier.elf --execute
3. Дати платі завантажитись: POST іде в main() до головного циклу.
4. 02_selftest_attest.py --elf soldier.elf  → читання обох глобалів через SWD
   (mode=UR — ядро стає на векторі скиду до startup, SRAM зберігає результат POST;
   HOTPLUG до сплячого в STOP2 Солдата не достукається) → вердикт.
5. PASS → фліп FW2_CCM_ENABLED (firmware) + TELEMETRY_CCM_ENABLED (backend) за
   чеклистом 03_05 «FW.2 flip-checklist» — і не раніше за його грошовий гейт (ARCH.8).
"""

SYMBOLS = ("g_ccm_selftest_failed", "g_sym_selftest_failed")
PROGRAMMER = "STM32_Programmer_CLI"


def symbol_address(nm_output: str, name: str) -> int | None:
    """Рядок `nm`: «20000abc D g_ccm_selftest_failed» → адреса або None."""
    m = re.search(rf"^([0-9A-Fa-f]{{8}})\s+\w\s+{re.escape(name)}$", nm_output, re.M)
    return int(m.group(1), 16) if m else None


def r32_word(stdout: str, addr: int) -> int | None:
    """Вивід `-r32 <addr> 4` («0x20000ABC : FFFFFFFF») → int32 або None.

    Форма та сама, що в FactoryFlashing::UidReadout (keyed на адресу, толерантна
    до 0x і регістру); точний формат live-CLI — bench-confirm (RUNBOOK 1.3)."""
    m = re.search(rf"(?:0x)?{addr:08X}\s*:\s*(?:0x)?([0-9A-Fa-f]{{8}})\b", stdout, re.I)
    if not m:
        return None
    word = int(m.group(1), 16)
    return word - (1 << 32) if word & 0x80000000 else word


def verdict(values: dict[str, int]) -> tuple[int, str]:
    if any(v == -1 for v in values.values()):
        return 3, "POST не виконувався — startup відпрацював, а до POST у main() плата не дійшла"
    failed = {k: v for k, v in values.items() if v != 0}
    if failed:
        return 1, f"FAIL: {failed} — HAL/endianness/errata, CCM не вмикати"
    return 0, "PASS: кремній ≡ OpenSSL ≡ backend за обома наборами KAT"


def self_check() -> int:
    nm = "20000a10 D g_ccm_selftest_failed\n20000a14 D g_sym_selftest_failed\n"
    assert symbol_address(nm, "g_ccm_selftest_failed") == 0x20000A10
    assert symbol_address(nm, "g_ccm") is None
    assert r32_word("0x20000A10 : 00000000", 0x20000A10) == 0
    assert r32_word("20000a14 : FFFFFFFF", 0x20000A14) == -1
    assert r32_word("0x20000A14 : 00000003", 0x20000A10) is None
    assert verdict({"a": 0, "b": 0})[0] == 0
    assert verdict({"a": 0, "b": 2})[0] == 1
    assert verdict({"a": -1, "b": 0})[0] == 3
    print("✅ self-check: парсер nm/-r32 і вердикт")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--elf", help="бенч-збірка з -DCCM_SELFTEST, та сама, що прошита")
    p.add_argument("--sn", help="серійник ST-LINK (станція з кількома зондами)")
    p.add_argument("--nm", default="arm-none-eabi-nm")
    p.add_argument("--plan", action="store_true")
    p.add_argument("--self-check", action="store_true")
    args = p.parse_args()

    if args.self_check:
        return self_check()
    if args.plan or not args.elf:
        print(PLAN)
        return 0

    nm_out = subprocess.run([args.nm, args.elf], capture_output=True, text=True, check=True).stdout
    connect = ["-c", "port=SWD", "mode=UR"] + ([f"sn={args.sn}"] if args.sn else [])
    values: dict[str, int] = {}
    for name in SYMBOLS:
        addr = symbol_address(nm_out, name)
        if addr is None:
            print(f"❌ {name} немає в {args.elf} — збірка без -DCCM_SELFTEST")
            return 3
        run = subprocess.run([PROGRAMMER, *connect, "-r32", f"0x{addr:08X}", "4"],
                             capture_output=True, text=True)
        if run.returncode != 0:
            print(f"❌ CLI не підключився (exit {run.returncode}) — зонд, NRST джиґа, живлення:\n{run.stdout[-300:]}")
            return 2
        out = run.stdout
        value = r32_word(out, addr)
        if value is None:
            print(f"❌ вивід -r32 для {name} не розпарсився — звір формат CLI (RUNBOOK 1.3):\n{out[-300:]}")
            return 2
        values[name] = value

    code, text = verdict(values)
    print(("✅ " if code == 0 else "❌ ") + text)
    return code


if __name__ == "__main__":
    sys.exit(main())
