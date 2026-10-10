#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""[SEC.42] Носій дисципліни календаря Солдата, якої host-тест не бачить (main.c хост не компілює).

Гроші від кроку годинника розв'язано в ОДНІЙ функції — `Silken_Beacon_Commit`
(firmware/common/wall_time.h): вона пише календар через шов {Wall_Seconds_Now,
Wall_Calendar_Set} і зсуває базу delta_t за кроком, ПЕРЕЧИТАНИМ із календаря.
Дисципліна тримається, доки (03_05 §2.4, врізка [SEC.42]; механізм — 03_02 §5а):
  · маяк застосовує рівно один виклик `Silken_Beacon_Commit` із тим самим станом
    (мітка синку · база delta_t · сторож) і дослівним швом;
  · читач шва — одне визначення, і віддає календар як є, без кешу, клемпу чи
    монотонного сторожа (тіло пінене дослівно: «час не йде назад» у читачі мовчки
    повертав би крок назад маяка у гроші);
  · календар не пише ніхто, крім тіла `Wall_Calendar_Set` (у ньому обидві половини
    запису), і ніхто не торкається RTC, DR1 чи шва повз застосування — ні записом,
    ні читанням (читати календар — через `Wall_Seconds_Now`), ні макрос-аліасом;
  · базу delta_t пишуть лише оголошення, відновлення з DR1, Фаза 1 і застосування
    маяка, її адресу беруть лише вони, а DR1 пишуть лише два збереження бази —
    і регістр кожного запису backup-регістрів названо літералом `RTC_BKP_DRn`.

Читає `firmware/soldier/main.c` і всі одиниці, що його #include-ять (з дерева, не
списком), без коментарів і рядкових літералів (нумерацію рядків збережено; `//` із
переносом через зворотну скісну продовжується, як у компілятора); лічить на склеєному коді, тож
перенесення рядків, Allman-дужка й `!= 0u` червоного не дають. На відмові друкує
очікуване, знайдене й рядки.

⚠️ Стеля: це носій від ВИПАДКОВОЇ регресії, а не межа проти навмисної правки — він
читає текст, а не семантику. Не бачить: макросу, що розгортається в заборонений
токен, якщо макрос живе поза цими файлами; писача календаря в інших одиницях
трансляції; значення, яке пишуть у DR1 (пінене лише число записів і їхня форма).
Кожну гілку `#if` рахує як живу — і в бік хибного червоного (другий виклик під
вимкненим гейтом), і в бік хибного зеленого (виклик лише під вимкненою гілкою).
Побітове `x & база` дасть хибне червоне — ціна лічби адрес у будь-якій позиції.
Тіло `Wall_Calendar_Set` дослівно не пінене свідомо: базу веде перечитування.

Запуск: `make -C firmware/test soldier` (або `python3 tools/firmware/check_sec42_calendar.py`).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "firmware/soldier/main.c"
# Одиниці трансляції, що включають main.c (образи для ARM-лейнів), — з дерева, не списком.
INCLUDERS = sorted(
    path for path in (ROOT / "firmware").rglob("*.c")
    if "extern" not in path.parts
    and re.search(r'#\s*include\s*"[^"]*soldier/main\.c"', path.read_text(encoding="utf-8", errors="replace"))
)

# Коментар `//` продовжується за `\`-переносом — так його бачить компілятор.
LITERAL_OR_COMMENT = re.compile(
    r"/\*.*?\*/|//(?:\\\n|[^\n])*|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'", re.S
)

# Прямий доступ до RTC і backup-регістра DR1 повз шов — і запис, і читання: календар
# читають через Wall_Seconds_Now, пишуть лише через Silken_Beacon_Commit.
FOREIGN_RTC = re.compile(
    r"(?<!\w)RTC\s*->|hrtc\s*(?:\.|->)\s*Instance\s*->|LL_RTC_|HAL_RTC_DST_|DAYLIGHT_SAVING"
    r"|RTC_CR_(?:ADD|SUB)1H|SetSynchroShift|SetSmoothCalib|HAL_RTC_DeInit|(?<!\w)BKP1R(?!\w)"
    r"|(?:\.|->)(?:read|write)_wall(?!\w)"
)
# Макрос-аліас бази, шва чи DR1 — інакше лічба нижче бачила б лише псевдонім.
ALIAS_DEFINE = re.compile(
    r"^\s*#\s*define\b.*(?<!\w)(?:last_wakeup_timestamp|Wall_Calendar_Set|Wall_Seconds_Now"
    r"|soldier_calendar_ops|Silken_Beacon_Commit|RTC_BKP_DR1)(?!\w)"
)
CALENDAR_SET = re.compile(r"HAL_RTC_Set(?:Time|Date)\s*\(")
BASE = r"last_wakeup_timestamp"
BASE_WRITE = re.compile(
    rf"(?<![\w.>]){BASE}\s*(?:[-+*/%&|^]|<<|>>)?=(?!=)|(?:\+\+|--)\s*{BASE}(?!\w)|(?<![\w.>]){BASE}\s*(?:\+\+|--)"
)
# Адреса бази в будь-якій позиції (не «&&»); побітове «x & база» дасть хибне червоне — ціна.
ADDRESS_OF_BASE = re.compile(rf"(?<!&)&\s*{BASE}(?!\w)")

