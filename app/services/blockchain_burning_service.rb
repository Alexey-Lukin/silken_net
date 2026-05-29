# frozen_string_literal: true

require "eth"

class BlockchainBurningService < ApplicationService
  # ABI для функції вилучення/спалювання (Sovereign Slashing)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"investor","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"slash","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  # Кількість десяткових знаків токена (ERC-20 стандарт = 18).
  # Змініть тут, якщо почнемо підтримувати стейблкоіни з іншою розрядністю (напр. USDC = 6).
  TOKEN_DECIMALS = 18

  # [§6.2 Slashing curve — DAO-governed via SystemParameter ← ProtocolParameters.sol (05_03)]
  DEFAULT_SLASH_GAMMA = 1.3          # convex progressive curve (no dead-zone)
  DEFAULT_PENALTY_FACTOR_MAX = 2.0   # ceiling on the penalty MULTIPLIER (not final slash_ratio)
  DEFAULT_PENALTY_FACTOR = 1.0       # negligence baseline; cause-driven uplift = separate SLASH-1 task

  def initialize(organization_id, naas_contract_id, source_tree: nil)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
    @source_tree = source_tree
  end

  def perform
    # =========================================================================
    # [HYBRID PROTOCOL GAIA — SLASHING REDISTRIBUTION (Deflation)]
    #
    # Виклик slash() (який внутрішньо використовує _burn у Solidity) перманентно
    # видаляє токени з totalSupply ERC-20 контракту. Це створює дефляційний ефект:
    # загальна кількість SCC в обігу зменшується, що підвищує вартість кожного
    # залишкового токена, утримуваного чесними форестерами.
    #
    # Цей механізм "Slashing Redistribution" діє як неявна винагорода для всіх
    # учасників, що дотримуються умов контракту — їхня частка в загальному пулі
    # зростає без необхідності додаткового мінтингу.
    # =========================================================================

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
    # [§6.2] Progressive convex slash curve (damage_ratio^GAMMA × min(pf, MAX)),
    # NOT the old linear total × damage_ratio. See #calculate_slash_ratio.
    damage_ratio = calculate_damage_ratio
    slash_ratio  = calculate_slash_ratio(damage_ratio)
    burn_amount  = (total_minted_amount * slash_ratio).ceil

    return if burn_amount.zero?

    # 2. WEB3 ПІДГОТОВКА (The Judgment Bridge) — Thread-cached RPC client
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    # [E.2 ROLE SEPARATION]: Окремий ключ для SLASHER_ROLE зменшує blast radius
    # при компрометації — мінтинг залишається під окремим ключем.
    # Backward-compatible fallback на ORACLE_PRIVATE_KEY для існуючих деплоїв.
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_SLASHER_PRIVATE_KEY") { ENV.fetch("ORACLE_PRIVATE_KEY") })
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = Web3::WeiConverter.to_wei(burn_amount, TOKEN_DECIMALS)
    investor_address = @organization.crypto_public_address

    # 3. ВИКОНАННЯ (The Verdict)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil
      reason = @source_tree ? "загибель дерева #{@source_tree.did}" : "порушення умов кластера"

      Rails.logger.warn "🔥 [Slashing] Вилучення #{burn_amount}/#{total_minted_amount} SCC (damage #{(damage_ratio * 100).round(1)}% → slash #{(slash_ratio * 100).round(1)}%, §6.2 γ=#{slash_gamma}) у #{@organization.name}. Причина: #{reason}."

      # [ВИПРАВЛЕНО: Lock Duration]: 30 секунд достатньо для transact() (fire-and-forget,
      # повертається миттєво після відправки TX у мемпул). Операції всередині локу:
      # client.transact (~1-3s мережева затримка) + DB writes (~10-50ms) = ~5s worst case.
      # Попередній 60s лок був для transact_and_wait, який чекав підтвердження блоку.
      Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
        # [ВИПРАВЛЕНО: The 429 Trap]: Використовуємо transact (fire-and-forget) замість
        # transact_and_wait, який блокує Sidekiq-потік нескінченно при перевантаженні Polygon.
        # Підтвердження транзакції делеговано BlockchainConfirmationWorker (як у BlockchainMintingService).
        tx_hash = client.transact(
          contract, "slash", investor_address, amount_in_wei,
          sender_key: oracle_key, legacy: false
        )
      end

      # 4. ФІКСАЦІЯ (Immutable Audit)
      if tx_hash.present?
        # Маркуємо контракт як розірваний. Це автоматично блокує майбутні виплати.
        @naas_contract.update!(status: :breached)

        create_audit_transaction(tx_hash, burn_amount, reason)

        # [ВИПРАВЛЕНО]: Запускаємо воркер-підтверджувач для відстеження квитанції
        # (аналогічно BlockchainMintingService — transact + confirm pattern).
        BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)

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

  # [§6.2 Slashing curve] Progressive CONVEX penalty:
  #   slash_ratio = clamp(damage_ratio^GAMMA × min(penalty_factor, PENALTY_FACTOR_MAX), 0, 1.0)
  # Replaces the old LINEAR burn (total × damage_ratio — no GAMMA, no penalty_factor; the
  # verified code↔doc divergence, 00_01 §6.2 / 04_02 §11). GAMMA>1 makes the curve convex:
  # a small loss is punished gently (d=0.10 → ~5%) so an investor isn't wiped out over a
  # minor incident, yet full negligent loss reaches 100% (d=1.0, pf=1.0 → 1.0) — the
  # "no dead-zone" property (the old min(…, 0.40) ceiling that flat-lined 40%→100% damage
  # is removed). penalty_factor baseline 1.0 (negligence); cause-driven uplift (Streamr
  # gap, repeat offence) + signal de-correlation is a separate SLASH-1 sub-task.
  # GAMMA + PENALTY_FACTOR_MAX are DAO-governed (SystemParameter ← ProtocolParameters.sol).
  def calculate_slash_ratio(damage_ratio, penalty_factor = DEFAULT_PENALTY_FACTOR)
    return 0.0 if damage_ratio <= 0.0

    effective_pf = [ penalty_factor, penalty_factor_max ].min
    ((damage_ratio**slash_gamma) * effective_pf).clamp(0.0, 1.0)
  end

  # DAO-governed slash curve exponent (SystemParameter ← on-chain ProtocolParameters.sol).
  # Memoized per instance. Falls back to the canon default (1.3) when unset.
  def slash_gamma
    @slash_gamma ||= SystemParameter.current(:slash_gamma, default: DEFAULT_SLASH_GAMMA).to_f
  end

  # DAO-governed ceiling on the penalty MULTIPLIER (not the final slash_ratio). Memoized.
  def penalty_factor_max
    @penalty_factor_max ||= SystemParameter.current(:slash_penalty_factor_max, default: DEFAULT_PENALTY_FACTOR_MAX).to_f
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
