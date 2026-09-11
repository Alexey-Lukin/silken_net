# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"

# ⛽ Носій оцінки ЛІМІТУ газу на шві підписанта.
#
# 🔴 Куплено живим дефектом 2026-09-05: на canopy **44 мінти SCC поспіль** осіли в
# `manual_review` з `tx_hash = nil` — жодна не пішла в мережу, — а Amoy відповідав
# дослівно `Transaction gas limit is too low, try 74494!`. Причина не наша арифметика,
# а гем: `Eth::Client#transact` без `gas_limit:` бере `Tx.estimate_intrinsic_gas`,
# тобто ІНТРИНСИК (21 000 + байти calldata) — газ на ДОСТАВКУ, не на ВИКОНАННЯ.
#
# 🔑 Це сестра ARCH.62 з тією ж геометрією: присвоєння в усьому `app/` існувало РІВНО
# ОДНЕ (L1-якір, `ETHEREUM_GAS_LIMIT`), решта тракту їхала на гем-дефолті. Ми лікували
# вісь ЦІНИ газу й не подивились на вісь ЛІМІТУ в тому самому виклику.
RSpec.describe Web3::KeySigner, "#transact" do
  let(:key)      { instance_double(Eth::Key, address: Eth::Address.new("0x#{'d' * 40}")) }
  let(:signer)   { described_class.new(key) }
  let(:function) { instance_double(Eth::Contract::Function, encode_call: "0xdeadbeef") }
  let(:contract) do
    instance_double(Eth::Contract, address: "0x#{'c' * 40}").tap do |c|
      allow(c).to receive(:function).and_return(function)
    end
  end

  # ⚠️ СПРАВЖНІЙ `Eth::Client`, не дубль — саме його вимагає `MEASURABLE_CLIENTS`,
  # і саме тому решта сюїти не мусить стабити цінові RPC (урок 175 падінь того ж дня;
  # `rescue StandardError` тут не рятує — `MockExpectationError` є `Exception`).
  # `Eth::Client.create` мережі не чіпає: перший мережевий виклик — `chain_id`.
  # ⚠️ Баланс і ціна стабляться ТУТ, бо шов тепер несе ще й reserve-перевірку
  # (`assert_gas_reserve!`): без стабу вона пішла б у мережу на кожному прикладі
  # й тихо деградувала через fail-open — тобто приклади лишились би зеленими,
  # а нова гілка не виконувалась би ЖОДНОГО разу. Щедрий баланс = гейт проходить,
  # тож усі піни нижче судять рівно те, що судили до нього.
  let(:real_client) do
    Eth::Client.create("http://127.0.0.1:8545").tap do |c|
      allow(c).to receive_messages(transact: "0x#{'f' * 64}", get_balance: 10**18)
      c.max_fee_per_gas = 1_000_000
    end
  end

  it "питає мережу й додає запас — 74494 не пройшло б на гем-дефолті 21000" do
    allow(real_client).to receive(:eth_estimate_gas)
      .and_return({ "jsonrpc" => "2.0", "id" => 1, "result" => "0x122fe" }) # 74 494

    signer.transact(real_client, contract, "mint", "0x#{'b' * 40}", 1)

    expect(real_client).to have_received(:transact)
      .with(contract, "mint", "0x#{'b' * 40}", 1,
            sender_key: key, gas_limit: (74_494 * described_class::HEADROOM).ceil)
  end

  # ⛔ Запас не декоративний: оцінка робиться на ПОТОЧНОМУ стані, а між нею й включенням
  # холодний слот стореджу стає теплим і чужий мінт лягає першим. Занижена на кілька
  # відсотків оцінка дала б рівно ту відмову, яку цей код знімає.
  it "запас СТРОГО більший за оцінку" do
    allow(real_client).to receive(:eth_estimate_gas)
      .and_return({ "jsonrpc" => "2.0", "id" => 1, "result" => "0x122fe" })

    signer.transact(real_client, contract, "mint")

    expect(real_client).to have_received(:transact)
      .with(contract, "mint", hash_including(gas_limit: a_value > 74_494))
  end

  it "явний `gas_limit:` викликача БʼЄ оцінку — L1-якір лишається на своєму числі" do
    allow(real_client).to receive(:eth_estimate_gas).and_return({ "result" => "0x122fe" })

    signer.transact(real_client, contract, "storeStateRoot", gas_limit: 100_000)

    aggregate_failures do
      expect(real_client).to have_received(:transact)
        .with(contract, "storeStateRoot", sender_key: key, gas_limit: 100_000)
      expect(real_client).not_to have_received(:eth_estimate_gas)
    end
  end

  # ⛔ Нода може віддати не-Hash (проксі-помилка, HTML-сторінка 502, `nil`).
  # `envelope["result"]` на такому впав би `NoMethodError` — тобто оцінка, що мала
  # деградувати тихо, шуміла б на грошовому шляху при живому фолбеку поруч.
  it "не-Hash у відповіді ноди не ламає підпис — kwargs лишаються недоторканими" do
    allow(real_client).to receive(:eth_estimate_gas).and_return("<html>502</html>")

    signer.transact(real_client, contract, "mint")

    expect(real_client).to have_received(:transact).with(contract, "mint", sender_key: key)
  end

  # ⛔ Не-hex у `result` — НЕ нуль, а НЕВИМІРЯНО. `to_i(16)` на сміттєвому рядку
  # мовчки дав би 0, тобто `gas_limit: 0`, і транзакція була б відхилена НАЗАВЖДИ
  # під виглядом успішної оцінки — гірше за пропущений вимір.
  it "не-hex `result` рахується НЕВИМІРЯНИМ, а не нулем" do
    allow(real_client).to receive(:eth_estimate_gas).and_return({ "result" => "не-число" })

    signer.transact(real_client, contract, "mint")

    expect(real_client).to have_received(:transact).with(contract, "mint", sender_key: key)
  end

  # 🔴 Мертва нода не сміє завалити ПІДПИС: без оцінки kwargs проходять НЕДОТОРКАНИМИ
  # і гем застосовує власний фолбек — рівно як до цієї правки.
  it "збій оцінки лишає kwargs недоторканими, а не ставить nil" do
    allow(real_client).to receive(:eth_estimate_gas).and_raise(Net::ReadTimeout)

    expect { signer.transact(real_client, contract, "mint", nonce: 7) }.not_to raise_error
    expect(real_client).to have_received(:transact)
      .with(contract, "mint", sender_key: key, nonce: 7)
  end

  # =======================================================================
  # ⛽💰 RESERVE-GATE — «чи проїде ЦЯ транзакція»
  # =======================================================================
  # 🔴 Куплено живим інцидентом 2026-09-06: `MintBatchCollectorWorker` упав
  # `insufficient funds for gas * price + value` при балансі РІВНО `0.05` MATIC,
  # тобто рівно на порозі `oracle_min_balance_matic` — операторська шкала була
  # зелена (`ratio = 1.00`), money-шлях непрацездатний. Гард міряв «скільки Є»
  # там, де питання було «скільки ТРЕБА на одну операцію» (геометрія ARCH.95).
  describe "резерв газу (`assert_gas_reserve!`)" do
    let(:estimated_limit) { (74_494 * described_class::HEADROOM).ceil }
    let(:reserve)         { estimated_limit * 1_000_000 }

    before do
      allow(real_client).to receive(:eth_estimate_gas)
        .and_return({ "jsonrpc" => "2.0", "id" => 1, "result" => "0x122fe" })
    end

    it "відмовляє ДО відправки, коли балансу не вистачає на gasLimit × maxFeePerGas" do
      allow(real_client).to receive(:get_balance).and_return(reserve - 1)

      expect { signer.transact(real_client, contract, "mint") }
        .to raise_error(described_class::InsufficientGasReserve, /insufficient funds/)
      expect(real_client).not_to have_received(:transact)
    end

    # ⛔ Межа несуча: EVM резервує за ЛІМІТОМ і пропускає рівність, тож гейт, що
    # відхиляв би `balance == reserve`, був би СУВОРІШИМ за сам ланцюг — тобто
    # блокував би транзакцію, яка проїде.
    it "рівність балансу й резерву ПРОПУСКАЄ — ланцюг її пропускає теж" do
      allow(real_client).to receive(:get_balance).and_return(reserve)

      expect { signer.transact(real_client, contract, "mint") }.not_to raise_error
      expect(real_client).to have_received(:transact)
    end

    it "`value:` входить у резерв — EVM рахує `gasLimit × maxFeePerGas + value`" do
      allow(real_client).to receive(:get_balance).and_return(reserve)

      expect { signer.transact(real_client, contract, "mint", value: 1) }
        .to raise_error(described_class::InsufficientGasReserve, /\+ value 1/)
    end

    # 🔑 НЕСУЧИЙ ПІН УСЬОГО ГЕЙТА, і він не про гард, а про його ЧИТАЧІВ.
    # Наш вирок мусить читатись рівно так само, як вирок ноди, — інакше ми самі
    # почнемо виробляти `manual_review`, тобто лімб, з якого виходу немає.
    # ⚠️ Три доми звірено ПОІМЕННО: докстрінг, що НАЗИВАЄ споживачів, гниє тихіше
    # за код, тож звʼязок доводиться прогоном, а не абзацом.
    it "текст вироку читається як PRE-BROADCAST усіма ТРЬОМА класифікаторами" do
      allow(real_client).to receive(:get_balance).and_return(0)

      message = begin
        signer.transact(real_client, contract, "mint")
        nil
      rescue described_class::InsufficientGasReserve => e
        e.message
      end

      aggregate_failures do
        expect(message).to be_present
        # (1) Polygon: `fail!` + retry, НЕ escalate у manual_review
        expect(
          BlockchainMintingService.new([]).send(:transact_error_pre_broadcast?, StandardError.new(message))
        ).to be true
        # (2) Celo: нода ВІДХИЛИЛА — інтент безпечно перевиплатити наступним циклом
        expect(Celo::CommunityRewardService::REJECTED_PATTERNS).to match(message)
        # (3) Код, що їде в НЕЗВОРОТНИЙ IPFS-пін: названий клас, ніколи `:unknown`
        expect(Web3::TransactionErrorClassifier.classify(message)).to eq(:insufficient_funds)
      end
    end

    # ⚠️ Оголошена стеля гейта, перевірена обома напрямками: він судить лише те,
    # що ЗМІГ ПРОЧИТАТИ. Мовчазна деградація тут свідома — блокувати money-path
    # через RPC-гикавку дорожче за дефект, який гейт стереже.
    it "збій читання балансу вирок НЕ виносить — транзакція йде" do
      allow(real_client).to receive(:get_balance).and_raise(Net::ReadTimeout)

      expect { signer.transact(real_client, contract, "mint") }.not_to raise_error
      expect(real_client).to have_received(:transact)
    end

    it "без оцінки ліміту балансу навіть НЕ ПИТАЄ — множника немає, вироку немає" do
      allow(real_client).to receive(:eth_estimate_gas).and_return({ "result" => "не-число" })

      signer.transact(real_client, contract, "mint")

      expect(real_client).not_to have_received(:get_balance)
    end
  end

  # =======================================================================
  # ⛽🕰 ОСВІЖЕННЯ ВИМІРЯНОГО FEE НА ШВІ [ARCH.62]
  # =======================================================================
  # 🔴 Предмет: fee міряється на НАРОДЖЕННІ клієнта, клієнт кешується per-thread,
  # а Sidekiq-потік живе до деплою — тож виміряне число далі лише старіє. Режим
  # відмови детермінований: протухлий-занизький cap → tx не майниться → вічний
  # `:sent` → rollback → `manual_review`, тобто заблоковані кошти.
  #
  # 🔑 ЧОМУ НЕ TTL: TTL є проксі для «щось змінилось», а пускач тут відомий точно —
  # мить перед підписом. Заразом це знімає потребу в ЧИСЛІ порога, якого не існує:
  # форми Polygon і Celo інверсні (tip домінує ⊥ база домінує).
  describe "освіження fee перед підписом" do
    let(:stale_cap)   { 1_000_000 }          # виміряне колись і відтоді протухле
    let(:fresh_tip)   { 100_000_000_000 }    # 100 Gwei — чайова, яку нода каже ЗАРАЗ
    let(:fresh_base)  { 10_000_000_000 }     # 10 Gwei бази
    # ⛔ База СВІДОМО не нульова: при `base = 0` вирази `base×2 + tip` і просто `tip`
    # збігаються, тож пін на «свіжий cap» був би сліпий до самої формули.
    let(:fresh_cap)   { (fresh_base * Web3::FeePolicy::BASE_FEE_HEADROOM) + fresh_tip }
    let(:gas_limit)   { (74_494 * described_class::HEADROOM).ceil }
    let(:stale_reserve) { gas_limit * stale_cap }

    # Клієнт, народжений ПУЛОМ, — саме це робить його впізнаваним для освіження.
    let(:pooled_client) do
      Eth::Client.create("http://127.0.0.1:8545").tap do |c|
        allow(c).to receive_messages(
          transact: "0x#{'f' * 64}",
          eth_estimate_gas: { "result" => "0x122fe" },
          eth_max_priority_fee_per_gas: { "result" => "0x174876e800" }
        )
        allow(c).to receive(:eth_get_block_by_number)
          .with("latest", false).and_return({ "result" => { "baseFeePerGas" => "0x2540be400" } })
      end
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      # ⛔ Не покладатись на оточення машини: заданий ENV-пін БʼЄ вимір, тож
      # експортована `POLYGON_*_FEE_GWEI` зробила б ці приклади зеленими з
      # ХИБНОЇ причини (пін теж перевищує протухлий резерв).
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return(nil)
      Web3::RpcConnectionPool::NETWORK_FALLBACK_ENV_KEYS.values.flatten.uniq.each do |key|
        allow(ENV).to receive(:[]).with(key).and_return(nil)
      end
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("http://127.0.0.1:8545")
      allow(Eth::Client).to receive(:create).and_return(pooled_client)
    end

    # Клієнт беруть із пулу, і аж ТОДІ його число протухає — саме так воно й
    # старіє в проді: вимір лишається на народженні, а мережа їде далі.
    def client_with_stale_cap
      Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL").tap do |c|
        c.max_fee_per_gas = stale_cap
      end
    end

    # 🔑 НЕСУЧИЙ ПІН, і він дискримінує саме той дефект, а не сусідній: баланс
    # рівно покриває резерв за ПРОТУХЛИМ cap і не покриває за СВІЖИМ. Без
    # освіження резерв рахувався б за протухлою ціною, гейт мовчав би, і на дріт
    # пішла б невключабельна транзакція — тобто зелений прогін над заблокованими
    # коштами. ⚠️ Пін ловить і ПОРЯДОК — мутаційно доведено в ОБИДВА боки: зняти
    # освіження ЦІЛКОМ і пересунути його ПІСЛЯ `assert_gas_reserve!` червонять
    # саме цей приклад (сусід нижче при тій самій перестановці лишається зеленим
    # правильно — свіжий cap на дроті є й тоді). Тобто приклади міряють різне.
    it "резерв судиться за СВІЖОЮ ціною, а не за протухлою" do
      client = client_with_stale_cap
      allow(client).to receive(:get_balance).and_return(stale_reserve)

      expect { signer.transact(client, contract, "mint") }
        .to raise_error(described_class::InsufficientGasReserve, /insufficient funds/)
      expect(client).not_to have_received(:transact)
    end

    it "на дріт іде СВІЖИЙ cap — протухле число не переживає підпису" do
      client = client_with_stale_cap
      allow(client).to receive(:get_balance).and_return(10**18)

      signer.transact(client, contract, "mint")

      aggregate_failures do
        expect(client.max_fee_per_gas).to eq(fresh_cap) # base × BASE_FEE_HEADROOM + tip
        expect(client.max_priority_fee_per_gas).to eq(fresh_tip)
        expect(client).to have_received(:transact)
      end
    end

    # 🔴 ДРУГИЙ ГАРД, і він окремий від `MEASURABLE_CLIENTS`: клієнт, який НЕ
    # народився в пулі, не впізнається за ENV-ключем — тож його не допитують
    # цінових RPC ВЗАГАЛІ. Саме це тримає периметр правки нульовим і закриває
    # той клас регресії, що вже коштував 175 і 78 падінь сюїти.
    it "клієнт ПОЗА пулом не допитується й свого числа не втрачає" do
      allow(real_client).to receive(:eth_estimate_gas).and_return({ "result" => "0x122fe" })
      allow(real_client).to receive(:eth_max_priority_fee_per_gas)

      signer.transact(real_client, contract, "mint")

      aggregate_failures do
        expect(real_client).not_to have_received(:eth_max_priority_fee_per_gas)
        expect(real_client.max_fee_per_gas).to eq(1_000_000)
      end
    end
  end
end
