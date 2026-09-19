#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
CHEM.11 — compensating surface-polar mutations for the aglycosylated dgrFAD-GDH.

L1 §2 records a recipe: the 11 removed glycans expose hydrophobic surface, "an in-house
hydrophobic-SASA proxy flags 4 aggregation-prone sites (Gln71, Gln200, Gln258, Gln405)",
and before CRO expression one should add "Aggrescan3D + compensating surface-polar
mutations (Asp/Ser) near them". This script is the instrument for the second half.

⚠️ THE PROXY DID NOT EXIST IN THE TREE. Neither a script nor a cache defined it — the
2026-06-06 commit (2e607abc) wrote the four-site CONCLUSION into canon and committed no
measurer, so for fifteen months the freeze-gating claim was prose. This script therefore
DECLARES a proxy (below) and then asks whether it re-selects the published four. It does,
but only inside a contact shell: see `proxy_sensitivity`. Outside 6.5–7.5 Å the set changes
membership, and without the aromatics in the residue set it never reproduces at all. So the
published four is one definition's answer, not a definition-free fact.

WHAT IS COMPUTED
  1. the declared hydrophobic-SASA patch proxy over all 11 N→Q sites, with a radius and
     residue-set sensitivity, and the same score for all 600 residues so a hotspot can be
     read against the protein's OWN surface rather than only against its ten siblings;
  2. per hotspot, the surface apolar residues that are candidates for an Asp/Ser swap, each
     carrying its exclusion verdict (FAD pocket · electron-exit path · burial · secondary
     structure) with the measured distance that produced it;
  3. for every candidate × {Asp, Ser}: the built mutant (pdbfixer) after a side-chain-only
     OpenMM minimisation, its patch apolar-SASA change, the local and surface formal-charge
     change, and its distance to FAD and to the electron path;
  4. a recommended set selected by FIELDS (see `recommendation_rule`), never by prose — and it
     REFUSES the Asp/Ser choice where the two tie inside the measured noise floor, because the
     ranked winner at Leu80 was observed flipping between runs of identical inputs and what
     separates the two is a charge;
  5. the recommended set built as ONE variant, since a freeze is a sequence and not a sum of
     single mutations; and the Å² each declared threshold REFUSES, so its value stays visible.

WHAT IS **NOT** COMPUTED — and each of these is absent, not merely undiscussed
  · Aggrescan3D was NOT run. It is an external web server (registration/upload), outside
    this repo's zero-network compute. The L1 §2 recipe's first half remains OPEN.
  · This is not an aggregation PREDICTION. An exposed apolar patch is a static surface
    descriptor; aggregation is a multi-molecule, concentration-, pH- and shear-dependent
    kinetic process. Nothing here computes a rate, a solubility or a critical concentration.
  · No sequence conservation / phylogeny. A position may be catalytically or structurally
    load-bearing for reasons invisible to geometry, and no alignment is consulted HERE — that
    axis has its own instrument since 2026-09-18 (script 70), and its output is NOT an input to
    this score: the two are read side by side, never merged.
  · No MD of any mutant, no ΔΔG of folding, no pKa model. The minimisation relaxes side
    chains in an implicit solvent for a few hundred steps; it does not judge stability.
  · No catalytic-residue list exists in our canon for GcGDH, so "catalytic" is approximated
    by the FAD-pocket shell — a geometric stand-in, declared as such.
  · The only substitutions scored are apolar→{Asp, Ser}. Adding charge at a position that is
    already polar (e.g. Thr→Asp) raises local polarity WITHOUT removing apolar area; that
    lever exists and is not scored here.
  · The 11 Gln sites themselves are never mutation targets — they are the N→Q design.

