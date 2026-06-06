# Patent Claims — Draft (synergy-focused) для TISC ЧНУ / патентного повіреного

> **Статус:** 🟡 **DRAFT — технічна заготовка**, НЕ фінальна заявка. Формальності (UA/PCT
> формат, нумерація, «characterised in that» стиль, єдність винаходу) фіналізує патентний
> повірений + Кафедра ІВ ЧНУ. Тут — **технічний зміст claims + лінія захисту**, щоб не
> починати з чистого аркуша.
> **Призначення:** вхідний матеріал для TISC-пошуку + чернетка незалежних/залежних пунктів.
> **Cross-ref:** [`prior_art_queries.md`](prior_art_queries.md) (пошукові запити + positioning) ·
> [`08_01 §2.1`](../../08_01_Joint_Publications_and_IP_Strategy.md) (TISC engagement) ·
> [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (EBFC канон) · [`01_01`/`01_02`](../../01_01_Anchor_Geometry_and_Materials.md) (gyroid).
> 🛑 **Filing PRECEDES journal submission** — Стаття 1 розкриває cascade/PCET механізм (08_01 §2).

---

## 0. Стратегія (read first)

Кожен **окремий** компонент (gyroid-імплант, FAD-GDH/Os EBFC, laccase/ZIF катод, LoRa-mesh,
blockchain-MRV) має **prior art** (`prior_art_queries.md` §78–81). Патентоспроможність тримається
**не на деталях, а на синергії** — двох ефектах, яких **жодне джерело не вчить**:

- **СИНЕРГІЯ A (EBFC dual-function):** один і той самий EBFC **ОДНОЧАСНО** (a) живить електроніку
  *і* (b) є біосенсором з **нульовим інструментальним шумом** — сам час заряду `delta_t`
  суперконденсатора є вимірювальним сигналом (немає окремого сенсора → немає його шуму/живлення/дрейфу).
- **СИНЕРГІЯ B (gyroid triple-function):** одна геометрія gyroid **ОДНОЧАСНО** (a) інтегрується з
  потоком ксилемного соку, (b) дає isoelastic stress-matching до живої деревини, (c) формує
  **електрод metal↔xylem інтерфейсу** того самого EBFC.

> **Правило:** claim'и формулюються навколо **комбінації + цих двох синергій**, НЕ навколо
> списку частин. Це лінія проти заперечення «обвіозність комбінації відомих елементів».

---

## 1. Independent Claim 1 — System (EN, PCT-ready draft)

**1.** A self-powered apparatus for *in-situ* monitoring of the physiological state of living
woody plant tissue, comprising:

&nbsp;&nbsp;(a) a porous metal anchor of additively-manufactured titanium alloy having a triply-periodic
minimal-surface (gyroid) architecture, configured for implantation into the xylem of a living tree,
wherein said gyroid architecture **simultaneously** (i) admits xylem sap into the porous volume,
(ii) provides an isoelastic stiffness gradient matched to the surrounding living wood, and
(iii) constitutes a metal–xylem interface electrode;

&nbsp;&nbsp;(b) an enzymatic biofuel cell (EBFC) established at said metal–xylem interface, having an
anode at which an immobilised flavin-dependent oxidoreductase oxidises xylem-borne glucose through a
redox-mediator, and a cathode at which oxygen is reduced;

&nbsp;&nbsp;(c) an energy-storage element charged by said EBFC and supplying the apparatus electronics; and

&nbsp;&nbsp;(d) a processing unit configured to derive a plant-health signal **from the charging dynamics of
said energy-storage element itself**, such that the EBFC **simultaneously** powers the apparatus and
serves as its physiological sensor without a separate instrumented transducer;

&nbsp;&nbsp;**characterised in that** the time interval (`delta_t`) required for the EBFC to charge the
energy-storage element through a defined voltage window is processed as the primary physiological
measurand, and the plant-health state is classified from the **non-linear (chaotic) temporal dynamics**
of a time series of said intervals.

---

## 2. Dependent Claims (EN draft)

**2.** The apparatus of claim 1, wherein the titanium alloy is Ti-6Al-4V and the gyroid has a porosity
gradient (≈65 % nominal) with pore size graded from the anchor centre to its periphery, the principal
cell axis oriented parallel to the sap-flow axis.

**3.** The apparatus of claim 1, wherein the oxidoreductase is a fungal FAD-dependent glucose
dehydrogenase and the mediator is an osmium-bis-bipyridyl poly(vinylimidazole) redox polymer
co-immobilised in a genipin-cross-linked chitosan / cellulose-nanocrystal hydrogel matrix.

**4.** The apparatus of claim 1, wherein the cathode comprises a multi-metallic (e.g. Cu-Co-Ce)
zeolitic-imidazolate-framework laccase-mimicking nanozyme effecting direct electron transfer.

**5.** The apparatus of claim 1, wherein the processing unit classifies the plant-health state by
evolving a deterministic non-linear dynamical system (a Lorenz-type attractor) parametrised by said
`delta_t` interval together with on-board temperature and acoustic-emission inputs.

**6.** The apparatus of claim 1, further comprising a low-power wide-area (LoRa-type) radio forming a
mesh network of said apparatuses across a stand of trees, each node powered solely by its own EBFC.

**7.** The apparatus of claim 6, wherein health classifications are committed to a distributed ledger
as the verification layer of a measurement-reporting-and-verification (MRV) record for the monitored
biomass.

**8.** The apparatus of claim 1, wherein the metal–xylem interface bears a zone-restricted protective
arrangement (e.g. anti-corrosion / anti-biofouling layer) applied to surfaces **other than** the
enzyme-bearing gyroid wall, so as not to passivate the EBFC interface.

---

## 3. Independent Claim 2 — Method (EN draft)

**9.** A method of monitoring the health of a living tree, comprising: implanting into the tree xylem a
porous gyroid titanium-alloy anchor that simultaneously integrates with sap flow, elastically matches
the wood, and forms an EBFC metal–xylem electrode; generating electrical power from xylem glucose at
said EBFC; storing said power in an energy-storage element; and deriving a health signal **from the
charge-time dynamics of that same element**, whereby a single enzymatic biofuel cell both powers the
monitoring and constitutes its zero-instrumental-noise sensor.

---

## 4. Inventive-step defence (для розгляду заперечень)

| Очікуване заперечення експертизи | Лінія захисту (synergy / teaching-away) |
|---|---|
| «Gyroid Ti-імпланти відомі (ортопедія)» | Так — але як **xylem-electrode EBFC-інтерфейс** з isoelastic-matching до **живої деревини** — ні; потрійна функція однієї геометрії = неочікувано. |
| «Os-mediated FAD-GDH EBFC відомий (Degani-Heller →)» | Так — каскад/тюнінг медіатора **НЕ claim'имо** (prior art). Claim — EBFC як **сенсорний сигнал** (`delta_t`), чого джерела EBFC не вчать. |
| «Self-powered LoRa-сенсори відомі» | Так — але там harvester живить **окремий** сенсор. Тут сенсора **немає як вузла** — вимірює сама комірка живлення (zero-noise). Це teaching-away: інженерія завжди додає сенсор. |
| «Обвіозно скомбінувати A+B+C» | Синергія A та B дають ефект, відсутній у сумі частин: усунення сенсорного шуму/живлення + потрійна роль геометрії. Комбінація не «складання», а **усунення компонентів**. |

---

## 5. Що НЕ claim'имо (prior art — щоб не отримати novelty-reject)

- FADH₂→Os **каскад** і тюнінг потенціалу медіатора *per se* (Degani-Heller; Mano/Heller +15…+489 mV;
  обвіозно через Lever E_L). → лише як елемент комбінації, не як винахід.
- Концепція **laccase/ZIF ORR-катода** *per se* (Cu/Zn-ZIF, Cu-ZIF-67 опубліковані).
- Будь-який **окремий** компонент. Незалежні пункти ЗАВЖДИ містять обидві синергії (A+B).

---

## 6. Дії для TISC / патентного повіреного (👤 owner)

1. Прогнати `prior_art_queries.md` Sets 1–5 (PATENTSCOPE + Espacenet + Google Patents + Lens.org) —
   **patentability** режим (no date filter, full text, broad terms).
2. Для кожного near-hit — лог: чи б'є **novelty** (точна комбінація) чи лише **inventive-step** (synergy рятує).
3. Перевести claims 1–9 у формальний UA/PCT формат (єдність винаходу: 1 product + 1 method ОК).
4. Узгодити з **08_01 §2.1** розподіл прав (ЧНУ Кафедра ІВ) + embargo (filing ПЕРЕД сабмітом Статті 1).
