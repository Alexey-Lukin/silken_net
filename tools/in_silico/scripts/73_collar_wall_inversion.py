#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.33 — Підстава стінки коміра байонета, ІНВЕРСІЄЮ (00_07 HW.33, нога «підстава стінки»).

⚖️ Прогін дозволено винятком із ⏸ паузи крони — ратифіковано founder 2026-10-01
(преамбула §01a; прецедент — виняток для теплової огинаючої HW.37, 09-26). Підстава
винятку: власна підстава паузи («решта невизначеності крони є входом ЗЗОВНІ») цього
предмета не покриває — питання стінки розсуджує модель дерева (інверсією; сили утримання
в дереві немає), не вендор.

🔑 ЧОМУ ІНВЕРСІЯ, А НЕ ПРЯМИЙ РОЗРАХУНОК. Нога просить «модель навантаження байонета»,
але сили, якою його навантажують, у дереві НЕМА і вона не обчислювана сьогодні: 02_02
§4.1 перелічує вимоги утримання без жодної сили, а `52_z_stack_tolerance.rim_datum_creep`
прямо каже, що навантаження O-ring на одиницю довжини ущільнення дому в каноні не має.
⛔ І ті «100 Н», що стоять у 52, НЕ є виміром — це СВІДОМО ЩЕДРИЙ здогад, уведений як
МЕЖА для іншого питання (чи треба моделювати крип обода). Узяти його сюди як силу
означало б рівно той клас, проти якого стоїть 00_01 §1.1: число, підставлене для одного
питання, прочитане як вимір для другого.

Тому ми не рахуємо силу, якої не маємо, а рахуємо, ЗА ЯКОЇ СИЛИ стінка взагалі стає
обмежувачем — той самий хід, яким дерево вже розсудило обід (52 §rim_datum_creep) і шов
шини (55 §weld_seam). Якщо навіть друкована підлога з запасом тримає ЩЕДРУ межу
правдоподібної сили утримання, то стінку задає ДРУКОВНІСТЬ, а не міцність, і нога
закривається без відсутнього датума.

ТРИ ВИПАДКИ НАВАНТАЖЕННЯ (кожен — інверсією):
  A. Осьове утримання   — кільце коміра на розтяг; нетто-переріз за вирахуванням пазів.
  B. Зріз кореня вушка  — локальний член, бо вушко є саме тим, що навантажують.
  C. ЗАМКНЕНИЙ ЛІД      — випадок FMEA `#26` (RPN 504). Тут інверсія не потрібна: стеля
                          тиску фізична й самообмежена, і саме вона дає вирок.

⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС (інакше зелений прогін почне означати «міцність доведено»):
  - це замкнені форми на ідеалізаціях, НЕ FE: кільце рахується як призматичний переріз,
    вушко — як зріз по кореню, лід — як рівномірний радіальний тиск. Концентрацій
    напружень у галтелі вушка модель НЕ несе (їх дає FEA, 00_07 HW.26);
  - ВТРАТИ СТІЙКОСТІ короткого кільця під зовнішнім тиском модель НЕ рахує: формула
    довгого циліндра для коміра 3.5 мм, затисненого знизу товстим фланцем, дала б
    абсурдно низьку межу, а коректна оболонкова потребує довжини й крайових умов → FE.
    Висновок випадку C на неї не спирається (він стоїть на текучості, яку лід перевищує
    навіть на найтовшій стінці смуги — у 2.1× при 1.6 мм), але для ВИБОРУ стінки під
    реальним тиском вона була б несучою;
  - втому модель не судить взагалі (цикли монтажу/зняття, гойдання) — 00_07 HW.23;
  - геометрія коміра в дереві ще не змодельована (сам предмет ноги), тож смуга сокета
    береться з маніфестів і кешу 52, а не з рендера.
Канон: 02_02 §4.1/§4.4 (байонет) · 01_02 (сплав) · 00_07 HW.33 · HW.36 (FMEA `#26`).
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.constants import ALLOY_PROPERTIES
from lib.utils import banner

CEM = Path(__file__).resolve().parents[2] / "cad" / "cem"
CACHE = Path(__file__).resolve().parents[1] / "cache" / "mechanical"
OUT = CACHE / "collar_wall_inversion.json"