Runtime ~9 min (CPU): 24 mutants + 4 reference replicates + the combined variant, ~17 s each.
Output: tools/in_silico/cache/chemistry/chem11_aggregation_compensation.json
"""
from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path

import numpy as np

try:
    import mdtraj as md
except ImportError:
    sys.exit("mdtraj required (silken_md env)")
try:
    from openmm import LangevinMiddleIntegrator, Platform, app, unit
    from pdbfixer import PDBFixer
except ImportError:
    sys.exit("openmm + pdbfixer required (silken_md env)")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import AF3_PDB, CACHE_DIR, DFT_CACHE, PH, REPO_ROOT, TEMPERATURE_K
from lib.utils import banner

AF3_CIF = REPO_ROOT / "docs/protocols/ebfc/in_silico/alphafold3/fold_dgrgcgdh_fad_v1_model_0.cif"
TUNNELING_JSON = DFT_CACHE / "tunneling_pathway.json"
OUT_DIR = CACHE_DIR / "chemistry"
OUT_JSON = OUT_DIR / "chem11_aggregation_compensation.json"

# ─────────────────────────── declared parameters ───────────────────────────
# Every threshold below is OURS unless a source is named on its line. None of them is
# "standard"; each carries a sensitivity in the cache.

# The 11 N→Q sequon positions — L1 §2 table (the design, not a computed set).
DEGLYC_SITES = (71, 100, 192, 200, 249, 258, 271, 355, 380, 405, 463)
# The four sites L1 §2 publishes as aggregation-prone. Held here to be TESTED, not assumed.
PUBLISHED_HOTSPOTS = (71, 200, 258, 405)

# Aggregation-prone residue set = Kyte-Doolittle hydropathy > 0 {A,C,F,I,L,M,V}
# (Kyte & Doolittle 1982, J. Mol. Biol. 157(1):105-132, doi:10.1016/0022-2836(82)90515-0 —
# Crossref-verified) ∪ {W, Y}. The aromatic addition is OURS: W and Y are hydropathy-negative
# on that scale yet dominate aromatic-stacking aggregation propensity. Both sets are swept.
KD_POSITIVE = frozenset({"ALA", "CYS", "PHE", "ILE", "LEU", "MET", "VAL"})
AROMATIC_ADD = frozenset({"TRP", "TYR"})
AGGREGATION_PRONE = KD_POSITIVE | AROMATIC_ADD

# Patch radius: side-chain centroid to side-chain centroid. 7.0 Å is a CONTACT SHELL — the
# first shell of side chains that can touch the site's own. Ours; swept 5–12 Å.
PATCH_RADIUS_A = 7.0
PATCH_RADIUS_SWEEP_A = (5.0, 6.0, 6.5, 7.0, 7.5, 8.0, 10.0, 12.0)

# Candidate search radius around a hotspot. Ours; the two sensitivity values are 8 and 12.
# Candidates are COLLECTED out to the widest swept radius and then filtered, so the 12 Å row
# is a real measurement rather than a copy of the 10 Å one.
CAND_RADIUS_A = 10.0
CAND_RADIUS_SENSITIVITY_A = (8.0, 12.0)
CAND_COLLECT_RADIUS_A = max(CAND_RADIUS_A, *CAND_RADIUS_SENSITIVITY_A)

# A candidate must present at least this much solvent-exposed apolar area to be worth
# replacing — the quantity the recommendation is ABOUT, so no normalisation is borrowed.
CAND_APOLAR_MIN_A2 = 20.0
CAND_APOLAR_MIN_SENSITIVITY_A2 = (10.0, 30.0)

# Burial = 1 − (side-chain SASA in the protein / side-chain SASA of the SAME side chain,
# same conformation, sliced out of the structure). Computed here, so no external max-ASA
# table and no from-memory numbers enter. Ours; swept.
CAND_BURIAL_MAX = 0.75
CAND_BURIAL_MAX_SENSITIVITY = (0.65, 0.85)

# Keep-out shells. Conservative on purpose: the gene freeze is not cheap to revisit and the
# MET architecture (L1 §5) is the whole cell. Ours; the FAD shell carries a sensitivity.
FAD_POCKET_EXCL_A = 12.0
FAD_POCKET_EXCL_SENSITIVITY_A = 8.0
EPATH_EXCL_A = 8.0

# Electron-exit guard residues: the Beratan-Onuchic path is LOADED from script 28's cache
# (drift-proof — never mirrored here), plus Tyr90 (the d_FAD exit reference, L1 §4) and
# Lys109/Lys262 (CHEM.10 genipin shield, L1 §2).
EPATH_EXTRA = (90, 109, 262)

# Secondary structure in which an introduced Asp is treated as risky (DSSP letters).
# Declared heuristic; it blocks ASP ONLY — Ser carries no charge and no β-branch, so it is
# not blocked by secondary structure.
SS_RISKY_FOR_ASP = frozenset({"H", "G", "I", "E", "B"})

# Formal-charge convention for the charge columns: at the matrix pH of 4.5 an introduced
# carboxylate is only partly deprotonated, so −1 is an UPPER BOUND on delivered charge.
# No pKa model is used and none is implied.
FORMAL_CHARGE = {"ASP": -1, "GLU": -1, "LYS": +1, "ARG": +1}
# An ionisable residue counts toward SURFACE charge when its side chain actually reaches the
# solvent. Ours. Without this floor the "surface" charge is the whole-protein charge under a
# name that does not say so.
SURFACE_CHARGE_SASA_MIN_A2 = 10.0

# Minimisation. constraints=None is forced by the frozen backbone: OpenMM refuses a
# constraint on a massless particle.
FF_XMLS = ("amber14/protein.ff14SB.xml", "implicit/gbn2.xml")
MIN_ITERATIONS = 500
NONBONDED_CUTOFF_NM = 1.6
BACKBONE = frozenset({"N", "CA", "C", "O", "OXT"})

SUBSTITUTIONS = ("ASP", "SER")
# Reference replicates behind the noise floor. Four, not two, because two was MEASURED to be
# insufficient: successive two-run estimates gave 2.52 and 0.25 Å².
N_REF_REPLICATES = 4
# When Asp and Ser tie inside the noise floor the script refuses to recommend either — but the
# COMBINED variant still has to be built out of real residues. It is built as Ser: that is the
# option which commits no charge, so the build does not smuggle in the decision the tie refused.
TIE_BUILD_SUBSTITUTION = "SER"
PROBE_RADIUS_NM = 0.14      # mdtraj shrake_rupley default, stated so it is not implicit
N_SPHERE_POINTS = 960       # mdtraj shrake_rupley default


# ─────────────────────────── surface geometry ───────────────────────────
def side_chain(res):
    """Side-chain atoms; for Gly (no side chain) fall back to the whole residue."""
    atoms = [a for a in res.atoms if a.name not in BACKBONE]
    return atoms if atoms else list(res.atoms)


class Surface:
    """Per-residue SASA decomposition of one structure (protein chain 0 + any cofactor)."""

    def __init__(self, traj):
        self.traj = traj
        self.top = traj.topology
        self.xyz = traj.xyz[0] * 10.0
        self.sasa_atom = md.shrake_rupley(traj, probe_radius=PROBE_RADIUS_NM,
                                          n_sphere_points=N_SPHERE_POINTS, mode="atom")[0] * 100.0
        self.prot = [r for r in self.top.residues if r.chain.index == 0]
        self.name = {r.resSeq: r.name for r in self.prot}
        self.centroid, self.apolar, self.sc_sasa = {}, {}, {}
        for r in self.prot:
            sc = side_chain(r)
            idx = [a.index for a in sc]
            self.centroid[r.resSeq] = self.xyz[idx].mean(axis=0)
            self.sc_sasa[r.resSeq] = float(sum(self.sasa_atom[i] for i in idx))
            self.apolar[r.resSeq] = float(sum(self.sasa_atom[a.index] for a in sc
                                              if a.element.symbol in ("C", "S")))
        self._cofactor = np.array([self.xyz[a.index] for a in self.top.atoms
                                   if a.residue.chain.index > 0])

    def patch(self, site: int, radius: float = PATCH_RADIUS_A, residue_set=AGGREGATION_PRONE) -> float:
        """The proxy: exposed apolar area carried by aggregation-prone side chains whose own
        centroid lies within `radius` of this site's. A buried member contributes ~0 by
        construction, so no separate exposure filter is applied to members."""
        c = self.centroid[site]
        return float(sum(self.apolar[r.resSeq] for r in self.prot
                         if r.resSeq != site and r.name in residue_set
                         and np.linalg.norm(self.centroid[r.resSeq] - c) <= radius))

    def patch_members(self, site: int, radius: float = PATCH_RADIUS_A) -> list[dict]:
        c = self.centroid[site]
        out = []
        for r in self.prot:
            if r.resSeq == site or r.name not in AGGREGATION_PRONE:
                continue
            d = float(np.linalg.norm(self.centroid[r.resSeq] - c))
            if d <= radius:
                out.append({"residue": f"{r.name}{r.resSeq}", "distance_A": round(d, 2),
                            "exposed_apolar_A2": round(self.apolar[r.resSeq], 1)})
        return sorted(out, key=lambda m: m["distance_A"])

    def burial(self, site: int) -> float:
        """1 − context SASA / isolated SASA of the SAME side chain in the SAME conformation."""
        idx = [a.index for a in side_chain(next(r for r in self.prot if r.resSeq == site))]
        sub = self.traj.atom_slice(idx)
        iso = float((md.shrake_rupley(sub, probe_radius=PROBE_RADIUS_NM,
                                      n_sphere_points=N_SPHERE_POINTS, mode="atom")[0] * 100.0).sum())
        return 1.0 - (self.sc_sasa[site] / iso if iso > 0 else 0.0)

    def d_cofactor(self, site: int) -> float:
        if not len(self._cofactor):
            return float("nan")
        return float(np.min(np.linalg.norm(self._cofactor - self.centroid[site], axis=1)))

    def d_to(self, site: int, others) -> float:
        return float(min(np.linalg.norm(self.centroid[o] - self.centroid[site]) for o in others))

    def net_formal_charge(self, sites=None) -> int:
        """Net formal charge over the whole chain, or over `sites` — no exposure filter."""
        pool = self.prot if sites is None else [r for r in self.prot if r.resSeq in sites]
        return int(sum(FORMAL_CHARGE.get(r.name, 0) for r in pool))

    def surface_net_formal_charge(self, sites=None) -> int:
        """Net formal charge counting only side chains that reach the solvent."""
        pool = self.prot if sites is None else [r for r in self.prot if r.resSeq in sites]
        return int(sum(FORMAL_CHARGE.get(r.name, 0) for r in pool
                       if self.sc_sasa[r.resSeq] >= SURFACE_CHARGE_SASA_MIN_A2))

    def within(self, site: int, radius: float) -> set[int]:
        c = self.centroid[site]
        return {r.resSeq for r in self.prot
                if np.linalg.norm(self.centroid[r.resSeq] - c) <= radius}


# ─────────────────────────── inputs ───────────────────────────
def load_plddt() -> dict[int, float]:
    """Per-residue pLDDT = the CA atom's B_iso from the AF3 CIF.

    The CA convention is not a choice made here: L1 §4 publishes Tyr90 = 98.71 / THR288 =
    95.57, and those are the CA values (the residue MEANS are 98.23 / 91.36). Reproducing
    the canon numbers is asserted in `controls`. The canonical PDB is not a source for this
    — it was written by OpenMM, which zeroed the B-factor column.
    """
    ca, mean = {}, {}
    for line in AF3_CIF.read_text().splitlines():
        if not line.startswith("ATOM"):
            continue
        f = line.split()
        if f[16] != "A":
            continue
        seq, b = int(f[15]), float(f[14])
        mean.setdefault(seq, []).append(b)
        if f[3] == "CA":
            ca[seq] = b
    if not ca:
        raise RuntimeError(f"no pLDDT parsed from {AF3_CIF} — do not proceed with a guess")
    return ca, {k: statistics.mean(v) for k, v in mean.items()}


def electron_path_residues() -> list[int]:
    """Guard residues on the electron exit: script 28's path, LOADED, + the named extras."""
    tp = json.loads(TUNNELING_JSON.read_text())
    path = [int("".join(c for c in r if c.isdigit())) for r in tp["residue_pathway"]
            if not r.startswith("FAD")]
    return sorted(set(path) | set(EPATH_EXTRA))


