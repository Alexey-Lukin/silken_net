# Глосарій domain-термінів — довідник для перекладів

> **Статус: робоча чернетка, не канон.** Дім механіки i18n — [`04_04 §12`](../../04_04_Phlex_UI_and_Tailwind); стан роботи — [`00_07`](../../00_07_Action_Plan_Tracker) I18N.1 (residual «глосарій domain-термінів поруч із локалями»). Сестринський документ — [`translation_audit_2026_07.md`](translation_audit_2026_07.md) (перший лінгвістичний аудит, 136 файлів ключ за ключем); цей файл **не дублює** його зміст — лише посилається там, де факти перетинаються.
>
> **Дата збору:** 2026-08-20. **Порядок роботи з цим файлом: спершу глосарій (яке слово канонічне), потім авторинг** (нові ключі пишуться вже узгодженим терміном) — глосарій розвʼязує клас «та сама сутність названа двічі всередині однієї мови», який `translation_audit` виявив і назвав §B, одним артефактом.
>
> **Метод:** кожен рядок — це `grep` живого корпусу `config/locales/**/{uk,lv,lt,en}.yml` (136 файлів, 34 домени), не судження про мову. Де корпус дає ≥2 живі форми, канонічну **не обрано** — стоїть ⚖️ до 👤-ревʼю, окрім місць, де `translation_audit` уже виніс вердикт (тоді тут — посилання, не новий розгляд). Порожній рядок для терміна, якого корпус не містить, чесно каже «не вживається» — переклад НЕ придуманий.

---

## 1. Правила вжитку (виведені з корпусу)

### 1.1 Locale-інваріанти — підтверджено фактичним корпусом

Ці класи значень **не належать у цей глосарій як «переклад»**, бо корпус трактує їх як дані, не як мову — підтверджено безпосереднім читанням YAML, не з памʼяті:

- **Тікери монет (`SCC`, `SFC`)** — байтово ідентичні в усіх чотирьох мовах на КОЖНОМУ сайті: `dashboard.minted_scc` = «Змінтовано **SCC**» / «Kalts **SCC**» / «Nukalta **SCC**» / «**SCC** Minted» — дієслово перекладається, тікер ніколи. Це відповідає `04_04 §12.14`/скіл `frontend` (тікер — locale-інваріантні дані, дім значення поза Ruby YAML, у `BlockchainTransaction::TOKEN_TICKERS`); тут лише підтверджено фактом корпусу, не переприсуджено.
- **Гліфи/емодзі** — ідентичні в усіх мовах на кожному алерті: 👑 (Queen), 🚨 (критична тривога), ❄️/🔥/📵/🛰️/🎲/⏮️/⚙️/⬢/🔧 — жодного випадку локалізованого емодзі не знайдено. Підтверджує скіл `frontend` gotcha 10 (гліфи — фрозен Ruby-мапа, не YAML).
- **Бренд-абревіатура `NaaS`** — одностайно **англійська у ВСІХ чотирьох мовах**, на кожному з 6 сайтів (`contracts.index_title`, `contracts.decoration`, `clusters.empty/heading`, `navigation.naas_contracts`, `reports.active_contracts_sub`); навіть `index_title`, де uk/lv/lt МАЛИ Б розгорнути повну фразу (як робить `en`: "Nature-as-a-Service Registry"), кажуть «Реєстр **NaaS**-контрактів» / «**NaaS** līgumu reģistrs» / «**NaaS** sutarčių registras» — «Nature-as-a-Service» ніде не розгорнуто жодною мовою. Це **не суперечка про переклад** (одностайність повна) — це вже занесене аудитом мовчазне бренд-рішення, що потребує явного присуду (§07), не мовного: «усі три: Nature-as-a-Service зникає з не-англійських UI — рішення бренд-поверхні, ухвалене мовчки в локаль-файлі». Не дублюю — дім рішення `legal-business`/§07, посилання лише.
- **Власні назви мереж** (`Solana`, `Celo`, EVM-мережі) — `blockchain_network` уже виведений з переліку авторингу `00_07` I18N.1 як власна назва, не enum-мітка; той самий клас — тут лише pointer, не новий розгляд.

### 1.2 Кодові імена `Queen`/`Soldier` — ФАКТИЧНА конвенція корпусу (не чиста, є винятки)

Корпус **не трактує** `Queen`/`Soldier` як чисті locale-інваріантні власні назви — практика мішана й асиметрична між двома термінами (адреси — §4):

