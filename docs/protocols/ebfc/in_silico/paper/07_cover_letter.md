# Cover Letter — Стаття 1 (draft)

> 🟡 **DRAFT** · ✅ **no IP gate on submission** — defensive publication (`00_01 §8`; tracker `UNI.3`): the
> publication itself is the protection (prior art); no patent gate. What still stands between the draft and
> SUBMIT is the manuscript's own legs (`00_07` HW.5.IS), not this letter.
> ⏸ **DORMANT with the journal branch** (⚖️ founder 2026-10-03, [`00_02 §2.1`](../../../../00_02_Academic_Integration_and_IP.md)):
> the publication is the ChemRxiv preprint (CC BY 4.0) with a Zenodo DOI; a journal submission — and this letter —
> wakes only on its trigger (coin Stage 2 data, or a collaborator or funder that requires peer review).
> Target if it wakes: *J. Phys. Chem. B* (primary) · *PCCP* fallback · *Bioelectrochemistry* applied-backup.
> Voice/claims per [`00_OUTLINE.md §0`](00_OUTLINE.md) + [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md);
> numbers → [`SUMMARY.md`](../SUMMARY.md). Bracketed `[…]` = fill at submission.

---

[Date]

Dear Editor,

We wish to submit the enclosed manuscript, **"Computational Electron-Transfer Energetics in Component Models of a FAD–Osmium Enzymatic Biofuel Cell: Flavin PCET Potential, Osmium-Mediator Hammett Trends, ZIF-Cluster Direct Electron Transfer, and How Far an Affordable PCM-DFT Protocol Can Be Read,"** for
consideration as an Article in *The Journal of Physical Chemistry B*, Section [finalise: the letter must
name the Journal Part and Section (ACS Author Guidelines, Cover Letter) — the founder picks one **at the
moment of submission** (⚖️ founder 2026-10-01: the section is deliberately not fixed in this draft, because
the Part/Section list is the journal's and is copied from the live guidelines page when the letter goes);
the candidates as read on the guidelines page 2026-10-01 (copy the exact titles at submission): B1 Biophysical
and Biochemical Systems and Processes · B2 Biomaterials and Membranes · B3 Liquids; Chemical and Dynamical
Processes in Solution · B4 Soft Matter …].

Enzymatic biofuel cells (EBFCs) are a promising route to self-powered, long-lived biosensors, yet
their performance is governed by electron-transfer (ET) steps that the field has characterised almost
exclusively **experimentally and with macro-kinetic / reaction-diffusion models** — rarely at the
electronic-structure level. We address that gap with a first-principles account of component models of the ET
chain of a FAD-glucose-dehydrogenase / osmium-mediator / ZIF-nanozyme cell — the flavin couple, the osmium mediator and a Cu–Co node of the framework cathode — **together with a measurement of how far an affordable PCM-DFT protocol can be read** on this class of problem. The contribution is therefore **mechanistic and methodological — not a re-confirmation** of an
experimentally known device.

Four findings, each with its stated limit: (1) a thermodynamic proton reference makes the proton-coupled
FAD redox potential computable with implicit solvation — 65 mV from experiment at the screening level, ≈210 mV
more negative with relaxed geometries and zero-point energy — no level is a validation; (2) a Hammett trend for
the osmium mediator (slope −0.92 eV per σ unit per complex at B3LYP, four substituents, ≈0.23 eV per σ per substituent; ≈15 % shallower at ωB97X/def2-TZVP
over the shared points; its donor pairs move by up to 20.1 mV per substituent when both osmium oxidation states are relaxed) reproduces the sign of the measured substituent shifts in three series, overshoots on the acceptor side and is
consistent with the trade-off behind the empirical potential optimum, which it does not locate; (3) a two-state diabatised coupling with
reorganisation energies computed for Co, Ce and Ru (λ(Cu) cited) shows the Co–Cu–Ce-ZIF cathode direct electron transfer to be *rate-limiting* at the
computed Co reorganisation energy and to straddle enzymatic turnover only at an assumed literature value — a verdict
conditional on λ(Co) — with the low-λ-metal lever computed indicatively; and (4) the anode→mediator cascade, compared like for like (the two-electron, two-proton flavin couple against
each one-electron osmium couple on one SHE scale), is downhill in every osmium form at every level of the flavin
treatment at B3LYP/6-31G(d) — a direction that the ωB97X/def2-TZVP tier on both sides (single points, LANL2DZ on osmium) reverses for the device couple on
the relaxed electronic flavin level and that spin–orbit coupling on osmium, omitted here, reverses for the device
couple on one flavin level at the literature size for homoleptic [Os(bpy)₃] (and more cells at the larger shifts the same source computes for other ligand sets), while against the measured flavin the device couple keeps +69.8 mV at the [Os(bpy)₃] size and turns uphill past −320 mV, so the protocol does not determine the sign — while its magnitude is method-dependent and its near-exact agreements are named as cancellations, with
explicit-water QM/MM and spin–orbit coupling on osmium identified as the next steps toward the magnitude.

We believe the manuscript is well matched to *J. Phys. Chem. B*: it sits squarely at the intersection
of **enzyme/redox catalysis and computational electronic-structure methodology**, and extends the
journal's recent model-driven redox-mediator design literature. A distinguishing feature is
**reproducibility**: every computed number but the four ωB97X end points named in §2.2 is the output of an open-source script run in a
recorded, version-exact environment (committed with it; §2.7 states what a re-run under a newer PySCF moves, and §2.2 names the four ωB97X end-point values transcribed from run logs that are not deposited), and the full pipeline is provided for the reviewers.

This work is original, has not been published previously, and is not under consideration elsewhere.
Explicit-solvation QM/MM of the cascade, which the manuscript identifies as one step toward the cascade's magnitude,
is outside its scope and is stated as a limit of the method; spin–orbit coupling on osmium is not computed, and its
size computed for [Os(bpy)₃] in the literature, with the other rows of its table (other ligand sets) as the range, is set against every
cell.
The author is the founder of the SilkenNet project, an open-hardware forest-monitoring platform of which
the biofuel cell studied here is a candidate power source, whose utility token is currently accrued from the
charge interval of that cell, and which is intended for commercial deployment. No patent
has been or will be filed on the work disclosed here (defensive-publication posture); the code, hardware
design and documentation are released under open licenses (AGPL-3.0-or-later, CERN-OHL-S-2.0,
CC-BY-SA-4.0). The author declares no other competing financial or non-financial interests.
[finalise: founder confirms the standard wording — ONE text, identical to the Competing Interests draft in
`08_declarations.md`. ACS Author Guidelines for J. Phys. Chem. A/B/C, Appendix 1 «Conflict of Interest
Disclosure» (page last updated 2026-08-27; read 2026-10-01): the corresponding author enters the
statement in the SUBMISSION FORM on behalf of all authors, and it is published with the article; it is
not on the cover letter's must-include list. So the form is the binding place and must carry THIS text
explicitly — the ACS default printed when nothing is declared («The authors declare no competing financial
interest.») does not carry the founder position above; in the letter the paragraph is optional. The text is written for a
single author; if co-authors are added, rewrite it for all authors and declare each co-author's interests
before entering it in the form]

[finalise: the letter must say whether the manuscript has been posted in a preprint / electronic archive,
with the details (JPC Author Guidelines, Cover Letter: «Notification if the manuscript has been uploaded to an
electronic archive, with details»). What ACS allows — read 2026-10-02 on the JPC Author Guidelines «Prior
Publication Policy» (page last updated 2026-08-27) and the ACS «Prior Publication Policies» page: an initial draft
may sit on a PREPRINT SERVICE (ChemRxiv, bioRxiv, arXiv or the applicable discipline repository) and may be revised
until acceptance — note it here with a link and say how the manuscript changed since deposition; but «any content
that has been made publicly available ... in electronic format other than a preprint ... may jeopardize the
originality of the submission and may preclude consideration». The manuscript text and its results are already
public in the project repository (github.com/Alexey-Lukin/silken_net, docs/protocols/ebfc/in_silico/paper and the
in-silico summaries), and a project repository is not a preprint service — so this paragraph discloses it with the
URL and the tag or commit in every case, plus the preprint DOI and the Zenodo DOI. The preprint comes FIRST
(⚖️ founder 2026-10-03, 00_02 §2.1: ChemRxiv under CC BY 4.0 is the publication itself), so by the time this letter
is used it exists — name it and say how the manuscript changed since deposition. After acceptance the published version is NOT mirrored
into the repository: «the use of a repository for published versions of papers ... generally requires copyright
permission» (same Guidelines)]

We thank you for your consideration and look forward to the reviewers' comments.

Sincerely,
[The author — sole and corresponding author; affiliation «Independent researcher»]
[finalise at submission: full name · postal address · telephone · e-mail · an ACS account (ACS Author
Guidelines, Cover Letter). ACS also asks for a CURRENT INSTITUTION e-mail and a letter on the official
letterhead of the author's affiliation, which an independent researcher does not have — the price the
author verdict named (⚖️ founder 2026-10-03, 00_02 §2.1), resolved only if the journal branch wakes;
contacts filled in at submission, never kept in this repository]
