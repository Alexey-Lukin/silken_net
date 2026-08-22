# Business Registry — SilkenNet (§07 бізнес-концерн)

> **Що це:** індекс **робочих бізнес-артефактів** SilkenNet (SLA-exhibit · carbon/biodiversity-реєстри · страхова спека · enterprise-readiness · integrity- та OSS/Web3-стандарт-ландшафти) — один рядок на артефакт: про що, чий канон він дзеркалить, де живе його стан.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе всередині — робочі чернетки й вказівники, **не підписані документи**; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-25** (вміст кожного артефакта — за датою в його власній шапці).
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07 §00b`](../../00_07_Action_Plan_Tracker.md) — BIZ.*/UNI.*. Іменна конвенція шару: `protocols/business/<topic>.md`.

---

## 1. Артефакт-реєстр

Колонка «канон-дім» = **дзеркало**: числа/присуди всередині артефакта походять звідти й правляться **там**.

| Артефакт | Про що | Канон-дім (правити там) | 00_07 |
|---|---|---|---|
| [`../outreach/legal_business_outreach.md`](../outreach/legal_business_outreach.md) | Dispatch-карта: пакет → людина → що просимо → що розблокує | — (сама карта; канон-домів не дзеркалить) | **§07 загалом** (маршрутизує до items, власного не має) |
| [`sla_exhibit.md`](sla_exhibit.md) | Шаблон customer-facing availability-SLA (exhibit до MSA) | [`06_06 §3`](../../06_06_Disaster_Recovery_and_Backup.md) (RTO/RPO) · [`06_08 §2.4`](../../06_08_Resilience_and_Failover_Policy.md) (internal SLO) | **BIZ.18** (живить BIZ.2 → [`legal/`](../legal/legal_registry.md)) |
| [`carbon_registry_matrix.md`](carbon_registry_matrix.md) | Порівняння carbon/biodiversity-реєстрів + метрологічний розрив | [`00_04 §3`](../../00_04_Nature_as_a_Service_Contracts.md) (фін-константи) · [`02_06 §7.3`](../../02_06_Unit_Economics_and_BOM.md) | **BIZ.9** (вибір реєстру = ⚖️) |
| [`eo_insurance_spec.md`](eo_insurance_spec.md) | Спека coverage-вимог для страхового брокера (E&O / CGL) | [`00_04 §7`](../../00_04_Nature_as_a_Service_Contracts.md) (параметричне страхування **клієнта** — сусіднє, не це) · [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) | **BIZ.21** (поліс gated на BIZ.20-entity) |
| [`b2b_readiness.md`](b2b_readiness.md) | Що вимагає enterprise-procurement × наша phase-gated готовність | [`00_03`](../../00_03_TRL_Matrix_HIL_and_Beyond.md) (чесний TRL) · [`00_04 §1.1`](../../00_04_Nature_as_a_Service_Contracts.md) | живить **BIZ.2** / **BIZ.18** |
| [`carbon_integrity_standards.md`](carbon_integrity_standards.md) | Buyer-side integrity-стек: ICVCM CCP, VCMI, Oxford, SBTi, ISO 14064, IAPB | [`02_06 §7.1`](../../02_06_Unit_Economics_and_BOM.md) (growth_points → CO₂-еквівалент) · [`00_04 §3`](../../00_04_Nature_as_a_Service_Contracts.md) | **BIZ.9** / **BIZ.23** (biodiversity = stewardship, не offset) |
| [`oss_web3_standards.md`](oss_web3_standards.md) | Web3-токен + open-source best practices: SPDX/REUSE, SBOM/CRA, DCO, AGPL | [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) (ліцензійна матриця) · [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md) | **UNI.20** (DCO) / **BIZ.24** (CRA/SBOM) |

---

> **⚠️ Провенанс тверджень про зовнішнє право/ринок.** Фактура цих документів здебільшого **single-sourced з web-дослідження** ([`../research/`](../research/R1_ua_legal.md)), яке саме себе позначає «НЕ верифіковано пофактно». Похідні артефакти цей статус **успадковують**: «не юридична порада» — про скоуп, «⏳ станом на» — про вік, а це — про **походження**. Перед будь-яким зовнішнім використанням звіряй першоджерело.

## 2. Особливість класу: вік — це валідність, не стиль

Ці документи спираються на **зовнішнє право й ринок, що рухаються незалежно від repo**: регламент набуває чинності за календарем, integrity-стандарт виходить новою версією, реєстр змінює правила й прайс поквартально, страховий ринок переписує винятки після кожного великого збитку. Тому кожен артефакт несе `⏳ станом на <дата>` — і ця дата читається **не як метадані охайності, а як строк придатності**: протермінований ринковий документ не «стилістично застарілий», він може бути **просто неправильним**, і тим небезпечніший, чим упевненіше написаний. Перед будь-яким використанням (перемовини, тендер, підпис) — звіряй первинне джерело; при розходженні перемагає джерело, а артефакт переписується.

---

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md) | One-Home реєстрація цього concern'у (дзеркала → правити в домі) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | §07 BIZ.*/UNI.* — **дім стану** кожного артефакта (що зроблено, що 👤/⚖️) |
| [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) | Відкриті юр/бізнес-передумови NaaS (SLA · страхування · RWA) — дім присудів |
| [`00_02`](../../00_02_Academic_Integration_and_IP.md) | IP/ліцензійна постава (§3) + академ-канал, на який спираються OSS-стандарти |
| [`legal/legal_registry.md`](../legal/legal_registry.md) | Сусідній реєстр — право (MSA/ToS · entity · податки · ™ · securities) |
| [`../research/`](../research/R3_carbon_registries.md) | Вхідні web-знімки (R1–R6) — сировина цих артефактів, **не** джерело істини |
