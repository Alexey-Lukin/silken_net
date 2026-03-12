# frozen_string_literal: true

module Iotex
  class W3bstreamVerificationService
    TIMEOUT_OPEN  = 10  # seconds
    TIMEOUT_READ  = 30  # seconds

    class VerificationError < StandardError; end

    def initialize(telemetry_log)
      @telemetry_log = telemetry_log
      @tree = telemetry_log.tree
    end

    # Відправляє телеметрію на W3bstream для ZK-верифікації та повертає proof reference.
    def verify!
      payload = build_payload
      response = send_to_w3bstream(payload)
      parse_response(response)
    end

    private

    def build_payload
      {
        device_id: @tree.did,
        peaq_did: @tree.peaq_did,
        telemetry_log_id: @telemetry_log.id_value,
        timestamp: @telemetry_log.created_at.to_i,
        hardware_signature: hardware_signature,
        chaotic_data: {
          z_value: @telemetry_log.z_value.to_f,
          temperature_c: @telemetry_log.temperature_c.to_f,
          acoustic_events: @telemetry_log.acoustic_events,
          voltage_mv: @telemetry_log.voltage_mv,
          bio_status: @telemetry_log.bio_status
        }
      }
    end

    def hardware_signature
      Digest::SHA256.hexdigest("#{@tree.did}:#{@telemetry_log.id_value}:#{@telemetry_log.created_at.to_i}")
    end

    def send_to_w3bstream(payload)
      w3bstream_url = Rails.application.credentials.iotex_w3bstream_url
      api_key       = Rails.application.credentials.iotex_api_key

      raise VerificationError, "iotex_w3bstream_url не налаштовано в credentials" if w3bstream_url.blank?
      raise VerificationError, "iotex_api_key не налаштовано в credentials" if api_key.blank?

      Web3::HttpClient.post("#{w3bstream_url}/verify",
        body: payload,
        headers: { "Authorization" => "Bearer #{api_key}" },
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ,
        service_name: "W3bstream"
      )
    rescue Web3::HttpClient::RequestError => e
      raise VerificationError, e.message
    end

    def parse_response(response)
      body = response.parsed_body
      zk_proof_ref = body["proof_id"] || body["receipt_id"]

      raise VerificationError, "W3bstream не повернув proof reference" if zk_proof_ref.blank?

      zk_proof_ref
    rescue Web3::HttpClient::RequestError => e
      raise VerificationError, "Невалідна JSON-відповідь від W3bstream: #{e.message}"
    end
  end
end
