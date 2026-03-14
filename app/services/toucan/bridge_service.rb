# frozen_string_literal: true

require "eth"
require "bigdecimal"

module Toucan
  # = ===================================================================
  # 🌉 TOUCAN BRIDGE SERVICE (SCC → TCO2 Interoperability)
  # = ===================================================================
  # Відповідає за бриджинг SCC у Toucan Protocol через Polygon.
  # Підключається до Toucan Carbon Bridge контракту, виконує approve + deposit
  # для конвертації SCC в TCO2 (глобальні карбонові пули).
  #
  # Використання:
  #   Toucan::BridgeService.call(blockchain_transaction_id)
  # = ===================================================================
  class BridgeService < ApplicationService
    # ABI Toucan Carbon Bridge контракту — deposit функція для бриджингу SCC → TCO2
    BRIDGE_ABI = [
      {
        "inputs" => [
          { "internalType" => "address", "name" => "erc20Addr", "type" => "address" },
          { "internalType" => "uint256", "name" => "amount", "type" => "uint256" }
        ],
        "name" => "deposit",
        "outputs" => [],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    def initialize(blockchain_transaction_id)
      @transaction = BlockchainTransaction.find(blockchain_transaction_id)
    end

    def perform
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      bridge_address = ENV.fetch("TOUCAN_BRIDGE_CONTRACT_ADDRESS")
      scc_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")

      contract = Eth::Contract.from_abi(
        name: "ToucanCarbonBridge",
        address: bridge_address,
        abi: BRIDGE_ABI
      )

      amount_wei = Web3::WeiConverter.to_wei(@transaction.locked_points)

      tx_hash = client.transact(
        contract, "deposit", scc_address, amount_wei,
        sender_key: oracle_key, legacy: false
      )

      tx_hash
    end
  end
end
