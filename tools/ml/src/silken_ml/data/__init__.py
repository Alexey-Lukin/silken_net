"""Dataset loading / splits / manifest — SCAFFOLD (no dataset yet).

Enterprise conventions to honour when this lands (deliberately documented now so
the first real dataset slots in without re-litigating process):

  - Audio lives under ``data/raw/`` (gitignored). A COMMITTED ``data/manifest.json``
    pins the corpus: per-file ``sha256`` + source + license + label. A model is
    then reproducible from its manifest hash, not a mutable folder.
  - Deterministic, STRATIFIED train/val/test split (seeded). Split indices are
    saved with the run — never re-derived ad hoc (that silently leaks).
  - First target corpus: the Cherkasy Soundscape Library (dawn/dusk), ``docs/03_03
    §10``; field partners UNI.11 (ЧДТУ ПМКТ) + UNI.13a (ЧНУ Біо-хаб).

Until then the firmware front-end (``dsp``) is fully usable on synthetic frames.
"""

from __future__ import annotations


def load_manifest(*_args, **_kwargs):  # pragma: no cover - scaffold
    raise NotImplementedError("data module is a scaffold — see module docstring")
