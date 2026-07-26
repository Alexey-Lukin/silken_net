# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterEntropySweepWorker, type: :worker do
  describe "#perform" do
    it "enqueues ClusterEntropyAnalyzerWorker for every cluster" do
      org = create(:organization)
      clusters = create_list(:cluster, 3, organization: org)
      allow(ClusterEntropyAnalyzerWorker).to receive(:perform_async)

      described_class.new.perform

      clusters.each do |cluster|
        expect(ClusterEntropyAnalyzerWorker).to have_received(:perform_async).with(cluster.id)
      end
    end

    it "enqueues nothing when there are no clusters" do
      allow(ClusterEntropyAnalyzerWorker).to receive(:perform_async)

      described_class.new.perform

      expect(ClusterEntropyAnalyzerWorker).not_to have_received(:perform_async)
    end
  end
end
