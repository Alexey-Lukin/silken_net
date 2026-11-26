#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""08_logger_readout.py — [bench:logger-journal] зчитування журналу логера пілота П3 з UTC хоста (FW.70).

Календар логера не пишемо (⚖️ founder 2026-11-26, «(г) Якорі зчитування» — docs/03_01 §12.4):
мітки журналу — секунди годинника пристрою, а UTC дає ЯКІР — рядок `#S,<секунди пристрою>,…`
консолі, поруч із яким хост ставить власний UTC. Два режими:

  capture  RST біля плати → банер `#S` → скрипт одразу шле `D` (вікно чекає першого байта 5 с),
           пише кожен рядок у файл, а після кожного `#S` — `#H,<UTC хоста>`; на `#E` шле `Q`.
  map      файли захоплень у порядку часу (останній — зчитування) → CSV вимірів з UTC.

Як `map` ставить UTC — і де відмовляє (`NA`, не вигадане значення):
  · епохи живлення: календар скидається разом із backup-доменом (втрата живлення, зміна джерела
    RTC) і стартує знову з 2000-01-01, тож межа — якір BOOT із кодом POWER_ON або із секундами
    ≤ попереднього запису, якір TIME_SET, будь-який інший запис із секундами < попереднього
    (заголовок сторінки `#P` несе сітковий час і сам «попереднім» не стає);
  · якір зчитування (перший у файлі) — ОСТАННІЙ епосі, якщо дамп цілий і якір не менший за її
    останній запис мінус каденс/4; якір раннього файла — лише епосі, де стоїть ОСТАННЯ ПАРА
    вимірів останньої епохи того самого захоплення разом із seq сторінки, на якій вона лежить
    (хоч один показ — не NA, дамп цілий; той самий предикат попереджає в `capture`): інакше не
    доведено, що живлення між ними не зникало;
  · два якорі одного файла (банер і рядок стану `D`) мусять погоджуватись до 2 с — інакше файл
    без якоря;
  · лінійна мапа — лише через КРАЙНІ якорі епохи, рознесені ≥ 6 год (поза ними — `linear-extrap`),
    і лише якщо швидкість годинника між ними правдоподібна для джерела (`--clock lsi`: LSI
    29.5–34 кГц при подільниках на 32 кГц → −7.8…+6.25 %; `lse`: ±200 ppm); інакше — якорі
    суперечать (найімовірніше, чужа епоха) і `NA`;
  · один якір (або ближчі за 6 год) — сталий зсув лише з `--clock lse`; на LSI швидкість без
    другого якоря невідома, і UTC — `NA`.

    08_logger_readout.py --plan
    08_logger_readout.py capture --port /dev/cu.usbserial-XXX --out install.txt
    08_logger_readout.py map install.txt readout.txt [--clock lse] --out pilot.csv
    08_logger_readout.py --selftest

Стелі, названі вголос:
  · на LSI швидкість годинника залежить від температури, тож лінійна мапа між якорем
    встановлення й зимовим зчитуванням бреше посередині інтервалу (≈ 1 % різниці частот —
    години на місяць); на LSE сталий зсув дрейфує на хвилини за сезон; надрукована швидкість —
    середня, не крива;
  · якір — ±1 с (секунди `#S` цілі) і за умови, що годинник хоста синхронізовано (NTP);
  · brownout без скиду backup-домену теж дає межу (BOOT із POWER_ON) — ціна обережності:
    епоха, що насправді тривала, ділиться, і половина без якоря дістає `NA`;
  · межу не видно, якщо попередня епоха коротша за час від увімкнення до першого запису
    наступної і BOOT цієї наступної не записався: їх зіллє;
  · якір, знятий уже після втрати живлення, якої дамп того захоплення не показує, плутається з
    епохою свого ключа, коли нова епоха до якоря прожила не менше, ніж стара до ключової пари
    (мінус каденс/4) — тому якір встановлення беруть одразу після першої пари й далі живлення не
    переривають; гейт швидкості ловить це лише тоді, коли розрив великий;
  · ключова пара разом із seq сторінки повториться в чужій епосі лише після обгортки 8-бітного
    seq (роки на каденсі 30 хв); тоді лишається гейт швидкості, а вікно LSI пропускає розбіжність
    епох до ≈ 2–4 тижнів на сезоні ≈ 170 діб;
  · рядок із прапорцем «час виставлено» = 1 береться як UTC календаря лише в епосі, де якоря
    немає (у пілоті календар не пише ніхто — прапорець 0);
  · дамп без `#E` або з битим рядком — CSV пишеться, код виходу 2, а якір зчитування не
    призначається (обрізаний дамп міг не дійти до епохи, якій він належить); `capture` такий
    дамп відкидає й просить повтор.

