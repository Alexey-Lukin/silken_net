# Enterprise B2B-Readiness — phase-gated план готовності (procurement · GDPR · SOC 2 / ISO 27001)

> **Що це:** gap-analysis enterprise-B2B-готовності (vendor-due-diligence, GDPR-стандарти поверх Privacy Policy, економіка атестацій) у рамці **phase-gated readiness-плану** — для founder'а та майбутнього compliance/юр-консультанта.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — живить BIZ.2 (MSA-DD-пакет) / BIZ.18 (SLA); GDPR-кластер = SEC.18 / SEC.23; страхування = BIZ.21; DR-drill = DR.1.

> **Статус:** DRAFT v0.1, 2026-07-24. Gap-analysis для планування, НЕ compliance-порада. Web-research станом на 2025–2026 (усі джерела — внизу, з датами). «Наш стан» — з прочитаних сиблінг-артефактів пакета ([`msa_skeleton`](../legal/msa_skeleton.md) · [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) · [`sla_exhibit`](sla_exhibit.md) · [`eo_insurance_spec`](eo_insurance_spec.md) · [`entity_structure`](../legal/entity_structure.md)) + repo-канону ([`06_07`](../../06_07_CICD_and_Runbook_Index.md), [`00_00`](../../00_00_SSOT_Index.md)) — НЕ здогадки.
>
> **Контекст:** solo-founder, phase-1, **нічого не задеплоєно, нуль users, нуль revenue**. Operational-vehicle = наявна UA-компанія, Дія.City-резидент, співзасновником якої є founder (тришар-присуд → [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) + [`entity_structure`](../legal/entity_structure.md)); IP/™ — на фізособі founder'а.
>
> **Guardrail документа: phase-aware, не gold-plate.** Більшість enterprise-вимог гейтяться подіями (перший live-деплой → перший enterprise-signing → scale), не календарем. Легенда фаз:
> - 🟢 **phase-1-мінімум** — треба ЗАРАЗ або строго ДО першого live-деплою (це наш найближчий реальний гейт, не enterprise-угода);
> - 🟡 **enterprise-signing-gate** — треба до/при підписанні першого B2B-enterprise контракту;
> - ⚪ **later-scale** — після revenue / на запит конкретного покупця / при рості.

---

## 0. Bottom-line (перед деталями)

