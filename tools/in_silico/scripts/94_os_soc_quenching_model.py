#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""94 — how far a low-symmetry t2g splitting quenches the spin–orbit shift of the Os(II/III) couple (one-hole model, no SCF).

WHY. Every cell of the like-for-like cascade (95) shares a scalar-relativistic Os; spin–orbit coupling (SOC), the one omitted
term of known sign, lowers E°(Os) by ≈ 300 mV in octahedral homoleptic complexes (lib.constants OS_SOC_SHIFT_V) and turns
the first cell uphill beyond 95's `shared_shifts.terms.spin_orbit_os.first_flip_at_V`. The device complex is C₁ and
heteroleptic, so its t2g levels are split and SOC is partly quenched. This script turns that weakest link into a THRESHOLD
on the t2g splitting: how large a splitting keeps the quenched shift below the first-flip margin.

MODEL. Low-spin d⁵ = one hole in t2g. Hamiltonian of the t2g electron levels: diag(ε₁, ε₂, ε₃) ⊗ 1₂ + ζ L·S (real d basis,
l = 2, restricted to xy · yz · xz); the hole sits in the highest level (on Os by 92 %: Mulliken spin density 0.917–0.925 in the relaxed caches), so
the SOC stabilisation of the Os(III) ground state
is max eig(H) − max ε. In Oh it equals ζ (doublet–quartet split 3ζ/2), so ζ = ⅔ × Srnec's Os³⁺ splitting
(OS3_SOC_SPLIT_CM1). f = stabilisation / ζ. Two normalisations bound the shift: A — the whole −300 mV scales with f;
B — only ζ scales and the remainder (−300 mV − ζ: by Srnec «the main contribution» is the M³⁺ splitting, the rest is taken
as an unquenched second-order Os(II) term) stays. Patterns: «one up» (the hole on a single orbital Δ above a pair),
«two up» (the hole on a pair Δ above the third orbital), and a rhombic grid (the upper pair at D, itself split by δ).

CALIBRATION (⊕ 2026-10-20, 00_07 HW.5.IS, the literature pass ⚖️ (з)). Srnec et al. 2008 (ref 63) tabulate in their SI
(Table S2, CASSCF(5,3)/CASPT2/CASSI) for six Os(II/III) couples the two excited ²A states of the t2g hole WITHOUT SOC —
the scalar levels this model takes as input — and the SOC shift of E° each one gets. Fed those levels, the model is read
three ways against them: A and B (above) under-predict EVERY row, by tens to over a hundred mV, because they anchor the
unquenched shift to the abstract's «≈ 300 mV» while the model's own octahedral stabilisation is ζ, 343–418 meV here; C —
the stabilisation itself, ζ·f — at the upper ζ reproduces five rows within a dozen mV and misses [Os(CN)₆] by sixty, at
the lower ζ it under-predicts every row. Only C at the upper ζ is a reading ref 63 supports; its thresholds are printed
beside A and B, which stay for the record and are NOT a criterion. Ref 63's own row for [Os(bipy)₃], the closest ligand
set it treats, is past the first-flip margin.

CAN: say, inside this model, which t2g splitting keeps every like-for-like cell downhill with SOC. CANNOT: (1) give the
device complex's splitting — no cache holds its t2g levels (the Os(III) UKS HOMO–LUMO gap is an exchange-inflated
occupied→hole gap, ≈ 2 eV, and must NOT be read as Δ); (2) replace a SOC calculation — ζ is carried over from Srnec's
homoleptic set (octahedral and tris-chelate, so f = 1 at Δ = 0 is itself an approximation), covalency is as in his value,
and the second-order term is a normalisation choice, not a computed one.

Run:  conda activate silken_md
      python tools/in_silico/scripts/94_os_soc_quenching_model.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, OS3_SOC_SPLIT_CM1, OS_SOC_SHIFT_V, REPO_ROOT, SRNEC_TABLE_S2_OS
from lib.utils import banner

SI_DESCRIPTION = ("L3 spin–orbit quenching of the Os(II/III) couple: one-hole t2g model with ζ from the literature Os³⁺ "
                  "splitting, the t2g splitting that keeps the SOC-shifted like-for-like cascade (95) downhill, under three "
                  "normalisations checked against the six Os couples of Srnec et al. 2008 (SI Table S2) — only the "
                  "stabilisation itself at the upper ζ reproduces them — and three splitting patterns; no SCF")

