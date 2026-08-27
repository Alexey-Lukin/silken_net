# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransaction, type: :model do
  describe "validations" do
    it "requires amount to be present and positive" do
      tx = build(:blockchain_transaction, amount: nil)
      expect(tx).not_to be_valid
      expect(tx.errors[:amount]).to be_present
    end

    # 🔴 [ARCH.95] Валідація існує рівно заради ГУЧНОЇ відмови — а сам момент її
    # спрацювання не виконувався в сюїті жодного разу (виміряно branch-coverage'ом:
    # непокритою була гілка «маркер слешу є, напрямок не burn»). Тобто гард, чия
    # єдина робота — не дати тихо завищити емісію, стояв недоведеним: зняття
    # `errors.add` лишалось зеленим. Ціна промаху названа в самій моделі — напрямок
    # годує `net_minted_supply`, а той годує L1-якір і базу розміру спалення.
    it "відхиляє slash-інтент, що не несе напрямку :burn (гард ARCH.95 справді кусає)" do
      tx = build(:blockchain_transaction,
                 sourceable: create(:naas_contract), direction: :mint)

      expect(tx).not_to be_valid
      expect(tx.errors[:direction].join).to include("ARCH.95")
    end

    it "той самий рядок із напрямком :burn валідний — гард не ширший за свій предмет" do
      tx = build(:blockchain_transaction,
                 sourceable: create(:naas_contract), direction: :burn)

      expect(tx).to be_valid
    end

    it "rejects zero amount" do
      tx = build(:blockchain_transaction, amount: 0)
      expect(tx).not_to be_valid
    end

    it "requires a valid 0x address" do
      tx = build(:blockchain_transaction, to_address: "invalid")
      expect(tx).not_to be_valid
      expect(tx.errors[:to_address]).to be_present
    end

    it "requires tx_hash when status is sent" do
      tx = build(:blockchain_transaction, status: :sent, tx_hash: nil)
      expect(tx).not_to be_valid
      expect(tx.errors[:tx_hash]).to be_present
    end

    it "requires tx_hash when status is confirmed" do
      tx = build(:blockchain_transaction, status: :confirmed, tx_hash: nil)
      expect(tx).not_to be_valid
    end

    it "allows nil gas_price" do
      tx = build(:blockchain_transaction, gas_price: nil)
      expect(tx).to be_valid
    end

    it "rejects negative gas_price" do
      tx = build(:blockchain_transaction, gas_price: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:gas_price]).to be_present
    end

    it "rejects negative gas_used" do
      tx = build(:blockchain_transaction, gas_used: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:gas_used]).to be_present
    end

    it "rejects zero block_number" do
      tx = build(:blockchain_transaction, block_number: 0)
      expect(tx).not_to be_valid
      expect(tx.errors[:block_number]).to be_present
    end

    it "allows positive block_number" do
      tx = build(:blockchain_transaction, block_number: 12_345_678)
      expect(tx).to be_valid
    end

    it "rejects negative nonce" do
      tx = build(:blockchain_transaction, nonce: -1)
      expect(tx).not_to be_valid
      expect(tx.errors[:nonce]).to be_present
    end

    it "allows zero nonce (first transaction)" do
      tx = build(:blockchain_transaction, nonce: 0)
      expect(tx).to be_valid
    end
  end

  describe "#mark_as_sent!" do
    it "sets tx_hash, status, and sent_at" do
      tx = create(:blockchain_transaction, status: :processing, tx_hash: nil)
      hash = "0x" + SecureRandom.hex(32)

      freeze_time do
        tx.mark_as_sent!(hash)
        tx.reload

        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(hash)
        expect(tx.sent_at).to be_within(1.second).of(Time.current)
        expect(tx.error_message).to be_nil
      end
    end
  end

  describe "#confirm!" do
    it "sets confirmed status and confirmed_at timestamp" do
      tx = create(:blockchain_transaction, status: :sent)

      freeze_time do
        tx.confirm!
        tx.reload

        expect(tx.status).to eq("confirmed")
        expect(tx.confirmed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "accepts block_number for reorg protection" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!(54_321_000)
      tx.reload

      expect(tx.block_number).to eq(54_321_000)
    end

    it "accepts gas_cost for financial reporting" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!(54_321_000, 21_000)
      tx.reload

      expect(tx.block_number).to eq(54_321_000)
      expect(tx.gas_used).to eq(21_000)
    end

    it "works without arguments (backward compatible)" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.confirm!
      tx.reload

      expect(tx.status).to eq("confirmed")
      expect(tx.block_number).to be_nil
      expect(tx.gas_used).to be_nil
    end
  end

  describe "#fail!" do
    it "sets failed status and error message" do
      tx = create(:blockchain_transaction, status: :sent)
      tx.fail!("RPC timeout")
      tx.reload

      expect(tx.status).to eq("failed")
      expect(tx.error_message).to eq("RPC timeout")
    end

    it "truncates long error messages to 500 characters" do
      tx = create(:blockchain_transaction, status: :sent)
      long_message = "x" * 1000
      tx.fail!(long_message)
      tx.reload

      expect(tx.error_message.length).to be <= 500
    end
  end

  describe "#explorer_url" do
    it "returns polygonscan URL when tx_hash is present" do
      tx = build(:blockchain_transaction, tx_hash: "0xabc123")
      expect(tx.explorer_url).to eq("https://polygonscan.com/tx/0xabc123")
    end

    it "returns nil when tx_hash is absent" do
      tx = build(:blockchain_transaction, tx_hash: nil, status: :pending)
      expect(tx.explorer_url).to be_nil
    end
  end

  describe "#polygonscan_url" do
    it "is an alias for explorer_url" do
      tx = build(:blockchain_transaction, tx_hash: "0xdef456")
      expect(tx.polygonscan_url).to eq(tx.explorer_url)
    end
  end

  describe "multichain support" do
    it "defaults blockchain_network to evm" do
      tx = create(:blockchain_transaction)
      expect(tx.blockchain_network).to eq("evm")
    end

    it "validates blockchain_network inclusion" do
      tx = build(:blockchain_transaction)
      tx.blockchain_network = "invalid_chain"
      expect(tx).not_to be_valid
      expect(tx.errors[:blockchain_network]).to be_present
    end

    it "accepts solana as blockchain_network" do
      tx = build(:blockchain_transaction,
        blockchain_network: "solana",
        to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV"
      )
      expect(tx).to be_valid
    end

    describe "#solana_network?" do
      it "returns true for solana transactions" do
        tx = build(:blockchain_transaction, blockchain_network: "solana",
                   to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")
        expect(tx.solana_network?).to be true
      end

      it "returns false for evm transactions" do
        tx = build(:blockchain_transaction, blockchain_network: "evm")
        expect(tx.solana_network?).to be false
      end
    end

    describe "#explorer_url for solana" do
      it "returns Solana Explorer URL for solana transactions" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV",
          tx_hash: "solana:sim:abc123"
        )
        expect(tx.explorer_url).to eq("https://explorer.solana.com/tx/solana:sim:abc123?cluster=devnet")
      end

      it "returns Polygonscan URL for evm transactions" do
        tx = build(:blockchain_transaction, tx_hash: "0xabc123", blockchain_network: "evm")
        expect(tx.explorer_url).to eq("https://polygonscan.com/tx/0xabc123")
      end
    end

    describe "Solana address validation" do
      it "validates Base58 format for solana network" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "invalid!address"
        )
        expect(tx).not_to be_valid
        expect(tx.errors[:to_address]).to be_present
      end

      it "rejects EVM address format for solana network" do
        tx = build(:blockchain_transaction,
          blockchain_network: "solana",
          to_address: "0x1234567890abcdef1234567890abcdef12345678"
        )
        expect(tx).not_to be_valid
      end
    end

    describe "#explorer_url for celo" do
      it "returns Celo Explorer URL for celo transactions" do
        tx = build(:blockchain_transaction,
          blockchain_network: "celo",
          to_address: "0x" + "a" * 40,
          tx_hash: "0xcelo123"
        )
        expect(tx.explorer_url).to eq("https://explorer.celo.org/alfajores/tx/0xcelo123")
      end
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:tx) { create(:blockchain_transaction, status: :pending, tx_hash: nil) }

    describe "initial state" do
      it "starts as pending" do
        expect(build(:blockchain_transaction, status: :pending)).to be_pending
      end
    end

    describe "#process!" do
      it "transitions from pending to processing" do
        tx.process!
        expect(tx.reload).to be_processing
      end

      it "rejects transition from confirmed" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.process! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#mark_as_sent!" do
      it "transitions from pending to sent and sets tx_hash + sent_at" do
        freeze_time do
          tx.mark_as_sent!("0xabc123")
          tx.reload
          expect(tx).to be_sent
          expect(tx.tx_hash).to eq("0xabc123")
          expect(tx.sent_at).to be_within(1.second).of(Time.current)
          expect(tx.error_message).to be_nil
        end
      end

      it "transitions from processing to sent" do
        tx.update_columns(status: described_class.statuses[:processing])
        tx.reload
        tx.mark_as_sent!("0xdef456")
        expect(tx.reload).to be_sent
      end

      it "rejects transition from confirmed" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.mark_as_sent!("0x1") }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#confirm!" do
      it "transitions from sent to confirmed and sets block_number + gas_used" do
        sent_tx = create(:blockchain_transaction, status: :sent)
        freeze_time do
          sent_tx.confirm!(42_000, 21_000)
          sent_tx.reload
          expect(sent_tx).to be_confirmed
          expect(sent_tx.block_number).to eq(42_000)
          expect(sent_tx.gas_used).to eq(21_000)
          expect(sent_tx.confirmed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "works without arguments and preserves existing values" do
        sent_tx = create(:blockchain_transaction, status: :sent, block_number: 100, gas_used: 50)
        sent_tx.confirm!
        sent_tx.reload
        expect(sent_tx).to be_confirmed
        expect(sent_tx.block_number).to eq(100)
        expect(sent_tx.gas_used).to eq(50)
      end

      it "updates only provided params and preserves nil ones" do
        sent_tx = create(:blockchain_transaction, status: :sent, block_number: 100, gas_used: 50)
        sent_tx.confirm!(200, nil)
        sent_tx.reload
        expect(sent_tx).to be_confirmed
        expect(sent_tx.block_number).to eq(200)
        expect(sent_tx.gas_used).to eq(50)
      end

      it "rejects transition from pending" do
        expect { tx.confirm! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#fail!" do
      it "transitions from pending to failed and sets error_message" do
        allow(Rails.logger).to receive(:error)
        tx.fail!("EVM revert")
        tx.reload
        expect(tx).to be_failed
        expect(tx.error_message).to eq("EVM revert")
      end

      it "truncates long error messages to 500 chars" do
        allow(Rails.logger).to receive(:error)
        long_reason = "x" * 600
        tx.fail!(long_reason)
        expect(tx.reload.error_message.length).to be <= 500
      end

      it "can fail from sent state" do
        allow(Rails.logger).to receive(:error)
        sent_tx = create(:blockchain_transaction, status: :sent)
        sent_tx.fail!("timeout")
        expect(sent_tx.reload).to be_failed
      end

      it "rejects transition from confirmed (blockchain finality)" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.fail!("error") }.to raise_error(AASM::InvalidTransition)
      end

      it "logs the failure" do
        allow(Rails.logger).to receive(:error).with(/провалилася/)
        tx.fail!("revert")

        expect(Rails.logger).to have_received(:error).with(/провалилася/)
      end

      # [M2/ARCH.45] fail! must release the growth_points a mint-tx locked, else the forester's
      # balance is frozen forever (ConfirmationWorker revert-branch does a bare fail!).
      describe "locked_points release on fail" do
        it "releases the wallet's locked_balance for a mint-tx (locked_points present)" do
          allow(Rails.logger).to receive(:error)
          wallet = create(:wallet, balance: 50_000, locked_balance: 10_000)
          mint_tx = create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: 10_000)

          expect { mint_tx.fail!("EVM revert") }.to change { wallet.reload.locked_balance }.from(10_000).to(0)
        end

        it "does NOT touch locked_balance for a slash/audit tx (locked_points nil)" do
          allow(Rails.logger).to receive(:error)
          wallet = create(:wallet, balance: 50_000, locked_balance: 10_000)
          slash_tx = create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: nil)

          expect { slash_tx.fail!("slash revert") }.not_to change { wallet.reload.locked_balance }
        end

        it "does NOT double-release on a repeated fail! (failed→failed retry)" do
          allow(Rails.logger).to receive(:error)
          wallet = create(:wallet, balance: 50_000, locked_balance: 10_000)
          mint_tx = create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: 10_000)
          mint_tx.fail!("first revert")

          expect { mint_tx.fail!("retry revert") }.not_to change { wallet.reload.locked_balance }
          expect(wallet.reload.locked_balance).to eq(0)
        end

        it "clamps release to the wallet's current locked_balance (partial rollback already ran)" do
          allow(Rails.logger).to receive(:error)
          wallet = create(:wallet, balance: 50_000, locked_balance: 3_000)
          mint_tx = create(:blockchain_transaction, wallet: wallet, status: :sent, locked_points: 10_000)

          expect { mint_tx.fail!("revert") }.to change { wallet.reload.locked_balance }.from(3_000).to(0)
        end

        it "no-ops safely when locked_points present but wallet is gone (return unless wallet)" do
          allow(Rails.logger).to receive(:error)
          tx = create(:blockchain_transaction, status: :sent, locked_points: 10_000)
          allow(tx).to receive(:wallet).and_return(nil)

          expect { tx.fail!("revert") }.not_to raise_error
          expect(tx.reload).to be_failed
        end
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions" do
        expect(tx.may_process?).to be true
        expect(tx.may_mark_as_sent?).to be true
        expect(tx.may_confirm?).to be false
        expect(tx.may_fail?).to be true
        expect(tx.may_escalate_to_review?).to be true
      end
    end

    describe "#escalate_to_review!" do
      it "transitions from pending to manual_review with reason" do
        allow(Rails.logger).to receive(:warn)
        tx.escalate_to_review!("tx_hash exists but receipt unknown")
        tx.reload
        expect(tx).to be_manual_review
        expect(tx.error_message).to include("tx_hash exists")
      end

      it "transitions from sent to manual_review" do
        allow(Rails.logger).to receive(:warn)
        sent_tx = create(:blockchain_transaction, status: :sent)
        sent_tx.escalate_to_review!("RPC timeout during receipt check")
        expect(sent_tx.reload).to be_manual_review
      end

      it "rejects transition from confirmed (blockchain finality)" do
        confirmed_tx = create(:blockchain_transaction, status: :confirmed)
        expect { confirmed_tx.escalate_to_review!("test") }.to raise_error(AASM::InvalidTransition)
      end

      it "logs the escalation" do
        allow(Rails.logger).to receive(:warn) # [MRV.1] audit-skip теж warn-ить без oracle-юзера
        tx.escalate_to_review!("test reason")
        expect(Rails.logger).to have_received(:warn).with(/ручної перевірки/)
      end
    end
  end

  # =========================================================================
  # PARTITION-AWARE LOOKUPS
  # =========================================================================
  describe ".find_with_partition_pruning" do
    let!(:tx) { create(:blockchain_transaction) }

    it "finds transaction by id alone (backward compatible)" do
      found = described_class.find_with_partition_pruning(tx.id)
      expect(found).to eq(tx)
    end

    it "finds transaction by id + created_at Time object" do
      found = described_class.find_with_partition_pruning(tx.id, tx.created_at)
      expect(found).to eq(tx)
    end

    it "finds transaction by id + created_at ISO 8601 string" do
      found = described_class.find_with_partition_pruning(tx.id, tx.created_at.iso8601)
      expect(found).to eq(tx)
    end

    # [ARCH.92] `params[:created_at]` приходить із HTTP, тобто рядок може НЕ нести
    # суфікса зони — а голий `Time.iso8601` читав би зону ПРОЦЕСУ й зсував секундне
    # вікно, після чого `first!` кидає `RecordNotFound` ПОВЗ rescue нижче (той ловить
    # формат, не порожній результат). 🔴 Зсуваємо зону ЗАСТОСУНКУ, не процесу: на CI
    # процес уже UTC, тож приклад на ній був би зеленим і не доводив би нічого.
    it "reads a zone-less ISO in the APPLICATION zone, not the process zone" do
      naive = tx.created_at.utc.strftime("%Y-%m-%dT%H:%M:%S")

      Time.use_zone("Asia/Tokyo") do
        expect { described_class.find_with_partition_pruning(tx.id, naive) }
          .to raise_error(ActiveRecord::RecordNotFound)
      end

      # Контроль: під UTC-зоною застосунку той самий рядок знаходить запис.
      expect(described_class.find_with_partition_pruning(tx.id, naive)).to eq(tx)
    end

    it "falls back to an unpruned lookup on a date-only string" do
      # Без гарда `Time.zone.iso8601` прийняв би дату як північ і звузив вікно до
      # секунди навколо 00:00:00 — тобто RecordNotFound замість чесного fallback'у.
      expect(described_class.find_with_partition_pruning(tx.id, tx.created_at.strftime("%Y-%m-%d")))
        .to eq(tx)
    end

    it "raises RecordNotFound for non-existent id" do
      expect {
        described_class.find_with_partition_pruning(-1)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound when created_at doesn't match any partition" do
      expect {
        described_class.find_with_partition_pruning(tx.id, "2020-01-01T00:00:00Z")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "falls back to unscoped lookup with invalid ISO 8601 string" do
      found = described_class.find_with_partition_pruning(tx.id, "not-a-date")
      expect(found).to eq(tx)
    end

    # [S6.16 / PERF.1] Раніше цей шлях деградував МОВЧКИ, тоді як його близнюк на
    # `TelemetryLog` рахувався лічильником — саме та подія, заради якої лічильник
    # заводили, була невидима на грошовій моделі.
    describe "degraded-path accounting" do
      let(:counter) { SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL }

      it "counts a lookup with no created_at at all" do
        allow(counter).to receive(:increment).with(labels: { caller: "Spec:missing_created_at" })
        described_class.find_with_partition_pruning(tx.id, nil, metric_caller: "Spec")

        expect(counter).to have_received(:increment).with(labels: { caller: "Spec:missing_created_at" })
      end

      it "counts a lookup whose created_at cannot be parsed" do
        allow(counter).to receive(:increment).with(labels: { caller: "Spec:invalid_created_at" })
        described_class.find_with_partition_pruning(tx.id, "not-a-date", metric_caller: "Spec")

        expect(counter).to have_received(:increment).with(labels: { caller: "Spec:invalid_created_at" })
      end

      it "labels an undeclared caller rather than dropping the event" do
        allow(counter).to receive(:increment).with(labels: { caller: "undeclared:missing_created_at" })
        described_class.find_with_partition_pruning(tx.id)

        expect(counter).to have_received(:increment).with(labels: { caller: "undeclared:missing_created_at" })
      end

      it "stays silent on the pruned happy path" do
        allow(counter).to receive(:increment)
        described_class.find_with_partition_pruning(tx.id, tx.created_at, metric_caller: "Spec")

        expect(counter).not_to have_received(:increment)
      end
    end
  end

  # [S6.16 / PERF.1] SET-форма One-Home. Її НЕСУЧА властивість — не швидкість
  # (виміряти план у спеці нічого не варте), а те, що підказка НЕ міняє множину
  # рядків: інакше «оптимізація» тихо перевизначила б, які транзакції мінтяться.
  describe ".where_ids_pruned" do
    let(:wallet) { create(:wallet) }
    let!(:txs) { create_list(:blockchain_transaction, 3, wallet: wallet) }
    let(:ids) { txs.map(&:id) }
    let(:span) { txs.map(&:created_at) }

    it "returns exactly the same rows as the unpruned form" do
      expect(described_class.where_ids_pruned(ids, span).to_a)
        .to match_array(described_class.where(id: ids).to_a)
    end

    it "accepts a Range span as well as a list of timestamps" do
      as_range = described_class.where_ids_pruned(ids, span.min..span.max)
      expect(as_range.to_a).to match_array(txs)
    end

    # 🔴 Регресія, знайдена adversarial-ревю: `InsurancePayoutWorker` — ЄДИНИЙ
    # викликач, що передає СКАЛЯР (`tx.created_at`), і `Kernel#Array` розкладав
    # `TimeWithZone` на десять компонентів → `.min` кидав ArgumentError на кожній
    # внутрішній страховій виплаті. Жодна call-site-спека цього не бачила, бо всі
    # стабили сам сервіс, тож значення не доходило до коду, що на ньому падав.
    it "accepts a BARE timestamp — the form the only scalar caller passes" do
      one = txs.first
      expect(described_class.where_ids_pruned([ one.id ], one.created_at).to_a).to eq([ one ])
    end

    it "does not decompose a bare timestamp into its components" do
      expect(described_class.send(:partition_span_for, txs.first.created_at))
        .to eq(txs.first.created_at..txs.first.created_at)
    end

    it "is chainable — narrowing further still composes" do
      # Фабрика дефолтить `:confirmed`, тож звужувати треба ПО ІНШОМУ значенню —
      # інакше приклад «звузив» би до всіх трьох і був би зелений ні за що.
      txs.first.update_columns(status: described_class.statuses[:pending])
      expect(described_class.where_ids_pruned(ids, span).where(status: :pending).to_a)
        .to eq([ txs.first ])
    end

    it "degrades to an unpruned relation, and says so, when no span is given" do
      allow(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to receive(:increment).with(labels: { caller: "Spec:missing_span" })

      expect(described_class.where_ids_pruned(ids, nil, metric_caller: "Spec").to_a).to match_array(txs)

      expect(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to have_received(:increment).with(labels: { caller: "Spec:missing_span" })
    end

    it "treats an all-nil span as no span rather than as an empty window" do
      allow(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to receive(:increment).with(labels: { caller: "Spec:missing_span" })

      expect(described_class.where_ids_pruned(ids, [ nil, nil ], metric_caller: "Spec").to_a).to match_array(txs)

      expect(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to have_received(:increment).with(labels: { caller: "Spec:missing_span" })
    end

    # 🔴 [PERF.1] Порожній `ids` — це `WHERE 1=0`: деградації НЕ БУЛО, бо сканувати нема
    # чого. Лічильник там труїв саме ту панель, задля якої його заводили.
    it "does NOT count a degradation when there is nothing to scan" do
      allow(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to receive(:increment)

      expect(described_class.where_ids_pruned([], nil, metric_caller: "Spec").to_a).to be_empty

      expect(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .not_to have_received(:increment)
    end

    # 🔴 [PERF.1] Ексклюзивний Range, побудований із самих рядків, викидав би рядок із
    # максимальним `created_at` — і саме цю ідіому викликач природно скопіює, бо
    # `find_with_partition_pruning` за десять рядків звідси рахує вікно `time...time+1s`.
    it "normalises an EXCLUSIVE range — a hint must not drop the boundary row" do
      newest = txs.max_by(&:created_at)

      expect(described_class.where_ids_pruned(ids, span.min...span.max).to_a)
        .to include(newest)
    end

    # 🔴 [PERF.1] ЧАСТКОВИЙ nil — єдина форма, на якій ламався інваріант «підказка,
    # НІКОЛИ фільтр»: `.compact` давав `t..t`, тож рядок із невідомим часом ВИПАДАВ
    # би з набору. На money-таблиці це не повільніший запит, а недорахований результат.
    # ⚠️ Сьогодні такий вхід недосяжний (`created_at` у composite PK → NOT NULL), тож
    # приклад стереже ЛАТЕНТНУ міну — саме тому він тут, а не «коли знадобиться».
    it "degrades on a PARTIAL nil span instead of silently narrowing the window" do
      allow(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to receive(:increment).with(labels: { caller: "Spec:missing_span" })

      partial = [ txs.first.created_at, nil ]
      expect(described_class.where_ids_pruned(ids, partial, metric_caller: "Spec").to_a)
        .to match_array(txs)

      expect(SilkenNet::Metrics::BLOCKCHAIN_TRANSACTION_UNPRUNED_LOOKUPS_TOTAL)
        .to have_received(:increment).with(labels: { caller: "Spec:missing_span" })
    end
  end

  describe ".unsettled_within" do
    let(:wallet) { create(:wallet) }

    it "includes pending/sent within the window" do
      pending_tx = create(:blockchain_transaction, wallet: wallet, status: :pending, created_at: 30.minutes.ago)
      sent_tx    = create(:blockchain_transaction, wallet: wallet, status: :sent, created_at: 30.minutes.ago)
      expect(wallet.blockchain_transactions.unsettled_within(2.hours)).to include(pending_tx, sent_tx)
    end

    it "excludes pending/sent older than the window (partition-prune preserved)" do
      old_pending = create(:blockchain_transaction, wallet: wallet, status: :pending, created_at: 3.hours.ago)
      expect(wallet.blockchain_transactions.unsettled_within(2.hours)).not_to include(old_pending)
    end

    # [ARCH.45 fix — P0-1] The load-bearing regression: an ambiguous possibly-landed slash/payout
    # escalated to :manual_review must block re-fire FOREVER, not just within the window — else the
    # daily slash-cron / hourly Solana-payout re-fires days later → deterministic double-burn/double-pay.
    it "includes :manual_review regardless of age (age-unbounded)" do
      aged_review = create(:blockchain_transaction, wallet: wallet, status: :manual_review, created_at: 10.days.ago)
      expect(wallet.blockchain_transactions.unsettled_within(2.hours)).to include(aged_review)
    end

    it "excludes terminal states (confirmed/failed) at any age" do
      confirmed = create(:blockchain_transaction, wallet: wallet, status: :confirmed, created_at: 1.minute.ago)
      failed    = create(:blockchain_transaction, wallet: wallet, status: :failed, created_at: 1.minute.ago)
      expect(wallet.blockchain_transactions.unsettled_within(2.hours)).not_to include(confirmed, failed)
    end
  end

  # =========================================================================
  # REAL-TIME BROADCASTS
  # =========================================================================
  describe "broadcast_status_change" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_later_to)
    end

    it "broadcasts when status changes" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)
      tx.update_columns(status: described_class.statuses[:processing])
      tx.reload

      # Simulate an AASM transition that triggers after_update_commit
      tx.mark_as_sent!("0x" + SecureRandom.hex(32))

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_later_to).at_least(:once)
    end

    it "broadcasts to [wallet, :transactions] stream with dom_id target" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)
      tx.update_columns(status: described_class.statuses[:processing])
      tx.reload

      tx.mark_as_sent!("0x" + SecureRandom.hex(32))

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_later_to).with(
        [ tx.wallet, :transactions ],
        hash_including(target: "blockchain_transaction_#{tx.id}")
      )
    end

    it "does not broadcast when non-status fields change" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)
      tx.update!(notes: "Updated notes")

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_later_to)
    end

    it "triggers wallet balance update on confirmed status" do
      tx = create(:blockchain_transaction, status: :sent)
      wallet = tx.wallet

      allow(wallet).to receive(:broadcast_balance_update)
      allow(tx).to receive(:wallet).and_return(wallet)

      tx.confirm!

      expect(wallet).to have_received(:broadcast_balance_update)
    end

    it "triggers wallet balance update on failed status" do
      tx = create(:blockchain_transaction, status: :sent)
      wallet = tx.wallet

      allow(Rails.logger).to receive(:error)
      allow(wallet).to receive(:broadcast_balance_update)
      allow(tx).to receive(:wallet).and_return(wallet)

      tx.fail!("RPC timeout")

      expect(wallet).to have_received(:broadcast_balance_update)
    end

    it "skips broadcast when wallet is nil (slashing audit tx)" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)
      # Simulate orphan tx by nullifying wallet
      tx.update_columns(wallet_id: nil)
      tx.reload

      # Should not raise error even without a wallet
      expect { tx.update!(notes: "audit") }.not_to raise_error
    end

    context "when wallet is nil during status change" do
      it "does not broadcast" do
        tx = create(:blockchain_transaction, status: :sent)
        allow(tx).to receive(:wallet).and_return(nil)
        # Verify no broadcast occurs specifically because wallet is nil
        tx.send(:broadcast_status_change)

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_later_to)
      end
    end
  end

  # [UI.4] Поява транзакції — окремий тракт від зміни статусу: `after_update_commit`
  # створення не ловить, тож доти щойно намінтована транзакція не доїжджала до
  # відкритого леджера жодного разу. Цілі тут пінені ЛІТЕРАЛАМИ свідомо: код
  # обох боків ходить через `Wallets::Show`-константи, і якби спека брала ту саму
  # константу, координоване перейменування лишилось би зеленим (`04_04 §8.3`).
  describe "broadcast_new_transaction" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_later_to)
    end

    it "prepends the new row into the ledger of the owning wallet" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
        [ tx.wallet, :transactions ],
        hash_including(target: "transactions_ledger")
      )
    end

    it "carries the rendered row itself, not an empty frame" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to) do |_stream, **opts|
        expect(opts[:html]).to include(%(id="blockchain_transaction_#{tx.id}"))
      end
    end

    it "removes the empty-ledger placeholder in the same stream" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).with(
        [ tx.wallet, :transactions ],
        hash_including(target: "empty_ledger")
      )
    end

    # Прикраса екрана не сміє вбити money-шлях: виняток із `after_create_commit`
    # пролітає нагору з `create!` (у `commit_records` є `ensure`, але немає
    # `rescue`), а на трьох сайтах створення це коштувало б необоротно.
    it "never lets a broadcast failure escape into the money path" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to).and_raise(StandardError, "cable down")
      allow(Rails.logger).to receive(:warn)

      expect { create(:blockchain_transaction, status: :pending, tx_hash: nil) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/broadcast_new_transaction/)
    end

    context "when the transaction has no wallet (cluster-sourced audit row)" do
      # ⚠️ Назву звужено 2026-08-18: доти вона казала «broadcasts nothing at all», і
      # це перестало бути правдою — org-сигнал (нижче) такий рядок якраз ЛОВИТЬ, бо
      # він і є той рід рухів, заради якого сигнал заведено. Приклад стереже рівно
      # свою половину: у неіснуючий гаманцевий леджер нічого не штовхається.
      it "pushes no row into a wallet ledger it does not have" do
        tx = build(:blockchain_transaction)
        allow(tx).to receive(:wallet).and_return(nil)

        tx.send(:broadcast_new_transaction)

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_remove_to)
      end
    end
  end

  # 🔴 [UI.4] Резолюція власника — дім ОДИН, і він мусить відповідати рівно так, як
  # `for_organization`: інакше рядок, ВИДИМИЙ в аудит-списку, адресувався б у чужий
  # стрім або нікуди. Тут доти стояв `delegate :organization, to: :wallet` з обіцянкою
  # «може бути nil — тоді через cluster», якої делегат не виконував; нуль викликачів
  # означав, що обіцянку ніколи не перевіряла реальність.
  describe "#organization" do
    it "resolves through the wallet's own denormalized column" do
      tx = create(:blockchain_transaction)

      expect(tx.organization).to eq(tx.wallet.organization)
    end

    # Друга ланка — та, якої делегат не мав: колонка nullable і без бекфілу, тож
    # порожня вона не виняток, а звичайний стан для гаманця осиротілого кластера.
    it "falls back to the tree's cluster when the wallet column is blank" do
      tx = create(:blockchain_transaction)
      owner = tx.wallet.tree.cluster.organization
      tx.wallet.update_column(:organization_id, nil)
      tx.wallet.reload

      expect(owner).to be_present
      expect(tx.organization).to eq(owner)
    end

    # Третя ланка — рядки, заради яких ARCH.98 і розширював скоуп сторінки.
    it "resolves through its own cluster when there is no wallet at all" do
      cluster = create(:cluster)
      tx = create(:blockchain_transaction, wallet: nil, cluster: cluster)

      expect(tx.organization).to eq(cluster.organization)
    end
  end

  # 🔴 [UI.4] Org-сигнал ортогональний до гаманцевого тракту, і саме тому окремий:
  # обидва продюсери гаманцевого починаються з `return unless wallet`, тобто під
  # спільним гардом німими лишались НАЙМАТЕРІАЛЬНІШІ рухи — ті, що гаманця не мають
  # за побудовою. Екран, живий на дрібному й німий на великому, гірший за чесно
  # статичний: це «живість, що бреше».
  describe "broadcast_ledger_signal" do
    before { allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to) }

    def ledger_stream_for(organization)
      "blockchain_ledger_org_#{organization.id}_e#{organization.stream_epoch}"
    end

    it "signals the owning organization of a cluster-sourced row" do
      cluster = create(:cluster)

      create(:blockchain_transaction, wallet: nil, cluster: cluster)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with(ledger_stream_for(cluster.organization))
    end

    it "signals the owning organization of a wallet-backed row" do
      tx = create(:blockchain_transaction)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with(ledger_stream_for(tx.wallet.organization))
    end

    # Поява й зміна — два різні хуки, і другий потрібен окремо: `after_update_commit`
    # створення не ловить, а `after_create_commit` не ловить переходу. Один без
    # одного дає екран, що показує рядок і не показує його долі.
    it "signals again when the status moves" do
      tx = create(:blockchain_transaction, status: :pending, tx_hash: nil)
      tx.process!

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with(ledger_stream_for(tx.wallet.organization)).at_least(:twice)
    end

    # Осиротілий кластер (`clusters.organization_id` nullable) — реальний стан, і
    # `TurboStreams::Name.org` на `nil` кинув би `ArgumentError`. Гард робить цю
    # тишу СВІДОМОЮ: без нього рядок лишався б німим так само, лише вже без сліду.
    it "stays silent, and raises nothing, when the owner cannot be resolved" do
      tx = build(:blockchain_transaction)
      allow(tx).to receive(:organization).and_return(nil)

      expect { tx.send(:broadcast_ledger_signal) }.not_to raise_error
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_later_to)
    end

    # Та сама ізоляція, що на гаманцевому тракті: виняток із `after_*_commit`
    # пролітає нагору з `create!`, а всі пускачі цього хука — money-переходи.
    it "never lets a signal failure escape into the money path" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to).and_raise(StandardError, "cable down")
      allow(Rails.logger).to receive(:warn)

      expect { create(:blockchain_transaction) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/broadcast_ledger_signal/)
    end
  end

  # [MRV.1] Кожен money-перехід → tamper-evident AuditLog-ланцюг організації.
  describe "money audit-trail (MRV.1)" do
    let(:tx) { create(:blockchain_transaction, status: :pending, tx_hash: nil) }

    context "when the system actor exists" do
      let!(:oracle) do
        create(:user, :super_admin, email_address: "oracle.executioner@system.silken.net",
                                    first_name: "Oracle", last_name: "Executioner")
      end

      it "records the transition into the organization AuditLog chain" do
        expect { tx.process! }.to change { AuditLogWorker.jobs.size }.by(1)

        args = AuditLogWorker.jobs.last["args"].first
        expect(args["action"]).to eq("blockchain_tx_process")
        expect(args["organization_id"]).to eq(tx.wallet.organization_id)
        expect(args["auditable_type"]).to eq("BlockchainTransaction")
        expect(args["metadata"]).to include("from" => "pending", "to" => "processing")
      end

      # [ARCH.57] money/MRV-шлях лишається в IPFS-outbox-периметрі (archive=true),
      # на відміну від chain-only привілейованих дій.
      it "passes archive: true (money/MRV IPFS outbox half)" do
        tx.process!

        expect(AuditLogWorker.jobs.last["args"][1]).to be true
      end

      # [ARCH.57] Raw update!(status:) повз AASM (perform_safe_rollback-шлях) —
      # хук ловить, action = state-based fallback (event-імені нема).
      it "records a raw update!(status:) with the state-based fallback action" do
        tx.update!(status: :failed)

        attrs = AuditLogWorker.jobs.last["args"].first
        expect(attrs["action"]).to eq("blockchain_tx_to_failed")
        expect(attrs["metadata"]).to include("from" => "pending", "to" => "failed")
      end

      # [SEC.18 / DPIA M6] Цей рядок їде в ПУБЛІЧНИЙ незворотний IPFS-пін, а
      # `error_message` несе `e.message` довільного винятку. Пін цілиться саме в
      # ЗНАЧЕННЯ, не в наявність ключа: `have_key`-форма була б зелена й на сирому
      # тексті, тобто доводила б форму відповіді й нічого про витік.
      # 🔴 Мутація, що ламає САМЕ його: повернути `error: error_message` у
      # `record_money_audit_trail` — приклад мусить почервоніти з обох боків
      # (код не той І фрагмент тексту присутній).
      it "carries an error CODE in metadata, never the raw exception text" do
        tx.fail!("Ambiguous mint broadcast — https://user:s3cret@rpc.example/eth reverted")

        metadata = AuditLogWorker.jobs.last["args"].first["metadata"]

        expect(metadata["error"]).to eq("broadcast_ambiguous")
        expect(metadata["error"]).not_to include("s3cret")
        expect(metadata["error"]).not_to include("rpc.example")
        # Сирий текст лишається локально — діагностику не втрачено, її переадресовано.
        expect(tx.reload.error_message).to include("s3cret")
      end

      it "writes the no-text sentinel when there is no error at all" do
        tx.process!

        expect(AuditLogWorker.jobs.last["args"].first["metadata"]["error"]).to eq("none")
      end

      # [MRV.1/ARCH.12] Транзитивна печатка lineage: корінь вікна їде в AuditLog-ланцюг
      # (→ leaf0 наступного тижневого якоря); nil = чесний unsealed у bundle.
      it "carries telemetry_merkle_root in metadata (lineage transitive seal)" do
        tx.update!(telemetry_merkle_root: "ab" * 32)
        tx.process!

        args = AuditLogWorker.jobs.last["args"].first
        expect(args["metadata"]).to include("telemetry_merkle_root" => "ab" * 32)
      end
    end

    it "skips with a WARN when the system actor is absent (no chain owner)" do
      allow(Rails.logger).to receive(:warn)

      expect { tx.process! }.not_to change { AuditLogWorker.jobs.size }

      expect(Rails.logger).to have_received(:warn).with(/AuditLog skip/)
    end

    # [MRV.1] cluster-sourced money (celo reward + last-tree slash, wallet=nil) резолвить
    # org через cluster — інакше найматеріальніші рухи писали б нуль audit-row (compliance-діра).
    context "when the tx is cluster-sourced (wallet=nil, org via cluster)" do
      let!(:oracle) do
        create(:user, :super_admin, email_address: "oracle.executioner@system.silken.net",
                                    first_name: "Oracle", last_name: "Executioner")
      end
      let(:cluster) { create(:cluster) }
      let(:cluster_tx) do
        create(:blockchain_transaction, status: :pending, tx_hash: nil, wallet: nil, cluster: cluster)
      end

      it "records the transition attributed to the cluster's organization" do
        expect { cluster_tx.process! }.to change { AuditLogWorker.jobs.size }.by(1)
        expect(AuditLogWorker.jobs.last["args"].first["organization_id"]).to eq(cluster.organization_id)
      end
    end
  end

  # [ARCH.96] Резолюція кластера + чиста емісія. `for_cluster` має ДВІ гілки, бо
  # slash-інтент при мертвому кластері живе з `wallet: nil` (пастка останнього дерева)
  # і join через гаманець його не бачить — саме той рядок найбільше й роздував базу.
  describe "рахунок емісії кластера (ARCH.96)" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    def net_scc
      described_class.for_cluster(cluster.id).net_minted_supply(:carbon_coin)
    end

    it "рахує лише вказаний тип токена" do
      create(:blockchain_transaction, wallet: wallet, amount: 100, token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: wallet, amount: 40, token_type: :forest_coin, status: :confirmed)

      expect(net_scc).to eq(100)
    end

    it "не рахує незавершені транзакції" do
      create(:blockchain_transaction, wallet: wallet, amount: 100, token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: wallet, amount: 55, token_type: :carbon_coin, status: :pending)

      expect(net_scc).to eq(100)
    end

    it "віднімає спалення, прив'язане до САМОГО кластера (пастка останнього дерева)" do
      create(:blockchain_transaction, wallet: wallet, amount: 100, token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: nil, cluster: cluster, amount: 25, token_type: :carbon_coin,
                                      status: :confirmed, sourceable: naas_contract, direction: :burn)

      expect(net_scc).to eq(75)
    end
  end

  # [ARCH.103] Батчева форма того самого агрегату. Пінимо не «сума правильна» (це вже
  # тримає сусід вище), а рівно те, що поодинока форма НЕ доводить: обидві координати
  # кластера сходяться в ОДНУ групу, а порожній кластер не вигадує запису.
  describe ".net_minted_by_cluster (ARCH.103)" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: organization) }
    let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }
    let(:tree) { create(:tree, cluster: cluster) }
    let(:wallet) { tree.wallet || create(:wallet, tree: tree) }

    # 🔴 Дискримінатор усього методу: мінт приходить ЧЕРЕЗ ГАМАНЕЦЬ (wallet→tree→cluster),
    # а спалення «останнього дерева» — ПРЯМО через `cluster_id` із `wallet: nil`. Якби
    # `COALESCE` брав лише одну координату, друга гілка мовчки випала б, і база вийшла
    # б завищеною рівно на спалення — той самий дефект, що ARCH.96 закрив у `for_cluster`.
    it "зводить обидві координати кластера в одну групу (гаманцеву й пряму)" do
      create(:blockchain_transaction, wallet: wallet, cluster: nil, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: nil, cluster: cluster, amount: 30,
                                      token_type: :carbon_coin, status: :confirmed,
                                      sourceable: naas_contract, direction: :burn)

      expect(described_class.net_minted_by_cluster([ cluster.id ], :carbon_coin))
        .to eq(cluster.id => 70)
    end

    it "не вигадує запису кластерові без підтверджених рухів" do
      create(:blockchain_transaction, wallet: wallet, cluster: nil, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)

      result = described_class.net_minted_by_cluster([ cluster.id, other_cluster.id ], :carbon_coin)

      expect(result).to have_key(cluster.id)
      expect(result).not_to have_key(other_cluster.id), "порожнеча мусить лишитись порожнечею, а не нулем у хеші"
    end

    it "віддає порожній хеш на порожньому наборі, не б'ючи в БД" do
      expect(described_class.net_minted_by_cluster([], :carbon_coin)).to eq({})
    end

    # 🔴 Замок на ЛАТЕНТНИЙ розкол двох форм того самого One-Home: `for_cluster` резолвить
    # координату через **OR** (рядок із ОБОМА координатами порахувався б у двох кластерах),
    # а `net_minted_by_cluster` — через **COALESCE** (лише в одному). Сьогодні їх тримає
    # рівними не схема й не гейт, а КОНВЕНЦІЯ ПИСАЧІВ: слеш ставить координати
    # взаємовиключно, мінт і страховка — лише гаманець, Celo — лише кластер.
    # Перший писач з обома координатами розвів би список і деталку МОВЧКИ, бо кожна
    # форма сама по собі лишається «правильною».
    it "тримає обидві форми One-Home узгодженими на тому самому наборі" do
      create(:blockchain_transaction, wallet: wallet, cluster: nil, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: nil, cluster: cluster, amount: 30,
                                      token_type: :carbon_coin, status: :confirmed,
                                      sourceable: naas_contract, direction: :burn)

      batched = described_class.net_minted_by_cluster([ cluster.id ], :carbon_coin)[cluster.id]
      single  = described_class.for_cluster(cluster.id).net_minted_supply(:carbon_coin)

      expect(batched).to eq(single)
    end
  end
end
