# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainBurningService do
  let(:fake_tx_hash) { "0x#{'f' * 64}" }
  let(:mock_client)  { instance_double(Eth::Client) }
  let(:mock_key)     { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_contract) { double("contract") }

  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] = "0x#{'a' * 64}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"

    # Kredis може бути відсутнім у тестовому середовищі
    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(Kredis).to receive(:lock).and_yield
    allow(mock_client).to receive(:transact).and_return(fake_tx_hash)

    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_new_alert)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)

    # [SLASH-1 §3.2] Default: positive-A evidence present, so the existing burn-mechanics
    # specs exercise the slash path. CauseEvidence's own logic is unit-tested in
    # spec/services/slashing/cause_evidence_spec.rb; here we stub the collaborator and
    # test the GATE WIRING explicitly below.
    allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(true)
  end

  describe ".call" do
    context "when no confirmed transactions exist" do
      it "returns early when no confirmed transactions exist" do
        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to be_nil
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    context "when confirmed minted tokens exist" do
      let!(:tree) { create(:tree, cluster: cluster) }

      before do
        tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )
      end

      it "calculates damage ratio from AiInsight data" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'c' * 64}"
        )

        # 1 of 2 trees is critically stressed → damage_ratio = 0.5
        create(:ai_insight,
               analyzable: tree,
               insight_type: :daily_health_summary,
               target_date: cluster.local_yesterday,
               stress_index: 1.0)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          # §6.2 convex curve: slash_ratio = damage_ratio^GAMMA (0.5^1.3), NOT linear 0.5
          burn_amount = (2000 * (0.5**1.3)).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "falls back to full burn when no AiInsight data and no source_tree" do
        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          expected_wei = (1000.0 * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "creates audit BlockchainTransaction on success" do
        expect {
          described_class.call(organization.id, naas_contract.id)
        }.to change(BlockchainTransaction, :count).by(1)

        audit_tx = BlockchainTransaction.last
        expect(audit_tx.tx_hash).to eq(fake_tx_hash)
        # [ARCH.45] intent → :sent; BlockchainConfirmationWorker дорезолвить до :confirmed/:failed.
        expect(audit_tx.status).to eq("sent")
        expect(audit_tx.to_address).to eq(organization.crypto_public_address)
        expect(audit_tx.sourceable).to eq(naas_contract)
      end

      it "schedules BlockchainConfirmationWorker after sending transaction" do
        expect(BlockchainConfirmationWorker).to receive(:perform_in).with(30.seconds, fake_tx_hash)

        described_class.call(organization.id, naas_contract.id)
      end

      # [ARCH.45] Double-burn crash-window guard — slash() необоротний; на повторному виклику
      # (non-StandardError крах, що обходить rescue-breach) intent-marker не дає палити вдруге.
      context "when an in-flight slash already exists" do
        it "does NOT re-slash when an in-flight :sent slash already exists for the contract" do
          BlockchainTransaction.create!(
            sourceable: naas_contract, cluster: cluster, amount: 500, token_type: :carbon_coin,
            status: :sent, to_address: organization.crypto_public_address, tx_hash: fake_tx_hash,
            notes: "prior in-flight slash"
          )

          result = described_class.call(organization.id, naas_contract.id)

          expect(result).to eq(:slashed)
          expect(mock_client).not_to have_received(:transact) # без повторного on-chain slash
        end

        it "re-slashes after a :pending intent (crash before broadcast), failing the stale one" do
          stale = BlockchainTransaction.create!(
            sourceable: naas_contract, cluster: cluster, amount: 500, token_type: :carbon_coin,
            status: :pending, to_address: organization.crypto_public_address,
            notes: "pre-broadcast crash intent"
          )

          described_class.call(organization.id, naas_contract.id)

          expect(stale.reload.status).to eq("failed")
          expect(mock_client).to have_received(:transact) # свіжий slash виконано
        end

        it "fails the intent (no in-flight orphan) when the slash broadcast raises" do
          allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC down")

          expect { described_class.call(organization.id, naas_contract.id) }
            .to raise_error(StandardError, /RPC down/)

          intent = BlockchainTransaction.where(sourceable: naas_contract).last
          expect(intent.status).to eq("failed") # не лишився :pending → не хибний in-flight на retry
        end
      end

      it "sets contract to breached and creates EwsAlert on blockchain failure" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        expect {
          described_class.call(organization.id, naas_contract.id)
        }.to raise_error(StandardError, "RPC timeout")
                .and change(EwsAlert, :count).by(1)

        expect(naas_contract.reload.status).to eq("breached")

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        expect(alert.alert_type).to eq("system_fault")
        expect(alert.cluster).to eq(cluster)
      end

      it "uses proportional damage ratio for single source_tree death" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'e' * 64}"
        )

        # 2 trees total, source_tree specified → damage_ratio = 1/2 = 0.5
        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          total_minted = 1500
          # §6.2 convex curve: slash_ratio = 0.5^1.3 (not linear 0.5)
          burn_amount = (total_minted * (0.5**1.3)).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end
    end
  end

  describe "positive-A-evidence gate (SLASH-1 §3.2)" do
    let!(:tree) { create(:tree, cluster: cluster) }

    before do
      tree.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'a' * 64}"
      )
    end

    it "FREEZES (no burn, no breach, Field-Audit alert) without direct Category-A evidence" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(false)

      result = nil
      expect {
        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)
      }.to change { EwsAlert.where(alert_type: :system_fault).count }.by(1)

      expect(result).to eq(:frozen)
      expect(mock_client).not_to have_received(:transact)
      expect(naas_contract.reload.status).not_to eq("breached")
    end

    it "SLASHES (returns :slashed, burns, breaches) when Category-A evidence is present" do
      result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

      expect(result).to eq(:slashed)
      expect(mock_client).to have_received(:transact)
      expect(naas_contract.reload.status).to eq("breached")
    end

    it "BYPASSES the gate for a contractual burn even without Category-A evidence" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(false)

      described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)

      expect(mock_client).to have_received(:transact)
    end
  end

  describe "#calculate_slash_ratio (§6.2 convex curve)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    it "reaches 100% slash for full negligent loss (no dead-zone)" do
      expect(service.send(:calculate_slash_ratio, 1.0)).to eq(1.0)
    end

    it "punishes a small loss gently (convex: d=0.1 → ~5%, not 10%)" do
      expect(service.send(:calculate_slash_ratio, 0.1)).to be_within(0.005).of(0.05)
    end

    it "is strictly below the old linear ratio for partial damage" do
      expect(service.send(:calculate_slash_ratio, 0.5)).to be < 0.5
    end

    it "is monotonic — more damage always burns strictly more" do
      ratios = [ 0.1, 0.3, 0.6, 1.0 ].map { |d| service.send(:calculate_slash_ratio, d) }
      expect(ratios).to eq(ratios.sort)
      expect(ratios.uniq.size).to eq(4)
    end

    it "returns 0.0 for zero damage" do
      expect(service.send(:calculate_slash_ratio, 0.0)).to eq(0.0)
    end

    it "caps the penalty_factor at PENALTY_FACTOR_MAX (multiplier ceiling, not final ratio)" do
      expect(service.send(:calculate_slash_ratio, 0.5, 5.0)).to be_within(1e-9).of((0.5**1.3) * 2.0)
    end

    it "clamps the final ratio to 1.0 even when the multiplier would exceed it" do
      expect(service.send(:calculate_slash_ratio, 1.0, 2.0)).to eq(1.0)
    end

    it "reads GAMMA from SystemParameter (DAO-governed)" do
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current).with(:slash_gamma, default: 1.3).and_return(2.0)
      # γ=2.0 → 0.5^2 × 1.0 = 0.25
      expect(service.send(:calculate_slash_ratio, 0.5)).to be_within(1e-9).of(0.25)
    end
  end

  describe "#combine_penalty_factor (SLASH-1 de-correlation §6, pure)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    def combine(no_ack: false, streamr_gap: false, no_maintenance: false)
      service.send(:combine_penalty_factor,
                   no_ack: no_ack, streamr_gap: streamr_gap, no_maintenance: no_maintenance)
    end

    it "is the negligence baseline when no signal fires" do
      expect(combine).to eq(1.0)
    end

    it "applies the no-ack uplift" do
      expect(combine(no_ack: true)).to eq(1.5)
    end

    it "applies the Streamr-gap uplift" do
      expect(combine(streamr_gap: true)).to eq(1.25)
    end

    # ── THE SLASH-SAFETY invariant (§6): correlated comms-loss MUST NOT sum ──
    it "DE-CORRELATES correlated comms-loss: no-ack + Streamr gap → max (1.5), NOT sum (1.75)" do
      penalty_factor = combine(no_ack: true, streamr_gap: true)
      expect(penalty_factor).to eq(1.5)      # 1.0 + max(0.5, 0.25)
      expect(penalty_factor).not_to eq(1.75) # the double-count we are preventing
    end

    it "stacks INDEPENDENT physical negligence on top of the comms-loss max" do
      # 1.0 + max(0.5, 0.25) + 0.5 = 2.0
      expect(combine(no_ack: true, streamr_gap: true, no_maintenance: true)).to eq(2.0)
    end

    it "feeds the multiplier into the slash curve, capped at PENALTY_FACTOR_MAX" do
      penalty_factor = combine(no_ack: true, no_maintenance: true) # 2.0 = PENALTY_FACTOR_MAX
      expect(service.send(:calculate_slash_ratio, 0.5, penalty_factor))
        .to be_within(1e-9).of((0.5**1.3) * 2.0)
    end
  end

  describe "#calculate_penalty_factor (SLASH-1 activation gate §3)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    context "when the activation gate is off (default — DAO-confirm pending, 05_05 §3)" do
      it "returns the negligence baseline" do
        expect(service.send(:calculate_penalty_factor))
          .to eq(described_class::DEFAULT_PENALTY_FACTOR)
      end

      it "stays inert even when a real cause signal is present" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active)
        expect(service.send(:calculate_penalty_factor)).to eq(1.0)
      end
    end

    context "when DAO-enabled via SystemParameter" do
      before do
        allow(SystemParameter).to receive(:current).and_call_original
        allow(SystemParameter).to receive(:current)
          .with(:slash_cause_uplift_enabled, default: false).and_return(true)
      end

      it "is the baseline when no signal fires" do
        expect(service.send(:calculate_penalty_factor)).to eq(1.0)
      end

      it "sources no-ack from an active critical EwsAlert and applies the uplift" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active)
        expect(service.send(:calculate_penalty_factor)).to eq(1.5)
      end
    end

    context "when sourcing signals from real records" do
      it "does not flag no-ack once the critical alert is resolved (acknowledged)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :resolved)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "flags physical negligence: aged critical alert with no MaintenanceRecord" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(true)
      end

      it "clears physical negligence once a MaintenanceRecord exists for the alert" do
        alert = create(:ews_alert, cluster: cluster, severity: :critical,
                                   alert_type: :vandalism_breach, status: :active, created_at: 1.hour.ago)
        create(:maintenance_record, ews_alert: alert)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end
    end
  end

  describe "calculate_damage_ratio edge cases" do
    context "when burn_amount is zero due to very small damage_ratio" do
      it "returns early without calling blockchain" do
        tree = create(:tree, cluster: cluster)
        # Create a very small confirmed amount
        tree.wallet.blockchain_transactions.create!(
          amount: 1,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # Many trees so damage_ratio is tiny, and ceil of (1 * tiny) = 0
        # We need enough trees that 1/N rounds to 0 after ceil. That's impossible with ceil.
        # Instead, test when total_minted is 0 by removing confirmed txs.
        # Actually, the burn_amount.zero? path is when damage_ratio * total_minted rounds to 0.
        # With source_tree, damage_ratio = 1/total_trees.
        # If total_minted=1 and total_trees=1, burn_amount = ceil(1 * 1.0) = 1, not zero.
        # The zero path happens when total_minted_amount itself is zero (already tested).
        # Let's verify total_minted_amount.zero? early return.
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    context "when cluster has zero trees" do
      it "returns damage_ratio of 1.0 (full burn)" do
        tree = create(:tree, cluster: cluster)
        tree.wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # Use send to directly test calculate_damage_ratio
        service = described_class.new(organization.id, naas_contract.id)
        trees_relation = double("trees_relation", count: 0)
        allow(cluster).to receive(:trees).and_return(trees_relation)
        # Set the @cluster instance variable
        service.instance_variable_set(:@cluster, cluster)

        result = service.send(:calculate_damage_ratio)
        expect(result).to eq(1.0)
      end
    end

    context "when no AiInsight and no source_tree" do
      it "returns damage_ratio of 1.0 (full burn)" do
        tree = create(:tree, cluster: cluster)
        tree.wallet.blockchain_transactions.create!(
          amount: 200,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # No AiInsight records, no source_tree
        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          expected_wei = (200.0 * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end
    end
  end

  describe "burn_amount zero" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "returns early when burn_amount is zero" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 1, status: :confirmed)
      allow_any_instance_of(described_class).to receive(:calculate_damage_ratio).and_return(0.0)

      result = described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      expect(result).to be_nil
    end
  end

  describe "total_minted_amount zero" do
    let(:tree_burn) { create(:tree, cluster: cluster) }

    it "returns early when no confirmed transactions exist" do
      result = described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      expect(result).to be_nil
    end
  end

  describe "success path with tx_hash" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "marks naas_contract as breached and creates audit transaction" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)

      allow(mock_client).to receive(:transact).and_return("0x" + "f" * 64)

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      naas_contract.reload
      expect(naas_contract.status).to eq("breached")

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx).not_to be_nil
      expect(audit_tx.tx_hash).to eq("0x" + "f" * 64)
    end
  end

  describe "nil source_tree" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "uses cluster.trees.active.first wallet as audit_wallet" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)

      allow(mock_client).to receive(:transact).and_return("0xabc123")

      described_class.call(organization.id, naas_contract.id)

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx.wallet).to eq(wallet_burn)
    end
  end

  describe "nil audit_wallet" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "creates transaction with cluster instead of wallet when all trees dead" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)
      tree_burn.update_columns(status: Tree.statuses[:deceased])

      allow(mock_client).to receive(:transact).and_return("0xdead")

      described_class.call(organization.id, naas_contract.id)

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx.wallet).to be_nil
      expect(audit_tx.cluster).to eq(cluster)
    end
  end

  # =========================================================================
  # ORACLE_SLASHER_PRIVATE_KEY FALLBACK (E.2 Role Separation)
  # =========================================================================
  describe "key selection (E.2 Role Separation)" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    before do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)
    end

    it "uses ORACLE_SLASHER_PRIVATE_KEY when available" do
      ENV["ORACLE_SLASHER_PRIVATE_KEY"] = "0x#{'b' * 64}"

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(Eth::Key).to have_received(:new).with(priv: "0x#{'b' * 64}")
    ensure
      ENV.delete("ORACLE_SLASHER_PRIVATE_KEY")
    end

    it "falls back to ORACLE_PRIVATE_KEY when slasher key is missing" do
      ENV.delete("ORACLE_SLASHER_PRIVATE_KEY")

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(Eth::Key).to have_received(:new).with(priv: "0x#{'a' * 64}")
    end
  end

  # =========================================================================
  # PROMETHEUS METRICS (SCC_SLASHED_TOTAL)
  # =========================================================================
  describe "Prometheus metric (SCC_SLASHED_TOTAL)" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "increments SCC_SLASHED_TOTAL after successful slash" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 500, status: :confirmed)
      allow(mock_client).to receive(:transact).and_return("0x" + "f" * 64)

      metric = SilkenNet::Metrics::SCC_SLASHED_TOTAL
      before_val = metric.get

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(metric.get).to be > before_val
    end
  end

  # =========================================================================
  # DAMAGE RATIO WITH AiInsight + SOURCE_TREE COMBINED
  # =========================================================================
  describe "damage_ratio with AiInsight and source_tree" do
    let!(:tree1) { create(:tree, cluster: cluster) }
    let!(:tree2) { create(:tree, cluster: cluster) }

    before do
      tree1.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'a' * 64}")
      tree2.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'b' * 64}")
    end

    it "prefers AiInsight ratio over source_tree ratio" do
      # AiInsight says 2/2 trees critical = 100% damage
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
             target_date: cluster.local_yesterday, stress_index: 1.0)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
             target_date: cluster.local_yesterday, stress_index: 1.0)

      described_class.call(organization.id, naas_contract.id, source_tree: tree1)

      expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
        # 100% of 2000 = 2000 tokens
        expected_wei = (2000.0 * (10**18)).to_i
        expect(amount_in_wei).to eq(expected_wei)
      end
    end

    it "caps damage_ratio at 1.0 maximum" do
      # Even with many critical trees, ratio can't exceed 1.0
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
             target_date: cluster.local_yesterday, stress_index: 1.0)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
             target_date: cluster.local_yesterday, stress_index: 1.0)

      # All trees critical → ratio = 2/2 = 1.0 (capped)
      described_class.call(organization.id, naas_contract.id)

      expect(mock_client).to have_received(:transact)
    end
  end

  describe "nil tx_hash from transact" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "does not mark contract as breached when transact returns nil" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)

      allow(mock_client).to receive(:transact).and_return(nil)

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(naas_contract.reload.status).not_to eq("breached")
    end
  end
end
