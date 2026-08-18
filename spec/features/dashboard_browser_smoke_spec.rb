# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# ПЕРШИЙ браузерний тест у цьому дереві.
#
# 🔴 Чому він потрібен був давно. Уся машинерія (cuprite + capybara + CI-джоба
# `feature-test`, яка піднімає Postgres і Redis на КОЖНОМУ ruby-PR) стояла зібрана
# й зелена — при нулі файлів у `spec/features/`. Тобто найдорожча джоба пайплайну
# виконувала нуль прикладів і повідомляла успіх: гейт, що не бачить нічого.
# Бракувало навіть `require "capybara/rspec"` — DSL не був підключений, бо нікому
# не був потрібен.
#
# 🔴 **[TEST.7] Тут доти стояло, що «наш JS у feature-тестах не виконується», а
# причина — рендер-шлях запиту Rails. Обидві половини спростовано виміром
# 2026-07-31, і винне було НЕ Rails.** Глушив `spec/support/layout_asset_stubs.rb`:
# він БЕЗУМОВНО повертав `""` замість `stylesheet_link_tag` /
# `javascript_importmap_tags`, тож сторінка приїжджала без importmap і
# `window.Stimulus` лишався `undefined`. Діагноз тричі шукали в чужому коді, бо
# `bin/rails runner` віддавав теги коректно — рівно тому, що НЕ вантажить
# `spec/support/`. Тепер фолбек ловить лише реальний `Propshaft::MissingAssetError`,
# і Stimulus та Turbo в браузері живі: `typeof window.Stimulus` = `"object"`,
# `turbo:morph` відтворюється керовано. ⚠️ **Умову доти було названо хибно**
# (виправлено 2026-08-17): стояло «при зібраних assets (`rails assets:precompile`
# — крок є у CI-джобі `feature-test`)». Такого кроку в тій джобі НЕМА і не було —
# `ci.yml` прямо над нею пише, що precompile пробували й зняли того ж дня, бо
# манифест перемикає Propshaft на Static. Потрібно й достатньо
# `bin/rails tailwindcss:build` (він у `setup-rails-test`): Propshaft у dev/test
# резолвить із load-path динамічно. Клас заяви — `04_06 §B.1.4`.
#
# ✅ **[TEST.7] Мапа більше НЕ виняток — і записана тут причина була хибна.**
# Тут стояло, що `map#connect()` «не спрацьовує», бо модуль не приїжджає з CDN.
# Механізм інший і ширший: `import L from "leaflet"` у `map_controller.js` —
# СТАТИЧНИЙ імпорт верхнього рівня, тож недосяжний CDN валив завантаження всього
# модуля, і Stimulus не реєстрував контролер узагалі (8 identifiers → 7, зникав
# саме `map`). Звідси й невідтворюваність: результат визначала доступність
# чужого домену в момент прогону, тому два прогони того самого коду давали
# `.leaflet-pane` = 7 і 0. Leaflet тепер локальний (JS + CSS + images), що
# доведено мутацією: із заблокованим `jspm.io` картина не змінюється.
# Інваріант походження стереже `spec/security/importmap_locality_spec.rb` — пін
# на «мапа будується» його НЕ замінює, бо при живому CDN він зелений і з
# зовнішнім піном.
#
# Тому цей файл пінить дві речі: серверний рендер у справжньому браузері (те, що
# інакше недоказовне — request-спека бачить `media_type` і тіло, браузер бачить,
# що з тим тілом сталося) і той факт, що НАШ Stimulus-контролер справді
# виконується.
RSpec.describe "Dashboard in a real browser", :js do
  let(:organization) { create(:organization) }
  let(:password)     { "browser-smoke-pass-1" }
  let!(:user) { create(:user, :admin, organization: organization, password: password) }

  # Логін живе в `spec/support/feature_helper.rb` — там же конвенція шару й
  # виміряні стелі. Локальна копія була б першою дуплікацією на новій поверхні.

  # [SEC.25] Дзеркало request-піна, але в середовищі, де він і має значення. Доти
  # реальний користувач після протермінування сесії діставав сирий
  # `{"error":"Authentication required..."}` — і саме браузер є єдиним місцем, де
  # видно, що тепер це справжня сторінка з формою входу, а не текст, який Chrome
  # показує як plain text.
  it "shows the login PAGE (not a JSON blob) when the session is gone" do
    sign_in_as(user, password: password)

    # Найчесніша симуляція «сесія протухла»: салт-стемп у cookie перестає збігатися
    # (SEC.16) — рівно те, що робить зміна пароля з іншого пристрою.
    user.update!(password: "rotated-elsewhere-pass-2")
    # ⚠️ Свідомо голий `visit`, НЕ `visit_ok` [UI.3]: тут не-200 і Є предметом прикладу
    # — протермінована сесія мусить віддати 401 зі СТОРІНКОЮ логіну, а не з JSON. Пін
    # на 200 тут забороняв би саме ту поведінку, яку приклад доводить; ⊥ решта
    # браузерних прикладів ходить `visit_ok`, бо для них не-200 означає, що далі
    # міряється `Errors::Page`. Статус перевіряється нижче ЯВНО.
    visit "/dashboard"

    expect(page.status_code).to eq(401), "сесія протухла — очікуємо 401 зі сторінкою логіну"

    expect(page).to have_field("email")
    expect(page).to have_css("form[action='/login']")
    expect(page).to have_no_text('{"error"')
  end

  # [TEST.7] Сценарій, який до локального піна був недоказовним У ПРИНЦИПІ.
  #
  # ⚠️ Він же несе роль, яку доти виконував окремий приклад на тумблері теми
  # («доводить виконання ВЛАСНОГО Stimulus-контролера, а не лише присутність
  # Stimulus»). Тумблер знято разом із клієнтським вибором теми, і предмет того
  # прикладу зник — але роль лишилась тут, причому в сильнішій формі: там
  # доводився обробник кліку, тут — увесь ланцюг від серверної розмітки до
  # намальованого маркера.
  #
  # Пінить увесь ланцюг, а не факт завантаження модуля: сервер рендерить
  # прихований `map_node_*` → Stimulus кличе `nodeTargetConnected` → контролер
  # ставить маркер. `.leaflet-pane` існує лише після `L.map()`, а
  # `.custom-tree-marker` — лише після `updateMarker`, тож ці два асерти
  # розрізняють «Leaflet піднявся» і «наші дані до нього доїхали».
  #
  # ⚠️ `visible: :all` обов'язковий: контейнер мапи має нульову висоту, доки
  # Tailwind не зібрано, а вузли даних свідомо `hidden` — без цього приклад
  # ловив би стан CSS, а не роботу контролера.
  it "boots Leaflet locally and plots a geolocated tree" do
    tree = create(:tree, cluster: create(:cluster, organization: organization))

    sign_in_as(user, password: password)

    expect(page).to have_css("#map_node_#{tree.id}", visible: :all)
    expect(page).to have_css(".leaflet-pane", visible: :all)
    expect(page).to have_css(".custom-tree-marker", visible: :all)

    # 🔴 Атрибуція тайлів — ВИМОГА ЛІЦЕНЗІЇ (OSM ODbL §4.3 + умови CARTO), і доти
    # її ЗАМІЩАВ наш власний підпис. Пін дивиться на вивід САМОГО Leaflet, а не на
    # джерело контролера: зовнішній якір тут і є суттю — карта мусить ПОКАЗАТИ
    # джерело, а не згадати його в коді.
    attribution = find(".leaflet-control-attribution", visible: :all).text
    expect(attribution).to include("OpenStreetMap")
    expect(attribution).to include("CARTO")
  end

  # 🔴 [UI.11 крок 3] Половина, недоказовна нижче В ПРИНЦИПІ: Turbo в компонентній
  # спеці не існує, а весь дефект жив саме в тому, що робить Turbo з вузлом при
  # візиті — permanent-вузол пересаджується, і локалізований рядок В АТРИБУТІ
  # застрягає мовою першого візиту, невидимо для зрячого QA.
  #
  # ⚠️ НОСІЙ ПЕРЕЇХАВ, інваріант — ні. Доти піном був `aria-label` тумблера
  # теми; тумблер знято разом із клієнтським вибором теми, тож приклад цілиться
  # в `LocaleSwitcher` — той несе рівно таку саму конструкцію (локалізований
  # `aria-label` на вузлі, що переживає Turbo-візит) і при цьому САМ виконує
  # дію, тобто пін став ще ближчим до місця відмови.
  #
  # ⚠️ Чесно про силу піна: ДО зміни він теж був би зелений, тобто він доводить
  # не фікс, а ІНВАРІАНТ — і червоніє рівно на рецидиві, яким цей клас
  # повертається: хтось ставить permanent «щоб не блимало», і ім'я мовчки
  # застрягає. Статичну половину тримає `spec/quality/no_turbo_permanent_spec.rb`.
  #
  # ⚠️ `document.documentElement` читаємо скриптом, а не `have_css`: Capybara
  # скоупить пошук у `/html/body` (стеля 1 у `feature_helper`), тож `html[lang]`
  # не зматчиться ніколи. Читання йде ПІСЛЯ `have_css`, коли візит уже доїхав.
  it "carries a localized aria-label into the NEW locale after a Turbo language switch" do
    sign_in_as(user, password: password)

    en_label = I18n.t("locale.switcher_label", locale: :en)
    uk_label = I18n.t("locale.switcher_label", locale: :uk)

    expect(page).to have_css("select[aria-label='#{en_label}']")

    select "UA · Українська", from: "locale"

    expect(page).to have_css("select[aria-label='#{uk_label}']")
    expect(page.evaluate_script("document.documentElement.lang")).to eq("uk")
  end

  # 🔴 [UI.11 крок 3] Найважливіший приклад цієї пари, і він існує через ПАМʼЯТЬ,
  # а не через план: зняття `data-turbo="false"` з перемикача мов озброює тракт,
  # який доти був інертним. Механізм морфу вже доведено джерелом (Idiomorph
  # `morphChildren` знімає дітей без пари в новій розмітці, а Stimulus
  # `processRemovedNodes` контейнер не бачить, тож `map#connect` не переграється) —
  # відкинутий як won't-do рівно тому, що ПУСКАЧА не існувало: єдиний
  # same-location redirect дерева стояв саме за цією формою.
  #
  # Тепер пускач можливий, тож інваріант мусить бути виміряним, а не виведеним:
  # після перемикання мови мапа лишається побудованою.
  it "keeps Leaflet alive across a language switch — the one same-location redirect in the tree" do
    tree = create(:tree, cluster: create(:cluster, organization: organization))

    sign_in_as(user, password: password)

    expect(page).to have_css("#map_node_#{tree.id}", visible: :all)
    expect(page).to have_css(".leaflet-pane", visible: :all)

    select "UA · Українська", from: "locale"

    # Спершу чекаємо, що візит доїхав (мова змінилась), і лише потім міряємо мапу —
    # інакше прочитаємо стан ДО навігації й приклад стане тавтологією.
    expect(page).to have_css("select[aria-label='#{I18n.t('locale.switcher_label', locale: :uk)}']")
    expect(page).to have_css(".leaflet-pane", visible: :all)
    expect(page).to have_css(".custom-tree-marker", visible: :all)
  end

  # 🔴 [UI.11] Приклад вище стереже ПУСКАЧ (одна форма зі щитом `advance`), цей —
  # сам МЕХАНІЗМ. Різниця несуча: доти безпека мапи трималась на тому, що на
  # `/dashboard` рівно одна форма й вона екранована; друга форма зробила б морф
  # досяжним, і жоден приклад не почервонів би. Тепер полотно непрозоре для морфу
  # само по собі, тож пускач більше не є частиною доказу.
  #
  # ⚠️ Морф тут викликається НАПРЯМУ вставкою справжнього `<turbo-stream
  # action="refresh">` — це рівно та розмітка, яку шле `broadcast_refresh_to`
  # (`turbo_stream_refresh_tag` без атрибутів, `action_helper.rb:44`), тож
  # приклад їде продовим шляхом клієнта, а не вигаданим.
  # 🔬 Виміряно перед фіксом: панелей було **7**, після морфу — **0**; під
  # `method: "replace"` — 7 → 7. Тобто мутація тут не теоретична.
  it "survives a morph refresh — the canvas declares itself opaque to Idiomorph" do
    create(:tree, cluster: create(:cluster, organization: organization))

    sign_in_as(user, password: password)
    expect(page).to have_css(".leaflet-pane", visible: :all)

    # Ліхтар на ПЕРЕДУМОВУ: без нього приклад був би зелений і тоді, коли морф
    # узагалі не налаштований, тобто доводив би відсутність механізму.
    expect(page.evaluate_script(<<~JS)).to eq("morph")
      document.querySelector('meta[name="turbo-refresh-method"]').content
    JS

    panes_before = page.evaluate_script("document.querySelectorAll('.leaflet-pane').length")
    expect(panes_before).to be_positive

    # 🔴 Ліхтар на ПОДІЮ, а не `sleep`. Перша редакція цього приклада була
    # ВАКУУМНА і показала це мутацією: без слухача морф-скіпу вона лишалась
    # зеленою, бо `have_css` встигав прочитати панелі ДО того, як візит доїхав.
    # Тобто зелене означало «ще не сталось», не «вижило». Turbo шле `turbo:morph`
    # після рендеру (`turbo.js:4034`) — чекаємо саме на нього.
    page.execute_script(<<~JS)
      window.__morphSeen = false;
      document.addEventListener("turbo:morph", () => { window.__morphSeen = true }, { once: true });
      document.body.insertAdjacentHTML('beforeend', '<turbo-stream action="refresh"></turbo-stream>');
    JS

    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until page.evaluate_script("window.__morphSeen === true")
    end

    expect(page.evaluate_script("document.querySelectorAll('.leaflet-pane').length")).to eq(panes_before)
    expect(page).to have_css(".custom-tree-marker", visible: :all)
  end

  # 🔴 [UI.11] Остання ціна morph-на-refresh, і вона НЕ від морфу, а від самого
  # ВІЗИТУ: `mobile_nav` закривався на будь-якому `turbo:visit`, тож алерт-шторм
  # згортав drawer користувачеві під пальцем — сторінка не мінялась, а навігація
  # зникала. Пара обовʼязкова: без другої половини гард, що не закриває НІКОЛИ,
  # лишався б зеленим.
  describe "drawer vs visit" do
    it "stays open when the page merely refreshes under it" do
      sign_in_as(user, password: password)

      page.execute_script("document.querySelector('#mobile-nav-drawer').showModal()")
      expect(page).to have_css("#mobile-nav-drawer[open]", visible: :all)

      page.execute_script(<<~JS)
        window.__morphSeen = false;
        document.addEventListener("turbo:morph", () => { window.__morphSeen = true }, { once: true });
        document.body.insertAdjacentHTML('beforeend', '<turbo-stream action="refresh"></turbo-stream>');
      JS
      Timeout.timeout(Capybara.default_max_wait_time) do
        sleep 0.1 until page.evaluate_script("window.__morphSeen === true")
      end

      expect(page).to have_css("#mobile-nav-drawer[open]", visible: :all)
    end

    it "still closes on a real navigation" do
      sign_in_as(user, password: password)

      page.execute_script("document.querySelector('#mobile-nav-drawer').showModal()")
      expect(page).to have_css("#mobile-nav-drawer[open]", visible: :all)

      page.execute_script("Turbo.visit('/clusters')")

      expect(page).to have_no_css("#mobile-nav-drawer[open]", visible: :all)
    end
  end
end
