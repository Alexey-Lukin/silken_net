# Legal Registry — SilkenNet (§07 юр-концерн)

> **Що це:** індекс **робочих юр-артефактів** SilkenNet (контракт-каркаси · entity-структура · податкова постава · ™-бриф · securities-review · SPDX-план) — один рядок на артефакт: про що, чий канон він дзеркалить, де живе його стан.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе всередині — робочі чернетки й вказівники, **не підписані документи**; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-25** (вміст кожного артефакта — за датою в його власній шапці).
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) §07 — BIZ.*/UNI.*. Іменна конвенція шару: `protocols/legal/<topic>.md`.

---

## 1. Артефакт-реєстр

Колонка «канон-дім» = **дзеркало**: числа/присуди всередині артефакта походять звідти й правляться **там**.

| Артефакт | Про що | Канон-дім (правити там) | 00_07 |
|---|---|---|---|
| [`msa_skeleton.md`](msa_skeleton.md) | Term Sheet + каркас B2B Master Service Agreement + Carbon Rider | [`07_01 §1.1`](../../07_01_Nature_as_a_Service_Contracts.md) (тип контракту) · [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md) (фін-константи) | **BIZ.2** (+ SLA-exhibit → [`business/`](../business/business_registry.md) BIZ.18; counterparty ← BIZ.20) |
| [`b2c_tos_privacy.md`](b2c_tos_privacy.md) | Чернетки B2C ToS / Privacy Policy (GDPR) / Cookie Policy + DPA-нота | [`07_01 §1.2`](../../07_01_Nature_as_a_Service_Contracts.md) (B2C-підписка) · [`07_01 §6`](../../07_01_Nature_as_a_Service_Contracts.md) (ролі/доступ) | **BIZ.3** |
| [`entity_structure.md`](entity_structure.md) | Тришар юр-структури: operational-vehicle ⊥ IP/™ ⊥ token-контур; фазова драбина | [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) (IP-постава) · [`07_01 §8`](../../07_01_Nature_as_a_Service_Contracts.md) | **BIZ.20** (token-контур gated на BIZ.22) |
| [`tax_posture_ua.md`](tax_posture_ua.md) | Податкова постава UA: SCC-дохід, ПДВ на carbon-послугу, фіат-операційка, питання до економістів | [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md) (on-chain dynamic-tax ≠ фіскальний) · [`07_02 §7`](../../07_02_Unit_Economics_and_BOM.md) | **UNI.14** (Ус/Гедз) |
| [`trademark_brief.md`](trademark_brief.md) | Бриф повіреному: 3 марки × Nice-класи, clearance, UA→Paris→EU фазування | [`07_03 §4`](../../07_03_Academic_Integration_and_IP.md) (™-інструменти) · [`07_03 §5`](../../07_03_Academic_Integration_and_IP.md) (бренд-архітектура) | **UNI.15** (тайминг ← UNI.3 TDCommons) |
| [`securities_review.md`](securities_review.md) | As-built fact-pattern продукту проти інвестконтракт-ознак; питання крипто-юристу | [`07_01 §8`](../../07_01_Nature_as_a_Service_Contracts.md) · [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md) | **UNI.16** (канал) / **BIZ.22** (product-присуд) |
| [`spdx_rollout_plan.md`](spdx_rollout_plan.md) | План ідемпотентного проставляння SPDX-заголовків по дереву | [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) (ліцензійна матриця = дзеркало кореневих LICENSE) | **UNI.3** / DOC-T.47 (зонні винятки ратифіковано) |

---

## 2. Особливість класу: вік — це валідність, не стиль

Ці документи спираються на **зовнішнє право й ринок, що рухаються незалежно від repo**: закон правиться без нашого коміту, регламент набуває чинності за календарем, реєстр змінює правила поквартально. Тому кожен артефакт несе `⏳ станом на <дата>` — і ця дата читається **не як метадані охайності, а як строк придатності**: протермінований юр-документ не «стилістично застарілий», він може бути **просто неправильним**, і тим небезпечніший, чим упевненіше написаний. Перед будь-яким використанням (розмова з юристом, відправка контрагенту, рішення) — звіряй первинне джерело; при розходженні перемагає джерело, а артефакт переписується.

---

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md) | One-Home реєстрація цього concern'у (дзеркала → правити в домі) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | §07 BIZ.*/UNI.* — **дім стану** кожного артефакта (що зроблено, що 👤/⚖️) |
| [`07_01`](../../07_01_Nature_as_a_Service_Contracts.md) | NaaS-контракти: типи (§1), фін-константи (§3), відкриті юр-передумови (§8) |
| [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) | IP-постава (defensive-publication, ліцензійна матриця) + ™/юр-review-канали (§4) |
| [`../outreach/legal_business_outreach.md`](../outreach/legal_business_outreach.md) | Dispatch-карта: пакет → людина → що просимо → що розблокує |
| [`business/business_registry.md`](../business/business_registry.md) | Сусідній реєстр — ринок/комерція (SLA · реєстри · страхування · стандарти) |
| [`../research/`](../research/R1_ua_legal.md) | Вхідні web-знімки (R1–R6) — сировина цих артефактів, **не** джерело істини |
