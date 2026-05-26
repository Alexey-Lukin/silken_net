---
name: scripts
description: "Skill for the Scripts area of silken_net. 108 symbols across 22 files."
---

# Scripts

108 symbols | 22 files | Cohesion: 97%

## When to Use

- Working with code in `tools/`
- Understanding how banner, ps_to_steps, pick_platform work
- Modifying scripts-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `tools/in_silico/scripts/21b_dft_os_bpy_full.py` | _plane_normal, build_cis_bpy, build_meimidazole, _align_bpy, _align_monodentate (+6) |
| `tools/in_silico/scripts/12_temperature_sweep_md.py` | banner, ps_to_steps, pick_platform, positions_to_nm_array, place_on_sphere (+3) |
| `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | banner, read_xyz, write_xyz, build_mol, build_mf (+3) |
| `tools/in_silico/scripts/23_build_zif_clusters.py` | banner, write_xyz, check_distances, main, build_meimidazole (+3) |
| `tools/in_silico/scripts/11_full_matrix_md.py` | banner, ps_to_steps, pick_platform, positions_to_nm_array, place_on_sphere (+2) |
| `tools/in_silico/scripts/21_dft_os_bipy_complex.py` | banner, build_nh3_at_position, build_os_complex, write_xyz, atoms_to_pyscf (+2) |
| `tools/in_silico/scripts/10_genipin_stability_md.py` | banner, ps_to_steps, pick_platform, positions_to_nm_array, restraint_protein_heavy_atoms (+1) |
| `tools/in_silico/scripts/13_psbma_diffusion_md.py` | banner, ps_to_steps, pick_platform, positions_to_nm_array, build_glucose (+1) |
| `tools/in_silico/scripts/20_dft_lumiflavin.py` | banner, build_mol_from_smiles, mol_to_pyscf_atoms, write_xyz, dft_singlepoint (+1) |
| `tools/in_silico/scripts/24_dft_hopping_integrals.py` | banner, read_xyz, build_mol, run_uks, marcus_rate (+1) |

## Entry Points

Start here when exploring this area:

- **`banner`** (Function) — `tools/in_silico/scripts/12_temperature_sweep_md.py:101`
- **`ps_to_steps`** (Function) — `tools/in_silico/scripts/12_temperature_sweep_md.py:105`
- **`pick_platform`** (Function) — `tools/in_silico/scripts/12_temperature_sweep_md.py:109`
- **`positions_to_nm_array`** (Function) — `tools/in_silico/scripts/12_temperature_sweep_md.py:121`
- **`place_on_sphere`** (Function) — `tools/in_silico/scripts/12_temperature_sweep_md.py:132`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `banner` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 101 |
| `ps_to_steps` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 105 |
| `pick_platform` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 109 |
| `positions_to_nm_array` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 121 |
| `place_on_sphere` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 132 |
| `restraint_protein_heavy_atoms` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 148 |
| `run_single_temperature` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 169 |
| `main` | Function | `tools/in_silico/scripts/12_temperature_sweep_md.py` | 297 |
| `banner` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 51 |
| `read_xyz` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 55 |
| `write_xyz` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 65 |
| `build_mol` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 72 |
| `build_mf` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 81 |
| `extract_frontier` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 93 |
| `os_n_distances` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 109 |
| `main` | Function | `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | 122 |
| `banner` | Function | `tools/in_silico/scripts/11_full_matrix_md.py` | 97 |
| `ps_to_steps` | Function | `tools/in_silico/scripts/11_full_matrix_md.py` | 101 |
| `pick_platform` | Function | `tools/in_silico/scripts/11_full_matrix_md.py` | 105 |
| `positions_to_nm_array` | Function | `tools/in_silico/scripts/11_full_matrix_md.py` | 117 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Main → _plane_normal` | cross_community | 4 |

## How to Explore

1. `gitnexus_context({name: "banner"})` — see callers and callees
2. `gitnexus_query({query: "scripts"})` — find related execution flows
3. Read key files listed above for implementation details
