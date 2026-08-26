# SPDX-License-Identifier: AGPL-3.0-or-later
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
  #
  # 🔴 [DOC-T.89, ⚖️ 2026-08-26] `credits:` несе ЛИШЕ виміряний ріст. Страхова виплата
  # — теж емісія і теж чесно `direction: :mint`, але намінчена за ЗБИТОК, і вікна
  # вимірів під нею немає ЗА КОНСТРУКЦІЄЮ, — тож у `credits:` вона стверджувала б
  # ріст, якого не було. Її дім — окремий ключ `insurance_payouts:`, а не тиша:
  # мовчазне викидання лишило б on-chain баланс орг більшим за суму bundle-кредитів
  # БЕЗ пояснення, тобто зламало б «невідбирано» рівно там, де лікує «правдиво».
  # ==========================================================================
  class LineageReportService
    SCHEMA = "silken.mrv.lineage.v1"

    # Чесна межа довіри (анти-overclaim — клас, за який архівовано ARCH.53):
    # офлайн-верифіковне З ЦЬОГО ФАЙЛУ — payload→CID, mint-root sealed-кредитів,
    # tier1-субкорінь, tier2→state_root, device_uid↔tree_did. Issuer-asserted
    # (офлайн НЕ перевіриш): amount, ПОВНОТА набору кредитів/листя, континуїтет
    # вікон; backstop = org AuditLog-ланцюг, запечатаний у leaf0 тижневих якорів.
    #
    # [DOC-T.89] `insurance_payouts:` не додає до перевірюваного НІЧОГО: крипто під ним
    # немає за конструкцією (немає листя — немає CID, кореня і шляхів), тож секція цілком
    # issuer-asserted. Це сказано ВГОЛОС нижче: секція, яку аудитор може прийняти за
    # покриту верифікатором, гірша за її відсутність.
    VERIFICATION_INSTRUCTIONS =
      "Run `ruby scripts/verify_lineage_bundle.rb <bundle.json>` (pure Ruby, offline). " \
      "Cryptographically verified from this file alone: leaf payload -> CID, per-credit " \
      "window Merkle-root (sealed credits), tier1 subroot recomputation, tier2 -> state_root, " \
      "device_uid <-> tree_did binding. THEN verify each printed state_root on-chain: the " \
      "storeStateRoot tx MUST target the canonical StateRootAnchor contract — cross-check " \
      "the `anchor_contract` address against an INDEPENDENT source (project canon / official " \
      "site), never against this file alone. Issuer-asserted (NOT offline-verifiable): tx " \
      "amounts, completeness of the credit/leaf set, window continuity; backstop = the org " \
      "AuditLog hash-chain sealed into every weekly anchor's leaf0. " \
      "SCOPE OF `credits`: MEASURED GROWTH ONLY. An insurance payout is SCC minted against a " \
      "LOSS, carries no telemetry window by construction and is NOT a carbon credit; payouts " \
      "are listed separately under `insurance_payouts` and that section is ENTIRELY " \
      "issuer-asserted — the offline verifier checks NOTHING in it, because there is no " \
      "cryptography under it. On-chain those mints carry the `INS_` identifier prefix, so " \
      "their total is cross-checkable against the subgraph's " \
      "`ProtocolFinancials.totalMintedInsurance`."

    def self.call(organization:, from:, to:)
      new(organization: organization, from: from, to: to).call
    end

    def initialize(organization:, from:, to:)
      @organization = organization
      @from = from
      @to = to
      # Мемо (opus/fable review): усі листи одного кластера в одному якорі ділять
      # ідентичний leaf-list — без мемо bundle був O(листя × кластер-вікно).
      @cluster_cids_memo = {}
    end

    def call
      {
        schema: SCHEMA,
        generated_at: Time.current.utc.iso8601,
        organization: { id: @organization.id, name: @organization.name },
        period: { from: @from.utc.iso8601, to: @to.utc.iso8601 },
        anchor_contract: ENV["ETHEREUM_ANCHOR_CONTRACT"],
        credits: credit_transactions.map { |tx| credit_entry(tx) },
        insurance_payouts: insurance_payout_transactions.map { |tx| insurance_payout_entry(tx) },
        verification_instructions: VERIFICATION_INSTRUCTIONS
      }
    end

    private

    # [ARCH.98] Org-scoping через One-Home `for_organization` (дві гілки: гаманці ∪
    # прямий `cluster_id`). Доти тут стояв `joins(wallet: …)` «за прецедентом
    # `ReportsController#financial_summary`» — і успадкував разом із ним INNER JOIN,
    # тобто cluster-sourced слеш останнього дерева випадав із ДОКАЗОВОГО шляху
    # (ISO 14064/Verra), а не лише з екрана.
    # created_at-вікно = partition-pruning на партиційованій таблиці.
    # 🔴 [ARCH.101 → ARCH.95] Напрямок ОГОЛОШЕНО (колонка `direction`), і без того рядка
    # ключ `credits:` ніс спалення: слеш-інтент теж `carbon_coin`, теж доходить до
    # `:confirmed` і пишеться ДОДАТНОЮ сумою (модель каже це прямо), тож ані `token_type`,
    # ані `status`, ані знак `amount` його не відсіюють — зовнішній аудитор ISO 14064/Verra
    # дістав би штраф як виданий кредит. ⚠️ Цей абзац доти казав «деривується» і посилався
    # на `IS DISTINCT FROM 'NaasContract'` у `net_minted_supply` — обидва твердження ARCH.95
    # зняв (спека це вже зафіксувала, коментар лишався в старому світі).
    #
    # ⊥ Передумова, оголошена свідомо: після цього фільтра КОЖЕН рядок має гаманець —
    # але це властивість складу ПИСАЧІВ (`wallet: nil` пише рівно `BlockchainBurningService`,
    # «пастка останнього дерева»), а не інваріант схеми: `belongs_to :wallet` тут
    # `optional`, і `for_organization` має другу гілку саме по `cluster_id`. Тобто
    # `inherited_failed_attempts` безпечний ВИПАДКОВО; перший не-burn писач із
    # кластерною координатою зробить його падінням на доказовому шляху.
    def org_confirmed_mints
      BlockchainTransaction
        .for_organization(@organization.id)
        .where(token_type: [ :carbon_coin, :forest_coin ], status: :confirmed)
        # [ARCH.95] Напрямок читається з колонки `direction`, а не деривується з
        # `sourceable_type`: ESG-погашення теж є вилученням з обігу й `sourceable`
        # не має, тож стара форма зарахувала б його КРЕДИТОМ у доказовий bundle.
        .where(direction: :mint)
        .where(created_at: @from..@to)
        .order(:created_at, :id)
    end

    def credit_transactions
      measured_only(org_confirmed_mints)
    end

    def insurance_payout_transactions
      org_confirmed_mints.where(sourceable_type: insurance_sourceable_type)
    end

    # 🔴 [DOC-T.89] Дискримінатор ПРИРОДИ емісії — окрема вісь від напрямку. Виплата
    # чесно `direction: :mint` (реальний писач `InsurancePayoutWorker` навіть не передає
    # `direction:` — його дає DB-default), тож [ARCH.95]-фільтр її НЕ ловить: питання
    # «мінт чи спалення» і питання «за вимір чи за збиток» — різні питання.
    #
    # ⚠️ `IS DISTINCT FROM`, а не `where.not`: `sourceable_type` у зростового мінту
    # NULL, а `<> 'ParametricInsurance'` для NULL дає NULL → наївна форма викинула б
    # САМЕ кредити й лишила виплату. Та сама пастка, за яку куплено [ARCH.101].
    #
    # Живе ОДНИМ методом, бо читачів ДВА — набір `credits:` і `prev`-межа успадкування.
    # Розійшовшись, вони дали б половинчастий фікс: виплату вигнали б з кредитів, але
    # вона й далі обрізала б успадковані вікна вимірів.
    def measured_only(relation)
      relation.where(
        "blockchain_transactions.sourceable_type IS DISTINCT FROM ?", insurance_sourceable_type
      )
    end

    # Літерала "ParametricInsurance" тут немає СВІДОМО: `sourceable_type` пише сам Rails
    # через `polymorphic_name`, тож єдиний чесний дім цього рядка — сам клас. Перейменують
    # модель — фільтр поїде за нею, а не почне мовчки пропускати виплати в кредити.
    def insurance_sourceable_type
      ParametricInsurance.polymorphic_name
    end

    def credit_entry(tx)
      own_logs = Mrv::LineageWindow.logs_for(tx).preload(tree: :cluster).to_a
      inherited = inherited_failed_attempts(tx)
      inherited_logs = inherited.flat_map { |ftx| Mrv::LineageWindow.logs_for(ftx).preload(tree: :cluster).to_a }

      {
        tx: {
          id: tx.id, tx_hash: tx.tx_hash, amount: tx.amount.to_s("F"), token_type: tx.token_type,
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

    # 🔴 [DOC-T.89] Страхова виплата — емісія за ЗБИТОК, і форма запису це КАЖЕ, а не
    # натякає: `lineage: "none_by_construction"` (вікна немає й не могло бути), поле
    # звуться `audit_anchor_tree_did`, а не `tree_did` — те дерево нічого не заробило,
    # воно лише якір аудит-звʼязку (писач бере ПЕРШЕ-ліпше дерево кластера). Префікс
    # on-chain ідентифікатора йде поруч, щоб аудитор зшив цю секцію з subgraph-стороною
    # (`kind: INSURANCE`, `totalMintedInsurance`) — і взяв його з ОДНОГО дому.
    def insurance_payout_entry(tx)
      {
        tx: {
          id: tx.id, tx_hash: tx.tx_hash, amount: tx.amount.to_s("F"), token_type: tx.token_type,
          to_address: tx.to_address, created_at: tx.created_at.utc.iso8601(6)
        },
        policy: { type: tx.sourceable_type, id: tx.sourceable_id },
        audit_anchor_tree_did: tx.wallet&.tree&.did,
        on_chain_identifier_prefix: BlockchainMintingService::INSURANCE_MINT_PREFIX,
        lineage: "none_by_construction"
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
    # Межі = tuple (created_at, id) — total order, µs-збіг не сиротить спробу;
    # «голий» created_at-предикат поруч — partition-pruning (партиційована таблиця).
    def inherited_failed_attempts(tx)
      # 🔴 [DOC-T.89] Межа = попередній ВИМІРЯНИЙ кредит, той самий предикат, що й
      # `credits:`. Доти тут стояв голий `status: :confirmed` — тобто межею ставав
      # БУДЬ-ЯКИЙ підтверджений рядок гаманця, включно зі страховою виплатою і
      # спаленням, які жодного вікна не спожили. Наслідок був тихий і однобічний:
      # failed-спроба ДО такого рядка переставала успадковуватись, тобто вікно
      # вимірів, яке доказує кредит, зникало з доказового bundle зовсім.
      prev = measured_only(tx.wallet.blockchain_transactions)
               .where(status: :confirmed, direction: :mint)
               .where(created_at: ..tx.created_at)
               .where("(created_at, id) < (?, ?)", tx.created_at, tx.id)
               .order(:created_at, :id).last
      scope = tx.wallet.blockchain_transactions
                .where(status: :failed)
                .where.not(telemetry_window_to_at: nil)
                .where(created_at: ..tx.created_at)
                .where("(created_at, id) < (?, ?)", tx.created_at, tx.id)
      if prev
        scope = scope.where(created_at: prev.created_at..)
                     .where("(created_at, id) > (?, ?)", prev.created_at, prev.id)
      end
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
    # Кандидати кешуються раз на виклик сервісу (пошук по листах — in-memory).
    def anchor_proof(log)
      anchor = covering_anchors.find do |a|
        a.window_to >= log.created_at && (a.window_from.nil? || a.window_from < log.created_at)
      end
      return { status: "pending_anchor" } if anchor.nil?

      cluster_id = log.tree.cluster_id
      entry_index = anchor.subtree_roots.index { |e| e.key?("cluster_id") && e["cluster_id"] == cluster_id }
      return { status: "unprovable_regrouped" } if entry_index.nil?

      cluster_cids, recomputed_subroot = anchor_cluster_leaf_cids(anchor, cluster_id)
      leaf_cid = Mrv::TelemetryLeaf.cid_for(log)
      leaf_index = cluster_cids.index(leaf_cid)
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

    def covering_anchors
      @covering_anchors ||= EthereumAnchor.status_confirmed.where(root_version: 1)
                                          .order(:anchored_at, :id).to_a
    end

    # Перевибірка кластерного вікна якоря в канонічному порядку (report-time, не hot-path);
    # мемо по (anchor, cluster) → [cids, субкорінь] — колапсує K листів у 1 скан.
    def anchor_cluster_leaf_cids(anchor, cluster_id)
      @cluster_cids_memo[[ anchor.id, cluster_id ]] ||= begin
        scope = TelemetryLog.joins(:tree)
                            .where(trees: { cluster_id: cluster_id })
                            .where(created_at: ..anchor.window_to)
        scope = scope.where("telemetry_logs.created_at > ?", anchor.window_from) if anchor.window_from
        cids = scope.order(:created_at, :id).preload(:tree).map { |l| Mrv::TelemetryLeaf.cid_for(l) }
        [ cids, MerkleTree.root(cids) ]
      end
    end
  end
end
