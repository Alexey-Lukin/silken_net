# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Iotex
  class W3bstreamVerificationService
    TIMEOUT_OPEN  = 10  # seconds
    TIMEOUT_READ  = 30  # seconds

    class VerificationError < StandardError; end

    # [OPS.37 / ARCH.118] ACTIVATION GATE — one home for «is the W3bstream leg live at all».
    # Both values are ENV-first with a credentials fallback (SEC.22); neither sits on any deploy
    # surface today, and the URL that `.env.example` used to carry (`w3bstream-api.iotex.io`)
    # has no DNS record (measured 2026-09-02) — so on canopy AND on a first production deploy
    # the leg is unconfigured, not broken. Unconfigured ⇒ nothing enqueues, nothing re-arms:
    # the previous shape raised `VerificationError` inside the retry ladder for EVERY telemetry
    # record (6 attempts → Dead Set, hourly backfill re-arming 200 more), i.e. ~85% of all job
    # executions and Redis commands of a slot were failure work invisible to Sentry (the
    # exception is in `excluded_exceptions`). ⚠️ Not a mint gate and never was: PATH 2 mints
    # optimistically (05_02 «Чесна рамка»); `verified_by_iotex` stays honestly false until the
    # leg is activated by provisioning both values — the same shape as the aux signers.
    def self.configured?
      url = ENV["IOTEX_W3BSTREAM_URL"].presence || Rails.application.credentials.iotex_w3bstream_url
      key = ENV["IOTEX_API_KEY"].presence || Rails.application.credentials.iotex_api_key
      url.present? && key.present?
    end

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

    # [BLOCKER-06 FIX + ARCH.42 update 2026-05-23]: Ed25519-підпис payload'у
    # окремим Iotex-seed (HKDF з PROVISIONING_MASTER_KEY + device_uid). До ARCH.42
    # підпис використовував HardwareKey.binary_key (AES-256, 32 байти випадково
    # збігалося з Ed25519 seed size). Після ARCH.42 Tree AES = 16 байт — недосить
    # для Ed25519. Тому деривуємо окремий 32-байтний seed через info "silken-ed25519
    # -iotex-v1" — domain separation з AES (LoRa/CoAP) та Lorenz K_seed.
    def hardware_signature
      hardware_key = @tree.hardware_key
      if hardware_key&.binary_key.present?
        message = "#{@tree.did}:#{@telemetry_log.id_value}:#{@telemetry_log.created_at.to_i}"
        iotex_seed_hex = HardwareKeyService.derive_iotex_seed(@tree.did)
        Ed25519Crypto::SigningService.sign(iotex_seed_hex, message)
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
                "потрібно provision'ити пристрій через POST /provisioning/register."
        end

        Rails.logger.warn "⚠️ [W3bstream] HardwareKey відсутній для Tree #{@tree.did} (#{reason}). " \
                          "Використовуємо SHA256 fallback (legacy/dev лише; не підтверджує апаратне походження)."
        Digest::SHA256.hexdigest("#{@tree.did}:#{@telemetry_log.id_value}:#{@telemetry_log.created_at.to_i}")
      end
    end

    def send_to_w3bstream(payload)
      w3bstream_url = ENV["IOTEX_W3BSTREAM_URL"].presence || Rails.application.credentials.iotex_w3bstream_url
      api_key       = ENV["IOTEX_API_KEY"].presence || Rails.application.credentials.iotex_api_key

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
