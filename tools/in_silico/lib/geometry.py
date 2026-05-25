"""Shared geometry utilities for placing molecules in MD boxes."""
from __future__ import annotations

import numpy as np
import openmm
from openmm import Vec3
from openmm.unit import nanometer, kilojoule_per_mole


def positions_to_nm_array(positions) -> np.ndarray:
    """OpenMM positions Quantity → (N, 3) numpy array in nm."""
    val = positions.value_in_unit(nanometer)
    try:
        arr = np.asarray(val, dtype=float)
        if arr.ndim == 2 and arr.shape[1] == 3:
            return arr
    except (TypeError, ValueError):
        pass
    return np.array([[v.x, v.y, v.z] for v in val], dtype=float)


def place_on_sphere(
    modeller,
    template,
    n_copies: int,
    protein_center: np.ndarray,
    shell_radius: float,
    rng: np.random.Generator,
    offset: int = 0,
) -> None:
    """Place n_copies of a molecule on a Fibonacci sphere.

    Each ligand type should use its own offset range to avoid overlap:
    e.g. genipin offset=0, chitosan offset=N_GENIPIN, etc.
    The Fibonacci indices are computed per-type (i=0..n_copies-1) but
    shifted by offset for angular separation from other types.
    """
    t = template.to_topology().to_openmm()
    coords_nm = positions_to_nm_array(template.conformers[0].to_openmm())
    coords_nm -= coords_nm.mean(axis=0)

    total = n_copies + offset
    for i in range(n_copies):
        idx = i + offset
        phi = np.pi * (3.0 - np.sqrt(5.0)) * idx
        y = 1.0 - (idx / max(1, total - 1)) * 2.0 if total > 1 else 0.0
        r = np.sqrt(max(0.0, 1.0 - y * y))
        unit_vec = np.array([np.cos(phi) * r, y, np.sin(phi) * r])
        unit_vec += rng.normal(scale=0.02, size=3)

        translated = coords_nm + (protein_center + unit_vec * shell_radius)
        new_pos = [Vec3(*xyz) for xyz in translated] * nanometer
        modeller.add(t, new_pos)


def restraint_protein_heavy_atoms(system, positions, topology, k: float = 10.0):
    """Add harmonic position restraints on protein heavy atoms (NVT stage).

    Args:
        k: force constant in kJ/mol/nm² (default 10.0, literature range 1-50)

    Returns the CustomExternalForce so caller can release via setParameter("k", 0).
    """
    restraint = openmm.CustomExternalForce(
        "0.5*k*((x-x0)^2 + (y-y0)^2 + (z-z0)^2)"
    )
    restraint.addGlobalParameter("k", k * kilojoule_per_mole / nanometer**2)
    restraint.addPerParticleParameter("x0")
    restraint.addPerParticleParameter("y0")
    restraint.addPerParticleParameter("z0")

    standard_aa = {
        "ALA", "ARG", "ASN", "ASP", "CYS", "GLN", "GLU", "GLY", "HIS", "ILE",
        "LEU", "LYS", "MET", "PHE", "PRO", "SER", "THR", "TRP", "TYR", "VAL",
    }
    for atom in topology.atoms():
        if atom.residue.name not in standard_aa:
            continue
        if atom.element is None or atom.element.symbol == "H":
            continue
        pos = positions[atom.index]
        restraint.addParticle(atom.index, [pos.x, pos.y, pos.z])
    system.addForce(restraint)
    return restraint
