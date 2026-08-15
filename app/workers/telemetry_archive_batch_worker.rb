# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 📦 TELEMETRY ARCHIVE BATCH WORKER (E.60 Фаза 1б — pin-нога)
# = ===================================================================
# Довершує архів-батч ПІСЛЯ диспатчу мінта: rebuild артефакту з БД (вікна —
# НІКОЛИ стемп-фільтр archive_root: у стемп-щілині набір був би неповний) →
# звірка кореня → стемп листя (raw-SQL VALUES-join, per-slice created_at-межі
# для partition-pruning) → пін JSON-артефакту (Pinata) → CAS-термінал.
#
# Термінали CAS-гардовані в моделі (перехід лише з pending) → конкурентні
# копії (первинний enqueue × reconcile-backstop) безпечні: stale-копія no-op,
# mismatch/superseded не перетираються pinned. Тому БЕЗ unique_for (шим no-op,
# а справжній dedup-skip på re-enqueue = self-masking «success» без піну).
#
# Розрізнення розбіжності кореня (E.60 Фаза 1б):
#   листя < leaf_count → retention_expired (партиції дропнуто — НЕ tamper);
#   інакше → mismatch (integrity-сигнал: алерт + runbook 06_08 §4) —
#   розбіжний артефакт НІКОЛИ не пінити.
class TelemetryArchiveBatchWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "low", retry: 5

  # Detect-половина (дзеркало FilecoinArchiveWorker/INF.22): вичерпаний пін без
  # hook'а тихо осідав би в Dead Set; error_message = attributable слід (окремого
  # pin_failed-стану СВІДОМО нема — документована стеля, reconcile re-enqueue'їть).
  sidekiq_retries_exhausted do |job, exception|
    batch_id = job["args"].first
    Rails.logger.error "🛑 [E.60] TelemetryArchiveBatchWorker вичерпав retry для батчу ##{batch_id} " \
                       "(лишається pending, reconcile підбере): #{exception.message}"
    SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "pin" })
    # CAS-запис: конкурентна копія могла щойно запінити — не
    # затирати pinned-рядок stale-помилкою.
    batch = TelemetryArchiveBatch.find_by(id: batch_id)
    batch&.with_lock do
      batch.update!(error_message: "pin exhausted: #{exception.message}".truncate(450)) if batch.status_pending?
    end
  end

  STAMP_SLICE = 500
  ARTIFACT_VERSION = 1

  # Trust-boundary артефакту — самоописова (урок 1а «верифікатор сам overclaim'ить»);
  # дзеркалиться scripts/verify_archive_bundle.rb.
  VERIFICATION_INSTRUCTIONS = [
    "ВЕРИФІКОВНЕ ОФЛАЙН: кожен leaf.payload → CIDv1 (raw+sha2-256, base32) має збігатися з leaf_cid;",
    "MerkleTree.root над leaf_cid'ами у порядку масиву (глобальний (created_at, id) asc) має збігатися з archive_root;",
    "archive_root має збігатися з on-chain archiveRoot події CarbonMinted/ForestMinted відповідного мінта (contract-адресу звіряй з НЕЗАЛЕЖНИМ джерелом, не з цим файлом);",
    "device_uid кожного листа = did дерева (прив'язка лист ↔ дерево).",
    "ISSUER-ASSERTED (НЕ верифіковне з цього файла): amount кожної tx (growth_points у листі немає — leaf v1 = Z);",
    "повнота набору tx/листя; межі вікон; відповідність root → ipfs_cid (discovery через реєстр issuer'а);",
    "root = свідок evidence-набору ДИСПАТЧУ (N:1): вікна tx'ів, що не мінтились (failed/poisoned/KYC-skip), присутні легально."
  ].freeze

  def perform(batch_id)
    batch = TelemetryArchiveBatch.find(batch_id)
    return attempt_repair(batch) if batch.status_build_failed?
    return unless batch.status_pending?

    txs = bounded_txs(batch).order(:created_at, :id).to_a
    if txs.empty?
      # Усі tx перейшли в інші батчі (легально лише в обхід guard'ів — defensive).
      Rails.logger.warn "⚠️ [E.60] Батч ##{batch.id} без жодного tx → superseded (не пінимо)."
      batch.mark_superseded!
      return
    end

    logs = Mrv::TelemetryArchiveBatchService.union_logs(txs)
    leaves = logs.map { |log| [ log, Mrv::TelemetryLeaf.cid_for(log) ] }
    root = MerkleTree.root(leaves.map(&:last))

    return handle_root_divergence(batch, leaves.size) if root != batch.archive_root

    stamp!(leaves, batch.archive_root)

    cid = with_web3_error_handling("Filecoin", "ArchiveBatch ##{batch.id}") do
      Filecoin::ArchiveService.pin_json!(
        build_artifact(batch, txs, leaves),
        name: "silkennet-telemetry-batch-#{batch.archive_root[0, 16]}",
        keyvalues: { archive_root: batch.archive_root, token_type: batch.token_type }
      )
    end

    batch.mark_pinned!(cid)
    Rails.logger.info "📦 [E.60] Батч ##{batch.id} запінено: root=#{batch.archive_root[0, 12]}… → CID #{cid}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "📦 [E.60] Батч ##{batch_id} не знайдено, skip."
  end

  private

  def handle_root_divergence(batch, rebuilt_leaf_count)
    if rebuilt_leaf_count < batch.leaf_count
      Rails.logger.warn "⚠️ [E.60] Батч ##{batch.id}: листя #{rebuilt_leaf_count} < #{batch.leaf_count} — " \
                        "ретеншн-дроп партицій, НЕ tamper → retention_expired."
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "retention_expired" })
      batch.mark_retention_expired!("rebuild leaves #{rebuilt_leaf_count} < #{batch.leaf_count} (partition drop)")
    else
      Rails.logger.error "🛑 [E.60] INTEGRITY: батч ##{batch.id} rebuild-root ≠ stored root при живих " \
                         "логах — розбіжний артефакт НЕ пінимо (runbook 06_08 §4)."
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_FAILURES_TOTAL.increment(labels: { reason: "mismatch" })
      batch.mark_mismatch!("rebuild root diverged at #{rebuilt_leaf_count} leaves")
    end
  end

  # Стемп: merkle_leaf per-row + спільний archive_root — raw-SQL VALUES-join
  # (update_all не вміє per-row значення). Листя відсортовані за created_at →
  # per-slice межі прунять партиції. Ідемпотентно (same-value re-UPDATE = no-op);
  # AR-колбеки не стріляють — seal-guard моделі тримає AR-шлях, sweeper ловить
  # raw-шлях. [transitional] стеля: тисячі рядків/батч у low-черзі; upgrade-path =
  # шардинг стемпа окремими джобами (ARCH.52-клас).
  def stamp!(leaves, root)
    conn = ActiveRecord::Base.connection
    leaves.each_slice(STAMP_SLICE) do |slice|
      placeholders = ([ "(?, ?)" ] * slice.size).join(", ")
      t_min, t_max = slice.map { |log, _cid| log.created_at }.minmax
      conn.exec_update(ActiveRecord::Base.sanitize_sql_array(
        [ <<~SQL, root, *slice.flat_map { |log, cid| [ log.id, cid ] }, t_min, t_max ]
          UPDATE telemetry_logs
          SET merkle_leaf = v.leaf, archive_root = ?
          FROM (VALUES #{placeholders}) AS v(id, leaf)
          WHERE telemetry_logs.id = v.id
            AND telemetry_logs.created_at >= ?
            AND telemetry_logs.created_at <= ?
        SQL
      ))
    end
  end

  def build_artifact(batch, txs, leaves)
    {
      artifact_version: ARTIFACT_VERSION,
      kind: "silkennet-telemetry-archive-batch",
      archive_root: batch.archive_root,
      token_type: batch.token_type,
      leaf_version: Mrv::TelemetryLeaf::LEAF_VERSION,
      hash_algorithm: "sha256 (RFC-6962 domain-sep 0x00/0x01, MerkleTree)",
      leaf_order: "global (created_at, id) asc",
      tax_rate_applied: batch.tax_rate_applied&.to_s,
      pinned_at: Time.current.utc.iso8601,
      transactions: txs.map { |tx| tx_entry(tx) },
      leaves: leaves.map { |log, cid| { payload: Mrv::TelemetryLeaf.payload_for(log), leaf_cid: cid } },
      verification_instructions: VERIFICATION_INSTRUCTIONS
    }
  end

  # window-tuples per tx + tree_did = офлайн window-binding верифікатора
  # (кожен лист ∈ рівно ОДНЕ вікно свого дерева — smuggled-leaf детекція) і
  # крос-батч overlap-детекція; amount/status = issuer-asserted (instructions).
  def tx_entry(tx)
    {
      blockchain_transaction_id: tx.id,
      tree_did: tx.wallet&.tree&.did,
      amount: tx.amount.to_s,
      status_at_pin: tx.status,
      telemetry_merkle_root: tx.telemetry_merkle_root,
      window: {
        from_at: tx.telemetry_window_from_at&.utc&.iso8601(6),
        from_id: tx.telemetry_window_from_id,
        to_at: tx.telemetry_window_to_at&.utc&.iso8601(6),
        to_id: tx.telemetry_window_to_id
      }
    }
  end

  # Read-back'и по партиційованій blockchain_transactions ЗАВЖДИ
  # з created_at-межами батчу (id-only lookup пробував би кожну партицію).
  def bounded_txs(batch, scope = batch.blockchain_transactions)
    return scope unless batch.txs_created_from && batch.txs_created_to

    scope.where(created_at: batch.txs_created_from..batch.txs_created_to)
  end

  # Repair-нога (reconcile → build_failed): пізній rebuild для tx, яких НЕ
  # забрав жоден інший батч (set-once фільтр). Chain на той мінт уже поїхав
  # zero32 → root off-chain-only, легально («zero32 = без клейму», runbook).
  # Невиправний (усі tx розібрані / вікна порожні) → abandon (
  # інакше вічний daily re-enqueue no-op'ів).
  def attempt_repair(batch)
    txs = bounded_txs(batch, BlockchainTransaction.where(id: Array(batch.tx_ids), archive_batch_id: nil)).to_a
    if txs.empty?
      batch.abandon_repair!("repair неможливий: усі tx уже в інших батчах або зникли")
      return
    end

    logs = Mrv::TelemetryArchiveBatchService.union_logs(txs)
    if logs.empty?
      batch.abandon_repair!("repair неможливий: вікна tx порожні (windowless/ретеншн)")
      return
    end

    root = MerkleTree.root(logs.map { |log| Mrv::TelemetryLeaf.cid_for(log) })
    ActiveRecord::Base.transaction do
      break unless batch.repair!(root, leaf_count: logs.size, tx_count: txs.size)

      # [PERF.1] Делеговано в One-Home: форма правильна й доти, але вона була третьою
      # рукописною копією span-логіки, а дім заразом веде лічильник деградації
      # (`missing_span`), якого рукописна форма не мала — тихий промах тут означає
      # скан усіх партицій на money-таблиці.
      BlockchainTransaction.where_ids_pruned(txs.map(&:id), txs.map(&:created_at),
                                             metric_caller: "TelemetryArchiveBatchWorker")
                           .where(archive_batch_id: nil)
                           .update_all(archive_batch_id: batch.id)
    end
    TelemetryArchiveBatchWorker.perform_async(batch.id) if batch.reload.status_pending?
  rescue ActiveRecord::RecordNotUnique
    # Той самий root уже має власника (tx re-dispatch'нулись) — build_failed
    # лишається чесним слідом, не дублюємо.
    Rails.logger.warn "⚠️ [E.60] repair батчу ##{batch.id}: root уже має власника — лишаємо слід."
  end
end
