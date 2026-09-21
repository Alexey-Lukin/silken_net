#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
CHEM.11 — residue conservation at the freeze positions of the aglycosylated dgrFAD-GDH.

L1 §2 records three compensating substitutions taken into the ordered gene (`L80D`, `A70S`,
`I401S`). The third was held back until «is position 401 conserved?» was answered, and the
answer that lifted the hold (2026-09-18) came from scripts living in a session scratchpad —
⚠️ the exact shape in which CHEM.11 itself gated the freeze on PROSE for months: a conclusion
in canon with no measurer in the tree (00_07 HW.5.IS, script 69's own header). This script is
that measurement in the tree: committed inputs, a re-runnable pipeline, a cache.

WHAT IS COMPUTED
  1. the residue distribution at the freeze positions (70 · 80 · 401 · 405) over a COMMITTED
     homolog selection — the quality filter and the 90 % de-duplication are re-run here from
     the source FASTAs, never inherited as a number;
  2. the same distribution over the reliably-anchored subset only (local window identity),
     because a projected residue is worth exactly as much as the alignment around it;
  3. the POSITIVE CONTROL on the same instrument — the catalytic His537/His580 (`ACT_SITE` in
     UniProt G8E4B5). An instrument that cannot separate an invariant position from a variable
     one measures nothing, so this control is a gate, not decoration;
  4. clade locality of 401 (per-genus and per-identity-bin breakdown): a frequency can be an
     artefact of who is in the sample;
  5. robustness of the 401 reading to the gap penalties (three settings), because the 398–406
     stretch is indel-rich and that is precisely where a gap model decides the answer;
  6. an INDEPENDENT reading of the same column from an EXTERNAL MSA (EBI Clustal Omega) and
     from an EXTERNAL pairwise alignment (EBI EMBOSS Needle) — compared against OUR reading
     restricted to the external MSA's own 85 accessions, so the two aligners are judged on the
     identical set rather than on two different ones.

WHAT IS **NOT** COMPUTED — absent, not merely undiscussed
  · No phylogeny and no tree-aware weighting. The 90 % de-duplication is a crude correction
    for sampling bias, not a substitute for it: a frequency here is «how often in THIS set».
  · No structural or functional consequence of any substitution. This says how often a residue
    occurs at a position, never what putting it there does — that is script 69 (patch SASA)
    and, for stability, nothing in this tree.
  · Nothing about aggregation, solubility or expression yield.
  · The external MSA is NOT re-run here (it is a web service) and covers a SUBSET of 85
    accessions whose selection rule was never recorded — the file is committed, so the set is
    inspectable, but it is a CURATED sample and is reported as one.
  · Of the eight Ser-carrying homologs named in canon, only one (C. incanum A0A161YBC9) has an
     external pairwise alignment in the tree; the other seven are read by our own aligner only.
  · Nothing here re-predicts the structure on the compensated sequence (that is a separate run
    with its own provenance — L1 §2 keeps the AF3 input string unedited on purpose).

Runtime ~1 min (CPU, numpy only — no conda deps beyond numpy).
Inputs:  tools/in_silico/data/chem11_conservation/ (committed; provenance in its README.md)
Output:  tools/in_silico/cache/chemistry/chem11_site_conservation.json
"""
from __future__ import annotations

import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

DATA = REPO_ROOT / "tools/in_silico/data/chem11_conservation"
OUT_JSON = CACHE_DIR / "chemistry" / "chem11_site_conservation.json"

# ── the positions, and WHY each is here ──
# The four freeze positions are the candidates/compensations of L1 §2; the two His are the
# catalytic pair UniProt G8E4B5 annotates as ACT_SITE, and they are the instrument's control.
FREEZE_POSITIONS = (70, 80, 401, 405)
CONTROL_POSITIONS = (537, 580)
# Positions the patch score (69) found admissible on area and REFUSED on a declared threshold. They
# are not in the gene and not controls — they are the price of a threshold, and the threshold is
# judged by the founder. 201 (Ala201→Ser, Gln200's only lever) is refused by burial 0.770 against
# our declared ceiling of 0.75: a margin of 0.020. The I401S hold was lifted by exactly this axis,
# so refusing 201 on geometry ALONE would leave the two positions judged by different evidence.
REFUSED_CANDIDATE_POSITIONS = (201,)
POSITIONS = FREEZE_POSITIONS + CONTROL_POSITIONS + REFUSED_CANDIDATE_POSITIONS
FOCUS = 401  # the position whose hold this script was written to settle

# Numbering asserts: the residue our numbering must find at each position. A one-off shift
# (signal peptide stripped, an isoform, a re-download) would otherwise move every count
# silently, and the failure would look like biology.
# 🔑 The query is the WILD TYPE (UniProt G8E4B5). Canon names the aggregation patches by their
# DESIGNED residue — `Gln405` is one of the 11 N→Q sequon substitutions — so at position 405
# this file asserts **N**, not Q, and the frequency reported there is Asn's. Asserting Q was
# the author's first guess and this control caught it: the homologs are aligned against the
# wild-type string, so the wild-type residue is the only one the numbering can be checked on.
EXPECTED_RESIDUES = {70: "A", 80: "L", 401: "I", 405: "N", 537: "H", 580: "H", 201: "A"}
QUERY_LENGTH = 600

# ── selection thresholds (declared, not tuned per answer) ──
PID_MIN = 25.0          # % identity to the query over aligned columns — below it the projection is noise
ALIGNED_COLS_MIN = 450  # aligned columns — a fragment cannot place a position 400 residues in
DEDUP_IDENTITY_MAX = 90.0   # % — two sequences above it count once
DEDUP_MIN_OVERLAP = 300     # projected positions that must overlap before the pair is judged
ANCHOR_WINDOW = 10          # ± columns around the position
ANCHOR_LOCAL_MIN = 40.0     # % local identity inside that window → «reliably anchored»
IDENTITY_BINS = ((70.0, 101.0), (50.0, 70.0), (40.0, 50.0), (33.0, 40.0), (25.0, 33.0))
GAP_SETTINGS = ((-11.0, -1.0), (-14.0, -2.0), (-8.0, -1.0))   # (open, extend); first = default

SOURCES = (
    ("blast", "homologs_blast.fasta"),
    ("gmc_reviewed", "homologs_gmc_reviewed.fasta"),
    ("uniref50", "homologs_uniref50.fasta"),
    ("genus_scan", "homologs_genus_scan.fasta"),
)

# ── BLOSUM62, inline: the matrix is part of the instrument, not an install ──
B62_TXT = """   A  R  N  D  C  Q  E  G  H  I  L  K  M  F  P  S  T  W  Y  V  B  Z  X  *
A  4 -1 -2 -2  0 -1 -1  0 -2 -1 -1 -1 -1 -2 -1  1  0 -3 -2  0 -2 -1  0 -4
R -1  5  0 -2 -3  1  0 -2  0 -3 -2  2 -1 -3 -2 -1 -1 -3 -2 -3 -1  0 -1 -4
N -2  0  6  1 -3  0  0  0  1 -3 -3  0 -2 -3 -2  1  0 -4 -2 -3  3  0 -1 -4
D -2 -2  1  6 -3  0  2 -1 -1 -3 -4 -1 -3 -3 -1  0 -1 -4 -3 -3  4  1 -1 -4
C  0 -3 -3 -3  9 -3 -4 -3 -3 -1 -1 -3 -1 -2 -3 -1 -1 -2 -2 -1 -3 -3 -2 -4
Q -1  1  0  0 -3  5  2 -2  0 -3 -2  1  0 -3 -1  0 -1 -2 -1 -2  0  3 -1 -4
E -1  0  0  2 -4  2  5 -2  0 -3 -3  1 -2 -3 -1  0 -1 -3 -2 -2  1  4 -1 -4
G  0 -2  0 -1 -3 -2 -2  6 -2 -4 -4 -2 -3 -3 -2  0 -2 -2 -3 -3 -1 -2 -1 -4
H -2  0  1 -1 -3  0  0 -2  8 -3 -3 -1 -2 -1 -2 -1 -2 -2  2 -3  0  0 -1 -4
I -1 -3 -3 -3 -1 -3 -3 -4 -3  4  2 -3  1  0 -3 -2 -1 -3 -1  3 -3 -3 -1 -4
L -1 -2 -3 -4 -1 -2 -3 -4 -3  2  4 -2  2  0 -3 -2 -1 -2 -1  1 -4 -3 -1 -4
K -1  2  0 -1 -3  1  1 -2 -1 -3 -2  5 -1 -3 -1  0 -1 -3 -2 -2  0  1 -1 -4
M -1 -1 -2 -3 -1  0 -2 -3 -2  1  2 -1  5  0 -2 -1 -1 -1 -1  1 -3 -1 -1 -4
F -2 -3 -3 -3 -2 -3 -3 -3 -1  0  0 -3  0  6 -4 -2 -2  1  3 -1 -3 -3 -1 -4
P -1 -2 -2 -1 -3 -1 -1 -2 -2 -3 -3 -1 -2 -4  7 -1 -1 -4 -3 -2 -2 -1 -2 -4
S  1 -1  1  0 -1  0  0  0 -1 -2 -2  0 -1 -2 -1  4  1 -3 -2 -2  0  0  0 -4
T  0 -1  0 -1 -1 -1 -1 -2 -2 -1 -1 -1 -1 -2 -1  1  5 -2 -2  0 -1 -1  0 -4
W -3 -3 -4 -4 -2 -2 -3 -2 -2 -3 -2 -3 -1  1 -4 -3 -2 11  2 -3 -4 -3 -2 -4
Y -2 -2 -2 -3 -2 -1 -2 -3  2 -1 -1 -2 -1  3 -3 -2 -2  2  7 -1 -3 -2 -1 -4
V  0 -3 -3 -3 -1 -2 -2 -3 -3  3  1 -2  1 -1 -2 -2  0 -3 -1  4 -3 -2 -1 -4
B -2 -1  3  4 -3  0  1 -1  0 -3 -4  0 -3 -3 -2  0 -1 -4 -3 -3  4  1 -1 -4
Z -1  0  0  1 -3  3  4 -2  0 -3 -3  1 -1 -3 -1  0 -1 -3 -2 -2  1  4 -1 -4
X  0 -1 -1 -1 -2 -1 -1 -1 -1 -1 -1 -1 -1 -1 -2  0  0 -2 -1 -1 -1 -1 -1 -4
* -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4  1"""
NEG = -1e9


def _load_b62() -> np.ndarray:
    lines = B62_TXT.strip().split("\n")
    cols = lines[0].split()
    m = np.full((128, 128), -4, dtype=np.float32)
    for line in lines[1:]:
        parts = line.split()
        row, vals = parts[0], [int(x) for x in parts[1:]]
        for col, val in zip(cols, vals, strict=True):
            m[ord(row), ord(col)] = val
    return m


B62 = _load_b62()


def align(query: str, target: str, gap_open: float, gap_extend: float):
    """Gotoh affine-gap alignment with FREE END GAPS (overlap), BLOSUM62, numpy only.

    Free end gaps are the right semantics here and not a convenience: the pool carries
    fragments and multi-domain proteins, so penalising a missing N-terminus would drag the
    whole alignment frame and move the very columns this script reads. Returns the two gapped
    strings, the score and the (i, j) the traceback started from (= the unaligned prefix
    lengths, needed to place the first aligned query residue).
    """
    n, m = len(query), len(target)
    qi = np.frombuffer(query.encode(), dtype=np.uint8).astype(np.int32)
    ti = np.frombuffer(target.encode(), dtype=np.uint8).astype(np.int32)
    sub = B62[qi[:, None], ti[None, :]]
    mat = np.full((n + 1, m + 1), NEG, dtype=np.float32)   # ends in a match
    ins = np.full((n + 1, m + 1), NEG, dtype=np.float32)   # ends in a gap in the query
    dele = np.full((n + 1, m + 1), NEG, dtype=np.float32)  # ends in a gap in the target
    ins[0, :] = 0.0
    dele[:, 0] = 0.0
    mat[0, 0] = 0.0
    jj = np.arange(m + 1, dtype=np.float32)
    for i in range(1, n + 1):
        prev_m, prev_i, prev_d = mat[i - 1], ins[i - 1], dele[i - 1]
        dele[i, :] = np.maximum(prev_m + gap_open, prev_d + gap_extend)
        dele[i, 0] = 0.0
        diag = np.maximum(np.maximum(prev_m[:-1], prev_i[:-1]), prev_d[:-1])
        mat[i, 1:] = sub[i - 1, :] + diag
        acc = np.maximum.accumulate(mat[i, :] - gap_extend * jj)
        ins[i, 1:] = gap_open + gap_extend * (jj[1:] - 1.0) + acc[:-1]
    best = np.maximum(np.maximum(mat, ins), dele)
    row_j = int(np.argmax(best[n, :]))
    col_i = int(np.argmax(best[:, m]))
    if best[n, row_j] >= best[col_i, m]:
        i, j = n, row_j
    else:
        i, j = col_i, m
    score = float(best[i, j])
    state = "M" if mat[i, j] == best[i, j] else ("I" if ins[i, j] == best[i, j] else "D")
    aq, at = [], []
    while i > 0 and j > 0:
        if state == "M":
            aq.append(query[i - 1])
            at.append(target[j - 1])
            i -= 1
            j -= 1
            if i == 0 or j == 0:
                break
            here = max(mat[i, j], ins[i, j], dele[i, j])
            state = "M" if mat[i, j] == here else ("I" if ins[i, j] == here else "D")
        elif state == "I":
            aq.append("-")
            at.append(target[j - 1])
            j -= 1
            if j == 0:
                break
            state = "I" if abs(ins[i, j + 1] - (ins[i, j] + gap_extend)) < 1e-4 else "M"
        else:
            aq.append(query[i - 1])
            at.append("-")
            i -= 1
            if i == 0:
                break
            state = "D" if abs(dele[i + 1, j] - (dele[i, j] + gap_extend)) < 1e-4 else "M"
    return "".join(reversed(aq)), "".join(reversed(at)), score, (i, j)


def read_fasta(path: Path) -> list[tuple[str, str]]:
    recs: list[tuple[str, str]] = []
    head, seq = None, []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith(">"):
            if head is not None:
                recs.append((head, "".join(seq)))
            head, seq = line[1:], []
        elif line:
            seq.append(line)
    if head is not None:
        recs.append((head, "".join(seq)))
    return recs


def parse_header(head: str) -> tuple[str, str, str]:
    """UniProt-style header → (accession, organism, protein name). Bare id → (id, '?', '?')."""
    acc = head.split("|")[1] if "|" in head else head.split()[0]
    organism = head.split("OS=")[1].split(" OX=")[0] if "OS=" in head else "?"
    name = head.split(" OS=")[0]
    name = " ".join(name.split()[1:]) if " " in name else name
    return acc, organism, name


def project(query: str, target: str, gap_open: float, gap_extend: float):
    """Align and read the query's positions off the target.

    Returns (residues, pid, aligned_cols, local, projected) where `projected` is the target
    residue for EVERY query position (1-based, uint8, '-' where unaligned) — the frame the
    de-duplication compares in, so the alignment is paid for once.
    """
    aq, at, _score, (si, _sj) = align(query, target, gap_open, gap_extend)
    qpos = si
    cols: list[tuple[int, str, str]] = []
    for a, b in zip(aq, at, strict=True):
        if a != "-":
            qpos += 1
        cols.append((qpos, a, b))
    identical = sum(1 for _, a, b in cols if a == b and a != "-")
    aligned = sum(1 for _, a, b in cols if a != "-" and b != "-")
    pid = 100.0 * identical / aligned if aligned else 0.0
    first_col: dict[int, int] = {}
    projected = np.full(len(query) + 1, ord("-"), dtype=np.uint8)
    for k, (pos, a, b) in enumerate(cols):
        if a != "-" and pos not in first_col:
            first_col[pos] = k
            projected[pos] = ord(b)
    residues: dict[int, str] = {}
    local: dict[int, float] = {}
    for pos in POSITIONS:
        k = first_col.get(pos)
        if k is None:
            residues[pos] = "-"       # the query residue is outside the aligned region
            local[pos] = 0.0
            continue
        residues[pos] = cols[k][2]
        lo, hi = max(0, k - ANCHOR_WINDOW), min(len(cols), k + ANCHOR_WINDOW + 1)
        window = cols[lo:hi]
        same = sum(1 for _, a, b in window if a == b and a != "-")
        local[pos] = 100.0 * same / len(window)
    return residues, pid, aligned, local, projected


def distribution(rows: list[dict], pos: int, query_residue: str, anchored_only: bool = False) -> dict:
    sel = [r for r in rows if not anchored_only or r["local"][pos] >= ANCHOR_LOCAL_MIN]
    counts = Counter(r["residues"][pos] for r in sel)
    n = len(sel)

    def pct(count: int) -> float:
        return round(100.0 * count / n, 1) if n else 0.0

    return {
        "n": n,
        "identical": counts[query_residue],
        "identical_pct": pct(counts[query_residue]),
        "ser": counts["S"],
        "ser_pct": pct(counts["S"]),
        "gap_or_uncovered": counts["-"],
        "gap_or_uncovered_pct": pct(counts["-"]),
        "distribution": dict(counts.most_common()),
    }


def msa_column_for_query_position(msa: list[tuple[str, str]], query_acc: str, pos: int) -> int:
    """The 0-based column of an aligned MSA that carries the query's residue `pos`."""
    row = next((s for h, s in msa if parse_header(h)[0] == query_acc), None)
    if row is None:
        raise KeyError(f"{query_acc} not found in the external MSA")
    seen = 0
    for col, ch in enumerate(row):
        if ch != "-":
            seen += 1
            if seen == pos:
                return col
    raise ValueError(f"the external MSA's {query_acc} row has fewer than {pos} residues")


def parse_needle_pair(path: Path) -> tuple[str, str, str, str]:
    """EMBOSS Needle `pair` output → (name_a, name_b, gapped_a, gapped_b). Format-only, no deps."""
    names: list[str] = []
    blocks: dict[str, list[str]] = defaultdict(list)
    order: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# 1:") or line.startswith("# 2:"):
            names.append(line.split(":", 1)[1].strip())
            continue
        if not line or line.startswith("#") or line.startswith(" "):
            continue
        parts = line.split()
        if len(parts) < 4 or not parts[1].isdigit():
            continue
        name, seq = parts[0], parts[2]
        if name not in blocks:
            order.append(name)
        blocks[name].append(seq)
    if len(order) < 2:
        raise ValueError(f"{path.name}: could not read two aligned sequences")
    a, b = order[0], order[1]
    return names[0] if names else a, names[1] if len(names) > 1 else b, "".join(blocks[a]), "".join(blocks[b])


def residue_at_query_position(gapped_q: str, gapped_t: str, pos: int) -> str:
    seen = 0
    for qa, ta in zip(gapped_q, gapped_t, strict=True):
        if qa != "-":
            seen += 1
            if seen == pos:
                return ta
    raise ValueError(f"the pairwise alignment covers fewer than {pos} query residues")


def main() -> int:
    t0 = time.time()
    banner("CHEM.11 site conservation — loading the committed selection")

    qhead, qseq = read_fasta(DATA / "query_G8E4B5.fasta")[0]
    query_acc = parse_header(qhead)[0]
    if len(qseq) != QUERY_LENGTH:
        sys.exit(f"query length {len(qseq)} != {QUERY_LENGTH} — numbering would shift silently")
    for pos, expected in EXPECTED_RESIDUES.items():
        if qseq[pos - 1] != expected:
            sys.exit(f"query position {pos} is {qseq[pos - 1]}, expected {expected} — numbering shifted")
    print(f"  query {query_acc}: {len(qseq)} aa · " + " · ".join(f"{p}{qseq[p - 1]}" for p in POSITIONS))

    # ── control the instrument on the query itself: self-alignment must be perfect ──
    self_res, self_pid, self_cols, _self_local, _self_proj = project(qseq, qseq, *GAP_SETTINGS[0])
    if round(self_pid, 6) != 100.0 or self_cols != len(qseq):
        sys.exit(f"self-alignment control failed: pid={self_pid} cols={self_cols}")
    if any(self_res[p] != qseq[p - 1] for p in POSITIONS):
        sys.exit("self-alignment control failed: a position projected onto the wrong residue")

    candidates: dict[str, dict] = {}
    per_source: dict[str, int] = {}
    for tag, fname in SOURCES:
        recs = read_fasta(DATA / fname)
        per_source[tag] = len(recs)
        for head, seq in recs:
            acc, organism, name = parse_header(head)
            if acc == query_acc or acc in candidates:
                continue
            candidates[acc] = {"acc": acc, "org": organism, "name": name, "seq": seq, "source": tag}
    print("  sources: " + " · ".join(f"{k}={v}" for k, v in per_source.items()) +
          f" → {len(candidates)} unique accessions")

    banner("Projecting the positions (query-anchored pairwise, BLOSUM62)")
    rows: list[dict] = []
    for rec in candidates.values():
        residues, pid, cols, local, projected = project(qseq, rec["seq"], *GAP_SETTINGS[0])
        rows.append({**{k: rec[k] for k in ("acc", "org", "name", "source")},
                     "length": len(rec["seq"]), "pid": round(pid, 1), "aligned_cols": cols,
                     "residues": residues, "local": local, "projected": projected})
    passed = [r for r in rows if r["pid"] >= PID_MIN and r["aligned_cols"] >= ALIGNED_COLS_MIN]
    print(f"  aligned {len(rows)} · quality-filtered (pid≥{PID_MIN:.0f}%, cols≥{ALIGNED_COLS_MIN}) → {len(passed)}")

    # ── 90 % de-duplication in the PROJECTED frame (query coordinates), highest-pid first ──
    # The projection is the one computed above: re-aligning here would pay twice for the same
    # matrices AND put a second copy of the frame logic in the file, where the two could drift.
    passed.sort(key=lambda r: -r["pid"])
    proj = np.stack([r["projected"] for r in passed]) if passed else np.zeros((0, QUERY_LENGTH + 1), np.uint8)
    gap = ord("-")
    kept_idx: list[int] = []
    for i in range(len(passed)):
        a = proj[i, 1:]
        redundant = False
        for j in kept_idx:
            b = proj[j, 1:]
            mask = (a != gap) & (b != gap)
            n = int(mask.sum())
            if n >= DEDUP_MIN_OVERLAP and 100.0 * int(((a == b) & mask).sum()) / n >= DEDUP_IDENTITY_MAX:
                redundant = True
                break
        if not redundant:
            kept_idx.append(i)
    kept = [passed[i] for i in kept_idx]
    genera = sorted({r["org"].split()[0] for r in kept})
    print(f"  90 %-deduped → {len(kept)} homologs from {len(genera)} genera")

    banner("Distributions")
    positions_out: dict[str, dict] = {}
    for pos in POSITIONS:
        qr = qseq[pos - 1]
        whole = distribution(kept, pos, qr)
        anchored = distribution(kept, pos, qr, anchored_only=True)
        all_quality = distribution(passed, pos, qr)
        positions_out[str(pos)] = {
            "query_residue": qr,
            "role": ("freeze" if pos in FREEZE_POSITIONS
                     else "refused_candidate" if pos in REFUSED_CANDIDATE_POSITIONS
                     else "catalytic_control"),
            "deduped": whole,
            "anchored": anchored,
            "all_quality_filtered": all_quality,
        }
        print(f"  pos {pos} ({qr}): n={whole['n']} identical={whole['identical_pct']}% "
              f"Ser={whole['ser_pct']}% | anchored n={anchored['n']} identical={anchored['identical_pct']}% "
              f"Ser={anchored['ser_pct']}%")

    # ── clade locality of the focus position ──
    by_genus: dict[str, Counter] = defaultdict(Counter)
    for r in kept:
        by_genus[r["org"].split()[0]][r["residues"][FOCUS]] += 1
    ser_named = [
        {"acc": r["acc"], "organism": r["org"], "identity_to_query_pct": r["pid"],
         "local_window_identity_pct": round(r["local"][FOCUS], 0), "source": r["source"]}
        for r in kept if r["residues"][FOCUS] == "S"
    ]
    ser_named.sort(key=lambda d: -d["identity_to_query_pct"])
    # The nearest neighbourhood, ranked — so a claim of the form «the Nth-closest homolog carries X»
    # has an owner here instead of living in canon prose with nothing to check it against.
    nearest = [
        {"rank": i + 1, "acc": r["acc"], "organism": r["org"],
         "identity_to_query_pct": r["pid"], f"residue_at_{FOCUS}": r["residues"][FOCUS],
         "local_window_identity_pct": round(r["local"][FOCUS], 0)}
        for i, r in enumerate(sorted(kept, key=lambda r: -r["pid"])[:10])
    ]
    bins_out = []
    for lo, hi in IDENTITY_BINS:
        sel = [r for r in kept if lo <= r["pid"] < hi]
        counts = Counter(r["residues"][FOCUS] for r in sel)
        anch = Counter(r["residues"][FOCUS] for r in sel if r["local"][FOCUS] >= ANCHOR_LOCAL_MIN)
        bins_out.append({
            "identity_range_pct": [lo, hi],
            "n": len(sel),
            "distribution": dict(counts.most_common()),
            "anchored_n": sum(anch.values()),
            "anchored_distribution": dict(anch.most_common()),
        })

    # ── gap-penalty robustness on the kept set ──
    banner("Gap-penalty robustness")
    robustness = []
    for go, ge in GAP_SETTINGS:
        counts, anch = Counter(), Counter()
        for r in kept:
            residues, _pid, _cols, local, _proj = project(qseq, candidates[r["acc"]]["seq"], go, ge)
            counts[residues[FOCUS]] += 1
            if local[FOCUS] >= ANCHOR_LOCAL_MIN:
                anch[residues[FOCUS]] += 1
        n = sum(counts.values())
        na = sum(anch.values())
        robustness.append({
            "gap_open": go, "gap_extend": ge, "n": n,
            "identical_pct": round(100.0 * counts[qseq[FOCUS - 1]] / n, 1),
            "ser_pct": round(100.0 * counts["S"] / n, 1),
            "anchored_n": na,
            "anchored_identical_pct": round(100.0 * anch[qseq[FOCUS - 1]] / na, 1) if na else 0.0,
            "anchored_ser_pct": round(100.0 * anch["S"] / na, 1) if na else 0.0,
        })
        print(f"  open {go} ext {ge}: identical={robustness[-1]['identical_pct']}% "
              f"Ser={robustness[-1]['ser_pct']}% (anchored n={na})")

    # ── the INDEPENDENT readings ──
    banner("External readings (not our aligner)")
    msa = read_fasta(DATA / "external_msa_clustalo.fasta")
    msa_accs = [parse_header(h)[0] for h, _ in msa]
    col = msa_column_for_query_position(msa, query_acc, FOCUS)
    msa_counts = Counter(s[col] for h, s in msa if parse_header(h)[0] != query_acc)
    msa_n = sum(msa_counts.values())
    ours_same_subset = [r for r in rows if r["acc"] in set(msa_accs)]
    ours_counts = Counter(r["residues"][FOCUS] for r in ours_same_subset)
    ours_n = sum(ours_counts.values())
    # Per-sequence agreement, and then the SAME number with the MSA's own gaps taken out.
    # The raw figure is dominated by them by construction: where the external alignment puts a
    # gap in this column it makes no claim about a residue, so counting that as a disagreement
    # prices the indel-rich window twice. Both are reported — the raw one is what a reader would
    # compute, the conditional one is what the two aligners actually disagree about.
    msa_by_acc = {parse_header(h)[0]: s for h, s in msa}
    kinds: Counter = Counter()
    for r in ours_same_subset:
        theirs, mine = msa_by_acc[r["acc"]][col], r["residues"][FOCUS]
        if theirs == mine:
            kinds["same"] += 1
        elif theirs == "-":
            kinds["msa_gap_vs_our_residue"] += 1
        elif mine == "-":
            kinds["our_gap_vs_msa_residue"] += 1
        else:
            kinds["both_residue_but_different"] += 1
    agree = kinds["same"]
    placed = ours_n - kinds["msa_gap_vs_our_residue"]
    external_msa = {
        "tool": "Clustal Omega",
        "provider": "EBI Job Dispatcher REST",
        "job_id": "clustalo-R20260918-064814-0951-10344109-p1m",
        "input_file": "external_msa_input.fasta",
        "alignment_file": "external_msa_clustalo.fasta",
        "sequences_in_alignment": len(msa),
        "column_0based": col,
        "counts_excluding_query": dict(msa_counts.most_common()),
        "n": msa_n,
        "gap_pct": round(100.0 * msa_counts["-"] / msa_n, 1) if msa_n else 0.0,
        "ser_pct": round(100.0 * msa_counts["S"] / msa_n, 1) if msa_n else 0.0,
        "identical_pct": round(100.0 * msa_counts[qseq[FOCUS - 1]] / msa_n, 1) if msa_n else 0.0,
        "our_reading_on_the_same_accessions": {
            "n": ours_n,
            "counts": dict(ours_counts.most_common()),
            "ser_pct": round(100.0 * ours_counts["S"] / ours_n, 1) if ours_n else 0.0,
            "identical_pct": round(100.0 * ours_counts[qseq[FOCUS - 1]] / ours_n, 1) if ours_n else 0.0,
        },
        "per_sequence_agreement_pct": round(100.0 * agree / ours_n, 1) if ours_n else 0.0,
        "per_sequence_agreement_where_msa_places_a_residue_pct": round(100.0 * agree / placed, 1) if placed else 0.0,
        "disagreement_kinds": dict(kinds.most_common()),
        "subset_selection_rule": "NOT RECORDED — the 85 accessions were chosen in the session that "
                                 "submitted the job; the input file is committed, so the set is "
                                 "inspectable, but it is a CURATED sample, not a defined stratum",
    }
    print(f"  external MSA column {col}: Ser={external_msa['ser_pct']}% "
          f"identical={external_msa['identical_pct']}% gaps={external_msa['gap_pct']}% (n={msa_n})")
    print(f"  our reading on the SAME {ours_n} accessions: Ser={external_msa['our_reading_on_the_same_accessions']['ser_pct']}% "
          f"identical={external_msa['our_reading_on_the_same_accessions']['identical_pct']}% "
          f"· per-sequence agreement {external_msa['per_sequence_agreement_pct']}% "
          f"({external_msa['per_sequence_agreement_where_msa_places_a_residue_pct']}% where the MSA places a residue)")
    print(f"  disagreement kinds: {external_msa['disagreement_kinds']}")

    # Each entry is ONE committed EMBOSS Needle job. Canon names eight Ser-carrying homologs near
    # our clade, so this list is a growing subset, never the set — `pairwise_n` below reports its
    # size from the data so no prose can claim a count the tree does not hold.
    NEEDLE_JOBS = [
        ("A0A161YBC9", "Colletotrichum incanum",
         "emboss_needle-R20260918-070304-0265-99399309-p2m"),
        ("A0A9W8Z4G1", "Gnomoniopsis smithogilvyi",
         "emboss_needle-R20260918-070301-0914-9312139-p1m"),
        ("A0AAJ0ES17", "Colletotrichum godetiae",
         "emboss_needle-R20260921-114618-0460-66964301-p1m"),
        ("A0A8H6N132", "Colletotrichum plurivorum",
         "emboss_needle-R20260921-114621-0111-15641806-p1m"),
        ("A0A5Q4BTX3", "Colletotrichum shisoi",
         "emboss_needle-R20260921-114623-0526-87193400-p1m"),
        ("A0A066XAU2", "Colletotrichum sublineola",
         "emboss_needle-R20260921-114626-0222-73480118-p1m"),
        ("A0AAD8PX48", "Colletotrichum navitas",
         "emboss_needle-R20260921-114628-0618-77563113-p1m"),
        ("A0A1G4ASF8", "Colletotrichum orchidophilum",
         "emboss_needle-R20260921-114631-0683-23158585-p1m"),
    ]
    external_pairwise = []
    for acc, organism, job_id in NEEDLE_JOBS:
        needle_path = DATA / f"external_needle_{acc}.aln"
        name_a, name_b, gq, gt = parse_needle_pair(needle_path)
        needle_residue = residue_at_query_position(gq, gt, FOCUS)
        ours_for_needle = next((r for r in rows if r["acc"] == acc), None)
        # ⚠️ `in_external_msa` is not decoration: an accession absent from the curated 85 makes its
        # pairwise an INDEPENDENT reading rather than a second look at the same cell.
        external_pairwise.append({
            "tool": "EMBOSS Needle",
            "provider": "EBI Job Dispatcher REST",
            "job_id": job_id,
            "alignment_file": needle_path.name,
            "query_name": name_a,
            "target_name": name_b,
            "target_acc": acc,
            "target_organism": organism,
            f"residue_at_query_{FOCUS}": needle_residue,
            "our_reading": ours_for_needle["residues"][FOCUS] if ours_for_needle else None,
            "agrees": bool(ours_for_needle and ours_for_needle["residues"][FOCUS] == needle_residue),
            "in_external_msa": acc in msa,
        })
        print(f"  external Needle ({name_b}): {FOCUS} → {needle_residue} "
              f"(ours: {external_pairwise[-1]['our_reading']}"
              f"{'' if external_pairwise[-1]['in_external_msa'] else ', outside the curated MSA'})")
    pairwise_n = len(external_pairwise)
    pairwise_agreeing = sum(1 for e in external_pairwise if e["agrees"])

    focus = positions_out[str(FOCUS)]
    control = positions_out[str(CONTROL_POSITIONS[0])]
    verdict = (
        f"Position {FOCUS} ({qseq[FOCUS - 1]}) is VARIABLE in this set: the query residue occurs in "
        f"{focus['deduped']['identical_pct']} % of {focus['deduped']['n']} de-duplicated homologs "
        f"({len(genera)} genera) and Ser in {focus['deduped']['ser_pct']} %; in the anchored subset "
        f"(n={focus['anchored']['n']}) it is {focus['anchored']['identical_pct']} % vs "
        f"{focus['anchored']['ser_pct']} % Ser. The catalytic control His{CONTROL_POSITIONS[0]} reads "
        f"{control['deduped']['identical_pct']} % on the same instrument "
        f"({control['anchored']['identical_pct']} % anchored, Ser {control['anchored']['ser_pct']} %), "
        f"so the instrument separates an invariant position from a variable one. The external MSA "
        f"(Clustal Omega, {msa_n} sequences) reads the same column as "
        f"{external_msa['ser_pct']} % Ser / {external_msa['identical_pct']} % "
        f"{qseq[FOCUS - 1]} with {external_msa['gap_pct']} % gaps: the direction agrees, the magnitudes "
        f"do not, and the gap fraction is why — per sequence the two aligners agree on "
        f"{external_msa['per_sequence_agreement_pct']} % of the shared accessions, rising to "
        f"{external_msa['per_sequence_agreement_where_msa_places_a_residue_pct']} % once the cells where "
        f"the external alignment places NO residue are excluded "
        f"({kinds['msa_gap_vs_our_residue']} of {ours_n} cells). The external PAIRWISE alignments in "
        f"the tree (EMBOSS Needle, n={pairwise_n}: "
        + "; ".join(f"{e['target_organism']} → {e[f'residue_at_query_{FOCUS}']}"
                    for e in external_pairwise)
        + f") agree with our reading in {pairwise_agreeing} of {pairwise_n}."
    )

    out = {
        "script": Path(__file__).name,
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runtime_s": round(time.time() - t0, 1),
        "question": "Is position 401 of dgrGcGDH conserved? (the hold that gated I401S in the ordered gene)",
        "query": {
            "accession": query_acc,
            "header": qhead,
            "length": len(qseq),
            "residues_at_positions": {str(p): qseq[p - 1] for p in POSITIONS},
            "numbering_controls": {str(p): r for p, r in EXPECTED_RESIDUES.items()},
        },
        "selection": {
            "sources": {tag: {"file": fname, "records": per_source[tag]} for tag, fname in SOURCES},
            "unique_accessions": len(candidates),
            "quality_filter": {
                "pid_min_pct": PID_MIN, "aligned_cols_min": ALIGNED_COLS_MIN, "passed": len(passed),
            },
            "dedup": {
                "identity_max_pct": DEDUP_IDENTITY_MAX, "min_overlap_positions": DEDUP_MIN_OVERLAP,
                "kept": len(kept), "genera": len(genera), "genera_list": genera,
            },
            "anchor_rule": {
                "window_half_width_cols": ANCHOR_WINDOW, "local_identity_min_pct": ANCHOR_LOCAL_MIN,
            },
            "aligner": {
                "algorithm": "Gotoh affine-gap, free end gaps (overlap)", "matrix": "BLOSUM62",
                "gap_open": GAP_SETTINGS[0][0], "gap_extend": GAP_SETTINGS[0][1],
                "implementation": "this script (numpy only)",
            },
        },
        "positions": positions_out,
        "focus_position": FOCUS,
        "clade_locality": {
            "position": FOCUS,
            "by_genus": {g: dict(c.most_common()) for g, c in
                         sorted(by_genus.items(), key=lambda kv: -sum(kv[1].values()))},
            "ser_carrying_homologs": ser_named,
            "nearest_homologs_by_identity": nearest,
            "identity_bins": bins_out,
        },
        "gap_penalty_robustness": robustness,
        "external_msa": external_msa,
        "external_pairwise": external_pairwise,
        "controls": {
            "numbering_asserted_against": "UniProt G8E4B5 (600 aa, ACT_SITE 537/580) — the script exits "
                                          "if any position does not carry its expected residue",
            "self_alignment": {"pid_pct": round(self_pid, 1), "aligned_cols": self_cols,
                               "positions_recovered": True},
            "positive_control_positions": list(CONTROL_POSITIONS),
            "refused_candidate_positions": list(REFUSED_CANDIDATE_POSITIONS),
            "refused_candidate_scope": "positions script 69 found admissible on apolar area and "
                                       "refused on a declared threshold. Reported so the refusal is "
                                       "judged on the SAME axis that lifted the I401S hold; this "
                                       "script says how often the residue varies, never what the "
                                       "swap would do to folding, activity or yield",
        },
        "verdict": verdict,
        "caveats": [
            "A frequency in a selected set is not a conservation SCORE: there is no phylogeny and no "
            "tree-aware weighting here, and the 90 % de-duplication is a crude bias correction.",
            "The external MSA covers a CURATED 85-accession subset whose selection rule was never "
            "recorded; it is committed, so the set can be inspected, but it is not a defined stratum.",
            f"The {FOCUS - 3}–{FOCUS + 5} stretch is indel-rich: the external MSA puts "
            f"{external_msa['gap_pct']} % gaps in this column, so a column-based reading there is weaker "
            "than the same reading at a well-anchored position — which is exactly why the anchored "
            "subset and the gap-penalty sweep are reported beside the headline.",
            f"The two aligners' raw per-sequence agreement ({external_msa['per_sequence_agreement_pct']} %) "
            "is NOT a measure of how much they disagree about the residue: "
            f"{kinds['msa_gap_vs_our_residue']} of the {ours_n} shared cells are the external alignment "
            "placing a GAP where ours places a residue, i.e. it makes no claim there. The number to read "
            f"is the conditional one "
            f"({external_msa['per_sequence_agreement_where_msa_places_a_residue_pct']} %), and even that "
            f"leaves {kinds['both_residue_but_different']} cells where both place a residue and the two "
            "differ.",
            "Of the eight Ser-carrying homologs named in canon, ONE has an external pairwise alignment "
            "in the tree (C. incanum); the rest are this aligner's reading only.",
            "Frequency says nothing about consequence: that a residue is common at a position is not "
            "evidence that putting it there is safe for folding, activity or expression.",
        ],
        "declared_ceilings": [
            "No structural, kinetic or stability consequence of any substitution is computed here.",
            "The homolog pool is what four named queries returned on 2026-09-18; a re-fetch would "
            "return a different pool, and the committed FASTAs are what makes THIS number re-runnable.",
            "Sequences are read as annotated in UniProt: signal peptides, isoforms and mis-annotated "
            "fragments are filtered only by the pid / aligned-column thresholds above.",
        ],
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    banner("Verdict")
    print(f"  {verdict}")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)} ({out['runtime_s']:.0f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
