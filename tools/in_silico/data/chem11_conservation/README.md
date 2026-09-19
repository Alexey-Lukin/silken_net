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
- **One external pairwise alignment, not eight.** Canon names eight Ser-carrying homologs near
  our clade; only *C. incanum* has an independent pairwise alignment here. A second Needle job
  for *Gnomoniopsis smithogilvyi* (`emboss_needle-R20260918-070301-0914-9312139-p1m`) finished on
  the EBI side but its result was not retrievable from this network — drop the `.aln` in this
  directory and extend `external_pairwise` in the script when it is.
- **Nothing here is a conservation SCORE.** Frequencies over a selected set, with no phylogeny and
  no tree-aware weighting; the 90 % de-duplication is a crude bias correction, not a substitute
  for one.

## Re-running

```bash
~/miniforge3/envs/silken_md/bin/python tools/in_silico/scripts/70_chem11_site_conservation.py
```
~10 s, numpy only. The script **exits** if the query is not 600 aa or if any studied position does
not carry its expected wild-type residue — a numbering shift must never be readable as biology.
