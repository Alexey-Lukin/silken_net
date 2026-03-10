# frozen_string_literal: true

module Chainlink
  class OracleDispatchService
    class DispatchError < StandardError; end

    # Lorenz attractor defaults (σ, ρ, β)
    LORENZ_SIGMA = 10
    LORENZ_RHO   = 28
    LORENZ_BETA  = Rational(8, 3)

    def initialize(telemetry_log)
      @log = telemetry_log
      @tree = telemetry_log.tree
    end

    def dispatch!
      validate_iotex_verification!

      payload = build_chainlink_payload
      request_id = simulate_chainlink_request(payload)

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
          sigma: LORENZ_SIGMA,
          rho: LORENZ_RHO,
          beta: LORENZ_BETA.to_f,
          z_value: @log.z_value.to_f
        },
        zk_proof_ref: @log.zk_proof_ref,
        tree_did: @tree.did,
        telemetry_log_id: @log.id,
        timestamp: Time.current.iso8601
      }
    end

    # Simulates sending a request to the Chainlink Functions DON.
    # In production, this would call the Chainlink Functions Router contract
    # via Eth::Client to submit the request on-chain.
    def simulate_chainlink_request(_payload)
      "chainlink-req-#{SecureRandom.hex(16)}"
    end
  end
end
