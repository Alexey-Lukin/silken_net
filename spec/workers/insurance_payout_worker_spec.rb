# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsurancePayoutWorker, type: :worker do
  let(:organization) { create(:organization, crypto_public_address: "0x" + "ab" * 20) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }
  let!(:wallet) { create(:wallet, tree: tree) }
  let(:insurance) { create(:parametric_insurance, :triggered, cluster: cluster, organization: organization) }

  # [INS.1 dual-trigger] За замовчуванням НЕЗАЛЕЖНЕ підтвердження присутнє (cluster-level verified
  # fire — Trigger-2), тож happy-path виплата проходить gate. Cluster-level (tree: nil), щоб не
  # конфліктувати з per-tree fire-алертами сателітних тестів. Тести «без підтвердження → тримаємо»
  # прибирають `confirmation`.
  let!(:confirmation) do
    create(:ews_alert, :fire, cluster: cluster, tree: nil, satellite_status: :verified)
  end

  before do
    allow(BlockchainMintingService).to receive(:call)
    # [INS.1 kill-switch] Прапор УВІМКНЕНО за замовчуванням (інакше воркер no-op); окремий тест нижче перевіряє flip-off.
    allow(SystemParameter).to receive(:current).and_call_original
    allow(SystemParameter).to receive(:current)
      .with(:parametric_insurance_oracle_enabled, default: false).and_return(true)
    # EwsAlert-колбеки (after_create_commit не фаєрить у транзакційних тестах — стабимо про всяк).
    silence_broadcasts!(:alert_notify, :alert_new, :alert_update)
    silence_side_effects!(:satellite_verification)
  end

  # [DOC-T.89, ⚖️ 2026-08-26] Гард на SFC-виплату ЗНЯТО разом із самим значенням:
  # `forest_coin` більше не в енумі `ParametricInsurance`, тож поліс не може бути
  # підписаний у типі, який система відмовляється виконувати. Пін переїхав у
  # `spec/models/parametric_insurance_spec.rb` — там він стереже ДЖЕРЕЛО вибору,
  # а не наслідок. Тутешній приклад був би тепер невибудовним: фабрика підняла б
  # `ArgumentError` ще в `let`, тобто зелений давав би сам факт неможливості —
  # це вимір фікстури, не поведінки воркера.

  it "memoizes the kill-switch flag — SystemParameter is read once per worker instance" do
    worker = described_class.new
    allow(SystemParameter).to receive(:current)
      .with(:parametric_insurance_oracle_enabled, default: false).and_return(true)

    2.times { worker.send(:oracle_enabled?) } # 2nd call hits the `defined?(@oracle_enabled)` memo

    expect(SystemParameter).to have_received(:current)
      .with(:parametric_insurance_oracle_enabled, default: false).once
  end

  # [INS.1 kill-switch] Прапор OFF → money-path не виконується (кандидат тримається).
  it "is an inert no-op when the kill-switch flag is off (default)" do
    allow(SystemParameter).to receive(:current)
      .with(:parametric_insurance_oracle_enabled, default: false).and_return(false)

    described_class.new.perform(insurance.id)

    expect(BlockchainMintingService).not_to have_received(:call)
    expect(insurance.reload.status).to eq("triggered")
  end

  describe "#perform" do
    it "creates a BlockchainTransaction for payout" do
      expect {
        described_class.new.perform(insurance.id)
      }.to change(BlockchainTransaction, :count).by(1)

      tx = BlockchainTransaction.last
      expect(tx.amount).to eq(insurance.payout_amount)
      expect(tx.to_address).to eq(organization.crypto_public_address)
      expect(tx.status).to eq("pending")
      expect(tx.notes).to include("Страхове відшкодування")
    end

    it "marks insurance as paid" do
      described_class.new.perform(insurance.id)

      insurance.reload
      expect(insurance.status).to eq("paid")
      expect(insurance.paid_at).to be_present
    end

    it "calls BlockchainMintingService to execute payout" do
      described_class.new.perform(insurance.id)

      expect(BlockchainMintingService).to have_received(:call)
        .with(kind_of(Integer), created_at_span: kind_of(Time)) # [S6.16] partition-prune hint
    end

    # [INF.26] Чисельник SLO рахує РЕЗУЛЬТАТ, не виклик — і пін тут навмисно ПАРНИЙ.
    # Доти інкремент стояв одразу за сервісом і стверджував лише «не кинуло винятку»,
    # тож панель «Money-Path Success Rate» була структурно приліплена до 1.0. Один
    # приклад цього не тримає: «рахує на broadcast'і» лишився б зеленим і на старому
    # безумовному інкременті. Дискримінатором є ДРУГИЙ приклад — той, де сервіс
    # повертає МОВЧКИ (KYC-фільтр · SEC.13 · ARCH.62 circuit · ambiguous-ескалація),
    # і лічильник СТОЯТЬ мусить.
    it "рахує виплату лише коли мінт справді пішов у мемпул (status→sent)" do
      allow(BlockchainMintingService).to receive(:call) do |tx_id, **|
        BlockchainTransaction.find(tx_id).mark_as_sent!("0x" + "cd" * 32)
      end
      counter = SilkenNet::Metrics::INSURANCE_PAYOUT_SUCCESS_TOTAL
      before_count = counter.get.to_i

      described_class.new.perform(insurance.id)

      expect(counter.get.to_i).to eq(before_count + 1)
    end

    it "НЕ рухає чисельник, коли сервіс повернувся мовчки (tx лишився :pending)" do
      # Дефолтний стаб `BlockchainMintingService.call` — no-op, тобто рівно та тиха
      # відмова, на якій дефект і був вибірковим: про неї нема кому доповісти.
      counter = SilkenNet::Metrics::INSURANCE_PAYOUT_SUCCESS_TOTAL
      before_count = counter.get.to_i

      described_class.new.perform(insurance.id)

      expect(counter.get.to_i).to eq(before_count)
      expect(BlockchainTransaction.last.status).to eq("pending")
    end

    context "with the INS.2 reserve gate" do
      it "holds the payout in manual_review WITHOUT minting when the reserve gate fails" do
        allow(Insurance::ReserveGate).to receive(:call).and_return(
          Insurance::ReserveGate::Result.new(ok: false, reason: :aggregate_cap, detail: "over cap")
        )

        expect { described_class.new.perform(insurance.id) }
          .to change { EwsAlert.where(alert_type: :system_fault).count }.by(1)

        expect(BlockchainMintingService).not_to have_received(:call)
        expect(insurance.reload.blockchain_transaction.status).to eq("manual_review")
      end

      # [ARCH.82] ⚖️ founder 2026-08-14: HOLD дістає Grafana-канал, і це ЄДИНИЙ канал —
      # сам EwsAlert безкластерний, тож `Organization has_many :ews_alerts, through:
      # :clusters` (INNER JOIN) не показує його на жодній орг-поверхні. Лічильник має
      # мітку причини, бо `manual_review`-gauge, куди HOLD теж потрапляє, не розрізняє
      # казначейську політику від double-spend-лімбо, а відповіді на них протилежні.
      it "рахує HOLD окремою метрикою з міткою причини (ЄДИНИЙ канал до оператора)" do
        allow(Insurance::ReserveGate).to receive(:call).and_return(
          Insurance::ReserveGate::Result.new(ok: false, reason: :reserve_inadequate, detail: "under reserve")
        )
        counter = SilkenNet::Metrics::INSURANCE_RESERVE_HOLD_TOTAL
        labels = { reason: "reserve_inadequate" }
        before_count = counter.get(labels: labels).to_i

        described_class.new.perform(insurance.id)

        expect(counter.get(labels: labels).to_i).to eq(before_count + 1)
      end

      it "НЕ рахує HOLD на transient RPC-збої — той шлях іде в Sidekiq-retry, не в політику" do
        # Ліхтар проти over-broad лічильника: :eval_error реврайзиться вище по коду й
        # ніколи не є присудом gate'а. Порахувати його означало б підняти оператора на
        # мережевий збій під виглядом зупиненої емісії.
        allow(Insurance::ReserveGate).to receive(:call).and_return(
          Insurance::ReserveGate::Result.new(ok: false, reason: :eval_error, detail: "RPC down")
        )
        counter = SilkenNet::Metrics::INSURANCE_RESERVE_HOLD_TOTAL
        before_count = counter.get(labels: { reason: "eval_error" }).to_i

        # Той шлях RAISE-иться раніше за лічильник — і саме це робить пін подвійним:
        # він тримає і напрямок обробки, і мовчання метрики.
        expect { described_class.new.perform(insurance.id) }
          .to raise_error(/transient RPC error/)

        expect(counter.get(labels: { reason: "eval_error" }).to_i).to eq(before_count)
      end

      it "proceeds to mint when the reserve gate passes" do
        allow(Insurance::ReserveGate).to receive(:call).and_return(
          Insurance::ReserveGate::Result.new(ok: true, reason: :ok)
        )

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).to have_received(:call)
      end

      it "raises on a transient reserve-gate RPC error (Sidekiq retry, not permanent manual_review park)" do
        allow(Insurance::ReserveGate).to receive(:call).and_return(
          Insurance::ReserveGate::Result.new(ok: false, reason: :eval_error, detail: "RPC down")
        )

        expect { described_class.new.perform(insurance.id) }.to raise_error(/reserve-gate transient/)
        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    it "returns nil for non-existent insurance" do
      expect(described_class.new.perform(-1)).to be_nil
    end

    it "skips non-triggered insurance" do
      active_insurance = create(:parametric_insurance, cluster: cluster, organization: organization, status: :active)

      described_class.new.perform(active_insurance.id)

      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "skips already paid insurance" do
      insurance.update!(status: :paid, paid_at: Time.current)

      described_class.new.perform(insurance.id)

      expect(BlockchainMintingService).not_to have_received(:call)
    end

    context "with satellite verification guard (Cosmic Eye)" do
      before do
        silence_broadcasts!(:alert_notify, :alert_new, :alert_update)
        silence_side_effects!(:satellite_verification)
      end

      it "skips payout when unverified fire alerts exist in cluster" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :unverified)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "skips payout when inconclusive fire alerts exist in cluster" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "proceeds with payout when fire alerts are satellite_verified" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)
      end

      # [INS.1] rejected_fraud = dClimate ВІДХИЛИВ FIRE-подію (заявлено пожежу, супутник вогню не бачить) —
      # ВІДМОВА, не confirmation → HOLD. Після peril-чесного роутингу не-пожежні перили НЕ доходять до
      # rejected_fraud (вони → :inconclusive); тест тримає саме fire-rejected → hold інваріант.
      it "holds payout when the only independent alert is satellite_rejected_fraud (not verified)" do
        confirmation.destroy # прибираємо global verified
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :rejected_fraud)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      # [INS.1 dual-trigger] Без незалежного fire/drought-підтвердження (Trigger-2) — ТРИМАЄМО,
      # навіть якщо є інші алерти. Це й є замок проти basis-risk (не платимо за нашим сигналом).
      it "holds payout when no independent fire/drought confirmation exists (basis-risk guard)" do
        confirmation.destroy
        create(:ews_alert, cluster: cluster, tree: tree, alert_type: :vandalism_breach)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "logs satellite pending message for unverified alerts" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :unverified)
        allow(Rails.logger).to receive(:info).with(/\[Insurance\] Виплата відкладена — очікуємо незалежну верифікацію для кластера ##{cluster.id}/)

        described_class.new.perform(insurance.id)

        expect(Rails.logger).to have_received(:info).with(/\[Insurance\] Виплата відкладена — очікуємо незалежну верифікацію для кластера ##{cluster.id}/)
      end

      it "logs manual audit message for inconclusive alerts" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive)
        allow(Rails.logger).to receive(:warn).with(/\[Insurance\] Виплата заблокована — потрібен ручний DAO \/ Field-Audit для кластера ##{cluster.id}/)

        described_class.new.perform(insurance.id)

        expect(Rails.logger).to have_received(:warn).with(/\[Insurance\] Виплата заблокована — потрібен ручний DAO \/ Field-Audit для кластера ##{cluster.id}/)
      end

      # [INS.1] Не-пожежний перил (посуха) → :inconclusive (Field Audit) → HOLD, консистентно з fire.
      # [ARCH.102] Перилів у whitelist'і воркера ДВА (fire/drought): insect знято разом із
      # вердиктом, якого нічим виміряти; chainsaw сюди не належить — він не страховий.
      it "holds payout when the only independent alert is severe_drought at :inconclusive" do
        confirmation.destroy
        create(:ews_alert, cluster: cluster, tree: tree, alert_type: :severe_drought, severity: :critical, satellite_status: :inconclusive)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      # 🔴 [INS.1 cross-peril] Гейт мусить питати про перил ЦЬОГО поліса, а не «чи є в
      # кластері хоч якийсь verified-алерт». Доти фільтр брав ОБИДВА перил-типи, тож поліс
      # від ПОСУХИ платився б за доказом ПОЖЕЖІ — а `:verified` пише рівно один сайт у
      # дереві, і він fire-only. Це дзеркало ратифікованого peril-honest routing: посуху
      # не таврують фраудом (`05_05 §4`) — і так само не оплачують чужим доказом.
      context "when the policy's peril differs from the confirmed one" do
        let(:drought_policy) do
          create(:parametric_insurance, :drought, cluster: cluster, status: :triggered,
                                                  payout_amount: 100, token_type: :carbon_coin)
        end

        it "holds a drought policy even when a FIRE alert is satellite_verified" do
          confirmation.destroy
          create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified)

          described_class.new.perform(drought_policy.id)

          expect(BlockchainMintingService).not_to have_received(:call)
          expect(drought_policy.reload).to be_status_triggered
        end

        # Позитивна половина, без якої попередній приклад зелений і на гейті, що тримає
        # ВСЕ: fire-поліс на fire-доказі мусить проходити далі.
        it "still pays a fire policy on its own verified fire alert" do
          create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified)

          expect {
            described_class.new.perform(insurance.id)
          }.to change(BlockchainTransaction, :count).by(1)
        end
      end
    end

    it "returns early when no trees exist in cluster" do
      # Порожній кластер без дерев, але з незалежним підтвердженням (щоб дійти до wallet-перевірки).
      empty_cluster = create(:cluster, organization: organization)
      empty_insurance = create(:parametric_insurance, :triggered, cluster: empty_cluster, organization: organization)
      create(:ews_alert, :fire, cluster: empty_cluster, tree: nil, satellite_status: :verified)

      allow(Rails.logger).to receive(:error).with(/без жодного дерева/)

      described_class.new.perform(empty_insurance.id)

      expect(Rails.logger).to have_received(:error).with(/без жодного дерева/)
      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "re-raises errors for Sidekiq retry" do
      allow(BlockchainMintingService).to receive(:call).and_raise(StandardError, "RPC error")

      expect {
        described_class.new.perform(insurance.id)
      }.to raise_error(StandardError, "RPC error")
    end

    context "when insurance status changes between lock and check (pessimistic lock re-check)" do
      it "skips payout when insurance is no longer triggered after lock" do
        # Simulate: insurance.lock! succeeds, but then status changes to :paid
        allow_any_instance_of(ParametricInsurance).to receive(:lock!) do |ins|
          ins.update_columns(status: :paid, paid_at: Time.current)
        end

        expect {
          described_class.new.perform(insurance.id)
        }.not_to change(BlockchainTransaction, :count)

        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    context "when ActiveRecord::RecordNotFound is raised" do
      it "rescues RecordNotFound and logs a warning" do
        allow(ParametricInsurance).to receive_messages(includes: ParametricInsurance, find_by: insurance)
        allow(insurance).to receive(:status_triggered?).and_return(true)
        allow(insurance).to receive(:lock!).and_raise(ActiveRecord::RecordNotFound)

        allow(Rails.logger).to receive(:warn).with(/зник із Матриці/)

        expect {
          described_class.new.perform(insurance.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:warn).with(/зник із Матриці/)
      end
    end

    context "when tx is nil (transaction block exits early via next)" do
      it "does not call BlockchainMintingService" do
        allow_any_instance_of(ParametricInsurance).to receive(:lock!) do |ins|
          ins.update_columns(status: :paid)
        end

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    context "when recovering an orphaned non-:pending internal-mint TX (ARCH.51 double-mint guard)" do
      it "escalates to manual_review and does NOT re-mint a recovered :sent tx" do
        # recovery path: insurance already :paid, an orphaned :sent mint TX from a prior attempt.
        insurance.update_columns(status: "paid", paid_at: Time.current)
        orphan = insurance.create_blockchain_transaction!(
          wallet: wallet, amount: insurance.payout_amount, token_type: insurance.token_type,
          to_address: organization.crypto_public_address, status: :sent,
          tx_hash: "0x#{SecureRandom.hex(32)}"
        )

        described_class.new.perform(insurance.id)

        # the broken guard would have RE-MINTED (BlockchainMintingService excludes only :confirmed).
        expect(BlockchainMintingService).not_to have_received(:call)
        expect(orphan.reload.status).to eq("manual_review")
      end

      it "skips a recovered :confirmed tx (no re-mint, no escalate — already terminal)" do
        insurance.update_columns(status: "paid", paid_at: Time.current)
        orphan = insurance.create_blockchain_transaction!(
          wallet: wallet, amount: insurance.payout_amount, token_type: insurance.token_type,
          to_address: organization.crypto_public_address, status: :confirmed,
          tx_hash: "0x#{SecureRandom.hex(32)}"
        )

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
        expect(orphan.reload.status).to eq("confirmed")
      end

      # [P1-2] recovered + :manual_review Etherisc tx must NOT re-claim (age-unbounded unsettled_within
      # finds it) — else double-pay-exposure + mark_as_sent! whiny-raise cycles claim!.
      it "does NOT re-claim a recovered :manual_review Etherisc tx" do
        claim = instance_double(Etherisc::ClaimService, claim!: "0x#{SecureRandom.hex(32)}")
        allow(Etherisc::ClaimService).to receive(:new).and_return(claim)
        allow(BlockchainConfirmationWorker).to receive(:perform_in)
        etherisc = create(:parametric_insurance, :triggered,
                          cluster: cluster, organization: organization, etherisc_policy_id: "42")
        etherisc.update_columns(status: "paid", paid_at: Time.current)
        orphan = etherisc.create_blockchain_transaction!(
          wallet: wallet, amount: etherisc.payout_amount, token_type: etherisc.token_type,
          to_address: organization.crypto_public_address, status: :manual_review,
          tx_hash: "0x#{SecureRandom.hex(32)}"
        )

        expect { described_class.new.perform(etherisc.id) }.not_to raise_error
        expect(claim).not_to have_received(:claim!)
        expect(orphan.reload.status).to eq("manual_review")
      end
    end

    context "when no active trees exist but non-active trees have wallets" do
      it "falls back to non-active tree wallet for audit" do
        # Remove the active tree so no active trees exist
        tree.update!(status: :removed)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.wallet.tree).to eq(tree)
        expect(tx.notes).to include("Страхове відшкодування")
      end
    end

    # =========================================================================
    # SIDEKIQ CONFIGURATION
    # =========================================================================
    it "uses critical queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("critical")
    end

    it "retries 10 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(10)
    end

    # =========================================================================
    # SATELLITE VERIFICATION — MULTIPLE ALERT TYPES
    # =========================================================================
    context "with mixed alert types (fire + vandalism)" do
      before do
        silence_broadcasts!(:alert_notify, :alert_new, :alert_update)
        silence_side_effects!(:satellite_verification)
      end

      it "blocks payout only when fire/drought alerts are unverified" do
        # Non-fire alert — should NOT block
        create(:ews_alert, cluster: cluster, tree: tree, alert_type: :vandalism_breach, severity: :critical)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)
      end

      it "blocks payout when severe_drought alert is unverified" do
        create(:ews_alert, cluster: cluster, tree: tree, alert_type: :severe_drought,
               severity: :critical, satellite_status: :unverified)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    context "when insurance uses Etherisc DIP" do
      let(:etherisc_insurance) do
        create(:parametric_insurance, :triggered,
               cluster: cluster, organization: organization,
               etherisc_policy_id: "42")
      end
      let(:fake_tx_hash) { "0x" + "fa" * 32 }

      before do
        claim_service_instance = instance_double(Etherisc::ClaimService, claim!: fake_tx_hash)
        allow(Etherisc::ClaimService).to receive(:new).and_return(claim_service_instance)
        allow(BlockchainConfirmationWorker).to receive(:perform_in)
      end

      it "calls Etherisc::ClaimService instead of BlockchainMintingService" do
        described_class.new.perform(etherisc_insurance.id)

        expect(Etherisc::ClaimService).to have_received(:new).with(etherisc_insurance)
        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "updates BlockchainTransaction with tx_hash and sent status" do
        described_class.new.perform(etherisc_insurance.id)

        tx = BlockchainTransaction.last
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_tx_hash)
      end

      it "enqueues BlockchainConfirmationWorker for receipt polling" do
        described_class.new.perform(etherisc_insurance.id)

        expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash, kind_of(String)) # [ARCH.52] +created_at
      end

      context "when an orphaned :pending Etherisc tx is recovered (claim may already be sent) [ARCH.45]" do
        let!(:orphaned_tx) do
          etherisc_insurance.update!(status: :paid, paid_at: Time.current)
          create(:blockchain_transaction,
                 wallet: wallet,
                 amount: etherisc_insurance.payout_amount,
                 token_type: :carbon_coin,
                 to_address: organization.crypto_public_address,
                 status: :pending,
                 notes: "Страхове відшкодування ##{etherisc_insurance.id}.")
        end

        before do
          # Associate the tx with the insurance
          allow(ParametricInsurance).to receive(:includes).and_return(ParametricInsurance)
          allow(ParametricInsurance).to receive(:find_by).with(id: etherisc_insurance.id).and_return(etherisc_insurance)
          allow(etherisc_insurance).to receive_messages(blockchain_transaction: orphaned_tx, uses_etherisc?: true, cluster: cluster)
        end

        it "escalates to manual_review WITHOUT re-claiming (double-pay guard)" do
          # [ARCH.45] Сліпий re-claim тут = можлива подвійна зовнішня USDC-виплата (claim! міг
          # пройти до краху tx.update). Замість повтору — manual_review для ручної звірки DIP.
          allow(Etherisc::ClaimService).to receive(:new)

          described_class.new.perform(etherisc_insurance.id)

          expect(Etherisc::ClaimService).not_to have_received(:new)

          expect(orphaned_tx.reload.status).to eq("manual_review")
        end
      end

      context "when the associated tx is already sent (idempotency guard, §P1)" do
        let!(:sent_tx) do
          etherisc_insurance.update!(status: :paid, paid_at: Time.current)
          create(:blockchain_transaction,
                 wallet: wallet,
                 amount: etherisc_insurance.payout_amount,
                 token_type: :carbon_coin,
                 to_address: organization.crypto_public_address,
                 status: :sent,
                 tx_hash: fake_tx_hash,
                 notes: "Страхове відшкодування ##{etherisc_insurance.id}.")
        end

        before do
          allow(ParametricInsurance).to receive(:includes).and_return(ParametricInsurance)
          allow(ParametricInsurance).to receive(:find_by).with(id: etherisc_insurance.id).and_return(etherisc_insurance)
          allow(etherisc_insurance).to receive_messages(blockchain_transaction: sent_tx, uses_etherisc?: true, cluster: cluster)
        end

        it "does not re-submit the Etherisc claim" do
          described_class.new.perform(etherisc_insurance.id)

          expect(Etherisc::ClaimService).not_to have_received(:new)
        end

        it "still enqueues confirmation for the existing tx_hash" do
          described_class.new.perform(etherisc_insurance.id)

          expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash, kind_of(String)) # [ARCH.52] +created_at
        end
      end
    end
  end
end
