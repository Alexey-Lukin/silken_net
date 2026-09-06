# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "digest"

module Ethereum
  # =========================================================================
  # ⚓ STATE ROOT ANCHORING SERVICE (L1 Ethereum Mainnet)
  # =========================================================================
  # Реалізує архітектуру "State Root Anchoring" (Rollup-стиль):
  # один раз на тиждень криптографічний хеш усього стану SilkenNet
  # записується у смарт-контракт на Ethereum Mainnet (32 байти).
  #
  # Це фінальна печатка, яка доводить усьому світу:
  # "Те, що сталося в SilkenNet до цього моменту, є істиною,
  #  і її більше ніколи не можна змінити."
  #
  # Gas-ефективність: тільки 1 запис (bytes32) на тиждень.
  #
  # [BLOCKER-2] Зберігає state_root та tx_hash в EthereumAnchor для аудит-трейлу.
  # [BLOCKER-3] Gas management: max_fee_per_gas + gas_limit safety caps.
  # [BLOCKER-4] Inline ETH balance guard перед відправленням транзакції.
  # [BLOCKER-6] Зберігає компоненти state_root для незалежної верифікації.
  # =========================================================================
  class StateAnchorService
    # ABI для контракту StateRootAnchor на Ethereum Mainnet
    ANCHOR_ABI = [
      {
        "inputs" => [
          { "internalType" => "bytes32", "name" => "root", "type" => "bytes32" }
        ],
        "name" => "storeStateRoot",
        "outputs" => [],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    # [BLOCKER-3] Gas safety caps для L1 Ethereum транзакцій.
    # storeStateRoot(bytes32) потребує ~45,000 gas (1 SSTORE + event).
    # 100,000 — безпечна верхня межа з запасом.
    DEFAULT_GAS_LIMIT = 100_000

    # ⊕ [ARCH.62] Константи fee (100 Gwei cap / 2 Gwei tip) переїхали у
    # `Web3::FeePolicy` разом із присвоєнням — тримати їх тут означало б другий
    # дім для тих самих чисел. Імена ENV не змінились.

    # [BLOCKER-4] Мінімальний баланс ETH на oracle-гаманці для виконання L1 транзакції.
    # 0.01 ETH достатньо для ~3-5 storeStateRoot транзакцій при нормальних gas цінах.
    # [INF.22] Default value — fallback if SystemParameter not seeded yet.
    DEFAULT_MIN_ANCHOR_BALANCE_ETH = 0.01

    # [ARCH.66 companion] Node-помилки, що доводять: tx під нашим nonce уже досяг мережі (mined
    # або мемпул), тож same-nonce re-broadcast відхилено. На resume (`:pending` з персистованим
    # nonce) → перший broadcast landed, tx_hash втрачено у crash → escalate людині, не blind-retry.
    # Дзеркало money-path AMBIGUOUS-класу (celo `AMBIGUOUS_PATTERNS` / mint pre-broadcast whitelist).
    AMBIGUOUS_ALREADY_LANDED = /nonce too low|already known|replacement transaction underpriced|already imported/i

    # [ARCH.12] Верхня межа вікна = now − GRACE: рядок телеметрії, що комітиться ПІД ЧАС
    # repeatable_read-снапшота (created_at уже поставлено, commit ще ні), інакше випав би
    # з ЦЬОГО вікна назавжди (наступне стартує вище). GRACE >> insert-латентності; residual
    # (commit довший за GRACE) — теоретичний, задокументовано в 05_04. Історичні вікна
    # НЕ залежать від значення — обидві межі персистуються. One-Home значення = Mrv.
    WINDOW_GRACE = Mrv::WINDOW_GRACE

    # Генерує State Root — SHA256 дайджест, що об'єднує:
    # 1. Сумарний scc_balance усіх гаманців (SCC supply)
    # 2. Сумарний SFC balance усіх гаманців (SFC supply) — [E.53]
    # 3. Кількість активних дерев у екосистемі — [E.54]
    # 4. chain_hash останнього AuditLog
    # 5. Поточний timestamp (UTC)
    #
    # [BLOCKER-6] Повертає Hash з усіма компонентами для збереження в EthereumAnchor.
    #
    # [E.53] SFC supply включено до state root для повноти верифікації токеноміки.
    # SFC (SilkenForestCoin) є governance-токеном, його supply впливає на quorum та
    # voting power в DAO. Виключення з state root дозволяло б непомітну маніпуляцію.
    #
    # [E.54] Active tree count включено як метрика покриття екосистеми.
    # Різка зміна кількості активних дерев без відповідних audit events
    # може вказувати на маніпуляцію або системну помилку.
    #
    # [SNAPSHOT ISOLATION]: Обчислення state_root відбувається всередині транзакції
    # з рівнем ізоляції REPEATABLE READ. Це гарантує, що Wallet.sum(:scc_balance)
    # та AuditLog.pick(:chain_hash) бачать один і той самий "заморожений" знімок БД,
    # навіть якщо паралельний воркер (MintCarbonCoinWorker, AuditLogWorker) записує
    # дані між цими двома SQL-запитами.
    # [ARCH.12 Фаза 1а] state_root = Merkle-корінь: tier2-листя = [leaf0-агрегат] + cluster-субкорені.
    # leaf0 = SHA256 тієї САМОЇ агрегат-формули (EthereumAnchor.aggregate_payload — One-Home з
    # verify), тож supply-finality і незалежна верифікація з 5 збережених колонок живуть далі;
    # per-record телеметрія-листя (Mrv::TelemetryLeaf) дають inclusion-proof для ISO-звіту.
    def generate_state_root
      ActiveRecord::Base.transaction(isolation: :repeatable_read) do
        # [ARCH.97] ДВІ РІЗНІ ВЕЛИЧИНИ, і плутати їх не можна — доти якір ніс лише першу
        # під іменем другої. `balance` читається НАПРЯМУ, не через alias `scc_balance`:
        # доказовий шлях не має залежати від імені, що обіцяє монети (ARCH.88).
        total_growth_points = Wallet.sum(:balance).to_d
        total_scc_supply    = BlockchainTransaction.net_minted_supply(:carbon_coin).to_d
        # ⚠️ SFC — СИРА сума confirmed-мінтів (без віднімання burn'ів), і це коректно рівно
        # доти, доки SFC не палиться: `BlockchainBurningService` жорстко ставить
        # `carbon_coin`. Зʼявиться SFC-burn — цей рядок дістане ту саму ваду й мусить
        # перейти на `net_minted_supply(:forest_coin)`.
        total_sfc = BlockchainTransaction.where(token_type: :forest_coin, status: :confirmed).sum(:amount).to_d
        active_tree_count = Tree.active.count
        latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"
        timestamp = Time.current.utc

        leaf0 = Digest::SHA256.hexdigest(
          EthereumAnchor.aggregate_payload(
            total_growth_points: total_growth_points, total_scc_supply: total_scc_supply,
            total_sfc: total_sfc, active_tree_count: active_tree_count,
            chain_hash: latest_chain_hash, anchored_at: timestamp
          )
        )

        # Вікно ланцюжиться від window_to ПОПЕРЕДНЬОГО confirmed merkle-якоря (перший → from-genesis);
        # (from, to] — суміжні вікна не перетинаються і не лишають дір.
        window_from = EthereumAnchor.status_confirmed.where(root_version: 1)
                                    .order(anchored_at: :desc, id: :desc).pick(:window_to)
        window_to = timestamp - WINDOW_GRACE
        subroots, leaf_count = telemetry_subtree_roots(window_from, window_to)

        tier2 = [ { "kind" => "aggregate", "root" => leaf0 } ] + subroots
        state_root = MerkleTree.root(tier2.map { |entry| entry["root"] })

        {
          state_root: state_root,
          total_growth_points: total_growth_points,
          total_scc_supply: total_scc_supply,
          total_sfc: total_sfc,
          active_tree_count: active_tree_count,
          chain_hash: latest_chain_hash,
          anchored_at: timestamp,
          window_from: window_from,
          window_to: window_to,
          leaf_count: leaf_count,
          subtree_roots: tier2,
          root_version: 1
        }
      end
    end

    # Записує State Root у смарт-контракт на Ethereum Mainnet (L1).
    # [BLOCKER-2] Зберігає результат в EthereumAnchor для аудит-трейлу.
    # [BLOCKER-3] Використовує gas safety caps.
    # [BLOCKER-4] Перевіряє баланс ETH перед відправленням.
    # [DOUBLE-ANCHOR GUARD] Перевіряє наявність in-flight anchor перед створенням нового.
    #
    # @return [EthereumAnchor] Збережений запис з tx_hash та state_root.
    def anchor_to_l1!
      # [DOUBLE-ANCHOR GUARD] Якщо існує anchor зі статусом :pending або :sent за останній тиждень,
      # це означає, що попередня TX може бути в мемпулі Ethereum. Створення нового state_root
      # призведе до подвійного якорення (два state_root за один тиждень на L1).
      # Замість цього пробуємо дослати існуючий anchor.
      existing_anchor = EthereumAnchor.in_flight.order(created_at: :desc).first

      if existing_anchor&.status_sent?
        # TX вже відправлена і може бути в мемпулі — не відправляємо дублікат.
        # [ARCH.66] Re-arm поллер: якщо його попередній enqueue загубився (Redis-мигання на
        # perform_in) або той поллер помер, weekly-resume дає швидше відновлення за 6-год
        # sweeper-backstop. Дубль безпечний (confirm! with_lock + status_sent? = idempotent).
        EthereumAnchorConfirmationWorker.perform_async(existing_anchor.id)
        Rails.logger.info "⚓ [Ethereum L1] In-flight anchor detected (status: sent, " \
                          "tx_hash: #{existing_anchor.tx_hash}). Skipping to avoid double-anchoring."
        return existing_anchor
      end

      if existing_anchor&.status_pending?
        # Anchor створено, але TX не відправлена (crash між create! і transact).
        # Перевикористовуємо цей anchor замість генерації нового state_root.
        anchor = existing_anchor
        state_root = anchor.state_root
        Rails.logger.info "⚓ [Ethereum L1] Resuming pending anchor (state_root: #{state_root[0..15]}...)."
      else
        root_data = generate_state_root
        state_root = root_data[:state_root]

        # [BLOCKER-2] Створюємо запис до відправлення TX для crash recovery.
        # Race condition safety: unique_for: 7.days в Sidekiq запобігає паралельним запускам,
        # а DB unique index на state_root забезпечує додатковий захист.
        anchor = EthereumAnchor.create!(
          state_root: state_root,
          total_growth_points: root_data[:total_growth_points],
          total_scc_supply: root_data[:total_scc_supply],
          total_sfc: root_data[:total_sfc],
          active_tree_count: root_data[:active_tree_count],
          chain_hash: root_data[:chain_hash],
          anchored_at: root_data[:anchored_at],
          window_from: root_data[:window_from],
          window_to: root_data[:window_to],
          leaf_count: root_data[:leaf_count],
          subtree_roots: root_data[:subtree_roots],
          root_version: root_data[:root_version],
          status: :pending
        )
      end

      client = Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")
      # [SEC.17] Деривація — через seam `Web3::OracleSigner` (ENV-дефолт незмінний).
      signer = Web3::OracleSigner.for(:anchor)

      # [BLOCKER-4] Inline guard clause — перевірка балансу ETH перед відправленням.
      # [INF.22] Threshold configurable через SystemParameter (governance-aware, 24h cache).
      min_eth = (SystemParameter.current(:oracle_min_balance_eth, default: DEFAULT_MIN_ANCHOR_BALANCE_ETH) || DEFAULT_MIN_ANCHOR_BALANCE_ETH).to_f
      min_balance_wei = (min_eth * (10**18)).to_i
      balance = client.get_balance(signer.address)
      # 🔴 [ВИМІРЯНО 2026-09-06] НУЛЬ ≠ ВИЧЕРПАННЯ — четверта нога вже ратифікованого
      # присуду. 09-05 цей розкол відвантажили на Polygon, Celo й Solana, а L1-якір
      # свіп не дістав, тож ЄДИНА гілка тут стверджувала ВИТРАТУ («Insufficient»)
      # там, де адресу просто не поповнювали, і посилала оператора шукати витік,
      # якого не існує. Знайшов не аудит форми, а перелік того, ХТО ЩЕ належить до
      # класу ([`00_05 §3`](00_05_AI_Native_Operating_Model): ратифікувавши фікс,
      # свіпай не «де я його застосував», а «хто робить інакше»).
      # ⚠️ Тут це дорожче, ніж у сусідів: рядок ще й ПЕРСИСТИТЬСЯ в
      # `anchor.error_message`, тобто хибний діагноз переживає інцидент і читається
      # пізніше як факт.
      if balance.zero?
        anchor.update!(status: :failed, error_message: "Anchor wallet NOT PROVISIONED: balance is exactly 0")
        raise "🚨 [Ethereum L1] Якір НЕ ПРОВІЖИНЕНО: баланс рівно 0 — стан НАЛАШТУВАННЯ, не вичерпання. " \
              "⛔ Не шукати витік: звір `nonce` (0 = з адреси не йшло нічого)."
      elsif balance < min_balance_wei
        anchor.update!(status: :failed, error_message: "Insufficient ETH balance: #{balance}")
        raise "🚨 [Ethereum L1] Баланс якоря НИЖЧИЙ ЗА МІНІМУМ: #{balance} wei " \
              "(поріг #{min_balance_wei} wei) — витрачено більше, ніж поповнено."
      end

      contract_address = ENV.fetch("ETHEREUM_ANCHOR_CONTRACT")
      contract = Eth::Contract.from_abi(
        name: "StateRootAnchor",
        address: contract_address,
        abi: ANCHOR_ABI
      )

      # Конвертуємо SHA256 hex string → bytes32 для EVM
      root_bytes = "0x#{state_root}"

      # [BLOCKER-3] Gas management: явні ліміти та fee caps
      gas_limit = ENV.fetch("ETHEREUM_GAS_LIMIT", DEFAULT_GAS_LIMIT).to_i

      # [ARCH.66 companion — F2a double-send guard] Персистимо nonce ПЕРЕД broadcast. Crash між
      # transact() і update!(:sent) лишає anchor :pending з уже-персистованим nonce → resume-гілка
      # (нижче, existing_anchor&.status_pending?) ре-використає ТОЙ САМИЙ слот. Без цього resume
      # кликав би авто-nonce: pending-count уже врахував завислий tx → nonce+1 = ДРУГИЙ незалежний
      # on-chain запис (обидва майнились би; контракт revert'нув би дубль, але спалений gas +
      # брехливий :failed). Новий anchor → get_nonce (pending-tag) + persist; resume → nonce уже є,
      # get_nonce НЕ кликається → same-nonce re-broadcast (node: replace / already-known / nonce-too-low).
      anchor.update!(nonce: client.get_nonce(signer.address)) if anchor.nonce.nil?

      # 🔴 [SEC.17] FEE ЇДЕ АТРИБУТАМИ КЛІЄНТА, НЕ KWARG'АМИ — і це не стиль.
      # `Eth::Client#transact` (eth 0.5.17 `client.rb:322-336`) читає рівно
      # `tx_value/gas_limit/address/legacy/sender_key/nonce`; обидва fee-kwarg'и
      # він ІГНОРУЄ й бере значення з атрибутів клієнта. Доти ми їх сумлінно
      # рахували з ENV і передавали в порожнечу, тобто на дроті стояли gem-дефолти
      # `Tx::DEFAULT_GAS_PRICE` = 42.69 Gwei / `DEFAULT_PRIORITY_FEE` = 1.01 Gwei —
      # НИЖЧЕ за наші 100/2. Наслідок операційний, а не косметичний: на завантаженому
      # L1 (base fee > 42.69) якір не майниться взагалі й осідає в `:sent`-лімбі, а
      # `ETHEREUM_MAX_FEE_GWEI` — важіль, яким рунбук велить його розчистити, — не
      # робив НІЧОГО.
      # ⊕ [ARCH.62, 2026-08-28] Fee більше НЕ присвоюється тут — і зникла разом із
      # присвоєнням причина, чому воно стояло впритул до `transact`. Політика живе
      # у `Web3::FeePolicy` і накладається на МІСЦІ НАРОДЖЕННЯ клієнта
      # (`Web3::RpcConnectionPool#build_client`), тобто ДО того, як його візьме
      # будь-який споживач. Цей сервіс перестав бути єдиним місцем у дереві, де
      # fee взагалі існує, і став одним зі споживачів спільного дому — числа для
      # chain 1 там ті самі (`ETHEREUM_MAX_FEE_GWEI`/`ETHEREUM_PRIORITY_FEE_GWEI`,
      # дефолти 100/2), тож поведінка L1 не змінилась. Абзац вище лишається як
      # ІСТОРІЯ дефекту: він пояснює, ЧОМУ kwarg'и були оголошенням без механізму.
      # `gas_limit` лишається ТУТ свідомо — він властивість ЦЬОГО виклику
      # (~45k на `storeStateRoot`), а не мережі.

      tx_hash = signer.transact(
        client, contract, "storeStateRoot", root_bytes,
        nonce: anchor.nonce,
        legacy: false,
        gas_limit: gas_limit
      )

      # [BLOCKER-2] Оновлюємо запис з tx_hash
      anchor.update!(status: :sent, tx_hash: tx_hash)

      # [ARCH.66] Довершуємо lifecycle: поллер receipt'а → :confirmed/:failed/:manual_review.
      # Без цього anchor вічно :sent (fire-and-forget) → double-anchor guard деградує до
      # тижневого таймера. perform_in(30s) — receipt рідко готовий миттєво (дзеркало money-path).
      EthereumAnchorConfirmationWorker.perform_in(30.seconds, anchor.id)

      Rails.logger.info "⚓ [Ethereum L1] State Root anchored: #{state_root} → TX: #{tx_hash}"

      anchor
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      # [S6.7 DOUBLE-ANCHOR GUARD]: Do NOT mark as :failed on network timeout.
      # The TX may already be in the Ethereum mempool — marking :failed would cause
      # the retry to create a NEW state_root, risking double-anchoring on L1.
      # Keeping status :pending lets the in_flight guard resume this anchor on retry.
      # Note: error_message truncated to 450 chars to leave room for the ~50-char prefix.
      if anchor&.persisted?
        anchor.update!(error_message: "Timeout (TX may be in-flight): #{e.message.truncate(450)}")
        Rails.logger.warn "⚠️ [Ethereum L1] Timeout — anchor #{anchor.id} kept as :pending " \
                          "(TX may be in mempool). Next retry will resume. Error: #{e.message}"
      end
      raise "Ethereum L1 Timeout: #{e.message}"
    rescue Eth::Client::RpcError => e
      # [ARCH.66 companion] RpcError < IOError → МУСИТЬ бути перед `rescue IOError` нижче. На resume
      # (`:pending` з персистованим nonce) node-відмова `nonce too low`/`already known` доводить, що
      # перший broadcast під цим nonce уже досяг мережі до crash (tx_hash втрачено у вікні) — N+1
      # неможливий (той самий слот), тож escalate людині замість осідання у `:pending`-limbo (що
      # rescue IOError нижче й робив би). Не-ambiguous RpcError (fresh send: revert/insufficient
      # funds) → raise (Sidekiq retry / ConfirmationWorker вирішить долю). Дзеркало money-path.
      if anchor&.persisted? && anchor.status_pending? && ambiguous_already_landed?(e.message)
        anchor.escalate_pending_ambiguous!(
          "Resume re-broadcast rejected (nonce #{anchor.nonce} already used: #{e.message.truncate(200)}) — " \
          "перший broadcast досяг мережі, tx_hash втрачено у crash; звірити storeStateRoot на etherscan за " \
          "адресою #{signer.address} nonce #{anchor.nonce}."
        )
        Rails.logger.warn "⚓ [ARCH.66] Resume ambiguous ##{anchor.id} (nonce #{anchor.nonce} spent) → " \
                          ":manual_review (tx_hash lost, оператор звіряє etherscan)."
        return anchor
      end
      raise "Ethereum L1 RPC Error: #{e.message}"
    rescue IOError => e
      # [S6.7 DOUBLE-ANCHOR GUARD]: Same rationale as timeout — connection reset
      # after transact() means TX may have been broadcast before the socket closed.
      # Note: error_message truncated to 450 chars to leave room for the ~50-char prefix.
      if anchor&.persisted?
        anchor.update!(error_message: "Connection error (TX may be in-flight): #{e.message.truncate(450)}")
        Rails.logger.warn "⚠️ [Ethereum L1] Connection error — anchor #{anchor.id} kept as :pending " \
                          "(TX may be in mempool). Next retry will resume. Error: #{e.message}"
      end
      raise "Ethereum L1 Connection Error: #{e.message}"
    end

    private

    # [ARCH.12] Cluster-субкорені вікна (from, to]: детермінований порядок = cluster_id asc,
    # NULL-cluster sentinel-групою останньою; листя всередині кластера — (created_at, id) asc.
    # [transitional] один процес вантажить усе тижневе вікно в память (partition-scan hot-path;
    # стеля ~10^6 листя) — upgrade-path = per-cluster субкорінь-воркери поверх збережених
    # subtree_roots → ARCH.52. Ієрархія тут форму дає, масштаб ще ні (05_04).
    def telemetry_subtree_roots(window_from, window_to)
      base = TelemetryLog.joins(:tree).where(created_at: ..window_to)
      base = base.where("telemetry_logs.created_at > ?", window_from) if window_from

      cluster_ids = base.distinct.pluck("trees.cluster_id")
                        .sort_by { |cid| cid.nil? ? [ 1, 0 ] : [ 0, cid ] }
      leaf_count = 0

      subroots = cluster_ids.map do |cid|
        leaf_cids = base.where(trees: { cluster_id: cid })
                        .order(:created_at, :id)
                        .preload(:tree)
                        .map { |log| Mrv::TelemetryLeaf.cid_for(log) }
        leaf_count += leaf_cids.size
        { "cluster_id" => cid, "root" => MerkleTree.root(leaf_cids) }
      end

      [ subroots, leaf_count ]
    end

    # [ARCH.66 companion] Чи node-помилка = «tx під цим nonce уже досяг мережі» (див. AMBIGUOUS_ALREADY_LANDED).
    def ambiguous_already_landed?(message)
      AMBIGUOUS_ALREADY_LANDED.match?(message.to_s)
    end
  end
end
