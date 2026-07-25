---
name: legal-business
description: "Use when working on the silken_net §07 surface — legal / business / academic-partner / IP-and-brand. Covers NaaS contract terms and financial constants (07_01), unit economics · BOM rollup · ROI (07_02), the 5-university partner registry · publication plan · defensive-publication IP posture · SilkenNet/GaiaNexus brand (07_03), and the working draft layer in docs/protocols/{legal,business,procurement,outreach,research}/ (MSA skeleton, B2C ToS/Privacy, entity structure, tax posture, trademark brief, securities review, SPDX plan, SLA exhibit, carbon registry matrix, E&O spec, vendor templates, outreach dispatch map). Knows the non-obvious traps — a draft is never a signed document and a spec is never a bought policy; SCC is an internal accounting convention, NOT a registry-recognised carbon credit; our own analysis is publishable but a third party's operational facts are not; the rate-guard and solc-guard DO scan docs/protocols/** and fire on a customer-facing document that restates a rate; protocols/ refs need relative hrefs with correct ../-depth; one advisor workshop cannot close a securities question. Routes to the 07_01..07_03 canon + 00_07 §07 state, does not restate. NOT this skill: canon-doc mechanics / linters / wiki → ssot-maintenance; token & money-path code → web3-pipeline. Examples: \"draft an NaaS clause\", \"онови юніт-економіку після нового BOM\", \"is SCC a security?\", \"що просити в Аблязова\", \"додай документ у protocols/legal\", \"статус MoU з ЧНУ\", \"trademark strategy\", \"чи можна назвати це вуглецевим кредитом\"."
---

# §07 — Legal / Business / Academic / IP

Домен, у якому **founder не є експертом**, а більшість роботи — людська (юристи, повірені, брокери, ВНЗ). Тому центр ваги цього скіла інший, ніж у решти: не «як швидше збудувати», а **як не сказати неправди й не опублікувати зайвого**. Помилка тут їде не в білд — вона їде до юриста, до страховика або в публічний GitHub.

> **SSOT One-Home:** цей скіл **маршрутизує**. Значення (курси, ціни, payback, профілі партнерів, статуси айтемів) живуть у своїх домах — не дублюй їх сюди, бо вони рухаються, а скіл почне брехати впевнено. Дім стану — `00_07 §07`; дім кампанійного «чому» — `[[project_sec07_legal_campaign]]`.

## 🛑 Межі чесності — читати ПЕРШИМ

Порушення будь-якої з них дорожче за будь-який технічний баг у цьому домені.

1. **Чернетка ≠ підписаний документ. Спека ≠ куплений поліс. План ≠ виконаний прохід.** Усе в `docs/protocols/{legal,business}/` — **робочий вхід у платну консультацію**. Ніколи не позначай айтем закритим, бо машинна половина написана.
2. **SCC ≠ сертифікований вуглецевий кредит.** `2000 SCC = 1 tCO₂` — **внутрішня облікова конвенція** Proof-of-Growth. Жоден реєстр не бере фізіологічний сигнал дерева як прямий вхід для tCO₂e. Продаємо дані моніторингу й фіксацію подій; кредит видає зовнішній реєстр за власною методологією → [`07_01 §3`](../../../docs/07_01_Nature_as_a_Service_Contracts.md), `protocols/business/carbon_registry_matrix.md` §1.
3. **Наш аналіз публікуємо — чужі факти ні.** Repo публічний. Власні знахідки, чесні межі, навіть незручні — повністю. Але операційні факти третьої компанії (чисельність, вік, ланцюг білінгу, її податковий статус) не наші, щоб їх публікувати; генеризуй їх, зміст лишай.
4. **Securities — регістр трекера, не юр-висновок про себе.** Правильно: «as-built fact-pattern збігається з пронгами; консультація + redesign гейтять перший live-mint». Неправильно: «ми є незареєстрованим цінним папером». Дім — `00_07` BIZ.22.
5. **Імена — тільки ті, що називає канон.** Де виконавця немає — пиши «TBD, не контактовано». Не вигадуй персону й не перетворюй адресата на домовленість: більшість контактів ще **не відбулась**.
6. **`R1`–`R6` у `protocols/research/` — не джерело істини.** Це датовані web-знімки, **не верифіковані пофактно**. Цитувати їх як факт = перетворити дисклеймер на твердження.
7. **Вік документа тут = валідність, а не стиль.** Цей шар спирається на право й ринок, що рухаються без нашого коміту. Протермінований юр-документ не «застарілий стилістично» — він може бути просто неправильним, і тим небезпечніший, чим упевненіше написаний.

## Куди йти за питанням

