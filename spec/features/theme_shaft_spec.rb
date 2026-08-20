# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [UI.1] Тема має РІВНО одну шафу, і нею є середовище — `prefers-color-scheme`.
#
# Доти шаф було дві, і вони розходились: семантичні токени слухали клас `.dark`
# (його ставив клієнтський скрипт із `localStorage`), а сирі `dark:`-утиліти
# Tailwind — операційну систему. Тумблер знято, клас знято, скрипт знято: обидві
# половини тепер компілюються в ОДИН медіа-запит, оголошений у
# `app/assets/tailwind/application.css` (`@custom-variant` + блок токенів).
#
# ⚠️ ФОРМА ПІНА ЗМІНИЛАСЬ РАЗОМ ІЗ МЕХАНІЗМОМ, і це не послаблення.
# Доти інваріант доводився РОЗВЕДЕННЯМ: тумблер в один бік, ОС у другий, і
# розбіжність було видно. Клієнтського важеля більше не існує, тож розводити
# нічим — доводити треба ЗБІГ: при кожній емульованій перевазі ОС токен і
# `dark:`-утиліта мусять опинитись в ОДНОМУ стані. Мутації, на яких це червоніє:
#   · повернути `@custom-variant dark (&:where(.dark, .dark *))` → утиліта
#     перестає діяти взагалі (класу в дереві немає) → падає приклад «темна»;
#   · повернути токени під селектор `.dark` → токен застрягає на світлому
#     значенні в обох прикладах;
#   · зняти `screen and` з однієї з двох половин → розходження видно лише на
#     друці, тож його стереже окремий приклад нижче.
#
# ⚠️ Чому це неможливо довести статично — і чому саме браузером.
#   · Скан бачить РЯДОК у CSS, а не те, під яку шафу Tailwind його скомпілював,
#     і — головне — не те, чи браузер справді перемкнув палітру. ⚠️ Тут доти
#     стояла ще й друга причина («білд у `.gitignore`, тож гейт по ньому був би
#     зелений на порожній множині») — вона ВИМІРЯНО хибна: обидві спек-джоби
#     заходять через `setup-rails-test`, яка робить `tailwindcss:build`. Ризик
#     порожньої множини знімається ліхтарем, не відмовою від якоря
#     (§Guard-craft #68). Браузер тут потрібен із першої причини, не з другої.
#   · Компонентна спека рендерить розмітку без CSS узагалі.
RSpec.describe "Theme: одна шафа, і нею є середовище", :js do
  let(:organization) { create(:organization) }
  let(:password)     { "theme-shaft-pass-1" }
  let!(:user) { create(:user, :admin, organization: organization, password: password) }

  # `StatCard` — носій `shadow-sm dark:shadow-none`, стоїть на дашборді чотири
  # рази. Пінимось за `role="group"` (стабільний контракт компонента), а не за
  # клас: клас — це те, що ми й перевіряємо на чинність.
  let(:card) { 'div[role="group"]' }

  # Значення `--tw-shadow`, яке ставить `shadow-none`. Чому оракул саме такий —
  # у `card_shadow_token` нижче.
  let(:shadow_off) { "0 0 #0000" }

  # Токенна половина. Читаємо ОБЧИСЛЕНИЙ фон `<body>`, а не сире значення
  # змінної: `getPropertyValue('--gaia-surface-base')` віддає текст оголошення
  # (`#050607`) і тому зелений навіть тоді, коли токен нікуди не доїхав. Ті самі
  # оракули використовує `spec/support/contrast_audit.rb`.
  let(:surface_dark)  { "rgb(5, 6, 7)" }
  let(:surface_light) { "rgb(250, 250, 250)" }

  before { sign_in_as(user, password: password) }

  # ── інструменти виміру ──

  # Емуляція переваги ОС. Ставиться ДО візиту: тема тепер застосовується чистим
  # CSS, тобто вже на першому пейнті, без жодного кроку JS.
  def emulate_os(scheme)
    page.driver.browser.page.command(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: scheme } ]
    )
  end

  # 🔴 Прилад мусить свідчити про СЕБЕ, і після зняття тумблера це стало
  # несучим, а не бажаним: CDP лишився ЄДИНИМ важелем, тож при його тихій
  # відмові кожен приклад нижче зелений на порожній множині — тобто атестує
  # рівно той клас, який мав ловити.
  def os_reports_dark?
    page.evaluate_script("window.matchMedia('(prefers-color-scheme: dark)').matches")
  end

  # 🔴 Оракул читає `--tw-shadow`, а НЕ `boxShadow`. У Tailwind v4 `shadow-none`
  # не дає `box-shadow: none`: він ставить `--tw-shadow: 0 0 #0000`, а
  # `box-shadow` лишається композитом `var(--tw-inset-shadow), … , var(--tw-shadow)`,
  # тобто обчислений рядок ЗАВЖДИ є переліком `rgba(0,0,0,0) …` і НІКОЛИ не
  # дорівнює `"none"`. Пін `eq("none")` не здатен пройти, а `not_to eq("none")` —
  # упасти: одна половина вічно червона, друга вічно зелена на порожній множині.
  def card_shadow_token
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{card.to_json})).getPropertyValue('--tw-shadow').trim()"
    )
  end

  def surface_base_token
    page.evaluate_script("getComputedStyle(document.body).backgroundColor")
  end

  def dark_class_present?
    page.evaluate_script("document.documentElement.classList.contains('dark')")
  end

  # ── сам інваріант ──

  it "при ТЕМНІЙ перевазі ОС темніють ОБИДВІ половини — і токен, і `dark:`-утиліта" do
    emulate_os("dark")
    visit_ok "/dashboard"

    expect(page).to have_css(card, minimum: 1)
    expect(os_reports_dark?).to be(true), "емуляція ОС не спрацювала — вимір недійсний"

    expect(surface_base_token).to eq(surface_dark)
    expect(card_shadow_token).to eq(shadow_off)
  end

  it "при СВІТЛІЙ перевазі ОС світлішають ОБИДВІ половини" do
    emulate_os("light")
    visit_ok "/dashboard"

    expect(page).to have_css(card, minimum: 1)
    expect(os_reports_dark?).to be(false), "емуляція ОС не спрацювала — вимір недійсний"

    expect(surface_base_token).to eq(surface_light)
    expect(card_shadow_token).not_to eq(shadow_off)
  end

  # 🔒 Посередника між середовищем і токеном більше немає. Пін на ВІДСУТНІСТЬ
  # класу тримає саме це: щойно хтось поверне клієнтський перемикач теми (а з
  # ним `localStorage` і недетермінований рендер), приклад почервоніє поіменно.
  it "не ставить на <html> жодного класу теми — посередника не існує" do
    emulate_os("dark")
    visit_ok "/dashboard"

    expect(page).to have_css(card, minimum: 1)
    expect(dark_class_present?).to be(false)
  end

  # 🔴 `screen and` мусить стояти в ОБОХ половинах шафи — у `@custom-variant`
  # (утиліти) і в блоці токенів. Дефолт Tailwind — медіа-запит БЕЗ `screen`, тож
  # варіант, з якого його знято, дав би темні `dark:`-утиліти на світлому
  # друкованому аркуші: та сама «дві шафи», лише в print-контексті, і тому
  # невидима для обох прикладів вище.
  #
  # ⚠️ ЧОМУ ПІН СТАТИЧНИЙ, А НЕ БРАУЗЕРНИЙ — виміряно, не вигадано.
  # `Emulation.setEmulatedMedia` з `media: "print"` оновлює `matchMedia`
  # (`print` → true, `screen` → false, і сам складений запит → false), але
  # обчислені стилі вже відрендереної сторінки Chrome НЕ перераховує: фон
  # `<body>` лишається темним при media-запиті, який більше не матчиться. Тобто
  # браузерний приклад тут міряв би не наш CSS, а момент рестайлу в рушії, і
  # був би червоним на правильному коді.
  #
  # Пін судить ДЖЕРЕЛО — і тут це правильний якір по суті предмета: перевіряється
  # текст медіа-запиту, який ми пишемо самі, а не результат генерації. ⚠️ Мотив
  # «білд у `.gitignore`, тож гейт по ньому був би зелений на порожній множині»
  # знято як виміряно хибний (§Guard-craft #68).
  it "тримає `screen and` у КОЖНОМУ media-запиті теми — інакше друк розколює шафу" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    queries = css.scan(/@media[^{]*prefers-color-scheme[^{]*|@custom-variant\s+dark[^;]*;/)

    expect(queries).not_to be_empty, "у джерелі не знайдено жодного media-запиту теми — пін безпредметний"

    unguarded = queries.reject { |q| q.include?("screen and") }

    expect(unguarded).to be_empty, <<~MSG
      Медіа-запит теми без `screen and` — на друці ця половина розійдеться з іншою:

      #{unguarded.map(&:strip).join("\n")}
    MSG
  end

  # [UI.1 порція 11] Три a11y-середовища, яких доти не існувало в дереві ЗОВСІМ.
  # Піни статичні по джерелу (той самий якір, що `screen and` вище) і цілять у
  # НЕСУЧУ частину кожного блоку — те, що ламається без нього, а не в сам факт
  # наявності @media-рядка.
  describe "a11y-середовища (prefers-contrast · forced-colors · print)" do
    let(:css) { Rails.root.join("app/assets/tailwind/application.css").read }

    def block(css, query)
      start = css.index(query)
      return nil unless start
      css[start, 1200]
    end

    it "prefers-contrast: more піднімає найтихіші токени ТІЄЮ Ж шафою (var, не нові значення)" do
      b = block(css, "@media (prefers-contrast: more)")
      expect(b).to be_present, "блоку prefers-contrast немає в джерелі"
      expect(b).to include("--gaia-text-muted:  var(--gaia-text)")
      expect(b).to include("--gaia-border:      var(--gaia-border-strong)")
    end

    it "forced-colors повертає видимий фокус: ring-и (box-shadow) там стираються системою" do
      b = block(css, "@media (forced-colors: active)")
      expect(b).to be_present, "блоку forced-colors немає в джерелі"
      expect(b).to include(":focus-visible")
      expect(b).to include("outline: 2px solid")
      expect(b).to include(".gaia-select")
    end

    it "print ховає інтерактивний хром і чистить відбиток" do
      b = block(css, "@media print")
      expect(b).to be_present, "блоку print немає в джерелі"
      expect(b).to include('header[role="banner"]')
      expect(b).to include("display: none !important")
      expect(b).to include("box-shadow: none !important")
    end
  end
end
