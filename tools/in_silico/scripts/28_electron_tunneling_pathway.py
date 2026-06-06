#!/usr/bin/env python
"""
L3 — Beratan-Onuchic electron tunneling pathway analysis.

Maps the optimal electron transfer route from FAD cofactor to
protein surface through the dgrGcGDH structure. Uses a graph-based
model where atoms are nodes and bonds/contacts are edges with
coupling penalties:
  - Covalent bond:    penalty × 0.6
  - Hydrogen bond:    penalty × 0.9
  - Through-space:    penalty × exp(-β·R), β = 1.1 Å⁻¹

Finds the minimum-penalty path (Dijkstra) from FAD ring to the
nearest surface-accessible residue — this is the "wire" that Os
mediator must reach.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

try:
    import networkx as nx
except ImportError:
    sys.exit("networkx required: conda install networkx")

try:
    import mdtraj as md
except ImportError:
    sys.exit("mdtraj required (already in silken_md env)")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, REPO_ROOT
from lib.utils import banner

AF3_PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
OUT_JSON = DFT_CACHE / "tunneling_pathway.json"

BETA_THROUGH_SPACE = 1.1       # Å⁻¹ (Marcus/Moser canonical)
PENALTY_COVALENT = 0.6
PENALTY_HBOND = 0.9
COVALENT_CUTOFF = 1.8          # Å
HBOND_CUTOFF = 3.5             # Å (donor-acceptor distance)
CONTACT_CUTOFF = 6.0           # Å (through-space jump limit)

FAD_RESNAME = "FAD"


def build_contact_graph(traj) -> nx.Graph:
    """Build weighted graph from protein + FAD structure."""
    G = nx.Graph()
    top = traj.topology
    coords = traj.xyz[0] * 10.0  # nm → Å

    for atom in top.atoms:
        G.add_node(atom.index, name=atom.name, resname=atom.residue.name,
                   resid=atom.residue.resSeq, element=atom.element.symbol,  # resSeq = PDB numbering, not 0-based MDTraj index (#3)
                   pos=coords[atom.index])

    n = top.n_atoms
    for i in range(n):
        if G.nodes[i]["element"] == "H":
            continue
        pos_i = coords[i]
        for j in range(i + 1, n):
            if G.nodes[j]["element"] == "H":
                continue
            dist = np.linalg.norm(pos_i - coords[j])
            if dist > CONTACT_CUTOFF:
                continue

            if dist < COVALENT_CUTOFF:
                weight = PENALTY_COVALENT
                bond_type = "covalent"
            elif dist < HBOND_CUTOFF:
                ei = G.nodes[i]["element"]
                ej = G.nodes[j]["element"]
                if {ei, ej} & {"N", "O", "S"}:
                    weight = PENALTY_HBOND
                    bond_type = "hbond"
                else:
                    weight = np.exp(BETA_THROUGH_SPACE * dist)
                    bond_type = "through-space"
            else:
                weight = np.exp(BETA_THROUGH_SPACE * dist)
                bond_type = "through-space"

            G.add_edge(i, j, weight=weight, distance=dist, bond_type=bond_type)

    return G


def find_fad_atoms(G) -> list[int]:
    """Find FAD ring atoms (N5, C4a, N10 — redox center)."""
    fad_atoms = [n for n, d in G.nodes(data=True) if d["resname"] == FAD_RESNAME]
    if not fad_atoms:
        fad_atoms = [n for n, d in G.nodes(data=True)
                     if d["resname"] not in ("HOH", "NA", "CL") and d["resid"] > 580]
    return fad_atoms


def find_surface_atoms(G, coords, percentile=90) -> list[int]:
    """Find surface-exposed atoms (high distance from centroid)."""
    protein_atoms = [n for n, d in G.nodes(data=True)
                     if d["resname"] not in ("HOH", "NA", "CL", FAD_RESNAME)
                     and d["element"] != "H"]
    if not protein_atoms:
        return []
    positions = np.array([coords[a] for a in protein_atoms])
    centroid = positions.mean(axis=0)
    distances = np.linalg.norm(positions - centroid, axis=1)
    threshold = np.percentile(distances, percentile)
    return [a for a, d in zip(protein_atoms, distances, strict=False) if d >= threshold]


def main() -> int:
    if not AF3_PDB.exists():
        sys.exit(f"Missing {AF3_PDB}")

    banner("Beratan-Onuchic electron tunneling pathway analysis")

    traj = md.load(str(AF3_PDB))
    coords = traj.xyz[0] * 10.0  # nm → Å
    print(f"  Loaded: {traj.n_atoms} atoms, {traj.topology.n_residues} residues")

    banner("Building contact graph")
    G = build_contact_graph(traj)
    print(f"  Nodes: {G.number_of_nodes()}, Edges: {G.number_of_edges()}")

    fad_atoms = find_fad_atoms(G)
    surface_atoms = find_surface_atoms(G, coords)
    print(f"  FAD atoms: {len(fad_atoms)}")
    print(f"  Surface atoms (top 10%): {len(surface_atoms)}")

    if not fad_atoms or not surface_atoms:
        print("  ⚠️ Could not identify FAD or surface atoms")
        return 1

    banner("Finding optimal tunneling pathway (Dijkstra)")
    best_path = None
    best_cost = float("inf")

    for source in fad_atoms[:5]:
        try:
            lengths, paths = nx.single_source_dijkstra(G, source, weight="weight")
        except Exception:
            continue
        for target in surface_atoms:
            if target in lengths and lengths[target] < best_cost:
                best_cost = lengths[target]
                best_path = paths[target]

    if best_path is None:
        print("  ⚠️ No pathway found")
        return 1

    euclidean = np.linalg.norm(coords[best_path[0]] - coords[best_path[-1]])
    path_length = sum(
        G.edges[best_path[i], best_path[i + 1]]["distance"]
        for i in range(len(best_path) - 1)
    )

    print(f"  Path length: {len(best_path)} atoms")
    print(f"  Euclidean distance: {euclidean:.1f} Å")
    print(f"  Through-bond path: {path_length:.1f} Å")
    print(f"  Coupling penalty: {best_cost:.4f}")
    print(f"  Effective β·d: {np.log(best_cost):.2f}")

    print("\n  Pathway:")
    residues_in_path = []
    for i, atom_idx in enumerate(best_path):
        d = G.nodes[atom_idx]
        residues_in_path.append(f"{d['resname']}{d['resid']}")
        if i < len(best_path) - 1:
            edge = G.edges[best_path[i], best_path[i + 1]]
            arrow = f"--({edge['bond_type']}, {edge['distance']:.1f}Å)-->"
        else:
            arrow = ""
        if i < 6 or i >= len(best_path) - 3:
            print(f"    [{i}] {d['resname']}{d['resid']}:{d['name']} {arrow}")
        elif i == 6:
            print(f"    ... ({len(best_path) - 9} intermediate atoms) ...")

    unique_residues = list(dict.fromkeys(residues_in_path))

    result = {
        "method": "Beratan-Onuchic (Dijkstra shortest path)",
        "beta_through_space": BETA_THROUGH_SPACE,
        "path_atoms": len(best_path),
        "euclidean_distance_A": round(float(euclidean), 2),
        "through_bond_path_A": round(float(path_length), 2),
        "coupling_penalty": round(float(best_cost), 6),
        "effective_beta_d": round(float(np.log(best_cost)), 3),
        "residue_pathway": unique_residues[:20],
        "source": f"{G.nodes[best_path[0]]['resname']}{G.nodes[best_path[0]]['resid']}",
        "target": f"{G.nodes[best_path[-1]]['resname']}{G.nodes[best_path[-1]]['resid']}",
    }

    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(result, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
