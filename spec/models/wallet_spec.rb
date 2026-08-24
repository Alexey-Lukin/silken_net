# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  before { silence_broadcasts!(:wallet_balance) }

  # [UI.4 · I18N.2] Контракт трансляції балансу. Кожен із трьох прикладів пінить
  # окремий баг, який тут уже жив: (1) стрім був голий `wallet`, якого не слухала
  # жодна сторінка, тож баланс не оновлювався живим НІКОЛИ; (2) ціль була
  # `wallet_balance_#{id}` — елемент усередині фрейму, а не сам фрейм; (3) payload
  # ніс `BalanceDisplay` з шістьма `t()`, тобто локаль ПРОДЮСЕРА розліталась усім
  # глядачам (`04_04 §8.1а`). Глобальний мок вимикається `and_call_original`.
  describe "#broadcast_balance_update" do
    let(:wallet)   { create(:tree).wallet }
    let(:captured) { [] }

    before do
      allow_any_instance_of(described_class).to receive(:broadcast_balance_update).and_call_original
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) { |*args, **kwargs| captured << [ args, kwargs ] }
    end

    it "broadcasts to the composite stream Wallets::Show actually subscribes to" do
      wallet.broadcast_balance_update

      expect(captured.first[0].first).to eq([ wallet, :transactions ])
    end

    it "targets the turbo-frame id, not the inner balance div" do
      wallet.broadcast_balance_update

      expect(captured.first[1][:target]).to eq("wallet_balance_frame_#{wallet.id}")
    end

    it "renders a locale-invariant payload — byte-identical in two locales" do
      uk = I18n.with_locale(:uk) { wallet.broadcast_balance_update; captured.pop[1][:html] }
      lv = I18n.with_locale(:lv) { wallet.broadcast_balance_update; captured.pop[1][:html] }

      expect(uk).to eq(lv)
      # І це саме порожня заглушка, а не відрендерений фрагмент: інакше «однаково
      # у двох локалях» могло б означати лише «переклад ще не додано».
      expect(uk).to match(%r{\A<turbo-frame [^>]*></turbo-frame>\z})
    end

    it "points the stub at the balance endpoint each viewer re-fetches for itself" do
      wallet.broadcast_balance_update

      expect(captured.first[1][:html]).to include(%(src="/wallets/#{wallet.id}/balance"))
    end
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

    # 🔴 [UI.4, 2026-08-17] Тут стояли ТРИ приклади, що цементували leading-edge
    # тротл — включно з «throttles subsequent broadcasts within the throttle
    # window», тобто сюїта ВИМАГАЛА викидання новішого балансу. Дискримінатор
    # нижче інший і навмисно: пін не на кількість кадрів (їх однаково один в
    # обох світах), а на ЗНАЧЕННЯ, яке бачить ОСТАННІЙ кадр.
    #
    # ⚠️ Стеля названа: у тестах `Turbo::ThreadDebouncer` підмінений на
    # `ImmediateDebouncer` (`spec/support/turbo_debouncer.rb`), тож САМЕ
    # коалесування тут не перевіряється — перевіряється, що останній кадр
    # доїжджає. Коалесування живе в гемі й має власні тести там.
    describe "коалесування броадкасту балансу" do
      it "останній кадр бачить баланс ПІСЛЯ останнього кредиту" do
        # Знімаємо файловий стаб (рядок 8) — інакше приклад міряв би заглушку.
        allow_any_instance_of(described_class).to receive(:broadcast_balance_update).and_call_original

        wallet = create(:tree).wallet
        start  = wallet.balance

        seen = []
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do
          seen << described_class.find(wallet.id).balance
        end

        wallet.credit!(10)
        wallet.credit!(20)

        # Ліхтар: без непорожньої множини приклад був би зелений на нулі кадрів.
        expect(seen).not_to be_empty, "жодного броадкасту — приклад безпредметний"

        expect(seen.last).to eq(start + 30),
                             "останній кадр показує #{seen.last} замість #{start + 30} — новіше значення викинуто"
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

    # [ARCH.94] Некратний вхід морозив залишок під НУЛЬ монет — і назавжди, бо
    # reserve-семантика (`04_01 §6`) locked не звільняє взагалі. Живого некратного
    # викликача сьогодні немає (`EvaluateTreeBatchWorker` рахує `tokens × threshold`),
    # тож без цього прикладу гілка озброїлась би тихо першим новим.
    it "locks only the CONVERTED points when the input is not a multiple of the threshold" do
      wallet = create(:tree).wallet
      wallet.update!(balance: 30_000)
      allow(wallet.tree).to receive(:active?).and_return(true)

      tx = wallet.lock_and_mint!(25_000, 10_000)
      wallet.reload

      expect(tx.amount).to eq(2)
      # 2 монети коштують 20 000 балів — решта 5 000 мусить лишитись ДОСТУПНОЮ,
      # інакше вона заморожена ні за що (виміряний дефект: locked ставало 25 000).
      expect(wallet.locked_balance).to eq(20_000)
      expect(wallet.available_balance).to eq(10_000)
      expect(tx.locked_points).to eq(20_000)
    end
  end

  describe "#lock_and_mint! lineage [MRV.1]" do
    let(:wallet) do
      w = create(:tree).wallet
      w.update!(balance: 1000)
      allow(w.tree).to receive(:active?).and_return(true)
      w
    end

    it "first mint (NULL cursor): window covers full history up to GRACE, root attached, cursor advanced" do
      old_log = create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      tx = wallet.lock_and_mint!(500, 100)
      wallet.reload

      expect(tx.telemetry_window_from_at).to be_nil
      expect(tx.telemetry_window_to_id).to eq(old_log.id)
      expect(tx.telemetry_lineage_version).to eq(Mrv::TelemetryLeaf::LEAF_VERSION)
      expect(tx.reload.telemetry_merkle_root)
        .to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(old_log) ]))
      expect(wallet.lineage_cursor_log_id).to eq(old_log.id)
    end

    it "GRACE: log younger than WINDOW_GRACE stays out of the window (next mint's business)" do
      create(:telemetry_log, tree: wallet.tree, created_at: 1.minute.ago)
      tx = wallet.lock_and_mint!(500, 100)
      wallet.reload

      expect(tx.telemetry_window_to_at).to be_nil
      expect(tx.reload.telemetry_merkle_root).to be_nil
      expect(wallet.lineage_cursor_log_id).to be_nil
    end

    it "empty window (carry-mint без нових логів): from == to == cursor, root nil, cursor unchanged" do
      log = create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      wallet.lock_and_mint!(300, 100)
      wallet.reload
      tx2 = wallet.lock_and_mint!(300, 100)
      wallet.reload

      expect(tx2.telemetry_window_from_id).to eq(log.id)
      expect(tx2.telemetry_window_to_id).to eq(log.id)
      expect(tx2.reload.telemetry_merkle_root).to be_nil
      expect(wallet.lineage_cursor_log_id).to eq(log.id)
    end

    it "consecutive windows chain without overlap: second mint covers only newer logs" do
      log1 = create(:telemetry_log, tree: wallet.tree, created_at: 3.hours.ago)
      wallet.lock_and_mint!(300, 100)
      log2 = create(:telemetry_log, tree: wallet.tree, created_at: 1.hour.ago)
      tx2 = wallet.reload.lock_and_mint!(300, 100)

      expect(tx2.telemetry_window_from_id).to eq(log1.id)
      expect(tx2.telemetry_window_to_id).to eq(log2.id)
      expect(Mrv::LineageWindow.logs_for(tx2.reload)).to contain_exactly(
        an_object_having_attributes(id: log2.id)
      )
    end

    it "clock-regression clamp: window_upper нижче курсора → порожнє вікно, курсор СТОЇТЬ (review-фікс)" do
      log = create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      wallet.lock_and_mint!(300, 100)
      wallet.reload
      # Симуляція NTP step-back / крос-нодового відставання: курсор «у майбутньому»
      future_cursor = 1.hour.from_now
      wallet.update!(lineage_cursor_at: future_cursor, lineage_cursor_log_id: log.id + 1_000)

      tx2 = wallet.lock_and_mint!(300, 100)
      wallet.reload

      expect(tx2.telemetry_window_from_at).to eq(tx2.telemetry_window_to_at) # порожнє
      expect(wallet.lineage_cursor_at).to be_within(1.second).of(future_cursor) # НЕ відкотився
      expect(tx2.reload.telemetry_merkle_root).to be_nil
    end

    it "cursor is monotonic: tx.fail! does NOT roll it back (windows attach to attempts)" do
      log = create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      tx = wallet.lock_and_mint!(500, 100)
      tx.fail!("boom")
      wallet.reload

      expect(wallet.lineage_cursor_log_id).to eq(log.id)
    end

    it "fail-open: root computation failure never blocks the mint (WARN + metric, root NULL)" do
      create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      allow(Mrv::LineageWindow).to receive(:root_for).and_raise(StandardError, "leaf exploded")
      expect(SilkenNet::Metrics::LINEAGE_ROOT_FAILURES_TOTAL).to receive(:increment)

      tx = wallet.lock_and_mint!(500, 100)

      expect(tx).to be_persisted
      expect(tx.reload.telemetry_merkle_root).to be_nil
    end

    it "zero-mint (points below threshold) does not move the cursor" do
      create(:telemetry_log, tree: wallet.tree, created_at: 2.hours.ago)
      result = wallet.lock_and_mint!(50, 100)
      wallet.reload

      expect(result).to be_nil
      expect(wallet.lineage_cursor_log_id).to be_nil
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
      silence_broadcasts!(:tree_map)
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
      silence_broadcasts!(:tree_map)
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
        wallet.update!(balance: 500, locked_balance: 500)
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

    # [E.60 Фаза 1б] Стемпнутий tx = член archive-батчу: root міг поїхати on-chain,
    # видалення стерло б вікна → хибний mismatch у pin-воркера.
    it "aborts destroy when a pending tx is archive-batch-stamped [E.60]" do
      batch = TelemetryArchiveBatch.create!(archive_root: "e" * 64, token_type: :carbon_coin)
      wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending,
        to_address: "0x" + "b" * 40, archive_batch_id: batch.id
      )

      expect(wallet.destroy).to be false
      expect(wallet.errors[:base].first).to include("MRV")
      expect(described_class.exists?(wallet.id)).to be true
    end

    # [ARCH.57] Дозволений destroy лишає ряди сиротами (nullify), НЕ стирає:
    # сирітський tx валідний за дизайном (cluster-sourced money вже живе без wallet).
    it "nullifies (not deletes) the remaining tx rows on a permitted destroy" do
      tx = wallet.blockchain_transactions.create!(
        amount: 1, token_type: :carbon_coin, status: :pending, to_address: "0x" + "b" * 40
      )

      expect { wallet.destroy! }.not_to change(BlockchainTransaction, :count)
      expect(tx.reload.wallet_id).to be_nil
    end
  end
end
