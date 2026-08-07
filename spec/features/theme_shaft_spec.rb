# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [UI.1] Тема мусить перемикатися ОДНІЄЮ шафою — класом `.dark` на `<html>`.
#
# Доти їх було дві, незалежні. Семантичні токени (`--gaia-*` у блоці `.dark`)
# слухали ТУМБЛЕР, а сирі `dark:`-утиліти Tailwind — ОПЕРАЦІЙНУ СИСТЕМУ, бо у
# Tailwind v4 варіант `dark:` за замовчуванням компілюється в
# `@media (prefers-color-scheme: dark)`, і класовим його робить рядок
# `@custom-variant dark (…)`, якого в `app/assets/tailwind/application.css` не
# було взагалі. Розходились вони рівно тоді, коли людина тумблером
# скористалась — тобто дефект був невидимий для всіх, хто лишався на дефолті.
#
# Периметр — `dark:shadow-none` (8 сайтів: `shared/ui/{stat_card,photo_card,
# data_table}`, `components/{tree_families,maintenance,firmwares}/form`,
# `components/codex/node_card`, `components/actuators/card`) плюс
# `dark:bg-[url(…)]` (текстура в `layouts/dashboard_layout`).
#
# ⚠️ Тут доти стояло, що найдорожчий наслідок — `dark:prose-invert`, який
# «давав світлий текст на білому». **Заява спростована виміром:**
# `@tailwindcss/typography` не встановлений, тож `.prose` у зібраному CSS має
# НУЛЬ входжень — чотири prose-сайти Codex не генерують нічого й у розходження
# не входили ніколи. Тобто периметр був завищений на них, а справжній дефект
# поруч зовсім інший (посилання в лор-Markdown немаркуються — `00_07` UI.3).
#
# ⚠️ Чому це неможливо довести нижче — і чому саме тут.
#   · Статичний скан бачить лише РЯДОК у CSS, а не те, під яку шафу Tailwind його
#     скомпілював; сам компільований `app/assets/builds/` у `.gitignore`, тож гейт
#     по ньому був би зелений на порожній множині (та сама пастка, що названа в
#     шапці `spec/quality/design_token_existence_spec.rb`).
#   · Компонентна спека рендерить розмітку без CSS узагалі — вона бачить рядок
#     `dark:shadow-none` у класі й нічого не знає про його чинність.
#   Отже інструмент один: справжній браузер, який САМ вирішує, чи правило діє.
#
# 🔒 Форма піна — розвести ОС і тумблер у ПРОТИЛЕЖНІ боки, обидві комбінації.
# Це не подвійна робота: до фіксу приклади падали в РІЗНІ боки (при світлій ОС
# `dark:`-утиліта не діяла ніколи, при темній — діяла завжди), тобто одна
# половина сліпа до половини дефекту. Асиметрія тут і є суттю.
#
# ⚠️ ОС емулюється через CDP (`Emulation.setEmulatedMedia`), а не приймається
# такою, якою її рапортує headless-Chrome: інакше результат визначала б
# конфігурація машини, і зелений колір нічого не доводив би.
RSpec.describe "Theme: одна шафа (клас), не дві (клас + ОС)", :js do
  let(:organization) { create(:organization) }
  let(:password)     { "theme-shaft-pass-1" }
  let!(:user) { create(:user, :admin, organization: organization, password: password) }

  # `StatCard` — носій `shadow-sm dark:shadow-none`, і він стоїть на дашборді
  # чотири рази. Пінимось за `role="group"` (стабільний контракт компонента), а
  # не за клас: клас — це те, що ми й перевіряємо на чинність.
  let(:card) { 'div[role="group"]' }

  # Значення `--tw-shadow`, яке ставить `shadow-none`. Чому оракул саме таке —
  # у `card_shadow_token` нижче.
  let(:shadow_off) { "0 0 #0000" }

  before { sign_in_as(user, password: password) }

  # ── інструменти виміру ──

  # Емуляція ОС-переваги. Ставиться ДО візиту, бо FOUC-скрипт у `<head>` читає
  # `prefers-color-scheme` на завантаженні.
  def emulate_os(scheme)
    page.driver.browser.page.command(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: scheme } ]
    )
  end

  # Явна перевага застосунку. З нею FOUC-скрипт ігнорує ОС (`localStorage ||
  # matchMedia`), тож ОС і тумблер справді розходяться.
  def force_app_theme(theme)
    page.execute_script("localStorage.setItem('theme', #{theme.to_json})")
  end

  def dark_class_present?
    page.evaluate_script("document.documentElement.classList.contains('dark')")
  end

  # 🔴 Прилад мусить свідчити про СЕБЕ. Без цього приклад «при темній ОС» міряє
  # наслідок, не довівши передумови: якщо CDP-емуляція мовчки не спрацювала, він
  # зелений на порожній множині — тобто атестує рівно те, що мав ловити.
  def os_reports_dark?
    page.evaluate_script("window.matchMedia('(prefers-color-scheme: dark)').matches")
  end

  # 🔴 Оракул читає `--tw-shadow`, а НЕ `boxShadow` — і це не педантизм, а
  # виправлення підміни виміру, яка коштувала цьому файлу першої редакції.
  # У Tailwind v4 `shadow-none` не дає `box-shadow: none`: він ставить
  # `--tw-shadow: 0 0 #0000`, а `box-shadow` лишається композитом
  # `var(--tw-inset-shadow), … , var(--tw-shadow)`, тобто обчислений рядок ЗАВЖДИ
  # є довгим переліком `rgba(0,0,0,0) …` і НІКОЛИ не дорівнює `"none"`.
  # Наслідок: пін `eq("none")` не здатен пройти, а `not_to eq("none")` — упасти.
  # Одна половина була б вічно червона, друга — вічно зелена на порожній множині.
  def card_shadow_token
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{card.to_json})).getPropertyValue('--tw-shadow').trim()"
    )
  end

  # ── самий інваріант ──

  it "вмикає `dark:`-утиліту при ТЕМНІЙ темі, навіть коли ОС світла" do
    force_app_theme("dark")
    emulate_os("light")
    visit "/dashboard"

    expect(page).to have_css(card, minimum: 1)
    expect(os_reports_dark?).to be(false), "емуляція ОС не спрацювала — вимір недійсний"
    expect(dark_class_present?).to be(true), "тумблер не поставив `.dark` — далі міряти нічого"

    # До фіксу: `@media (prefers-color-scheme: dark)` не матчиться, тож
    # `dark:shadow-none` не діє і тінь `shadow-sm` лишається.
    expect(card_shadow_token).to eq(shadow_off)
  end

  it "НЕ вмикає `dark:`-утиліту при СВІТЛІЙ темі, навіть коли ОС темна" do
    force_app_theme("light")
    emulate_os("dark")
    visit "/dashboard"

    expect(page).to have_css(card, minimum: 1)
    expect(os_reports_dark?).to be(true), "емуляція ОС не спрацювала — вимір недійсний"
    expect(dark_class_present?).to be(false), "світла тема не встановилась — далі міряти нічого"

    # До фіксу: media матчиться попри світлу тему, тож `dark:shadow-none`
    # перемагає й тінь зникає у СВІТЛІЙ темі — саме там, де вона й потрібна,
    # бо картка на світлій поверхні відділяється від тла тінню, а не рамкою.
    expect(card_shadow_token).not_to eq(shadow_off)
  end
end
