# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::LoadTest::DrainBench do
  def stub_sidekiq(queue_sizes: Hash.new(0), busy: 0, retries: 0, scheduled: 0)
    allow(Sidekiq::Queue).to receive(:new) { |q| instance_double(Sidekiq::Queue, size: queue_sizes[q]) }
    allow(Sidekiq::Workers).to receive(:new).and_return(instance_double(Sidekiq::Workers, size: busy))
    allow(Sidekiq::RetrySet).to receive(:new).and_return(instance_double(Sidekiq::RetrySet, size: retries))
    allow(Sidekiq::ScheduledSet).to receive(:new).and_return(instance_double(Sidekiq::ScheduledSet, size: scheduled))
  end

  describe ".cascade_drained?" do
    it "true лише коли всі черги + busy + retry + scheduled нульові" do
      stub_sidekiq
      expect(described_class.cascade_drained?).to be(true)
    end

    it "false коли web3_critical ще повна (uplink==0 недостатньо — red-team #2)" do
      stub_sidekiq(queue_sizes: Hash.new(0).merge("web3_critical" => 5))
      expect(described_class.cascade_drained?).to be(false)
    end

    it "false коли є busy-воркер (job знятий, size==0, але ще виконується)" do
      stub_sidekiq(busy: 2)
      expect(described_class.cascade_drained?).to be(false)
    end

    it "false коли RetrySet непорожній (невидимий для голого queue.size)" do
      stub_sidekiq(retries: 1)
      expect(described_class.cascade_drained?).to be(false)
    end
  end

  describe "згенерований батч реально проходить каскад (валідний вхід → commit)" do
    it "UnpackTelemetryWorker декриптить + комітить рядок на кожне дерево" do
      result = SilkenNet::LoadTest::Provisioning.provision(trees: 3)
      # web3-downstream (real HTTPX) поза скоупом intake→commit виміру
      allow(IotexVerificationWorker).to receive(:perform_async)
      allow(TimeSyncDownlinkWorker).to receive(:perform_async)

      key     = result.gateway.hardware_key.binary_key
      dids    = result.trees.map { |t| t.did.delete_prefix("SNET-").to_i(16) }
      payload = SilkenNet::LoadTest::TelemetryBatchFactory.encrypted_batch(key: key, dids: dids)

      expect do
        UnpackTelemetryWorker.new.perform(
          Base64.strict_encode64(payload), result.gateway.ip_address, result.gateway.uid
        )
      end.to change(TelemetryLog, :count).by(3)

      SilkenNet::LoadTest::Provisioning.teardown(result)
    end
  end

  describe "arrival divergence detection" do
    it "flagує монотонно зростаючий backlog, не чіпає плоский" do
      expect(described_class.send(:diverging?, (1..12).to_a)).to be(true)
      expect(described_class.send(:diverging?, Array.new(12, 5))).to be(false)
    end

    it "withholds a verdict on fewer than six samples (too short to judge a trend)" do
      expect(described_class.send(:diverging?, [ 1, 2, 3, 4, 5 ])).to be(false)
    end
  end

  # The drain/arrival LOOPS themselves need a live Sidekiq process (bin/coap_load vs a
  # dev/staging stack) — integration-class, out of host-unit scope (04_06 §B.1.3). Only the
  # pure input-guard is unit-checkable here.
  describe "run_arrival input guard" do
    it "rejects a non-positive arrival rate before enqueueing anything" do
      expect { described_class.run_arrival(Object.new, batches: 1, lambda_per_s: 0) }
        .to raise_error(ArgumentError, /lambda_per_s/)
    end
  end
end
