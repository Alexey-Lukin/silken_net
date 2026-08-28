---
name: frontend
description: "Use when working on the silken_net frontend — the Phlex component tree (app/views/components/ + shared/ui|iot|web3/), the Tailwind v4 @theme design-token system (gaia-* surfaces/text, status-*, token-* blockchain, gaia-input-*), the ApplicationComponent base (the tokens() TailwindMerge wrapper + class-autoscoped t() i18n + Turbo-broadcast-safe delegated helpers), the Stimulus controllers, and Turbo Streams/Frames. Knows the non-obvious gotchas — NO tailwind.config.js (SSOT = app/assets/tailwind/application.css @theme), raw Tailwind forbidden in shared components (use status-*/gaia-* tokens), register a new font-size in CUSTOM_TEXT_SCALE for TailwindMerge, NO DB queries in a Phlex initialize, t('.key') autoscopes by class name, specs default to English, Turbo broadcast_* runs in model context (no current_user AND no viewer locale — a broadcast payload must carry no locale-dependent prose), a user-visible enum label belongs in the locale file behind one shared scope constant (i18n-tasks is structurally blind to enum growth). Routes to 04_04 (the design-system SSOT) + CLAUDE.md §6, does not restate. The gotchas are indexed here one line each and written in full in this skill's `gotchas.md`, which loads on demand — open it when an index line stops you and you need the mechanism, the incident that bought it, or its bounds. Examples: 'add a Phlex component', 'add a design token', 'why isn't my color class merging', 'add a Stimulus controller', 'i18n a component', 'a Turbo stream broadcast', 'why does a component spec render English'."
---

# Frontend (Phlex + Tailwind v4 + Turbo + Stimulus)