# ── Сплав: BASELINE-якір, не обраний сплав (down-select — coin bake-off, 00_07 HW.24) ──
ALLOY = "Ti-6Al-4V"
YIELD_MPA = ALLOY_PROPERTIES[ALLOY]["yield_MPa"]

# Коефіцієнт запасу. ⚠️ Числа SF канон для цього вузла не задає — 2.0 є ОГОЛОШЕНИМ
# вибором цього скрипта, і всі вироки нижче друкуються разом із ним.
SAFETY_FACTOR = 2.0

# Зріз по дотичних напруженнях: межа текучості на зріз ≈ σ_y/√3 (критерій фон Мізеса).
SHEAR_YIELD_FACTOR = 1.0 / math.sqrt(3.0)

# ── Лід у замкненій кишені (FMEA `#26`) ───────────────────────────────────────────
# Тиск САМООБМЕЖЕНИЙ: уздовж кривої плавлення лід I існує лише до потрійної точки
# лід I / лід III / вода (≈ −21.985 °C, ≈ 209.9 МПа). Нижче цієї температури
# утворюється ЩІЛЬНІШИЙ лід III, і подальше охолодження тиск уже не підіймає.
# ⚠️ Це СТЕЛЯ цілком замкненої, цілком заповненої й абсолютно жорсткої порожнини —
# реальна кишеня піддатлива й заповнена частково, тож дійсний тиск НИЖЧИЙ. Стеля
# вжита саме як стеля: якщо навіть вона не дає стінки, що влазить, лік лежить не в
# стінці (див. вирок).
ICE_I_III_LIQUID_TRIPLE_MPA = 209.9
ICE_I_III_LIQUID_TRIPLE_C = -21.985

# ── Сили, які дерево ВСЕ Ж знає — для порівняння з break-even ──────────────────────
POGO_SPRING_FORCE_N = 0.96   # на пін при повному ході (02_02 §2.2) — верхня межа
POGO_PIN_COUNT = 2           # центр (GND) + зовнішнє кільце (V+), 02_02 §1.2
# ⛔ Не вимір, а щедра МЕЖА з 52 §rim_datum_creep — вживається лише як орієнтир.
GENEROUS_ORING_BOUND_N = 100.0

WALL_CANDIDATES_MM = (0.2, 0.3, 0.5, 0.8, 1.0, 1.6)


def cem(stem: str) -> dict:
    return json.loads((CEM / f"{stem}.json").read_text())


def socket_pocket(dome_mm: float, wall_mm: float, lug_r_mm: float, slot_clr_mm: float) -> tuple:
    """Кишеня сокета — замкнена форма `Radome.cs`, не власна: смуга = r_lug + зазор
    (`SocketBandMm`), скін = стінка купола − смуга (`SocketSkinMm`), кишеня r від
    dome/2 − смуга (`SocketPocketInnerRMm`) до dome/2 − скін (`SocketPocketOuterRMm`)."""
    band = lug_r_mm + slot_clr_mm
    skin = wall_mm - band
    return band, skin, dome_mm / 2.0 - band, dome_mm / 2.0 - skin


# Позитивний контроль ери Ø25 — ЗАМОРОЖЕНИЙ вихід, не формула: кеш 52 на коміті a9b92b00c
# (`applied_gland.socket_pocket_r_mm` = [10.7, 12.3], скін 0.2), який xUnit
# `Rim_Boss_And_Gland_Derivation_Matches_Script_52_Cache` тоді пінив до `Radome.SocketPocket*RMm`,
# на вході radome.json тієї ери (купол 25.0 · стінка 2.0 · r_lug 1.5 · зазор 0.3).
ERA_D25_INPUTS = (25.0, 2.0, 1.5, 0.3)
ERA_D25_POCKET_R = (10.7, 12.3)


