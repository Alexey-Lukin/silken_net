# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.7] Рукописна `<form>` у Phlex мусить нести `authenticity_token`.
#
# 🔴 Чому цього НЕ можна довести поведінковою спекою — і саме тому гейт
# статичний. `config/environments/test.rb` вимикає `allow_forgery_protection`,
# а `ActionView`'s `token_tag` (`url_helper.rb`) віддає порожній рядок, коли
# `protect_against_forgery?` хибний. Тобто в цій сюїті `form_with`/`button_to`
# токена НЕ рендерять узагалі. Дзеркально `form_authenticity_token` прапорця не
# питає й повертає токен ЗАВЖДИ. Наслідок контрінтуїтивний: пін «у розмітці є
# authenticity_token» тут ІНВЕРТОВАНИЙ — він зелений на рукописній формі й
# червоний на правильному хелпері. Перевірка мусить дивитись на ДЖЕРЕЛО.
#
# 🔒 Стеля названа, бо вона не косметична:
#   · перевірка ФАЙЛОВА, не по-формова — файл із двома рукописними формами, де
#     токен несе лише одна, пройде зеленим;
#   · вона не звіряє, що токен стоїть саме в ТІЙ формі;
#   · `form_with`/`button_to` вона не бачить і бачити не мусить — ті кладуть
#     токен самі.
#
# ⚖️ Гейт СВІДОМО не забороняє рукописну `<form>` як таку. Правило «ніколи не
# рукописна форма» лишається відкритим присудом (`00_07` UI.7): у дереві є
# файли з рукописними формами, що чесно несуть токен, і блокетна заборона
# ухвалила б це рішення замість founder'а.
RSpec.describe "handwritten Phlex forms carry a CSRF token" do # rubocop:disable RSpec/DescribeClass
  # Рукописний Phlex-елемент — рівно `form(` на початку виразу. `form_with(` під
  # нього не підпадає (інший токен), як і `perform(`.
  let(:raw_form) { /^\s*form\(/ }

  let(:scanned_files) { Dir[Rails.root.join("app/views/**/*.rb")].sort }

  let(:files_with_raw_form) do
    scanned_files.select do |path|
      File.readlines(path).any? { |line| !line.lstrip.start_with?("#") && line.match?(raw_form) }
    end
  end

  let(:offenders) do
    files_with_raw_form
      .reject { |path| File.read(path).include?("authenticity_token") }
      .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }
  end

  # Без цих двох «0 порушень» означало б «glob дивиться не туди» або «правило
  # не має жодного підмета».
  it "is a live check (the component tree is scannable)" do
    expect(scanned_files.size).to be > 50,
      "сканер знайшов замало Phlex-файлів — glob дивиться не туди"
  end

  it "has subjects (raw `form(` still exists in the tree)" do
    expect(files_with_raw_form).not_to be_empty,
      "рукописних форм не лишилось — правило втратило підмет, зніми гейт або звузь glob"
  end

  it "detects a token-less form (the detector itself works)" do
    sample = "        form(\n          action: \"/x\",\n          method: \"post\"\n        ) do\n"
    expect(sample.lines.any? { |line| line.match?(raw_form) }).to be(true)
    expect(sample).not_to include("authenticity_token")
    # Дзеркало: правильний хелпер під детектор НЕ підпадає.
    expect("        form_with(url: \"/x\") do\n".lines.any? { |l| l.match?(raw_form) }).to be(false)
  end

  it "never ships a handwritten form without a token" do
    expect(offenders).to be_empty, <<~MSG
      рукописна `<form>` без `authenticity_token` падає на CSRF без JS (422) —
      працює лише тому, що Turbo підставляє `X-CSRF-Token` зі свого мета-тега.
      Лік — `form_with`/`button_to` (токен приїде сам) або явний
      `form_authenticity_token`. Знайдено: #{offenders.join(', ')}
    MSG
  end
end
