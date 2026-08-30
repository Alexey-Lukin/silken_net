# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractTerminationService do
  before do
    silence_broadcasts!(:tree_map)
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

    # [BIZ.22, ⚖️ 2026-08-30] Опція 1 MSA: результат несе ЛИШЕ burned — точна
    # рівність є негативним піном проти тихого повернення refund/fee-ключів.
    it "returns burned only — no refund/fee keys under MSA Option 1" do
      contract.update!(early_exit_fee_percent: 10, burn_accrued_points: false)

      result = described_class.call(contract)

      expect(result).to eq({ burned: false })
    end

    context "when transaction rolls back (P0 fix)" do
      it "does not enqueue BurnCarbonTokensWorker" do
        contract.update!(burn_accrued_points: true)

        # Force update! to succeed but then raise before transaction commits,
        # triggering a full rollback
        original_update = contract.method(:update!)
        call_count = 0
        allow(contract).to receive(:update!) do |**args|
          call_count += 1
          original_update.call(**args)
          raise StandardError, "DB constraint violation"
        end

        BurnCarbonTokensWorker.jobs.clear

        expect {
          described_class.call(contract) rescue nil
        }.not_to change(BurnCarbonTokensWorker.jobs, :size)

        # Verify contract is NOT cancelled (transaction rolled back)
        contract.reload
        expect(contract).to be_status_active
      end
    end
  end
end
