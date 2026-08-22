# Procurement / RFQ Registry — SilkenNet (cross-domain)

> **Що це:** домен-нейтральний **індекс усього procurement-концерну** (RFQ-артефакти + vendor-канали + hard-constraint-доми + workflow-айтеми) + стандартна **RFQ-аркуш-конвенція**.
> Concern-шар (як [`paper/`](../paper/self_review_checklist.md) / [`outreach/`](../outreach/owner_meeting_briefs.md)) — **НЕ канон**. **Усе тут — вказівники/дзеркало канону**; правити в домі, не тут (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> RFQ-аркуші: `protocols/procurement/<domain>_<scope>_rfq.md`.

---

## 1. RFQ-artifact registry (компонент-група → дім → аркуш → канал → статус)

Статус: **✅** повний аркуш є · **🟡** stub (індексовано; аркуш авториться як-procure'иться) · **⚪** future. Канал: **CRO** commercial · **ACAD** академ-co-pub ([`07_03`](../../07_03_Academic_Integration_and_IP.md)) · **DIST** дистриб'ютор · **AM** друк-бюро.

| Домен | Компонент-група | Канон BOM-дім | Hard-constraint дім (§4) | Аркуш | Vendor / канал | 00_07 |
|---|---|---|---|---|---|---|
| **EBFC хімія** | фермент · Os · ZIF · genipin · мембрана · CNC | [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | §4.A | [`ebfc_chem_rfq`](ebfc_chem_rfq.md) **✅** | GenScript/ProteoGenix **CRO** (🔴 4-8тиж) · ЧМА/ЧНУ **ACAD** (ZIF/сік) · Challenge (genipin) | HW.5 |
| **Анкер сплав** | Ti-coupon 6-alloy bake-off | [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | §4.B | [`anchor_alloy_rfq`](anchor_alloy_rfq.md) **✅** | 3D Metal Tech Київ **AM** · EL-CELL (CV/EIS) **CRO** · Гусак **ACAD** | HW.24/HW.3 |
| **Анкер dummy (Stage-1)** | 2-3 НЕ-функц. анкери — qualify DMLS-друк + props (SLA form&fit / SLM-Ti-4V метал) | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) Stage 1 | §4.B (друк) | 🟡 STL ✅ (`tools/cad` `build`; gallery [`images/cad`](../../images/cad/README.md)) | 3D Metal Tech Київ / 3D Lab PL **AM** · SLA-сервіс | HW.24 (Stage 1) · BIZ.6 |
| **Анкер hardware** | PEEK Zone2/Radome · pogo · O-ring · DIN-471 · болти | [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`02_02`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`07_01 §8`](../../07_01_Nature_as_a_Service_Contracts.md) | §4.B/§4.C | 🟡 | EU DMLS (3D Lab PL…) **AM** · Mill-Max (pogo) · fastener-**DIST** | HW.1/HW.8/HW.17/HW.23/HW.27/BIZ.6 |
| **Капсула електроніка** | MCU · MPPT · supercap · антена · piezo · conformal · PCB | [`02_01 §1`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_01 §3`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_03`](../../02_03_BQ25570_MPPT_Nano_Power.md) | §4.D | ⚪ | Mouser/Digi-Key **DIST** · Parylene-shop · PCB-fab | HW.9/HW.11/HW.29/HW.32 |
| **Брама Queen** | SIM7070G · LTE/LoRa антени · solar · battery+BMS | [`02_05`](../../02_05_Queen_Hardware_and_Starlink.md) — §2–§7 | §4.D | ⚪ | SIMCom/Київстар · antenna-spec · LiFePO4 **DIST** | HW.10/HW.14/HW.15/HW.16/HW.31 |
| **Secure Element** | NXP SE05x (baseline SE051C2) | [`03_05 §3.7`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md) · [`03_06`](../../03_06_Factory_Flashing_and_Key_Provisioning.md) | §4.D | ⚪ | NXP **DIST** (DNP до FW.2) | SEC.6 / FW.2 (в) |
| **Стерилізація** | gamma (Co-60) · UV-C · автоклав/EtO послуги | [`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md) | §4.E | ⚪ | Co-60 (Чорнобиль НДІ / Київ ІРОНЦ) **CRO** | HW.22 |
| **Покриття / біо** | 8-HQ · Zn-HAp · PEDOT:PSS · PTFE-GDL · лігнін | [`01_02 §3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_04 §4`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §5`](../../01_04_CODIT_and_Xylemointegration.md) | §4.A/§4.E | ⚪ | ЧНУ/ЧМА **ACAD** · Gore/Donaldson (PTFE) **DIST** | HW.4/HW.25/HW.27 |
| **Інструмент монтажу** | step-drill · microfreze (WC+TiN) | [`01_04 §3.1`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §3.3`](../../01_04_CODIT_and_Xylemointegration.md) | — | ⚪ | MicroX/OSG **DIST** | HW.6 |

> 🟡/⚪ = повний аркуш авториться **коли компонент procure'иться** (інкрементально — DOC-T у [`00_07`](../../00_07_Action_Plan_Tracker.md)); рядок = індекс на канон vendor/constraint-дім тим часом. Не boil-the-ocean.

---

## 2. Два procurement-шари (різні workflow)

| | **R&D-RFQ** (TRL 3→5, Stage 1-3) | **Production-procurement** (TRL 6+, Stage 4 100-партія) |
|---|---|---|
| **Дім** | `protocols/procurement/` (цей шар) | [`02_06 §8`](../../07_01_Nature_as_a_Service_Contracts.md) (BOM/хаби) + §8.1.1 Frame Agreement |
| **Вендор-зв'язок** | spot-quote (CRO / academ-co-pub) | Frame Agreement (+20% premium, 30-day activation, SLA) |
| **Авторитет** | architect + ЧНУ-PI | CEO/Partnerships (контракт) |
| **00_07** | HW.5/HW.24/HW.3 | **BIZ.6** (EU-backup) |

Stage-2 coin-bake-off = **R&D-шар**; 100-партія = **Production-шар** (НЕ замовляти до Stage-2 гейту, [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)).

---

## 3. Cross-cutting procurement-політики (вказівники на доми)

- **IP / CDA / NDA:** [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) — **defensive-publication** → RFQ-specs **відкриті** (вже prior art); CDA = **стандартні комерц-умови** (ціни/строки/QC), НЕ для новизни; NDA **лише** для нерозкритого (prod-keys/telemetry/ML-ваги). RFQ-аркуші це наслідують у §IP.
- **Академічний канал** ([`07_03`](../../07_03_Academic_Integration_and_IP.md)): co-pub (ЧНУ/ЧМА/ЧДТУ) = $0 + Q1-публікація, але темп-партнер-залежний; commercial CRO = $ + швидше + стандартний CDA. **Гібрид** на критичному шляху (HW.5: academ-валідація архітектури + commercial-експресія). Партнер-MoU гейт = ЧНУ лаб-доступ (**UNI.2**, passive) + CDA/NDA legal (**UNI.14** СЄУ Аблязов).
- **Фінансування-гейти** ([`00_07` BIZ.20](../../00_07_Action_Plan_Tracker.md)): procurement-authority вивільняється поетапно з self-fund (operational-особа вже існує) (перша 100-партія CAPEX gated на BIZ.20).

---

## 4. Hard sourcing constraints — доми (RFQ МУСИТЬ нести; тут = індекс, не дублі)

Кожен аркуш тягне ці constraint'и з канону (дзеркало). Індекс домів:

- **§4.A EBFC хімія** ([`01_03 §2.1/§2.2/§3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): **dgrFAD-GDH** деглікозильований, *Pichia* НЕ *E.coli*, **НЕ GOx** (H₂O₂→CODIT) · **Genipin НЕ глутаральдегід** (токсичний) · Os E° +309мВ · Nafion-g-PSBMA (НЕ PEG) · ZIF/Laccase гібрид (chloride +7.5%) · PTFE-GDL (НЕ PEO/Nafion).
- **§4.B Анкер метал** ([`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): **SLM НЕ EBM** Zone 1 (порошок 15-45µm) · **HIP обов'язково** (920°C/100-150МПа/2-4год) · build BD∥вісь · **dehydrogenation bake** 250°C/10⁻³mbar <2год після rinse, H<100ppm · **ZnO-Ta ЗАБОРОНЕНО** на Zone 1 (§3.6).
- **§4.C Анкер механіка** ([`01_01 §3/§4.2/§4.3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)): PEEK annealing 200-250°C перед фрезеруванням · H7/s6 hex ≤0.05мм · barbs (3-5 рядів, h0.28/α30/β70, self-support) · DIN-471 external · press-fit 150°C/800-1200Н.
- **§4.D Електроніка** ([`02_01 §1/§3`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_03`](../../02_03_BQ25570_MPPT_Nano_Power.md) · [`02_05 §2`](../../02_05_Queen_Hardware_and_Starlink.md) · [`03_05 §3.7`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md)): BQ25570 VBAT_OV=5.5V · **buffer-cap 25V НЕ 6.3V** (DC-bias) · Mill-Max pogo <50мОм · SMD-антена (НЕ зовнішній дріт) · **SIM7070G НЕ SIM7000G** (eDRX/PSM) · **BME280 НЕ BME680** (gas-heater) · **Parylene C НЕ Sylgard** full-pot (глушить TinyML) · SE050 (НЕ ATECC, non-extractable Ed25519).
- **§4.E Стерилізація/мембрана** ([`01_04 §5/§6`](../../01_04_CODIT_and_Xylemointegration.md)): **ГІЛКА A (Ti+ферменти) — Co-60, НЕ EtO** (EtO незворотно денатурує dgrFAD-GDH/лакказу + лишає цитотоксичні побічні продукти в порах гіроїда — [`01_04 §6.1`](../../01_04_CODIT_and_Xylemointegration.md); ГІЛКА B [PTFE-GDL+O-ring] EtO/автоклав **допускає**, §6.2) · **low-dose 15кГр** для ферментів (НЕ 25, [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)) · PTFE-GDL 0.2-1.0µm.

---

## 5. Стандартна RFQ-аркуш-конвенція (шаблон)

Кожен `<domain>_<scope>_rfq.md`: **Header** («Що це» · статус 🟡 · One-Home-disclaimer · cross-ref) → **§0 cover-note** (CDA · мета · послідовність критичним шляхом) → **per-component spec-table** (`Поле | Специфікація`: Продукт · Метод · QC/acceptance · Цільові-показники-дзеркало · Партнер-опція · IP) → **dispatch-checklist** (👤, критичний шлях першим) → **§Cross-references**.

**Крос-доменні шаблони** (не per-component аркуш → не рядок §1): [`vendor_templates.md`](vendor_templates.md) — DMLS vendor-scoring matrix + ESG-screening checklist + взаємний CDA/NDA під ВНЗ-MoU ([`00_07` BIZ.17](../../00_07_Action_Plan_Tracker.md)); застосовуються поверх будь-якого аркуша, IP/CDA-політика — §3.

---

## 6. Послідовність (критичний шлях першим)

Найдовший lead-time стартує першим: **dgrFAD-GDH 4-8 тиж** ([`ebfc_chem_rfq`](ebfc_chem_rfq.md) Spec A, 🔴). Купони (2-4 тиж) + genipin (дні) — швидкі; усе сходиться на Ti-coin для CV/EIS ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

---

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md) | One-Home реєстрація цього concern'у |
| [`02_06 §8`](../../07_01_Nature_as_a_Service_Contracts.md) | economics/BOM + україн­ські DMLS-хаби + Production-шар (Frame Agreement) |
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | IP/CDA/NDA-політика (defensive-publication) — дім |
| [`07_03`](../../07_03_Academic_Integration_and_IP.md) | академічні co-pub канали (ЧНУ/ЧМА/ЧДТУ) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | HW.*/BIZ.* procurement-action-items + DOC-T (інкрементальне авторство) |
