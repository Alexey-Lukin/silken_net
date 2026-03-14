# frozen_string_literal: true

require "eth"

module Etherisc
  # = ===================================================================
  # 🛡️ ETHERISC CLAIM SERVICE (DIP Oracle Mode)
  # = ===================================================================
  # Тригерить claim через Etherisc Decentralized Insurance Protocol (DIP)
  # на Polygon. Система діє як Oracle — замість емісії внутрішніх токенів
  # (SCC/SFC), виплата здійснюється в USDC з децентралізованого пулу
  # ліквідності Etherisc.
  #
  # Це усуває інфляційний тиск на внутрішню токеноміку при страхових подіях.
  #
  # Використання:
  #   tx_hash = Etherisc::ClaimService.new(insurance).claim!
  class ClaimService
    # Etherisc DIP Gateway ABI — мінімальний інтерфейс для тригеру claim.
    # Повна ABI: https://docs.etherisc.com/
    ETHERISC_CLAIM_ABI = [
      {
        "inputs" => [
          { "internalType" => "uint256", "name" => "policyId", "type" => "uint256" }
        ],
        "name" => "triggerClaim",
        "outputs" => [],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    def initialize(insurance)
      @insurance = insurance
    end

    # Відправляє `triggerClaim` транзакцію до Etherisc DIP контракту на Polygon.
    #
    # @return [String] tx_hash відправленої транзакції
    # @raise [StandardError] при помилці RPC або недостатньому балансі Oracle
    def claim!
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      contract_address = ENV.fetch("ETHERISC_DIP_CONTRACT_ADDRESS")
      contract = Eth::Contract.from_abi(
        name: "EtheriscDIP",
        address: contract_address,
        abi: ETHERISC_CLAIM_ABI
      )

      policy_id = @insurance.etherisc_policy_id.to_i

      Rails.logger.info "🛡️ [Etherisc] Triggering DIP claim for policy #{@insurance.etherisc_policy_id} " \
                        "(insurance ##{@insurance.id})..."

      tx_hash = client.transact(
        contract, "triggerClaim", policy_id,
        sender_key: oracle_key, legacy: false
      )

      Rails.logger.info "🛡️ [Etherisc] Claim TX sent: #{tx_hash}"

      tx_hash
    end
  end
end
