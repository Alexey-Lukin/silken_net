# frozen_string_literal: true

class HadronAssetRegistrationWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_low", retry: 5

  def perform(naas_contract_id)
    naas_contract = NaasContract.find(naas_contract_id)

    with_web3_error_handling("Hadron", "NaaSContract ##{naas_contract_id}") do
      Polygon::HadronComplianceService.new.register_asset!(naas_contract)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "🛡️ [Hadron] NaaSContract ##{naas_contract_id} not found, skipping"
  end
end
