# frozen_string_literal: true

require "eth"
require "bigdecimal"

class BlockchainMintingService < ApplicationService
  # [HYBRID PROTOCOL GAIA]: Dynamic Minting Tax для фінансування DAO Treasury / Parametric Insurance Pool.
  # 2% від кожного карбонового мінтингу направляється до DAO Treasury, якщо страховий пул потребує фінансування.
  # [S6.17]: Ставка тепер читається з SystemParameter (governance-aware, synced from on-chain ProtocolParameters.sol).
  DEFAULT_DYNAMIC_TAX_RATE = BigDecimal("0.02")

  # [B-05 FIX]: Цільовий поріг балансу DAO Treasury (у токенах SCC).
  # Якщо баланс DAO Treasury < порогу — Dynamic Tax активний (2% від емісії).
  # Якщо баланс >= порогу — податок вимикається, інвестори отримують 100%.
  # [S6.17]: Поріг тепер читається з SystemParameter (governance-aware).
  DEFAULT_INSURANCE_POOL_THRESHOLD = 100_000

  WEI_MULTIPLIER = 10**18

  # Мінімальний ABI для читання балансу ERC-20 (balanceOf).
  BALANCE_OF_ABI = [
    {
      "inputs" => [ { "internalType" => "address", "name" => "account", "type" => "address" } ],
      "name" => "balanceOf",
      "outputs" => [ { "internalType" => "uint256", "name" => "", "type" => "uint256" } ],
      "stateMutability" => "view",
      "type" => "function"
    }
  ].to_json

  # Кеш-ключ та TTL для on-chain запиту до DAO Treasury.
  # 15 хвилин — оптимальний TTL: стан пулу змінюється рідко (лише при страхових виплатах),
  # а максимальне навантаження на RPC = 4 запити/годину замість тисяч.
  TREASURY_CACHE_KEY = "dao_treasury_needs_funding"
  TREASURY_CACHE_TTL = 15.minutes
  TREASURY_RPC_TIMEOUT = 10

  # ABI оновлено для підтримки поштучного mint та пакетного batchMint
  CONTRACT_ABI = [
    {
      "inputs" => [
        { "internalType" => "address", "name" => "to", "type" => "address" },
        { "internalType" => "uint256", "name" => "amount", "type" => "uint256" },
        { "internalType" => "string", "name" => "identifier", "type" => "string" }
      ],
      "name" => "mint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    },
    {
      "inputs" => [
        { "internalType" => "address[]", "name" => "recipients", "type" => "address[]" },
        { "internalType" => "uint256[]", "name" => "amounts", "type" => "uint256[]" },
        { "internalType" => "string[]", "name" => "treeDids", "type" => "string[]" }
      ],
      "name" => "batchMint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    }
  ].to_json

  # Поштучний виклик — делегується через ApplicationService.call → new.perform
  def self.call(blockchain_transaction_id, telemetry_log: nil)
    new([ blockchain_transaction_id ], telemetry_log: telemetry_log).perform
  end

  # Пакетний виклик для цілого сектора/кластера
  def self.call_batch(blockchain_transaction_ids, telemetry_log: nil)
    new(blockchain_transaction_ids, telemetry_log: telemetry_log).perform
  end

  def initialize(transaction_ids, telemetry_log: nil)
    @transactions = BlockchainTransaction.where(id: transaction_ids)
                                         .where.not(status: :confirmed)
    @wallet_mapping = @transactions.includes(wallet: :tree).index_by(&:id)
    @telemetry_log = telemetry_log
  end

  def perform
    return if @transactions.empty?

    # [TRUSTLESS]: Перевірка децентралізованої верифікації перед мінтингом.
    # Guard clauses активні лише коли telemetry_log передано (oracle-driven flow).
    # TokenomicsEvaluatorWorker працює без telemetry_log — він конвертує вже
    # накопичені growth_points, які були зараховані через верифікований pipeline
    # (TelemetryUnpackerService → IoTeX → Chainlink → credit!).
    if @telemetry_log
      raise "Security Breach: Data not verified by IoTeX" unless @telemetry_log.verified_by_iotex?
      raise "Security Breach: Chainlink Oracle consensus not fulfilled" unless @telemetry_log.oracle_status_fulfilled?
    else
      # [BLOCKER-11 FIX]: Логування для аудиту — tokenomics flow працює без
      # прямої прив'язки до telemetry_log, але growth_points вже верифіковані.
      Rails.logger.info "📊 [Trustless] Batch minting без telemetry_log — " \
                        "використовуються накопичені верифіковані growth_points."
    end

    # [RWA COMPLIANCE]: Перевірка Hadron KYC для кожного гаманця-отримувача.
    # Інституційні токени (SCC/SFC) мінтяться ТІЛЬКИ для верифікованих гаманців.
    @wallet_mapping.each_value do |tx|
      recipient_wallet = tx.wallet
      unless recipient_wallet.hadron_kyc_status == "approved"
        raise "Compliance Breach: Wallet is not Hadron KYC approved"
      end
    end

    # 1. ПІДКЛЮЧЕННЯ (The Alchemy Link) — Thread-cached RPC client
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    # [E.2 ROLE SEPARATION]: Окремий ключ для MINTER_ROLE зменшує blast radius
    # при компрометації — slashing залишається під окремим ключем.
    # Backward-compatible fallback на ORACLE_PRIVATE_KEY для існуючих деплоїв.
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_MINTER_PRIVATE_KEY") { ENV.fetch("ORACLE_PRIVATE_KEY") })

    # [SAFETY]: Перевірка балансу Оракула
    # [E.51] Threshold configurable через SystemParameter (governance-aware, 24h cache).
    min_oracle_matic = (SystemParameter.current(:oracle_min_balance_matic, default: 0.05) || 0.05).to_f
    balance = client.get_balance(oracle_key.address)
    raise "🚨 [Web3] Критично низький баланс Оракула: #{balance}" if balance < min_oracle_matic * (10**18)

    # 2. ГРУПУВАННЯ ЗА ТИПОМ ТОКЕНА (SCC та SFC мають різні контракти)
    # ⚡ [ANTI-N+1]: Використовуємо preloaded @wallet_mapping для уникнення повторних запитів
    @wallet_mapping.values.group_by(&:token_type).each do |token_type, txs|
      process_token_group(client, oracle_key, token_type, txs)
    end
  end

  private

  def process_token_group(client, oracle_key, token_type, txs)
    contract_address = case token_type
    when "carbon_coin" then ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    when "forest_coin" then ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
    else raise ArgumentError, "Невідомий тип токена: #{token_type}"
    end

    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil

      # [S6.5 FIX]: Збільшено lock timeout з 30s до 120s для batch operations.
      # Хоча ми не чекаємо підтвердження блоку (fire-and-forget), batch minting може включати:
      #   - Dry-run eth_call (~3-5s)
      #   - Binary Search Isolation при revert: до MAX_BINARY_SEARCH_DEPTH=6 рівнів × 2 eth_call = ~36s
      #   - Fallback individual mints для poisoned records: до ~30 × transact() = ~90s
      # Загальний worst case: ~130s. З 30s lock виникає double-mint ризик при RPC congestion.
      Kredis.lock(lock_key, expires_in: 120.seconds, after_timeout: :raise) do
        # Переводимо всі транзакції в статус обробки
        txs.each do |tx|
          tx.update!(status: :processing)
          broadcast_tx_update(tx)
        end

        if txs.size == 1
          # Одиночний мінтинг (Fire-and-Forget)
          tx = txs.first
          # [ВИПРАВЛЕНО]: Використовуємо transact ЗАМІСТЬ transact_and_wait
          tx_hash = client.transact(
            contract, "mint", tx.to_address, to_wei(tx.amount), identifier_for(tx),
            sender_key: oracle_key, legacy: false
          )
        else
          # 💎 ПАКЕТНИЙ МІНТИНГ (Gas Saving Mode)
          # [HYBRID PROTOCOL GAIA]: Для carbon_coin при недофінансованому страховому пулі
          # застосовується Dynamic Tax — 2% від суми кожної транзакції направляється до DAO Treasury.
          # batchMint в Solidity підтримує array-based splitting, тому math виконується off-chain.
          recipients, amounts, identifiers = build_batch_arrays(txs, token_type)

          Rails.logger.info "📦 [Web3] BatchMinting #{txs.size} транзакцій для #{token_type}..."

          # [DRY-RUN GUARD]: Симулюємо batchMint через eth_call перед реальною відправкою.
          # Якщо хоча б один запис у батчі спричиняє revert (наприклад, відкликаний Hadron KYC
          # між моментом перевірки та виконанням на блокчейні), весь атомарний batchMint впаде.
          # Dry-run виявляє "отруйний" запис ДО витрати газу і дозволяє fallback.
          #
          # [BINARY SEARCH]: При збої dry-run замість наївного fallback на N окремих mint(),
          # використовується алгоритм бінарного пошуку для ізоляції "отруйних" записів.
          # Чисті підбатчі відправляються через batchMint, отруйні — поштучно.
          if batch_dry_run_reverts?(client, contract, oracle_key, recipients, amounts, identifiers)
            Rails.logger.warn "⚠️ [Web3] batchMint dry-run reverted. Binary search isolation for #{txs.size} txs..."
            tx_hash = fallback_to_individual_mints(client, contract, oracle_key, token_type, txs)
          else
            tx_hash = client.transact(
              contract, "batchMint", recipients, amounts, identifiers,
              sender_key: oracle_key, legacy: false
            )
          end
        end
      end

      # 5. ФІКСАЦІЯ ВІДПРАВКИ (The Sentinel State)
      if tx_hash.present?
        txs.each do |tx|
          # Оновлюємо статус на :sent і зберігаємо хеш для подальшого аудиту.
          # [TRUSTLESS]: Зберігаємо chainlink_request_id та zk_proof_ref для
          # перманентного зв'язку між on-chain транзакцією та її децентралізованим доказом.
          update_attrs = { status: :sent, tx_hash: tx_hash }
          if @telemetry_log
            update_attrs[:chainlink_request_id] = @telemetry_log.chainlink_request_id
            update_attrs[:zk_proof_ref] = @telemetry_log.zk_proof_ref
          end
          tx.update!(**update_attrs)
          broadcast_tx_update(tx)

          # [OBSERVABILITY]: Increment minted token counter for Prometheus
          SilkenNet::Metrics::SCC_MINTED_TOTAL.increment(labels: { token_type: token_type })
        end

        # Запускаємо воркер-підтверджувач, який прийде через 30 секунд перевірити квитанцію
        BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)

        Rails.logger.info "🛰️ [Web3] Пакет відправлено в мемпул. TX: #{tx_hash}"
      end

    rescue StandardError => e
      txs.each do |tx|
        tx.fail!(e.message.truncate(200))
        broadcast_tx_update(tx)
      end
      Rails.logger.error "🛑 [Web3 Failure] Пакетна помилка: #{e.message}"
      raise e
    end
  end

  # [DRY-RUN GUARD]: Симуляція batchMint через eth_call (zero-gas execution).
  # eth_call виконує код контракту на поточному блоці без створення транзакції.
  # Повертає true, якщо симуляція завершилась revert (батч містить "отруйний" запис).
  # При помилці підключення — повертає false (оптимістичний фолбек: спробувати transact).
  def batch_dry_run_reverts?(client, contract, oracle_key, recipients, amounts, identifiers)
    client.call(contract, "batchMint", recipients, amounts, identifiers, sender_key: oracle_key)
    false
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Web3] batchMint dry-run помилка: #{e.message}"
    # Розрізняємо EVM revert (контракт відхилив) від мережевих помилок (RPC timeout)
    evm_revert?(e)
  end

  # Визначає, чи помилка є EVM revert (контракт відхилив виконання).
  # Мережеві помилки (timeout, connection refused) не рахуються як revert.
  def evm_revert?(error)
    message = error.message.to_s.downcase
    message.include?("revert") || message.include?("execution reverted") || message.include?("out of gas")
  end

  # =========================================================================
  # 🔍 BINARY SEARCH POISONED RECORD ISOLATION (Divide & Conquer)
  # =========================================================================
  # Замість наївного fallback на N окремих mint() транзакцій при збої batchMint,
  # використовуємо бінарний пошук через безкоштовні eth_call dry-run для ізоляції
  # "отруйних" записів. Типовий сценарій (1-2 отруйних з 100) вирішується за
  # ~14 eth_call + 2-3 batchMint замість 100 окремих mint().
  #
  # Обмеження:
  #   - MIN_BINARY_SEARCH_SIZE (4): підбатчі менше цього → індивідуальні mints
  #   - MAX_BINARY_SEARCH_DEPTH (6): запобігає нескінченній рекурсії (~2^6 = 64 мін. елементів)
  #   - Poisoned ratio guard: якщо >30% батча отруйні → fallback на індивідуальні mints
  # =========================================================================

  # Мінімальний розмір підбатча для binary search. Менші батчі мінтяться поштучно.
  MIN_BINARY_SEARCH_SIZE = 4

  # Максимальна глибина рекурсії binary search (запобігає нескінченному поділу).
  MAX_BINARY_SEARCH_DEPTH = 6

  # Поріг "отруйності" — якщо більше 30% транзакцій отруйні, binary search неефективний.
  POISONED_RATIO_THRESHOLD = 0.3

  # [FALLBACK]: Ізоляція "отруйних" записів через бінарний пошук (Divide & Conquer).
  # Якщо batchMint dry-run впав, розбиваємо батч навпіл і тестуємо кожну половину.
  # "Чисті" половини відправляються через batchMint, "отруйні" — далі діляться.
  # Результат: 99 з 100 транзакцій відправляються 1-2 batchMint, 1 отруйна — mint().
  def fallback_to_individual_mints(client, contract, oracle_key, token_type, txs)
    poisoned = []
    clean = []
    original_batch_size = txs.size

    # Запускаємо бінарний пошук для ізоляції отруйних записів
    isolate_poisoned_records(client, contract, oracle_key, token_type, txs, poisoned, clean,
                             depth: 0, original_batch_size: original_batch_size)

    Rails.logger.info "🔍 [Web3] Binary search result: #{clean.size} clean, #{poisoned.size} poisoned out of #{original_batch_size}"

    # Відправляємо "чисті" транзакції оптимальними батчами
    clean.each_slice(Treasury::MintBatchCollectorService::OPTIMAL_BATCH_SIZE) do |batch|
      send_clean_batch(client, contract, oracle_key, token_type, batch)
    end

    # Мінтимо "отруйні" транзакції поштучно (вони, ймовірно, впадуть)
    poisoned.each do |tx|
      mint_individual(client, contract, oracle_key, token_type, tx)
    end

    # Повертаємо nil — всі транзакції вже оброблені
    nil
  end

  # Рекурсивний бінарний пошук для ізоляції отруйних записів.
  # Кожен рівень рекурсії ділить батч навпіл і тестує через eth_call dry-run.
  def isolate_poisoned_records(client, contract, oracle_key, token_type, txs, poisoned, clean, depth:, original_batch_size:)
    # Базовий випадок: батч занадто малий або досягнуто максимальної глибини — мінтимо поштучно
    if txs.size < MIN_BINARY_SEARCH_SIZE || depth >= MAX_BINARY_SEARCH_DEPTH
      Rails.logger.info "🔍 [Web3] Binary search: #{txs.size} txs at depth=#{depth} below threshold, marking as potentially poisoned"
      txs.each { |tx| poisoned << tx }
      return
    end

    # Перевіряємо, чи ще ефективний binary search (>30% від оригінального батча отруйні — fallback)
    if poisoned.any? && poisoned.size > original_batch_size * POISONED_RATIO_THRESHOLD
      Rails.logger.warn "⚠️ [Web3] Binary search: >30% poisoned (#{poisoned.size}/#{original_batch_size}). " \
                        "Fallback to individual mints for remaining #{txs.size} txs."
      txs.each { |tx| poisoned << tx }
      return
    end

    mid = txs.size / 2
    left_half = txs[0...mid]
    right_half = txs[mid..]

    # Тестуємо ліву половину через dry-run
    process_half(client, contract, oracle_key, token_type, left_half, poisoned, clean,
                 depth: depth, original_batch_size: original_batch_size)

    # Тестуємо праву половину через dry-run
    process_half(client, contract, oracle_key, token_type, right_half, poisoned, clean,
                 depth: depth, original_batch_size: original_batch_size)
  end

  # Обробляє одну половину батча: dry-run → clean або рекурсивний поділ.
  def process_half(client, contract, oracle_key, token_type, half_txs, poisoned, clean, depth:, original_batch_size:)
    return if half_txs.empty?

    recipients, amounts, identifiers = build_batch_arrays(half_txs, token_type)

    if batch_dry_run_reverts?(client, contract, oracle_key, recipients, amounts, identifiers)
      # Ця половина містить отруйний запис — ділимо далі
      Rails.logger.info "🔍 [Web3] Binary search depth=#{depth + 1}: sub-batch of #{half_txs.size} reverted, splitting..."
      isolate_poisoned_records(client, contract, oracle_key, token_type, half_txs, poisoned, clean,
                               depth: depth + 1, original_batch_size: original_batch_size)
    else
      # Ця половина чиста — додаємо до clean
      clean.concat(half_txs)
    end
  end

  # Будує масиви recipients/amounts/identifiers для підбатча (з Dynamic Tax).
  def build_batch_arrays(txs, token_type)
    recipients = []
    amounts = []
    identifiers = []

    txs.each do |tx|
      if token_type == "carbon_coin" && insurance_pool_requires_funding?
        tax_amount = (tx.amount * dynamic_tax_rate).round(4)
        forester_amount = tx.amount - tax_amount

        recipients.push(tx.to_address, ENV.fetch("DAO_TREASURY_ADDRESS"))
        amounts.push(to_wei(forester_amount), to_wei(tax_amount))
        identifiers.push(identifier_for(tx), "TAX_#{identifier_for(tx)}")
      else
        recipients.push(tx.to_address)
        amounts.push(to_wei(tx.amount))
        identifiers.push(identifier_for(tx))
      end
    end

    [ recipients, amounts, identifiers ]
  end

  # Відправляє "чистий" батч через batchMint (або mint для одиночних).
  def send_clean_batch(client, contract, oracle_key, token_type, txs)
    return if txs.empty?

    if txs.size == 1
      mint_individual(client, contract, oracle_key, token_type, txs.first)
      return
    end

    recipients, amounts, identifiers = build_batch_arrays(txs, token_type)

    tx_hash = client.transact(
      contract, "batchMint", recipients, amounts, identifiers,
      sender_key: oracle_key, legacy: false
    )

    txs.each { |tx| finalize_sent_transaction(tx, tx_hash, token_type) }

    Rails.logger.info "✅ [Web3] Clean sub-batch of #{txs.size} sent via batchMint. TX: #{tx_hash}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] Clean batch failed (#{txs.size} txs): #{e.message}. Falling back to individual mints."
    txs.each { |tx| mint_individual(client, contract, oracle_key, token_type, tx) }
  end

  # Мінтить одну транзакцію індивідуально з обробкою помилок.
  def mint_individual(client, contract, oracle_key, token_type, tx)
    individual_tx_hash = client.transact(
      contract, "mint", tx.to_address, to_wei(tx.amount), identifier_for(tx),
      sender_key: oracle_key, legacy: false
    )

    finalize_sent_transaction(tx, individual_tx_hash, token_type)
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] Individual mint failed for TX ##{tx.id}: #{e.message}"
    tx.fail!(e.message.truncate(200))
    broadcast_tx_update(tx)
  end

  # Фіналізує транзакцію після успішної відправки (shared logic для batch та individual).
  def finalize_sent_transaction(tx, tx_hash, token_type)
    update_attrs = { status: :sent, tx_hash: tx_hash }
    if @telemetry_log
      update_attrs[:chainlink_request_id] = @telemetry_log.chainlink_request_id
      update_attrs[:zk_proof_ref] = @telemetry_log.zk_proof_ref
    end
    tx.update!(**update_attrs)
    broadcast_tx_update(tx)

    SilkenNet::Metrics::SCC_MINTED_TOTAL.increment(labels: { token_type: token_type })

    # Запускаємо підтверджувач для кожної індивідуальної транзакції
    BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)
  end

  def identifier_for(tx)
    tree = tx.wallet.tree
    tx.token_type == "carbon_coin" ? (tree&.did || "ORG_#{tx.wallet.organization_id}") : "CLUSTER_#{tree&.cluster_id || 'GLOBAL'}"
  end

  def to_wei(amount)
    Web3::WeiConverter.to_wei(amount)
  end

  # [B-05 FIX]: Cached On-Chain Oracle для перевірки стану Parametric Insurance Pool.
  # Виконує eth_call balanceOf на SCC-контракті для адреси DAO Treasury.
  # Результат кешується на 15 хвилин — стан пулу змінюється рідко (лише при страхових виплатах).
  #
  # [E.46 FIX]: При збої RPC повертаємо false — не накладаємо 2% Dynamic Tax під час деградації мережі.
  # Rationale: False negative (пропущений внесок до пулу) безпечніший за false positive
  # (постійний 2% податок на кожен mint при тривалому RPC outage). Пул поповниться при
  # наступному успішному виклику. Помилка логується для моніторингу (Sentry + Prometheus).
  def insurance_pool_requires_funding?
    Rails.cache.fetch(TREASURY_CACHE_KEY, expires_in: TREASURY_CACHE_TTL) do
      fetch_treasury_balance_wei < insurance_pool_threshold_wei
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] DAO Treasury balance check failed (RPC degraded): #{e.message}"
    # [E.46] Завжди false при RPC-збої — не штрафуємо мінтинг під час деградації мережі.
    false
  end

  # Повертає баланс DAO Treasury у wei (Integer) для точного порівняння без Float.
  def fetch_treasury_balance_wei
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    contract = Eth::Contract.from_abi(
      name: "SilkenCarbonCoin",
      address: ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS"),
      abi: BALANCE_OF_ABI
    )

    treasury_address = ENV.fetch("DAO_TREASURY_ADDRESS")

    raw = Timeout.timeout(TREASURY_RPC_TIMEOUT) do
      client.call(contract, "balanceOf", treasury_address)
    end

    Integer(raw)
  end

  def broadcast_tx_update(transaction)
    wallet = transaction.wallet

    # Оновлення рядка в таблиці через Hotwire
    Turbo::StreamsChannel.broadcast_replace_to(
      wallet,
      target: "transaction_#{transaction.id}",
      html: Wallets::TransactionRow.new(tx: transaction).call
    )

    # Оновлення балансу (тільки при успіху або старті)
    Turbo::StreamsChannel.broadcast_replace_to(
      wallet,
      target: "wallet_balance_#{wallet.id}",
      html: Wallets::BalanceDisplay.new(wallet: wallet).call
    )
  end

  # [S6.17] Governance-aware Dynamic Tax Rate.
  # Reads from SystemParameter (synced from on-chain ProtocolParameters.sol via ParameterSyncWorker).
  # Falls back to DEFAULT_DYNAMIC_TAX_RATE if not set.
  def dynamic_tax_rate
    BigDecimal(SystemParameter.current(:dynamic_tax_rate, default: DEFAULT_DYNAMIC_TAX_RATE).to_s)
  end

  # [S6.17] Governance-aware Insurance Pool Threshold.
  def insurance_pool_threshold
    SystemParameter.current(:insurance_pool_threshold, default: DEFAULT_INSURANCE_POOL_THRESHOLD).to_i
  end

  # [S6.17] Computed threshold in wei for on-chain balance comparison.
  def insurance_pool_threshold_wei
    insurance_pool_threshold * WEI_MULTIPLIER
  end
end
