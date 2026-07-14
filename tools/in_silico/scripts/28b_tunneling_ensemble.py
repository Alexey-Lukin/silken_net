#!/usr/bin/env python
"""
L3 / CHEM.16 — dynamic electron-tunnelling over the MD ensemble.

Script 28 computes the Beratan-Onuchic FAD→surface coupling on ONE (AF3) snapshot.
Thermal motion modulates the through-space gaps in that path, so the *rate* is a
Boltzmann-weighted ensemble average, not a single-geometry number — "conformational
gating". Here we replay script 28's pathway analysis over frames of the full-matrix
MD trajectory (the same production.dcd script 27 uses) and report:

  • the distribution of the effective decay (β·d)_eff = ln(coupling penalty);
  • the conformational-gating factor  ⟨k⟩ / k(⟨β·d⟩) = ⟨exp(−2·β·d)⟩ / exp(−2·⟨β·d⟩),
    i.e. how much the rate is enhanced by the low-β·d (open-gate) tail
    (k_ET ∝ |H_DA|² ∝ exp(−2·(β·d)_eff)).

Light (graph + Dijkstra, KD-tree neighbour search — NO DFT); safe alongside a DFT job.
The FAD cofactor is the GAFF "UNK" residue in the MD topology (script 27 note); we identify it
by its phosphorus (unique vs the matrix 'UNK' polymers), slice std-AA protein + FAD heavy atoms
only (the path runs through the protein, not the matrix/water), and source from the
isoalloxazine ring (N5 exit), not the ADP tail.

PBC handling (essential): production.dcd is wrapped, so molecules split across the box → a wrapped
protein/FAD disconnects the contact graph → β·d = NaN. We call mdtraj **image_molecules** (anchor =
largest molecule = protein), which BOTH makes the protein whole AND co-locates the FAD cofactor —
a SEPARATE non-covalent molecule — into the protein's periodic image. `make_molecules_whole` alone
is NOT sufficient: it makes each molecule whole but leaves the FAD in a different image → still
disconnected (verified: 1/15 frames). With image_molecules all 15 frames are analysable.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

try:
    import mdtraj as md
    import networkx as nx
    from scipy.spatial import cKDTree
except ImportError as e:
    sys.exit(f"need mdtraj+networkx+scipy: {e}")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, REPO_ROOT
from lib.utils import banner

RUNS_DIR = REPO_ROOT / "tools/in_silico/cache/runs"
OUT = DFT_CACHE / "tunneling_ensemble.json"

# Beratan-Onuchic params — identical to script 28 (the single-snapshot owner)
BETA_TS = 1.1            # Å⁻¹ through-space decay
P_COVALENT = 0.6
P_HBOND = 0.9
COVALENT_CUT = 1.8
HBOND_CUT = 3.5
CONTACT_CUT = 6.0
N_FRAMES = 15           # evenly-spaced snapshots from the strided trajectory

STD_AA = {"ALA", "ARG", "ASN", "ASP", "CYS", "GLN", "GLU", "GLY", "HIS", "HID", "HIE",
          "HIP", "ILE", "LEU", "LYS", "MET", "PHE", "PRO", "SER", "THR", "TRP", "TYR", "VAL"}
# isoalloxazine ring atom-name prefixes (GAFF FAD 'UNK', from script 27) — the redox source,
# excluding the ADP/ribitol tail so Dijkstra starts at the electron-exit (N5) end, not the phosphate.
RING_PREFIXES = {"N5", "N6", "N7", "N8", "C9", "C10", "C11", "C12", "C13", "C14", "C15",
                 "C16", "C17", "C18", "C19", "C20", "C21", "O7", "O8"}


def find_run() -> Path | None:
    best, best_size = None, 0
    for c in RUNS_DIR.glob("*fullmatrix*"):
        dcd, pdb = c / "production.dcd", c / "system.pdb"
        if dcd.exists() and pdb.exists() and dcd.stat().st_size > best_size:
            best, best_size = c, dcd.stat().st_size
    return best


def graph_from_frame(coords, elements, fad_mask):
    """KD-tree contact graph (heavy atoms) → Beratan-Onuchic weights."""
    G = nx.Graph()
    G.add_nodes_from(range(len(coords)))
    pairs = cKDTree(coords).query_pairs(CONTACT_CUT, output_type="ndarray")
    don_acc = {"N", "O", "S"}
    for i, j in pairs:
        d = float(np.linalg.norm(coords[i] - coords[j]))
        if d < COVALENT_CUT:
            w = P_COVALENT
        elif d < HBOND_CUT and ({elements[i], elements[j]} & don_acc):
            w = P_HBOND
        else:
            w = float(np.exp(BETA_TS * d))
        G.add_edge(int(i), int(j), weight=w, distance=d)
    return G


def best_beta_d(G, fad_idx, surf_idx):
    best = np.inf
    for s in fad_idx[:5]:
        try:
            lengths = nx.single_source_dijkstra_path_length(G, s, weight="weight")
        except Exception:
            continue
        for t in surf_idx:
            if t in lengths and lengths[t] < best:
                best = lengths[t]
    return np.log(best) if np.isfinite(best) else np.nan


def main() -> int:
    banner("CHEM.16 — dynamic tunnelling over the MD ensemble")
    run = find_run()
    if run is None:
        sys.exit("No fullmatrix MD run with production.dcd + system.pdb in cache/runs/")
    print(f"  run: {run.name}")

    top = md.load_topology(str(run / "system.pdb"))
    # FAD = the residue carrying phosphorus (its diphosphate) — unique vs the matrix 'UNK' polymers.
    # Earlier bug: mdtraj "protein" mis-includes those matrix 'UNK' residues → graph splits into a
    # protein and a matrix component (>6 Å gaps) → no FAD→surface path → NaN. Use protein = std-AA only.
    fad_res = next((r for r in top.residues if any(a.element.symbol == "P" for a in r.atoms)), None)
    if fad_res is None:
        sys.exit("FAD (P-containing residue) not found in topology")
    fad_atoms_full = [a.index for a in fad_res.atoms if a.element.symbol != "H"]
    prot_atoms_full = [a.index for a in top.atoms if a.residue.name in STD_AA and a.element.symbol != "H"]
    keep = sorted(set(prot_atoms_full) | set(fad_atoms_full))
    print(f"  FAD '{fad_res.name}' (P-residue, {fad_res.n_atoms} atoms); {len(prot_atoms_full)} std-AA protein heavy; kept {len(keep)}")

    traj = md.load(str(run / "production.dcd"), top=str(run / "system.pdb"), stride=100)
    # PBC unwrap — stitch molecules split across the periodic box BEFORE slicing, while the FULL bond
    # topology is available (a wrapped protein otherwise disconnects the contact graph → NaN). Done on
    # the full topology so the bond walk is complete; the contact graph then uses plain Euclidean dist.
    n_bonds = traj.topology.n_bonds
    try:
        # image_molecules (not just make_molecules_whole): also co-locates the FAD cofactor — a SEPARATE
        # non-covalent molecule — into the protein's periodic image (anchor = largest molecule = protein).
        # make_molecules_whole alone left the FAD whole but in a DIFFERENT image → still disconnected.
        traj.image_molecules(inplace=True)
        print(f"  PBC: image_molecules applied ({n_bonds} bonds; anchor = largest molecule = protein)")
    except Exception as e:
        print(f"  ⚠️ image_molecules failed ({e}); proceeding with wrapped coords")
    traj = traj.atom_slice(keep)
    frames = np.linspace(0, traj.n_frames - 1, min(N_FRAMES, traj.n_frames), dtype=int)
    print(f"  trajectory {traj.n_frames} frames (stride 100) → analysing {len(frames)} snapshots")

    elements = [a.element.symbol for a in traj.topology.atoms]
    # FAD in the SLICED topology (atom_slice re-indexes) = the P-containing residue; the tunnelling
    # SOURCE is its isoalloxazine ring only (redox centre / N5 exit), not the ADP-phosphate tail.
    sliced_fad = next(r for r in traj.topology.residues if any(a.element.symbol == "P" for a in r.atoms))
    fad_local = [a.index for a in sliced_fad.atoms if a.name.rstrip("x") in RING_PREFIXES]
    if len(fad_local) < 5:
        fad_local = [a.index for a in sliced_fad.atoms if a.element.symbol != "H"]
    prot_local = np.array([a.index for a in traj.topology.atoms if a.residue.index != sliced_fad.index])
    print(f"  FAD ring source atoms: {len(fad_local)} · protein atoms: {len(prot_local)}")

    beta_ds = []
    for fr in frames:
        coords = traj.xyz[fr] * 10.0
        cen = coords[prot_local].mean(axis=0)
        dist = np.linalg.norm(coords[prot_local] - cen, axis=1)
        surf = prot_local[dist >= np.percentile(dist, 90)].tolist()
        G = graph_from_frame(coords, elements, fad_local)
        bd = best_beta_d(G, fad_local, surf)
        beta_ds.append(bd)
        print(f"    frame {fr:4d}: β·d = {bd:.2f}")

    bd = np.array([x for x in beta_ds if np.isfinite(x)])
    n_valid, n_total = int(bd.size), len(frames)
    if bd.size == 0:
        sys.exit("no finite pathway in any frame — production.dcd needs PBC-unwrapping (protein split across the box)")
    # safety guard: with image_molecules (above) all frames should be analysable; a high NaN rate here
    # would mean PBC handling failed (wrapped protein → disconnected graph), so flag it rather than
    # silently averaging a single survivor.
    pbc_limited = n_valid < n_total / 2
    gating = float(np.mean(np.exp(-2.0 * (bd - bd.mean())))) if n_valid > 1 else 1.0

    banner("Ensemble tunnelling result")
    flag = "  ⚠️ PBC-LIMITED — most frames' protein wrapped across the box; UNWRAP the trajectory + re-run" if pbc_limited else ""
    print(f"  analysable frames: {n_valid}/{n_total}{flag}")
    single_bd = json.loads((DFT_CACHE / "tunneling_pathway.json").read_text()).get("effective_beta_d", float("nan"))
    print(f"  β·d  mean={bd.mean():.2f}  std={bd.std():.2f}  min={bd.min():.2f}  max={bd.max():.2f}")
    print(f"  single-snapshot (script 28, AF3, from tunneling_pathway.json) = {single_bd}")
    if n_valid > 1:
        print(f"  conformational-gating factor ⟨k⟩/k(⟨β·d⟩) = {gating:.2f}×")
    verdict = ("⚠️ INCONCLUSIVE (n=1 after PBC losses; the one valid β·d≈AF3 hints robustness, not proof)"
               if pbc_limited else ("gating significant" if gating > 2 else "path thermally robust (gating modest)"))
    print(f"  → {verdict}")

    OUT.write_text(json.dumps({
        "method": "Beratan-Onuchic (script 28) replayed over MD-ensemble frames; KD-tree contact graph, "
                  "Dijkstra FAD-ring→surface; k_ET ∝ exp(−2·β·d)",
        "run": run.name,
        "n_valid_frames": n_valid,
        "n_total_frames": n_total,
        "pbc_limited": bool(pbc_limited),
        "beta_d_mean": round(float(bd.mean()), 3),
        "beta_d_std": round(float(bd.std()), 3),
        "beta_d_single_snapshot_AF3": single_bd,
        "conformational_gating_factor": round(gating, 3) if n_valid > 1 else None,
        "status": ("WIP — needs PBC-unwrapping of production.dcd before the ensemble is meaningful"
                   if pbc_limited else
                   f"complete — image_molecules co-locates the FAD cofactor; {n_valid}/{n_total} frames analysable"),
        "interpretation": verdict,
    }, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
