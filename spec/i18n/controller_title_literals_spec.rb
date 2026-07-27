# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт класу «заголовок сторінки захардкоджено англійською в контролері».
#
# Чому саме контролери й саме `title:`: аргумент іде в `render_dashboard` /
# `render_auth_page` і стає ОДРАЗУ двома речами — `<title>` вкладки браузера
# (тобто ще й записом в історії) і видимим `<h1>` сторінки (`DashboardLayout`).
# Тобто це не «дрібний рядок десь у кутку», а ім'я сторінки, яке користувач
# бачить на КОЖНОМУ екрані. До міграції 2026-07-27 таких було 56 у 25 контролерах.
#
# Чому це не ловив жоден наявний гейт: `i18n-tasks` звіряє локаль з локаллю й
# бачить лише ІСНУЮЧІ `t()`-ключі — сирий строковий літерал для нього не існує
# взагалі. `raise_on_missing_translations` теж мовчить: ніхто нічого не шукає.
# Це та сама сліпа зона «гейт звіряє однорідну пару» (`00_06 §3`).
#
# 🔒 Стеля: гейт бачить ЛИШЕ літерал одразу після `title:` у контролерах.
# Хардкод, зібраний у змінну рядком вище, або в іншому kwarg — поза ним.
RSpec.describe "controller page titles are localized" do # rubocop:disable RSpec/DescribeClass
  # `title: title` — прокидання параметра в `render_dashboard`, не літерал.
  let(:literal_title)    { /title:\s*"/ }
  let(:any_title_kwarg)  { /\btitle:/ }

  let(:controller_files) { Dir[Rails.root.join("app/controllers/**/*.rb")].sort }

  let(:offenders) do
    controller_files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, idx|
        next unless line.match?(literal_title)

        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{idx + 1} — #{line.strip}"
      end
    end
  end

  # Без цього «0 порушень» могло б означати «сканер нічого не знайшов узагалі»
  # (перейменували метод, змінили шлях, зламали glob).
  it "is a live check (controllers exist and do pass title: kwargs)" do
    expect(controller_files).not_to be_empty
    with_title = controller_files.count { |p| File.read(p).match?(any_title_kwarg) }
    expect(with_title).to be > 1,
      "жоден контролер не передає `title:` — сканер дивиться не туди"
  end

  it "passes no hardcoded string literal as a page title" do
    expect(offenders).to be_empty,
      "заголовок сторінки мусить іти через I18n.t (`04_04 §12.8`), знайдено:\n  " + offenders.join("\n  ")
  end
end
