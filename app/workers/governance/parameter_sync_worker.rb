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

    sidekiq_options queue: "web3_low", retry: 3, unique_for: 24.hours

    # Маппінг on-chain параметрів до SystemParameter ключів.
    # On-chain значення зберігаються як uint256 з 18 decimals (1e18 = 1.0).
    # Всі значення конвертуються: raw_uint256 / 1e18 → Ruby number.
    # Тип value_type визначає як SystemParameter зберігає результат.
    PARAMETER_MAP = {
      # Lorenz attractor
      lorenz_sigma:              { value_type: "float",   category: "lorenz"     },
      lorenz_rho:                { value_type: "float",   category: "lorenz"     },
      lorenz_beta:               { value_type: "float",   category: "lorenz"     },
      lorenz_dt:                 { value_type: "float",   category: "lorenz"     },
      lorenz_iterations:         { value_type: "integer", category: "lorenz"     },
      lorenz_z_min:              { value_type: "float",   category: "lorenz"     },
      lorenz_z_max:              { value_type: "float",   category: "lorenz"     },
      lorenz_z_target:           { value_type: "float",   category: "lorenz"     },
      # Tokenomics
      emission_threshold:        { value_type: "integer", category: "tokenomics" },
      dynamic_tax_rate:          { value_type: "float",   category: "tokenomics" },
      insurance_pool_threshold:  { value_type: "integer", category: "tokenomics" },
      # Slashing
      slash_threshold:           { value_type: "float",   category: "alerts"     },
      stress_threshold:          { value_type: "float",   category: "alerts"     }
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

    # On-chain fixed-point: 18 decimals (1e18 = 1.0), same as ERC-20 wei.
    FIXED_POINT_DECIMALS = 18
    FIXED_POINT_DIVISOR = BigDecimal(10**FIXED_POINT_DECIMALS)

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

          converted_value = convert_from_fixed_point(raw_value, config[:value_type])

          # Compare with current SystemParameter (type-aware comparison)
          current = SystemParameter.current(param_key)
          if current.present? && values_equal?(current, converted_value, config[:value_type])
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

    # Type-aware comparison to avoid false updates due to string representation differences.
    # e.g., BigDecimal('10.0').to_s vs Integer(10).to_s → '10.0' vs '10'.
    def values_equal?(current, on_chain, value_type)
      case value_type
      when "integer"
        current.to_i == on_chain.to_i
      when "float", "decimal"
        (current.to_f - on_chain.to_f).abs < 1e-15
      else
        current.to_s == on_chain.to_s
      end
    end

    # Compute Solidity-compatible keccak256 hash of a string for mapping key.
    # Returns bytes32 hex string matching Solidity: keccak256("lorenz_sigma").
    def solidity_keccak256(str)
      Eth::Util.keccak256(str)
    end

    # Convert raw uint256 (18-decimal fixed-point) to Ruby value.
    # All on-chain values use 18 decimals: 10.0 → 10_000000000000000000.
    # Integer-typed params (iterations=250, emission_threshold=10000) are also
    # stored as 250e18 / 10000e18 on-chain and converted back to integers here.
    def convert_from_fixed_point(raw_uint256, value_type)
      decimal_value = BigDecimal(raw_uint256.to_s) / FIXED_POINT_DIVISOR

      case value_type
      when "integer"
        decimal_value.to_i
      else
        decimal_value
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
