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

    # [ARCH.94 / ARCH.59] Семпл stall-глибини ПЕРЕЇХАВ у `MintStallProbeWorker`
    # (cron `55 * * * *`), бо `on(:success)` не спрацьовує саме тоді, коли емісія
    # застрягла найгірше — коли чанки падають. Вісь перецілено: тут лишається пін
    # на ВІДСУТНІСТЬ сайту, з фікстурою, що перетинає поріг — інакше він був би
    # зелений і при поверненому семплі, що звітує нуль.
    it "does NOT sample the stall gauge from here" do
      tree = create(:tree, status: :active)
      tree.wallet.update!(balance: TokenomicsEvaluatorWorker.emission_threshold * 2, locked_balance: 0)

      allow(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to receive(:set)

      described_class.new.on_success(Sidekiq::Batch::Status.new("bid"), { "cycle_id" => "cycle" })

      expect(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).not_to have_received(:set)
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
