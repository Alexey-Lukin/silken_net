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
- **Aggregation (CHEM.11):** the 11 removed glycans expose hydrophobic surface — an in-house hydrophobic-SASA proxy flags **4 aggregation-prone sites (Gln71, Gln200, Gln258, Gln405)**. Before CRO expression: Aggrescan3D + compensating surface-polar mutations (Asp/Ser) near them. Single-molecule L2 MD (§3) cannot see colloidal aggregation, so this is *not* covered by the folding check.
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
