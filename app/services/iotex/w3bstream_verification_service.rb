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

    # [BLOCKER-06 FIX]: Ed25519-підпис payload'у ключем з HardwareKey.binary_key.
    # Замість SHA256-хеша, формуємо криптографічний підпис, що доводить
    # апаратне походження даних із конкретного STM32 пристрою.
    # W3bstream може верифікувати, що саме цей пристрій надіслав цю телеметрію.
    def hardware_signature
      hardware_key = @tree.hardware_key
      if hardware_key&.binary_key.present?
        message = "#{@tree.did}:#{@telemetry_log.id_value}:#{@telemetry_log.created_at.to_i}"
        Ed25519Crypto::SigningService.sign(hardware_key.binary_key, message)
      else
        # [S6.13]: Fallback допустимий ТІЛЬКИ для legacy/dev (TRL ≤ 5, lab benches).
        # У production / WEB3_STRICT_MODE — fail-closed: SHA256 не доводить апаратне
        # походження, тому пакет з відсутнім HardwareKey не може отримати ZK-proof
        # рівноцінний справжньому Ed25519-підпису.
        reason = hardware_key.nil? ? "missing_hardware_key" : "missing_binary_key"
        SilkenNet::Metrics::W3BSTREAM_SIGNATURE_FALLBACK_TOTAL.increment(labels: { reason: reason })

        if Rails.env.production? || ENV["WEB3_STRICT_MODE"] == "true"
          raise VerificationError,
                "HardwareKey відсутній для Tree #{@tree.did} (reason=#{reason}). " \
                "SHA256 fallback заборонений у production / WEB3_STRICT_MODE=true — " \
                "потрібно provision'ити пристрій через POST /api/v1/provisioning/register."
        end

        Rails.logger.warn "⚠️ [W3bstream] HardwareKey відсутній для Tree #{@tree.did} (#{reason}). " \
                          "Використовуємо SHA256 fallback (legacy/dev лише; не підтверджує апаратне походження)."
        Digest::SHA256.hexdigest("#{@tree.did}:#{@telemetry_log.id_value}:#{@telemetry_log.created_at.to_i}")
      end
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

    # [BLOCKER-07 FIX]: Додана валідація формату proof reference.
    # Перевіряємо, що zk_proof_ref відповідає очікуваному формату
    # (hex, UUID, або W3bstream proof ID: alphanumeric + hyphens),
    # а не є довільним рядком з пробілами чи спецсимволами.
    ZK_PROOF_REF_PATTERN = /\A[0-9a-zA-Z\-_]{8,128}\z/

    def parse_response(response)
      body = response.parsed_body
      zk_proof_ref = body["proof_id"] || body["receipt_id"]

      raise VerificationError, "W3bstream не повернув proof reference" if zk_proof_ref.blank?

      unless zk_proof_ref.match?(ZK_PROOF_REF_PATTERN)
        raise VerificationError, "W3bstream повернув невалідний proof reference: #{zk_proof_ref.truncate(50)}"
      end

      zk_proof_ref
    rescue Web3::HttpClient::RequestError => e
      raise VerificationError, "W3bstream response error: #{e.message}"
    end
  end
end
