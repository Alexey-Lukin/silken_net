#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""114 — whether a point dendrometer that uses the anchor as its support can hold its reading: the support's thermal
artefact per fixation point, the magnetic scale behind the capsule wall (its period, the sensor's error terms and the
unwrap margin through winter and outages), a table of sensors judged with their offset AND axis-mismatch drift in one
verdict, the energy of a read, and how soon the bark passes the capsule along the tilted axis (00_07 HW.54, the leg
«Р3(в) — дендрометр», its instrument plan of 2026-10-30; the sensor table and the tilt, 2026-11-16; TI's answer on the
drift-linearity rows, the Infineon row and the screen rows, 2026-11-17).

WHY. The desk leg of 2026-10-26 (01_03 §4 ⊕, (в)) left the principle standing and named the weakest links: the scale's
travel and geometry, the support's thermal path with PEEK in it («≈ 5–10× worse than < 0.3 µm/K of commercial frames» —
the collector's derivation, not re-read), a pole counter that must not lose its count across a winter swing «ten times
the seasonal one» and the outages of the same nights, and the energy of a read. This script turns each into a number
the tree can check, from inputs the tree already holds.

MODEL.
(1) THE SUPPORT'S THERMAL ARTEFACT. Depth z runs from the flange seat (0) into the stem. The anchor is held by the wood
    at a fixation depth z_f; the live bark the probe rests on lies z_t below the seat (the dead bark is cut away under
    the probe); the sensor sits h above the seat; the scale runs from the probe's tip up to the sensor. Under a uniform
    ΔT the reading moves, per kelvin, by
        A = ∫₀^{z_f} (α_w − α_anchor(z)) dz + (α_s − α_w)·z_t + (α_s − α_h)·h
    — the closure of the loop fixation → anchor → holder → scale → bark → wood → fixation (controls 1–2). A > 0 reads
    as growth on warming; A < 0 reads as shrinkage on warming and as swelling on cooling — at dawn, the coldest hour,
    which is when a stem rehydrates and when the zero-growth method credits new growth. The first term is the ANCHOR's,
    on `103`'s sections read from its cache: the PEEK sleeve over the span (under a Zone-3 fit only below the shank's
    composite run), then the Zone-1 shank in the sleeve's bottom, then the gyroid. The shank is read two ways: BONDED to
    the sleeve by its fit (`103`'s reading) and ON ITS SHOULDER — the fit slips (PEEK relaxes), the sleeve rests on the
    gyroid's shoulder, and the whole sleeve down to it is PEEK in the path: the adverse end for |A|. The other two terms
    are DESIGN terms (the scale's and the holder's material, the sensor's height); the base reading sets them to zero and
    the cache states their sensitivity. The anchor term cannot be designed away until the fixation is known: named
    points from a callus tie (`103`'s axis: from just under the flange down to the install-day cambium, the deepest it
    can sit — it climbs toward the flange as the stem grows, so A drifts year by year) to an anode bond along the
    gyroid; the depth at which |A| crosses the frames' 0.3 µm/K is solved exactly per reading.
    THE BARK BEARING is not a thermal term and not a point on this axis: a flange that bears on the dead bark ties the
    reference to the surface being measured. The flange then sits between two springs — the deep wood through the anode
    bond and the sleeve in series (1/k_A + 1/k_s) and the bark through the bearing (k_F) — so it follows a radial change
    of the bark by U = (1/k_A + 1/k_s)/(1/k_A + 1/k_s + 1/k_F), and the reading loses that fraction (U → 1 for a rigid
    bark: no measurement). Priced on `103`'s stiffnesses for premise (b), sway and slow (relaxed PEEK) — our reading of
    a growth push as a displacement source; under premise (a) the shank sits in clearance, so a rising bark can lift
    the flange off the sleeve and leave no reference at all (our reading — `103` does not model lift-off).
(2) THE SCALE BEHIND THE WALL. The sensor sits inside the capsule; the scale slides outside it, so the read gap g is
    at least the radome's wall. A periodically magnetised scale of period P, thickness t and remanence B_r gives, in our
    idealisation (sinusoidal magnetisation, infinite width), a field of amplitude B = (B_r/2)·(1 − e^{−kt})·e^{−kg},
    k = 2π/P, its two components in quadrature; a two-axis Hall sensor reads the phase by atan2, and a COMMON gain
    (with it the magnet's temperature coefficient) cancels. What does not cancel, per the sensor's datasheet:
      offset drift — δB on each component moves the reading by up to (P/2π)·√2·δB/B; the scan finds the period P*
        that minimises it at a gap (for t → ∞, P* = 2πg — control 3) and the cache gives the B_r a scale NEEDS for this
        term alone to stay within 0.3 µm/K, the field it then puts on the sensor against its linear range, and the
        two-channel samples a read needs for 1 µm of noise there (the angle's RMS noise is σ/B, so at the needed B_r it
        is σ·0.3 µm/(√2·δB) whatever the geometry);
      gain MISMATCH between the two axes — a static ε gives a cyclic error (P/2π)·(ε/2); the datasheet gives its drift
        «from 25 °C» over the operating range with no per-kelvin basis, so the cache prints the cyclic peak over that
        whole drift, and a per-kelvin figure only under a stated linear spread (to −40 ⊥ +125 °C — an assumed operating
        range, not among the rows read);
      ANGLE error — static and cyclic, P·AERR/360; calibrating it IN PLACE needs the scale to pass a full period, i.e. years of
        growth.
    Both pairs of axes are printed: X–Y (both axes in the field's plane, which needs the IC mounted edge-on) and X–Z
    (the IC flat on the board). The tables (2) · (2b) and the verdict (2c) read ONE sensor, the table's base row
    (TMAG5273A1 — `base_lanes`, a view of that row), with the offset term only; (2d) judges every row with the sum.
    THE SENSOR'S LINEAR RANGE caps the period: the field the offset term needs at the sensor
    is P·√2·δB/(2π·target) — the period alone sets it, not the magnet and not the thickness — so a period above
    P_cap = 2π·target·B_lin/(√2·δB) asks for a field the sensor cannot read linearly; each row prints, per range and
    drift, the best period inside the cap and the remanence needed THERE, and the magnet families with a class at or
    above it (`MAGNET_FAMILIES_BR_T`, a canon mirror). THE THICKNESS KNOB (2b): the same row at t 3 · 5 · 10 mm in a
    block of its own, with its remanence and period over the t 2 mm row's — a thicker scale lowers the remanence at a
    longer P*, and the longer P* raises the field needed and the angle and mismatch errors with it. THE MAGNET'S
    TEMPERATURE (2c): the coefficient of B_r cancels in the atan2 but not in the two absolute bounds, and they bind at
    opposite ends — with B_r(T) = B_r(T_ref)·(1 + α·(T − T_ref)), T_ref in the (23 ± 5) °C band the class minima hold
    at, the offset term's need holds at the HOTTEST hour (the field weakest), so a class minimum must reach
    need/(1 + α·ΔT_hot), and a period fixed for the batch must keep the weakest unit over it while the strongest, put on
    the sensor at the COLDEST hour, stays inside the range: the cap shrinks to P_cap·(1 + α·ΔT_hot)/(1 + α·ΔT_cold), per
    family (the coefficient is the family's) — with ΔT_hot from the unit meeting its minimum at the band's cold end and
    ΔT_cold from the one meeting it at the warm end, the band being a spread between units — and by a further 1/(1 + s)
    for a unit s above its minimum (printed for assumed s). A
    family holds a cell when its strongest class reaches the minimum, over a CONTINUOUS period inside that cap, of
    the hot-end need (the tables above scan a 0.01 mm grid); «holds with the unwrap floor» adds the period the unwrap
    needs across a season's outage and lets any class of the family's span be chosen. Each family × thickness gap
    limit and, at the 3 mm gap, each thickness limit are SOLVED, not read off the grid (§When Modifying #54), at two
    corners — kind (a uniform batch at 28 °C, the coefficient's smaller end, `78`'s α 0.5 hour, the record's coldest air)
    ⊥ adverse (the need at 18 °C and the cap at 28 °C, the larger end, `78`'s α 0.9 hour, `81`'s sky-cooled capsule edge
    that hour) — beside the isothermal solve; sintered ferrite, with no coefficient, isothermally, with its own floor list;
    and each cap against the period a TWO-month unwrap basis needs (the basis decides REFeB's adverse verdict). THE COUNT across periods: the device sends the phase, the server unwraps the series —
    nothing is persisted on the device (its RTC backup domain does not survive an outage on our board, 03_01). The
    unwrap holds while every change between two delivered readings stays under P/2 (an absolute-in-period phase; the
    collector's «half a pole» was for an incremental pole counter, a different reader); the change is priced on a
    declared, season-consistent basis and the period each basis requires and every geometry's margin are printed.
(2d) THE SENSOR TABLE (2026-11-16). `SENSORS` holds one row per device and linear range, each value transcribed from
    the primary datasheet its comment cites (section and table), each drift with its declared basis — a per-kelvin row ⊥
    a total from 25 °C the datasheet itself says scales linearly ⊥ a total with no ΔT, spread over the branch only by
    our assumption (`BRANCH_SPAN_K`, or a row's own `branch_span_K` where its band ends short of +125 °C) — the offset by the same two bases (a per-kelvin row ⊥ a total over the band) — per axis
    and per branch (cold 25 → −40 °C ⊥ hot 25 → +125 °C), typical and guaranteed columns (an empty column stays empty),
    lifetime drifts where given. THE COMBINATION RULE — the SUM: per branch, (P/2π)·δB_pair/B +
    (P/2π)·ε/2 ≤ 0.3 µm/K, the offset term with δB_pair = √(δa² + δb²) of the pair's axes and the mismatch term with ε the
    pair's mismatch drift per kelvin — a linear sum of two worst-case bounds of independent sources, as (7) of the list
    below asked (an RSS would be kinder and is not taken). Each branch binds where ITS band's field is weakest (the
    offset term divides by the field): the hot branch at the hottest hour, the cold branch at its warm end, 25 °C — at
    the cold edge itself the field is stronger; the range bound reads the coldest hour. So the cap generalises (2c)'s to
    min over branches of B*·T/(K + B*·c), and the need at P is the binding branch's 2·P·δB_pair/(2π·(T − P·ε/4π)·geom·f).
    The verdict lane: the guaranteed columns (the TMAG5273's typical mismatch, its only column, flagged). Per row and pair,
    on (2c)'s corners and families, at 3 and 4 mm: the thickness limit offset only (the base row's IS (2c)'s, a control)
    ⊥ with the mismatch term ⊥ with it and the unwrap floor; the levers — the gap held at a 10 mm scale, and the factor
    on the guaranteed mismatch drift at or below which an infinitely thick scale holds each gap (the flip threshold of
    the binding member, §When Modifying #40), beside the row's typical/guaranteed ratio; the read's energy on the verdict
    lane; the lifetime steps (not per kelvin, not summed). The support's term (1) is NOT in the sum — a maximum over
    unknown fixations. ANGLE (SATURATION) SENSORS: (2g) since 2026-11-17 (until then a named gap — the 2026-11-16 desk
    read mirrors and distributor copies only); sensors whose primaries give no guaranteed drift, or were not re-read,
    are named in `SENSOR_GAPS`, so «the table» is never read as «every sensor».
(2e) THE DRIFT-LINEARITY ROWS (2026-11-17). The TMAG3001's datasheet publishes SENSMS_DR_LIN · Boff_DR_LIN · SENSDRLER
    with a MAX column and no definition; TI's answer (case CS3699089, `DRIFT_LIN_DEFINITION`) defines them as the largest
    deviation of the drift curve from a best-fit line over −40…+125 °C («typically referenced to the 25 °C point» — a
    different line), in % of the nominal sensitivity, guaranteed, NOT per kelvin. So LIN bounds the residual's SIZE
    after a per-unit linear compensation, not its slope, and the frames' per-kelvin rule has no guaranteed reading from
    it. What is printed instead is the sum rule computed DIRECTLY on each reading of EACH member — the offset and the
    mismatch each raw (its guaranteed per-kelvin row, uncompensated) ⊥ compensated as a chord at the window's edge with
    the residual's change from 25 °C ≤ LIN (a line through the 25 °C point) ⊥ ≤ 2·LIN (the best-fit line) — the edge
    being the most favourable point (nearer 25 °C the same residual is a larger per-kelvin figure, without bound); the
    offset compensated only in OUR full-scale reading of Boff_DR_LIN (% of the verdict range — TI's stated reference
    gives no field for an offset); per row, pair, corner, family and gap, with and without the unwrap floor. The
    both-raw reading is the table's own verdict (a control). The sensitivity row is a common gain's and cancels.
    ⊕ 2026-11-18, TI's follow-up in the same case: Boff_DR_LIN is a % of the TOTAL offset drift over the full
    temperature range (their figure: the Boff_DR maximum times the span) — not of the range, not of the sensitivity —
    and its line is a best fit NOT held to the 25 °C point (from 25 °C the deviation is up to about twice LIN). So the
    offset has a fourth reading, `ti_total_drift` (k = 2 on that basis; the total drift in a number is OUR step from
    their words — the largest guaranteed per-kelvin maximum times the full operating span). TI's answer excludes a
    share of the full-scale range in so many words; OUR full-scale reading is kept beside it as the ADVERSE BOUND, not as
    a rival definition — the datasheet prints none, the two answers of the case name two bases (the nominal
    sensitivity, then the total drift), and the residual TI's reading leaves is far below the sensor's own noise — so a
    consumer takes the adverse one until the bench measures the residual. The offset's «from 25 °C» (k = 1) cells are a
    control since that answer: TI's line does not pass through 25 °C; the counts name them apart.
(2f) SCREEN ROWS (2026-11-17). `SCREEN_ROWS` — sensors whose primary gives the two drift bounds but whose read rows are
    settings-dependent (Melexis MLX90395, Allegro ALS31313) — are judged by the same sum rule, offset and mismatch, on
    every family, corner and gap, without levers or a read; each total is derived from the datasheet's own columns by
    a reading named in the row.
(2g) ANGLE ROWS (2026-11-17). `ANGLE_ROWS` — sensors that read the field's DIRECTION (TMR · AMR) in saturation: the
    field must exceed the row's minimum, its size drops out to first order, and the reading moves by P·δθ/360° (θ the
    field angle). So the frames cap the period from ABOVE, P ≤ 0.3 µm/K · 360°/δθ — the opposite of a Hall reading, whose
    offset term the field divides — while the unwrap floor (doubled for a 180° row) and the period at which the
    strongest class at the hottest hour saturates the row bound it from below, and the period above which the WEAKEST
    class, thick, at the coldest hour passes the row's field maximum closes it from above too (the classes between cover
    the window continuously). Each row reads the field in the plane of its die and the scale's field turns in the plane
    of the motion and the scale's normal, so the package stands edge-on to the wall: the row's OWN minimum gap is the
    wall plus the die's depth from the package's lead-free end (the shortest body the primary prints; the die centred
    where it says so, assumed where it does not) — cells at 3 · 4 mm carry `reachable`, and every row is also judged at
    its own minimum. No primary prints the angle drift per kelvin; each prints a SIZE over its span, or (KMZ60) a
    worst-case simulated curve after a 25 °C calibration, with TC compensation on ⊥ off, so δθ is read on a grid: the size
    — the limit as the change from 25 °C ⊥ the limit plus the 25 °C bound (the triangle bound; twice the limit where no
    25 °C row is printed) — × the spread — linearly to the band's ends ⊥ a chord at the corner's own hours; a curve at the
    corner's hours, in field degrees ⊥ in the bridge's doubled (electrical) degrees, and at its read tolerance. The members
    a row prints per kelvin alone (the TLE5501's offset coefficient over its weakest hot amplitude, the TAS2141's
    amplitude-synchronism coefficient as ε/2) are NECESSARY caps; the TLE5501's amplitude coefficient read per channel is
    printed as a REJECTED member (its span would move the angle further than the row's own limit). The static cyclic error
    (the 25 °C bound, else the row's limit) and the lifetime row (each an absolute size over the part's qualification
    stress, not the 20-year life) at the floored period stand beside, not per kelvin, not summed. No read is priced.
(2h) PACKAGE REACH (2026-11-17). The tables (2d) · (2e) judge the gap as given; a package cannot reach every gap. The
    X–Z pair reads with the package flat, its top to the wall — the gap is the wall plus the elements' depth under the top;
    the X–Y pair needs both axes in the plane of the motion and the scale's normal, so the package stands edge-on on its
    lead-free end — the wall plus the elements' distance from that end. `PACKAGE_REACH` takes both off the primaries'
    sensor-location figures and outlines, as an interval over the drawings' tolerances, with a holder's clearance zero;
    per row and pair it prints whether 3 · 4 mm are reachable (yes ⊥ no ⊥ within tolerance), which of (2d)'s and (2e)'s
    3 mm holds sit at a gap the package cannot reach, the best gap a 10 mm scale holds against the interval, what 3 mm
    leaves for a holder, and — for an X–Y pair that holds 3 mm — the package tilted end-on by β (`end_on_tilt`): the
    off-plane axis reads the normal component as sin β, its offset term grows by 1/sin β, and the gap shrinks to the top-
    end corner; the largest margin over β.
(3) THE ENERGY OF A READ. The read rides the node's existing wake (cadence C): the sensor's wake and measure transitions
    once, then N two-channel samples at its active current, N from the VERDICT lane (the guaranteed drift — a scale
    designed to it puts the stronger field on the sensor; to 2026-11-15 N was the maximum over the typ ⊥ max lanes, kept
    beside as `convention_to_2026_11_15`), with the core awake throughout at its run current (02_03
    §9.4's mruby member — a ceiling: the core could sleep through a conversion; the bus transfer is not in the tree),
    taken from VSTOR through the active buck. Printed against the node's demand (`110`'s) and E_CYCLE, beside an
    absolute encoder IC of 2 mm period at its power-up current and time with the core awake through it.
(4) THE TRAVEL WINDOW. Years until the live bark under the probe reaches the flange seat, and until the outer bark
    around the capsule reaches the dome's top (`Radome.cs`'s top over the rim, on the flange's top face), at the
    slowest and the fastest radial increment the desk leg names — along the TILTED axis: the seat is faced square to the
    anchor's axis at the install angle, so `78`'s facing spread is Ø·sin θ (θ recovered from those two raw numbers), the
    install-day bark stands spread/cos θ higher along the axis at the deep edge than at the shallow one, and a mark h
    along the axis is passed after a radial travel (h − b₀)·cos θ. This block is the ONE home of that oblique cut —
    `119` reads it; until 2026-11-16 it subtracted the radial spread from an axial height and carried no tilt.

INPUTS — each with its home: geometry, the anchor's α sections, the bearing's share and the green xylem's α (Sevanto et
al. 2005, P. sylvestris, radial) from `103`'s cache; the flange's and the cambium's hottest hour from `78`'s; the
capsule's sky-cooled cold edge from `81`'s; the B_r coefficients from 01_03 §4 ⊕ (в) (mirror below); the
radome's and the flange's dimensions from their CEMs; cadence C and the demand from `110`'s cache; E_CYCLE and the
active buck from lib; the core's run current and VOUT from 02_03 §9.4 (mirrors below); air temperature from the ERA5
hourly record `71` loads; the Hall sensors' rows from their datasheets (TI SLYS045C · SBASAF4 · SLYS053C, read
2026-11-16 — the section and table in each row's comment; SLYS045 first read 2026-10-31; Infineon TLE493D-P3B6 Rev.
1.0, Melexis MLX90395 Revision 6.0 and MLX90393 Revision 012, Allegro ALS31313 Rev. 9, read 2026-11-17), and TI's
definition of the drift-linearity rows (case CS3699089, 2026-11-17 — `DRIFT_LIN_DEFINITION`); the angle rows' from
their primaries (Infineon TLE5501 Rev. 1.0, TI TMAG6180-Q1 SLYS037A, TDK's TAS series catalog of November 2017, NXP
KMZ60 Rev. 2 Fig. 11 off the page image; MultiDimension TMR3004 · TMR3005 read and named a gap), read 2026-11-17; the encoder's, the frames' temperature sensitivity and the growth rates from the primaries the 2026-10-26
collection read (provenance: handoff `2026-10-26_r3v_dendrometer.json`); the frost swing, the daily swing and the radial
rate's ends from 01_03 §4 ⊕ (в).

WHAT IT CANNOT SEE.
  (1) Where the anchor is held — an axis of named points; a hold shared between bearing, tie and bond is priced only as
      the bearing's share in (1), not solved; and the bearing only with the anode bonded (before ingrowth the deep tie
      is the sleeve's grip, which `103` leaves unbounded). A hold shallower than the live bark sits in the dead bark, whose
      α is taken at the xylem's like the phloem's — and which follows the bark as the bearing does.
  (2) The temperatures. The model is uniform-ΔT and the µm figures use the AIR (ERA5) as a stem-interior proxy, NOT a
      bound: the top of the sleeve sits under the Ti flange, which in sun runs far above the air and at night radiates
      to the sky (`78`). Frozen wood's strain is not thermal expansion, so the seasonal figure uses unfrozen days only and
      the frost swing enters (2) as a travel.
  (3) The phloem and the callus at the xylem's α (no reading of either); α_xylem as one reading (the cache gives the
      sensitivity per ppm/K, the green-wood bracket in the collection is wide) — the anchor term's sign rests on it: the
      gyroid exceeds it by 0.7 ppm/K, the bonded Zone-1 composite by 1.5, the Zone-3 composite by 1.9. The design terms are nulled, not zero: their sign is the
      scale's and the holder's material, still open.
  (4) The field is an idealisation (finite width, pole-pitch errors, a ferromagnetic neighbour); the magnet is not
      chosen, so (2) gives the remanence a scale NEEDS, not one a product has; the families it is held against are a
      mirror of the canon's desk (specified minima per family, ferrite typical), not a product's datasheet, and «meets»
      says only that some class of the family reaches the need — not its corrosion or whether a scale of that class and
      thickness is made. The tables (2) and (2b) are ISOTHERMAL and read on the gap grid (GAPS_MM); the temperature
      and the solved limits are (2c)'s, and it cannot see: the SIZE validity of the minima — IEC 60404-8-1:2023 §5.2
      makes them valid only for magnets of at least 5 mm in all three directions and 0.125 cm³ («lower values … may be
      obtained» otherwise), so every verdict on a thinner scale, and poles of ≈ 5 mm, read the minima outside that
      validity, in the direction that makes them optimistic (a weaker class than a family's minimum, which an unread
      edition could add, would bring the wall's thick REFeB cells back under the unwrap floor); the scale's own temperature — the hot end is the flange's
      hottest hour (`78`, sunlit, still air, at α 0.5 ⊥ α 0.9; a shaded flange runs cooler — the break-even hour is
      printed) and the cold end the record's coldest air hour and `81`'s sky-cooled capsule edge that hour (a lump the
      capsule's size, not the scale); the coefficients' form — the 2001/AMD1:2004 tables give them as TYPICAL values for
      20 °C to 100 °C (Table 11 in English, Table 12's note in the preview's French), so below 20 °C it is our linear
      extrapolation; the spread of a unit above its class minimum
      (the standard sets no upper limit — printed for assumed spreads only); irreversible loss at the hot end — the
      strongest class has the lowest coercivity and a thin multipole scale works at a low permeance; the sensor's linear
      range held at its datasheet row at every temperature; the unwrap floor's basis (a season's outage over one growing
      month — our assumption, (2)). Sintered ferrite has no coefficient in the tree, so (2c) solves it isothermally. The
      family maxima are the 2001/AMD1:2004 minima the canon read; the 2015 and 2023 editions are unread past the 2023
      preview, which says only that «new and high-performance grades of REFeB and RE₂Co₁₇ sintered magnets» were added
      (it stops before Tables 12–13), so (2c) prints the need a class must reach, cell by cell. The base sensor's
      mismatch drift is a typical total with no ΔT (its per-kelvin figure stands on our linear spread), and its offset
      drift is one row for both ranges. (2d) cannot see: a guaranteed column is a bound over the population, not a unit;
      noise, current and timing rows the datasheet gives only at another range or supply (each row's `assumed`); the
      sensors not in the table (`SENSOR_GAPS`); the cyclic terms at the scale's own phase (the sum is at the worst phase);
      a drift given as a BAND over a span spread linearly over it (our assumption, `branch_span_K`) — the band may be
      reached anywhere inside, and at the window's own edge, nearer 25 °C than the band's end, the same band is a larger
      per-kelvin figure, so the spread reading is the favourable one — the levers print a less favourable chord
      reading too (`band_reached_at_the_window_edge`, the band that covers the edge reached there; not a ceiling — a band
      bounds the value, not the slope), and which reading the datasheet means it does not say.
      (2e) cannot see: whether TI's definition holds for
      the offset row (its stated reference gives no field), which of its two lines the rows mean, whether the drift
      repeats after cycling or holds for 20 years (not published — a calibrated slope's validity is unbounded), the
      chamber a −40…+125 °C line would need; and it is no guarantee in the per-kelvin sense at all. (2f)
      cannot see: a screen row's derivation of a total from absolute bounds (ours, named in the row), the read. (2g)
      cannot see: which reading a datasheet means (none says whether its limit is a change or an absolute error, nor how
      it grows inside the span); whether the «relative» error's reference line is re-set at each temperature (the TLE5501
      and the TMAG6180 measure the error from a line set symmetric to it — then a common shift of the zero is bounded by
      no reading at all); the members a row does not print (the TLE5501's mismatch and orthogonality drift, the TAS2141's
      offset drift, none of the TMAG6180's guaranteed); the error's dependence on the field inside the row's band (the
      TMAG6180's row is printed at 30 mT only, and B_r swings about 10 % over the hours); the field form's prefactor (½·B_r;
      an ideal alternating magnetisation's fundamental is (2/π)·B_r, 27 % stronger — conservative for saturation,
      optimistic for the field maximum); the die's position where a primary does not print it, and a holder's clearance
      (zero taken); a scale turned on edge behind the wall, whose field would lie in the plane of a FLAT package (not
      modelled); a real scale's harmonics; hysteresis under the daily swings' reversals (inside the TLE5501's limit, apart
      elsewhere); the read's energy.
      (2h) cannot see: a holder's clearance and the sub-board an edge-on package needs (zero taken — `budget_left_at_3mm_mm`
      is what 3 mm leaves for them and the scale's running clearance); mould flash (TI allows it, not added); the elements'
      positions where a figure gives no tolerance (TI's are single numbers; the TLE493D's Hall plane inside its hatched
      block); a package tilted towards a LEADED side (the lead form is not dimensioned — only the end-on tilt, body only, is
      priced); a virtual normal axis combined from two channels; the band read more favourably than linear (the Infineon
      row's held gap is its linear reading's); the best gap taken over the levers' corners and families only (kind ·
      adverse; REFeB · RE₂Co₁₇); static, calibratable offsets between the elements of one package; a scale turned on edge
      behind the wall (whose field a flat package's X–Y could read — not modelled).
  (5) Whether a scale and a probe can travel 16–100 mm past a flush capsule without a visit — the geometry (01_04
      §5.5); (4) says only when the problem starts.
  (6) Separating reversible shrinkage (TWD) from growth — the zero-growth method's job, not priced here.
  (7) The budget: the frames' 0.3 µm/K is the whole instrument's. (2d) sums the sensor's offset and mismatch terms
      (since 2026-11-16 — the sum this item named); the support's term (1) still prints against it alone, because it is
      a maximum over unknown fixations, not a property — what the instrument meets is that sum plus (1).

CONTROLS (each says what it CAN and CANNOT catch).
  (1) Closure: with one α everywhere A = 0 at every fixation depth, probe depth and sensor height; CAN catch a term with
      no partner, CANNOT a flipped or a dropped pair (that is (2)'s).
  (2) Unit impulses against the node positions derived independently: α_w = 1 alone → z_f − z_t; α_s = 1 → z_t + h;
      α_h = 1 → −h; α = 1 on one anchor section → −(its length above z_f); CAN catch a flipped, dropped or mis-weighted
      term, CANNOT a wrong section in `103`'s cache.
  (3) Sections: they tile the anchor from 0, end at `103`'s full depth, put the gyroid's centre on `103`'s nominal anode
      centroid, and carry, down to the shank's top, `103`'s PEEK length of the premise; CAN catch a misread length or a
      section dropped, CANNOT a swap of two sections that keeps the PEEK length (both readings come from one cache).
  (4) Field: for a very thick scale the scanned P* equals 2πg within the scan's step, and at the needed B_r the field
      equals P·√2·δB/(2π·target) by a separate route; CAN catch a slip in the exponent, its factor or the (1 − e^{−kt})
      term in either function, CANNOT an error in the idealised field form itself.
  (5) Energy: the same function and buck give lib's E_CYCLE from 02_03 §9.4's members; CAN catch a buck applied the
      wrong way or lib drifting from §9.4, CANNOT a wrong sensor current.
  (6) The ERA5 record has `110`'s hour count; CAN catch a truncated or a different file, CANNOT a shifted clock.
  (7) Monotone support: every anchor section's α exceeds α_w, so |A| grows with depth and the crossing is unique —
      asserted, not assumed; and |A| at the solved crossing equals 0.3 µm/K; CAN catch a wrong slope or bookkeeping in
      the solve, CANNOT a wrong section (that is (3)'s).
  (8) Thickness and cap: per gap and drift a thicker scale needs strictly less B_r at a P* that grows with t and stays
      at or under 2πg; the field needed at P_cap equals the linear range by a separate route; no capped period overruns
      its cap; CAN catch a sign slip in the (1 − e^{−kt}) term, a cap applied the wrong way or a scan past it, CANNOT
      an error in the idealised field form.
  (9) Temperature and solves: `81`'s deepest edge and the coldest air fall on this record's coldest hour («that
      hour»); at the thermal cap the hot-end need equals the field the cold end allows (the window closes — a second
      route to the cap); each of the four corner inputs moved alone from its kind to its adverse value never lowers a
      need, and the isothermal ≤ kind ≤ adverse order holds in every cell; the continuous isothermal need sits at or
      under the grid's by less than the grid step's worth; the need rises strictly with the gap and falls strictly with
      the thickness on sampled grids (so each root is unique), each root returns the family's maximum, and every grid
      cell's «holds» agrees with its row's solved gap limit (§When Modifying #54) AND with a brute-force search over the
      period in both directions (knife-edge cells within 0.2 % skipped); «holds with the unwrap floor» never admits a
      cell «holds» refuses and changes no verdict from the realistic gap up; a class spread never lowers a thickness
      limit, and its roots, ferrite's and the break-even hot hour each return the family's maximum; ferrite's floor list
      never admits a cell its gap limit refuses. The corner-input check runs on every cell. The cost's unimodality is asserted but cannot fail on
      this form (its log is convex in 2π/P). CAN catch a factor applied at the wrong end, a root off its function, a grid
      verdict that disagrees with its solve or with the brute force; CANNOT the coefficients' values, the linear form or
      the size validity (inputs and limits, named above).
 (10) The sensor table: the base row offset only reproduces (2c)'s thickness limit and cap at every family and corner;
      every root, every lever's gap limit and every infinite-thickness need is held to the sum rule written out again
      apart from `need_br_lane`, and a «no thickness» cell exactly to an infinite-thickness need above the family's
      maximum; at each lever's gap limit the offset term alone needs strictly less — so a verdict that DROPS the
      mismatch term fails here (mutation-checked: dropping it inside `sensor_table` trips the lever check); the mismatch
      and the floor never lower a limit; kind ≤ adverse on every limit and lever; a brute force over the period window
      at every solved cell (a second minimum the bounded search missed would red); each per-kelvin band row covers the
      edge it is applied at. CAN catch a dropped or mis-weighted mismatch term, a branch judged at the wrong temperature
      in one route only, a search that missed the minimum; CANNOT a datasheet value transcribed wrong (the row's comment
      cites the section; the read is the control) or the idealised field form.
 (11) The read: the base row's verdict-lane read in (2d) is (3)'s; CAN catch the two drifting apart, CANNOT a wrong
      current or timing row.
 (12) Linearity and screen: each (2e) reading's per-kelvin drifts, mismatch AND offset, equal the row's raw
      row or k·LIN over the edge distance from the corner's own hours; each (2e) and screen cell's infinite-thickness need IS the sum rule at its period and «no thickness» is
      exactly a need above the family's maximum; the floor never lowers a limit; the both-raw reading agrees with the table's verdict both ways; «from 25 °C» never needs
      more than «best fit»; TI's total-drift reading of the offset is its own residual over the edge distance, and where that
      residual is the smaller one it never needs more than our full-scale best fit; a row with zero LIN fields, compensated, keeps no drift and holds at the thinnest scale; a band reached at the
      window's edge never holds more than the band spread to its end. CAN catch a reading that ignores LIN or the
      offset, a cell off its sum rule, a swapped span or edge; CANNOT TI's definition read wrong or a value transcribed
      wrong (the rows cite their sources).
 (13) Angle rows: each 180° row's floor is twice the 360° one and each row's minimum gap is the wall plus its die depth;
      a curve returns its transcribed points and zero at 25 °C, its electrical reading doubles its field cap and its read
      tolerance brackets its cap; each window-edge span equals the corner's hours from 25 °C, each band-end span covers it
      and never gives a shorter cap; the triangle bound never gives a longer cap than the limit; the binding branch is the
      larger drift and P_max·δθ/360° returns 0.3 µm/K; at each saturation and field-maximum period the field equals the
      row's limit and a hair beyond crosses it, a «never» is checked by a scan; the strongest class passes the maximum
      first; «reachable» is the gap against the minimum; the floor and t 2 mm never admit what the thick scale without
      them refuses; each window starts at or above the floor and ends at or under P_max and the weakest class's maximum;
      each member's cap returns 0.3 µm/K and a rejected member moves the angle further than its row's limit. CAN catch a
      span from the wrong hours, a cap off its formula, a saturation or maximum root off its field, a floor not doubled, a
      gap the package cannot reach counted as holding; CANNOT a value transcribed wrong (the rows cite their sources;
      KMZ60's curves are read off images to ±0.05° · ±0.02°) or the idealised field form.
 (14) Package reach: each interval's bottom is the wall plus the depth's lower end and its order holds; «reachable» at
      3 · 4 mm follows the interval; the table's 3 mm holds are recounted from (2d)'s cells; a lever's family and corner
      that holds 3 mm at t ≤ 10 mm holds at least 3 mm at t 10 mm; a best gap below the interval leaves no 3 mm hold
      reachable; each tilt's gap reached is the corner's projection at its β. CAN catch an interval built
      off the wrong depth, a reach verdict off its interval, a hold list that drifted from the table; CANNOT a position
      read wrong off a figure (each row cites its figure) or the mounting itself.

Run:  python tools/in_silico/scripts/114_dendrometer_support_budget.py      # a few seconds
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import brentq, minimize_scalar

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALPHA_PEEK_1K, CACHE_DIR, E_CYCLE, ETA_BUCK_ACTIVE, KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Whether a point dendrometer that uses the anchor as its support can hold its reading: the thermal "
                  "artefact of the support per fixation depth, the period a magnetic scale needs behind the capsule wall "
                  "and the error terms of two-axis Hall sensors reading it, judged per datasheet with the offset and the "
                  "axis-mismatch drift summed, the unwrap margin through winter swings and power outages, the energy of a "
                  "read, and how soon the growing bark passes the capsule along the tilted axis.")

HERE = Path(__file__).resolve().parent
OUT = CACHE_DIR / "mechanical" / "dendrometer_support_budget.json"
WOOD_SHARE = CACHE_DIR / "mechanical" / "anchor_wood_share.json"        # `103`
FLANGE_HEAT = CACHE_DIR / "thermal" / "flange_cambium_heat.json"         # `78`
PV_AUTONOMY = KINETICS_DIR / "winter_pv_autonomy.json"                   # `110`
SKY_EDGE = CACHE_DIR / "thermal" / "capsule_cold_edge_sky.json"         # `81`
RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"
FLANGE_CEM = REPO_ROOT / "tools/cad/cem/cathode_flange.json"

# 02_03 §9.4 — the core's run current and VOUT of the mruby member, and the members E_CYCLE is built from (mirrors)
I_CORE_RUN_A = 8e-3
V_OUT = 3.3
CYCLE_MEMBERS_J = {"mruby": (8e-3, 0.15), "tx_14dbm_sf9": (23.5e-3, 0.1649)}
E_RADIO_RX_TCXO_J = 12.58e-3
# ── THE SENSOR TABLE (2d) — one row per device and linear range, each value transcribed from the primary datasheet
# named in the row's `source` (PDFs from ti.com/lit/ds/symlink/, read 2026-11-16 with `pdftotext -layout`, every
# column read by its header — in-silico §Critical Rules #41). Per axis and per temperature BRANCH (cold = 25 → −40 °C,
# hot = 25 → +125 °C) each drift is a pair (typical, guaranteed): the guaranteed value is the larger magnitude of the
# MIN and MAX columns, None where the datasheet gives only a typical one. `offset_basis` / `mismatch_basis` declare
# the form: "per_K" (a per-kelvin row) ⊥ "total_linear" (a total from 25 °C to the branch's end, which the datasheet
# itself says scales linearly with the excursion) ⊥ "total_no_dT" (a total over the operating range with no ΔT and
# no linearity statement — per kelvin ONLY under our assumed spread to the branch's end, `BRANCH_SPAN_K`). The X and
# Y axes share one row in every datasheet read here, so the X–Y pair takes the X row twice. The rest of a row: RMS
# noise per axis (typical, at the conversion setting of the timing row), angle error per pair (typical, 25 °C; and
# its maximum over temperature where given), the lifetime drifts where given, and the energy members (active current,
# one-channel conversion, the added second channel, the wake path, sleep current). `assumed` names every member that
# is not the datasheet's row for our operating point. ──
BRANCH_SPAN_K = {"cold": 65.0, "hot": 100.0}   # 25 → −40 ⊥ 25 → +125 °C: the span a «from 25 °C» total is spread over
MISMATCH_LINEAR_SPREAD_K = (65.0, 100.0)   # the base tables' (2) print: IF the drift spread linearly to −40 ⊥ +125 °C
SENSORS = {
    # TI SLYS045C (TMAG5273, June 2021, revised April 2026): §5.7 «Magnetic Characteristics For A1, B1, C1, D1» — BIN,
    # Boff_TC (typ ±3.0, max ±10.0 µT/°C, one row for every axis over the operating range), SENSMS_DR (X–Y ±5 %,
    # Y–Z/X–Z ±15 %, TYPICAL column only, no ΔT), NRMS at CONV_AVG = 101b, LP_LN = 0b (X, Y 22 µT; Z 11 µT), AERR at
    # CONV_AVG = 101b, 25 °C (X–Y ±0.5°, X–Z ±1.0°); §5.5 IACTIVE (LP_LN = 0b) 2.3 mA, ISLEEP 5 nA; §5.11 tmeasure
    # 825 µs (CONV_AVG = 101b, one channel; note 3: +32 × 25 µs = 800 µs per added channel), tstart_sleep 50 µs,
    # tstart_measure 70 µs; §5.3 TA −40…125 °C
    "TMAG5273A1": {
        "source": "TI SLYS045C (June 2021, rev. April 2026) §5.7 · §5.5 · §5.11 · §5.3",
        "ranges_T": (0.040, 0.080), "verdict_range_T": 0.080, "operating_C": (-40.0, 125.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (3.0e-6, 10.0e-6), "hot": (3.0e-6, 10.0e-6)},
                           "z": {"cold": (3.0e-6, 10.0e-6), "hot": (3.0e-6, 10.0e-6)}},
        "mismatch_basis": "total_no_dT",
        "mismatch": {"x_y": {"cold": (0.05, None), "hot": (0.05, None)}, "x_z": {"cold": (0.15, None), "hot": (0.15, None)}},
        "noise_T": {"x": 22e-6, "z": 11e-6}, "angle_error_deg": {"x_y": 0.5, "x_z": 1.0}, "angle_error_over_T_deg": None,
        "lifetime": None,
        "i_active_A": 2.3e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 70e-6), "i_sleep_A": 5e-9,
        "assumed": []},
    # the same datasheet, §5.8 «Magnetic Characteristics For A2, B2, C2, D2»: BIN ±133 ⊥ ±266 mT, Boff drift typ ±3.0,
    # max ±10 µT/°C, SENSMS_DR ±5 % ⊥ ±15 % (typical), NRMS (CONV_AVG = 101b, LP_LN = 0b) X, Y 24 µT, Z 15 µT, AERR
    # X–Y ±0.50°, X–Z ±1.0°; §5.5 and §5.11 are not per variant
    "TMAG5273A2": {
        "source": "TI SLYS045C (June 2021, rev. April 2026) §5.8 · §5.5 · §5.11 · §5.3",
        "ranges_T": (0.133, 0.266), "verdict_range_T": 0.266, "operating_C": (-40.0, 125.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (3.0e-6, 10.0e-6), "hot": (3.0e-6, 10.0e-6)},
                           "z": {"cold": (3.0e-6, 10.0e-6), "hot": (3.0e-6, 10.0e-6)}},
        "mismatch_basis": "total_no_dT",
        "mismatch": {"x_y": {"cold": (0.05, None), "hot": (0.05, None)}, "x_z": {"cold": (0.15, None), "hot": (0.15, None)}},
        "noise_T": {"x": 24e-6, "z": 15e-6}, "angle_error_deg": {"x_y": 0.5, "x_z": 1.0}, "angle_error_over_T_deg": None,
        "lifetime": None,
        "i_active_A": 2.3e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 70e-6), "i_sleep_A": 5e-9,
        "assumed": []},
    # TI SBASAF4 (TMAG5170, September 2021) §6.6, TMAG5170A1, x_RANGE = 10b (±100 mT): Boff_DR_A1 X/Y 25 → 125 °C typ 0,
    # max ±5.0; 25 → −40 °C min −6.5, typ −1.5, max 2.5; Z 25 → 125 typ 0, max ±1.5; 25 → −40 min −3.0, typ −1.0, max
    # 1.0 µT/°C; SENSMS_DR_XY_A1 25 → 125 typ ±0.8 %, max ±4.0 %; 25 → −40 typ ±0.5 %, max ±3.4 %; SENSMS_DR_XZ_A1
    # 25 → 125 ±1.4 ⊥ ±4.2 %, 25 → −40 ±0.1 ⊥ ±3.5 %; note (1): «drift at any temperature can be calculated from drift
    # values at 125 °C or −40 °C», linearly in the excursion from 25 °C; Boff_DR_A1 lifetime ±50 µT and SENSLDR_A1
    # ±0.5 % (typical); NRMS_XY_SLOW_A1 (x_RANGE = 00b, CONV_AVG = 101b, 25 °C) typ 24, max 34 µT, NRMS_Z_SLOW_A1 11 ⊥
    # 14.2 µT; AERR X–Y ±0.4°, X–Z ±0.5° (typical, 25 °C, after 25 °C gain and offset correction); §6.5 IACT 3.4 mA
    # (VCC 5.5 V), tmeasure 825 µs (CONV_AVG = 101, one channel; note 3: +800 µs per added axis), IDEEP_SLP 5 nA;
    # §6.7 tstart_sleep max 50 µs, tstand_by 90 µs; §6.3 TA −40…150 °C
    "TMAG5170A1": {
        "source": "TI SBASAF4 (September 2021) §6.6 TMAG5170A1 · §6.5 · §6.7 · §6.3",
        "ranges_T": (0.025, 0.050, 0.100), "verdict_range_T": 0.100, "operating_C": (-40.0, 150.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (1.5e-6, 6.5e-6), "hot": (0.0, 5.0e-6)},
                           "z": {"cold": (1.0e-6, 3.0e-6), "hot": (0.0, 1.5e-6)}},
        "mismatch_basis": "total_linear",
        "mismatch": {"x_y": {"cold": (0.005, 0.034), "hot": (0.008, 0.040)},
                     "x_z": {"cold": (0.001, 0.035), "hot": (0.014, 0.042)}},
        "noise_T": {"x": 24e-6, "z": 11e-6}, "angle_error_deg": {"x_y": 0.4, "x_z": 0.5}, "angle_error_over_T_deg": None,
        "lifetime": {"offset_T": 50e-6, "sensitivity": 0.005, "kind": "typical"},
        "i_active_A": 3.4e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 90e-6), "i_sleep_A": 5e-9,
        "assumed": ["noise: given at the ±50 mT range only, taken for ±100 mT",
                    "IACT: given at VCC 5.5 V only, taken at 3.3 V",
                    "wake: tstart_sleep + tstand_by, our reading of the mode sequence (the operating-modes table not read)"]},
    # the same datasheet, TMAG5170A2, x_RANGE = 00b (±150 mT): Boff_DR_A2 X/Y 25 → 125 typ 1.0, max ±5.5; 25 → −40 min
    # −8.0, typ −3.0, max 2.0; Z 25 → 125 typ −1.5, max ±3.5; 25 → −40 typ −0.4, max ±5.0 µT/°C; SENSMS_DR_XY_A2 (75 ·
    # 150 mT) over −40…125 °C typ ±0.5 %, max ±4.0 %; SENSMS_DR_XZ_A2 ±0.2 ⊥ ±5.5 %; lifetime ±50 µT, SENSLDR_A2 ±0.6 %;
    # NRMS (X, Y) CONV_AVG = 101b, 25 °C 28 ⊥ 41 µT, (Z) 13 ⊥ 16 µT; AERR X–Y ±0.40°, X–Z ±0.5°
    "TMAG5170A2": {
        "source": "TI SBASAF4 (September 2021) §6.6 TMAG5170A2 · §6.5 · §6.7 · §6.3",
        "ranges_T": (0.075, 0.150), "verdict_range_T": 0.150, "operating_C": (-40.0, 150.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (3.0e-6, 8.0e-6), "hot": (1.0e-6, 5.5e-6)},
                           "z": {"cold": (0.4e-6, 5.0e-6), "hot": (1.5e-6, 3.5e-6)}},
        "mismatch_basis": "total_linear",
        "mismatch": {"x_y": {"cold": (0.005, 0.040), "hot": (0.005, 0.040)},
                     "x_z": {"cold": (0.002, 0.055), "hot": (0.002, 0.055)}},
        "noise_T": {"x": 28e-6, "z": 13e-6}, "angle_error_deg": {"x_y": 0.4, "x_z": 0.5}, "angle_error_over_T_deg": None,
        "lifetime": {"offset_T": 50e-6, "sensitivity": 0.006, "kind": "typical"},
        "i_active_A": 3.4e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 90e-6), "i_sleep_A": 5e-9,
        "assumed": ["IACT: given at VCC 5.5 V only, taken at 3.3 V",
                    "wake: tstart_sleep + tstand_by, our reading of the mode sequence (the operating-modes table not read)"]},
    # the same device at x_RANGE = 10b (±300 mT): Boff_DR_A2 (300 mT range, every axis) over −40…125 °C typ ±2.5, max
    # ±12.0 µT/°C; SENSMS_DR_XY_A2 (300 mT) 25 → 125 ±0.5 ⊥ ±5.2 %, 25 → −40 ±0.9 ⊥ ±7.6 %; SENSMS_DR_XZ_A2 (300 mT)
    # over −40…125 ±1.1 ⊥ ±6.6 %
    "TMAG5170A2_300mT": {
        "source": "TI SBASAF4 (September 2021) §6.6 TMAG5170A2, 300 mT range · §6.5 · §6.7 · §6.3",
        "ranges_T": (0.300,), "verdict_range_T": 0.300, "operating_C": (-40.0, 150.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (2.5e-6, 12.0e-6), "hot": (2.5e-6, 12.0e-6)},
                           "z": {"cold": (2.5e-6, 12.0e-6), "hot": (2.5e-6, 12.0e-6)}},
        "mismatch_basis": "total_linear",
        "mismatch": {"x_y": {"cold": (0.009, 0.076), "hot": (0.005, 0.052)},
                     "x_z": {"cold": (0.011, 0.066), "hot": (0.011, 0.066)}},
        "noise_T": {"x": 28e-6, "z": 13e-6}, "angle_error_deg": {"x_y": 0.4, "x_z": 0.5}, "angle_error_over_T_deg": None,
        "lifetime": {"offset_T": 50e-6, "sensitivity": 0.006, "kind": "typical"},
        "i_active_A": 3.4e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 90e-6), "i_sleep_A": 5e-9,
        "assumed": ["noise and angle error: given at the ±150 mT range only, taken for ±300 mT",
                    "IACT: given at VCC 5.5 V only, taken at 3.3 V",
                    "wake: tstart_sleep + tstand_by, our reading of the mode sequence (the operating-modes table not read)"]},
    # TI SLYS053C (TMAG3001, November 2023, revised May 2025) §5.7 «Magnetic Characteristics For A1»: BIN ±37 ⊥ ±75 mT;
    # Boff_DR −40 → 25 °C typ ±1, max ±9.3; 25 → 125 °C typ ±1, max ±9.6 µT/°C (every axis); SENSMS_DR, %/°C, MIN ⊥ MAX
    # only: X–Y −40…25 −0.027 ⊥ 0.029, 25…85 −0.032 ⊥ 0.023, 85…125 −0.041 ⊥ 0.029; X–Z or Y–Z −40…25 −0.054 ⊥ 0.027,
    # 25…85 −0.063 ⊥ 0.023, 85…125 −0.067 ⊥ 0.036 (the 25…85 band is the hot branch's here: our hottest hour lies in
    # it — asserted); NRMS (LP_LN = 0h, Conv_AVG = 5h) X, Y 17.5 µT, Z 10 µT; AERR 25 °C X–Y 0.4 (max ±0.95), X–Z 0.43
    # (±1.0)°, over −40…125 °C max X–Y ±2.3°, X–Z ±1.5°; §5.5 IACTIVE (LP_LN = 0h, 3.3 V) typ 2.4 mA, ISLEEP 40 nA;
    # §5.11 tmeasure (Conv_AVG = 5h, one channel) typ 825 µs, tstart_sleep 50 µs, tstart_measure 62 µs; §5.3 −40…125 °C
    "TMAG3001A1": {
        "source": "TI SLYS053C (November 2023, rev. May 2025) §5.7 · §5.5 · §5.11 · §5.3",
        "ranges_T": (0.037, 0.075), "verdict_range_T": 0.075, "operating_C": (-40.0, 125.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (1.0e-6, 9.3e-6), "hot": (1.0e-6, 9.6e-6)},
                           "z": {"cold": (1.0e-6, 9.3e-6), "hot": (1.0e-6, 9.6e-6)}},
        "mismatch_basis": "per_K", "mismatch_hot_band_C": (25.0, 85.0),
        "mismatch": {"x_y": {"cold": (None, 0.029e-2), "hot": (None, 0.032e-2)},
                     "x_z": {"cold": (None, 0.054e-2), "hot": (None, 0.063e-2)}},
        "noise_T": {"x": 17.5e-6, "z": 10e-6}, "angle_error_deg": {"x_y": 0.4, "x_z": 0.43},
        "angle_error_over_T_deg": {"x_y": 2.3, "x_z": 1.5},
        "lifetime": None,
        "i_active_A": 2.4e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 62e-6), "i_sleep_A": 40e-9,
        "assumed": ["the added channel's conversion time: not stated, taken as the TMAG5273's and TMAG5170's 800 µs"],
        # §5.7, MAX column only: SENSMS_DR_LIN X–Y 1.5, Y–Z or X–Z 1.5 %; Boff_DR_LIN Range 0h 0.06, Range 1h 0.04 %;
        # SENSDRLER X, Y 3.5, Z 4.3 % — their definition is TI's answer, case CS3699089 (2026-11-17), `DRIFT_LIN_DEFINITION`
        "drift_linearity": {"mismatch": {"x_y": 0.015, "x_z": 0.015},
                            "offset_pct_of_range_by_range_T": ((0.037, 0.0006), (0.075, 0.0004)),
                            "sensitivity": {"x": 0.035, "z": 0.043}}},
    # the same datasheet, §5.8 «Magnetic Characteristics For A2»: BIN ±120 ⊥ ±240 mT; Boff_DR −40 → 25 typ ±1, max
    # ±9.1; 25 → 125 typ ±1, max ±8 µT/°C; SENSMS_DR X–Y −40…25 ±0.041 (−0.041 ⊥ 0.041), 25…85 −0.046 ⊥ 0.044, 85…125
    # −0.057 ⊥ 0.055; X–Z or Y–Z −40…25 −0.063 ⊥ 0.024, 25…85 −0.074 ⊥ 0.035, 85…125 −0.083 ⊥ 0.070 %/°C; NRMS (LP_LN = 0h,
    # Conv_AVG = 5h) X, Y 20 µT, Z 14.5 µT; AERR 25 °C X–Y ±0.43 (max ±1.4), X–Z ±0.35 (±0.85)°, over −40…125 °C max
    # X–Y ±2.25°, X–Z ±1.4°
    "TMAG3001A2": {
        "source": "TI SLYS053C (November 2023, rev. May 2025) §5.8 · §5.5 · §5.11 · §5.3",
        "ranges_T": (0.120, 0.240), "verdict_range_T": 0.240, "operating_C": (-40.0, 125.0),
        "offset_basis": "per_K",
        "offset_T_per_K": {"x": {"cold": (1.0e-6, 9.1e-6), "hot": (1.0e-6, 8.0e-6)},
                           "z": {"cold": (1.0e-6, 9.1e-6), "hot": (1.0e-6, 8.0e-6)}},
        "mismatch_basis": "per_K", "mismatch_hot_band_C": (25.0, 85.0),
        "mismatch": {"x_y": {"cold": (None, 0.041e-2), "hot": (None, 0.046e-2)},
                     "x_z": {"cold": (None, 0.063e-2), "hot": (None, 0.074e-2)}},
        "noise_T": {"x": 20e-6, "z": 14.5e-6}, "angle_error_deg": {"x_y": 0.43, "x_z": 0.35},
        "angle_error_over_T_deg": {"x_y": 2.25, "x_z": 1.4},
        "lifetime": None,
        "i_active_A": 2.4e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6, "t_wake_s": (50e-6, 62e-6), "i_sleep_A": 40e-9,
        "assumed": ["the added channel's conversion time: not stated, taken as the TMAG5273's and TMAG5170's 800 µs"],
        # §5.8, MAX column only: SENSMS_DR_LIN X–Y 3.2, «Z axis» (the pairs with Z) 3.5 %; Boff_DR_LIN Range 0h 0.07,
        # Range 1h 0.04 %; SENSDRLER X, Y 2.5, Z 3.5 %
        "drift_linearity": {"mismatch": {"x_y": 0.032, "x_z": 0.035},
                            "offset_pct_of_range_by_range_T": ((0.120, 0.0007), (0.240, 0.0004)),
                            "sensitivity": {"x": 0.025, "z": 0.035}}},
    # Infineon TLE493D-P3B6 Datasheet Rev. 1.0 (2024-08-26), read 2026-11-17 in the browser (pdf.js on infineon.com —
    # curl gets an empty 202 there): Table 4 magnetic range ±50 · ±100 · ±160 mT (extra short · short · full), operating
    # −40…125 °C; Table 8 «Compensated magnetic drift characteristics» — «changes from the initial characteristics [0 h,
    # 25 °C] due to external influences», all range settings, after the host polynomial of §4.1.3 with the FIXED
    # coefficients of Table 13 (one set for the population, the on-chip temperature read once per read, which it barely moves within — no per-unit
    # calibration), MIN ⊥ MAX only, one row per temperature span: offset drift X, Y, Z ±0.3 mT on −40…85 · −40…105 ·
    # −40…125 °C alike; X to Y magnetic matching drift ±1.65 · ±1.7 · ±1.9 %, X/Y to Z ±6.5 · ±6.75 · ±8 %. The table's
    # SPREAD reading takes, per branch, the row with the smallest per-kelvin figure — the cold branch from the −40…85 °C
    # row (all three start at −40 °C; it has the tightest band), the hot one from −40…125 °C (1.9 % over 100 K < 1.65 %
    # over 60 K; X/Y–Z 8 % over 100 K) — the LINEAR reading, the tightest row per branch (a unit drifting linearly at
    # those two slopes meets all three rows; a curve flatter than linear inside the window the band also admits, so
    # this is not «the most favourable» reading); `band_at_window_edge` is the
    # −40…85 °C band reached at the window's own edge (our hottest hour lies in that span, asserted), a less
    # favourable chord reading; Table 10 noise (rms, 1 σ, MAX column only) XY / Z
    # full range 250 / 173, short 176 / 122, extra short 125 / 86 µT; Table 5 supply current active typ 4.2 (max 6) mA,
    # power down typ 500 nA at 25 °C (max 6 µA at 85 °C); Tables 15–16 oscillator period typ 500 ns, Bx/By/Bz conversion
    # 86 · 118 · 182 t_OSC (full · short · extra short), temperature conversion 86 t_OSC, trigger delay typ 16 µs, first
    # measurement ≤ 75 µs. Table 9 (raw, without compensation, −40…105 °C: offset ±0.35 mT, matching ±1.7 ⊥ ±7.5 %) is
    # not a row: the compensated row is the sensor as its datasheet specifies it.
    "TLE493D-P3B6_comp": {
        "source": "Infineon TLE493D-P3B6 Datasheet Rev. 1.0 (2024-08-26) Tables 4 · 5 · 8 · 10 · 13 · 15 · 16, §4.1.3",
        "ranges_T": (0.050, 0.100, 0.160), "verdict_range_T": 0.160, "operating_C": (-40.0, 125.0),
        "mismatch_hot_band_C": (25.0, 125.0),
        "band_at_window_edge": {"band_C": (-40.0, 85.0), "offset_T": 0.3e-3, "mismatch": {"x_y": 0.0165, "x_z": 0.065}},
        "offset_basis": "total_no_dT",
        "offset_T_total": {"x": {"cold": (None, 0.3e-3), "hot": (None, 0.3e-3)},
                           "z": {"cold": (None, 0.3e-3), "hot": (None, 0.3e-3)}},
        "mismatch_basis": "total_no_dT",
        "mismatch": {"x_y": {"cold": (None, 0.0165), "hot": (None, 0.019)},
                     "x_z": {"cold": (None, 0.065), "hot": (None, 0.08)}},
        "noise_T": {"x": 250e-6, "z": 173e-6}, "angle_error_deg": None, "angle_error_over_T_deg": None,
        "lifetime": None,
        "i_active_A": 4.2e-3, "t_conv_one_ch_s": 43e-6, "t_add_ch_s": 43e-6, "t_wake_s": (16e-6, 75e-6, 43e-6),
        "i_sleep_A": 500e-9,
        "assumed": ["the drift totals spread linearly over 25 → −40 °C (the −40…85 °C row) ⊥ 25 → +125 °C (the −40…125 °C "
                    "row) — `BRANCH_SPAN_K`: the datasheet gives bands over spans, with no per-kelvin row and no linearity "
                    "statement, and the row read per branch is the tightest one",
                    "the host polynomial's temperature: one conversion per read, not per sample (it barely moves within a "
                    "read; a conversion per sample would cost more)",
                    "noise: the MAX column (no typical given), full range",
                    "conversion: the typical oscillator period, 500 ns (max 640 ns)",
                    "wake: trigger delay (typ) + first measurement (max) + the temperature conversion the host polynomial "
                    "needs — our reading of the measurement sequence",
                    "lifetime: the drifts are changes «due to external influences»; whether ageing is one, it does not say"]},
}
# TI's definition of the TMAG3001's drift-linearity rows (SENSMS_DR_LIN · Boff_DR_LIN · SENSDRLER), case CS3699089, TI
# Customer Support, 2026-11-17 (our summary of their answer): the maximum deviation of the actual drift curve from a
# BEST-FIT straight line over the full −40…+125 °C range («typically referenced to the 25 °C point»), in % of the
# NOMINAL sensitivity — not of the full-scale range, not of the drift slope; a production-guaranteed limit over that
# range; NOT a per-kelvin coefficient («you cannot simply divide the % value by the temperature delta»); no published
# data on repeatability after thermal cycling or on 20-year stability. Two things in it the datasheet does not settle:
# «best-fit» and «referenced to 25 °C» are two different lines, and a % of the nominal SENSITIVITY gives no field for an
# OFFSET row — so (2e) prices the offset row only under our full-scale reading, labelled as such.
# ⊕ The follow-up answer in the same case, 2026-11-18 (our summary): Boff_DR_LIN «is defined relative to the total offset
# drift (Boff_DR) across the full temperature range, not relative to nominal sensitivity or magnetic full-scale range»;
# «offset drift linear error (µT) = Boff_DR_LIN × total offset drift over temperature span», the budget named as the
# Boff_DR maximum per °C over −40…125 °C; the line is a best fit over that range, «not constrained to pass through the
# 25 °C point», and against a 25 °C baseline the deviation «could be up to approximately twice the listed LIN value».
# The answer excludes the full-scale reading explicitly («It is not a fixed percentage of the full-scale magnetic range»).
# (2e) still prints it beside TI's (`OFFSET_LIN_READINGS`) as the ADVERSE BOUND — the datasheet prints no definition, the
# case's first answer named another base (% of the nominal sensitivity), and the residual TI's reading gives is far below
# the row's own noise — until the bench measures the residual. That the row prints one value per range decides nothing:
# the absolute residual differs by range on either reading.
DRIFT_LIN_DEFINITION = {"line": "best fit over −40…+125 °C", "unit": "% of the nominal sensitivity", "guaranteed": True,
                        "per_kelvin": False, "repeatability_and_lifetime": "not published",
                        "source": "TI Customer Support case CS3699089, 2026-11-17",
                        "offset_row_2026_11_18": {
                            "unit": "% of the total offset drift over the full temperature range",
                            "line_held_to_25C": False, "from_25C_factor": 2.0,
                            "source": "TI Customer Support case CS3699089, follow-up 2026-11-18"}}
# PACKAGE REACH (2h) — where each Hall row's elements sit in its package, read 2026-11-17 off the primaries' figures (page
# images): the X–Z pair reads with the package FLAT, its top to the wall, so the gap is the wall plus the element's depth
# under the top; the X–Y pair needs both axes in the plane of the motion and the scale's normal, so the package stands
# EDGE-ON on its lead-free end, and the gap is the wall plus the element's distance from that end. Each is an interval
# (lo, hi) over the drawing's tolerances; a holder's clearance is zero.
PACKAGE_REACH = {
    # TI SLYS045C §6.3.2 Fig. 6-2: X, Y, Z elements 0.73 mm under the top, 1.85 mm from the pin-1 end; outline DBV0006A-C02
    # (p. 54, read off the page image): body 2.75–3.05 mm long, leads on the long sides — the far end 0.90–1.20 mm away
    # (mould flash, ≤ 0.25 mm per side by note 3, not added).
    "TMAG5273": {"rows": ("TMAG5273A1", "TMAG5273A2"),
                 "source": "TI SLYS045C §6.3.2 Fig. 6-2; outline DBV0006A-C02 (body 2.75–3.05 mm)",
                 "x_z_mm": (0.73, 0.73), "x_y_mm": (2.75 - 1.85, 3.05 - 1.85), "end_on": (0.73, 2.75 - 1.85)},
    # TI SBASAF4 §7.3.2 Fig. 7-2: 0.32 mm under the top, 1.54 mm from the pin-1 end; DGK body 2.9–3.1 mm (outline) —
    # the nearer end is the far one below 3.08 mm of body.
    "TMAG5170": {"rows": ("TMAG5170A1", "TMAG5170A2", "TMAG5170A2_300mT"),
                 "source": "TI SBASAF4 §7.3.2 Fig. 7-2; DGK body 2.9–3.1 mm (package outline)",
                 "x_z_mm": (0.32, 0.32), "x_y_mm": (2.9 - 1.54, min(1.54, 3.1 - 1.54)), "end_on": (0.32, 2.9 - 1.54)},
    # TI SLYS053C §6.3.2 Fig. 6-2: the Z element 0.25 mm under the top, 0.338 mm from the die centre along the long side
    # (0.007 across); X 0.10 mm from Z in X (drawn across, to one side), Y 0.099 mm from Z in Y; WCSP 0.76–0.82 × 1.26–1.32
    # mm, balls underneath, every edge lead-free — the nearest is the long side the X element is drawn towards: the
    # farther element of the pair (Z) W/2 − 0.007 = 0.373–0.403 mm in (the end: 0.391–0.421).
    "TMAG3001": {"rows": ("TMAG3001A1", "TMAG3001A2"),
                 "source": "TI SLYS053C §6.3.2 Fig. 6-2 (WCSP 0.76–0.82 × 1.26–1.32 mm)",
                 "x_z_mm": (0.25, 0.25), "x_y_mm": (0.76 / 2 - 0.007, 0.82 / 2 - 0.007), "end_on": (0.25, 0.76 / 2 - 0.007)},
    # Infineon TLE493D-P3B6 Rev. 1.0 §2.3 Fig. 4: the sensitive area's centre 1.45 mm from datum A (the pin-1 end) with
    # ⌀0.2 position tolerance, 0.785 mm from datum B (a long side) with ⌀0.10, and 0.65 ± 0.05 mm under the top to the
    # LOWER edge of the hatched block (drawn ≈ 0.2 mm thick; where the Hall plane sits in it is not printed, so the depth
    # runs 0.39–0.70); §7.2 Fig. 23: PG-TSOP6 body 2.9 ± 0.1 × 1.6 ± 0.1 mm, lead span 2.8 ± 0.1 on the long sides.
    # Edge-on, the nearest edge is a LEADED long side, the lead tips 0.735 + (2.7 − 1.7)/2 = 1.235 mm from the centre at
    # the drawing's favourable ends (nominal 1.385); worst case the far end, 1.45 (the end at best 1.25 — `end_on`).
    "TLE493D-P3B6": {"rows": ("TLE493D-P3B6_comp",),
                     "source": "Infineon TLE493D-P3B6 Datasheet Rev. 1.0 §2.3 Fig. 4 · §7.2 Fig. 23",
                     "x_z_mm": (0.39, 0.70), "x_y_mm": (0.735 + (2.7 - 1.7) / 2, 1.45), "end_on": (0.39, 2.8 - 1.55)},
}
BASE_SENSOR = "TMAG5273A1"   # the row the base tables (2) · (2b) and the 2026-11-10/11 verdict (2c) were priced on
# Rows NOT in the table — named, so «the table» is not read as «every sensor»: what is missing is a primary read here
SENSOR_GAPS = {
    "TLE493D-W2B6 (Infineon)": "primary not re-read in this run (the 2026-11-16 desk read v1.2 Table 9 as «not "
        "production tested»); the family's P3B6 is priced as a row",
    "MLX90393 (Melexis)": "primary read 2026-11-17 (Revision 012, 2025-11-18, Table 9): no guaranteed offset drift — "
        "OFFSTHD «< ±1000 LSB» stands in the Nom column, «based on characterization on limited sample size» (note 7) — and "
        "no mismatch-drift row (SENSTHD ±3 % is the sensitivity's band, not a mismatch bound), so it is not even screened",
    "TLV493D-A2BW (Infineon)": "operating range −20…85 °C per the desk — short of the record's cold edge; not re-read",
    "TMR3004 · TMR3005 (MultiDimension)": "primaries read 2026-11-17 (TMR3005 datasheet V2.0, TMR3004 V1.0a — "
        "distributor-hosted copies of MDT's documents): the angular error ±0.6° · ±1.5° stands in the Typ column at "
        "TA = 25 °C, with no over-temperature angle row (each prints only a typical amplitude coefficient, −970 · −990 "
        "ppm/°C), so the angle rows (2g) cannot judge them; both operate −40…85 °C",
}
# SCREEN ROWS (2f) — sensors whose primary gives the two drift bounds the verdict needs but not the rows a READ would be
# priced from (their noise and conversion time are settings-dependent): judged by the same sum rule, offset and mismatch,
# without the energy columns. Each drift is a TOTAL change from 25 °C derived from the datasheet's own columns — the
# derivation is ours and named in the row — and is per kelvin only under our spread to the band's ends (`branch_span_K`).
SCREEN_ROWS = {
    # Melexis MLX90395 Datasheet Revision 6.0 (2020-09-15) Table 14, medium-field variant (-0xx), read 2026-11-17 with
    # pdftotext from melexis.com: sensing range 50 mT; offset X0, Y0, Z0 −150 ⊥ 150 LSB16 «TA within TAMB» (−40…125 °C)
    # at 2.5 µT/LSB16 (note 11: «the thermal offset drift will be within a ±30 LSB window, by characterization» — not a
    # guaranteed column); «Thermal Drift of Sensitivity Mismatch» −3 ⊥ 3 % within TAMB, one row for every pair.
    "MLX90395-0xx": {
        "source": "Melexis MLX90395 Datasheet Revision 6.0 (2020-09-15) Table 14 (medium-field, -0xx)",
        "verdict_range_T": 0.050, "operating_C": (-40.0, 125.0),
        "offset_basis": "total_no_dT",
        "offset_T_total": {ax: dict.fromkeys(("cold", "hot"), (None, 0.00075)) for ax in ("x", "z")},
        "mismatch_basis": "total_no_dT",
        "mismatch": {p: dict.fromkeys(("cold", "hot"), (None, 0.03)) for p in ("x_y", "x_z")},
        "assumed": ["offset: an ABSOLUTE band ±375 µT over the range bounds the change from 25 °C by 750 µT (our reading)",
                    "mismatch: the «thermal drift of sensitivity mismatch» ±3 % read as the change from 25 °C (the table "
                    "names no reference temperature; its neighbours are at 35 °C)",
                    "the totals spread linearly to −40 ⊥ +125 °C (`BRANCH_SPAN_K`)"]},
    # Allegro ALS31313 Datasheet Rev. 9 (2021-05-18), performance characteristics per variant, «valid through full range
    # of TA» (−40…125 °C), read 2026-11-17 with pdftotext from allegromicro.com: offset error X/Y and Z at BIN = 0 G —
    # -500: ±24 LSB (25 °C) · ±40 (125 °C) · ±40 (−40 °C) at 4 LSB/G; -1000: ±12 · ±24 · ±32 at 2 LSB/G; -2000: ±10 · ±20
    # · ±32 at 1 LSB/G; sensitivity mismatch X–Y and X/Y–Z ±5 %, no temperature condition (the header's «full range»).
    **{f"ALS31313-{v}": {
        "source": f"Allegro ALS31313 Datasheet Rev. 9 (2021-05-18), ALS31313KLEATR-{v} performance characteristics",
        "verdict_range_T": rng, "operating_C": (-40.0, 125.0),
        "offset_basis": "total_no_dT",
        "offset_T_total": {ax: {"cold": (None, (e25 + ecold) / lsb_g * 1e-4), "hot": (None, (e25 + ehot) / lsb_g * 1e-4)}
                           for ax in ("x", "z")},
        "mismatch_basis": "total_no_dT",
        "mismatch": {p: dict.fromkeys(("cold", "hot"), (None, 0.1)) for p in ("x_y", "x_z")},
        "assumed": ["offset: the change from 25 °C bounded by the 25 °C and the end-point ABSOLUTE errors added; no bound "
                    "between the points the table names (our reading)",
                    "mismatch: an absolute ±5 % over the range bounds the change by 10 % (our reading)",
                    "the totals spread linearly to −40 ⊥ +125 °C (`BRANCH_SPAN_K`)"]}
       for v, rng, lsb_g, e25, ehot, ecold in (("500", 0.050, 4.0, 24.0, 40.0, 40.0), ("1000", 0.100, 2.0, 12.0, 24.0, 32.0),
                                               ("2000", 0.200, 1.0, 10.0, 20.0, 32.0))},
}
# ANGLE (SATURATION) ROWS (2g) — sensors that read the field's DIRECTION: the scale's field has only to exceed the row's
# minimum and its magnitude drops out, so the reading drifts by the change of the angle error with temperature and x moves
# by P·δθ/360° (θ the field angle the sensor reports — the AMR's included, whose output angle is the field's over its
# 180° range). Every primary read 2026-11-17 with pdftotext; KMZ60's curve off the page image at 300 dpi.
ANGLE_ROWS = {
    # Infineon TLE5501 Datasheet Rev. 1.0 (2018-07-24, infineon.com) Table 12, differential: AErr,RT 0.8° «at 0 h/25 °C»
    # and AErr,0 1.0° «at 0 h/over temperature TA = −40 °C to 150 °C», both «with compensation of offset, orthogonality and
    # amplitude at 0h/25°C», B 25…80 mT (note 2: 20…25 and 80…100 mT add 0.2°), hysteresis and noise included (note 1);
    # AErr,125 1.2° «over lifetime & temperature» to 125 °C under Grade 1 stress. Table 11: Aout,diff 270 / 320 / 370 mV/V
    # at 25 °C, TCAmp −0.145 / −0.12 / 0 %/K, TCVoff −5 / 0 / 5 µV/V/K, «single and differential ended». §6.1: the field
    # «parallel to the package surface» is sensed; §8.4: the TMR area's centre «in the center of the package»; Fig. 12
    # (read off the page image): PG-DSO-8 body 5 −0.2 × 4 −0.2 mm, leads on the long sides.
    "TLE5501-E0001_diff": {
        "source": "Infineon TLE5501 Datasheet Rev. 1.0 (2018-07-24) Tables 11–12, §8.4, Fig. 12 — differential outputs",
        "operating_C": (-40.0, 150.0), "field_min_T": 0.025, "field_max_T": 0.080, "range_deg": 360.0,
        "total_deg": 1.0, "at_25C_deg": 0.8, "lifetime_deg": 1.2,
        "offset_tc_V_per_V_K": 5e-6, "amplitude_min_V_per_V": 0.270, "amplitude_tc_min_per_K": -0.145e-2,
        "amplitude_tc_max_per_K": 0.0, "mismatch_tc_per_K": None,
        "package": "PG-DSO-8, body 4.8–5.0 × 3.8–4.0 mm, die centred", "die_to_edge_mm": 4.8 / 2,
        "assumed": ["AErr,0 read as the change from 25 °C at any temperature in its span (limit) ⊥ the change bounded by "
                    "AErr,0 + AErr,RT (limit_plus_25C) — the table bounds the error's size at a temperature, not its "
                    "change; and the «relative» error is measured from a reference line set symmetric to it — if that "
                    "line is re-set at each temperature, a common shift of the zero is bounded by neither reading",
                    "the field held inside 25…80 mT, the rows' own band (the 0.2° adder outside it is not taken)",
                    "edge-on on a lead-free end, the die 2.4 mm in (the shortest body)",
                    "TCAmp is one coefficient for both channels (a common gain that cancels); read per channel its span "
                    "is the rejected member `mismatch_if_TCAmp_per_channel`"]},
    # TI TMAG6180-Q1 SLYS037A (2023-03, rev. 2024-03) §5.6: ANGERR_RTCAL_DE 1.0° max at VCC 3.3 V (0.95° at 5 V) — «angular
    # error linearity across temperature after room temperature calibration (of offset / gain mismatch)», B = 30 mT, ideal
    # magnet alignment, over the operating free-air range −40…150 °C; ANGLT_DRIFT ±0.75° (lifetime, B = 30 mT); AMR
    # saturation ≥ 20 mT (§5.3); the AMR's 180° extended to 360° by the Hall outputs Q0/Q1; «the center of the AMR and Hall
    # sensors lie in the center of the package»; DGK (VSSOP-8) 3 mm × 4.9 mm nominal, pins included. The TMAG6181-Q1
    # (SLYS048B) prints the same angle rows but gives pins 4–5 to SLEEP and TURNS — no quadrant outputs — so it is not
    # this row.
    "TMAG6180-Q1_RTCAL_DE": {
        "source": "TI TMAG6180-Q1 SLYS037A §5.3 · §5.6 (ANGERR_RTCAL_DE at 3.3 V) · §6 (die position)",
        "operating_C": (-40.0, 150.0), "field_min_T": 0.030, "field_max_T": None, "range_deg": 360.0,
        "total_deg": 1.0, "at_25C_deg": None, "lifetime_deg": 0.75,
        "offset_tc_V_per_V_K": None, "amplitude_min_V_per_V": None, "amplitude_tc_min_per_K": None,
        "amplitude_tc_max_per_K": None, "mismatch_tc_per_K": None,
        "package": "VSSOP-8 (DGK), 3 mm body length nominal, AMR centred", "die_to_edge_mm": 3.0 / 2,
        "assumed": ["the row read as the change from 25 °C (limit) ⊥ twice the row, the 25 °C error bounded by the same "
                    "row (limit_plus_25C) — «linearity across temperature» names no reference, and TI calls the error "
                    "«relative»: a zero re-set per temperature would leave a common shift unbounded",
                    "the field at or above 30 mT, the row's only condition (AMR saturation starts at 20 mT)",
                    "edge-on on a lead-free end at the nominal body length (no tolerance read)"]},
    # TDK «TMR Angle Sensor TAS series» catalog (November 2017; Mouser-hosted TDK document) TAS2141-AAAB: «Angle Error
    # (After compensation)» 0.6° max, T opt −40…150 °C, 20…80 mT; TCk «Temperature Coefficient of Amplitude Synchronism»
    # −0.015 / 0.015 %/K over the same span; the offset only as an initial ±5 mV/V, with no coefficient; «Shape &
    # dimensions (TSSOP8)»: 3.0 ± 0.2 × 4.4 ± 0.2 mm body; no die position printed.
    "TAS2141-AAAB": {
        "source": "TDK TMR Angle Sensor TAS series catalog (November 2017), TAS2141-AAAB characteristics and TSSOP8 shape",
        "operating_C": (-40.0, 150.0), "field_min_T": 0.020, "field_max_T": 0.080, "range_deg": 360.0,
        "total_deg": 0.6, "at_25C_deg": None, "lifetime_deg": None,
        "offset_tc_V_per_V_K": None, "amplitude_min_V_per_V": None, "amplitude_tc_min_per_K": None,
        "amplitude_tc_max_per_K": None, "mismatch_tc_per_K": 0.015e-2,
        "package": "TSSOP8, body 2.8–3.2 × 4.2–4.6 mm, die position not printed", "die_to_edge_mm": 2.8 / 2,
        "assumed": ["«after compensation» is not defined (when, of what) — read as a 25 °C compensation, the row as the "
                    "change from 25 °C (limit) ⊥ twice the row (limit_plus_25C)",
                    "the die at the package's centre (not printed), edge-on on a lead-free end at the shortest body"]},
    # NXP KMZ60 Product data sheet Rev. 2 (2014-02-07) Figs. 11–12: «start-up angle error after calibration» with pin
    # TCC_EN to VCC (TC compensation on) ⊥ to ground (off) — after one-point calibration at 25 °C, «from worst case
    # simulations», «related to 180 degree angular range of the MR sensor»; read off the page image (Fig. 11 at 300 dpi,
    # ±0.05°; Fig. 12 at 600 dpi by its crossings with the grid, ±0.02°). Hext ≥ 25 kA/m (31.4 mT). §1: the field «in the
    # surface parallel to the chip (x-y plane)», outputs cos(2α) · sin(2α). SO8 (SOT96-1): D 4.8–5.0, E 3.8–4.0 mm.
    "KMZ60": {
        "source": "NXP KMZ60 Product data sheet Rev. 2 (2014-02-07) Figs. 11–12 (read off the page images), SOT96-1",
        "operating_C": (-40.0, 150.0), "field_min_T": 4e-7 * math.pi * 25e3, "field_max_T": None, "range_deg": 180.0,
        "curves_deg": {"fig11_tcc_on": ((-40.0, 2.45), (0.0, 0.97), (25.0, 0.0), (60.0, 1.35), (80.0, 2.2)),
                       "fig12_tcc_off": ((-40.0, 0.36), (-20.0, 0.27), (0.0, 0.16), (25.0, 0.0), (40.0, 0.12),
                                         (60.0, 0.28), (80.0, 0.48))},
        "curve_read_tolerance_deg": {"fig11_tcc_on": 0.05, "fig12_tcc_off": 0.02},
        "degree_readings": {"field": 1.0, "electrical": 0.5}, "lifetime_deg": None,
        "offset_tc_V_per_V_K": None, "amplitude_min_V_per_V": None, "amplitude_tc_min_per_K": None,
        "amplitude_tc_max_per_K": None, "mismatch_tc_per_K": None,
        "package": "SO8 (SOT96-1), D 4.8–5.0 × E 3.8–4.0 mm, die position not printed", "die_to_edge_mm": 4.8 / 2,
        "assumed": ["the curves are worst-case SIMULATIONS, not guaranteed columns; read linearly between their points",
                    "«related to 180 degree angular range» read as degrees of the FIELD (the reading) ⊥ of the bridge's "
                    "doubled output angle (electrical: half the field error) — printed both ways, the verdict's flip",
                    "the AMR's 180° range: the reading wraps twice per period, so the unwrap floor on P doubles",
                    "the die at the package's centre (not printed), edge-on on a lead-free end at the shortest body"]},
}
ANGLE_SIZE_READINGS = ("limit", "limit_plus_25C")
ANGLE_SPREAD_READINGS = ("band_ends", "window_edge")


def base_lanes() -> dict:
    """The base row as the isothermal tables (2) · (2b) and the 2026-11-10/11 verdict (2c) read it: ONE offset drift per
    lane (typ ⊥ max — its datasheet gives one Boff_TC row for every axis and both branches, asserted), the X–Y ⊥ X–Z
    mismatch totals and angle errors, the X-axis noise, the linear ranges. A view of the table's row, not a second home."""
    r = SENSORS[BASE_SENSOR]
    rows = {r["offset_T_per_K"][ax][br] for ax in ("x", "z") for br in ("cold", "hot")}
    assert len(rows) == 1, "the base row's offset drift is no longer one row — (2) and (2c) read it as one"
    typ, mx = rows.pop()
    assert all(r["mismatch"][p]["cold"] == r["mismatch"][p]["hot"] for p in ("x_y", "x_z"))
    return {"offset_drift_T_per_K": {"typ": typ, "max": mx}, "noise_T": r["noise_T"]["x"],
            "sens_mismatch_drift": {p: r["mismatch"][p]["hot"][0] for p in ("x_y", "x_z")},
            "angle_error_deg": r["angle_error_deg"], "linear_range_T": r["ranges_T"]}


BASE = base_lanes()
# ams AS5311 (rev 1.13): supply current, power-up time; pole length 1.0 mm → a 2.0 mm magnetic period
ENCODER_2MM = {"i_supply_A": {"typ": 16e-3, "max": 21e-3}, "t_power_up_s": 20e-3, "period_mm": 2.0}
# The frames' temperature sensitivity — Natkon ZN11 «< 0.3 µm °C⁻¹» (Zweifel et al. 2021, New Phytol., Methods)
FRAME_UM_PER_K = 0.3
# Growth: P. sylvestris GRO.yr 795 µm and GRO.hr 2.29 µm h⁻¹ (Zweifel 2021 New Phytol. 10.1111/nph.17552, Table 1);
# 0.8 mm yr⁻¹ over 29 growth days (Etzold et al. 2022 Ecol. Lett. 10.1111/ele.13933); reliable resolution 1–5 µm
# (Zweifel et al. 2021 Front. For. Glob. Change 10.3389/ffgc.2021.776905, p. 9)
GROWTH = {"yr_um": 795.0, "hr_um": 2.29, "dry_site_um_per_growth_day": round(800.0 / 29.0, 1),
          "resolution_um": (1.0, 5.0)}
# 01_03 §4 ⊕ (в): the winter frost swing (our ×10 of the daily swing), the daily swing and the radial rate's ends
FROST_SWING_MM = (1.0, 2.0)
DAILY_SWING_MM = (0.1, 0.2)
RADIAL_RATE_MM_PER_YR = (0.8, 5.0)
GROWTH_MONTHS_MIN = 4.0                    # our assumption: the year's increment is laid down over at least four months
NOISE_TARGET_UM = 1.0
GAPS_MM = (1.5, 2.0, 3.0, 4.0)             # the radome wall's band, then the wall plus clearances (not in the tree)
SCALE_T_MM = (1.0, 2.0)
# The thickness knob (01_03 §4 ⊕ (в), desk 2026-11-10: «t 3–10 mm»), priced in its OWN block so the base table's
# population — which the canon's «one cell passes» and the in-place calibration span are quantified over — stays t 1–2 mm
SCALE_T_KNOB_MM = (3.0, 5.0, 10.0)
# Magnet families against the remanence a scale needs — mirror of 01_03 §4 ⊕ (в), desk 2026-11-10 (edit THERE): the
# range of specified MINIMA over each family's classes, IEC 60404-8-1:2001/AMD1:2004 Tables 11–12 (iTeh preview); sintered
# ferrite from MMPA 0100-00 Table III-1, TYPICAL values, not minima. A family «meets» a need when its highest value does —
# i.e. at least one of its classes; which class, and its corrosion and temperature coefficient, the canon says
MAGNET_FAMILIES_BR_T = {"RECo5": (0.80, 0.93), "RE2Co17": (0.90, 1.10), "REFeB_sintered": (0.98, 1.42),
                        "ferrite_sintered_typical": (0.23, 0.41)}
# B_r temperature coefficients per family, 1/K, as (kind end, adverse end) — mirror of 01_03 §4 ⊕ (в) (edit THERE): IEC
# 60404-8-1:2001/AMD1:2004, the TYPICAL values under Tables 11–12, for 20 °C to 100 °C (Table 12's note is in the preview's
# French) — RECo₅ −0.04, RE₂Co₁₇ −0.03, REFeB −0.10…−0.12 %/°C. Sintered ferrite: no coefficient in the tree, so (2c) solves it
# isothermally only
BR_TEMP_COEFF_PER_K = {"RECo5": (-0.04e-2, -0.04e-2), "RE2Co17": (-0.03e-2, -0.03e-2),
                       "REFeB_sintered": (-0.10e-2, -0.12e-2)}
# The class minima hold «at ambient temperature of (23 ± 5) °C» (IEC 60404-8-1:2023 §5.2) — the band's ends. A unit meeting
# its minimum at 18 °C is weaker at every temperature than one meeting it at 28 °C, so within a batch the band is a spread:
# the adverse corner judges the need on the 18 °C unit and the cap on the 28 °C one; the kind corner, a uniform batch at 28 °C
BR_REF_BAND_C = (18.0, 28.0)
HOT_HOUR_78 = ("sunlit_0.50", "sunlit_0.90")   # `78`'s hottest flange hour — (kind: the ratified α ≤ 0.5, adverse: dark)
UNWRAP_FLOOR_BASIS = "cross_season_outage"     # the unwrap basis the period must clear for «holds with the unwrap floor»
CLASS_SPREAD = (0.03, 0.05)   # an ASSUMED spread of a unit above its class minimum — the standard sets no upper limit
GAP_REALISTIC_MM = 3.0                     # 01_03 §4 ⊕ (в): the assumed floor of a realistic gap (the wall plus clearances)
VERDICT_LANE = "80mT:max"                  # the canon's verdict lane: the ±80 mT range, the guaranteed (maximum) drift
TIE_SHALLOWEST_MM = 0.5                   # `103`'s DEPTH_MIN — its tie axis starts here
LIFE_YR = 20.0                             # the field product's design life (01_03 §4; a goal, not a property)


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def anchor_sections(z103: dict, premise: str, shank: str) -> list[tuple[float, float, float]]:
    """The anchor from the flange seat down, as (from_mm, to_mm, α in 1/K): `103`'s premise, the Zone-1 shank bonded
    by its fit or the sleeve resting on the gyroid's shoulder (PEEK down to it)."""
    g, inp = z103["geometry"], z103["inputs"]
    span, z1 = g["span_mm"], g["zone1_shank_in_sleeve"]
    if premise == "flange_on_bark":
        top = [(0.0, span, ALPHA_PEEK_1K)]
    else:
        z3 = z103["zone3_fit"]
        run, gap = z3["sections_mm"]["composite_run"], z3["sections_mm"]["peek_gap"]
        top = [(run[0], run[1], z3["alpha_composite_ppm_K"] * 1e-6), (gap[0], gap[1], ALPHA_PEEK_1K)]
    shank_end = span + z1["length_mm"]
    shank_alpha = z1["alpha_bonded_ppm_K"] * 1e-6 if shank == "bonded" else ALPHA_PEEK_1K
    return [*top, (span, shank_end, shank_alpha),
            (shank_end, shank_end + g["anode_length_mm"], inp["alpha_anode_ppm_K"] * 1e-6)]


def anchor_term_um_per_k(sections, z_f: float, alpha_w: float) -> float:
    """∫₀^{z_f} (α_w − α_anchor) dz in µm/K (lengths in mm)."""
    s = 0.0
    for a, b, alpha in sections:
        hi = min(b, z_f)
        if hi > a:
            s += (alpha_w - alpha) * (hi - a)
    return s * 1e3


def artefact_um_per_k(sections, z_f, z_t, h, alpha_w, alpha_s, alpha_h) -> float:
    return anchor_term_um_per_k(sections, z_f, alpha_w) + ((alpha_s - alpha_w) * z_t + (alpha_s - alpha_h) * h) * 1e3


def alpha_at(sections, z: float) -> float:
    return next(al for a, b, al in sections if a <= z < b) if z < sections[-1][1] else sections[-1][2]


def peek_in_path_mm(sections, z_f: float) -> float:
    return sum(max(0.0, min(b, z_f) - a) for a, b, al in sections if al == ALPHA_PEEK_1K)


def frames_crossing_mm(sections, alpha_w: float) -> float | None:
    """The exact depth at which |A| reaches the frames' sensitivity (A is linear inside each section)."""
    acc = 0.0
    for a, b, alpha in sections:
        slope = (alpha - alpha_w) * 1e3                       # |A| per mm here (positive: control 7)
        if acc + slope * (b - a) >= FRAME_UM_PER_K:
            return a + (FRAME_UM_PER_K - acc) / slope
        acc += slope * (b - a)
    return None


def field_amplitude_t(b_r: float, p_mm: float, t_mm: float, g_mm: float) -> float:
    k = 2 * math.pi / p_mm
    return 0.5 * b_r * (1 - math.exp(-k * t_mm)) * math.exp(-k * g_mm)


def best_period_mm(t_mm: float, g_mm: float, step: float = 0.01, p_max_mm: float | None = None) -> float:
    """The period minimising the offset term at the gap — B_r and δB only scale it, so they do not move it. With
    `p_max_mm` the scan stops there: the best period the sensor's linear range allows (see `period_cap_mm`)."""
    grid = np.arange(0.5, 60.0 + step, step)      # below 0.5 mm e^{−kg} underflows; the optimum is far above it
    if p_max_mm is not None:
        grid = grid[grid <= p_max_mm + 1e-9]
    k = 2 * np.pi / grid
    cost = grid / ((1 - np.exp(-k * t_mm)) * np.exp(-k * g_mm))
    return round(float(grid[int(np.argmin(cost))]), 2)


def period_cap_mm(linear_range_t: float, db_per_k: float, target_um_per_k: float) -> float:
    """The longest period at which the field the offset term NEEDS stays inside the sensor's linear range. That field is
    P·√2·δB/(2π·target) — the period alone sets it, not the magnet and not the scale's thickness (control 4's identity)."""
    return 2 * math.pi * target_um_per_k * 1e-3 * linear_range_t / (math.sqrt(2) * db_per_k)


def families_meeting(need_t: float) -> list[str]:
    """The magnet families with at least one class at or above `need_t` (their highest value in MAGNET_FAMILIES_BR_T)."""
    return [f for f, (_lo, hi) in MAGNET_FAMILIES_BR_T.items() if hi >= need_t]


def b_r_needed_t(p_mm, t_mm, g_mm, db_per_k, target_um_per_k) -> float:
    """The remanence at which the offset drift on both components moves the reading by `target` µm/K."""
    k = 2 * math.pi / p_mm
    return (2 * p_mm / (2 * math.pi) * math.sqrt(2) * db_per_k
            / (target_um_per_k * 1e-3 * (1 - math.exp(-k * t_mm)) * math.exp(-k * g_mm)))


def scale_cell(t_mm: float, g: float, wall_mm: float) -> dict:
    """One (thickness, gap) row of the scale behind the wall — the ONE home of the row, for the base table and the
    thickness knob alike."""
    p = best_period_mm(t_mm, g)
    need_raw = {k: b_r_needed_t(p, t_mm, g, db, FRAME_UM_PER_K) for k, db in BASE["offset_drift_T_per_K"].items()}
    need = {k: round(v, 3) for k, v in need_raw.items()}
    b_sensor = {k: round(field_amplitude_t(br, p, t_mm, g) * 1e3, 1) for k, br in need.items()}
    n_conv = {}
    for k, br in need.items():
        noise = p / (2 * math.pi) * BASE["noise_T"] / field_amplitude_t(br, p, t_mm, g) * 1e3
        n_conv[k] = max(1, math.ceil((noise / NOISE_TARGET_UM) ** 2))
    pairs = {}
    for pair in ("x_y", "x_z"):
        eps = BASE["sens_mismatch_drift"][pair]
        peak = p / (2 * math.pi) * eps / 2 * 1e3
        pairs[pair] = {"angle_error_static_cyclic_um": round(p * BASE["angle_error_deg"][pair] / 360 * 1e3, 1),
                       "mismatch_drift_cyclic_peak_um_over_datasheet_drift": round(peak, 1),
                       "mismatch_um_per_K_if_linear_over_K": [round(peak / dk, 2) for dk in MISMATCH_LINEAR_SPREAD_K[::-1]]}
    within_range = {}
    for lin in BASE["linear_range_T"]:
        for drift, db in BASE["offset_drift_T_per_K"].items():
            cap = period_cap_mm(lin, db, FRAME_UM_PER_K)
            p_in = best_period_mm(t_mm, g, p_max_mm=cap)
            need_in = b_r_needed_t(p_in, t_mm, g, db, FRAME_UM_PER_K)
            within_range[f"{lin * 1e3:g}mT:{drift}"] = {
                "period_cap_mm": round(cap, 2), "best_period_within_cap_mm": p_in, "capped": p_in < p,
                "b_r_needed_T": round(need_in, 3), "magnet_families_meeting": families_meeting(need_in),
                "angle_error_static_cyclic_um": {pr: round(p_in * BASE["angle_error_deg"][pr] / 360 * 1e3, 1)
                                                 for pr in ("x_y", "x_z")},
                "mismatch_drift_cyclic_peak_um": {pr: round(p_in / (2 * math.pi) * BASE["sens_mismatch_drift"][pr] / 2 * 1e3, 1)
                                                  for pr in ("x_y", "x_z")}}
    return {
        "t_mm": t_mm, "g_mm": g, "best_period_mm": p, "half_period_mm": round(p / 2, 3),
        "b_r_needed_T_offset_term_only": need, "field_at_sensor_mT_at_needed_b_r": b_sensor,
        "within_linear_range_40mT": {k: v <= BASE["linear_range_T"][0] * 1e3 for k, v in b_sensor.items()},
        "within_linear_range_80mT": {k: v <= BASE["linear_range_T"][1] * 1e3 for k, v in b_sensor.items()},
        "two_channel_samples_for_1um_at_needed_b_r": n_conv, "axis_pairs": pairs,
        "surface_field_share_kept_by_2mm_period": float(f"{math.exp(-2 * math.pi * g / ENCODER_2MM['period_mm']):.2e}"),
        "gap_below_radome_wall": g < wall_mm,
        "in_place_angle_calibration_yr_fast_slow": [round(p / RADIAL_RATE_MM_PER_YR[1], 1),
                                                    round(p / RADIAL_RATE_MM_PER_YR[0], 1)],
        "magnet_families_meeting_at_p_star": {k: families_meeting(v) for k, v in need_raw.items()},
        "within_sensor_linear_range": within_range}


# ── (2c) the magnet's temperature: the two absolute bounds at opposite ends, the limits solved ──
def thermal_factor(alpha: float, t_c: float, t_ref: float) -> float:
    """B_r(T) / B_r(T_ref) on the linear coefficient — T_ref is the temperature a unit meets its class minimum at."""
    return 1.0 + alpha * (t_c - t_ref)


def lane_parts(lane: str) -> tuple[float, float]:
    lin_mt, drift = lane.split("mT:")
    return float(lin_mt) * 1e-3, BASE["offset_drift_T_per_K"][drift]


def period_cap_thermal_mm(lane: str, a: tuple) -> float:
    """The cap a period fixed for the batch keeps: the weakest unit (its minimum met at `t_ref_need`) must clear the need at
    the hot end, the strongest (met at `t_ref_cap`, then `spread` above it) must stay inside the range at the cold end —
    P_cap·f(T_hot; t_ref_need)/f(T_cold; t_ref_cap)/(1 + spread)."""
    alpha, t_ref_need, t_ref_cap, t_hot, t_cold, spread = a
    lin, db = lane_parts(lane)
    return (period_cap_mm(lin, db, FRAME_UM_PER_K) * thermal_factor(alpha, t_hot, t_ref_need)
            / thermal_factor(alpha, t_cold, t_ref_cap) / (1.0 + spread))


def best_period_cont_mm(t_mm: float, g_mm: float) -> float:
    """P* over a continuous period (the tables scan a 0.01 mm grid). The log of the cost is convex in 2π/P, so the cost
    is unimodal in P and the minimum over P ≤ cap is min(P*, cap) — asserted in control 9, which cannot fail on this form."""
    r = minimize_scalar(lambda p: b_r_needed_t(p, t_mm, g_mm, 1.0, 1.0), bounds=(0.5, 60.0), method="bounded",
                        options={"xatol": 1e-9})
    return float(r.x)


def need_at_ref(t_mm: float, g_mm: float, lane: str, a: tuple) -> tuple[float, float]:
    """The B_r a class minimum must reach (at T_ref), and the period it is read at: the hot-end need at the best period
    inside the thermal cap."""
    alpha, t_ref_need, _t_ref_cap, t_hot, _t_cold, _s = a
    _lin, db = lane_parts(lane)
    p = min(best_period_cont_mm(t_mm, g_mm), period_cap_thermal_mm(lane, a))
    return b_r_needed_t(p, t_mm, g_mm, db, FRAME_UM_PER_K) / thermal_factor(alpha, t_hot, t_ref_need), p


def gap_limit_mm(t_mm: float, lane: str, a: tuple, b_r_max: float) -> float | None:
    """The gap at which the need reaches `b_r_max` — it rises strictly with g (control 9), so the root is unique;
    None if even 0.2 mm needs more. The offset and range bounds only — not the unwrap floor (`holds_with_unwrap_floor`)."""
    def f(g):
        return need_at_ref(t_mm, g, lane, a)[0] - b_r_max
    if f(0.2) > 0:
        return None
    assert f(40.0) > 0, (t_mm, lane, a, b_r_max)
    return float(brentq(f, 0.2, 40.0, xtol=1e-10))


def thickness_limit_mm(g_mm: float, lane: str, a: tuple, b_r_max: float) -> float | None:
    """The thickness from which the need falls to `b_r_max` — it falls strictly with t (control 9); None if even an
    infinitely thick scale needs more (that limit is printed beside it)."""
    def f(t):
        return need_at_ref(t, g_mm, lane, a)[0] - b_r_max
    if f(1e4) >= 0:
        return None
    assert f(0.05) > 0, (g_mm, lane, a, b_r_max)
    return float(brentq(f, 0.05, 1e4, xtol=1e-10))


def window_holds(t_mm: float, g_mm: float, lane: str, a: tuple, fam: str, p_floor: float, step: float = 0.001) -> bool:
    """Brute force over the period: is there P in [p_floor, cap] at which SOME class of the family (its minima span,
    MAGNET_FAMILIES_BR_T) clears the hot-end need and stays inside the range at the cold end? With p_floor 0.5 this is
    «holds» recomposed without the analytic derivation (control 9); with the unwrap floor, «holds with the unwrap floor»."""
    alpha, t_ref_need, t_ref_cap, t_hot, t_cold, spread = a
    lin, db = lane_parts(lane)
    lo, hi = MAGNET_FAMILIES_BR_T[fam]
    cap = min(60.0, period_cap_thermal_mm(lane, a))
    if cap < p_floor:
        return False
    p = np.arange(p_floor, cap + step / 2, step)
    k = 2 * np.pi / p
    geom = (1 - np.exp(-k * t_mm)) * np.exp(-k * g_mm)
    need = 2 * p / (2 * np.pi) * math.sqrt(2) * db / (FRAME_UM_PER_K * 1e-3 * geom) / thermal_factor(alpha, t_hot, t_ref_need)
    lin_b = 2 * lin / (geom * thermal_factor(alpha, t_cold, t_ref_cap) * (1.0 + spread))
    return bool(np.any((need <= hi) & (lin_b >= lo) & (need <= lin_b)))


def magnet_temperature(t_hots: dict, colds: dict, rows: dict, unwrap_floor_mm: float, two_month_floor_mm: float) -> dict:
    """(2c) on the verdict lane: thermal caps per family and corner, the need per grid cell, «holds» with and without the
    unwrap floor, the gap limit per family × thickness and the thickness limit at the realistic gap — each corner beside
    the isothermal solve; the class-spread sensitivity; the hot hour at which the t 2 mm scale on 3 mm breaks even;
    sintered ferrite solved isothermally; whether each cap clears the period a two-month unwrap basis needs."""
    corners = {"isothermal": None,
               "kind": {"coefficient_end": 0, "t_ref_need_C": BR_REF_BAND_C[1], "t_ref_cap_C": BR_REF_BAND_C[1],
                        "hot": HOT_HOUR_78[0], "cold": "air_era5_min"},
               "adverse": {"coefficient_end": 1, "t_ref_need_C": BR_REF_BAND_C[0], "t_ref_cap_C": BR_REF_BAND_C[1],
                           "hot": HOT_HOUR_78[1], "cold": "capsule_sky_edge_81"}}

    def args(fam, corner, spread=0.0):
        c = corners[corner]
        if c is None:
            return 0.0, 20.0, 20.0, 20.0, 20.0, spread
        return (BR_TEMP_COEFF_PER_K[fam][c["coefficient_end"]], c["t_ref_need_C"], c["t_ref_cap_C"], t_hots[c["hot"]],
                colds[c["cold"]], spread)

    fams = list(BR_TEMP_COEFF_PER_K)
    caps = {f: {c: period_cap_thermal_mm(VERDICT_LANE, args(f, c)) for c in corners} for f in fams}
    cells = {}
    for key, row in rows.items():
        t, g = row["t_mm"], row["g_mm"]
        need = {f"{f}:{c}": need_at_ref(t, g, VERDICT_LANE, args(f, c))[0] for f in fams for c in corners}
        cells[key] = {"t_mm": t, "g_mm": g, "need_T": need,
                      "holds": {c: [f for f in fams if MAGNET_FAMILIES_BR_T[f][1] >= need[f"{f}:{c}"]] for c in corners},
                      "holds_with_unwrap_floor": {c: [f for f in fams if window_holds(t, g, VERDICT_LANE, args(f, c), f,
                                                                                       unwrap_floor_mm)] for c in corners}}
    ts = sorted({r["t_mm"] for r in rows.values()})
    gaps = {f: {f"t{t:g}": {c: gap_limit_mm(t, VERDICT_LANE, args(f, c), MAGNET_FAMILIES_BR_T[f][1]) for c in corners}
                for t in ts} for f in fams}
    thick = {f: {c: thickness_limit_mm(GAP_REALISTIC_MM, VERDICT_LANE, args(f, c), MAGNET_FAMILIES_BR_T[f][1])
                 for c in corners} for f in fams}
    t_inf = {f: {c: need_at_ref(1e4, GAP_REALISTIC_MM, VERDICT_LANE, args(f, c))[0] for c in corners} for f in fams}
    spread = {f"{s:g}": {f: thickness_limit_mm(GAP_REALISTIC_MM, VERDICT_LANE, args(f, "adverse", s), MAGNET_FAMILIES_BR_T[f][1])
                         for f in fams} for s in CLASS_SPREAD}

    def break_even(corner):
        a = list(args("REFeB_sintered", corner))
        def f(t_hot):
            a[3] = t_hot
            return need_at_ref(2.0, GAP_REALISTIC_MM, VERDICT_LANE, tuple(a))[0] - MAGNET_FAMILIES_BR_T["REFeB_sintered"][1]
        return float(brentq(f, -20.0, 150.0, xtol=1e-9))

    fer_max = MAGNET_FAMILIES_BR_T["ferrite_sintered_typical"][1]
    iso = (0.0, 20.0, 20.0, 20.0, 20.0, 0.0)
    fer = "ferrite_sintered_typical"
    ferrite = {lane: {"gap_limit_mm": {f"t{t:g}": gap_limit_mm(t, lane, iso, fer_max) for t in ts},
                      "thickness_limit_mm": {f"g{g:g}": thickness_limit_mm(g, lane, iso, fer_max) for g in (3.0, 4.0)}}
               for lane in (VERDICT_LANE, "80mT:typ")}
    ferrite[VERDICT_LANE]["holds_with_unwrap_floor"] = [k for k, r in rows.items()
                                                        if window_holds(r["t_mm"], r["g_mm"], VERDICT_LANE, iso, fer, unwrap_floor_mm)]
    return {"lane": VERDICT_LANE, "corners": corners, "unwrap_floor_mm": unwrap_floor_mm,
            "period_cap_mm": caps, "cells": cells, "gap_limit_mm": gaps,
            "thickness_limit_mm_at_realistic_gap": thick, "need_T_at_infinite_thickness_at_realistic_gap": t_inf,
            "thickness_limit_mm_at_realistic_gap_adverse_by_class_spread": spread,
            "hot_hour_C_at_which_t2_on_3mm_REFeB_breaks_even": {c: break_even(c) for c in ("kind", "adverse")},
            "ferrite_isothermal": {"family_max_T_typical": fer_max, "by_lane": ferrite},
            "two_month_unwrap_period_mm": two_month_floor_mm,
            "period_cap_clears_two_month_unwrap_period": {f: {c: caps[f][c] >= two_month_floor_mm for c in corners} for f in fams},
            "_args": args}


def control_temperature(mt: dict, rows: dict, t_hots: dict, colds: dict, z81: dict, hours: dict) -> None:
    """Control 9 — see the docstring's CONTROLS."""
    args, lane = mt["_args"], mt["lane"]
    lin, db = lane_parts(lane)
    i_min = int(np.argmin(hours["t_air"]))
    # «that morning»: 81's deepest edge falls on the record's coldest air hour, and that hour is this record's
    assert z81["edges"]["deep"]["at"] == z81["air"]["at"] == str(hours["time"][i_min])[:16], (z81["air"]["at"], hours["time"][i_min])
    assert abs(z81["air"]["coldest_c"] - colds["air_era5_min"]) < 0.05
    assert colds["capsule_sky_edge_81"] < colds["air_era5_min"] < min(t_hots.values())
    for fam in BR_TEMP_COEFF_PER_K:
        for corner in ("kind", "adverse"):
            a = args(fam, corner)
            alpha, tn, tcap, th, tc, _s = a
            cap = period_cap_thermal_mm(lane, a)
            # the window closes at the cap: the weakest unit's hot-end need there, put on the sensor by the strongest
            # unit at the cold end, fills the range
            b_need_cap = b_r_needed_t(cap, 2.0, GAP_REALISTIC_MM, db, FRAME_UM_PER_K) / thermal_factor(alpha, th, tn)
            cold_field = field_amplitude_t(b_need_cap * thermal_factor(alpha, tc, tcap), cap, 2.0, GAP_REALISTIC_MM)
            assert abs(cold_field - lin) < 1e-12, (fam, corner, cold_field)
        # each input moved ALONE from its kind to its adverse value never lowers the need, in every cell
        ak, aa = args(fam, "kind"), args(fam, "adverse")
        for key in rows:
            t, g = rows[key]["t_mm"], rows[key]["g_mm"]
            nk = need_at_ref(t, g, lane, ak)[0]
            for i in range(5):
                moved = list(ak)
                moved[i] = aa[i]
                assert need_at_ref(t, g, lane, tuple(moved))[0] >= nk - 1e-12, (fam, key, i)
        for key, cell in mt["cells"].items():
            ni, nk, na = (cell["need_T"][f"{fam}:{c}"] for c in ("isothermal", "kind", "adverse"))
            assert ni <= nk + 1e-12 and nk <= na + 1e-12, (fam, key, ni, nk, na)
    for key, row in rows.items():
        t, g = row["t_mm"], row["g_mm"]
        d = np.diff([b_r_needed_t(p, t, g, db, FRAME_UM_PER_K) for p in np.arange(0.5, 60.0, 0.05)])
        assert np.all(np.diff(np.sign(d)) >= 0) and (d < 0).any() and (d > 0).any(), (key, "cost not unimodal")
        grid = b_r_needed_t(best_period_mm(t, g, p_max_mm=period_cap_mm(lin, db, FRAME_UM_PER_K)), t, g, db, FRAME_UM_PER_K)
        cont = mt["cells"][key]["need_T"]["REFeB_sintered:isothermal"]
        assert 0.0 <= grid - cont <= 2e-3 * grid, (key, grid, cont)
    ts = sorted({r["t_mm"] for r in rows.values()})
    for fam in BR_TEMP_COEFF_PER_K:
        b_max = MAGNET_FAMILIES_BR_T[fam][1]
        for corner in ("isothermal", "kind", "adverse"):
            a = args(fam, corner)
            for t in ts:
                ng = [need_at_ref(t, g, lane, a)[0] for g in np.linspace(0.5, 6.0, 56)]
                assert all(x < y for x, y in itertools.pairwise(ng)), (fam, corner, t, "need not rising with the gap")
                glim = mt["gap_limit_mm"][fam][f"t{t:g}"][corner]
                if glim is not None:
                    assert abs(need_at_ref(t, glim, lane, a)[0] - b_max) < 1e-9, (fam, corner, t)
                for g in GAPS_MM:
                    cell = mt["cells"][f"t{t:g}:g{g:g}"]
                    holds = fam in cell["holds"][corner]
                    assert holds == (glim is not None and g <= glim), (fam, corner, t, g, glim, "grid ≠ solve")
                    # «holds» recomposed by brute force over the period, in BOTH directions (skip a knife-edge cell)
                    if abs(cell["need_T"][f"{fam}:{corner}"] - b_max) > 2e-3 * b_max:
                        assert window_holds(t, g, lane, a, fam, 0.5, step=0.002) == holds, (fam, corner, t, g, "brute ≠ holds")
                    floor_holds = fam in cell["holds_with_unwrap_floor"][corner]
                    assert not floor_holds or holds, (fam, corner, t, g, "the floor admitted a cell «holds» refuses")
                    if g >= GAP_REALISTIC_MM:   # the prose: from the realistic gap up the floor changes no verdict
                        assert floor_holds == holds, (fam, corner, t, g, "the floor bites at the realistic gap")
            nt = [need_at_ref(t, GAP_REALISTIC_MM, lane, a)[0] for t in np.geomspace(0.1, 30.0, 60)]
            # up to 30 mm: past it 1 − e^{−kt} rounds to 1.0 in floats and the need is flat to the last bit
            assert all(x > y for x, y in itertools.pairwise(nt)), (fam, corner, "need not falling with the thickness")
            tlim = mt["thickness_limit_mm_at_realistic_gap"][fam][corner]
            if tlim is None:
                assert mt["need_T_at_infinite_thickness_at_realistic_gap"][fam][corner] > b_max
            else:
                assert abs(need_at_ref(tlim, GAP_REALISTIC_MM, lane, a)[0] - b_max) < 1e-9, (fam, corner)
        # a spread above the minimum only shortens the cap, so it never lowers a thickness limit
        for s, by_f in mt["thickness_limit_mm_at_realistic_gap_adverse_by_class_spread"].items():
            base, moved = mt["thickness_limit_mm_at_realistic_gap"][fam]["adverse"], by_f[fam]
            assert (base is None and moved is None) or (moved is None) or (moved >= base - 1e-9), (fam, s, base, moved)
            if moved is not None:   # each spread root returns the family's maximum too
                assert abs(need_at_ref(moved, GAP_REALISTIC_MM, lane, args(fam, "adverse", float(s)))[0] - b_max) < 1e-9, (fam, s)
    fe, fer_max, iso = mt["ferrite_isothermal"]["by_lane"], MAGNET_FAMILIES_BR_T["ferrite_sintered_typical"][1], args("RECo5", "isothermal")
    for fl, v in fe.items():   # the ferrite roots return its maximum
        for tk, glim in v["gap_limit_mm"].items():
            assert glim is not None and abs(need_at_ref(float(tk[1:]), glim, fl, iso)[0] - fer_max) < 1e-9, (fl, tk)
        for gk, tlim in v["thickness_limit_mm"].items():
            if tlim is None:
                assert need_at_ref(1e4, float(gk[1:]), fl, iso)[0] > fer_max, (fl, gk)
            else:
                assert abs(need_at_ref(tlim, float(gk[1:]), fl, iso)[0] - fer_max) < 1e-9, (fl, gk)
    for key in fe[lane]["holds_with_unwrap_floor"]:   # the floor never admits a ferrite cell its gap limit refuses
        assert rows[key]["g_mm"] <= fe[lane]["gap_limit_mm"][f"t{rows[key]['t_mm']:g}"], key
    for corner, t_be in mt["hot_hour_C_at_which_t2_on_3mm_REFeB_breaks_even"].items():
        a = list(args("REFeB_sintered", corner))
        a[3] = t_be
        assert abs(need_at_ref(2.0, GAP_REALISTIC_MM, lane, tuple(a))[0] - MAGNET_FAMILIES_BR_T["REFeB_sintered"][1]) < 1e-9


# ── (2d) the sensor table: the offset AND the mismatch term in one verdict, each branch at its own temperature edge ──
PAIR_AXES = {"x_y": ("x", "x"), "x_z": ("x", "z")}   # X and Y share one row in every datasheet read (SENSORS)
VERDICT_GAPS_MM = (3.0, 4.0)
VERDICT_FAMILIES = ("REFeB_sintered", "RE2Co17", "RECo5")
TARGET_MM = FRAME_UM_PER_K * 1e-3                    # the frames' 0.3 µm/K, in mm/K


def per_k(row: dict, pair: str, kind: int) -> dict:
    """Per branch: the pair's offset drift √(δa² + δb²) in T/K and its mismatch drift per kelvin, on the typical (kind 0)
    or guaranteed (kind 1) column. Where the guaranteed mismatch column is absent the typical one stands in, flagged.
    The mismatch per kelvin follows the row's declared basis: a per-kelvin row as read; a total from 25 °C over the
    branch's span (`BRANCH_SPAN_K`, or the row's own `branch_span_K` where its band ends short of +125 °C) — the
    datasheet's own linear statement ⊥ our assumption for a total with no ΔT. The offset follows its basis the same way
    (a per-kelvin row ⊥ a total over the band); a column the datasheet leaves empty stays None."""
    a, b = PAIR_AXES[pair]
    span = row.get("branch_span_K", BRANCH_SPAN_K)
    out = {"dbp_T_per_K": {}, "eps_per_K": {}, "mismatch_column": {}}
    for br in ("cold", "hot"):
        if row["offset_basis"] == "per_K":
            oa, ob = row["offset_T_per_K"][a][br][kind], row["offset_T_per_K"][b][br][kind]
        else:
            ta, tb = row["offset_T_total"][a][br][kind], row["offset_T_total"][b][br][kind]
            oa, ob = (None, None) if ta is None or tb is None else (ta / span[br], tb / span[br])
        out["dbp_T_per_K"][br] = None if oa is None or ob is None else math.hypot(oa, ob)
        m, col = row["mismatch"][pair][br][kind], ("typical", "guaranteed")[kind]
        if m is None:
            m, col = row["mismatch"][pair][br][0], "typical (no guaranteed column)"
        if m is None:
            out["eps_per_K"][br], out["mismatch_column"][br] = None, "not given"
            continue
        out["eps_per_K"][br] = m if row["mismatch_basis"] == "per_K" else m / span[br]
        out["mismatch_column"][br] = col
    return out


def make_lane(row: dict, pair: str, kind: int, with_mismatch: bool) -> dict:
    pk = per_k(row, pair, kind)
    return {"lin_T": row["verdict_range_T"], "dbp": pk["dbp_T_per_K"],
            "eps": {br: (pk["eps_per_K"][br] if with_mismatch else 0.0) for br in ("cold", "hot")}}


BRANCH_SPLIT_C = 25.0   # the datasheets' drifts are «from 25 °C»: below it the cold branch's slope, above it the hot one's


def edge_factors(a: tuple) -> dict:
    """The weakest unit's B_r where each branch binds, over B_r at the reference it meets its minimum at. A branch's
    per-kelvin drift holds over its whole band, and the offset term divides by the field, so each branch binds where its
    band's field is WEAKEST (§When Modifying #50): the hot branch at the hottest hour, the cold branch at its warm end,
    25 °C — at the cold edge itself the field is stronger. (The range bound reads the coldest hour, in the cap.)"""
    alpha, t_ref_need, _t_ref_cap, t_hot, _t_cold, _s = a
    return {"hot": thermal_factor(alpha, t_hot, t_ref_need), "cold": thermal_factor(alpha, BRANCH_SPLIT_C, t_ref_need)}


def cap_lane_mm(lane: dict, a: tuple) -> float:
    """The longest period a batch keeps under the sum rule: per branch the field the weakest unit must put on the
    sensor, P·δB_pair/(2π·(T − P·ε/4π)), over f where that branch binds (`edge_factors`) — once put on the sensor by
    the strongest unit at the coldest hour —
    stays inside the range. Each edge is linear-fractional in P, so the cap is min over edges of B*·T/(K + B*·c),
    K = δB_pair/(2π·f), c = ε/(4π), B* = B_lin/(f_cap(T_cold)·(1 + s)); with ε = 0 it is `period_cap_thermal_mm`."""
    alpha, _t_ref_need, t_ref_cap, _t_hot, t_cold, spread = a
    f, b_star = edge_factors(a), lane["lin_T"] / (thermal_factor(alpha, t_cold, t_ref_cap) * (1.0 + spread))
    caps = []
    for e in ("cold", "hot"):
        k_e, c_e = lane["dbp"][e] / (2 * math.pi * f[e]), lane["eps"][e] / (4 * math.pi)
        caps.append(math.inf if k_e == 0.0 and c_e == 0.0 else b_star * TARGET_MM / (k_e + b_star * c_e))
    return min(caps)


def need_br_lane(p: float, t_mm: float, g_mm: float, lane: dict, f: dict) -> float:
    """The class minimum (at T_ref) the sum rule needs at period p: per branch the offset term takes what the mismatch
    term leaves of the frames' 0.3 µm/K — B_r = 2·P·δB_pair/(2π·(T − P·ε/4π)·geom·f) — and the binding branch decides."""
    k = 2 * math.pi / p
    geom = (1 - math.exp(-k * t_mm)) * math.exp(-k * g_mm)
    worst = 0.0
    for e in ("cold", "hot"):
        left = TARGET_MM - p * lane["eps"][e] / (4 * math.pi)
        if left <= 0.0:
            return math.inf
        worst = max(worst, p * lane["dbp"][e] / (2 * math.pi * left * f[e]))
    return 2 * worst / geom


def need_lane(t_mm: float, g_mm: float, lane: dict, a: tuple, p_floor: float = 0.5) -> tuple[float, float | None]:
    """(the least need over P in [max(0.5, p_floor), min(60, cap)], the P it is read at). Offset only (ε = 0) every edge
    term is one shape times a constant, so the least sits at P* clipped into the window (unimodal, as (2c)); with a
    mismatch term the window is searched by a bounded scalar minimisation and its two ends — and control 10 holds every
    solved cell against a brute force over the window, so a second minimum the search missed reds."""
    f = edge_factors(a)
    lo, hi = max(0.5, p_floor), min(60.0, cap_lane_mm(lane, a))
    if lo > hi:
        return math.inf, None
    if lane["eps"]["cold"] == 0.0 and lane["eps"]["hot"] == 0.0:
        p = min(max(best_period_cont_mm(t_mm, g_mm), lo), hi)
        return need_br_lane(p, t_mm, g_mm, lane, f), p
    r = minimize_scalar(lambda q: math.log(need_br_lane(q, t_mm, g_mm, lane, f)), bounds=(lo, hi), method="bounded",
                        options={"xatol": 1e-9})
    cands = [(need_br_lane(q, t_mm, g_mm, lane, f), q) for q in (float(r.x), lo, hi)]
    return min(cands)


def thickness_limit_lane(g_mm: float, lane: dict, a: tuple, b_r_max: float, p_floor: float = 0.5) -> float | None:
    """The thickness from which the sum rule's need falls to `b_r_max` — it falls strictly with t at every fixed P and
    the window does not depend on t, so the root is unique; None if an infinitely thick scale needs more."""
    def f(t):
        return need_lane(t, g_mm, lane, a, p_floor)[0] - b_r_max
    if f(1e4) >= 0:
        return None
    assert f(0.05) > 0, (g_mm, lane, a, b_r_max)
    return float(brentq(f, 0.05, 1e4, xtol=1e-10))


def gap_limit_lane(t_mm: float, lane: dict, a: tuple, b_r_max: float, p_floor: float = 0.5) -> float | None:
    """The gap at which the sum rule's need reaches `b_r_max` — it rises strictly with g at every fixed P and the window
    does not depend on g, so the root is unique; None if even 0.2 mm needs more."""
    def f(g):
        return need_lane(t_mm, g, lane, a, p_floor)[0] - b_r_max
    if f(0.2) > 0:
        return None
    assert f(40.0) > 0, (t_mm, lane, a, b_r_max)
    return float(brentq(f, 0.2, 40.0, xtol=1e-10))


LEVER_T_MM = 10.0     # the thickest scale (2b) prices — the gap a row holds there is the most a thickness buys on the grid


def mismatch_scale_to_hold(g_mm: float, row: dict, pair: str, a: tuple, b_r_max: float, p_floor: float) -> float | None:
    """The factor on the guaranteed mismatch drift (both branches) at or below which the family's strongest class holds
    the gap at an infinitely thick scale — the verdict's flip threshold in its binding member (§When Modifying #40).
    The need rises with the factor (the offset term's share shrinks and the cap with it), so the root is unique; None
    when even no mismatch at all does not hold (the offset and range bounds alone refuse the cell)."""
    def lane(s):
        ln = make_lane(row, pair, 1, True)
        return {**ln, "eps": {br: s * v for br, v in ln["eps"].items()}}

    def f(s):
        return need_lane(1e4, g_mm, lane(s), a, p_floor)[0] - b_r_max
    if f(0.0) >= 0:
        return None
    if f(1.0) <= 0:
        return 1.0
    return float(brentq(f, 0.0, 1.0, xtol=1e-12))


def sensor_table(args, t_hots: dict, colds: dict, unwrap_floor_mm: float) -> dict:
    """(2d) per row, axis pair, family, corner and gap: the thickness limit offset only ⊥ with the mismatch term ⊥ with it
    and the unwrap floor, the period each is read at, the caps; per row and pair the per-kelvin drifts, the period at
    which the mismatch alone takes the frames' 0.3 µm/K (typical ⊥ guaranteed), the read's energy on the verdict lane."""
    for row in SENSORS.values():   # a per-kelvin band row must cover the edge it is applied at
        lo_c, hi_c = row.get("mismatch_hot_band_C", (25.0, row["operating_C"][1]))
        assert lo_c <= 25.0 and max(t_hots.values()) <= hi_c and row["operating_C"][0] <= min(colds.values()), row["source"]
    corners = ("isothermal", "kind", "adverse")
    out = {}
    for name, row in SENSORS.items():
        pairs = {}
        for pair in PAIR_AXES:
            pk = {k: per_k(row, pair, i) for k, i in (("typical", 0), ("guaranteed", 1))}
            alone = {k: {br: (None if v["eps_per_K"][br] in (None, 0.0) else TARGET_MM * 4 * math.pi / v["eps_per_K"][br])
                         for br in ("cold", "hot")} for k, v in pk.items()}
            lanes = {"offset_only": make_lane(row, pair, 1, False), "with_mismatch": make_lane(row, pair, 1, True)}
            cells, caps = {}, {}
            for fam in VERDICT_FAMILIES:
                b_max = MAGNET_FAMILIES_BR_T[fam][1]
                for c in corners:
                    a = args(fam, c)
                    caps[f"{fam}:{c}"] = {k: cap_lane_mm(ln, a) for k, ln in lanes.items()}
                    for g in VERDICT_GAPS_MM:
                        cell = {}
                        for variant, ln, floor in (("offset_only", lanes["offset_only"], 0.5),
                                                   ("with_mismatch", lanes["with_mismatch"], 0.5),
                                                   ("with_mismatch_and_unwrap_floor", lanes["with_mismatch"], unwrap_floor_mm)):
                            t_lim = thickness_limit_lane(g, ln, a, b_max, floor)
                            n_inf, p_inf = need_lane(1e4, g, ln, a, floor)
                            cell[variant] = {"t_min_mm": t_lim,
                                             "p_mm": None if t_lim is None else need_lane(t_lim, g, ln, a, floor)[1],
                                             "need_T_at_infinite_thickness": None if math.isinf(n_inf) else n_inf,
                                             "p_mm_at_infinite_thickness": p_inf}
                        cells[f"{fam}:{c}:g{g:g}"] = cell
            # the levers: the gap each holds at the thickest scale priced, and the factor on the guaranteed mismatch drift
            # below which an infinitely thick scale holds each gap — against the typical/guaranteed ratio the row prints
            levers = {}
            for fam in VERDICT_FAMILIES[:2]:
                b_max = MAGNET_FAMILIES_BR_T[fam][1]
                for c in ("kind", "adverse"):
                    a = args(fam, c)
                    gl = {"offset_only": gap_limit_lane(LEVER_T_MM, lanes["offset_only"], a, b_max),
                          "with_mismatch": gap_limit_lane(LEVER_T_MM, lanes["with_mismatch"], a, b_max),
                          "with_mismatch_and_unwrap_floor": gap_limit_lane(LEVER_T_MM, lanes["with_mismatch"], a, b_max,
                                                                           unwrap_floor_mm)}
                    levers[f"{fam}:{c}"] = {
                        "gap_limit_mm_at_t10": gl,
                        "p_mm_at_the_gap_limit_with_mismatch": None if gl["with_mismatch"] is None else need_lane(
                            LEVER_T_MM, gl["with_mismatch"], lanes["with_mismatch"], a)[1],
                        "mismatch_scale_to_hold_at_infinite_thickness": {
                            f"g{g:g}": {"no_floor": mismatch_scale_to_hold(g, row, pair, a, b_max, 0.5),
                                        "with_unwrap_floor": mismatch_scale_to_hold(g, row, pair, a, b_max, unwrap_floor_mm)}
                            for g in VERDICT_GAPS_MM}}
                    # a BAND over a span is a set of readings (§When Modifying #11): spread over the span to the band's
                    # end (above, favourable) ⊥ reached already at the window's own edge, nearer 25 °C — a LESS
                    # favourable chord reading, not a ceiling: a band bounds the value, not the slope, and nearer 25 °C
                    # the same band is a larger per-kelvin figure without bound; printed for every row with a band basis
                    if "total_no_dT" in (row["offset_basis"], row["mismatch_basis"]):
                        *_, t_hot_c, t_cold_c, _s = a
                        span_e = {"cold": BRANCH_SPLIT_C - t_cold_c, "hot": t_hot_c - BRANCH_SPLIT_C}
                        row_e = {**row, "branch_span_K": span_e}
                        eb = row.get("band_at_window_edge")
                        if eb is not None:   # the band that covers the window's edge, both branches
                            assert eb["band_C"][0] <= t_cold_c and t_hot_c <= eb["band_C"][1], name
                            row_e["offset_T_total"] = {ax: dict.fromkeys(("cold", "hot"), (None, eb["offset_T"])) for ax in ("x", "z")}
                            row_e["mismatch"] = {p: dict.fromkeys(("cold", "hot"), (None, eb["mismatch"][p])) for p in PAIR_AXES}
                        ln_e = make_lane(row_e, pair, 1, True)
                        levers[f"{fam}:{c}"]["band_reached_at_the_window_edge"] = {
                            "span_K": span_e,
                            "gap_limit_mm_at_t10_with_mismatch": gap_limit_lane(LEVER_T_MM, ln_e, a, b_max),
                            "gap_limit_mm_at_t10_with_mismatch_and_unwrap_floor": gap_limit_lane(LEVER_T_MM, ln_e, a, b_max, unwrap_floor_mm),
                            "mismatch_scale_to_hold_at_infinite_thickness_no_floor": {
                                f"g{g:g}": mismatch_scale_to_hold(g, row_e, pair, a, b_max, 0.5) for g in VERDICT_GAPS_MM}}
            ratio = {br: (None if pk["typical"]["eps_per_K"][br] is None or not pk["guaranteed"]["eps_per_K"][br]
                          or "no guaranteed" in pk["guaranteed"]["mismatch_column"][br]
                          else pk["typical"]["eps_per_K"][br] / pk["guaranteed"]["eps_per_K"][br]) for br in ("cold", "hot")}
            # the read's energy on the verdict (guaranteed) lane: at the needed field the angle noise is at most
            # σ·0.3 µm/K / δB_pair (the mismatch term only raises the field), σ the noisier axis of the pair
            sig = max(row["noise_T"][ax] for ax in PAIR_AXES[pair])
            noise_um = sig * FRAME_UM_PER_K / min(pk["guaranteed"]["dbp_T_per_K"].values())
            n = max(1, math.ceil((noise_um / NOISE_TARGET_UM) ** 2))
            e = energy_j(row["i_active_A"] + I_CORE_RUN_A, V_OUT,
                         n * (row["t_conv_one_ch_s"] + row["t_add_ch_s"]) + sum(row["t_wake_s"])) / ETA_BUCK_ACTIVE
            # lifetime drifts (typical, where given): a STEP over the life, not per kelvin — the offset step at the
            # sensor's full range (the smallest it can be) at the offset-only adverse REFeB cap, and the cyclic peak the
            # per-axis sensitivity drift makes if the two axes drift apart (our reading: no mismatch lifetime row)
            life = None
            if row["lifetime"]:
                p_cap = caps["REFeB_sintered:adverse"]["offset_only"]
                life = {"offset_step_um_at_full_range_at_offset_only_adverse_REFeB_cap": round(
                            p_cap / (2 * math.pi) * math.hypot(row["lifetime"]["offset_T"], row["lifetime"]["offset_T"])
                            / row["verdict_range_T"] * 1e3, 2),
                        "mismatch_peak_um_if_the_axes_drift_apart_at_that_cap": round(
                            p_cap / (2 * math.pi) * 2 * row["lifetime"]["sensitivity"] / 2 * 1e3, 1),
                        "kind": row["lifetime"]["kind"]}
            pairs[pair] = {"per_K": pk, "mismatch_alone_takes_the_frames_at_period_mm": alone,
                           "mismatch_typical_over_guaranteed": ratio,
                           "caps_mm": caps, "cells": cells, "levers": levers,
                           "read": {"noise_um_upper_at_the_needed_field": round(noise_um, 3), "samples": n,
                                    "vstor_uJ": round(e * 1e6, 1), "share_of_E_cycle_pct": round(e / E_CYCLE * 100, 2)},
                           "lifetime": life}
        out[name] = {"source": row["source"], "verdict_range_T": row["verdict_range_T"],
                     "offset_basis": row["offset_basis"], "mismatch_basis": row["mismatch_basis"],
                     "assumed": row["assumed"], "pairs": pairs}
    return out


LIN_READINGS = {"raw": None, "from_25C": 1.0, "best_fit": 2.0}   # per member: the guaranteed per-kelvin row as read
# (no compensation) ⊥ a linear compensation whose residual changes by at most k·LIN from 25 °C (TI: a best-fit line,
# «typically referenced to the 25 °C point» — two different lines, so both are read)
# The OFFSET's readings: (k, the basis LIN is a % of). `range` — OUR full-scale reading (the verdict range), kept as the
# adverse bound; `total_drift` — TI's follow-up of 2026-11-18 (in a number, our step: the largest Boff_DR maximum times
# the full operating span), whose line is not held to 25 °C, hence k = 2 only. `from_25C` on the range is a control
# since that answer (no such line in it) — still computed, and counted apart.
OFFSET_LIN_READINGS = {"raw": None, "from_25C": (1.0, "range"), "best_fit": (2.0, "range"),
                       "ti_total_drift": (DRIFT_LIN_DEFINITION["offset_row_2026_11_18"]["from_25C_factor"], "total_drift")}
TI_OFFSET_KEY = ":offset_ti_total_drift:"   # the cell keys of TI's reading — counted beside ours, never among them


def offset_lin_residual_t(row: dict, basis: str) -> float:
    """L_off — the size LIN bounds, in tesla: LIN's % of the verdict range (`range`) ⊥ of the total offset drift over the
    full operating range, the largest guaranteed per-kelvin maximum of any axis and branch times the span (`total_drift`
    — TI's figure, 2026-11-18)."""
    pct = dict(row["drift_linearity"]["offset_pct_of_range_by_range_T"])[row["verdict_range_T"]]
    if basis == "range":
        return pct * row["verdict_range_T"]
    assert basis == "total_drift" and row["offset_basis"] == "per_K", (basis, row["offset_basis"])
    per_k = max(v[1] for axis in row["offset_T_per_K"].values() for v in axis.values())
    return pct * per_k * (row["operating_C"][1] - row["operating_C"][0])


def _t_lim_safe(g_mm: float, lane: dict, a: tuple, b_r_max: float, p_floor: float = 0.5) -> float | None:
    """`thickness_limit_lane`, with a lane that already holds at the thinnest computed scale returned as that scale."""
    if need_lane(0.05, g_mm, lane, a, p_floor)[0] <= b_r_max:
        return 0.05
    return thickness_limit_lane(g_mm, lane, a, b_r_max, p_floor)


def lin_lane(row: dict, pair: str, k_off: float | None, k_mis: float | None, d_t: dict, off_basis: str = "range") -> dict:
    """A lane under one reading of each member: None keeps the guaranteed per-kelvin row (no compensation), a k gives a
    per-unit LINEAR compensation read as a chord at the window's edge — ε′ = k·LIN/ΔT for the mismatch, δa′ = δb′ =
    k·L_off/ΔT for the offset (L_off — `offset_lin_residual_t` on `off_basis`: our full-scale reading of Boff_DR_LIN ⊥
    TI's total-drift one); ΔT the edge's distance from 25 °C, the most favourable point: nearer 25 °C the same residual
    is a larger per-kelvin figure."""
    lin = row["drift_linearity"]
    l_off = offset_lin_residual_t(row, off_basis)
    raw = make_lane(row, pair, 1, True)
    eps = dict(raw["eps"]) if k_mis is None else {br: k_mis * lin["mismatch"][pair] / d_t[br] for br in ("cold", "hot")}
    dbp = (dict(raw["dbp"]) if k_off is None
           else {br: math.hypot(k_off * l_off / d_t[br], k_off * l_off / d_t[br]) for br in ("cold", "hot")})
    return {"lin_T": row["verdict_range_T"], "dbp": dbp, "eps": eps}


def linearity_reading(args, floor_mm: float) -> dict:
    """(2e) the verdict for a per-unit LINEAR compensation of the drift, read as TI defines the drift-linearity rows
    (`DRIFT_LIN_DEFINITION`), computed DIRECTLY by the sum rule on each reading of each member (`LIN_READINGS` for the
    offset × for the mismatch — the both-raw one is the table's own verdict, a control), per row, pair and corner (kind ⊥
    adverse — their hours as the window's edges), family and gap: the thickness limit without and with the unwrap
    floor, the need at an infinitely thick scale, the gap held at t 10 mm. The sensitivity row is a COMMON gain's and
    cancels in the atan2. What none of these readings is: a per-kelvin guarantee — LIN bounds a residual's size, not its
    slope."""
    rows = {}
    for name, row in SENSORS.items():
        if "drift_linearity" not in row:
            continue
        pairs = {}
        for pair in PAIR_AXES:
            out = {}
            for c in ("kind", "adverse"):
                *_, t_hot, t_cold, _s = args("REFeB_sintered", c)
                d_t = {"cold": BRANCH_SPLIT_C - t_cold, "hot": t_hot - BRANCH_SPLIT_C}
                for ro, off in OFFSET_LIN_READINGS.items():
                    k_off, off_basis = (None, "range") if off is None else off
                    for rm, k_mis in LIN_READINGS.items():
                        ln = lin_lane(row, pair, k_off, k_mis, d_t, off_basis)
                        cells = {}
                        for fam in VERDICT_FAMILIES:
                            a, b_max = args(fam, c), MAGNET_FAMILIES_BR_T[fam][1]
                            for g in VERDICT_GAPS_MM:
                                n_inf, p_inf = need_lane(1e4, g, ln, a)
                                cells[f"{fam}:g{g:g}"] = {
                                    "t_min_mm": _t_lim_safe(g, ln, a, b_max),
                                    "t_min_mm_with_unwrap_floor": _t_lim_safe(g, ln, a, b_max, floor_mm),
                                    "need_T_at_infinite_thickness": None if math.isinf(n_inf) else n_inf,
                                    "p_mm_at_infinite_thickness": p_inf}
                        out[f"{c}:offset_{ro}:mismatch_{rm}"] = {
                            "edge_distance_K": d_t, "eps_per_K": ln["eps"], "dbp_T_per_K": ln["dbp"], "cells": cells,
                            "gap_limit_mm_at_t10_REFeB": gap_limit_lane(LEVER_T_MM, ln, args("REFeB_sintered", c),
                                                                        MAGNET_FAMILIES_BR_T["REFeB_sintered"][1])}
            pairs[pair] = out
        lin = row["drift_linearity"]
        rows[name] = {"mismatch_drift_lin": lin["mismatch"],
                      "offset_drift_lin_pct_at_verdict_range": dict(lin["offset_pct_of_range_by_range_T"])[row["verdict_range_T"]],
                      "offset_residual_T_by_basis": {b: offset_lin_residual_t(row, b) for b in ("range", "total_drift")},
                      "sensitivity_drift_lin_not_a_member": lin["sensitivity"], "pairs": pairs}
    # the population of `holds` and `total` is OUR readings of the offset (raw ⊥ full-scale from 25 °C ⊥ full-scale best
    # fit) — what the 2026-11-17 verdict counted; TI's total-drift reading (2026-11-18) is counted beside it, never mixed in
    all_holds = sorted(f"{n} {p} {key}" for n, r in rows.items() for p, pr in r["pairs"].items() for key, blk in pr.items()
                       if blk["cells"]["REFeB_sintered:g3"]["t_min_mm"] is not None)
    ti_keys = [k for r in rows.values() for pr in r["pairs"].values() for k in pr if TI_OFFSET_KEY in k]
    ti_holds = [h for h in all_holds if TI_OFFSET_KEY in h]
    holds = [h for h in all_holds if TI_OFFSET_KEY not in h]
    total = sum(len(pr) for r in rows.values() for pr in r["pairs"].values()) - len(ti_keys)
    all_comp_off = all(":offset_raw:" not in h for h in holds)
    ours_keys = [k for r in rows.values() for pr in r["pairs"].values() for k in pr if ":offset_best_fit:" in k]
    ours_holds = [h for h in holds if ":offset_best_fit:" in h]
    floor_holds = sorted(f"{n} {p} {key}" for n, r in rows.items() for p, pr in r["pairs"].items() for key, blk in pr.items()
                         if blk["cells"]["REFeB_sintered:g3"]["t_min_mm_with_unwrap_floor"] is not None)
    ti_floor = [h for h in floor_holds if TI_OFFSET_KEY in h]
    ours_floor = [h for h in floor_holds if ":offset_best_fit:" in h]
    ctrl_keys = [k for r in rows.values() for pr in r["pairs"].values() for k in pr if ":offset_from_25C:" in k]
    ctrl_holds = [h for h in holds if ":offset_from_25C:" in h]
    noise_over_ti = {n: min(SENSORS[n]["noise_T"].values()) / r["offset_residual_T_by_basis"]["total_drift"] for n, r in rows.items()}
    ratio = {n: r["offset_residual_T_by_basis"]["range"] / r["offset_residual_T_by_basis"]["total_drift"] for n, r in rows.items()}
    verdict = ("LIN bounds the SIZE of the drift's residual over −40…+125 °C, not its slope (TI: not a per-kelvin "
               "coefficient), so the frames' per-kelvin rule has no guaranteed reading from it; at the window's edge — the "
               f"most favourable point — the readings hold 3 mm on REFeB in {len(holds)} of {total} row·pair·corner·reading "
               f"cells{', every one with the offset compensated' if holds and all_comp_off else ''}; nearer 25 °C the same "
               "residual is a larger per-kelvin figure without bound, and the drift's repeatability and 20-year stability "
               "are not published — a linear compensation is a MEASURED band, not a guarantee. The offset row has two "
               "readings of what LIN is a share of: TI's follow-up (2026-11-18) — the total offset drift over the full "
               f"range, a best-fit line not held to 25 °C — holds 3 mm on REFeB in {len(ti_holds)} of {len(ti_keys)} of its "
               f"cells, {len(ti_floor)} with the unwrap floor; TI's answer excludes a share of the full-scale range, and "
               f"our full-scale reading is kept as the adverse bound (its residual is ×{min(ratio.values()):.0f}–"
               f"×{max(ratio.values()):.0f} TI's, whose own is ×{math.floor(min(noise_over_ti.values()))}–"
               f"×{math.floor(max(noise_over_ti.values()))} below one read's noise): on the same line it holds in "
               f"{len(ours_holds)} of {len(ours_keys)}, {len(ours_floor)} with the floor. With that line not through 25 °C "
               f"the offset's «from 25 °C» cells are a control — {len(ctrl_holds)} of the {len(holds)} holds above; "
               f"without them {len(holds) - len(ctrl_holds)} of {total - len(ctrl_keys)}")
    return {"definition": DRIFT_LIN_DEFINITION, "readings_k": LIN_READINGS, "offset_readings": OFFSET_LIN_READINGS,
            "rows": rows, "verdict": verdict,
            "holds_3mm_REFeB": holds, "cells_total": total, "every_hold_compensates_the_offset": all_comp_off,
            "population": "holds_3mm_REFeB and cells_total count OUR readings of the offset; TI's total-drift reading is "
                          "`ti_total_drift_reading`",
            "ti_total_drift_reading": {"holds_3mm_REFeB": ti_holds, "cells_total": len(ti_keys),
                                       "holds_3mm_REFeB_with_unwrap_floor": ti_floor,
                                       "residual_ours_over_ti": ratio, "one_read_noise_over_residual": noise_over_ti},
            "best_fit_full_scale_ours": {"holds_3mm_REFeB": ours_holds, "cells_total": len(ours_keys),
                                         "holds_3mm_REFeB_with_unwrap_floor": ours_floor},
            "offset_from_25C_control": {"holds_3mm_REFeB": ctrl_holds, "cells_total": len(ctrl_keys),
                                        "holds_without_it": len(holds) - len(ctrl_holds),
                                        "cells_without_it": total - len(ctrl_keys)}}


def screen_rows(args, t_hots: dict, colds: dict) -> dict:
    """(2f) the screen rows judged by the sum rule — per row, pair, family, corner and gap the thickness limit with the
    mismatch term and the need at an infinitely thick scale; no read, no levers (their energy rows are not read)."""
    out = {}
    for name, row in SCREEN_ROWS.items():
        assert row["operating_C"][0] <= min(colds.values()) and max(t_hots.values()) <= row["operating_C"][1], name
        pairs = {}
        for pair in PAIR_AXES:
            ln = make_lane(row, pair, 1, True)
            cells = {}
            for fam in VERDICT_FAMILIES:
                for c in ("isothermal", "kind", "adverse"):
                    a = args(fam, c)
                    for g in VERDICT_GAPS_MM:
                        n_inf, p_inf = need_lane(1e4, g, ln, a)
                        cells[f"{fam}:{c}:g{g:g}"] = {
                            "t_min_mm": thickness_limit_lane(g, ln, a, MAGNET_FAMILIES_BR_T[fam][1]),
                            "need_T_at_infinite_thickness": None if math.isinf(n_inf) else n_inf,
                            "p_mm_at_infinite_thickness": p_inf}
            pairs[pair] = {"per_K_guaranteed": per_k(row, pair, 1), "cells": cells,
                           "holds_any_cell": any(v["t_min_mm"] is not None for v in cells.values())}
        out[name] = {"source": row["source"], "verdict_range_T": row["verdict_range_T"], "assumed": row["assumed"],
                     "pairs": pairs}
    return out


def control_linearity_and_screen(lin: dict, scr: dict, st: dict, args) -> None:
    """Control 12 — see the docstring's CONTROLS."""
    for name, r in lin["rows"].items():
        row = SENSORS[name]
        for pair, pr in r["pairs"].items():
            raw = make_lane(row, pair, 1, True)
            for key, blk in pr.items():
                c, ro, rm = key.split(":")
                ro, rm = ro[len("offset_"):], rm[len("mismatch_"):]
                *_, t_hot, t_cold, _s = args("REFeB_sintered", c)
                d_t = {"cold": BRANCH_SPLIT_C - t_cold, "hot": t_hot - BRANCH_SPLIT_C}   # from the corner, not the block
                for br in ("cold", "hot"):
                    assert abs(blk["edge_distance_K"][br] - d_t[br]) < 1e-12, (name, pair, key)
                    want = raw["eps"][br] if LIN_READINGS[rm] is None else LIN_READINGS[rm] * row["drift_linearity"]["mismatch"][pair] / d_t[br]
                    assert abs(blk["eps_per_K"][br] - want) <= 1e-15, (name, pair, key)
                    off = OFFSET_LIN_READINGS[ro]
                    # the residual rebuilt here from the row's own fields, not through `offset_lin_residual_t`
                    pct = dict(row["drift_linearity"]["offset_pct_of_range_by_range_T"])[row["verdict_range_T"]]
                    l_by = {"range": pct * row["verdict_range_T"],
                            "total_drift": pct * max(v[1] for ax in row["offset_T_per_K"].values() for v in ax.values())
                            * (row["operating_C"][1] - row["operating_C"][0])}
                    want_o = raw["dbp"][br] if off is None else math.sqrt(2.0) * off[0] * l_by[off[1]] / d_t[br]
                    assert abs(blk["dbp_T_per_K"][br] - want_o) <= 1e-12 * want_o, (name, pair, key)
                    for b in l_by:
                        assert abs(r["offset_residual_T_by_basis"][b] - l_by[b]) <= 1e-18, (name, b)
                for ck, cell in blk["cells"].items():
                    fam, gk = ck.split(":")
                    f, b_max, g = edge_factors(args(fam, c)), MAGNET_FAMILIES_BR_T[fam][1], float(gk[1:])
                    # the both-raw reading IS the table's verdict at that corner — need and «holds» both ways, the floor too
                    if ro == "raw" and rm == "raw":
                        tc = st[name]["pairs"][pair]["cells"][f"{fam}:{c}:{gk}"]
                        assert (tc["with_mismatch"]["need_T_at_infinite_thickness"] is None) == (cell["need_T_at_infinite_thickness"] is None), (name, pair, key, ck)
                        assert (tc["with_mismatch"]["t_min_mm"] is None) == (cell["t_min_mm"] is None), (name, pair, key, ck)
                        assert (tc["with_mismatch_and_unwrap_floor"]["t_min_mm"] is None) == (cell["t_min_mm_with_unwrap_floor"] is None), (name, pair, key, ck)
                        nt = tc["with_mismatch"]["need_T_at_infinite_thickness"]
                        if nt is not None:
                            assert abs(nt - cell["need_T_at_infinite_thickness"]) < 1e-9 * nt, (name, pair, key, ck)
                    if cell["need_T_at_infinite_thickness"] is None:
                        assert cell["t_min_mm"] is None, (name, pair, key, ck)
                        continue
                    p_ = cell["p_mm_at_infinite_thickness"]
                    kk = 2 * math.pi / p_
                    geom = (1 - math.exp(-kk * 1e4)) * math.exp(-kk * g)
                    n = max(2 * p_ * blk["dbp_T_per_K"][e] / (2 * math.pi * (TARGET_MM - p_ * blk["eps_per_K"][e] / (4 * math.pi)) * geom * f[e])
                            for e in ("cold", "hot"))
                    assert abs(n - cell["need_T_at_infinite_thickness"]) < 1e-9 * n, (name, pair, key, ck)
                    assert (cell["t_min_mm"] is None) == (n >= b_max), (name, pair, key, ck)
                    inf = math.inf
                    assert (cell["t_min_mm"] if cell["t_min_mm"] is not None else inf) <= (
                        cell["t_min_mm_with_unwrap_floor"] if cell["t_min_mm_with_unwrap_floor"] is not None else inf) + 1e-9
            # «from 25 °C» never needs more than «best fit», member by member with the other held
            for c in ("kind", "adverse"):
                for other in LIN_READINGS:
                    for ck in pr[f"{c}:offset_from_25C:mismatch_{other}"]["cells"]:
                        for k1, k2 in ((f"{c}:offset_from_25C:mismatch_{other}", f"{c}:offset_best_fit:mismatch_{other}"),
                                       (f"{c}:offset_{other}:mismatch_from_25C", f"{c}:offset_{other}:mismatch_best_fit")):
                            n1, n2 = (pr[k]["cells"][ck]["need_T_at_infinite_thickness"] for k in (k1, k2))
                            assert (n1 if n1 is not None else math.inf) <= (n2 if n2 is not None else math.inf) * (1 + 1e-9), (name, pair, k1, ck)
                        # TI's total-drift reading (k = 2) against our full-scale best fit (k = 2), the other member held:
                        # the smaller residual never needs more — a swapped basis would red here
                        lo_b, hi_b = sorted(("ti_total_drift", "best_fit"),
                                            key=lambda q: r["offset_residual_T_by_basis"]["total_drift" if q == "ti_total_drift" else "range"])
                        n1, n2 = (pr[f"{c}:offset_{q}:mismatch_{other}"]["cells"][ck]["need_T_at_infinite_thickness"] for q in (lo_b, hi_b))
                        assert (n1 if n1 is not None else math.inf) <= (n2 if n2 is not None else math.inf) * (1 + 1e-9), (name, pair, c, other, ck)
    # a row whose LIN fields are ZERO leaves no drift under a compensation of both members (k = 1): a lane that ignored
    # the LIN fields, or a compensation that ignored the offset, would keep a drift here
    for name, row in SENSORS.items():
        if "drift_linearity" not in row:
            continue
        a0 = args("REFeB_sintered", "adverse")
        row0 = {**row, "drift_linearity": {**row["drift_linearity"], "mismatch": dict.fromkeys(PAIR_AXES, 0.0),
                                            "offset_pct_of_range_by_range_T": tuple((rng, 0.0) for rng, _ in row["drift_linearity"]["offset_pct_of_range_by_range_T"])}}
        z = lin_lane(row0, "x_y", 1.0, 1.0, {"cold": 58.0, "hot": 38.0})
        assert all(v == 0.0 for v in (*z["eps"].values(), *z["dbp"].values()))
        assert _t_lim_safe(3.0, z, a0, MAGNET_FAMILIES_BR_T["REFeB_sintered"][1]) == 0.05, name
    # a band reached at the window's edge never holds more than the band spread to its end: the edge's distance from
    # 25 °C is at most the span, so the per-kelvin drifts only grow (a swapped span or edge would red here)
    for name, s in st.items():
        span = SENSORS[name].get("branch_span_K", BRANCH_SPAN_K)
        for pair, pr in s["pairs"].items():
            for key, lv in pr["levers"].items():
                e = lv.get("band_reached_at_the_window_edge")
                if e is None:
                    continue
                fam_, c_ = key.split(":")
                a_ = args(fam_, c_)
                *_, t_hot_c, t_cold_c, _s = a_
                assert abs(e["span_K"]["cold"] - (BRANCH_SPLIT_C - t_cold_c)) < 1e-12 and abs(e["span_K"]["hot"] - (t_hot_c - BRANCH_SPLIT_C)) < 1e-12, (name, pair, key)
                assert all(0.0 < e["span_K"][br] <= span[br] for br in ("cold", "hot")), (name, pair, key)
                ge, gs = e["gap_limit_mm_at_t10_with_mismatch"], lv["gap_limit_mm_at_t10"]["with_mismatch"]
                assert (ge if ge is not None else -math.inf) <= (gs if gs is not None else -math.inf) + 1e-9, (name, pair, key)
                for gk, se in e["mismatch_scale_to_hold_at_infinite_thickness_no_floor"].items():
                    ss = lv["mismatch_scale_to_hold_at_infinite_thickness"][gk]["no_floor"]
                    assert (se or 0.0) <= (ss or 0.0) + 1e-9, (name, pair, key, gk)
    # each screen cell: its infinite-thickness need IS the sum rule at its period, and «no thickness» is exactly a need
    # above the family's maximum — the same closed form the table's control holds its cells to
    for name, s in scr.items():
        row = SCREEN_ROWS[name]
        for pair, pr in s["pairs"].items():
            ln = make_lane(row, pair, 1, True)
            for key, cell in pr["cells"].items():
                fam, c, gk = key.split(":")
                f = edge_factors(args(fam, c))
                if cell["need_T_at_infinite_thickness"] is None:
                    assert cell["t_min_mm"] is None, (name, pair, key)
                    continue
                p, g = cell["p_mm_at_infinite_thickness"], float(gk[1:])
                k = 2 * math.pi / p
                geom = (1 - math.exp(-k * 1e4)) * math.exp(-k * g)
                n = max(2 * p * ln["dbp"][e] / (2 * math.pi * (TARGET_MM - p * ln["eps"][e] / (4 * math.pi)) * geom * f[e])
                        for e in ("cold", "hot"))
                assert abs(n - cell["need_T_at_infinite_thickness"]) < 1e-9 * n, (name, pair, key)
                assert (cell["t_min_mm"] is None) == (n >= MAGNET_FAMILIES_BR_T[fam][1]), (name, pair, key)


def angle_curve_deg(row: dict, curve: str, t_c: float) -> float:
    """A curve row's angle error at t_c on the named curve, linear between its transcribed points (inside them only)."""
    pts = row["curves_deg"][curve]
    assert pts[0][0] <= t_c <= pts[-1][0], (t_c, pts)
    return float(np.interp(t_c, [x for x, _ in pts], [y for _, y in pts]))


def angle_p_sat_mm(b_r: float, g_mm: float, b_min: float, t_mm: float | None) -> float | None:
    """The shortest period at which the field amplitude at the gap reaches b_min — the rotating field's magnitude is the
    fundamental's amplitude. An infinitely thick scale (t None) gives it in closed form, 2πg/ln(B_r/2b_min); a finite one
    has a field that peaks at P* and falls beyond it, so the root is searched below the peak; None if never reached."""
    if t_mm is None:
        return None if 0.5 * b_r <= b_min else 2 * math.pi * g_mm / math.log(0.5 * b_r / b_min)
    peak = minimize_scalar(lambda q: -field_amplitude_t(b_r, q, t_mm, g_mm), bounds=(0.5, 200.0), method="bounded")
    if field_amplitude_t(b_r, peak.x, t_mm, g_mm) < b_min:
        return None
    return brentq(lambda q: field_amplitude_t(b_r, q, t_mm, g_mm) - b_min, 0.05, peak.x, xtol=1e-9)


def angle_readings(row: dict) -> list[tuple[str, str]]:
    """(size, spread) per row: a limit row on the 2×2 grid; a curve row per curve × degree reading, at the corner's hours."""
    if "curves_deg" in row:
        return [(f"{cv}_{dg}", "window_edge") for cv in row["curves_deg"] for dg in row["degree_readings"]]
    return list(itertools.product(ANGLE_SIZE_READINGS, ANGLE_SPREAD_READINGS))


def angle_drift_deg_per_k(row: dict, size: str, spread: str, edge: dict, curve_shift: float = 0.0) -> tuple[dict, dict]:
    """The per-kelvin FIELD-angle drift per branch and the span it is spread over (see `angle_rows`)."""
    if spread == "band_ends":
        span = {"cold": BRANCH_SPLIT_C - row["operating_C"][0], "hot": row["operating_C"][1] - BRANCH_SPLIT_C}
    else:
        span = {br: abs(edge[br] - BRANCH_SPLIT_C) for br in edge}
    if "curves_deg" in row:
        cv, dg = size.rsplit("_", 1)
        k = row["degree_readings"][dg]
        return {br: k * max(angle_curve_deg(row, cv, edge[br]) + curve_shift, 0.0) / span[br] for br in edge}, span
    extra = row["at_25C_deg"] if row["at_25C_deg"] is not None else row["total_deg"]
    size_deg = row["total_deg"] + (0.0 if size == "limit" else extra)
    return {br: size_deg / span[br] for br in edge}, span


def angle_rows(args, t_hots: dict, colds: dict, floor_mm: float, wall_mm: float) -> dict:
    """(2g) the angle rows. Each reads the field in the plane of its die, and the scale's field turns in the plane of the
    motion and the scale's normal, so the package stands edge-on to the wall: the row's own minimum gap is the wall plus
    the die's depth from the package's lead-free end. Per row, reading and corner: the per-kelvin field-angle drift per
    branch and the longest period that keeps it within the frames (P_max = 0.3 µm/K · 360°/δθ; a curve row also at its
    read tolerance); per family and gap (3 · 4 mm and the row's own minimum) the window of periods — from the period at
    which the strongest class at the hottest hour saturates the row (a thick scale ⊥ t 2 mm) and the unwrap floor
    (doubled for a 180° row) up to P_max and the period above which the WEAKEST class, thick, at the coldest hour passes
    the row's field maximum (the classes between cover the window continuously); whether the gap is reachable. The
    per-kelvin members a row prints alone are NECESSARY caps; a rejected member reading is printed with its reason; the
    static cyclic error and the lifetime row at the floored period stand beside, not per kelvin, not summed."""
    out = {}
    for name, row in ANGLE_ROWS.items():
        assert row["operating_C"][0] <= min(colds.values()) and max(t_hots.values()) <= row["operating_C"][1], name
        floor_eff = floor_mm * 360.0 / row["range_deg"]
        g_min = wall_mm + row["die_to_edge_mm"]
        gaps = [*((f"g{g:g}", g) for g in VERDICT_GAPS_MM), ("gmin", g_min)]
        readings = {}
        for size, spread in angle_readings(row):
            for c in ("kind", "adverse"):
                *_, t_hot, t_cold, _s = args("REFeB_sintered", c)
                edge = {"cold": t_cold, "hot": t_hot}
                dth, span = angle_drift_deg_per_k(row, size, spread, edge)
                bind = max(dth, key=dth.get)
                p_max = TARGET_MM * 360.0 / dth[bind]
                band = None
                if "curves_deg" in row:
                    tol = row["curve_read_tolerance_deg"][size.rsplit("_", 1)[0]]
                    hi_d = max(angle_drift_deg_per_k(row, size, spread, edge, +tol)[0].values())
                    lo_d = max(angle_drift_deg_per_k(row, size, spread, edge, -tol)[0].values())
                    band = [TARGET_MM * 360.0 / hi_d, math.inf if lo_d == 0.0 else TARGET_MM * 360.0 / lo_d]
                cells = {}
                for fam in VERDICT_FAMILIES:
                    alpha, t_ref_need, t_ref_cap, *_ = args(fam, c)
                    lo_cls, hi_cls = MAGNET_FAMILIES_BR_T[fam]
                    b_r = hi_cls * thermal_factor(alpha, t_hot, t_ref_need)
                    b_cold_hi = hi_cls * thermal_factor(alpha, t_cold, t_ref_cap)
                    b_cold_lo = lo_cls * thermal_factor(alpha, t_cold, t_ref_cap)
                    for gk, g in gaps:
                        p_thick = angle_p_sat_mm(b_r, g, row["field_min_T"], None)
                        p_t2 = angle_p_sat_mm(b_r, g, row["field_min_T"], max(SCALE_T_MM))
                        if row["field_max_T"] is None:
                            over_hi = over_lo = None
                        else:
                            over_hi = angle_p_sat_mm(b_cold_hi, g, row["field_max_T"], None)
                            over_lo = angle_p_sat_mm(b_cold_lo, g, row["field_max_T"], None)
                        top = min(p_max, math.inf if over_lo is None else over_lo)
                        win = (None if p_thick is None or max(p_thick, floor_eff) > top
                               else [max(p_thick, floor_eff), top])
                        cells[f"{fam}:{gk}"] = {
                            "g_mm": g, "reachable": g >= g_min - 1e-9,
                            "p_sat_mm_thick": p_thick, "p_sat_mm_t2": p_t2,
                            "p_over_field_max_mm_thick_cold_strongest": over_hi,
                            "p_over_field_max_mm_thick_cold_weakest": over_lo,
                            "holds_thick": p_thick is not None and p_thick <= p_max,
                            "holds_thick_with_floor": win is not None,
                            "holds_t2_with_floor": p_t2 is not None and max(p_t2, floor_eff) <= top,
                            "window_thick_with_floor_mm": win}
                readings[f"{c}:size_{size}:spread_{spread}"] = {
                    "span_K": span, "drift_deg_per_K": dth, "binding_branch": bind, "p_max_mm": p_max,
                    "p_max_mm_at_read_tolerance": band, "cells": cells}
        members = {}
        for c in ("kind", "adverse"):
            *_, t_hot, _t_cold, _s = args("REFeB_sintered", c)
            m = {}
            if row["offset_tc_V_per_V_K"] is not None:
                amp = row["amplitude_min_V_per_V"] * (1.0 + row["amplitude_tc_min_per_K"] * (t_hot - BRANCH_SPLIT_C))
                d_off = math.hypot(row["offset_tc_V_per_V_K"], row["offset_tc_V_per_V_K"]) / amp
                m["offset"] = {"rad_per_K": d_off, "cap_mm": TARGET_MM * 2 * math.pi / d_off,
                               "amplitude_at_hot_hour_V_per_V": amp}
            if row["mismatch_tc_per_K"] is not None:
                d_mis = row["mismatch_tc_per_K"] / 2.0
                m["mismatch"] = {"rad_per_K": d_mis, "cap_mm": TARGET_MM * 2 * math.pi / d_mis}
            if row["amplitude_tc_max_per_K"] is not None:
                d_rej = (row["amplitude_tc_max_per_K"] - row["amplitude_tc_min_per_K"]) / 2.0
                implied = math.degrees(d_rej * (BRANCH_SPLIT_C - row["operating_C"][0]))
                m["mismatch_if_TCAmp_per_channel"] = {
                    "rad_per_K": d_rej, "cap_mm": TARGET_MM * 2 * math.pi / d_rej, "rejected": True,
                    "implied_change_deg_over_cold_band": implied,
                    "why": "read per channel, the coefficient's span would move the angle further over the cold band "
                           "than the row's own over-temperature limit allows"}
            members[c] = m
        static = row.get("at_25C_deg") if row.get("at_25C_deg") is not None else row.get("total_deg")
        life = row.get("lifetime_deg")
        out[name] = {"source": row["source"], "range_deg": row["range_deg"], "field_min_T": row["field_min_T"],
                     "field_max_T": row["field_max_T"], "package": row["package"], "die_to_edge_mm": row["die_to_edge_mm"],
                     "min_gap_mm": g_min, "unwrap_floor_mm_effective": floor_eff, "assumed": row["assumed"],
                     "readings": readings, "members_alone": members,
                     "static_cyclic_um_at_floor": None if static is None else floor_eff * static / 360.0 * 1e3,
                     "lifetime_row_um_at_floor": None if life is None else floor_eff * life / 360.0 * 1e3}
    def hold_list(gk):
        return sorted(f"{n} {k}" for n, r in out.items() for k, blk in r["readings"].items()
                      if blk["cells"][f"REFeB_sintered:{gk}"]["reachable"]
                      and blk["cells"][f"REFeB_sintered:{gk}"]["holds_thick_with_floor"])
    h3, h4, hmin = hold_list("g3"), hold_list("g4"), hold_list("gmin")
    total = sum(len(r["readings"]) for r in out.values())
    g_mins = {n: r["min_gap_mm"] for n, r in out.items()}
    limit_only_fav = all(":size_limit:spread_band_ends" in h for h in hmin if "curve" not in h and "fig1" not in h)
    by_row = {}
    for h in hmin:
        n, k = h.split(" ", 1)
        by_row.setdefault(n, set()).add(k.split(":", 1)[1])
    widths = {}
    for n, r in out.items():
        for blk in r["readings"].values():
            w = blk["cells"]["REFeB_sintered:gmin"]["window_thick_with_floor_mm"]
            if w is not None:
                widths.setdefault(n, []).append(w)
    p_max_all = [blk["p_max_mm"] for r in out.values() for blk in r["readings"].values()]
    caps = sorted({round(b["cap_mm"], 1) for r in out.values() for m in r["members_alone"].values()
                   for b in m.values() if not b.get("rejected")})
    verdict = ("an angle sensor reads the field's direction, so the frames cap the period from above (P ≤ 0.3 µm/K · "
               "360°/δθ) while the unwrap floor and the field the sensor needs bound it from below; and it reads in the "
               "plane of its die, so it stands edge-on to the wall: its own minimum gap is "
               + ", ".join(f"{n} {g:.2f}" for n, g in g_mins.items()) + " mm — "
               f"{'none' if not any(g <= 3.0 for g in g_mins.values()) else 'some'} reaches 3 mm "
               f"(at 3 mm: {len(h3)} holding cells, at 4 mm: {len(h4)}); at its own minimum gap a thick REFeB scale, "
               f"with the unwrap floor and under the row's field maximum, holds in {len(hmin)} of {total} "
               f"row·reading·corner cells — " + "; ".join(
                   f"{n} on {', '.join(sorted(ks))} ({min(w[0] for w in widths[n]):.2f}–{max(w[1] for w in widths[n]):.2f} mm)"
                   for n, ks in sorted(by_row.items()))
               + f"; P_max over all readings runs {min(p_max_all):.2f}–{max(p_max_all):.2f} mm; no row prints the angle "
               f"drift per kelvin (the members two rows print alone cap P only at {', '.join(f'{c:g}' for c in caps)} mm "
               f"— necessary, not sufficient), so each verdict reads a SIZE over a span as a slope, and the favourable "
               f"spread is no ceiling")
    return {"rows": out, "verdict": verdict, "holds_3mm_REFeB_with_floor": h3, "holds_4mm_REFeB_with_floor": h4,
            "holds_at_own_min_gap_REFeB_with_floor": hmin, "min_gap_mm": g_mins, "wall_mm": wall_mm,
            "limit_rows_hold_only_on_the_most_favourable_reading": limit_only_fav,
            "cells_total": total, "size_readings": ANGLE_SIZE_READINGS, "spread_readings": ANGLE_SPREAD_READINGS}


def control_angle(ang: dict, args, floor_mm: float) -> None:
    """Control 13 — see the docstring's CONTROLS."""
    for name, r in ang["rows"].items():
        row = ANGLE_ROWS[name]
        assert math.isclose(r["unwrap_floor_mm_effective"] * row["range_deg"], floor_mm * 360.0, rel_tol=1e-12), name
        assert math.isclose(r["min_gap_mm"], ang["wall_mm"] + row["die_to_edge_mm"], rel_tol=1e-12), name
        for cv, pts in row.get("curves_deg", {}).items():
            for t_c, v in pts:
                assert math.isclose(angle_curve_deg(row, cv, t_c), v, abs_tol=1e-12), (name, cv, t_c)
            assert angle_curve_deg(row, cv, BRANCH_SPLIT_C) == 0.0, (name, cv)
        for key, blk in r["readings"].items():
            c, size, spread = key.split(":")
            *_, t_hot, t_cold, _s = args("REFeB_sintered", c)
            if spread == "spread_band_ends":
                assert blk["span_K"]["cold"] >= BRANCH_SPLIT_C - t_cold and blk["span_K"]["hot"] >= t_hot - BRANCH_SPLIT_C, key
                twin = r["readings"][f"{c}:{size}:spread_window_edge"]
                assert blk["p_max_mm"] >= twin["p_max_mm"] - 1e-12, (name, key)
            else:
                assert math.isclose(blk["span_K"]["cold"], BRANCH_SPLIT_C - t_cold, rel_tol=1e-12), key
                assert math.isclose(blk["span_K"]["hot"], t_hot - BRANCH_SPLIT_C, rel_tol=1e-12), key
            if size == "size_limit_plus_25C":
                assert blk["p_max_mm"] <= r["readings"][key.replace("size_limit_plus_25C", "size_limit")]["p_max_mm"] + 1e-12, key
            if size.endswith("_electrical"):
                assert math.isclose(blk["p_max_mm"], 2 * r["readings"][key.replace("_electrical", "_field")]["p_max_mm"], rel_tol=1e-12), key
            if blk["p_max_mm_at_read_tolerance"] is not None:
                lo, hi = blk["p_max_mm_at_read_tolerance"]
                assert lo <= blk["p_max_mm"] <= hi, (name, key)
            d = blk["drift_deg_per_K"][blk["binding_branch"]]
            assert d == max(blk["drift_deg_per_K"].values()), key
            assert math.isclose(blk["p_max_mm"] * d / 360.0, TARGET_MM, rel_tol=1e-12), key
            for ck, cell in blk["cells"].items():
                fam, _gk = ck.split(":")
                alpha, t_ref_need, t_ref_cap, *_ = args(fam, c)
                lo_cls, hi_cls = MAGNET_FAMILIES_BR_T[fam]
                b_r = hi_cls * thermal_factor(alpha, t_hot, t_ref_need)
                g = cell["g_mm"]
                assert cell["reachable"] == (g >= r["min_gap_mm"] - 1e-9), (name, key, ck)
                for tk, t_mm in (("p_sat_mm_thick", 1e6), ("p_sat_mm_t2", max(SCALE_T_MM))):
                    q = cell[tk]
                    if q is None:
                        assert max(field_amplitude_t(b_r, x, t_mm, g) for x in np.linspace(0.5, 200.0, 4000)) < row["field_min_T"] * (1 + 1e-6), (name, key, ck, tk)
                        continue
                    assert math.isclose(field_amplitude_t(b_r, q, t_mm, g), row["field_min_T"], rel_tol=1e-6), (name, key, ck, tk)
                    assert field_amplitude_t(b_r, q * (1 - 1e-4), t_mm, g) < row["field_min_T"], (name, key, ck, tk)
                for tk, cls in (("p_over_field_max_mm_thick_cold_strongest", hi_cls), ("p_over_field_max_mm_thick_cold_weakest", lo_cls)):
                    q = cell[tk]
                    if q is not None:
                        b_c = cls * thermal_factor(alpha, t_cold, t_ref_cap)
                        assert math.isclose(field_amplitude_t(b_c, q, 1e6, g), row["field_max_T"], rel_tol=1e-9), (name, key, ck, tk)
                        assert field_amplitude_t(b_c, q * (1 + 1e-4), 1e6, g) > row["field_max_T"], (name, key, ck, tk)
                qs, qw = cell["p_over_field_max_mm_thick_cold_strongest"], cell["p_over_field_max_mm_thick_cold_weakest"]
                assert qs is None or qw is None or qs <= qw, (name, key, ck)
                assert not cell["holds_thick_with_floor"] or cell["holds_thick"], (name, key, ck)
                assert not cell["holds_t2_with_floor"] or cell["holds_thick_with_floor"], (name, key, ck)
                w = cell["window_thick_with_floor_mm"]
                assert (w is not None) == cell["holds_thick_with_floor"], (name, key, ck)
                if w is not None:
                    assert w[0] >= r["unwrap_floor_mm_effective"] and w[0] <= w[1] <= blk["p_max_mm"], (name, key, ck)
                    assert qw is None or w[1] <= qw, (name, key, ck)
        for c, m in r["members_alone"].items():
            for mk, blk in m.items():
                assert math.isclose(blk["cap_mm"] * blk["rad_per_K"] / (2 * math.pi), TARGET_MM, rel_tol=1e-12), (name, c)
                if blk.get("rejected"):
                    assert blk["implied_change_deg_over_cold_band"] > row["total_deg"], (name, mk)


def end_on_tilt(row: dict, gk_pair: str, pk: dict, args, wall_mm: float) -> dict:
    """An X–Y package tilted by β about the motion axis from flat (β 0) to end-on (β 90°): the axis that leaves the wall's
    plane reads the scale's normal component as sin β, so under the sum rule its offset term grows by 1/sin β —
    δB_pair → √(δa² + δb²/sin²β) (one row for both axes: by hypot(1, 1/sin β)/√2) — while the gap shrinks to the wall
    plus h·cos β + e·sin β, the top-end corner of the lead-free end to the wall (h the elements' depth, e their distance
    from that end — the drawing's favourable ends, body only: no lead is near that corner). Per corner on REFeB, the
    largest margin over β of the gap a 10 mm scale holds over the gap reached."""
    h, e = pk["end_on"]
    base = make_lane(row, gk_pair, 1, True)
    out = {}
    for c in ("kind", "adverse"):
        a, b_max = args("REFeB_sintered", c), MAGNET_FAMILIES_BR_T["REFeB_sintered"][1]
        best = None
        for deg in range(5, 91):
            b = math.radians(deg)
            r = math.hypot(1.0, 1.0 / math.sin(b)) / math.sqrt(2.0)
            ln = {"lin_T": base["lin_T"], "dbp": {k: v * r for k, v in base["dbp"].items()}, "eps": dict(base["eps"])}
            g_hold = gap_limit_lane(LEVER_T_MM, ln, a, b_max)
            if g_hold is None:
                continue
            g_reach = wall_mm + h * math.cos(b) + e * math.sin(b)
            if best is None or g_hold - g_reach > best["margin_mm"]:
                best = {"margin_mm": g_hold - g_reach, "beta_deg": deg, "gap_held_mm": g_hold, "gap_reached_mm": g_reach}
        out[c] = best
    return out


def package_reach(st: dict, lin: dict, wall_mm: float, args) -> dict:
    """(2h) per Hall row and pair: the gap the package can reach (the wall plus the element's depth — flat for X–Z,
    edge-on for X–Y; an interval over the drawing's tolerances) against what (2d) and (2e) hold: the cells that hold 3 · 4
    mm, whether those gaps are reachable (yes: at or above the interval's top · no: below its bottom · tolerance: inside),
    and the best gap a 10 mm scale holds on each reading against the interval's bottom."""
    owner = {r: k for k, v in PACKAGE_REACH.items() for r in v["rows"]}
    assert set(owner) == set(SENSORS), "a Hall row without its package"

    def reach(g, lo, hi):
        return "yes" if g >= hi - 1e-9 else ("no" if g < lo - 1e-9 else "tolerance")

    out = {}
    for name, r in st.items():
        pk = PACKAGE_REACH[owner[name]]
        pairs = {}
        for pair, pr in r["pairs"].items():
            depth = pk["x_y_mm" if pair == "x_y" else "x_z_mm"]
            lo, hi = wall_mm + depth[0], wall_mm + depth[1]
            holds = {f"g{g:g}": sorted(k for k, v in pr["cells"].items()
                                       if k.endswith(f":g{g:g}") and v["with_mismatch"]["t_min_mm"] is not None)
                     for g in VERDICT_GAPS_MM}
            fav = max((lv["gap_limit_mm_at_t10"]["with_mismatch"] or 0.0) for lv in pr["levers"].values())
            edge = [lv["band_reached_at_the_window_edge"]["gap_limit_mm_at_t10_with_mismatch"]
                    for lv in pr["levers"].values() if lv.get("band_reached_at_the_window_edge")]
            entry = {"mount": "edge-on" if pair == "x_y" else "flat", "min_gap_mm": [lo, hi],
                     "reach_3mm": reach(3.0, lo, hi), "reach_4mm": reach(4.0, lo, hi),
                     "budget_left_at_3mm_mm": 3.0 - hi,
                     "sensor_table_holds": holds,
                     "sensor_table_best_gap_t10_mm": fav,
                     "sensor_table_best_gap_t10_reachable": reach(fav, lo, hi),
                     "sensor_table_best_gap_t10_edge_reading_mm": max((e or 0.0) for e in edge) if edge else None}
            if pair == "x_y" and holds["g3"]:
                entry["end_on_tilt_REFeB"] = end_on_tilt(SENSORS[name], pair, pk, args, wall_mm)
            if name in lin["rows"]:
                lp_all = lin["rows"][name]["pairs"][pair]
                # our readings of the offset ⊥ TI's total-drift one, kept apart (key «:offset_ti_total_drift:»)
                lp = {k: b for k, b in lp_all.items() if ":offset_ti_total_drift:" not in k}
                lp_ti = {k: b for k, b in lp_all.items() if ":offset_ti_total_drift:" in k}
                best = max((b["gap_limit_mm_at_t10_REFeB"] or 0.0) for b in lp.values())
                entry["linearity_holds_3mm_REFeB"] = sorted(k for k, b in lp.items()
                                                           if b["cells"]["REFeB_sintered:g3"]["t_min_mm"] is not None)
                entry["linearity_best_gap_t10_mm"] = best
                entry["linearity_best_gap_t10_reachable"] = reach(best, lo, hi)
                ti_gaps = [b["gap_limit_mm_at_t10_REFeB"] or 0.0 for b in lp_ti.values()]
                entry["linearity_ti_total_drift"] = {
                    "holds_3mm_REFeB": sorted(k for k, b in lp_ti.items()
                                              if b["cells"]["REFeB_sintered:g3"]["t_min_mm"] is not None),
                    "holds_3mm_REFeB_with_unwrap_floor": sorted(
                        k for k, b in lp_ti.items() if b["cells"]["REFeB_sintered:g3"]["t_min_mm_with_unwrap_floor"] is not None),
                    "cells": len(lp_ti), "gap_t10_mm_min_max": [min(ti_gaps), max(ti_gaps)],
                    "worst_gap_t10_reachable": reach(min(ti_gaps), lo, hi)}
                # the offset's «from 25 °C» cells are a control since TI's answer of 2026-11-18: the same two figures without them
                lp_nc = {k: b for k, b in lp.items() if ":offset_from_25C:" not in k}
                best_nc = max((b["gap_limit_mm_at_t10_REFeB"] or 0.0) for b in lp_nc.values())
                entry["linearity_without_offset_from_25C"] = {
                    "holds_3mm_REFeB": sorted(k for k, b in lp_nc.items()
                                              if b["cells"]["REFeB_sintered:g3"]["t_min_mm"] is not None),
                    "best_gap_t10_mm": best_nc, "best_gap_t10_reachable": reach(best_nc, lo, hi)}
            pairs[pair] = entry
        out[name] = {"package": owner[name], "source": pk["source"], "pairs": pairs}
    held_unreach = sorted(f"{n} {p}" for n, r in out.items() for p, e in r["pairs"].items()
                          if e["sensor_table_holds"]["g3"] and e["reach_3mm"] == "no")
    lin_reach = sorted(f"{n} {p}" for n, r in out.items() for p, e in r["pairs"].items()
                       if e.get("linearity_holds_3mm_REFeB") and e["reach_3mm"] == "yes")
    ti_all = sorted(f"{n} {p}" for n, r in out.items() for p, e in r["pairs"].items()
                    if "linearity_ti_total_drift" in e and e["reach_3mm"] == "yes"
                    and len(e["linearity_ti_total_drift"]["holds_3mm_REFeB"]) == e["linearity_ti_total_drift"]["cells"])
    ti_all_floor = sorted(f"{n} {p}" for n, r in out.items() for p, e in r["pairs"].items()
                          if "linearity_ti_total_drift" in e and e["reach_3mm"] == "yes"
                          and len(e["linearity_ti_total_drift"]["holds_3mm_REFeB_with_unwrap_floor"]) == e["linearity_ti_total_drift"]["cells"])
    no_gap = sorted(f"{n} {p}" for n, r in out.items() for p, e in r["pairs"].items()
                    if e["sensor_table_best_gap_t10_mm"] > 0 and e["sensor_table_best_gap_t10_reachable"] == "no"
                    and e["sensor_table_holds"]["g3"])
    tilt = {f"{n} {p}": e["end_on_tilt_REFeB"] for n, r in out.items() for p, e in r["pairs"].items()
            if "end_on_tilt_REFeB" in e}
    tilt_helps = sorted(k for k, v in tilt.items() if any(b is not None and b["margin_mm"] >= 0.0 for b in v.values()))
    verdict = ("the gap a package can reach is the wall plus where its elements sit — flat for X–Z, edge-on for X–Y: "
               + "; ".join(f"{n} {p} {e['min_gap_mm'][0]:.2f}–{e['min_gap_mm'][1]:.2f} mm"
                           for n, r in out.items() for p, e in r["pairs"].items() if n in ("TMAG5273A1", "TMAG5170A1",
                                                                                         "TMAG3001A1", "TLE493D-P3B6_comp"))
               + f"; the sensor table's 3 mm holds that the package cannot reach: {held_unreach or 'none'}"
               + (f" — edge-on, none of them reaches any gap it holds even on a 10 mm scale ({', '.join(no_gap)}), and "
                  f"tilted end-on {'some angle helps (' + ', '.join(tilt_helps) + ')' if tilt_helps else 'no angle helps'}; "
                  "a tilt towards the leaded side (the lead form is not dimensioned) and a band reading flatter than "
                  "linear are not excluded" if no_gap else "")
               + f"; the linear compensation's 3 mm holds that it can reach: {lin_reach or 'none'}"
               + f"; on TI's total-drift reading of the offset, reachable and held at 3 mm on EVERY reading of the mismatch: "
                 f"{ti_all or 'none'} without the unwrap floor, {ti_all_floor or 'none'} with it")
    return {"rule": "X–Z flat (the wall plus the element's depth under the top) ⊥ X–Y edge-on on a lead-free end (the "
                    "wall plus the element's distance from it); intervals over the drawings' tolerances; a holder's "
                    "clearance zero", "wall_mm": wall_mm, "rows": out, "verdict": verdict,
            "held_at_3mm_but_unreachable": held_unreach, "no_reachable_gap_even_at_t10": no_gap,
            "end_on_tilt_helps": tilt_helps,
            "linearity_3mm_reachable": lin_reach,
            "linearity_ti_total_drift_3mm_reachable_on_every_mismatch_reading": ti_all,
            "linearity_ti_total_drift_3mm_reachable_on_every_mismatch_reading_with_unwrap_floor": ti_all_floor}


def control_reach(rch: dict, st: dict) -> None:
    """Control 14 — see the docstring's CONTROLS."""
    for name, r in rch["rows"].items():
        pk = PACKAGE_REACH[r["package"]]
        for pair, e in r["pairs"].items():
            depth = pk["x_y_mm" if pair == "x_y" else "x_z_mm"]
            assert depth[0] <= depth[1] and math.isclose(e["min_gap_mm"][0], rch["wall_mm"] + depth[0], rel_tol=1e-12), (name, pair)
            for g, key in ((3.0, "reach_3mm"), (4.0, "reach_4mm")):
                lo, hi = e["min_gap_mm"]
                assert e[key] == ("yes" if g >= hi - 1e-9 else "no" if g < lo - 1e-9 else "tolerance"), (name, pair, g)
            cells, levers = st[name]["pairs"][pair]["cells"], st[name]["pairs"][pair]["levers"]
            for lk, lv in levers.items():
                # a lever's family and corner that holds 3 mm at t ≤ 10 mm holds at least 3 mm at t 10 mm
                t3 = cells.get(f"{lk}:g3", {}).get("with_mismatch", {}).get("t_min_mm")
                if t3 is not None and t3 <= LEVER_T_MM:
                    assert (lv["gap_limit_mm_at_t10"]["with_mismatch"] or 0.0) >= 3.0 - 1e-6, (name, pair, lk)
            if e["sensor_table_best_gap_t10_reachable"] == "no":
                assert e["reach_3mm"] == "no" or not e["sensor_table_holds"]["g3"], (name, pair)
            for c, b in e.get("end_on_tilt_REFeB", {}).items():
                if b is not None:
                    h, en = pk["end_on"]
                    bb = math.radians(b["beta_deg"])
                    assert math.isclose(b["gap_reached_mm"], rch["wall_mm"] + h * math.cos(bb) + en * math.sin(bb), rel_tol=1e-12), (name, c)
            assert e["sensor_table_holds"]["g3"] == sorted(k for k, v in st[name]["pairs"][pair]["cells"].items()
                                                          if k.endswith(":g3") and v["with_mismatch"]["t_min_mm"] is not None)


def control_sensor_table(st: dict, args, mt: dict, t_hots: dict, colds: dict) -> None:
    """Control 10 — see the docstring's CONTROLS."""
    base = st[BASE_SENSOR]["pairs"]["x_y"]
    for fam in VERDICT_FAMILIES:
        b_max = MAGNET_FAMILIES_BR_T[fam][1]
        for c in ("isothermal", "kind", "adverse"):
            # the old verdict, reproduced: the base row, offset only, is (2c)'s thickness limit and cap
            old_t, new_t = mt["thickness_limit_mm_at_realistic_gap"][fam][c], base["cells"][f"{fam}:{c}:g3"]["offset_only"]["t_min_mm"]
            assert (old_t is None and new_t is None) or abs(old_t - new_t) < 1e-9, (fam, c, old_t, new_t)
            assert abs(base["caps_mm"][f"{fam}:{c}"]["offset_only"] - mt["period_cap_mm"][fam][c]) < 1e-9, (fam, c)
    def sum_rule_need(p, t, g, ln, f):   # the sum rule written out again, apart from `need_br_lane`
        k = 2 * math.pi / p
        geom = (1 - math.exp(-k * t)) * math.exp(-k * g)
        return max(2 * p * ln["dbp"][e] / (2 * math.pi * (TARGET_MM - p * ln["eps"][e] / (4 * math.pi)) * geom * f[e])
                   for e in ("cold", "hot"))

    for name, s in st.items():
        row = SENSORS[name]
        for pair, pr in s["pairs"].items():
            ln_m, ln_0 = make_lane(row, pair, 1, True), make_lane(row, pair, 1, False)
            for key, lv in pr["levers"].items():
                fam, c = key.split(":")
                g_m = lv["gap_limit_mm_at_t10"]["with_mismatch"]
                if g_m is not None:   # the lever's root on the sum rule — dropping the mismatch moves it off the maximum
                    f = edge_factors(args(fam, c))
                    p = lv["p_mm_at_the_gap_limit_with_mismatch"]
                    assert abs(sum_rule_need(p, LEVER_T_MM, g_m, ln_m, f) - MAGNET_FAMILIES_BR_T[fam][1]) < 1e-9, (name, pair, key)
                    assert sum_rule_need(p, LEVER_T_MM, g_m, ln_0, f) < MAGNET_FAMILIES_BR_T[fam][1] * (1 - 1e-6), (name, pair, key)
            for key, cell in pr["cells"].items():
                fam_, c_, gk_ = key.split(":")
                f_ = edge_factors(args(fam_, c_))
                for variant in ("with_mismatch", "with_mismatch_and_unwrap_floor"):
                    v = cell[variant]
                    if v["need_T_at_infinite_thickness"] is None:
                        continue   # the window is empty: no period clears the floor under the cap
                    # the recorded infinite-thickness need IS the sum rule at its period, and a cell with no thickness
                    # limit is exactly one whose infinite-thickness need exceeds the family's maximum
                    n = sum_rule_need(v["p_mm_at_infinite_thickness"], 1e4, float(gk_[1:]), ln_m, f_)
                    assert abs(n - v["need_T_at_infinite_thickness"]) < 1e-9 * n, (name, pair, key, variant)
                    assert (v["t_min_mm"] is None) == (n >= MAGNET_FAMILIES_BR_T[fam_][1]), (name, pair, key, variant)
                fam, c, gk = key.split(":")
                g, b_max, a = float(gk[1:]), MAGNET_FAMILIES_BR_T[fam][1], args(fam, c)
                t0, t1, t2 = (cell[v]["t_min_mm"] for v in ("offset_only", "with_mismatch", "with_mismatch_and_unwrap_floor"))
                inf = math.inf
                # the mismatch term and the floor only ever raise a limit (None = no thickness)
                # within the roots' precision (brentq xtol 1e-10): where the floor does not bind t1 and t2 coincide
                assert (t0 if t0 is not None else inf) <= (t1 if t1 is not None else inf) + 1e-9, (name, pair, key)
                assert (t1 if t1 is not None else inf) <= (t2 if t2 is not None else inf) + 1e-9, (name, pair, key)
                if t1 is None:
                    continue
                # the root returns the family's maximum by a SEPARATE closed form of the sum rule at its recorded period —
                # if the verdict dropped the mismatch term the root would sit at the offset-only limit and this would miss
                p, f = cell["with_mismatch"]["p_mm"], edge_factors(a)
                need = sum_rule_need(p, t1, g, ln_m, f)
                assert abs(need - b_max) < 1e-9 * b_max, (name, pair, key, need)
                # … and the mismatch term carries part of it: the offset term alone at that point needs strictly less
                if max(ln_m["eps"].values()) > 0:
                    assert t0 is None or t1 > t0 + 1e-6, (name, pair, key, t0, t1)
                # brute force over each window at its limit: no period the search missed needs less
                for variant, floor in (("with_mismatch", 0.5), ("with_mismatch_and_unwrap_floor", mt["unwrap_floor_mm"])):
                    t_v = cell[variant]["t_min_mm"]
                    if t_v is None:
                        continue
                    q = np.linspace(max(0.5, floor), min(60.0, cap_lane_mm(ln_m, a)), 4001)
                    kq = 2 * np.pi / q
                    geom_q = (1 - np.exp(-kq * t_v)) * np.exp(-kq * g)
                    need_q = np.max([2 * q * ln_m["dbp"][e] / (2 * np.pi * (TARGET_MM - q * ln_m["eps"][e] / (4 * np.pi)) * f[e])
                                     for e in ("cold", "hot")], axis=0) / geom_q
                    assert need_q.min() >= b_max * (1 - 1e-6), (name, pair, key, variant, need_q.min(), b_max)
    # the levers' roots return the family's maximum, and a gap limit with the mismatch never exceeds the offset-only one
    for name, s in st.items():
        row = SENSORS[name]
        for pair, pr in s["pairs"].items():
            for key, lv in pr["levers"].items():
                fam, c = key.split(":")
                a, b_max = args(fam, c), MAGNET_FAMILIES_BR_T[fam][1]
                gl = lv["gap_limit_mm_at_t10"]
                inf = math.inf
                # within the roots' precision (brentq xtol 1e-10): where the floor does not bind the two roots coincide
                assert (gl["offset_only"] or -inf) >= (gl["with_mismatch"] or -inf) - 1e-9, (name, pair, key)
                assert (gl["with_mismatch"] or -inf) >= (gl["with_mismatch_and_unwrap_floor"] or -inf) - 1e-9, (name, pair, key)
                ln = make_lane(row, pair, 1, True)
                if gl["with_mismatch"] is not None:
                    assert abs(need_lane(LEVER_T_MM, gl["with_mismatch"], ln, a)[0] - b_max) < 1e-9, (name, pair, key)
                for gk, sc in lv["mismatch_scale_to_hold_at_infinite_thickness"].items():
                    for floor_key, floor in (("no_floor", 0.5), ("with_unwrap_floor", mt["unwrap_floor_mm"])):
                        v = sc[floor_key]
                        if v is None or v == 1.0:
                            continue
                        ln_s = {**ln, "eps": {br: v * e for br, e in ln["eps"].items()}}
                        assert abs(need_lane(1e4, float(gk[1:]), ln_s, a, floor)[0] - b_max) < 1e-6 * b_max, (name, pair, key, gk, floor_key)
    # the corners stay ordered kind ≤ adverse on every limit and lever (the isothermal corner, with no coefficient, is NOT
    # ordered against them once the cold branch binds: at 25 °C the kind corner's units, met at 28 °C, stand above it)
    inf = math.inf
    for name, s in st.items():
        for pair, pr in s["pairs"].items():
            for key, cell in pr["cells"].items():
                fam, c, gk = key.split(":")
                if c != "kind":
                    continue
                adv = pr["cells"][f"{fam}:adverse:{gk}"]
                for v, blk in cell.items():
                    tk, ta = blk["t_min_mm"], adv[v]["t_min_mm"]
                    assert (inf if tk is None else tk) <= (inf if ta is None else ta) + 1e-12, (name, pair, key, v)
            for fam in VERDICT_FAMILIES[:2]:
                lk, la = pr["levers"][f"{fam}:kind"], pr["levers"][f"{fam}:adverse"]
                assert (la["gap_limit_mm_at_t10"]["with_mismatch"] or 0.0) <= (lk["gap_limit_mm_at_t10"]["with_mismatch"] or 0.0) + 1e-12
                for gk in la["mismatch_scale_to_hold_at_infinite_thickness"]:
                    sa = la["mismatch_scale_to_hold_at_infinite_thickness"][gk]["no_floor"]
                    sk = lk["mismatch_scale_to_hold_at_infinite_thickness"][gk]["no_floor"]
                    assert (sa or 0.0) <= (sk or 0.0) + 1e-12, (name, pair, fam, gk)
    # the edges each branch is judged at: hot above 25 °C, cold below it
    assert min(t_hots.values()) > BRANCH_SPLIT_C > max(colds.values())


def energy_j(i_a: float, v: float, t_s: float) -> float:
    return i_a * v * t_s


def control_closure_and_impulses(sections) -> None:
    one = [(a, b, 9e-6) for a, b, _ in sections]
    zero = [(a, b, 0.0) for a, b, _ in sections]
    for z_f in (0.0, 11.3, 32.0, 50.0, 70.0, 90.0):
        for z_t in (8.3, 21.0):
            for h in (0.0, 5.0, 12.0):
                assert abs(artefact_um_per_k(one, z_f, z_t, h, 9e-6, 9e-6, 9e-6)) < 1e-12, (z_f, z_t, h)
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 1e-6, 0.0, 0.0) - (z_f - z_t) * 1e-3) < 1e-12
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 0.0, 1e-6, 0.0) - (z_t + h) * 1e-3) < 1e-12
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 0.0, 0.0, 1e-6) + h * 1e-3) < 1e-12
                for k, (a, b, _) in enumerate(sections):
                    imp = [(aa, bb, 1e-6 if j == k else 0.0) for j, (aa, bb, _) in enumerate(sections)]
                    want = -max(0.0, min(b, z_f) - a) * 1e-3
                    assert abs(artefact_um_per_k(imp, z_f, z_t, h, 0.0, 0.0, 0.0) - want) < 1e-12, (k, z_f)


