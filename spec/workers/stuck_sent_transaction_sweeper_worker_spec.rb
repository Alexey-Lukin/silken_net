# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StuckSentTransactionSweeperWorker, type: :worker do
  let(:wallet) { create(:wallet) }

  def sent_tx(sent_ago:, created_ago: sent_ago, tx_hash: "0x#{SecureRandom.hex(32)}")
    create(:blockchain_transaction, wallet: wallet, status: :sent,
                                    tx_hash: tx_hash, created_at: created_ago,
                                    sent_at: sent_ago)
  end

  describe "#perform" do
    it "re-arms confirmation for a tx stuck in :sent past the threshold" do
      tx = sent_tx(sent_ago: 20.minutes.ago)
      allow(BlockchainConfirmationWorker).to receive(:perform_async).with(tx.tx_hash, kind_of(String))

      described_class.new.perform

      expect(BlockchainConfirmationWorker).to have_received(:perform_async).with(tx.tx_hash, kind_of(String))
    end

    it "ignores a :sent tx still within the live-poller window" do
      sent_tx(sent_ago: 5.minutes.ago)
      allow(BlockchainConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(BlockchainConfirmationWorker).not_to have_received(:perform_async)
    end

    it "ignores a stuck :sent tx on a non-EVM network (ConfirmationWorker is Polygon-specific)" do
      tx = sent_tx(sent_ago: 20.minutes.ago)
      tx.update_columns(blockchain_network: "solana")
      allow(BlockchainConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(BlockchainConfirmationWorker).not_to have_received(:perform_async)
    end

    it "ignores terminal states (confirmed/failed) at any age" do
      create(:blockchain_transaction, wallet: wallet, status: :confirmed, created_at: 2.hours.ago)
      create(:blockchain_transaction, wallet: wallet, status: :failed, created_at: 2.hours.ago)
      allow(BlockchainConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(BlockchainConfirmationWorker).not_to have_received(:perform_async)
    end

    it "keys on sent_at, NOT created_at (reset-to-pending keeps an old created_at)" do
      # A genuinely-stuck tx whose pending wait was long: created 3h ago, broadcast 20m ago.
      tx = sent_tx(sent_ago: 20.minutes.ago, created_ago: 3.hours.ago)
      allow(BlockchainConfirmationWorker).to receive(:perform_async).with(tx.tx_hash, kind_of(String))

      described_class.new.perform

      expect(BlockchainConfirmationWorker).to have_received(:perform_async).with(tx.tx_hash, kind_of(String))
    end

    it "dedups a batchMint (shared tx_hash) to one re-arm with the earliest created_at" do
      shared = "0x#{SecureRandom.hex(32)}"
      earliest = 40.minutes.ago
      sent_tx(sent_ago: 20.minutes.ago, created_ago: earliest, tx_hash: shared)
      sent_tx(sent_ago: 20.minutes.ago, created_ago: 25.minutes.ago, tx_hash: shared)

      allow(BlockchainConfirmationWorker).to receive(:perform_async)
        .with(shared, earliest.iso8601)

      described_class.new.perform

      expect(BlockchainConfirmationWorker).to have_received(:perform_async)
        .with(shared, earliest.iso8601).once
    end

    it "skips a stuck :sent tx with a blank tx_hash (nothing to re-arm)" do
      tx = build(:blockchain_transaction, wallet: wallet, status: :sent, tx_hash: "0xtmp")
      tx.save!(validate: false)
      tx.update_columns(tx_hash: nil, sent_at: 20.minutes.ago)
      allow(BlockchainConfirmationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(BlockchainConfirmationWorker).not_to have_received(:perform_async)
    end

    it "does not log when nothing is stuck (re_armed stays zero)" do
      sent_tx(sent_ago: 2.minutes.ago) # fresh → not swept
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn)
    end

    # [ARCH.45 :processing-orphan] крах між transact і mark_as_sent — ambiguous
    # (мінт міг landed, tx_hash невідомий) → :manual_review, НІКОЛИ blind re-mint.
    describe ":processing-orphan escalation" do
      it "escalates a :processing tx stuck past the threshold to :manual_review" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :processing)
        tx.update_columns(updated_at: 20.minutes.ago)

        described_class.new.perform

        expect(tx.reload.status).to eq("manual_review")
        expect(tx.error_message).to include("processing-orphan")
      end

      it "leaves a LIVE :processing tx alone (batch mid-transact)" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :processing)

        described_class.new.perform

        expect(tx.reload.status).to eq("processing")
      end

      it "skips a :processing orphan a live poller advanced past :processing (re-read race guard)" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :processing)
        tx.update_columns(updated_at: 20.minutes.ago)

        # [S6.16] Гонку відтворюємо В БАЗІ, а не підміною значення в памʼяті. Доти цей
        # приклад стабив `reload` і присвоював статус самому обʼєкту — тобто пінив ІМʼЯ
        # методу, а не властивість «свіжий стан беремо з бази»; заміна `reload` на
        # партиційно-звужене пере-читання лишила б його зеленим ні за що. Стаб тут —
        # лише ГОДИННИК: він позначає мить між SELECT'ом свіпера й пере-читанням, а сам
        # перехід робить справжній UPDATE, і читається він теж справжнім запитом.
        reread_ids = []
        allow(BlockchainTransaction).to receive(:find_with_partition_pruning).and_wrap_original do |orig, *args, **kwargs|
          reread_ids << args.first
          tx.update_columns(status: BlockchainTransaction.statuses[:sent])
          orig.call(*args, **kwargs)
        end

        described_class.new.perform

        # 🔴 [PERF.1] Ліхтар на власну ПЕРЕДУМОВУ: без нього приклад не стверджує, що
        # гард пере-читання взагалі дійшов до НАШОГО орфана. Сьогодні другого сайту
        # виклику в `perform` немає, тож пін нижче тримає — але щойно він зʼявиться,
        # стаб спрацює там, переведе tx у `:sent` ще до гілки орфанів, і «зелено»
        # означатиме «гілка не виконувалась». Стаб — це out-of-band маніпуляція, і вона
        # мусить мати власне позитивне твердження, а не покладатись на наслідок.
        expect(reread_ids).to include(tx.id),
                              "гард пере-читання не дійшов до орфана — приклад вакуумний"

        # Свіжий :sent не перетерто — саме це стереже гард (`escalate_to_review`
        # приймає sent→manual_review, тож без гарда тут стояло б "manual_review").
        expect(tx.reload.status).to eq("sent")
      end

      # 🔴 [PERF.1] Свідок для НУЛЬОВОГО результату: доти свіпер мовчав ЦІЛКОМ, коли
      # гард пропускав усю вибірку — тобто саме тоді, коли підозрілих рядків було
      # найбільше. Пін на лог, бо іншого спостережного виходу в цієї гілки немає.
      it "says out loud that it examined orphans even when it escalated NONE" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :processing)
        tx.update_columns(updated_at: 20.minutes.ago)

        allow(BlockchainTransaction).to receive(:find_with_partition_pruning).and_wrap_original do |orig, *args, **kwargs|
          tx.update_columns(status: BlockchainTransaction.statuses[:sent])
          orig.call(*args, **kwargs)
        end

        allow(Rails.logger).to receive(:info).with(/Розглянуто 1 :processing-орфан/)

        described_class.new.perform

        expect(Rails.logger).to have_received(:info).with(/Розглянуто 1 :processing-орфан/)
      end
    end
  end
end
