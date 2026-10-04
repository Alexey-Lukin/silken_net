#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
CHEM.11 — the Aggrescan3D half of the L1 §2 recipe, read against our own proxy (script 69).

L1 §2 has carried a two-part recipe since 2026-06-06: an in-house hydrophobic-SASA proxy that
flags four aggregation-prone deglycosylation sites (script 69), and an **Aggrescan3D run** on the
same structure. The second half stayed open for months — the hosted servers need an account —
and it was the remaining gate on the dgrFAD-GDH gene freeze. The standalone release was run on
2026-10-04 (posture `/NOTICE`, permission and recipe `L1 §2`); this script reads its committed
output and asks the ONE question the recipe asks: does an instrument we did not write put its
flags where our proxy put its compensations?

⚠️ **A3D output is third-party, non-commercially licensed, and EXCLUDED from this repository's
CC-BY-SA-4.0 grant** (`/NOTICE`, block «Aggrescan3D»). This script's own output is ours.

WHAT IS COMPUTED
  1. the A3D score of every one of the ELEVEN deglycosylation sites, and of the three positions
     the ratified gene compensates (Ala70 · Leu80 · Ile401);
  2. for each site, the best **measured positively-scoring** neighbour inside a CA-CA shell, over
     a radius sweep — because the agreement, if any, lives at the NEIGHBOUR, not at the Gln;
  3. A3D's own ranking of the mature chain, so «our two positions are flagged» can be read as a
     rank and not as an adjective;
  4. the signal-peptide block (residues 1-16) separately from the mature chain, with its share of
     the positive tail — the stretch is cleaved on secretion, so it must not enter a ranking;
  5. the exposure-gate census: how many residues A3D scores as a hard 0.0 and how many of those
     are hydrophobic by A3D's own matrix.

🔴 **THE TRAP THIS SCRIPT EXISTS TO NAME.** A3D's per-residue score is
`agg_sup_i + Σ_j≠i agg_sup_j · 1.2915 · exp(−2.56·d_ij/D)` over CA-CA `d_ij < D` (D = 10 Å here),
where `agg_sup = matrix[resn] · 0.0599 · exp(0.0521 · RSA)` — **and `agg_sup` is forced to 0 when
RSA < 10 %, after which the whole final score is forced to 0.0 as well.** So `0.000` in `A3D.csv`
means «this residue is buried, the instrument does not speak about it», and it is written in the
same column, in the same format, as a genuine measured zero. In this run **253 of 600 residues
(42 %) carry that sentinel, 161 of them hydrophobic by A3D's own matrix** — i.e. a buried
hydrophobic patch and «nothing here» print the identical number. Any max / min / ranking that
admits those rows is reading a sentinel as a measurement (it already happened once, in the first
reading of this run on 2026-10-04: the «max in the 7 Å shell» of Gln258 and Gln200 came out as
`0.000` carried by buried residues, which hid a real — if marginal — positive neighbour at
Gln258). Every statistic below therefore carries `measured_only=True` and the sentinel is
counted, never aggregated. Class: `project_mission_criterion` §ФОЛБЕК (a sentinel read as a
measurement) and `feedback_silent_default`.