def control_sections(z103: dict, premise: str, sections, alpha_w: float) -> None:
    span87, g = z103["geometry"]["shift_span_mm_87"], z103["geometry"]
    for a, b in itertools.pairwise(sections):
        assert abs(a[1] - b[0]) < 1e-9, "sections must tile the anchor"
    assert sections[0][0] == 0.0 and abs(sections[-1][1] - span87["ceiling_full_depth_77"]) < 1e-9, "full depth ≠ 103's"
    gyroid = sections[-1]
    assert abs(0.5 * (gyroid[0] + gyroid[1]) - span87["nominal_anode_centroid_to_flange_77"]) < 1e-9, "centroid ≠ 103's"
    peek_103 = (g["span_mm"] if premise == "flange_on_bark"
                else z103["zone3_fit"]["sections_mm"]["peek_gap"][1] - z103["zone3_fit"]["sections_mm"]["peek_gap"][0])
    assert abs(peek_in_path_mm(sections, g["span_mm"]) - peek_103) < 1e-9, (premise, "PEEK to the shank's top ≠ 103's")
    assert all(al > alpha_w for _, _, al in sections), "control 7: an anchor section at or below α_w — A not monotone"
    cross = frames_crossing_mm(sections, alpha_w)
    assert cross is not None and abs(abs(anchor_term_um_per_k(sections, cross, alpha_w)) - FRAME_UM_PER_K) < 1e-9