def geometry() -> dict:
    """Смуга сокета й висота коміра — з маніфестів (формула Radome.cs), звірені з кешем 52.

    ПОЗИТИВНИЙ КОНТРОЛЬ — два assert'и проти двох незалежних від цієї функції референтів:
      1. заморожений вихід ери Ø25 (10.7–12.3) — не рухається разом із маніфестами;
      2. живий `applied_gland.socket_pocket_r_mm` кешу 52 на Ø29.8 (13.1–14.7), який xUnit пінить
         до `Radome.SocketPocket*RMm`, тобто до геометрії, що справді вокселізується.
    ЛОВИТЬ: формулу кишені, що розійшлась із Radome.cs, і кеш 52, застарілий відносно radome.json
    (падає №2). Саме так стояв вхід до 2026-10-01: скін = slot_clearance 0.3 замість стінка − смуга
    0.2 давав кишеню 10.8 і 13.2 — смуга 1.5 замість 1.6, і контролю, що це спіймав би, не було
    (мутацію «скін = зазор» №1 тепер ловить: 12.2 ≠ 12.3).
    НЕ ЛОВИТЬ: хибне значення в radome.json (вхід спільний для всіх трьох), Radome.cs і 52, що
    розійшлися з дійсністю РАЗОМ (xUnit тримає їх рівними, не правими), і геометрію самого коміра —
    її не змодельовано на жодній деталі (02_02 §4.4).
    """
    flange, radome = cem("cathode_flange"), cem("radome")
    z = json.loads((CACHE / "z_stack_tolerance.json").read_text())
    socket_band, skin, r_inner, r_outer = socket_pocket(
        radome["dome_diameter_mm"], radome["wall_thickness_mm"],
        radome["lug_radius_mm"], radome["slot_clearance_mm"])
    era = socket_pocket(*ERA_D25_INPUTS)[2:]
    assert all(abs(a - b) < 1e-6 for a, b in zip(era, ERA_D25_POCKET_R, strict=True)), \
        f"кишеня ери Ø25 {era} ≠ {ERA_D25_POCKET_R} (Radome.cs на a9b92b00c)"
    live = z["applied_gland"]["socket_pocket_r_mm"]
    assert abs(r_inner - live[0]) < 1e-3 and abs(r_outer - live[1]) < 1e-3, \
        f"кишеня r {r_inner:.3f}–{r_outer:.3f} ≠ кеш 52 {live} (Radome.SocketPocket*RMm)"
    return {
        "alloy": ALLOY,
        "flange_diameter_mm": flange["flange_diameter_mm"],
        "socket_band_mm": round(socket_band, 3),
        "socket_skin_mm": round(skin, 3),
        "band_r_inner_mm": round(r_inner, 3),
        "band_r_outer_mm": round(r_outer, 3),
        "band_r_mean_mm": round((r_inner + r_outer) / 2.0, 3),
        "collar_height_mm": radome["lock_groove_z_mm"],
        "bayonet_lugs": flange["bayonet_lugs"],
        "lug_radius_mm": flange["lug_radius_mm"],
        "lug_protrusion_mm": flange["lug_protrusion_mm"],
    }


def case_a_axial_retention(g: dict) -> dict:
    """A. Кільце коміра на осьовий розтяг — break-even сила для кожної стінки.

    Нетто-переріз: повна кільцева площа МІНУС вхідні пази байонета. Пазів стільки ж,
    скільки вушок, і консервативно беремо ширину паза рівною ширині вушка (2·r_lug).
    """
    sigma_allow = YIELD_MPA / SAFETY_FACTOR
    r_mean = g["band_r_mean_mm"]
    slot_arc_total = g["bayonet_lugs"] * 2.0 * g["lug_radius_mm"]
    circumference = 2.0 * math.pi * r_mean
    net_fraction = max(0.0, (circumference - slot_arc_total) / circumference)
    rows = []
    for t in WALL_CANDIDATES_MM:
        area_net = circumference * t * net_fraction
        rows.append({
            "wall_mm": t,
            "net_area_mm2": round(area_net, 2),
            "breakeven_force_N": round(sigma_allow * area_net, 0),
        })
    return {
        "sigma_allow_MPa": sigma_allow,
        "net_section_fraction": round(net_fraction, 3),
        "slot_arc_total_mm": round(slot_arc_total, 2),
        "rows": rows,
        "idealisation": "призматичне кільце на чистий розтяг; згину від ексцентриситету вушка немає",
    }


