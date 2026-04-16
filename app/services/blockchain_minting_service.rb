# frozen_string_literal: true

require "eth"
require "bigdecimal"

class BlockchainMintingService < ApplicationService
  # [HYBRID PROTOCOL GAIA]: Dynamic Minting Tax для фінансування DAO Treasury / Parametric Insurance Pool.
  # 2% від кожного карбонового мінтингу направляється до DAO Treasury, якщо страховий пул потребує фінансування.
  DYNAMIC_TAX_RATE = BigDecimal("0.02")

  # [B-05 FIX]: Цільовий поріг балансу DAO Treasury (у токенах SCC).
  # Якщо баланс DAO Treasury < порогу — Dynamic Tax активний (2% від емісії).
  # Якщо баланс >= порогу — податок вимикається, інвестори отримують 100%.
  INSURANCE_POOL_THRESHOLD = 100_000
  INSURANCE_POOL_THRESHOLD_WEI = INSURANCE_POOL_THRESHOLD * 10**18

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
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

    # [SAFETY]: Перевірка балансу Оракула
    balance = client.get_balance(oracle_key.address)
    raise "🚨 [Web3] Критично низький баланс Оракула: #{balance}" if balance < 0.05 * (10**18)

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

      # [ОПТИМІЗАЦІЯ]: Скорочуємо час локу, бо ми більше не чекаємо підтвердження блоку
      Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
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
          recipients = []
          amounts = []
          identifiers = []

          txs.each do |tx|
            if token_type == "carbon_coin" && insurance_pool_requires_funding?
              tax_amount = (tx.amount * DYNAMIC_TAX_RATE).round(4)
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

          Rails.logger.info "📦 [Web3] BatchMinting #{txs.size} транзакцій для #{token_type}..."

          # [DRY-RUN GUARD]: Симулюємо batchMint через eth_call перед реальною відправкою.
          # Якщо хоча б один запис у батчі спричиняє revert (наприклад, відкликаний Hadron KYC
          # між моментом перевірки та виконанням на блокчейні), весь атомарний batchMint впаде.
          # Dry-run виявляє "отруйний" запис ДО витрати газу і дозволяє fallback.
          if batch_dry_run_reverts?(client, contract, oracle_key, recipients, amounts, identifiers)
            Rails.logger.warn "⚠️ [Web3] batchMint dry-run reverted. Fallback на поодинокі mint()..."
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

  # [FALLBACK]: Поодинокий мінтинг для кожної транзакції з батча.
  # Викликається, коли dry-run batchMint виявив revert.
  # Кожна транзакція мінтиться окремо: "отруйний" запис fail'не сам,
  # а решта — успішно замінтяться. Gas дорожчий (~30-40%), але на Polygon
  # це ~$0.001/tx — прийнятна ціна за збереження 99% батча.
  def fallback_to_individual_mints(client, contract, oracle_key, token_type, txs)
    txs.each do |tx|
      begin
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
    end

    # Повертаємо nil — індивідуальні транзакції вже оброблені в циклі
    nil
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
  # Безпечний фолбек: при збої RPC повертає true (краще перефінансувати пул, ніж недофінансувати).
  def insurance_pool_requires_funding?
    Rails.cache.fetch(TREASURY_CACHE_KEY, expires_in: TREASURY_CACHE_TTL) do
      fetch_treasury_balance_wei < INSURANCE_POOL_THRESHOLD_WEI
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] DAO Treasury balance check failed: #{e.message}"
    true
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
end