def control_thickness() -> None:
    """Control 8 — the knob and the cap. For each gap and drift, a thicker scale needs STRICTLY less remanence at its own
    best period, which grows with thickness and stays at or under 2πg; at the cap the needed field equals the linear
    range (the cap formula inverted — control 4 is the independent route), and a capped period never exceeds its cap. CAN catch a sign slip in the (1 − e^{−kt})
    term, a cap applied the wrong way or a scan that overruns it; CANNOT an error in the idealised field form."""
    ts = sorted({*SCALE_T_MM, *SCALE_T_KNOB_MM})
    for g in GAPS_MM:
        periods = [best_period_mm(t, g) for t in ts]
        assert all(a <= b for a, b in itertools.pairwise(periods)), (g, periods)
        assert periods[-1] <= 2 * math.pi * g + 0.02, (g, periods[-1])
        for db in BASE["offset_drift_T_per_K"].values():
            needs = [b_r_needed_t(p, t, g, db, FRAME_UM_PER_K) for p, t in zip(periods, ts, strict=True)]
            assert all(a > b for a, b in itertools.pairwise(needs)), (g, db, needs)
            for lin in BASE["linear_range_T"]:
                cap = period_cap_mm(lin, db, FRAME_UM_PER_K)
                assert abs(cap * math.sqrt(2) * db / (2 * math.pi * FRAME_UM_PER_K * 1e-3) - lin) < 1e-12
                for t in ts:
                    assert best_period_mm(t, g, p_max_mm=cap) <= cap + 1e-9, (t, g, lin)


