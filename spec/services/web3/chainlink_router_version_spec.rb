# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::ChainlinkRouterVersion do
  describe ".active_version" do
    it "defaults to :v1 when CHAINLINK_ROUTER_VERSION is unset" do
      stub_const("ENV", ENV.to_h.except("CHAINLINK_ROUTER_VERSION"))
      expect(described_class.active_version).to eq(:v1)
    end

    it "respects an explicit CHAINLINK_ROUTER_VERSION ENV value" do
      stub_const("ENV", ENV.to_h.merge("CHAINLINK_ROUTER_VERSION" => "v1"))
      expect(described_class.active_version).to eq(:v1)
    end

    it "treats blank ENV value as default" do
      stub_const("ENV", ENV.to_h.merge("CHAINLINK_ROUTER_VERSION" => "  "))
      expect(described_class.active_version).to eq(:v1)
    end

    it "raises UnsupportedVersionError for unknown versions" do
      stub_const("ENV", ENV.to_h.merge("CHAINLINK_ROUTER_VERSION" => "v99"))
      expect {
        described_class.active_version
      }.to raise_error(described_class::UnsupportedVersionError, /v99/)
    end
  end

  describe ".abi_for" do
    it "returns a JSON-serialisable ABI array for v1" do
      abi = described_class.abi_for(:v1)
      expect(abi).to be_an(Array)
      expect(abi.first["name"]).to eq("sendRequest")
      expect(abi.first["inputs"].size).to eq(5)
      expect(abi.first["inputs"].map { |i| i["name"] }).to contain_exactly(
        "subscriptionId", "data", "dataVersion", "callbackGasLimit", "donId"
      )
      expect(abi.to_json).to be_a(String)
    end

    it "raises UnsupportedVersionError for unregistered versions" do
      expect {
        described_class.abi_for(:v42)
      }.to raise_error(described_class::UnsupportedVersionError)
    end
  end

  describe ".selector_for" do
    it "exposes the keccak256 selector for sendRequest v1" do
      # Expected selector = first 4 bytes of keccak256(canonical_signature)
      # for `sendRequest(uint64,bytes,uint16,uint32,bytes32)`. Pinned in the
      # registry — recompute with `Eth::Util.keccak256(...)` if the
      # signature ever changes.
      expect(described_class.selector_for(:v1)).to eq("0x461d2762")
    end
  end

  describe ".signature_for" do
    it "returns the canonical Solidity signature for v1" do
      expect(described_class.signature_for(:v1))
        .to eq("sendRequest(uint64,bytes,uint16,uint32,bytes32)")
    end
  end

  describe ".fallback_for" do
    it "returns nil when the version is the oldest registered" do
      expect(described_class.fallback_for(:v1)).to be_nil
    end

    it "returns nil for an unregistered version" do
      expect(described_class.fallback_for(:v_unknown)).to be_nil
    end
  end

  describe ".selector_present_in_code?" do
    let(:selector) { described_class.selector_for(:v1).delete_prefix("0x") }

    it "returns true when the selector substring appears in the bytecode" do
      code = "0x60806040526004361061004a5760003560e01c8063#{selector}1461004f5760405162461bcd60e51b"
      expect(described_class.selector_present_in_code?(code, :v1)).to be(true)
    end

    it "is case-insensitive" do
      code = "0x60806040526004361061004a5760003560e01c8063#{selector.upcase}1461004f"
      expect(described_class.selector_present_in_code?(code, :v1)).to be(true)
    end

    it "returns false when the selector is absent" do
      code = "0x60806040526004361061004a5760003560e01c8063deadbeef1461004f"
      expect(described_class.selector_present_in_code?(code, :v1)).to be(false)
    end

    it "returns false for blank or nil bytecode" do
      expect(described_class.selector_present_in_code?(nil, :v1)).to be(false)
      expect(described_class.selector_present_in_code?("", :v1)).to be(false)
      expect(described_class.selector_present_in_code?("0x", :v1)).to be(false)
    end
  end

  describe ".supported?" do
    it "returns true for registered versions" do
      expect(described_class.supported?(:v1)).to be(true)
    end

    it "returns false for unregistered versions" do
      expect(described_class.supported?(:v999)).to be(false)
    end
  end
end
