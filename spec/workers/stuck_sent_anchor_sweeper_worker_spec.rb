# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StuckSentAnchorSweeperWorker, type: :worker do
  def make_stuck(anchor)
    anchor.update_column(:updated_at, (EthereumAnchor::STUCK_SENT_THRESHOLD + 1.hour).ago)
    anchor
  end

  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end
  end

  describe "#perform" do
    it "re-arms confirmation for an anchor stuck in :sent past the threshold" do
      stuck = make_stuck(create(:ethereum_anchor, :sent))

      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async).with(stuck.id)

      described_class.new.perform

      expect(EthereumAnchorConfirmationWorker).to have_received(:perform_async).with(stuck.id)
    end

    it "ignores a fresh :sent anchor still within the live-poller window" do
      create(:ethereum_anchor, :sent)

      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(EthereumAnchorConfirmationWorker).not_to have_received(:perform_async)
    end

    it "ignores terminal anchors (confirmed) regardless of age" do
      make_stuck(create(:ethereum_anchor, :confirmed))

      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(EthereumAnchorConfirmationWorker).not_to have_received(:perform_async)
    end

    it "skips a row already resolved before re-arm (reload-guard vs a live poller)" do
      stuck = make_stuck(create(:ethereum_anchor, :sent))
      allow(EthereumAnchor).to receive(:stuck_sent).and_return(EthereumAnchor.where(id: stuck.id))
      stuck.update_column(:status, EthereumAnchor.statuses[:confirmed])

      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(EthereumAnchorConfirmationWorker).not_to have_received(:perform_async)
    end

    it "does not log when nothing is stuck" do
      create(:ethereum_anchor, :sent) # fresh — not stuck

      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:info)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn).with(/Re-armed/)
      expect(Rails.logger).not_to have_received(:info).with(/Розглянуто/)
    end

    # 🔴 [PERF.1] Свідок для НУЛЬОВОГО результату — третій член класу (два сусіди
    # дістали його раніше). Без нього свіпер німий рівно тоді, коли reload-гард
    # пропустив УСЮ вибірку: оператор не бачить ані «є N застряглих якорів», ані
    # «усіх довершив живий поллер», а це доказова база L1-якоря.
    it "says out loud that it examined anchors even when it re-armed NONE" do
      stuck = make_stuck(create(:ethereum_anchor, :sent))
      allow(EthereumAnchor).to receive(:stuck_sent).and_return(EthereumAnchor.where(id: stuck.id))
      stuck.update_column(:status, EthereumAnchor.statuses[:confirmed])

      allow(Rails.logger).to receive(:info).with(/Розглянуто 1 stuck-:sent anchor/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/Розглянуто 1 stuck-:sent anchor/)
    end

    it "skips a row deleted between SELECT and reload (RecordNotFound)" do
      stuck = make_stuck(create(:ethereum_anchor, :sent))
      allow(EthereumAnchor).to receive(:stuck_sent).and_return(EthereumAnchor.where(id: stuck.id))
      allow_any_instance_of(EthereumAnchor).to receive(:reload).and_raise(ActiveRecord::RecordNotFound)

      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async)

      expect { described_class.new.perform }.not_to raise_error

      expect(EthereumAnchorConfirmationWorker).not_to have_received(:perform_async)
    end

    it "caps re-arms at BATCH_LIMIT per run (backlog drains across successive crons)" do
      stub_const("#{described_class}::BATCH_LIMIT", 2)
      3.times { make_stuck(create(:ethereum_anchor, :sent)) }

      armed = 0
      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async) { armed += 1 }

      described_class.new.perform

      expect(armed).to eq(2)
    end
  end
end
