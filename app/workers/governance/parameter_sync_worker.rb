# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Governance
  # = ===================================================================
  # 🏛️ GOVERNANCE PARAMETER SYNC WORKER
  # = ===================================================================
  # Синхронізує параметри протоколу з on-chain ProtocolParameters.sol
  # у локальну SystemParameter модель Rails.
  #
  # Запускається 1×/день (cron: 30 3 * * *), зчитує поточні параметри
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
  # Див: docs/05_06 §7, ARCH.4, GOV.1
  class ParameterSyncWorker
    include ApplicationWeb3Worker

    sidekiq_options queue: "web3_low", retry: 3, unique_for: 24.hours

    # Маппінг on-chain параметрів до SystemParameter ключів — дзеркало
    # Well-Known Keys у ProtocolParameters.sol; value_type/category/bounds
    # узгоджені з db/seeds.rb (той самий запис, та сама валідація).
    # On-chain значення зберігаються як uint256 з 18 decimals (1e18 = 1.0).
    # min/max — safety-межі проти мис-скейлу (18-decimals slip / нонсенс-голос,
    # напр. tax=2e18 «200%» → beneficiary_amount<0 → mint-halt): out-of-bounds
    # значення НЕ записується (bounds-валідація SystemParameter), чинним
    # лишається попереднє + ERROR-лог + метрика → коригувальний DAO-голос.
    PARAMETER_MAP = {
      # Tokenomics
      emission_threshold:        { value_type: "integer", category: "tokenomics", min: 1_000,  max: 100_000 },
      dynamic_tax_rate:          { value_type: "decimal", category: "minting",    min: 0,      max: 0.10 },
      insurance_pool_threshold:  { value_type: "integer", category: "insurance",  min: 10_000, max: 1_000_000 },
      scc_per_tonne_co2:         { value_type: "integer", category: "tokenomics", min: 100,    max: 100_000 },
      scc_fallback_price_usd:    { value_type: "float",   category: "tokenomics", min: 0.01,   max: 1000.0 },
      # Slashing (05_05 §3) + slash/stress пороги
      slash_threshold:           { value_type: "float",   category: "alerts",     min: 0.05,   max: 1.0 },
      stress_threshold:          { value_type: "float",   category: "alerts",     min: 0.65,   max: 1.0 }, # [E.64] floor > Z-anomaly base_stress 0.6 (§7 «Z alone never slashes»: DAO не може опустити поріг під anomaly-рівень, інакше Z сам би слешив)
      slash_gamma:               { value_type: "float",   category: "alerts",     min: 1.0,    max: 3.0 },
      slash_penalty_factor_max:  { value_type: "float",   category: "alerts",     min: 1.0,    max: 5.0 }
    }.freeze

    # [GOV.1] Lorenz-ключі СВІДОМО не синхронізуються: константи биті-в-біт
    # спільні з прошитим firmware (FW.7 DCI) — governance-зміна зламала б
    # device↔server parity. Tripwire нижче: якщо DAO таки проголосував такий
    # ключ — гучний WARN (ефект нульовий до координованого fleet-reflash),
    # НЕ тихе ігнорування. Дім: 03_04 + 05_06 §7.
    DCI_LOCKED_KEYS = %i[
      lorenz_sigma lorenz_rho lorenz_beta lorenz_dt
      lorenz_iterations lorenz_z_min lorenz_z_max lorenz_z_target
    ].freeze

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
      rejected = 0

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

          begin
            SystemParameter.set(
              param_key,
              converted_value.to_s,
              updated_by: system_bot,
              value_type: config[:value_type],
              category: config[:category],
              min_value: config[:min],
              max_value: config[:max],
              source: "governance"
            )
          rescue ActiveRecord::RecordInvalid => e
            rejected += 1
            Rails.logger.error "🛑 [Governance] REJECTED #{param_key}=#{converted_value} " \
                               "(bounds #{config[:min]}..#{config[:max]}): " \
                               "#{e.record.errors.full_messages.join('; ')}. " \
                               "Чинним лишається попереднє значення — потрібен коригувальний DAO-голос."
            SilkenNet::Metrics::GOVERNANCE_PARAM_REJECTED_TOTAL.increment(labels: { parameter: param_key.to_s })
            next
          end

          Rails.logger.info "🏛️ [Governance] Updated #{param_key}: #{current} → #{converted_value}"
          synced += 1
        end

        warn_dci_locked_votes(client, contract)
      end

      Rails.logger.info "🏛️ [Governance] Sync complete: #{synced} updated, #{skipped} skipped, #{rejected} rejected."
    end

    private

    # [GOV.1] Tripwire: DCI-locked ключ проголосовано on-chain → гучний WARN,
    # без запису в SystemParameter (жоден споживач не сміє його читати).
    def warn_dci_locked_votes(client, contract)
      DCI_LOCKED_KEYS.each do |param_key|
        on_chain_key = solidity_keccak256(param_key.to_s)

        is_set = Timeout.timeout(RPC_TIMEOUT_SECONDS) do
          client.call(contract, "isParameterSet", on_chain_key)
        end
        next unless is_set

        Rails.logger.warn "⚠️ [Governance] DCI-locked #{param_key} проголосовано on-chain — " \
                          "свідомо НЕ синхронізується (FW.7 bit-parity з прошитим firmware; " \
                          "набуття ефекту = координований fleet-reflash — 03_04, 05_06 §7)."
      end
    end

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
    # Returns bytes32 hex string matching Solidity: keccak256("slash_gamma").
    def solidity_keccak256(str)
      Eth::Util.keccak256(str)
    end

    # Convert raw uint256 (18-decimal fixed-point) to Ruby value.
    # All on-chain values use 18 decimals: 10.0 → 10_000000000000000000.
    # Integer-typed params (emission_threshold=10000, scc_per_tonne_co2=2000) are
    # also stored as 10000e18 / 2000e18 on-chain and converted back to integers here.
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
