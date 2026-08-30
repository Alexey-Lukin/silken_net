# SPDX-License-Identifier: AGPL-3.0-or-later
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
    silence_broadcasts!(:wallet_balance, :tree_map)

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

      it "raises on a mainnet slot when SOLANA_RPC_URL is not set [E.47]" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(solana_public_address: recipient_solana_address)
        ENV.delete("SOLANA_RPC_URL")

        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        expect {
          described_class.new(log).mint_micro_reward!
        }.to raise_error(RuntimeError, /SOLANA_RPC_URL is required on a mainnet slot/)
      ensure
        ENV.delete("SOLANA_RPC_URL")
      end

      # [OPS.37] The discriminating half: RAILS_ENV stays production (canopy runs that way
      # deliberately), and ONLY the chain declaration moves. Without this example the one
      # above stays green against either axis and proves nothing about the split.
      it "does NOT refuse the Devnet fallback on a slot declared testnet, even under RAILS_ENV=production" do
        log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(solana_public_address: recipient_solana_address)
        previous_rpc = ENV.fetch("SOLANA_RPC_URL", nil)
        ENV.delete("SOLANA_RPC_URL")
        ENV["WEB3_CHAIN_ENV"] = "testnet"

        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        expect(described_class.new(log).send(:solana_rpc_urls))
          .to include(Solana::MintingService::DEVNET_RPC_URL)
      ensure
        # RESTORE, never blind-delete: the sibling example above deletes it unconditionally,
        # and that leak is exactly what let an order-dependent failure hide from a local run.
        previous_rpc.nil? ? ENV.delete("SOLANA_RPC_URL") : ENV["SOLANA_RPC_URL"] = previous_rpc
        ENV.delete("WEB3_CHAIN_ENV")
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
        # [ARCH.51] tx_hash = intent-signature (base58, обчислений ДО broadcast), не sendTransaction-стаб.
        expect(tx.tx_hash).to be_present
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

      it "[ARCH.51] returns the deterministic intent-signature (computed before broadcast)" do
        result = described_class.new(log).mint_micro_reward!

        # Per-event тепер sign-first: повертає prepared[:signature] (= tx_hash інтенту), не broadcast-стаб.
        expect(result).to be_present
        expect(result).to eq(BlockchainTransaction.last.tx_hash)
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

    context "when a per-event reward retries [ARCH.51 crash-window idempotency]" do
      let(:log) { create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10) }

      before { wallet.update!(solana_public_address: recipient_solana_address) }

      it "writes a :pending intent BEFORE broadcast (durable crash-marker)" do
        # На момент broadcast intent уже мусить існувати у :pending (sign-first дзеркало batch).
        allow_any_instance_of(described_class).to receive(:broadcast_prepared) do
          tx = BlockchainTransaction.last
          expect(tx.status).to eq("pending")
          expect(tx.blockchain_network).to eq("solana")
          "sig"
        end

        described_class.new(log).mint_micro_reward!
      end

      it "reconciles on retry instead of re-broadcasting (no double-pay)" do
        described_class.new(log).mint_micro_reward!
        expect(BlockchainTransaction.where(blockchain_network: "solana").count).to eq(1)

        # Retry тієї ж телеметрії: unsettled intent існує → reconcile (signature_status), НЕ другий broadcast.
        allow_any_instance_of(described_class).to receive(:signature_status).and_return(:confirmed)
        expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

        described_class.new(log).mint_micro_reward!
        expect(BlockchainTransaction.where(blockchain_network: "solana").count).to eq(1)
      end

      it "confirms a :pending intent stranded by a pre-mark_as_sent crash (review-fix: no stuck :pending → no eventual double-pay)" do
        # Крах ПІСЛЯ broadcast, ДО mark_as_sent! → intent лишився :pending. reconcile :confirmed
        # МУСИТЬ спершу mark_as_sent!, інакше confirm! (з [:sent,:processing]) пропуститься → stuck.
        intent = wallet.blockchain_transactions.create!(
          amount: 0.015, token_type: :carbon_coin, status: :pending, blockchain_network: "solana",
          to_address: recipient_solana_address, tx_hash: "stuck-sig",
          chainlink_request_id: log.chainlink_request_id
        )

        allow_any_instance_of(described_class).to receive(:signature_status).and_return(:confirmed)
        expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

        described_class.new(log).mint_micro_reward!

        expect(intent.reload.status).to eq("confirmed") # mark_as_sent!→confirm!, не застрягло :pending
        expect(BlockchainTransaction.where(blockchain_network: "solana").count).to eq(1)
      end

      it "escalates to manual_review on :not_found (possible RPC lag — no blind re-pay)" do
        described_class.new(log).mint_micro_reward!
        tx = BlockchainTransaction.last

        allow_any_instance_of(described_class).to receive(:signature_status).and_return(:not_found)
        expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

        described_class.new(log).mint_micro_reward!
        expect(tx.reload.status).to eq("manual_review")
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
        # [ARCH.51] intent-signature (sign-first), не sendTransaction-стаб; dest-ATA резолюція ще тестується через getTokenAccountsByOwner-стаб у prepare_transfer.
        expect(result).to be_present
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

  describe "RPC nil-response + oracle-balance guards" do
    let(:service) { described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree)) }

    it "raises when getLatestBlockhash returns a nil response body" do
      allow(service).to receive(:execute_rpc_call).and_return(nil)
      expect { service.send(:fetch_latest_blockhash) }
        .to raise_error(RuntimeError, /Failed to fetch blockhash/)
    end

    it "raises when getTokenAccountsByOwner returns a nil response body" do
      allow(service).to receive(:execute_rpc_call).and_return(nil)
      expect { service.send(:resolve_dest_token_account, "owner", "mint") }
        .to raise_error(RuntimeError, /No USDC token account found/)
    end

    it "raises an unknown-error when sendTransaction returns a nil response body" do
      allow(service).to receive(:execute_rpc_call).and_return(nil)
      expect { service.send(:broadcast_signed_transaction, "sig", "msg") }
        .to raise_error(RuntimeError, /Unknown Solana RPC error/)
    end

    it "treats a nil getBalance response as zero and raises low-balance" do
      allow(service).to receive(:execute_rpc_call).and_return(nil)
      expect { service.send(:verify_oracle_balance!, "pubkey") }
        .to raise_error(RuntimeError, /низький баланс/)
    end

    it "raises when the oracle balance is below the configured minimum" do
      allow(service).to receive(:execute_rpc_call).and_return({ "result" => { "value" => 1_000 } })
      expect { service.send(:verify_oracle_balance!, "pubkey") }
        .to raise_error(RuntimeError, /низький баланс/)
    end
  end

  describe "batch mode [E.61]" do
    let(:log) do
      create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 50)
    end

    before do
      wallet.update!(solana_public_address: recipient_solana_address)
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current)
        .with(:solana_batch_threshold_usdc, default: 0).and_return(0.10)
    end

    it "accumulates the reward in Kredis instead of sending a transaction" do
      expect {
        result = described_class.new(log).mint_micro_reward!
        expect(result).to be_nil
      }.not_to change(BlockchainTransaction, :count)

      expect(Web3::HttpClient).not_to have_received(:post)
    end

    it "stores the reward lamports, event count and wallet in the pending Kredis keys" do
      described_class.new(log).mint_micro_reward!

      # growth_points 50 → 10_000 base + 50×100 bonus
      expect(Kredis.counter("solana_pending_payouts:#{wallet.id}").value.to_i).to eq(15_000)
      expect(Kredis.counter("solana_pending_payout_count:#{wallet.id}").value.to_i).to eq(1)
      expect(Kredis.set(described_class::PENDING_PAYOUT_WALLETS_KEY).members).to include(wallet.id.to_s)
    end

    it "accumulates across multiple events" do
      2.times { described_class.new(log).mint_micro_reward! }

      expect(Kredis.counter("solana_pending_payouts:#{wallet.id}").value.to_i).to eq(30_000)
      expect(Kredis.counter("solana_pending_payout_count:#{wallet.id}").value.to_i).to eq(2)
    end

    it "falls back to per-event payout when threshold is zero (backward-compat)" do
      allow(SystemParameter).to receive(:current)
        .with(:solana_batch_threshold_usdc, default: 0).and_return(0)

      expect {
        described_class.new(log).mint_micro_reward!
      }.to change(BlockchainTransaction, :count).by(1)
    end
  end

  describe "#batch_payout! [E.61]" do
    before { wallet.update!(solana_public_address: recipient_solana_address) }

    it "sends one TransferChecked and records an aggregated audit transaction" do
      result = nil
      expect {
        result = described_class.new(nil, wallet: wallet).batch_payout!(25_000, 3)
      }.to change(BlockchainTransaction, :count).by(1)

      tx = BlockchainTransaction.last
      expect(tx.blockchain_network).to eq("solana")
      expect(tx.amount).to eq(0.025)
      expect(tx.to_address).to eq(recipient_solana_address)
      expect(tx.status).to eq("sent")
      expect(tx.notes).to include("batch", "3 подій")
      # [ARCH.45] batch_payout! повертає intent-marker tx (не signature-рядок) для in-flight звірки.
      expect(result).to be_a(BlockchainTransaction)
      expect(result.tx_hash).to be_present
    end

    it "raises without a wallet" do
      expect { described_class.new(nil).batch_payout!(10_000, 1) }
        .to raise_error(RuntimeError, /потребує wallet/)
    end

    it "returns nil for a zero amount" do
      expect(described_class.new(nil, wallet: wallet).batch_payout!(0, 0)).to be_nil
    end
  end

  describe "#build_spl_transfer_checked_message [E.61]" do
    let(:service) { described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree)) }

    it "serializes a TransferChecked instruction (golden-vector structure)" do
      message = service.send(:build_spl_transfer_checked_message,
        fee_payer: fee_payer_pubkey,
        source_token_account: fee_payer_token_account,
        dest_token_account: dest_token_account,
        usdc_mint: usdc_mint_address,
        recent_blockhash: "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N",
        amount_lamports: 20_000
      )

      expect(message.encoding).to eq(Encoding::BINARY)
      # Header: 1 signer, 0 readonly-signed, 2 readonly-unsigned (mint + token program)
      expect(message.bytes[0..2]).to eq([ 1, 0, 2 ])
      # num_accounts = 5: fee_payer, source, dest, mint, token program
      expect(message.bytes[3]).to eq(5)

      # Instruction begins after header(3) + count(1) + 5×32 keys + blockhash(32) + num_ix(1)
      ix = 3 + 1 + (5 * 32) + 32 + 1
      expect(message.bytes[ix]).to eq(4)                  # program_id_index → SPL Token Program
      expect(message.bytes[ix + 2, 4]).to eq([ 1, 3, 2, 0 ]) # source, mint, dest, authority
      expect(message.bytes[ix + 7]).to eq(12)             # TransferChecked instruction index
      expect(message.bytes[ix + 16]).to eq(6)             # USDC decimals
    end
  end

  # [ARCH.45] signature_status — on-chain reconcile primitive, що вирішує чи безпечно
  # re-pay-ити. Reconcile-тести вище СТАБЛЯТЬ його; тут — прямий unit по кожній гілці
  # getSignatureStatuses, бо саме він визначає double-pay-безпеку.
  describe "#signature_status" do
    let(:service) { described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree)) }

    it "returns :confirmed for a finalized signature" do
      allow(service).to receive(:execute_rpc_call)
        .and_return({ "result" => { "value" => [ { "confirmationStatus" => "finalized", "err" => nil } ] } })
      expect(service.signature_status("sig")).to eq(:confirmed)
    end

    it "returns :processing for a not-yet-finalized signature" do
      allow(service).to receive(:execute_rpc_call)
        .and_return({ "result" => { "value" => [ { "confirmationStatus" => "processed", "err" => nil } ] } })
      expect(service.signature_status("sig")).to eq(:processing)
    end

    it "returns :not_found when the signature is absent (nil status entry)" do
      allow(service).to receive(:execute_rpc_call)
        .and_return({ "result" => { "value" => [ nil ] } })
      expect(service.signature_status("sig")).to eq(:not_found)
    end

    # [ARCH.45 money-safety] Виконано on-chain, але З помилкою → кошти НЕ пішли → безпечно re-pay.
    it "returns :not_found when the tx executed on-chain WITH an error (safe re-pay)" do
      allow(service).to receive(:execute_rpc_call)
        .and_return({ "result" => { "value" => [ { "confirmationStatus" => "finalized", "err" => { "InstructionError" => [ 0, "Custom" ] } } ] } })
      expect(service.signature_status("sig")).to eq(:not_found)
    end

    it "returns :not_found when the RPC envelope is nil (total RPC failure short-circuits the dig)" do
      allow(service).to receive(:execute_rpc_call).and_return(nil)
      expect(service.signature_status("sig")).to eq(:not_found)
    end
  end

  # [INF.22] RPC fallback cascade — Solana не-EVM, тож каскад живе в execute_rpc_call
  # (не Web3::ResilientClient). Primary SOLANA_RPC_URL → SOLANA_RPC_URL_FALLBACK_* по черзі.
  describe "#execute_rpc_call RPC fallback cascade [INF.22]" do
    let(:service) { described_class.new(create(:telemetry_log, :verified_telemetry, tree: tree)) }
    let(:payload) { { jsonrpc: "2.0", id: "x", method: "getBalance", params: [] } }

    it "falls back to SOLANA_RPC_URL_FALLBACK_1 when the primary endpoint raises" do
      ENV["SOLANA_RPC_URL"] = "https://primary.example"
      ENV["SOLANA_RPC_URL_FALLBACK_1"] = "https://fallback1.example"

      allow(Web3::HttpClient).to receive(:post) do |url, **_kwargs|
        raise Web3::HttpClient::RequestError, "primary down" if url == "https://primary.example"

        Web3::HttpClient::Response.new({ "result" => "ok" }.to_json)
      end

      expect(service.send(:execute_rpc_call, payload)).to eq({ "result" => "ok" })
      expect(Web3::HttpClient).to have_received(:post).with("https://primary.example", any_args)
      expect(Web3::HttpClient).to have_received(:post).with("https://fallback1.example", any_args)
    ensure
      ENV.delete("SOLANA_RPC_URL")
      ENV.delete("SOLANA_RPC_URL_FALLBACK_1")
    end

    it "raises the last error when every endpoint in the cascade fails" do
      ENV["SOLANA_RPC_URL"] = "https://primary.example"
      ENV["SOLANA_RPC_URL_FALLBACK_1"] = "https://fallback1.example"

      allow(Web3::HttpClient).to receive(:post).and_raise(Web3::HttpClient::RequestError, "all down")

      expect { service.send(:execute_rpc_call, payload) }
        .to raise_error(Web3::HttpClient::RequestError, /all down/)
    ensure
      ENV.delete("SOLANA_RPC_URL")
      ENV.delete("SOLANA_RPC_URL_FALLBACK_1")
    end

    it "skip-clean: without any fallback ENV, uses exactly one endpoint" do
      ENV["SOLANA_RPC_URL"] = "https://primary.example"
      allow(Web3::HttpClient).to receive(:post)
        .and_return(Web3::HttpClient::Response.new({ "result" => "ok" }.to_json))

      service.send(:execute_rpc_call, payload)

      expect(Web3::HttpClient).to have_received(:post).once
    ensure
      ENV.delete("SOLANA_RPC_URL")
    end
  end

  describe "#mint_micro_reward! reconcile edge states [ARCH.51]" do
    let(:log) { create(:telemetry_log, :verified_telemetry, tree: tree, growth_points: 10) }

    before { wallet.update!(solana_public_address: recipient_solana_address) }

    it "leaves an in-flight intent untouched when the signature is still :processing" do
      described_class.new(log).mint_micro_reward!
      tx = BlockchainTransaction.last

      allow_any_instance_of(described_class).to receive(:signature_status).and_return(:processing)
      expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

      described_class.new(log).mint_micro_reward!
      expect(tx.reload.status).to eq("sent") # ще в польоті — стан не чіпаємо, без re-pay
    end

    # [ARCH.51] Auto-heal: manual_review-intent, що ВСЕ Ж landed on-chain. confirm! пропускається
    # (may_confirm? false на manual_review), але re-pay теж НЕ відбувається — жодного thrash.
    it "does not thrash a manual_review intent that later confirms on-chain (may_confirm? false)" do
      described_class.new(log).mint_micro_reward!
      tx = BlockchainTransaction.last
      tx.escalate_to_review!("prior RPC lag")

      allow_any_instance_of(described_class).to receive(:signature_status).and_return(:confirmed)
      expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

      described_class.new(log).mint_micro_reward!
      expect(tx.reload.status).to eq("manual_review")
    end

    # [ARCH.51] Повторний :not_found на вже-manual_review intent → escalate пропускається
    # (may_escalate_to_review? false), без re-pay — double-spend guard тримається.
    it "keeps a manual_review intent stable on a repeated :not_found (may_escalate? false)" do
      described_class.new(log).mint_micro_reward!
      tx = BlockchainTransaction.last
      tx.escalate_to_review!("prior lag")

      allow_any_instance_of(described_class).to receive(:signature_status).and_return(:not_found)
      expect_any_instance_of(described_class).not_to receive(:broadcast_prepared)

      described_class.new(log).mint_micro_reward!
      expect(tx.reload.status).to eq("manual_review")
    end

    it "unsettled_event_tx returns nil without a chainlink_request_id (no dedup key)" do
      # @telemetry_log nil (batch-конструктор) → `&.chainlink_request_id` blank → guard повертає nil.
      service = described_class.new(nil, wallet: wallet)
      expect(service.send(:unsettled_event_tx)).to be_nil
    end
  end

  describe "#batch_payout! missing address [E.61]" do
    it "raises when the wallet has no Solana address for a batch payout" do
      wallet.update!(solana_public_address: nil)
      allow(wallet).to receive(:organization).and_return(nil)

      expect { described_class.new(nil, wallet: wallet).batch_payout!(25_000, 2) }
        .to raise_error(RuntimeError, /Missing Solana address for batch payout/)
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
