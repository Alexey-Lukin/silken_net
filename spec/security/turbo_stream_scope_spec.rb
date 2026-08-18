# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/turbo_stream_inventory")

# Вісь СКОУПУ Turbo-стріму — окрема від осі існування («чи є кому слухати»),
# і до цього гейта її не тримав ніщо. `00_07` SEC.25 / UI.4, канон `04_04 §8.1`.
#
# 🔴 Чому підписка, а не продюсер, є точкою істини. Підписане імʼя стріму —
# непідробний HMAC (перевірено рантаймом), тож ЄДИНИЙ спосіб його дістати —
# щоб сторінка тобі його відрендерила. Отже тенант-ізоляція вирішується на боці
# ПІДПИСНИКА: чи контролер, що рендерить `turbo_stream_from`, віддає це імʼя лише
# членам організації-власника.
#
# 🔴 Класифікація першого аргументу — ДИСПЕТЧЕР, а не перевірка. Це важливо
# сформулювати точно, бо я спершу спроектував гейт навпаки й помилився:
# пʼять правдивих замірів про токен стосувалися обох класів ОДНАКОВО, тож
# ранжувати ними класи неможливо (`ssot-maintenance` §Guard-craft #22). Клас
# каже лише, ЯКИЙ доказ мусить існувати:
#   · `record_ref`/`record_array` (AR-запис) → імʼя не несе org-токена взагалі,
#     тож потрібна спека крос-фетч-ВІДМОВИ (чужа сутність → 404/403);
#   · `derived_org` (`TurboStreams::Name.org(...)`) → потрібен two-subject пін
#     ІМЕНІ (двоє глядачів дістають РІЗНІ стріми — з одним підміна на
#     `Organization.first` лишає приклад зеленим);
#   · `derived_gateway` (`TurboStreams::Name.gateway_ota(...)`) → імʼя org-токена
#     не несе, безпечне лише ТРАНЗИТИВНО, тож потрібен пін РІВНОСТІ МНОЖИНИ;
#   · `bare_string`/`bare_symbol` (голе глобальне імʼя) → червоне за
#     замовчуванням. Саме цим був `"telemetry_stream"`, і саме так витік
#     віддавав payload чужих Королев кожному автентифікованому глядачу.
#
# 🧱 Рядкове імʼя стріму більше не пишеться руками НІ НА ЯКОМУ боці тракту — його
# виводить один дім `lib/turbo_streams/name.rb`, який кличуть і підписники, і
# продюсери. Це прибирає клас «продюсер і підписник на РІЗНИХ АДРЕСАХ»
# конструктивно, а не ловить постфактум: до дому чотири імені жили в 11 рукописних
# копіях через два шари. ⚠️ Прецедентів розходження самого ІМЕНІ репо не має —
# три відомі катастрофи цього роду були на СУСІДНІЙ осі (target-id / record-форма),
# і дім їх не накриває. Виправдання інше: втрата `_org_` дає ВИТІК, а не мертвий
# стрім. Тому `scoped_string`/`unscoped_interpolation` на підписці тепер ЧЕРВОНІ
# як форма, а не лише як скоуп.
#
# 🔒 Три стелі, названі чесно — інакше зелене читається як «перевірено»:
#   1. Реєстр пінить ІМʼЯ приклада-доказу, не його доказовість. Перейменований
#      або вихолощений приклад із тією ж назвою пройде. Це слабше, ніж звучить
#      (`ssot-maintenance` §Guard-craft #5), але сильніше за «файл існує».
#   2. ПОХОДЖЕННЯ org-токена статично невидиме: `@organization.id` виглядає
#      однаково, чи прийшла організація з сесії, чи з параметра запиту.
#   3. Гейт сканує `app/**/*.rb` цілком (не лише `app/views/**`, як тут доти
#      стояло — шапка суперечила власному глобу нижче). Підписка, зібрана в
#      обхід хелпера (руками через `tag.turbo_cable_stream_source`), сюди не
#      потрапить. ⚠️ Раніше тут стояло «а саме так її доведеться писати, якщо
#      колись додаватимемо TTL» — TTL відкинуто виміром (прострочений токен на
#      реконекті = безшумна назавжди смерть живості: `Subscription` ctor
#      заморожує ідентифікатор, а елемент не визначає `rejected`-колбека), тож
#      обхід хелпера більше не запланований і стеля лишається чисто теоретичною.
#   4. 🔴 КЛАС виводиться з форми ІМЕНІ, а потрібна форма доказу залежить від
#      КАРДИНАЛЬНОСТІ сторінки — цього екстрактор не бачить у принципі, тож це
#      декларація, не виведення. `unscoped_interpolation` накриває два різні
#      випадки: власний атрибут ОДНОГО запису (`Gateways::Show` — скоуп
#      транзитивно доведений спільним фетчем ПЕРЕД `respond_to`, недоведеним
#      лишалось саме імʼя) і цикл по КОЛЕКЦІЇ (`Firmwares::Index` — там дефект
#      виглядає як ЗАЙВИЙ стрім, тому рівність множини несуча). Обидва тепер
#      пінені рівністю множини на HTML-гілці; якщо додаватимеш третій сайт цього
#      класу — питай не «яка форма імені», а «скільки стрімів сторінка може
#      відрендерити».
RSpec.describe "Turbo stream scope axis" do # rubocop:disable RSpec/DescribeClass
  # Обовʼязок доказу на кожен сайт підписки. Ключ — ФАЙЛ (не `file:line`:
  # номери рядків зсуваються, а підписка у файлі рівно одна).
  let(:obligations) do
    {
      "app/views/components/telemetry/live_stream.rb" => {
        kind: :derived_org,
        proof: "spec/requests/api/v1/telemetry_controller_spec.rb",
        example: "subscribes each viewer to their OWN organization stream"
      },
      "app/views/components/alerts/index.rb" => {
        kind: :derived_org,
        proof: "spec/requests/api/v1/alerts_controller_spec.rb",
        example: "subscribes each viewer to their OWN organization alert stream"
      },
      "app/views/components/dashboard/home.rb" => {
        kind: :derived_org,
        proof: "spec/requests/api/v1/dashboard_controller_spec.rb",
        example: "subscribes to exactly the domains its event feed is built from"
      },
      "app/views/components/dashboard/map.rb" => {
        kind: :derived_org,
        proof: "spec/requests/api/v1/dashboard_controller_spec.rb",
        example: "subscribes each viewer to their OWN organization map stream"
      },
      "app/views/components/blockchain_transactions/index.rb" => {
        kind: :derived_org,
        proof: "spec/requests/api/v1/blockchain_transactions_controller_spec.rb",
        example: "subscribes each viewer to their OWN organization ledger stream"
      },
      "app/views/components/firmwares/index.rb" => {
        kind: :derived_gateway,
        proof: "spec/requests/api/v1/firmwares_controller_spec.rb",
        example: "subscribes only to the viewer's OWN gateways' OTA channels"
      },
      "app/views/components/gateways/show.rb" => {
        kind: :derived_gateway,
        proof: "spec/requests/api/v1/gateways_controller_spec.rb",
        example: "subscribes only to the gateway's OWN OTA channel"
      },
      "app/views/components/clusters/show.rb" => {
        kind: :record_ref,
        proof: "spec/requests/api/v1/clusters_controller_spec.rb",
        example: "returns 404 for a cluster from another organization"
      },
      "app/views/components/actuators/show.rb" => {
        kind: :record_ref,
        proof: "spec/requests/api/v1/actuators_controller_spec.rb",
        example: "returns 404 for an actuator from another organization"
      },
      "app/views/components/wallets/show.rb" => {
        kind: :record_ref,
        proof: "spec/requests/api/v1/wallets_controller_spec.rb",
        example: "when the wallet belongs to another organization"
      }
    }
  end

  # Голе глобальне імʼя — це той самий клас, що дав живий крос-тенант витік.
  let(:unscoped_kinds) { %i[bare_string bare_symbol] }

  # Рукописне імʼя, що НЕ є голим глобальним: скоуп у ньому, може, і правильний,
  # але виведене воно окремою копією, тож розійтись із другим боком може будь-коли.
  # Свідомо НЕ перетинається з `unscoped_kinds` — щоб одна поломка світилась в
  # одному прикладі з правильною інструкцією, а не в двох.
  let(:handwritten_kinds) { %i[scoped_string unscoped_interpolation] }

  # На боці ПІДПИСКИ (де мінтиться capability-токен) легальні лише два джерела
  # імені: благословенний дім або сам AR-запис. `:indirect` — це локал/чужий
  # метод, тобто саме та невидимість, за яку гейт критикували: статично не
  # скажеш, чи ім'я взагалі скоуплене.
  #
  # 🔴 На боці ПРОДЮСЕРА `:indirect` теж більше НЕ вільний — і тут доти стояло
  # протилежне («лишається легальним, бо локал є нормальною формою»). Заміром
  # проти історичного коду це виявилось найдорожчою поблажкою гейта: **сім**
  # сайтів, знятих як «продюсер у порожнечу», адресували стрім саме непрозоро —
  # параметром методу (`broadcast_final_state(command, organization)` ×2 ·
  # `broadcast_slashing_event(contract, …)`), локалом з `||`-ланцюга (`org` ×2),
  # ланцюгом викликів (`insurance.cluster.organization`) і голим `self`
  # (`Wallet` слав у власний стрім, тоді як підписник слухав `[wallet, :transactions]`).
  # Тобто клас, який гейт пропускав, і є фактичною популяцією дефектів поверхні.
  #
  # Розрізняє їх не резолвер (значення знати не треба ніколи), а походження:
  # локал, ПРИСВОЄНИЙ із дому, лишається легальним — це рівно те, що робить
  # `unpack_telemetry_worker` (імʼя вживається двічі, тож винесене в змінну).
  let(:opaque_kinds) { %i[indirect] }

  let(:app_files) { Dir[Rails.root.join("app/**/*.rb")].sort }
  let(:subscriptions) { TurboStreamInventory.subscriptions(app_files) }
  let(:producers) { TurboStreamInventory.producers(app_files, methods: gem_broadcast_methods) }

  # Джерело істини для «що є броадкаст» — САМ гем, не наш патерн. Патерн хибний
  # в обидва боки (виміряно): `broadcast_\w*_to` пропускає не-`_to` форми,
  # `broadcast_\w+` ловить 22 власні хелпери застосунку. Дериваний набір ще й
  # переживає апгрейд turbo-rails без правки гейта.
  let(:gem_broadcast_methods) do
    (Turbo::Streams::Broadcasts.public_instance_methods(false) +
     Turbo::Broadcastable.public_instance_methods(false))
      .map(&:to_s).grep(/\Abroadcast_/).uniq
  end
  # Курований перелік ФАЙЛІВ-продюсерів. 🔴 Тут раніше стояла підлога на КІЛЬКІСТЬ
  # викликів (`>= 12`), і вона впала на першому ж чесному рефакторі: виніс дубльований
  # org-броадкаст `EwsAlert` у власний метод — викликів стало 11, гейт почервонів на
  # покращенні. Це рівно та вада, про яку попереджає власне design-правило
  # (`ssot-maintenance` §Guard-craft, «пінь інваріант, а не лічильник, що росте»):
  # лічильник карає за видалення й ремонт. Файлове покриття стабільне до внутрішніх
  # рефакторів і лишається tripwire'ом у два боки — зникнення файла тут червоніє.
  # (Бік ПІДПИСКИ власного канарка не потребує: реєстр обовʼязків звіряється в
  # обидва боки нижче, тож осліплий екстрактор дає 8 мертвих обовʼязків = червоне.)
  let(:producer_files) do
    %w[
      app/models/blockchain_transaction.rb
      app/models/ews_alert.rb
      app/models/maintenance_record.rb
      app/models/organization.rb
      app/models/tree.rb
      app/models/wallet.rb
      app/services/downlink/pending_queue_service.rb
      app/workers/actuator_command_worker.rb
      app/workers/ota_transmission_worker.rb
      app/workers/unpack_telemetry_worker.rb
    ]
  end

  def rel(path) = Pathname.new(path).relative_path_from(Rails.root).to_s


  # 🔒 Стеля, названа чесно, бо файлове покриття купило стабільність ЦІНОЮ
  # чутливості: воно бачить «файл узагалі видний», а не «всі його виклики видні».
  # `ews_alert.rb` тримає три броадкасти, тож втрата ОДНОГО з них лишила б цей
  # приклад зеленим (стара підлога на кількість почервоніла б — і саме тому
  # `unpack_telemetry_worker` окремо пінований ТОЧНОЮ двійкою нижче: там цю
  # сліпоту виміряно). Тобто вибір свідомий: канарок стереже орієнтацію
  # екстрактора, а повноту в межах файла — окремі спеки продюсерів.
  it "is a live check (every known producer file is still discovered)" do
    missing = producer_files - producers.map { |p| rel(p.file) }.uniq

    expect(missing).to be_empty, <<~MSG
      продюсера більше не видно — або броадкаст свідомо знято (тоді приберіть файл
      із переліку тим самим комітом), або екстрактор осліп. Знайдено: #{missing.join(', ')}
    MSG
  end

  # Зворотний напрямок — дзеркало «assigns every subscription site a proof
  # obligation». Без нього перелік гниє МОВЧКИ: новий продюсер-файл ніде не
  # реєструється, і канарок вище лишається зеленим, стережучи лише старе.
  it "forces a NEW producer file into the curated list" do
    unlisted = producers.map { |p| rel(p.file) }.uniq - producer_files

    expect(unlisted).to be_empty, <<~MSG
      новий файл-продюсер. Додайте його в `producer_files` — це не бюрократія:
      перелік і є тим, що робить канарок вище здатним побачити зникнення. Плюс
      перевірте, чи імʼя стріму йде через `TurboStreams::Name`. Знайдено:
      #{unlisted.join(', ')}
    MSG
  end

  it "collects the single-line call form the regex extractor cannot see" do
    single_line = producers.select { |p| p.file.end_with?("unpack_telemetry_worker.rb") }

    expect(single_line.size).to eq(2), <<~MSG
      саме тут виміряно провал регекс-екстрактора (`spec/i18n/broadcast_payload_invariance_spec.rb`
      бачить 1 із 2, бо вимагає багаторядкової форми). Якщо тут знову 1 — AST-екстрактор
      деградував до тієї ж сліпоти, і гейт, якому потрібен ПОВНИЙ набір, став хибно-зеленим.
    MSG
  end

  it "assigns every subscription site a proof obligation" do
    unregistered = subscriptions.map { |s| rel(s.file) }.uniq - obligations.keys

    expect(unregistered).to be_empty, <<~MSG
      новий Turbo-стрім без обовʼязку доказу. Додай запис у `obligations`: клас
      першого аргументу диктує форму доказу (див. шапку). Знайдено: #{unregistered.join(', ')}
    MSG
  end

  it "has no dead obligation (a registry row is a tripwire, not a list)" do
    dead = obligations.keys - subscriptions.map { |s| rel(s.file) }

    expect(dead).to be_empty,
      "підписки більше немає, а обовʼязок лишився — приберіть: #{dead.join(', ')}"
  end

  # ЦЕ і є вісь скоупу: звуження/розширення імені стріму мусить стати видимим.
  it "keeps every stream name in the class its proof was written for" do
    drifted = subscriptions.filter_map do |site|
      expected = obligations[rel(site.file)]&.dig(:kind)
      next if expected.nil? || expected == site.arg_kind

      "#{rel(site.file)}:#{site.line} — реєстр каже #{expected}, код дає #{site.arg_kind}"
    end

    expect(drifted).to be_empty, <<~MSG
      клас імені стріму змінився, а доказ лишився написаним під старий клас —
      найгірший напрямок цієї осі (`scoped_string` → `bare_string` = повернення
      витоку SEC.25). Перепиши доказ під новий клас, потім онови реєстр:
      #{drifted.join('; ')}
    MSG
  end

  it "keeps every named proof example alive" do
    missing = obligations.filter_map do |site, duty|
      path = Rails.root.join(duty[:proof])
      next "#{site} → #{duty[:proof]} (файла немає)" unless File.exist?(path)
      next if File.read(path).include?(duty[:example])

      "#{site} → #{duty[:proof]} не містить «#{duty[:example]}»"
    end

    expect(missing).to be_empty, <<~MSG
      названий доказ зник або перейменований — обовʼязок став вказівником у порожнечу:
      #{missing.join('; ')}
    MSG
  end

  # Інваріант, який канон (`04_04 §8.1`) і скіл `frontend` декларували ПРОЗОЮ, а
  # не тримало ніщо: успадкований `broadcast_*` без `_to` адресує стрім самим
  # записом і дефолтиться на `to_partial_path` — а партіалів моделей у репо НЕМА
  # взагалі, тож рендер-форми кидають `ActionView::MissingTemplate` СИНХРОННО у
  # місці виклику (прецедент ARCH.67: такий виклик у money-сервісі обірвав
  # батч-цикл, лишивши `locked_balance` замороженим). `broadcast_refresh` не
  # впаде — але створить стрім без імені й без обовʼязку доказу.
  it "never calls a model's inherited broadcast_* (implicit self-stream)" do
    implicit = producers.select { |p| p.arg_kind == :implicit_self }
                        .map { |p| "#{rel(p.file)}:#{p.line} — #{p.method}" }

    expect(implicit).to be_empty, <<~MSG
      успадкований `broadcast_*` моделі: рендер-форми кидають MissingTemplate у
      місці виклику (партіалів моделей нема), а `broadcast_refresh` тихо створює
      стрім, якого не знає ані реєстр §8.1, ані цей гейт. Використовуй явний
      `Turbo::StreamsChannel.broadcast_*_to` з `html:`. Знайдено: #{implicit.join(', ')}
    MSG
  end

  it "mints no stream name by hand — every string name comes from TurboStreams::Name" do
    offenders = (subscriptions + producers)
                .select { |s| handwritten_kinds.include?(s.arg_kind) }
                .map { |s| "#{rel(s.file)}:#{s.line} (#{s.arg_pattern.inspect})" }

    expect(offenders).to be_empty, <<~MSG
      рукописне імʼя стріму. Скоуп у ньому може бути й правильний — проблема в
      тому, що воно ВИВЕДЕНЕ ОКРЕМОЮ КОПІЄЮ, тож розійтись із другим боком тракту
      може будь-коли, а виглядатиме це як тихо мертвий стрім (репо ловило цей клас
      тричі — уже після відвантаження). Проведи через `lib/turbo_streams/name.rb`:
      `TurboStreams::Name.org(:kind, org)` або `.gateway_ota(gateway)`. Знайдено:
      #{offenders.join(', ')}
    MSG
  end

  it "accepts only the blessed home or an AR record on the SUBSCRIBE side" do
    offenders = subscriptions
                .select { |s| opaque_kinds.include?(s.arg_kind) }
                .map { |s| "#{rel(s.file)}:#{s.line}" }

    expect(offenders).to be_empty, <<~MSG
      непрозоре джерело імені на боці підписки (локал або чужий метод). Саме тут
      мінтиться capability-токен, тож статична невидимість «а чи скоуплене це
      імʼя взагалі» тут неприйнятна: або `TurboStreams::Name`, або сам AR-запис.
      Знайдено: #{offenders.join(', ')}
    MSG
  end

  # Дзеркало прикладу вище, на боці ПРОДЮСЕРА — і саме воно, а не «пара
  # продюсер⟷підписник», відповідає фактичній популяції дефектів цієї поверхні.
  #
  # ⚠️ Чому НЕ пара множин, хоч `00_07` UI.4 довго прописував саме її: виміряно,
  # що пара ловить 1 із 12 історичних дефектів чистого приросту й приїжджає з
  # вбудованим винятком (tombstone `organization.rb` адресує ПОКИНУТУ епоху, тобто
  # не має підписника ЗА ПРИЗНАЧЕННЯМ). Цей інваріант ловить сім — бо дефект тут
  # має форму «продюсер адресує непрозоро», а не «адреси двох боків розійшлись».
  it "accepts an opaque producer name ONLY when the local came from the blessed home" do
    offenders = producers
                .select { |p| opaque_kinds.include?(p.arg_kind) }
                .reject { |p| p.arg_pattern && TurboStreamInventory.blessed_locals(p.file).include?(p.arg_pattern) }
                .map { |p| "#{rel(p.file)}:#{p.line} (#{p.arg_pattern || 'self / ланцюг викликів'})" }

    expect(offenders).to be_empty, <<~MSG
      продюсер адресує стрім НЕПРОЗОРО — параметром методу, ланцюгом викликів або
      `self`. Саме так адресували стрім усі продюсери, зняті як «у порожнечу»: ім'я
      не видно ні гейту, ні читачеві, тож розходження з підписником помічається
      лише тим, що живі оновлення тихо не приходять. Виведи ім'я через
      `TurboStreams::Name` — прямо у виклику або в локал (`stream = TurboStreams::Name.org(...)`),
      якщо воно потрібне двічі. Знайдено: #{offenders.join(', ')}
    MSG
  end

  it "has no bare global stream name on either side of the tract" do
    offenders = (subscriptions + producers)
                .select { |s| unscoped_kinds.include?(s.arg_kind) }
                .map { |s| "#{rel(s.file)}:#{s.line} (#{s.arg_pattern.inspect})" }

    expect(offenders).to be_empty, <<~MSG
      голе глобальне імʼя стріму: підписатись може будь-хто, кому сторінка
      відрендерилась, а сторінка не звужена нічим. Саме цим був `"telemetry_stream"`
      (`00_07` SEC.25 — живий крос-тенант витік). Скоупни імʼя або доведи скоуп
      спекою й заведи явний обовʼязок. Знайдено: #{offenders.join(', ')}
    MSG
  end
end
