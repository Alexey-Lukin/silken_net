# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Cuprite — headless Chrome driver for Capybara via Chrome DevTools Protocol.
# 2-5x faster than Selenium because it talks directly to Chrome (no Java middleman).
# https://github.com/rubycdp/cuprite
require "capybara/cuprite"
# Дає Capybara-DSL (`visit` / `fill_in` / `click_button`) прикладам `type: :feature`.
# Доти не підключався жодного разу, бо `spec/features/` була порожня — тобто
# CI-джоба `feature-test` піднімала Postgres+Redis і виконувала НУЛЬ прикладів.
require "capybara/rspec"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1440, 900 ],
    browser_options: {
      "no-sandbox": nil,
      "disable-gpu": nil,
      "disable-dev-shm-usage": nil
    },
    # 🔴 45, не 15 — виміряно, а не про запас. За 14 послідовних ранів `CI · Code`
    # джоба `feature-test` упала ДВІЧІ (≈14%), обидва рази однаково:
    # `Ferrum::ProcessTimeoutError` на першому ж `visit`, рівно один приклад із 14,
    # локально зелено — тобто headless-Chrome не встигав СТАРТУВАТИ на спільному
    # раннері, а не наш код помилявся. Обидва рази `rerun --failed` давав зелене,
    # тож симптом читався як «флейк» і двічі коштував червоного `main`.
    # ⚠️ Це НЕ маскування дефекту: предмет цих спек — поведінка застосунку, а не
    # швидкість запуску браузера, тож старт не має бути частиною вимірюваного.
    # Ціна підвищення однобічна й мала: коли Chrome справді мертвий, приклад
    # чекатиме 45 с замість 15 — один раз, перед тим самим падінням.
    process_timeout: 45,
    inspector: ENV["INSPECTOR"].present?,
    headless: ENV.fetch("HEADLESS", "true") != "false"
  )
end

Capybara.default_driver    = :rack_test
Capybara.javascript_driver = :cuprite
