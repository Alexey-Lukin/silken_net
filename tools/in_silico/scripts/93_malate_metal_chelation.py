#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""93 — malate as a chelator of the ZIF cathode's metals in the cathode medium (00_07 HW.5.IS · 01_03 §3.5).

QUESTION. The cathode compartment's medium (⚖️ 2026-10-12, `01_03 §3.5`) is the sap's salts with malic acid at 10 mM,
pH 4.5, and that verdict's weakest link reads «констант малат–Cu/Co в дереві немає». How far does that malate raise the
dissolved share of each metal of the nanozyme — Cu(II), Co(II) and Ce(III) — at equilibrium?

THE NUMBER. α, the side-reaction coefficient of a TRACE metal M: dissolved M over free M = 1 + Σ β·Π[ligand]ⁿ. Against a
phase that fixes the free metal's activity, α is how many times the malate raises the dissolved metal over a
non-complexing buffer at the same pH and ionic strength.
  ⛔ α is an EQUILIBRIUM, not a leaching RATE: the framework's solubility, its proton-driven breakdown and the imidazole
     it releases are not in it.
  ⛔ It is the trace-metal limit — no metal–metal species; the onset of the Cu dimer (NIST 46) is printed beside it.

READINGS — a bracket of named readings, never a pick (in-silico §When Modifying #11); the ADVERSE end for the cathode is
the LARGEST α (the strongest pull of the metal into solution):
  constants — every set as printed in its source, at its own I and T (table `SETS` below, the source beside each row);
  pH 4.5 read three ways — (A) p[H] at the source's I, with the source's own ligand constants · (B) activity at the
     source's I, same ligand · (C) activity in the cathode medium itself: the free malate and hydrogen-malate from `67`'s
     speciation of `85`'s buffered medium, every metal constant Davies-shifted to that medium's I;
  competition — (C) runs over every documented Ca/Mg–malate reading of `67` (the set `85` uses); K–malate (NIST 46,
     I = 0) is printed as a side estimate, because `67` carries no K–malate species.
DERIVED here and named so: the Davies shifts (for the I = 0.2 readings past the equation's stated 0.1 — the same step
`67` takes for Günzel's constants); no temperature correction (no ΔH exists for the metal constants), so each set keeps
its source's T. The Davies step is checked on NIST's own I = 0 rows (`davies_check`).

Run:  python tools/in_silico/scripts/93_malate_metal_chelation.py      (seconds; no DFT)
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT

SI_DESCRIPTION = ("How strongly the cathode medium's malate (10 mM, pH 4.5) pulls the nanozyme's copper, cobalt and "
                  "cerium into solution at equilibrium: the side-reaction coefficient of each trace metal over every "
                  "stability-constant set read in its source.")  # its row in the paper SI (72): English, no repo jargon
SCRIPTS = Path(__file__).resolve().parent
OUT_JSON = CACHE_DIR / "chemistry" / "malate_metal_chelation.json"
PH = 4.5
T_MEDIUM_C = 25.0


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod            # 67 declares dataclasses, which look their module up by name
    spec.loader.exec_module(mod)
    return mod


S85 = _load("s85_iph", "85_electrode_interfacial_ph.py")  # the buffered cathode medium and the reading set — one home
S67 = S85.S67                                             # Davies and the medium's speciation — the SAME instance 85 uses

# ───────────────────────────── sources (each constant below was read in the source beside it) ─────────────────────────────
NIST46 = ("NIST SRD 46 v8.0 (Martell & Smith, critically selected), doi:10.18434/M32154 — SQL dump SRD_46_SQL.zip, "
          "sha256 141269bb8c6d9e8271a5b4bff35f7c9fa913938bb50a62c096847de67e382d18; values in parentheses are "
          "«questionable» (Users' Guide, Presentation conventions); row ids beside each value")
BUZKO = ("Buzko, Sukhno & Klimova (2004) Acta Chim. Slov. 51:213–222 — Table 3 p.220 (0.1 M KCl, 25 °C), ligand "
         "Table 2 p.216 («calculated in present work»); their HMal²⁻/H₂Mal⁻ = our L²⁻/HL⁻ (H₃Mal counts the OH proton)")
BUZKO_T1 = ("Buzko 2004 Table 1 p.216 — SECONDARY: values they cite, «contradictory … not critically estimated»; "
            "CeHMal⁺ (their notation) = our CeL⁺")
ZAB21 = ("Zabiszak et al. (2021) Molecules 26:5290, doi:10.3390/molecules26175290 — Table 2 (0.1 M KNO₃, 20 ± 1 °C), "
         "read in the PMC8433706 full text; log Kₑ column; their model has no CuL")

# Ligand constants as (log K of L²⁻ + H⁺ ⇌ HL⁻, log K of HL⁻ + H⁺ ⇌ H₂L), at the set's own I and T.
LIG = {"nist_25_0.1": (4.68, 3.24),   # NIST 46 rows 154695 · 154708 (25 °C; no 20 °C row — ΔH(HL) 1.3 kJ/mol at I = 0,
                                      # so a 5 K step moves it < 0.01)
       "buzko": (4.78, 3.26),         # Buzko Table 2, 0.1 M KCl, 298 K
       "zab21": (4.70, 3.22)}         # Zabiszak 2021 Table 2

# One term: (species label, log β, metal charge, {ligand: power}). Ligands: "L" = L²⁻, "HL" = HL⁻.
# A set: metal, source, T (°C), I (mol/L), ligand key (None = the set enters reading C only), quality, terms.
SETS = [
    {"key": "cu_nist_25", "metal": "Cu", "src": NIST46 + " — 154818 · 154826", "t": 25, "i": 0.1, "lig": "nist_25_0.1", "q": "critical",
         "terms": [("CuL", 3.64, 2, {"L": 1}), ("CuHL", 2.09, 2, {"HL": 1})]},
    {"key": "cu_nist_20", "metal": "Cu", "src": NIST46 + " — 154819 · 154827", "t": 20, "i": 0.1, "lig": "nist_25_0.1", "q": "critical",
         "terms": [("CuL", 3.42, 2, {"L": 1}), ("CuHL", 2.00, 2, {"HL": 1})]},
    {"key": "cu_zab21", "metal": "Cu", "src": ZAB21, "t": 20, "i": 0.1, "lig": "zab21", "q": "primary",
         "terms": [("CuHL", 4.26, 2, {"HL": 1}), ("Cu(HL)2", 5.89, 2, {"HL": 2})]},
    {"key": "co_nist_20", "metal": "Co", "src": NIST46 + " — 154813 · 154814", "t": 20, "i": 0.1, "lig": "nist_25_0.1", "q": "critical",
         "terms": [("CoL", 2.86, 2, {"L": 1}), ("CoHL", 1.64, 2, {"HL": 1})]},
    {"key": "co_zab21", "metal": "Co", "src": ZAB21, "t": 20, "i": 0.1, "lig": "zab21", "q": "primary",
         "terms": [("CoL", 3.06, 2, {"L": 1}), ("CoL2", 5.56, 2, {"L": 2})]},
    {"key": "ce_buzko", "metal": "Ce", "src": BUZKO, "t": 25, "i": 0.1, "lig": "buzko", "q": "primary (no β₂: CeL₂ not in their model)",
         "terms": [("CeL", 4.32, 3, {"L": 1}), ("CeHL", 2.09, 3, {"HL": 1})]},
    # Ce has no critically selected malate constant (NIST 46: «Published data do not meet the criteria»), and Buzko
    # prints no β₂ — the La and Pr neighbours' β₂ (NIST, «questionable») stand in for it as two readings.
    {"key": "ce_buzko_b2La", "metal": "Ce", "src": BUZKO + " + β₂ of La, " + NIST46 + " — 154776", "t": 25, "i": 0.1, "lig": "buzko",
         "q": "primary + neighbour β₂ (questionable)",
         "terms": [("CeL", 4.32, 3, {"L": 1}), ("CeHL", 2.09, 3, {"HL": 1}), ("CeL2 (La β₂)", 7.16, 3, {"L": 2})]},
    {"key": "ce_buzko_b2Pr", "metal": "Ce", "src": BUZKO + " + β₂ of Pr, " + NIST46 + " — 154782", "t": 25, "i": 0.1, "lig": "buzko",
         "q": "primary + neighbour β₂ (questionable)",
         "terms": [("CeL", 4.32, 3, {"L": 1}), ("CeHL", 2.09, 3, {"HL": 1}), ("CeL2 (Pr β₂)", 7.74, 3, {"L": 2})]},
    # The other Ce measurements Buzko cites — their ligand sets are not all printed, so they enter reading C only.
    {"key": "ce_t1_ref3", "metal": "Ce", "src": BUZKO_T1 + ", their ref 3 (0.2 M KCl, 25 °C)", "t": 25, "i": 0.2, "lig": None,
         "q": "secondary", "terms": [("CeL", 4.11, 3, {"L": 1})]},
    {"key": "ce_t1_ref6", "metal": "Ce", "src": BUZKO_T1 + ", their ref 6 (0.2 M NaClO₄, 25 °C)", "t": 25, "i": 0.2, "lig": None,
         "q": "secondary", "terms": [("CeL", 4.10, 3, {"L": 1})]},
    {"key": "ce_t1_ref10", "metal": "Ce", "src": BUZKO_T1 + ", their ref 10 (0.1 M KCl, 30 °C)", "t": 30, "i": 0.1, "lig": None,
         "q": "secondary", "terms": [("CeL", 5.00, 3, {"L": 1})]},
    {"key": "ce_t1_ref11", "metal": "Ce", "src": BUZKO_T1 + ", their ref 11 (0.2 M NaClO₄, 25 °C)", "t": 25, "i": 0.2, "lig": None,
         "q": "secondary", "terms": [("CeL", 5.23, 3, {"L": 1})]},
]
LIGAND_CHARGE = {"L": -2, "HL": -1}

# NIST 46 side constants (25 °C): K–malate at I = 0 (row 154728) for the competition estimate; the Cu dimer
# [Cu₂(H₋₁L)L][H]/[Cu]²[L]² at I = 0.1 (row 154834) for the trace-metal limit; and the I = 0 rows the Davies step is
# checked against (HL 154703 · H₂L 154715 · CuL 154823 · CuHL 154830).
K_MALATE_LOGK_I0 = 0.4
CU_DIMER_LOGK = 5.15
DAVIES_CHECK = [("HL⁻ (L²⁻ + H⁺)", 4.68, 5.097, 1, {"L": 1}), ("H₂L (HL⁻ + H⁺)", 3.24, 3.459, 1, {"HL": 1}),
                ("CuL", 3.64, 4.53, 2, {"L": 1}), ("CuHL", 2.09, 2.44, 2, {"HL": 1})]   # (name, I=0.1, I=0, z cation, powers)


def delta_z2(zm: int, powers: dict) -> int:
    """Σz²(reactants) − z²(product) of M + Σ n·ligand ⇌ complex — the Davies coefficient of a concentration constant
    (a protonation is the same with H⁺, z = 1, as the cation)."""
    return zm * zm + sum(n * LIGAND_CHARGE[lig] ** 2 for lig, n in powers.items()) - (
        zm + sum(n * LIGAND_CHARGE[lig] for lig, n in powers.items())) ** 2


def shift(log_k: float, dz2: int, i_from: float, i_to: float, t_c: float) -> float:
    """Concentration constant moved from i_from to i_to with Davies: log Kc(I₂) = log Kc(I₁) + Δz²·A·(f(I₁) − f(I₂))."""
    return log_k + dz2 * S67.davies_a(t_c + 273.15) * (S67.davies_f(i_from) - S67.davies_f(i_to))


def davies_check() -> list:
    """The Davies step, taken from NIST's I = 0.1 rows to I = 0, against NIST's own I = 0 rows (25 °C)."""
    out = []
    for name, k01, k0, z, powers in DAVIES_CHECK:
        got = shift(k01, delta_z2(z, powers), 0.1, 0.0, 25.0)
        out.append({"constant": name, "nist_I0.1": k01, "davies_to_I0": round(got, 3), "nist_I0": k0,
                    "diff": round(got - k0, 3)})
        # 0.1 is the measured worst miss (CuHL, 0.08 — two different measurement sets meet here, and Davies is an
        # approximation); a wrong Δz² or sign misses by 0.2–0.9, so the check still catches a broken step.
        assert abs(got - k0) < 0.1, f"Davies step misses NIST's own I = 0 row for {name}: {got:.3f} vs {k0}"
    return out


def ligand_at_source(s: dict, ph_is_activity: bool) -> dict:
    """Free L²⁻ and HL⁻ (mol/L) at the source's I with the source's own ligand constants — readings A and B (no
    competitors: the source's medium is an indifferent electrolyte)."""
    k_hl, k_h2l = LIG[s["lig"]]
    p_h = PH - S67.davies_a(s["t"] + 273.15) * S67.davies_f(s["i"]) if ph_is_activity else PH
    h = 10.0 ** -p_h
    c_t = S85.BUFFERED_MALIC_MM * 1e-3
    a1, a2 = h * 10.0 ** k_hl, h * h * 10.0 ** (k_hl + k_h2l)
    lig = c_t / (1.0 + a1 + a2)
    return {"L": lig, "HL": lig * a1, "p[H]": p_h, "ionic": s["i"]}


def ligand_in_medium(sc) -> dict:
    """Free L²⁻ and HL⁻ (mol/L) in `85`'s buffered cathode medium under one `67` reading — reading C."""
    model = S67.model_for(sc, T_MEDIUM_C)
    sol = S67.speciate(model, S85.TOTALS_BUFFERED, PH)
    return {"L": sol.free["Mal"], "HL": sol.conc["HMal-"], "ionic": sol.ionic_strength, "K_free": sol.free["K"],
            "p[H]": PH + sol.log_gamma[1], "Ca_held_by_malate": sol.conc.get("CaMal0", 0.0),
            "Mg_held_by_malate": sol.conc.get("MgMal0", 0.0)}


def alpha(s: dict, lig: dict, i_to: float) -> tuple[float, list]:
    terms, total = [], 1.0
    for name, log_b, z, powers in s["terms"]:
        lk = shift(log_b, delta_z2(z, powers), s["i"], i_to, s["t"]) if i_to != s["i"] else log_b
        val = 10.0 ** lk * math.prod(lig[k] ** n for k, n in powers.items())
        terms.append({"species": name, "log_beta_source": log_b, "log_beta_used": round(lk, 3), "contribution": val})
        total += val
    return total, terms


def main() -> int:
    checks = davies_check()
    readings = {}
    for s in SETS:
        rows = {}
        if s["lig"]:
            for tag, act in (("A_p[H]_at_source_I", False), ("B_activity_at_source_I", True)):
                lig = ligand_at_source(s, act)
                a, terms = alpha(s, lig, s["i"])
                rows[tag] = {"alpha": a, "ionic": s["i"], "p[H]": round(lig["p[H]"], 3), "terms": terms}
        for sc in S85.READINGS:
            lig = ligand_in_medium(sc)
            a, terms = alpha(s, lig, lig["ionic"])
            rows[f"C_medium|{sc.key}"] = {"alpha": a, "ionic": round(lig["ionic"], 5), "p[H]": round(lig["p[H]"], 3),
                                          "terms": terms}
        readings[s["key"]] = {"metal": s["metal"], "source": s["src"], "T_C": s["t"], "I_source": s["i"],
                              "quality": s["q"], "rows": rows}

    by_metal = {}
    for m in ("Cu", "Co", "Ce"):
        cells = [(k, tag, r["alpha"]) for k, v in readings.items() if v["metal"] == m for tag, r in v["rows"].items()]
        primary = [c for c in cells if readings[c[0]]["quality"] != "secondary"]
        lo, hi = min(cells, key=lambda c: c[2]), max(cells, key=lambda c: c[2])
        by_metal[m] = {"alpha_min": lo[2], "alpha_min_at": f"{lo[0]} · {lo[1]}",
                       "alpha_max_ADVERSE": hi[2], "alpha_max_at": f"{hi[0]} · {hi[1]}",
                       "alpha_max_without_secondary": max(c[2] for c in primary),
                       "medium_selected": {k: v["rows"]["C_medium|selected"]["alpha"] for k, v in readings.items()
                                           if v["metal"] == m}}

    # Competition: what the Ca/Mg readings do to free L²⁻ in the medium, and the K–malate side estimate.
    med = {sc.key: ligand_in_medium(sc) for sc in S85.READINGS}
    sel = med["selected"]
    k_kl = 10.0 ** shift(K_MALATE_LOGK_I0, delta_z2(1, {"L": 1}), 0.0, sel["ionic"], 25.0)
    competition = {
        "free_L_mM_by_reading": {k: round(v["L"] * 1e3, 4) for k, v in med.items()},
        "free_L_spread_vs_selected": round(min(v["L"] for v in med.values()) / sel["L"] - 1.0, 4),
        "K_free_mM": round(sel["K_free"] * 1e3, 3),
        "K_malate_would_hold_fraction_of_free_L": round(k_kl * sel["K_free"], 4),
        "K_malate_note": "NIST 46 K⁺–L²⁻ log K 0.4 at I = 0 (row 154728), Davies-shifted to the medium; not in 67's "
                         "model — the fraction by which α's 1:1 terms would drop",
    }

    # Trace-metal limit for Cu: the free Cu at which the dimer holds 10 % of what CuL holds (reading A, NIST 25 °C).
    cu = next(s for s in SETS if s["key"] == "cu_nist_25")
    lig_a = ligand_at_source(cu, False)
    k1 = 10.0 ** cu["terms"][0][1]
    ratio_per_m = 2.0 * 10.0 ** CU_DIMER_LOGK * lig_a["L"] / (10.0 ** -PH) / k1
    cu_free = 0.1 / ratio_per_m
    a_cu = readings["cu_nist_25"]["rows"]["A_p[H]_at_source_I"]["alpha"]
    trace_limit = {"cu_free_at_10pct_dimer_uM": round(cu_free * 1e6, 2),
                   "cu_dissolved_there_uM": round(a_cu * cu_free * 1e6, 1),
                   "cu_dissolved_there_mg_L": round(a_cu * cu_free * 63.546e3, 2),
                   "source": NIST46 + " — 154834 (25 °C, I = 0.1), reading A"}

    i_med = sel["ionic"]
    i_85 = json.loads((CACHE_DIR / "kinetics" / "electrode_interfacial_ph.json").read_text())[
        "cathode"]["media"]["buffered_pH4.5"]["ionic_strength_25C"]
    assert abs(round(i_med, 4) - i_85) < 1e-4, f"the medium here (I {i_med:.4f}) is not 85's ({i_85})"

    order = {r: sorted(("Cu", "Co", "Ce"), key=lambda m: by_metal[m][r]) for r in ("alpha_min", "alpha_max_ADVERSE")}
    out = {
        "what": "side-reaction coefficient α of trace Cu(II) · Co(II) · Ce(III) in the cathode medium (malic acid 10 mM, "
                "the sap's salts, pH 4.5) — EQUILIBRIUM, not a leaching rate; trace-metal limit",
        "medium": {"totals_mM": S85.TOTALS_BUFFERED, "pH": PH, "ionic_strength_selected": round(i_med, 5),
                   "matches_85": True},
        "davies_check": checks,
        "davies_step_error": {"worst_miss_0.1_to_0": max(abs(c["diff"]) for c in checks),
                              "medium_step_share": round((S67.davies_f(0.1) - S67.davies_f(i_med)) / S67.davies_f(0.1), 3),
                              "reading": "the derived 0.1 → medium step is this share of the checked 0.1 → 0 one, so "
                                         "its error in log K scales by it"},
        "readings": readings,
        "by_metal": by_metal,
        "order_low_to_high": order,
        "competition": competition,
        "trace_metal_limit_cu": trace_limit,
        "bounds": "α counts complexation only: the ZIF's solubility, its proton-driven breakdown and released "
                  "imidazole are outside it; constants keep their source T (no ΔH)",
    }
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")

    print("=== Davies step vs NIST's own I = 0 rows ===")
    for c in checks:
        print(f"  {c['constant']:18s} {c['nist_I0.1']} → {c['davies_to_I0']} (NIST I=0: {c['nist_I0']}, Δ {c['diff']:+.3f})")
    print(f"\n=== α at 10 mM malate, pH 4.5 (medium I = {i_med:.4f}, matches 85) ===")
    for k, v in readings.items():
        cells = "  ".join(f"{t.split('|')[0][:1]}{'' if '|' not in t else ':' + t.split('|')[1][:14]}={r['alpha']:.3g}"
                          for t, r in v["rows"].items())
        print(f"  {k:15s} [{v['quality'][:9]}] {cells}")
    for m, b in by_metal.items():
        print(f"  {m}: α {b['alpha_min']:.3g} … {b['alpha_max_ADVERSE']:.3g} (adverse at {b['alpha_max_at']}); "
              f"without secondary readings ≤ {b['alpha_max_without_secondary']:.3g}")
    print(f"  order low→high: at the low ends {order['alpha_min']}, at the adverse ends {order['alpha_max_ADVERSE']}")
    print(f"\n  competition: free L²⁻ across 67's Ca/Mg readings moves by ≤ {abs(competition['free_L_spread_vs_selected']):.1%}; "
          f"K–malate would hold {competition['K_malate_would_hold_fraction_of_free_L']:.1%} of free L²⁻ (not in 67)")
    print(f"  trace limit: the Cu dimer reaches 10 % of CuL at free Cu {trace_limit['cu_free_at_10pct_dimer_uM']} µM "
          f"(dissolved ≈ {trace_limit['cu_dissolved_there_mg_L']} mg/L)")
    print(f"  saved → {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
