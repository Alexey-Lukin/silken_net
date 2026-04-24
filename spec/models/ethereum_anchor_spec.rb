# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchor, type: :model do
  subject(:anchor) do
    described_class.new(
      state_root: "a" * 64,
      total_scc: 1000.0,
      chain_hash: "abc123",
      anchored_at: Time.current
    )
  end

  describe "validations" do
    it "is valid with correct attributes" do
      expect(anchor).to be_valid
    end

    it "requires state_root" do
      anchor.state_root = nil
      expect(anchor).not_to be_valid
      expect(anchor.errors[:state_root]).to include("can't be blank")
    end

    it "requires state_root to be 64-char hex" do
      anchor.state_root = "invalid"
      expect(anchor).not_to be_valid
      expect(anchor.errors[:state_root]).to include("must be a 64-char hex SHA-256")
    end

    it "requires total_scc" do
      anchor.total_scc = nil
      expect(anchor).not_to be_valid
    end

    it "requires chain_hash" do
      anchor.chain_hash = nil
      expect(anchor).not_to be_valid
    end

    it "requires anchored_at" do
      anchor.anchored_at = nil
      expect(anchor).not_to be_valid
    end

    it "validates state_root uniqueness" do
      anchor.save!
      duplicate = described_class.new(
        state_root: anchor.state_root,
        total_scc: 2000.0,
        chain_hash: "def456",
        anchored_at: Time.current
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:state_root]).to include("has already been taken")
    end

    it "validates tx_hash format when present" do
      anchor.tx_hash = "invalid_hash"
      expect(anchor).not_to be_valid
      expect(anchor.errors[:tx_hash]).to include("must be a valid Ethereum tx hash")
    end

    it "accepts valid tx_hash format" do
      anchor.tx_hash = "0x#{"ab" * 32}"
      expect(anchor).to be_valid
    end

    it "requires tx_hash for sent status" do
      anchor.status = :sent
      anchor.tx_hash = nil
      expect(anchor).not_to be_valid
      expect(anchor.errors[:tx_hash]).to include("can't be blank")
    end

    it "requires tx_hash for confirmed status" do
      anchor.status = :confirmed
      anchor.tx_hash = nil
      expect(anchor).not_to be_valid
    end

    it "validates block_number is positive integer" do
      anchor.block_number = -1
      expect(anchor).not_to be_valid
    end

    it "validates gas_used is non-negative" do
      anchor.gas_used = -1
      expect(anchor).not_to be_valid
    end
  end

  describe "enum :status" do
    it "defaults to pending" do
      expect(described_class.new.status).to eq("pending")
    end

    it "supports all statuses" do
      expect(described_class.statuses).to include(
        "pending" => 0, "sent" => 1, "confirmed" => 2, "failed" => 3
      )
    end
  end

  describe "#verify_state_root" do
    it "returns true when state_root matches recomputed hash" do
      freeze_time do
        now = Time.current.utc
        total_scc = BigDecimal("1000.5")
        total_sfc = BigDecimal("0")
        active_tree_count = 0
        chain_hash = "test_chain_hash"
        expected_payload = "#{total_scc}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{now.iso8601}"
        expected_root = Digest::SHA256.hexdigest(expected_payload)

        record = described_class.new(
          state_root: expected_root,
          total_scc: total_scc,
          chain_hash: chain_hash,
          anchored_at: now
        )

        expect(record.verify_state_root).to be true
      end
    end

    it "returns false when state_root does not match" do
      record = described_class.new(
        state_root: "b" * 64,
        total_scc: 1000.0,
        chain_hash: "abc",
        anchored_at: Time.current
      )

      expect(record.verify_state_root).to be false
    end
  end

  describe "#etherscan_url" do
    it "returns nil without tx_hash" do
      expect(anchor.etherscan_url).to be_nil
    end

    it "returns etherscan URL with tx_hash" do
      anchor.tx_hash = "0x#{"ab" * 32}"
      expect(anchor.etherscan_url).to eq("https://etherscan.io/tx/0x#{"ab" * 32}")
    end
  end

  describe "scopes" do
    before do
      described_class.create!(
        state_root: "a" * 64,
        total_scc: 100.0,
        chain_hash: "hash1",
        anchored_at: 2.days.ago,
        status: :confirmed,
        tx_hash: "0x#{"aa" * 32}"
      )
      described_class.create!(
        state_root: "b" * 64,
        total_scc: 200.0,
        chain_hash: "hash2",
        anchored_at: 1.day.ago,
        status: :failed,
        error_message: "timeout"
      )
    end

    it ".successful returns only confirmed anchors" do
      expect(described_class.successful.count).to eq(1)
      expect(described_class.successful.first.state_root).to eq("a" * 64)
    end

    it ".recent orders by created_at desc" do
      expect(described_class.recent.first.state_root).to eq("b" * 64)
    end

    it ".in_flight returns only pending/sent anchors from the last week" do
      pending_anchor = described_class.create!(
        state_root: "c" * 64,
        total_scc: 300.0,
        chain_hash: "hash3",
        anchored_at: 1.hour.ago,
        status: :pending
      )
      sent_anchor = described_class.create!(
        state_root: "d" * 64,
        total_scc: 400.0,
        chain_hash: "hash4",
        anchored_at: 2.hours.ago,
        status: :sent,
        tx_hash: "0x#{"cc" * 32}"
      )

      in_flight = described_class.in_flight
      expect(in_flight).to include(pending_anchor, sent_anchor)
      expect(in_flight).not_to include(described_class.find_by(state_root: "a" * 64))
      expect(in_flight).not_to include(described_class.find_by(state_root: "b" * 64))
    end
  end
end
