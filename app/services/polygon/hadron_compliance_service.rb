# frozen_string_literal: true

module Polygon
  # =========================================================================
  # 🛡️ HADRON COMPLIANCE SERVICE (Юридичний Щит RWA)
  # =========================================================================
  # Інтегрує Polygon Hadron для забезпечення відповідності RWA (Real World Assets).
  # Перевіряє KYC/KYB статус інвесторів та реєструє фізичні лісові ділянки
  # як регульовані активи на платформі Hadron перед мінтингом ERC-3643.
  #
  # Два потоки:
  #   1. verify_investor!(wallet)  — перевірка KYC через Hadron Identity
  #   2. register_asset!(contract) — реєстрація лісової ділянки як RWA
  # =========================================================================
  class HadronComplianceService
    HADRON_API_URL = ENV.fetch("HADRON_API_URL", "https://api.hadron.polygon.technology")
    TIMEOUT_OPEN   = 10  # секунд
    TIMEOUT_READ   = 30  # секунд

    class ComplianceError < StandardError; end

    # Перевіряє KYC статус гаманця через Polygon Hadron Identity.
    # Оновлює wallet.hadron_kyc_status на 'approved' або 'rejected'.
    def verify_investor!(wallet)
      raise ComplianceError, "Wallet must have a crypto_public_address" if wallet.crypto_public_address.blank?

      response = check_kyc_status(wallet.crypto_public_address)

      new_status = response[:approved] ? "approved" : "rejected"
      wallet.update!(hadron_kyc_status: new_status)

      Rails.logger.info "🛡️ [Hadron] KYC #{new_status} for Wallet ##{wallet.id} (#{wallet.crypto_public_address})"

      new_status
    end

    # Реєструє фізичну лісову ділянку (NaaSContract) як RWA на Hadron.
    # Зберігає отриманий asset_id у NaaSContract.
    def register_asset!(naas_contract)
      raise ComplianceError, "NaaSContract must be active" unless naas_contract.status_active?
      raise ComplianceError, "NaaSContract must have an associated Cluster for RWA asset registration" if naas_contract.cluster.blank?

      response = register_rwa_asset(naas_contract)
      asset_id = response[:asset_id]

      naas_contract.update!(hadron_asset_id: asset_id)

      Rails.logger.info "🛡️ [Hadron] RWA Asset registered: #{asset_id} for NaaSContract ##{naas_contract.id}"

      asset_id
    end

    private

    # Симулює API-виклик до Hadron Identity Platform для перевірки KYC.
    # У production буде реальний HTTP-запит до Hadron API.
    def check_kyc_status(crypto_address)
      api_key = Rails.application.credentials.hadron_api_key

      if api_key.present?
        perform_kyc_request(crypto_address, api_key)
      else
        simulate_kyc_check(crypto_address)
      end
    end

    # Симулює реєстрацію RWA активу на Hadron.
    # У production буде реальний HTTP-запит до Hadron API.
    def register_rwa_asset(naas_contract)
      api_key = Rails.application.credentials.hadron_api_key

      if api_key.present?
        perform_asset_registration(naas_contract, api_key)
      else
        simulate_asset_registration(naas_contract)
      end
    end

    # --- Production API calls ---

    def perform_kyc_request(crypto_address, api_key)
      response = Web3::HttpClient.post("#{HADRON_API_URL}/identity/kyc/verify",
        body: { wallet_address: crypto_address, chain: "polygon" },
        headers: { "Authorization" => "Bearer #{api_key}" },
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ,
        service_name: "Hadron"
      )

      body = response.parsed_body
      { approved: body["status"] == "approved" }
    rescue Web3::HttpClient::RequestError => e
      raise ComplianceError, e.message
    end

    def perform_asset_registration(naas_contract, api_key)
      response = Web3::HttpClient.post("#{HADRON_API_URL}/assets/rwa/register",
        body: build_asset_payload(naas_contract),
        headers: { "Authorization" => "Bearer #{api_key}" },
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ,
        service_name: "Hadron"
      )

      body = response.parsed_body
      asset_id = body["asset_id"]
      raise ComplianceError, "Hadron did not return an asset_id" if asset_id.blank?

      { asset_id: asset_id }
    rescue Web3::HttpClient::RequestError => e
      raise ComplianceError, e.message
    end

    # --- Simulation mode (no API key configured) ---

    def simulate_kyc_check(crypto_address)
      Rails.logger.info "🛡️ [Hadron] Simulating KYC check for #{crypto_address}"
      { approved: true }
    end

    def simulate_asset_registration(naas_contract)
      asset_id = "HADRON-RWA-#{naas_contract.id}-#{SecureRandom.hex(8)}"
      Rails.logger.info "🛡️ [Hadron] Simulating RWA registration → #{asset_id}"
      { asset_id: asset_id }
    end

    def build_asset_payload(naas_contract)
      {
        asset_type: "forest_plot",
        chain: "polygon",
        organization_id: naas_contract.organization_id,
        cluster_id: naas_contract.cluster_id,
        total_funding: naas_contract.total_funding.to_f,
        start_date: naas_contract.start_date.iso8601,
        end_date: naas_contract.end_date.iso8601,
        metadata: {
          source: "silken_net",
          contract_status: naas_contract.status
        }
      }
    end
  end
end
