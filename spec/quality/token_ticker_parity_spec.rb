# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ДРУГОГО ДОМУ: `BlockchainTransaction::TOKEN_TICKERS` — Ruby-копія значення,
# чий верхній дім живе в Solidity (`ERC20(name, symbol)`). Тікер свідомо НЕ в
# локаль-файлі — він locale-інваріантний, і YAML змусив би тримати по копії на
# кожну локаль каталогу (`04_04 §12.14`, той самий клас, що емодзі-мапи). Але ціна
# цього вибору — рівно те, що цей файл стереже: символ можна перейменувати в
# контракті, і жоден інший гейт цього не побачить, бо обидві сторони «present».
#
# Народився з дефекту, який жив непоміченим: усі чотири UI-сайти підписували СУМУ
# транзакції зашитим «SCC», тоді як `token_type` має три значення, а SFC-транзакції
# законно потрапляють у леджер гаманця (страхова виплата бере тип із контракту —
# `insurance_payout_worker.rb`). Тобто виплата в лісовій монеті малювалась як SCC.
#
# 🔒 Стеля, названа чесно:
#   · Перелік символів ДЕРИВУЄТЬСЯ з файлів `contracts/*.sol`, а не з рукописної
#     мапи: скопійований перелік членів — дзеркало, і гниє на першій же зміні.
#   · Зовнішні токени чужих мереж — `cUSD` (Celo) і `USDC` (Solana, [ARCH.120]) —
#     контракту в цьому репо не мають, тож їхні символи не стереже ніщо і стерегти
#     нічим: carve-out за ПОБУДОВОЮ, не недогляд, і він постійний, а не тимчасовий.
#   · Carve-out'ів ДВА РІЗНИХ — на символ і на НАЗВУ, у різних `it`; заводячи
#     зовнішній токен, оновлюй обидва (на [ARCH.120] правка одного лишила другий RED).
#   · Гейт судить РІВНІСТЬ рядків, не правильність символу: два однаково хибні
#     написання він пропустить.
RSpec.describe "token ticker parity: Ruby map ⟷ Solidity ERC20 symbol" do # rubocop:disable RSpec/DescribeClass
  # `ERC20("Silken Carbon Coin", "SCC")` → ["Silken Carbon Coin", "SCC"], по всіх
  # контрактах репо. Обидва аргументи беруться ОДНИМ проходом свідомо: назва й
  # символ оголошені одним конструктором, тож два екстрактори розійшлися б тихо.
  let(:declared_tokens) do
    Dir[Rails.root.join("contracts/*.sol")].sort.filter_map do |path|
      File.read(path).match(/ERC20\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)/)&.captures
    end
  end

  let(:declared_symbols) { declared_tokens.map(&:last) }
  let(:declared_names)   { declared_tokens.map(&:first) }

  # Liveness. Без цього прикладу «0 порушень» означало б «0 перевірок»: щойно
  # конструктор перепишуть (або каталог переїде), екстрактор віддасть порожню
  # множину, і кожна перевірка нижче пройде вакуумно.
  it "видобуває непорожню множину ERC20-символів із contracts/" do
    expect(declared_symbols).not_to be_empty
  end

  it "тримає в мапі КОЖЕН символ, оголошений контрактом у цьому репо" do
    missing = declared_symbols - BlockchainTransaction::TOKEN_TICKERS.values

    expect(missing).to be_empty,
                       "символ(и) #{missing.join(', ')} оголошені в contracts/*.sol, але " \
                       "їх немає в `BlockchainTransaction::TOKEN_TICKERS` — мапа відстала від Solidity"
  end

  # Shrink-list: тікери без контракту в репо. Тільки скорочується — щойно токен
  # дістає власний `.sol`, рядок мусить зникнути звідси сам, інакше carve-out
  # тихо ріс би, а гейт вироджувався б у нуль перевірок.
  # ⚠️ Список ВИРІС один раз, і підстава протилежна до послаблення: [ARCH.120] завів
  # `usdc`, бо Solana-мікровинагороди писались у USDC під `:carbon_coin` і
  # підсумовувались у `net_minted_supply`. Обидва carve-out'и — ЗОВНІШНІ токени
  # чужих мереж (Celo cUSD, Solana USDC); власного `.sol` вони не матимуть ніколи,
  # тож рядок тут постійний за побудовою, а не тимчасовий.
  it "не має тікера без контракту, окрім зовнішніх cUSD і USDC" do
    expect(BlockchainTransaction::TOKEN_TICKERS.values - declared_symbols)
      .to contain_exactly("cUSD", "USDC")
  end

  it "покриває КОЖНЕ значення enum'а — і не тримає запису для неіснуючого типу" do
    expect(BlockchainTransaction::TOKEN_TICKERS.keys)
      .to match_array(BlockchainTransaction.token_types.keys)
  end

  # Друга вісь того самого дому: НАЗВА токена. Символ locale-інваріантний і живе
  # в Ruby-мапі; назва перекладається і живе в локалях — але БАЗОВА мітка є таким
  # самим другим домом чужого значення, тож стереже її той самий гейт.
  # 🔒 Стеля: перевіряється ЛИШЕ базова локаль. uk/lv/lt перекладають вільно — їхню
  # парність тримає `i18n-tasks missing`, а не цей файл (`04_04 §12.14`: ціна не
  # росте з каталогом, і нова неперекладена локаль гейт не червонить).
  describe "базова мітка `token_type` ⟷ ERC20 name" do
    let(:base_labels) do
      BlockchainTransaction.token_types.keys.to_h do |value|
        key = "#{BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE}.#{value}"
        [ value, I18n.t(key, locale: I18n.default_locale, default: nil) ]
      end
    end

    it "має базову мітку для КОЖНОГО значення enum'а" do
      missing = base_labels.select { |_value, label| label.nil? }.keys

      expect(missing).to be_empty,
                         "нема мітки `#{BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE}.<value>` для: #{missing.join(', ')}"
    end

    it "тримає базову мітку ДОСЛІВНО рівною назві з контракту" do
      drifted = declared_names - base_labels.values.compact

      expect(drifted).to be_empty,
                         "назва(и) #{drifted.join(', ')} оголошені в contracts/*.sol, але жодна базова мітка " \
                         "`#{BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE}.*` їм не дорівнює — локаль відстала від Solidity"
    end

    # Shrink-list, дзеркало символьного вище: мітка без контракту. Щойно токен
    # дістає власний `.sol`, рядок мусить зникнути звідси сам.
    # ⚠️ Обидві осі цього гейта — символ і назва — мають ВЛАСНИЙ carve-out, і на
    # [ARCH.120] це коштувало другого проходу: правка символьного списку лишила
    # цей червоним. Заводячи зовнішній токен, оновлюй ОБИДВА, не один.
    it "не має мітки без контракту, окрім зовнішніх Celo Dollar і USD Coin" do
      expect(base_labels.values.compact - declared_names)
        .to contain_exactly("Celo Dollar", "USD Coin")
    end
  end

  describe "#token_type_label" do
    it "віддає базову мітку з локалі" do
      tx = build(:blockchain_transaction, token_type: :forest_coin)
      expect(tx.token_type_label).to eq("Silken Forest Coin")
    end

    # Fail-open — дзеркало `#ticker` нижче: тихий `nil` тут означав би бейдж без
    # тексту на грошовому екрані.
    it "фолбекає на сире значення для типу поза локаллю" do
      expect(BlockchainTransaction.token_type_label("quantum_coin")).to eq("quantum_coin")
    end
  end

  describe "#ticker" do
    it "віддає символ із мапи" do
      tx = build(:blockchain_transaction, token_type: :forest_coin)
      expect(tx.ticker).to eq("SFC")
    end

    # Fail-open — дзеркало `StatusBadge.label`: новий стан рендериться рівно ще до
    # того, як мітка доїде. Пін тримає саме цю властивість, бо тихий `nil` тут
    # означав би суму БЕЗ одиниці на грошовому екрані.
    it "фолбекає на сире значення, а не на nil, для типу поза мапою" do
      tx = build(:blockchain_transaction)
      allow(tx).to receive(:token_type).and_return("quantum_coin")
      expect(tx.ticker).to eq("QUANTUM_COIN")
    end
  end
end
