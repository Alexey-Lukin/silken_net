# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ethereum::StateAnchorService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    silence_broadcasts!(:wallet_balance, :tree_map)
  end

  describe "#generate_state_root" do
    it "returns a Hash with state_root as a 64-character SHA256 hex string" do
      result = described_class.new.generate_state_root

      expect(result).to be_a(Hash)
      expect(result[:state_root]).to match(/\A[a-f0-9]{64}\z/)
    end

    it "includes all components for reproducibility (BLOCKER-6, E.53, E.54)" do
      result = described_class.new.generate_state_root

      expect(result).to include(:state_root, :total_growth_points, :total_sfc, :active_tree_count, :chain_hash, :anchored_at)
      expect(result[:anchored_at]).to be_a(Time)
      expect(result[:total_sfc]).to be_a(Numeric)
      expect(result[:active_tree_count]).to be_a(Integer)
    end

    it "incorporates total scc_balance from all wallets" do
      wallet.update!(scc_balance: 1000.0)

      root1 = described_class.new.generate_state_root[:state_root]

      wallet.update!(scc_balance: 2000.0)

      root2 = described_class.new.generate_state_root[:state_root]

      expect(root1).not_to eq(root2)
    end

    it "incorporates chain_hash from latest AuditLog" do
      user = create(:user, organization: organization)

      freeze_time do
        AuditLog.create!(
          user: user,
          organization: organization,
          action: "test_action_1",
          chain_hash: "abc123"
        )

        root1 = described_class.new.generate_state_root[:state_root]

        AuditLog.create!(
          user: user,
          organization: organization,
          action: "test_action_2",
          chain_hash: "def456"
        )

        root2 = described_class.new.generate_state_root[:state_root]

        expect(root1).not_to eq(root2)
      end
    end

    it "uses GENESIS fallback when no AuditLog exists (leaf0 = flat aggregate, root = Merkle over [leaf0])" do
      # [ARCH.97] Шосте поле — `total_scc_supply`; на порожній БД теж 0.0, але
      # величина ІНША за природою (Σ confirmed-мінтів − Σ burn'ів, не сума балансів).
      expected_payload = "0.0|0.0|0|GENESIS|#{Time.current.utc.iso8601}|0.0"
      leaf0 = Digest::SHA256.hexdigest(expected_payload)

      freeze_time do
        result = described_class.new.generate_state_root
        expect(result[:state_root]).to eq(MerkleTree.root([ leaf0 ]))
        expect(result[:chain_hash]).to eq("GENESIS")
        expect(result[:total_sfc]).to eq(0)
        expect(result[:active_tree_count]).to eq(0)
      end
    end

    describe "Merkle tier2 [ARCH.12 Фаза 1а]" do
      it "empty window → tier2 = [aggregate leaf0] only, root_version 1, leaf_count 0" do
        result = described_class.new.generate_state_root

        expect(result[:root_version]).to eq(1)
        expect(result[:leaf_count]).to eq(0)
        expect(result[:subtree_roots].size).to eq(1)
        expect(result[:subtree_roots].first["kind"]).to eq("aggregate")
        expect(result[:window_from]).to be_nil
        expect(result[:window_to]).to eq(result[:anchored_at] - described_class::WINDOW_GRACE)
      end

      it "leaf0 equals the flat aggregate hash (supply-finality preserved)" do
        freeze_time do
          result = described_class.new.generate_state_root
          expected_leaf0 = Digest::SHA256.hexdigest(
            EthereumAnchor.aggregate_payload(
              total_growth_points: result[:total_growth_points],
              total_scc_supply: result[:total_scc_supply], total_sfc: result[:total_sfc],
              active_tree_count: result[:active_tree_count],
              chain_hash: result[:chain_hash], anchored_at: result[:anchored_at]
            )
          )
          expect(result[:subtree_roots].first["root"]).to eq(expected_leaf0)
        end
      end

      it "builds one cluster subroot per cluster and counts leaves; state_root = Merkle over tier2" do
        log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
        result = described_class.new.generate_state_root

        cluster_entry = result[:subtree_roots].find { |e| e["cluster_id"] == cluster.id }
        expect(cluster_entry).to be_present
        expect(cluster_entry["root"]).to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(log) ]))
        expect(result[:leaf_count]).to eq(1)
        expect(result[:state_root])
          .to eq(MerkleTree.root(result[:subtree_roots].map { |e| e["root"] }))
      end

      it "GRACE boundary: logs newer than window_to are excluded (no forever-lost rows)" do
        create(:telemetry_log, tree: tree, created_at: 1.minute.ago)
        result = described_class.new.generate_state_root

        expect(result[:leaf_count]).to eq(0)
      end

      it "window chains from previous confirmed merkle anchor's window_to" do
        old_log = create(:telemetry_log, tree: tree, created_at: 3.days.ago)
        create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
        # window_to СВІДОМО розведено з anchored_at: тест мусить розрізняти
        # «код бере prev.window_to» (правильно) від «prev.anchored_at» (регресія
        # → загублені-назавжди рядки між ними) — review-фікс слабкого assert.
        prev = create(:ethereum_anchor, :confirmed,
                      root_version: 1, window_to: 1.day.ago - 10.minutes,
                      subtree_roots: [ { "kind" => "aggregate", "root" => "ab" * 32 } ],
                      leaf_count: 1, anchored_at: 1.day.ago)

        result = described_class.new.generate_state_root

        expect(result[:window_from]).to eq(prev.reload.window_to)
        expect(result[:leaf_count]).to eq(1) # old_log поза вікном (≤ prev.window_to)
        cluster_entry = result[:subtree_roots].find { |e| e["cluster_id"] == cluster.id }
        expect(cluster_entry["root"]).not_to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(old_log) ]))
      end

      it "NULL-cluster trees form a sentinel group sorted last" do
        clusterless_tree = create(:tree, cluster: nil)
        create(:telemetry_log, tree: clusterless_tree, created_at: 2.hours.ago)
        create(:telemetry_log, tree: tree, created_at: 2.hours.ago)

        result = described_class.new.generate_state_root

        expect(result[:subtree_roots].last["cluster_id"]).to be_nil
        expect(result[:subtree_roots].last).not_to have_key("kind")
        expect(result[:leaf_count]).to eq(2)
      end
    end

    it "incorporates timestamp so results differ over time" do
      root1 = travel_to(Time.utc(2026, 3, 1, 12, 0, 0)) { described_class.new.generate_state_root[:state_root] }
      root2 = travel_to(Time.utc(2026, 3, 1, 12, 0, 1)) { described_class.new.generate_state_root[:state_root] }

      expect(root1).not_to eq(root2)
    end

    it "executes within a REPEATABLE READ transaction for snapshot isolation" do
      # Verify that generate_state_root wraps SQL queries in a transaction
      # with isolation level :repeatable_read to prevent inconsistent snapshots
      # when parallel workers (MintCarbonCoinWorker, AuditLogWorker) write between queries.
      expect(ActiveRecord::Base).to receive(:transaction).with(isolation: :repeatable_read).and_call_original

      described_class.new.generate_state_root
    end
  end

  describe "#anchor_to_l1!" do
    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_key) { instance_double(Eth::Key, address: "0x" + "ab" * 20) }
    let(:mock_contract) { instance_double(Eth::Contract) }

    before do
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALCHEMY_ETHEREUM_RPC_URL").and_return("https://eth-mainnet.g.alchemy.com/v2/test-key")
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_PRIVATE_KEY").and_return("0x" + "ab" * 32)
      allow(ENV).to receive(:fetch).with("ETHEREUM_ANCHOR_CONTRACT").and_return("0x" + "cd" * 20)
      allow(ENV).to receive(:fetch).with("ETHEREUM_MAX_FEE_GWEI", anything).and_return(100)
      allow(ENV).to receive(:fetch).with("ETHEREUM_PRIORITY_FEE_GWEI", anything).and_return(2)
      allow(ENV).to receive(:fetch).with("ETHEREUM_GAS_LIMIT", anything).and_return(100_000)

      # [BLOCKER-4] Mock balance check — sufficient balance by default

      # [ARCH.66 companion] get_nonce кличеться для нового anchor (nonce nil) перед broadcast.
      allow(mock_client).to receive_messages(get_balance: 1 * (10**18), get_nonce: 42)

      # [ARCH.66] Не запускати реальний confirmation-поллер (happy-path enqueue після :sent /
      # re-arm на resume-гілці).
      allow(EthereumAnchorConfirmationWorker).to receive(:perform_in)
      allow(EthereumAnchorConfirmationWorker).to receive(:perform_async)
    end

    it "returns an EthereumAnchor record on success (BLOCKER-2)" do
      expected_tx_hash = "0x" + "fa" * 32
      allow(mock_client).to receive(:transact).and_return(expected_tx_hash)

      result = described_class.new.anchor_to_l1!

      expect(result).to be_a(EthereumAnchor)
      expect(result).to be_persisted
      expect(result.tx_hash).to eq(expected_tx_hash)
      expect(result).to be_status_sent
    end

    it "[ARCH.66] schedules confirmation polling after a successful send" do
      allow(mock_client).to receive(:transact).and_return("0x" + "fa" * 32)

      result = described_class.new.anchor_to_l1!

      expect(EthereumAnchorConfirmationWorker).to have_received(:perform_in).with(30.seconds, result.id)
    end

    it "persists state_root components for reproducibility (BLOCKER-6, E.53, E.54)" do
      allow(mock_client).to receive(:transact).and_return("0x" + "fa" * 32)

      result = described_class.new.anchor_to_l1!

      expect(result.state_root).to match(/\A[a-f0-9]{64}\z/)
      expect(result.total_growth_points).to be_present
      expect(result.total_sfc).to be_present
      expect(result.active_tree_count).to be_present
      expect(result.chain_hash).to be_present
      expect(result.anchored_at).to be_present
      expect(result.verify_state_root).to be true
    end

    it "passes gas parameters to transact (BLOCKER-3)" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(mock_client).to have_received(:transact) do |_contract, _method, _root, **opts|
        expect(opts[:gas_limit]).to eq(100_000)
        expect(opts[:max_fee_per_gas]).to eq(100 * (10**9))
        expect(opts[:max_priority_fee_per_gas]).to eq(2 * (10**9))
        expect(opts[:legacy]).to be false
      end
    end

    it "raises when ETH balance is insufficient (BLOCKER-4)" do
      allow(mock_client).to receive(:get_balance).and_return(0)

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Insufficient anchor wallet balance/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_failed
      expect(anchor.error_message).to include("Insufficient ETH balance")
    end

    it "connects to Alchemy Ethereum RPC" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(Eth::Client).to have_received(:create).with("https://eth-mainnet.g.alchemy.com/v2/test-key")
    end

    it "calls storeStateRoot with a 0x-prefixed bytes32 root" do
      allow(mock_client).to receive(:transact).and_return("0x" + "aa" * 32)

      described_class.new.anchor_to_l1!

      expect(mock_client).to have_received(:transact) do |contract, method, root, **_opts|
        expect(contract).to eq(mock_contract)
        expect(method).to eq("storeStateRoot")
        expect(root).to match(/\A0x[a-f0-9]{64}\z/)
      end
    end

    it "rescues Net::OpenTimeout and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(Net::OpenTimeout, "execution expired")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_pending
      expect(anchor.error_message).to include("Timeout")
      # [ARCH.66 companion regression-guard] nonce персиститься ПЕРЕД transact → присутній навіть коли
      # broadcast timeout'ить (сам F2a crash-window); переміщення persist-after-transact = цей assert червоний.
      expect(anchor.nonce).to eq(42)
    end

    it "rescues Net::ReadTimeout and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(Net::ReadTimeout, "Net::ReadTimeout")

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      anchor = EthereumAnchor.last
      expect(anchor).to be_status_pending
    end

    it "rescues IOError and keeps anchor as pending (S6.7 double-anchor guard)" do
      allow(mock_client).to receive(:transact).and_raise(IOError, "Connection reset by peer")

      expect(Rails.logger).to receive(:warn).with(/Connection error.*kept as :pending/)

      expect {
        described_class.new.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Connection Error/)

      expect(EthereumAnchor.last).to be_status_pending
    end

    it "re-raises the Timeout when generate_state_root fails before the anchor row is created" do
      service = described_class.new
      allow(service).to receive(:generate_state_root).and_raise(Net::OpenTimeout, "DB unreachable")

      before_count = EthereumAnchor.count
      expect {
        service.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      expect(EthereumAnchor.count).to eq(before_count)
    end

    it "re-raises the Connection Error when generate_state_root fails before the anchor row is created" do
      service = described_class.new
      allow(service).to receive(:generate_state_root).and_raise(IOError, "broken pipe")

      before_count = EthereumAnchor.count
      expect {
        service.anchor_to_l1!
      }.to raise_error(RuntimeError, /Ethereum L1 Connection Error/)

      expect(EthereumAnchor.count).to eq(before_count)
    end

    it "logs successful anchoring" do
      allow(mock_client).to receive(:transact).and_return("0x" + "bb" * 32)

      expect(Rails.logger).to receive(:info).with(/State Root anchored/)

      described_class.new.anchor_to_l1!
    end

    context "with double-anchoring guard" do
      it "skips when a sent anchor exists within the last week" do
        sent_anchor = EthereumAnchor.create!(
          state_root: "c" * 64,
          total_growth_points: 500.0,
          chain_hash: "existing_hash",
          anchored_at: 1.hour.ago,
          status: :sent,
          tx_hash: "0x#{"dd" * 32}"
        )

        expect(Rails.logger).to receive(:info).with(/In-flight anchor detected/)

        result = described_class.new.anchor_to_l1!

        expect(result).to eq(sent_anchor)
        expect(EthereumAnchor.count).to eq(1)
        # [ARCH.66 INFO-7] resume-гілка re-arm'ить поллер (recovery якщо enqueue загубився / поллер помер)
        expect(EthereumAnchorConfirmationWorker).to have_received(:perform_async).with(sent_anchor.id)
      end

      it "resumes a pending anchor instead of creating a new one" do
        pending_anchor = EthereumAnchor.create!(
          state_root: "d" * 64,
          total_growth_points: 600.0,
          chain_hash: "pending_hash",
          anchored_at: 30.minutes.ago,
          status: :pending
        )

        expected_tx_hash = "0x#{"ee" * 32}"
        allow(mock_client).to receive(:transact).and_return(expected_tx_hash)

        result = described_class.new.anchor_to_l1!

        expect(result.id).to eq(pending_anchor.id)
        expect(result).to be_status_sent
        expect(result.tx_hash).to eq(expected_tx_hash)
        expect(EthereumAnchor.count).to eq(1)
      end

      it "ignores anchors older than one week" do
        travel_to(8.days.ago) do
          EthereumAnchor.create!(
            state_root: "e" * 64,
            total_growth_points: 700.0,
            chain_hash: "old_hash",
            anchored_at: Time.current,
            status: :sent,
            tx_hash: "0x#{"ff" * 32}"
          )
        end

        allow(mock_client).to receive(:transact).and_return("0x#{"ab" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.state_root).not_to eq("e" * 64)
        expect(EthereumAnchor.count).to eq(2)
      end

      it "ignores failed anchors and creates a new one" do
        EthereumAnchor.create!(
          state_root: "f" * 64,
          total_growth_points: 800.0,
          chain_hash: "failed_hash",
          anchored_at: 1.hour.ago,
          status: :failed,
          error_message: "timeout"
        )

        allow(mock_client).to receive(:transact).and_return("0x#{"ab" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.state_root).not_to eq("f" * 64)
        expect(result).to be_status_sent
        expect(EthereumAnchor.count).to eq(2)
      end
    end

    context "with nonce-persist (ARCH.66 F2a double-send guard)" do
      it "persists the broadcast nonce before sending and passes it explicitly to transact" do
        allow(mock_client).to receive_messages(get_nonce: 42, transact: "0x#{"ab" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.nonce).to eq(42)
        expect(mock_client).to have_received(:transact) do |_contract, _method, _root, **opts|
          expect(opts[:nonce]).to eq(42)
        end
      end

      it "reuses the persisted nonce on a pending resume instead of re-fetching (no N+1)" do
        # crash між transact() і update!(:sent): anchor лишився :pending з уже-персистованим nonce.
        pending_anchor = EthereumAnchor.create!(
          state_root: "a" * 64, total_growth_points: 900.0, chain_hash: "resume_hash",
          anchored_at: 20.minutes.ago, status: :pending, nonce: 7
        )
        allow(mock_client).to receive(:transact).and_return("0x#{"cc" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(result.id).to eq(pending_anchor.id)
        expect(result.nonce).to eq(7)
        expect(mock_client).not_to have_received(:get_nonce)
        expect(mock_client).to have_received(:transact) do |_contract, _method, _root, **opts|
          expect(opts[:nonce]).to eq(7)
        end
      end

      it "fetches a fresh nonce on resume when the crash landed before nonce was persisted" do
        # crash між create!(:pending) і persist nonce → tx НЕ полетів → безпечно фетчити свіжий.
        EthereumAnchor.create!(
          state_root: "b" * 64, total_growth_points: 950.0, chain_hash: "no_nonce_hash",
          anchored_at: 15.minutes.ago, status: :pending, nonce: nil
        )
        allow(mock_client).to receive_messages(get_nonce: 99, transact: "0x#{"dd" * 32}")

        result = described_class.new.anchor_to_l1!

        expect(mock_client).to have_received(:get_nonce)
        expect(result.nonce).to eq(99)
        expect(EthereumAnchor.count).to eq(1) # resume-гілка перевикористала pending, не створила новий
      end
    end

    context "when a resume re-broadcast is rejected — nonce already landed → escalate (ARCH.66 companion)" do
      let(:pending_resume) do
        # F2a: crash між broadcast і update!(:sent) лишив :pending з персистованим nonce; на resume
        # перший tx уже досяг мережі → same-nonce re-broadcast відхиляється нодою (RpcError < IOError).
        EthereumAnchor.create!(
          state_root: "a" * 64, total_growth_points: 900.0, chain_hash: "ambiguous_hash",
          anchored_at: 20.minutes.ago, status: :pending, nonce: 7
        )
      end

      it "escalates a pending resume to :manual_review on 'nonce too low' (tx already mined)" do
        pending_resume
        allow(mock_client).to receive(:transact).and_raise(Eth::Client::RpcError.new("nonce too low"))

        result = described_class.new.anchor_to_l1!

        expect(result.id).to eq(pending_resume.id)
        expect(result.reload).to be_status_manual_review
        expect(result.error_message).to include("nonce 7")
        expect(result.tx_hash).to be_nil
      end

      it "escalates on 'already known' (tx still in mempool)" do
        pending_resume
        allow(mock_client).to receive(:transact).and_raise(Eth::Client::RpcError.new("already known"))

        expect(described_class.new.anchor_to_l1!.reload).to be_status_manual_review
      end

      it "re-raises a NON-ambiguous RpcError (fresh insufficient-funds) without escalating" do
        pending_resume
        allow(mock_client).to receive(:transact).and_raise(Eth::Client::RpcError.new("insufficient funds for gas"))

        expect { described_class.new.anchor_to_l1! }.to raise_error(/Ethereum L1 RPC Error/)
        expect(pending_resume.reload).to be_status_pending # доля справді невідома → НЕ escalate
      end
    end
  end
end
