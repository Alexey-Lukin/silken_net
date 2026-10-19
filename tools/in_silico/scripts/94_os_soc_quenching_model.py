#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""94 — how far a low-symmetry t2g splitting quenches the spin–orbit shift of the Os(II/III) couple (one-hole model, no SCF).

WHY. Every cell of the like-for-like cascade (95) shares a scalar-relativistic Os; spin–orbit coupling (SOC), the one omitted
term of known sign, lowers E°(Os) by ≈ 300 mV in octahedral homoleptic complexes (lib.constants OS_SOC_SHIFT_V) and turns
the first cell uphill beyond 95's `shared_shifts.terms.spin_orbit_os.first_flip_at_V`. The device complex is C₁ and
heteroleptic, so its t2g levels are split and SOC is partly quenched. This script turns that weakest link into a THRESHOLD
on the t2g splitting: how large a splitting keeps the quenched shift below the first-flip margin.

MODEL. Low-spin d⁵ = one hole in t2g. Hamiltonian of the t2g electron levels: diag(ε₁, ε₂, ε₃) ⊗ 1₂ + ζ L·S (real d basis,
l = 2, restricted to xy · yz · xz); the hole sits in the highest level, so the SOC stabilisation of the Os(III) ground state
is max eig(H) − max ε. In Oh it equals ζ (doublet–quartet split 3ζ/2), so ζ = ⅔ × Srnec's Os³⁺ splitting
(OS3_SOC_SPLIT_CM1). f = stabilisation / ζ. Two normalisations bound the shift: A — the whole −300 mV scales with f;
B — only ζ scales and the remainder (−300 mV − ζ: by Srnec «the main contribution» is the M³⁺ splitting, the rest is taken
as an unquenched second-order Os(II) term) stays. Patterns: «one up» (the hole on a single orbital Δ above a pair),
«two up» (the hole on a pair Δ above the third orbital), and a rhombic grid (the upper pair at D, itself split by δ).

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
from lib.constants import DFT_CACHE, OS3_SOC_SPLIT_CM1, OS_SOC_SHIFT_V, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("L3 spin–orbit quenching of the Os(II/III) couple: one-hole t2g model with ζ from the literature Os³⁺ "
                  "splitting, the t2g splitting that keeps the SOC-shifted like-for-like cascade (95) downhill, under two "
                  "normalisations and three splitting patterns; no SCF")

OUT = DFT_CACHE / "os_soc_quenching_model.json"
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
        rows[f"split_{split:.0f}_cm1"] = row
        print(f"  ζ = {zeta:.3f} eV: " + " · ".join(
            f"{n[:1]}: one-up ≥ {v['one_up']:.3f} / two-up ≥ {v['two_up']:.3f} eV" for n, v in row["threshold_eV"].items()))
    allv = [v for r in rows.values() for n in r["threshold_eV"].values() for v in n.values() if v is not None]
    one = [r["threshold_eV"][n]["one_up"] for r in rows.values() for n in r["threshold_eV"]]
    two = [r["threshold_eV"][n]["two_up"] for r in rows.values() for n in r["threshold_eV"]]
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
                    "note": "every cell stays downhill with the quenched shift if the t2g splitting of Os(III) is at "
                            "least the threshold — one_up: the hole on a single orbital, two_up: on a degenerate pair "
                            "(a split pair, rhombic_f, lowers it further); the device complex's splitting is not in "
                            "any cache — do not read it from the Os(III) HOMO–LUMO gap"},
        "cannot": ["the device complex's t2g splitting (no cache holds it)",
                   "a SOC calculation: ζ is carried over, covalency as in the literature value, the second-order "
                   "term a normalisation choice"],
    }
    assert allv, "no threshold reached"
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    s = result["summary"]
    print(f"  quoted (rounded up): one-up ≥ {s['one_up_threshold_eV'][0]:.2f}–{s['one_up_threshold_eV'][1]:.2f} eV · "
          f"two-up ≥ {s['two_up_threshold_eV'][0]:.2f}–{s['two_up_threshold_eV'][1]:.2f} eV")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
