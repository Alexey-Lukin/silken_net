# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ДОСТАВКИ ручки: кожен `SystemParameter`-ключ, який сіє `db/seeds.rb`, мусить
# мати бодай ОДИН канал, яким його значення доходить до поведінки — або його читає
# код (`SystemParameter.current(:key)`), або він стоїть у `PARAMETER_MAP` і його
# може виставити DAO (`04_01 §7`, `04_02 §11`).
#
# Народився з ARCH.104: сідові рядки з нулем читачів ОБОМА каналами — ручка, яку
# нікому крутити. ⚠️ Периметр назвав саме цей гейт, а не пункт: трекер перелічував
# пʼять ключів, перший прогін знайшов ВІСІМ (три хардверні — залишок шкали заряду,
# знятої ARCH.99 — не стояли в жодному переліку). Тому число тут не фіксується:
# питати треба прогоном. 🔴 **Чому клас дожив — гейт над цією парою вже
# існував і був зелений ЗА ПОБУДОВОЮ:** крок `Governance-bounds sync` (GOV.3) звіряє
# `db/seeds.rb` ⟷ `PARAMETER_MAP`, але лише МЕЖІ ключів, які в мапі Є — сідовий рядок
# ПОЗА мапою для нього не існує взагалі. Тобто він чесно відповідає на «чи узгоджені
# спільні ключі», а читається як «сіди звірені»: класична форма «гейт перевіряє
# ІСНУВАННЯ там, де дефект у ПОКРИТТІ» (`ssot-maintenance` §Guard-craft #8). Цей гейт
# закриває саме вісь покриття й GOV.3 не дублює.
#
# 🔒 Стелі, названі чесно:
#   · Судиться ДОСТАВКА, ніколи ДОРЕЧНІСТЬ значення. Прочитаний ключ із безглуздим
#     числом пройде.
#   · Читачі беруться ЛІТЕРАЛАМИ. Єдиний динамічний сайт у дереві
#     (`treasury/monitor_service` — ключ із мапи гаманців) оголошено нижче явно:
#     інакше його вісім ключів читались би як осиротілі. Зʼявиться другий такий
#     споживач — його треба оголосити тут САМЕ ТАК, і це свідома ціна за те, що
#     статичний скан не бачить обчисленого ключа.
#   · Перемога цього гейта — ПОРОЖНЯ множина порушень, тож живість він доводить
#     САМОПЕРЕВІРКОЮ ДЕТЕКТОРА (позитивний ⊥ негативний контроль), а не популяцією
#     порушників (§Guard-craft #61). Плюс ліхтарі на ВХОДИ: якщо парсер сідів або
#     скан читачів мовчки зламається, обидві множини стануть порожні й гейт
#     зазеленіє назавжди (§Guard-craft #28).
module SystemParameterDeliveryGate
  SEEDS_PATH = Rails.root.join("db/seeds.rb")
  CODE_GLOBS = [ Rails.root.join("app/**/*.rb"), Rails.root.join("lib/**/*.rb") ].freeze

  # Динамічні читачі: ключ обчислюється, тож літерал у коді не стоїть. Оголошується
  # ПОІМЕННО з підставою — мовчазний виняток тут дорівнював би дірці розміром у цей
  # споживач.
  DYNAMIC_READERS = {
    "app/services/treasury/monitor_service.rb" =>
      "ключ береться з мапи гаманців (`wallet[:param_key]`), тож усі `oracle_min_balance_*` читаються обчисленим ім'ям"
  }.freeze

  module_function

  # Ключі, які сіє `db/seeds.rb`. Форма запису одна — `{ key: "…", value: …`.
  def seeded_keys(text = SEEDS_PATH.read)
    text.scan(/\{\s*key:\s*"([a-z0-9_]+)"/).flatten.uniq
  end

  # Ключі, прочитані ЛІТЕРАЛОМ. Дві форми виклику, обидві реальні в дереві:
  # `current(:key…)` і `current_values(key: …)`.
  def literal_read_keys(sources)
    sources.flat_map do |src|
      src.scan(/SystemParameter\.current\(\s*:([a-z0-9_]+)/).flatten +
        src.scan(/SystemParameter\.current_values\(([^)]*)\)/m).flatten.flat_map { |a| a.scan(/([a-z0-9_]+):/).flatten }
    end.uniq
  end

  # Єдиний оголошений динамічний споживач — мапа гаманців скарбниці.
  #
  # 🔴 БЕЗ `rescue`, і це куплено падінням у першому ж прогоні цього гейта: спершу тут
  # стояло `rescue StandardError → []` над невірним іменем константи, і воно тихо
  # перетворило `NameError` на «динамічних читачів немає» — гейт видав ВПЕВНЕНИЙ
  # список із вісьмома зайвими ключами, тобто хибне звинувачення. Гард, що не
  # відрізняє «нема читачів» від «я не зміг подивитись», друкує власний дефолт як
  # вердикт (§Guard-craft #47). Хай падає гучно: зникла константа має ЗУПИНИТИ гейт,
  # а не звузити його мовчки.
  def dynamic_read_keys
    Treasury::MonitorService::WALLETS.values.map { |w| w[:param_key] }.compact
  end

  def governed_keys = Governance::ParameterSyncWorker::PARAMETER_MAP.keys.map(&:to_s)

  def code_sources = CODE_GLOBS.flat_map { |g| Dir[g] }.map { |f| File.read(f) }

  def orphans
    delivered = literal_read_keys(code_sources) + dynamic_read_keys + governed_keys
    seeded_keys - delivered
  end
end

RSpec.describe "SystemParameter delivery", type: :model do # rubocop:disable RSpec/DescribeClass
  # ── Ліхтарі на ВХОДИ. Без них кожне твердження нижче зелене на порожньому наборі.
  it "is a live check (the seed file and the read surface are both non-empty)" do
    expect(SystemParameterDeliveryGate.seeded_keys.size).to be > 10,
                                                            "парсер сідів дав замало ключів — форма запису змінилась, гейт осліп"
    expect(SystemParameterDeliveryGate.literal_read_keys(SystemParameterDeliveryGate.code_sources).size).to be > 10,
                                                                                                            "скан читачів дав замало ключів — форма виклику змінилась, гейт осліп"
  end

  # ── САМОПЕРЕВІРКА ДЕТЕКТОРА. Перемога — порожня множина порушників, тож живість
  # доводить пара контролів на фікстурі, а не наявність жертв у дереві.
  describe "the detector itself" do
    let(:seed_line)    { '{ key: "totally_made_up_knob", value: "1", value_type: "integer" }' }
    let(:reader_line)  { "SystemParameter.current(:already_read_elsewhere, default: 1)" }

    it "sees a seeded key (positive control)" do
      expect(SystemParameterDeliveryGate.seeded_keys(seed_line)).to eq([ "totally_made_up_knob" ])
    end

    it "does not invent a key where the seed form is absent (negative control)" do
      expect(SystemParameterDeliveryGate.seeded_keys(reader_line)).to be_empty
    end

    it "counts a literal reader (positive control)" do
      expect(SystemParameterDeliveryGate.literal_read_keys([ "SystemParameter.current(:some_knob, default: 1)" ]))
        .to eq([ "some_knob" ])
    end
  end

  # ── Сам інваріант.
  it "leaves no seeded key without a delivery channel" do
    orphans = SystemParameterDeliveryGate.orphans

    expect(orphans).to be_empty,
                       "сідові ключі, яких не читає НІ код, НІ `PARAMETER_MAP` — ручка, яку нікому крутити " \
                       "(ARCH.104): #{orphans.sort.join(', ')}. Присуд по кожному окремо: зняти сід ⊥ дротувати " \
                       "читача ⊥ додати в `PARAMETER_MAP`, якщо величина справді має бути DAO-керованою."
  end
end