def control_field() -> None:
    for g in GAPS_MM:
        assert abs(best_period_mm(1e3, g) - 2 * math.pi * g) < 0.02, g
        for t_mm in (*SCALE_T_MM, *SCALE_T_KNOB_MM):
            p = best_period_mm(t_mm, g)
            for db in BASE["offset_drift_T_per_K"].values():
                b = field_amplitude_t(b_r_needed_t(p, t_mm, g, db, FRAME_UM_PER_K), p, t_mm, g)
                assert abs(b - p * math.sqrt(2) * db / (2 * math.pi * FRAME_UM_PER_K * 1e-3)) < 1e-12, (g, t_mm)


def control_energy() -> None:
    members = sum(energy_j(i, V_OUT, t) for i, t in CYCLE_MEMBERS_J.values()) + E_RADIO_RX_TCXO_J
    assert abs(members / ETA_BUCK_ACTIVE - E_CYCLE) < 0.02e-3, (members / ETA_BUCK_ACTIVE, E_CYCLE)


def temperature_spans(hours: dict) -> dict:
    """Air (a stem-interior proxy): the diurnal range per local day in the growing season, the spread of daily means
    over unfrozen days, the freeze–thaw days."""
    days, idx = np.unique(np.array([s[:10] for s in hours["time"]]), return_inverse=True)
    t = hours["t_air"]
    tmax, tmin = np.full(len(days), -np.inf), np.full(len(days), np.inf)
    tsum, n = np.zeros(len(days)), np.zeros(len(days))
    np.maximum.at(tmax, idx, t)
    np.minimum.at(tmin, idx, t)
    np.add.at(tsum, idx, t)
    np.add.at(n, idx, 1)
    month = np.array([int(d[5:7]) for d in days])
    rng, mean = tmax - tmin, tsum / n
    growing, unfrozen = np.isin(month, (5, 6, 7, 8)), tmin > 0.0

    def pct(x, q):
        return round(float(np.percentile(x, q)), 1)

    return {"diurnal_range_growing_MJJA_K": {"p50": pct(rng[growing], 50), "p95": pct(rng[growing], 95)},
            "daily_mean_unfrozen_p5_p95_C": [pct(mean[unfrozen], 5), pct(mean[unfrozen], 95)],
            "freeze_thaw_days_per_year": round(float(((tmin < 0) & (tmax > 0)).sum() / (len(days) / 365.25)), 1),
            "unfrozen_days_share": round(float(unfrozen.mean()), 3), "days": len(days)}


