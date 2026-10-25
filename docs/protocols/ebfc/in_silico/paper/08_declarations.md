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
  predicted geometries were assessed by pLDDT before use.
- **Computational pipeline & analysis.** The DFT/MD pipeline was written and run by an LLM coding agent — **Claude
  (Anthropic), used through Claude Code**; the agent transcribed literature values into the code and the reference index,
  drafted the manuscript text, ran both adversarial self-review rounds and made delegated analysis choices that the author
  ratified; the author set the questions, ruled on every choice and reviewed every claim. The model behind a change is recorded
  in the `Co-Authored-By` trailer of every commit but one that touches `tools/in_silico` or `docs/protocols/ebfc/in_silico/paper/` (609 of 610 at commit
  778207a99; re-counted at deposit). The reported calculations are scripted; every result cache
  outside `cache/reproduction/` was computed in one recorded version-exact environment (§2.7), and the records in that
  directory — the re-runs under the later conda-lock, the attribution of §2.7 and the chelate-closing sensitivity of
  §2.3, which ran under the lock — are named as such where they are reported; the molecular dynamics are not seeded and are stochastic. Many of the computed numbers in the
  text are pinned to the committed result caches by tests in the repository; not every number has such a pin.
- **Literature search and citations.** The literature search, the collection of references and the check of every
  DOI against its registry record (Crossref; DataCite for the one software DOI, ref 47) were carried out with the same agent
  (Claude, through Claude Code). [finalise — the author confirms that he checked the citations, and names any value
  taken from an abstract rather than a full text]
- **Manuscript preparation.** The same agent drafted the manuscript text and ran both self-review rounds; the author ruled
  on every choice and reviewed every claim, as stated above.
- **Other tools.** Google Gemini may also have been used outside the repository over the project's development;
  that use is not recorded. [finalise — the author confirms this sentence and states the method of use at deposit:
  ChemRxiv requires the name of every AI tool and how it was used (chemrxiv.org FAQ, read 2026-10-11); the author's
  own word, 2026-10-11: «може Gemini»]

**All scientific content,
  interpretations, claims, and citations were reviewed, verified, and are the sole responsibility of the
  author.** No number in this work was produced by a generative model: every number is the output of a scripted calculation
  or a literature value transcribed by the agent; the AlphaFold 3 structure model is the one exception, declared above.

## Other required declarations

> **Workshop notes — not printed.** Every item below waits for the author at submission (each carries its own
> `[finalise` marker, which the manuscript print refuses until it is answered); the notes in quotes like this one
> are the drafting record and the manuscript print strips them (`scripts/disclosure_pdf.rb`, manuscript mode).
> Moved out of the item text 2026-10-11, verbatim, so that answering a marker never prints a draft note.

