# SPDX-License-Identifier: AGPL-3.0-or-later
"""E.64 — санітизація UA-набору санітарного стану лісів + зріз Черкащини.

    python3 tools/ground_truth/fetch.py          # спершу транспорт
    python3 tools/ground_truth/build_slice.py    # → cherkasy_sanitary.csv

Межі придатності набору канонізовані в `docs/05_05_Slashing_and_Risk_Policy.md` §8.5
і сюди не переказуються. Одне, що мусить стояти В МІСЦІ ДІЇ, бо визначає, як читати
вихід: зерно рядка — **виділ**, не дерево; це реєстр новопризначених заходів, не
панель; ⛔ per-tree ground truth з нього не робиться.

Що робить санітизація (кожен крок лишає СЛІД у колонці `repaired`):

1. **Подвійне кодування.** Кирилиця в UTF-8, помилково прочитана як cp1251 і
   збережена знову — знімається зворотним `encode('cp1251').decode('utf-8')`,
   і лише якщо результат МЕНШ мохібейний за вхід (евристика `_weird`).
2. **Байтові дублі.** Дедуплікація за SHA-256 ФАЙЛУ, не за міткою кварталу:
   портал опублікував 2024-Q3 побайтовою копією 2024-Q1, але хардкодити цей
   висновок означало б протухнути, щойно його полагодять.
3. **Excel «число → дата».** «22.6» збережене як «22.Чер» — відновлюється
   однозначно (день.місяць → день.номер_місяця). ⚠️ Межа, названа вголос: так
   постраждали ЛИШЕ значення з дробовою частиною 1..12, решта неушкоджені —
   тобто псування СИСТЕМАТИЧНЕ, і воно зміщене до малих дробових.
4. **Excel «дата → серійний номер».** 45421 → 2024-05-14 (епоха 1899-12-30).
5. **Назви підприємств.** Та сама одиниця має 3+ написань; ключ нормалізується
   (форма власності, лапки, «лісгосп/ЛГ/лісове господарство»). ⚠️ Це ЕВРИСТИКА,
   тож оригінал лишається в `enterprise_raw` — нормалізація є нашим твердженням
   про чужі дані, і аудитор мусить мати змогу його спростувати.

🔴 Похідні колонки (`pine_share`, `cut_share`, `severity_ordinal`, `reason_*`) —
теж НАШІ твердження, не дані джерела. Джерельні поля лишаються поруч.
"""

import argparse
import collections
import csv
import datetime
import hashlib
import io
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
EXCEL_EPOCH = datetime.date(1899, 12, 30)

CYR_CLASS = r"А-Яа-яЇїІіЄєҐґ"
MONTHS = {"січ": 1, "лют": 2, "бер": 3, "кві": 4, "тра": 5, "чер": 6,
          "лип": 7, "сер": 8, "вер": 9, "жов": 10, "лис": 11, "гру": 12}

# Сосна звичайна у лісовпорядній формулі складу: «С», «Сз», «СЗ», «Сзв».
PINE = re.compile(rf"(?<![{CYR_CLASS}])С(?:З|з|зв)?(?![{CYR_CLASS}])")
COMPOSITION_TERM = re.compile(rf"(\d{{1,2}})\s*([{CYR_CLASS}]{{1,4}})")

# Класи причин заходу. Джерельне поле — вільний текст, тож це НАШ класифікатор;
# класи НЕ взаємовиключні (рядок легітимно несе кілька причин).
#
# 🔑 Словник виведено з САМИХ ДАНИХ (частотний розбір поля по Черкащині), не з
# голови: перша редакція, написана «зі знання домену», лишила 5.9 % рядків
# нерозкласифікованими — і всі вони виявились біотичними (вусачі · златки ·
# лубоїди · трутовики · рак-сірянка), тобто бідність словника читалась як
# властивість джерела. ⚠️ Межі слова тут несучі, а не охайність: «град» без
# них ловить «деградацію», «рак» — випадкові збіги.
REASON_CLASSES = {
    "biotic": re.compile(
        r"\b(?:шкідник|хвороб|короїд|вусач|златк|лубоїд|омел|трутовик|заболонник|"
        r"рак|некроз|гнил|рагій|губк|грибк|всихан|усихан|шовкопряд|пильщик|"
        r"ентомо|фітопатолог|пошкодж\w*\s+стовбуров)", re.IGNORECASE),
    "abiotic": re.compile(
        r"\b(?:стихійн|аварі|сніголом|сніговал|вітровал|вітролом|бурелом|буревій|"
        r"вітер|вітром|ожелед|посух|підтопл|ураган|морозобій|блискавк|град\b)",
        re.IGNORECASE),
    "fire": re.compile(r"\b(?:пожеж|горінн|згорі|загорян|згар)", re.IGNORECASE),
}

