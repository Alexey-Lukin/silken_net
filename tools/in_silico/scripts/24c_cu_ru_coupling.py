#!/usr/bin/env python
"""24c — Cu–Ru DET coupling (CHEM.32, the Ru "double-whammy" test).

Hypothesis (CHEM.32): swapping the Co ZIF node for Ru raises the electronic
coupling t_ij of the rate-limiting Cu–node hop, ON TOP of Ru's already-canon
lower reorganization energy (λ_Ru 0.78 vs Co). Physical basis: Ru's diffuse 4d
orbitals overlap the imidazolate bridge / Cu(T1) better than Co's contracted 3d.

Design — isolate the orbital effect:
  geometry = the canon `cu_co_zif` cluster with Co→Ru swapped at IDENTICAL
  coordinates (`cu_ru_zif.xyz`). Fixing the geometry controls for distance, so a
  change in t_ij is the pure 4d-vs-3d diffuseness effect. Caveat: the real Ru–N
  bond is ~0.03–0.05 Å longer than Co–N; a longer M–M distance would slightly
  REDUCE overlap → this fixed-geometry t_ij is a mild UPPER bound on the
  pure-diffuseness gain (the net real effect = diffuseness↑ minus a small
  distance↑). Same "geometry-bounded" caveat as the canon cathode result.

Rigor — reuse + control:
  imports script 24's exact ΔSCF machinery (build_mol/run_uks), so the Cu–Co
  CONTROL must reproduce the canon t_ij = 0.00128 eV — that validates the setup
  before we trust the Cu–Ru number. Writes a SEPARATE cache (cu_ru_coupling.json);
  does NOT touch the canon zif_hopping.json.

Run:  mamba run -n silken_md python tools/in_silico/scripts/24c_cu_ru_coupling.py
Wall: ~2 h CPU (2 pairs × 2 ΔSCF states; DFT sequential — never two heavy jobs/CPU).
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import REPO_ROOT, LIGANDS_DIR, DFT_CACHE, HARTREE_TO_EV, TEMPERATURE_K
from lib.utils import banner

# Reuse script 24's exact functions (digit-leading module name → importlib).
_spec = importlib.util.spec_from_file_location("hop24", HERE / "24_dft_hopping_integrals.py")
hop24 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hop24)
hop24.BASIS_METALS["Ru"] = "lanl2dz"   # Ru valence basis + ECP (lanl2dz covers the 4d row)
hop24.ECP_METALS["Ru"] = "lanl2dz"

KB = 8.617333262e-5        # eV/K
HBAR = 6.582119569e-16     # eV·s
TURNOVER = 1.0e3           # s⁻¹ (enzymatic, for the margin)

# (xyz, metal1, metal2, label, charge, spin_guess)
# Cu-Co control = canon (+1, spin 2). Cu-Ru: Ru(lanl2dz)=16 valence e⁻ vs Co 17
# → total e⁻ parity flips → spin guess 1 (low-spin Ru); two_state_tij auto-corrects parity.
PAIRS = [
    ("cu_co_zif.xyz", "Cu", "Co", "Cu-Co (control)", +1, 2),
    ("cu_ru_zif.xyz", "Cu", "Ru", "Cu-Ru (CHEM.32)", +1, 1),
]


def build_with_spin(atoms, charge, spin_guess):
    """Build mol, trying spin parities until one is electron-count-consistent."""
    last = None
    for sp in (spin_guess, spin_guess - 1, spin_guess + 1, spin_guess + 2, spin_guess - 2):
        if sp < 0:
            continue
        try:
            return hop24.build_mol(atoms, charge, sp), sp
        except RuntimeError as e:
            last = e
    raise RuntimeError(f"no consistent spin near {spin_guess}: {last}")


def two_state_tij(atoms, charge, spin_guess, label):
    """ΔSCF energy-splitting t_ij — mirrors script 24 main's A/B + degeneracy fallback."""
    mol, spin = build_with_spin(atoms, charge, spin_guess)
    if spin != spin_guess:
        print(f"  ⚠️ spin parity adjusted {spin_guess} → {spin}")

    e_a, conv_a = hop24.run_uks(mol, f"{label} State A")

    mf_b = dft.UKS(build_with_spin(atoms, charge, spin)[0])
    mf_b.xc = hop24.XC_FUNCTIONAL
    mf_b.conv_tol = 1e-5
    mf_b.max_cycle = 500
    mf_b.verbose = 0
    mf_b.level_shift = 0.5   # bias toward an alternative (localized) SCF minimum
    t0 = time.time()
    e_b = mf_b.kernel()
    conv_b = bool(mf_b.converged)
    print(f"    {label} State B: E = {e_b:.6f} Ha ({time.time() - t0:.0f}s, conv={conv_b})")

    d_ev = abs(e_a - e_b) * HARTREE_TO_EV
    t_ij = d_ev / 2.0
    if d_ev < 0.001:   # degenerate → frontier α/β splitting (same fallback as script 24)
        print(f"  ⚠️ states degenerate (ΔE={d_ev:.4f} eV) → HOMO α-β splitting")
        mf = dft.UKS(mol)
        mf.xc = hop24.XC_FUNCTIONAL
        mf.conv_tol = 1e-5
        mf.max_cycle = 500
        mf.verbose = 0
        mf.kernel()
        na, nb = mol.nelec
        t_ij = abs(mf.mo_energy[0][na - 1] - mf.mo_energy[1][nb - 1]) * HARTREE_TO_EV / 2.0 if na and nb else 0.05
    return {"t_ij_eV": t_ij, "spin": spin, "E_A_Ha": float(e_a), "E_B_Ha": float(e_b),
            "converged_A": conv_a, "converged_B": conv_b}


