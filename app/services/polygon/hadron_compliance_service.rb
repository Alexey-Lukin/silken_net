# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # [ARCH.119 ⚖️ 2026-09-04] ДВІ ОСІ, доти дубльовані умовою у двох приватних
    # методах. `configured?` — чи є РЕАЛЬНИЙ провайдер; `simulation_allowed?` — чи
    # легальна заглушка; `verification_reachable?` — чи виклик здатен ЗАВЕРШИТИСЬ
    # хоч якось. Гейт enqueue стоїть на ТРЕТЬОМУ: без провайдера (ARCH.118 —
    # продукту не існує, статус не вийде з "pending" НІКОЛИ) кожна поставлена
    # джоба лише проходить `retry: 5` у Dead Set, тобто це retry-драбина, не гард.
    # ⛔ НЕ гейтуй на `configured?`: у dev/test заглушка легальна й мінт-демо
    # тримається саме на ній — це купило б гейт ціною непрацездатного dev-тракту.
    def self.api_key
      ENV["HADRON_API_KEY"].presence || Rails.application.credentials.hadron_api_key
    end

    def self.configured?
      api_key.present?
    end

    def self.simulation_allowed?
      !(ENV["WEB3_STRICT_MODE"] == "true" || Rails.env.production?)
    end

    def self.verification_reachable?
      configured? || simulation_allowed?
    end

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

    # [KYC.1] KYC організації-бенефіціара: custodial-гаманці (без власної адреси)
    # мінтять на адресу організації → її статус успадковується
    # (Wallet#kyc_approved_for_minting?).
    def verify_organization!(organization)
      raise ComplianceError, "Organization must have a crypto_public_address" if organization.crypto_public_address.blank?

      response = check_kyc_status(organization.crypto_public_address)

      new_status = response[:approved] ? "approved" : "rejected"
      organization.update!(hadron_kyc_status: new_status)

      Rails.logger.info "🛡️ [Hadron] KYC #{new_status} for Organization ##{organization.id} (#{organization.crypto_public_address})"

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

    # [BLOCKER-4 FIX]: У production АБО WEB3_STRICT_MODE заглушки вимкнено (belt-and-suspenders,
    # дзеркало oracle_callbacks/helium_sos — прапор може дрейфнути з deploy-поверхні, production — ні;
    # інакше забутий прапор → simulate = fake-KYC approve → фродовий mint через kyc_approved_for_minting?).
    def check_kyc_status(crypto_address)
      key = self.class.api_key

      if key.present?
        perform_kyc_request(crypto_address, key)
      elsif self.class.simulation_allowed?
        simulate_kyc_check(crypto_address)
      else
        raise ComplianceError, "hadron_api_key обов'язковий у production / WEB3_STRICT_MODE."
      end
    end

    # [BLOCKER-4 FIX]: У production АБО WEB3_STRICT_MODE заглушки вимкнено (belt-and-suspenders,
    # дзеркало oracle_callbacks/helium_sos — прапор може дрейфнути з deploy-поверхні, production — ні;
    # інакше забутий прапор → simulate = fake-KYC approve → фродовий mint через kyc_approved_for_minting?).
    def register_rwa_asset(naas_contract)
      key = self.class.api_key

      if key.present?
        perform_asset_registration(naas_contract, key)
      elsif self.class.simulation_allowed?
        simulate_asset_registration(naas_contract)
      else
        raise ComplianceError, "hadron_api_key обов'язковий у production / WEB3_STRICT_MODE."
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
