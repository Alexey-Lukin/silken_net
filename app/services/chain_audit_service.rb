# frozen_string_literal: true

require "eth"

class ChainAuditService
  TOTAL_SUPPLY_ABI = [
    {
      "inputs" => [],
      "name" => "totalSupply",
      "outputs" => [
        { "internalType" => "uint256", "name" => "", "type" => "uint256" }
      ],
      "stateMutability" => "view",
      "type" => "function"
    }
  ].to_json

  CRITICAL_DELTA_THRESHOLD = 0.0001

  Result = Struct.new(:db_total, :chain_total, :delta, :critical, :checked_at, keyword_init: true)

  def self.call
    new.call
  end

  def call
    db_total     = fetch_db_scc_total
    chain_total  = fetch_chain_total_supply
    delta        = (db_total - chain_total).abs

    Result.new(
      db_total:   db_total,
      chain_total: chain_total,
      delta:      delta,
      critical:   delta > CRITICAL_DELTA_THRESHOLD,
      checked_at: Time.current
    )
  end

  private

  # Сума всіх підтверджених SCC-транзакцій у БД Postgres
  def fetch_db_scc_total
    BlockchainTransaction
      .where(token_type: :carbon_coin, status: :confirmed)
      .sum(:amount)
      .to_f
  end

  # Загальна емісія SCC у смарт-контракті Polygon (totalSupply)
  def fetch_chain_total_supply
    client   = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    contract = Eth::Contract.from_abi(
      name:    "SilkenCarbonCoin",
      address: ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS"),
      abi:     TOTAL_SUPPLY_ABI
    )

    raw = client.call(contract, "totalSupply")
    raw.to_f / (10**18)
  end
end
