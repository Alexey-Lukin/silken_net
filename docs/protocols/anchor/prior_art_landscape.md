# Prior-Art Landscape — SilkenNet (novelty evidence + anti-capture scan)

> **Що це:** карта попереднього рівня техніки навколо SilkenNet. Під **defensive-publication** поставою
> ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) її мета **подвійна**: (a) **доказ новизни** для наукової статті ([`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md)); (b)
> **анти-захоплення FTO-lite** — підтвердити, що жодна третя сторона вже не тримає блокуючого патенту на
> ту саму синергію, тож наше відкрите використання безпечне. **Це НЕ patentability-пошук перед поданням
> заявки** (ми не подаємо — [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)).
> **Cross-ref:** [`defensive_disclosure.md`](defensive_disclosure.md) (що саме ми розкриваємо) ·
> [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) (постава) ·
> [`00_02 §4.1`](../../00_02_Academic_Integration_and_IP.md) (TISC може прогнати ці запити).

---

## Метод сканування

Шукати **широко**, full-text, у патентних базах (PATENTSCOPE / Espacenet / Google Patents) + NPL
(Scholar / Lens.org). Proximity `NEARn`, wildcard `*`, кожен OR-набір у дужках.
**Дві цілі — дві оптики:**
- **Новизна для статті:** жодне одне джерело не поєднує нашу комбінацію + дві синергії → це й
  підкреслює стаття. Кожен компонент окремо очікувано має prior art — це нормально.
- **Анти-захоплення:** чи немає **чинного патенту третьої сторони** на саму синергію (EBFC-as-sensor /
  gyroid-as-EBFC-electrode), що міг би заблокувати мережу. Якщо є — оцінити freedom-to-operate.

---

> ⏳ **СТАТУС: query-set написано, пошуки ще НЕ прогнані.** Таблиці hit-логу порожні, а висновок нижче сформульований **умовно** («очікуваний результат… якщо нема чинного блокуючого патенту»). Це **план FTO-перевірки**, а не її результат — не цитувати як «новизну підтверджено». Прогін + hit-лог = residual у [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3, і він має передувати публічному disclosure.

## Query Set 1 — Coaxial Gyroid Anchor (геометрія + матеріал)
```
("gyroid" OR "TPMS" OR "triply periodic minimal surface") NEAR15 ("titanium" OR "Ti-6Al-4V" OR "Ti alloy") AND (implant* OR anchor* OR scaffold*)
```
```
("gyroid" OR "TPMS" OR lattice*) NEAR15 (tree* OR plant* OR wood* OR xylem OR trunk*) AND (sensor* OR monitor* OR implant* OR IoT)
```
**CPC:** A01G 7/00, A01G 29/00 (рослини); A61L 27/06 (Ti-імпланти); B33Y 70/80/00 (адитивне).

## Query Set 2 — EBFC mediator chemistry
```
("enzymatic biofuel cell" OR "enzymatic fuel cell" OR "biofuel cell") NEAR20 (tree* OR plant* OR xylem OR sap)
```
```
(("flavin adenine dinucleotide" NEAR5 "glucose dehydrogenase") OR "FAD-GDH") AND (osmium OR "redox polymer" OR "redox mediator")
```
```
(laccase OR "bilirubin oxidase") NEAR15 (ZIF OR "zeolitic imidazolate" OR MOF OR nanozyme*) AND ("oxygen reduction" OR ORR OR cathode*)
```
**CPC:** G01N 27/327 (enzyme-біосенсори); H01M 8/16 (biofuel cells); C12N 9/04 (оксидоредуктази).
> 🔎 **Відомий prior art** (літ-скан): Os-медіація FAD-GDH established (Degani-Heller 1987→; Os-PVI window
> +15…+489 mV, Zafar 2012; тюнінг обвіозний через Lever E_L 1990); laccase/ZIF-катоди опубліковані (Cu/Zn-ZIF,
> Cu-ZIF-67). → це **очікувано** і **підкреслює**, що наша новизна — у синергії (EBFC = одночасно
> живлення *і* zero-noise сенсор), а не в хімії компонентів. Деталі — [`defensive_disclosure.md`](defensive_disclosure.md) §1.

## Query Set 3 — LoRa mesh + bio-powered forest monitoring
```
(LoRa OR LoRaWAN OR LPWAN) NEAR15 (forest* OR tree* OR vegetation) AND (monitor* OR sensor* OR IoT)
```
```
("self-powered" OR "energy harvest*" OR "biofuel cell") NEAR15 (sensor* OR node* OR wireless) AND (tree* OR plant* OR forest*)
```
```
("non-linear" OR nonlinear OR chaotic OR "strange attractor" OR "Lorenz" OR "dynamical system*") NEAR15 (sensor* OR monitor* OR diagnos*) AND (health OR status OR homeostasis OR anomaly)
```
```
("carbon credit*" OR "measurement, reporting and verification" OR "digital MRV" OR dMRV) AND (blockchain OR token* OR "distributed ledger") AND (forest* OR tree*)
```
> ⚠️ Не шукати голий "Lorenz attractor" (→0, хибне «чисте поле»); писати «measurement, reporting and
> verification» повністю (акронім MRV колізіонує).
**CPC:** G06Q 50/02 (agri-digital); H04W 84/18 (mesh); H02J 7/00, G16Y (harvesting/IoT).

## Query Set 4 — Self-healing coating + Query Set 5 — anti-biofouling zwitterionic membrane
```
("self-healing" OR "self-repair*") NEAR15 (coating* OR microcapsule*) AND (titanium OR "Ti-6Al-4V")
```
```
(zwitterion* OR sulfobetaine OR SBMA OR PSBMA) NEAR15 (Nafion OR "proton exchange membrane" OR PEM)
```
**CPC:** C09D 5/08 (anti-corr); A61L 27/34 (anti-foul); C08J 5/22 / H01M 8/1067 (ion-exchange).

---

## Лог на кожен hit

| № / DOI | Назва | Assignee | Які фічі розкриває | Чинний патент? (анти-захоплення) | Новизна нашої синергії vs цей hit |
|---|---|---|---|---|---|

> **Висновок-рамка:** очікуваний результат — компоненти мають prior art, але **синергія A (EBFC =
> одночасно живлення + zero-noise `delta_t`-сенсор)** не вчиться ніким → новизна для статті стоїть, і
> якщо нема чинного блокуючого патенту на синергію — наше відкрите використання вільне (анти-захоплення
> підтверджено). Будь-який near-hit на саму синергію → ескалювати на FTO-оцінку ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)).
