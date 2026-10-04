# CHEM.11 — committed output of the Aggrescan3D run (and its provenance)

These files are the **output of a third-party tool**, committed because they are the measurement
that closed the open half of the `L1 §2` aggregation recipe — the half that gated the
**dgrFAD-GDH gene freeze** (`I401S` · `L80D` · `A70S` in Spec A of
[`ebfc_chem_rfq`](../../../../docs/protocols/procurement/ebfc_chem_rfq.md)). The reading of them is
`tools/in_silico/scripts/80_chem11_a3d_crosscheck.py`; its cache is
`tools/in_silico/cache/chemistry/chem11_a3d_crosscheck.json`.

> ⚠️ **LICENCE — these files are NOT under this repository's CC-BY-SA-4.0 grant.** Aggrescan3D is
> third-party software whose upstream texts disagree with each other (repository `LICENCE` = MIT;
> `setup.py` and PyPI metadata = «free for non-commercial users»). The posture, both readings, and
> the exclusion are in [`/NOTICE`](../../../../NOTICE), block «Aggrescan3D (standalone release)».
> Canon home of the result: [`L1 §2`](../../../../docs/protocols/ebfc/in_silico/L1_protein_architecture.md).

| File | What it is |
|---|---|
| `A3D.csv` | the measurement: A3D score per residue, 600 rows, chain A |
| `Aggrescan.log` | the tool's own log of the run (`-r` writes it), including the exact `freesasa` invocation |
| `config.ini` | the resolved options the run used — A3D writes this itself, so it is the command as the tool understood it |
| `uniprot_G8E4B5_features.json` | the **signal-peptide annotation artefact**, fetched 2026-10-04 from `rest.uniprot.org/uniprotkb/G8E4B5.json` (fields: accession · protein_name · organism_name · length · ft_signal · ft_chain · annotation_score · reviewed). Committed for the same reason `chem11_conservation/` commits its FASTAs: the Signal 1-16 / Chain 17-600 split is quoted **to the CRO** in Spec A, so the claim must have a carrier. ⚠️ It records `entryType: UniProtKB unreviewed (TrEMBL)`, `annotationScore 2.0` and `ECO:0000256` on both features — i.e. a rule-based prediction, not an experiment. |

## Provenance of the run

| | |
|---|---|
| **Date** | 2026-10-04 |
| **Permission** | ⚖️ founder 2026-10-03 — execution on this machine, each command confirmed, the first one showing the founder the licence texts (`L1 §2`, «Execution on this machine»). The licence step fired first and is recorded in `/NOTICE`. |
| **Package** | `Aggrescan3D` 1.0.2, sdist `Aggrescan3D-1.0.2.tar.gz`, uploaded 2019-01-31 |
| **sdist sha256** | `bc076dc999218041281a2bfadbca0ac390937373f8d90f7bc0c9cdd4ebc21d92` — taken from the PyPI JSON API and **verified against the downloaded file** before installation |
| **Install** | `pip install --no-deps --no-index <sdist>` into the environment below. `--no-deps` and `--no-index`: no network during installation, no dependency resolution — the three dependencies were already present. |
| **Environment** | `a3d_py27`, conda-forge, **outside every one of our locks** (it cannot be in them: the package is py2-only). Python 2.7.15 (osx-64 via Rosetta) · numpy 1.16.5 · matplotlib 2.2.5 · requests 2.25.1. Created 2026-10-03. |
| **Why py2** | measured 2026-10-02: the `aggrescan` entry point pulls `newRunJob` (implicit py2 relative imports, the `print` statement) and three core modules do not parse under py3; conda-forge ships Python 2.7.15 for osx-64 only. |
| **Command** | `aggrescan -i docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb -w <work_dir> -D 10 -v 4 -r` |
| **Mode** | **Static.** `-d` (dynamic / CABS-flex) NOT used · `-am` (automatic mutagenic optimisation) NOT used · `-m` / `-f` (FoldX) NOT used — as the recipe specifies. |
| **Aggregation distance** | `-D 10`, the tool's default |
| **Input** | `docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb`, sha256 `44f34e5af1d46c48d83a59e84e984a3c47fda8a07c6d9b709bf145753598a319` — the AF3 model of the **aglycosylated 11 N→Q mutant**, i.e. **without** the three compensations |
| **SASA engine** | the bundled `freesasa` 2.0.1, binary `freesasa_Darwin` (Mach-O x86_64), sha256 `a9a60dc486fbc1dd6114cdfedeaa5eebf772ae4041b263d18adf14e33dae6ed9`, called as `--resolution 100 folded.pdb --radii naccess --format pdb --format rsa`. It ships **prebuilt** in the sdist, so nothing was compiled. |
| **Network** | none during the run. The only network call in the package's core fetches RCSB **when the input is a 4-letter PDB code**; ours is a local file path. ⚠️ **Do not read `remote : True` in `config.ini` as a network flag** — it is A3D's `--remote`, whose documented effect is «redirects output to a Aggrescan.log file created in the working directory, turns off log coloring»; the name is misleading and that flag is precisely why the log exists to be committed. |
| **Determinism** | the run was **repeated on the identical input** and `A3D.csv` came back **byte-identical**. (Contrast script 69, whose pdbfixer step is non-deterministic and carries a measured 3.77 Å² noise floor.) |
| **`work_dir`** | a session scratchpad **outside the tree**. The run also writes `A.png`, `A.svg`, `output.pdb` (the scored structure) and a `tmp/` directory there; they are derivable from `A3D.csv` plus the input and are **not** committed. |

## ⚠️ What this output does NOT carry, named rather than implied

- 🔴 **`0.000` in `A3D.csv` is a SENTINEL, not a measurement.** A3D forces a residue's score to
  exactly `0.0` when its relative solvent accessibility is below 10 % (`min_surf` in
  `aggrescan/aggrescan_3d.py`). In this run **253 of 600 residues (42 %) carry that value, 161 of
  them hydrophobic by A3D's own matrix** — so a buried hydrophobic patch and «nothing here» print
  the identical number, in the same column, in the same format. Any consumer that takes a maximum,
  a minimum or a ranking over this file **must exclude those rows**; script 80 does, and counts
  them. The first reading of this very run did not, and it hid a real (if marginal) finding.
- **The matrix is signed and Gln is negative** (−1.1394), so an exposed Gln scores negative almost
  by construction. «A3D does not flag site X» is therefore a weak absence claim for all eleven
  deglycosylation sites, and script 80 reports it as one.
- **The cofactor is absent.** A3D read only `ATOM` records, so the FAD (53 `HETATM` rows of the
  input) was **silently dropped** — exposure near the flavin pocket is over-stated. The tool issued
  no warning about this; it was found by comparing atom counts.
- **The structure is the uncompensated mutant.** There is no A3D run on the compensated sequence;
  that would need an AF3 re-prediction, which `L1 §2` deliberately has not done.
- **The signal-peptide boundary is an automatic annotation.** UniProt `G8E4B5` gives Signal 1-16 /
  Chain 17-600 with evidence `ECO:0000256` (TrEMBL, annotationScore 2.0) — a rule-based prediction,
  not an experiment. It matters because residues 1-16 hold **13 of the 50** positively-scoring
  residues of the whole construct, i.e. the hottest stretch is the one secretion is supposed to
  remove; whether cleavage actually happens is a QC question (intact-mass MS, Spec A).
- **No aggregation prediction.** The score is a static single-molecule surface descriptor: no rate,
  no solubility, no critical concentration.
