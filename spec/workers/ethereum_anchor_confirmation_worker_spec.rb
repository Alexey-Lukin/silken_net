# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchorConfirmationWorker, type: :worker do
  let(:anchor) { create(:ethereum_anchor, :sent) }
  let(:mock_client) { instance_double(Eth::Client) }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
    # Reorg-gate off за замовчуванням (0) — базові тести не потребують eth_block_number stub;
    # сам gate покритий describe "reorg-depth gate".
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_MIN_CONFIRMATIONS", anything).and_return(0)
  end

  # Receipt-envelope як його повертає eth-gem (hex-поля).
  def envelope(status, block: "0xe4e1c0", gas: "0xb798")
    { "result" => { "status" => status, "blockNumber" => block, "gasUsed" => gas } }
  end

  describe "sidekiq_options" do
    it("uses the web3_low queue") { expect(described_class.sidekiq_options["queue"]).to eq("web3_low") }
    it("has a long retry horizon for slow L1 inclusion") { expect(described_class.sidekiq_options["retry"]).to eq(60) }

    it "uses a FIXED 180s retry interval (NOT exponential — bounded ~3h horizon)" do
      expect(described_class.sidekiq_retry_in_block.call(5, StandardError.new)).to eq(180)
    end
  end

  # --- normal poll (final: false) ---
  it "confirms a mined anchor (status 0x1), parsing block_number/gas_used from hex" do
    allow(mock_client).to receive(:eth_get_transaction_receipt)
      .and_return(envelope("0x1", block: "0xe4e1c0", gas: "0xb798"))

    described_class.new.perform(anchor.id)

    expect(anchor.reload).to be_status_confirmed
    expect(anchor.block_number).to eq(0xe4e1c0)
    expect(anchor.gas_used).to eq(0xb798)
  end

  it "confirms a flat receipt with already-integer block/gas (legacy/flat envelope)" do
    # [LOW-1/LOW-3] receipt без "result"-обгортки + поля вже Integer (не hex-string):
    # confirm_anchor! бере flat-гілку, hex_to_i повертає Integer as-is.
    allow(mock_client).to receive(:eth_get_transaction_receipt)
      .and_return("status" => "0x1", "blockNumber" => 15_000_000, "gasUsed" => 47_000)

    described_class.new.perform(anchor.id)

    expect(anchor.reload).to be_status_confirmed
    expect(anchor.block_number).to eq(15_000_000)
    expect(anchor.gas_used).to eq(47_000)
  end

  it "confirms with a nil gasUsed (partial receipt — block present, gas absent)" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1", gas: nil))

    described_class.new.perform(anchor.id)

    expect(anchor.reload).to be_status_confirmed
    expect(anchor.gas_used).to be_nil
  end

  it "fails a reverted anchor (status 0x0) and increments the reverted counter" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))
    allow(SilkenNet::Metrics::ETHEREUM_ANCHOR_REVERTED_TOTAL).to receive(:increment)

    described_class.new.perform(anchor.id)

    expect(SilkenNet::Metrics::ETHEREUM_ANCHOR_REVERTED_TOTAL).to have_received(:increment)

    expect(anchor.reload).to be_status_failed
  end

  it "raises (Sidekiq retry) while the tx is still pending (nil result)" do
    allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })

    expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
    expect(anchor.reload).to be_status_sent
  end

  it "skips (idempotent) an anchor that is no longer :sent — no RPC poll" do
    anchor.update_column(:status, EthereumAnchor.statuses[:confirmed])

    described_class.new.perform(anchor.id)

    expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
  end

  it "no-ops when the anchor is not found" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  describe "reorg-depth gate (finality before seal)" do
    before do
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_MIN_CONFIRMATIONS", anything).and_return(64)
    end

    it "confirms when the receipt block is buried deep enough (depth >= min)" do
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"), # 100
        eth_block_number: { "result" => "0xa4" } # 164 → depth 64
      )

      described_class.new.perform(anchor.id)

      expect(anchor.reload).to be_status_confirmed
    end

    it "raises (waits) when confirmation depth is insufficient" do
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"), # 100
        eth_block_number: { "result" => "0x6e" } # 110 → depth 10 < 64
      )

      expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
      expect(anchor.reload).to be_status_sent
    end

    it "raises (retry) when eth_block_number is unavailable — RPC hiccup nil-guard (LOW-2)" do
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"),
        eth_block_number: { "result" => nil }
      )

      expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
      expect(anchor.reload).to be_status_sent
    end

    it "raises (retry) when eth_block_number itself returns nil, not a hash" do
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"),
        eth_block_number: nil
      )

      expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
      expect(anchor.reload).to be_status_sent
    end

    it "raises at depth == 63 — exactly one below the finality floor (boundary)" do
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"), # 100
        eth_block_number: { "result" => "0xa3" } # 163 → depth 63 < 64
      )

      expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
      expect(anchor.reload).to be_status_sent
    end

    it "raises (retry) on a confirmed receipt WITHOUT blockNumber — anomalous, not sealed" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1", block: nil))

      expect { described_class.new.perform(anchor.id) }.to raise_error(/не готовий до seal/)
      expect(anchor.reload).to be_status_sent
    end
  end

  describe "sidekiq_retries_exhausted — FINAL re-check then escalate (ARCH.66 HIGH-1)" do
    let(:msg) { { "args" => [ anchor.id ] } }

    it "escalates to :manual_review ONLY when the receipt is still pending" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_manual_review
    end

    it "CONFIRMS (not escalates) a tx that landed on the final re-check" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_confirmed
    end

    it "FAILS (not escalates) a tx that reverted on the final re-check" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_failed
    end

    it "ESCALATES a confirmed-but-SHALLOW tx — finality not reached by SLA (LOW-A3)" do
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_MIN_CONFIRMATIONS", anything).and_return(64)
      allow(mock_client).to receive_messages(
        eth_get_transaction_receipt: envelope("0x1", block: "0x64"), # 100
        eth_block_number: { "result" => "0x6e" } # depth 10 < 64
      )

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_manual_review
    end

    it "escalates on the final re-check when a confirmed receipt lacks blockNumber (anomalous)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1", block: nil))

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_manual_review
    end

    it "escalates on an RPC failure during the final re-check (INFO-A4 rescue)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_raise(HTTPX::TimeoutError.new(nil, "boom"))

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_manual_review
    end

    it "leaves an already-resolved (non-:sent) anchor untouched — no RPC poll" do
      anchor.update_column(:status, EthereumAnchor.statuses[:confirmed])

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("вичерпано"))

      expect(anchor.reload).to be_status_confirmed
      expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
    end

    it "no-ops when the exhausted anchor is not found (deleted between enqueue and hook)" do
      expect do
        described_class.sidekiq_retries_exhausted_block.call({ "args" => [ -1 ] }, StandardError.new("x"))
      end.not_to raise_error
    end
  end

  describe "lost-race no-op (LOW-4 / LOW-A2 / Sonnet-1)" do
    it "does not log 'sealed' when confirm! is a no-op (another worker already resolved it)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x1"))
      allow_any_instance_of(EthereumAnchor).to receive(:confirm!).and_return(false)

      allow(Rails.logger).to receive(:info)

      described_class.new.perform(anchor.id)

      expect(Rails.logger).not_to have_received(:info).with(/запечатано/)
    end

    it "does NOT increment reverted_total when mark_failed! is a no-op (LOW-A2 double-count guard)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(envelope("0x0"))
      allow_any_instance_of(EthereumAnchor).to receive(:mark_failed!).and_return(false)

      allow(SilkenNet::Metrics::ETHEREUM_ANCHOR_REVERTED_TOTAL).to receive(:increment)

      described_class.new.perform(anchor.id)

      expect(SilkenNet::Metrics::ETHEREUM_ANCHOR_REVERTED_TOTAL).not_to have_received(:increment)
    end

    it "does not log 'вичерпано' when escalate_to_review! is a no-op (Sonnet-1)" do
      allow(mock_client).to receive(:eth_get_transaction_receipt).and_return({ "result" => nil })
      allow_any_instance_of(EthereumAnchor).to receive(:escalate_to_review!).and_return(false)

      allow(Rails.logger).to receive(:warn)

      described_class.sidekiq_retries_exhausted_block.call({ "args" => [ anchor.id ] }, StandardError.new("x"))

      expect(Rails.logger).not_to have_received(:warn).with(/вичерпано/)
    end
  end
end