- **`Queen`:** лишається англійською в структурних UI-місцях (навігація, index/show-заголовки, alert-заголовки на кшталт `queen_offline`) у **lv/lt**; але переходить на «Karalienes»/«Karalienės» рівно в домені `flash` (OTA-повідомлення). **uk перекладає завжди** («Королева») без винятку.
- **`Soldier`:** дзеркально — **lv/lt перекладають** («karavīrs»/«karys») у більшості доменів (organizations, trees, contracts, navigation, dashboard, gateways, wallets, tree_families), але лишають англійське «Soldier»/«Soldiers» саме в `provisioning` і `firmwares` (домени, де дерево — це технічна ціль прошивки/провіжінінгу, не персонаж наративу). uk знову перекладає всюди.
- **`Oracle`** іде за тим самим візерунком, що й `Queen`: англійська в `oracle_visions`/`navigation` (структурні заголовки), перекладена («Orākula»/«Orakulo») у прозі `alerts`.

**Спостережена (не приписана) конвенція:** структурні UI-елементи (навігація, заголовки, table-заголовки) тяжіють тримати кодове імʼя англійським; природномовна проза (alert-текст, flash-повідомлення) тяжіє його схиляти/перекладати. Це emergent-патерн, не write-up правило — і `Soldier` явно ІНВЕРТУЄ його на двох доменах (provisioning/firmwares лишаються англійськими, хоча це не проза). uk єдина мова, що уникає питання повністю (перекладає скрізь). **Рішення, яку форму канонізувати — мовне, стоїть у §4.**

### 1.3 Money-path одиниці (пункт CLAUDE.md §6, не переприсуджую)

`бали`/`SCC` — одиниця й напрямок грошового рядка НЕ виводяться з сусіднього UI; дім `ARCH.88`/`ARCH.101` (`00_07`) + `04_04 §12.14`. Глосарій нижче фіксує ЛЕКСИКУ («бали росту» vs «вуглецеві бали» — обидва варіанти корпусу, обидва законні за англійським джерелом, див. рядок `growth points`), не одиницю — те питання вже має власний дім і сюди не переноситься.

---

## 2. Таблиця термінів

Статус: **✅** одностайний (одна форма на мову, або одна форма з очікуваною граматичною варіацією) · **⚖️** розбіжність, канонічну НЕ обрано — чекає 👤-ревʼю, деталі в §4 · **🔧** розбіжність, але `translation_audit` уже дав напрямок — деталі в §3 · **➖** не вживається в UI жодною мовою.

| Термін | en (джерело) | uk | lv | lt | Статус |
|---|---|---|---|---|---|
| **Queen** (кодове імʼя Королеви/шлюзу) | Queen | Королева | Queen *(крім `flash`: Karalienes)* | Queen *(крім `flash`: Karalienės)* | ⚖️ §4.1 |
| **Soldier** (кодове імʼя Солдата/дерева) | Soldier | Солдат | karavīrs *(крім `provisioning`/`firmwares`: Soldier)* | karys *(крім `provisioning`/`firmwares`: Soldier)* | ⚖️ §4.1 |
| **gateway** (загальне слово, не кодове імʼя) | gateway | Шлюз | vārteja | šliuzas | ✅ |
| **uplink** | Uplink | зв'язок *(+ 3 сайти сирого «uplink»/«UPLINK»)* | augšupsaite | ryšys aukštyn | ⚖️ §4.2 |
| **downlink** | — | — | — | — | ➖ §5 |
| **payload** | Payload | Дані / «Сирий вміст» *(+ 1 сайт сирого «Payload»)* | slodze / dati | naudingoji apkrova / duomenys | ⚖️ §4.3 |
| **hash** (TX Hash) | TX Hash | TX Hash *(+ «TX Хеш» + «Хеш транзакції»)* | TX Kods | TX Kodas | ⚖️ §4.4 |
| **gas** | Gas Price/Used | газ | gāze | dujos | ✅ |
| **mint / minting** | Mint / Minted / Emission | Емісія / Намінтовано / Мінти / Створено / Змінтовано *(5+ форм)* | Kalts / Emisija / Emitēts | Nukalta / Nukalinta / Emisija / Išleista / Sukurta / kalimo *(6 форм)* | ⚖️🔧 §3.3 + §4.5 |
| **slash / slashing** | Slash / Slashing | Slashing / slash / Слешинг / Slash-* *(4 форми)* | Slash / Slashing *(стабільний loanword)* | Slash / Slashing *(стабільний loanword)* | ⚖️ §4.6 |
| **burn / burning** | Burn / Burned | Спалення/спалено/спалити (єдиний корінь) | Sadedzināšana (єдиний корінь) | Sudeginimas/sudeginta *(+ 1 сайт «deginimas» без префікса)* | ✅ *(lt: мінорна нота §4.7)* |
| **growth points / points** | Growth Points / Carbon Points | бали росту / вуглецеві бали | izaugsmes punkti / oglekļa punkti | augimo taškai / anglies taškai | ✅ |
| **alert** (сутність EwsAlert) | Alert | Тривога *(+ «попередження» + «Сигнали загрози», 3 форми)* | Brīdinājums *(+ 1 винятковий сайт «Trauksme»)* | Įspėjimas *(+ 1 винятковий сайт «Pavojus»)* | ⚖️ §4.8 |
| **actuator** | Actuator | Актуатор (єдиний корінь) | aktuators *(+ «izpildmehānisms» на 5 сайтах)* | aktuatorius *(+ «vykdiklis» на 5 + «pavara» на 4 сайтах)* | ⚖️ §4.9 |
| **cluster** | Cluster | Кластер | klasteris | klasteris | ✅ |
| **wallet** | Wallet | Гаманець | maks | piniginė | ✅ |
| **ledger** | Ledger | Реєстр *(+ 1 сайт «Леджер»)* | virsgrāmata | (sandorių) knyga | ⚖️ §4.10 |
| **maintenance** | Maintenance | обслуговування | apkope | priežiūra | ✅ |
| **firmware** | Firmware | прошивка | programmaparatūra | programinė įranga | ✅ *(lt: audit-концерн §4.11)* |
| **token** | Token | токен | žetons | žetonas | ✅ |
| **stake** (staking, окремо від slashing) | — | — | — | — | ➖ §5 |
| **oracle** | Oracle | Оракул | Oracle *(крім `alerts`: Orākula)* | Oracle *(крім `alerts`: Orakulo)* | ⚖️ §4.1 |
| **anchor** (геопросторовий/фізичний) | Anchor | Анкер | enkurs | inkaras | ✅ |

