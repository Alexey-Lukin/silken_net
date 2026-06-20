"""Shared utility functions for the in-silico pipeline."""
from __future__ import annotations

import os
import time


def banner(msg: str) -> None:
    """Print timestamped banner (flush for background jobs)."""
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


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