| Питання | Дім |
|---|---|
| Типи NaaS-контрактів, умови входу, що входить у послугу | [`07_01 §1`](../../../docs/07_01_Nature_as_a_Service_Contracts.md) |
| Юр-подія → on-chain tx (mint / slash / payout / anchor) | [`07_01 §2`](../../../docs/07_01_Nature_as_a_Service_Contracts.md) — ⚠️ це НЕ availability-SLA |
| Фінансові константи (бізнес-в'ю) | [`07_01 §3`](../../../docs/07_01_Nature_as_a_Service_Contracts.md); технічний дім тих самих курсів — [`05_03`](../../../docs/05_03_Tokenomics_SCC_and_SFC.md) |
| Життєвий цикл контракту · схема даних · ролі | [`07_01 §4`](../../../docs/07_01_Nature_as_a_Service_Contracts.md) · `§5` · `§6` |
| Параметричне страхування **клієнта** | [`07_01 §7`](../../../docs/07_01_Nature_as_a_Service_Contracts.md); політика-дім — [`05_05 §4`](../../../docs/05_05_Slashing_and_Risk_Policy.md) |
| Яких юр/бізнес-артефактів бракує | [`07_01 §8`](../../../docs/07_01_Nature_as_a_Service_Contracts.md) |
| Per-component BOM Soldier | [`02_01 §3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md) — **не** 07_02 |
| Node-rollup $ · cluster CAPEX · ROI-крива | [`07_02 §1.2`](../../../docs/07_02_Unit_Economics_and_BOM.md) · `§5.3` · `§7.3` (решта — дзеркала, правити в домі) |
| Виробничі хаби, EU-backup, Frame Agreement | [`07_02 §8`](../../../docs/07_02_Unit_Economics_and_BOM.md) |
| Академ-реєстр 5 ВНЗ · план публікацій | [`07_03 §1`](../../../docs/07_03_Academic_Integration_and_IP.md) · `§2` |
| IP-постава, ліцензійна матриця, межа «відкрито/утримуємо», правовий актор | [`07_03 §3`](../../../docs/07_03_Academic_Integration_and_IP.md) — значення ліцензій = дзеркало `/LICENSE*` + `/NOTICE` |
| TISC · ™ · UA-юр-review · послідовність кроків | [`07_03 §4`](../../../docs/07_03_Academic_Integration_and_IP.md) |
| Бренд-архітектура | [`07_03 §5`](../../../docs/07_03_Academic_Integration_and_IP.md) |
| Робочі чернетки (юр / бізнес) | `protocols/legal/legal_registry.md` · `protocols/business/business_registry.md` |
| Вендори / RFQ | `protocols/procurement/rfq_registry.md` |
| «Пакет → людина → що просимо» · prep конкретної зустрічі | `protocols/outreach/legal_business_outreach.md` · `owner_meeting_briefs.md` |
| Self-review перед сабмітом статті | `protocols/paper/self_review_checklist.md` |
| **Стан, рішення, блокери** | `00_07 §07` + шапка `🚦 Critical Path` / `⛓️ Гейт-кластери` |

Суміжне, що виглядає як §07, але живе інде: метрологія/ЗВТ → `00_07` STK.5 (у §05) · slashing-бізнес → [`05_05`](../../../docs/05_05_Slashing_and_Risk_Policy.md) · культурний шар → `docs/cultural_layer.md`.

## Хто на яке питання відповідає

Ролі канонізовані в [`07_03 §1.5`](../../../docs/07_03_Academic_Integration_and_IP.md) + `§4`; поточний стан контактів — `00_07`. **Більшість — ще не контактовані.**

- **UA господарське/комерційне право, MSA, IP-carve-out, RWA vs Лісовий Кодекс, NDA** → Аблязов (СЄУ, персонально; UNI.14 → UNI.16).
- **Крипто / securities / MiCA** → профільний юрист, **TBD**. 🔴 Це найгостріша вакансія домену: вона гейтить `00_07` BIZ.22, а той — Web3 mainnet. Один воркшоп UA-господарника її **не закриє** — і скіл не має вдавати протилежне.
- **Податки, облік криптоактивів, 90%-тест Дія.City** → Ус / Гедз (СЄУ; UNI.14).
- **Подача ™** → прямий повірений УкрНОІВІ (роль канонізована, особа TBD; UNI.15). TISC консультує, але **сам не подає**.
- **E&O / CGL поліси** → страховий брокер, TBD (BIZ.21).
- **Carbon-методолог / PDD** → TBD, gated на реальний ліс (BIZ.9).
- **Лаб-MoU** → Спрягайло (ЧНУ) · Гончаров (ЧДТУ). Режим **passive**: рішення на боці ВНЗ, не дотискати.

**Найбільший важіль** — один воркшоп Аблязова фанається у п'ять айтемів (`00_07 ⛓️`). Нести весь підпакет разом, не по документу за раз.

## 🔴 Гейт-пастки цього шару

`docs/protocols/**` — **не вільна зона**. Value/owner-гейти сканують розширену поверхню (DOC-T.42), і жоден concern-файл не exempt (owner-регекси матчать лише `NN_NN`-basename). Натомість **структурні** гейти (ToC, TRL, Статус, conformance) сюди **не дістають** — concern-документу не потрібні ані ✅ Статус, ані auto-ToC.

1. **rate-guard — найімовірніший стріл.** Рядок із `10 000 … = 1 SCC` або `2000 SCC = 1 t…` (ловить і кирилицю) валить CI **поза** `05_03`/`07_01`/`07_02`/`00_07`/`manifest`. Лік — **не прибирати число, а поставити дзеркало-маркер у ТОМУ Ж рядку** (`дзеркало` / `mirror` / `05_03` / `07_01` / `SystemParameter` / `ProtocolParameters`). Клієнтський документ **мусить** називати курс — тому це єдиний коректний шлях. ⚠️ Інверсна форма (`1 SCC = 0.5 кг CO₂`) гейт **не ловить** — не спокушайся, One-Home від цього не зникає.
2. **solc-guard не пропускає код-блоки.** `pragma solidity 0.8.NN` усередині ` ``` ` теж червоніє. Пиши плейсхолдер + реф у тому ж рядку: `pragma solidity <pinned>;   // версія — One-Home 05_03`.
3. **deprecated-terms — substring по всьому файлу**, фенси не рятують. Для цього домену живий ризик один: ретирований codename (BIZ.16). Пиши описово, без самого літерала.
4. **`protocols_ref_check` (HARD).** Канон-реф = `` [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md) `` — code-span-мітка + relative href + `.md`. Перевіряються **чотири** речі: док існує · `§X` резолвиться в реальний заголовок · `#anchor` резолвиться · голий `` `NN_NN` `` має док. **І глибина `../`**: з `protocols/<dir>/` рівно `../../`, з чотирирівневих (`protocols/ebfc/in_silico/`) — `../../../`. Хибна глибина раніше проходила мовчки — гейт валідував ім'я, не шлях.
5. **ai-vendor-guard** б'є в enterprise/OSS-документах (security-questionnaire «які AI-інструменти»). Пиши **роль** (`coding-agent` / `frontier-LLM`), не вендора.
6. **`.claude/**` сканується** на фантомні tracker-ID — тому **сам цей файл**, цитуючи `BIZ.22` чи `UNI.16`, мусить називати ID, що реально живуть у `00_07`.
7. **`00_07`-форма** (робота тут завжди торкається трекера): meta-рядок `**PN** · WHO · STAGE · → канон-реф` · перший рядок тіла — завжди `- **Стан:**` · чекбокси вертикально, і **чекбокс несе лише ВІДКРИТЕ** (закрита половина → `Стан` + git) · section-home: `#### ` під `## §07` мусить канон-рефити модуль 07.

## Як додати документ у concern-шар

1. **Куди:** `legal/` — право · `business/` — ринок і комерція · `procurement/` — вендори/RFQ · `research/` — сирі web-знімки · `outreach/` — «пакет → людина».
2. **Обов'язкова шапка** (форма ідентична в усіх наявних — скопіюй із сусіда): що це · **concern-шар, НЕ канон** · `⏳ Станом на <дата>` · **не юридична/податкова порада** · **дім стану** з ID айтема.
3. **Реєстрація:** рядок у власному реєстрі (`Артефакт | Про що | Канон-дім (правити там) | 00_07`). Новий рядок у `00_06 §2` **не потрібен** — клас уже зареєстрований.
4. **Стан** — айтемом у `00_07 §07`, не в самому документі.

## Verify

```
ruby scripts/docs_check.rb            # ~0.3с, без Rails; ті самі rake-тіла, що в CI
ruby scripts/protocols_ref_check.rb   # канон-рефи підшару + глибина ../
ruby scripts/code_tracker_id_check.rb # якщо правив .claude/** або код із tracker-ID
```
Перевіряй **exit-code**, не хвіст виводу. Мінімум після правки в `protocols/{legal,business}/` — перші два.

## Keep this skill bounded

Це **метод**. Сюди не накопичуються: *значення* (курси, ціни, payback) → канон `07_01`/`07_02`/`05_03` · *статуси й рішення* → `00_07 §07` · *профілі партнерів і план публікацій* → `07_03 §1`/`§2` · *історія кампаній і «чому»* → memory. Якщо кортить дописати сюди факт — він належить одному з тих домів, і саме ця дисципліна тут несуча: домен, у якому founder не перевірить мене сам, найменше пробачає впевнено написану неправду.
