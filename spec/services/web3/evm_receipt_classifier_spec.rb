# frozen_string_literal: true

require "rails_helper"

# [ARCH.50] Pure tri-state classifier, shared by MintingRollbackService (Polygon/Celo
# rollback reconcile) and CeloConfirmationWorker. Covered transitively by both, but
# B.2#1 requires a dedicated spec — the envelope/legacy/status matrix lives here directly.
RSpec.describe Web3::EvmReceiptClassifier do
  describe ".classify" do
    context "when the tx is still in the mempool (→ :pending)" do
      it "returns :pending for a nil envelope" do
        expect(described_class.classify(nil)).to eq(:pending)
      end

      it "returns :pending for an empty envelope" do
        expect(described_class.classify({})).to eq(:pending)
      end

      it "returns :pending when the wrapped result is nil (not yet mined)" do
        expect(described_class.classify({ "result" => nil })).to eq(:pending)
      end

      it "returns :pending when the wrapped result is empty" do
        expect(described_class.classify({ "result" => {} })).to eq(:pending)
      end

      it "returns :pending when the receipt has no status field yet" do
        expect(described_class.classify({ "result" => { "blockNumber" => "0x1" } })).to eq(:pending)
      end
    end

    context "when the tx executed successfully (→ :confirmed)" do
      it "recognises the hex status 0x1 in a wrapped JSON-RPC envelope" do
        expect(described_class.classify({ "result" => { "status" => "0x1" } })).to eq(:confirmed)
      end

      it "recognises the zero-padded hex status 0x01" do
        expect(described_class.classify({ "result" => { "status" => "0x01" } })).to eq(:confirmed)
      end

      it "recognises the integer status 1" do
        expect(described_class.classify({ "result" => { "status" => 1 } })).to eq(:confirmed)
      end

      it "accepts a flat (legacy-fixture) receipt without the result wrapper" do
        expect(described_class.classify({ "status" => "0x1" })).to eq(:confirmed)
      end
    end

    context "when the tx reverted on-chain (→ :reverted)" do
      it "returns :reverted for the failure status 0x0 in a wrapped envelope" do
        expect(described_class.classify({ "result" => { "status" => "0x0" } })).to eq(:reverted)
      end

      it "returns :reverted for a flat failure receipt" do
        expect(described_class.classify({ "status" => "0x0" })).to eq(:reverted)
      end

      it "returns :reverted for an unexpected non-success status token" do
        expect(described_class.classify({ "result" => { "status" => "0x2" } })).to eq(:reverted)
      end
    end
  end
end
