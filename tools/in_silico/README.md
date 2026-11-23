# `tools/in_silico/` — Zero-Lab Computational Stack

This directory hosts the **Python-based simulation environment** for the in-silico models of the node's hardware —
anchor mechanics, the capsule's thermal envelope, the stem's radio shadow, winter PV, the point dendrometer, wind and
the synthetic-sap recipe (`67`); in-silico as HIL and its TRL boundary —
[`docs/00_03_TRL_Matrix_HIL_and_Beyond.md §3.6`](../../docs/00_03_TRL_Matrix_HIL_and_Beyond.md).

SSOT artifacts (results, per-script status) live in
`docs/protocols/ebfc/in_silico/`. Scripts live in `scripts/` here.

## Scripts in `scripts/` (ordered)

> **Inventory only** (what each script does + cost). Per-script **status + result numbers** live in
> [`SUMMARY.md`](../../docs/protocols/ebfc/in_silico/SUMMARY.md) (results) and
> [`PIPELINE_STATUS.md`](../../docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md) (status) — this table
> links there, it does **not** mirror the numbers (SSOT One-Home; the mirror was a drift source).

| # | Script | What it does | Cost |
|---|--------|--------------|------|
| 01 | `01_smoke_test_water_box.py` | Engine sanity check — load protein (N-terminal tail dropped), water box, 1000 steps | ~70 s CI |
| 50 | `50_thermal_stress_lame.py` | HW.3 anchor: Lamé thermal stress + Findley creep | ~1 s |
| 51 | `51_gusak_degradation_model.py` | HW.3 anchor: Arrhenius aging + Kirkendall V/Al/Nb/Zr diffusion (Nb, Zr on a placeholder D) + H7/s6 window | ~1 s |
| 52 | `52_z_stack_tolerance.py` | HW.8.7 anchor: 2-spring blind-mate Z-stack tolerance (pogo, O-ring) | ~1 s |
| 54 | `54_anchor_thermal_bridge.py` | HW.34 anchor: central bus thermal bridge through the PEEK break (Cu vs Ti-monolithic) | ~1 s |
| 55 | `55_bus_mechanical.py` | HW.34 anchor: bus rod buckling + sway fatigue (supported-by-liner vs bare, per alloy) | ~1 s |
| 56 | `56_unified_press_fit_lame.py` | HW.3.IS anchor: unified thick-wall Lamé — combined thermal + press-fit (SF 5.6×) | ~1 s |
| 57 | `57_gdl_breakthrough.py` | HW.25 cathode: PTFE-GDL liquid-entry pressure (Young–Laplace) + O₂ diffusion budget; the rain/dew stand's positive-control aperture — the any-angle bound 4γ/(ρgh) and the margin of the sheet's punch | < 1 s |
| 58 | `58_thermal_install_field.py` | HW.6 install: 2D axisymmetric thermal field → cambium safety + generator for the 1D orphan cache | ~13 min |
| 59 | `59_contact_endurance_check.py` | HW.43: endurance-limit literature review for the three contact/elastic parts (pogo spring, genipin matrix, PEEK barbs) — closed form, no FEA; the question is the acceptance unit | < 1 s |
| 62 | `62_wind_duty_cycle.py` | HW.43: wind duty-cycle for the Cherkasy pine forest from the committed NASA POWER record (daily WS10M) — bounds the trunk-sway cycle count | < 1 s |
| 63 | `63_delta_t_aux_power_sensitivity.py` | HW.42: does a second (TEG) power source on the shared BQ25570 rail contaminate `delta_t` — closed-form P_aux 10-200 µW sensitivity bracket | ~1 s |
| 64 | `64_teg_across_peek_break.py` | HW.21: may a Bi₂Te₃ TEG be mounted ACROSS the Zone-2 PEEK break instead of glued to bark — imports script 54's ladder + a `G_TEG` branch, thermal gate vs own Seebeck output | ~2 s |
| 66 | `66_gyroid_ligament_thickness.py` | HW.33: thinnest printed feature of a gyroid per topology (sheet vs network) at fixed porosity → minimum printable period | ~2 min |
| 67 | `67_sap_recipe_saturation.py` | HW.3: calcium oxalate saturation of the `01_02 §2.1` synthetic sap — corner scan per test band, admissible Ca × oxalate window on a constant-free hard bound, base and buffer prices; the live pine point (Q7) and the broadleaf point (Q8, beech trunk-base sap transcribed from Glavac 1990 and its nitrate from Glavac & Jochheim 1993, with oak's own *Q. rubra* reading and two crown-twig readings — Soper 2018, Schneider 1996) | ~14 s |
| 68 | `68_bus_contact_equilibrium.py` | HW.34 / HW.23: bus rod in the cathode channel solved as unilateral contact (FE + active set) — where the wall is met under pogo drag, and what a channel off the root axis costs, swept over the Zone-1 insertion placeholder and lock window | ~10 s |
| 71 | `71_capsule_thermal_envelope.py` | HW.37: the hottest hour of a Soldier capsule under its PEEK radome over 30 ERA5 hourly Cherkasy years (lumped balance; α swept — the finish is specified as α ≤ 0.5 since 2026-09-27, `02_01 §5.2`; this sweep is its first basis, the cambium under the flange (`78`) the second) against the EDLC operating rating, the temperature the EDLC ages at (life via `51`'s kernel) and the cold hours under its floor | ~9 s |
| 73 | `73_collar_wall_inversion.py` | HW.33: what wall the bayonet collar needs — by INVERSION, because the retention FORCE has no home in canon (02_02 §4.1 lists requirements without one, and the 100 N in `lib.constants`, shared with `52`, is a deliberately generous BOUND, not a measurement). Three load cases: collar ring in axial tension · lug-root shear · CONFINED ICE at its self-limiting ceiling (ice I/III/liquid triple point). Verdict: static does not size the wall (printability does — ⊕ 2026-10-13: at the nominal squeeze; at the window top `88` asks more, a conditional root-package member, and `89` grows it with the loop's stiffness), ice does — and not by thickness, so drainage is the only lever | ~1 s |
| 74 | `74_site_rain_dew.py` | HW.25 + HW.6: site climate of the Cherkasy ERA5 grid point 1991–2020 — wet-day share and wet-day intensity, dew nights and hours (air criterion) for the rain/dew stand, and the dates at which published xylogenesis thresholds (soil 3.5 °C, air 8–9 °C) are crossed SUSTAINEDLY (a winter thaw is not spring, a warm wave after weeks of cold is not the end of the season), for the install season; an orientation and an input, never a stand regime or a window | ~1 s |
| 77 | `77_anchor_torque_path.py` | HW.26: the torque path onto the anchor's OWN axis — the measurement that decided the anti-rotation fork `01_01 §4.3` C on its wind ground. Analytic: stem bending puts no rotation gradient along a radial anchor, stem TORSION does (ω_r = −½·r·φ′), and against the rigid-inclusion turning stiffness 4πGa² the wood modulus cancels; inverted for the stem-surface torsional shear stress τ_s* at which the shank↔sleeve press-fit slips (Lamé P_c from `lib.mechanics`, relaxed, at 20 °C and +40 °C; μ bracketed — unmeasured). Q2 estimates the demand at its CAP (green shear strength, Wood Handbook 2010 pines — species means, directions declared): the slip at the shank surface at the centroids and its peak at the sleeve's bark end (the sleeve's torsional decay length on wood, a few mm, says it follows its local wood), the rigid-part demand (compliant parts lower it), and the clearance below which a hex key would engage, beside the PEEK↔Ti swing of that clearance. Reads the CEM manifests and `55`'s lock window; writes `cache/mechanical/anchor_torque_path.json` | ~1 s |
| 78 | `78_flange_cambium_heat.py` | HW.6: the flange → cambium path under the flange ring Ø15–Ø29.8 since the 2026-10-03 seat on faced dead bark. 1D Crank–Nicolson column (dead bark → phloem → sapwood; layer properties and the cambium gate from `58`) driven by `71`'s hourly capsule temperature — recomputed with `71`'s own code (importlib) and checked against `capsule_envelope.json` — over `71`'s α sweep, both of its cases and two winds; a closed-form scheme check (24 h wave on a half-space) runs first. Inverts the finish α and the dead-bark floor at which the cambium reaches the gate, at `71`'s nominal h_c and again at its h_c × 0.7 reading (the `h_c_x0_7` block, checked against `71`'s cached sensitivity rows). Writes `cache/thermal/flange_cambium_heat.json` | ~5 min |
| 79 | `79_flange_cambium_frost.py` | HW.6: the frost half of the flange → cambium path. `78`'s grid with a surface energy balance in place of an imposed temperature — convection (`71`'s Churchill–Bernstein and Churchill–Chu, called with |ΔT|; a vertical-plate Churchill–Chu for the stem), long-wave exchange with a clear (Brutsaert 1975 from the ERA5 dew point) or overcast sky, and optionally ERA5 diffuse sun — stepped fully implicit (Crank–Nicolson rings on a balanced surface half-cell), one banded factor per bark side shared through Sherman–Morrison; runtime gates: a step against Incropera eq. 5.60, a diurnal wave against Crank–Nicolson, the substep count against 6× on the coldest real window and on three beam windows, and over the whole 30-year series against 3× (Richardson). Sky × sun × coupling ends; reports the daily-minimum shift against bark without the flange, a mechanism block and three sensitivities; ⊕ a real-cloud block (2026-10-12) — ERA5 hourly cover from `data/era5_cherkasy/hourly_cloud_1991_2020.csv.gz` mixing the sky ends through two long-wave forms, with a month-by-month split; ⊕ a beam block (2026-10-14) — ERA5 DNI on a trunk face swept over eight azimuths through NOAA GML's solar position, the data clock checked against the DNI itself, hours of cambium above ≈ 13 °C counted beside the shift; ⊕ ground-reflected light (2026-10-18) riding with the beam — snow on the ground from `data/era5_cherkasy/hourly_snow_era5_land_1991_2020.csv.gz` and `hourly_snow_cerra_1991_2020.csv.gz` checked against the GHCN Lubny station file, albedo from Baker et al. (a mean and a sample cutoff), two ends of the input. Writes `cache/thermal/flange_cambium_frost.json` | ≈ 6.4 h beside a DFT Hessian (16 substeps/h, 2026-10-18); alone not re-measured |
| 82 | `82_collar_running_clearance.py` | HW.33 · HW.9 root package (crown-pause exception, ⚖️ 2026-10-05): the radial running clearance of the bayonet collar in the radome's socket band — the member `52` §collar_radial_budget has no number for. Reads `73` (interface Ø), `52` (chain, print floor), `71` (capsule requirement) and `81` (cold edge); thermal closing with the PEEK band outside the Ti collar (isothermal, model edge, a gradient bound with the Ti at 20 °C, a CTE sensitivity), ISO 286 grades computed from the standard's formula, three manufacturing routes (ours) → design clearance and the board ceiling through `52`'s chain. Three controls (ISO table · the chain against `52`'s cache · the sign). Writes `cache/mechanical/collar_running_clearance.json` | < 1 s |
| 86 | `86_coaxiality_allocation.py` | HW.34: the channel-to-root coaxiality priced as a Soderberg MEAN stress over `68`'s and `55`'s caches — seam break-even `k` and wire SF per allowed offset, per alloy and geometry. Seconds, stdlib + caches. |
| 87 | `87_pogo_sway_transfer.py` | HW.43: how trunk sway reaches the pogo pins — the rim-friction condition (the O-ring reaction each clamp design needs; the reaction is `88`'s), the board stack's inertia as a force ratio and at a part-by-part mass estimate, and a mass-independent centre-pad Poisson ceiling per 1000 µε of stem strain; stem input from Schindler & Kolbe 2020 Fig. 9. Seconds; imports `52` and `55`, reads `52`'s and `77`'s caches and the radome CEM. |
| 88 | `88_oring_reaction_band.py` | HW.33 · HW.43: the O-ring's own compression reaction — Parker ORD 5700 Figure 2-4 (.070 section, 70 Shore A) transcribed from the PDF's vector paths, in the part of the bar Table 2-3 gives a ring under 1″, interpolated over `52`'s squeeze window on the seal length of the AS568-019 ring; against it `52`'s rim-clamp requirement between assembly and 20 years, `73`'s lug-root capacity (the share of its reaction the ring must lose, the squeeze at which a non-relaxing ring binds the lug, the collar wall strength asks, the share the ring must have lost by each year) and `87`'s two rim needs (assembly temperature only). Seconds; reads `52`'s, `73`'s and `87`'s caches. |
| 89 | `89_bayonet_thermal_clamp.py` | HW.33: the bayonet clamp over its interference tolerance and temperature — the collar wall as a function of the loop stiffness k (closed form; δ, Δα and temperature readings), the k each wall tolerates, the PEEK-only ceiling and the force-controlled limit; the consumer is the conditional root-package member «collar wall by strength». Seconds; imports `88` (`wall_for_force`), reads `52`'s, `73`'s, `82`'s, `88`'s and `71`'s caches and the radome CEM. |
| 90 | `90_pogo_thermal_gap.py` | HW.43: the pogo gap's thermal travel — the radome PEEK column minus the hanging board stack (lib CTEs: PEEK, FR-4 Z, steels) and, for the working stroke, the pin's brass body over its free length (C36000), the seasonal swing against `52`'s mitigations, and from `71`'s hourly capsule temperature the daily stroke, force ratio and radial slide (PEEK and FR-4 in-plane). ~1 s; imports `52` (pogo constants) and `71` (hourly capsule temperature, checked against its own cache), reads `52`'s, `82`'s and `71`'s caches and the radome CEM. |
| 91 | `91_liner_exit_contact.py` | HW.34 · HW.23: the liner's exit contact as an elastic-layer problem coupled to the rod, read over the drag cycle — PEEK layer on the rigid wire (plane-strain Navier kernel, bonded ⊥ frictionless base), Ti half-space (Love), Polonsky–Keer on a DC-FFT, the rod through the exact Mohr flexibility of `55`'s piecewise EI, a pad couple, lumped contact friction (loading and unloading), each figure beside a rigid wall at the same edge. Controls (kernel limits and table · padding · Hertz · thin-layer Winkler asymptote · Mohr ⊥ FE touchdown · rigid limit = `68` · rigid point ⊥ LCP at a rounded edge · the pad couple ⊥ 68 (d) · the peak on the rigid touchdown value · the smallest radius's edge peak at two steps · the in-layer sharp edge's ρ^(−½) growth). Imports `55`, reads `68`'s and `55`'s caches. Writes `cache/mechanical/liner_exit_contact.json` | ~15 min (two threads) |
| 92 | `92_liner_mouth_contact.py` | HW.34 · HW.23: the liner at the channel mouth under an axis offset — `91`'s kernels and rod with two patches (mouth and exit), a Newton on the rod's pose per window; controls against `68`'s tables, `91`'s exit row and edge peaks, and the rigid limit; the static edge peak (offset × entry radius, two or three square grids); the mouth-edge peak over the drag CYCLE on three Zone-3 shanks at 50–100 µm and the exit-edge peak over the cycle by exit radius (coaxial and at the ⌀0.10 limit), in parallel workers; the beam's swing on the rigid same-edge model, dense in offset, with the elastic correction where cheap and the entry radius's effect; base/modulus brackets; the shank sweep. `--resummarise` re-derives the summary from the cached rows. Writes `cache/mechanical/liner_mouth_contact.json` | ~2 h on 2 workers beside a DFT |
| 97 | `97_wire_under_liner_edges.py` | HW.34: the bus wire under the liner's edges — `92`'s contact pressure carried through the PEEK layer onto an elastic Ti half-space (bonded ⊥ frictionless base), added to the wire's nominal bending along `92`'s drag path, read on `86`'s Soderberg line (drawn wire at the stations, the welded root with its seam `k`); `--summary-only` re-derives the verdict from a written cache, no solve. Writes `cache/mechanical/wire_under_liner_edges.json` | ~1 h (CPU, two workers) |
| 98 | `98_field_strain_campaign.py` | HW.43: the field strain campaign's length from the 30-year hourly ERA5 10 m wind (`71`'s loader, fixed UTC+3) — per month the hours per day at Beaufort 4 / 5 and the hourly p99, the Beaufort-5 storms and the years without one, and the replay of every start month over each of the 30 years to 10 h at ≥ 8 m/s (median / p75 / p90 as actual years); battery trips (installation, swaps, removal) for two strain sensors and one tilt sensor on one receiver (power from the TreeMMoSys primaries, checked against their 152 h); the battery type for the ratified set — AGM ⊥ LiFePO4 over the capped December campaign with the ERA5 2 m air (discharge floors, AGM freezing for 10 … 14-day swaps and every first-swap day, humidity, battery days and trips on the makers' cold readings, swap calendars). Writes `cache/mechanical/field_strain_campaign.json` | seconds |
| 101 | `101_bus_torsion_budget.py` | HW.26: elastic twist angle of the welded bus wire to first surface yield over the weld-root → liner-grip run (`55`'s spans), per alloy, von Mises ⊥ Tresca and liner slipping ⊥ sharing the torque; the wire's yield torque against the liner tube's torsional first yield and grip (`55`, nominal and creep-relaxed) with the wire yield at which that order flips, and the wind's rotation and torque at the sleeve's bark end (`77`); second-route control. Writes `cache/mechanical/bus_torsion_budget.json` | seconds |
| 102 | `102_wire_liner_shear_lag.py` | HW.43: the bus wire in its press-fitted PEEK liner as a shear-lag pair with Coulomb slip — root axial force and centre-pad travel vs the share of `87`'s sway shift and the sleeve's thermal growth, per `55` tolerance part and μ; `86`'s seam requirement on them, `90`'s L1 margins against the pad; independent FE control. Writes `cache/mechanical/wire_liner_shear_lag.json` | seconds |
| 103 | `103_anchor_wood_share.py` | HW.43: the share of the stem's radial shift the wood imposes on the anchor per bond state (anode free · anode bonded with the sleeve free below the bark · a rigid callus tie of the sleeve with the bark bearing), on one three-node solver; the bark bearing's stiffness and the tie's depth as axes, with the bearing at which each state-2 conclusion is reached at both ends of the bond bracket, the tie depth at which each mature-state one is reached with no bearing, and the span's lowest effective CTE against the pad travel's sign change; the seam on `102`'s closed form with its hot preload; all of it twice — the flange located by the bark, and by a rigid Zone-3 fit (the shank's run as Ti bonded to PEEK), the reduction checked against a chain of short elements; and per premise the (CTE, share) front `104` reads. Writes `cache/mechanical/anchor_wood_share.json` | seconds |
| 104 | `104_pad_travel_remedies.py` | HW.43: the prices of the remedies for the centre pad's thermal travel — how far it passes `90`'s L1 margin on both of `102`'s spans over every grip (the Zone-3 shank bonded on 18 mm), held and with the sway on top (`103`'s (CTE, share) front), and what each remedy buys: the PEEK run's length or effective CTE (bisected to close the need), a longer pin stroke, a smaller `52` residual (bayonet hard-stop · CNC tolerance class · spacer step · their combination); the seam's hot preload and `86`'s requirement with `103`'s sway corners; the need's sensitivity to the placeholder shank; controls hold `102`'s pad travel, `102`/`103`'s seam requirements, `90`'s residuals and `55`'s geometry. Writes `cache/mechanical/pad_travel_remedies.json` | seconds |
| 105 | `105_printed_part_sway_stress.py` | HW.23: the cyclic stress the stem's sway puts into the anchor's titanium parts, path by path (the full path list with each one's status is in the cache): an energy LOWER bound on the bonded gyroid's ligament stress — strain-controlled, so σ_e/E_s is the alloy's figure of merit at t_L = 1 (the share is `106`'s) — given as the stem surface strain above which it alone reaches SF 2 per alloy, FE reading (per axis the claim-adverse end of the [finest unlocked ⊥ finest locked] finest-step bracket over the pinned sweep and the HW.23 re-sweep — `read_fe`, one home; the lower one, which a binding claim takes, is the radial one — `00_07` HW.23), stress-state reading and sensor reference; the anode's bond force and the bearing force from `103`'s closed forms (held to its cached caps on its own grid); the nominal stress, K_f at SF 2 per cycle reading and route, and the mean at SF 2 in the Zone 1 and Zone 3 shanks, barbs and the flange disc (an annular Kirchhoff plate in `103`'s state 2, held to an independent FD solve); the junction's mismatch and the mass path; beside the bound, never inside it, the periodic voxel case's uniaxial-state READING of the ligament peak (two stress measures and two quantiles named, the lowest peak over rungs × measures, the highest threshold over the sampled angles, every knife-edge). Writes `cache/mechanical/printed_part_sway_stress.json` | ~1 s |
| 106 | `106_gyroid_wood_strain_share.py` | HW.23: the share t_L of the wood's in-plane strain the bonded gyroid takes — an orthotropic Eshelby circular cylinder (Mura's integral) in Scots pine sapwood on Güntekin & Akar 2019's measured constants (four moisture groups, three symmetrisation readings, the non-positive-definite ones excluded) and, as a separate group, on green sets of four other Pinaceae (Davies 2016 Table 2 ⊥ its raw ESM means, Liu 2019 P4, Jeong 2026's red and Korean pine on the stiffer-axis reading with G_RT borrowed for both and red pine's ν_RT too — ours), the lattice's C11/C12 from `105`'s two voxel-FE ratios (per axis the claim-adverse end of the finest-step bracket — `00_07` HW.23) read as one homogeneous cubic body, C44 swept to Voigt's ceiling and read apart from the periodic voxel case (three named readings), the install angle and three pore readings (bare lattice ⊥ additive ⊥ Voigt phase bound) swept; the Zener ratio at which t_L crosses 1, the moisture counts per reading, the θ = 0 share range and `105`'s binds-above strains at its lowest (the tensor's own E[100] ⊥ `105`'s radial reading; which of them is `105`'s lower one is read from its cache) for the Scots pine group and for the union, each green set's own verdict, the consumer's ceilings with their citations, and the off-axis threshold factor and modulus under the same tensor. Controls: isotropic cylinder, Lekhnitskii's hole, covariance under a rotation, Goodier's inclusion; each green transcription against its source's own aggregate, G_LR/G_RT out of the share, Jeong's borrowed ν_RT at θ = 0. Writes `cache/mechanical/gyroid_wood_strain_share.json` | ~7 s |
| 107 | `107_stem_radio_shadow.py` | HW.6: the stem's own radio shadow at 868 MHz — the exact two-dimensional cylindrical-wave series for a line source beside a layered lossy stem (heartwood · sapwood · bark, one admittance recursion), both polarizations (an electric line along the stem ⊥ a line of dipoles tangential to the bark) as a bracket; the field with the tree against the same source current (exact in the horizontal plane for a short dipole or a small loop along an infinite stem) and at equal input power (a 2-D indicator of the near-field loss); stems from lib `DBH_MIN_CM` to `DBH_MAX_CM`, the RF deck's standoff from `52`'s stack rows and the flange CEM, the carrier from the firmware's PHY header, sixteen permittivity readings (Mavrovic 2018 in situ L-band, its Fig. S2 profile, Bieker & Rust 2010's and Björklund 1999's sapwood widths, named dry ⊥ wet ⊥ «phloem» proxies for the bark — the last a balsam-fir trunk bark interpolated to 868 MHz off its figure, «phloem-dominated» our hypothesis — and a dry proxy for the heartwood). Controls: free space, lossless, the energy balance on every row against the interior volume integral, truncation, and the bark figure's interpolation (the «phloem» rows re-run at six alternative A.36 readings — controls on the figure's interpolation — the floors they give). Three sweeps over the resonant axes — the sapwood width (2.2–13.6 cm), the stem's diameter (38–60 cm, the bark derived per stem; a probe to 90 cm under three bark assumptions) and the dead bark (canon's thin to thick end, TM «phloem»; the loss at ±50° on the floor rows, their A.36 spans, a refinement around both floors, the floor row's deck sensitivity and a probe past the thick end) — each with an identity control against the rows it extends, the standoff's monotonicity counted per polarization. Writes `cache/radio/stem_radio_shadow.json` | ~20–40 min, load-dependent |
| 81 | `81_capsule_cold_edge_sky.py` | HW.37: the cold edge `71` leaves open. `71`'s isolated lump hourly over the ERA5 record with `79`'s sky term (Brutsaert clear sky from the ERA5 dew point ⊥ overcast), natural convection called with |ΔT|, long-wave at full T⁴, solved per hour by vectorised bisection with the air returned EXACTLY where no gain meets no deficit (ERA5 air sits ON the floor in 0.1 K steps). Sky × sun × wind ends; four controls (`79`'s reference hour · overcast without sun = the air on every hour · the air count = `71`'s · an unbroken hourly clock). Reports hours, days and the longest spell below the EDLC floor, hours below the capsule requirement and the coldest hour per run, the edges selected from the runs, and ERA5's own sunshine share (WMO DNI threshold) and wind on the cold days against the whole winter. Writes `cache/thermal/capsule_cold_edge_sky.json` | ~5 s |
| 108 | `108_gyroid_interface_contact_map.py` | HW.23: `106`'s bonded gyroid interface read as a contact pressed by a growth pressure and held by friction — the exact interface traction σᴵ·n of `106`'s Eshelby solution (σᴵ recomputed with `106`'s own functions, every share of both of `106`'s wood groups reproduced first; a `106` group it does not read stops the run) split into normal and in-plane shear, the friction it needs (the tangent to the shifted Mohr circle), where it opens and the p₀ needed to keep it closed (a lower bound on a smooth envelope, a demand elsewhere), per cell at θ = 0 and over `106`'s install-angle × Zener grid, per group (Scots pine ⊥ green ⊥ union) over all cells and over the bare lattice alone (the only cells a smooth envelope is consistent with), against two named readings of root growth pressure (Bruder 1998) at the source day's strain from `105`; both consumers' cells from `106`'s consumer blocks (the junction with its published-sets-only companion) and `105`'s axial bond force over the envelope; what excluding the 2.5 MPa costs; a sha256 of the `106`, `105` and CEM fields read. Controls: `106`'s cells, Goodier's isotropic traction with shear, the Mohr identity, the tangent maximum against a brute force, the axial shear's symmetry zero, the groups read. Writes `cache/mechanical/gyroid_interface_contact_map.json` | ~8 s |
| 110 | `110_winter_pv_autonomy.py` | HW.54: the effective aperture A_eff = η_pv · T · A below which a PV cell on the dome cannot keep the EDLC from emptying over ERA5 1991–2020 (`71`'s hourly loader; `79`'s sun, faces, reflected ends and its sun and clock gates) — per demand (the Standby sleep, cadence C, STOP2 at cadence C) and per corner of the bands the canon carries (capacitance tolerance, VBAT_OV and OK_PROG worst-case bands, the wake-energy bracket; the boost at its plateau's top ⊥ the EBFC anchors' least efficient curve) plus §9.3's leak illustration; vertical open faces and two closed-stand forms; bisected, floored; ten controls, each with what it can and cannot catch | ~40 s |
| 111 | `111_pv_window_thermal.py` | HW.54: a dark PV window in the radome's crown — `71`'s capsule lump and `78`'s cambium column (imported) under a two-zone dome in `71`'s worst-orientation construction, the window at α_c (1.00 the bound, 0.90 ours), the rest at α 0.50, h_c at `71`'s two readings for the capsule and the cambium; per `110`'s named areas (cell outlines ⊥ windows), plus the largest dark aperture that keeps the cambium under its gate on a grid over the crown, floored; the two-zone term against a brute force over the beam angle, plumbing identities against `71`'s and `78`'s cached rows | ~5 min |
| 114 | `114_dendrometer_support_budget.py` | HW.54 Р3(в): a point dendrometer with the anchor as its support — the support's thermal artefact per fixation point (`103`'s sections), the bark bearing's share, the magnetic scale behind the wall (period, remanence, the Hall sensor's error terms, server-side unwrap), the period cap the sensor's linear range sets and the magnet families meeting the need there (a canon mirror), the scale-thickness knob in a block of its own, the magnet's temperature (the need at the hottest hour, the cap at the coldest, the class minima's (23 ± 5) °C band) with each family × thickness gap limit and the thickness limit at 3 mm SOLVED (ferrite isothermally), «holds» with the unwrap floor, the class-spread sensitivity (the class minima hold only for magnets ≥ 5 mm — every thinner verdict is read outside that, named), the sensor table (2026-11-16: TI rows transcribed per datasheet section, the offset and axis-mismatch drift summed in one verdict, each branch where its band's field is weakest, the base row reproducing the offset-only verdict, the levers — the gap held at 10 mm and the mismatch factor that flips 3 mm — and the sensors not read named as gaps), the energy of a read on the verdict lane, the travel window along the tilted axis (the one home of the oblique cut `119` reads; `71`'s ERA5 loader · `78` · `81` · `110` · radome and flange CEMs); its controls each say what they can and cannot catch | seconds |
| 115 | `115_pv_face_snow_frost_azimuth.py` | HW.54 Р3(б): snow and hoarfrost on the dome's PV face and the azimuth the gateway sets — `110`'s fields, lanes, harvest arm and bisection (imported) on covered fields at cadence C; four named readings of the cover named by how they are built (a ceiling, melt only, a vapour budget with NREL's slide rate via pvlib `coverage_nrel` on our wet-snow events, a favourable end) with their order measured on every threshold; the longest covered runs against `110`'s autonomy; the best face within ±50° of each gateway bearing; four controls, each with what it can and cannot catch | ~1.5 min |
| 116 | `116_countersink_ring_and_exit.py` | HW.34: the countersunk exit — the clearance a PEEK ring's bore needs over the channel so it never bears (rigid band over offsets, plays and the pogo couple + the measured elastic increment), the exit radius's floor over the tolerance offset (elastic end points on the adverse corner and `92`'s frame, every play × couple at the floor, cycles to verify, interior offsets), and what the depth costs the rod (coaxial cycle and slide on `91`'s path, the seam `k` on `86`'s formula); (d) the ratified exit radius run through the floor's own procedure on every depth; `92`'s solve carried to a depth and a couple, unchanged at zero | ≈ 1¾ h on 8 workers |
| 117 | `117_stem_face_cover_rules_rehearsal.py` | HW.54 Р3(б)(4): the stem-face light sheet's cover rules (§6 pp. 1–4) rehearsed on ERA5 1991–2020 December–February before the logger — the candidate days and the share of days the rules as written and a rejected draft rewrite can judge against a base of cover-free days (judgeability is necessary, not an acceptance test), the event days the season's ceiling loses with CERRA (it ends June 2021), and an upper bound on the overcast bare-ground hours an adverse R for `110` could stand on (`79`'s weather and snow · `110`'s irradiance · `115`'s ice saturation); ⊕ 2026-11-15 the rules rewritten that day on a PERFECT logger — the south face under no cover, each `115` reading, three hybrids and three dry readings (`115`'s `cover_readings`, a private instance for the dry window), the base, runs and misses of `124` (imported; its cache gives the Poisson bar), a log-normal day noise over 10 seeds and σ 0–1.2 | < 1 min |
| 118 | `118_stem_face_cover_power.py` | HW.54 Р3(б)(4): how often one season of one south-face logger can tell the four `115` cover readings apart, on a perfect logger (the truth's cover known hour by hour, the base exact) — per pair, reflection end and winter, under three readings of the coverage test (lenient · strict · runs) and the sheet's count test, with a per-day noise term on the lenient one; a measured power per test, not a ceiling on every rule; reuses `115`'s `cover_readings` | ~16 s |
| 119 | `119_bark_overgrowth_consumers.py` | HW.54: what the stem's outward growth passes on the radome and when (rim · vent hole · RF deck · crown, from the radome's manifest, `52`'s deck rows, `78`'s facing spread and `114`'s rate and bearing-share brackets), the far field of the antenna plane once it lies under the surface (reciprocity on `107`'s solve, both polarizations, sixteen readings, the overgrown stem solved per depth — checked against the embedded source's own boundary-value problem), the share of an isotropic field a disc keeps at the bottom of a straight pit, and the allowance that keeps the lowest opening clear, as a flange thickness and as a raised stack; reuses `107`'s solver and readings | ~1 min |
| 120 | `120_sky_longwave_product.py` | HW.6: which cloudy-sky long-wave form the winter sky follows — `79`'s two forms and its clear-sky formula against NASA POWER's hourly surface flux (`data/power_cherkasy_longwave/`, 2001–2020), and `79`'s frost half re-run under that sky in three named readings; imports `79` (its `simulate`, columns, thresholds) and feeds the product's sky through an effective dew point, so `79` is neither edited nor re-run | ~30 min on two cores |
| 121 | `121_cold_edge_station.py` | HW.37: whether the reanalysis the cold edge stands on runs warm on cold nights — ERA5's and MERRA-2's daily minima against two non-overlapping records of the Cherkasy synoptic station (`data/station_cherkasy/`), conditioned three ways over three day windows, and the cold edge and cold hours from both reanalyses; stdlib only | seconds |
| 122 | `122_capsule_cold_edge_second_reading.py` | HW.37: `81`'s deep cold edge of the capsule (isolated lump, no sun, still air) on MERRA-2's hourly air under three readings of the sky (Brutsaert's formula · CERES SYN1deg clear-sky · all-sky flux) and on ERA5's, each beside `71`'s ×0.7 reading of its still-air kernel, and at every daily minimum before the hourly record, against the EDLC floor and the capsule requirement; on the days that fall below it — the sky ratio, the wind and the station row the same files carry; imports `81`, `120`, `121` | under a minute |
| 123 | `123_wind_reanalyses_station.py` | HW.43: which reanalysis of the 10 m wind the Cherkasy station sits nearer to — the station's daily mean and daily maximum wind (GSOD 1991–1998, `data/station_cherkasy/`) against ERA5's hourly and MERRA-2's daily and hourly series, the gap at Beaufort 5 conditioned on the station, on the reanalysis and on neither, and the Beaufort-5 hours of the campaign seasons from both; reads its thresholds from `62`'s and `98`'s caches, stdlib only. Writes `cache/mechanical/wind_reanalyses_station.json` | seconds |
| 124 | `124_stem_face_second_sky.py` | HW.54 Р3(б)(4), stage 1: the stem-face light logger under a SECOND sky and a second air — the south face lit by ERA5 + α · (CERES SYN1deg − ERA5) (NASA POWER hourly, `data/power_cherkasy_shortwave/`; α 0 · 1/√2 · 1), the truth's and the analyst's cover on ERA5's or MERRA-2's air (`data/power_cherkasy_longwave/`; its humidity column as a dew point and as a frost point, `120`'s conversion), judged against ERA5's GHI with the base the record itself offers; per world, reflection end, truth (none · the four `115` readings) and dip threshold: the false runs of a cover-free face, the false and not-proven-false rejections of each reading over 19 winters, how a season ends, and the seasonal R between the two skies; readings, not bounds; reuses `115`'s `cover_readings` and `118`'s run rule; ⊕ the rule of two airs — the same records judged on ERA5's air, on the logger's (the truth's air ± a constant offset, and a yard warmed by 1–2 K) and on both | ~2.5 min |
| 125 | `125_stem_face_courtyard.py` | HW.54 Р3(б)(4): the stem-face logger in a courtyard open to one side — three walls at their own distances and the opening's edges, read by eye off the founder's satellite image of the court (two readings of the plan, side by side); the share of the same face's open winter light that reaches a south face and a face turned to the opening (beam past the roof line, sky-diffuse through the face's sky view, ground-reflected from the yard's own light); ERA5's sky and the CERES SYN1deg product's (`124`'s loader); brackets on the plan (roof · scale · edges, the eastern edge alone, the trunk moved in the fixed building); a neighbour's stem as an opaque strip; a level horizon inside the opening (0–60°) with the building's share given it, a screen in one half of the opening; the hours the sun is first seen from the trunk; controls through the yard function and a second ray–segment implementation | ~45 s |
| 126 | `126_liner_wall_axial_stress.py` | HW.34: the bus liner's wall under the axial path, a first-order cabinet check — the wall's mean and amplitude (`102`'s root force over the tube's section) per bond state of `103` (both premises), alloy and corner, against PEEK's fatigue readings (the anchor at two named R readings; Victrex 450G at R 0.1; all carried to R −1) and against its short-term strength and 23 °C creep at two warm-edge temperatures (the hot preload rebuilt by `102`'s forms); the shares at which each axis switches on, the holding force below which a capture keeps each reading off the wall, the retained modulus that takes the hot preload under the warm-edge yield, the cold edge; `102`'s grid reproduced as a control. Writes `cache/mechanical/liner_wall_axial_stress.json` | seconds |
| 127 | `127_bonded_liner_end_corner.py` | HW.34: the bus wire at the liner's end — a semi-analytical axisymmetric FE (Fourier modes 0/1, Q9 elements graded to the corner) of the Ø1.0 wire and the 0.15 mm layer stopping square, in frictionless contact, with a Coulomb full-slip end zone, or bonded; the sway's bending, the bore's interference and the thermal mismatch with the axial misfit locked at T_g ⊥ the assembly; the two-wedge Williams order of the bonded corner; the end's Soderberg SF against `97`'s governing sections per distance from the corner; controls against closed forms, a refined mesh and the argument principle. Writes `cache/mechanical/bonded_liner_end_corner.json` | ≈ 8 min |
| 128 | `128_collar_lug_sway_fatigue.py` | HW.23: the bayonet collar's foot and the lug root of the Zone 3 flange under the sway — the collar as a thin cylinder whose foot the bending disc turns (on `105`'s plate and bearing forces; plate readings: `105`'s uniform · with the O-ring groove · grooved on a compliant root), FOLLOW ⊥ COUPLED through the foot's energy stiffness; the lug's sway force (the capsule's inertia and drag, and the clamp loop's length change × an unknown loop stiffness); two named readings of the clamp's eccentric bending at the lug root; Soderberg in `105`'s form; controls against `105`'s cache, a piecewise closed-form plate, the shell's semi-infinite limits and finite differences. Writes `cache/mechanical/collar_lug_sway_fatigue.json` | ≈ 1 min |
| 129 | `129_inclusion_strain_ligament_field.py` | HW.23: the gyroid's ligament field under the inclusion's OWN multiaxial strain — `106` exports the Eshelby ε_I per cell into the lattice's cube frame (`cache/mechanical/gyroid_inclusion_strain_cases.json`), `fea --periodic --strain-cases` superposes the rung's six unit solutions under it (tools/cad `periodic_strain_fields.*`), and `129` reads the peak per unit far-field strain, the binding surface strain per alloy (empty-pore fill ⊥ filled fills), the factor R over `105`'s uniaxial peak and the source day; controls against the ladder's tensor, the energy identity and the export. Writes `cache/mechanical/inclusion_strain_ligament_field.json` | seconds (after the C# run, ≈ 10 min) |

Numeric prefixes are one shared namespace: 01 is the CI engine smoke test; from 50 up, lab-gated desk models tied to
the tracker item each row names. Rows are listed in execution order.

## CI gate

`.github/workflows/in_silico_smoke.yml` has three working jobs, all gated by its `changes`
paths-filter (the path list lives in the workflow, not here):

- **`lock_sync`** — fail-fast: `conda-lock.yml` must still match `environment.yml`
  (`conda-lock --check-input-hash` + `git diff`). Edit `environment.yml` without
  regenerating the lock and this job fails (see *Adding a new dependency* below).
- **`smoke`** — runs `01_smoke_test_water_box.py` with `SILKEN_FORCE_PLATFORM=CPU`
  (deterministic on hosted runners), in the env built from the **pinned**
  `conda-lock.yml`. Cached by `mamba-org/setup-micromamba@v3` keyed on the lock
  hash, so cold runs take ~10 min, cached runs ~3 min.
- **`cache_doc_sync`** — no conda env: hash-pinned pytest on the runner's `python3`, running
  `test_doc_cache_sync.py` plus the unit test whose import chain is stdlib-only
  (`test_unified_lame.py`). A test that imports numpy
  belongs in `smoke`, not here — run it under a bare `python3` before adding it.

> **Why the lock (resolved 2026-06-04):** `environment.yml` uses `>=` specifiers,
> so a bare `conda env create` picks the latest compatible build each solve — a
> breaking transitive conda-forge release could red CI on code nobody touched and,
> worse, silently shift the numbers behind a TRL-evidence run. The committed
> `conda-lock.yml` pins exact versions + hashes per platform (`linux-64` +
> `osx-arm64`) → bit-reproducible envs. Repo-wide pin-policy home:
> [`docs/03_01_Firmware_Lifecycle_and_DMA.md §12.5`](../../docs/03_01_Firmware_Lifecycle_and_DMA.md).

## The smoke test's input structure (AlphaFold 3)

`01_smoke_test_water_box.py` loads an AlphaFold 3 Server prediction of deglycosylated FAD-GDH
(dgrGcGDH from *Glomerella cingulata*) with its FAD cofactor, stored in
`docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb`; the server job — its request, the five models,
their confidences and the output terms of use — is kept in `docs/protocols/ebfc/in_silico/alphafold3/`.

1. Go to [AlphaFold 3 Server](https://alphafoldserver.com/) and sign in
   with a Google account (free for academic/non-commercial use).
2. Take the dgr-mutant sequence from the job request in `alphafold3/` (UniProt **G8E4B5**,
   FAD-GDH *G. cingulata*, 600 aa, its 11 N-X-S/T sequons mutated N→Q).
3. Create a new AF3 job:
   - **Protein**: paste the dgr-mutant sequence (600 aa, monomer)
   - **Ligand**: add FAD (CCD code `FAD`)
4. Submit and wait (~5 min). Download the top-ranked PDB → `dgrGcGDH_AF3.pdb`.

## Quickstart (one-time setup)

```bash
# 1. Install Miniforge (conda-forge native arm64 builds)
curl -L -o /tmp/Miniforge3.sh \
  "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh"
bash /tmp/Miniforge3.sh -b -p "$HOME/miniforge3"
"$HOME/miniforge3/bin/conda" init zsh
# → restart shell, or `source ~/.zshrc`

# 2. Create the project env from spec
conda env create -f tools/in_silico/environment.yml

# 3. Activate
conda activate silken_md

# 4. Verify
python -m openmm.testInstallation
```

## Reproducible install (pinned lock)

`conda env create -f environment.yml` (above) re-solves and grabs the latest
compatible builds — fine for day-to-day dev. For the **exact** env CI uses, install
from the committed `conda-lock.yml` instead — a REPRODUCTION env, not the one the
numbers came from: that is the recorded env, `environment.computed.explicit.txt`
(PySCF 2.11.0, while the lock resolves 2.13.1 — paper §2.7). ⛔ On the machine whose
`silken_md` is that record, install the lock under its own name (`silken_lock`), never
over it (`00_07` OPS.22). Needs `conda-lock` once (`pipx install conda-lock`, or
`conda install -n base -c conda-forge conda-lock`):

```bash
conda-lock install -n silken_lock tools/in_silico/conda-lock.yml
```

`environment.yml` stays the human-editable source; `conda-lock.yml` is the
generated pinned artifact (versions + hashes, `linux-64` + `osx-arm64`). Pin
rationale: `docs/03_01 §12.5`.

## Daily use

```bash
conda activate silken_md
python tools/in_silico/scripts/<script>.py
```

## Linting (`ruff`)

Python style/bug linter — аналог RuboCop для Ruby-боку. Конфіг: root `ruff.toml`
(спільний з `tools/ml/`). Standalone, conda не потрібна. CI-гейт: `ci.yml › python_lint`.

```bash
pip install ruff       # one-time
ruff check .           # лінт
ruff check . --fix     # + безпечні авто-фікси
```

## Python version policy

Pinned to **Python 3.12** in `environment.yml`. This is the highest version
with full conda-forge coverage for the L2-L4 stack as of 2026-Q2
(`openmm 8.3+`, `pdbfixer`, `mdtraj`, `pyscf`, `scipy/numpy`). When 3.13 ships
stable builds for all dependencies, bump and refresh `environment.yml`.

## GPU notes (macOS arm64)

OpenMM ships four platforms: `Reference`, `CPU`, `OpenCL`, `CUDA`. On Apple
Silicon **`OpenCL` is the GPU platform to use** — despite Apple's "deprecated"
label, OpenMM 8.x runs on the Apple GPU through it. **Verified on this project:**
our L2 production MD (467k-atom system) auto-selects `OpenCL` and sustains
**~10–11 ns/day** on the M-series GPU. `CUDA` is Nvidia-only; `CPU`/`Reference`
are ~10–20× slower and reserved for CI determinism and tiny sanity runs.

Scripts auto-select the fastest available platform; force one with
`SILKEN_FORCE_PLATFORM=CPU` (CI uses this for reproducibility).

**This means**: the Mac (OpenCL) handles development **and** the short-to-medium
production runs we actually do (single MD trajectories up to ~10 ns ≈ a day).
Reach for cloud GPU only for **large/parallel campaigns** (100+ ns, or many
trajectories at once) per `docs/01_03 §3.4`:

- GCP `g2-standard-12` (1× L4) — ~$1–2/h
- AWS `g5.2xlarge` (1× A10G) — ~$1.20/h
- AWS `p5.2xlarge` (1× H100) — ~$30/h (heavy MD only)

## Adding a new dependency

1. Edit `environment.yml`, append under `dependencies:`.
2. Regenerate the lock (re-solves both platforms):
   ```bash
   conda-lock lock -f tools/in_silico/environment.yml \
     --lockfile tools/in_silico/conda-lock.yml -p linux-64 -p osx-arm64
   ```
3. Sync your local env to the new lock:
   `conda-lock install -n silken_md tools/in_silico/conda-lock.yml` — ⛔ where `silken_md`
   is the record, sync `silken_lock` instead (see *Reproducible install*).
4. Commit **both** `environment.yml` and `conda-lock.yml` (the `lock_sync` CI job
   fails if they drift apart).

Never `pip install` directly into the env without recording it in
`environment.yml` — that breaks reproducibility for the rest of the team
and the AI agents that consume this stack.

## Why not GROMACS / NAMD?

See `docs/01_03 §3.4` for the full rationale. TL;DR: OpenMM is Python-first,
so AI agents (Claude, Copilot) can generate runnable simulation scripts
end-to-end without us hand-writing GROMACS `.mdp` files.
