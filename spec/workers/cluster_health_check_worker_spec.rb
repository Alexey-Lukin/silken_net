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

    it "logs breached contracts" do
      allow_any_instance_of(NaasContract).to receive(:check_cluster_health!) do |contract, _date|
        contract.update_column(:status, :breached)
      end

      expect(Rails.logger).to receive(:warn).with(/ПОРУШЕНО/).at_least(:once)

      described_class.new.perform
    end
  end
end
