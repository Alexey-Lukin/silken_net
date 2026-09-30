# Declarations — draft (Стаття 1)

> **Draft section** (self-review Gate 4, 2026-06-16). Standard journal declarations + the AI-use
> disclosure. **Venue-specific:** final wording and placement follow the target journal's policy
> (*J. Phys. Chem. B* / ACS); ethos = `00_01 §8` (publish-to-protect — transparency is the standard,
> not concealment). Items marked **[finalise]** need author input before submission.

## AI Use Disclosure

This study used artificial-intelligence tools, disclosed here for transparency:

- **Structure prediction.** The enzyme model was generated with **AlphaFold 3** (cited in Methods §2.1);
  predicted geometries were assessed by pLDDT and a molecular-dynamics ensemble before use.
- **Computational pipeline & analysis.** The DFT/MD pipeline was implemented with the assistance of an
  **LLM coding-agent**; every calculation is deterministic, run in a recorded version-exact environment, scripted, and
  reproducible from the Supporting Information, and all numerical results were verified against committed
  result caches.
- **Manuscript preparation.** An LLM assisted with drafting and editing. **All scientific content,
  interpretations, claims, and citations were reviewed, verified, and are the sole responsibility of the
  authors.** AI tools were not used to generate or fabricate data, results, or references.

## Other required declarations [finalise at submission]

- **Data Availability.** Scripts, golden reference outputs, and result caches provided as Supporting
  Information / repository (publish-to-protect, `00_01 §8`); the SI itself is the generated manifest
  [`10_supporting_information.md`](10_supporting_information.md) (script 72 — sha256 of every committed
  file it lists). [finalise — repository DOI]
- **Competing Interests.** Draft (2026-09-30, from `00_01 §8` + `/NOTICE`; the cover letter carries the
  same position — [finalise: founder confirms the standard wording]): *The author is the founder of the
  SilkenNet project, an open-hardware forest-monitoring platform of which the biofuel cell studied here
  is a component and which is intended for commercial deployment. No patent has been or will be filed on
  the work disclosed here (defensive-publication posture); the code, hardware design and documentation are
  released under open licenses (AGPL-3.0-or-later, CERN-OHL-S-2.0, CC-BY-SA-4.0). The author declares no
  other competing financial or non-financial interests.*
- **Funding.** Draft (2026-09-30 — [finalise: founder confirms; add a grant number only if one exists by
  submission]): *This research received no specific grant from any funding agency in the public,
  commercial, or not-for-profit sectors. Computations were performed on the author's own workstation.*
- **Author Contributions (CRediT).** Draft (2026-09-30, from [`00_OUTLINE.md`](00_OUTLINE.md) §0 —
  [finalise: author list and corresponding author are the founder's call, ⚖️ `00_07` HW.5.IS; roles below
  are the outline's, not an addition]): *Conceptualization, Methodology, Software, Investigation, Data
  curation, Validation, Visualization, Writing – original draft, Writing – review & editing: the author.*
  No external collaborator and no pre-submission QM/MM section (founder 2026-09-23, `00_02 §2.1` Стаття 1):
  explicit-water QM/MM is a stated method limit. The AI-use disclosure above is part of this statement.
