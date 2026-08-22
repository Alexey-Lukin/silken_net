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
  **LLM coding-agent**; every calculation is deterministic, version-pinned (conda-lock), scripted, and
  reproducible from the Supporting Information, and all numerical results were verified against committed
  result caches.
- **Manuscript preparation.** An LLM assisted with drafting and editing. **All scientific content,
  interpretations, claims, and citations were reviewed, verified, and are the sole responsibility of the
  authors.** AI tools were not used to generate or fabricate data, results, or references.

## Other required declarations [finalise at submission]

- **Data Availability.** Scripts, golden reference outputs, and result caches provided as Supporting
  Information / repository (publish-to-protect, `00_01 §8`). [finalise — repository DOI]
- **Competing Interests.** [finalise]
- **Funding.** [finalise — see funding-statement guidance]
- **Author Contributions (CRediT).** [finalise — Architect (Silken Net): in-silico baseline, drafting;
  external computational-electrochemistry collaborator (TBD): explicit-water QM/MM section, added pre-submission per `00_02 §2.1` Стаття 1]