OUT = DFT_CACHE / "os_soc_quenching_model.json"
# The literature pass ⚖️ (з), 2026-10-20: low-spin Os(III) analogues with a measured or fitted t2g splitting — the ground of
# «no analogue found reaches the C threshold». Neither is the device complex; each carries how it was read.
ANALOGUES_READ = [
    {"complex": "[Os(bpy)3]3+", "what": "two interconfigurational (dpi->dpi) near-IR bands, cm-1", "value": [4580, 5090],
     "source": "Kober & Meyer 1983, Inorg. Chem. 22, 1614 — quoted by D'Alessandro et al. 2006, Inorg. Chem. 45, 3261",
     "access": "second-hand: D'Alessandro's full text read; the primary's first page only (it states a 2A1 ground state)"},
    {"complex": "low-spin Os(III) chlorido / ammine / indazole complexes", "what": "|Delta/zeta| from EPR g-tensor fits",
     "value": [0.23, 0.50],
     "source": "Buchel et al. 2017, Dalton Trans. 46, 11925, Table 4 (McGarvey t2g-hole analysis)", "access": "full text read"},
]

CM1_PER_EV = 8065.544


def _l_dot_s() -> np.ndarray:
    """ζ-free L·S on the t2g spin-orbitals (xy, yz, xz) ⊗ (α, β), built from the l = 2 matrices in the real d basis."""
    s2 = np.sqrt(2.0)
    u = np.zeros((5, 5), complex)          # rows: xy, yz, z², xz, x²−y²; columns: m = 2, 1, 0, −1, −2
    u[0, 0], u[0, 4] = -1j / s2, 1j / s2
    u[1, 1], u[1, 3] = 1j / s2, 1j / s2
    u[2, 2] = 1.0
    u[3, 1], u[3, 3] = -1 / s2, 1 / s2
    u[4, 0], u[4, 4] = 1 / s2, 1 / s2
    m = np.array([2, 1, 0, -1, -2])
    lz = np.diag(m).astype(complex)
    lp = np.zeros((5, 5), complex)
    for i in range(1, 5):
        lp[i - 1, i] = np.sqrt(6 - m[i] * (m[i] + 1))
    lm = lp.conj().T
    t2g = [0, 1, 3]
    ls = [(u @ a @ u.conj().T)[np.ix_(t2g, t2g)] for a in ((lp + lm) / 2, (lp - lm) / 2j, lz)]
    sp = [np.array([[0, 1], [1, 0]]) / 2, np.array([[0, -1j], [1j, 0]]) / 2, np.array([[1, 0], [0, -1]]) / 2]
    return sum(np.kron(ls[k], sp[k]) for k in range(3))


LS = _l_dot_s()


def stabilisation(levels_over_zeta: tuple[float, float, float]) -> float:
    """SOC stabilisation of the t2g⁵ ground state, in units of ζ (the hole in the highest electron level)."""
    h0 = np.kron(np.diag(levels_over_zeta), np.eye(2))
    return float(np.linalg.eigvalsh(h0 + LS).max() - max(levels_over_zeta))


def one_up(x: float) -> float:
    return stabilisation((0.0, 0.0, x))


def two_up(x: float) -> float:
    return stabilisation((0.0, x, x))


def threshold(fun, target: float, hi: float = 20.0) -> float | None:
    """Smallest Δ/ζ with fun(Δ/ζ) ≤ target (fun falls monotonically), by bisection to 1e-9; None if never reached."""
    if fun(hi) > target:
        return None
    lo = 0.0
    for _ in range(100):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if fun(mid) > target else (lo, mid)
    else:
        return hi


def _up(x: float) -> float:
    return math.ceil(x * 100 - 1e-9) / 100


