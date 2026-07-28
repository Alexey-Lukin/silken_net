# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт класу «`%{count}` + іменник у ЗАСТИГЛІЙ формі».
#
# Англійська ховає цю помилку за одним `-s`, тож у базовій локалі рядок виглядає
# бездоганно: `"%{count} units"`. У відмінюваних мовах він ламається на кожному
# числі, де форма інша: «21 одиниць», «1 vienības», «10 vienetai».
#
# 🔴 Чому це не бачить ЖОДЕН наявний гейт — і не випадково: `i18n-tasks missing`
# міряє НАЯВНІСТЬ ключа, `check-consistent-interpolations` — набір змінних `%{}`,
# `check-normalized` — форму YAML. Граматичність форми не міряє ніхто, а
# `rails-i18n` дає лише ПРАВИЛА плюралізації — обирати між `few`/`many` він може
# тільки якщо ключ узагалі є plural-блоком. На ~1 600 ключів корпусу їх було три.
#
# Форма — курована tripwire з ДВОМА списками (`00_06 §3`), і різниця між ними
# несуча: `EXEMPT` — рядки, де узгоджувати нічого (число стоїть останнім, після
# нього іменника немає) — це назавжди; `PENDING` — реальний борг, і він мусить
# ТІЛЬКИ скорочуватись. Мертвий запис у будь-якому списку червонить (інакше
# «0 порушень» означало б «0 перевірок»).
#
# 🔒 Стеля: перевіряється лише БАЗОВА локаль (ціна не росте з каталогом) і лише
# наявність plural-блоку — правильність САМИХ форм у кожній мові гейт не судить.
# Окремо не покрито: `lv` за CLDR потребує ще форми `zero`, якої в наших
# plural-блоках немає — це вісь «повнота набору форм», не «є блок чи ні».
RSpec.describe "pluralized strings declare a plural block" do # rubocop:disable RSpec/DescribeClass
  # Число останнє, іменника ПІСЛЯ нього немає → плюралізувати нічого.
  # 🔒 Стеля цього критерію названа явно: він АНГЛОЦЕНТРИЧНИЙ. У мовах із
  # відмінюванням іменник може стояти ПЕРЕД числом і все одно мусить із ним
  # узгоджуватись — `dashboard.map.live_nodes` в uk дає «Живих активних
  # вузлів: 1», де іменник заморожено в родовому множини. Тобто такий ключ
  # не є ані коректно звільненим, ані боргом у сенсі списку нижче: рамку
  # треба або переписати, або визнати конвенцією. Рішення мовне → `00_07` I18N.1.
  let(:exempt) do
    %w[
      codex.discoveries.counter
      dashboard.map.live_nodes
      account_security.show.mfa.enabled_with_remaining
    ]
  end

  # Борг: після `%{count}` стоїть іменник/дієприкметник, який мусить узгоджуватись.
  # Список ТІЛЬКИ скорочується → `00_07` I18N.1.
  let(:pending_keys) do
    %w[
      firmwares.index.units
      gateways.show.fleet.active_nodes
      maintenance.index.page_info
      organizations.show.clusters.soldiers_count
      tree_families.index.soldiers_count
      trees.chronicle.events
      users.profile.security.linked_count
    ]
  end

  let(:plural_suffixes) { %w[zero one two few many other] }
  # YAML напряму, а не `I18n.backend` — його внутрішній кеш лінивий і на момент
  # прикладу може бути порожнім (KeyError). Джерело істини тут — самі файли.
  let(:base_values) do
    base = I18n.default_locale.to_s
    Dir[Rails.root.join("config/locales/**/#{base}.yml")].sort.each_with_object({}) do |path, acc|
      root = YAML.load_file(path)&.fetch(base, nil)
      flatten_locale(root, [], acc) if root.is_a?(Hash)
    end
  end
  # Ключ вважається плюралізованим, якщо його ЛИСТ — одна з CLDR-форм.
  let(:count_keys) do
    base_values.select { |k, v| v.is_a?(String) && v.include?("%{count}") }
               .keys
               .reject { |k| plural_suffixes.include?(k.split(".").last) }
  end

  def flatten_locale(hash, path = [], acc = {})
    hash.each do |k, v|
      v.is_a?(Hash) ? flatten_locale(v, path + [ k.to_s ], acc) : acc[(path + [ k.to_s ]).join(".")] = v
    end
    acc
  end



  it "is a live check (the base locale really carries %{count} strings)" do
    expect(base_values).not_to be_empty
    expect(count_keys).not_to be_empty,
      "жодного `%{count}`-рядка не знайдено — сканер дивиться не туди"
  end

  it "has no dead entry in either list" do
    dead = (exempt + pending_keys).reject { |k| count_keys.include?(k) }

    expect(dead).to be_empty,
      "запис списку більше не існує як плоский `%{count}`-ключ (мігрував або перейменований) — приберіть його: #{dead.join(', ')}"
  end

  it "flags every %{count} string that is neither exempt nor a known debt" do
    unknown = count_keys - exempt - pending_keys

    expect(unknown).to be_empty,
      "новий `%{count}`-рядок без plural-блоку — у відмінюваних мовах він зламається на 1/21/… : #{unknown.join(', ')}"
  end
end