# Вид заходу як ординал тяжкості: вибіркова < суцільна санітарна рубка (§8.5).
SEVERITY = {"ВСР": 1, "ССР": 2}

OWNERSHIP_PREFIX = re.compile(
    r"^(дп|мп|кп|тов|пп|дсгп|сгп|фг|ат|пат|прат|двнз|філія|дочірнє підприємство|"
    r"державне підприємство|комунальне підприємство|міжгосподарське підприємство)\b[\s.'\"]*",
)

OUT_COLUMNS = [
    "quarter_published", "event_date", "area",
    "enterprise", "enterprise_raw", "forestry", "forest_quarter", "section",
    "allotment_area", "subdivision_area", "subdivision_area_for_operation",
    "composition", "pine_share", "age", "completeness", "bonitet",
    "avg_height", "avg_diameter", "stock", "cut_stock", "cut_share",
    "security_category", "event_type", "severity_ordinal",
    "reason_raw", "reason_biotic", "reason_abiotic", "reason_fire", "reason_unclassified",
    "repaired",
]


# ── 1. кодування ───────────────────────────────────────────────────────────────

def _weird(text: str) -> int:
    """Скільки в рядку послідовностей, типових для мохібейку (Р/С + не-кирилиця)."""
    return len(re.findall(rf"[РС][^{CYR_CLASS}\s\"';.,()0-9A-Za-z-]", text))


def unmoji(value):
    if not isinstance(value, str) or not value:
        return value
    try:
        candidate = value.encode("cp1251").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return value
    return candidate if _weird(candidate) < _weird(value) else value


# ── 3-4. Excel-пошкодження ─────────────────────────────────────────────────────

def repair_number(value):
    """«22.Чер» → 22.6. Повертає (значення, чи_відновлено)."""
    if not isinstance(value, str):
        return value, False
    text = value.strip()
    match = re.fullmatch(r"(\d{1,2})[.\-/]\s*([А-Яа-яЇїІіЄєҐґ]{3,4})\.?", text)
    if not match:
        return text, False
    month = MONTHS.get(match.group(2)[:3].lower())
    if month is None:
        return text, False
    return f"{int(match.group(1))}.{month}", True


def repair_date(value):
    """Серійний номер Excel → ISO-дата; «03.01.2024» → «2024-01-03»."""
    text = str(value or "").strip()
    if not text or text.lower() in ("null", "none"):
        return "", False
    if text.isdigit() and 40000 <= int(text) <= 50000:
        return (EXCEL_EPOCH + datetime.timedelta(days=int(text))).isoformat(), True
    match = re.fullmatch(r"(\d{1,2})[./-](\d{1,2})[./-](\d{4})", text)
    if match:
        day, month, year = (int(g) for g in match.groups())
        try:
            return datetime.date(year, month, day).isoformat(), False
        except ValueError:
            return text, False
    return text, False


# ── 5. назви підприємств ───────────────────────────────────────────────────────

def normalise_enterprise(raw: str) -> str:
    text = (raw or "").strip().lower()
    text = text.replace("«", "").replace("»", "").replace('"', " ").replace("'", "'")
    text = re.sub(r"\s+", " ", text).strip(" .,-")
    for _ in range(2):  # «філія ДП …» — форма власності буває подвоєна
        text = OWNERSHIP_PREFIX.sub("", text).strip(" .,-")
    text = re.sub(r"\bлісове господарство\b|\bлісгоспу?\b|\bлг\b|\bлісгосп\b", "лісгосп", text)
    text = re.sub(r"\bлісомисливськ\w*\b", "лмг", text)
    text = re.sub(r"\s+", " ", text).strip(" .,-")
    return text


