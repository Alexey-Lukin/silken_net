# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Web3
  # =========================================================================
  # 🔎 ERC-20 READER (One-Home for on-chain balanceOf reads)
  # =========================================================================
  # Колапсує `balanceOf` ABI + client-build + Timeout + cache, що
  # BlockchainMintingService / Insurance::ReserveGate / BlockchainBurningService
  # кожен re-implement-ив (ABI-літерал жив у 4 файлах). Повертає raw wei (Integer) —
  # виклик конвертує одиниці. Спільний `cache_key` між читачами ТОГО САМОГО holder →
  # один RPC на вікно (а не один на фічу).
  # =========================================================================
  class Erc20Reader
    BALANCE_OF_ABI = [
      {
        "inputs" => [ { "internalType" => "address", "name" => "account", "type" => "address" } ],
        "name" => "balanceOf",
        "outputs" => [ { "internalType" => "uint256", "name" => "", "type" => "uint256" } ],
        "stateMutability" => "view",
        "type" => "function"
      }
    ].to_json

    DEFAULT_TIMEOUT = 10

    def self.balance_of_wei(contract_env_key:, holder:, cache_key:, ttl:, rpc_env_key: "ALCHEMY_POLYGON_RPC_URL", timeout: DEFAULT_TIMEOUT)
      Rails.cache.fetch(cache_key, expires_in: ttl) do
        client = Web3::RpcConnectionPool.client_for(rpc_env_key)
        contract = Eth::Contract.from_abi(
          name: "Erc20", address: ENV.fetch(contract_env_key), abi: BALANCE_OF_ABI
        )
        raw = Timeout.timeout(timeout) { client.call(contract, "balanceOf", holder) }
        Integer(raw)
      end
    end
  end
end
