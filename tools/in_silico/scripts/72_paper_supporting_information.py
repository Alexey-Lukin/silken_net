#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""72 — Стаття 1 Supporting Information index, generated from the tree (no compute).

Renders `paper/10_supporting_information.md` — the SI the manuscript promises three times
(02_methods §2.5 «scripts in the Supporting Information» · §2.7 «the exact package list with
checksums is in the Supporting Information» · «scripts and golden reference outputs are provided as
Supporting Information») and 08_declarations «Data Availability»:

  S1  the RECORDED environment (explicit conda list, md5 per package) + the conda-lock (a reproduction, not a replay)
  S2  every script, shared-library module and test of the pipeline — sha256 + the first docstring line
  S3  every COMMITTED reference output under cache/ (the JSON/PNG the docs pin; trajectories are never committed)
  S4  committed input data (ERA5 · NASA POWER · CHEM.11 alignments)
  S5  coordinates — the AF3 model, its raw AF3 outputs, the ligand / cluster geometries, the deglycosylation script
  S6  the paper figures and the script that renders each
  S7  the reproduction recipe

Every row comes from `git ls-files` (committed bytes only — an untracked scratch file cannot leak in) and
carries a sha256, so the SI is a MANIFEST of the tree, not a prose description of it. Deterministic: sorted,
no timestamps — `test_paper_si_matches_its_generator` pins the rendered file exactly as 61's tables are pinned.
Re-run after ANY cache, script or figure change (in-silico §When Modifying #19) — the pin will tell you.

Run:  python tools/in_silico/scripts/72_paper_supporting_information.py                    # stdlib only, no env
      python tools/in_silico/scripts/72_paper_supporting_information.py --bundle out/si   # + copies + SHA256SUMS
      python tools/in_silico/scripts/72_paper_supporting_information.py --bundle out/si --zip   # + out/si.zip
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import PAPER_DIR, REPO_ROOT  # noqa: E402  (stdlib-only module: Path + numbers)

OUT_MD = PAPER_DIR / "10_supporting_information.md"
IN_SILICO = "docs/protocols/ebfc/in_silico"

# ── what the SI carries, as git pathspecs (committed bytes only) ──
ENV_SPECS = ["tools/in_silico/conda-lock.yml", "tools/in_silico/environment.yml",
             "tools/in_silico/environment.computed.explicit.txt", "tools/in_silico/requirements-*"]
CODE_SPECS = ["tools/in_silico/scripts/*.py", "tools/in_silico/lib/*.py", "tools/in_silico/tests/*.py"]
CACHE_SPECS = ["tools/in_silico/cache"]
DATA_SPECS = ["tools/in_silico/data"]
COORD_SPECS = [f"{IN_SILICO}/dgrGcGDH_AF3.pdb", f"{IN_SILICO}/deglycosylate.rb",
               f"{IN_SILICO}/alphafold3", f"{IN_SILICO}/ligands"]
FIG_SPECS = [f"{IN_SILICO}/paper/figures"]


def git_files(specs: list[str]) -> list[str]:
    """Committed files matching the pathspecs, repo-relative, sorted. Empty list if none."""
    out = subprocess.run(["git", "-C", str(REPO_ROOT), "ls-files", "--", *specs],
                         capture_output=True, text=True, check=True).stdout
    return sorted(line for line in out.splitlines() if line and not line.endswith("/.DS_Store"))


def sha256(rel: str) -> str:
    h = hashlib.sha256()
    with (REPO_ROOT / rel).open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def nbytes(rel: str) -> int:
    return (REPO_ROOT / rel).stat().st_size


def first_doc_line(rel: str) -> str:
    """First line of the module docstring — the roster's own words, never retyped here."""
    try:
        doc = ast.get_docstring(ast.parse((REPO_ROOT / rel).read_text(encoding="utf-8"))) or ""
    except SyntaxError:
        return "—"
    line = doc.strip().splitlines()[0].strip() if doc.strip() else "—"
    return line.replace("|", "\\|")


def figure_generators(fig_rel: str, scripts: list[str]) -> str:
    """Which committed script names this figure file — found by the literal, so a renamed figure goes «—»."""
    name = Path(fig_rel).name
    hits = [Path(s).name for s in scripts
            if name in (REPO_ROOT / s).read_text(encoding="utf-8", errors="replace")]
    return " · ".join(f"`{h}`" for h in hits) if hits else "—"


def table(rows: list[tuple[str, ...]], header: tuple[str, ...]) -> str:
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(lines)


def file_rows(files: list[str]) -> list[tuple[str, str, str]]:
    return [(f"`{f}`", f"`{sha256(f)}`", f"{nbytes(f):,}") for f in files]


def build() -> str:
    env = git_files(ENV_SPECS)
    code = git_files(CODE_SPECS)
    caches = git_files(CACHE_SPECS)
    data = git_files(DATA_SPECS)
    coords = git_files(COORD_SPECS)
    figs = git_files(FIG_SPECS)
    scripts = [c for c in code if c.startswith("tools/in_silico/scripts/")]
    everything = env + code + caches + data + coords + figs
    total = sum(nbytes(f) for f in everything)

    parts: list[str] = []
    parts.append("# Supporting Information — Стаття 1 (generated manifest)\n")
    parts.append(
        "> **Generated by `tools/in_silico/scripts/72_paper_supporting_information.py` — do not hand-edit; "
        "re-run the script after any cache, script or figure change** (the pin `test_paper_si_matches_its_generator` "
        "reds a hand edit or a stale copy). Every row is a COMMITTED file of this repository with its SHA-256, so a "
        "reviewer can check that the artefact they hold is the one the manuscript's numbers came from. "
        "Result numbers themselves live in [`SUMMARY.md`](../SUMMARY.md) (One-Home) and are pinned to these caches "
        "by `tools/in_silico/tests/test_doc_cache_sync.py`; this file carries no number of its own.\n>\n"
        "> **Honesty line (mirrors Methods §2.7):** the numbers were computed in the RECORDED environment of S1 "
        "(PySCF 2.11.0 · geomeTRIC 1.1 · Python 3.12); the conda-lock beside it was generated later and resolves "
        "PySCF 2.13.1, so a re-run under the lock is a reproduction attempt, not a replay. The committed caches "
        "(S3) ARE the reported results — re-running a DFT script writes a new cache and is a new measurement.\n>\n"
        f"> Files in this manifest: {len(everything)} · {total:,} bytes. Bundle for upload: "
        "`python tools/in_silico/scripts/72_paper_supporting_information.py --bundle out/si --zip`.\n"
    )

    parts.append("## S1. Recorded computational environment\n")
    parts.append(
        "`environment.computed.explicit.txt` is the conda `--explicit --md5` export of the environment every "
        "committed cache was computed in — one URL + md5 per package; its header names the pip-installed helpers "
        "that are not inputs to any result. `conda-lock.yml` is the maintained lock (reproduction). "
        "`environment.yml` / `requirements-*` are the human-facing specs the lock was solved from.\n")
    parts.append(table(file_rows(env), ("File", "SHA-256", "Bytes")) + "\n")

    parts.append("## S2. Scripts, shared library and tests\n")
    parts.append(
        "Numbered scripts are listed in pipeline order (the numeric prefix encodes the DAG — "
        "[`README`](../../../../../tools/in_silico/README.md) is the inventory with costs, "
        "[`PIPELINE_STATUS`](../PIPELINE_STATUS.md) the per-script status). The description column is each "
        "module's own first docstring line.\n")
    parts.append(table([(f"`{f}`", f"`{sha256(f)}`", first_doc_line(f)) for f in code],
                       ("Module", "SHA-256", "What it does (first docstring line)")) + "\n")

    parts.append("## S3. Reference outputs — the committed caches\n")
    parts.append(
        "Every JSON is written by exactly one owner script (in-silico rule «one cache per model»); the PNGs beside "
        "them are the scripts' own diagnostic plots. Trajectories (`cache/runs/`) are not committed — only their "
        "JSON summaries are. `test_cache_integrity.py` pins the internal consistency of these files; "
        "`test_doc_cache_sync.py` pins every headline number in SUMMARY / L3 / the paper to them.\n")
    by_dir: dict[str, list[str]] = {}
    for c in caches:
        by_dir.setdefault(str(Path(c).parent), []).append(c)
    for d in sorted(by_dir):
        parts.append(f"### `{d}/`\n")
        parts.append(table(file_rows(by_dir[d]), ("File", "SHA-256", "Bytes")) + "\n")

    parts.append("## S4. Committed input data\n")
    parts.append(
        "External records the desk models read at run time (climate reanalysis, wind, homolog alignments). "
        "Their provenance (query, date, licence) is stated in the README beside each set, not here.\n")
    parts.append(table(file_rows(data), ("File", "SHA-256", "Bytes")) + "\n")

    parts.append("## S5. Coordinates\n")
    parts.append(
        "`dgrGcGDH_AF3.pdb` is the aglycosylated FAD-GDH·FAD model every L1/L2/L3 number stands on (eleven N→Q, "
        "Methods §2.1); `alphafold3/` holds the raw AlphaFold 3 job outputs it was derived from; `ligands/` holds "
        "the RDKit/MMFF94s ligand geometries, the Os-mediator octahedra (speciation and Hammett series), the "
        "lumiflavin redox pair and the ZIF cluster models (`*.xyz`, `*.sdf`); `deglycosylate.rb` is the sequon "
        "mutation script. ⚠️ **Licence carve-out:** the AlphaFold 3 outputs are distributed under the AlphaFold 3 "
        "Output Terms of Use (`alphafold3/terms_of_use.md`, mirrored in the repository `/NOTICE`) and are "
        "EXCLUDED from the CC-BY-SA licence that covers the rest of this documentation.\n")
    parts.append(table(file_rows(coords), ("File", "SHA-256", "Bytes")) + "\n")

    parts.append("## S6. Figures\n")
    parts.append(
        "Rendered from the committed caches (and the PDB for Fig 2) by the scripts named; a figure whose renderer "
        "no longer names it prints «—». PNG bytes are not portable across matplotlib builds, so the pin here is "
        "the SHA of the COMMITTED file, not a re-render.\n")
    parts.append(table([(f"`{f}`", f"`{sha256(f)}`", figure_generators(f, scripts)) for f in figs],
                       ("File", "SHA-256", "Rendered by")) + "\n")

    parts.append("## S7. Reproduction recipe\n")
    parts.append(
        "```bash\n"
        "# 1. the recorded environment (osx-arm64) — a REPLAY of the exact package set\n"
        "conda create -n silken_md_replay --file tools/in_silico/environment.computed.explicit.txt\n"
        "# 2. the maintained lock — a REPRODUCTION attempt (PySCF 2.13.1 ≠ the 2.11.0 the caches came from)\n"
        "conda-lock install -n silken_md_lock tools/in_silico/conda-lock.yml\n"
        "# 3. the pins: every headline number in SUMMARY / L3 / the paper equals its owner cache\n"
        "cd tools/in_silico && python -m pytest tests -q\n"
        "# 4. the paper assets, from the caches only (no DFT): figures · tables · this manifest\n"
        "python scripts/60_paper_figures.py && python scripts/61_paper_tables.py && "
        "python scripts/72_paper_supporting_information.py\n"
        "# 5. a re-run of any numbered DFT/MD script writes a NEW cache — compare it to the committed one field by field\n"
        "```\n\n"
        "A verified SHA-256 of every file above is what makes step 3 meaningful: the pins prove the docs match "
        "the caches, this manifest proves the caches are the committed bytes.\n")
    return "\n".join(parts)


def bundle(out_dir: Path, make_zip: bool) -> None:
    """Copy the SI file set into `out_dir` (repo-relative paths kept) + SHA256SUMS + this manifest; optional zip."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    files = (git_files(ENV_SPECS) + git_files(CODE_SPECS) + git_files(CACHE_SPECS) + git_files(DATA_SPECS)
             + git_files(COORD_SPECS) + git_files(FIG_SPECS))
    sums = []
    for rel in files:
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO_ROOT / rel, dst)
        sums.append(f"{sha256(rel)}  {rel}")
    (out_dir / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
    (out_dir / OUT_MD.name).write_text(build(), encoding="utf-8")
    print(f"bundle: {len(files)} files → {out_dir}")
    if make_zip:
        archive = shutil.make_archive(str(out_dir), "zip", root_dir=out_dir.parent, base_dir=out_dir.name)
        print(f"zip: {archive}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bundle", metavar="DIR", help="copy the SI file set + SHA256SUMS + manifest into DIR")
    ap.add_argument("--zip", action="store_true", help="with --bundle: also write DIR.zip")
    args = ap.parse_args()
    md = build()
    OUT_MD.write_text(md, encoding="utf-8")
    print(f"wrote {OUT_MD.relative_to(REPO_ROOT)} ({len(md):,} chars)")
    if args.bundle:
        bundle(Path(args.bundle), args.zip)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