# ── похідні ────────────────────────────────────────────────────────────────────

def pine_share(composition) -> int:
    """Коефіцієнт сосни у формулі складу (0..10). «10СЗ» → 10, «5СЗ5ДЗ» → 5."""
    if not isinstance(composition, str):
        return 0
    total = 0
    for coefficient, species in COMPOSITION_TERM.findall(composition):
        if PINE.fullmatch(species):
            total += int(coefficient)
    return total


def classify_reason(raw: str) -> dict:
    text = raw or ""
    hits = {name: bool(pattern.search(text)) for name, pattern in REASON_CLASSES.items()}
    hits["unclassified"] = bool(text.strip()) and not any(hits.values())
    return hits


def _s(value) -> str:
    """Джерельне поле як текст: JSON-квартали віддають числа там, де CSV — рядки."""
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in ("null", "none") else text


def to_float(value):
    text = str(value or "").strip().replace(",", ".")
    if not text or text.lower() in ("null", "none"):
        return None
    try:
        return float(text)
    except ValueError:
        return None


# ── читання ────────────────────────────────────────────────────────────────────

def load_rows(path: pathlib.Path) -> list[dict]:
    raw = path.read_bytes().decode("utf-8-sig")
    if path.suffix.lower() == ".json":
        doc = json.loads(raw)
        if isinstance(doc, dict):
            # 2024-Q4 приїхав обгорнутим у назву аркуша Excel: {"Зведена": [...]}.
            lists = [v for v in doc.values() if isinstance(v, list)]
            doc = lists[0] if lists else []
        return [{k: unmoji(v) if isinstance(v, str) else v for k, v in row.items()} for row in doc]
    reader = csv.DictReader(io.StringIO(raw), delimiter=";")
    return [{(k or ""): unmoji(v) if isinstance(v, str) else v for k, v in row.items()}
            for row in reader]


QUARTER_RE = re.compile(r"(20\d{2})[-_]?(\d)\s*kv", re.IGNORECASE)


def quarter_label(name: str) -> str:
    match = QUARTER_RE.search(name)
    return f"{match.group(1)}-Q{match.group(2)}" if match else name


def collect(raw_dir: pathlib.Path):
    """Читає всі квартальні файли, дедуплікує ЗА SHA-256 файлу."""
    seen_digests: dict[str, str] = {}
    rows, skipped = [], []
    for path in sorted(raw_dir.iterdir()):
        if path.name == "manifest.json" or path.suffix.lower() not in (".csv", ".json"):
            continue
        if not path.name.lower().startswith("perelik_"):
            continue  # strukture_perelik.csv — словник полів, не дані
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in seen_digests:
            skipped.append((path.name, seen_digests[digest]))
            continue
        seen_digests[digest] = path.name
        label = quarter_label(path.name)
        for row in load_rows(path):
            row["_q"] = label
            rows.append(row)
    return rows, skipped


# ── трансформація ──────────────────────────────────────────────────────────────

NUMERIC_SOURCE = {
    "allotment_area": "areaOfAllotment",
    "subdivision_area": "subdivisionArea",
    "subdivision_area_for_operation": "subdivisionAreaForOperation",
    "completeness": "completeness",
    "avg_height": "averageHeight",
    "avg_diameter": "averageDiameter",
    "stock": "stockOfTreesToBeCutDown",
    "cut_stock": "estimatedStockOfTimberToBeCut",
}


