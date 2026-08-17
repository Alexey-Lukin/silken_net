# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# 🔴 [UI.4, 2026-08-17] Turbo дебаунсить броадкасти на ФОНОВОМУ треді, і гем сам
# вважає це небезпечним у тестах — але вимикає лише для Minitest.
#
# `turbo-rails/lib/turbo/engine.rb` робить це всередині
# `ActiveSupport.on_load(:active_support_test_case)` з коментарем «Use
# ImmediateDebouncer in tests to prevent flaky tests from background threads».
# Ми на RSpec, тож той хук не спрацьовує ніколи: виміряно
# `RAILS_ENV=test bin/rails runner` — `debouncer_class` дорівнював
# `Turbo::Debouncer`, тобто справжньому, з `Concurrent::ScheduledTask`.
#
# Чим це коштувало б, якби лишилось:
#   * блок дебаунсера біжить на ІНШОМУ треді, тобто на іншому зʼєднанні з БД —
#     а транзакційні фікстури тримають дані незакоміченими, тож той тред бачить
#     порожню базу (найгірша форма: приклад зелений, а броадкаст мовчки
#     відпрацював не по тих даних);
#   * задача стріляє через 0,5 с, тобто вже ПІСЛЯ того, як приклад завершився і
#     транзакцію відкотили — недетермінізм, який читається як флейк харнесу.
#
# ⚠️ Стеля названа: `ImmediateDebouncer` не дебаунсить ВЗАГАЛІ (`block.call`),
# тож у тестах коалесування НЕ перевіряється — перевіряється лише те, що
# останній кадр доїжджає. Хто пінить саме коалесування, мусить робити це
# окремо й свідомо, а не покладатись на цей файл.
RSpec.configure do
  Turbo::ThreadDebouncer.debouncer_class = Turbo::ImmediateDebouncer
end
