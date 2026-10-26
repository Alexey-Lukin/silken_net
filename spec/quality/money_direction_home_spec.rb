# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.95] Напрямок грошового рядка має РІВНО ОДИН дім — колонку
# `blockchain_transactions.direction`.
#
# Механізм дефекту, який купив цей гейт. Доти напрямок деривувався з
# `sourceable_type` (`"NaasContract"` = burn, усе інше = емісія), і та форма стояла
# на передумові «slash — ЄДИНИЙ шлях зменшення обігу». ESG-погашення передумову
# знімало, доки жило: воно вилучало монети з обігу без `sourceable`, тож деривація
# зарахувала б погашення ЕМІСІЄЮ. Промах тихий і дорогий одночасно —
# `net_minted_supply` годує L1-якір (`Ethereum::StateAnchorService`) і базу розміру
# спалення. ⛔ Після зняття погашення ([ARCH.95] (В), 2026-10-26) передумова знову
# правдива, і гейт лишається: «одна причина burn» є фактом про сьогоднішніх писачів,
# не властивістю, тож наступна причина вилучення без цього гейта знову стала б емісією.
#
# 🔒 Чому саме така форма. Поведінку стережуть піни: валідація
# `slash_intent_must_be_a_burn` (писач слешу) і приклади «віднімає burn без sourceable …»
# у `spec/models/blockchain_transaction_spec.rb` (по одному на кожну форму One-Home).
# ⚠️ Перше з двох тверджень було НЕТОЧНИМ до 2026-08-27, і поправка варта рядка:
# валідація ІСНУВАЛА, але її гілка ВІДМОВИ не виконувалась у сюїті жодного разу
# (виміряно branch-coverage'ом), тобто зняття `errors.add` лишалось зеленим.
# «Гард є» і «гард доведено» — різні твердження, і саме друге тут несуче;
# обидва плечі тепер стоять у `spec/models/blockchain_transaction_spec.rb`. Чого не стерегло НІЩО —
# це повернення самої ФОРМИ: присуд заборонив деривацію, а заборона жила лише
# прозою в `CLAUDE.md §6` і в коментарях по сайтах. Клас «відкинута вокабуляра»:
# те, що робить гейт потрібним, — саме ВІДСУТНІСТЬ терміна в дереві, не його
# наявність (скіл `ssot-maintenance` §Guard-craft #76).
#
# 🔴 Виняток для дому НАВМИСНО вужчий за файл. `BURN_SOURCEABLE_TYPE` лишається
# живим у моделі — але як ознака «цей burn є слешем» усередині ВАЛІДАЦІЇ, і ніколи
# як джерело напрямку. Тому HOME судиться не рядками, а ТІЛАМИ агрегатів (через
# `source_location`) — обох: `net_minted_supply` і `net_minted_by_cluster`. ⚠️ Доти
# судилось тіло лише першого, і історична форма другого (SQL-CASE по
# `sourceable_type`, рознесений на два рядки) лишала гейт зеленим (адверсар, 2026-10-26).
#
# ⚠️ Стеля, названа прямо: гейт статичний і судить ФОРМУ виразу. Він не побачить
# деривації в HOME поза тілами двох агрегатів, зробленої через проміжну змінну чи через `sourceable`-асоціацію
# (`tx.sourceable.is_a?(NaasContract)`); цю половину тримає сам дім — доки читачі
# беруть напрямок із колонки, вигадати обхід нема де.
module MoneyDirectionHome
  HOME = "app/models/blockchain_transaction.rb"

  # Заборонена форма: `sourceable_type` як ПОРІВНЯННЯ з burn-маркером.
  SOURCEABLE_TYPE = /sourceable_type/
  BURN_TOKEN      = /BURN_SOURCEABLE_TYPE|["']NaasContract["']/

  # Агрегати «скільки монет існує» — їх тіла судяться окремо від файлу HOME.
  AGGREGATES = %i[net_minted_supply net_minted_by_cluster].freeze

  # 🔴 Виняток, знайдений закриваючим свіпом ПЕРШ ніж на ньому хтось спіткнувся:
  # `sourceable_type` як КЛЮЧ ХЕША (`where(sourceable_type: …)`) — це ФІЛЬТР, а не
  # деривація напрямку, і `CLAUDE.md §6` прямо лишає `BURN_SOURCEABLE_TYPE` живим
  # як вужчу ознаку «цей burn є слешем». Тобто перший, хто написав би ПРАВИЛЬНИЙ
  # запит «дай мені слеш-рядки», дістав би червоне на коректному коді — а найдешевша
  # реакція на такий гейт відома: послабити його. База сьогодні порожня, тож хибний
  # позитив був би невидимий до першого ж легітимного вжитку.
  # ⚠️ Стара ЗАБОРОНЕНА форма при цьому лишається в периметрі: вона писалась або як
  # `sourceable_type == BURN_SOURCEABLE_TYPE` (голий ідентифікатор), або як
  # `where("… sourceable_type IS DISTINCT FROM ?", BURN_SOURCEABLE_TYPE)` — де
  # `sourceable_type` живе в РЯДКУ, а не ключем. Обидві предикат бачить.
  HASH_KEY_FILTER = /sourceable_type:/

  # Дім читання: агрегат «скільки монет існує».
  HOME_CALL = /net_minted_supply/

  ROOTS = [ "app/**/*.rb", "lib/**/*.rb" ].freeze

  # Рядки КОДУ, не проза: коментарі цитують і `sourceable_type`, і присуд ARCH.95
  # навмисно — саме там і живе пояснення, чому форма заборонена.
  def self.code_lines(path)
    File.readlines(path).reject { |line| line.lstrip.start_with?("#") }
  end

  def self.files_where(&predicate)
    ROOTS.flat_map { |glob| Dir[Rails.root.join(glob)] }.filter_map do |path|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      rel if code_lines(path).any?(&predicate)
    end.sort
  end

  def self.deriving_files
    files_where do |line|
      line.match?(SOURCEABLE_TYPE) && line.match?(BURN_TOKEN) && !line.match?(HASH_KEY_FILTER)
    end
  end

  def self.consumer_files
    files_where { |line| line.match?(HOME_CALL) } - [ HOME ]
  end

  # Тіло агрегату, взяте з РЕАЛЬНОГО `source_location`, а не грепом:
  # так гейт не залежить від номерів рядків і не роз'їдеться при зсуві файлу.
  def self.aggregate_body(name = :net_minted_supply)
    path, line_no = BlockchainTransaction.method(name).source_location
    lines = File.readlines(path)
    header = lines[line_no - 1]
    indent = header[/\A\s*/]

    body = []
    lines[line_no..].each do |line|
      break if line == "#{indent}end\n"

      body << line
    end
    raise "aggregate body not delimited — перевір відступ `end` у #{path}" if body.size >= lines.size - line_no

    body.join
  end
end

RSpec.describe MoneyDirectionHome, type: :quality do
  it "derives mint-vs-burn from `sourceable_type` NOWHERE but the model's own validation" do
    expect(described_class.deriving_files).to eq([ described_class::HOME ])
  end

  it "keeps the burn marker OUT of every supply aggregate — the column is the discriminator" do
    described_class::AGGREGATES.each do |name|
      agg = described_class.aggregate_body(name)

      expect(agg).not_to match(described_class::SOURCEABLE_TYPE), "#{name} reads sourceable_type"
      expect(agg).not_to match(described_class::BURN_TOKEN), "#{name} carries the burn marker"
      expect(agg).to include("direction"), "#{name} must read the direction column"
    end

    body = described_class.aggregate_body
    # Обидва боки читаються колонкою — інакше «Σmints − Σburns» знову стало б
    # твердженням про тип джерела, а не про напрямок.
    expect(body).to include("direction: :mint")
    expect(body).to include("direction: :burn")
  end

  # 🔦 Ліхтар на предмет, не на форму. Без нього перші два приклади лишились би
  # зеленими на дереві, де напрямок узагалі перестали читати: «нуль деривацій»
  # однаково правдиве і для полагодженого дерева, і для порожнього.
  it "the column and its home have real consumers — otherwise the guards guard emptiness" do
    # Виміряно 8 (2026-10-26, після зняття ESG-тракту); поріг нижчий свідомо — ліхтар
    # судить ПОРОЖНЕЧУ, а не лічбу, тож легальне зняття одного читача не мусить червонити.
    expect(described_class.consumer_files.size).to be >= 6

    # Колонка є носієм присуду: обидва значення, NOT NULL, дефолт свідомо `mint`
    # (тому писач БУРНУ мусить оголосити напрямок явно — див. валідацію моделі).
    expect(BlockchainTransaction.directions.keys).to match_array(%w[mint burn])
    expect(BlockchainTransaction.columns_hash["direction"].null).to be(false)
  end
end