def case_b_lug_root_shear(g: dict) -> dict:
    """B. Зріз кореня вушка — локальний член, бо навантажують саме вушко.

    Площа зрізу одного вушка по кореню ≈ ширина вушка (2·r_lug) × стінка коміра:
    вушко відривається вздовж стінки, на якій сидить.
    """
    tau_allow = YIELD_MPA * SHEAR_YIELD_FACTOR / SAFETY_FACTOR
    rows = []
    for t in WALL_CANDIDATES_MM:
        area_one = 2.0 * g["lug_radius_mm"] * t
        rows.append({
            "wall_mm": t,
            "shear_area_all_lugs_mm2": round(area_one * g["bayonet_lugs"], 2),
            "breakeven_force_N": round(tau_allow * area_one * g["bayonet_lugs"], 0),
        })
    return {
        "tau_allow_MPa": round(tau_allow, 1),
        "rows": rows,
        "idealisation": "чистий зріз по кореню; концентрації в галтелі НЕ модельовано (FEA — HW.26)",
    }


def case_c_confined_ice(g: dict) -> dict:
    """C. Замкнений лід у кишені сокета (FMEA `#26`) — вирок дає СТЕЛЯ, не інверсія.

    Кільце коміра під рівномірним радіальним тиском: σ_hoop = p·r/t. Питаємо стінку,
    потрібну при стелі тиску, і порівнюємо з радіальним простором, який узагалі є.
    """
    sigma_allow = YIELD_MPA / SAFETY_FACTOR
    p = ICE_I_III_LIQUID_TRIPLE_MPA
    r = g["band_r_mean_mm"]
    t_required = p * r / sigma_allow
    space = g["socket_band_mm"] - g["socket_skin_mm"]
    rows = [{
        "wall_mm": t,
        "hoop_stress_at_ceiling_MPa": round(p * r / t, 0),
        "over_yield_x": round((p * r / t) / YIELD_MPA, 1),
    } for t in WALL_CANDIDATES_MM]
    return {
        "pressure_ceiling_MPa": p,
        "ceiling_at_C": ICE_I_III_LIQUID_TRIPLE_C,
        "ceiling_is_self_limiting": "вище цього тиску утворюється щільніший лід III, тож подальше "
                                    "охолодження тиск НЕ підіймає",
        "required_wall_at_ceiling_mm": round(t_required, 1),
        "radial_space_available_mm": round(space, 2),
        "fits": bool(t_required <= space),
        "rows": rows,
        "idealisation": "рівномірний радіальний тиск, текучість по колу; втрати стійкості НЕ модельовано",
    }


def verdict(a: dict, b: dict, c: dict, g: dict) -> dict:
    floor = WALL_CANDIDATES_MM[0]
    a_floor = next(r for r in a["rows"] if r["wall_mm"] == floor)["breakeven_force_N"]
    b_floor = next(r for r in b["rows"] if r["wall_mm"] == floor)["breakeven_force_N"]
    binding = "A — осьове утримання" if a_floor < b_floor else "B — зріз кореня вушка"
    governing_floor_N = min(a_floor, b_floor)
    return {
        "binding_static_case": binding,
        "capacity_at_print_floor_N": governing_floor_N,
        "margin_x_over_generous_oring_bound": round(governing_floor_N / GENEROUS_ORING_BOUND_N, 1),
        "margin_x_over_pogo_pair": round(governing_floor_N / (POGO_SPRING_FORCE_N * POGO_PIN_COUNT), 0),
        "static": (f"СТАТИКА СТІНКИ НЕ ЗАДАЄ: уже на друкованій підлозі звʼязувальний випадок тримає "
                   f"{governing_floor_N:.0f} Н — це "
                   f"{round(governing_floor_N / GENEROUS_ORING_BOUND_N, 1)}× ЩЕДРОЇ межі 100 Н і "
                   f"{round(governing_floor_N / (POGO_SPRING_FORCE_N * POGO_PIN_COUNT)):.0f}× єдиної пружини, "
                   f"яку канон задає. ⚠️ Запас проти щедрої межі — кілька разів, НЕ «порядки»: порядки є лише "
                   f"проти pogo. Але він уже містить SF {SAFETY_FACTOR}, тож до самої текучості вдвічі більше. "
                   f"Тож стінку задає ДРУКОВНІСТЬ (SLM-підлога) або механообробка на CNC-маршруті, не міцність — "
                   f"і відсутній датум O-ring перестає бути блокером САМЕ ТОМУ, що щедра межа вже перекрита."),
        "ice": ("ЛІД ЗАДАЄ, І НЕ СТІНКОЮ: при стелі тиску потрібна стінка "
                f"{c['required_wall_at_ceiling_mm']} мм проти {c['radial_space_available_mm']} мм радіального "
                "простору, що взагалі є. Жодна стінка, яка влазить у смугу сокета, замкненого льоду не тримає, "
                "тож єдиний важіль — ДРЕНАЖ кишень, а не товщина. Це той самий лік, який FMEA `#26` уже "
                "називає передусім дизайнерським."),
        "answer_to_the_leg": "підставою стінки коміра є ДРУКОВНІСТЬ плюс вимога дренажу; сили утримання "
                             "для її вибору не потрібно, і відсутній датум O-ring перестає бути блокером.",
    }


