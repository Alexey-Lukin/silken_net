# Declarations — draft (Стаття 1)

> **Draft section** (self-review Gate 4, 2026-06-16). Standard journal declarations + the AI-use
> disclosure. **Venue-specific:** final wording and placement follow the target journal's policy
> (*J. Phys. Chem. B* / ACS); ethos = `00_01 §8` (publish-to-protect — transparency is the standard,
> not concealment). Items marked **[finalise]** need author input before submission.
> ⊕ **Route (⚖️ founder 2026-10-03, [`00_02 §2.1`](../../../../00_02_Academic_Integration_and_IP.md)):** the publication is the
> ChemRxiv preprint (CC BY 4.0) with a Zenodo DOI, so these declarations travel with the preprint; the ACS-form
> specifics below wake only with the journal branch (its trigger — the same §2.1).

## AI Use Disclosure

This study used artificial-intelligence tools, disclosed here for transparency:

- **Structure prediction.** The enzyme model was generated with **AlphaFold 3** (cited in Methods §2.1);
  predicted geometries were assessed by pLDDT and a molecular-dynamics ensemble before use.
- **Computational pipeline & analysis.** The DFT/MD pipeline was implemented with the assistance of an
  LLM coding agent — **Claude (Anthropic), used through Claude Code**; the model behind a change is recorded in the
  `Co-Authored-By` trailer of nearly every commit in the repository; every calculation is deterministic, run in a recorded version-exact environment, scripted, and
  reproducible from the Supporting Information, and all numerical results were verified against committed
  result caches.
- **Manuscript preparation.** Claude (Anthropic, through Claude Code) assisted with drafting and editing.
- **Other tools.** Google Gemini may also have been used outside the repository over the project's development;
  that use is not recorded. [finalise — the author confirms this sentence and states the method of use at deposit:
  ChemRxiv requires the name of every AI tool and how it was used (chemrxiv.org FAQ, read 2026-10-11); the author's
  own word, 2026-10-11: «може Gemini»]

**All scientific content,
  interpretations, claims, and citations were reviewed, verified, and are the sole responsibility of the
  author.** AI tools were not used to generate or fabricate data, results, or references.

## Other required declarations

> **Workshop notes — not printed.** Every item below waits for the author at submission (each carries its own
> `[finalise` marker, which the manuscript print refuses until it is answered); the notes in quotes like this one
> are the drafting record and the manuscript print strips them (`scripts/disclosure_pdf.rb`, manuscript mode).
> Moved out of the item text 2026-10-11, verbatim, so that answering a marker never prints a draft note.

- **Data Availability.** Scripts, golden reference outputs, and result caches provided as Supporting
  Information / repository; the SI itself is the generated manifest
  [`10_supporting_information.md`](10_supporting_information.md) (script 72 — sha256 of every committed
  file it lists). The manuscript and its computations are developed openly in a public repository — the development tree of this preprint, whose history predates it. [finalise — repository DOI; in a later journal version also the ChemRxiv preprint DOI
  beside it — ⚖️ 2026-10-03]

> Data Availability — provenance: publish-to-protect, `00_01 §8`.
> *Snapshot recipe (prepared 2026-10-01; minting the DOI needs the founder's account, and the archive
> channel — e.g. Zenodo's GitHub-release integration — is his choice):* neither §2.7 nor the SI names a
> commit or a tag; the SI binds to the tree by the SHA-256 of every file it lists. So (1) re-render the SI
> LAST (script 72) and commit it; (2) tag THAT commit and cut the release from the tag; (3) archive the
> release and mint the DOI; (4) on a fresh checkout of the tag, `python -m pytest tools/in_silico/tests -q`
> must pass — `test_paper_si_matches_its_generator` re-renders the SI and compares it byte for byte, which
> proves the archived tree is the one the SI describes. A tag cut before the last SI render archives a tree
> the SI does not describe.

- **Competing Interests.** *The author is the founder of the
  SilkenNet project, an open-hardware forest-monitoring platform of which the biofuel cell studied here
  is a component and which is intended for commercial deployment. No patent has been or will be filed on
  the work disclosed here (defensive-publication posture); the code, hardware design and documentation are
  released under open licenses (AGPL-3.0-or-later, CERN-OHL-S-2.0, CC-BY-SA-4.0). The author declares no
  other competing financial or non-financial interests.* [finalise: founder confirms the standard wording]

> Competing Interests — draft (2026-09-30, from `00_01 §8` + `/NOTICE`; the cover letter carries the
> same position). For the journal branch: it goes into the ACS submission-form
> field, which is where *J. Phys. Chem. B* takes the statement and from which it is printed with the
> article — the ACS default sentence is printed only when nothing is declared and would not carry this
> position, so enter it explicitly; ACS Author Guidelines, Appendix 1, read 2026-10-01; the text is written for a
> single author — if co-authors are added, rewrite it for all authors and declare each co-author's interests.

- **Funding.** *This research received no specific grant from any funding agency in the public,
  commercial, or not-for-profit sectors. Computations were performed on the author's own workstation.*
  [finalise: founder confirms; add a grant number only if one exists by submission]

> Funding — draft (2026-09-30).

- **Author Contributions (CRediT).** *Conceptualization, Methodology, Software, Investigation, Data
  curation, Validation, Visualization, Writing – original draft, Writing – review & editing: the author.*
  The AI-use disclosure above is part of this statement.

> Author Contributions — draft (2026-09-30, from [`00_OUTLINE.md`](00_OUTLINE.md) §0; the
> author list is decided — one author, also the corresponding author, affiliation «Independent researcher»,
> ⚖️ founder 2026-10-03, [`00_02 §2.1`](../../../../00_02_Academic_Integration_and_IP.md); roles above are
> the outline's, not an addition).
> No external collaborator and no pre-submission QM/MM section (founder 2026-09-23, `00_02 §2.1` Стаття 1):
> explicit-water QM/MM is a stated method limit.