def main() -> int:
    if abs(one_up(0.0) - 1.0) > 1e-12 or abs(two_up(0.0) - 1.0) > 1e-12:
        raise SystemExit("the octahedral limit is not ζ — the L·S matrices are wrong")
    # the strong-splitting limits: a degenerate pair keeps ζ/2 (approached as ½ + ζ/2Δ), a single orbital loses it all
    if not (0.499 < two_up(1000.0) < 0.502 and one_up(1000.0) < 0.002):
        raise SystemExit("the strong-splitting limits are not ζ/2 and 0 — the L·S matrices are wrong")
    lfl = json.loads((DFT_CACHE / "cascade_like_for_like.json").read_text(encoding="utf-8"))
    margin = lfl["shared_shifts"]["terms"]["spin_orbit_os"]["first_flip_at_V"]      # 95, not typed here
    soc = -OS_SOC_SHIFT_V
    banner("94 — SOC quenching of the Os(II/III) couple (one-hole t2g model)")
    rows = {}
    for split in OS3_SOC_SPLIT_CM1:
        zeta = (2.0 / 3.0) * split / CM1_PER_EV
        targets = {"A_whole_shift_scales": margin / soc,
                   "B_only_zeta_scales": (margin - (soc - zeta)) / zeta}
        row = {"zeta_eV": round(zeta, 6), "f_target": {k: round(v, 6) for k, v in targets.items()}, "threshold_eV": {}}
        for name, t in targets.items():
            row["threshold_eV"][name] = {pat: (None if (x := threshold(fun, t)) is None else round(x * zeta, 6))
                                         for pat, fun in (("one_up", one_up), ("two_up", two_up))}
        row["rhombic_f"] = {f"D{d:.1f}_eV": {f"delta{dl:.2f}_eV": round(stabilisation((0.0, d / zeta, (d + dl) / zeta)), 6)
                                             for dl in (0.0, 0.05, 0.1, 0.2, 0.3)} for d in (0.2, 0.3, 0.5)}
        # C — the stabilisation itself is the shift (f_target = margin / ζ); the reading ref 63's rows support at the upper ζ
        t_c = margin / zeta
        row["f_target"]["C_stabilisation_itself"] = round(t_c, 6)
        row["threshold_eV"]["C_stabilisation_itself"] = {pat: (None if (x := threshold(fun, t_c, hi=200.0)) is None else round(x * zeta, 6))
                                                         for pat, fun in (("one_up", one_up), ("two_up", two_up))}
        row["pair_floor_mV_C"] = round(zeta / 2 * 1e3, 1)
        rows[f"split_{split:.0f}_cm1"] = row
        print(f"  ζ = {zeta:.3f} eV: " + " · ".join(
            f"{n[:1]}: one-up ≥ {v['one_up']:.3f} / two-up ≥ {v['two_up']:.3f} eV" for n, v in row["threshold_eV"].items()))
    ab = ("A_whole_shift_scales", "B_only_zeta_scales")
    allv = [v for r in rows.values() for n in ab for v in r["threshold_eV"][n].values() if v is not None]
    one = [r["threshold_eV"][n]["one_up"] for r in rows.values() for n in ab]
    two = [r["threshold_eV"][n]["two_up"] for r in rows.values() for n in ab]
    # ── the calibration against ref 63's own rows: each row's scalar hole levels in, its CASSI shift out ──
    vs63 = {}
    for split in OS3_SOC_SPLIT_CM1:
        zeta = (2.0 / 3.0) * split / CM1_PER_EV
        cells = {}
        for cname, (e2, e3, shift) in SRNEC_TABLE_S2_OS.items():
            f = stabilisation((-e3 / CM1_PER_EV / zeta, -e2 / CM1_PER_EV / zeta, 0.0))   # the hole in the 1²A level
            model = {"A_whole_shift_scales": soc * f, "B_only_zeta_scales": (soc - zeta) + zeta * f,
                     "C_stabilisation_itself": zeta * f}
            cells[cname] = {"f": round(f, 6), "cassi_mV": -shift,
                            "model_mV": {k: round(v * 1e3, 1) for k, v in model.items()},
                            "model_minus_cassi_mV": {k: round(v * 1e3 + shift, 1) for k, v in model.items()}}
        vs63[f"split_{split:.0f}_cm1"] = cells
    dev = {n: [c["model_minus_cassi_mV"][n] for r in vs63.values() for c in r.values()] for n in ("A_whole_shift_scales", "B_only_zeta_scales")}
    hi = vs63[f"split_{max(OS3_SOC_SPLIT_CM1):.0f}_cm1"]
    c_hi = {k: c["model_minus_cassi_mV"]["C_stabilisation_itself"] for k, c in hi.items()}
    bipy = "[Os(bipy)3]2+/3+"
    if not all(x < 0 for v in dev.values() for x in v):
        raise SystemExit("A and B no longer under-predict every row of ref 63 — re-read the calibration prose")
    result = {
        "model": "one t2g hole, H = diag(ε) ⊗ 1 + ζ L·S on xy·yz·xz; f = SOC stabilisation of Os(III) / ζ; ζ = ⅔ × "
                 "the Os³⁺ ²T₂g splitting of Srnec et al. 2008 (OS3_SOC_SPLIT_CM1); normalisation A: the whole "
                 "OS_SOC_SHIFT_V scales with f; B: only ζ scales, the remainder stays",
        "first_flip_margin_V": margin,
        "soc_shift_octahedral_V": OS_SOC_SHIFT_V,
        "by_splitting": rows,
        # a SUFFICIENCY threshold («downhill if the splitting is ≥ T») is quoted rounded UP, so the sentence stays true at
        # its edge (in-silico §When Modifying #43); the exact values are in by_splitting
        "summary": {"one_up_threshold_eV": [_up(min(one)), _up(max(one))],
                    "two_up_threshold_eV": [_up(min(two)), _up(max(two))],
                    "quoted_rounding": "up to 0.01 eV — a sufficiency threshold",
                    "A_B_not_a_criterion": "ref 63's own rows refute A and B (vs_ref63_table_s2) — these two ranges are kept for the record",
                    "C_upper_zeta_one_up_threshold_eV": _up(hi_c1) if (hi_c1 := rows[f"split_{max(OS3_SOC_SPLIT_CM1):.0f}_cm1"]["threshold_eV"]["C_stabilisation_itself"]["one_up"]) is not None else None,
                    "C_upper_zeta_two_up_threshold_eV": _up(hi_c2) if (hi_c2 := rows[f"split_{max(OS3_SOC_SPLIT_CM1):.0f}_cm1"]["threshold_eV"]["C_stabilisation_itself"]["two_up"]) is not None else None,
                    "C_upper_zeta_pair_floor_mV": rows[f"split_{max(OS3_SOC_SPLIT_CM1):.0f}_cm1"]["pair_floor_mV_C"],
                    "note": "every cell stays downhill with the quenched shift if the t2g splitting of Os(III) is at "
                            "least the threshold — one_up: the hole on a single orbital, two_up: on a degenerate pair "
                            "(a split pair, rhombic_f, lowers it further); only the C reading at the upper ζ is "
                            "supported by ref 63's own rows (vs_ref63_table_s2), and under it a hole on a pair never "
                            "gets below the margin in practice; the device complex's splitting is not in any cache — "
                            "do not read it from the Os(III) HOMO–LUMO gap"},
        "analogues_read": ANALOGUES_READ,
        "vs_ref63_table_s2": {
            "source": "Srnec et al. 2008 (ref 63) SI Table S2, CASSCF(5,3)/CASPT2/CASSI, TZP/DZ, every Os row",
            "by_splitting": vs63,
            "A_B_model_minus_cassi_mV": {k: [min(v), max(v)] for k, v in dev.items()},
            "C_upper_zeta_model_minus_cassi_mV": c_hi,
            "bipy_cassi_mV": -SRNEC_TABLE_S2_OS[bipy][2],
            "bipy_cassi_past_first_flip": -SRNEC_TABLE_S2_OS[bipy][2] > margin * 1e3,
            "bipy_hole_pattern": "one_up — the 1²A hole on a single orbital, the 2²A/3²A pair "
                                 f"{SRNEC_TABLE_S2_OS[bipy][0] / CM1_PER_EV:.3f}–{SRNEC_TABLE_S2_OS[bipy][1] / CM1_PER_EV:.3f} eV above",
            "reading": "A and B under-predict every row and are not a criterion; C at the upper ζ is the reading ref 63's "
                       "rows support (all but [Os(CN)6] within a dozen mV)",
        },
        "cannot": ["the device complex's t2g splitting (no cache holds it)",
                   "a SOC calculation: ζ is carried over, covalency as in the literature value, the second-order "
                   "term a normalisation choice"],
    }
    assert allv, "no threshold reached"
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    s = result["summary"]
    v = result["vs_ref63_table_s2"]
    print(f"  A/B (record only — ref 63's rows refute them, model − CASSI {min(min(x) for x in v['A_B_model_minus_cassi_mV'].values()):.0f}…"
          f"{max(max(x) for x in v['A_B_model_minus_cassi_mV'].values()):.0f} mV): one-up ≥ {s['one_up_threshold_eV'][0]:.2f}–"
          f"{s['one_up_threshold_eV'][1]:.2f} eV · two-up ≥ {s['two_up_threshold_eV'][0]:.2f}–{s['two_up_threshold_eV'][1]:.2f} eV")
    print(f"  C at the upper ζ (ref 63's rows within a dozen mV but [Os(CN)6]): one-up ≥ {s['C_upper_zeta_one_up_threshold_eV']:.2f} eV · "
          f"a hole on a pair floors at {s['C_upper_zeta_pair_floor_mV']:.1f} mV · ref 63's [Os(bipy)3] {v['bipy_cassi_mV']:.0f} mV")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