WHAT IS **NOT** COMPUTED — absent, not merely undiscussed
  · **The two instruments are NOT independent in family, only in authorship and inputs.** Both are
    exposure-weighted neighbourhood hydrophobicity. They differ in every detail — CA-CA vs
    side-chain centroid, 10 Å exponential weighting vs a flat 7 Å shell, A3D's own signed matrix
    vs Kyte-Doolittle>0 plus aromatics, freesasa RSA vs mdtraj Shrake-Rupley SASA — and agreement
    between them is therefore worth less than agreement between two different KINDS of method.
  · **A3D says little about a Gln by construction.** Gln's matrix value is −1.1394, so an exposed
    Gln scores negative unless ringed by exposed hydrophobics. «A3D does not flag site X» is
    consequently a weak absence claim for every one of the eleven; the informative axis is the
    neighbourhood.
  · **The cofactor is absent from the A3D model.** A3D read only `ATOM` records, so the FAD
    (53 `HETATM`) was silently dropped: exposure near the flavin pocket is over-stated. Gln405 is
    28.8 Å from the cofactor (unaffected), Gln71 13.2 Å (script 69's cache, `d_cofactor_A`).
  · **The structure is the UNCOMPENSATED mutant.** No A3D run exists on the compensated sequence;
    that needs an AF3 re-prediction, which `L1 §2` deliberately has not done.
  · **No aggregation prediction, of either instrument.** Both are static single-molecule surface
    descriptors: no rate, no solubility, no critical concentration. Nothing here says the
    compensated protein expresses, and nothing here says an un-compensated site aggregates.
  · No ΔΔG of folding, no dynamic (CABS-flex) A3D mode, no automatic mutagenic optimisation —
    `-d` and `-am` were deliberately not used (recipe `L1 §2`).

Runtime < 1 s (pure Python; numpy not required).
Inputs:  tools/in_silico/data/chem11_a3d/        (committed A3D output + its provenance README)
         docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb   (CA coordinates — A3D's own geometry)
         tools/in_silico/cache/chemistry/chem11_aggregation_compensation.json   (script 69)
Output:  tools/in_silico/cache/chemistry/chem11_a3d_crosscheck.json
"""
from __future__ import annotations

import csv
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = (
    "Aggrescan3D cross-check of the four deglycosylation hotspots of the aglycosylated FAD-GDH."
)  # its row in the paper SI (72): English, no repo jargon

DATA = REPO_ROOT / "tools/in_silico/data/chem11_a3d"
A3D_CSV = DATA / "A3D.csv"
PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
PROXY_CACHE = CACHE_DIR / "chemistry" / "chem11_aggregation_compensation.json"
OUT_JSON = CACHE_DIR / "chemistry" / "chem11_a3d_crosscheck.json"

# ── the positions, and why each is here ──
# The eleven N→Q deglycosylation sites of the ordered gene (L1 §2 / Spec A of ebfc_chem_rfq).
SITES = [71, 100, 192, 200, 249, 258, 271, 355, 380, 405, 463]
# The three compensations the ratified gene carries (⚖️ founder 2026-09-17 / 2026-09-18).
COMPENSATIONS = {70: "A70S", 80: "L80D", 401: "I401S"}
# UniProt G8E4B5 Signal 1-16 / Chain 17-600, evidence ECO:0000256 — an AUTOMATIC annotation
# (TrEMBL, annotationScore 2.0), not a curated or experimental one. Read 2026-10-04 from
# rest.uniprot.org. It is why the mature-chain statistics below start at 17.
SIGNAL_PEPTIDE = (1, 16)
MATURE_FIRST = 17

# A3D's own constants, read from aggrescan/aggrescan_3d.py of release 1.0.2 (NOT from memory):
A3D_MIN_SURF_RSA_PCT = 10        # `min_surf` — below this RSA, agg_sup := 0 and the score := 0.0
A3D_MAX_DIST_A = 10              # our `-D 10`, the CA-CA cutoff of the neighbourhood sum
A3D_MATRIX = {                   # data/matrices/aggrescan.mat, one-letter code → propensity
    "I": 1.9136, "F": 1.8456, "V": 1.6856, "L": 1.4716, "Y": 1.2506, "W": 1.1286,
    "M": 1.0016, "C": 0.6956, "A": 0.0556, "T": -0.0674, "S": -0.2024, "P": -0.2424,
    "G": -0.4434, "K": -1.6164, "H": -0.9414, "Q": -1.1394, "R": -1.7534, "N": -1.2104,
    "E": -1.7304, "D": -1.7014,
}
HYDROPHOBIC = sorted(r for r, v in A3D_MATRIX.items() if v > 0)
SHELL_RADII_A = [6.0, 6.5, 7.0, 7.5, 8.0, 10.0]


def read_a3d(path: Path) -> tuple[dict[int, float], dict[int, str]]:
    """A3D.csv → {resi: score}, {resi: one-letter}. Single chain A by construction here."""
    score: dict[int, float] = {}
    name: dict[int, str] = {}
    with path.open() as fh:
        for row in csv.DictReader(fh):
            i = int(row["residue"])
            score[i] = float(row["score"])
            name[i] = row["residue_name"]
    return score, name


def read_ca(path: Path) -> dict[int, tuple[float, float, float]]:
    """CA coordinates — A3D measures residue-residue distance between CA atoms, so we do too."""
    ca: dict[int, tuple[float, float, float]] = {}
    for line in path.read_text().splitlines():
        if line.startswith("ATOM") and line[12:16].strip() == "CA":
            ca[int(line[22:26])] = (float(line[30:38]), float(line[38:46]), float(line[46:54]))
    return ca


def is_sentinel(value: float) -> bool:
    """A hard 0.0 from A3D means RSA < min_surf — 'buried, not spoken about', not 'measured 0'."""
    return value == 0.0


def shell(ca: dict, centre: int, radius: float) -> list[tuple[int, float]]:
    """[(resi, CA-CA distance)] within `radius`, self excluded — A3D's own exclusion."""
    out = []
    for j, xyz in ca.items():
        if j == centre:
            continue
        d = math.dist(ca[centre], xyz)
        if d <= radius:
            out.append((j, d))
    return sorted(out, key=lambda t: t[1])


def best_measured_positive(score, name, ca, centre: int, radius: float) -> dict | None:
    """Highest-scoring neighbour with a MEASURED positive score. Sentinels never enter."""
    cands = [
        (j, score[j], d)
        for j, d in shell(ca, centre, radius)
        if j in score and not is_sentinel(score[j]) and score[j] > 0.0
    ]
    if not cands:
        return None
    j, s, d = max(cands, key=lambda t: t[1])
    return {"residue": f"{name[j]}{j}", "position": j, "a3d_score": round(s, 4),
            "ca_ca_distance_A": round(d, 2)}


def main() -> int:
    t0 = time.time()
    banner("CHEM.11 A3D cross-check — reading the committed A3D output")
    score, name = read_a3d(A3D_CSV)
    ca = read_ca(PDB)
    proxy = json.loads(PROXY_CACHE.read_text())
    proxy_scores = proxy["proxy_scores_all_11_sites_A2"]

    sentinels = sorted(i for i, v in score.items() if is_sentinel(v))
    measured = sorted(i for i, v in score.items() if not is_sentinel(v))
    sentinel_hydrophobic = [i for i in sentinels if name[i] in HYDROPHOBIC]

    banner("Exposure-gate census — the sentinel is counted, never aggregated")
    print(f"  residues {len(score)} | sentinel (RSA < {A3D_MIN_SURF_RSA_PCT} %) {len(sentinels)} "
          f"({100.0 * len(sentinels) / len(score):.0f} %) | measured {len(measured)}")
    print(f"  of the sentinels, hydrophobic by A3D's own matrix: {len(sentinel_hydrophobic)}")

    # ── the eleven sites: own score, and the neighbourhood over a radius sweep ──
    banner("The eleven deglycosylation sites — the agreement, if any, is at the NEIGHBOUR")
    sites_out = {}
    for s in SITES:
        per_radius = {
            f"{r:g}": best_measured_positive(score, name, ca, s, r) for r in SHELL_RADII_A
        }
        at7_n = per_radius["7"]
        sites_out[f"Gln{s}"] = {
            "position": s,
            "a3d_score_own": round(score[s], 4),
            "a3d_score_own_is_sentinel": is_sentinel(score[s]),
            "proxy_patch_apolar_A2": proxy_scores[f"Gln{s}"],
            # DERIVED, not asserted: is the residue A3D flags beside this site one of the three
            # the ratified gene actually substitutes? That is the whole question of the recipe.
            "flagged_neighbour_is_a_ratified_compensation": (
                at7_n is not None and at7_n["position"] in COMPENSATIONS
            ),
            "ratified_compensations_within_7A": sorted(
                COMPENSATIONS[j] for j, _ in shell(ca, s, 7.0) if j in COMPENSATIONS
            ),
            "best_measured_positive_neighbour_by_radius_A": per_radius,
        }
        at7 = per_radius["7"]
        shown = (f"{at7['residue']} +{at7['a3d_score']:.3f} @{at7['ca_ca_distance_A']:.1f} Å"
                 if at7 else "NONE — no positively-scoring neighbour")
        print(f"  Gln{s:<4} own {score[s]:+7.3f} | 7 Å: {shown:<34} | proxy {proxy_scores[f'Gln{s}']:>6.1f} Å²")

    # ── the three compensated positions, in A3D's own ranking of the mature chain ──
    mature_positive = sorted(
        (i for i in measured if i >= MATURE_FIRST and score[i] > 0), key=lambda i: -score[i]
    )
    banner("A3D's own ranking of the mature chain (17-600), positive scores only")
    for i in mature_positive[:8]:
        tag = f"  ← {COMPENSATIONS[i]}" if i in COMPENSATIONS else ""
        print(f"  #{mature_positive.index(i) + 1:<2} {name[i]}{i:<4} +{score[i]:.3f}{tag}")
    # The top of that ranking is NOT ours, and saying so is half the honesty of this cross-check:
    # the recipe scopes the eleven deglycosylation sites, not the protein's globally worst patch.
    # Script 69 said the same thing on its own instrument (max 282.9 Å² at Thr12, 2.0× Gln71).
    top_mature = mature_positive[0]
    top_nearest_site = min(SITES, key=lambda s: math.dist(ca[top_mature], ca[s]))
    worst_not_ours = {
        "residue": f"{name[top_mature]}{top_mature}",
        "a3d_score": round(score[top_mature], 4),
        "is_a_ratified_compensation": top_mature in COMPENSATIONS,
        "nearest_deglycosylation_site": f"Gln{top_nearest_site}",
        "ca_ca_distance_to_it_A": round(math.dist(ca[top_mature], ca[top_nearest_site]), 1),
        "reading": "A3D's highest-scoring mature residue is not one the gene touches and is not "
                   "beside any of the eleven sites — both instruments agree that the "
                   "deglycosylation sites are NOT this protein's worst patches; they are the worst "
                   "among the eleven, which is what the recipe asked about",
    }
    print(f"  ⚠️ top of this ranking is NOT ours: {worst_not_ours['residue']} "
          f"+{worst_not_ours['a3d_score']}, nearest site "
          f"{worst_not_ours['nearest_deglycosylation_site']} at "
          f"{worst_not_ours['ca_ca_distance_to_it_A']} Å")

    comps_out = {}
    for p, label in sorted(COMPENSATIONS.items()):
        rank = mature_positive.index(p) + 1 if p in mature_positive else None
        comps_out[label] = {
            "position": p,
            "wild_type_residue": name[p],
            "a3d_score": round(score[p], 4),
            "a3d_score_is_sentinel": is_sentinel(score[p]),
            "rank_among_mature_positive": rank,
            "n_mature_positive": len(mature_positive),
        }

    # ── the signal peptide: hottest stretch in the protein, and it is cleaved ──
    sig = [i for i in score if SIGNAL_PEPTIDE[0] <= i <= SIGNAL_PEPTIDE[1]]
    sig_pos = [i for i in sig if not is_sentinel(score[i]) and score[i] > 0]
    all_pos = [i for i in measured if score[i] > 0]
    banner("Signal peptide 1-16 — reported apart, because secretion removes it")
    print(f"  positive residues in 1-16: {len(sig_pos)} of {len(sig)} | "
          f"share of the whole positive tail: {len(sig_pos)}/{len(all_pos)}")

    totals = {
        "n_residues": len(score),
        "sum_of_scores": round(sum(score.values()), 4),
        "mean_score": round(sum(score.values()) / len(score), 4),
        "min_score": round(min(score.values()), 4),
        "max_score": round(max(score.values()), 4),
        "n_positive_measured": len(all_pos),
        "note": "sum and mean include the sentinel rows as literal 0.0, which is what A3D itself "
                "reports; they are therefore totals of A3D's OUTPUT, not of the protein's surface",
    }

    flagged_sites = [k for k, v in sites_out.items()
                     if v["best_measured_positive_neighbour_by_radius_A"]["7"]]
    sites_matched = [k for k in flagged_sites
                     if sites_out[k]["flagged_neighbour_is_a_ratified_compensation"]]
    sites_flagged_uncompensated = [k for k in flagged_sites if k not in sites_matched]
    compensated_flagged = [
        lbl for lbl, v in comps_out.items() if v["rank_among_mature_positive"] is not None
    ]
    g71_score = sites_out["Gln71"]["best_measured_positive_neighbour_by_radius_A"]["7"]["a3d_score"]
    g405_score = sites_out["Gln405"]["best_measured_positive_neighbour_by_radius_A"]["7"]["a3d_score"]

    out = {
        "script": Path(__file__).name,
        "tracker": "00_07 HW.5.IS — CHEM.11",
        "canon_home": "docs/protocols/ebfc/in_silico/L1_protein_architecture.md §2",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runtime_s": round(time.time() - t0, 2),
        "inputs": {
            "a3d_output": str(A3D_CSV.relative_to(REPO_ROOT)),
            "a3d_provenance": str((DATA / "README.md").relative_to(REPO_ROOT)),
            "structure": str(PDB.relative_to(REPO_ROOT)),
            "proxy_cache": str(PROXY_CACHE.relative_to(REPO_ROOT)),
            "structure_note": "the AGLYCOSYLATED 11 N→Q mutant WITHOUT the three compensations; "
                              "A3D read only ATOM records, so the FAD cofactor was dropped",
        },
        "licence": {
            "a3d_output_excluded_from_cc_by_sa": True,
            "home": "/NOTICE, block «Aggrescan3D (standalone release)»",
        },
        "a3d_scoring_as_read_from_source": {
            "release": "1.0.2 (sdist, sha256 in the data README)",
            "formula": "score_i = agg_sup_i + Σ_{j≠i, d_ij<D} agg_sup_j · 1.2915 · "
                       "exp(−2.56·d_ij/D);  agg_sup = matrix[resn] · 0.0599 · exp(0.0521·RSA)",
            "distance": "CA-CA",
            "max_dist_A": A3D_MAX_DIST_A,
            "exposure_gate_rsa_pct": A3D_MIN_SURF_RSA_PCT,
            "exposure_gate_effect": "agg_sup := 0 below the gate, and the final score is then "
                                    "forced to exactly 0.0 — a SENTINEL, not a measurement",
            "matrix_is_signed": True,
            "gln_matrix_value": A3D_MATRIX["Q"],
            "why_that_matters": "an exposed Gln scores negative unless ringed by exposed "
                                "hydrophobics, so 'A3D does not flag site X' is a weak absence "
                                "claim for any of the eleven",
        },
        "exposure_gate_census": {
            "n_sentinel": len(sentinels),
            "n_measured": len(measured),
            "sentinel_fraction": round(len(sentinels) / len(score), 3),
            "n_sentinel_hydrophobic_by_a3d_matrix": len(sentinel_hydrophobic),
            "hydrophobic_set": HYDROPHOBIC,
            "why_counted": "a buried hydrophobic patch and 'nothing here' print the identical "
                           "0.000 in the same column of A3D.csv",
        },
        "totals_of_a3d_output": totals,
        "sites": sites_out,
        "compensated_positions": comps_out,
        "highest_scoring_mature_residue": worst_not_ours,
        "signal_peptide": {
            "range": list(SIGNAL_PEPTIDE),
            "annotation": "UniProt G8E4B5 Signal 1-16 / Chain 17-600, ECO:0000256 — AUTOMATIC "
                          "annotation (TrEMBL, annotationScore 2.0), read 2026-10-04",
            "n_positive": len(sig_pos),
            "n_positive_whole_protein": len(all_pos),
            "positive_positions": sig_pos,
            "consequence": "the hottest stretch of the construct is the one secretion removes, so "
                           "every ranking here starts at residue 17 — and whether cleavage "
                           "actually happened is a QC question, not a modelling one (Spec A "
                           "intact-mass MS, ebfc_chem_rfq)",
        },
        "controls": {
            "run_is_deterministic": True,
            "determinism_evidence": "the run was repeated on the identical input on 2026-10-04 "
                                    "and A3D.csv came back byte-identical — unlike script 69, "
                                    "whose pdbfixer step carries a 3.77 Å² noise floor",
            "instrument_separates_anything": len(all_pos) > 0 and totals["max_score"] > 0,
            "what_these_controls_cannot_catch": "determinism is not correctness: a reproducible "
                                                "instrument can still be the wrong instrument, and "
                                                "both instruments here are of the SAME family "
                                                "(exposure-weighted neighbourhood hydrophobicity)",
        },
        "agreement": {
            "sites_with_a_measured_positive_neighbour_at_7A": flagged_sites,
            "of_those_whose_flagged_neighbour_is_a_ratified_compensation": sites_matched,
            "of_those_uncompensated": sites_flagged_uncompensated,
            "compensations_that_are_themselves_flagged": compensated_flagged,
            # ⚠️ Written from the three lists above, never beside them: the first draft of this
            # field said «the sites carrying a positive neighbour ARE the compensated ones», which
            # the same run disproves — Gln258 carries one too (00_05 §5, a summary beside a table
            # must be derived from it).
            "statement": (
                f"{len(flagged_sites)} of the {len(SITES)} deglycosylation sites carry a measured "
                f"positively-scoring neighbour within 7 Å: {', '.join(flagged_sites)}. In "
                f"{len(sites_matched)} of those {len(flagged_sites)} the flagged neighbour IS a "
                f"position the ratified gene substitutes ({', '.join(sites_matched)}). The "
                f"remaining {len(sites_flagged_uncompensated)} "
                f"({', '.join(sites_flagged_uncompensated)}) is flagged and NOT compensated, and "
                f"its flag is an order of magnitude weaker "
                f"(+{sites_out['Gln258']['best_measured_positive_neighbour_by_radius_A']['7']['a3d_score']} "
                f"against +{g71_score} and +{g405_score})."
            ),
        },
        "verdict": "",
        "caveats": [
            "A SASA/propensity proxy is NOT an aggregation prediction — neither instrument has a "
            "rate, a solubility or a critical concentration.",
            "The two instruments are independent in authorship and inputs but of the SAME FAMILY "
            "(exposure-weighted neighbourhood hydrophobicity), so their agreement is worth less "
            "than agreement between two different kinds of method.",
            "A3D's signed matrix makes a negative score at a Gln nearly structural, so 'no new "
            "site flagged' is a weak absence claim and is reported as one.",
            "The FAD cofactor is absent from the A3D model (HETATM dropped), so exposure near the "
            "flavin pocket is over-stated.",
            "The structure is the UNCOMPENSATED mutant; no A3D run exists on the compensated "
            "sequence, and that would need an AF3 re-prediction L1 §2 deliberately has not done.",
            "253 of 600 residues carry the exposure-gate sentinel; any statistic that admits them "
            "reads 'buried' as 'neutral'. The first reading of this very run did exactly that.",
            "The signal-peptide annotation is automatic (ECO:0000256), not experimental.",
            "Gln258's positive neighbour at 7 Å is an order of magnitude weaker than those at "
            "Gln71 and Gln405 — it is reported, not treated as a flag.",
            "Nothing here says the compensated protein expresses, folds or stays soluble; that is "
            "the CRO's QC and, downstream, coin Stage 2.",
            "A3D's own highest-scoring mature residue is NOT a position the gene touches and is "
            "not beside any of the eleven sites — the recipe scopes the eleven, not the global "
            "worst patch, and this cache reports that rather than cropping the ranking.",
        ],
    }

    g71 = out["sites"]["Gln71"]["best_measured_positive_neighbour_by_radius_A"]["7"]
    g405 = out["sites"]["Gln405"]["best_measured_positive_neighbour_by_radius_A"]["7"]
    out["verdict"] = (
        f"The open half of the L1 §2 recipe is now RUN. A3D puts its flags on "
        f"{g71['residue']} (+{g71['a3d_score']}, rank "
        f"{comps_out['L80D']['rank_among_mature_positive']} of the mature chain's "
        f"{comps_out['L80D']['n_mature_positive']} positive residues) and "
        f"{g405['residue']} (+{g405['a3d_score']}, rank "
        f"{comps_out['I401S']['rank_among_mature_positive']}) — the two positions the ratified "
        f"gene compensates, reached from Gln71 and Gln405 respectively. No OTHER deglycosylation "
        f"site carries a comparable flag: Gln258's best measured positive neighbour is an order of "
        f"magnitude weaker and the remaining eight have none at 7 Å. The third compensation "
        f"(A70S) sits on a residue A3D scores {comps_out['A70S']['a3d_score']:+.3f}, i.e. A3D does "
        f"not support it and does not contradict it. ⚠️ Two limits that shrink this to its true "
        f"size: the instruments are of the same family, and A3D's matrix makes a Gln negative "
        f"almost by construction, so 'nothing new was flagged' is a weak absence claim. What the "
        f"run does NOT do is close Gln258 and Gln200 — the gene carries no lever for either, and "
        f"only an expressed protein will say whether that matters."
    )

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    banner("Verdict")
    print(f"  {out['verdict']}")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)} ({out['runtime_s']:.2f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
