# L1 — Архітектура білка (in silico, Gen 2.0 EBFC анод)

> **Рівень in-silico pipeline:** L1 з 4-рівневого Zero-Lab стеку ([`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
> **Канонічна папка хімічних артефактів:** `docs/protocols/ebfc/in_silico/`.

---

## Статус

**L1 Validation Status: ✅ Passed (2026-05-24)**

| Метрика | Значення | Джерело |
|---|---|---|
| Вихідний фермент | FAD-dependent glucose dehydrogenase (GcGDH) | *Glomerella cingulata* |
| UniProt ID | **G8E4B5** | https://www.uniprot.org/uniprotkb/G8E4B5/entry |
| Довжина амінокислотного ланцюга | **600 aa** | UniProt fasta |
| Деглікозильовано сайтів N-glycosylation | **11** | `deglycosylate.rb` (sliding window N-X-S/T, X ≠ P) |
| Позиції мутацій N → Q | **N71, N100, N192, N200, N249, N258, N271, N355, N380, N405, N463** | Output скрипту |
| 3D фолдинг | AlphaFold 3 Server, з нативним кофактором FAD | DeepMind |
| Глибина FAD-N5 → поверхня білка (Tyr90 OH) | **15.998 Å** | UCSF ChimeraX `distance` command |

---

## 1. Вихідні дані

- **Білок:** FAD-залежна глюкозо-дегідрогеназа з *Glomerella cingulata* (синонім: *Colletotrichum gloeosporioides*).
- **UniProt accession:** [`G8E4B5`](https://www.uniprot.org/uniprotkb/G8E4B5/entry) — 600 aa, expressed natively as a heavily N-glycosylated secreted glycoprotein.
- **Чому саме G8E4B5:** baseline-кандидат у Gen 2.0 архітектурі — кисень-незалежний (без H₂O₂), FAD-кофактор узгоджується з осмієвим редокс-полімером, доступний для рекомбінантної експресії у *Pichia pastoris* (див. [`01_03 §1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

## 2. Аглікозильований мутант (N→Q design, НЕ модель PNGase F)

> ⚠️ **Термінологічна точність (виправлено):** N→Q — це **раціональний дизайн аглікозильованого мутанта**, а **не** in-silico імітація PNGase F. Це різні хімічні шляхи:
> - **PNGase F** (ензимна обробка wild-type) відрізає глікан *і деамідує* Asn → **аспарагінову кислоту (Asp, D)** → додає негативний заряд на поверхню, зсуває локальну pI. Модель цього шляху мала б мати мутації **N→D**.
> - **N→Q (наш шлях)** зберігає нейтральний заряд (Gln ізостеричний до Asn без -NH₂ для glycan attachment) і вбудовується **прямо в синтетичний ген (dgr-mutant)** → *Pichia* фізично не глікозилює ці сайти → PNGase F у лабораторії **взагалі не потрібен** ([`01_03 §3.7`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
>
> Ми свідомо обрали N→Q (aglycosylated mutant) як чистіший виробничий маршрут. Фолдинг мутанта (§3) також підтверджує, що самі 11 точкових замін не дестабілізують глобулу/активний центр.

Програмно мутуються канонічні **N-X-S/T sequons** (X ≠ P): Asparagine (N) → Glutamine (Q).

**Скрипт:** [`deglycosylate.rb`](deglycosylate.rb) — sliding window O(n), 3-residue triplets (детектує sequons; назва історична).

**Знайдені та мутовані сайти (11 шт.):**

| # | Позиція | Sequon | Мутація |
|---|---|---|---|
| 1 | N71 | NVT | NVT → QVT |
| 2 | N100 | NAS | NAS → QAS |
| 3 | N192 | NDS | NDS → QDS |
| 4 | N200 | NAT | NAT → QAT |
| 5 | N249 | NRT | NRT → QRT |
| 6 | N258 | NTT | NTT → QTT |
| 7 | N271 | NGT | NGT → QGT |
| 8 | N355 | NFT | NFT → QFT |
| 9 | N380 | NES | NES → QES |
| 10 | N405 | NVT | NVT → QVT |
| 11 | N463 | NST | NST → QST |

**Інваріант:** довжина = 600 aa (без змін; N → Q — point mutation).

**In-silico follow-ups on the deglyc mutant (verified 2026-06-06; both tracked → [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.5.IS):**
- **Aggregation (CHEM.11 — computed 2026-09-17, script [`69_chem11_aggregation_compensation.py`](../../../../tools/in_silico/scripts/69_chem11_aggregation_compensation.py) → `cache/chemistry/chem11_aggregation_compensation.json`; numbers → [`SUMMARY.md`](SUMMARY.md) §CHEM.11):** the 11 removed glycans expose hydrophobic surface. ⚠️ **The proxy this line used to cite did not exist in the tree** — the 2026-06-06 commit canonised the four-site conclusion and committed neither script nor cache, so a freeze-gating claim stood on prose. Script 69 is that instrument: exposed apolar (side-chain C/S) SASA carried by Kyte-Doolittle-positive **+ aromatic** side chains inside a **7 Å contact shell** re-selects **Gln71 · Gln200 · Gln258 · Gln405** exactly — but only at 6.5–7.5 Å, and **never** without the aromatics, so the four is one definition's answer rather than a definition-free fact. 🔴 Read against the protein's OWN surface these are **not** its worst patches, so "hotspot" ranks the 11 deglycosylation sites, not absolute risk.
  **Admissible compensation — three positions, ALL THREE TAKEN:** `Leu80 → Asp` and `Ala70 → Ser` (⚖️ founder 2026-09-17), `Ile401 → Ser` (⚖️ founder 2026-09-18, after the hold's own question was measured — see the conservation block below). Leu80 was a tie inside the measured noise floor (−78.4 Å² either way) and the discriminator was charge: a negative surface charge is the stronger anti-aggregation lever and is electrostatically complementary to the cationic Os-PVI mediator we wire with. ⚠️ The combined variant was BUILT with `LEU80SER` (a tie is built as the neutral option), so the measured «Gln71 140.1 → 2.9 Å²» belongs to the Ser build; the Asp build was not measured. Two of the three sit on the Gln71 patch; `Ile401` is the ONLY compensation of `Gln405`, which is why lifting its hold mattered — without it that patch stays at 119.8 Å² with no lever at all.
  🔬 **Conservation of position 401 — MEASURED 2026-09-18, and it is what lifted the hold** (332 homologs from 98 genera after 90 % de-duplication, four sources): **Ile 3.6 % · Ser 15.7 %** — Ser is four times more frequent than the residue we would replace; in the reliably-anchored subset (local window identity ≥ 40 %, n = 103) it is **Ser 39.8 % vs Ile 6.8 %**. Positive control on the same instrument: the catalytic **His537 reads 98.8 %** (100 % anchored, zero Ser), so the method does separate an invariant position from a variable one. Ile401 is **clade-local**: Ser occupies it in seven well-anchored species of our own genus *Colletotrichum* (an eighth, *C. kahawae*, carries Ser at only 31.8 % identity and fails the anchor rule) and in *Gnomoniopsis smithogilvyi* (75.9 % identity, the **fifth**-closest homolog — «fourth» here was off by one and the instrument corrected it). ⚠️ **And the instrument added the qualification the hold's answer did not carry: the four homologs CLOSER than that all keep Ile** — *C. gloeosporioides* `G8E4B4` (99.8 %) and three *Cytospora* spp. (79.0–81.3 %), each at a strong local anchor (90 %). So «variable» is a statement about the family, not about the immediate neighbourhood: our nearest relatives keep the residue we are replacing, and the Ser carriers sit one step further out (*Gnomoniopsis* 75.9 % · the *Colletotrichum* set at ≈ 62–64 %). Calibration against the two positions already ratified: 401 (3.6 %) is LESS conserved than Ala70 (14.2 %) and Leu80 (41.9 %), and `Leu80 → Asp` places a residue whose natural frequency at its own position is 0.6 % against 15.7 % here. Structurally the site is half-exposed and the remotest of the three compensations from the chemistry — and these numbers are quoted from their IN-TREE owner, script 69's cache, with its definitions: burial **0.503** (1 − context SASA ÷ isolated side-chain SASA), **29.3 Å** from FAD and **27.9 Å** from the tunnelling path (side-chain centroid to nearest cofactor atom / to the path), against Leu80's 12.1 Å and Ala70's 17.4 Å; and **5.75 Å** centroid-to-centroid from Gln405, i.e. inside the 7 Å contact shell that defines the patch it compensates. ⚠️ The reading this sentence carried until 2026-09-18 («60 % relative SASA · 26.5 Å · 3.48 Å») was not wrong and not owned: it came from a scratchpad script that never entered the tree and used different definitions (Tien-normalised SASA, minimum heavy-atom distances). Same class as the conservation numbers themselves — a quantity with no measurer in the tree cannot be pinned, so it is quoted from the owner or not at all. ✅ **The instrument is in the tree** (`tools/in_silico/scripts/70_chem11_site_conservation.py`, committed inputs + provenance in `tools/in_silico/data/chem11_conservation/`, cache `chemistry/chem11_site_conservation.json`, every number above pinned doc↔cache): the pool, the quality filter and the 90 % de-duplication re-run from the source FASTAs, and the script **exits** rather than count if the query is not 600 aa or a position does not carry its wild-type residue. ⚠️ **Ceiling, and it did not go away with the port:** the main table is still OUR query-anchored aligner, and the 398–406 stretch is indel-rich — the external Clustal Omega run puts **61.9 % gaps** in that column. Measured against that external MSA on the *same* 84 accessions, the two aligners agree per sequence on **33.3 %** raw, **71.8 %** once the cells where the external alignment places no residue at all are excluded (45 of 84 are exactly that); 9 cells carry a residue in both and differ. The reading also survives the gap-penalty sweep in direction (Ser 15.7–17.5 % against the query residue's 3.6–5.1 %). One of the eight Ser-carrying homologs has an independent PAIRWISE alignment in the tree (EMBOSS Needle, *C. incanum*) and it agrees residue-for-residue; the other seven are this aligner's reading only. Frequency is not consequence: none of this says what the swap does to folding, activity or yield.
  ⛔ **The AF3 input sequence below is NOT rewritten by these three substitutions, and that is deliberate:** it is the exact string the shipped model, the MD runs and every SASA number stand on. The gene ordered from the CRO carries `11 N→Q + L80D + A70S + I401S` ([`ebfc_chem_rfq`](../../procurement/ebfc_chem_rfq.md) Spec A); re-predicting the structure on the compensated sequence is a separate run with its own provenance, not an edit to this block. (Asp is refused in regular secondary structure by a declared heuristic, Ser is not.) ⛔ **Gln258 and Gln200 get none.** Gln258's entire apolar neighbourhood lies in the FAD pocket / electron-exit shell — the site itself sits **8.0 Å from the tunnelling path and 11.0 Å from FAD** (§5) — so aggregation margin there is bought with the MET architecture. Gln200 is the **most buried of the 11** (burial 0.847) and its neighbours are buried too; ⚖️ but its refusal is our **burial ceiling's**, not the measurement's — the cache prices in Å² what each declared threshold refuses, and the thresholds were left where they were declared.
  **Ceiling of the method:** an exposed-apolar patch is a static single-molecule descriptor, **not** an aggregation prediction (no rate, no solubility, no critical concentration); **Aggrescan3D was NOT run** — an external web server — so that half of the recipe stays OPEN; no sequence conservation INSIDE this proxy (that axis is measured separately — script 70, the block above — and it is not an input to the patch score), no MD of any mutant, no ΔΔG of folding; and the reference state is the **aglycosylated** mutant, so what the glycans were shielding is not measured. Single-molecule L2 MD (§3) still cannot see colloidal aggregation. The final choice of mutations is the founder's presumption — this is its evidence base, not a verdict.
- **Genipin-shield (CHEM.10):** the layer-4 genipin cross-links Lys ε-NH₂; **Lys109 (6.9 Å from Tyr90) + Lys262 (7.4 Å from THR288)** sit at the electron exit (§5) → mutate **Lys109/Lys262 → Arg** (conservative; guanidinium ≈ inert to genipin) so a genipin knot cannot block Os-mediator docking.

**Мутована послідовність (input для AlphaFold 3):**

```
MKNLIPLSLLATTVAARPGSAPRDQAAATAYDYIVIGGGTSGLVVANRLSEDASVSVLVIEAGDSVLNNAQVTNANGYGLAFGTDIDYAYQTTAQTYANQASTTLRAAKALGGTSTINGMAYTRAEASQIDAWETVGNEGWNWDALLPYYLKSETFQAPDAERSIKGHISYESDVHGHDGPLYTAYAYGSTQDSYPTSLQATYQALNVPWKEDIAGGSMVGFASYPKTLNQDLNIRWDAARAYYFPYEQRTNLKVVLQTTAKKLTWASATQGTDATASGVEITAADGTTSVVTANKEVIISAGALVSPLLLELSGVGNPAWLSQYGIETVVELPTVGENLQDQINNELIYSPPTQFTSTYDSGVGAFVAYPSASHVFGTQESSASEELKSQLTAYADTVAIANGQVTKASDLLDFFQLQYDLIFKDQVPFAEVLIYIAKGSWGAEYWGLLPFSRGSIHISQAQSTAGALINPNYFMLDYDVELQVATAKFIRSVFGTGPFASVAGTETTPGFDVIPADADEATWKSWATKEYRSNFHPVATAAMLPKEKGGVVDAQLKVYGTTNVRVVDASVLPFQVCGHLVSTLYAVAEKASDLIKAAA
```

## 3. 3D-фолдинг (AlphaFold 3)

- **Інструмент:** AlphaFold 3 Server (DeepMind, registration-gated).
- **Job ID:** `fold_dgrgcgdh_fad_v1` (job spec — [`alphafold3/fold_dgrgcgdh_fad_v1_job_request.json`](alphafold3/fold_dgrgcgdh_fad_v1_job_request.json)).
- **Вхід:** мутована амінокислотна послідовність (600 aa) + **FAD** (CCD entry) як native cofactor у multi-entity input. Seed: `1390281012`, `useStructureTemplate: true`.
- **Вихід (5 ranked models):** mmCIF — [`alphafold3/fold_dgrgcgdh_fad_v1_model_{0..4}.cif`](alphafold3/). Top-ranked **model_0** конвертовано в PDB як канонічний артефакт: [`dgrGcGDH_AF3.pdb`](dgrGcGDH_AF3.pdb) (2 chains, 601 residues, 4584 atoms; chain A = протеїн, chain B = FAD).

**AF3 confidence metrics (model_0, top-ranked):**

| Metric | Value | Interpretation |
|---|---|---|
| **ranking_score** | **1.00** | Top-1 серед 5 моделей |
| **ipTM** (interface predicted TM) | **0.99** | Protein↔FAD interface майже ідеально передбачений |
| **pTM** (predicted TM-score) | **0.93** | Глобальний fold — high-confidence |
| **chain_pTM (protein)** | 0.92 | Глобуля протеїну стабільна |
| **chain_pTM (FAD)** | 0.84 | Ліганд orientation — high-confidence |
| **fraction_disordered** | 0.04 | 4% дисордерованих ділянок (терміни/loops) |
| **has_clash** | 0.0 | Стеричних конфліктів немає |
| **num_recycles** | 10 | Повний recycling cycle |

> Bulk intermediates (msas 49MB, full_data_*.json 17.5MB, templates) **не комітимо** — regenerable з `job_request.json` за допомогою AlphaFold 3 Server.

## 4. Вимірювання глибини залягання FAD (UCSF ChimeraX)

**Реактивний атом:** N5 на ізоалоксазинному (флавіновому) кільці FAD — точка переносу електрона у redox-циклі FAD → FADH₂.

**Референтна точка на поверхні білка:** атом OH тирозину **Tyr90** — найближча до проєкції N5 поверхнева sidechain.

**ChimeraX:**
```
distance #1:FAD@N5 #1:90@OH
```

**Результат:** **d(N5 → Tyr90 OH) = 15.998 Å** (Евклідова відстань — геометричний показник *глибини залягання* FAD, тобто мінімальної товщини Os-шару; це **не** маршрут тунелювання — див. §5).

**Локальна впевненість точки виходу електрона (виправлення SSOT-рецензії):** глобальні pTM/fraction_disordered не гарантують жорсткість конкретного якірного залишку. Витягнуто per-residue pLDDT з AF3 CIF (B-factor колонка):

| Залишок | pLDDT | Інтерпретація |
|---|---|---|
| **Tyr90 (точка виходу для d_FAD)** | **98.71** | Дуже жорсткий (≫ 80) → координати надійні, **не** гнучка петля → 15.998 Å стабільна |
| **THR288 (tunneling exit, script 28)** | **95.57** | Жорсткий (≫ 80). ✅ Розв'язано (#3): script 28 рапортував 0-based MDTraj index («THR287»), що = PDB **resSeq 288** (THR); тепер емітить resSeq. Весь шлях жорсткий: ALA261=98.53, THR260=98.12, THR283=97.22, THR288=95.57 |

## 5. Фізичне обґрунтування MET (Mediated Electron Transfer)

Осмієвий редокс-полімер **[Os(4,4'-dimethyl-2,2'-bipyridine)₂(poly-vinylimidazole)Cl]⁺/²⁺** (потенціал E° = +309 мВ vs NHE, Zafar 2012) формує тривимірну redox-сітку на поверхні fMWCNT. Електрон з FAD-центру тунелює до Os-центру через білкову матрицю.

**Критерій життєздатності MET (теорія Маркуса):**

| Параметр | Значення | Інтерпретація |
|---|---|---|
| Глибина залягання N5 (Евклід) | **15.998 Å** | Геометричний bound — товщина Os-шару, НЕ маршрут тунелювання |
| Радіус ефективного quantum tunneling для Os-polymer | ≈ 18–20 Å | Літературна межа для bipyridyl-Os mediators |
| **Through-bond tunneling pathway (script 28, Beratan-Onuchic)** | **FAD→…→THR288, β·d = 2.05** | **Справжній доказ MET** — граф ковалентних/H-зв'язків, не пряма лінія |
| Жорсткість точки виходу (Tyr90 pLDDT) | **98.71** | Не гнучка петля → відстань не «стрибає» 15→25 Å |
| Необхідність руйнування глобули | **Ні** | Os-центри підходять через native conformation |
| Необхідність проміжних медіаторів | **Ні** | One-step MET достатній |
| k_et (intermolecular ET rate, FAD→Os) | експоненційно росте при d ↓ | Marcus: k ∝ exp(−β·d), β ≈ 1.1 Å⁻¹ |

> 📐 **Чому два показники, а не один (виправлення рецензії):** Електрон не тунелює по прямій Евклідовій лінії — він іде мережею ковалентних/H-зв'язків. Тому **кінетичний доказ MET — це through-bond pathway зі Script 28** (β·d = 2.05, [`L3_quantum_chemistry.md`](L3_quantum_chemistry.md)), а 15.998 Å — лише геометричний показник глибини залягання FAD (визначає товщину Os-шару). Обидва підтверджують feasibility, але роль у них різна.
>
> 🔤 **Термінологія:** FAD→Os — це **intermolecular** перенос (k_et / k_ex), а **не** гетерогенний k_s. k_s описує крок Os→електрод (молекула↔тверде тіло). Раніше тут було помилково «k_s».

**Висновок:** Through-bond tunneling pathway (β·d = 2.05, script 28) + жорстка точка виходу (Tyr90 pLDDT 98.71) + глибина залягання 15.998 Å ≪ 18-20 Å межі **разом доводять життєздатність MET архітектури Gen 2.0** — без руйнування глобули, без проміжних медіаторів.

## 6. TRL-гейт L1 → L2

| Критерій | Статус |
|---|---|
| Послідовність валідована проти UniProt G8E4B5 | ✅ |
| Sequon-видалення детерміністичне та відтворюване | ✅ |
| AlphaFold 3 фолдинг з FAD-кофактором завершений | ✅ |
| Глибина FAD N5 → поверхня виміряна та зафіксована | ✅ **(15.998 Å)** |
| MET-feasibility математично обґрунтована | ✅ |

**Gate:** **L1 → L2** — ✅ пройдено. (L2 результати — канонічний [`SUMMARY.md`](SUMMARY.md) + [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md); тут не дублюємо, щоб не тримати застарілі RMSD — попередні значення 0.95/1.11 Å були отримані з неправильним ізомером геніпіну і замінені на 1.20/1.22 Å після перезапуску з коректним C₁₁.)

---

## 7. Артефакти у цій папці

**SSOT-артефакти (chemistry, ця папка):**

| Файл | Опис | Статус |
|---|---|---|
| `deglycosylate.rb` | Ruby sliding-window — детекція N-X-S/T sequons + N→Q (aglycosylated mutant) | ✅ |
| `L1_protein_architecture.md` | Цей документ | ✅ |
| `dgrGcGDH_AF3.pdb` | Канонічний PDB (aglycosylated GcGDH + FAD), конвертовано з `alphafold3/…_model_0.cif` | ✅ |
| `alphafold3/` | AF3 raw output: 5 ranked CIF моделей + summaries + job_request + terms_of_use | ✅ |
| `ligands/FAD.sdf`, `ligands/genipin.sdf` | Reference structures (вхід для L2) | ✅ |
| `chimerax_distance_session.cxs` | ChimeraX session з вимірюванням 15.998 Å | ⏳ Опційно |

> 🟢 **Робочі скрипти L2+ та їх статус — НЕ дублюються тут** (SSOT-політика). Канонічні джерела: опис → [`tools/in_silico/README.md`](../../../../tools/in_silico/README.md); статус виконання + dependency graph → [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md); результати/числа → [`SUMMARY.md`](SUMMARY.md). Параметризаційний кеш: `tools/in_silico/cache/gaff_cache.json`.

> **L1 → L2 inженерний міст:** AMBER ff14SB має шаблони лише для 20 стандартних амінокислот → щоб запустити MD з FAD (кофактор) і геніпіном (зшивач матриці), потрібен окремий ligand-parameterization крок. Він реалізований через `openmmforcefields.GAFFTemplateGenerator` поверх AmberTools `antechamber`/`sqm`. Деталі — `docs/01_03 §3.4 Інженерний нюанс L2`.

---

## 8. Cross-references

- Архітектура Gen 2.0 EBFC анода → [`01_03 §1 Анод`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- 4-рівневий in-silico pipeline → [`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- TRL-гейт біохімії → [`01_03 §3.5`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- Action Plan tracker → [`00_07`](../../../00_07_Action_Plan_Tracker.md)
- Joint Q1-publication scope → [`00_02 Стаття 1`](../../../00_02_Academic_Integration_and_IP.md)
- Майбутні R&D напрямки → [`01_03 §3.1, §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