### Додаткові терміни, знайдені при зборі (поза ядром трекера)

| Термін | en (джерело) | uk | lv | lt | Статус |
|---|---|---|---|---|---|
| **batch** (втрата пакету телеметрії) | batch | батч *(транслітерація)* | partija | partija | ⚖️ §4.12 |
| **transaction** | Transaction | транзакція (єдиний корінь) | darījums *(+ 1 сайт «transakcija»)* | sandoris *(+ 3 сайти «operacija»)* | ⚖️ §4.13 |
| **chronicle** (журнал дерева) | Chronicle | Хроніка *(+ 1 сайт калька «Хронограф»)* | hronika | kronika | 🔧 §3.1 |
| **patrol** | Patrol | патруль (єдиний корінь) | patruļa (єдиний корінь) | patrulys *(+ 1 сайт «patruliavimas», процес замість особи)* | 🔧 §3.2 |
| **NaaS** | NaaS / Nature-as-a-Service | NaaS | NaaS | NaaS | ✅ *(§1.1 — бренд-питання, не мовне)* |
| **backing asset** | — | — | — | — | ➖ §5 |
| **leaderboard** | — | — | — | — | ➖ §5 |

---

## 3. Уже присуджене аудитом (посилання, не новий розгляд)

Ці три пункти `translation_audit_2026_07.md` уже кваліфікував як калька/дефект (не як «стилістичний варіант») — глосарій відображає вердикт з адресою, авторити наново не треба.

### 3.1 chronicle: «Хронограф» — зареєстрована калька

`trees/uk.yml:17` (`heading: Цифровий хронограф`) розходиться з власним же `navigation/uk.yml:15` (`chronicle: Хроніка`). `translation_audit_2026_07.md` §Систематика прямо перелічує «хронограф» серед зареєстрованих кальок uk (разом із «пункти, вітальні, двигун»), і П'ята хвиля того ж документа окремо ловить спробу агента запропонувати «хронограф» ЗНОВУ для `chronicle`-сегмента крихт, називаючи це прикладом, де «доказово в корпусі» і «правильно» розходяться. **Канонічна форма — «Хроніка»** (і так уже каже `navigation/uk.yml:15`, `trees/lv.yml`/`trees/lt.yml` через `hronika`/`kronika` теж одностайні). lv/lt дефекту не мають — `hronika`/`kronika` вжиті послідовно на всіх сайтах (`trees.chronicle.heading`, `.empty_title`, `navigation.chronicle`).

### 3.2 patrol (lt): «Surasti patruliavimą» — процес замість особи