Navigation aid + non-obvious gotchas. The **SSOT is `04_04` + the code below** — this skill
points, it does not restate (so it can't drift). Verify a fact at its home before trusting a
summary. The view layer is **Phlex** (Ruby components, NOT ERB) on Rails 8.1, styled by
**Tailwind v4** (CSS-first `@theme`, no JS config), with **Turbo** + a handful of **Stimulus** controllers.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|----------------|
| `docs/04_04_Phlex_UI_and_Tailwind.md` | **The design-system SSOT** — §1 component hierarchy / render-flow / layout, §2 `ApplicationComponent`, §3 the token families (`gaia-*` surface+text, `status-*`, `token-*` blockchain, `gaia-input-*`) + colour-usage rules + the v3→v4 cheatsheet [DOC.11], §4 typography + motion scale, §5 TailwindMerge + `tokens()`, §6 the component registry (shared/ui, shared/iot, shared/web3, domain) |
| `CLAUDE.md §6` | The load-bearing frontend invariants (design-tokens only in shared components · `tokens(...)` · no DB in a Phlex `initialize` · `focus-visible:`) |
| `docs/04_06_Testing_Guide_and_Coverage.md §A` | RSpec conventions for Phlex components + the view-coverage map |

## Source Files

| File | Role |
|------|------|
| `app/views/components/application_component.rb` | The Phlex base (`< Phlex::HTML`). The **`tokens(*args, **conditions)`** TailwindMerge wrapper (last-wins conflict resolution); the **class-autoscoped `t('.key')`** override (`Wallets::Show#t('.heading')` → `wallets.show.heading`; overridden because the Phlex::Rails helper needs a view-context that is `nil` in component specs + Turbo broadcasts → absolute keys fall back to `I18n.t`); `CUSTOM_TEXT_SCALE` (custom font-sizes registered for TailwindMerge); pure helpers (`time_ago_in_words`, `number_to_human_size`) **delegated** so components render in broadcasts |
| `app/assets/tailwind/application.css` | **The Tailwind `@theme` block = the design-token SSOT** — there is **NO `tailwind.config.js`** (v4). Every `gaia-*`/`status-*`/`token-*` colour + the `CUSTOM_TEXT_SCALE` font-sizes live here |
| `app/views/shared/ui/*.rb` | Domain-agnostic primitives — `data_table`, `meta_row`, `pagination`, `empty_state`, `skeleton`, `photo_card`, `locale_switcher`. **Tokens only** (no raw Tailwind). Registry → `04_04 §6.1` |
| `app/views/shared/iot/*.rb` · `app/views/shared/web3/*.rb` | Shared IoT + Web3 components — `04_04 §6.2/§6.3` |
| `app/views/components/<domain>/*.rb` | Domain page components (trees, clusters, oracle_visions, contracts, alerts, …). ⚠️ This cell used to end «these MAY use page-specific raw Tailwind» — **withdrawn 2026-08-07** (gotcha 2): raw is legal only theme-invariant *and* declared. ⚠️ **This cell also used to say «much of this tree still violates it (migration backlog)» — that too is now FALSE (2026-08-21):** the campaign is exhausted, `gaia:lint_tokens` covers the entire view layer by default, and a raw hit here reds CI immediately. So there is no backlog to inherit — a hit you find is a REGRESSION, not debt, and the only legal raw values are the declared allowlist entries. ⚠️ Full-line comments are skipped by the gate, so a comment QUOTING a removed raw class is legal and lives in the tree — do not read those as survivors (there are five; measured 2026-08-21) |
| `app/javascript/controllers/*_controller.js` | The Stimulus controllers (mobile_nav, clipboard, map) — auto-registered via importmap. ⚠️ `theme_controller` is **gone** (UI.1): the theme is pure CSS now, so there is no JS in that chain to reach for. ⚠️ `reveal_controller` is **gone too** (UI.3) — it had zero consumers for seven months, and `eagerLoadControllersFrom` ships every file in this directory, so a scaffold here is bundle weight no gate can see. The list above is therefore EXHAUSTIVE, not a sample |

## Gotchas Not Obvious From Docs


Один рядок на пункт нижче — це **носій**, не зміст: він мусить спинити тебе в мить, коли ти збираєшся порушити правило. Механізм, інцидент, що його купив, і межі — у `gotchas.md` (читається на вимогу, не вантажиться щосесії).

<!-- FRONTEND-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. NO `tailwind.config.js` — **Reflex when you meet an UNMEASURABLE bucket in any of our instruments: that is a list of places to inspect by hand, not a list of things that passed**
2. Raw Tailwind forbidden across the component tree, not just `shared/` — **its ceiling belongs in ONE home — the script header — and a registry row that restates the dialect list beside its own router is the copy that rots**
2a. The theme rides exactly ONE shaft, and since 2026-08-08 that shaft is the ENVIRONMENT — `@media screen and (prefers-color-scheme: dark)`
2b. Phlex формалізує в текст ЛИШЕ `Float` та `Integer` — усе інше його `format_object` віддає `nil`, і вузол виходить порожнім БЕЗ помилки
2c. A hand-written `autoload_paths` line does NOT put the component layer into `eager_load_paths` — and the gap is invisible until production
2d. `@theme` оголошує стек, а не ДОСТАВКУ — і два сусідні токени можуть хворіти в ПРОТИЛЕЖНІ боки
3. A new font-size → register it in `CUSTOM_TEXT_SCALE`
4. Ніяких DB-запитів у Phlex `initialize` — компонент приймає лише вже завантажені дані
5. `t('.key')` autoscopes by class-name — **Рефлекс перед будь-яким One-Home над i18n-ключем: спитай, на ЧОМУ ключується сканер, і залиш йому літерал**
6. Спеки за замовчуванням рендерять АНГЛІЙСЬКУ — свідок іншої локалі мусить її оголосити
7. Turbo `broadcast_*` runs in MODEL context — **Рефлекс перед тим, як покласти `*_path` у компонент: грепни, чи його НЕ рендерять через `.call` — і якщо рендерять, питання не «чи додати хелпер», а «хто будує адресу»**
8. Класи будуй через `tokens()`, не склеюванням рядка — інакше TailwindMerge не розвʼяже конфлікт утиліт
9. For live updates use `turbo_stream_from` + `Turbo::StreamsChannel.broadcast_*_to` (§8), NOT raw `ActionCable.server.broadcast` — **any broadcast reachable from a model commit-hook on a money path needs the same isolation as the device-reply path — ask what the CALLER does when the hook raises, not whether the broadcast matters**
9a. The tract has a FIFTH link the registry sweep above cannot see, and it is upstream of all four: the CONDITION under which the producer fires at all — **Reflex when a live update looks dead despite a healthy tract: diff the trigger set against the columns the component actually RENDERS, then check whether the writer bypasses callbacks**
10a. PLURAL-категорії МІРЯЮТЬ рантаймом, ніколи не пригадують — і промах тут коштує роботи БЕЗ ЕФЕКТУ, не червоного гейта — **перш ніж шукати форму слова для числа, спитай, чи це число взагалі ДОСЯЖНЕ — і чи не бреше сама ШКАЛА поруч; питання про відмінок часто зникає разом із предметом**
10. A user-visible enum value's home is the locale file, not `.humanize` — **Reflex for any behaviour change that touches user-visible prose: grep the key and edit every locale BY HAND, and treat a category/severity change as half a fix until you have re-read the sentence**
10c. Перш ніж АВТОРИТИ мітку, грепни її ЗНАЧЕННЯ по каталогах, не лише ключ — сусідній домен міг уже її перекласти
10b. Число з іменником після нього заводить плюральний борг — часто його можна ОБІЙТИ, назвавши межу замість тривалості — **побачив `%{count}`/`%{n}` перед іменником — спитай, чи взагалі потрібне ЧИСЛО, чи потрібен ФАКТ, який воно кодує (дата · діапазон · назва періоду)**
11. A broadcast payload must carry NO locale-dependent prose
12. A component that renders a GATED action must TAKE the actor — and its default must fail CLOSED — **Reflex for any cell-level migration: enumerate which cells change on the event you are re-targeting, not just the one you are fixing**
12b. `data-turbo-frame` мусить указувати на `<turbo-frame>`, а не на елемент із таким id — і провал ТИХИЙ
12a. A stream+target pair has exactly ONE owner — the page that renders the target — and the payload's shape belongs to that owner, not to the producer — **Reflex before any migration to a signal: list the `turbo_frame`s with `src` on the owner page — the layout meta-tags know nothing about them**
13. A gated action needs the right ACTOR (#12) — but it also needs a right TARGET, and that is a separate axis no gate and no component spec can see
14. A component spec's own fixture is an unproven contract with the CALLER, and it lies in two ways — **before trusting a fixture whose names are right, ask whether the component reads THAT name or something derived from it**
15. Flash-поверхня існує з 2026-08-01, і має рівно один спосіб вживання
16. `data-turbo-permanent` у цьому дереві не стоїть НІДЕ — і це стан, а не випадковість
17. `*TargetConnected` спрацьовує РАНІШЕ за `connect()` — тож стан, ініціалізований у `connect()`, для серверної розмітки ще не існує — **Рефлекс при написанні будь-якого контролера з `*TargetConnected`: спитай, чи він виживе, якщо target прийде ПЕРШИМ — і перевір це прикладом, у якому дані Є**
18. «Не виміряно» — окремий СТАН, і в UI він має ІМʼЯ, не тире
19. Твердження «HTML цього не дозволяє» майже завжди про ПАРСЕР — а Turbo ходить повз нього, тож обмеження може бути реальним і водночас не діяти на твоєму шляху доставки — **перш ніж будувати вибір на «розмітка так не вміє», спитай, ЯКИМ шляхом їде твій фрагмент**
20. Закривши сайт класу, перечитай ФАЙЛ цілком — а не околицю правки
21. Глобальне правило `td:nth-child(N)` бачить і комірку, що ОХОПЛЮЄ колонки — і саме вона є найпоширенішим винятком у наших таблицях — **пишучи позиційний селектор по клітинках, спитай, чи є в цій таблиці комірка з `colspan` — вона позиції не має за визначенням**
22. Клас, який ставить лише JS, у білд ПОТРАПЛЯЄ — але перевірити це грепом важче, ніж здається
23. `aria-label` на кнопці ПЕРЕКРИВАЄ її вміст — тож підміна тексту всередині кнопки не озвучується взагалі
24. i18n-скоуп, названий як компонент, часто називає РОЛЬ розмітки — і тоді зняття компонента не вимагає чіпати ключі взагалі — **перш ніж переносити скоуп разом із компонентом, прочитай, що називає останній сегмент — сутність (`row`, `item`, `card`) чи клас; для першого зняття безкоштовне, для другого потрібен `i18n-tasks normalize` після перейменування**
25. КОЛІР бреше окремо від ЗНАЧЕННЯ — і це найтонша форма «вигаданого виміру», бо текст поруч буває чесний — **полагодивши значення, ОДРАЗУ грепни його ж у методах кольору/класу того самого компонента (`*_color`, `*_class`, `tokens(...)`) — вони беруть те саме поле окремим шляхом і мають власний дефолт**
26. `limit(N)` у контролері — це ТВЕРДЖЕННЯ, яке екран мусить оголосити; інакше стеля видима лише тому, хто читає контролер — **побачив `limit(` на шляху рендеру — спитай не «чи достатня стеля», а «де на екрані про неї сказано»**
27. Морф має ДВА незалежні вимикачі, і той, що адресніший, — на ФОРМІ, не в лейауті
28. Морф зносить дітей вузла, який САМ вижив — тож Stimulus не переграється, і зовнішній віджет помирає мовчки; лік у платформі, не в обході
29. Морф знімає й АТРИБУТ — суто клієнтський стан зникає БЕЗ власної події елемента, тож прибирання не відпрацьовує
30. Клієнтський стан, що ставиться ОДИН раз і не вміє поставитись удруге, несумісний із морфом ЗА ПОБУДОВОЮ — і саме одноразовість перетворює косметичний відкат на ПОСТІЙНУ втрату
31. Предикат, що фільтрує асоціацію, у циклі коштує лінійно — і `includes(:та_сама_асоціація)` цього НЕ лікує — **Рефлекс при рев'ю компонента-циклу: на кожен виклик усередині `.each` спитай не «чи це асоціація», а «чи будує він relation» — предикат, скоуп і `.count`/`sum(:колонка)` будують, `.size` і блокова `sum` ні**
32. РУХ не сміє бути носієм сенсу — і клас має ДВІ шкоди, з яких дискримінація дорожча за контраст — **рух легітимний лише на чистій декорації БЕЗ тексту (LED-крапка, скелетон, SVG-штрих); сенс несе статичний дискримінатор**
33. Tailwind v4: `bg-[radial-gradient(…var(--tw-gradient-stops))]` без утиліти `bg-radial`/`bg-linear-*` не малює НІЧОГО — **побачив arbitrary-градієнт із `var(--tw-*)` усередині — відкрий `getComputedStyle(el).backgroundImage` у браузері, а не читай класи**
34. Lookbook: ДВА реєстри шляхів, і другий легко лишити недротованим
35. ТОКЕН, непридатний до РОЛІ, дорожчий за сиру палітру — бо виглядає ЗРОБЛЕНИМ
36. Перевір ІНСТРУМЕНТ міграції перш ніж гнати ним хвилю — `bin/migrate-tailwind-tokens` виробляв той самий дефект, який знімає — **Рефлекс перед будь-яким codemod'ом: візьми його MAPPING як СПИСОК ЗАЯВ і зміряй КОЖНУ ЦІЛЬ проти реальних поверхонь у ДВОХ темах; окремо грепни, яких родин у мапі немає взагалі**
37. Un-layered CSS перемагає layered-утиліти НЕЗАЛЕЖНО від специфічності — тож «глобальний дефолт» поза `@layer` тихо зʼїдає явні Tailwind-класи
38. Перш ніж писати Stimulus controller — пройди список нативних шляхів; якщо хоч один підходить, контролер не потрібен
39. У YAML незакавичене значення, що містить ` #`, МОВЧКИ стає коментарем — тож скриптова вставка локалей ОБРІЗАЄ рядки, і три з чотирьох наших i18n-гейтів це пропускають — **після БУДЬ-ЯКОГО скриптового запису в структурований файл — перепарсь і роздрукуй ЗНАЧЕННЯ, а не рядки**

<!-- /FRONTEND-GOTCHAS-INDEX -->

## Common Tasks

- **Add a Phlex component**: `app/views/components/<domain>/<name>.rb` (`< ApplicationComponent`, `def view_template`); a reusable primitive → `app/views/shared/ui/`. **Tokens only** if shared; accept **pre-loaded data** (no DB in `initialize`); i18n via `t('.key')`. Spec per `04_06 §A`. 🔴 **Then register it, or CI reds** (`component_doc_sync`, `docs.yml`, since 2026-08-07): a row in `04_04 §6.4` (domain) or §6.1–6.3 (shared), and — for a brand-new namespace — a line in the §1 hierarchy tree. Placement rule is the §6.5 decision tree; the ONLY exempt file is `application_component.rb` itself. ⚠️ The registry writes components in **three** row forms (detailed `` `Ns::Class` `` · compressed `` `Ns` `` + leaf list under "Інші Доменні Компоненти" · **bold** in the shared sections) — match the form your section already uses, and note that the §1 tree carries **namespaces only**, never leaves (leaves have one home, §6).
- **Add a design token**: edit the `@theme` block in `app/assets/tailwind/application.css` (a `gaia-*`/`status-*`/`token-*` colour or a font-size); a **font-size ALSO → `CUSTOM_TEXT_SCALE`**; document the usage rule in `04_04 §3`.
- **Token-migration (UI.1 — ✅ ARCHIVED 2026-08-21, `00_07 §🗄️`)**: the backlog is EXHAUSTED (eleven waves) — `default_scopes` covers all of `components/` + `shared/` + `layouts/`; `LINT_SCOPE=` is a spot-check. ⚠️ The last ⚖️ of that item («status-token refactor: yes/when?») was closed as **VACUOUS**, not decided: both its premises had died in other people's work, and it had been gating the AA-contour of every money and ops page meanwhile — so do not re-open it, and do not read «UI.1 is open» anywhere as current. `bin/migrate-tailwind-tokens` = the safe Ruby codemod (MAPPING + PROTECTED list + dry-run) — replacement is NOT visually-neutral, so QA both themes after a run; role-corrections on top of the map are the rule, not the exception (headings → `-strong`, signals → `-accent`, glows removed unless the declared 8px LED pair). ⚠️ This line used to say the backlog was **blocked** on a ⚖️ verdict about the three skin fractions ("is SECTOR a deliberate brand skin?"). **That verdict landed 2026-08-07 and the answer is no** — the light theme is supported, single-theme is legal only when *declared*, and §3.5 now defines the criterion (gotcha 2 above). So what remains is scope, not a decision: per-domain migrate wave → regex expansion, in that order (expanding first reds CI instantly). Plan → `00_07 UI.1`.
- **Add a Stimulus controller**: `app/javascript/controllers/<name>_controller.js` (auto-registered); wire via `data-controller` / `data-action` in the Phlex component. ⚠️ **`data-controller` мусить стояти на СПІЛЬНОМУ ПРЕДКУ всіх своїх targets** — scope контролера = елемент **+ нащадки**, тож target-сиблінг поза піддеревом не реєструється БЕЗ жодної помилки. Куплено: контролер стояв на `div` зі списком, а форма рендерилась сиблінгом того списку — `Cmd/Ctrl+Enter` був мертвий, доки `data-controller` не переїхав на секцію-предка. **Провал тихий за побудовою** (незареєстрований target не кидає), тож перевіряй не наявність атрибута, а те, що ВСІ targets лежать усередині його вузла.
- **A Turbo broadcast**: render the component with explicit data (no `current_user`, gotcha #7); use the delegated pure helpers.
- **Local-verify**: `bin/rubocop -a app/views app/javascript` — ⚠️ **точковий прогін лише для швидкої ітерації, НЕ як верифікація** (2026-08-28): саме ця форма поклала `main` — лінт прогнали по файлу, який правили, а файл, СТВОРЕНИЙ пізніше в тій самій сесії, у прогін не входив. Повний `bin/rubocop` тепер блокуючий блок `pre-push` (~3.2 с), тож забування перестало мати наслідки — але не покладайся на точковий як на доказ ([[feedback_local_verify]]) → `COVERAGE=0 bin/rspec spec/views` (Phlex specs — wrap non-English assertions in `I18n.with_locale`) → eyeball the dark theme + `focus-visible:` rings.
