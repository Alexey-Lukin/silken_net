# frozen_string_literal: true

class HadronAssetRegistrationWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  def perform(naas_contract_id)
    naas_contract = NaasContract.find(naas_contract_id)

    Polygon::HadronComplianceService.new.register_asset!(naas_contract)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "🛡️ [Hadron] NaaSContract ##{naas_contract_id} not found, skipping"
  end
end