# ─────────────────────────── mutant construction ───────────────────────────
def build_and_minimise(mutations: list[str], tag: str, workdir: Path) -> Path:
    """pdbfixer mutate → protonate at the matrix pH → side-chain-only minimisation.

    The cofactor is removed for the minimisation (FAD has no ff14SB template and
    parameterising it is script 02's job, not this one's). That is admissible ONLY because
    the backbone is frozen: the global frame is preserved exactly, so the original FAD
    coordinates can be re-attached afterwards. `controls.backbone_frozen_max_CA_drift_A`
    measures that and would be non-zero if the freeze ever broke.
    """
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(False)
    if mutations:
        fixer.applyMutations(mutations, "A")
    fixer.findMissingResidues()
    fixer.missingResidues = {}          # never model absent termini/loops into a freeze input
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(PH)
    forcefield = app.ForceField(*FF_XMLS)
    system = forcefield.createSystem(fixer.topology, nonbondedMethod=app.CutoffNonPeriodic,
                                     nonbondedCutoff=NONBONDED_CUTOFF_NM * unit.nanometer,
                                     constraints=None)
    for atom in fixer.topology.atoms():
        if atom.name in BACKBONE:
            system.setParticleMass(atom.index, 0.0)
    integrator = LangevinMiddleIntegrator(TEMPERATURE_K * unit.kelvin, 1 / unit.picosecond,
                                          0.002 * unit.picoseconds)
    sim = app.Simulation(fixer.topology, system, integrator, Platform.getPlatformByName("CPU"))
    sim.context.setPositions(fixer.positions)
    sim.minimizeEnergy(maxIterations=MIN_ITERATIONS)
    positions = sim.context.getState(getPositions=True).getPositions()
    out = workdir / f"{tag}.pdb"
    with out.open("w") as fh:
        app.PDBFile.writeFile(fixer.topology, positions, fh, keepIds=True)
    return out


def surface_of(minimised_pdb: Path, cofactor_traj, workdir: Path, tag: str) -> Surface:
    """Heavy-atom surface of the minimised protein with the original cofactor re-attached."""
    prot = md.load(str(minimised_pdb))
    prot = prot.atom_slice(prot.topology.select("not element H"))
    joined = prot.stack(cofactor_traj)
    path = workdir / f"{tag}_complex.pdb"
    joined.save(str(path))
    return Surface(md.load(str(path)))


def ca_drift(a: Surface, b: Surface) -> float:
    ia = a.traj.topology.select("name CA and chainid 0")
    ib = b.traj.topology.select("name CA and chainid 0")
    if len(ia) != len(ib):
        return float("nan")
    return float((np.linalg.norm(a.traj.xyz[0][ia] - b.traj.xyz[0][ib], axis=1) * 10.0).max())


