# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TokenomicsBatchCallbacks do
  describe "#on_success" do
    it "enqueues MintCarbonCoinWorker for auto-discovery minting" do
      status = Sidekiq::Batch::Status.new("test-bid")
      options = { "cycle_id" => "test-cycle-uuid" }

      described_class.new.on_success(status, options)

      expect(MintCarbonCoinWorker.jobs.size).to eq(1)
      # Auto-discovery mode: no arguments
      expect(MintCarbonCoinWorker.jobs.first["args"]).to be_empty
    end

    # [ARCH.94] Детектор застрягання емісії. Дискримінатор точний: мінт піднімає
    # `locked_balance`, тож ПІСЛЯ здорового циклу eligible-множина порожня за
    # побудовою — усе, що в ній лишилось, мало змінтувати й не змінтувало.
    describe "stall depth gauge" do
      let(:threshold) { TokenomicsEvaluatorWorker.emission_threshold }
      let(:status) { Sidekiq::Batch::Status.new("bid") }
      let(:options) { { "cycle_id" => "cycle" } }

      it "reports depth 0 when every eligible wallet converted its points" do
        tree = create(:tree, status: :active)
        # available = balance − locked = 0 → сконвертовано, більше не eligible
        tree.wallet.update!(balance: threshold, locked_balance: threshold)

        allow(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to receive(:set).with(0)

        described_class.new.on_success(status, options)

        expect(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to have_received(:set).with(0)
      end

      it "reports a non-zero depth when an eligible wallet produced no mint" do
        tree = create(:tree, status: :active)
        # Фікстура МУСИТЬ перетинати поріг, інакше клас невидимий (04_06 §B.2 BP #14).
        tree.wallet.update!(balance: threshold * 2, locked_balance: 0)

        allow(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to receive(:set).with(1)

        described_class.new.on_success(status, options)

        expect(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to have_received(:set).with(1)
      end

      it "never lets the visibility probe break the money path" do
        allow(TokenomicsEvaluatorWorker).to receive(:eligible_wallets).and_raise(StandardError, "db down")

        expect { described_class.new.on_success(status, options) }.not_to raise_error
        expect(MintCarbonCoinWorker.jobs.size).to eq(1)
      end
    end

    it "logs batch completion with cycle_id" do
      status = Sidekiq::Batch::Status.new("abc123")
      options = { "cycle_id" => "my-cycle" }

      allow(Rails.logger).to receive(:info).with(/Батч abc123 завершено.*my-cycle/)

      described_class.new.on_success(status, options)

      expect(Rails.logger).to have_received(:info).with(/Батч abc123 завершено.*my-cycle/)
    end
  end
end
