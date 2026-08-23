# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Solana::BatchPayoutService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }
  let(:recipient_solana_address) { "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV" }
  let(:pending_key) { Solana::MintingService::PENDING_PAYOUT_WALLETS_KEY }
  # Мутабельний RPC-стан у let-hash (RSpec/InstanceVariable — не тримаємо @-змінні):
  # sends = лічильник sendTransaction; sig = керована відповідь getSignatureStatuses.
  let(:rpc) { { sends: 0, sig: "confirmed" } }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    silence_broadcasts!(:wallet_balance, :tree_map)

    ENV["SOLANA_WALLET_KEYPAIR"] = "a" * 64
    ENV["SOLANA_FEE_PAYER_PUBKEY"] = "SiLkEnFeEpAyEr11111111111111111111111111111"
    ENV["SOLANA_FEE_PAYER_TOKEN_ACCOUNT"] = "SiLkEnSoUrCeAtA1111111111111111111111111111"
    ENV["SOLANA_USDC_MINT_ADDRESS"] = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"
    ENV["SOLANA_DEST_TOKEN_ACCOUNT"] = "DeSt1nAt1oNaTa111111111111111111111111111111"

    allow(Ed25519Crypto::SigningService).to receive(:sign).and_return("ab" * 64)

    stub_solana_rpc

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

  def pending_lamports(wallet_id)
    Kredis.counter("solana_pending_payouts:#{wallet_id}").value.to_i
  end

  describe ".call — fresh payout (no in-flight)" do
    before { seed_pending(wallet.id, 25_000, 2) }

    it "creates an intent-marker tx (:sent) and sends exactly one transaction" do
      expect { described_class.call }.to change(BlockchainTransaction, :count).by(1)

      tx = BlockchainTransaction.last
      expect(tx.blockchain_network).to eq("solana")
      expect(tx.status).to eq("sent")
      expect(tx.tx_hash).to be_present
      expect(tx.amount).to eq(0.025)
      expect(rpc[:sends]).to eq(1)
    end

    it "is confirm-gated: does NOT drain Kredis until on-chain confirm" do
      described_class.call
      # Kredis тримається до reconcile-підтвердження (запобігає втраті при краху до confirm).
      expect(pending_lamports(wallet.id)).to eq(25_000)
      expect(Kredis.set(pending_key).members).to include(wallet.id.to_s)
    end
  end

  describe ".call — under-lock TOCTOU re-check (L40)" do
    before { seed_pending(wallet.id, 25_000, 2) } # passes the cheap pre-check (≥ 20_000 lamports)

    it "does NOT pay when another process drains the counter between the pre-check and the lock" do
      # simulate the race: the counter falls below threshold the instant the lock is acquired,
      # so the in-lock re-read (`next if pending < threshold`) must skip the payout.
      allow(Kredis).to receive(:lock).and_wrap_original do |orig, *args, **kwargs, &blk|
        Kredis.counter("solana_pending_payouts:#{wallet.id}").decrement(by: 25_000) # → 0, below threshold
        orig.call(*args, **kwargs, &blk)
      end

      expect { described_class.call }.not_to change(BlockchainTransaction, :count)
      expect(rpc[:sends]).to eq(0)
    end
  end

  describe ".call — reconcile in-flight payout" do
    before do
      seed_pending(wallet.id, 25_000, 2)
      described_class.call # 1-й цикл: створює :sent intent
    end

    it "on confirmed: settles Kredis + confirms tx, WITHOUT re-paying" do
      rpc[:sig] = "confirmed"
      described_class.call # 2-й цикл: reconcile

      expect(BlockchainTransaction.where(blockchain_network: "solana").count).to eq(1) # без нової tx
      expect(rpc[:sends]).to eq(1) # без 2-го sendTransaction
      expect(BlockchainTransaction.last.status).to eq("confirmed")
      expect(pending_lamports(wallet.id)).to eq(0)
      expect(Kredis.set(pending_key).members).not_to include(wallet.id.to_s)
    end

    # 🔴 [INF.26] Чисельник SLO визначений як BROADCAST (докстрінг + три сиблінги), а
    # `:sent` входить в `unsettled_within` — тож без гарда КОЖНА нормальна виплата
    # лічилась двічі (broadcast, потім confirm наступного циклу) при знаменнику +0:
    # панель `success/attempts` читала б ~200 % замість SLO.
    it "does not re-count the SLO numerator on reconcile — broadcast already counted it" do
      rpc[:sig] = "confirmed"
      metric = SilkenNet::Metrics::SOLANA_PAYOUT_SUCCESS_TOTAL
      before_val = metric.get

      described_class.call # 2-й цикл: reconcile уже порахованої виплати

      expect(metric.get).to eq(before_val)
    end

    it "on not_found: escalates to manual_review WITHOUT re-pay (RPC-lag double-pay guard)" do
      rpc[:sig] = "not_found"
      described_class.call

      expect(BlockchainTransaction.last.status).to eq("manual_review")
      expect(rpc[:sends]).to eq(1) # без авто-re-pay — :not_found неавторитетне (можливо landed)
      expect(pending_lamports(wallet.id)).to eq(25_000)
    end

    it "on processing: skips and leaves the tx in-flight" do
      rpc[:sig] = "processing"
      described_class.call

      expect(BlockchainTransaction.last.status).to eq("sent")
      expect(pending_lamports(wallet.id)).to eq(25_000)
    end

    it "manual_review tx keeps blocking re-pay (no double-pay even if RPC lagged)" do
      rpc[:sig] = "not_found"
      described_class.call # → manual_review
      rpc[:sig] = "not_found"
      expect { described_class.call }.not_to change(BlockchainTransaction, :count) # без свіжої виплати
      expect(rpc[:sends]).to eq(1) # ВСЕ ОДНЕ — manual_review блокує сліпий re-pay
      expect(BlockchainTransaction.last.status).to eq("manual_review")
    end

    it "auto-heals a manual_review tx when the payout later confirms on-chain" do
      rpc[:sig] = "not_found"
      described_class.call # → manual_review
      rpc[:sig] = "confirmed"
      described_class.call # reconcile → confirmed → settle, без re-pay
      expect(rpc[:sends]).to eq(1)
      expect(pending_lamports(wallet.id)).to eq(0)
    end
  end

  # Позитивна половина того самого гарда: без неї мутація `if false` лишила б гілку
  # німою, а негативний пін вище — зеленим. Тут broadcast стався, але процес упав ДО
  # `mark_as_sent!`, тож tx лишився `:pending` і лічильник його проґавив — саме цей
  # випадок reconcile і має внести в чисельник.
  describe ".call — reconcile of a payout whose process crashed before mark_as_sent!" do
    it "counts the SLO numerator once, because broadcast was never counted" do
      wallet.blockchain_transactions.create!(
        blockchain_network: "solana", status: :pending, tx_hash: "cr" * 32,
        amount: 0.025, token_type: :cusd, to_address: recipient_solana_address
      )
      seed_pending(wallet.id, 25_000, 2)
      rpc[:sig] = "confirmed"
      metric = SilkenNet::Metrics::SOLANA_PAYOUT_SUCCESS_TOTAL
      before_val = metric.get

      described_class.call

      expect(metric.get - before_val).to eq(1)
    end
  end

  describe ".call — crash-window double-pay protection [ARCH.45]" do
    before { seed_pending(wallet.id, 25_000, 2) }

    it "never double-pays even if Kredis was never drained after the first send" do
      described_class.call            # 1-й цикл: on-chain send + :sent intent, БЕЗ drain (симуляція краху до confirm)
      expect(rpc[:sends]).to eq(1)
      expect(pending_lamports(wallet.id)).to eq(25_000) # лічильник не занулено

      # 2-й цикл: pending усе ще ≥ поріг, але in-flight guard звіряє замість сліпої виплати.
      rpc[:sig] = "confirmed"
      described_class.call
      expect(rpc[:sends]).to eq(1)    # ВСЕ ОДНЕ — подвійної виплати немає
      expect(BlockchainTransaction.where(blockchain_network: "solana").count).to eq(1)
      expect(pending_lamports(wallet.id)).to eq(0)
    end

    it "resumes a :pending intent (crash between broadcast and mark_as_sent) without re-broadcasting" do
      described_class.call # 1-й цикл: створює :sent intent (broadcast відбувся)
      # Симулюємо краху ПІСЛЯ broadcast, ДО mark_as_sent: tx лишилась :pending з signature.
      BlockchainTransaction.last.update_columns(status: BlockchainTransaction.statuses[:pending])
      rpc[:sig] = "confirmed" # on-chain виплата насправді пройшла
      send_before = rpc[:sends]

      described_class.call # reconcile :pending → on-chain confirmed → settle
      expect(rpc[:sends]).to eq(send_before) # НЕ re-broadcast
      expect(BlockchainTransaction.last.status).to eq("confirmed")
      expect(pending_lamports(wallet.id)).to eq(0)
    end
  end

  describe ".call — concurrent reward survival" do
    before { seed_pending(wallet.id, 25_000, 2) }

    it "settles only the paid amount so a concurrent increment survives" do
      described_class.call # :sent для 25_000
      Kredis.counter("solana_pending_payouts:#{wallet.id}").increment(by: 5_000) # подія у польоті
      Kredis.counter("solana_pending_payout_count:#{wallet.id}").increment(by: 1)

      rpc[:sig] = "confirmed"
      described_class.call # reconcile settle by tx amount (25_000), не за поточним pending (30_000)

      expect(pending_lamports(wallet.id)).to eq(5_000)
      expect(Kredis.set(pending_key).members).to include(wallet.id.to_s)
    end
  end

  describe ".call — edge cases" do
    it "is a no-op when the pending-wallet set is empty (threshold set, nothing matured)" do
      # threshold > 0 (before-hook), але жоден гаманець не акумулював → wallet_ids порожній → return.
      expect { described_class.call }.not_to change(BlockchainTransaction, :count)
      expect(rpc[:sends]).to eq(0)
    end

    it "settles lamports but skips the event counter when the intent carries no events tag" do
      # Per-event legacy intent (notes без «events:N») підхоплений batch-reconcile: settle_kredis
      # decrement-ить lamports (amount>0 завжди), але count пропускає — events regex → 0.
      seed_pending(wallet.id, 25_000, 2)
      described_class.call
      BlockchainTransaction.last.update_columns(notes: "Solana micro-reward: legacy per-event")

      rpc[:sig] = "confirmed"
      described_class.call

      expect(pending_lamports(wallet.id)).to eq(0) # lamports settled
      expect(Kredis.counter("solana_pending_payout_count:#{wallet.id}").value.to_i).to eq(2) # events NOT decremented
    end

    it "does not pay when pending is below the threshold" do
      seed_pending(wallet.id, 5_000, 1)
      expect { described_class.call }.not_to change(BlockchainTransaction, :count)
      expect(pending_lamports(wallet.id)).to eq(5_000)
    end

    it "is a no-op when the threshold is zero (per-event path owns payouts)" do
      allow(SystemParameter).to receive(:current)
        .with(:solana_batch_threshold_usdc, default: 0).and_return(0)
      seed_pending(wallet.id, 25_000, 2)
      expect { described_class.call }.not_to change(BlockchainTransaction, :count)
    end

    it "discards the orphan pending balance when the wallet no longer exists" do
      orphan_id = 999_999
      seed_pending(orphan_id, 30_000, 1)
      expect { described_class.call }.not_to change(BlockchainTransaction, :count)
      expect(Kredis.set(pending_key).members).not_to include(orphan_id.to_s)
      expect(Kredis.counter("solana_pending_payouts:#{orphan_id}").value.to_i).to eq(0)
    end

    it "isolates a per-wallet failure and still processes healthy wallets" do
      tree2 = create(:tree, cluster: cluster)
      wallet2 = tree2.wallet
      wallet2.update!(solana_public_address: recipient_solana_address)
      seed_pending(wallet.id, 25_000, 1)
      seed_pending(wallet2.id, 25_000, 1)

      allow_any_instance_of(Solana::MintingService).to receive(:batch_payout!) do |instance|
        raise "boom" if instance.instance_variable_get(:@wallet).id == wallet.id

        instance.instance_variable_get(:@wallet).blockchain_transactions.create!(
          amount: 0.025, token_type: :carbon_coin, status: :sent, to_address: recipient_solana_address,
          tx_hash: "sig2", blockchain_network: "solana", notes: "events:1"
        )
      end

      expect { described_class.call }.not_to raise_error
      expect(Kredis.set(pending_key).members).to include(wallet.id.to_s) # failed wallet retained
    end
  end

  private

  def resp(result)
    Web3::HttpClient::Response.new({ "jsonrpc" => "2.0", "result" => result }.to_json)
  end

  def stub_solana_rpc
    allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
      case kwargs[:body][:method]
      when "getLatestBlockhash"
        resp({ "value" => { "blockhash" => "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N" } })
      when "sendTransaction"
        rpc[:sends] += 1
        resp("5UfDuX7hXbLMKnPRqHxJgpPh6W9y3m4Nk7v2zKQ1YdCE")
      when "getBalance"
        resp({ "value" => 1_000_000_000 })
      when "getSignatureStatuses"
        val = case rpc[:sig]
        when "confirmed" then [ { "confirmationStatus" => "finalized", "err" => nil } ]
        when "processing" then [ { "confirmationStatus" => "processed", "err" => nil } ]
        else [ nil ] # not_found
        end
        resp({ "value" => val })
      else
        resp({})
      end
    end
  end
end
