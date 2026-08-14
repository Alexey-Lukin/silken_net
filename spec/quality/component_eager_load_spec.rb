# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.93] Компонентний шар мусить входити в eager-перелік, а не лише в
# autoload.
#
# Чому це інваріант, а не гігієна: `eager_load = true` у проді існує рівно щоб
# `NameError`, синтаксис і циклічний реф падали НА СТАРТІ, поки процес ще не
# приймає трафік. `autoload_paths` в `eager_load_paths` не входить автоматично
# (Rails виключає `app/views` з дефолтного `app/*`), тож до 2026-08-14 виміряно:
# `eager_load!` давав 16 нащадків при 112 файлах — 96 класів народжувались під
# час ЗАПИТУ, і перший відвідувач сторінки був тим, хто ловив помилку.
#
# 🔴 Форма перевірки куплена пасткою: `Object.const_defined?` САМ тригерить
# автолоад, тож пін на ньому був би вакуумним за побудовою — він завантажив би
# те, чого мав не побачити, і завжди зеленів. `descendants` показують лише
# реально завантажене, тому дискримінатор саме тут.
#
# ⚠️ Приклад ОБОВʼЯЗКОВО кличе `eager_load!` сам: у `test` середовищі його не
# робить ніхто, тож без цього виклику пін міряв би порожнечу.
RSpec.describe "Phlex component eager-load perimeter", type: :model do
  # Зіставляємо МНОЖИНИ імен, не лічильники: пропущений файл мусить назватись
  # поіменно, інакше «на один менше» нічого не каже про те, який саме.
  let(:expected_component_names) do
    Rails.autoloaders.main.all_expected_cpaths
         .select { |path, _| path.end_with?(".rb") && path.include?("/app/views/") }
         .values
         .reject { |cpath| cpath == "ApplicationComponent" } # базовий клас не є власним нащадком
         .to_set
  end

  # 🔴 `filter_map`, не `map`: у ПОВНОМУ прогоні сусідні спеки створюють
  # анонімні `Class.new(ApplicationComponent)`, і `descendants` їх бачить — їхнє
  # `name` дорівнює `nil`. Перша редакція брала `map(&:name)`, тож дзеркальний
  # приклад був зелений у файлі й ЧЕРВОНИЙ у сюїті, ще й друкував порожній
  # перелік винних (nil у `join`). Спіймано повним прогоном, не мутацією —
  # мутація йшла по файлу, а цей клас із файлу не видно за побудовою.
  let(:loaded_component_names) do
    Rails.application.eager_load!
    ApplicationComponent.descendants.filter_map(&:name).to_set
  end

  it "вантажить КОЖЕН компонентний клас на старті, а не за першим запитом" do
    # Ліхтар: без нього приклад зелений на порожній множині — саме тому, що
    # `all_expected_cpaths` мовчки віддав би нуль при зміні фільтра.
    expect(expected_component_names.size).to be >= 100,
      "очікуваних компонентів #{expected_component_names.size} — фільтр шляхів зламався, пін вакуумний"

    missing = expected_component_names - loaded_component_names
    expect(missing).to be_empty,
      "поза eager-переліком (народяться під час запиту): #{missing.to_a.sort.join(", ")}"
  end

  # Дзеркальна половина: перелік не мусить БІЛЬШАТИ за рахунок класів, що
  # успадкували базу поза `app/views` — інакше «нуль пропущених» перестане
  # означати «периметр той самий».
  it "не тягне в перелік нащадків поза компонентним деревом" do
    stray = loaded_component_names - expected_component_names
    expect(stray).to be_empty,
      "нащадки ApplicationComponent поза app/views: #{stray.to_a.sort.join(", ")}"
  end
end
