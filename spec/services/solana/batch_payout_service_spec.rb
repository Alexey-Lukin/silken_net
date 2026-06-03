# frozen_string_literal: true

require "rails_helper"

RSpec.describe Solana::BatchPayoutService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }
  let(:recipient_solana_address) { "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV" }
  let(:pending_key) { Solana::MintingService::PENDING_PAYOUT_WALLETS_KEY }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)

    ENV["SOLANA_WALLET_KEYPAIR"] = "a" * 64
    ENV["SOLANA_FEE_PAYER_PUBKEY"] = "SiLkEnFeEpAyEr11111111111111111111111111111"
    ENV["SOLANA_FEE_PAYER_TOKEN_ACCOUNT"] = "SiLkEnSoUrCeAtA1111111111111111111111111111"
    ENV["SOLANA_USDC_MINT_ADDRESS"] = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"
    ENV["SOLANA_DEST_TOKEN_ACCOUNT"] = "DeSt1nAt1oNaTa111111111111111111111111111111"

    allow(Ed25519Crypto::SigningService).to receive(:sign).and_return("ab" * 64)
    stub_solana_rpc_success

    wallet.update!(solana_public_address: recipient_solana_address)

    # Поріг = 0.02 USDC (20_000 lamports), governance-aware.
    allow(SystemParameter).to receive(:current).and_call_original
    allow(SystemParameter).to receive(:current)
      .with(:solana_batch_threshold_usdc, default: 0).and_return(0.02)
  end

  after do
    %w[SOLANA_WALLET_KEYPAIR SOLANA_FEE_PAYER_PUBKEY SOLANA_FEE_PAYER_TOKEN_ACCOUNT
       SOLANA_USDC_MINT_ADDRESS SOLANA_DEST_TOKEN_ACCOUNT].each { |k| ENV.delete(k) }
  end

  def seed_pending(wallet_id, lamports, events)
    Kredis.counter("solana_pending_payouts:#{wallet_id}").increment(by: lamports)
    Kredis.counter("solana_pending_payout_count:#{wallet_id}").increment(by: events)
    Kredis.set(pending_key).add(wallet_id.to_s)
  end

  describe ".call" do
    context "when a wallet's pending crossed the threshold" do
      before { seed_pending(wallet.id, 25_000, 2) }

      it "pays out via one transaction and drains the Kredis keys" do
        expect { described_class.call }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.blockchain_network).to eq("solana")
        expect(tx.amount).to eq(0.025)
        expect(tx.to_address).to eq(recipient_solana_address)

        expect(Kredis.counter("solana_pending_payouts:#{wallet.id}").value.to_i).to eq(0)
        expect(Kredis.set(pending_key).members).not_to include(wallet.id.to_s)
      end
    end

    context "when pending is below the threshold" do
      before { seed_pending(wallet.id, 5_000, 1) }

      it "does not pay out and leaves the pending balance intact" do
        expect { described_class.call }.not_to change(BlockchainTransaction, :count)
        expect(Kredis.counter("solana_pending_payouts:#{wallet.id}").value.to_i).to eq(5_000)
        expect(Kredis.set(pending_key).members).to include(wallet.id.to_s)
      end
    end

    context "when the threshold is zero (batch disabled)" do
      before do
        allow(SystemParameter).to receive(:current)
          .with(:solana_batch_threshold_usdc, default: 0).and_return(0)
        seed_pending(wallet.id, 25_000, 2)
      end

      it "is a no-op (backward-compat — per-event path owns payouts)" do
        expect { described_class.call }.not_to change(BlockchainTransaction, :count)
      end
    end

    context "with a concurrent increment during payout" do
      before { seed_pending(wallet.id, 25_000, 2) }

      it "decrements (not clears) so the concurrent reward survives" do
        # Імітуємо подію, що надійшла поки виплата у польоті.
        allow_any_instance_of(Solana::MintingService).to receive(:batch_payout!) do
          Kredis.counter("solana_pending_payouts:#{wallet.id}").increment(by: 5_000)
          "sig"
        end

        described_class.call

        expect(Kredis.counter("solana_pending_payouts:#{wallet.id}").value.to_i).to eq(5_000)
        expect(Kredis.set(pending_key).members).to include(wallet.id.to_s)
      end
    end

    context "when one wallet's payout fails" do
      let(:tree2) { create(:tree, cluster: cluster) }
      let(:wallet2) { tree2.wallet }

      before do
        wallet2.update!(solana_public_address: recipient_solana_address)
        seed_pending(wallet.id, 25_000, 1)
        seed_pending(wallet2.id, 25_000, 1)

        allow_any_instance_of(Solana::MintingService).to receive(:batch_payout!) do |instance, *_args|
          raise "boom" if instance.instance_variable_get(:@wallet).id == wallet.id

          "sig"
        end
      end

      it "isolates the failure and still drains the healthy wallet" do
        expect { described_class.call }.not_to raise_error

        # Healthy wallet drained; failed wallet retains pending for the next cycle.
        expect(Kredis.set(pending_key).members).to include(wallet.id.to_s)
        expect(Kredis.set(pending_key).members).not_to include(wallet2.id.to_s)
      end
    end

    context "when a pending wallet no longer exists in the DB" do
      let(:orphan_id) { 999_999 }

      before { seed_pending(orphan_id, 30_000, 1) }

      it "discards the orphan pending balance" do
        expect { described_class.call }.not_to change(BlockchainTransaction, :count)
        expect(Kredis.set(pending_key).members).not_to include(orphan_id.to_s)
        expect(Kredis.counter("solana_pending_payouts:#{orphan_id}").value.to_i).to eq(0)
      end
    end
  end

  private

  def stub_solana_rpc_success
    allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
      case kwargs[:body][:method]
      when "getLatestBlockhash"
        Web3::HttpClient::Response.new({ "jsonrpc" => "2.0", "result" => { "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } } }.to_json)
      when "sendTransaction"
        Web3::HttpClient::Response.new({ "jsonrpc" => "2.0", "result" => "5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE" }.to_json)
      when "getBalance"
        Web3::HttpClient::Response.new({ "jsonrpc" => "2.0", "result" => { "value" => 1_000_000_000 } }.to_json)
      else
        Web3::HttpClient::Response.new({ "jsonrpc" => "2.0", "result" => {} }.to_json)
      end
    end
  end
end