1. **Зараз (phase-1, pre-deploy) купувати/аудитувати НІЧОГО не треба.** Жоден фреймворк (SOC 2, ISO 27001, pentest, страхування) не є «due» для solo pre-revenue без деплою. Це підтверджує і власний phase-gate у [`eo_insurance_spec`](eo_insurance_spec.md) §3.1: «юридично нічого не обов'язкове… нічого не купувати».
2. **Наш найближчий реальний compliance-гейт — не enterprise-підписання, а перший live-деплой**: GDPR-обов'язки (RoPA Art.30, DPIA Art.35 для anchor-geo, breach-72h процес, vendor-DPA ланцюг, SEC.23 Akash-рішення) вмикаються з першим реальним processing EU-даних, незалежно від того, чи є хоч один B2B-клієнт.
3. **Несподівано сильна сторона:** engineering-controls шар (OpenSSF Best Practices + Scorecard badges публічні, 8 required branch-protection gates, CodeQL, secret-scanning+push-protection, SHA-pinned supply-chain, Sigstore SLSA provenance + SBOM, Trivy IaC, SECURITY.md, Sentry `send_default_pii=false`, Argon2id, AR-encryption at-rest — інвентар [`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md)) — це верифіковані *технічні* контролі рівня, який більшість seed-стартапів не має. **Слабка сторона:** enterprise-procurement питає *папір* (атестація, written policies, CoI, DPA), а не git-репозиторій — цей шар у нас майже порожній, і це нормально для фази.
4. **Operational-vehicle закриває financial-DD майже безкоштовно:** наявна UA-компанія з багаторічною операційною історією + Дія.City-резидентство (= щорічний обов'язковий compliance-аудит УЖЕ існує) — це готова відповідь на «audited financials + business standing», де чистий новостворений стартап-vehicle провалював би DD.
5. **SOC 2 Type II — НЕ зараз і, ймовірно, не при першому підписанні.** Ринкова практика 2025-26: перші enterprise-угоди закриваються через security-questionnaire (SIG Lite/CAIQ) + trust-page + roadmap-letter («Type I через N міс»); повний Type II = $20–35k+ перший рік + 6–12 міс — тригериться першим покупцем, що ставить його hard-gate, не наперед.

---

## 1. Research-блок A: що enterprise вимагає від SaaS/data-vendor ПЕРЕД підписанням

Зведення з vendor-due-diligence практики 2025-26 (Panorays, Peony 6-domain framework, Sprinto, Mitratech, CT Acquisitions — див. Джерела):

| Вимога | Роль у процесі | Hard-gate signing чи nice-to-have? (ринкова практика) |
|---|---|---|
| **Security-questionnaire** (SIG Lite ~150 питань / SIG Full 1000+ / CAIQ ~17 cloud-доменів / VSA / custom Excel) | Надсилається при onboarding, ДО підписання | 🔴 **Де-факто hard-gate** — це сам механізм DD; відповісти доведеться завжди. SOC 2/ISO «закриває більшість питань автоматично», але їх відсутність ≠ автоматичний fail — заповнений questionnaire + пояснені контролі проходить у mid-market і частині enterprise |
| **SOC 2 Type II** (US-покупці) / **ISO 27001** (EU/global) | Атестація/сертифікат контролів | 🟠 **Залежить від покупця**: у US-enterprise «many refuse to proceed until valid SOC 2»; у mid-market і early-adopter угодах — negotiable через questionnaire+roadmap. EU/global enterprise частіше вимагають ISO 27001. Для «critical vendor»-класифікації — практично hard |
| **DPA (Art.28)** — якщо vendor обробляє PII покупця | Юр-додаток до MSA | 🔴 **Hard-gate**, якщо PII є (у нас: акаунти співробітників клієнта в дашборді = є). Стандартний, дешевий — template-робота юриста |
| **Certificate of Insurance** (Cyber, E&O, GL) | Signing-exhibit | 🔴 **Hard-gate у більшості enterprise-MSA** («required before signing commercial contracts, issuing COI» — [`eo_insurance_spec`](eo_insurance_spec.md) §2); просять «by name», часто поруч із SOC2-запитом |
| **SLA** | Exhibit до MSA | 🔴 **Hard-gate** — enterprise не підписує без availability-зобов'язань і remedies |
| **Financial due-diligence** (audited financials, credit, business standing) | Оцінка виживання vendor'а | 🟠 Стандартний запит для critical vendors; для стартапів часто заміняється funding-історією/материнською компанією |
| **Business-continuity / DR-plan** | «Must exist AND be tested, not just documented» | 🟠 Питається в questionnaire завжди; «tested» (drill-докази) — вимога для critical-tier |
| **Penetration-test report** (summary) | Технічна перевірка | 🟡 **Nice-to-have → hard лише для high-risk/critical-tier vendors**; «for higher-risk vendors you may also review pen test results» |
| **Sub-processor list** | GDPR-прозорість | 🟠 Стандартний запит privacy-office покупця; hard, якщо покупець EU |
| **Incident-response plan** | Питання questionnaire | 🟡 Written-policy рівень; для critical vendors — показати документ |

**Ключовий патерн для нас:** трійка «DPA + CoI + SLA» — це те, що юридично гейтить сам підпис MSA (наш MSA-каркас це вже знає: [`msa_skeleton`](../legal/msa_skeleton.md) Exhibit B/E/A відповідно). Атестації (SOC 2/ISO) і pentest — гейтять *залежно від покупця й tier-класифікації*, і для першого пілота майже завжди обходяться questionnaire-шляхом.

---

## 2. Research-блок B: GDPR full-compliance поверх Privacy Policy

Що ВЖЕ покрито нашим [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) (Privacy Policy + DPA-нота): controller/processor-мапа (§D.1), субпроцесор-реєстр (§D.3), SCC-2021 transfer-механізм (§B.10), DPO-assessment (§B.13 — правильний висновок «не потрібен»), Art.27-статус чесно TBD (§B.12), retention чесно «не формалізовано» (§B.8, SEC.18), DSAR-права з ручним виконанням (§B.9). Нижче — те, що *поверх* цього.

### 2.1 RoPA — Records of Processing Activities (Art.30)

- **Що це:** внутрішній реєстр усіх processing-активностей (мета, категорії даних/суб'єктів, отримувачі, transfers, retention, security-заходи). Показується наглядовому органу на запит.
- **«Виняток <250 працівників» нам НЕ допомагає:** виняток діє лише якщо processing «occasional» + без ризику + без special categories. Будь-який SaaS зі сталими user-акаунтами = «not occasional» → RoPA обов'язковий навіть для 1-особової компанії (консенсус джерел: GDPRLedger, Legiscope, DPO Consulting, 2025-26).
- **Тригер для нас:** перший реальний processing (= live-деплой з users), не enterprise-угода.
- **Наш стан:** ✅ окремий RoPA **існує** — [`ropa_art30.md`](../legal/ropa_art30.md) (Art.30-структура, побудована прямим проходом по коду, а не переформатуванням). ⚠️ Тут до 2026-08-28 стояло «окремого RoPA нема … 🤖-робота на годину-дві»: рядок пережив власний предмет і читався як **наявна робота**, тобто протухла клітинка readiness-таблиці давала читачеві хибний ХІД, а не лише хибний факт. 🔑 Побічний вихід того проходу вартий більше за сам RoPA: побудова знайшла **три процесори, відсутні в реєстрі субпроцесорів** — тобто «переформатувати наявне» було б замало за побудовою, бо джерелом істини тут є код, а не сусідній документ ([`ropa_art30.md`](../legal/ropa_art30.md) §6).
- **Enterprise-хвіст:** privacy-office покупця в questionnaire питає «do you maintain a RoPA?» — готовий документ = ще одна безкоштовна галочка.

### 2.2 DPIA — Data Protection Impact Assessment (Art.35) — **прямий мапінг на anchor-geo**

- **Коли обов'язковий:** processing «likely high risk»; EDPB WP248 дає 9 критеріїв — **2+ критеріїв = DPIA required** (усталена позиція EDPB, endorsed 2018, чинна).
- **Наш anchor-geo кейс (red-flag 3 з `b2c_tos_privacy` §🔴3: `Tree.latitude/longitude` + `Cluster.geo_boundary` + кадастр → пере-ідентифікація власника ділянки) збирає ЩОНАЙМЕНШЕ ТРИ критерії:**
  1. *location data / data of highly personal nature* (гранулярна geo ділянки);
  2. *systematic monitoring* (безперервний D-MRV-моніторинг — сама суть продукту);
  3. *innovative use of technology* (bio-IoT сенсорика + blockchain — класичний «innovative tech» у розумінні WP248);
  4. (при масштабі — ще й *large scale*).
- **Висновок research'у:** формально це **high-risk processing, що вимагає DPIA ДО початку обробки** — тобто до першого live-деплою з реальними EU-власниками ділянок, а не «колись потім». Важливий нюанс EDPB: сенсорні IoT-дані *самі по собі* (один критерій) DPIA не тригерять — тригерить саме **комбінація** з location+monitoring, що в нас і є.
- **Наш стан (оновлено 2026-08-21):** ✅ DPIA **написано** — [`dpia_art35.md`](../legal/dpia_art35.md), структура Art.35(7)(a)–(d), ризики R1–R9 виведені з коду, заходи M1–M9. Підтвердилось, що це **self-executed структурований документ**, не зовнішній аудит — вартість = наш час. ⚠️ **Але «написано» ≠ «виконано»:** оцінка ЗАЛИШКОВОГО ризику й висновок про Art.36 (prior consultation) свідомо порожні — це юридична кваліфікація з процесуальним наслідком перед наглядовим органом, тож неподільно людська; доки §6 того документа порожній, обовʼязок Art.35 не закритий. 🔴 І головна знахідка самого DPIA міняє формулювання цього рядка: мітигація огрублення координат — не «те, що DPIA ймовірно призначить», а **виконання Art.5(1)(c)**, бо мета досяжна меншим втручанням; тобто поточна обробка непропорційна за замовчуванням у поверхнях, виданих за межі оператора ділянки (M1, gated [`ARCH.63`](../../00_07_Action_Plan_Tracker.md)).
- **Enterprise-хвіст:** ESG-покупець, чий portfolio включає дані малих landowners, спитає про це в privacy-DD; готовий DPIA = сильна відповідь.

### 2.3 Breach-notification 72h (Art.33/34)

- **Вимога:** нотифікація наглядового органу ≤72 год від виявлення breach (якщо ризик для суб'єктів); суб'єктам — «without undue delay» при high risk. Діє з першого EU-user.
- **Наш стан:** контрактні хуки вже є ([`sla_exhibit`](sla_exhibit.md) §6.3 pipe'ить PII-інциденти в DPA-строки; `b2c_tos_privacy` §D.1 фіксує обов'язок) — але **внутрішнього runbook'а нема**: хто детектить (Sentry/Grafana-алерти вже є), хто кваліфікує «ризик», куди подавати (наглядовий орган TBD у `b2c_tos_privacy` §B.18), шаблон нотифікації. Дім у трекері — SEC.18 (outbound breach-notification чекбокс). Для solo це 1-сторінковий runbook — дешево, робиться до live.

### 2.4 DPO (Art.37)

- **Коли обов'язковий:** public authority / систематичний моніторинг суб'єктів у великому масштабі як core-activity / large-scale special categories.
- **Наш стан:** ✅ **вже правильно вирішено** (`b2c_tos_privacy` §B.13): на phase-1 жоден тригер не виконаний, DPO не потрібен. Нюанс на майбутнє: «систематичний моніторинг» у нас — *дерев*, не *людей*; DPO-тригер дивиться на суб'єктів даних (людей), тож навіть при scale аргумент «не потрібен» тримається, доки людський моніторинг не стане core. Переглянути при великій EU-базі. Нічого не робити.

### 2.5 EU-representative (Art.27)

- **Вимога:** non-EU controller під Art.3(2) призначає представника в ЄС; виняток — «occasional, low-risk» processing (систематичні акаунти під нього не підпадають).
- **Ринок 2025-26:** сервісні провайдери €600–€2,400/рік типово; є від ~€19/міс (EDPO, DataRep, GDPR Local та ін.).
- **Наш стан:** TBD, чесно зафіксовано (`b2c_tos_privacy` §B.12) із правильною позою «призначимо до того, як EU-база стане нетривіальною». Тригер = перші реальні EU-users (або EU-enterprise клієнт, чий privacy-office це перевірить). Не зараз — але це найдешевший paper-fix у всьому списку, коли тригер настане.

### 2.6 Мапінг GDPR-стандартів на трекер-айтеми

| Трекер-айтем ([`00_07`](../../00_07_Action_Plan_Tracker.md)) | Який GDPR-стандарт торкається | Зв'язок |
|---|---|---|
| **SEC.23** — Rails САМ переїжджає на Akash (permissionless анонімні провайдери) + Alchemy RPC логує IP+wallet | **Art.28 (processor-контракт)** + Art.30 (RoPA мусить назвати processors) + Art.44+ (transfers) | Art.28 вимагає *named, законтрактованого* processor'а з письмовим DPA — permissionless-маркетплейс взаємозамінних анонімних хостів структурно це ламає (`b2c_tos_privacy` §D.3: «найслабша ланка»). **Рішення архітектурне, не paperwork**: (а) гео-фільтр Audited Attributes до GDPR-адекватних провайдерів + прямий контракт, або (б) PII-шар (Postgres/Redis/сесії) лишається на GCP (DPA click-accept існує), Akash — лише non-personal workload. Alchemy: IP+wallet = персональні дані (CJEU *Breyer*) → верифікувати DPA або замінити/прийняти ризик задокументовано. **Гейтить live-деплой PII на Akash; для enterprise-DD — це рядок субпроцесор-списку, який privacy-office покупця не пропустить** |
| **SEC.18** (чекбокс anchor-geo) — re-identification (`Tree.lat/lng` + `Cluster.geo_boundary` + кадастр) | **Art.35 (DPIA)** — прямий кандидат high-risk (див. §2.2: 3 з 9 EDPB-критеріїв) + Art.5(1)(c) minimisation | DPIA робиться ДО processing; його мітигації (огрублення geo у B2B-продукті / окрема lawful basis) закривають red-flag 3. Без DPIA перший live-деплой з EU-власниками = формальне порушення Art.35 |
| **SEC.18** (retention, DSAR-tooling, AnonymizeUserService) | Art.5(1)(e) storage limitation + Ch. III rights + Art.30 (retention-колонка RoPA) | Privacy Policy чесно каже «не формалізовано» — прийнятно на старті з ручним DSAR (30 днів Art.12(3)); RoPA-заповнення §2.1 змусить визначити retention-строки хоча б на папері |

---

## 3. Research-блок C: SOC 2 / ISO 27001 для solo-startup

| Вісь | SOC 2 Type II | ISO 27001 |
|---|---|---|
| **Що це** | Атестаційний ЗВІТ (AICPA Trust Services Criteria) про операційну ефективність контролів за період 3–12 міс; аудитор = CPA-фірма | СЕРТИФІКАТ (міжнародний стандарт ISMS); акредитований certification body, 3-річний цикл |
| **Хто вимагає** | US-enterprise procurement («reigns supreme» у США; часто відмова рухатись без valid SOC 2) | EU/global enterprise, регульовані сектори, держзакупівлі; «manufacturing, telecom, global enterprises часто мають ISO 27001 embedded у procurement» |
| **Вартість (small/solo, 2025-26)** | Realistic all-in перший рік $20–35k (Secureleap); bootstrapped DIY-мінімум $15–30k (StartupDefense); сам аудит від ~$7–15k (boutique CPA); + automation-платформа (Vanta/Drata/Sprinto) $8–30k/рік | Для <10-person SaaS на cloud + automation: від ~$7k за Stage 1+2 аудити (Secureleap); типово $10–50k all-in (Vanta/Scrut, 2025) |
| **Timeline** | 3–12 міс (3-міс observation window — популярний перший Type II; Type I — швидший point-in-time старт) | 4–9 міс типово |
| **Lighter-weight драбина (реальна ринкова практика)** | (1) **Trust-page/security-page** — самопублікація контролів (нуль $); (2) **CAIQ self-assessment → CSA STAR Level 1** — безкоштовний публічний listing; (3) **заповнений SIG Lite** під конкретного покупця; (4) **SOC 2 roadmap-letter** («Type I через N міс, Type II через M») — стандартний стартап-хід у переговорах; (5) **readiness-assessment без аудиту** ($5–15k) — лише коли перший реальний покупець уже питає; (6) automation-платформа заздалегідь збирає evidence, щоб коли настане час — observation window стартував одразу | Аналогічна драбина; self-assessment проти Annex A |
| **Вердикт для нас** | ⚪ **Не зараз.** Тригер = перший US-enterprise покупець із hard-gate. До того — драбина 1–4 (безкоштовна/дешева) | ⚪ **Не зараз.** Якщо перші покупці = EU industrial ESG (наш ймовірний профіль!) — при настанні тригера зважити ISO 27001 ПЕРШИМ замість SOC 2 (EU-procurement визнає його частіше), або дешевший спільний шлях: automation-платформа веде обидва фреймворки з одного evidence-набору |

**Чесна вилка для нашого профілю покупця:** «промислові ESG-покупці карбону, agri» — це скоріше EU/global corporates (ISO-світ), ніж US SaaS-procurement (SOC 2-світ). Тож дефолтна порада «стартап = SOC 2» для нас НЕ автоматична — рішення відкладається до профілю першого реального покупця, і це ще один аргумент нічого не купувати наперед.

---

## 4. Phase-gated readiness-план: вимога × фаза × поточний стан × дім у трекері

Рамка читання: це **план готовності**, не заповнений за нас questionnaire — кожен рядок = «що і НА ЯКІЙ фазі мусить бути готове → де ми зараз (verified проти артефактів/repo) → де це трекається». Жоден пункт не «прострочений»: через phase-gates (легенда в шапці) видно, що через 🟢-рядки гейтиться перший live-деплой, через 🟡 — перше enterprise-підписання, ⚪ — event-triggered.

| # | Вимога | Що конкретно вимагається | Фаза (коли стає due) | Поточний стан готовності (verified) | Дім у [`00_07`](../../00_07_Action_Plan_Tracker.md) |
|---|---|---|---|---|---|
| 1 | **Security-questionnaire readiness** (SIG Lite/CAIQ) | Заповнені відповіді на ~150+ питань про контролі | 🟡 | Заповненого ще нема; сирі відповіді сильні: [`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md) (8 required CI-gates, CodeQL, secret-scanning, SLSA provenance+SBOM, SHA-pinning, Scorecard weekly), Sentry `pii=false`, Argon2id, AR-encryption, KENOSIS-межі | — (пакет §5 п.9; живить BIZ.2-DD) |
| 2 | **SOC 2 Type II** | Атестація контролів за 3–12 міс, CPA-аудит | ⚪ (тригер = перший US-enterprise hard-gate; до того — trust-page/CAIQ/roadmap-letter) | Ще не стартовано (за фазою); engineering-controls є, paper-ISMS нема | — (buyer-triggered; драбина §3) |
| 3 | **ISO 27001** | Сертифікована ISMS | ⚪ (якщо перші покупці EU-corporate — розглянути ПЕРШИМ замість SOC 2) | Ще не стартовано (за фазою) | — (buyer-triggered; драбина §3) |
| 4 | **Written InfoSec policy-pack** (InfoSec Policy, Access Control, IR-plan, Change Mgmt) | Документи-політики, які питає кожен questionnaire | 🟡 (перший questionnaire змусить) | Як документів ще нема; фактичні контролі живуть у CI/коді/каноні ([`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md), [`06_04 §5`](../../06_04_Secrets_Checklist.md) secrets-runbooks) — політики генеруються з реального стану, не вигадуються | — (пакет §5 п.10) |
| 5 | **DPA до клієнта (Art.28)** — MSA Exhibit B | Письмовий processor-контракт для PII співробітників клієнта | 🟡 (юрист-template; дешево, бо мапа готова) | Каркас-hook є ([`msa_skeleton`](../legal/msa_skeleton.md) §B.10, Exhibit B «TBD скласти»); controller/processor-мапа готова (`b2c_tos_privacy` §D.1 — включно з правильним «D-MRV data-продукт = ми controller, DPA на нього не потрібен») | BIZ.2 |
| 6 | **Certificate of Insurance** — MSA Exhibit E | E&O + CGL (+Cyber) поліси, named coverage | 🟡 (купівля = signing-тригер) | Полісів нема; coverage-spec ГОТОВИЙ ([`eo_insurance_spec`](eo_insurance_spec.md): Tech E&O $1–2M перший → CGL+completed-ops перед першою інсталяцією → Cyber bundled, war-exclusion питання №1–5 для UA); юрисдикція страхувальника = operational-vehicle (UA) вже відома | BIZ.21 |
| 7 | **SLA-exhibit** | Availability-зобов'язання + credits + remedies | 🟡 (числа = після live) | ✅ **Template готовий повністю** ([`sla_exhibit`](sla_exhibit.md): tiers, credits, exclusions, claim-процедура) — лишились числа з перших live-SLO-вікон (свідомо, не лінь) | BIZ.18 |
| 8 | **Financial DD / business standing** | Audited financials, роки існування, credit | 🟢 (готово) | ✅ **Фактично закрито entity-присудом**: operational-vehicle = наявна UA-компанія + Дія.City-резидент → щорічний обов'язковий compliance-аудит УЖЕ існує ([`entity_structure`](../legal/entity_structure.md) §1.6); лишається підняти папери operational-vehicle при DD-запиті | BIZ.20 (присуд ухвалено) |
| 9 | **BC/DR-plan** («exist AND tested») | Документ + докази drill | 🟡 (перший drill + 1-pager для клієнта перед signing) | Runbooks існують ([`06_06 §5`](../../06_06_Disaster_Recovery_and_Backup.md): PITR restore, TF-state rollback, region rebuild) + RTO/RPO-цілі ([`06_06 §3`](../../06_06_Disaster_Recovery_and_Backup.md); `sla_exhibit` Додаток A — свідомо інформативні); **DR-drill ще НЕ проведено** — «documented, not tested»; `sla_exhibit` вже правильно забороняє контрактні RTO/RPO до drill | DR.1 (drill-чекбокс) |
| 10 | **Pentest-report** | Third-party pentest summary | ⚪ (лише якщо покупець класифікує нас critical-tier; $5–25k тоді) | Нема (за фазою); часткова компенсація = CodeQL+Brakeman+Slither/Aderyn/Halmos/Medusa (money-path) + публічний Scorecard | — (buyer-triggered) |
| 11 | **Sub-processor list** (публічний) | Реєстр + вікно заперечення | 🟡 (публікація разом із trust-page) | ✅ **Реєстр готовий** — [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) §D.3 (вендор × роль × дані × регіон × transfer-механізм × DPA-статус × confidence) + модель general authorization (§D.2); не опублікований (нема куди: сайту нема). ⚠️ **Поіменний склад тут навмисно НЕ дублюється — рахуй у домі:** до 2026-08-28 тут стояв перелік із шести вендорів, а реєстр уже ніс одинадцять, і розходження зростає з кожним новим зовнішнім сервісом. ⛔ Публікується **спрощена** версія (вендор / роль / регіон / transfer), без колонок DPA-статус і confidence — вони внутрішні (§0) | SEC.23 (реєстр-чекбокс; живить BIZ.3) |
| 12 | **RoPA (Art.30)** | Внутрішній реєстр processing-активностей; <250-виняток НЕ рятує (processing not occasional) | 🟢 (ДО першого live-деплою; 🤖-переформатування, нуль $) | ✅ **написано 2026-08-20 — [`ropa_art30.md`](../legal/ropa_art30.md)** (складено виведенням модель-за-моделлю з коду). ⚠️ Рядок казав «окремим документом ще нема» до 2026-08-27 — клас `DOC-T.91`: реєстр готовності старіє в бік ЗАНИЖЕННЯ, бо його пишуть один раз, а роботу закривають окремими комітами | SEC.18-кластер (data-subject compliance) |
| 13 | **DPIA (Art.35)** — **anchor-geo re-identification** | DPIA ДО high-risk processing; EDPB: 2+ з 9 критеріїв → у нас 3 (location data + systematic monitoring + innovative tech) | 🟢 (ДО першого live-processing EU-власників; self-executed, нуль $) | ✅ Написано 2026-08-21 — [`dpia_art35.md`](../legal/dpia_art35.md) (R1–R9 з джерелом у коді, заходи M1–M9). ⚠️ Залишковий ризик + Art.36 = 👤 (не закрито); мітигація огрублення geo не впроваджена й gated ARCH.63 | SEC.18 (DPIA-нога) |
| 14 | **Breach-notification 72h (Art.33)** | Внутрішній процес: детекція → кваліфікація → нотифікація ≤72h | 🟢 (1-pager runbook до live) | Контрактні хуки є (`sla_exhibit` §6.3, `b2c_tos_privacy` §D.1); ✅ **runbook написано 2026-08-23 — [`gdpr_runbook.md`](../legal/gdpr_runbook.md)** (breach + DSAR-процедура; строки Art.33/34 і Art.12(3) — зовнішні, тому й закривались до юрканалу); детекція-інфраструктура (Sentry/Grafana alerts) є. ⚠️ Рядок казав «ще нема» до 2026-08-27 — той самий `DOC-T.91` | SEC.18 (breach-notification чекбокс) |
| 15 | **DPO (Art.37)** | Лише при тригерах (public / large-scale monitoring людей / special categories) | 🟢 (дія = нічого) | ✅ **Вирішено правильно**: не потрібен (`b2c_tos_privacy` §B.13); переглянути при великій EU-базі | — (вирішено; дім аналізу = `b2c_tos_privacy` §B.13) |
| 16 | **EU-representative (Art.27)** | Представник у ЄС для non-EU controller | 🟡/⚪ (тригер = перші реальні EU-users або EU-enterprise DD) | TBD чесно (`b2c_tos_privacy` §B.12); ринок €600–2,400/рік — найдешевший fix у списку, коли тригер настане | — (тригер-gated; §2.5) |
| 17 | **Vendor-DPA ланцюг (Art.28 вгору)** | Підписані DPA ВІД наших processors | 🟢 (до live; GCP — найлегша дія) | Чеклист готовий — [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) §D.4: GCP = click-accept (найлегша дія, механізм публічний); решта = **verify напряму, не припускати**. ⚠️ Перелік цілей рахуй у домі: тут стояли чотири вендори, тоді як §D.4 уже називав удвічі більше — множина verify-цілей росте разом із реєстром §D.3, тож копія старіє в бік НЕДООЦІНКИ обсягу | SEC.23 (verify-чекбокс) |
| 18 | **SEC.23 — Akash × Art.28** | Named законтрактований processor для PII-workload | 🟢 (архітектурне рішення ДО live-PII-на-Akash: гео-фільтр+контракт АБО PII лишається на GCP, Akash = non-personal workload) | 🔴 **Найслабша GDPR-ланка** (`b2c_tos_privacy` §D.3): Rails цільово їде на Akash (`config/deploy.yml`), permissionless анонімні провайдери ≠ Art.28-processor; mainnet ще НЕ задіяний = вікно вирішити ДО | SEC.23 (placement-рішення) |
| 19 | **Trust-page / security-page** | Самообслуговування buyer-DD (SafeBase-патерн) | 🟡 (дешевий quick-win при першому pilot-розмові) | Сторінки ще нема; контент готовий і незвично сильний: OpenSSF Best Practices **silver** (earned 2026-06-25) + Scorecard badges ([`00_00`](../../00_00_SSOT_Index.md) — ПУБЛІЧНІ), SLSA provenance, SBOM, SECURITY.md — наші публічні badges = діфференціатор, який показують замість «trust me» | — (пакет §5 п.9) |
| 20 | **D&O** | Захист директорів | ⚪ (board/priced-раунд; НЕ B2B-запит) | Нема; свідомо відкладено ([`eo_insurance_spec`](eo_insurance_spec.md) §3.3) | BIZ.21 (свідомо deferred) |
| 21 | **Carbon project-level insurance** (Kita/Oka-типу) | Non-delivery/reversal cover | ⚪ (лише якщо registry/buyer вимагатиме) | Нема; methodology-gated ([`eo_insurance_spec`](eo_insurance_spec.md) §3.4) | BIZ.21 / BIZ.9-gated |

---

## 5. Prioritized enterprise-readiness checklist

### 🟢 Phase-1 / до першого live-деплою (усе — нуль грошей, 🤖-робота + 2 рішення)

Порядок = пріоритет. Це НЕ «зараз сідай і роби» — це «мусить бути зроблено до того, як перший EU-user/власник ділянки з'явиться в проді»; але 1–3 можна зробити 🤖 будь-коли, вони дешеві.

1. ~~**DPIA anchor-geo**~~ ✅ **написано 2026-08-21** ([`dpia_art35.md`](../legal/dpia_art35.md)) — залишається **👤-половина**: залишковий ризик по R1–R9 + висновок про Art.36. 🔴 Формулювання «нульова ціна закриття» протрималось рівно до написання й виявилось хибним у той бік, що коштує: машинна частина справді безкоштовна, але вона **не закриває обовʼязок** — а те, що закриває (кваліфікація залишкового ризику), гейтоване юр-каналом. Тобто діра не «найбільша з нульовою ціною», а найбільша з ЦІНОЮ В ЮРИСТІ.
2. **RoPA-скелет** (#12; SEC.18-кластер) — переформатувати `b2c_tos_privacy` §B.3+§D.3 в Art.30-структуру. Година-дві.
3. **Breach-72h runbook** (#14; дім SEC.18) — 1 сторінка: детекція (Sentry/Grafana) → кваліфікація → орган → шаблон.
4. **SEC.23-рішення** (#18) — ⚖️ founder+архітектура: PII-шар НЕ їде на Akash без Art.28-шляху (рекомендований дефолт: Postgres/Redis/сесії на GCP, Akash = non-personal compute). Зафіксувати рішення в каноні.
5. **Vendor-DPA ланцюг** (#17; SEC.23 👤-чекбокс, той самий захід) — GCP click-accept, решта verify напряму; **поіменну множину бери в** [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) §D.4, вона росте разом із реєстром §D.3.
6. Financial-DD (#8; BIZ.20) — дія = нічого (operational-vehicle готовий; знати, що це наша відповідь).

### 🟡 Enterprise-signing-gate (тригер = перший реальний B2B-pilot у переговорах)

7. **CoI-пакет** (#6; дім BIZ.21) — Tech E&O → CGL+completed-ops → Cyber, за готовим spec'ом [`eo_insurance_spec`](eo_insurance_spec.md) (брокер-intake checklist §6 вже написаний). Єдина суттєва ГРОШОВА позиція цієї фази (~$2–5k/рік сумарно за оцінками [`R6_insurance_dpa`](../research/R6_insurance_dpa.md)).
8. **DPA-template Exhibit B** (#5; живить BIZ.2) — юрист, на базі готової §D.1-мапи.
9. **SIG Lite/CAIQ self-assessment** (#1) + **trust-page** (#19) + публікація sub-processor list (#11) — один пакет «buyer-facing security». CAIQ → CSA STAR Level 1 listing = безкоштовно.
10. **InfoSec policy-pack** (#4) — згенерувати з фактичного стану ([`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md)/[`06_04 §5`](../../06_04_Secrets_Checklist.md) вже описують реальні контролі — політики пишуться «зверху» них, не вигадуються).
11. **DR-drill №1** (#9; дім DR.1) — виконати runbooks [`06_06 §5`](../../06_06_Disaster_Recovery_and_Backup.md) за drill-процедурою [`06_06 §6`](../../06_06_Disaster_Recovery_and_Backup.md), оформити 1-pager «BC/DR summary» — закриває drill-половину DR.1 (master-key-backup чекбокс — окремий, deploy-time) і знімає «documented, not tested».
12. **SLA-числа** (#7; дім BIZ.18) — з перших live-SLO-вікон (`sla_exhibit` Додаток C, checklist готовий).
13. **EU-rep** (#16) — якщо клієнт/users = EU (€600–2,400/рік).
14. **SOC 2 roadmap-letter** (#2) — ЯКЩО покупець питає атестацію: лист «Type I через N міс» + trust-page; НЕ купувати аудит наперед.

### ⚪ Later-scale (event-triggered, не календар)

15. **SOC 2 Type II АБО ISO 27001** (#2/#3) — при першому покупці з hard-gate; вибір за географією покупця (US → SOC 2; EU industrial/agri → ISO 27001 перший). Бюджет $20–35k+ / рік-цикл; стартувати з automation-платформи (Vanta/Drata/Sprinto), щоб observation window почався швидко.
16. **Pentest** (#10) — при critical-tier класифікації покупцем.
17. **D&O** (#20; BIZ.21) — board/раунд. **Carbon project-insurance** (#21; BIZ.21/BIZ.9) — registry/buyer-gated.

---

## 6. Що з цього треба ЗАРАЗ (пряма відповідь)

**Купувати/аудитувати — нічого.** Реальний «зараз»-список був чотирма безкоштовними артефактами; **три з них написані** (~~RoPA-скелет~~ [`ropa_art30.md`](../legal/ropa_art30.md) · ~~breach-runbook~~ [`gdpr_runbook.md`](../legal/gdpr_runbook.md) · ~~DPIA anchor-geo~~ [`dpia_art35.md`](../legal/dpia_art35.md)), відкритим лишається **SEC.23-рішення** (Akash) — воно ⚖️, не письмо. 🔴 **Урок, який ця трійка купила й через який рядок переписано:** «безкоштовний артефакт» міряв ЦІНУ ПИСЬМА, а не ціну ЗАКРИТТЯ — у всіх трьох документах найдорожче лишилось після тексту (retention-строки · форма erasure · залишковий ризик Art.36), і воно гейтоване юр-каналом. Тобто написання зняло не обовʼязок, а **невизначеність про те, що саме просити в юриста** — і це чесніша міра їхньої цінності. Вони й далі формально гейтяться першим live-деплоєм, а не сьогоднішньою датою. Все інше — signing-gate (CoI + DPA + questionnaire-пакет) або buyer-triggered (SOC 2/ISO/pentest). Наш найсильніший наявний актив для майбутнього DD — верифікована публічна security-posture (OpenSSF badges + SLSA + 8 CI-gates) + наявна Дія.City-компанія (operational-vehicle зі щорічним обов'язковим аудитом) як counterparty; наш найслабший — відсутність paper-шару (політики/атестації), що нормально для фази і закривається дешево, коли настане тригер.

---

## Джерела (web, 2025-26)

**Vendor-onboarding / questionnaires:**
- [Bitsight — CAIQ vs SIG](https://www.bitsight.com/blog/caiq-vs-sig-top-questionnaires-vendor-risk-assessment) · [Workstreet — CAIQ vs SIG](https://www.workstreet.com/blog/caiq-vs-sig) · [Sparrowgenie — SIG questionnaire](https://www.sparrowgenie.com/blog/sig-questionnaire) (2025)
- [Steerlab — Security questionnaire questions](https://www.steerlab.ai/blog/security-questionnaire-questions-examples) · [DevBrows — VSQ Response Playbook 2026](https://www.devbrows.com/blog/vendor-security-questionnaire-response-playbook-2026)
- [Panorays — Vendor DD checklist](https://panorays.com/blog/why-vendor-due-diligence-checklists-are-critically-important/) · [Peony — 6-domain DD framework 2026](https://www.peony.ink/blog/vendor-due-diligence-checklist) · [Sprinto — Vendor DD checklist](https://sprinto.com/blog/vendor-due-diligence-checklist/) · [Mitratech — Vendor DD](https://mitratech.com/resource-hub/blog/vendor-due-diligence/) · [CT Acquisitions — DD framework 2026](https://ctacquisitions.com/vendor-due-diligence-checklist/)
- [Conveyor — "All your vendors have a SOC 2"](https://www.conveyor.com/blog/all-your-vendors-have-a-soc-2-now-what)

**SOC 2 / ISO 27001 економіка:**
- [Secureleap — SOC 2 cost 2026](https://www.secureleap.tech/blog/soc-2-certification-cost) · [StartupDefense — SOC 2 costs breakdown](https://www.startupdefense.io/soc-2-costs-for-startups-complete-breakdown-and-budget-guide) · [Sprinto — SOC 2 cost](https://sprinto.com/blog/soc-2-compliance-cost/) · [Drata — SOC 2 audit cost](https://drata.com/learn/soc-2/cost) · [Thoropass — SOC 2 audit cost](https://www.thoropass.com/blog/soc-2-audit-cost-a-guide)
- [Vanta — ISO 27001 cost](https://www.vanta.com/collection/iso-27001/iso-27001-certification-cost) · [Scrut — ISO 27001 cost 2025](https://www.scrut.io/hub/iso-27001/iso-27001-certification-cost) · [Secureleap — ISO 27001 for startups 2025](https://www.secureleap.tech/blog/the-real-cost-of-iso-27001-certification-for-startups-in-2025) · [Rhymetec — ISO 27001 cost 2025](https://rhymetec.com/iso-27001-certification-cost-breakdown-2025/)
- [Security Boulevard — SOC 2 vs ISO 27001: which do enterprise customers care about (2026)](https://securityboulevard.com/2026/06/soc-2-vs-iso-27001-which-certification-do-enterprise-customers-really-care-about/) · [Secureframe — SOC 2 vs ISO 27001](https://secureframe.com/blog/soc-2-vs-iso-27001) · [Cherry Bekaert — key differences](https://www.cbh.com/insights/articles/iso-27001-vs-soc-2-key-differences-and-when-you-need-each/)
- [Juan Idrovo — SOC 2 alternatives for small companies](https://juanidrovo.com/blog/soc-2-alternatives-small-companies/) · [ComplyJet — Trust center software 2026](https://www.complyjet.com/blog/best-trust-center-software) · [Workstreet — SOC 2 for startups 2026](https://www.workstreet.com/blog/soc-2-for-startups)

**GDPR:**
- RoPA: [GDPRLedger — Art.30 guide](https://www.gdprledger.com/guides/records-of-processing-activities) · [Legiscope — RoPA template](https://www.legiscope.com/blog/ropa-template-records-of-processing.html) · [DPO Consulting — Art.30](https://www.dpo-consulting.com/blog/gdpr-article-30-guide) · [DPC Ireland — RoPA guidance (PDF)](https://www.dataprotection.ie/sites/default/files/uploads/2023-04/Records%20of%20Processing%20Activities%20(RoPA)%20under%20Article%2030%20GDPR.pdf) · [LegalPolicyGen — RoPA guide 2026](https://legalpolicygen.com/blog/gdpr-article-30-ropa-guide-2026)
- DPIA: [IAPP — what is/isn't subject to DPIA](https://iapp.org/news/a/what-is-and-what-isnt-subject-to-a-dpia-under-gdpr-an-update) · [European Commission — when DPIA required](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/obligations/when-data-protection-impact-assessment-dpia-required_en) · [T&F — DPIA in smart city / IoT 'high risk'](https://www.tandfonline.com/doi/full/10.1080/13600834.2020.1790092) · [RecordingLaw — DPIA 2026](https://www.recordinglaw.com/world-laws/world-data-privacy-laws/eu-data-privacy-laws/gdpr-dpia/)
- Art.27: [GDPR Local — Art.27 explained](https://gdprlocal.com/gdpr-art-27-requirements-explained/) · [EDPO — representative price](https://edpo.com/data-protection-representative-price/) · [DataRep — EU rep service](https://www.datarep.com/service/eu-gdpr-article-27-representative-service/) · [Cruxi — Art.27 cost calculator](https://cruxi.ai/pages/directories/gdpr-art27/gdpr-article-27-cost-calculator.html)

**Внутрішні (наш стан):** [`msa_skeleton`](../legal/msa_skeleton.md) · [`b2c_tos_privacy`](../legal/b2c_tos_privacy.md) · [`sla_exhibit`](sla_exhibit.md) · [`eo_insurance_spec`](eo_insurance_spec.md) · [`entity_structure`](../legal/entity_structure.md) · [`06_07`](../../06_07_CICD_and_Runbook_Index.md) · [`00_00`](../../00_00_SSOT_Index.md) (OpenSSF badges) · [`06_06`](../../06_06_Disaster_Recovery_and_Backup.md) (DR runbooks).