# Дослівний пін тіла читача шва (без пробілів біля пунктуації).
READER_SIGNATURE = r"static\s+uint32_t\s+Wall_Seconds_Now\s*\(\s*void\s*\)"
READER_BODY = (
    "{RTC_TimeTypeDef t={0};RTC_DateTypeDef d={0};"
    "if(HAL_RTC_GetTime(&hrtc,&t,RTC_FORMAT_BIN)!=HAL_OK)return 0u;"
    "if(HAL_RTC_GetDate(&hrtc,&d,RTC_FORMAT_BIN)!=HAL_OK)return 0u;"
    "return Silken_Unix_From_Calendar((int32_t)d.Year+2000,d.Month,d.Date,t.Hours,t.Minutes,t.Seconds);}"
)
WRITER_SIGNATURE = r"static\s+void\s+Wall_Calendar_Set\s*\([^;{}()]*\)"

failures = []


def strip(src):
    """Коментарі → порожні рядки тієї ж кількості, літерали → порожні літерали."""
    def repl(m):
        t = m.group(0)
        if t.startswith("/"):
            return "\n" * t.count("\n")
        return '""' if t.startswith('"') else "' '"
    return LITERAL_OR_COMMENT.sub(repl, src)


def flat(code):
    """Один рядок: пробіли стиснуто, біля пунктуації — знято (між словами лишається)."""
    return re.sub(r" ?([^\w ]) ?", r"\1", re.sub(r"\s+", " ", code)).strip()


def body(code, signature):
    """(перший рядок, текст) тіла ВИЗНАЧЕННЯ за регексом сигнатури (не прототипу) — дужки рахуються; None, якщо нема."""
    m = re.search(signature + r"\s*\{", code)
    if m is None:
        return None
    open_at = m.end() - 1
    depth = 0
    for i in range(open_at, len(code)):
        depth += {"{": 1, "}": -1}.get(code[i], 0)
        if depth == 0:
            return code.count("\n", 0, open_at) + 1, code[open_at:i + 1]
    return None


def hits(code, pattern, path):
    return [f"  {path.relative_to(ROOT)}:{n}: {line.strip()}"
            for n, line in enumerate(code.split("\n"), 1) if pattern.search(line)]


def expect(what, want, found, lines=()):
    if found != want:
        failures.append(f"FAIL [SEC.42]: {what} — очікувано {want}, знайдено {found}"
                        + "".join("\n" + line for line in lines))


main = strip(MAIN.read_text(encoding="utf-8"))
one = flat(main)
units = {MAIN: main, **{path: strip(path.read_text(encoding="utf-8")) for path in INCLUDERS}}

# 1. Застосування маяка — рівно один виклик, з тим самим станом і дослівним швом.
call = re.compile(r"(?<!\w)Silken_Beacon_Commit\(")
pinned_call = re.compile(
    r"(?<!\w)Silken_Beacon_Commit\(&soldier_calendar_ops,[A-Za-z_]\w*,&soldier_unix_ts,"
    rf"&{BASE},&wakeups_since_sync\)"
)
expect("викликів Silken_Beacon_Commit", 1, len(call.findall(one)),
       hits(main, re.compile(r"Silken_Beacon_Commit\s*\("), MAIN))
expect("викликів Silken_Beacon_Commit із міткою синку, базою delta_t і сторожем", 1,
       len(pinned_call.findall(one)), hits(main, re.compile(r"Silken_Beacon_Commit\s*\("), MAIN))

# 2. Шов — один, дослівний, і більше ніде не згадується.
seam = re.compile(r"(?<!\w)soldier_calendar_ops(?!\w)")
expect("дослівних визначень шва {Wall_Seconds_Now, Wall_Calendar_Set}", 1,
       one.count("static const SilkenCalendarOps soldier_calendar_ops={Wall_Seconds_Now,Wall_Calendar_Set};"),
       hits(main, seam, MAIN))
for token, want, roles in (("soldier_calendar_ops", 2, "визначення шва й виклик застосування"),
                           ("SilkenCalendarOps", 1, "лише тип шва"),
                           ("Wall_Calendar_Set", 3, "прототип, визначення, шов")):
    pattern = re.compile(rf"(?<!\w){token}(?!\w)")
    expect(f"згадок {token} ({roles})", want, len(pattern.findall(main)), hits(main, pattern, MAIN))

# 3. Читач шва — дослівно, і визначення в нього одне (друге під #else не пінилось би).
for name in ("Wall_Seconds_Now", "Wall_Calendar_Set"):
    definition = re.compile(rf"(?<!\w){name}\s*\([^;{{}}()]*\)\s*\{{")
    expect(f"визначень {name}", 1, len(definition.findall(main)), hits(main, re.compile(rf"(?<!\w){name}\s*\("), MAIN))
