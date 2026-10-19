# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared utility functions for the in-silico pipeline."""
from __future__ import annotations

import os
import time


def banner(msg: str) -> None:
    """Print timestamped banner (flush for background jobs)."""
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def repo_relative(path) -> str:
    """A path as a cache records it: relative to the repo root. The files a cache points at (Hessians) sit under the
    gitignored `cache/runs/`, so they are this machine's alone; an absolute path only adds the machine's home to the
    cache and to the paper-SI bundle (`72`). A path outside the repo — a test's `tmp_path`, or a rehearsal directory
    (`32b --rehearse`, `96 --rehearse`) given outside it — keeps its file name alone: such a record is never committed."""
    from pathlib import Path

    from .constants import REPO_ROOT
    p = Path(path).resolve()
    return p.relative_to(REPO_ROOT).as_posix() if p.is_relative_to(REPO_ROOT) else p.name


def ps_to_steps(ps: float, timestep_fs: float = 2.0) -> int:
    """Convert picoseconds to integration steps."""
    return round(ps * 1000.0 / timestep_fs)


def pick_platform() -> Platform:  # noqa: F821 — lazy import below (str annotation via __future__)
    """Pick fastest available OpenMM platform, respecting SILKEN_FORCE_PLATFORM.

    OpenMM is imported lazily here so banner()/ps_to_steps() stay import-safe in pure-Python
    scripts (the anchor-mechanics tolerance/Lamé tools) that have no MD/conda env.
    """
    import openmm
    from openmm import Platform

    forced = os.environ.get("SILKEN_FORCE_PLATFORM")
    if forced:
        return Platform.getPlatformByName(forced)
    for name in ("CUDA", "OpenCL", "CPU", "Reference"):
        try:
            return Platform.getPlatformByName(name)
        except openmm.OpenMMException:
            continue
    raise RuntimeError("No OpenMM platform available")
