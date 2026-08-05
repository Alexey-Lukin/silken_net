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
#   · `cUSD` контракту в цьому репо не має (зовнішній Celo-токен), тож його символ
#     не стереже ніщо і стерегти нічим — carve-out за ПОБУДОВОЮ, не недогляд.
#   · Гейт судить РІВНІСТЬ рядків, не правильність символу: два однаково хибні
#     написання він пропустить.
RSpec.describe "token ticker parity: Ruby map ⟷ Solidity ERC20 symbol" do # rubocop:disable RSpec/DescribeClass
  # `ERC20("Silken Carbon Coin", "SCC")` → "SCC", по всіх контрактах репо.
  let(:declared_symbols) do
    Dir[Rails.root.join("contracts/*.sol")].sort.filter_map do |path|
      File.read(path)[/ERC20\(\s*"[^"]*"\s*,\s*"([^"]+)"\s*\)/, 1]
    end
  end

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
  it "не має тікера без контракту, окрім зовнішнього cUSD" do
    expect(BlockchainTransaction::TOKEN_TICKERS.values - declared_symbols).to eq([ "cUSD" ])
  end

  it "покриває КОЖНЕ значення enum'а — і не тримає запису для неіснуючого типу" do
    expect(BlockchainTransaction::TOKEN_TICKERS.keys)
      .to match_array(BlockchainTransaction.token_types.keys)
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
