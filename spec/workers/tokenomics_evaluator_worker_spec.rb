# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TokenomicsEvaluatorWorker, type: :worker do
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "with eligible wallets above threshold" do
      it "enqueues EvaluateTreeBatchWorker for eligible wallets" do
        tree = create(:tree, status: :active)
        wallet = create(:wallet, tree: tree, balance: 25_000)

        described_class.new.perform

        expect(EvaluateTreeBatchWorker.jobs.size).to be >= 1
        enqueued_ids = EvaluateTreeBatchWorker.jobs.flat_map { |j| j["args"].first }
        expect(enqueued_ids).to include(wallet.id)
      end

      it "creates a Sidekiq::Batch with description and callback" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 10_000)

        batch_instance = nil
        allow(Sidekiq::Batch).to receive(:new).and_wrap_original do |method, *args|
          batch_instance = method.call(*args)
          batch_instance
        end

        described_class.new.perform

        expect(batch_instance).to be_present
        expect(batch_instance.description).to start_with("Tokenomics Cycle")
        expect(batch_instance.callbacks).to include(
          hash_including(event: :success, klass: TokenomicsBatchCallbacks)
        )
      end

      it "passes cycle_id to callback options" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 10_000)

        batch_instance = nil
        allow(Sidekiq::Batch).to receive(:new).and_wrap_original do |method, *args|
          batch_instance = method.call(*args)
          batch_instance
        end

        described_class.new.perform

        callback = batch_instance.callbacks.find { |c| c[:klass] == TokenomicsBatchCallbacks }
        expect(callback[:options]).to have_key("cycle_id")
        expect(callback[:options]["cycle_id"]).to be_present
      end
    end

    context "with wallets below threshold" do
      it "does not enqueue any batch workers" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 9_999)

        described_class.new.perform

        expect(EvaluateTreeBatchWorker.jobs).to be_empty
      end
    end

    context "with inactive trees" do
      it "skips wallets of inactive trees" do
        tree = create(:tree, status: :removed)
        create(:wallet, tree: tree, balance: 50_000)

        described_class.new.perform

        expect(EvaluateTreeBatchWorker.jobs).to be_empty
      end
    end

    # [ARCH.94] Gross-баланс іще над порогом, але все вже сконвертовано (locked
    # лишається назавжди — 04_01 §6 E.66), тож мінтувати такому гаманцю нічого.
    # Селектор по `balance` тягнув би його в кожен цикл довіку.
    context "with fully converted wallets" do
      it "skips a wallet whose balance is entirely locked" do
        tree = create(:tree, status: :active)
        create(:wallet, tree: tree, balance: 50_000, locked_balance: 50_000)

        described_class.new.perform

        expect(EvaluateTreeBatchWorker.jobs).to be_empty
      end
    end

    it "handles empty eligible wallets gracefully" do
      expect { described_class.new.perform }.not_to raise_error
      expect(EvaluateTreeBatchWorker.jobs).to be_empty
    end
  end

  describe "sidekiq options" do
    it "uses default queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("default")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end

    it "has unique_for set to 60 minutes" do
      expect(described_class.get_sidekiq_options["unique_for"]).to eq(60.minutes)
    end
  end

  describe "BATCH_CHUNK_SIZE" do
    it "is configured for planetary scale" do
      expect(described_class::BATCH_CHUNK_SIZE).to eq(1_000)
    end
  end

  describe ".emission_threshold" do
    it "defaults to EMISSION_THRESHOLD" do
      expect(described_class.emission_threshold).to eq(10_000)
    end

    it "reads the governance value from SystemParameter (GOV.1)" do
      create(:system_parameter, :emission_threshold, value: "12000")
      expect(described_class.emission_threshold).to eq(12_000)
    end

    it "falls back to the default on a non-positive value (mis-scale guard)" do
      create(:system_parameter, key: "emission_threshold", value: "0",
                                value_type: "integer", category: "tokenomics")
      expect(described_class.emission_threshold).to eq(10_000)
    end
  end
end
