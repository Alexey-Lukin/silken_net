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
# і при зібраних assets (`rails assets:precompile`, ~1 c — крок є у CI-джобі
# `feature-test`) Stimulus і Turbo в браузері живі: `typeof window.Stimulus`
# = `"object"`, `turbo:morph` відтворюється керовано.
#
# ⚠️ Що лишається недоказовним і ЧОМУ — межа тепер інша й вужча: `leaflet`
# пінниться на ЗОВНІШНІЙ CDN (`config/importmap.rb` → `ga.jspm.io`), тож у
# тестовому середовищі модуль не приїжджає, `map#connect()` не спрацьовує і
# `.leaflet-pane` лишається нуль. Тобто сценарії на МАПУ й далі неможливі, але
# вже через один конкретний пін, а не через увесь харнес.
#
# Тому цей файл пінить дві речі: серверний рендер у справжньому браузері (те, що
# інакше недоказовне — request-спека бачить `media_type` і тіло, браузер бачить,
# що з тим тілом сталося) і той факт, що НАШ Stimulus-контролер справді
# виконується.
RSpec.describe "Dashboard in a real browser", :js do
  let(:organization) { create(:organization) }
  let!(:user) { create(:user, :admin, organization: organization, password: "browser-smoke-pass-1") }

  def sign_in_through_the_form
    visit "/login"
    # ⚠️ Колонка зветься `email_address`, а поле форми — `email`: форма йде через
    # `form_with url:` без моделі, тож імена полів свої. Розбіжність реальна, не описка.
    fill_in "email", with: user.email_address
    fill_in "password", with: "browser-smoke-pass-1"
    click_button type: "submit"
  end

  # [SEC.25] Дзеркало request-піна, але в середовищі, де він і має значення. Доти
  # реальний користувач після протермінування сесії діставав сирий
  # `{"error":"Authentication required..."}` — і саме браузер є єдиним місцем, де
  # видно, що тепер це справжня сторінка з формою входу, а не текст, який Chrome
  # показує як plain text.
  it "shows the login PAGE (not a JSON blob) when the session is gone" do
    sign_in_through_the_form
    expect(page).to have_current_path(%r{/dashboard})

    # Найчесніша симуляція «сесія протухла»: салт-стемп у cookie перестає збігатися
    # (SEC.16) — рівно те, що робить зміна пароля з іншого пристрою.
    user.update!(password: "rotated-elsewhere-pass-2")
    visit "/dashboard"

    expect(page).to have_field("email")
    expect(page).to have_css("form[action='/login']")
    expect(page).to have_no_text('{"error"')
  end

  # [TEST.7] Перший приклад у цьому дереві, що доводить виконання ВЛАСНОГО
  # Stimulus-контролера, а не лише присутність Stimulus.
  #
  # 🔒 Пін навмисно тримається за ІКОНКУ, а не за клас на `<html>`, і це обходить
  # обидві пастки, виміряні при першій спробі: Capybara скоупить пошук у
  # `/html/body`, тож `have_css("html.dark")` не матчить НІКОЛИ; а `toggle()` іде
  # через `document.startViewTransition`, тобто застосування асинхронне й
  # миттєвий `evaluate_script` читає стан ДО транзиції. `theme#updateIcon`
  # переписує `iconTarget.innerHTML` — а той у body, отже Capybara вміє його
  # дочекатись штатно. Пряму перевірку класу лишаємо ДРУГОЮ: після того, як
  # іконка доїхала, транзиція вже завершена, і гонки немає.
  it "runs OUR Stimulus controller in the browser, not just boots Stimulus" do
    sign_in_through_the_form
    expect(page).to have_current_path(%r{/dashboard})

    moon = "#theme-switcher svg path[d^='M20.354']" # світла тема → пропонує темну
    sun  = "#theme-switcher svg path[d^='M12 3v1']"  # темна тема → пропонує світлу

    # ⚠️ Пін тримається за ПЕРЕХІД, а не за абсолютний стан: стартова тема
    # залежить від середовища (збережений `localStorage` і те, що саме рапортує
    # `prefers-color-scheme` у headless-Chrome), тож зафіксований старт зробив би
    # приклад крихким до конфігурації браузера, а не до нашого коду.
    was_dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
    expect(page).to have_css(was_dark ? sun : moon)

    find("#theme-switcher button").click

    # Якби Stimulus не виконувався, іконка лишилась би серверним місяцем
    # назавжди — саме цей приклад червонів, поки asset-теги глушив stub.
    expect(page).to have_css(was_dark ? moon : sun)
    expect(page.evaluate_script("document.documentElement.classList.contains('dark')")).to be(!was_dark)
  end
end
