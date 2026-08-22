# BIZ.9 — Carbon + Biodiversity Registry-Matrix (both/and-scope)

> **Що це:** порівняльна карта carbon- і biodiversity-реєстрів + метрологічна корекція SCC-наративу — робочий вхід для вибору реєстру та для розмови з незалежним carbon-методологом.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — BIZ.9.

---

> ## ⚠️ СТАТУС ДОКУМЕНТА: ORIENTATION-МАТРИЦЯ — НЕ юридична/фінансова порада, НЕ рішення про реєстр
>
> Це **порівняльна registry-matrix + метрологічна корекція** для BIZ.9. Призначення — дати founder'у карту вибору, а не зробити вибір: **вибір реєстру = ⚖️ founder**, після реального лісу + MRV-даних + (для UA) прямого запиту до нац-focal-point. Усі cost/timeline-числа — 🟡 **MEDIUM** (consultant/trade-press-оцінки, не офіційні прайс-листи реєстрів; ринок рухається поквартально). Перед реальним контрактом — юрист з carbon-law (особливо UA-частина §3).
>
> **Це 🤖-половина першого чекбокса BIZ.9** ([`00_07`](../../00_07_Action_Plan_Tracker.md) — «🤖+⚖️ порівняльна registry-matrix … → 🤖 складе, ⚖️ вибір»). 👤-половина = engagement методолога (~$50–100k) → PDD, gated на реальний ліс роки downstream.
>
> **Джерела:** [`R3_carbon_registries.md`](../research/R3_carbon_registries.md) (carbon, несучий metrology-gap) · [`R4_biodiversity_credits.md`](../research/R4_biodiversity_credits.md) (biodiversity both/and). **Канон:** [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md) (фін-константи, 2000 SCC = 1 tCO₂) + [`07_01 §2`](../../07_01_Nature_as_a_Service_Contracts.md) (Puro death-path) · [`02_06 §7`](../../02_06_Unit_Economics_and_BOM.md) (unit-economics; SCC = «Silken Carbon/**Condition** Coin») · [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.9 / BIZ.1 / ARCH.5 · дотично [`05_02`](../../05_02_Proof_of_Growth_Pipeline.md) (Proof-of-Growth), [`05_05 §3.2`](../../05_05_Slashing_and_Risk_Policy.md) (chainsaw_detected/SLASH-1), [`03_03`](../../03_03_TinyML_Acoustic_Inference.md) (TinyML 5-клас).
>
> **Легенда впевненості:** 🟢 висока (офіц. реєстр-док / ≥2 незалежні джерела) · 🟡 середня (одне якісне джерело / trade-press) · 🔴 низька (paywall / суперечливо / unknown).

---

## 0. Bottom-line наперед (перед деталями)

1. **🔴 НЕСУЧЕ: жоден реєстр — ні класичний, ні digital-native — НЕ приймає сирий фізіологічний/біоелектричний сигнал дерева як прямий carbon-quantification-вхід.** Усі forest-методології рахують tCO₂e через remote-sensing canopy-proxy (LiDAR/NDVI/Stocking Index) або алометрію DBH. Навіть найбільш «digital-native» реєстр (Isometric) рахує дерево через Pachama-супутник/LiDAR, **не** через дендрометр чи EBFC-сигнал у стовбурі. Це **той самий клас чесності, що «in-silico ≠ TRL 4»** — не поразка, а точна локалізація того, де наша цінність реальна (§1).
2. **SCC ≠ прямий carbon-credit.** Реальний трек ЗАРАЗ — не власний реєстр-мінт, а **«vetted MRV Data Service Provider»** (структурний аналог Sylvera/Kanop/Chloris у Verra VM0047) АБО **permanence/disturbance-monitoring шар** (`chainsaw_detected`/panic — реальна, диференційована цінність, якої remote-sensing не дає в real-time) поверх ЧУЖОГО вже-credited проєкту (§1.3, §6).
3. **Для лісового пілоту як проєкту:** **Isometric** — найкращий cost/timeline fit (buyer-pays, ~1 міс, CCP-eligible), АЛЕ потребує anchor-buyer наперед; **Gold Standard Microscale** (<10k tCO₂e/рік) — найкращий fallback без buyer; **Verra** — buyer-recognition топ, але $100–300k+ / 2–3 роки (погано для solo pre-revenue) (§2).
4. **Double-count / Article 6 UA — найбільший відкритий невідомий, НЕ registry-специфіка.** UA прийняла Article-6 pilot 18.06.2026 + нацреєстр (forestry-пріоритет); NDC покриває 100% LULUCF → структурний double-count-ризик. **Прямий запит нац-focal-point (Міндовкілля), не web** (§3).
5. **Biodiversity (both/and) — co-benefit evidence ЗАРАЗ, не окремий SKU 2026.** Cercarbono/Savimbo ISBM = єдиний живий реєстр, що приймає звукозапис як доказ — але **species-level** (56 indicator species), а наш TinyML = 5-клас presence → gap. COP17 (Єреван, жовт-2026) = контрольна точка (§4).
6. **Репутаційно:** вести ARR/IFM + sensor-permanence-verification, **НЕ** REDD+ «повірте базовій лінії» (спалив Verra 2023). Carpathian illegal-logging = двосічний меч. UA-ліс 73% державний → пілот через держлісгосп (§5).

**Чи міняє metrology-gap SCC-наратив?** — **Так, суттєво.** Коротко: SCC — це **Condition/homeostasis-токен (Proof-of-Growth)**, а не сертифікований tCO₂e; on-chain «2000 SCC = 1 tCO₂» = внутрішня облікова конвенція, НЕ registry-визнаний кредит (дзеркало SSOT → [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md); правити там). Розгорнуто → §1.4 + §6.3.

---

## 1. 🔴 Метрологічний розрив (НЕСУЧА секція)

### 1.1 Твердження (cross-registry, 🟢)

**Жоден реєстр не бере raw ground-сенсорний сигнал дерева як ПРЯМИЙ carbon-метрик.** Це не «поки що не наш реєстр» — це структурна властивість УСІХ forest-методологій станом на дослідження (R3 §0, §5):

| Реєстр / методологія | Як рахується tCO₂e | Ground-фізіологічний сигнал як прямий вхід? |
|---|---|---|
| Verra VM0047 (ARR) | Stocking Index — remote-sensing проксі (NDVI Landsat + canopy-height LiDAR) | ❌ Ні |
| Verra VM0045 (IFM) | Dynamic data-driven baselines (remote sensing) | ❌ Ні |
| Isometric Reforestation (Pachama) | AI+LiDAR canopy-height, dynamic baseline | ❌ Ні — теж remote sensing |
| Gold Standard ARR / LUF | Алометрія DBH + remote sensing | ❌ Ні |
| Cercarbono CM-LU-002 | Dynamic baselines через GIS/remote sensing | ❌ Ні |

Навіть найбільш MRV-first-реєстр (Isometric, побудований з нуля навколо континуальної верифікації) рахує дерево через супутник/LiDAR-проксі. **Найближчий структурний аналог для нашої технології — роль vetted DSP (як Sylvera/Kanop/Chloris постачають Stocking-Index-дані у VM0047), а не заміна методології.**

### 1.2 Це той самий honesty-клас, що «in-silico ≠ TRL 4»

Сенсор вимірює **гомеостаз/приріст-проксі** (Lorenz-DCI + `growth_points` = метаболічна `m(delta_t)`), не **поглинений вуглець**. Кореляція `growth_points` → фактичний приріст біомаси, валідована проти destructive sampling або стандартних алометричних моделей — це **окремий, багаторічний науковий проєкт**, аналогічний за суворістю до EBFC in-silico→TRL 4. «Сенсор бреше про carbon, поки калібрація не доведена» — рівно та сама дисципліна, що вже прошита в CLAUDE.md §4 («чесність про залізо: … in-silico ≠ TRL»). Не змішувати цей шлях із критичним шляхом пілоту.

### 1.3 Реальний трек: DSP / permanence-monitor, не реєстр-мінт

Два життєздатні позиціювання, обидва **обходять** metrology-gap (продаємо моніторинг-дані/permanence, а не carbon-quantification):

**(A) MRV-Data Service Provider** — структурний аналог Sylvera/Kanop/Chloris Geospatial для VM0047.
- ⚠️ Нюанс чесності: наявні vetted DSP постачають *remote-sensing* (Stocking Index). Наш диференціал — *ground-truth continuous* дані, **комплементарні** до супутника, не drop-in-заміна DSP. Це **новий шар даних**, а не готова DSP-вакансія. Позиціювання: «continuous ground-truth поверх вашого remote-sensing baseline».

**(B) Permanence / disturbance-monitoring шар** — `chainsaw_detected` / panic-flag.
- **Це найсильніший чесний value-prop.** Continuous permanence-monitoring — рівно те, чого remote-sensing НЕ дає: супутникові прольоти періодичні; подія бензопили між прольотами невидима до наступного знімка. Наш real-time acoustic-тригер закриває саме цю сліпу пляму.
- Реальна, вже-shipped спроможність: `chainsaw_detected` живе у firmware/telemetry (SLASH-1, [`05_05 §3.2`](../../05_05_Slashing_and_Risk_Policy.md) — справжня пилка = panic→`chainsaw_detected`), не гіпотеза.

**Технічний registry-integration-surface уже доведений:** `PuroEarth::PassportService`/`PuroEarth::RegistryApiService` (`[MAINNET READY]`, ARCH.5) — transform → canonical JSON → SHA-256 → on-chain anchor → IPFS → REST submit. Тобто плагін у ЧУЖИЙ реєстр = **format-адаптери × N поверх доведеного патерну**, не greenfield. Твердий гейт — не код, а BIZ.9-методолог (methodology-ID) + institutional buyer.

### 1.4 🔴 Що це означає для SCC-наративу (пряма відповідь)

Поточний канон фузить ДВА твердження в SCC:

| Прочитання | Твердження | Метрологічний статус |
|---|---|---|
| **«Condition Coin»** | SCC підтверджує гомеостаз дерева (Proof-of-Growth) | ✅ **Захищене** — це те, що сенсор реально вимірює |
| **«Carbon Coin»** | 1 SCC = 0.5 kg поглиненого CO₂ (2000 SCC = 1 tCO₂ — дзеркало SSOT → [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md)) | ⚠️ **НЕ registry-визнане** — flat ratio = внутрішня облікова конвенція |

**Наратив-зсув (honesty-корекція):**

1. SCC — насамперед **Condition/homeostasis-токен**. Це прочитання **вже латентне в каноні** ([`02_06 §7`](../../02_06_Unit_Economics_and_BOM.md): «SCC (Silken Carbon/**Condition** Coin)») — треба на нього спертися, а не на «Carbon» половину.
2. On-chain «2000 SCC = 1 tCO₂» (BIZ.1, `ProtocolParameters.sol#sccPerTonneCo2()`; дім → [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md)) — **внутрішня облікова конвенція**, НЕ заява, що 1 SCC = визнаний реєстром 0.5 kg tCO₂e-кредит. Продати його institutional-buyer'у як останнє **без** registry-approved методології = рівно той unbacked-baseline-claim, що спалив Verra REDD+ 2023.
3. Шлях SCC → продаваний carbon-credit — **не «сертифікувати наше число»**, а **репозиціювання** у (A) MRV-data-provider або (B) permanence-monitor поверх чужого credited-проєкту. Прямий SCC-мінт-як-carbon-credit — **поза столом** за поточного registry-ландшафту.
4. Це **НЕ применшує платформу** — коректно локалізує цінність SCC (continuous ground-truth condition + real-time permanence) там, де remote-sensing-реєстри сліпі = диференційована цінність.

> ✅ **Канонізовано — різницю зроблено explicit (2026-07-24).** На момент написання чернетки канон подавав «2000 SCC = 1 tCO₂» просто як `✅ done`, і зробити явною різницю «внутрішня конвенція ≠ продаваний кредит» було лише **кандидатом** на ssot-задачу. Її **закрито в обох домах**: [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md) (рядок `[BIZ.1]`) тепер прямо каже «**внутрішня облікова конвенція** Proof-of-Growth (Condition-прочитання), НЕ registry-визнаний tCO₂e-кредит: продаваний кредит лише через незалежну методологію (BIZ.9); трек = MRV-Data-Provider/permanence-monitor», а [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md) несе те саме застереження у деривації `MAX_SUPPLY`. Metrology-gap ніколи не суперечив BIZ.1 («методологічна сертифікація post-TRL 7 тримає BIZ.9») — він **розширював природу розриву**: це репозиціювання, не аудит числа, і саме це тепер сказано в каноні. Ця секція — дзеркало канону, не другий дім.

---

## 2. Carbon-registry матриця

> Читати крізь лінзу §1: матриця = «у ЯКИЙ реєстр плагінитись даними / під ЯКИЙ реєстр вести пілот», **не** «яким реєстром стати». Cost/timeline = 🟡 MEDIUM (R3 §0).

| Реєстр | Методологія-fit | Cost (до 1-го issuance) | Timeline | dMRV-readiness | CCP-eligible | Інституц-довіра | Fit для SilkenNet |
|---|---|---|---|---|---|---|---|
| **Verra (VCS)** | VM0047 ARR ✅ / VM0045 IFM ✅ / VM0048 REDD+ ⚠️ (уникати) | $150–300k+ (validation $30–100k + verif $5k/цикл + registry 3–8% + monitoring $10–50k/рік) 🟡 | 12–18 міс валідація, **2–3 роки** до 1-го issuance; crediting 20–40 р 🟡 | Retrofit: Stocking Index + vetted DSP (Sylvera/Kanop/Chloris, 2025) + Forest Carbon Tech WG | ✅ Так | Найвища (98% ринку), але **scandal-scarred**, rebuild триває | Buyer-recognition топ; cost/timeline **погано** для solo pre-revenue → «якщо фінансування/партнер» |
| **Gold Standard** (full) | ARR/AR + LUF smallholder | ~$20k VVB-сертифікація + PDD окремо 🟡 | Порівнювано з Verra (full-scale) | Наявний, менш агресивний dMRV-push | ✅ Так | Висока, особливо SDG/co-benefit buyers | SDG-premium-трек; солідна альтернатива Verra |
| **GS Microscale** (<10k tCO₂e/рік) | ARR/LUF, спрощена **self-verification** замість повного VVB-циклу | Суттєво дешевше (внутрішня V/V) 🟡 | Швидше за full-scale | Як GS-parent | ✅ (через GS-parent) | Висока (GS-бренд) | ⭐ **Найкращий fallback без anchor-buyer** для малого пілоту |
| **Isometric** | Reforestation v1.0→1.2 (Pachama LiDAR/AI canopy-height, dynamic baseline) | **Buyer платить** (per-tonne $30→$3/t за обсягом); near-zero upfront для supplier 🟡 | **~1 міс** verification cycle, continuous tonne-by-tonne, без batching | **Найкращий** (MRV-first з нуля) — та все ж canopy-height/LiDAR, не ground | ✅ Так | Швидко зростає; молодий track record у reforestation | ⭐ **Найкращий структурний fit — ЯКЩО anchor buyer наперед** |
| **Puro.earth** | ❌ **НЕМАЄ forestry/ARR** — лише engineered/durable (biochar, DACCS, ERW, BiCRS) | N/A для живого лісу | N/A | Puro dMRV Connect API (2025) | ✅ (durable-CDR) | Висока в durable-CDR ніші | ❌ **НЕ fit для живого лісу**; АЛЕ = **death-path** (biochar CORC, вже shipped, див. нижче) |
| **Rainbow** (ex-Riverse) | ❌ **7 методологій, усі industrial** (battery/biochar/ERW/biogas/e-waste); forestry немає | N/A | N/A | dMRV-first | ✅ (9-й CCP-eligible, бер-2026) | Висока для своєї ніші | ❌ **ВИКЛЮЧИТИ** — «engineered ≠ farming», afforestation excluded |
| **Cercarbono** | CM-LU-002 (reforestation+restoration+agroforestry, dynamic + GIS) | Заявлено дешевше за Verra (не перевірено) 🔴 | Порівнювано з Verra | GIS/remote sensing (та сама структура, не ground-native) | ❌ **НЕ в CCP-списку** | **Суттєво нижча** (no CCP → ESG-buyers дисконтують) | Радар, не primary; **АЛЕ** = єдиний biodiversity-реєстр з acoustic (§4) |
| **BioCarbon** | REDD v5.0 (лип-2025) — REDD-focus ⚠️ | Не знайдено 🔴 | Не знайдено 🔴 | Заявлений dMRV-фокус (деталі не дослідж.) | ❌ Не в CCP-списку | Нижча (no CCP) | Deep-dive якщо серйозно; REDD-focus = репутаційно ризикова категорія |

### 2.1 Три реєстри, що варті деталі

- **Isometric** — buyer платить за верифікацію (не supplier) → вирівнює стимули, прибирає структурний over-credit. Реєстр сам призначає VVB. Continuous tonne-by-tonne. **Chicken-and-egg:** cost-перевага реалізується ЛИШЕ якщо anchor-buyer уже вірить у проєкт (класична пастка pre-revenue).
- **GS Microscale** — спрощена self-verification для <10k tCO₂e/рік. Прямий структурний fallback для малого UA-пілоту, доки не переросте поріг. Менший upfront cash-burn.
- **Verra** — «розробник володіє кредитами й продає будь-кому» без anchor-buyer, ціною $100k+ upfront + 2–3 роки. Тримати як опцію «за зовнішнього фінансування».

### 2.2 Puro.earth — важлива both/and-корекція (death-path, не living-carbon)

Puro **НЕ покриває** живий-ліс ARR/IFM — це engineered/durable-CDR стандарт. **АЛЕ** у SilkenNet Puro вже живе на ІНШОМУ треку: коли дерево вмирає біологічно (`Tree.status = :deceased`), `PuroEarthPassportWorker` генерує **biochar CORC** на Puro.earth ([`07_01 §2`](../../07_01_Nature_as_a_Service_Contracts.md), рядок «Смерть дерева»). Тобто:
- Живий ліс (carbon-sink, поглинання) → Verra/GS/Isometric-клас (§2, з metrology-gap §1).
- Мертве дерево → biochar → Puro CORC (durable removal, вже `[MAINNET READY]`).
Це **не конфлікт, а два різні продукти** з одного лісу. Puro-експорт — уже доведений патерн (ARCH.5), що обслуговує лише death-path.

---

## 3. Double-counting / Article 6 — Україна

> **Найважливіший ЄДИНИЙ відкритий невідомий пункт для будь-якого реального продажу UA-лісових кредитів. Це НЕ registry-специфіка — це system-level blocker, який web-ресьорч не закриє.** (R3 §3)

### 3.1 Структурний ризик (🟢)

- **UA NDC покриває 100% секторів включно з LULUCF** (ціль −65% до 2030 vs 1990). → Лісовий carbon-sink України **вже всередині** націнвентаря. Будь-який forest-removal, проданий як міжнародний voluntary offset, — **prima facie double-count-кандидат** проти власного NDC, якщо не carve-outed/adjusted. (Загальний ризик усіх Сторін з LULUCF-inclusive NDC, але реальний і застосовний тут.)

### 3.2 Свіжий розвиток (🟡/🔴)

- **UA прийняла Article-6 pilot framework 18.06.2026** (дворічний; процедури authorization/issuance/transfer + правила нацреєстру). **Forestry — явно пріоритетний сектор.**
- 🔴 **Невідомо:** чи вимагатиме framework authorization і для **чисто voluntary** (не-Стаття-6) кредитів — Carbon Pulse-деталі за paywall. Дата (18.06.2026) = ~5 тижнів до дослідження → деталі ще уточнюватимуться.
- Окремий compliance-трек: **ETS pilot** стартує 2026 (другий шар нацобліку).
- Прецедент **host-country authorization creep** (Zimbabwe 2023: revenue-share навіть над voluntary-продажем) → приймаючі країни дедалі частіше трактують ВЕСЬ carbon-export як такий, що потребує держ-sign-off.

### 3.3 Дія (⚖️/👤)

- ⚖️ **Прямий запит до нац-focal-point** (Міндовкілля / профільний департамент нацреєстру): чи потрібна authorization для VCM (не-Стаття-6) кредитів + чи прийматимуть покупці кредити без corresponding adjustment. **Не web-ресьорч.**
- Не хардкодити припущення в архітектуру/бізнес-план до з'ясування.

---

## 4. Biodiversity-вісь (both/and — 2-й D-MRV-вимір ПОВЕРХ carbon)

> **Both/and, не або/або (E.59):** biodiversity = другий вимір **поверх** carbon, не заміна. Зараз — **co-benefit evidence**, не окремий продаваний SKU 2026. (R4)

### 4.1 Стан ринку — carbon-ринок ~2008 (🟡)

Biodiversity-credit-ринок структурно ідентичний ранньому voluntary carbon: оцінки розміру 2025 розходяться **$0.09B–$7.1B (80×!)** — сам розкид = найчесніший індикатор незрілості. Royal Society (серп-2025): навіть 11 найбільших постачальників у середньому 2/3 за IAPB-критеріями, найслабше — **незалежність верифікації**. Biodiversity **не commensurable** за конструкцією (на відміну від tCO₂e) — структурна, не тимчасова відмінність.

### 4.2 Acoustic-канал: Cercarbono/Savimbo ISBM (🟢)

**Єдиний живий реєстр, що explicitly приймає звукозапис** як доказовий канал (перші кредити вер-2024). АЛЕ:
- Звук = один з трьох рівноправних non-invasive каналів (відео/фото/аудіо) для **присутності indicator species** — **НЕ** континуальний acoustic-index.
- **Species-level (56 indicator species).** Наш TinyML = **5-клас presence** (fauna/silence/wind/chainsaw, [`03_03`](../../03_03_TinyML_Acoustic_Inference.md)) → **gap: ISBM вимагає видо-специфічну присутність, не родову «є фауна чи ні».**
- Явно voluntary-only: «can never be used to provide offsets of any kind».

### 4.3 Ключове наукове застереження (🟢, Bell & Malerba 2025)

PAM (passive acoustic monitoring) дав ~70× детекцій за найнижчу вартість/вид — **АЛЕ покриває ЛИШЕ вокалізуючі таксони** (птахи/амфібії): не рослини, більшість безхребетних, немі ссавці, бентос. → **Acoustic-only `biodiversity_score` структурно неповний.** Не over-claim'ити повне біорізноманіття — це proxy для конкретної (переважно птахо-амфібійної) під-навіски.

### 4.4 Чому acoustic ПІДСИЛЮЄ carbon-наратив (Delgado 2026, 🟢)

Супутник показує canopy cover, але **не показує, чи ліс ФУНКЦІОНУЄ**. Soundscape ловить *функцію*: регенеровані ліси звучали ближче до mature forest, ніж до деградованих пасовищ. → Acoustic-шар **прямо підсилює довіру до Proof-of-Growth carbon-клейму** як co-benefit evidence (за зразком «sound proves forest function, satellite тільки покриття»). Це ж — аргумент permanence-monitor'а §1.3(B).

### 4.5 Stacking (carbon + biodiversity на одній ділянці)

Дозволено «на папері», майже без живих прикладів (🟡):

| Юрисдикція | Позиція | Умова |
|---|---|---|
| Plan Vivo | ✅ Explicitly | Лише в межах власного стандарту (PV Nature + PV Climate); interoperability ще не жива |
| Biodiversity Credit Alliance | ✅ «Yes, if additionality met» | Форвардна guidance (не фінальний протокол) |
| UK | ✅ Частково | BNG ↔ nutrient markets |
| Australia | ❌ Нац-бан / ✅ окремі штати | Cassowary Credits (штат) дозволяє carbon+bio |

**Double-counting = ризик №1 всюди.** Практичних живих carbon+biodiversity-stacking-прикладів (крім Plan-Vivo-внутрішнього + Australia-Cassowary) не знайдено.

### 4.6 Контрольна точка

**COP17 (Єреван, 19–30 жовт-2026)** = midpoint GBF; biodiversity credits прогнозовано «from specialized concept to central pillar». Природна точка переоцінки цього дослідження за ~3 міс. ISSB Exposure Draft (nature-disclosure) теж до COP17.

> **Biodiversity bottom-line:** far-horizon 2-й revenue-стрім зі значним «але» (кредити вже видаються, венчур тече, TNFD тисне попит-side). **Вхід ЗАРАЗ = co-benefit evidence поверх carbon** (не окремий SKU). Cercarbono/Savimbo — на радар, але **тільки якщо/коли TinyML розшириться за 5-клас до species-level** (gated на labeled dataset — UNI.13a-клас master-key).

---

## 5. Репутаційна стратегія меседжу

> Continuous per-tree телеметрія — саме такий доказ, що МІГ БИ відновити довіру в forest-carbon, ЯКЩО metrology-gap (§1) закрито І наратив ведеться правильно.

- **Вести ARR (новий приріст) / IFM (покращене управління) + sensor-permanence-verification.** НЕ REDD+ (avoided deforestation).
- **Чому не REDD+:** саме ця категорія спалила Verra 2023 (>90% rainforest-офсетів «безцінні»; VCM впав −61%). Слабкість REDD+ = counterfactual/baseline-проблема («що було б вирубано без проєкту», майже нефальсифіковна). ARR/IFM з hard sensor telemetry = **структурно протилежний ризик-профіль**.
- **Carpathian illegal-logging (~1.4M м³/рік) = двосічний меч:**
  - Актив: виправдовує `chainsaw_detected` permanence value-add.
  - Ризик: структурно нагадує «наша базова лінія припускає масову нелегальну вирубку, яку проєкт запобігає» — рівно той наратив, що рейтингові агенції/репортери тепер натреновані підозрювати.
  - **Тримати два меседжі ОКРЕМО** в кожному pitch-документі.
- **Рекомендація:** вести disturbance-detection/permanence як **verification-enhancement поверх чужої вже-credited baseline**, НЕ як власний additionality-аргумент — доки немає довшого моніторингового track-record. (Це = §1.3(B), і воно ж природно уникає REDD+-пастки.)
- **Держлісгосп-шлях:** UA-ліс **73% державний** (<0.1% приватний) → реальний пілот потребує carbon/use-rights-угоди з держлісгоспом (SFE «Ліси України») чи регіональною владою, **не з приватним землевласником**. Governance/procurement-залежність, що **передує** вибору реєстру.
- **Війна-специфічний permanence-ризик** (UXO / conflict-access) — окремий фізичний ризик, який глобальні non-permanence tools **явно не моделюють**. Варта примітка в розмові з реєстром/страховиком про buffer-pool.

---

## 6. Bottom-line рекомендація

### 6.1 Трек ЗАРАЗ (pre-revenue, solo, TRL 3 anchor/EBFC)

**Позиціювання = MRV-Data-Provider / Permanence-Monitor, НЕ власний реєстр-мінт.** Це обходить metrology-gap повністю: продаємо continuous ground-truth моніторинг + real-time disturbance-detection (§1.3), а не carbon-quantification. Технічний surface доведений (Puro-патерн ARCH.5); гейт = методолог + buyer, не код.

### 6.2 Коли з'явиться buyer / реальний ліс (⚖️ founder-вибір реєстру)

| Ситуація | Рекомендований реєстр | Чому |
|---|---|---|
| Anchor-buyer готовий комітитись наперед | **Isometric** | buyer-pays, ~1 міс, continuous, CCP-eligible, reforestation-протокол+Pachama baseline готові |
| Малий пілот (<10k tCO₂e/рік), buyer ще нема | **GS Microscale** | спрощена self-verification, менший cash-burn |
| Є зовнішнє фінансування/партнер, треба max recognition | **Verra** (ARR/IFM, НЕ REDD+) | 98% ринку, CCP; ціною $100k+ / 2–3 роки |
| Death-path (мертве дерево → biochar) | **Puro.earth** | вже `[MAINNET READY]`, окремий продукт |
| — | ❌ Rainbow (no forestry) · ⚠️ Cercarbono/BioCarbon (no CCP → низька інституц-довіра) | тримати на радарі, не primary |

### 6.3 Що це означає для SCC-наративу (стисло)

- SCC = **Condition/Proof-of-Growth-токен** (homeostasis), не сертифікований tCO₂e. Спертися на «Condition Coin»-прочитання (вже в каноні [`02_06 §7`](../../02_06_Unit_Economics_and_BOM.md)).
- «2000 SCC = 1 tCO₂» on-chain = **внутрішня облікова конвенція**, не продаваний реєстром кредит (дзеркало SSOT → [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md); правити там). Не продавати як останнє без methodology-ID.
- Carbon-credit-конверсія = **окремий, downstream, methodology-gated науковий проєкт** (калібрація growth_points ↔ біомаса), не критичний шлях пілоту.
- Це honesty-корекція класу «in-silico ≠ TRL 4» — **диференціює**, а не применшує: наша цінність (continuous ground-truth + real-time permanence) там, де remote-sensing-реєстри сліпі.
- ✅ Різницю «внутрішня конвенція ≠ продаваний кредит» **уже зроблено explicit у каноні** — [`07_01 §3`](../../07_01_Nature_as_a_Service_Contracts.md) (рядок `[BIZ.1]`) + [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md) (деривація `MAX_SUPPLY`). Тут — дзеркало, не другий дім (§1.4).

### 6.4 Наступні дії (не gold-plate)

1. ⚖️ **Прямий запит нац-focal-point** (Article-6 VCM-authorization, §3.3) — блокує будь-який реальний UA-продаж; найдешевша дія з найбільшим de-risk.
2. 👤 **Держлісгосп-контакт** (SFE «Ліси України» / регіон) — carbon/use-rights, передує реєстру (§5).
3. 👤 (коли є ліс+MRV+VVB, роки downstream) engagement методолога (~$50–100k) → PDD під обраний реєстр.
4. Тримати COP17 (жовт-2026) як точку переоцінки biodiversity-осі (§4.6).

---

## 7. Ключові невідомі / застереження (сумарно)

| # | Невідоме | Впевненість | Хто закриває |
|---|---|---|---|
| U1 | UA Article-6: чи потрібна authorization для voluntary-кредитів | 🔴 | ⚖️ прямий запит focal-point (не web) |
| U2 | Реальні cost/timeline реєстрів для UA-inc forest-профілю | 🟡 | 👤 quote від реєстру/консультанта |
| U3 | Чи прийме registry ground-sensor як **DSP-канал** (не quantification) | 🔴 (не досліджено з реєстром) | 👤 запит до Verra Forest Carbon Tech WG / Isometric |
| U4 | Species-level розширення TinyML для ISBM | 🟡 | gated на labeled dataset (UNI.13a-клас) |
| U5 | Cercarbono/BioCarbon реальна cost + CCP-траєкторія | 🔴 | deep-dive якщо стануть primary |

> **Загальний дисклеймер:** ринок carbon+biodiversity-реєстрів рухається поквартально (методології, fee-schedules, CCP-статуси, COP17). Числа тут = «порядок величини» для orientation, не committed-дані для контракту. Перед реальним рішенням — верифікація на первинному джерелі + carbon-law-юрист.
