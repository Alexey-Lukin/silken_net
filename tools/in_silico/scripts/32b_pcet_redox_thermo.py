#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""32b — the FAD/FADH₂ PCET potential with relaxed geometries and harmonic thermochemistry (B3LYP/6-31G(d)+C-PCM).

WHY. Script 32 reads E°(FAD/FADH₂) from ELECTRONIC energies of MMFF94s geometries (its own docstring: «screening tier …
no ZPE/thermal, MMFF geometry»), and the like-for-like cascade (95) rests its donor side on that number. The PCET couple
gains two X–H bonds, so the omitted zero-point and thermal terms are larger on this side than on the one-electron Os
couple — measured here before the thesis was rewritten like for like (⚖️ founder 2026-10-16, 00_07 HW.5.IS).

One knob at a time (in-silico §When Modifying #36), each a separate E°:
  (0) control — at start, 32's formula on 20's cached energies must give 32's cached potentials; then the shared-library
      single point on the committed MMFF geometries must reproduce 20's energies (≤ 1e-6 Ha), else the run stops: a
      protocol drift would otherwise read as a geometry or thermal effect;
  (i)   relaxed geometry, electronic energy (lib/dft_utils.dft_optimize, grid response, conv_tol 1e-8); a Hessian that
        finds a mode beyond IMAG_TOL_CM sends the optimisation off that saddle along it (lib `relax_to_minimum`, at most
        SADDLE_ESCAPES times) — the planar MMFF start of the reduced flavin converges to the butterfly's planar saddle
        otherwise (measured 2026-10-16); each saddle's energy, frequencies, geometry and Hessian stay in the record, and
        its height over the minimum is `saddle_above_minimum_meV`;
  (ii)  (i) + zero-point energy (harmonic, analytic C-PCM Hessian);
  (iii) (i) + the full thermal free energy at 298.15 K (rigid-rotor harmonic oscillator).
The proton and the SHE are 32's constants (Isse & Gennaro 2010), loaded from 32, never retyped. The ideal-gas standard
state of FAD and FADH₂ (1 atm) is left as is: one molecule on each side, so the 1 atm → 1 M term cancels in ΔG, and
G*(H⁺,aq) is already a 1 M quantity.

CAN: say how far relaxing the geometry, then the ZPE, then the thermal terms move E°(FAD/FADH₂) at this tier.
CANNOT: (1) the Os side — no Hessian of the 66-atom ECP complex is computed, so a cascade built on (ii)/(iii) is corrected
on the donor side only (95 says so); (2) anharmonicity, and the low modes (< 100 cm⁻¹) that RRHO turns into too much
entropy — (ii) is the reading robust to them, and every frequency is kept in the cache so a quasi-RRHO treatment needs
no recompute; and the reduced flavin's butterfly is a double well whose planar saddle lies 117.5 meV above the minimum
(`saddle_above_minimum_meV`, run 2 — the run-1 rigid cut's ~1 meV moved one hydrogen and understated it by two orders);
that saddle is second order (the fold and the N10-methyl rotor), so its height bounds the inversion barrier from ABOVE
only, and whether the fold's zero point clears that barrier is not computed — counting the fold as a harmonic mode at
the minimum (as here) and dropping it at the planar saddle bracket its anharmonic zero point; (3) explicit solvation; (4) PySCF marks the PCM Hessian experimental, and its Hessian carries no DFT grid
response while the geometry was minimised with it — soft modes can come out slightly imaginary; a mode under
IMAG_TOL_CM is a DECLARED tolerance (not measured), it is dropped from (ii)/(iii) by PySCF and counted in the verdict;
the path's checks are the water control (ZPE 0.571 eV, modes 1683 · 3716 · 3817 cm⁻¹, 2026-10-16) and the analytic
Hessian against central differences of the analytic C-PCM gradient without grid response (water, h = 1e-3 bohr: max
3.2e-4 Ha/bohr², 4.6e-4 relative, 2026-10-16); (5) that a relaxed minimum is the global one; (6) inherited from 32 and equal at every level:
pKa(FADH₂) ≈ 6.7, so the measured −220 mV at pH 7 is not a pure 2e⁻/2H⁺ couple, and (ii) mixes a 298 K free energy of
the proton with 0 K + ZPE flavins.

Writes `cache/dft/pcet_redox_potential_thermo.json` (its own cache — 32's is never touched), the relaxed geometries
`ligands/lumiflavin_ox_opt.xyz` · `ligands/lumiflavin_red_opt.xyz` (after their checks), a `<cache>.partial.json` after
each species and on any failure, the Hessians (a saddle's as `hessian_<tag>_saddle<n>.npy`) and optimisation
checkpoints under `cache/runs/32b/` (its `.npy`/`.xyz` committed since 2026-10-23, the logs ignored). An unconverged optimisation, a mode beyond IMAG_TOL_CM left after
SADDLE_ESCAPES escapes, or an escape that did not descend writes `<cache>.unconverged.json` and no cache.

Run (in-silico §When Modifying #21a · #34 — sequential, nothing heavy alongside):
  cd /Users/oleksiilukin/silken_net || exit 1
  nohup caffeinate -ims ~/miniforge3/envs/silken_md/bin/python -u tools/in_silico/scripts/32b_pcet_redox_thermo.py \\
      > tools/in_silico/cache/runs/32b/run.log 2>&1 &          # macOS has no setsid; nohup detaches from the shell
  python tools/in_silico/scripts/32b_pcet_redox_thermo.py --rehearse <dir>     # STO-3G, writes only into <dir>
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.dft_utils import ESCAPE_CONV, ESCAPE_CONV_TOL, _scf_object, relax_to_minimum, tautomer_change
from lib.flavin import LUMIFLAVIN_OX_SMILES, LUMIFLAVIN_RED_SMILES, check_15_dihydro
from lib.utils import banner

SI_DESCRIPTION = ("L3 FAD/FADH₂ PCET potential with B3LYP/6-31G(d)+C-PCM relaxed geometries and harmonic thermochemistry "
                  "(analytic C-PCM Hessian): E° read at one knob at a time — geometry, then ZPE, then RRHO thermal free energy")

SCRIPTS = Path(__file__).resolve().parent
OUT = DFT_CACHE / "pcet_redox_potential_thermo.json"
RUNS = CACHE_DIR / "runs" / "32b"
T_K, P_PA = 298.15, 101325.0
CONTROL_TOL_HA = 1e-6
IMAG_TOL_CM = 20.0       # DECLARED tolerance for a slightly imaginary soft mode (CANNOT 4) — not a measured noise floor
XH_MAX_A = 1.2
SADDLE_ESCAPES = 2       # displace-and-reoptimise attempts after a Hessian finds a mode beyond IMAG_TOL_CM
ESCAPE_STEP_A = 0.1      # largest atomic displacement of the summed step off the saddle (Å) — breaks a planar start's symmetry
# the escape's convergence criteria (ESCAPE_CONV, ESCAPE_CONV_TOL) and their reasons live in lib/dft_utils — one home for
# every flavin optimisation from a planar start (21g · 33 · 29b · this script)


def _module(fname: str):
    spec = importlib.util.spec_from_file_location(fname[:-3], SCRIPTS / fname)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _read_xyz(path: Path) -> list:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [(ln.split()[0], np.array([float(x) for x in ln.split()[1:4]])) for ln in lines[2:2 + int(lines[0])]]


def _write_xyz(atoms, path: Path, comment: str) -> None:
    body = "\n".join(f"{s:2s} {p[0]:14.8f} {p[1]:14.8f} {p[2]:14.8f}" for s, p in atoms)
    path.write_text(f"{len(atoms)}\n{comment}\n{body}\n", encoding="utf-8")


def geometry_check(s20) -> dict:
    """Before any SCF: 20's builder, re-run, must give the committed MMFF geometries, and the reduced one must be the
    1,5-dihydro tautomer (in-silico §Critical Rules #16)."""
    out = {}
    for tag, smi in (("ox", LUMIFLAVIN_OX_SMILES), ("red", LUMIFLAVIN_RED_SMILES)):
        mol = s20.build_mol_from_smiles(smi, tag)
        if tag == "red":
            out["red_tautomer"] = check_15_dihydro(mol)
        built = s20.mol_to_pyscf_atoms(mol)
        committed = _read_xyz(LIGANDS_DIR / f"lumiflavin_{tag}.xyz")
        if [a for a, _ in built] != [a for a, _ in committed]:
            raise SystemExit(f"{tag}: 20's builder gives another atom order than ligands/lumiflavin_{tag}.xyz")
        dev = max(float(np.abs(np.asarray(p) - q).max()) for (_, p), (_, q) in zip(built, committed, strict=True))
        if dev > 1e-4:
            raise SystemExit(f"{tag}: 20's builder departs from the committed MMFF geometry by {dev:.2e} Å")
        out[tag] = {"atoms": committed, "builder_max_dev_A": dev}
    return out


def same_tautomer(start, relaxed) -> None:
    """Before the Hessian: no proton moved to another heavy atom during the optimisation (§Critical Rules #16)."""
    moved, long = tautomer_change(start, relaxed, XH_MAX_A)
    if moved or long:
        raise SystemExit(f"the relaxed geometry is not the input's tautomer — moved H {moved}, long X–H {long}")


def single_point(atoms, protocol: dict, label: str) -> tuple:
    mol, mf = _scf_object(atoms, 0, 0, **protocol)
    e = float(mf.kernel())
    if not mf.converged:
        raise SystemExit(f"{label}: the SCF did not converge — no number is written")
    return mol, mf, e


def potential(g_red_ha: float, g_ox_ha: float, s32) -> dict:
    """E° of FAD + 2H⁺ + 2e⁻ → FADH₂ with 32's proton reference and SHE, at pH 0 / 4.5 / 7 — 32's formula, line for line."""
    dg = (g_red_ha - g_ox_ha) * HARTREE_TO_EV - s32.N_H * s32.G_STAR_H_AQ_EV
    e_abs = -dg / s32.N_E
    e0 = e_abs - s32.SHE_ABS_V
    return {f"pH_{ph}": round((e0 - s32.NERNST_SLOPE * s32.N_H / s32.N_E * ph) * 1000, 1) for ph in (0.0, 4.5, 7.0)}


def main(argv) -> int:
    import pyscf
    rehearse = argv[argv.index("--rehearse") + 1] if "--rehearse" in argv else None
    out_cache = Path(rehearse) / OUT.name if rehearse else OUT
    out_lig = Path(rehearse) if rehearse else LIGANDS_DIR
    runs = Path(rehearse) / "runs" if rehearse else RUNS
    runs.mkdir(parents=True, exist_ok=True)
    protocol = {"conv_tol": 1e-8, **({"basis_light": "sto-3g"} if rehearse else {})}
    tier = "STO-3G REHEARSAL" if rehearse else "B3LYP/6-31G(d)+C-PCM"
    s20, s32 = _module("20_dft_lumiflavin.py"), _module("32_pcet_redox_potential.py")
    cache20 = json.loads((DFT_CACHE / "lumiflavin.json").read_text(encoding="utf-8"))
    cache32 = json.loads((DFT_CACHE / "pcet_redox_potential.json").read_text(encoding="utf-8"))
    if potential(cache20["red"]["E_total_Ha"], cache20["ox"]["E_total_Ha"], s32) != cache32["E_vs_SHE_mV"]:
        raise SystemExit("32's formula on 20's cache does not give 32's cached potentials — the shared formula drifted")
    meas = cache32["exp_free_flavin_pH7_mV"][0]

    banner(f"32b — geometry check before any SCF ({tier})")
    geo = geometry_check(s20)
    record = {"method": f"{tier}; geomeTRIC via lib/dft_utils.dft_optimize (grid response, conv_tol 1e-8); analytic C-PCM "
                        "Hessian (no grid response); RRHO thermochemistry at 298.15 K, 1 atm",
              "rehearsal": bool(rehearse), "pyscf": pyscf.__version__, "protocol": protocol,
              "imag_tolerance_cm": IMAG_TOL_CM,
              "saddle_escape": {"max_attempts": SADDLE_ESCAPES, "step_A": ESCAPE_STEP_A, "conv_params": ESCAPE_CONV,
                                "conv_tol": ESCAPE_CONV_TOL,
                                "note": "attempt 0 converges on geomeTRIC's default (GAU) set at the protocol's conv_tol; "
                                        "an escape on these criteria"},
              "red_tautomer": geo["red_tautomer"], "species": {}}
    partial = Path(f"{out_cache}.partial.json")

    def dump(path: Path) -> None:
        path.write_text(json.dumps(record, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")

    try:
        banner("(0) control — the shared protocol on the MMFF geometries against 20's cache")
        for tag in ("ox", "red"):
            _, _, e = single_point(geo[tag]["atoms"], protocol, f"{tag} control")
            d = e - cache20[tag]["E_total_Ha"]
            record["species"][tag] = {"E_mmff_Ha": e, "control_delta_vs_20_Ha": d,
                                      "builder_max_dev_A": geo[tag]["builder_max_dev_A"]}
            print(f"  {tag}: E = {e:.8f} Ha, Δ vs 20 = {d:+.2e} Ha", flush=True)
            if abs(d) > CONTROL_TOL_HA and not rehearse:
                raise SystemExit(f"control failed: the shared protocol departs from 20 by {d:+.2e} Ha on {tag}")
        dump(partial)

        for tag in ("ox", "red"):
            def on_relaxed(relaxed, info, tag=tag):
                record["species"][tag]["geom_opt"] = info
                if not info["converged"]:
                    record["species"][tag]["restart_geometry"] = [(s, [float(x) for x in p]) for s, p in relaxed]
                    dump(Path(f"{out_cache}.unconverged.json"))
                    raise SystemExit(f"{tag}: optimisation not converged ({info['returned']}) — no cache written")
                try:
                    same_tautomer(geo[tag]["atoms"], relaxed)
                except SystemExit:
                    record["species"][tag]["rejected_geometry"] = [(s, [float(x) for x in p]) for s, p in relaxed]
                    dump(Path(f"{out_cache}.unconverged.json"))
                    raise

            def on_saddle(saddle, tag=tag):
                record["species"][tag].setdefault("saddles", []).append(saddle)
                dump(partial)
            relaxed, th, _ = relax_to_minimum(geo[tag]["atoms"], 0, 0, label=f"lumiflavin_{tag}", tag=tag, runs=runs,
                                              imag_tol_cm=IMAG_TOL_CM, max_escapes=SADDLE_ESCAPES, step_a=ESCAPE_STEP_A,
                                              on_relaxed=on_relaxed, on_saddle=on_saddle, write_xyz=_write_xyz,
                                              temperature_K=T_K, pressure_Pa=P_PA, **protocol)
            th.pop("_escape_modes")
            record["species"][tag].update(th)
            record["species"][tag]["relaxed_geometry"] = [(s, [float(x) for x in p]) for s, p in relaxed]
            dump(partial)
            print(f"  {tag}: E_opt {th['E_Ha']:.8f} · ZPE {th['ZPE_Ha'] * HARTREE_TO_EV:.4f} eV · imaginary "
                  f"{th['imaginary_cm']} · below 100 cm⁻¹: {th['n_modes_below_100cm']}", flush=True)
    except BaseException:
        dump(partial)
        raise

    beyond = {t: record["species"][t]["n_imag_beyond_tolerance"] for t in ("ox", "red")}
    if any(beyond.values()):
        dump(Path(f"{out_cache}.unconverged.json"))
        raise SystemExit(f"imaginary mode(s) beyond {IMAG_TOL_CM} cm⁻¹ — a saddle, not a minimum ({beyond}); no cache written")
    # the electronic height of each saddle over the minimum reached from it — for the reduced flavin, the butterfly's
    # inversion barrier at this tier, which every flavin geometry optimised from the planar MMFF start carries as excess
    heights = {t: [(s["E_Ha"] - record["species"][t]["E_Ha"]) * HARTREE_TO_EV * 1000 for s in record["species"][t]["saddles"]]
               for t in ("ox", "red") if record["species"][t].get("saddles")}
    record["saddle_above_minimum_meV"] = {t: [round(h, 2) for h in hs] for t, hs in heights.items()}
    if any(h <= 0 for hs in heights.values() for h in hs):
        dump(Path(f"{out_cache}.unconverged.json"))
        raise SystemExit(f"a minimum reached by a saddle escape lies at or above its saddle ({record['saddle_above_minimum_meV']}) "
                         "— the step did not descend from it; no cache written")
    for tag in ("ox", "red"):
        _write_xyz([(s, np.array(p)) for s, p in record["species"][tag]["relaxed_geometry"]], out_lig / f"lumiflavin_{tag}_opt.xyz",
                   f"lumiflavin {tag} — {tier} relaxed (32b)")

    ox, red = record["species"]["ox"], record["species"]["red"]
    steps = record["E_vs_SHE_mV"] = {
        "mmff_electronic": potential(red["E_mmff_Ha"], ox["E_mmff_Ha"], s32),
        "relaxed_electronic": potential(red["E_Ha"], ox["E_Ha"], s32),
        "relaxed_plus_zpe": potential(red["E_Ha"] + red["ZPE_Ha"], ox["E_Ha"] + ox["ZPE_Ha"], s32),
        "relaxed_rrho_free_energy": potential(red["G_tot_Ha"], ox["G_tot_Ha"], s32),
    }
    record["control_mmff_vs_32_pH7_mV"] = round(steps["mmff_electronic"]["pH_7.0"] - cache32["E_vs_SHE_mV"]["pH_7.0"], 1)
    record["vs_measured_free_flavin_pH7_mV"] = {k: round(v["pH_7.0"] - meas, 1) for k, v in steps.items()}
    soft = {t: (record["species"][t]["n_modes_below_100cm"], record["species"][t]["n_imag_tolerated"]) for t in ("ox", "red")}
    record["verdict"] = (
        f"E°(FAD/FADH₂, pH 7) at {tier}: {steps['mmff_electronic']['pH_7.0']:+.1f} mV on the MMFF geometries (32's "
        f"protocol), {steps['relaxed_electronic']['pH_7.0']:+.1f} relaxed, {steps['relaxed_plus_zpe']['pH_7.0']:+.1f} with the "
        f"ZPE, {steps['relaxed_rrho_free_energy']['pH_7.0']:+.1f} with the RRHO free energy — against {meas:+.0f} mV measured "
        f"for the free flavin ({record['vs_measured_free_flavin_pH7_mV']['relaxed_plus_zpe']:+.1f} mV with the ZPE). Modes below "
        f"100 cm⁻¹ / tolerated imaginary (excluded by PySCF): ox {soft['ox'][0]}/{soft['ox'][1]}, red {soft['red'][0]}/"
        f"{soft['red'][1]} — the RRHO reading leans on them, the ZPE one barely. The Os side carries no thermochemistry (CANNOT 1)."
        + "".join(f" {t}: the optimisation met {len(hs)} saddle(s) on the way "
                  f"({'; '.join(str([round(v) for v in s['imaginary_cm']]) for s in record['species'][t]['saddles'])} cm⁻¹ "
                  f"imaginary), lying {', '.join(f'{h:.2f}' for h in hs)} meV above the minimum it reached by stepping off "
                  f"(attempt 0 on geomeTRIC's default criteria, escapes on TIGHT gradients)."
                  for t, hs in record["saddle_above_minimum_meV"].items()))
    dump(out_cache)
    for stale in (partial, Path(f"{out_cache}.unconverged.json")):
        stale.unlink(missing_ok=True)
    banner(f"✅ saved {out_cache if rehearse else out_cache.relative_to(REPO_ROOT)}")
    print("  " + record["verdict"], flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
