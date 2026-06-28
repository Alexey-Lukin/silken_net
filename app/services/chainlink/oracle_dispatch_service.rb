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

      version = pick_router_version(client, router_address)

      contract = Eth::Contract.from_abi(
        name: "FunctionsRouter",
        address: router_address,
        abi: functions_router_abi(version)
      )

      # [BLOCKER-09 FIX]: Передаємо всі обов'язкові параметри Chainlink Functions Router v1.
      data_version = ENV.fetch("CHAINLINK_DATA_VERSION", "1").to_i
      callback_gas_limit = ENV.fetch("CHAINLINK_CALLBACK_GAS_LIMIT", "300000").to_i
      don_id = ENV.fetch("CHAINLINK_DON_ID") { raise DispatchError, "CHAINLINK_DON_ID обов'язковий для on-chain dispatch" }

      # [ARCH.49] Серіалізуємо підпис на спільній base-EOA (той самий lock, що mint/burn/celo):
      # eth-gem бере nonce per-call → конкурентні підписи колізять nonce. Це гарячий per-uplink
      # шлях, тож контенція реальна. LockTimeout re-raise нижче (перед StandardError) — інакше
      # lock-не-взято хибно став би DispatchError замість чистого retry.
      tx_hash = nil
      Kredis.lock("lock:web3:oracle:#{oracle_key.address}", expires_in: 30.seconds, after_timeout: :raise) do
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
      end

      Rails.logger.info "🔗 [Chainlink] On-chain request submitted (router=#{version}). TX: #{tx_hash}"
      tx_hash
    rescue Web3::ChainlinkRouterVersion::UnsupportedVersionError,
           Web3::ChainlinkRouterVersion::MissingAbiError => e
      raise DispatchError, "Chainlink router ABI registry error: #{e.message}"
    rescue Kredis::LockTimeout
      raise # lock не взято → transact не виконувався → чистий Sidekiq-retry, НЕ DispatchError
    rescue StandardError => e
      raise DispatchError, "Chainlink on-chain dispatch failed: #{e.message}"
    end

    # [S6.15] Resolve which Chainlink Functions Router ABI version to use.
    # 1. Read the active version from `CHAINLINK_ROUTER_VERSION` ENV (defaults v1).
    # 2. Pull the deployed Router bytecode (`eth_getCode`) and verify the
    #    expected `sendRequest` selector is present in the dispatch table.
    # 3. If verification fails, attempt the previous registered version
    #    (graceful fallback during a Router upgrade window).
    # 4. If no fallback is registered, raise a `DispatchError` — refuse
    #    to submit a request against an unknown ABI shape.
    #
    # When `CHAINLINK_ROUTER_BYTECODE_CHECK=false` (for staging/dev RPC
    # endpoints that strip `eth_getCode`), the bytecode probe is skipped
    # and the active version is trusted as-is.
    def pick_router_version(client, router_address)
      active = Web3::ChainlinkRouterVersion.active_version
      return active unless bytecode_check_enabled?

      code_hex = fetch_router_code(client, router_address)

      if Web3::ChainlinkRouterVersion.selector_present_in_code?(code_hex, active)
        return active
      end

      fallback = Web3::ChainlinkRouterVersion.fallback_for(active)
      if fallback && Web3::ChainlinkRouterVersion.selector_present_in_code?(code_hex, fallback)
        Rails.logger.warn(
          "🔗 [Chainlink] Router #{router_address} bytecode does not expose " \
          "active version #{active} selector " \
          "(#{Web3::ChainlinkRouterVersion.selector_for(active)}); " \
          "falling back to #{fallback}."
        )
        return fallback
      end

      raise DispatchError,
            "Chainlink Router #{router_address} не експортує очікуваний " \
            "`#{Web3::ChainlinkRouterVersion.signature_for(active)}` селектор " \
            "(#{Web3::ChainlinkRouterVersion.selector_for(active)}). " \
            "Перевір CHAINLINK_FUNCTIONS_ROUTER та CHAINLINK_ROUTER_VERSION."
    end

    def bytecode_check_enabled?
      ENV.fetch("CHAINLINK_ROUTER_BYTECODE_CHECK", "true") == "true"
    end

    # Returns hex-encoded bytecode (with or without `0x` prefix), or nil
    # if the RPC client does not expose `eth_getCode`. We intentionally
    # do not raise here — `selector_present_in_code?` returns false on
    # blank input, and `pick_router_version` handles the fallback chain.
    #
    # The dual `Hash` / `String` shape handles two real-world RPC client
    # return contracts: `Eth::Client` returns the raw `result` field as a
    # String, while some pooled / instrumented wrappers (and JSON-RPC
    # transports configured with `raw_response: true`) return the full
    # `{ "id" => ..., "result" => "0x...", ... }` envelope. Normalising
    # here keeps the probe ergonomically simple for both cases.
    def fetch_router_code(client, router_address)
      if client.respond_to?(:eth_get_code)
        result = client.eth_get_code(router_address, "latest")
        return result.is_a?(Hash) ? result["result"] : result
      end
      nil
    rescue StandardError => e
      Rails.logger.warn "🔗 [Chainlink] eth_getCode probe failed: #{e.message}"
      nil
    end

    # [BLOCKER-09 FIX]: Актуальний ABI Chainlink Functions Router v1 (Polygon Mainnet).
    # Додані обов'язкові параметри: dataVersion, callbackGasLimit, donId.
    # [S6.15]: ABI delegated to Web3::ChainlinkRouterVersion registry so
    # adding a future Router upgrade only requires a new registry entry.
    def functions_router_abi(version = Web3::ChainlinkRouterVersion.active_version)
      Web3::ChainlinkRouterVersion.abi_for(version).to_json
    end
  end
end
