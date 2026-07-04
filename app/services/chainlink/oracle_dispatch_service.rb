# frozen_string_literal: true

module Chainlink
  # [ARCH.53 демоут]: PATH 1 (Chainlink Functions DON) unwired — on-chain sendRequest
  # прибрано (LINK-cost за callback, що не прилетить: нема DON source/consumer/relayer,
  # а tx_hash ≠ requestId — callback-lookup ніколи б не збігся). Мінт іде PATH 2
  # (tokenomics, чесна L0-custodial модель + ex-post clawback — 05_02 §trust-origin).
  # dispatch! лишається як internal correlation-marker: chainlink_request_id живе
  # dedup-ключем Solana-винагород та idempotency-guard'ом dispatch/callback-шляхів.
  # On-chain гілка (Router ABI registry + bytecode probe + ARCH.49 nonce-lock)
  # воскресає з git, коли PATH 1 замкнеться справжньою DON-інженерією.
  class OracleDispatchService
    class DispatchError < StandardError; end

    def initialize(telemetry_log)
      @log = telemetry_log
    end

    def dispatch!
      validate_iotex_verification!

      request_id = "chainlink-req-#{SecureRandom.hex(16)}"

      @log.update!(
        chainlink_request_id: request_id,
        oracle_status: "dispatched"
      )

      Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{@log.id} dispatched (local marker). Request ID: #{request_id}"

      request_id
    end

    private

    def validate_iotex_verification!
      return if @log.verified_by_iotex?

      raise DispatchError, "TelemetryLog ##{@log.id} не верифіковано IoTeX. Chainlink dispatch відхилено."
    end
  end
end
