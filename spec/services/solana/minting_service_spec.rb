# frozen_string_literal: true

require "rails_helper"

RSpec.describe Solana::MintingService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  # Valid Ed25519 seed (32 bytes hex = 64 hex chars)
  let(:valid_keypair_hex) { "a" * 64 }
  # Valid Base58 Solana addresses for ENV configuration
  let(:fee_payer_pubkey) { "SiLkEnFeEpAyEr11111111111111111111111111111" }
  let(:fee_payer_token_account) { "SiLkEnSoUrCeAtA1111111111111111111111111111" }
  let(:usdc_mint_address) { "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU" }
  let(:recipient_solana_address) { "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV" }
  let(:dest_token_account) { "DeSt1nAt1oNaTa111111111111111111111111111111" }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)

    # Configure mandatory ENV variables for production transaction flow
    ENV["SOLANA_WALLET_KEYPAIR"] = valid_keypair_hex
    ENV["SOLANA_FEE_PAYER_PUBKEY"] = fee_payer_pubkey
    ENV["SOLANA_FEE_PAYER_TOKEN_ACCOUNT"] = fee_payer_token_account
    ENV["SOLANA_USDC_MINT_ADDRESS"] = usdc_mint_address
    ENV["SOLANA_DEST_TOKEN_ACCOUNT"] = dest_token_account

    # Stub Ed25519 signing to return deterministic 64-byte hex signature
    allow(Ed25519Crypto::SigningService).to receive(:sign).and_return("ab" * 64)

    # Stub Web3::HttpClient calls to Solana RPC
    stub_solana_rpc_success
  end

  after do
    ENV.delete("SOLANA_WALLET_KEYPAIR")
    ENV.delete("SOLANA_FEE_PAYER_PUBKEY")
    ENV.delete("SOLANA_FEE_PAYER_TOKEN_ACCOUNT")
    ENV.delete("SOLANA_USDC_MINT_ADDRESS")
    ENV.delete("SOLANA_DEST_TOKEN_ACCOUNT")
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

      it "raises in production when SOLANA_RPC_URL is not set [E.47]" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        ENV.delete("SOLANA_RPC_URL")

        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /SOLANA_RPC_URL is required in production/)
      ensure
        ENV.delete("SOLANA_RPC_URL")
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
        wallet.update!(solana_public_address: recipient_solana_address)
      end

      it "creates a blockchain_transaction with solana network and sent status" do
        expect {
          described_class.new(log).mint_micro_reward!
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.blockchain_network).to eq("solana")
        expect(tx.to_address).to eq(recipient_solana_address)
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq("5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE")
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

      it "returns the real transaction signature from sendTransaction" do
        result = described_class.new(log).mint_micro_reward!

        expect(result).to eq("5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE")
      end

      it "includes growth_points in transaction notes" do
        described_class.new(log).mint_micro_reward!

        tx = BlockchainTransaction.last
        expect(tx.notes).to include("growth_points: 50")
        expect(tx.notes).to include("Solana micro-reward")
      end

      it "calls getLatestBlockhash before sendTransaction" do
        rpc_calls = []
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          method = kwargs[:body][:method]
          rpc_calls << method
          case method
          when "getBalance"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
            )
          when "getLatestBlockhash"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
            )
          when "sendTransaction"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => "5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE" }.to_json
            )
          end
        end

        described_class.new(log).mint_micro_reward!

        expect(rpc_calls).to eq(%w[getBalance getLatestBlockhash sendTransaction])
      end

      it "signs the transaction message with Ed25519" do
        described_class.new(log).mint_micro_reward!

        expect(Ed25519Crypto::SigningService).to have_received(:sign).with(
          valid_keypair_hex,
          instance_of(String)
        )
      end
    end

    context "when growth_points is zero" do
      it "returns nil and does not create a transaction" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 0)
        wallet.update!(solana_public_address: recipient_solana_address)

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

    context "when SOLANA_WALLET_KEYPAIR is not set" do
      before { ENV.delete("SOLANA_WALLET_KEYPAIR") }

      it "raises an error requiring the keypair" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /SOLANA_WALLET_KEYPAIR is required/)
      end
    end

    context "when SOLANA_FEE_PAYER_PUBKEY is not set" do
      before { ENV.delete("SOLANA_FEE_PAYER_PUBKEY") }

      it "raises an error requiring the fee payer" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /SOLANA_FEE_PAYER_PUBKEY is required/)
      end
    end

    context "when SOLANA_FEE_PAYER_TOKEN_ACCOUNT is not set" do
      before { ENV.delete("SOLANA_FEE_PAYER_TOKEN_ACCOUNT") }

      it "raises an error requiring the source token account" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /SOLANA_FEE_PAYER_TOKEN_ACCOUNT is required/)
      end
    end

    context "when Solana RPC fails on sendTransaction" do
      it "raises an error on RPC failure" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        stub_solana_rpc_send_error

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Error/)
      end
    end

    context "when Solana RPC fails on getLatestBlockhash" do
      it "raises an error about failed blockhash fetch" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        stub_solana_rpc_blockhash_error

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Failed to fetch blockhash/)
      end
    end

    context "when Solana RPC times out" do
      it "raises a timeout error on Net::ReadTimeout" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Solana Timeout: execution expired"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(Web3::HttpClient::RequestError, /Solana Timeout/)
      end

      it "raises a timeout error on Net::OpenTimeout" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Solana Timeout: connection timeout"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(Web3::HttpClient::RequestError, /Solana Timeout/)
      end
    end

    context "when Solana RPC returns invalid JSON" do
      it "raises a parse error" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        response = Web3::HttpClient::Response.new("not json")
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(Web3::HttpClient::RequestError, /Invalid JSON response/)
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

    context "when wallet.organization is nil" do
      it "raises missing address when wallet has no solana address and no org" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: nil)
        allow(wallet).to receive(:organization).and_return(nil)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Missing Solana address/)
      end
    end

    context "when Solana RPC returns nil response for sendTransaction" do
      it "raises error with default message" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          method = kwargs[:body][:method]
          case method
          when "getBalance"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
            )
          when "getLatestBlockhash"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
            )
          when "sendTransaction"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0" }.to_json
            )
          end
        end

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Solana RPC Error: Unknown Solana RPC error/)
      end
    end

    context "when record_transaction! wallet is nil" do
      it "does not create a transaction when wallet returns nil" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        service = described_class.new(log)
        allow(tree).to receive(:wallet).and_return(nil)

        result = service.send(:record_transaction!, "recipient", 10_000, "sig")
        expect(result).to be_nil
      end
    end

    context "when SOLANA_WALLET_KEYPAIR is invalid" do
      it "raises an error on Ed25519 signing failure" do
        allow(Ed25519Crypto::SigningService).to receive(:sign).and_raise(
          Ed25519Crypto::SigningService::SigningError, "invalid key"
        )

        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /Invalid SOLANA_WALLET_KEYPAIR/)
      end
    end

    context "when SOLANA_DEST_TOKEN_ACCOUNT is not set" do
      before { ENV.delete("SOLANA_DEST_TOKEN_ACCOUNT") }

      it "resolves destination token account via RPC lookup" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          method = kwargs[:body][:method]
          case method
          when "getBalance"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
            )
          when "getLatestBlockhash"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
            )
          when "getTokenAccountsByOwner"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => [ { "pubkey" => "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM" } ] } }.to_json
            )
          when "sendTransaction"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => "5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE" }.to_json
            )
          end
        end

        result = described_class.new(log).mint_micro_reward!
        expect(result).to eq("5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE")
      end

      it "raises error when recipient has no USDC token account" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10)
        wallet.update!(solana_public_address: recipient_solana_address)

        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          method = kwargs[:body][:method]
          case method
          when "getBalance"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
            )
          when "getLatestBlockhash"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
            )
          when "getTokenAccountsByOwner"
            Web3::HttpClient::Response.new(
              { "jsonrpc" => "2.0", "result" => { "value" => [] } }.to_json
            )
          end
        end

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /No USDC token account found/)
      end
    end
  end

  describe "binary serialization" do
    let(:service) { described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree)) }

    describe "#decode_base58" do
      it "decodes a valid Base58 Solana address to 32 bytes" do
        result = service.send(:decode_base58, "11111111111111111111111111111111")
        expect(result.bytesize).to eq(32)
        expect(result.bytes).to all(eq(0))
      end

      it "raises on invalid Base58 character" do
        expect {
          service.send(:decode_base58, "0InvalidBase58")
        }.to raise_error(RuntimeError, /Invalid Base58 character/)
      end
    end

    describe "#encode_compact_u16" do
      it "encodes single-byte values (0..127)" do
        result = service.send(:encode_compact_u16, 5)
        expect(result.bytes).to eq([ 5 ])
      end

      it "encodes two-byte values (128..16383)" do
        result = service.send(:encode_compact_u16, 128)
        expect(result.bytesize).to eq(2)
      end

      it "encodes three-byte values (16384..65535)" do
        result = service.send(:encode_compact_u16, 16384)
        expect(result.bytesize).to eq(3)
      end

      it "raises on out of range value" do
        expect {
          service.send(:encode_compact_u16, 0x10000)
        }.to raise_error(ArgumentError, /out of range/)
      end
    end

    describe "#build_spl_transfer_message" do
      it "builds a binary message with correct structure" do
        message = service.send(:build_spl_transfer_message,
          fee_payer: fee_payer_pubkey,
          source_token_account: fee_payer_token_account,
          dest_token_account: dest_token_account,
          recent_blockhash: "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N",
          amount_lamports: 10_000
        )

        expect(message).to be_a(String)
        expect(message.encoding).to eq(Encoding::BINARY)

        # Verify header: 1 required signature, 0 readonly signed, 1 readonly unsigned
        expect(message.bytes[0..2]).to eq([ 1, 0, 1 ])

        # Verify num_accounts (compact-u16 of 4)
        expect(message.bytes[3]).to eq(4)
      end
    end
  end

  private

  def stub_solana_rpc_success
    allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
      method = kwargs[:body][:method]
      case method
      when "getLatestBlockhash"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
        )
      when "sendTransaction"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => "5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE" }.to_json
        )
      when "getBalance"
        # [BLOCKER-1 FIX]: Return sufficient balance (1 SOL = 1_000_000_000 lamports)
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
        )
      else
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => {} }.to_json
        )
      end
    end
  end

  def stub_solana_rpc_send_error
    allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
      method = kwargs[:body][:method]
      case method
      when "getLatestBlockhash"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json
        )
      when "sendTransaction"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "error" => { "code" => -32002, "message" => "Transaction simulation failed" } }.to_json
        )
      when "getBalance"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
        )
      end
    end
  end

  def stub_solana_rpc_blockhash_error
    allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
      method = kwargs[:body][:method]
      case method
      when "getLatestBlockhash"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => {} }.to_json
        )
      when "getBalance"
        Web3::HttpClient::Response.new(
          { "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json
        )
      end
    end
  end

  describe "#decode_base58_to_bytes (oversized address)" do
    it "raises error when decoded address exceeds 32 bytes" do
      service = described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree))
      oversized_address = "z" * 60

      expect {
        service.send(:decode_base58, oversized_address)
      }.to raise_error(RuntimeError, /Invalid address.*expected ≤ 32/)
    end
  end
end
