# Defensive Disclosure — SilkenNet self-powered tree-health monitor (prior art)

> **Author / discloser:** Oleksii Lukin (SilkenNet) · **Public repository:** `github.com/Alexey-Lukin/silken_net`
> **First published in the public repository:** 2026-06-07 (commit `b0546460`) · **This revision:** 2026-09-05
> **Status:** disclosure-ready for submission to Technical Disclosure Commons.
>
> **What this is:** a deliberate **public technical disclosure** of the inventive core of SilkenNet,
> published **as prior art**. The goal is the opposite of a patent: to place the invention in the public
> record so that (a) it stays **free for every forest and community** to use, and (b) a third party cannot
> obtain valid claims over it and lock the network out. This is the honest execution of a
> **defensive-publication-first** posture.
>
> **Why publish rather than patent:** for a mission-first project with a public repository, the
> enforcement reality of a solo Ukrainian rights-holder, and open/DePIN DNA, defensive publication
> achieves anti-capture without the cost and exclusivity of a patent. Disclosure posture is owned by
> [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md); novelty landscape →
> [`prior_art_landscape.md`](prior_art_landscape.md); technical canon →
> [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (EBFC) ·
> [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (gyroid).
>
> **Language note.** This document is written wholly in English, unlike the rest of this repository.
> That is deliberate: prior art only defeats a later claim if an examiner actually **finds** it, and
> patent examination is conducted through English full-text and CPC classification search. A disclosure
> nobody retrieves is legally public and practically useless. State home → [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3.

---

## 1. Inventive core — two synergies

Every component **taken separately** — gyroid titanium implant, FAD-GDH/Os enzymatic biofuel cell,
laccase/ZIF cathode, LoRa mesh, blockchain-anchored MRV — already has prior art
([`prior_art_landscape.md`](prior_art_landscape.md)). The substance of this disclosure is therefore **not
the components but two synergies that no single source teaches**, and it is precisely those that are
placed here into the public record:

- **SYNERGY A — dual-function EBFC.** One and the same enzymatic biofuel cell **simultaneously**
  (a) powers the electronics *and* (b) acts as the biosensor with **zero instrumental noise**: the
  supercapacitor charge time `delta_t` **is itself** the measurement of tree physiology. Because there is
  no separate sensor, there is no separate sensor noise, sensor power draw, or sensor drift. Conventional
  engineering *adds* a sensor; here the sensor is *eliminated*.
- **SYNERGY B — triple-function gyroid.** A single triply-periodic-minimal-surface (gyroid) geometry
  **simultaneously** (a) admits xylem sap into its porous volume, (b) provides isoelastic stress matching
  to living wood, and (c) forms the metal↔xylem interface electrode of that same EBFC.
- **SYNERGY C — the chaotic transform as an INTEGRITY SEAL, not a sensor.** The same non-linear
  (Lorenz) transform is evaluated **twice and independently**: once on the constrained node, from a
  per-device secret seed provisioned at manufacture, and once on the verifying server from that same
  seed — and the two results must agree **categorically**. Because a chaotic map amplifies any
  divergence in inputs or initial state exponentially, a party not holding the seed cannot fabricate a
  telemetry frame whose reported measurements and reported transform result are mutually consistent.
  The measurement is thereby rendered **self-authenticating without a separate secure element or
  per-frame signature**: forgery is defeated by the sensitivity of the dynamics themselves.
  Conventional engineering *signs* the message; here the message **cannot be constructed at all**
  without the secret. ⚠️ This synergy — not the health interpretation below — is the non-obvious
  teaching of the chaotic layer, and it is placed on the public record here for the first time.

---

## 2. Disclosed system (description, not claims)

A self-powered device for *in-situ* monitoring of the physiological state of living woody tissue,
comprising:

- **(a) a porous metal anchor** of additively manufactured titanium alloy (Ti-6Al-4V) with a **gyroid**
  (TPMS) architecture, for implantation into the xylem of a living tree, wherein the gyroid
  **simultaneously** (i) admits xylem sap into the porous volume, (ii) provides a stiffness gradient
  isoelastic with living wood, and (iii) constitutes the metal↔xylem interface electrode (≈65% porosity;
  unit-cell axis parallel to sap flow);
- **(b) an enzymatic biofuel cell (EBFC)** at that interface: an anode carrying an immobilised
  flavin-dependent oxidoreductase (deglycosylated FAD-dependent glucose dehydrogenase, dgrFAD-GDH) that
  oxidises xylem glucose via a redox mediator (an osmium bis-bipyridyl polyvinylimidazole complex in a
  genipin-crosslinked chitosan/cellulose-nanocrystal matrix); and an oxygen-reduction cathode (laccase, or
  a trimetallic Cu-Co-Ce zeolitic-imidazolate-framework nanozyme operating by direct electron transfer);
- **(c) an energy store** (supercapacitor) charged by the EBFC and powering the electronics;
- **(d) a compute node** that derives a health signal **from the charge dynamics of that energy store
  itself** — so that the EBFC **simultaneously** powers the device and serves as its sensor, with no
  separate measurement transducer;

wherein the **time `delta_t`** required by the EBFC to charge the energy store across a defined voltage
window is treated as the **primary physiological indicator**, from which physiological state is derived by a
**direct monotonic mapping** of that interval; and wherein a series of such intervals, together with
temperature and acoustic emission, parameterises a **deterministic Lorenz attractor** whose role in the
reference implementation is the **integrity seal of SYNERGY C** (dual independent recomputation), and
not the health classifier. ⚠️ **Truthfulness note, added 2026-09-05:** an earlier revision stated that
health state is *classified from* those chaotic dynamics. The implementation was measured and that
interpretation withdrawn — the transform is a deterministic function of inputs the verifier already
holds, so by the data-processing inequality it adds no predictive information about physiology beyond
them. The chaotic-classification variant **remains disclosed** here, so that it stays unpatentable by
others; it is simply **not asserted as validated, and not practised**
([`03_04`](../../03_04_mruby_Lorenz_Attractor.md)).

**Extensions.** A LoRa mesh in which every node is powered **solely by its own EBFC**; classifications
committed to a distributed ledger as the verification layer of a measurement-reporting-verification
system; and zonal protective coating applied to surfaces **other than** the enzyme-bearing gyroid wall, so
as not to passivate the EBFC interface.

---

## 3. Disclosed method (description)

A method of monitoring the health of a living tree: implanting into its xylem a porous gyroid titanium
alloy anchor that **simultaneously** integrates with sap flow, matches the elastic response of the wood,
and forms the metal↔xylem electrode of an enzymatic biofuel cell; generating electrical energy from xylem
glucose at that cell; storing that energy in an energy store; and deriving a health signal **from the
charge-time dynamics of that same cell** — such that a single enzymatic biofuel cell both powers the
monitoring and constitutes its sensor, with zero instrumental noise.

---

## 4. Enablement and incorporation by reference

This document discloses the **combination**. The quantitative and procedural detail that makes it
reproducible by a person skilled in the art — enzyme loading and immobilisation protocol, mediator
synthesis, gyroid wall parameter and unit-cell period, the defined charge voltage window, energy-store
capacitance, and the Lorenz parameterisation and thresholds — is **published in the same public
repository, on and since the dates above**, and is incorporated here by reference:

| Referenced disclosure | Supplies |
|---|---|
| [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | EBFC chemistry: enzyme, mediator, matrix, membrane, cathode |
| [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | Gyroid geometry, porosity, zonal architecture |
| [`03_04`](../../03_04_mruby_Lorenz_Attractor.md) | Chaotic classification of `delta_t` (Lorenz parameterisation) |
| [`02_03`](../../02_03_BQ25570_MPPT_Nano_Power.md) | Energy-store charging path and voltage window |

Those documents are part of the same dated, publicly accessible repository; together with this disclosure
they constitute an enabling publication of the combination described in §2 and §3.

---

## 5. Publication anchors

- **Technical Disclosure Commons** — a no-fee defensive-publication venue whose records are indexed and
  consulted by patent offices.
- **The public SilkenNet git repository** — this file, with a verifiable commit date.
- **A peer-reviewed article** (Article 1, [`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md)) —
  peer-reviewed prior art for the mechanism.

Together these create **citable prior art** for the combination disclosed above, which should prevent a
third party from obtaining *valid* claims over it and keep it free for use in forest-health monitoring.
Stated precisely, and deliberately not more strongly than is true: prior art does not make patenting
impossible — an application may still issue if the art is never retrieved, and defeating it then requires
opposition or invalidation. That is exactly why the venue, the English text and the indexed commit date
matter, and why the anti-capture search remains a separate open task
([`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3).

**Non-assertion.** SilkenNet files no patents on this technology; should any ever be obtained
defensively, an irrevocable non-assertion pledge applies to all good-faith users — see `/NOTICE` and
[`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md).

---

## 6. Cross-references

| Resource | Role |
|---|---|
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | **owner** of the IP posture (defensive-publication-first, licences, pledge) |
| [`prior_art_landscape.md`](prior_art_landscape.md) | novelty landscape and anti-capture (FTO-lite) scan plan |
| [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | EBFC / gyroid technical canon |
| [`03_04`](../../03_04_mruby_Lorenz_Attractor.md) | chaotic classification of `delta_t` (Lorenz) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | state: UNI.3 (disclosure execution), UNI.15 (trademark timing) |