def main() -> int:
    banner("HW.54 Р3(в) — a point dendrometer on the anchor: support artefact · scale behind the wall · read energy · travel")
    z103 = json.loads(WOOD_SHARE.read_text())
    z78 = json.loads(FLANGE_HEAT.read_text())
    z110 = json.loads(PV_AUTONOMY.read_text())
    radome, flange = json.loads(RADOME_CEM.read_text()), json.loads(FLANGE_CEM.read_text())
    alpha_w = z103["inputs"]["alpha_xylem_green_ppm_K"] * 1e-6
    z_t = dict(z103["geometry"]["bark_mm_78"])            # proxy: the dead bark under the flange, cut away under the probe
    ties = dict(z103["geometry"]["flange_seat_to_install_day_cambium_mm"])
    span87 = z103["geometry"]["shift_span_mm_87"]

    readings = {(p, s): anchor_sections(z103, p, s) for p in ("flange_on_bark", "zone3_fit") for s in ("bonded", "shoulder")}
    for (p, _s), secs in readings.items():
        control_closure_and_impulses(secs)
        control_sections(z103, p, secs, alpha_w)
    control_field()
    control_thickness()
    control_energy()

    s71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
    hours = s71.load_hours()
    assert len(hours["t_air"]) == z110["record"]["hours"], "the ERA5 record ≠ 110's"
    spans = temperature_spans(hours)

    # (1) the support: the anchor term per reading, fixation point and probe site
    shank_top = z103["geometry"]["span_mm"]
    gyroid_top = shank_top + z103["geometry"]["zone1_shank_in_sleeve"]["length_mm"]
    points = {"tie_shallowest": TIE_SHALLOWEST_MM, "tie_at_install_cambium": None, "zone1_shank_top": shank_top,
              "gyroid_top": gyroid_top, "anode_centroid": span87["nominal_anode_centroid_to_flange_77"],
              "gyroid_bottom": span87["ceiling_full_depth_77"]}
    support = {}
    for (prem, shank), secs in readings.items():
        rows = {}
        for site, zt in z_t.items():
            for name, zf in points.items():
                zf = ties[site] if zf is None else zf
                a = anchor_term_um_per_k(secs, zf, alpha_w)
                rows[f"{name}:{site}"] = {"z_f_mm": zf, "peek_in_path_mm": round(peek_in_path_mm(secs, zf), 2),
                                          "anchor_term_um_per_K": round(a, 3), "x_frames": round(abs(a) / FRAME_UM_PER_K, 1),
                                          "d_anchor_term_d_alpha_w_um_per_K_per_ppm": round(zf * 1e-3, 4),
                                          "d_total_A_d_alpha_w_um_per_K_per_ppm": round((zf - zt) * 1e-3, 4)}
        tie_drift = {site: [round(abs(alpha_w - alpha_at(secs, ties[site])) * r * 1e3, 3) for r in RADIAL_RATE_MM_PER_YR]
                     for site in ties}
        cross = frames_crossing_mm(secs, alpha_w)
        support[f"{prem}:{shank}"] = {
            "sections_mm_alpha_ppm_K": [[a, b, round(al * 1e6, 4)] for a, b, al in secs], "points": rows,
            "frames_crossing_depth_mm": round(cross, 2) if cross is not None else None,
            "crossing_minus_live_bark_depth_mm": {s: round(cross - zt, 3) for s, zt in z_t.items()},
            "reading_note": ("the consistent adverse end — the Zone-1 fit slipped" if (prem, shank) == ("flange_on_bark", "shoulder")
                             else "intermediate — the Zone-3 fit held while the Zone-1 fit slipped" if shank == "shoulder"
                             else "the fits held (103's reading)"),
            "tie_climb_drift_um_per_K_per_year_at_rate_ends": tie_drift}

    anchor_rows = [r for p in support.values() for r in p["points"].values()]
    worst = max(abs(r["anchor_term_um_per_K"]) for r in anchor_rows)
    worst_bonded = max(abs(r["anchor_term_um_per_K"]) for k, p in support.items() if k.endswith(":bonded")
                       for r in p["points"].values())
    d_t = spans["diurnal_range_growing_MJJA_K"]
    season_k = spans["daily_mean_unfrozen_p5_p95_C"][1] - spans["daily_mean_unfrozen_p5_p95_C"][0]
    in_um = {f"{lbl}": {"diurnal_growing_p50_um": round(w * d_t["p50"], 1), "diurnal_growing_p95_um": round(w * d_t["p95"], 1),
                        "seasonal_unfrozen_p5_p95_um": round(w * season_k, 1)}
             for lbl, w in (("worst_shoulder", worst), ("worst_bonded", worst_bonded))}
    hot = z78["verdict"]["worst_cell"]["sunlit_0.50"]
    flange_hot = {"flange_max_C": hot["flange_max_C"], "cambium_under_flange_max_C": hot["cambium_max_C"],
                  "cambium_no_flange_max_C": z78["verdict"]["no_flange_max_C"], "case": "78: sunlit, α 0.5, still air"}
    stf = z103["stiffness_N_per_mm"]
    k_s = z103["zone3_fit"]["stiffness_N_per_mm"]["sleeve_whole"]
    k_a = stf["anode_bond"]
    k_f = stf["bark_bearing_at_air_dry_readings"]
    u_rows = {f"{load}:{a_key}:{f_key}": round((1 / k_a[a_key] + 1 / k_s[load])
                                               / (1 / k_a[a_key] + 1 / k_s[load] + 1 / k_f[f_key]), 4)
              for load in ("sway", "slow") for a_key in k_a for f_key in k_f}
    u_lo, u_hi = min(u_rows.values()), max(u_rows.values())
    bearing = {"fraction_lost_U_at_air_dry_bark_readings": [u_lo, u_hi], "fraction_lost_U_rigid_bark": 1.0,
               "before_anode_bond": ("unpriced — before ingrowth the deep tie is not the anode but "
                                     + " and ".join(z103["zone3_fit"]["share"]["state1_ties_not_bounded"])
                                     + ", which 103 leaves unbounded (zone3_fit.share.state1_ties_not_bounded)"),
               "growth_under_reported_um_per_yr_at_795": [round(u_lo * GROWTH["yr_um"], 1), round(u_hi * GROWTH["yr_um"], 1)],
               "U_rows_premise_b": u_rows,
               "reading": "U = (1/k_A + 1/k_s)/(1/k_A + 1/k_s + 1/k_F) on 103's stiffnesses, premise (b), sway and slow "
                          "(relaxed PEEK): the fraction of a radial change of the bark the flange follows, so the reading loses "
                          "it (our reading of a growth push as a displacement source; k_F is the air-dry bark readings, green "
                          "bark is softer); U is priced with the anode BONDED (103's state 2) — before ingrowth the deep tie is a "
                          "grip 103 leaves unbounded, so U there is not priced; under premise (a) a rising bark can "
                          "lift the flange off the sleeve — our reading, 103 does not model lift-off"}

    # (2) the scale behind the wall
    scale = {f"t{t_mm:g}:g{g:g}": scale_cell(t_mm, g, radome["wall_thickness_mm"]) for t_mm in SCALE_T_MM for g in GAPS_MM}
    month_fast_mm = RADIAL_RATE_MM_PER_YR[1] / GROWTH_MONTHS_MIN
    bases = {"winter": FROST_SWING_MM[1],
             "growing_month_fast_end_plus_daily_swing": round(month_fast_mm + DAILY_SWING_MM[1], 3),
             "cross_season_outage": round(FROST_SWING_MM[1] + month_fast_mm + DAILY_SWING_MM[1], 3)}
    unwrap = {"worst_change_mm_by_basis": bases,
              "period_required_mm_by_basis": {k: round(2 * v, 2) for k, v in bases.items()},
              "margin_by_geometry": {key: {b: round(v["half_period_mm"] / w, 3) for b, w in bases.items()}
                                     for key, v in scale.items()},
              "basis_note": "season-consistent: winter = the frost swing with no growth; growing season = a month of the fast "
                            f"end's increment (laid down over ≥ {GROWTH_MONTHS_MIN:g} months — our assumption; a growing-season "
                            "outage of a month is itself an assumption, 110's outages fall in winter) plus the daily swing; "
                            "cross-season = an outage spanning both. P/2 bounds an absolute-in-period phase; the collector's "
                            "«half a pole» bounds an incremental pole counter, a different reader. A period above P* buys unwrap "
                            "margin at a small cost to the OFFSET term (its optimum is flat) — the angle and mismatch "
                            "errors grow in proportion to P.",
              "sensitivity_two_growing_months": (lambda w: {
                  "worst_change_mm": round(w, 3), "period_required_mm": round(2 * w, 2),
                  "geometries_meeting_at_p_star": [k for k, v in scale.items() if v["best_period_mm"] >= 2 * w]})(
                  FROST_SWING_MM[1] + 2 * month_fast_mm + DAILY_SWING_MM[1]),
              "encoder_2mm_half_period_mm": ENCODER_2MM["period_mm"] / 2,
              "count_home": "the server unwraps the delivered phases — nothing persisted on the device (03_01: the RTC backup "
                            "domain does not survive an outage on our board). What breaks it: a maintenance event that moves the "
                            "sensor against the scale (radome off/on, a board re-seat) — a step the server must mark as a "
                            "discontinuity; a ledger whose old readings are archived or expire — the server keeps a persisted "
                            "running unwrapped position, not a recompute over history; creep of the sensor's mount; and the "
                            "phase needs a field on the wire."}

    # (2b) the thickness knob — a thicker scale lowers the remanence the offset term needs, at a longer best period
    knob_rows = {}
    for t_mm in SCALE_T_KNOB_MM:
        for g in GAPS_MM:
            row = scale_cell(t_mm, g, radome["wall_thickness_mm"])
            ref = scale[f"t2:g{g:g}"]
            # the ratio from the UNROUNDED needs — dividing the cached (rounded) ones put up to 0.003 of artefact into it
            row["b_r_needed_over_t2_same_gap"] = {
                k: round(b_r_needed_t(row["best_period_mm"], t_mm, g, db, FRAME_UM_PER_K)
                         / b_r_needed_t(ref["best_period_mm"], 2.0, g, db, FRAME_UM_PER_K), 3)
                for k, db in BASE["offset_drift_T_per_K"].items()}
            row["best_period_over_t2_same_gap"] = round(row["best_period_mm"] / ref["best_period_mm"], 3)
            row["unwrap_margin_by_basis"] = {b: round(row["half_period_mm"] / w, 3) for b, w in bases.items()}
            knob_rows[f"t{t_mm:g}:g{g:g}"] = row
    thickness_knob = {
        "thickness_mm": SCALE_T_KNOB_MM, "reference": "the t 2 mm row of the base table at the same gap",
        "rows": knob_rows,
        "reading": "each row is the base table's row at a thicker scale, computed by the same function; the field the "
                   "offset term needs at the sensor depends on the period alone, so a longer best period also raises "
                   "it — `within_sensor_linear_range` gives the best period the sensor's linear range allows and the "
                   "remanence needed there. The base table's population stays t 1–2 mm."}

    # (2c) the magnet's temperature — the hot end binds the need, the cold end the cap
    z81 = json.loads(SKY_EDGE.read_text())
    t_hots = {k: z78["verdict"]["worst_cell"][k]["flange_max_C"] for k in HOT_HOUR_78}
    colds = {"air_era5_min": float(np.min(hours["t_air"])), "capsule_sky_edge_81": z81["edges"]["deep"]["coldest_c"]}
    grid_rows = {**scale, **knob_rows}
    floor_mm = unwrap["period_required_mm_by_basis"][UNWRAP_FLOOR_BASIS]
    mt = magnet_temperature(t_hots, colds, grid_rows, floor_mm, unwrap["sensitivity_two_growing_months"]["period_required_mm"])
    control_temperature(mt, grid_rows, t_hots, colds, z81, hours)
    st = sensor_table(mt["_args"], t_hots, colds, floor_mm)
    control_sensor_table(st, mt["_args"], mt, t_hots, colds)
    lin = linearity_reading(mt["_args"], floor_mm)
    scr = screen_rows(mt["_args"], t_hots, colds)
    control_linearity_and_screen(lin, scr, st, mt["_args"])
    ang = angle_rows(mt["_args"], t_hots, colds, floor_mm, radome["wall_thickness_mm"])
    control_angle(ang, mt["_args"], floor_mm)
    rch = package_reach(st, lin, radome["wall_thickness_mm"], mt["_args"])
    control_reach(rch, st)
    mt.pop("_args")
    hinge = {f"t{t:g}:g{GAP_REALISTIC_MM:g}": {c: mt["cells"][f"t{t:g}:g{GAP_REALISTIC_MM:g}"]["need_T"][f"REFeB_sintered:{c}"]
                                               for c in ("isothermal", "kind", "adverse")} for t in (1.0, 2.0)}
    magnet_t = {
        **mt,
        "inputs": {"br_ref_band_C": BR_REF_BAND_C, "t_hot_C": t_hots,
                   "t_hot_source": "78: the flange's hottest hour, sunlit, still air — α 0.5 (the ratified finish) ⊥ α 0.9 (a dark "
                                   "one); the scale's own temperature is not modelled",
                   "t_hot_shaded_alpha_0_5_C_78": z78["verdict"]["worst_cell"]["shaded_0.50"]["flange_max_C"],
                   "t_cold_C": colds, "t_cold_at": z81["air"]["at"],
                   "t_cold_source": {"air_era5_min": "the ERA5 record's coldest air hour (71's loader)",
                                     "capsule_sky_edge_81": "81: the capsule under a clear sky, no sun, still air, the same hour — a "
                                                            "lump the capsule's size, not the scale"},
                   "coefficients_per_K_kind_adverse": BR_TEMP_COEFF_PER_K, "realistic_gap_mm": GAP_REALISTIC_MM,
                   "unwrap_floor_basis": UNWRAP_FLOOR_BASIS, "class_spread_assumed": CLASS_SPREAD,
                   "family_maxima_T": {f: MAGNET_FAMILIES_BR_T[f][1] for f in BR_TEMP_COEFF_PER_K},
                   "family_minima_T": {f: MAGNET_FAMILIES_BR_T[f][0] for f in BR_TEMP_COEFF_PER_K}},
        "remanence_a_class_must_reach_T_unread_editions": hinge,
        "reading": "B_r(T) = B_r(T_ref)·(1 + α·(T − T_ref)), T_ref in the (23 ± 5) °C band a unit meets its class minimum at; a "
                   "period fixed for the batch must keep the weakest unit over the need at the hottest hour and the strongest inside "
                   "the range at the coldest. A family holds a cell when its strongest class (MAGNET_FAMILIES_BR_T, the "
                   "2001/AMD1:2004 minima) reaches the minimum, over a continuous period inside its thermal cap, of the hot-end need; "
                   "«with the unwrap floor» adds P ≥ the cross-season unwrap period and lets any class of the family's span be chosen. "
                   "Kind = a uniform batch meeting its minimum at 28 °C, the coefficient's smaller end, 78's α 0.5 hour and the "
                   "coldest air; adverse = the need on a unit meeting its minimum at 18 °C and the cap on one meeting it at 28 °C, "
                   "the larger end, 78's α 0.9 hour and 81's sky edge that hour. Gap and thickness limits are solved roots (None = no "
                   "gap ≥ 0.2 mm / no thickness; the t → ∞ need beside), for the offset and range bounds. The class minima are valid "
                   "only for magnets ≥ 5 mm in all three directions (IEC 60404-8-1:2023 §5.2) — every thinner scale, and every pole "
                   "shorter than 5 mm (P/2 at the caps here is under it), reads them outside that validity. Ferrite has no "
                   "coefficient: it is solved isothermally, and its floor list is its own. The 2015 and 2023 editions' minima are "
                   "unread: `remanence_a_class_must_reach_T_unread_editions` is what such a class would have to reach."}

    # (3) the energy of a read, riding cadence C
    cad = z110["inputs"]["cadence_c_interval_s"]
    demand = {k: v["nominal"] for k, v in z110["inputs"]["demand_uw"].items()}
    br = SENSORS[BASE_SENSOR]
    t_sample = br["t_conv_one_ch_s"] + br["t_add_ch_s"]
    t_wake = sum(br["t_wake_s"])
    # N from the VERDICT lane (the guaranteed drift — the field a scale designed to the verdict puts on the sensor);
    # until 2026-11-15 N was the maximum over the typ ⊥ max lanes, i.e. at a scale designed to the typical drift —
    # kept beside, reproducible (`convention_to_2026_11_15`)
    n_verdict = max(v["two_channel_samples_for_1um_at_needed_b_r"][VERDICT_LANE.split(":")[1]] for v in scale.values())
    n_old = max(n for v in scale.values() for n in v["two_channel_samples_for_1um_at_needed_b_r"].values())
    e_hall, e_old = (energy_j(br["i_active_A"] + I_CORE_RUN_A, V_OUT, n * t_sample + t_wake) / ETA_BUCK_ACTIVE
                     for n in (n_verdict, n_old))
    e_enc = {k: energy_j(i + I_CORE_RUN_A, V_OUT, ENCODER_2MM["t_power_up_s"]) / ETA_BUCK_ACTIVE
             for k, i in ENCODER_2MM["i_supply_A"].items()}
    energy = {"cadence_c_s": cad, "demand_uW_110_nominal": demand,
              "two_channel_sample_s": round(t_sample, 6), "samples_verdict_lane": n_verdict,
              "samples_from": f"the verdict lane ({VERDICT_LANE}) of the base row {BASE_SENSOR}",
              "hall_read_vstor_uJ": round(e_hall * 1e6, 1), "hall_read_avg_uW": round(e_hall / cad * 1e6, 4),
              "hall_read_share_of_E_cycle_pct": round(e_hall / E_CYCLE * 100, 2),
              "convention_to_2026_11_15": {
                  "samples_worst_lane": n_old, "hall_read_vstor_uJ": round(e_old * 1e6, 1),
                  "hall_read_share_of_E_cycle_pct": round(e_old / E_CYCLE * 100, 2),
                  "rule": "N the maximum over the typ ⊥ max lanes — the typical lane is a scale designed to the typical "
                          "drift, whose weaker field needs more samples; the verdict's scale is designed to the guaranteed one"},
              "hall_sleep_uW_at_vout": round(br["i_sleep_A"] * V_OUT * 1e6, 4),
              "hall_sleep_share_of_smallest_demand_pct": round(br["i_sleep_A"] * V_OUT * 1e6 / min(demand.values()) * 100, 2),
              "encoder_2mm_read_vstor_mJ": {k: round(v * 1e3, 3) for k, v in e_enc.items()},
              "encoder_2mm_avg_uW": {k: round(v / cad * 1e6, 3) for k, v in e_enc.items()},
              "encoder_2mm_share_of_E_cycle_pct": {k: round(v / E_CYCLE * 100, 2) for k, v in e_enc.items()}}

    # the base row's verdict-lane read in (2d) is this block's read (one function of the same row)
    bx = st[BASE_SENSOR]["pairs"]["x_y"]["read"]
    assert bx["samples"] == n_verdict and bx["vstor_uJ"] == energy["hall_read_vstor_uJ"], (bx, n_verdict)

    # (4) the travel window, along the TILTED axis: the seat is faced square to the anchor's axis and the axis stands at
    # the install angle, so `78`'s facing spread is Ø·sin θ — a RADIAL depth difference — and θ is recovered from those two
    # raw numbers (no new input). Along the axis the bark's plane stands spread/cos θ higher at the deep edge than at the
    # shallow one (half that on the mid-line), and a mark h along the axis is passed after a RADIAL travel (h − b₀)·cos θ.
    # Until 2026-11-16 this block subtracted the radial spread from an axial height and carried no tilt (00_07 HW.54);
    # it is the ONE home of the oblique cut — `119` reads it from here
    spread, flange_d = z78["bark"]["facing_spread_mm"], z78["bark"]["flange_diameter_mm"]      # raw (§When Modifying #6)
    tilt = math.asin(spread / flange_d)
    cos_t = math.cos(tilt)
    flange_t = flange["flange_thickness_mm"]
    top_over_rim = radome["cavity_height_mm"] + radome["bell_radius_mm"]           # Radome.TopZMm, along the axis
    dome_top_over_seat = flange_t + top_over_rim
    install = {"flange_top": 0.0, "deep_edge": spread / cos_t - flange_t, "mid_seat": spread / (2.0 * cos_t) - flange_t,
               "shallow_edge": -flange_t}                                          # the install-day bark over the flange's top
    climb = {ref: (top_over_rim - b0) * cos_t for ref, b0 in install.items()}      # the radial travel to the dome's top
    slow, fast = RADIAL_RATE_MM_PER_YR
    travel = {"tilt": {"install_angle_deg": math.degrees(tilt), "install_angle_rad": tilt, "cos": cos_t, "facing_spread_mm_78": spread,
                       "flange_diameter_mm_78": flange_d,
                       "from": "asin(78's facing spread / the flange's diameter) — the seat faced square to the tilted axis"},
              "dome_top_over_seat_mm": dome_top_over_seat, "of_which_flange_thickness_placeholder_mm": flange_t,
              "install_bark_over_flange_top_mm": install,
              "outer_bark_climb_to_dome_top_mm": {ref: round(c, 3) for ref, c in climb.items()},
              "outer_bark_to_dome_top_yr": [round(climb["deep_edge"] / fast, 1), round(climb["shallow_edge"] / slow, 1)],
              "outer_bark_to_dome_top_yr_by_edge_fast_slow": {
                  ref: [round(climb[ref] / fast, 1), round(climb[ref] / slow, 1)] for ref in ("deep_edge", "mid_seat", "shallow_edge")},
              "radome_height_over_flange_top_mm": top_over_rim,
              "radial_travel_flange_top_to_dome_top_mm": climb["flange_top"],
              "outer_bark_flange_top_to_dome_top_yr_fast_slow": [round(climb["flange_top"] / fast, 1),
                                                                 round(climb["flange_top"] / slow, 1)],
              # a one-sided «passed inside the life at every rate above X»: X rounded UP keeps it true (§When Modifying #43)
              "flange_top_to_dome_top_inside_life_above_mm_per_yr": math.ceil(climb["flange_top"] / LIFE_YR * 100) / 100,
              "outer_bark_above_flange_top_at_install_mm": {ref: round(install[ref], 3) for ref in ("deep_edge", "mid_seat", "shallow_edge")},
              "live_bark_to_flange_seat_yr": {s: [round(zt / fast, 1), round(zt / slow, 1)] for s, zt in z_t.items()},
              "live_bark_note": "z_t is a RADIAL thickness — 78's dead-bark ridge (radial) minus its facing spread Ø·sin θ "
                                "(a radial depth difference) — so the radial travel to the seat is z_t itself, with no "
                                "cos θ: that factor turns a height ALONG the axis into a radial travel, as for the dome "
                                "above; model (1) reads the same number along the axis, an approximation by 1/cos θ",
              "twenty_year_travel_mm": [round(LIFE_YR * slow, 1), round(LIFE_YR * fast, 1)]}

    # ── print ──
    print(f"  (1) the support's anchor term, µm/K (α_xylem {alpha_w * 1e6:g} ppm/K; frames < {FRAME_UM_PER_K} µm/K):")
    for key, d in support.items():
        print(f"    {key}: |A| reaches the frames at {d['frames_crossing_depth_mm']} mm "
              f"(minus the live bark's depth: {d['crossing_minus_live_bark_depth_mm']} mm; {d['reading_note']}); tie climb drifts A by "
              f"{d['tie_climb_drift_um_per_K_per_year_at_rate_ends']} µm/K per year")
        for k, r in d["points"].items():
            if k.endswith("thin_contact_78"):
                print(f"      {k.split(':')[0]:24s} z_f {r['z_f_mm']:6.2f}  PEEK {r['peek_in_path_mm']:5.1f} mm  "
                      f"A {r['anchor_term_um_per_K']:+.3f}  (×{r['x_frames']})")
    print(f"    air (stem-interior proxy, not a bound): growing diurnal p50/p95 {d_t['p50']}/{d_t['p95']} K; unfrozen daily "
          f"means p5–p95 {spans['daily_mean_unfrozen_p5_p95_C']} °C; freeze–thaw {spans['freeze_thaw_days_per_year']} d/yr")
    print(f"    in µm: {in_um}; under the flange in sun (78): {flange_hot}")
    print(f"    bearing: {bearing}")
    print("  (2) the scale behind the wall — P*, B_r needed (offset term only), field at the sensor, samples for 1 µm:")
    for k, v in scale.items():
        print(f"      {k:8s} P* {v['best_period_mm']:6.2f}  B_r {v['b_r_needed_T_offset_term_only']} T  "
              f"B {v['field_at_sensor_mT_at_needed_b_r']} mT  N {v['two_channel_samples_for_1um_at_needed_b_r']}  "
              f"pairs {v['axis_pairs']}")
    print(f"    unwrap: {json.dumps({k: unwrap[k] for k in ('worst_change_mm_by_basis', 'period_required_mm_by_basis', 'margin_by_geometry')})}")
    print("  (2b) the thickness knob — P*, B_r needed (typ ⊥ max) and its ratio to t 2 mm; inside the 80 mT range at max drift:")
    for k, v in knob_rows.items():
        w = v["within_sensor_linear_range"]["80mT:max"]
        print(f"      {k:9s} P* {v['best_period_mm']:6.2f}  B_r {v['b_r_needed_T_offset_term_only']} T  "
              f"×t2 {v['b_r_needed_over_t2_same_gap']}  | ≤80 mT, max: P {w['best_period_within_cap_mm']} "
              f"B_r {w['b_r_needed_T']} {w['magnet_families_meeting']}")
    for k, v in scale.items():
        w = v["within_sensor_linear_range"]["80mT:max"]
        print(f"      base {k:9s} ≤80 mT, max: P {w['best_period_within_cap_mm']} (cap {w['period_cap_mm']}) "
              f"B_r {w['b_r_needed_T']} {w['magnet_families_meeting']}  | at P*: {v['magnet_families_meeting_at_p_star']}")
    print(f"  (2c) the magnet's temperature ({VERDICT_LANE}; hot {t_hots} °C, cold {colds}):")
    for fam, by_t in magnet_t["gap_limit_mm"].items():
        caps = {c: round(v, 3) for c, v in magnet_t["period_cap_mm"][fam].items()}
        lims = {t: {c: (None if v is None else round(v, 3)) for c, v in d.items()} for t, d in by_t.items()}
        tl = {c: (None if v is None else round(v, 3)) for c, v in magnet_t["thickness_limit_mm_at_realistic_gap"][fam].items()}
        print(f"      {fam:15s} cap {caps}  gap limits {lims}  thickness limit at {GAP_REALISTIC_MM:g} mm {tl}")
    print(f"      the need at t 1 · 2 mm on {GAP_REALISTIC_MM:g} mm, REFeB: {json.dumps(hinge)}")
    print(f"      break-even hot hour, t 2 mm on 3 mm, REFeB: {magnet_t['hot_hour_C_at_which_t2_on_3mm_REFeB_breaks_even']}; "
          f"spread: {magnet_t['thickness_limit_mm_at_realistic_gap_adverse_by_class_spread']}; ferrite: {json.dumps(magnet_t['ferrite_isothermal'])}")
    for key, cell in magnet_t["cells"].items():
        if cell["holds"] != cell["holds_with_unwrap_floor"]:
            print(f"      unwrap floor bites at {key}: {cell['holds']} → {cell['holds_with_unwrap_floor']}")
    print(f"  (2d) the sensor table — g 3 · 4 mm, adverse corner, thickness limit REFeB / RE₂Co₁₇ / RECo₅, mm "
          f"(offset only ⊥ + mismatch ⊥ + unwrap floor {floor_mm} mm; — = none):")
    def _t(v):
        return "—" if v is None else f"{v:.2f}"
    for name, r in st.items():
        for pair, pr in r["pairs"].items():
            cols = []
            for g in VERDICT_GAPS_MM:
                cols.append(" ⊥ ".join("/".join(_t(pr["cells"][f"{fam}:adverse:g{g:g}"][v]["t_min_mm"]) for fam in VERDICT_FAMILIES)
                                       for v in ("offset_only", "with_mismatch", "with_mismatch_and_unwrap_floor")))
            alone = pr["mismatch_alone_takes_the_frames_at_period_mm"]["guaranteed"]
            print(f"      {name:17s} {pair}  g3 {cols[0]}  |  g4 {cols[1]}  | mismatch alone at P "
                  f"{ {k: (None if v is None else round(v, 2)) for k, v in alone.items()} } mm; read {pr['read']}")
    print(f"      not in the table: {list(SENSOR_GAPS)}")
    print(f"  (2e) drift linearity (TI CS3699089): {lin['verdict']}")
    for name, r in lin["rows"].items():
        for pair, pr in r["pairs"].items():
            for key, blk in pr.items():
                c3 = blk["cells"]["REFeB_sintered:g3"]
                g10 = blk["gap_limit_mm_at_t10_REFeB"]
                print(f"      {name} {pair} {key:34s} REFeB g3 t_min {c3['t_min_mm'] if c3['t_min_mm'] is None else round(c3['t_min_mm'], 2)}"
                      f" (floor {c3['t_min_mm_with_unwrap_floor'] if c3['t_min_mm_with_unwrap_floor'] is None else round(c3['t_min_mm_with_unwrap_floor'], 2)})"
                      f"  gap@t10 {None if g10 is None else round(g10, 2)}")
    print("  (2f) screen rows — holds any cell at 3 · 4 mm (any family, corner, thickness):")
    for name, s in scr.items():
        print(f"      {name:14s} " + "  ".join(f"{pair}: {pr['holds_any_cell']}" for pair, pr in s["pairs"].items()))
    print(f"  (2g) angle rows: {ang['verdict']}")
    for name, r in ang["rows"].items():
        print(f"      {name}: min gap {r['min_gap_mm']:.2f} mm, floor {r['unwrap_floor_mm_effective']:g} mm, static "
              f"{r['static_cyclic_um_at_floor']} µm, lifetime row {r['lifetime_row_um_at_floor']} µm at the floor")
        for key, blk in r["readings"].items():
            cm = blk["cells"]["REFeB_sintered:gmin"]
            w = cm["window_thick_with_floor_mm"]
            print(f"        {key:44s} P_max {blk['p_max_mm']:6.2f} ({blk['binding_branch']})  REFeB @gmin P_sat "
                  f"{cm['p_sat_mm_thick']:.2f}  window {None if w is None else [round(x, 2) for x in w]}")
        for c, m in r["members_alone"].items():
            for mk, blk in m.items():
                print(f"        {c}: {mk} alone caps P at {blk['cap_mm']:.1f} mm{' (rejected)' if blk.get('rejected') else ''}")
    print(f"  (2h) package reach: {rch['verdict']}")
    print(f"  (3) read energy: {json.dumps(energy, ensure_ascii=False)}")
    print(f"  (4) travel: {json.dumps(travel, ensure_ascii=False)}")

    OUT.write_text(json.dumps({
        "script": Path(__file__).name,
        "leg": "00_07 HW.54 Р3(в)",
        "what": "a point dendrometer with the anchor as its support: (1) the support's thermal artefact per fixation depth "
                "and the bark bearing's share, (2) the magnetic scale behind the capsule wall — period, the Hall sensor's "
                "error terms, the unwrap margin, (3) the energy of a read on cadence C, (4) years until the bark reaches "
                "the flange seat and the dome's top",
        "inputs": {"alpha_xylem_green_ppm_K": round(alpha_w * 1e6, 4), "alpha_peek_ppm_K": round(ALPHA_PEEK_1K * 1e6, 4),
                   "dead_bark_under_flange_78_probe_proxy_mm": z_t, "tie_axis_mm_103": [TIE_SHALLOWEST_MM, ties],
                   "frame_sensitivity_um_per_K": FRAME_UM_PER_K, "growth": GROWTH, "frost_swing_mm": FROST_SWING_MM,
                   "daily_swing_mm": DAILY_SWING_MM, "radial_rate_mm_per_yr": RADIAL_RATE_MM_PER_YR,
                   "growth_months_min_assumed": GROWTH_MONTHS_MIN, "sensors": SENSORS, "base_sensor": BASE_SENSOR,
                   "sensor_gaps": SENSOR_GAPS, "screen_rows": SCREEN_ROWS, "angle_rows": ANGLE_ROWS,
                   "package_reach": PACKAGE_REACH,
                   "branch_span_K": BRANCH_SPAN_K,
                   "mismatch_linear_spread_K_assumed": MISMATCH_LINEAR_SPREAD_K, "encoder_2mm": ENCODER_2MM,
                   "core_run_A": I_CORE_RUN_A, "v_out": V_OUT, "eta_buck_active": ETA_BUCK_ACTIVE, "e_cycle_J": E_CYCLE,
                   "gaps_mm": GAPS_MM, "scale_thickness_mm": SCALE_T_MM, "noise_target_um": NOISE_TARGET_UM,
                   "scale_thickness_knob_mm": SCALE_T_KNOB_MM, "magnet_families_br_T": MAGNET_FAMILIES_BR_T,
                   "sources": {"geometry_alpha_share": "103 cache (anchor_wood_share.json); xylem α — Sevanto et al. 2005, "
                                                       "Boreal Env. Res. 10:437, Table 1, P. sylvestris, radial",
                               "flange_heat": "78 cache (flange_cambium_heat.json)",
                               "radome_flange": "tools/cad/cem/radome.json · cathode_flange.json; top = Radome.TopZMm",
                               "cadence_demand": "110 cache", "air": "ERA5 hourly, Cherkasy grid point (71's loader)",
                               "angle": "the angle rows' primaries, each in `angle_rows.*.source` (read 2026-11-17)",
                               "hall": "the sensor table's rows, each with its datasheet section in `sensors.*.source` "
                                       "(TI SLYS045C · SBASAF4 · SLYS053C, read 2026-11-16; SLYS045 first read 2026-10-31; "
                                       "Infineon TLE493D-P3B6 Rev. 1.0 and the screen rows' Melexis and Allegro "
                                       "datasheets, read 2026-11-17); TI's drift-linearity definition — case CS3699089",
                               "encoder": "ams AS5311 rev 1.13",
                               "frames": "Zweifel et al. 2021 New Phytol. 10.1111/nph.17552, Methods (ZN11)",
                               "growth": "nph.17552 Table 1 · Etzold et al. 2022 Ecol. Lett. 10.1111/ele.13933 · "
                                         "Zweifel et al. 2021 Front. For. Glob. Change 10.3389/ffgc.2021.776905 p. 9",
                               "swings_and_rate_ends": "01_03 §4 ⊕ (в)", "core_vout_cycle": "02_03 §9.4",
                               "magnet_families": "01_03 §4 ⊕ (в), desk 2026-11-10 — IEC 60404-8-1:2001/AMD1:2004 "
                                                  "Tables 11–12 (specified minima) · MMPA 0100-00 Table III-1 (ferrite, "
                                                  "typical) — a mirror, edit THERE",
                               "collection": "handoff 2026-10-26_r3v_dendrometer.json"}},
        "controls": {"closure_and_impulses": "A = 0 with one α; unit impulses → z_f − z_t · z_t + h · −h · −section length",
                     "sections": "tile from 0, end at 103's full depth, gyroid centre on its anode centroid, 103's PEEK "
                                 "length to the shank's top",
                     "field_optimum": "P* = 2πg for a thick scale",
                     "thickness_and_cap": "a thicker scale needs strictly less B_r at a P* that grows toward 2πg; the "
                                          "field needed at the cap equals the linear range; no capped period overruns it",
                     "energy": "02_03 §9.4 members → lib's E_CYCLE through the active buck",
                     "era5_hours": z110["record"]["hours"], "monotone_support": "every anchor section's α > α_w"},
        "temperature": spans,
        "support": support,
        "support_worst_abs_um_per_K": {"shoulder": round(worst, 3), "bonded": round(worst_bonded, 3)},
        "support_worst_in_um_air_proxy": in_um,
        "flange_hot_hour_78": flange_hot,
        "bark_bearing": bearing,
        "design_terms": "(α_s − α_w)·z_t + (α_s − α_h)·h — nulled in the base reading; each ppm/K of mismatch costs "
                        "z_t (or h) in mm × 1e-3 µm/K, and α_s = α_w cannot be designed while α_w is one reading",
        "scale": scale,
        "scale_thickness_knob": thickness_knob,
        "scale_magnet_temperature": magnet_t,
        "sensor_table": {
            "rule": "the SUM rule: per temperature branch the offset term (P/2π)·δB_pair/B plus the mismatch term "
                    "(P/2π)·ε/2, both per kelvin, must stay within the frames' 0.3 µm/K — a linear sum of two worst-case "
                    "bounds of independent sources (an RSS would be kinder and is not taken); δB_pair = √(δa² + δb²) of the "
                    "pair's axes; each branch over its own band, where that band's field is weakest — 25 → +125 °C at the "
                    "hottest hour, 25 → −40 °C at its warm end, 25 °C (at the cold edge the field is stronger) — and the "
                    "range at the coldest hour; the guaranteed column (the mismatch's typical one where no guaranteed one "
                    "exists, flagged). The support's term (1) is NOT summed — it is a maximum over unknown fixations",
            "branch_binds_at_C": {"hot": "the corner's hottest hour", "cold": BRANCH_SPLIT_C},
            "corners": "(2c)'s: isothermal · kind · adverse, the same family coefficients, hours and class band",
            "unwrap_floor_mm": floor_mm, "gaps_mm": VERDICT_GAPS_MM,
            "rows": st},
        "sensor_drift_linearity": lin,
        "sensor_screen": {"rule": "the sensor table's sum rule on the screen rows' two drift bounds; no read, no levers",
                          "rows": scr},
        "sensor_angle": ang,
        "sensor_package_reach": rch,
        "unwrap": unwrap,
        "energy": energy,
        "travel": travel,
    }, indent=2, ensure_ascii=False))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
