# frozen_string_literal: true

require "rails_helper"

RSpec.describe Solana::MintingService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)

    # Stub HTTP calls to Solana RPC
    stub_solana_rpc_success
  end

  describe "#mint_micro_reward!" do
    context "when validating trustless guard clauses" do
      it "raises when telemetry_log is not verified by IoTeX" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: false, oracle_status: "fulfilled")

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Data not verified by IoTeX/)
      end

      it "raises when Chainlink Oracle consensus is not fulfilled" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: true, oracle_status: "dispatched")

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
      end

      it "raises when oracle_status is pending" do
        log = create(:telemetry_log, tree: tree, verified_by_iotex: true, oracle_status: "pending")

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Chainlink Oracle consensus not fulfilled/)
      end
    end

    context "with fully verified telemetry" do
      let(:log) do
        create(:telemetry_log, :verified_telemetry,
          tree: tree,
          growth_points: 50
        )
      end

      before do
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")
      end

      it "creates a blockchain_transaction with solana network" do
        expect {
          described_class.new(log).mint_micro_reward!
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.blockchain_network).to eq("solana")
        expect(tx.to_address).to eq("7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")
        expect(tx.status).to eq("confirmed")
        expect(tx.tx_hash).to start_with("solana:sim:")
      end

      it "stores chainlink_request_id and zk_proof_ref for audit" do
        described_class.new(log).mint_micro_reward!

        tx = BlockchainTransaction.last
        expect(tx.chainlink_request_id).to eq(log.chainlink_request_id)
        expect(tx.zk_proof_ref).to eq(log.zk_proof_ref)
      end

      it "calculates reward based on growth_points" do
        described_class.new(log).mint_micro_reward!

        tx = BlockchainTransaction.last
        # base (10_000) + bonus (50 * 100 = 5_000) = 15_000 lamports = 0.015 USDC
        expect(tx.amount).to eq(0.015)
      end

      it "returns the transaction signature" do
        result = described_class.new(log).mint_micro_reward!

        expect(result).to start_with("solana:sim:")
      end

      it "includes growth_points in transaction notes" do
        described_class.new(log).mint_micro_reward!

        tx = BlockchainTransaction.last
        expect(tx.notes).to include("growth_points: 50")
        expect(tx.notes).to include("Solana micro-reward")
      end
    end

    context "when growth_points is zero" do
      it "returns nil and does not create a transaction" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 0)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        expect {
          result = described_class.new(log).mint_micro_reward!
          expect(result).to be_nil
        }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "when no Solana address is configured" do
      it "raises an error about missing address" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: nil)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Missing Solana address/)
      end
    end

    context "when wallet uses organization Solana address as fallback" do
      it "uses organization solana_public_address" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: nil)
        organization.update!(solana_public_address: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")

        described_class.new(log).mint_micro_reward!

        tx = BlockchainTransaction.last
        expect(tx.to_address).to eq("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
      end
    end

    context "when Solana RPC fails" do
      it "raises an error on RPC failure" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        stub_solana_rpc_error

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Error/)
      end
    end

    context "when Solana RPC times out" do
      it "raises a timeout error on Net::ReadTimeout" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        allow_any_instance_of(Net::HTTP).to receive(:request)
          .and_raise(Net::ReadTimeout.new("execution expired"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Timeout/)
      end

      it "raises a timeout error on Net::OpenTimeout" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        allow_any_instance_of(Net::HTTP).to receive(:request)
          .and_raise(Net::OpenTimeout.new("connection timeout"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Timeout/)
      end
    end

    context "when Solana RPC returns invalid JSON" do
      it "raises a parse error" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        mock_response = instance_double(Net::HTTPResponse, body: "not json")
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Parse Error/)
      end
    end

    context "when wallet is nil (tree has no wallet)" do
      it "returns nil from resolve_recipient_address and raises" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        allow(tree).to receive(:wallet).and_return(nil)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Missing Solana address/)
      end
    end

    context "when record_transaction! wallet is nil" do
      it "does not create a transaction when wallet returns nil" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

        service = described_class.new(log)
        allow(tree).to receive(:wallet).and_return(nil)

        # Test the private method directly
        result = service.send(:record_transaction!, "recipient", 10_000, "sig")
        expect(result).to be_nil
      end
    end
  end

  private

  def stub_solana_rpc_success
    mock_response = instance_double(Net::HTTPResponse,
      body: { "jsonrpc" => "2.0", "result" => { "value" => { "err" => nil } } }.to_json
    )

    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
  end

  def stub_solana_rpc_error
    mock_response = instance_double(Net::HTTPResponse,
      body: { "jsonrpc" => "2.0", "error" => { "code" => -32002, "message" => "Transaction simulation failed" } }.to_json
    )

    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
  end
end
