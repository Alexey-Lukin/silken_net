# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Носій одного інваріанта: **фікстурні фабрики спільного хелпера не затінюються
# локально**. Хто хоче іншу фікстуру — будує її під власним іменем, а не переписує
# дім, на який спираються сусіди.
#
# 🔴 Народився з виміру, а не з припущення (`00_07` TEST.12/UI.17, 2026-08-19).
# `spec/quality/pagy_fixture_is_real_spec.rb` стверджує, що `OpenStruct`-двійник
# `Pagy` ВИМЕР — і був зелений, бо міряє СПІЛЬНИЙ хелпер (`include
# PhlexComponentHelper`). А `spec/views/components/maintenance/index_spec.rb`
# оголошував власний `def mock_pagy`, що віддавав рівно заборонену форму
# (`vars:`, публічний `series`, `count`/`last` як незалежні поля). Локальне
# визначення затінює хелпер УСЕРЕДИНІ файлу, і гейт цього не бачить за побудовою.
# **Тобто зелений гейт плюс надгробок на обʼєкт — саме та пара, під якою дефект
# і вижив.**
#
# ⚖️ Чому саме `mock_*`, а не «будь-яке затінення»: вимір розвів дві різні речі.
# `render_component` затінюють ДВАДЦЯТЬ файлів, і це законна спеціалізація — метод
# віддає РЕНДЕР, тобто зручність виклику, і локальна версія не бреше ні про що.
# `mock_*` віддає ФІКСТУРУ, що стоїть замість доменного обʼєкта, — і саме там
# підміна типу невидима для `verify_partial_doubles` (`OpenStruct` не йде через
# RSpec mock-API взагалі). Префікс `mock_` — власна конвенція корпусу, тож
# перелік нижче ДЕРИВУЄТЬСЯ з хелпера, а не пишеться руками: додай туди нову
# фабрику — вона потрапить під гейт сама.
#
# 🔒 Стелі, названі тут, бо без них зелений читатиметься ширше, ніж є:
#   · Судиться ЗАТІНЕННЯ, ніколи ЯКІСТЬ фікстури. Локальний `build_cluster`, що
#     віддає `OpenStruct`, цей гейт пройде — він не затінює дім. Ту вісь тримає
#     читання + `04_06 §B.2` BP #14.
#   · Судиться `spec/views/**` — рівно та популяція, куди `rails_helper` вмикає
#     хелпер автоматично (`config.include …, file_path: %r{spec/views/}`).
#     Файл поза нею хелпера не має, тож і затінити не може.
#   · `render_component`/`component_class` свідомо ПОЗА периметром (див. ⚖️ вище).
#   · Гейт не бачить затінення через `let(:mock_pagy)` чи `define_method` — форми
#     в дереві нуль, і розширення чекає на першу реальну.
module SharedFixtureHome
  HELPER_PATH = Rails.root.join("spec/support/phlex_component_helper.rb")
  # Популяція = там, де `rails_helper` вмикає хелпер автоматично.
  SPEC_GLOB = Rails.root.join("spec/views/**/*_spec.rb").to_s

  module_function

  # Фабрики деривуються з ДЖЕРЕЛА хелпера — другий перелік був би другим домом.
  def factory_methods
    HELPER_PATH.read.scan(/^\s*def\s+(mock_[a-z_0-9]*)/).flatten.uniq
  end

  def shadowing_sites
    factories = factory_methods
    Dir[SPEC_GLOB].sort.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, idx|
        name = line[/^\s*def\s+(mock_[a-z_0-9]*)/, 1]
        next unless name && factories.include?(name)

        "#{path.delete_prefix("#{Rails.root}/")}:#{idx + 1} — `def #{name}` затінює спільний дім"
      end
    end
  end

  def population_size = Dir[SPEC_GLOB].size
end

RSpec.describe "[TEST.12] фікстурні фабрики спільного хелпера не затінюються локально" do # rubocop:disable RSpec/DescribeClass
  # 🔴 Ліхтар популяції ПЕРШИМ: обидва боки цього гейта можуть виродитись у нуль
  # мовчки — перейменований хелпер віддасть порожній перелік фабрик, перенесена
  # тека віддасть порожню популяцію, — і в обох випадках вердикт нижче стане
  # вічнозеленим, не змінивши жодного слова.
  it "має що міряти з обох боків" do
    expect(SharedFixtureHome.factory_methods).not_to be_empty,
      "хелпер не оголошує жодної `mock_*`-фабрики — гейт судить порожню множину"
    expect(SharedFixtureHome.population_size).to be > 50,
      "популяція `spec/views/**` виродилась — перевір, чи не переїхала тека"
  end

  it "не має жодного локального перевизначення" do
    expect(SharedFixtureHome.shadowing_sites).to be_empty, <<~MSG
      Локальне визначення затінює фікстурну фабрику спільного хелпера:

      #{SharedFixtureHome.shadowing_sites.join("\n      ")}

      Спільний дім тримає ІНВАРІАНТ (справжній `Pagy::Offset`, справжні
      `model_name`/`to_key`), і гейт на нього міряє САМЕ хелпер. Локальна копія
      цей гейт обходить мовчки — рівно так `OpenStruct`-двійник `Pagy` пережив
      власне «вимер» (`spec/quality/pagy_fixture_is_real_spec.rb`).

      Потрібна інша фікстура — дай їй ВЛАСНЕ імʼя (`build_*`), не переписуй дім.
    MSG
  end
end
