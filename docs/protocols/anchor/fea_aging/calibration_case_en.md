# Додаток 3 до запиту FEA/Prony — калібрувальний кейс англійською (двійник UA-витягу)

> **Що це:** англомовний витяг для ВІДПРАВКИ англомовному виконавцеві (Veryst — [`lock_fea_prony_brief`](../../outreach/lock_fea_prony_brief.md) §10); двійник [`calibration_case_ua.md`](calibration_case_ua.md) з тими самими числами й тією самою межею: §4 звіту [`THERMAL_STRESS_REPORT`](THERMAL_STRESS_REPORT.md) мовою листа, без внутрішнього шару. Повний звіт як вкладення не їде — чому, каже шапка UA-двійника. Дім чисел — звіт; правити тут можна лише слідом за ним і за UA-двійником одним комітом.
>
> ⚠️ Перед відправкою — та сама звірка геометрії й опорної температури, що в шапці [`calibration_case_ua.md`](calibration_case_ua.md); сюди її не переписано, щоб перевірка мала один дім.
>
> ⛔ Це НЕ результат FEA і не видається за нього: аналітична оцінка, проти якої калібрується чужа модель.

## Attachment (EN) — calibration case for the FEA contractor

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у вкладення він НЕ йде.

### Appendix 3. Analytical stress calculation for the sleeve — calibration case

**Why this appendix.** Before the main problem is computed, we ask you to run one simplified case for which we have our own analytical answer: a smooth shaft without teeth, cooling to minus 30 degrees Celsius, and the maximum fit interference. If your result agrees with ours on it, we will have checked the assumptions before the main run; if it does not, the discrepancy is the first thing to discuss, and it is worth more than agreement.

**Geometry.** A coaxial press fit: a titanium shaft 11 mm in diameter enters a polyetheretherketone sleeve with a 2 mm wall. That is, the inner contact radius is 5.5 mm, the outer sleeve radius is 7.5 mm, the outer diameter is 15 mm. The sleeve is 50 mm long.

**The boundary condition that decides the result.** The outer surface of the sleeve is **free**: it stands in the wood of the trunk, not in a rigid outer housing. This is not a descriptive detail — it is exactly what distinguishes our arrangement from the usual "shaft in a sleeve in a housing" fit, and if the model clamps the outer surface, the numbers will disagree by a large factor. The inner surface, conversely, we take as bearing on a rigid shaft: the titanium modulus is 27 times that of the polymer.

**Materials.**

| Property | Titanium alloy | Polyetheretherketone |
|---|---|---|
| Coefficient of linear expansion, 1/K | 8.6 × 10⁻⁶ | 47 × 10⁻⁶ |
| Young's modulus, GPa | 110 | 4.0 (manufacturer's data at 23 degrees) |
| Poisson's ratio | 0.33 | 0.40 |
| Yield strength, MPa | 880 | approximately 98–100 |

The mismatch of the expansion coefficients is a factor of 5.5; it is what produces the interference on cooling.

**Calculation scheme.** A thick-walled cylinder per Lamé, rigid inner boundary and free outer boundary. The contact pressure is linear in the interference, so the mechanical fit interference and the thermal interference are added **before** the stress calculation and the sum is carried through one and the same relation. This matters: stresses computed by three different formulas must not be added, and that is exactly where we ourselves once went wrong — the naive addition gave a margin of 1.4 instead of the true one.

**Reference temperature.** The interference is specified at 20 degrees Celsius; cooling in the case goes to minus 30, a drop of 50 degrees.

**Components and result.**

| Component (at minus 30 degrees) | Radial interference | Hoop stress at the inner surface |
|---|---:|---:|
| Thermal only | 10.6 µm | 6.9 MPa |
| Fit only, maximum interference | 17.0 µm | 11.0 MPa |
| **Total** | **27.6 µm** | **17.9 MPa** |

Against the polymer's yield strength this is a margin of 5.6 on hoop stress and 4.7 on von Mises.

**What exactly we ask you to compare.** The hoop stress at the inner surface of the sleeve at the coldest point with maximum interference — that is, the number 17.9 MPa — and the total radial interference of 27.6 µm. The rest of our report is not needed for this check.

**One remark about the opposite end.** At the hot end of the range (plus 40 degrees, minimum interference) the effective interference becomes negative — the fit opens, the contact pressure drops to zero. For us this is not a failure: this joint is not a seal; the seal in the assembly is carried by another element. We say this so that you do not look for an error where there is none.

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## Звідки кожен блок

| Блок вкладення | Дім |
|---|---|
| усі блоки | ті самі, що в таблиці «Звідки кожен блок» [`calibration_case_ua.md`](calibration_case_ua.md): [`THERMAL_STRESS_REPORT`](THERMAL_STRESS_REPORT.md) §Materials · §Geometry · §4 · опорна температура — `T_ASSEMBLY_C` · «стик не є ущільненням» — шапка звіту. Переклад міняє мову, не числа |
