# SPDX-License-Identifier: AGPL-3.0-or-later
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
      # [INF.22] Dedicated Etherisc-підписант (легасі спільний ORACLE_PRIVATE_KEY retired) —
      # E.2-ізоляція blast-radius. Ключ інжектиться при активації insurance-шляху (06_04 §2.1).
      # [SEC.17] Деривація — через seam `Web3::OracleSigner` (ENV-дефолт незмінний).
      signer = Web3::OracleSigner.for(:etherisc)

      contract_address = ENV.fetch("ETHERISC_DIP_CONTRACT_ADDRESS")
      contract = Eth::Contract.from_abi(
        name: "EtheriscDIP",
        address: contract_address,
        abi: ETHERISC_CLAIM_ABI
      )

      policy_id = @insurance.etherisc_policy_id.to_i

      Rails.logger.info "🛡️ [Etherisc] Triggering DIP claim for policy #{@insurance.etherisc_policy_id} " \
                        "(insurance ##{@insurance.id})..."

      # [ARCH.49] Per-address nonce-serialization: eth-gem бере nonce per-call → конкурентні
      # підписи на одній адресі колізять nonce. Після dedicated-спліту [INF.22] адреса своя,
      # тож lock серіалізує лише конкурентні Etherisc-claims. after_timeout: :raise → lock не
      # взято → transact не виконувався → LockTimeout пробрасується для Sidekiq-retry
      # (idempotency double-claim уже закрита ARCH.45 у воркері).
      tx_hash = nil
      lock_key = "lock:web3:oracle:#{signer.address}"
      Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
        tx_hash = signer.transact(
          client, contract, "triggerClaim", policy_id,
          legacy: false
        )
      end

      Rails.logger.info "🛡️ [Etherisc] Claim TX sent: #{tx_hash}"

      tx_hash
    end
  end
end