def transform(row: dict) -> dict:
    repaired = []

    event_date, date_repaired = repair_date(row.get("data"))
    if date_repaired:
        repaired.append("event_date")

    out = {
        "quarter_published": row["_q"],
        "event_date": event_date,
        "area": _s(row.get("area")),
        "enterprise_raw": _s(row.get("nameOfTheForestOwnerPermanentForestuser")),
        "forestry": _s(row.get("forestry")),
        "forest_quarter": _s(row.get("quarter")),
        "section": _s(row.get("section")),
        "composition": _s(row.get("pantationComposition")),
        "age": _s(row.get("age")),
        "bonitet": _s(row.get("bonus")),
        "security_category": _s(row.get("securityCategory")),
        "event_type": _s(row.get("typeOfPlannedEvents")).upper(),
        "reason_raw": _s(row.get("reasonsForTheEvent")),
    }
    out["enterprise"] = normalise_enterprise(out["enterprise_raw"])

    for target, source in NUMERIC_SOURCE.items():
        value, was_repaired = repair_number(_s(row.get(source)))
        if was_repaired:
            repaired.append(target)
        out[target] = value

    out["pine_share"] = pine_share(out["composition"])
    out["severity_ordinal"] = SEVERITY.get(out["event_type"], "")

    stock, cut = to_float(out["stock"]), to_float(out["cut_stock"])
    out["cut_share"] = round(cut / stock, 4) if stock and cut is not None and stock > 0 else ""

    reasons = classify_reason(out["reason_raw"])
    out["reason_biotic"] = int(reasons["biotic"])
    out["reason_abiotic"] = int(reasons["abiotic"])
    out["reason_fire"] = int(reasons["fire"])
    out["reason_unclassified"] = int(reasons["unclassified"])

    out["repaired"] = "|".join(repaired)
    return out


# ── CLI ────────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description="E.64 — санітизація + зріз області")
    ap.add_argument("--raw", default=str(HERE / "raw"))
    ap.add_argument("--out", default=str(HERE / "cherkasy_sanitary.csv"))
    ap.add_argument("--area", default="еркас", help="підрядок назви області (за замовчуванням Черкаська)")
    args = ap.parse_args()

    raw_dir = pathlib.Path(args.raw)
    if not raw_dir.is_dir():
        print(f"немає теки {raw_dir} — спершу `python3 tools/ground_truth/fetch.py`", file=sys.stderr)
        return 1

    rows, skipped = collect(raw_dir)
    if not rows:
        print(f"у {raw_dir} нема квартальних файлів (perelik_*.csv/json)", file=sys.stderr)
        return 1

    print("=== ДЖЕРЕЛО ===")
    per_quarter = collections.Counter(r["_q"] for r in rows)
    for label in sorted(per_quarter):
        print(f"  {label}: {per_quarter[label]:>7,} рядків")
    print(f"  РАЗОМ  : {len(rows):>7,}")
    for name, original in skipped:
        print(f"  ⏭  {name} — байтовий дубль {original} (SHA-256 збігається), не береться")

    sliced = [transform(r) for r in rows if args.area in (r.get("area") or "")]
    print(f"\n=== ЗРІЗ «{args.area}» ===")
    print(f"  рядків: {len(sliced):,}")

    repaired_rows = sum(1 for r in sliced if r["repaired"])
    field_hits = collections.Counter(
        f for r in sliced for f in r["repaired"].split("|") if f)
    print(f"  відновлено полів у {repaired_rows:,} рядках "
          f"({100.0 * repaired_rows / max(len(sliced), 1):.1f}%)")
    for field, count in field_hits.most_common():
        print(f"    {field:<32} {count:>6,}")

    raw_names = len({r["enterprise_raw"] for r in sliced})
    norm_names = len({r["enterprise"] for r in sliced})
    print(f"  підприємства: {raw_names} написань → {norm_names} одиниць після нормалізації")

    pine = [r for r in sliced if r["pine_share"] >= 8]
    print(f"  переважно соснових виділів (коеф. ≥ 8): {len(pine):,}")
    severity = collections.Counter(r["event_type"] for r in pine)
    for value, count in severity.most_common(6):
        print(f"    {value or '(порожньо)':<10} {count:>5,}")
    # Дві популяції друкуються поруч навмисно: §8.5 цитує частки по СОСНОВИХ
    # виділах, а зріз пишеться по всій області — без обох чисел звірка з каноном
    # порівнювала б різні множини й читалась як дрейф.
    for label, population in (("уся область", sliced), ("сосна ≥8", pine)):
        parts = []
        for name in ("biotic", "abiotic", "fire", "unclassified"):
            hits = sum(r[f"reason_{name}"] for r in population)
            parts.append(f"{name} {100.0 * hits / max(len(population), 1):.1f}%")
        print(f"  причини ({label:<11}, n={len(population):>5,}): " + " · ".join(parts))

    out_path = pathlib.Path(args.out)
    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUT_COLUMNS)
        writer.writeheader()
        writer.writerows(sliced)
    print(f"\n→ {out_path}  ({out_path.stat().st_size:,} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