Залежність: capture — pip install pyserial; map і --selftest — лише stdlib (Python 3.9 теж).
"""

from __future__ import annotations

import argparse
import contextlib
import csv
import datetime as dt
import re
import sys
import time
from pathlib import Path

REASON_BOOT = 0
REASON_TIME_SET = 1
RESET_POWER_ON = 1           # firmware/common/reset_cause.h — SILKEN_RESET_POWER_ON
MIN_LINEAR_SPAN_S = 6 * 3600
DEFAULT_CAD_MIN = 30
ANCHOR_AGREE_S = 2.0
# Межі швидкості годинника пристрою проти хоста: LSI 29.5–34 кГц (DS13105) при подільниках образу
# mini на 32 кГц (soldier_lora_e5.c MX_RTC_Init) · LSE — запас понад допуск кварцу.
RATE_BOUNDS = {"lsi": (29.5 / 32.0 - 1.0, 34.0 / 32.0 - 1.0), "lse": (-200e-6, 200e-6)}
FIELDS = ("utc_unix", "utc_iso", "board_s", "epoch", "map", "reading", "temp_c")
# Форми рядка дампа — LogJ_Format (firmware/common/logger_journal.h): показ — ціле або NA,
# температура — пів-градуси, `#X` — 16 hex. Рядок поза формою — битий, не вимір.
READING = re.compile(r"NA|\d{1,5}")
TEMP = re.compile(r"NA|-?\d{1,2}\.[05]")
HEX16 = re.compile(r"[0-9a-f]{16}")

PLAN = """\
— план зчитування логера П3 (RUNBOOK §6, «Журнал логера на кремнії») —
1. FT232RL на TX2/RX2 (J1-13/14) і GND, 115200 8N1; образ логера soldier_lora_e5; журнал стенду
   стерти ДО останньої прошивки (сторінки 104–121 — RUNBOOK §6), інакше стендові епохи займуть кільце.
