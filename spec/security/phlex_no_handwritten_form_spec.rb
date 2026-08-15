# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.7 · ⚖️ founder 2026-08-15] Рукописна `<form>` у Phlex заборонена. ЗОВСІМ.
#
# Правило вже стояло в `CLAUDE.md §6` («дію рендери через `button_to`/`form_with`,
# ніколи рукописним `<form>`») — і не мало носія, тож у дереві жило 11 таких форм
# у 8 файлах, кожна з ВЛАСНОЮ копією CSRF-логіки. Клас устиг відстрілятись
# ЧОТИРИ рази: `Codex::Attunements::Toggle` слав обидві гілки на POST-only шлях
# (404 на un-attune) · `Maintenance::Form` не зберігався ЖОДНОГО разу, коли запис
# мав фото (вкладений `button_to` → парсер переносив `_method=delete` у зовнішню
# форму) · деплой прошивки не слав жодного body-параметра · `Settings` слав
# `locale=""` при кожному сабміті (422 на будь-якій правці).
#
# ⚖️ ЧОМУ ЗАБОРОНА, А НЕ РЕЄСТР ДОЗВОЛЕНИХ. Прецедент цього репо —
# `no_turbo_permanent_spec`: реєстр винятків гниє тихо (рядок переживає свій
# предмет і ніхто не помічає), а заборона не має чому гнити. Тут те саме з
# додатковою підставою: кожен «законний» виняток однаково дублює CSRF-логіку,
# тобто зберігає рівно ту поверхню, заради зняття якої правило й існує.
#
# 🔴 ЛІВНІСТЬ ЦЬОГО ГЕЙТА ДОВОДИТЬСЯ ІНАКШЕ, НІЖ У СУСІДА — і це не деталь.
# Попередник `phlex_form_csrf_spec` перевіряв ВЛАСТИВІСТЬ форм (чи несуть токен),
# тож мусив мати підмет — і ніс явний `has subjects`-приклад, який ЧЕСНО ВПАВ у
# мить, коли остання рукописна форма зникла: «правило втратило підмет, зніми
# гейт». Саме так його й знято 2026-08-15 — заборона строго сильніша (немає
# сирих форм ⇒ немає сирих форм без токена), і два гейти на одну вісь були б
# другим домом. Тут навпаки: порожня множина Є МЕТОЮ, тож `has subjects`-приклад
# заборонив би успіх. Отже
# живість несе САМОПЕРЕВІРКА ДЕТЕКТОРА (позитивний ⊥ негативний контроль нижче)
# плюс пін на те, що сканер узагалі бачить дерево. Без них «0 порушень»
# означало б «glob дивиться не туди», і гейт був би вічнозеленою декорацією.
RSpec.describe "Phlex components never hand-roll a <form>" do # rubocop:disable RSpec/DescribeClass
  # Рукописний Phlex-елемент — рівно `form(` на початку виразу. `form_with(`
  # під нього не підпадає (інший токен), як і `perform(`/`inform(`.
  let(:raw_form) { /^\s*form\(/ }

  let(:scanned_files) { Dir[Rails.root.join("app/views/**/*.rb")].sort }

  let(:offenders) do
    scanned_files.filter_map do |path|
      hits = File.readlines(path).each_with_index.select do |line, _i|
        !line.lstrip.start_with?("#") && line.match?(raw_form)
      end
      next if hits.empty?

      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      hits.map { |_line, i| "#{rel}:#{i + 1}" }
    end.flatten
  end

  it "scans a real component tree (guards against a glob that points nowhere)" do
    expect(scanned_files.size).to be > 50,
      "сканер знайшов замало Phlex-файлів — glob дивиться не туди, і «0 порушень» нічого не означає"
  end

  it "detects a hand-rolled form and ignores the sanctioned helpers" do
    raw = "        form(action: \"/x\", method: \"post\") do\n"
    expect(raw.lines.any? { |l| l.match?(raw_form) }).to be(true)

    # Негативні контролі: санкціоновані форми й схожі імена НЕ ловляться.
    [
      "        form_with(url: \"/x\", method: :post) do\n",
      "        button_to(\"Go\", x_path, method: :delete)\n",
      "        perform(job)\n",
      "        # form(action: \"/x\") — приклад у коментарі\n"
    ].each do |sample|
      expect(sample.lines.any? { |l| !l.lstrip.start_with?("#") && l.match?(raw_form) }).to be(false),
        "детектор хибно спрацював на: #{sample.strip}"
    end
  end

  it "has no hand-rolled forms anywhere in the component tree" do
    expect(offenders).to be_empty, <<~MSG
      Рукописна `<form>` у Phlex заборонена (⚖️ UI.7, 2026-08-15).

      Чим лікувати:
        · дія без вводу      → `button_to(label, path, method: :delete)`
        · форма з полями     → `form_with(url:, method:)` (або `model:` — але тоді
                               звір префікс параметрів із `params.require` контролера,
                               він деривується з КЛАСУ моделі)
        · файли              → `form_with(..., multipart: true)`

      Чому не «просто дописати authenticity_token»: хелпери дають ще й коректний
      `_method` (у HTML `method="delete"` — невалідне значення), кодування та
      захист від вкладеної форми. Саме ці три речі, а не самий токен, коштували
      чотирьох відомих багів цього класу.

      Знайдено: #{offenders.join(', ')}
    MSG
  end
end
