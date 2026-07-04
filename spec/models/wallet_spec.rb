# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  before do
    allow_any_instance_of(described_class).to receive(:broadcast_balance_update)
  end

  describe "#credit!" do
    it "atomically increments balance" do
      wallet = create(:tree).wallet
      original_balance = wallet.balance

      wallet.credit!(100)
      wallet.reload

      expect(wallet.balance).to eq(original_balance + 100)
    end

    it "does not change balance with zero points" do
      wallet = create(:tree).wallet
      original_balance = wallet.balance

      wallet.credit!(0)
      wallet.reload

      expect(wallet.balance).to eq(original_balance)
    end

    describe "broadcast throttling" do
      it "broadcasts on the first credit! call" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).once

        wallet.credit!(10)
      end

      it "throttles subsequent broadcasts within the throttle window" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).once

        3.times { wallet.credit!(10) }
      end

      it "broadcasts again after the throttle period expires" do
        wallet = create(:tree).wallet
        Rails.cache.clear

        expect(wallet).to receive(:broadcast_balance_update).twice

        wallet.credit!(10)
        # Очищаємо кеш троттлінгу, імітуючи закінчення таймера
        Rails.cache.delete("wallet_broadcast_throttle:#{wallet.id}")
        wallet.credit!(10)
      end
    end
  end

  describe "#lock_and_mint!" do
    it "locks balance using locked_balance instead of immediate decrement" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000)
      allow(wallet.tree).to receive(:active?).and_return(true)

      wallet.lock_and_mint!(500, 100)
      wallet.reload

      expect(wallet.balance).to eq(1000)
      expect(wallet.locked_balance).to eq(500)
      expect(wallet.available_balance).to eq(500)
    end
  end

  describe "validations" do
    it "rejects negative balance" do
      wallet = create(:tree).wallet
      wallet.balance = -1

      expect(wallet).not_to be_valid
      expect(wallet.errors[:balance]).to include("must be greater than or equal to 0")
    end
  end

  describe "#available_balance" do
    it "returns balance minus locked_balance" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 500, locked_balance: 200)

      expect(wallet.available_balance).to eq(300)
    end
  end

  describe "#lock_funds!" do
    it "increments locked_balance by the given amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000)

      wallet.lock_funds!(400)
      wallet.reload

      expect(wallet.locked_balance).to eq(400)
      expect(wallet.available_balance).to eq(600)
    end

    it "raises when insufficient available balance" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 100, locked_balance: 50)

      expect { wallet.lock_funds!(100) }.to raise_error(RuntimeError, /Недостатньо доступних коштів/)
    end
  end

  describe "#release_locked_funds!" do
    it "decrements locked_balance by the given amount" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 400)

      wallet.release_locked_funds!(200)
      wallet.reload

      expect(wallet.locked_balance).to eq(200)
    end

    it "raises when releasing more than locked" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 1000, locked_balance: 100)

      expect { wallet.release_locked_funds!(200) }.to raise_error(RuntimeError, /розблокувати більше/)
    end
  end

  describe "locked_balance validation" do
    it "rejects negative locked_balance" do
      wallet = create(:tree).wallet
      wallet.locked_balance = -1

      expect(wallet).not_to be_valid
      expect(wallet.errors[:locked_balance]).to include("must be greater than or equal to 0")
    end
  end

  describe "#lock_and_mint! edge cases" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:tree) { create(:tree, cluster: cluster, status: :active) }
    let(:wallet) { tree.wallet }

    before do
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
      wallet.update!(balance: 10_000)
    end

    it "raises when tree is not active" do
      tree.update_column(:status, Tree.statuses[:deceased])
      tree.reload

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /не активне/)
    end

    it "returns nil when threshold is zero" do
      result = wallet.lock_and_mint!(1000, 0)
      expect(result).to be_nil
    end

    it "returns nil when threshold is negative" do
      result = wallet.lock_and_mint!(1000, -5)
      expect(result).to be_nil
    end

    it "uses org crypto address when wallet has no crypto_public_address" do
      wallet.update!(crypto_public_address: nil)

      tx = wallet.lock_and_mint!(1000, 100)
      expect(tx).to be_present
      expect(tx.to_address).to eq(organization.crypto_public_address)
    end

    it "raises when neither wallet nor org have crypto address" do
      wallet.update!(crypto_public_address: nil)
      organization.update_column(:crypto_public_address, nil)

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /крипто-адреса/)
    end

    it "raises when available balance is insufficient" do
      wallet.update!(balance: 50, locked_balance: 0)

      expect {
        wallet.lock_and_mint!(1000, 100)
      }.to raise_error(RuntimeError, /Недостатньо балів/)
    end

    it "returns nil when tokens_to_mint is zero" do
      result = wallet.lock_and_mint!(50, 100)
      expect(result).to be_nil
    end

    it "creates blockchain transaction and enqueues worker on success" do
      tx = wallet.lock_and_mint!(1000, 100)

      expect(tx).to be_present
      expect(tx.amount).to eq(10)
      expect(tx.status).to eq("pending")
      expect(tx.locked_points).to eq(1000)
    end
  end

  describe "Wallet branch coverage" do
    let(:organization_bc) { create(:organization) }
    let(:cluster_bc) { create(:cluster, organization: organization_bc) }
    let(:tree_bc) { create(:tree, cluster: cluster_bc) }
    let(:wallet_bc) { tree_bc.wallet }

    before do
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    end

    describe "organization&.crypto_public_address when organization is nil" do
      it "raises when both wallet and organization addresses are blank" do
        wallet_bc.update_columns(crypto_public_address: nil, organization_id: nil)
        wallet_bc.reload

        expect {
          wallet_bc.lock_and_mint!(10_000, 10_000)
        }.to raise_error(RuntimeError, /крипто-адреса/)
      end
    end

    describe "return unless tx — tokens_to_mint zero" do
      it "returns nil when tokens_to_mint is zero" do
        wallet_bc.update_columns(balance: 5000)
        wallet_bc.reload

        result = wallet_bc.lock_and_mint!(5000, 10_000)
        expect(result).to be_nil
      end
    end

    describe "lock_and_mint! success path" do
      it "creates transaction" do
        wallet_bc.update_columns(balance: 20_000)
        wallet_bc.reload

        tx = wallet_bc.lock_and_mint!(20_000, 10_000)
        expect(tx).to be_persisted
        expect(tx.amount).to eq(2)
      end
    end
  end

  describe "lock_and_mint! nil tx return guard" do
    it "returns nil when transaction block returns nil (tokens_to_mint zero)" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster, status: :active)
      wallet = tree.wallet
      wallet.update!(balance: 50)

      # 50 / 10000 = 0 tokens → returns nil inside block → return unless tx
      result = wallet.lock_and_mint!(50, 10_000)
      expect(result).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # 🔒 PESSIMISTIC LOCKING (Wiki 04_01 Blocker Fix)
  # ---------------------------------------------------------------------------
  # Перевіряємо, що всі мутаційні методи гаманця використовують pessimistic lock
  # (SELECT ... FOR UPDATE) для захисту від race conditions при масовій телеметрії.
  describe "pessimistic locking" do
    describe "#credit! with pessimistic lock" do
      it "acquires a row lock via with_lock before incrementing balance" do
        wallet = create(:tree).wallet
        original_balance = wallet.balance

        # Verify that with_lock is used (lock! is called internally)
        expect(wallet).to receive(:lock!).and_call_original

        wallet.credit!(100)
        wallet.reload

        expect(wallet.balance).to eq(original_balance + 100)
      end

      it "serializes concurrent credits to the same wallet" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 0)

        # Simulate two sequential credits (representing serialized concurrent access)
        wallet.credit!(100)
        wallet.credit!(200)
        wallet.reload

        expect(wallet.balance).to eq(300)
      end
    end

    describe "#lock_funds! with pessimistic lock" do
      it "acquires a row lock before checking available balance" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 1000)

        expect(wallet).to receive(:lock!).and_call_original

        wallet.lock_funds!(400)
        wallet.reload

        expect(wallet.locked_balance).to eq(400)
      end

      it "raises with fresh balance data under lock" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 100, locked_balance: 50)

        expect { wallet.lock_funds!(100) }.to raise_error(RuntimeError, /Недостатньо доступних коштів/)
      end
    end

    describe "#release_locked_funds! with pessimistic lock" do
      it "acquires a row lock before checking locked balance" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 1000, locked_balance: 400)

        expect(wallet).to receive(:lock!).and_call_original

        wallet.release_locked_funds!(200)
        wallet.reload

        expect(wallet.locked_balance).to eq(200)
      end

      it "raises with fresh data under lock when releasing more than locked" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 1000, locked_balance: 100)

        expect { wallet.release_locked_funds!(200) }.to raise_error(RuntimeError, /розблокувати більше/)
      end
    end

    describe "consistent locking pattern across all mutation methods" do
      it "credit! uses with_lock" do
        wallet = create(:tree).wallet
        expect(wallet).to receive(:with_lock).and_call_original
        wallet.credit!(10)
      end

      it "lock_funds! uses with_lock" do
        wallet = create(:tree).wallet
        wallet.update!(balance: 1000)
        expect(wallet).to receive(:with_lock).and_call_original
        wallet.lock_funds!(100)
      end

      it "release_locked_funds! uses with_lock" do
        wallet = create(:tree).wallet
        wallet.update!(locked_balance: 500)
        expect(wallet).to receive(:with_lock).and_call_original
        wallet.release_locked_funds!(100)
      end
    end
  end

  # [KYC.1] KYC бенефіціара: власна адреса → власний статус; custodial → org.
  describe "#kyc_approved_for_minting?" do
    let(:wallet) { create(:tree).wallet }

    it "uses the wallet's own status when it has its own address" do
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
      expect(wallet.kyc_approved_for_minting?).to be true

      wallet.update!(hadron_kyc_status: "pending")
      expect(wallet.kyc_approved_for_minting?).to be false
    end

    it "inherits the organization's status for a custodial wallet (no own address)" do
      wallet.update_column(:crypto_public_address, nil)

      wallet.organization.update!(hadron_kyc_status: "approved")
      expect(wallet.reload.kyc_approved_for_minting?).to be true

      wallet.organization.update!(hadron_kyc_status: "pending")
      expect(wallet.reload.kyc_approved_for_minting?).to be false
    end

    it "is false for a custodial wallet without an organization" do
      wallet.update_column(:crypto_public_address, nil)
      wallet.update_column(:organization_id, nil)

      expect(wallet.reload.kyc_approved_for_minting?).to be false
    end
  end

  describe "KYC re-verification on address change (KYC.1)" do
    let(:wallet) { create(:tree).wallet }

    it "resets status to pending and enqueues verification when the address changes" do
      wallet.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")

      expect {
        wallet.update!(crypto_public_address: "0x" + "c" * 40)
      }.to change { HadronKycVerificationWorker.jobs.size }.by(1)

      expect(wallet.reload.hadron_kyc_status).to eq("pending")
      expect(HadronKycVerificationWorker.jobs.last["args"]).to eq([ "Wallet", wallet.id ])
    end

    it "keeps an explicitly-set status when address and status change together" do
      wallet.update!(crypto_public_address: "0x" + "d" * 40, hadron_kyc_status: "approved")
      expect(wallet.reload.hadron_kyc_status).to eq("approved")
    end
  end

  # [MRV.1] Settled/in-flight money-tx = MRV-докази — destroy заборонений.
  describe "#guard_mrv_evidence!" do
    let(:wallet) { create(:tree).wallet }

    it "aborts destroy when a confirmed transaction exists" do
      wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :confirmed,
        to_address: "0x" + "b" * 40, tx_hash: "0x" + "c" * 64
      )

      expect(wallet.destroy).to be false
      expect(wallet.errors[:base].first).to include('MRV')
      expect(described_class.exists?(wallet.id)).to be true
    end

    it "allows destroying a wallet with only pending transactions" do
      wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
      )

      expect { wallet.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
