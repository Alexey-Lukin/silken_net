# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared utility functions for the in-silico pipeline."""
from __future__ import annotations

import os
import time


def banner(msg: str) -> None:
    """Print timestamped banner (flush for background jobs)."""
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def pick_platform() -> Platform:  # noqa: F821 — lazy import below (str annotation via __future__)
    """Pick fastest available OpenMM platform, respecting SILKEN_FORCE_PLATFORM.

    OpenMM is imported lazily here so banner() stays import-safe in pure-Python
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
