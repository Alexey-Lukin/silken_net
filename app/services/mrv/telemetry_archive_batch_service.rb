# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Mrv
  # ==========================================================================
  # 📦 MRV TELEMETRY ARCHIVE BATCH SERVICE (E.60 Фаза 1б — mint-anchored)
  # ==========================================================================
  # Будує/реюзає архів-батчі для диспатчу мінта: батч ≔ union lineage-вікон
  # tx'ів (реюз Mrv::LineageWindow 1:1), корінь = MerkleTree.root над
  # leaf_cid'ами у ГЛОБАЛЬНОМУ порядку (created_at, id) — той самий порядок у
  # rebuild (pin-воркер) і офлайн-верифікаторі (scripts/verify_archive_bundle.rb).
  #
  # Інваріанти (канон 05_02 §E.60):
  #   • set-once membership: tx.archive_batch_id ставиться РАЗ, атомарно зі
  #     створенням батчу (root-set ≡ bind-set; SQL-фільтр archive_batch_id IS
  #     NULL); повторний диспатч реюзає stored root готової групи.
  #   • Детермінізм (вікна персистовані, верхня межа фіксована) +
  #     create_or_find_by → конкурентні build'и КОНВЕРГУЮТЬ у той самий рядок.
  #   • windowless-диспатч (insurance/celo/burn) → ZERO_ROOT БЕЗ рядка;
  #     zero32 on-chain = «без witness-клейму», derived-only.
  #   • збій build → build_failed-рядок (NULL root, reason, tx_ids-слід) БЕЗ
  #     біндингу (bind прирік би tx на zero32 назавжди через set-once) + мінт
  #     їде ZERO_ROOT (fail-open: money liveness > optional witness).
  #   • Викликається ПОЗА Kredis oracle-локом (див. BlockchainMintingService).
  # ==========================================================================
  class TelemetryArchiveBatchService
    # hex-форма bytes32(0) — «без witness-клейму» для windowless/fail-open мінтів.
    ZERO_ROOT = "0" * 64

    Group = Struct.new(:root, :txs, :batch, keyword_init: true)

    # Повертає масив Group (root · txs · batch|nil) для transact-циклу
    # per-підгрупою: «один batchMint = один root» фізично (жоден виклик не
    # мішає tx різних батчів).
    def self.group(txs, token_type:, tax_rate: nil)
      new(txs, token_type: token_type, tax_rate: tax_rate).group
    end

    def initialize(txs, token_type:, tax_rate: nil)
      @txs = txs
      @token_type = token_type
      @tax_rate = tax_rate
    end

    def group
      groups = []
      remaining = @txs

      # До двох проходів: partial-bind (конкурент вкрав частину
      # fresh-tx між читанням членства і bind'ом — обидва поза oracle-локом)
      # відкочується ЦІЛКОМ у bind_atomically, тут перечитуємо членство —
      # вкрадені стали existing-групами, залишок будується заново.
      2.times do |attempt|
        existing, fresh = remaining.partition(&:archive_batch_id)
        groups.concat(existing.group_by(&:archive_batch_id).map do |batch_id, member_txs|
          batch = TelemetryArchiveBatch.find_by(id: batch_id)
          # `batch&.`/ZERO_ROOT-fallback = dead-defensive: FK + restrict_with_error
          # роблять dangling archive_batch_id недосяжним (§B.4 leave).
          Group.new(root: batch&.archive_root || ZERO_ROOT, txs: member_txs, batch: batch)
        end)
        return groups if fresh.empty?

        result = build_fresh_group(fresh, final_attempt: attempt == 1)
        if result == :bind_race
          remaining = fresh.each(&:reload)
          next
        end
        groups << result
        return groups
      end
      groups
    end

    # One-Home union-запиту: ГЛОБАЛЬНИЙ порядок (created_at, id) по всіх вікнах
    # (вікна різних дерев не діляться логами → total order без дедупу).
    # Юзають build (тут) і rebuild (pin-воркер) — розійтись їм нема як.
    def self.union_logs(txs)
      txs.select(&:telemetry_window_to_at)
         .flat_map { |tx| Mrv::LineageWindow.logs_for(tx).preload(:tree).to_a }
         .sort_by { |log| [ log.created_at, log.id ] }
    end

    private

    def build_fresh_group(txs, final_attempt: false)
      logs = self.class.union_logs(txs)
      return Group.new(root: ZERO_ROOT, txs: txs, batch: nil) if logs.empty?

      root = MerkleTree.root(logs.map { |log| Mrv::TelemetryLeaf.cid_for(log) })
      assert_dispatch_consistency(txs, root)

      batch = bind_atomically(txs, root, logs.size)
      unless batch
        # Partial-bind: мінт із root'ом над union'ом, якого
        # прив'язаний набір не відтворює, зламав би witness (rebuild хибно
        # мітив би retention_expired). Один re-read; повторна гонка → fail-open.
        return :bind_race unless final_attempt

        record_build_failure(txs, RuntimeError.new("bind-race двічі поспіль — конкурентні диспатчі того ж пулу"))
        return Group.new(root: ZERO_ROOT, txs: txs, batch: nil)
      end

      # Первинний enqueue ПІСЛЯ commit (reconcile = backstop, не первинний шлях);
      # знайдений-існуючий рядок уже enqueue'нув свій творець.
      TelemetryArchiveBatchWorker.perform_async(batch.id) if Filecoin::ArchiveService.configured? && batch.previously_new_record?
      Group.new(root: batch.archive_root, txs: txs, batch: batch)
    rescue StandardError => e
      record_build_failure(txs, e)
      Group.new(root: ZERO_ROOT, txs: txs, batch: nil)
    end

    # Атомарність root-set ≡ bind-set СТРОГО: batch-row + bind УСІХ tx в одній
    # транзакції; member-set ≠ tx-set (конкурент вкрав частину) → rollback
    # ВСЬОГО і nil. create_or_find_by усередині безпечний (Rails
    # обгортає savepoint'ом requires_new); конвергентний ідентичний build
    # проходить member-чек (його tx уже прив'язані до ЦЬОГО ж рядка).
    def bind_atomically(txs, root, leaf_count)
      batch = nil
      complete = false
      window = txs.map(&:created_at).minmax
      ActiveRecord::Base.transaction do
        # find-гілка успадковує txs_created_межі від творця: той самий root ⇒
        # той самий детермінований tx-набір ⇒ те саме вікно (стеля: гіпотетичний
        # same-root-різні-tx недосяжний за конструкцією leaf-формули).
        batch = TelemetryArchiveBatch.create_or_find_by(archive_root: root, token_type: @token_type) do |b|
          b.leaf_count = leaf_count
          b.tx_count = txs.size
          b.tx_ids = txs.map(&:id)
          b.tax_rate_applied = @tax_rate
          b.txs_created_from = window.first
          b.txs_created_to = window.last
        end
        # created_at-межі = partition-pruning (партиційована таблиця; id-only
        # update_all сканував би всі партиції); archive_batch_id IS NULL =
        # set-once на рівні SQL (конкурент, що встиг першим, лишається власником).
        BlockchainTransaction.where_ids_pruned(txs.map(&:id), window,
                                               metric_caller: "Mrv::TelemetryArchiveBatchService")
                             .where(archive_batch_id: nil)
                             .update_all(archive_batch_id: batch.id)
        member_count = BlockchainTransaction.where_ids_pruned(txs.map(&:id), window,
                                                              metric_caller: "Mrv::TelemetryArchiveBatchService")
                                            .where(archive_batch_id: batch.id)
                                            .count
        complete = member_count == txs.size
        raise ActiveRecord::Rollback unless complete
      end
      complete ? batch : nil
    end

    # Advisory-assert (не блокує): для size-1 групи корінь батчу бітово =
    # tx.telemetry_merkle_root за конструкцією — розбіжність означає мутацію
    # телеметрії між lock_and_mint! і диспатчем (GRACE-каveат: 05_04 §Merkle).
    def assert_dispatch_consistency(txs, root)
      return unless txs.size == 1

      stored = txs.first.telemetry_merkle_root
      return if stored.blank? || stored == root

      Rails.logger.warn "⚠️ [E.60] dispatch-drift tx ##{txs.first.id}: stored lineage-root ≠ " \
                        "recomputed (#{stored[0, 8]}… ≠ #{root[0, 8]}…) — мутація вікна після мінт-інтенту?"
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "dispatch_drift" })
    end

    # build_failed = слід для розрізнення «порожньо» vs «зламано» (self-masking
    # guard: zero32-мінт при непорожніх вікнах = інцидент). БЕЗ біндингу tx.
    def record_build_failure(txs, error)
      Rails.logger.error "🛑 [E.60] Archive-batch build failed (#{txs.size} tx, #{@token_type}) — " \
                         "мінт іде zero32 (fail-open): #{error.message}"
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "build" })
      window = txs.map(&:created_at).minmax
      TelemetryArchiveBatch.create!(
        token_type: @token_type, status: :build_failed, tx_count: txs.size,
        tx_ids: txs.map(&:id), error_message: error.message.truncate(450),
        txs_created_from: window.first, txs_created_to: window.last
      )
    rescue StandardError => e
      Rails.logger.error "🛑 [E.60] build_failed-слід теж не записався: #{e.message}"
    end
  end
end