def marcus_k(t_ij, lam, dG=0.0, T=TEMPERATURE_K):
    pre = (2 * np.pi / HBAR) * t_ij ** 2
    return pre / np.sqrt(4 * np.pi * lam * KB * T) * np.exp(-(dG + lam) ** 2 / (4 * lam * KB * T))


def main() -> int:
    # λ_hop from the canon cache (drift-proof — never hardcode another script's result).
    # lit λ is the primary row (canon: B3LYP over-estimates first-row λ, esp. Co spin-crossover).
    klam = json.loads((DFT_CACHE / "cathode_ket_lambda.json").read_text())
    lam_lit = klam["lambda_lit_eV"]
    lam_hop = {
        "Cu-Co (control)": (lam_lit["Cu"] + lam_lit["Co"]) / 2,   # (2.0+1.4)/2 = 1.7
        "Cu-Ru (CHEM.32)": (lam_lit["Cu"] + lam_lit["Ru"]) / 2,   # (2.0+0.8)/2 = 1.4
    }
    out = {
        "method": "ΔSCF B3LYP/6-31g(d)+lanl2dz(Cu,Co,Ru); Co→Ru @identical geom; λ_hop=lit from cache",
        "caveat": "fixed-geom t_ij isolates 4d-diffuseness (controls distance); real Ru-N longer → upper bound on the pure-diffuseness gain",
        "turnover_s": TURNOVER, "lambda_hop_eV": lam_hop, "pairs": [],
    }
    for xyz, m1, m2, label, charge, spin in PAIRS:
        path = LIGANDS_DIR / xyz
        if not path.exists():
            sys.exit(f"missing {path} — build cu_ru_zif.xyz first")
        banner(f"ΔSCF {label}  ({xyz})")
        atoms = hop24.read_xyz(path)
        r = two_state_tij(atoms, charge, spin, label)
        lam = lam_hop[label]
        k = marcus_k(r["t_ij_eV"], lam)
        r.update(label=label, metal_node=m2, charge=charge, lambda_hop_eV=lam,
                 k_ET_per_s=k, margin_vs_turnover=k / TURNOVER)
        print(f"  |t_ij|={r['t_ij_eV']:.5f} eV | λ_hop={lam:.2f} eV | k_ET={k:.2e} /s | margin ×{k / TURNOVER:.3g}")
        out["pairs"].append(r)

    cc = next((p for p in out["pairs"] if "control" in p["label"]), None)
    cr = next((p for p in out["pairs"] if "CHEM.32" in p["label"]), None)
    canon = klam["t_ij_eV"]["Cu-Co"]
    out["canon_cuco_t_ij_eV"] = canon
    if cc:
        out["control_reproduces_canon"] = bool(abs(cc["t_ij_eV"] - canon) < 0.001)
    if cc and cr:
        out["t_ij_ratio_Ru_over_Co"] = cr["t_ij_eV"] / cc["t_ij_eV"] if cc["t_ij_eV"] else None
        out["k_ratio_Ru_over_Co"] = cr["k_ET_per_s"] / cc["k_ET_per_s"] if cc["k_ET_per_s"] else None

    # Persist the (expensive) results FIRST — before any pretty-print can fail.
    outp = DFT_CACHE / "cu_ru_coupling.json"
    outp.write_text(json.dumps(out, indent=2))
    banner(f"✅ saved {outp.relative_to(REPO_ROOT)}")

    def _f(x, spec="{:.2f}"):
        return spec.format(x) if isinstance(x, (int, float)) else "n/a"

    banner("Cu-Ru double-whammy verdict")
    if cc:
        print(f"  control Cu-Co t_ij={cc['t_ij_eV']:.5f} eV (canon {canon:.5f}) → reproduces canon = {out.get('control_reproduces_canon')}")
        if not out.get("control_reproduces_canon"):
            print("  🔴 CONTROL FAILED to reproduce canon — Cu-Ru number NOT trustworthy until setup is debugged")
    if cr:
        print(f"  Cu-Ru t_ij={cr['t_ij_eV']:.5f} eV → t_ij ratio ×{_f(out.get('t_ij_ratio_Ru_over_Co'))} (diffuseness effect)")
    if cc and cr:
        print(f"  margin vs turnover: Co ×{_f(cc['margin_vs_turnover'], '{:.3g}')} → Ru ×{_f(cr['margin_vs_turnover'], '{:.3g}')}  (k ratio ×{_f(out.get('k_ratio_Ru_over_Co'), '{:.2g}')}: t_ij² × λ)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
