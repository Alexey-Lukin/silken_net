# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module PuroEarth
  # =========================================================================
  # 🌿 PURO.EARTH REGISTRY API SERVICE (D-MRV Submission via REST)
  # =========================================================================
  # Submits Biomass Passport data to the Puro.earth REST API for CORC
  # (CO₂ Removal Certificate) issuance. This is the off-chain counterpart
  # to PassportService's on-chain anchoring — together they provide both
  # immutable provenance (Polygon) and registry compliance (Puro.earth).
  #
  # The service:
  # 1. Constructs a D-MRV submission payload including on-chain tx_hash
  # 2. Authenticates via Bearer token (Rails credentials or ENV)
  # 3. POSTs to Puro.earth /v1/dmrv/submissions endpoint
  # 4. Returns the CORC reference ID for tracking certification status
  #
  # Pattern: follows Dclimate::VerificationService (Web3::HttpClient,
  # Bearer auth, structured error handling, ENV-gated base URL).
  #
  # Usage:
  #   corc_ref = PuroEarth::RegistryApiService.new(payload, tx_hash: "0x...").submit!
  # =========================================================================
  class RegistryApiService
    class SubmissionError < StandardError; end

    # Base URL for the Puro.earth Registry API. Override via ENV for UAT
    # (`https://registry.api.purouat.com/registry/api` — access requested separately).
    # [ARCH.118, 2026-09-02] Retargeted from `https://api.puro.earth`: that host has NO A record
    # (measured with a positive control in the same run), while the documented production base
    # below answers 200 — docs.api.puro.earth/registry/overview. ⚠️ The PATH below the base is
    # still unproven without a key (the OpenAPI spec is served at `<base>-json`); a hardcoded
    # third-party host is a claim about someone else's infrastructure and ages without any
    # commit of ours — re-probe it, never trust the changelog (00_07 ARCH.118).
    PURO_EARTH_API_URL = ENV.fetch("PURO_EARTH_API_URL", "https://registry.api.puro.earth/registry/api")

    # D-MRV submission endpoint for Biochar CORC applications.
    SUBMISSIONS_ENDPOINT = "/v1/dmrv/submissions"

    # --- HTTP Timeouts (aligned with Sidekiq worker constraints) ---
    OPEN_TIMEOUT = 10  # seconds for TCP/TLS handshake
    READ_TIMEOUT = 30  # seconds for response (submission processing)

    # @param payload [Hash] D-MRV passport payload (tree_did, biomass_yield_kg, etc.)
    # @param tx_hash [String] Polygon on-chain anchoring transaction hash ("0x...")
    def initialize(payload, tx_hash:)
      @payload = payload
      @tx_hash = tx_hash
    end

    # Submits the Biomass Passport to Puro.earth and returns the CORC reference.
    #
    # @return [String] CORC reference ID (e.g., "CORC-2026-XXXXXXXX")
    # @raise [SubmissionError] on API failure, authentication error, or invalid response
    def submit!
      response_data = post_submission
      corc_ref = extract_corc_reference(response_data)

      Rails.logger.info "🌿 [Puro.earth] D-MRV submission accepted. " \
                        "Tree: #{@payload[:tree_did]}, CORC ref: #{corc_ref}"

      corc_ref
    rescue Web3::HttpClient::RequestError => e
      raise SubmissionError, "Puro.earth API request failed: #{e.message}"
    rescue StandardError => e
      raise SubmissionError, "Puro.earth submission failed: #{e.message}"
    end

    private

    # POST D-MRV submission to Puro.earth API.
    # Includes both the passport payload and on-chain proof (tx_hash)
    # for cross-referencing the immutable Polygon record.
    def post_submission
      headers = build_headers
      body = build_submission_body

      response = Web3::HttpClient.post(
        "#{PURO_EARTH_API_URL.chomp("/")}#{SUBMISSIONS_ENDPOINT}",
        body: body,
        headers: headers,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        service_name: "Puro.earth"
      )

      response.parsed_body
    end

    # Constructs the D-MRV submission body.
    # Includes passport data, on-chain proof, and source metadata
    # for Puro Standard methodology compliance.
    def build_submission_body
      {
        source: "silkennet",
        methodology: "biochar-corc",
        on_chain_proof: {
          network: "polygon",
          tx_hash: @tx_hash,
          contract: ENV.fetch("PURO_EARTH_REGISTRY_CONTRACT_ADDRESS", nil)
        },
        passport: {
          tree_did: @payload[:tree_did],
          biomass_yield_kg: @payload[:biomass_yield_kg],
          extraction_date: @payload[:extraction_date],
          gps_coordinates: @payload[:gps_coordinates],
          lifetime_telemetry_hash: @payload[:lifetime_telemetry_hash]
        }
      }
    end

    # Builds HTTP headers with Bearer authentication.
    # API key sourced from Rails credentials (preferred) or ENV fallback.
    def build_headers
      headers = { "Accept" => "application/json" }
      api_key = resolve_api_key

      headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
      headers
    end

    # Resolves API key from ENV (preferred, SEC.22) or Rails credentials (fallback).
    # ENV: PURO_EARTH_API_KEY
    # Credentials: Rails.application.credentials.dig(:puro_earth, :api_key)
    def resolve_api_key
      ENV["PURO_EARTH_API_KEY"].presence ||
        Rails.application.credentials.dig(:puro_earth, :api_key)
    end

    # Extracts the CORC reference from Puro.earth API response.
    # Expected response format: { "submission_id": "...", "corc_ref": "CORC-2026-XXXXXXXX", ... }
    def extract_corc_reference(response_data)
      corc_ref = response_data["corc_ref"] || response_data["submission_id"]

      unless corc_ref.present?
        raise SubmissionError, "Puro.earth API response missing CORC reference: #{response_data.inspect}"
      end

      corc_ref
    end
  end
end