`maintenance/lt.yml:100` (`locate: Surasti patruliavimą →`) — `translation_audit_2026_07.md` §A (литовська таблиця) уже назвав це дефектом: «Surasti patruliavimą» = «знайти патрулювання» (процес), а шукають ПАТРУЛЯ (особу/групу) — і дав напрямок фіксу: `Surasti patrulį`. Підтверджено фактом корпусу: та сама lt-локаль в іншому домені коректно вживає форму-особу — `alerts/lt.yml:14-15` («Reikalingas **patrulio** išvykimas»). uk (`патруль`) і lv (`patruļa`) дефекту не мають — обидві мови тримають форму-особу послідовно на обох сайтах.

### 3.3 mint (lt): «nukalta» ⟷ «nukalinta» — хибний друг

✅ **ВИПРАВЛЕНО 2026-08-27 (DOC-T.91) — і периметр виявився ВДВІЧІ ширшим за записаний.** Тут стояла пара `organizations/lt.yml:50/51`; насправді дефект жив на ЧОТИРЬОХ сайтах у ДВОХ файлах: `organizations/lt.yml` (`carbon_yield: Nukalta` ⊥ `carbon_yield_sub: Nukalinta` — сусідні ключі ОДНІЄЇ картки) **і** `dashboard/lt.yml` (`minted:` брoадкаст із `Nukalinta` ⊥ `minted_scc: Nukalta` — та сама пара, інший екран). 🔑 **Два уроки, обидва про запис, не про мову:** номери рядків у цьому файлі вже з'їхали (`:50/:51` → `:53/:54`), тобто **посилання на РЯДОК протухає тихіше за посилання на КЛЮЧ**; і перелік сайтів у вердикті є фотографією одного проходу, а не властивістю дерева — периметр міряють прогоном. Історична форма дефекту нижче. `translation_audit_2026_07.md` §B уже назвав пару й указав напрямок дефекту: «друга форма (`nukalinta`) читається від `kalinti` — увʼязнювати», тобто `nukalinta` — хибний друг, `nukalta` (від `kalti` — кувати/карбувати) — коректна форма. **Це стосується ЛИШЕ цієї пари.** Решта фрагментації навколо «mint» (uk 5+ форм, lt ще 4 форми — `emisija`/`išleista`/`sukurta`/`kalimo`, lv `kalts`⟷`emisija`) аудитом НЕ адресована — лишається в §4.5.

---

## 4. Розбіжності до 👤-ревʼю

Кожен пункт — живі форми з адресами; канонічна форма НЕ обрана.

### 4.1 Кодові імена (Queen / Soldier / Oracle) — яку конвенцію канонізувати

**Queen:**
- lv/lt тримають англійське «Queen» — `clusters/{lv,lt}.yml:49`, `provisioning/{lv,lt}.yml:17`, `navigation/{lv,lt}.yml:82`, `alerts/{lv,lt}.yml:36-55,64,104-105` (10 сайтів), `gateways/{lv,lt}.yml:7,10,36,43`, `telemetry/{lv,lt}.yml:11`, `firmwares/{lv,lt}.yml:8,24`.
- lv/lt перекладають у `flash`: `flash/lv.yml:18,20` («Karalienes»), `flash/lt.yml:18,20` («Karalienės»).
- uk перекладає всюди («Королева») — жодного винятку.

**Soldier:**
- lv/lt перекладають («karavīrs»/«karys») — `organizations/{lv,lt}.yml:34,47`, `trees/{lv,lt}.yml:52-53/51`, `contracts/{lv,lt}.yml:27`, `navigation/{lv,lt}.yml:84`, `dashboard/{lv,lt}.yml:20`, `gateways/{lv,lt}.yml:15,30,33-34`, `wallets/{lv,lt}.yml:15`, `tree_families/{lv,lt}.yml:32`.
- lv/lt лишають англійське «Soldier»/«Soldiers» — `provisioning/lv.yml:18`, `provisioning/lt.yml:18`, `firmwares/{lv,lt}.yml:10,26`.

**Oracle:**
- lv/lt тримають англійське «Oracle» — `oracle_visions/{lv,lt}.yml:3,15`, `navigation/{lv,lt}.yml:42,80`.
- lv/lt перекладають у `alerts`: `alerts/lv.yml:50` («Orākula»), `alerts/lt.yml:50` («Orakulo»).

**Питання до 👤:** чи канонізувати одну конвенцію на кодові імена для lv/lt (завжди англійською як власна назва / завжди перекладати як uk / тримати спостережений «структура англійською, проза перекладена» поділ і навести Soldier до нього), чи лишити асиметрію як є. `translation_audit` уже називав частину цього класу («Queens ⟷ Karalienes», «крос-мовне: кодові імена Queen/Soldier — uk перекладає, lv/lt тримають англійськими в одних ключах і відмінюють в інших. Потрібне одне рішення на мову») без вердикту.