# ─────────────────────────── main ───────────────────────────
def main() -> int:
    t_start = time.time()
    workdir = OUT_DIR / "_chem11_work"
    workdir.mkdir(parents=True, exist_ok=True)

    banner("CHEM.11 — anti-aggregation compensation (L1 §2)")
    raw = md.load(str(AF3_PDB))
    cofactor = raw.atom_slice(raw.topology.select("chainid 1"))
    af3 = Surface(raw)
    plddt_ca, plddt_mean = load_plddt()
    epath = electron_path_residues()
    print(f"  AF3 model: {raw.n_atoms} atoms, {raw.topology.n_residues} residues; "
          f"cofactor {cofactor.n_atoms} atoms")
    print(f"  electron-exit guard residues (28's cache + L1 §4/CHEM.10): "
          f"{[f'{af3.name[s]}{s}' for s in epath]}")

    # ── 1. the proxy on the AF3 model, and whether it re-selects the published four ──
    banner("Proxy over the 11 N→Q sites")
    site_scores = {s: af3.patch(s) for s in DEGLYC_SITES}
    ranked = sorted(DEGLYC_SITES, key=lambda s: -site_scores[s])
    reselects = set(ranked[:len(PUBLISHED_HOTSPOTS)]) == set(PUBLISHED_HOTSPOTS)
    for s in ranked:
        print(f"  Gln{s:<4} patch={site_scores[s]:7.1f} Å²  "
              f"{'← published hotspot' if s in PUBLISHED_HOTSPOTS else ''}")
    print(f"  re-selects the published four at R={PATCH_RADIUS_A} Å: {reselects}")

    sensitivity_radius = []
    for r in PATCH_RADIUS_SWEEP_A:
        sc = {s: af3.patch(s, radius=r) for s in DEGLYC_SITES}
        order = sorted(DEGLYC_SITES, key=lambda s: -sc[s])
        sensitivity_radius.append({
            "radius_A": r, "top4": order[:4],
            "reselects_published_set": set(order[:4]) == set(PUBLISHED_HOTSPOTS),
            "scores_A2": {f"Gln{s}": round(sc[s], 1) for s in order},
        })
    sensitivity_set = []
    for label, rset in (("kyte_doolittle_positive", KD_POSITIVE),
                        ("kyte_doolittle_positive_plus_aromatics", AGGREGATION_PRONE)):
        rows = []
        for r in (6.5, 7.0, 7.5, 10.0):
            sc = {s: af3.patch(s, radius=r, residue_set=rset) for s in DEGLYC_SITES}
            order = sorted(DEGLYC_SITES, key=lambda s: -sc[s])
            rows.append({"radius_A": r, "top4": order[:4],
                         "reselects_published_set": set(order[:4]) == set(PUBLISHED_HOTSPOTS)})
        sensitivity_set.append({"residue_set": label, "members": sorted(rset), "rows": rows})

    # ── 2. the protein's OWN surface as the yardstick ──
    banner("Whole-surface context — the same proxy on all 600 residues")
    all_scores = {r.resSeq: af3.patch(r.resSeq) for r in af3.prot}
    values = np.array(sorted(all_scores.values()))
    worst = sorted(all_scores.items(), key=lambda kv: -kv[1])[:10]
    context = {
        "note": "the published four are the worst among the ELEVEN deglycosylation sites; "
                "against the protein's own surface they are not its worst patches",
        "median_A2": round(float(np.median(values)), 1),
        "p90_A2": round(float(np.percentile(values, 90)), 1),
        "max_A2": round(float(values.max()), 1),
        "largest_patches_protein_wide": [{"residue": f"{af3.name[k]}{k}", "patch_A2": round(v, 1)}
                                         for k, v in worst],
    }
    print(f"  protein-wide patch: median {context['median_A2']} · p90 {context['p90_A2']} · "
          f"max {context['max_A2']} Å² ({worst[0][0]} → {af3.name[worst[0][0]]}{worst[0][0]})")

    hotspots = []
    for s in PUBLISHED_HOTSPOTS:
        pct = 100.0 * float((values < all_scores[s]).sum()) / len(values)
        hotspots.append({
            "site": s, "residue": f"{af3.name[s]}{s}",
            "patch_apolar_A2": round(site_scores[s], 1),
            "patch_members": af3.patch_members(s),
            "site_sidechain_sasa_A2": round(af3.sc_sasa[s], 1),
            "site_burial": round(af3.burial(s), 3),
            "surface_percentile_protein_wide": round(pct, 1),
            "plddt_ca": round(plddt_ca[s], 2),
            "d_cofactor_A": round(af3.d_cofactor(s), 1),
            "d_electron_path_A": round(af3.d_to(s, epath), 1),
            "proxy_rank_among_11": ranked.index(s) + 1,
        })
        print(f"  Gln{s:<4} percentile {pct:5.1f} · burial {af3.burial(s):.3f} · "
              f"d_FAD {af3.d_cofactor(s):5.1f} · d_epath {af3.d_to(s, epath):5.1f} Å")

    # ── 3. candidate compensating positions ──
    banner("Candidate positions (apolar, near a hotspot)")
    candidates: dict[int, list[dict]] = {}
    for s in PUBLISHED_HOTSPOTS:
        rows = []
        for r in af3.prot:
            q = r.resSeq
            if q == s or r.name not in AGGREGATION_PRONE or q in DEGLYC_SITES:
                continue
            d = float(np.linalg.norm(af3.centroid[q] - af3.centroid[s]))
            if d > CAND_COLLECT_RADIUS_A:
                continue
            burial = af3.burial(q)
            d_fad = af3.d_cofactor(q)
            d_ep = af3.d_to(q, epath)
            excluded = []
            if d_fad < FAD_POCKET_EXCL_A:
                excluded.append(f"fad_pocket(d={d_fad:.1f}<{FAD_POCKET_EXCL_A})")
            if d_ep < EPATH_EXCL_A:
                excluded.append(f"electron_path(d={d_ep:.1f}<{EPATH_EXCL_A})")
            if burial > CAND_BURIAL_MAX:
                excluded.append(f"buried({burial:.2f}>{CAND_BURIAL_MAX})")
            if af3.apolar[q] < CAND_APOLAR_MIN_A2:
                excluded.append(f"too_little_apolar({af3.apolar[q]:.1f}<{CAND_APOLAR_MIN_A2})")
            rows.append({
                "position": q, "residue": f"{r.name}{q}", "wt_resname": r.name,
                "distance_to_hotspot_A": round(d, 2),
                "in_primary_radius": d <= CAND_RADIUS_A,
                "exposed_apolar_A2": round(af3.apolar[q], 1),
                "burial": round(burial, 3),
                "dssp": None,          # filled below
                "d_cofactor_A": round(d_fad, 1),
                "d_electron_path_A": round(d_ep, 1),
                "plddt_ca": round(plddt_ca[q], 2),
                "excluded_by": excluded,
            })
        candidates[s] = sorted(rows, key=lambda x: -x["exposed_apolar_A2"])

    dssp = md.compute_dssp(raw, simplified=False)[0]
    ss_of = {r.resSeq: str(dssp[r.index]) for r in af3.prot}
    for s, rows in candidates.items():
        for row in rows:
            code = ss_of[row["position"]]
            row["dssp"] = code
            if code in SS_RISKY_FOR_ASP:
                row["excluded_by"] = row["excluded_by"] + [f"ss_regular_asp_only({code})"]
        print(f"  Gln{s}: {sum(1 for r in rows if r['in_primary_radius'])} within "
              f"{CAND_RADIUS_A} Å, "
              f"{sum(1 for r in rows if r['in_primary_radius'] and not r['excluded_by'])} "
              f"clear of every filter")

    # mutants are built for every candidate that has apolar area worth removing — including
    # the excluded ones, so the founder sees the number being declined, not only the label.
    to_build = [(s, row) for s, rows in candidates.items() for row in rows
                if row["exposed_apolar_A2"] >= CAND_APOLAR_MIN_A2]
    positions = sorted({row["position"] for _, row in to_build})
    print(f"  building mutants for {len(positions)} positions × {len(SUBSTITUTIONS)} substitutions")

    # ── 4. reference replicates (the noise floor is a control that CAN fail) ──
    # TWO replicates are not enough and measuring it proved it: two runs of an earlier version
    # gave floors of 2.52 and 0.25 Å² — a single |a−b| is one sample of the spread, and the
    # invariant that a Δ's SIGN is a finding rests on this number. So: N replicates, and the
    # floor is the widest pairwise disagreement over all of them, per hotspot.
    banner(f"Reference: {N_REF_REPLICATES} identical replicates ({MIN_ITERATIONS} iterations)")
    refs = [surface_of(build_and_minimise([], f"ref_{i}", workdir), cofactor, workdir, f"ref_{i}")
            for i in range(N_REF_REPLICATES)]
    ref_a = refs[0]          # declared: replicate 0 is the reference every Δ is taken against
    replicate_patches = {f"Gln{s}": [round(r.patch(s), 2) for r in refs]
                         for s in PUBLISHED_HOTSPOTS}
    noise = {f"Gln{s}": round(max(v) - min(v), 2) for s, v in
             ((s, [r.patch(s) for r in refs]) for s in PUBLISHED_HOTSPOTS)}
    noise_floor = max(noise.values())
    print(f"  per-hotspot spread over replicates: {noise} → floor {noise_floor} Å²")
    print("  (pdbfixer's addMissingHydrogens is non-deterministic; this is that cost, measured)")

    ref_patch = {s: ref_a.patch(s) for s in PUBLISHED_HOTSPOTS}
    ref_surface_charge = ref_a.surface_net_formal_charge()
    ref_total_charge = ref_a.net_formal_charge()

    # ── 5. mutants ──
    banner("Mutants")
    mutants = []
    max_drift = 0.0
    for pos in positions:
        wt = af3.name[pos]
        for new in SUBSTITUTIONS:
            tag = f"{wt}{pos}{new}"
            t0 = time.time()
            mutant = surface_of(build_and_minimise([f"{wt}-{pos}-{new}"], tag, workdir),
                                cofactor, workdir, tag)
            drift = ca_drift(ref_a, mutant)
            max_drift = max(max_drift, drift)
            row = {
                "position": pos, "from": wt, "to": new, "mutation": f"{wt}{pos}{new}",
                "surface_net_formal_charge_ref": ref_surface_charge,
                "surface_net_formal_charge_mutant": mutant.surface_net_formal_charge(),
                "whole_chain_net_formal_charge_ref": ref_total_charge,
                "whole_chain_net_formal_charge_mutant": mutant.net_formal_charge(),
                "backbone_CA_drift_A": round(drift, 4),
                "per_hotspot": {},
            }
            row["delta_surface_net_formal_charge"] = (row["surface_net_formal_charge_mutant"]
                                                      - ref_surface_charge)
            for s in PUBLISHED_HOTSPOTS:
                shell = ref_a.within(s, PATCH_RADIUS_A)
                row["per_hotspot"][f"Gln{s}"] = {
                    "patch_ref_A2": round(ref_patch[s], 1),
                    "patch_mutant_A2": round(mutant.patch(s), 1),
                    "delta_patch_apolar_A2": round(mutant.patch(s) - ref_patch[s], 1),
                    "patch_surface_net_formal_charge_ref": ref_a.surface_net_formal_charge(shell),
                    "patch_surface_net_formal_charge_mutant": mutant.surface_net_formal_charge(shell),
                }
            mutants.append(row)
            near = [s for s in PUBLISHED_HOTSPOTS
                    if any(r["position"] == pos for r in candidates[s])]
            own = min(near, key=lambda s: next(r["distance_to_hotspot_A"]
                                               for r in candidates[s] if r["position"] == pos))
            d = row["per_hotspot"][f"Gln{own}"]["delta_patch_apolar_A2"]
            print(f"  {tag:<12} ΔSASA(Gln{own}) = {d:+7.1f} Å²  "
                  f"Δq = {row['delta_surface_net_formal_charge']:+d}  ({time.time()-t0:.0f} s)")

    # ── 6. recommendation — by fields ──
    banner("Recommendation")
    rule = {
        "1_position_clear_of_hard_keepouts": "excluded_by contains no fad_pocket / "
                                             "electron_path / buried / too_little_apolar entry",
        "2_substitution_allowed": "Asp is blocked where DSSP ∈ "
                                  f"{sorted(SS_RISKY_FOR_ASP)}; Ser is never blocked by DSSP",
        "3_measurably_reduces_the_patch": f"delta_patch_apolar_A2 < −noise_floor "
                                          f"({-noise_floor} Å², measured this run)",
        "4_one_substitution_per_position": "the larger |delta| of the admissible Asp/Ser pair — "
                                           "UNLESS the two differ by less than the noise floor, in "
                                           "which case this script does NOT pick: `to` is null and "
                                           "both stay in `admissible_substitutions`",
        "4a_why_not_pick_on_a_tie": "measured: the ranked winner at Leu80 flipped Asp↔Ser between "
                                    "two runs of identical inputs. The difference is noise, the "
                                    "consequence is a CHARGE, and noise may not decide a charge",
        "5_cap": "at most 2 per hotspot",
        "6_build_resolution": f"the combined variant has to be built from concrete residues, so an "
                              f"undecided position is built as {TIE_BUILD_SUBSTITUTION} and says so "
                              f"in `tie_resolved_for_this_build` — a build choice, not a "
                              f"recommendation",
    }
    by_mutation = {m["mutation"]: m for m in mutants}
    recommended, per_hotspot_counts = [], {}
    no_candidate = []
    for s in PUBLISHED_HOTSPOTS:
        clear = [r for r in candidates[s] if r["in_primary_radius"]
                 and not [e for e in r["excluded_by"] if not e.startswith("ss_regular_asp_only")]]
        options = []
        for row in clear:
            ss_blocks_asp = ss_of[row["position"]] in SS_RISKY_FOR_ASP
            for new in SUBSTITUTIONS:
                if new == "ASP" and ss_blocks_asp:
                    continue
                key = f"{row['wt_resname']}{row['position']}{new}"
                if key not in by_mutation:
                    continue
                delta = by_mutation[key]["per_hotspot"][f"Gln{s}"]["delta_patch_apolar_A2"]
                if delta >= -noise_floor:
                    continue
                options.append((row, new, delta, key))
        best_per_pos = {}
        for row, new, delta, key in options:
            cur = best_per_pos.get(row["position"])
            if cur is None or abs(delta) > abs(cur[2]):
                best_per_pos[row["position"]] = (row, new, delta, key)
        chosen = sorted(best_per_pos.values(), key=lambda o: o[2])[:2]
        per_hotspot_counts[f"Gln{s}"] = len(chosen)
        if not chosen:
            in_radius = [r for r in candidates[s] if r["in_primary_radius"]]
            reasons = sorted({e.split("(")[0] for r in in_radius for e in r["excluded_by"]})
            no_candidate.append({"site": s, "residue": f"Gln{s}",
                                 "candidates_in_radius": len(in_radius),
                                 "exclusion_reasons_present": reasons})
        for row, new, delta, key in chosen:
            # Asp-vs-Ser can be a tie the measurement cannot break, and the ranked winner at Leu80
            # was MEASURED to flip between two runs of identical inputs. So on a tie this script
            # names the POSITION and refuses the substitution: `to` is null and both stay listed.
            sibling = next((o for o in options
                            if o[0]["position"] == row["position"] and o[1] != new), None)
            tie = sibling is not None and abs(sibling[2] - delta) < noise_floor
            per_sub = {n: by_mutation[f"{row['wt_resname']}{row['position']}{n}"]
                       ["per_hotspot"][f"Gln{s}"]["delta_patch_apolar_A2"]
                       for n in SUBSTITUTIONS
                       if f"{row['wt_resname']}{row['position']}{n}" in by_mutation}
            admissible = sorted({new} | ({sibling[1]} if sibling else set()))
            build_sub = (TIE_BUILD_SUBSTITUTION if tie and TIE_BUILD_SUBSTITUTION in admissible
                         else new)
            m = by_mutation[f"{row['wt_resname']}{row['position']}{build_sub}"]
            recommended.append({
                "hotspot": f"Gln{s}",
                "position_label": f"{row['wt_resname'].title()}{row['position']}"
                                  f"→({'|'.join(a.title() for a in admissible)})",
                "mutation": None if tie else key,
                "from": row["wt_resname"], "position": row["position"],
                "to": None if tie else new,
                "admissible_substitutions": admissible,
                "delta_patch_apolar_A2_by_substitution": per_sub,
                "delta_patch_apolar_A2": delta,
                "substitution_undecided_by_this_measurement": tie,
                "substitution_discriminator_if_tied": ("net charge: Asp delivers at most −1, Ser 0. "
                                                       "A founder decision, not a SASA one — the "
                                                       "area difference here is inside the noise "
                                                       "floor" if tie else None),
                "built_as_for_the_combined_variant": build_sub,
                "patch_ref_A2": m["per_hotspot"][f"Gln{s}"]["patch_ref_A2"],
                "patch_mutant_A2": m["per_hotspot"][f"Gln{s}"]["patch_mutant_A2"],
                "delta_surface_net_formal_charge": m["delta_surface_net_formal_charge"],
                "patch_surface_net_formal_charge_ref":
                    m["per_hotspot"][f"Gln{s}"]["patch_surface_net_formal_charge_ref"],
                "patch_surface_net_formal_charge_mutant":
                    m["per_hotspot"][f"Gln{s}"]["patch_surface_net_formal_charge_mutant"],
                "wt_exposed_apolar_A2": row["exposed_apolar_A2"],
                "burial": row["burial"], "dssp": row["dssp"],
                "d_cofactor_A": row["d_cofactor_A"],
                "d_electron_path_A": row["d_electron_path_A"],
                "plddt_ca": row["plddt_ca"],
                "excluded_by": row["excluded_by"],
            })
            label = recommended[-1]["position_label"]
            print(f"  {label:<20} Gln{s}: {m['per_hotspot'][f'Gln{s}']['patch_ref_A2']} → "
                  f"{m['per_hotspot'][f'Gln{s}']['patch_mutant_A2']} Å² "
                  f"({per_sub})" + ("  [substitution UNDECIDED — charge decides]" if tie else ""))
    for nc in no_candidate:
        print(f"  {nc['residue']}: NO admissible candidate "
              f"({nc['candidates_in_radius']} in radius, all excluded: "
              f"{', '.join(nc['exclusion_reasons_present'])})")

    # ── 6b. the set as a SEQUENCE, which is what actually gets frozen ──
    # Every delta above is a SINGLE mutation. Two recommendations inside one patch NEED NOT add —
    # they can remove overlapping area — and the founder freezes all of them at once, so the
    # singles answer a different question than the freeze asks. This builds the combined variant
    # and MEASURES the non-additivity instead of caveating it or assuming it.
    combined = None
    if len(recommended) > 1:
        banner("The recommended set as ONE sequence")
        muts = [f"{r['from']}-{r['position']}-{r['built_as_for_the_combined_variant']}"
                for r in recommended]
        tag = "combined_" + "_".join(m.replace("-", "") for m in muts)
        combo = surface_of(build_and_minimise(muts, tag, workdir), cofactor, workdir, tag)
        drift = ca_drift(ref_a, combo)
        max_drift = max(max_drift, drift)
        combined = {
            "mutations": [m.replace("-", "") for m in muts],
            "positions": [r["position_label"] for r in recommended],
            "pdbfixer_spec": muts,
            "tie_resolved_for_this_build": {
                str(r["position"]): r["built_as_for_the_combined_variant"] for r in recommended
                if r["substitution_undecided_by_this_measurement"]},
            "tie_resolution_is_a_build_choice": f"an undecided position is built as "
                                                f"{TIE_BUILD_SUBSTITUTION} because that commits no "
                                                f"charge; it is NOT a recommendation, and the "
                                                f"alternative's single-mutation number is in "
                                                f"`mutants`",
            "backbone_CA_drift_A": round(drift, 4),
            "surface_net_formal_charge_ref": ref_surface_charge,
            "surface_net_formal_charge_mutant": combo.surface_net_formal_charge(),
            "per_hotspot": {},
            "note": "the singles need NOT add — two substitutions in one patch remove overlapping "
                    "area. `non_additivity_A2` is the measured difference per hotspot; where it is "
                    "~0 they happened to add, and that is a result, not an assumption",
        }
        for s in PUBLISHED_HOTSPOTS:
            singles = [r["delta_patch_apolar_A2"] for r in recommended if r["hotspot"] == f"Gln{s}"]
            d_combined = combo.patch(s) - ref_patch[s]
            combined["per_hotspot"][f"Gln{s}"] = {
                "patch_ref_A2": round(ref_patch[s], 1),
                "patch_combined_A2": round(combo.patch(s), 1),
                "delta_patch_apolar_A2": round(d_combined, 1),
                "sum_of_singles_A2": round(sum(singles), 1),
                "non_additivity_A2": round(d_combined - sum(singles), 1),
                "n_recommended_here": len(singles),
            }
            print(f"  Gln{s}: {ref_patch[s]:.1f} → {combo.patch(s):.1f} Å² "
                  f"({d_combined:+.1f}; Σsingles {sum(singles):+.1f})")

    # ── 6c. what our own thresholds cost, measured ──
    # A candidate excluded by ONE filter, by a margin, whose mutant was nonetheless built: the
    # measured Δ is the price of that threshold. Reporting it is not a licence to move the
    # threshold — it is the only way the founder can see what the declared value is refusing.
    borderline = []
    for s in PUBLISHED_HOTSPOTS:
        for row in candidates[s]:
            if not row["in_primary_radius"]:
                continue
            hard = [e for e in row["excluded_by"] if not e.startswith("ss_regular_asp_only")]
            if len(hard) != 1:
                continue
            # A counterfactual must respect every OTHER declared filter, or it advertises a
            # substitution a second rule refuses anyway: Asp stays blocked in a regular element.
            ss_blocks_asp = row["dssp"] in SS_RISKY_FOR_ASP
            deltas = [(by_mutation[f"{row['wt_resname']}{row['position']}{n}"]
                       ["per_hotspot"][f"Gln{s}"]["delta_patch_apolar_A2"], n)
                      for n in SUBSTITUTIONS
                      if f"{row['wt_resname']}{row['position']}{n}" in by_mutation
                      and not (n == "ASP" and ss_blocks_asp)]
            if not deltas:
                continue
            best, best_sub = min(deltas)
            if best >= -noise_floor:
                continue        # the filter and the measurement agree: nothing was refused
            entry = {"hotspot": f"Gln{s}", "residue": row["residue"],
                     "excluded_by_only": hard[0],
                     "best_measured_delta_patch_apolar_A2": best,
                     "best_substitution": best_sub,
                     "best_substitution_scope": "the best substitution that every OTHER declared "
                                                "filter still allows, so this is what relaxing the "
                                                "named one would actually buy",
                     "patch_ref_A2": round(ref_patch[s], 1),
                     "fraction_of_patch_it_would_remove": round(abs(best) / ref_patch[s], 2),
                     "asp_also_blocked_by_ss": any(e.startswith("ss_regular_asp_only")
                                                   for e in row["excluded_by"]),
                     "burial": row["burial"], "dssp": row["dssp"],
                     "d_cofactor_A": row["d_cofactor_A"],
                     "d_electron_path_A": row["d_electron_path_A"]}
            if hard[0].startswith("buried"):
                entry["margin_over_threshold"] = round(row["burial"] - CAND_BURIAL_MAX, 3)
                entry["passes_at_sensitivity_value"] = [
                    v for v in CAND_BURIAL_MAX_SENSITIVITY if row["burial"] <= v]
            borderline.append(entry)
    borderline.sort(key=lambda e: e["best_measured_delta_patch_apolar_A2"])
    if borderline:
        banner("What the declared thresholds refuse — measured")
        for e in borderline:
            print(f"  {e['residue']:<8} {e['hotspot']}: {e['best_measured_delta_patch_apolar_A2']:+7.1f} Å² "
                  f"({e['fraction_of_patch_it_would_remove']:.0%} of the patch) refused by "
                  f"{e['excluded_by_only']}")

    # the same question for the apolar-area filter and the measurement: do they agree?
    filter_agreement = []
    for s in PUBLISHED_HOTSPOTS:
        for row in candidates[s]:
            if "buried" not in " ".join(row["excluded_by"]):
                continue
            for n in SUBSTITUTIONS:
                key = f"{row['wt_resname']}{row['position']}{n}"
                if key in by_mutation:
                    filter_agreement.append({
                        "residue": row["residue"], "to": n, "burial": row["burial"],
                        "delta_patch_apolar_A2":
                            by_mutation[key]["per_hotspot"][f"Gln{s}"]["delta_patch_apolar_A2"],
                        "within_noise_floor":
                            abs(by_mutation[key]["per_hotspot"][f"Gln{s}"]
                                ["delta_patch_apolar_A2"]) <= noise_floor})

    # relaxed-keepout counterfactual: what the FAD shell alone is costing
    relaxed = []
    for s in PUBLISHED_HOTSPOTS:
        for row in candidates[s]:
            if not row["in_primary_radius"]:
                continue
            hard = [e for e in row["excluded_by"] if not e.startswith("ss_regular_asp_only")]
            only_fad = hard and all(e.startswith("fad_pocket") for e in hard)
            if only_fad and row["d_cofactor_A"] >= FAD_POCKET_EXCL_SENSITIVITY_A:
                relaxed.append({"hotspot": f"Gln{s}", "residue": row["residue"],
                                "d_cofactor_A": row["d_cofactor_A"],
                                "d_electron_path_A": row["d_electron_path_A"]})

    # candidate-radius sensitivity: does the admissible set move with CAND_RADIUS_A?
    radius_sensitivity = []
    for rad in (*CAND_RADIUS_SENSITIVITY_A, CAND_RADIUS_A):
        clear_positions = []
        for s in PUBLISHED_HOTSPOTS:
            for row in candidates[s]:
                if row["distance_to_hotspot_A"] > rad:
                    continue
                hard = [e for e in row["excluded_by"] if not e.startswith("ss_regular_asp_only")]
                if not hard:
                    clear_positions.append(row["residue"])
        radius_sensitivity.append({"candidate_radius_A": rad,
                                   "positions_clear_of_hard_keepouts": sorted(set(clear_positions))})

    # ── 7. verdict, built from the data ──
    n_rec = len(recommended)
    rec_names = ", ".join(r["position_label"] for r in recommended) or "none"
    undecided = [r["position_label"] for r in recommended
                 if r["substitution_undecided_by_this_measurement"]]
    blocked = ", ".join(nc["residue"] for nc in no_candidate) or "none"
    gap = (round(site_scores[ranked[3]] - site_scores[ranked[4]], 1)
           if len(ranked) > 4 else float("nan"))
    verdict = (
        f"1. The L1 §2 four-site claim now has an instrument, and it holds only inside a contact "
        f"shell: at R = {PATCH_RADIUS_A} Å with aromatics in the residue set the proxy re-selects "
        f"{{Gln71, Gln200, Gln258, Gln405}} exactly, the 4th-to-5th gap is {gap} Å², and "
        f"{sum(1 for s in DEGLYC_SITES if site_scores[s] == 0.0)} of the 11 sites score exactly zero. "
        f"It re-selects at "
        f"{[r['radius_A'] for r in sensitivity_radius if r['reselects_published_set']]} Å and at no "
        f"other swept radius, and never without the aromatics. "
        f"2. Read against the protein's own surface the four are not its worst patches: percentiles "
        + " · ".join(f"Gln{h['site']} {h['surface_percentile_protein_wide']}" for h in hotspots)
        + f", against a protein-wide maximum of {context['max_A2']} Å² at "
        f"{context['largest_patches_protein_wide'][0]['residue']} — "
        f"{round(context['largest_patches_protein_wide'][0]['patch_A2'] / site_scores[ranked[0]], 1)}× "
        f"the largest deglycosylation-site patch. 'Hotspot' is a ranking among the 11 sites, not an "
        f"absolute aggregation risk. "
        f"3. Compensation is admissible at {n_rec} position(s): {rec_names}"
        + (f" — and at {', '.join(undecided)} the Asp/Ser choice is a TIE inside the noise floor, so "
           f"this script does not make it: the difference there is a charge, and the ranked winner "
           f"was measured flipping between identical runs." if undecided else "") + " "
        f"4. It is NOT admissible at {blocked}"
        + (f" — Gln258 because its entire apolar neighbourhood lies inside the FAD pocket and the "
           f"electron-exit shell (the site itself sits "
           f"{next(h['d_electron_path_A'] for h in hotspots if h['site'] == 258)} Å from the path and "
           f"{next(h['d_cofactor_A'] for h in hotspots if h['site'] == 258)} Å from FAD), so buying "
           f"aggregation margin there spends the MET architecture; and Gln200 because it is the most "
           f"buried of the 11 sites (burial "
           f"{next(h['site_burial'] for h in hotspots if h['site'] == 200)}) and every neighbour is "
           f"buried too — a surface-polar compensation there has no surface to act on."
           if len(no_candidate) == 2 else ".")
        + (" 5. Priced as ONE sequence, which is what a freeze is: "
           + " and ".join(
               f"Gln{s} {combined['per_hotspot'][f'Gln{s}']['patch_ref_A2']} → "
               f"{combined['per_hotspot'][f'Gln{s}']['patch_combined_A2']} Å²"
               for s in PUBLISHED_HOTSPOTS
               if combined['per_hotspot'][f'Gln{s}']['n_recommended_here'])
           + f". Largest non-additivity against the sum of singles: "
             f"{max(abs(v['non_additivity_A2']) for v in combined['per_hotspot'].values())} Å² — "
             f"measured on the built variant, not assumed either way."
           if combined else "")
        + (f" 6. {len(borderline)} further position(s) are refused by exactly one of OUR declared "
           f"filters while measurably reducing a patch — the refusal is the threshold's, not the "
           f"physics': "
           + "; ".join(f"{e['residue']}→{e['best_substitution'].title()} would remove "
                       f"{e['fraction_of_patch_it_would_remove']:.0%} of {e['hotspot']}'s patch "
                       f"({e['best_measured_delta_patch_apolar_A2']:+.1f} Å²), refused by "
                       f"{e['excluded_by_only']}" for e in borderline)
           + ". The values stay where they were declared; moving one is a founder call."
           if borderline else "")
        + " 7. Every number is an AF3 single-model surface descriptor, and the deciding quantity — "
        "whether this enzyme aggregates at expression concentration — is not computed anywhere in "
        "this script."
    )

    out = {
        "script": Path(__file__).name,
        "tracker": "00_07 HW.5.IS — CHEM.11",
        "canon_home": "docs/protocols/ebfc/in_silico/L1_protein_architecture.md §2",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runtime_s": round(time.time() - t_start, 1),
        "inputs": {
            "structure": str(AF3_PDB.relative_to(REPO_ROOT)),
            "plddt_source": str(AF3_CIF.relative_to(REPO_ROOT)),
            "electron_path_source": str(TUNNELING_JSON.relative_to(REPO_ROOT)),
            "structure_note": "AF3 model_0 of the AGLYCOSYLATED N→Q mutant — the reference state "
                              "here is that mutant, NOT the glycosylated wild type",
        },
        "provenance": {
            "proxy_definition_pre_existed_in_tree": False,
            "published_claim": "L1 §2: an in-house hydrophobic-SASA proxy flags 4 "
                               "aggregation-prone sites (Gln71, Gln200, Gln258, Gln405)",
            "published_claim_commit": "2e607abc (2026-06-06) — wrote the conclusion into canon "
                                      "and committed no script and no cache",
            "reselects_published_set": reselects,
            "reselects_only_within": [r["radius_A"] for r in sensitivity_radius
                                      if r["reselects_published_set"]],
        },
        "declared_parameters": {
            "aggregation_prone_set": sorted(AGGREGATION_PRONE),
            "aggregation_prone_set_ground": "Kyte & Doolittle 1982 hydropathy > 0 "
                                            "(doi:10.1016/0022-2836(82)90515-0, Crossref-verified: "
                                            "J. Mol. Biol. 157(1):105-132) ∪ {TRP, TYR}; the "
                                            "aromatic addition is OURS, not theirs",
            "patch_radius_A": PATCH_RADIUS_A,
            "patch_weight": "solvent-exposed apolar (side-chain C/S) SASA of each member; a buried "
                            "member contributes ~0 by construction, so members carry no separate "
                            "exposure filter",
            "candidate_radius_A": CAND_RADIUS_A,
            "candidate_min_exposed_apolar_A2": CAND_APOLAR_MIN_A2,
            "candidate_max_burial": CAND_BURIAL_MAX,
            "burial_definition": "1 − (side-chain SASA in the protein / side-chain SASA of the same "
                                 "side chain, same conformation, sliced out) — computed here, so no "
                                 "external max-ASA table enters",
            "fad_pocket_exclusion_A": FAD_POCKET_EXCL_A,
            "electron_path_exclusion_A": EPATH_EXCL_A,
            "electron_path_residues": [f"{af3.name[s]}{s}" for s in epath],
            "ss_risky_for_asp": sorted(SS_RISKY_FOR_ASP),
            "ss_rule_scope": "blocks ASP only — Ser adds no charge and no β-branch",
            "sasa": {"probe_radius_nm": PROBE_RADIUS_NM, "n_sphere_points": N_SPHERE_POINTS,
                     "engine": "mdtraj.shrake_rupley", "atoms": "heavy only (hydrogens stripped "
                     "after minimisation so the reference and the mutants are measured alike)"},
            "minimisation": {"forcefield": list(FF_XMLS), "iterations": MIN_ITERATIONS,
                             "nonbonded": f"CutoffNonPeriodic {NONBONDED_CUTOFF_NM} nm",
                             "constraints": None,
                             "frozen": "all backbone N/CA/C/O set to mass 0 — side chains only",
                             "protonation_pH": PH, "temperature_K": TEMPERATURE_K,
                             "cofactor": "removed for the minimisation (no ff14SB template), "
                                         "original coordinates re-attached for the SASA measurement; "
                                         "admissible only because the backbone is frozen"},
            "formal_charge_convention": FORMAL_CHARGE,
            "surface_charge_sidechain_sasa_min_A2": SURFACE_CHARGE_SASA_MIN_A2,
            "surface_charge_scope": "an ionisable residue counts toward the surface charge only "
                                    "when its side-chain SASA clears that floor; the whole-chain "
                                    "figure is reported beside it under its own name",
            "formal_charge_caveat": f"protonation is assigned by OpenMM's rule table at pH {PH}, "
                                    "not by a pKa model, so −1 per introduced carboxylate is an "
                                    "UPPER BOUND on delivered charge; the sap set-point assigns "
                                    "the same states (header of `PH` in lib/constants.py)",
            "threshold_ownership": "every threshold above is OURS except the Kyte-Doolittle set; "
                                   "none is an industry standard and none is quoted as one",
        },
        "plddt": {
            "convention": "CA-atom B_iso from the AF3 CIF — the statistic L1 §4 already publishes "
                          "(Tyr90 CA = 98.71 vs residue mean 98.23)",
            "canonical_pdb_is_not_a_source": "OpenMM wrote it and zeroed the B-factor column",
            "chain_mean_of_residue_means": round(statistics.mean(plddt_mean.values()), 2),
            "lowest_residue": min(plddt_mean, key=plddt_mean.get),
            "lowest_residue_plddt_mean": round(min(plddt_mean.values()), 2),
        },
        "proxy_scores_all_11_sites_A2": {f"Gln{s}": round(site_scores[s], 1) for s in ranked},
        "hotspots": hotspots,
        "whole_surface_context": context,
        "proxy_sensitivity": {"radius": sensitivity_radius, "residue_set": sensitivity_set},
        "candidates": {f"Gln{s}": rows for s, rows in candidates.items()},
        "candidate_radius_sensitivity": radius_sensitivity,
        "mutants": mutants,
        "recommendation_rule": rule,
        "recommended": recommended,
        "recommended_set_as_one_sequence": combined,
        "threshold_cost_measured": {
            "what_this_is": "candidates refused by EXACTLY ONE declared filter whose mutant was "
                            "built anyway — the measured Δ is what that threshold is refusing. "
                            "Reported so the value is visible; the threshold is NOT moved to suit "
                            "the answer",
            "entries": borderline,
        },
        "burial_filter_vs_measurement": {
            "what_this_is": "every burial-excluded candidate against its measured Δ. Where Δ is "
                            "inside the noise floor the filter refused nothing; where it is not, "
                            "the filter is making the decision and its value is load-bearing",
            "entries": filter_agreement,
        },
        "recommended_per_hotspot": per_hotspot_counts,
        "no_admissible_candidate": no_candidate,
        "relaxed_fad_shell_would_admit": {
            "relaxed_to_A": FAD_POCKET_EXCL_SENSITIVITY_A,
            "positions": relaxed,
            "note": "these fail ONLY the FAD-pocket shell at its declared 12 Å. They are reported "
                    "so the cost of that threshold is visible; they are NOT recommended, because "
                    "each still sits on the electron-exit face that L1 §5 makes load-bearing",
        },
        "controls": {
            "patch_sasa_noise_floor_A2": noise_floor,
            "patch_sasa_spread_over_replicates_A2": noise,
            "n_reference_replicates": N_REF_REPLICATES,
            "patch_per_replicate_A2": replicate_patches,
            "reference_for_every_delta": "replicate 0",
            "noise_source": "pdbfixer addMissingHydrogens is non-deterministic; the minimisation "
                            "path inherits it. Any |delta| below this floor is not a finding",
            "why_not_two_replicates": "two successive two-run estimates of this floor gave 2.52 "
                                      "and 0.25 Å² — a single pairwise difference is one sample of "
                                      "the spread and under-estimates it, so the floor is taken as "
                                      "the widest disagreement over all replicates",
            "backbone_frozen_max_CA_drift_A": round(max_drift, 4),
            "backbone_frozen_expectation": "0.0 — a non-zero value invalidates re-attaching the "
                                           "cofactor coordinates, and this control would catch it",
            "plddt_reproduces_canon_Tyr90": round(plddt_ca[90], 2),
            "plddt_canon_value_L1_s4": 98.71,
            "reference_minimisation_moves_the_surface_A2": {
                f"Gln{s}": round(ref_patch[s] - site_scores[s], 1) for s in PUBLISHED_HOTSPOTS},
            "reference_minimisation_note": "the minimised reference differs from the raw AF3 model "
                                           "by about the noise floor, so the proxy is reading the "
                                           "AF3 geometry and not the force field",
            "what_these_controls_cannot_catch": "none of them tests the PHYSICS: a proxy that is "
                                                "reproducible, frozen-frame and low-noise can still "
                                                "be the wrong descriptor for aggregation",
        },
        "verdict": verdict,
        "caveats": [
            "A SASA proxy is NOT an aggregation prediction. Exposed apolar area is a static "
            "single-molecule surface descriptor; aggregation is a multi-molecule kinetic process "
            "that depends on concentration, pH, ionic strength, temperature and shear. No rate, "
            "solubility or critical concentration is computed here.",
            "Aggrescan3D was NOT run. It is an external web server and the first half of the L1 §2 "
            "recipe stays OPEN; nothing in this cache substitutes for it.",
            "Sequence conservation is NOT an input to this score. It is measured separately "
            "(script 70) and read beside it, never merged — for Ile401 that reading is what lifted "
            "the hold (⚖️ founder 2026-09-18).",
            "No MD of any mutant and no ΔΔG of folding. A few hundred steps of side-chain "
            "minimisation in implicit solvent cannot tell whether a substitution destabilises the "
            "fold; the burial and DSSP columns are geometric PROXIES for that risk, not a verdict.",
            "One AF3 model, one conformation. Side-chain SASA on a predicted structure carries the "
            "prediction's error; the pLDDT columns bound the backbone confidence only.",
            "No catalytic-residue list exists in our canon for GcGDH, so catalysis is guarded only "
            "by the FAD-pocket shell — a geometric stand-in whose radius is ours.",
            "The reference state is the AGLYCOSYLATED N→Q mutant, not the glycosylated wild type. "
            "Nothing here measures what the removed glycans were actually shielding; the "
            "'newly exposed' framing in L1 §2 is not tested by this script.",
            "Only apolar→{Asp, Ser} substitutions are scored. A pure charge addition at an already "
            "polar position is a different lever and is not scored.",
            "Every per-mutation Δ is a SINGLE substitution, and a freeze is a SEQUENCE. Two "
            "substitutions in one patch can remove overlapping area, so "
            "`recommended_set_as_one_sequence` carries the set built as one variant and "
            "`non_additivity_A2` reports the measured difference rather than assuming either way.",
            f"The 4th-to-5th ranking gap is {gap} Å² against a measured noise floor of "
            f"{noise_floor} Å². The gap survives the noise, but it is not a wide margin, and the "
            "membership of the four is radius-dependent (see proxy_sensitivity).",
        ],
        "founder_decisions_taken": [
            "The frozen gene carries Leu80→Asp and Ala70→Ser (⚖️ founder 2026-09-17) and "
            "Ile401→Ser (⚖️ founder 2026-09-18, after script 70 measured the position) — home L1 §2. "
            "This script recommends; the choice was the founder's.",
            f"The Leu80 Asp/Ser tie inside the {noise_floor} Å² noise floor was decided by CHARGE: "
            "Asp. This script still BUILDS the tie as Ser (`substitution_undecided_by_this_measurement`), "
            "so `recommended_set_as_one_sequence` is not the ratified gene and the Asp build is unmeasured.",
            "Gln258 and Gln200 stay un-compensated — the ratified gene carries no lever for either; "
            "Gln200's refusal is our BURIAL threshold's, not the measurement's: see "
            "`threshold_cost_measured`.",
        ],
        "founder_decision_open": [
            f"Whether the {FAD_POCKET_EXCL_A} Å FAD shell is the right conservatism. Relaxing it to "
            f"{FAD_POCKET_EXCL_SENSITIVITY_A} Å would admit "
            f"{[p['residue'] for p in relaxed] or 'nothing'} — each still on the electron-exit face. "
            "The ratified gene was chosen under the declared value; it was never re-judged.",
            f"Whether the burial ceiling stays at {CAND_BURIAL_MAX}. Its sensitivity values are "
            f"{list(CAND_BURIAL_MAX_SENSITIVITY)} and `threshold_cost_measured` prices the "
            "difference in Å² actually removed. Same standing as the shell: declared, never re-judged.",
        ],
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    banner("Verdict")
    print(f"  {verdict}")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)} ({out['runtime_s']:.0f} s)")
    print(f"  intermediate PDBs in {workdir.relative_to(REPO_ROOT)} (gitignored scratch)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