reader = body(main, READER_SIGNATURE)
if reader is None:
    failures.append("FAIL [SEC.42]: не знайдено визначення «static uint32_t Wall_Seconds_Now(void)»")
elif flat(reader[1]) != READER_BODY:
    failures.append(
        f"FAIL [SEC.42]: тіло читача шва змінено ({MAIN.relative_to(ROOT)}:{reader[0]}) — читач мусить\n"
        "  віддавати календар як є: кеш, клемп чи «час не йде назад» повертають крок назад маяка в гроші\n"
        "  (03_05 §2.4). Коректну правку — переконатись у цьому й оновити READER_BODY тут.\n"
        f"  знайдено: {flat(reader[1])}")

# 4. Календар пише лише тіло Wall_Calendar_Set; шов повз застосування не кличуть.
writer = body(main, WRITER_SIGNATURE)
if writer is None:
    failures.append("FAIL [SEC.42]: не знайдено визначення «static void Wall_Calendar_Set(…)»")
else:
    start, text = writer
    outside = [h for h in hits(main, CALENDAR_SET, MAIN)
               if not start <= int(h.split(":")[1]) < start + text.count("\n") + 1]
    expect("HAL_RTC_SetTime/SetDate поза тілом Wall_Calendar_Set", 0, len(outside), outside)
    for half in ("SetTime", "SetDate"):
        if not re.search(rf"HAL_RTC_{half}\s*\(", text):
            failures.append(f"FAIL [SEC.42]: тіло Wall_Calendar_Set не кличе HAL_RTC_{half} — запис календаря неповний")
calls = [h for h in hits(main, re.compile(r"(?<!\w)Wall_Calendar_Set\s*\("), MAIN)
         if not re.search(r":\s*static\s+void\s+Wall_Calendar_Set\s*\(", h)]
expect("прямих викликів Wall_Calendar_Set повз Silken_Beacon_Commit", 0, len(calls), calls)
for path, code in units.items():
    found = hits(code, FOREIGN_RTC, path) + hits(code, ALIAS_DEFINE, path)
    if path != MAIN:
        found += hits(code, CALENDAR_SET, path) + hits(code, re.compile(rf"(?<!\w)(?:Wall_Calendar_Set|{BASE})(?!\w)"), path)
    expect(f"прямого доступу до RTC, DR1 чи шва повз застосування в {path.relative_to(ROOT)}", 0, len(found), found)

# 5. База delta_t: оголошення, відновлення з DR1, Фаза 1 і застосування маяка.
base_lines = hits(main, re.compile(rf"(?<!\w){BASE}(?!\w)"), MAIN)
expect("присвоєнь бази delta_t (оголошення й відновлення з DR1)", 2, len(BASE_WRITE.findall(one)), base_lines)
expect("відновлень бази з DR1", 1, one.count(f"{BASE}=HAL_RTCEx_BKUPRead(&hrtc,RTC_BKP_DR1);"), base_lines)
expect("адрес &last_wakeup_timestamp (Фаза 1 і застосування маяка)", 2, len(ADDRESS_OF_BASE.findall(one)), base_lines)
expect("передач бази у Фазу 1 (Silken_Wake_Delta_Seconds)", 1,
       len(re.findall(rf"(?<!\w)Silken_Wake_Delta_Seconds\([A-Za-z_]\w*,&{BASE},", one)), base_lines)

# 6. DR1 несе базу через скид — пишуть його лише два збереження бази, у всіх одиницях.
#    Регістр запису — лише літерал RTC_BKP_DRn: число, вираз чи цикл по DR0..DR19 лічба не бачить.
bkup = re.compile(r"HAL_RTCEx_BKUPWrite\s*\(")
dr1_writes = re.compile(r"HAL_RTCEx_BKUPWrite\([^,;]*,RTC_BKP_DR1,")
dr1_total = 0
for path, code in units.items():
    joined = flat(code)
    opaque = len(bkup.findall(joined)) - len(re.findall(r"HAL_RTCEx_BKUPWrite\([^,;]*,RTC_BKP_DR\d+,", joined))
    expect(f"записів backup-регістрів не літералом RTC_BKP_DRn в {path.relative_to(ROOT)}", 0, opaque,
           hits(code, bkup, path))
    dr1_total += len(dr1_writes.findall(joined))
dr1_lines = [h for path, code in units.items() for h in hits(code, re.compile(r"RTC_BKP_DR1(?!\d)"), path)]
expect("записів DR1 (збереження бази delta_t)", 2, dr1_total, dr1_lines)
expect("записів DR1 саме значенням бази", 2, one.count(f"HAL_RTCEx_BKUPWrite(&hrtc,RTC_BKP_DR1,{BASE});"), dr1_lines)

if failures:
    print("\n".join(failures))
    sys.exit(1)
