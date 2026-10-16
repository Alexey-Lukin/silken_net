#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""96 — the Os(III/II) couple's harmonic thermochemistry on the device mediator's adiabatic chloro form
(B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM), so one row of the like-for-like cascade (95) is corrected on BOTH sides.

WHY. 95's zero-point and RRHO rows correct the donor only (32b) — the one-sided correction 32b and 95 name as their
weakest link; ⚖️ founder 2026-10-16 «порахувати» (measure it rather than name it — 00_05 §5, the weakest link is measured
today, not only named). The Os form already relaxed in both states is the cheapest to correct: 21e `b3lyp-relaxed-os2`
and `b3lyp-relaxed-os3` on dmbpy, the «chloro, both states relaxed (adiabatic)» row of 95.

  (0) controls FIRST, both states, before any Hessian — at each cached geometry 21e's protocol at conv_tol 1e-9 must
      reproduce the cached energy (≤ CONTROL_TOL_HA), the state must be the one 21e accepted (<S²> ≤ S2_MAX_DOUBLET, its
      hole on Os, an aufbau filling — §Critical Rules #14), and Os(III) must be internally stable — else the Hessian would
      belong to another protocol or another state, and finding that out after a 7–10 h Os(II) Hessian would waste it;
  (1) the analytic C-PCM Hessian of each state (RKS Os(II), UKS Os(III)), reused from `cache/runs/96/hessian_<tag>.npy`
      when that file's record holds the same control energy (≤ RESUME_TOL_HA) — a killed run resumes, it does not restart;
  (2) harmonic analysis and RRHO at 298.15 K and 1 atm (PySCF's thermo puts S_elec = R ln(multiplicity) into G, so the
      doublet's R ln 2 is in); every imaginary mode is classified by its weight on the methyl groups (below);
  (3) E°(Os) vs SHE = −ΔG_red(III→II) − |SHE_abs| at three levels: electronic · + ZPE · RRHO free energy — 32's SHE,
      loaded from 32, never retyped; ΔG_red is kept unrounded per level (in-silico §When Modifying #6).

Methyl torsions (⚖️ delegated 2026-10-16, 00_07 HW.5.IS — measured before launch): in both cached geometries all five
methyls (four 4,4′-CH₃, the 1-MeIm N-CH₃) hold one C–H within 5° of their ring plane — a symmetric torsional stationary
point that GAU's gradient threshold cannot resolve, as the N10-methyl of 32b's run 1 (66i) showed. Whether such a point is
a torsional minimum or maximum carries no structural meaning for a near-free rotor, so an imaginary mode whose squared
amplitude lies ≥ METHYL_WEIGHT_MIN on CH₃ groups and whose magnitude is ≤ METHYL_IMAG_MAX_CM is recorded as a methyl
torsion and does NOT stop the run; any other mode beyond IMAG_TOL_CM is a skeletal saddle: `.unconverged.json`, no cache,
no escape (one relaxation of this complex took 7.9 h). PySCF drops every non-real mode from ZPE and G, so each dropped
torsion moves its state's ZPE by ≤ ½hν — a few meV — and the RRHO level, where one dropped or one near-zero real mode moves
G by tens of meV (adversary 2026-10-16), is flagged `rrho_comparable: false` whenever the two states' soft-mode censuses
differ; 95 then takes the both-sided row at the ZPE level only.

CAN: say how far the zero-point and thermal terms move the Os couple at this tier, and so give 95 one row in which both
sides carry them. CANNOT: (1) a minimum of the skeleton beyond what the Hessian shows — 21e relaxed both states on loose
DISPLACEMENT thresholds (the Os–Cl surface is flat) and computed no Hessian (§Critical Rules #18); (2) the other Os forms
of 95 — this corrects one form, and carrying its increment over to the others is an assumption 95 does not make silently;
(3) PySCF marks the PCM Hessian experimental, and its Hessian carries no DFT grid response (32b CANNOT 4); the UKS + ECP +
C-PCM Hessian path is checked against central differences only on a small Os doublet, not on this complex; (4) the
ECP-sphere switching of PySCF ≤ 2.12 PCM (paper §2.7) — the recorded convention of every metal-in-PCM cache, so this is the
Hamiltonian of the energies it corrects, not a better one; (5) anharmonicity — methyl rotors in particular; the ZPE level
is the reading robust to them; (6) explicit solvation, the polymer film.

Writes `cache/dft/os_couple_thermo.json` (its own cache); the Hessians, `os_couple_thermo.partial.json` after each step
and `os_couple_thermo.unconverged.json` on a refusal go to the gitignored `cache/runs/96/`, never beside the cache.
Os(II) first (RKS, the cheaper Hessian), then Os(III). Wall time ≈ 18–30 h (adversary 2026-10-16: the Hessian ≈ 13–19×
32b's flavin one for Os(II), × 1.5–2 for the UKS Os(III)).

Run (in-silico §When Modifying #21a · #34 — sequential, nothing heavy alongside, on AC power):
  cd /Users/oleksiilukin/silken_net || exit 1
  mkdir -p tools/in_silico/cache/runs/96 && nohup caffeinate -ims ~/miniforge3/envs/silken_md/bin/python -u \\
      tools/in_silico/scripts/96_os_couple_thermo.py > tools/in_silico/cache/runs/96/run.log 2>&1 &
  python tools/in_silico/scripts/96_os_couple_thermo.py --rehearse <dir>     # STO-3G light atoms, writes only into <dir>
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, DFT_CACHE, HARTREE_TO_EV, REPO_ROOT, S2_MAX_DOUBLET
from lib.dft_utils import _scf_object
from lib.utils import banner

SI_DESCRIPTION = ("L3 Os(III/II) couple harmonic thermochemistry (analytic C-PCM Hessian, B3LYP/6-31G(d)+LANL2DZ(Os)) on the "
                  "device mediator's adiabatic chloro form, so the like-for-like cascade (95) carries the ZPE and RRHO terms "
                  "on both sides for that form")

SCRIPTS = Path(__file__).resolve().parent
OUT = DFT_CACHE / "os_couple_thermo.json"
RUNS = CACHE_DIR / "runs" / "96"
SRC2 = DFT_CACHE / "os_mediator_series_relaxed_os2.json"
SRC3 = DFT_CACHE / "os_mediator_series_relaxed_os3.json"
POINT = "dmbpy"
TAGS = ("os2", "os3")
T_K, P_PA = 298.15, 101325.0
SCF_CONV_TOL = 1e-9
CONTROL_TOL_HA = 5e-6    # 21e's single points ran at dft_singlepoint's default conv_tol 1e-6 (they sit ~4e-7 Ha above the
#                          1e-8 optimiser energies); a protocol slip or another d-hole moves mHa
RESUME_TOL_HA = 1e-8     # a saved Hessian is this state's only if its record's control energy agrees to this
IMAG_TOL_CM = 20.0       # DECLARED tolerance for a skeletal soft mode (as 32b), not a measured noise floor
METHYL_WEIGHT_MIN = 0.8  # share of a mode's squared amplitude on CH₃ groups (C + 3 H) that makes it a methyl torsion —
#   calibrated on 32b run 1's saddle (2026-10-16): N10-methyl torsion 65.7i → 0.839, the N5–H wag 255.3i → 0.002, real
#   methyl torsions at 130–150 cm⁻¹ → 0.78–0.98, mixed butterfly-methyl soft modes at 62–158 cm⁻¹ → 0.59–0.69; a false
#   «skeletal» costs the controls only (the Hessians are reused), a false «torsion» would pass a saddle — so the high side
METHYL_IMAG_MAX_CM = 150.0   # a «torsion» stronger than this is not trusted as one
SOFT_CM = 50.0           # the census RRHO comparability is judged on
LEVEL_SHIFT_RETRY = 0.3  # §Critical Rules #5's value for an oscillating UKS Os(III); used only if the plain SCF does not converge


def _module(fname: str):
    spec = importlib.util.spec_from_file_location(fname[:-3], SCRIPTS / fname)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def states(s21e) -> dict:
    """Both cached states of the point, with their geometries — refused unless 21e accepts both and the Os(III) record is
    the relaxation of THIS Os(II)."""
    c2 = json.loads(SRC2.read_text(encoding="utf-8"))["complexes"][POINT]
    c3 = json.loads(SRC3.read_text(encoding="utf-8"))["complexes"][POINT]
    if c3["os2_E_Ha"] != c2["os2"]["E_total_Ha"]:
        raise SystemExit(f"{SRC3.name} was relaxed from another Os(II) point than {SRC2.name} holds — re-run 21e first")
    for g in (c2["geometry_os2_relaxed"], c3["geometry_os3_relaxed"]):
        if not g["info"]["converged"]:
            raise SystemExit(f"{g['info']['label']}: the cached relaxation did not converge — no geometry to differentiate")
    if s21e._acceptance(c2["os2"], False) != "accepted" or s21e._acceptance(c3["os3"], True) != "accepted":
        raise SystemExit("21e does not accept the cached states — nothing here would be the couple it reports")
    return {"os2": {"charge": 1, "spin": 0, "atoms": c2["geometry_os2_relaxed"]["atoms"], "E_cached_Ha": c2["os2"]["E_total_Ha"]},
            "os3": {"charge": 2, "spin": 1, "atoms": c3["geometry_os3_relaxed"]["atoms"], "E_cached_Ha": c3["os3"]["E_total_Ha"]},
            "dE_red_adiabatic_eV": c3["dE_red_adiabatic_eV"]}


def accept(mol, mf, spin: int, s21e) -> dict:
    """21e's acceptance metrics on a live SCF object: <S²>, the Mulliken spin on Os, the aufbau filling per spin."""
    out = {"converged": bool(mf.converged)}
    occ, e = (mf.mo_occ, mf.mo_energy) if spin else ([mf.mo_occ], [mf.mo_energy])
    out["aufbau"] = all(float(ei[oi > 0].max()) <= float(ei[oi == 0].min()) for oi, ei in zip(occ, e, strict=True))
    if spin:
        from pyscf.scf.uhf import mulliken_spin_pop
        out["s2"] = float(mf.spin_square()[0])
        ms = mulliken_spin_pop(mol, mf.make_rdm1(), verbose=0)[1]
        out["os_spin_mulliken"] = float(sum(ms[i] for i in range(mol.natm) if mol.atom_symbol(i) == "Os"))
    out["accepted"] = (out["converged"] and out["aufbau"]
                       and (not spin or (out["s2"] <= S2_MAX_DOUBLET and out["os_spin_mulliken"] >= s21e.OS3_MIN_OS_SPIN)))
    return out


def control(st: dict, tag: str, protocol: dict, s21e, rec: dict, rehearse: bool):
    """The control single point of one state; its record lands in `rec` BEFORE any refusal, so a refusal keeps its numbers."""
    atoms = [(s, np.asarray(p, float)) for s, p in st["atoms"]]
    mol, mf = _scf_object(atoms, st["charge"], st["spin"], conv_tol=SCF_CONV_TOL, max_cycle=s21e.VARIANT_MAX_CYCLE, **protocol)
    t0 = time.time()
    e = float(mf.kernel())
    shifted = False
    if not mf.converged and st["spin"]:   # §Critical Rules #5: a shift steers the PATH; accept() and the control judge the
        mf.level_shift, shifted = LEVEL_SHIFT_RETRY, True   # state it lands on (the Hessian never reads mf.level_shift)
        e = float(mf.kernel(dm0=mf.make_rdm1()))
        mf.level_shift = 0.0
    out = rec[tag] = {"E_Ha": e, "control_delta_vs_21e_Ha": e - st["E_cached_Ha"], "level_shift_retry": shifted,
                      **accept(mol, mf, st["spin"], s21e)}
    if st["spin"] and out["accepted"]:
        out["stable_internal"] = bool(mf.stability(return_status=True)[2])
    out["scf_wall_s"] = round(time.time() - t0, 1)
    print(f"  {tag}: E = {e:.8f} Ha, Δ vs 21e = {out['control_delta_vs_21e_Ha']:+.2e} Ha, "
          f"{ {k: v for k, v in out.items() if k not in ('E_Ha', 'control_delta_vs_21e_Ha')} }", flush=True)
    refused = (not out["accepted"] or out.get("stable_internal") is False
               or abs(out["control_delta_vs_21e_Ha"]) > CONTROL_TOL_HA)
    if refused and not rehearse:
        raise SystemExit(f"{tag}: the control single point is not the state and protocol 21e reports ({out}) — no Hessian")
    return mol, mf


def methyl_weight(mol, mode) -> float:
    """Share of a mode's squared Cartesian amplitude on the CH₃ groups (a carbon with three hydrogens, and those hydrogens)."""
    xyz = mol.atom_coords(unit="Angstrom")
    sym = [mol.atom_symbol(i) for i in range(mol.natm)]
    hyd = [i for i, s in enumerate(sym) if s == "H"]
    members = set()
    for c in (i for i, s in enumerate(sym) if s == "C"):
        hs = [h for h in hyd if np.linalg.norm(xyz[h] - xyz[c]) < 1.25]
        if len(hs) == 3:
            members.update([c, *hs])
    w = np.sum(np.asarray(mode) ** 2, axis=1)
    return float(w[sorted(members)].sum() / w.sum())


def analyse(mol, mf, hess) -> dict:
    from pyscf.hessian import thermo
    freq = thermo.harmonic_analysis(mol, hess)
    nu = np.asarray(freq["freq_wavenumber"], dtype=complex)
    imag = [(float(abs(v.imag)), methyl_weight(mol, freq["norm_mode"][i])) for i, v in enumerate(nu) if abs(v.imag) > 0]
    torsion = [(v, w) for v, w in imag if v > IMAG_TOL_CM and w >= METHYL_WEIGHT_MIN and v <= METHYL_IMAG_MAX_CM]
    skeletal = [(v, w) for v, w in imag if v > IMAG_TOL_CM and (v, w) not in torsion]
    real = np.sort(nu.real[np.abs(nu.imag) == 0])
    t = thermo.thermo(mf, freq["freq_au"], T_K, P_PA)
    return {"ZPE_Ha": float(t["ZPE"][0]), "G_tot_Ha": float(t["G_tot"][0]), "H_tot_Ha": float(t["H_tot"][0]),
            "S_elec_Eh_per_K": float(t["S_elec"][0]),
            "imaginary": [{"cm": round(v, 2), "methyl_weight": round(w, 3)} for v, w in sorted(imag, reverse=True)],
            "n_imag_tolerated": sum(v <= IMAG_TOL_CM for v, _ in imag), "n_methyl_torsion_imag": len(torsion),
            "n_skeletal_beyond_tolerance": len(skeletal), "real_cm": [round(float(x), 2) for x in real],
            "n_real_below_soft": int(np.sum(real < SOFT_CM))}


def potentials(os2: dict, os3: dict, she_abs: float) -> dict:
    """ΔG_red(III→II) = G(II) − G(III) in eV, unrounded, and E°(Os) vs SHE in V — 95's convention E_os = −ΔG_red − |SHE_abs|."""
    dg = {"electronic": (os2["E_Ha"] - os3["E_Ha"]) * HARTREE_TO_EV,
          "plus_zpe": (os2["E_Ha"] + os2["ZPE_Ha"] - os3["E_Ha"] - os3["ZPE_Ha"]) * HARTREE_TO_EV,
          "rrho_free_energy": (os2["G_tot_Ha"] - os3["G_tot_Ha"]) * HARTREE_TO_EV}
    return {"dG_red_eV": dg, "E_os_vs_SHE_V": {k: round(-v - she_abs, 4) for k, v in dg.items()}}


def main(argv) -> int:
    import pyscf
    rehearse = argv[argv.index("--rehearse") + 1] if "--rehearse" in argv else None
    out_cache = Path(rehearse) / OUT.name if rehearse else OUT
    runs = Path(rehearse) / "runs" if rehearse else RUNS
    runs.mkdir(parents=True, exist_ok=True)
    partial, refused = runs / f"{OUT.stem}.partial.json", runs / f"{OUT.stem}.unconverged.json"
    protocol = {"basis_light": "sto-3g"} if rehearse else {}
    tier = "STO-3G (light atoms) REHEARSAL" if rehearse else "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM"
    s21e, s32 = _module("21e_dft_os_mediator_series.py"), _module("32_pcet_redox_potential.py")
    if pyscf.__version__ != s21e._recorded_pyscf() and not rehearse:
        raise SystemExit(f"PySCF {pyscf.__version__} is not the recorded {s21e._recorded_pyscf()} — run in silken_md")
    st = states(s21e)
    previous = json.loads(partial.read_text(encoding="utf-8"))["species"] if partial.exists() else {}
    record = {"method": f"{tier}; analytic C-PCM Hessian (no grid response) at 21e's cached relaxed geometries of {POINT}; "
                        f"SCF conv_tol {SCF_CONV_TOL}; RRHO thermochemistry at {T_K} K, 1 atm",
              "rehearsal": bool(rehearse), "pyscf": pyscf.__version__, "point": POINT, "sources": [SRC2.name, SRC3.name],
              "gate": {"imag_tolerance_cm": IMAG_TOL_CM, "methyl_weight_min": METHYL_WEIGHT_MIN,
                       "methyl_imag_max_cm": METHYL_IMAG_MAX_CM, "soft_cm": SOFT_CM},
              "species": {}}

    def dump(path: Path) -> None:   # atomic: a kill mid-write never leaves half a record
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(record, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")
        tmp.replace(path)

    scf = {}
    try:
        banner(f"96 — (0) controls of both states before any Hessian ({tier})")
        for tag in TAGS:
            scf[tag] = control(st[tag], tag, protocol, s21e, record["species"], bool(rehearse))
            dump(partial)
        for tag in TAGS:
            mol, mf = scf[tag]
            rec, hess_file = record["species"][tag], runs / f"hessian_{tag}.npy"
            old = previous.get(tag, {})
            if hess_file.exists() and "hessian_wall_s" in old and abs(old.get("E_Ha", np.inf) - rec["E_Ha"]) <= RESUME_TOL_HA:
                banner(f"96 — (1) {tag}: Hessian reused from {hess_file.name} (control energy agrees to {RESUME_TOL_HA} Ha)")
                hess, rec["hessian_wall_s"], rec["hessian_reused"] = np.load(hess_file), old["hessian_wall_s"], True
            else:
                banner(f"96 — (1) {tag}: analytic C-PCM Hessian")
                t0 = time.time()
                hess = mf.Hessian().kernel()
                np.save(hess_file, hess)
                rec["hessian_wall_s"], rec["hessian_reused"] = round(time.time() - t0, 1), False
            rec["hessian_file"] = str(hess_file)
            rec.update(analyse(mol, mf, hess))
            dump(partial)
            print(f"  {tag}: ZPE {rec['ZPE_Ha'] * HARTREE_TO_EV:.4f} eV · imaginary {rec['imaginary']} · real below "
                  f"{SOFT_CM} cm⁻¹: {rec['n_real_below_soft']} · Hessian {rec['hessian_wall_s']} s", flush=True)
    except BaseException:
        dump(partial)
        raise

    skeletal = {t: record["species"][t]["n_skeletal_beyond_tolerance"] for t in TAGS}
    if any(skeletal.values()):
        dump(refused)
        raise SystemExit(f"a skeletal mode beyond {IMAG_TOL_CM} cm⁻¹ — a saddle, not a minimum ({skeletal}); no cache written, "
                         "and no escape here (CANNOT 1)")
    os2, os3 = record["species"]["os2"], record["species"]["os3"]
    record.update(potentials(os2, os3, s32.SHE_ABS_V))
    census = {t: (record["species"][t]["n_imag_tolerated"] + record["species"][t]["n_methyl_torsion_imag"],
                  record["species"][t]["n_real_below_soft"]) for t in TAGS}
    record["rrho_comparable"] = census["os2"] == census["os3"]
    record["rrho_census"] = {t: {"dropped_imaginary": c[0], f"real_below_{SOFT_CM:g}_cm": c[1]} for t, c in census.items()}
    record["control_dE_red_vs_21e_meV"] = round((record["dG_red_eV"]["electronic"] - st["dE_red_adiabatic_eV"]) * 1000, 3)
    e_os, dg = record["E_os_vs_SHE_V"], record["dG_red_eV"]
    shift = {k: round(-(v - dg["electronic"]) * 1000, 1) for k, v in dg.items()}
    record["shift_vs_electronic_mV"] = shift
    record["verdict"] = (
        f"E°(Os(III/II)) of the {POINT} chloro form, both states relaxed, at {tier}: {e_os['electronic'] * 1000:+.1f} mV vs SHE "
        f"electronic (21e's adiabatic couple, control {record['control_dE_red_vs_21e_meV']:+.3f} meV), "
        f"{e_os['plus_zpe'] * 1000:+.1f} with the ZPE ({shift['plus_zpe']:+.1f}), {e_os['rrho_free_energy'] * 1000:+.1f} with the "
        f"RRHO free energy ({shift['rrho_free_energy']:+.1f}, the doublet's R ln 2 included"
        + ("" if record["rrho_comparable"] else f"; NOT comparable — the soft-mode censuses differ, {record['rrho_census']}")
        + f"). Methyl torsions recorded imaginary and dropped: Os(II) {os2['n_methyl_torsion_imag']}, Os(III) "
          f"{os3['n_methyl_torsion_imag']}; tolerated soft imaginary: {os2['n_imag_tolerated']} / {os3['n_imag_tolerated']}. "
          "One form only (CANNOT 2).")
    dump(out_cache)
    for stale in (partial, refused):
        stale.unlink(missing_ok=True)
    banner(f"✅ saved {out_cache if rehearse else out_cache.relative_to(REPO_ROOT)}")
    print("  " + record["verdict"], flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
