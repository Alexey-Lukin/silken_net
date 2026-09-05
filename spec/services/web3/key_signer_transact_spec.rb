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
  let(:real_client) do
    Eth::Client.create("http://127.0.0.1:8545").tap do |c|
      allow(c).to receive(:transact).and_return("0x#{'f' * 64}")
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
end
