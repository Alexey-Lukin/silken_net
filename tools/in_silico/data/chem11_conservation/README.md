# CHEM.11 — committed inputs of the site-conservation instrument

These files are the **inputs** of `tools/in_silico/scripts/70_chem11_site_conservation.py`, and they
are committed for one reason: the numbers they produce decide a **gene that gets ordered**
(`I401S` in Spec A of [`ebfc_chem_rfq`](../../../procurement/ebfc_chem_rfq.md)). A re-fetch from
UniProt returns a *different* pool every month, so a re-runnable verdict needs the pool it was
computed on to sit in git — not a recipe for getting a similar one.

Canon home of the result: [`L1 §2`](../../../../docs/protocols/ebfc/in_silico/L1_protein_architecture.md)
(«Conservation of position 401»). Cache: `tools/in_silico/cache/chemistry/chem11_site_conservation.json`.

| File | What it is | Provenance |
|---|---|---|
| `query_G8E4B5.fasta` | the query: wild-type *Colletotrichum gloeosporioides* FAD-GDH, 600 aa | UniProt `G8E4B5` (`rest.uniprot.org/uniprotkb/G8E4B5.fasta`) |
| `homologs_blast.fasta` | 500 BLAST hits of that query | EBI NCBI BLAST (blastp) vs UniProtKB, job `ncbiblast-R20260918-062942-0303-97724679-p1m`, 2026-09-18 |
| `homologs_gmc_reviewed.fasta` | 32 **reviewed** GMC-family oxidoreductases (glucose oxidase, choline/glucose dehydrogenases …) | UniProtKB REST search, 2026-09-18 |
| `homologs_uniref50.fasta` | 36 members of the query's UniRef50 neighbourhood (`UniRef50_A0A1V6WJP6`, "glucose oxidase", leotiomyceta) | UniProt UniRef50 REST, 2026-09-18 |
| `homologs_genus_scan.fasta` | 46 Ascomycota FAD-GDH entries (genus-level scan incl. unreviewed) | UniProtKB REST search, 2026-09-18 |
| `external_msa_input.fasta` | the 85 accessions submitted to the external aligner (headers are bare accessions) | assembled in-session, 2026-09-18 |
| `external_msa_clustalo.fasta` | **external MSA** of those 85 — the independent reading of the 401 column | EBI Clustal Omega, job `clustalo-R20260918-064814-0951-10344109-p1m`, 2026-09-18 |
| `external_needle_A0A161YBC9.aln` | **external pairwise** alignment query ↔ *C. incanum* `A0A161YBC9` | EBI EMBOSS Needle, job `emboss_needle-R20260918-070304-0265-99399309-p2m`, 2026-09-18 (BLOSUM62, gap open 10.0, extend 0.5) |
| `external_needle_A0A9W8Z4G1.aln` | **external pairwise** alignment query ↔ *G. smithogilvyi* `A0A9W8Z4G1` | EBI EMBOSS Needle, job `emboss_needle-R20260918-070301-0914-9312139-p1m`, submitted 2026-09-18, **result retrieved 2026-09-21** (same parameters) |
| `external_needle_A0AAJ0ES17.aln` | **external pairwise** alignment query ↔ *C. godetiae* `A0AAJ0ES17` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114618-0460-66964301-p1m`, 2026-09-21 (same parameters) |
| `external_needle_A0A8H6N132.aln` | **external pairwise** alignment query ↔ *C. plurivorum* `A0A8H6N132` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114621-0111-15641806-p1m`, 2026-09-21 (same parameters) |
| `external_needle_A0A5Q4BTX3.aln` | **external pairwise** alignment query ↔ *C. shisoi* `A0A5Q4BTX3` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114623-0526-87193400-p1m`, 2026-09-21 (same parameters) |
| `external_needle_A0A066XAU2.aln` | **external pairwise** alignment query ↔ *C. sublineola* `A0A066XAU2` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114626-0222-73480118-p1m`, 2026-09-21 (same parameters) |
| `external_needle_A0AAD8PX48.aln` | **external pairwise** alignment query ↔ *C. navitas* `A0AAD8PX48` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114628-0618-77563113-p1m`, 2026-09-21 (same parameters) |
| `external_needle_A0A1G4ASF8.aln` | **external pairwise** alignment query ↔ *C. orchidophilum* `A0A1G4ASF8` | EBI EMBOSS Needle, job `emboss_needle-R20260921-114631-0683-23158585-p1m`, 2026-09-21 (same parameters) |

## ⚠️ What this provenance does NOT carry, named rather than implied

- **The exact REST query strings were not recorded.** The three UniProt sets were fetched by a
  read-only research agent that handed back the *results*; its own queries are not in any
  transcript. So the sets are inspectable and re-runnable **as committed**, and the recipe that
  produced them is not reproducible from the tree. The lesson is the general one for delegated
  data collection: the provenance of a fetched set is the QUERY, so it has to come back with the
  data or it is lost.
- **The 85-accession MSA subset is a CURATED sample.** Its selection rule was never recorded
  either; 82 of the 85 are in the de-duplicated set and they span the whole identity range
  (25.5–99.8 %), so it is not a top-N cut — but it is not a defined stratum. The script reports
  its reading beside our own reading *on those same accessions*, which is what makes the
  comparison a test of the two aligners rather than of two different sets.
- **Eight external pairwise alignments — the whole clade set, completed 2026-09-21.** Canon names
  eight Ser-carrying homologs near our clade; all eight now have an independent EMBOSS Needle
  alignment here, and **all eight read Ser at query position 401** (`8 of 8` in the cache verdict).
  The set is not hand-picked: it is the anchored Ser-carriers of the de-duplicated pool in our own
  clade — seven *Colletotrichum* plus *G. smithogilvyi* — and *C. kahawae* is outside it because it
  fails the anchor rule at 31.8 % identity, exactly as canon says.
  ⊕ **None of the eight sits in the curated 85-accession MSA subset** (`in_external_msa: false` on
  every entry), which is what makes each an INDEPENDENT reading rather than a re-look at the same
  cell — and therefore a real check on that subset's 61.9 % gap fraction.
  ⚠️ **Read the count from the data, not from this sentence:** the script reports `pairwise_n` and
  builds its verdict prose from the list, so a ninth alignment costs one row in `NEEDLE_JOBS`.
  🔑 **And one lesson worth more than the alignments:** the *G. smithogilvyi* job was recorded here
  as "not retrievable from this network" on 2026-09-18 — it had in fact FINISHED on the EBI side and
  stayed fetchable for days. The note was true about that session and read as true about the job.
  When a provenance line says something could not be fetched, re-probe before believing it.
- **Nothing here is a conservation SCORE.** Frequencies over a selected set, with no phylogeny and
  no tree-aware weighting; the 90 % de-duplication is a crude bias correction, not a substitute
  for one.

## Re-running

```bash
~/miniforge3/envs/silken_md/bin/python tools/in_silico/scripts/70_chem11_site_conservation.py
```
~10 s, numpy only. The script **exits** if the query is not 600 aa or if any studied position does
not carry its expected wild-type residue — a numbering shift must never be readable as biology.
