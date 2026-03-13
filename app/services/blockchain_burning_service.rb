# frozen_string_literal: true

require "eth"

class BlockchainBurningService < ApplicationService
  # ABI для функції вилучення/спалювання (Sovereign Slashing)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"investor","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"slash","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  # Кількість десяткових знаків токена (ERC-20 стандарт = 18).
  # Змініть тут, якщо почнемо підтримувати стейблкоіни з іншою розрядністю (напр. USDC = 6).
  TOKEN_DECIMALS = 18

  def initialize(organization_id, naas_contract_id, source_tree: nil)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
    @source_tree = source_tree
  end

  def perform
    # 1. АГРЕГАЦІЯ: Рахуємо всі токени, що були "зароблені" цим кластером.
    # [КЕНОЗИС]: Якщо порушення локальне (одне дерево), ми можемо вилучати
    # або частку, або весь контракт. Наразі йдемо шляхом повної ануляції за порушення гомеостазу.
    total_minted_amount = BlockchainTransaction
                          .joins(wallet: :tree)
                          .where(trees: { cluster_id: @cluster.id })
                          .where(status: :confirmed)
                          .sum(:amount)

    return if total_minted_amount.zero?

    # [КОЕФІЦІЄНТ ВТРАТ]: Спалюємо лише ту частку токенів, що відповідає
    # відсотку пошкодженої біомаси (розрахунок через AiInsight).
    # Це запобігає повній ануляції контракту при загибелі одного дерева з тисячі.
    damage_ratio = calculate_damage_ratio
    burn_amount  = (total_minted_amount * damage_ratio).ceil

    return if burn_amount.zero?

    # 2. WEB3 ПІДГОТОВКА (The Judgment Bridge) — Thread-cached RPC client
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = Web3::WeiConverter.to_wei(burn_amount, TOKEN_DECIMALS)
    investor_address = @organization.crypto_public_address

    # 3. ВИКОНАННЯ (The Verdict)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil
      reason = @source_tree ? "загибель дерева #{@source_tree.did}" : "порушення умов кластера"

      Rails.logger.warn "🔥 [Slashing] Вилучення #{burn_amount}/#{total_minted_amount} SCC (#{(damage_ratio * 100).round(1)}%) у #{@organization.name}. Причина: #{reason}."

      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        tx_hash = client.transact_and_wait(
          contract, "slash", investor_address, amount_in_wei,
          sender_key: oracle_key, legacy: false
        )
      end

      # 4. ФІКСАЦІЯ (Immutable Audit)
      if tx_hash.present?
        # Маркуємо контракт як розірваний. Це автоматично блокує майбутні виплати.
        @naas_contract.update!(status: :breached)

        create_audit_transaction(tx_hash, burn_amount, reason)

        # [OBSERVABILITY]: Track slashed tokens for Prometheus/Grafana
        SilkenNet::Metrics::SCC_SLASHED_TOTAL.increment(by: burn_amount)

        Rails.logger.info "✅ [Slashing] Виконано. TX: #{tx_hash}"
      end

    rescue StandardError => e
      # Контракт розривається в БД миттєво, навіть якщо блокчейн "лагає"
      @naas_contract.update!(status: :breached)
      handle_slashing_failure(e.message, total_minted_amount)
      raise e
    end
  end

  private

  def create_audit_transaction(tx_hash, amount, reason)
    # Пастка "Останнього дерева": якщо весь кластер мертвий, audit_wallet буде nil.
    # У такому разі прив'язуємо запис до самого кластера, а не до дерева-носія.
    audit_wallet = @source_tree&.wallet || @cluster.trees.active.first&.wallet

    BlockchainTransaction.create!(
      wallet:     audit_wallet,
      cluster:    audit_wallet.nil? ? @cluster : nil,
      sourceable: @naas_contract,
      to_address: @organization.crypto_public_address,
      amount:     amount,
      token_type: :carbon_coin,
      status:     :confirmed,
      tx_hash:    tx_hash,
      notes:      "🚨 SLASHING: Кошти вилучено. Причина: #{reason}."
    )
  end

  # Розраховує частку біомаси, що підлягає вилученню.
  # Використовує денні AiInsight-звіти, щоб не карати інвесторів за загибель
  # одного дерева з тисячі (Дракон vs. реальність).
  def calculate_damage_ratio
    total_trees = @cluster.trees.count
    return 1.0 if total_trees.zero?

    # Намагаємось отримати кількість критично стресованих дерев з AiInsight
    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    # [Cluster TZ]: Використовуємо часовий пояс кластера замість серверного Date.yesterday.
    critical_count = AiInsight
                     .daily_health_summary
                     .where(analyzable_type: "Tree", analyzable_id: @cluster.trees.select(:id), target_date: @cluster.local_yesterday)
                     .where("stress_index >= 1.0")
                     .count

    if critical_count.positive?
      # Частка пошкодженої біомаси (max 100%)
      [ critical_count.to_f / total_trees, 1.0 ].min
    elsif @source_tree.present?
      # Загибель одного конкретного дерева → пропорційна частка
      [ 1.0 / total_trees, 1.0 ].min
    else
      # Немає даних від AiInsight і немає конкретного дерева → повне вилучення
      1.0
    end
  end

  def handle_slashing_failure(error_msg, amount)
    Rails.logger.error "🛑 [Slashing Failure] ##{@naas_contract.id}: #{error_msg}"

    # Створюємо критичний алерт для ручного втручання Оракула
    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :system_fault,
      message: "Критичний збій спалювання #{amount} SCC. Можлива втрата контролю над активами інвестора. Error: #{error_msg}"
    )
  end
end
