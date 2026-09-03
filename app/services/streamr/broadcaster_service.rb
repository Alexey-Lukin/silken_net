# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Streamr
  class BroadcasterService
    TIMEOUT_OPEN = 5   # seconds
    TIMEOUT_READ = 10  # seconds

class BroadcastError < StandardError; end

# [ARCH.118, 2026-09-03] ACTIVATION GATE — the one home of «is this leg live», same shape as
# `Iotex::W3bstreamVerificationService.configured?` (OPS.37). An UNCONFIGURED leg must
# enqueue NOTHING: a job that can only raise buys one execution and ~30 Redis commands per
# telemetry record for nothing, and Upstash bills per COMMAND (00_07 INF.28) — the worker's
# own `rescue` kept that failure quiet, not free. ⚠️ Not a verdict on Streamr itself: the
# Brubeck data-api host is dead (TLS never completes) and keep-vs-drop is the founder's open
# ⚖️ in ARCH.118; this predicate neither decides it nor pre-empts it.
def self.configured?
  stream_id, api_key = credential_pair
  stream_id.present? && api_key.present?
end

# ENV-first, credentials fallback (SEC.22) — ONE resolver for the gate and the publisher,
# so «configured» and «what we would publish with» can never disagree.
def self.credential_pair
  [
    ENV["STREAMR_STREAM_ID"].presence || Rails.application.credentials.streamr_stream_id,
    ENV["STREAMR_API_KEY"].presence || Rails.application.credentials.streamr_api_key
  ]
end

def initialize(telemetry_log)
      @telemetry_log = telemetry_log
      @tree = telemetry_log.tree
    end

    # Транслює телеметрію в мережу Streamr для «прямого ефіру» лісу.
    # Це сирі, неверифіковані дані для реального часу — не для фінансового консенсусу.
    def broadcast!
      payload = build_payload
      publish_to_streamr(payload)
    end

    private

    def build_payload
      {
        tree_id: @tree.id,
        peaq_did: @tree.peaq_did,
        lorenz_state: {
          z_value: @telemetry_log.z_value.to_f,
          bio_status: @telemetry_log.bio_status
        },
        timestamp: @telemetry_log.created_at.iso8601(6),
        alerts: {
          critical: @telemetry_log.critical?,
          acoustic_events: @telemetry_log.acoustic_events,
          temperature_c: @telemetry_log.temperature_c.to_f,
          voltage_mv: @telemetry_log.voltage_mv
        }
      }
    end

    def publish_to_streamr(payload)
      stream_id, api_key = self.class.credential_pair

      raise BroadcastError, "streamr_stream_id не налаштовано в credentials" if stream_id.blank?
      raise BroadcastError, "streamr_api_key не налаштовано в credentials" if api_key.blank?

      encoded_stream_id = ERB::Util.url_encode(stream_id)
      url = "https://brubeck.streamr.network/api/v1/streams/#{encoded_stream_id}/data"

      Web3::HttpClient.post(url,
        body: payload,
        headers: { "Authorization" => "Bearer #{api_key}" },
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ,
        service_name: "Streamr"
      )
    rescue Web3::HttpClient::RequestError => e
      raise BroadcastError, e.message
    end
  end
end
