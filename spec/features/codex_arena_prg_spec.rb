# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [SEC.25] Приклад, який НЕ МОЖЕ жити нижче — і це не стильова преференція,
# а критерій шару (`04_06 §B.1.4`).
#
# Дефект, який тут пінимо, request-спека не бачить СТРУКТУРНО: сервер віддавав
# цілком здорову відповідь (повна сторінка, статус 201), і будь-який пін на статус
# чи тіло був зелений. Ламав її КЛІЄНТ: Turbo після сабміту робить
# `proposeVisit(fetchResponse.location)`, а `location` — це URL самого POST'а.
# Маршрут арени зареєстровано як `only: [:new, :create]`, тож адресний рядок після
# кожного голосу вказував на адресу, де GET не існує.
#
# Тобто симптом проявляється рівно однією дією, якої request-шар не моделює
# взагалі, — ПЕРЕЗАВАНТАЖЕННЯМ. Тому пін тут і живе.
#
# ⚠️ Дзеркальна половина правила шару: те, що доказовне нижче, сюди НЕ дублюється.
# Статус редиректу, його ціль і збереження реалму запінені в
# `spec/requests/api/v1/codex/matches_controller_spec.rb` і повторюватись тут не
# мають — цей файл відповідає рівно на питання «де опинився браузер».
RSpec.describe "Codex Battle Arena — PRG у справжньому браузері", :js do
  let(:organization) { create(:organization) }
  let(:password)     { "arena-prg-pass-1" }
  let!(:user)  { create(:user, :admin, organization: organization, password: password) }
  let!(:realm) { create(:codex_realm, position: 1) }

  before do
    # Пара для голосу + запас, щоб селектор міг видати наступну.
    create_list(:codex_node, 6, :thriving, realm: realm)
  end

  # ⚠️ Клік СКОУПЛЕНИЙ у саму арену, і це не косметика: перша версія брала
  # `first(:button)` по всій сторінці, тобто влучала в кнопку сайдбара — приклад
  # проходив, не голосуючи взагалі, і мутація (повернення старого рендера) лишала
  # його зеленим. Вакуумність тут ловиться лише перевіркою, що голос СТАВСЯ.
  it "після голосу браузер стоїть на GET-адресі й переживає перезавантаження" do
    sign_in_as(user, password: password)

    visit "/codex/matches/new"
    expect(page).to have_css("#codex_battle_arena")

    expect {
      within("#codex_battle_arena") { click_button("Pick", match: :first) }
      # Синхронізація: чекаємо, доки Turbo завершить візит після сабміту.
      expect(page).to have_css("#codex_battle_arena")
    }.to change(::Codex::Match, :count).by(1)

    # 1. PRG спрацював: адреса — та, яку можна відкрити знову.
    expect(page).to have_current_path(%r{/codex/matches/new}),
                    "після голосу браузер лишився на POST-only адресі"

    # 2. І головне — саме те, чого не вміє request-шар: перезавантаження.
    #    До фіксу тут була б сторінка помилки маршрутизації.
    page.refresh

    expect(page).to have_css("#codex_battle_arena")
    expect(page).to have_no_text("RoutingError")
  end
end
