# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [PERF.1(д)] Власний lifecycle-поллер Puro-анкера («третя форма», прецедент
# EthereumAnchorConfirmationWorker): доти конфірмейшн-нога вела в
# blockchain_transactions, куди паспортний хеш не потрапляє ніколи.
RSpec.describe PuroEarthConfirmationWorker, type: :worker do
  let(:fake_tx_hash) { "0x#{"fa" * 32}" }
  let(:tree) { create(:tree, status: :deceased) }
  let(:record) do
    create(:maintenance_record, :biomass_extraction, maintainable: tree,
                                                     biomass_passport_tx_hash: fake_tx_hash,
                                                     biomass_passport_status: :sent)
  end
  let(:mock_client) { instance_double(Eth::Client) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
    allow(PuroEarthPassportWorker).to receive(:perform_async)
  end

  def envelope(status)
    { "result" => { "status" => status, "blockNumber" => "0xe4e1c0", "gasUsed" => "0xb798" } }
  end

  describe "sidekiq_options" do
    it("polls on web3_low — not money-path, no locked funds waiting") {
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    }
  end

  it "confirms a mined anchor (0x1) and re-enqueues the orchestrator to open Phase 3" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))

    described_class.new.perform(record.id)

    expect(record.reload).to be_biomass_passport_confirmed
    expect(PuroEarthPassportWorker).to have_received(:perform_async).with(record.id)
  end

  it "fails a reverted anchor (0x0) terminally and does NOT open Phase 3" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))

    described_class.new.perform(record.id)

    expect(record.reload).to be_biomass_passport_failed
    expect(PuroEarthPassportWorker).not_to have_received(:perform_async)
  end

  it "raises (Sidekiq retry) while the tx is still in the mempool" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })

    expect { described_class.new.perform(record.id) }.to raise_error(/мемпулі/)
    expect(record.reload).to be_biomass_passport_sent
  end

  it "is a no-op for a record already resolved by a concurrent poller" do
    record.update!(biomass_passport_status: :confirmed)

    described_class.new.perform(record.id)

    expect(mock_client).not_to have_received(:client_for) if mock_client.respond_to?(:client_for)
    expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
  end

  it "is a no-op for a vanished record id" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  # Гонкові else-гілки: програвший поллер (перехід повернув false) не робить
  # side-effects — ані Phase-3 enqueue, ані error-лог, ані warn.
  describe "race losers stay silent" do
    it "does not enqueue the orchestrator when a concurrent poller already confirmed" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))
      allow(record).to receive(:confirm_biomass_passport!).and_return(false)
      allow(MaintenanceRecord).to receive(:find_by).and_return(record)

      described_class.new.resolve!(record, final: false)

      expect(PuroEarthPassportWorker).not_to have_received(:perform_async)
    end

    it "does not log the terminal error when fail! loses the race" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))
      allow(record).to receive(:fail_biomass_passport!).and_return(false)

      allow(Rails.logger).to receive(:error)

      described_class.new.resolve!(record, final: false)

      expect(Rails.logger).not_to have_received(:error)
    end

    it "does not warn when escalate loses the race on the final re-check" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })
      allow(record).to receive(:escalate_biomass_passport!).and_return(false)

      allow(Rails.logger).to receive(:warn)

      described_class.new.resolve!(record, final: true)

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  it "skips the exhausted hook for a record already resolved elsewhere" do
    record.update!(biomass_passport_status: :confirmed)

    described_class.sidekiq_retries_exhausted_block.call({ "args" => [ record.id ] }, nil)

    expect(record.reload).to be_biomass_passport_confirmed
  end

  describe "retries_exhausted → final receipt re-check (ARCH.66 precedent)" do
    let(:msg) { { "args" => [ record.id ] } }

    it "confirms on the final re-check when the tx mined during the last retry window" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))

      described_class.sidekiq_retries_exhausted_block.call(msg, nil)

      expect(record.reload).to be_biomass_passport_confirmed
    end

    it "escalates to manual_review when the receipt is still pending after the final re-check" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })

      described_class.sidekiq_retries_exhausted_block.call(msg, nil)

      expect(record.reload).to be_biomass_passport_manual_review
    end

    it "escalates (not :sent-limbo) when the final re-check itself blows up on RPC" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_raise(IOError, "rpc down")

      described_class.sidekiq_retries_exhausted_block.call(msg, nil)

      expect(record.reload).to be_biomass_passport_manual_review
    end
  end
end