def main() -> int:
    g = geometry()
    a = case_a_axial_retention(g)
    b = case_b_lug_root_shear(g)
    c = case_c_confined_ice(g)
    v = verdict(a, b, c, g)

    banner("HW.33 — стінка коміра байонета, ІНВЕРСІЄЮ (сили утримання в дереві немає)")
    print(f"  сплав {g['alloy']} (BASELINE-якір): σ_y = {YIELD_MPA} МПа, SF = {SAFETY_FACTOR} "
          f"(SF — оголошений вибір скрипта, не канон)")
    print(f"  смуга сокета r {g['band_r_inner_mm']}–{g['band_r_outer_mm']} мм, комір {g['collar_height_mm']} мм, "
          f"{g['bayonet_lugs']} вушка r {g['lug_radius_mm']} мм")

    print("\n── A. Осьове утримання: за якої сили стінка стає обмежувачем ──")
    for r in a["rows"]:
        print(f"     стінка {r['wall_mm']:.1f} мм → нетто {r['net_area_mm2']:6.2f} мм² → "
              f"break-even {r['breakeven_force_N']:>8.0f} Н")

    print("\n── B. Зріз кореня вушка ──")
    for r in b["rows"]:
        print(f"     стінка {r['wall_mm']:.1f} мм → зріз {r['shear_area_all_lugs_mm2']:6.2f} мм² → "
              f"break-even {r['breakeven_force_N']:>8.0f} Н")

    print("\n── C. Замкнений лід (FMEA #26): вирок дає СТЕЛЯ, не інверсія ──")
    print(f"     стеля тиску {c['pressure_ceiling_MPa']} МПа при {c['ceiling_at_C']} °C — самообмежена")
    for r in c["rows"]:
        print(f"     стінка {r['wall_mm']:.1f} мм → кільцеве {r['hoop_stress_at_ceiling_MPa']:>7.0f} МПа "
              f"= {r['over_yield_x']:>5.1f}× текучості")
    print(f"     потрібна стінка при стелі: {c['required_wall_at_ceiling_mm']} мм проти "
          f"{c['radial_space_available_mm']} мм простору → влазить: {c['fits']}")

    print("\n── Вирок ──")
    print(f"  зв'язує зі статики: {v['binding_static_case']} — {v['capacity_at_print_floor_N']:.0f} Н "
          f"уже на друкованій підлозі ({v['margin_x_over_generous_oring_bound']}× щедрої межі 100 Н, "
          f"{v['margin_x_over_pogo_pair']:.0f}× пари pogo)")
    print(f"  1. {v['static']}")
    print(f"  2. {v['ice']}")
    print(f"  → {v['answer_to_the_leg']}")

    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "geometry": g,
        "safety_factor": SAFETY_FACTOR,
        "alloy_yield_MPa": YIELD_MPA,
        "case_a_axial_retention": a,
        "case_b_lug_root_shear": b,
        "case_c_confined_ice": c,
        "verdict": v,
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"\n  кеш → {OUT.relative_to(Path.cwd()) if OUT.is_relative_to(Path.cwd()) else OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
