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
# 🔒 **Межа, знайдена виміром при написанні цього файлу, і вона більша за нього.**
# У test-середовищі сторінки **не несуть asset-тегів узагалі** — ні
# `javascript_importmap_tags`, ні `stylesheet_link_tag` не потрапляють у HTML
# (перевірено і браузером, і звичайною request-спекою; ті самі хелпери, викликані
# з `bin/rails runner` у RAILS_ENV=test, повертають коректні теги, тож розходження
# саме в рендер-шляху запиту). Наслідок: **наш JS у feature-тестах не виконується**
# — `window.Stimulus` там `undefined`. Прод це не зачіпає (assets precompiled), але
# будь-який сценарій, що пінить поведінку Stimulus/Turbo/Leaflet, сьогодні
# НЕМОЖЛИВИЙ, і CI-джоба цього б не сказала — вона просто лишалась би зеленою.
# Стан і план → `00_07` TEST.7.
#
# Тому цей файл свідомо пінить те, що від JS не залежить: серверний рендер у
# справжньому браузері. Це вже не нуль — і саме той сценарій, що інакше
# недоказовий: request-спека бачить `media_type` і тіло, браузер бачить, що з тим
# тілом сталося.
RSpec.describe "Dashboard in a real browser", :js do
  let(:organization) { create(:organization) }
  let!(:user) { create(:user, :admin, organization: organization, password: "browser-smoke-pass-1") }

  def sign_in_through_the_form
    visit "/api/v1/login"
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
    expect(page).to have_current_path(%r{/api/v1/dashboard})

    # Найчесніша симуляція «сесія протухла»: салт-стемп у cookie перестає збігатися
    # (SEC.16) — рівно те, що робить зміна пароля з іншого пристрою.
    user.update!(password: "rotated-elsewhere-pass-2")
    visit "/api/v1/dashboard"

    expect(page).to have_field("email")
    expect(page).to have_css("form[action='/api/v1/login']")
    expect(page).to have_no_text('{"error"')
  end
end
