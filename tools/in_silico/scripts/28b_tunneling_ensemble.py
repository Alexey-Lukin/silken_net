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
The FAD cofactor is the GAFF "UNK" residue in the MD topology (script 27 note); we
identify it as the large non-standard residue and slice protein+FAD heavy atoms only
(the tunnelling path runs through the protein, not the surrounding matrix/water).
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
from lib.constants import REPO_ROOT, DFT_CACHE
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
    fad_res = next((r for r in top.residues
                    if r.n_atoms > 50 and r.name not in ("HOH", "WAT", "NA", "CL")), None)
    if fad_res is None:
        sys.exit("FAD (large non-standard residue) not found in topology")
    fad_atoms_full = {a.index for a in fad_res.atoms if a.element.symbol != "H"}
    prot_atoms_full = top.select("protein and element != H")
    keep = sorted(set(prot_atoms_full) | fad_atoms_full)
    print(f"  FAD residue '{fad_res.name}' ({fad_res.n_atoms} atoms); kept {len(keep)} heavy protein+FAD atoms")

    traj = md.load(str(run / "production.dcd"), top=str(run / "system.pdb"), stride=100)
    traj = traj.atom_slice(keep)
    frames = np.linspace(0, traj.n_frames - 1, min(N_FRAMES, traj.n_frames), dtype=int)
    print(f"  trajectory {traj.n_frames} frames (stride 100) → analysing {len(frames)} snapshots")

    elements = [a.element.symbol for a in traj.topology.atoms]
    fad_local = [i for i, a in enumerate(traj.topology.atoms) if a.residue.index == fad_res.index]
    prot_local = np.array([i for i in range(traj.n_atoms) if i not in set(fad_local)])

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
    if bd.size == 0:
        sys.exit("no finite pathway found in any frame")
    # gating: k ∝ exp(−2 β·d); enhancement of the ensemble rate over the mean-geometry rate
    gating = float(np.mean(np.exp(-2.0 * (bd - bd.mean()))))

    banner("Ensemble tunnelling result")
    print(f"  β·d  mean={bd.mean():.2f}  std={bd.std():.2f}  min={bd.min():.2f}  max={bd.max():.2f}  (n={bd.size})")
    print(f"  single-snapshot (script 28, AF3) = 2.05")
    print(f"  conformational-gating factor ⟨k⟩/k(⟨β·d⟩) = {gating:.2f}×")
    print(f"  → {'gating significant' if gating > 2 else 'path thermally robust (gating modest)'}")

    OUT.write_text(json.dumps({
        "method": "Beratan-Onuchic (script 28) replayed over MD-ensemble frames; KD-tree contact graph, "
                  "Dijkstra FAD→surface; k_ET ∝ exp(−2·β·d)",
        "run": run.name,
        "n_frames": int(bd.size),
        "beta_d_mean": round(float(bd.mean()), 3),
        "beta_d_std": round(float(bd.std()), 3),
        "beta_d_min": round(float(bd.min()), 3),
        "beta_d_max": round(float(bd.max()), 3),
        "beta_d_single_snapshot_AF3": 2.05,
        "conformational_gating_factor": round(gating, 3),
        "interpretation": "gating modest → single-snapshot β·d representative"
                          if gating <= 2 else "conformational gating significant",
    }, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