- **Data Availability.** Scripts, golden reference outputs, and result caches provided as Supporting
  Information / repository; the SI itself is the generated manifest
  [`10_supporting_information.md`](10_supporting_information.md) (script 72 — sha256 of every committed
  file it lists). Superseded records stay in the caches and are not reported: an earlier cathode margin on a broken cluster
  geometry with an assumed λ = 0.7 eV, and the margins on the crude two-solution coupling (the cache `cathode_ket_lambda`
  keeps both scenarios beside the reported ones). The manuscript and its computations are developed openly in a public repository — the development tree of this preprint, whose history predates it. [finalise — repository DOI; in a later journal version also the ChemRxiv preprint DOI
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

> *Zenodo metadata — ready to paste at upload* (fields as the Zenodo deposit form and API name them — developers.zenodo.org
> «Deposit metadata» and help.zenodo.org «Describe records», read 2026-10-23; the licence IDs checked against
> zenodo.org/api/vocabularies/licenses the same day; the GitHub-tree convention read on a live GitHub-integrated record,
> ref 47's own, that day). The founder types these into the draft that holds the reserved DOI (step 1 of the recipe
> above); nothing here is printed in the manuscript.
> - **Resource type:** Software — the record is the archived tree (scripts, caches, manuscript sources, SI manifest),
>   not the preprint, which lives on ChemRxiv.
> - **Title:** `SilkenNet — development tree of the preprint "<paper title>" (snapshot <tag>)`, the paper title copied
>   at upload from its one home, the title line the manuscript print and the SI generator read (`scripts/disclosure_pdf.rb`,
>   script 72).
> - **Creators:** `Lukin, Oleksii` · affiliation `Independent researcher` (the authorship ruling the Author Contributions
>   note above cites) · ORCID: the founder's iD, the same one attached to the ChemRxiv account (not kept in the repository).
> - **Description** (paste, with the title and tag filled in): *Development tree of the preprint "<paper title>"
>   (ChemRxiv, CC BY 4.0), archived at tag <tag>: the scripted DFT/MD pipeline (tools/in_silico), its committed result
>   caches, the manuscript sources (docs/protocols/ebfc/in_silico/paper) and the generated Supporting Information
>   manifest (10_supporting_information.md — the SHA-256 of every file the manuscript's numbers come from), with the
>   recorded computational environment (environment.computed.explicit.txt; PySCF 2.11.0) and the maintained conda-lock.
>   The committed caches are the reported results; a re-run writes a new cache and is a new measurement. Licences by
>   zone (NOTICE at the root): code — GNU AGPL-3.0-or-later; Solidity contracts — MIT; hardware design sources —
>   CERN-OHL-S-2.0; documentation — CC BY-SA 4.0. Not under any of these: the AlphaFold 3 Server outputs
>   (docs/protocols/ebfc/in_silico/alphafold3/ and dgrGcGDH_AF3.pdb — AlphaFold Server Output Terms of Use,
>   non-commercial) and the Aggrescan3D output (tools/in_silico/data/chem11_a3d/ and every value quoted onward from
>   it — its own non-commercial licence); see NOTICE and THIRD_PARTY_NOTICES.*
> - **Licenses:** a mixed-licence upload, so declare all four standard ones (help.zenodo.org «Licenses», «Mixed license
>   uploads»): `agpl-3.0-or-later` · `mit` · `cern-ohl-s-2.0` · `cc-by-sa-4.0` — each an ID of Zenodo's vocabulary.
>   The two third-party exclusions are not licences we grant, so they stay in the description, not in this field.
> - **Version:** the tag name (for instance `article1-preprint-1`). **Publication date:** the day the record is
>   published. **Access right:** Open. **Funding:** none (the Funding declaration above). **Files:** the `git archive`
>   zip of step 6.
> - **Related works:** (a) `https://github.com/Alexey-Lukin/silken_net/tree/<tag>` — relation *Is supplement to*,
>   resource type Software, scheme URL — the form the GitHub–Zenodo integration itself writes; (b) the ChemRxiv
>   preprint DOI — relation *Is supplement to*, resource type Publication / Preprint — entered by editing the
>   published record once ChemRxiv assigns the DOI: a metadata edit of a published record needs no new version
>   (help.zenodo.org «Manage versions»: versioning is for changed FILES; title, creators, description «etc.» go through
>   Edit), while the files of a published record cannot change — which is why step 4 stands before the tag.
> - **Keywords:** enzymatic biofuel cell · FAD-dependent glucose dehydrogenase · osmium redox polymer · ZIF nanozyme ·
>   density functional theory · proton-coupled electron transfer · implicit solvation · reorganisation energy · Marcus
>   theory.
> - **Which DOI the manuscript cites:** the one reserved in step 1. Whether Zenodo also shows a second, record-level
>   DOI after publication is not stated on the reserve-DOI help page (read 2026-10-23) — Data Availability keeps the
>   reserved one.

- **Competing Interests.** *The author is the founder of the
  SilkenNet project, an open-hardware forest-monitoring platform of which the biofuel cell studied here
  is a candidate power source, whose utility token is currently accrued from the charge interval of that cell,
  and which is intended for commercial deployment. No patent has been or will be filed on
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

- **Author Contributions (CRediT).** *Conceptualization, Methodology, Investigation, Data curation, Validation,
  Visualization, Writing – review & editing: the author; Software, Writing – original draft: the agent under the author's
  direction.*
  The AI-use disclosure above is part of this statement.

> Author Contributions — draft (2026-09-30, from [`00_OUTLINE.md`](00_OUTLINE.md) §0; the
> author list is decided — one author, also the corresponding author, affiliation «Independent researcher»,
> ⚖️ founder 2026-10-03, [`00_02 §2.1`](../../../../00_02_Academic_Integration_and_IP.md); roles above are
> the outline's, not an addition).
> No external collaborator and no pre-submission QM/MM section (founder 2026-09-23, `00_02 §2.1` Стаття 1):
> explicit-water QM/MM is a stated method limit.
