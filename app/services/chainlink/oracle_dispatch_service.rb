# frozen_string_literal: true

module Chainlink
  class OracleDispatchService
    class DispatchError < StandardError; end

    # Lorenz attractor constants — single source of truth in SilkenNet::Attractor.
    # We delegate to avoid duplication: σ=10, ρ=28, β=8/3.
    delegate :BASE_SIGMA, :BASE_RHO, :BASE_BETA, to: SilkenNet::Attractor

    def initialize(telemetry_log)
      @log = telemetry_log
      @tree = telemetry_log.tree
    end

    def dispatch!
      validate_iotex_verification!

      payload = build_chainlink_payload
      request_id = submit_chainlink_request(payload)

      @log.update!(
        chainlink_request_id: request_id,
        oracle_status: "dispatched"
      )

      Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{@log.id} dispatched. Request ID: #{request_id}"

      request_id
    end

    private

    def validate_iotex_verification!
      return if @log.verified_by_iotex?

      raise DispatchError, "TelemetryLog ##{@log.id} не верифіковано IoTeX. Chainlink dispatch відхилено."
    end

    def build_chainlink_payload
      {
        peaq_did: @tree.peaq_did,
        lorenz_state: {
          sigma: SilkenNet::Attractor::BASE_SIGMA.to_f,
          rho: SilkenNet::Attractor::BASE_RHO.to_f,
          beta: SilkenNet::Attractor::BASE_BETA.to_f,
          z_value: @log.z_value.to_f
        },
        zk_proof_ref: @log.zk_proof_ref,
        tree_did: @tree.did,
        telemetry_log_id: @log.id,
        # [SCALE]: created_at is the partition key for telemetry_logs.
        # Embedding it in the Chainlink request allows the callback to
        # include it, enabling partition pruning on billions of rows.
        created_at: @log.created_at.iso8601(6),
        timestamp: Time.current.iso8601
      }
    end

    # Submits a request to the Chainlink Functions DON.
    # In production (CHAINLINK_FUNCTIONS_ROUTER configured): calls the Router
    # contract on-chain via Eth::Client to submit the request.
    # In development/test (no key): generates a local stub request ID.
    # [BLOCKER-4 FIX]: У production (WEB3_STRICT_MODE=true) заглушки вимкнено —
    # відсутність credentials викликає помилку замість фейкової відповіді.
    def submit_chainlink_request(payload)
      router_address = ENV["CHAINLINK_FUNCTIONS_ROUTER"]
      subscription_id = ENV["CHAINLINK_SUBSCRIPTION_ID"]

      if router_address.present? && subscription_id.present?
        send_on_chain_request(payload, router_address, subscription_id)
      elsif ENV["WEB3_STRICT_MODE"] == "true"
        raise DispatchError, "CHAINLINK_FUNCTIONS_ROUTER та CHAINLINK_SUBSCRIPTION_ID обов'язкові у Production (WEB3_STRICT_MODE=true)."
      else
        Rails.logger.info "🔗 [Chainlink] Stub mode — CHAINLINK_FUNCTIONS_ROUTER не налаштовано. Генерую локальний request ID."
        "chainlink-req-#{SecureRandom.hex(16)}"
      end
    end

    def send_on_chain_request(payload, router_address, subscription_id)
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      contract = Eth::Contract.from_abi(
        name: "FunctionsRouter",
        address: router_address,
        abi: functions_router_abi
      )

      # [BLOCKER-09 FIX]: Передаємо всі обов'язкові параметри Chainlink Functions Router v1.
      data_version = ENV.fetch("CHAINLINK_DATA_VERSION", "1").to_i
      callback_gas_limit = ENV.fetch("CHAINLINK_CALLBACK_GAS_LIMIT", "300000").to_i
      don_id = ENV.fetch("CHAINLINK_DON_ID") { raise DispatchError, "CHAINLINK_DON_ID обов'язковий для on-chain dispatch" }

      tx_hash = client.transact(
        contract, "sendRequest",
        subscription_id.to_i,
        payload.to_json,
        data_version,
        callback_gas_limit,
        don_id,
        sender_key: oracle_key,
        legacy: false
      )

      Rails.logger.info "🔗 [Chainlink] On-chain request submitted. TX: #{tx_hash}"
      tx_hash
    rescue StandardError => e
      raise DispatchError, "Chainlink on-chain dispatch failed: #{e.message}"
    end

    # [BLOCKER-09 FIX]: Актуальний ABI Chainlink Functions Router v1 (Polygon Mainnet).
    # Додані обов'язкові параметри: dataVersion, callbackGasLimit, donId.
    def functions_router_abi
      [
        {
          "inputs" => [
            { "internalType" => "uint64", "name" => "subscriptionId", "type" => "uint64" },
            { "internalType" => "bytes", "name" => "data", "type" => "bytes" },
            { "internalType" => "uint16", "name" => "dataVersion", "type" => "uint16" },
            { "internalType" => "uint32", "name" => "callbackGasLimit", "type" => "uint32" },
            { "internalType" => "bytes32", "name" => "donId", "type" => "bytes32" }
          ],
          "name" => "sendRequest",
          "outputs" => [ { "internalType" => "bytes32", "name" => "requestId", "type" => "bytes32" } ],
          "stateMutability" => "nonpayable",
          "type" => "function"
        }
      ].to_json
    end
  end
end
