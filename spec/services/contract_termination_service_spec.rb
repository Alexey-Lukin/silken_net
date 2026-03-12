# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractTerminationService do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

  describe ".call" do
    it "changes status to cancelled and sets cancelled_at" do
      described_class.call(contract)
      contract.reload

      expect(contract).to be_status_cancelled
      expect(contract.cancelled_at).to be_present
    end

    it "raises when contract is not active" do
      contract.update_column(:status, NaasContract.statuses[:draft])

      expect { described_class.call(contract) }.to raise_error(RuntimeError, /не активний/)
    end

    it "raises when minimum days before exit not met" do
      contract.update!(start_date: 10.days.ago, min_days_before_exit: 60)

      expect { described_class.call(contract) }.to raise_error(RuntimeError, /Мінімальний термін/)
    end

    it "enqueues BurnCarbonTokensWorker when burn_accrued_points is true" do
      contract.update!(burn_accrued_points: true)

      described_class.call(contract)

      expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
    end

    it "does not enqueue BurnCarbonTokensWorker when burn_accrued_points is false" do
      contract.update!(burn_accrued_points: false)

      described_class.call(contract)

      expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
    end

    it "returns refund and fee details" do
      contract.update!(early_exit_fee_percent: 10, burn_accrued_points: false)

      result = described_class.call(contract)

      expect(result).to include(:refund, :fee, :burned)
      expect(result[:burned]).to be(false)
    end
  end
end
