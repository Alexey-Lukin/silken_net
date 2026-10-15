# SPDX-License-Identifier: AGPL-3.0-or-later
"""Lumiflavin — the ONE home of the flavin SMILES the L3 chain computes on, and the check that the reduced form is the
tautomer the text names (in-silico §Critical Rules #16).

The reduced SMILES that stood in six scripts (20 · 21d · 21g · 29 · 29b · 33) until 2026-10-15 was
`CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2` — the 4a,5-DIHYDRO tautomer (H on sp³-C4a and N5), carried under the label
«1,5-dihydro». Both are C₁₃H₁₄N₄O₂, so every balance the pipeline runs (formula · electron count · charge · spin parity)
passed either way; only the hydrogen positions tell them apart, and those are what `check_15_dihydro` reads, before
any SCF. ⛔ Never re-type the SMILES in a script: import it from here.
"""
from __future__ import annotations

LUMIFLAVIN_OX_SMILES = "Cc1cc2nc3c(=O)[nH]c(=O)nc3n(C)c2cc1C"            # 7,8,10-trimethylisoalloxazine; N1, N5 bare
LUMIFLAVIN_RED_SMILES = "CC1=CC2=C(C=C1C)N(C)C3=C(N2)C(=O)NC(=O)N3"       # 1,5-dihydro (FADH₂ model): H on N1 · N3 · N5


def locants(mol) -> dict[int, str]:
    """Atom index → flavin locant for the four ring nitrogens, read from TOPOLOGY, never from an index (an index is
    not a locant: N1 of the 1,5-dihydro SMILES and N5 of the retired 4a,5-dihydro one are both index 18).
    N10 carries the methyl; N3 sits between the two carbonyl carbons; N1 is the other nitrogen of that ring; N5 is the
    remaining ring nitrogen. Works on the ox, reduced and deprotonated forms alike (H atoms are ignored)."""
    def carbonyl(a) -> bool:
        return a.GetSymbol() == "C" and any(n.GetSymbol() == "O" for n in a.GetNeighbors())

    ring_n = [a for a in mol.GetAtoms() if a.GetSymbol() == "N" and a.IsInRing()]
    if len(ring_n) != 4:
        raise ValueError(f"lumiflavin has four ring nitrogens, found {len(ring_n)}")
    out: dict[int, str] = {}
    for a in ring_n:
        heavy = [n for n in a.GetNeighbors() if n.GetSymbol() != "H"]
        if any(n.GetSymbol() == "C" and not n.IsInRing() for n in heavy):
            out[a.GetIdx()] = "N10"
        elif sum(carbonyl(n) for n in heavy) == 2:
            out[a.GetIdx()] = "N3"
    n3 = next(i for i, loc in out.items() if loc == "N3")
    pyrimidine = next(r for r in mol.GetRingInfo().AtomRings() if n3 in r)
    for a in ring_n:
        if a.GetIdx() not in out:
            out[a.GetIdx()] = "N1" if a.GetIdx() in pyrimidine else "N5"
    if sorted(out.values()) != ["N1", "N10", "N3", "N5"]:
        raise ValueError(f"flavin locants not resolved: {out}")
    return out


def check_15_dihydro(mol) -> dict:
    """Raise unless `mol` (with explicit H) is 1,5-dihydrolumiflavin: one H on each of N1 · N3 · N5, none on N10, and no
    sp³ carbon inside the fused ring system (the retired 4a,5 form has one, C4a). Returns the counts it judged."""
    from rdkit import Chem

    loc = locants(mol)
    h_on = {name: sum(n.GetSymbol() == "H" for n in mol.GetAtomWithIdx(i).GetNeighbors()) for i, name in loc.items()}
    sp3_ring_c = [a.GetIdx() for a in mol.GetAtoms() if a.GetSymbol() == "C" and a.IsInRing()
                  and a.GetHybridization() == Chem.HybridizationType.SP3]
    want = {"N1": 1, "N3": 1, "N5": 1, "N10": 0}
    if h_on != want or sp3_ring_c:
        raise ValueError(f"not 1,5-dihydrolumiflavin: H per ring N {h_on} (want {want}), sp3 ring carbons {sp3_ring_c}")
    return {"H_on_ring_N": h_on, "sp3_ring_carbons": sp3_ring_c}
