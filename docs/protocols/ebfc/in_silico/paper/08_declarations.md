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
  `Co-Authored-By` trailer of nearly every commit in the repository. Every calculation is scripted and was run in one
  recorded version-exact environment; the molecular dynamics are stochastic, and §2.7 states what a re-run under a newer
  PySCF reproduces and what it moves. Every number in the text is checked against the committed result caches by the
  repository's tests.
- **Literature search and citations.** The literature search, the collection of references and the check of every
  DOI against its Crossref record were carried out with the same agent (Claude, through Claude Code); a value is cited
  only after it was read in the cited source.
- **Manuscript preparation.** Claude (Anthropic, through Claude Code) assisted with drafting and editing.
- **Other tools.** Google Gemini may also have been used outside the repository over the project's development;
  that use is not recorded. [finalise — the author confirms this sentence and states the method of use at deposit:
  ChemRxiv requires the name of every AI tool and how it was used (chemrxiv.org FAQ, read 2026-10-11); the author's
  own word, 2026-10-11: «може Gemini»]

**All scientific content,
  interpretations, claims, and citations were reviewed, verified, and are the sole responsibility of the
  author.** Apart from the AlphaFold 3 structure model declared above, AI tools did not generate data or results, and
  every reference was checked against its DOI record.

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
> *Snapshot recipe.* ⚖️ The founder ratified the route on 2026-10-12 — a manual Zenodo upload with a reserved DOI
> (grounds, price and weakest link in `00_02 §2.1`). The order below, the verification before publication and
> the ⛔ on a GitHub Release are the machine's, added when the ruling was applied the same day. Neither §2.7 nor
> the SI names a commit or a tag: the SI binds to the tree by the SHA-256 of every file it lists, and the
> manuscript is printed from the tagged commit — so everything the manuscript prints, the DOI included, is
> final BEFORE the tag. (1) Open a new Zenodo upload draft and reserve its DOI («Get a DOI now!»); keep the
> draft until publication, since deleting it loses the DOI [founder's account]. (2) Answer EVERY `[finalise`
> marker of this file — the DOI in Data Availability, and the AI-use, Competing Interests and Funding items
> [founder's words]. (3) From a clean tree — 72 hashes the working-tree bytes of the tracked files, so a
> modified, uncommitted file would enter the SI as bytes the commit does not hold — re-render the SI LAST
> (script 72), commit and push. (4) Before any tag, on a fresh clone of that commit:
> `python -m pytest tools/in_silico/tests -q` passes (`test_paper_si_matches_its_generator` re-renders the SI
> and compares it byte for byte), and the manuscript prints and checks clean (`scripts/disclosure_pdf.rb`
> `render` and `check` with `--manuscript --byline …`). (5) Tag THAT commit with a plain tag outside `v*`
> (for instance `article1-preprint-1`) and push the tag; ⛔ cut NO GitHub Release from it — `release: published`
> starts Deploy · Production, the image mirror and the SBOM here (`06_07`), and a `v*` tag would also pass the
> production environment's ref policy. (6) `git archive --format=zip --prefix=<tag>/ -o <tag>.zip <tag>`,
> upload it to the same Zenodo draft and publish [founder's account]. A tag cut before the last SI render, or a
> publication before step 4, archives under the DOI a tree the SI or the manuscript does not describe.

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
