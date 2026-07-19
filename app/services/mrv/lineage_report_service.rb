# frozen_string_literal: true

module Mrv
  # ==========================================================================
  # 📜 MRV LINEAGE REPORT (ISO-звіт — ПЕРШИЙ inclusion-proof-споживач, ARCH.12/MRV.1)
  # ==========================================================================
  # Самодостатній офлайн-verifiable bundle «credit → measurements»: для кожного
  # confirmed-мінту організації — вікно вимірів, canonical-payload'и листя,
  # inclusion-proof'и до якорених тижневих state_root (два яруси: leaf→субкорінь,
  # субкорінь→root) і референси якоря (etherscan). Аудитор верифікує КОЖЕН крок
  # без доступу до БД/API — scripts/verify_lineage_bundle.rb (pure Ruby, офлайн);
  # довіра впирається лише в on-chain корінь.
  #
  # Чесні статуси пруфа: anchored (повний шлях) · pending_anchor (лист новіший за
  # останній confirmed-якір — proof після наступного тижневого seal) ·
  # unprovable_regrouped (дерево змінило кластер після якоря — перерахований
  # субкорінь ≠ збереженому; historical-groupування зафіксоване в subtree_roots).
  # Failed-спроби успадковуються: їхні вікна+листя входять у credit-entry
  # наступного успішного мінту (курсор монотонний — «чесна межа (г)» MRV.1).
  # ==========================================================================
  class LineageReportService
    SCHEMA = "silken.mrv.lineage.v1"

    VERIFICATION_INSTRUCTIONS =
      "Run `ruby scripts/verify_lineage_bundle.rb <bundle.json>` (pure Ruby, offline). " \
      "It recomputes every leaf CID from its canonical payload, every tier1 subroot from " \
      "the audit path, and every tier2 state_root — then compare each anchor's state_root " \
      "against the on-chain StateRootAnchor record (etherscan_url) yourself. " \
      "No trust in this file or its issuer is required beyond the on-chain roots."

    def self.call(organization:, from:, to:)
      new(organization: organization, from: from, to: to).call
    end

    def initialize(organization:, from:, to:)
      @organization = organization
      @from = from
      @to = to
    end

    def call
      {
        schema: SCHEMA,
        generated_at: Time.current.utc.iso8601,
        organization: { id: @organization.id, name: @organization.name },
        period: { from: @from.utc.iso8601, to: @to.utc.iso8601 },
        credits: credit_transactions.map { |tx| credit_entry(tx) },
        verification_instructions: VERIFICATION_INSTRUCTIONS
      }
    end

    private

    # Org-scoping через cluster-ланцюг (прецедент ReportsController#financial_summary);
    # created_at-вікно = partition-pruning на партиційованій таблиці.
    def credit_transactions
      BlockchainTransaction
        .joins(wallet: { tree: :cluster })
        .where(clusters: { organization_id: @organization.id })
        .where(token_type: [ :carbon_coin, :forest_coin ], status: :confirmed)
        .where(created_at: @from..@to)
        .order(:created_at, :id)
    end

    def credit_entry(tx)
      own_logs = Mrv::LineageWindow.logs_for(tx).preload(tree: :cluster).to_a
      inherited = inherited_failed_attempts(tx)
      inherited_logs = inherited.flat_map { |ftx| Mrv::LineageWindow.logs_for(ftx).preload(tree: :cluster).to_a }

      {
        tx: {
          id: tx.id, tx_hash: tx.tx_hash, amount: tx.amount.to_s, token_type: tx.token_type,
          to_address: tx.to_address, tree_did: tx.wallet.tree.did,
          created_at: tx.created_at.utc.iso8601(6)
        },
        window: window_hash(tx),
        telemetry_merkle_root: tx.telemetry_merkle_root,
        lineage_version: tx.telemetry_lineage_version,
        seal: tx.telemetry_merkle_root.present? ? "sealed" : "unsealed",
        inherited_windows: inherited.map { |ftx| { tx_id: ftx.id, status: ftx.status, window: window_hash(ftx) } },
        leaves: own_logs.map { |log| leaf_entry(log, window_source: tx.id) } +
                inherited_logs.map { |log| leaf_entry(log, window_source: nil) }
      }
    end

    def window_hash(tx)
      {
        from_at: tx.telemetry_window_from_at&.utc&.iso8601(6), from_id: tx.telemetry_window_from_id,
        to_at: tx.telemetry_window_to_at&.utc&.iso8601(6), to_id: tx.telemetry_window_to_id
      }
    end

    # «Чесна межа (г)»: failed-спроби між попереднім confirmed-мінтом гаманця і цим —
    # їхні бали звільнено і повторно замінчено, тож їхні вікна доказують ЦЕЙ кредит.
    def inherited_failed_attempts(tx)
      prev_confirmed_at = tx.wallet.blockchain_transactions
                            .where(status: :confirmed)
                            .where("created_at < ?", tx.created_at)
                            .maximum(:created_at)
      scope = tx.wallet.blockchain_transactions
                .where(status: :failed)
                .where.not(telemetry_window_to_at: nil)
                .where("created_at < ?", tx.created_at)
      scope = scope.where("created_at > ?", prev_confirmed_at) if prev_confirmed_at
      scope.order(:created_at, :id)
    end

    def leaf_entry(log, window_source:)
      {
        telemetry_log_id: log.id,
        window_source: window_source, # nil = успадкований failed-attempt лист
        payload: Mrv::TelemetryLeaf.payload_for(log),
        leaf_cid: Mrv::TelemetryLeaf.cid_for(log),
        anchor_proof: anchor_proof(log)
      }
    end

    # Covering-lookup: НАЙРАНІШІЙ confirmed merkle-якір, чиє вікно покриває лист
    # (log.created_at ∈ (window_from, window_to]) — overlap-правило 05_04 §Merkle.
    def anchor_proof(log)
      anchor = EthereumAnchor.status_confirmed.where(root_version: 1)
                             .where(window_to: log.created_at..)
                             .where("window_from IS NULL OR window_from < ?", log.created_at)
                             .order(:anchored_at, :id).first
      return { status: "pending_anchor" } if anchor.nil?

      cluster_id = log.tree.cluster_id
      entry_index = anchor.subtree_roots.index { |e| e.key?("cluster_id") && e["cluster_id"] == cluster_id }
      return { status: "unprovable_regrouped" } if entry_index.nil?

      cluster_cids = anchor_cluster_leaf_cids(anchor, cluster_id)
      leaf_cid = Mrv::TelemetryLeaf.cid_for(log)
      leaf_index = cluster_cids.index(leaf_cid)
      recomputed_subroot = MerkleTree.root(cluster_cids)
      stored_subroot = anchor.subtree_roots[entry_index]["root"]
      # Дерево могло змінити кластер ПІСЛЯ якоря (групування зафіксоване в subtree_roots) —
      # перерахунок тоді не збігається; чесний маркер замість фальшивого пруфа.
      return { status: "unprovable_regrouped" } if leaf_index.nil? || recomputed_subroot != stored_subroot

      {
        status: "anchored",
        anchor: {
          id: anchor.id, tx_hash: anchor.tx_hash, state_root: anchor.state_root,
          anchored_at: anchor.anchored_at.utc.iso8601, block_number: anchor.block_number,
          etherscan_url: anchor.etherscan_url
        },
        tier1: {
          cluster_id: cluster_id, subroot: stored_subroot,
          path: MerkleTree.proof(cluster_cids, leaf_index)
        },
        tier2: {
          path: MerkleTree.proof(anchor.subtree_roots.map { |e| e["root"] }, entry_index)
        }
      }
    end

    # Перевибірка кластерного вікна якоря в канонічному порядку (report-time, не hot-path).
    def anchor_cluster_leaf_cids(anchor, cluster_id)
      scope = TelemetryLog.joins(:tree)
                          .where(trees: { cluster_id: cluster_id })
                          .where(created_at: ..anchor.window_to)
      scope = scope.where("telemetry_logs.created_at > ?", anchor.window_from) if anchor.window_from
      scope.order(:created_at, :id).preload(:tree).map { |l| Mrv::TelemetryLeaf.cid_for(l) }
    end
  end
end
