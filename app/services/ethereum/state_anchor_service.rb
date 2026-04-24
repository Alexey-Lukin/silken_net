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

    # [BLOCKER-3] Максимальна ціна газу: 100 Gwei.
    # Захищає від випадкових gas spikes (>500 Gwei як у грудні 2021).
    # Configurable через ENV для оперативного реагування на ринкові умови.
    DEFAULT_MAX_FEE_GWEI = 100

    # [BLOCKER-3] Пріоритетна ціна газу: 2 Gwei (tip для validators).
    DEFAULT_PRIORITY_FEE_GWEI = 2

    # [BLOCKER-4] Мінімальний баланс ETH на oracle-гаманці для виконання L1 транзакції.
    # 0.01 ETH достатньо для ~3-5 storeStateRoot транзакцій при нормальних gas цінах.
    MIN_ANCHOR_BALANCE_WEI = 0.01 * (10**18)

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
    def generate_state_root
      ActiveRecord::Base.transaction(isolation: :repeatable_read) do
        total_scc = Wallet.sum(:scc_balance)
        total_sfc = BlockchainTransaction.where(token_type: :forest_coin, status: :confirmed).sum(:amount)
        active_tree_count = Tree.active.count
        latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"
        timestamp = Time.current.utc

        payload = "#{total_scc}|#{total_sfc}|#{active_tree_count}|#{latest_chain_hash}|#{timestamp.iso8601}"
        state_root = Digest::SHA256.hexdigest(payload)

        {
          state_root: state_root,
          total_scc: total_scc,
          total_sfc: total_sfc,
          active_tree_count: active_tree_count,
          chain_hash: latest_chain_hash,
          anchored_at: timestamp
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
          total_scc: root_data[:total_scc],
          total_sfc: root_data[:total_sfc],
          active_tree_count: root_data[:active_tree_count],
          chain_hash: root_data[:chain_hash],
          anchored_at: root_data[:anchored_at],
          status: :pending
        )
      end

      client = Web3::RpcConnectionPool.client_for("ALCHEMY_ETHEREUM_RPC_URL")
      anchor_key = Eth::Key.new(priv: ENV.fetch("ETHEREUM_ANCHOR_PRIVATE_KEY"))

      # [BLOCKER-4] Inline guard clause — перевірка балансу ETH перед відправленням.
      balance = client.get_balance(anchor_key.address)
      if balance < MIN_ANCHOR_BALANCE_WEI
        anchor.update!(status: :failed, error_message: "Insufficient ETH balance: #{balance}")
        raise "🚨 [Ethereum L1] Insufficient anchor wallet balance: #{balance} wei " \
              "(minimum: #{MIN_ANCHOR_BALANCE_WEI.to_i} wei)"
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
      max_fee = ENV.fetch("ETHEREUM_MAX_FEE_GWEI", DEFAULT_MAX_FEE_GWEI).to_i * (10**9)
      priority_fee = ENV.fetch("ETHEREUM_PRIORITY_FEE_GWEI", DEFAULT_PRIORITY_FEE_GWEI).to_i * (10**9)
      gas_limit = ENV.fetch("ETHEREUM_GAS_LIMIT", DEFAULT_GAS_LIMIT).to_i

      tx_hash = client.transact(
        contract, "storeStateRoot", root_bytes,
        sender_key: anchor_key,
        legacy: false,
        gas_limit: gas_limit,
        max_fee_per_gas: max_fee,
        max_priority_fee_per_gas: priority_fee
      )

      # [BLOCKER-2] Оновлюємо запис з tx_hash
      anchor.update!(status: :sent, tx_hash: tx_hash)

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
  end
end
