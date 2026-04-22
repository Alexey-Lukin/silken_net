# frozen_string_literal: true

require "eth"

module Governance
  # = ===================================================================
  # 🏛️ GOVERNANCE PARAMETER SYNC WORKER
  # = ===================================================================
  # Синхронізує параметри протоколу з on-chain ProtocolParameters.sol
  # у локальну SystemParameter модель Rails.
  #
  # Запускається 1×/день (cron: 0 3 * * *), зчитує поточні параметри
  # з Polygon через RPC, порівнює з SystemParameter та оновлює змінені
  # значення з source: "governance".
  #
  # Pipeline: ProtocolParameters.sol → RPC eth_call → ParameterSyncWorker → SystemParameter
  #
  # Залежності:
  #   - ProtocolParameters.sol deployed (PROTOCOL_PARAMETERS_CONTRACT_ADDRESS)
  #   - Web3::RpcConnectionPool (Alchemy/Infura RPC)
  #   - SystemParameter model (ARCH.15)
  #
  # Див: docs/05_03 § Governance-Aware Backend, ARCH.4
  class ParameterSyncWorker
    include ApplicationWeb3Worker

    sidekiq_options queue: "web3_low", retry: 3, unique_for: 12.hours

    # Маппінг on-chain параметрів до SystemParameter ключів.
    # On-chain значення зберігаються як uint256 з 18 decimals (1e18 = 1.0).
    # При decimals: 18 → ділимо на 1e18 для отримання float.
    # При decimals: 0 → використовуємо integer as-is.
    PARAMETER_MAP = {
      # Lorenz attractor
      lorenz_sigma:              { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_rho:                { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_beta:               { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_dt:                 { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_iterations:         { value_type: "integer", category: "lorenz",     decimals: 0 },
      lorenz_z_min:              { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_z_max:              { value_type: "float",   category: "lorenz",     decimals: 18 },
      lorenz_z_target:           { value_type: "float",   category: "lorenz",     decimals: 18 },
      # Tokenomics
      emission_threshold:        { value_type: "integer", category: "tokenomics", decimals: 0 },
      dynamic_tax_rate:          { value_type: "float",   category: "tokenomics", decimals: 18 },
      insurance_pool_threshold:  { value_type: "integer", category: "tokenomics", decimals: 0 },
      # Slashing
      slash_threshold:           { value_type: "float",   category: "alerts",     decimals: 18 },
      stress_threshold:          { value_type: "float",   category: "alerts",     decimals: 18 }
    }.freeze

    # Мінімальний ABI для читання ProtocolParameters.sol.
    # getParameter(bytes32) → uint256, isParameterSet(bytes32) → bool.
    CONTRACT_ABI = [
      {
        "inputs" => [ { "internalType" => "bytes32", "name" => "key", "type" => "bytes32" } ],
        "name" => "getParameter",
        "outputs" => [ { "internalType" => "uint256", "name" => "", "type" => "uint256" } ],
        "stateMutability" => "view",
        "type" => "function"
      },
      {
        "inputs" => [ { "internalType" => "bytes32", "name" => "key", "type" => "bytes32" } ],
        "name" => "isParameterSet",
        "outputs" => [ { "internalType" => "bool", "name" => "", "type" => "bool" } ],
        "stateMutability" => "view",
        "type" => "function"
      }
    ].to_json

    # RPC timeout для кожного виклику (секунди).
    RPC_TIMEOUT_SECONDS = 10

    def perform
      contract_address = ENV["PROTOCOL_PARAMETERS_CONTRACT_ADDRESS"]

      unless contract_address.present?
        Rails.logger.info "🏛️ [Governance] PROTOCOL_PARAMETERS_CONTRACT_ADDRESS not set. Skipping sync."
        return
      end

      Rails.logger.info "🏛️ [Governance] Starting parameter sync from #{contract_address}..."

      synced = 0
      skipped = 0

      with_web3_error_handling("Polygon", "ProtocolParameters sync") do
        client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
        contract = Eth::Contract.from_abi(
          name: "ProtocolParameters",
          address: contract_address,
          abi: CONTRACT_ABI
        )

        PARAMETER_MAP.each do |param_key, config|
          on_chain_key = solidity_keccak256(param_key.to_s)

          # Check if parameter is set on-chain
          is_set = Timeout.timeout(RPC_TIMEOUT_SECONDS) do
            client.call(contract, "isParameterSet", on_chain_key)
          end

          unless is_set
            skipped += 1
            next
          end

          # Read on-chain value
          raw_value = Timeout.timeout(RPC_TIMEOUT_SECONDS) do
            client.call(contract, "getParameter", on_chain_key)
          end

          converted_value = convert_value(raw_value, config[:decimals])

          # Compare with current SystemParameter
          current = SystemParameter.current(param_key)
          if current.present? && current.to_s == converted_value.to_s
            skipped += 1
            next
          end

          # Update SystemParameter
          SystemParameter.set(
            param_key,
            converted_value.to_s,
            updated_by: system_bot,
            value_type: config[:value_type],
            category: config[:category],
            source: "governance"
          )

          Rails.logger.info "🏛️ [Governance] Updated #{param_key}: #{current} → #{converted_value}"
          synced += 1
        end
      end

      Rails.logger.info "🏛️ [Governance] Sync complete: #{synced} updated, #{skipped} skipped."
    end

    private

    # Compute Solidity-compatible keccak256 hash of a string for mapping key.
    # Returns bytes32 hex string matching Solidity: keccak256("lorenz_sigma").
    def solidity_keccak256(str)
      Eth::Util.keccak256(str)
    end

    # Convert raw uint256 to Ruby value based on decimals.
    # decimals=18: on-chain 10e18 → Ruby 10.0
    # decimals=0:  on-chain 10000 → Ruby 10000
    def convert_value(raw_uint256, decimals)
      if decimals == 0
        raw_uint256.to_i
      else
        BigDecimal(raw_uint256.to_s) / BigDecimal(10**decimals)
      end
    end

    # System bot user (User.oracle_executioner) for audit trail.
    def system_bot
      @system_bot ||= User.oracle_executioner
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