2. Встановлення — удома, ПІСЛЯ останньої прошивки (з тим джерелом RTC, з яким логер іде на
   дерево): увімкнути елементом, дочекатись першої ПАРИ вимірів із показом (≥ 2 каденси: перший
   вимір живе в RAM до другого; датчик під'єднано — пара `NA,NA` якорем не годиться), тоді
     08_logger_readout.py capture --port <порт> --out install.txt                  + RST
   і далі живлення не переривати до дерева: втрата живлення скидає календар, а якір без пари
   тієї самої епохи мапер не призначає.
3. Кожне зчитування біля дерева:
     08_logger_readout.py capture --port <порт> --out readout_<дата>.txt          + RST
4. Мапа (на LSE — ще --clock lse):
     08_logger_readout.py map install.txt readout_<дата>.txt --out pilot.csv
   Файли захоплень — частина даних пілота: без них журнал має лише секунди пристрою.
"""


# ── розбір ────────────────────────────────────────────────────────────────────

def _ints(fields: list[str]) -> list[int] | None:
    try:
        return [int(f) for f in fields]
    except ValueError:
        return None


def parse_capture(text: str) -> dict:
    """Текст захоплення → якорі [(секунди пристрою, UTC хоста)] і ОСТАННІЙ дамп
    {records, end (число з `#E` або None), bad (нерозібрані рядки)}."""
    anchors: list[tuple[int, float]] = []
    dumps: list[dict] = []
    cur: dict | None = None
    pending_s: int | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if "#S," in line:
            line = line[line.find("#S,"):]   # сміттєвий байт скиду перед банером
        if not line or line.startswith("# "):
            continue
        p = line.split(",")
        if p[0] == "#S":
            v = _ints(p[1:2])
            pending_s = v[0] if v else None
            cur = {"records": [], "end": None, "bad": 0, "pg": None}   # банер і `D` починають рядком стану
            dumps.append(cur)
        elif p[0] == "#H" and len(p) == 2 and pending_s is not None:
            with contextlib.suppress(ValueError):   # битий UTC хоста — якоря немає
                anchors.append((pending_s, float(p[1])))
            pending_s = None
        elif cur is None:
            continue
        elif p[0] == "#E":
            v = _ints(p[1:2])
            cur["end"] = v[0] if v else -1
        elif p[0] == "#R":
            v = _ints(p[1:]) if len(p) == 6 else None
            if v:
                cur["records"].append({"kind": "anchor", "reason": v[0], "code": v[1], "s": v[2], "cad": v[4]})
            else:
                cur["bad"] += 1
        elif p[0] == "#P":
            v = _ints(p[1:]) if len(p) == 5 else None
            if v:
                cur["records"].append({"kind": "page", "s": v[1], "cad": v[3]})
                cur["pg"] = v[0]                    # seq сторінки — фізична тотожність записів під нею
            else:
                cur["bad"] += 1
        elif p[0] == "#X":
            if len(p) == 2 and HEX16.fullmatch(p[1]):
                cur["records"].append({"kind": "corrupt"})
            else:
                cur["bad"] += 1
        elif p[0] in ("OK", "ERR", "?") or p[0].startswith("#"):
            continue
        else:
            v = _ints(p[0:2]) if len(p) == 4 else None
            if v and v[1] in (0, 1) and READING.fullmatch(p[2]) and TEMP.fullmatch(p[3]):
                cur["records"].append({"kind": "meas", "s": v[0], "tv": v[1] == 1,
                                       "reading": p[2], "temp": p[3], "pg": cur["pg"]})
            else:
                cur["bad"] += 1
    full = [d for d in dumps if d["records"] or d["end"] is not None]
    return {"anchors": anchors, "dump": full[-1] if full else {"records": [], "end": None, "bad": 0, "pg": None}}


def dump_whole(d: dict) -> bool:
    return d["end"] is not None and d["end"] == len(d["records"]) + d["bad"] and not d["bad"]


def split_epochs(records: list[dict]) -> list[list[dict]]:
    """Записи дампа → епохи живлення (межі — шапка)."""
    epochs: list[list[dict]] = [[]]
    last_s: int | None = None
    for r in records:
        s = r.get("s")
        anchor = r["kind"] == "anchor"
        boot = anchor and r["reason"] == REASON_BOOT
        if s is not None and last_s is not None and (
                s < last_s
                or (boot and (s <= last_s or r["code"] == RESET_POWER_ON))
                or (anchor and r["reason"] == REASON_TIME_SET)):
            epochs.append([])
            last_s = None
        epochs[-1].append(r)
        if s is not None and r["kind"] != "page":   # заголовок сторінки несе сітковий час, не годинник
            last_s = s if last_s is None else max(last_s, s)
    return [e for e in epochs if e]


def cad_s(epoch: list[dict]) -> int:
    cads = [r["cad"] for r in epoch if r.get("cad")]
    return 60 * (cads[-1] if cads else DEFAULT_CAD_MIN)


def meas_key(r: dict) -> tuple:
    return (r["pg"], r["s"], r["tv"], r["reading"], r["temp"])


def install_key(dump: dict) -> tuple[list[tuple] | None, str]:
    """Ключ якоря встановлення — остання пара вимірів останньої епохи цілого дампа, хоч один
    показ не NA (спільний предикат `capture` і `map`). → (ключ, '') або (None, чому ні)."""
    if not dump_whole(dump):
        return None, "дамп неповний або битий"
    own = split_epochs(dump["records"])
    pair = [r for r in (own[-1] if own else []) if r["kind"] == "meas"][-2:]
    if len(pair) < 2:
        return None, "в останній епосі немає пари вимірів (перший вимір живе в RAM до другого)"
    if all(r["reading"] == "NA" for r in pair):
        return None, "у парі немає показу (датчик не під'єднано?)"
    return [meas_key(r) for r in pair], ""


def make_map(anchors: list[tuple[int, float]], clock: str):
    """Якорі однієї епохи → (функція секунди→UTC або None, назва мапи, примітка, межі якорів)."""
    pts = sorted(set(anchors), key=lambda a: a[1])
    if not pts:
        return None, "none", "", None
    first, last = pts[0], pts[-1]
    span = last[1] - first[1]
    if span >= MIN_LINEAR_SPAN_S and last[0] != first[0]:
        rate = (last[0] - first[0]) / span - 1.0
        lo, hi = RATE_BOUNDS[clock]
        if not lo <= rate <= hi:
            return None, "none-rate", (f" (швидкість {rate * 100:+.3f} % поза межами {clock} — якорі "
                                       f"суперечать, найімовірніше чужа епоха)"), None
        k = span / (last[0] - first[0])
        resid = max((abs(first[1] + (d - first[0]) * k - u) for d, u in pts), default=0.0)
        note = (f", годинник пристрою {rate * 100:+.4f} % проти хоста (крайні якорі за {span / 3600:.2f} год;"
                f" ±1 с на кожному — ±{200 / span:.4f} %; найбільше відхилення якоря від лінії {resid:.1f} с)")
        return (lambda s: first[1] + (s - first[0]) * k), "linear", note, (first[0], last[0])
    if clock == "lse":
        d0, u0 = last
        return (lambda s: u0 + (s - d0)), "offset", "", None
    return None, "none-lsi", " (LSI: без другого якоря, рознесеного на ≥ 6 год, швидкість невідома)", None


def map_captures(texts: list[str], clock: str = "lsi") -> tuple[list[dict], list[str], bool]:
    """Тексти захоплень (останній — зчитування) → (рядки CSV, звіт, дамп зчитування цілий)."""
    parsed = [parse_capture(t) for t in texts]
    report: list[str] = []
    for n, t in enumerate(parsed):
        a = t["anchors"]
        if len(a) >= 2 and abs((a[1][0] - a[0][0]) - (a[1][1] - a[0][1])) > ANCHOR_AGREE_S:
            report.append(f"файл {n + 1}: якорі одного захоплення розходяться понад {ANCHOR_AGREE_S:.0f} с — "
                          f"файл без якоря")
            t["anchors"] = []
    dump = parsed[-1]["dump"]
    records = dump["records"]
    epochs = split_epochs(records) or [[]]
    whole = dump_whole(dump)
    if dump["end"] is None:
        report.append("дамп зчитування без `#E` — обрізаний: решти рядків у файлі немає")
    elif not whole:
        report.append(f"дамп: `#E`={dump['end']}, розібрано {len(records)}, битих {dump['bad']} — "
                      f"рядки загублені чи биті")
    per_epoch: list[list[tuple[int, float]]] = [[] for _ in epochs]

    last = epochs[-1]
    last_rec_s = max((r["s"] for r in last if r["kind"] in ("meas", "anchor")), default=None)
    for a in parsed[-1]["anchors"][:1]:      # один якір на файл
        if not whole:   # обрізаний дамп міг не дійти до епохи, якій якір належить
            report.append("дамп зчитування неповний — якір зчитування не призначено (повтори захоплення)")
        elif last_rec_s is None or a[0] >= last_rec_s - cad_s(last) // 4:
            per_epoch[-1].append(a)
        else:
            report.append(f"якір зчитування {a[0]} < останнього запису {last_rec_s}: календар скинувся "
                          f"після журналу — якір не належить жодній епосі дампа")

    for n, t in enumerate(parsed[:-1]):
        if not t["anchors"]:
            continue
        a = t["anchors"][0]
        key, why = install_key(t["dump"])
        if key is None:
            report.append(f"файл {n + 1}: {why} — не доведено, що живлення не зникало; якір не призначено")
            continue
        hits = []
        for k, ep in enumerate(epochs):
            seq = [meas_key(r) for r in ep if r["kind"] == "meas"]
            if any(seq[i:i + 2] == key for i in range(len(seq) - 1)):
                hits.append(k)
        if len(hits) != 1:
            report.append(f"файл {n + 1}: ключова пара знайдена в {len(hits)} епохах дампа — якір не призначено")
        elif a[0] < key[-1][1] - cad_s(epochs[hits[0]]) // 4:
            report.append(f"файл {n + 1}: якір {a[0]} раніший за власну ключову пару — календар скинувся між "
                          f"ними; не призначено")
        else:
            per_epoch[hits[0]].append(a)

    rows: list[dict] = []
    for k, ep in enumerate(epochs):
        anc = per_epoch[k]
        f, kind, note, bounds = make_map(anc, clock)
        meas = [r for r in ep if r["kind"] == "meas"]
        report.append(f"епоха {k}: вимірів {len(meas)}, якорів {len(anc)}, мапа {kind}{note}")
        for r in meas:
            how = kind
            if f is not None:
                utc = f(r["s"])
                if bounds and not bounds[0] <= r["s"] <= bounds[1]:
                    how = "linear-extrap"
            elif r["tv"]:
                utc, how = float(r["s"]), "device-utc"
            else:
                utc = None
            rows.append({
                "utc_unix": "NA" if utc is None else f"{utc:.0f}",
                "utc_iso": "NA" if utc is None else
                dt.datetime.fromtimestamp(round(utc), dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "board_s": r["s"], "epoch": k, "map": how,
                "reading": r["reading"], "temp_c": r["temp"],
            })
    corrupt = sum(1 for r in records if r["kind"] == "corrupt")
    if corrupt:
        report.append(f"рядків #X (нечитабельний dw): {corrupt}")
    return rows, report, whole


def write_csv(fh, rows: list[dict]) -> None:
    w = csv.DictWriter(fh, fieldnames=FIELDS)
    w.writeheader()
    w.writerows(rows)


# ── захоплення ────────────────────────────────────────────────────────────────

def capture(ser, fh, wait_s: float) -> int:
    """Читає консоль від банера до `#E`, пише файл захоплення."""
    deadline = time.time() + wait_s
    buf, sent_d, lines = b"", False, []
    while time.time() < deadline:
        buf += ser.read(256)
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("ascii", "replace").strip()
            if "#S," in line:
                line = line[line.find("#S,"):]
            if not line:
                continue
            fh.write(line + "\n")
            lines.append(line)
            if line.startswith("#S,"):
                fh.write(f"#H,{time.time():.3f}\n")   # UTC хоста — у мить прийому рядка стану
                fh.flush()
                print(f"— якір: {line}")
                if not sent_d:
                    ser.write(b"D\n")
                    sent_d = True
                    deadline = time.time() + wait_s
            elif line.startswith("#E,"):
                ser.write(b"Q\n")
                ser.flush()
                print(f"— дамп: {line}")
                d = parse_capture("\n".join(lines))["dump"]
                if not dump_whole(d):
                    print("❌ дамп неповний (`#E` ≠ рядків або битий рядок) — повтори захоплення")
                    return 4
                key, why = install_key(d)
                if key is None:
                    print(f"⚠️  як якір встановлення цей файл не годиться: {why} — зачекай і повтори")
                return 0
            elif line.startswith("ERR") or line == "?":
                print(f"❌ плата відповіла «{line}»")
                return 2
    print("❌ банера чи кінця дампа не дочекались — натисни RST і повтори")
    return 3


# ── перевірка логіки ──────────────────────────────────────────────────────────

def selftest() -> int:
    o, u0, day = 946684800, 1764000000, 86400
    pair = f"#P,0,{o + 1800},0,30\n#R,0,1,{o + 1800},0,30\n{o + 1800},0,31000,-1.5\n{o + 3600},0,31004,-1.5\n"

    def cap(dev: int, utc: float, body: str = "", n: int | None = None) -> str:
        """Захоплення: банер + рядок стану `D` (за секунду), тоді дамп."""
        rows = sum(1 for x in body.splitlines() if x and not x.startswith("#E"))
        return (f"\x00#S,{dev},0,1,1,0,9,0,0\n#H,{utc:.1f}\n#S,{dev + 1},0,1,1,0,9,0,0\n#H,{utc + 1.2:.1f}\n"
                + body + (f"#E,{rows if n is None else n}\n" if body or n is not None else ""))

    install = cap(o + 3700, u0, pair)
    after = pair + f"#R,0,2,{o + 5400},0,30\n{o + 5400},0,31010,NA\n{o + 7200},0,NA,NA\n"

    def ru(dev: int) -> float:                     # годинник пристрою йде точно з хостом
        return u0 + dev - (o + 3700)

    # одна епоха: якір встановлення доведено парою свого захоплення → лінія, поза якорями — extrap
    rows, rep, whole = map_captures([install, cap(o + 93700, ru(o + 93700), after)])
    assert whole and [r["map"] for r in rows] == ["linear-extrap", "linear-extrap", "linear", "linear"], (rows, rep)
    assert [r["utc_unix"] for r in rows] == [str(u0 - 1900), str(u0 - 100), str(u0 + 1700), str(u0 + 3500)], rows
    # якір без пари в дампі (одразу після першого запису — вимір ще в RAM) або без дампа — не призначено
    for early in (cap(o + 1900, u0, f"#P,0,{o + 1800},0,30\n#R,0,1,{o + 1800},0,30\n"), cap(o + 100, u0)):
        rows, rep, _ = map_captures([early, cap(o + 93700, ru(o + 93700), after)])
        assert all(r["utc_unix"] == "NA" for r in rows) and any("не доведено" in m for m in rep), rep
    rows, _, _ = map_captures([cap(o + 100, u0), cap(o + 93700, u0 + 90000, after)], clock="lse")
    assert [r["map"] for r in rows] == ["offset"] * 4 and rows[0]["utc_unix"] == str(u0 + 90000 - 91900), rows
    # дамп встановлення сам показує втрату живлення після пари — якір не до старої епохи
    lost = cap(o + 1850, u0, pair + f"#R,0,1,{o + 1800},0,30\n")
    rows, rep, _ = map_captures([lost, cap(o + 93700, ru(o + 93700), after)], clock="lse")
    assert any("не доведено" in m for m in rep), rep
    # втрата живлення після встановлення: друга епоха знову з 2000-01-01; кожен якір — своїй епосі
    newer = after + f"#R,0,1,{o + 1800},0,30\n{o + 1800},0,30990,-3.0\n{o + 3600},0,30991,-3.0\n"
    rows, rep, whole = map_captures([install, cap(o + 5000, u0 + 9 * day, newer)], clock="lse")
    assert whole and [r["epoch"] for r in rows] == [0, 0, 0, 0, 1, 1], rows
    assert rows[0]["utc_unix"] == str(u0 - 1900) and rows[4]["utc_unix"] == str(u0 + 9 * day - 3200), rows
    rows, _, _ = map_captures([install, cap(o + 5000, u0 + 9 * day, newer)])
    assert all(r["utc_unix"] == "NA" for r in rows), rows
    # кільце затерло епоху встановлення, а пізніша епоха несе ту саму пару на іншій сторінці: ключ не збігся
    rows, rep, _ = map_captures([install, cap(o + 50 * day, u0 + 100 * day, pair.replace("#P,0,", "#P,7,"))])
    assert all(r["utc_unix"] == "NA" for r in rows) and any("0 епохах" in m for m in rep), (rows, rep)
    # навіть збіг разом із seq сторінки (обгортка 8-бітного seq) з великим розривом ловить гейт швидкості
    rows, rep, _ = map_captures([install, cap(o + 50 * day, u0 + 100 * day, pair)])
    assert all(r["map"] == "none-rate" for r in rows) and any("суперечать" in m for m in rep), (rows, rep)
    # обрізаний дамп зчитування: якір зчитування не призначається — епоха, якій він належить, могла не ввійти
    rows, rep, _ = map_captures([cap(o + 93700, ru(o + 93700), after).replace("#E,7\n", "")], clock="lse")
    assert all(r["utc_unix"] == "NA" for r in rows) and any("неповний" in m for m in rep), (rows, rep)
    # два захоплення за один візит (1 с розбіжності), потім сів елемент: лінія — крайніми якорями
    tail = after + f"{o + 90000},0,32000,-5.0\n{o + 91800},0,32001,-5.0\n{o + 180000},0,32050,-6.0\n"
    visit = after + f"{o + 90000},0,32000,-5.0\n{o + 91800},0,32001,-5.0\n"
    newer = tail + f"#R,0,1,{o + 1800},0,30\n{o + 1800},0,33000,-2.0\n{o + 3600},0,33001,-2.0\n"
    caps = [install, cap(o + 91900, ru(o + 91900), visit), cap(o + 91961, ru(o + 91960), visit),
            cap(o + 5000, u0 + 20 * day, newer)]
    rows, rep, _ = map_captures(caps)
    far = next(r for r in rows if r["board_s"] == o + 180000)
    assert far["map"] == "linear-extrap" and abs(int(far["utc_unix"]) - (u0 + 176300)) <= 3, (far, rep)
    # якорі одного файла, що розходяться, — файл без якоря
    bad = cap(o + 93700, ru(o + 93700), after).replace(f"#H,{ru(o + 93700) + 1.2:.1f}", f"#H,{ru(o + 93700) + 9:.1f}")
    rows, rep, _ = map_captures([install, bad])
    assert any("розходяться" in m for m in rep) and all(r["utc_unix"] == "NA" for r in rows), (rows, rep)
    # ключова пара в двох епохах — неоднозначно, не призначено
    twin = pair + f"#R,0,1,{o + 1800},0,30\n{o + 1800},0,31000,-1.5\n{o + 3600},0,31004,-1.5\n"
    rows, rep, _ = map_captures([install, cap(o + 5000, u0 + 9 * day, twin)], clock="lse")
    assert any("2 епохах" in m for m in rep) and rows[0]["utc_unix"] == "NA", (rows, rep)
    # дамп встановлення обрізаний · у його останній епосі один вимір · пара без показу — не призначено
    single = f"#P,0,{o + 1800},0,30\n#R,0,1,{o + 1800},0,30\n{o + 1800},0,31000,-1.5\n"
    nas = pair.replace("31000,-1.5", "NA,-1.5").replace("31004,-1.5", "NA,-1.5")
    for early in (install.replace("#E,4\n", ""), cap(o + 1900, u0, single), cap(o + 3700, u0, nas)):
        rows, rep, _ = map_captures([early, cap(o + 93700, ru(o + 93700), after)])
        assert all(r["utc_unix"] == "NA" for r in rows) and any("не доведено" in m for m in rep), (early, rep)
    # розрив із годинником назад, BOOT із POWER_ON, TIME_SET — межі
    for extra in (f"#R,2,0,{o + 100},0,30\n{o + 100},0,5,NA\n", f"#R,0,1,{o + 9000},0,30\n{o + 9000},0,5,NA\n",
                  f"#R,1,0,{u0},1,30\n{u0},1,5,NA\n"):
        rows, _, _ = map_captures([cap(o + 93700, ru(o + 93700), after + extra)])
        assert rows[-1]["epoch"] == 1, (extra, rows)
    # якір зчитування після скиду календаря не мапить журнал
    rows, rep, _ = map_captures([cap(o + 10, u0, after)], clock="lse")
    assert all(r["utc_unix"] == "NA" for r in rows) and any("скинувся" in m for m in rep), rep
    # обрізаний і битий дамп
    _, rep, whole = map_captures([cap(o + 93700, u0, after).replace("#E,7\n", "")])
    assert not whole and any("обрізаний" in m for m in rep), rep
    _, _, whole = map_captures([cap(o + 93700, u0, after + f"{o + 9000},0,3x,NA\n#X,00ff\n", n=9)])
    assert not whole
    # прапорець «час виставлено»: UTC календаря — лише без якоря
    rows, _, _ = map_captures(["#S,1,0,1,1,0,2,0,0\n" + f"{u0},1,5,NA\n#E,1\n"])
    assert rows[0]["map"] == "device-utc" and rows[0]["utc_unix"] == str(u0), rows
    print("✅ selftest: мапа й extrap, доказ якоря парою, межі епох, гейт швидкості, візит із двох "
          "захоплень, обрізаний дамп")
    return 0


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", nargs="?", choices=("capture", "map"))
    p.add_argument("files", nargs="*", help="map: файли захоплень у порядку часу")
    p.add_argument("--port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--wait", type=float, default=120.0, help="capture: секунд на банер і на дамп")
    p.add_argument("--clock", choices=("lsi", "lse"), default="lsi",
                   help="map: джерело RTC образу (lse дозволяє сталий зсув від одного якоря)")
    p.add_argument("--out")
    p.add_argument("--force", action="store_true", help="перезаписати наявний --out")
    p.add_argument("--plan", action="store_true")
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()

    if args.selftest:
        return selftest()
    if args.plan or args.mode is None:
        print(PLAN)
        return 0
    if args.out and Path(args.out).exists() and not args.force:
        print(f"❌ {args.out} уже є — інше --out або --force")
        return 1

    if args.mode == "map":
        if not args.files:
            print("❌ map: потрібен щонайменше один файл захоплення")
            return 1
        texts = [Path(f).read_text(encoding="ascii", errors="replace") for f in args.files]
        rows, report, whole = map_captures(texts, args.clock)
        if args.out:
            with open(args.out, "w", newline="") as fh:
                write_csv(fh, rows)
        else:
            write_csv(sys.stdout, rows)
        for m in report:
            print(f"— {m}", file=sys.stderr)
        return 0 if whole else 2

    if not args.port or not args.out:
        print("❌ capture: потрібні --port і --out")
        return 1
    try:
        import serial  # type: ignore
    except ImportError:
        print("❌ pyserial не встановлено (pip install pyserial) — або --plan")
        return 1
    print("натисни RST на платі — консоль слухає 5 с після банера")
    with serial.Serial(args.port, args.baud, timeout=0.2) as ser, open(args.out, "w") as fh:
        fh.write(f"# 08_logger_readout capture {dt.datetime.now(dt.timezone.utc).isoformat()} port={args.port}\n")
        try:
            return capture(ser, fh, args.wait)
        except KeyboardInterrupt:
            print("\n— перервано (Ctrl-C)")
            return 130


if __name__ == "__main__":
    sys.exit(main())