### 4.2 uplink — uk тримає англійське слово в заголовку, де сусідні заголовки перекладені

- uk переклад: `trees/uk.yml:78` (`uplink_state: Стан звʼязку`).
- uk сире «UPLINK»/«uplink»: `alerts/uk.yml:39` (заголовок `"📵 UPLINK:"` — сусідні заголовки того ж файлу ПЕРЕКЛАДЕНІ: `"❄️ ЗАМЕРЗАННЯ:"` рядок 36, `"🔥 ПЕРЕГРІВ:"` рядок 38), `alerts/uk.yml:53` («без uplink»), `alerts/uk.yml:54-55` (гібрид «uplink'и» — англійський корінь + українське закінчення), `telemetry/uk.yml:5` («Starlink Uplink»).
- lv/lt: **обидва перекладають той самий заголовок** — `alerts/lv.yml:39` (`"📵 AUGŠUPSAITE:"`), `alerts/lt.yml:39` (`"📵 RYŠYS AUKŠTYN:"`), і той самий `telemetry.awaiting` — `telemetry/lv.yml:5` («Gaida Starlink **augšupsaiti**»), `telemetry/lt.yml:5` («Laukiama Starlink **ryšio aukštyn**»). uk — єдина мова з сирим залишком.

**Питання до 👤:** чи `Стан звʼязку` (trees) і сире `uplink` (alerts/telemetry) — навмисний регістр (технічний жаргон у діагностичних місцях), чи залишок, вартий вирівняти на `звʼязок`/`аплінк`.

### 4.3 payload — uk тримає «Payload» там, де lv/lt перекладають

- uk: `actuators/uk.yml:44` («Дані»), `telemetry/uk.yml:12` («Сирий вміст CoAP») — перекладено; АЛЕ `flash/uk.yml:55` («**Payload** перевищує ліміт») — сире.
- lv: `flash/lv.yml:55` («**Slodze** пārsniedz») — перекладено (інше слово — «навантаження», доречний контекстний вибір).
- lt: `flash/lt.yml:55` («**Naudingoji apkrova** viršija») — перекладено повністю.

**Питання до 👤:** чи uk `flash/uk.yml:55` — забутий залишок (третій, за уже зафіксованими двома з `translation_audit`), вартий перекладу на кшталт «Дані»/«Обсяг даних».

### 4.4 hash (TX Hash) — uk тримає ТРИ форми на одну сутність

- `contracts/uk.yml:44` («TX Hash», англ.), `wallets/uk.yml:39` («TX Hash», англ.), `blockchain_transactions/uk.yml:19` («TX **Хеш**», транслітерація), `blockchain_transactions/uk.yml:32` (`tx_hash_label: Хеш транзакції`, повний переклад).
- lv: одностайно «TX **Kods**» — `contracts/lv.yml:44`, `blockchain_transactions/lv.yml:19`, `wallets/lv.yml:39`; label `blockchain_transactions/lv.yml:32` («Darījuma kods»).
- lt: одностайно «TX **Kodas**» — ті самі три сайти; label `blockchain_transactions/lt.yml:32` («Sandorio kodas»).

Це точно термін, названий `translation_audit` §B («TX Хеш» ⟷ `TX Hash`) — адреси тут доповнюють, вердикту аудит не давав.

**Питання до 👤:** канонічна uk-форма — «TX Hash» (англ., як контракти/гаманці) чи «TX Хеш» (як блокчейн-транзакції)? lv/lt для довідки НЕ калькують «hash» узагалі — вживають «код» (Kods/Kodas), що теж варіант відповіді для uk.

### 4.5 mint / minting — найширша фрагментація в корпусі (за межами §3.3)

**uk** (внутрішня фрагментація, 5+ форм на одне поняття): «Емісія» (`trees/uk.yml:13`), «Намінтовано»/«намінтовано» (`trees/uk.yml:24-25`, `alerts/uk.yml:49`), «Мінти» (`contracts/uk.yml:22`), «Створено» (`dashboard/uk.yml:8` — ІНШЕ слово, не похідне від «мінт»/«емісія» взагалі), «Змінтовано»/«змінтовано» (`dashboard/uk.yml:24`, `reports/uk.yml:41`), «мінтингу» (`alerts/uk.yml:67`), сире «Minting»/«Mint-volume» (`blockchain_transactions/uk.yml:9`, `alerts/uk.yml:49,66`).

**lv** (2 родини): «Kalts»/«kalts»/«kalšanas» (`organizations/lv.yml:50-51`, `alerts/lv.yml:49,67`, `dashboard/lv.yml:8,24`) проти «Emisija»/«Emitēts»/«emitēts» (`trees/lv.yml:13,24-25`, `contracts/lv.yml:22`, `reports/lv.yml:41`).

**lt** (6 форм — найширше): «Nukalta»/«Nukalinta» (§3.3, уже присуджено), «Emisija» (`trees/lt.yml:13`, `contracts/lt.yml:22`), «Išleista»/«išleista» (`trees/lt.yml:24-25`), «kalimo» (`alerts/lt.yml:67`), «Sukurta» (`reports/lt.yml:41` — паралель до uk-«Створено», ІНШЕ слово знову).

**Питання до 👤:** money-path термін (SLASH-1/мінт-тракт критичний, `CLAUDE.md §1`); чи має uk канонізувати «Емісія» (найчастіша, і вже канонічний переклад `05_03`) для всіх сайтів, знявши «Створено»/«Мінти»/сирі англ. форми? Для lv/lt — «Kalts»/«Emisija» та «Sukurta»/«Emisija»/«Išleista» відповідно — яка родина стає базовою.

### 4.6 slash / slashing — uk 4 форми на одну сутність, lv/lt стабільно тримають loanword

**uk:** «Slashing»/«slashing» англійською — `alerts/uk.yml:24,41,74`, `blockchain_transactions/uk.yml:9`; гібрид «Slash-ухилення» — `alerts/uk.yml:56-57`; гібрид «авто-slash» — `alerts/uk.yml:25`; транслітерація «Слешинг» — `alerts/uk.yml:58-61`.

**lv/lt:** обидві мови консистентно тримають «Slash»/«Slashing» як незмінний технічний loanword, обгортаючи рідною граматикою навколо нього — `alerts/lv.yml:24,41,56,58-61,74`, `alerts/lt.yml:24,41,56,58-61,74` (напр. «Slashing bloķēts», «Slash izvairīšanās», «Slashing užblokuotas», «Slash vengimas») — це СТАБІЛЬНА конвенція, не розбіжність.

**Питання до 👤:** money-path термін (`SLASH-1`, `CLAUDE.md §5`); чи привести uk до lv/lt-конвенції (стабільний loanword «Slash»/«Slashing» скрізь) — це усуне всі 4 форми одним рішенням, а не приватизувати одну з наявних.

### 4.7 burn (lt, мінорна нота)

`contracts/lt.yml:47` (`burn_points: Sukauptų taškų **deginimas**`) — без префікса «su-», тоді як решта корпусу консистентно тримає «su**deg**inimas»/«su**deg**inta»/«su**deg**inti» (`trees/lt.yml:9,22-23`, `alerts/lt.yml:19-20,34`, `dashboard/lt.yml:5`, `reports/lt.yml:40`). Низька гострота (той самий корінь, лише відсутній перфективний префікс) — не в топ-5, але вартий рядка для повноти.

### 4.8 alert — uk 3 форми (названо аудитом) + lv/lt спільний виняток (НЕ назван аудитом)

**uk** (уже назвав `translation_audit` §B, тут — адреси): «Тривога»/«тривога» (більшість, 15+ сайтів — `trees/uk.yml:8,19-20`, `alerts/uk.yml:12,86,88`, `flash/uk.yml:9-10`, `maintenance/uk.yml:21,122`, `mailers/uk.yml:8`, `navigation/uk.yml:10`, `errors/uk.yml:64`, `notifications/uk.yml:24`, `settings/uk.yml:9`); «попередження» — `alerts/uk.yml:6-7,78` (саме `alerts`-домен, 3 сайти); «Сигнали загрози» — `navigation/uk.yml:88` (окрема лексема, не похідна від жодної з двох інших).

**lv/lt — спільний виняток, якого `translation_audit` НЕ називав** (той документ стверджує «lv (`brīdinājums`) і lt (`įspėjimas`) однорідні» — це вірно для 15+ сайтів кожної мови, АЛЕ НЕ для одного спільного): `trees/lv.yml:8` (`event_types.alert: **Trauksme**` — не «Brīdinājums»!) і `trees/lt.yml:8` (`event_types.alert: **Pavojus**` — не «Įspėjimas»!). Це мітка ТИПУ ПОДІЇ в хроніці дерева (`trees.chronicle.event_types.*`, поруч із `burning`/`fraud`/`homeostasis`/`stress` — категорія, не сутність-нотифікація EwsAlert), і lv/lt НЕЗАЛЕЖНО обрали для неї гостріше слово (тривога/небезпека), відмінне від їхнього ж «попередження»-слова, вжитого в усіх інших 15+ місцях. uk НЕ робить цього розрізнення (`trees/uk.yml:8` теж «Тривога» — той самий корінь, що всюди).

**Питання до 👤:** (а) uk-триада тривога/попередження/сигнали — яка форма канонічна (аудит просив глосарій-присуд, не дав сам). (б) lv/lt: чи розрізнення «категорія-подія» (Trauksme/Pavojus) проти «сутність-нотифікація» (Brīdinājums/Įspėjimas) — свідомий семантичний вибір (і тоді вартий явної анотації в корпусі, щоб не виглядав дрейфом) чи випадковість генерації (і тоді привести до єдиної форми).

### 4.9 actuator — lv 2-way (названо аудитом), lt 3-way (не назван аудитом повністю)

**lv** (`translation_audit` §B назвав пару, тут — повні адреси): «aktuators»/«aktuatora»/«aktuatoram» — `navigation/lv.yml:8-9`, `flash/lv.yml:4-7`, `actuators/lv.yml:3-49` (5 сайтів), `errors/lv.yml:6-9`, ТА `alerts/lv.yml:26-29` (усі 4 `emergency_response_*`). «Izpildmehānisms»/«izpildmehānisma» — `alerts/lv.yml:14-17,95` (5 сайтів: `actuator_fault`, `actuator_fault_unknown`, обидва `actuator_stuck`, коротка мітка).

**lt** (ширше за те, що назвав аудит — ТРЕТЄ слово): «aktuatorius»/«aktuatoriaus»/«aktuatoriui» — `navigation/lt.yml:8-9`, `flash/lt.yml:4-7`, `actuators/lt.yml:3-49`, `errors/lt.yml:6-9`. «Vykdiklis»/«vykdiklio» — `alerts/lt.yml:14-17,95` (той самий набір сайтів, що lv-`izpildmehānisms`). «**pavara**»/«pavaros»/«pavarai» — ТРЕТЄ слово, `alerts/lt.yml:26-29` (усі 4 `emergency_response_*` — той самий набір, де lv каже «aktuators»!).

**Питання до 👤:** для lv — «aktuators» (майоритарний, 9 сайтів) чи «izpildmehānisms» (5 сайтів, живий клік-шлях: тривога називає пристрій одним словом, сторінка — іншим — `translation_audit` вже це відзначив як живу проблему UX). Для lt — та сама вісь, АЛЕ з ТРЬОМА кандидатами замість двох: «aktuatorius» (8 сайтів) / «vykdiklis» (5) / «pavara» (4) — жоден не є очевидною більшістю.

### 4.10 ledger — uk тримає «Леджер» там, де решта каже «Реєстр»

- uk: `navigation/uk.yml:28` (`ledger: **Леджер**`, транслітерація) проти `navigation/uk.yml:71` (`blockchain_ledger: **Реєстр** блокчейну`), `wallets/uk.yml:43` (`ledger_title: **Реєстр** On-Chain транзакцій`), `blockchain_transactions/uk.yml:8,24` (`**Реєстр** блокчейну`). «Реєстр» — 4 сайти, «Леджер» — 1.
- lv: одностайно «virsgrāmata» — `navigation/lv.yml:28,71`, `wallets/lv.yml:43`.
- lt: «(sandorių/grandinės) knyga» на всіх трьох сайтах, з незначною варіацією формулювання (не лексичний розкол) — `navigation/lt.yml:28` («Sandorių knyga»), `navigation/lt.yml:71` («Blokų grandinės knyga»), `wallets/lt.yml:43` («Grandinės sandorių knyga»).

**Питання до 👤:** чи привести uk `navigation/uk.yml:28` до «Реєстр» (майоритарна форма) — зауваж, що «реєстр» в uk-корпусі одночасно несе значення «registry» (organizations/gateways/users) і «register»-дієслово (maintenance) — тобто вибір «Реєстр» для ledger далі перевантажує вже багатозначне слово; альтернатива — узаконити «Леджер» як термін і РОЗвантажити «реєстр» деінде.

### 4.11 firmware (lt) — семантичний концерн, названий аудитом, без вердикту

`translation_audit_2026_07.md`, «Відкрите з другої хвилі»: «lt: `programinė įranga` для **firmware** — це software... вибір lt-терміна потребує носія». Підтверджено — lt внутрішньо ОДНОСТАЙНИЙ (`navigation/lt.yml:23,74`, `alerts/lt.yml:33-34,101-103`, `flash/lt.yml:17,20`, `gateways/lt.yml:20`, `firmwares/lt.yml:3` — усі «programinė įranga»/«programinės įrangos»), тобто це НЕ внутрішня розбіжність, а питання, чи саме ЦЕ слово — правильний термін для «firmware» (апаратно-вбудований код), а не для «software» загалом; lv для порівняння має власний неологізм «programmaparatūra» (не збігається з жодним «software»-словом).

### 4.12 batch — uk транслітерує, lv/lt перекладають

- uk: `alerts/uk.yml:40` («Ризик втрати **батчів**» — транслітерація).
- lv: `alerts/lv.yml:40` («**Partiju** zuduma risks» — рідне слово «партія» в сенсі «партія товару/даних»).
- lt: `alerts/lt.yml:40` («**Partijų** praradimo rizika» — те саме рідне слово).

Це той самий сайт (`gateway_weak_signal`), тому порівняння точне. `translation_audit` згадував пару «батч ⟷ пакет» у §B, але «пакет» у жодній формі в поточному корпусі НЕ знайдено (`grep -rn 'акет' config/locales/*/uk.yml` — порожньо) — можливо, уже вирівняно з часу аудиту, або згадка була про інший шар (не `config/locales`). Не вигадую відповідність — фіксую лише те, що є.

**Питання до 👤:** чи «батч» узаконити як термін (money-path/телеметрійний жаргон, прийнятний), чи перевести на «партія» слідом за lv/lt.

### 4.13 transaction — lv/lt мають частково закритий, частково відкритий розкол

- lv: майоритарно «darījums»/«Darījuma»/«darījumu» (15+ сайтів — `system_audits/lv.yml:17`, `navigation/lv.yml:13,58`, `blockchain_transactions/lv.yml:5,7,13,31-32,56-57,67`, `wallets/lv.yml:41,43`, `reports/lv.yml:33-34,65`); винятково «transakcija» — `alerts/lv.yml:20` (`burn_failure_ambiguous`).
- lt: майоритарно «sandoris»/«Sandorio»/«sandorių» (13+ сайтів — аналогічний набір); «operacija» на ТРЬОХ сайтах — `blockchain_transactions/lt.yml:5` (`audit_aria: Operacijos`), `blockchain_transactions/lt.yml:7` (`explorer_aria: operaciją`), `alerts/lt.yml:20` (`burn_failure_ambiguous: operacija`).

`translation_audit_2026_07.md`, Пʼята хвиля, уже ЗВАЖИВ цю пару — але лише для нового ключа breadcrumb (`darījum* проти transakcij* 8:2 у lv, sandori* проти operacij* 6:4 у lt, тож взято перше») — тобто рішення застосоване ОДНІЄЮ новою міткою (`navigation.breadcrumb.segments.on_chain` тощо), не ретроактивно до наявного корпусу. Три сайти вище (особливо `blockchain_transactions/lt.yml:5,7` — самі заголовки на сторінці блокчейн-транзакцій) лишаються незачепленими.

**Цікаво:** ОБИДВІ мови мають свій виняток на ТОМУ Ж ключі — `alerts.burn_failure_ambiguous` (`alerts/lv.yml:20`, `alerts/lt.yml:20`) — тобто цей один алерт послідовно «випадає» з майоритарної форми в ОБОХ мовах.

**Питання до 👤:** чи поширити вже ухвалений напрямок (darījums/sandoris) на решту корпусу — це узгоджується з `translation_audit`'s власним підрахунком, тож імовірно найдешевший «так».

---

## 5. Терміни, яких немає в UI

Чесно — жодна форма жодною мовою (включно з `en`) не знайдена в `config/locales/`; переклад НЕ придуманий.

- **downlink** — жодного `Downlink`/`даунлінк`/`lejupsaite`/`nusiuntimas` в жодному з 136 файлів (включно з `en`). Концепція живе на firmware-стороні (`03_02`), не в Rails UI.
- **stake** (staking, як окрема від slashing концепція) — жодного `stake`/`стейк`/`стейкінг`. У SilkenNet немає UI-поверхні proof-of-stake; `slashing` — єдиний вжитий термін цього кластера (§4.6).
- **backing asset** — жодної форми жодною мовою. `translation_audit` §B згадував «backing asset→основні засоби» як приклад класу калек — у живому корпусі сьогодні цього рядка нема (або вже вирівняно, або приклад був ілюстративний).
- **leaderboard** — те саме; «таблиц*» теж не знайдено жодною мовою в ролі цього поняття (DataTable-компоненти отримують мітки по колонках, не спільним словом «таблиця»).
