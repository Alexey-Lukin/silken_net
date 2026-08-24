# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CeloConfirmationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tx) do
    create(:blockchain_transaction, sourceable: cluster, token_type: :cusd, blockchain_network: "celo",
                                    status: :sent, reward_date: Date.yesterday, amount: 5.0,
                                    tx_hash: "0x#{SecureRandom.hex(32)}")
  end
  let(:mock_client) { instance_double(Eth::Client) }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
    silence_broadcasts!(:tx_status)
  end

  def envelope(status)
    { "result" => { "status" => status } }
  end

  it "confirms a mined reward (status 0x1)" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))

    described_class.new.perform(tx.id, tx.created_at.iso8601)

    expect(tx.reload.status).to eq("confirmed")
  end

  it "fails a reverted reward (cUSD never moved → re-payable)" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))

    described_class.new.perform(tx.id, tx.created_at.iso8601)

    expect(tx.reload.status).to eq("failed")
  end

  it "raises (Sidekiq retry) while the tx is still pending (nil result)" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })

    expect { described_class.new.perform(tx.id, tx.created_at.iso8601) }.to raise_error(/ще не підтверджено/)
    expect(tx.reload.status).to eq("sent")
  end

  it "skips (idempotent) a tx that is no longer :sent" do
    tx.update_column(:status, BlockchainTransaction.statuses[:confirmed])

    described_class.new.perform(tx.id, tx.created_at.iso8601)

    # returned before building the client → no Celo RPC poll
    expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
  end

  it "no-ops when the tx is not found" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  describe "sidekiq_retries_exhausted — escalation (ARCH.50)" do
    let(:msg) { { "args" => [ tx.id, tx.created_at.iso8601 ] } }

    it "escalates a still-:sent reward to manual_review (no blind re-pay vs RPC lag)" do
      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("polling вичерпано"))
      expect(tx.reload.status).to eq("manual_review")
    end

    it "leaves an already-resolved (non-:sent) reward untouched" do
      tx.update_column(:status, BlockchainTransaction.statuses[:confirmed])
      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("polling вичерпано"))
      expect(tx.reload.status).to eq("confirmed")
    end
  end
end
