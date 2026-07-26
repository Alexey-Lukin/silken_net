# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterHealthCheckWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

  before do
    allow_any_instance_of(Cluster).to receive(:recalculate_health_index!)
    allow_any_instance_of(NaasContract).to receive(:check_cluster_health!)
  end

  describe "#perform" do
    it "processes all active NaaS contracts without errors" do
      expect { described_class.new.perform }.not_to raise_error
    end

    it "passes date_string to NaasContract health check" do
      date = "2026-03-06"

      expect { described_class.new.perform(date) }.not_to raise_error
    end

    it "handles nil date_string gracefully" do
      expect { described_class.new.perform(nil) }.not_to raise_error
    end

    it "continues processing when a single contract errors" do
      contract2 = create(:naas_contract, organization: organization, cluster: cluster, status: :active)

      call_count = 0
      allow_any_instance_of(NaasContract).to receive(:check_cluster_health!) do
        call_count += 1
        raise "DB Error" if call_count == 1
      end

      expect { described_class.new.perform }.not_to raise_error
    end

    it "logs flagged (degraded) contracts" do
      allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:degraded)

      expect(Rails.logger).to receive(:warn).with(/ФЛАГОВАНО/).at_least(:once)

      described_class.new.perform
    end

    context "with explicit date_string parameter" do
      it "parses the date_string and passes it to health check" do
        date_string = "2026-06-15"
        expected_date = Date.parse(date_string)

        expect_any_instance_of(Cluster).to receive(:recalculate_health_index!).with(expected_date)
        expect_any_instance_of(NaasContract).to receive(:check_cluster_health!).with(expected_date)

        described_class.new.perform(date_string)
      end
    end

    context "when branching on the health verdict (SLASH-1)" do
      before { allow(CeloRewardWorker).to receive(:perform_async) }

      it "counts a flagged (:degraded) contract and does NOT reward it" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:degraded)
        allow(Rails.logger).to receive(:info).and_call_original
        allow(Rails.logger).to receive(:warn).and_call_original

        described_class.new.perform

        expect(Rails.logger).to have_received(:warn).with(/ФЛАГОВАНО/).at_least(:once)
        expect(Rails.logger).to have_received(:info).with(/Флаговано: 1/)
        expect(CeloRewardWorker).not_to have_received(:perform_async)
      end

      it "rewards a :healthy cluster via CeloRewardWorker" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:healthy)

        described_class.new.perform

        expect(CeloRewardWorker).to have_received(:perform_async).with(cluster.id, anything)
      end

      it "does NOT reward a :blackout cluster (force-majeure under audit)" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:blackout)

        described_class.new.perform

        expect(CeloRewardWorker).not_to have_received(:perform_async)
      end
    end
  end
end
