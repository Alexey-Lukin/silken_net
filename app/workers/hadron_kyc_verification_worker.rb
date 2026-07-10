# frozen_string_literal: true

# [KYC.1] Верифікація KYC бенефіціара мінтингу через Polygon Hadron.
# Enqueue: after_commit на біндингу/зміні crypto_public_address
# (Organization / Wallet — KYC чіпляється до адреси, зміна = ре-верифікація).
# Dev без hadron_api_key → simulate-approve; production АБО WEB3_STRICT_MODE →
# реальний API або loud fail (HadronComplianceService — belt-and-suspenders).
class HadronKycVerificationWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_low", retry: 5

  SUBJECTS = { "Wallet" => Wallet, "Organization" => Organization }.freeze

  def perform(subject_type, subject_id)
    subject = SUBJECTS.fetch(subject_type).find(subject_id)

    with_web3_error_handling("Hadron", "#{subject_type} ##{subject_id} KYC") do
      case subject
      when Wallet
        if subject.crypto_public_address.blank?
          Rails.logger.info "🛡️ [Hadron] Wallet ##{subject_id} has no own address (custodial — org-KYC governs), skipping"
          next
        end
        Polygon::HadronComplianceService.new.verify_investor!(subject)
      when Organization
        Polygon::HadronComplianceService.new.verify_organization!(subject)
      end
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "🛡️ [Hadron] #{subject_type} ##{subject_id} not found, skipping"
  end
end
