# frozen_string_literal: true

require "eth"

class BlockchainBurningService < ApplicationService
  # ABI для функції вилучення/спалювання (Sovereign Slashing)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"investor","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"slash","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  # Кількість десяткових знаків токена (ERC-20 стандарт = 18).
  # Змініть тут, якщо почнемо підтримувати стейблкоіни з іншою розрядністю (напр. USDC = 6).
  TOKEN_DECIMALS = 18

  # [05_05 §3 Slashing curve — DAO-governed via SystemParameter ← ProtocolParameters.sol (05_03)]
  DEFAULT_SLASH_GAMMA = 1.3          # convex progressive curve (no dead-zone)
  DEFAULT_PENALTY_FACTOR_MAX = 2.0   # ceiling on the penalty MULTIPLIER (not final slash_ratio)
  DEFAULT_PENALTY_FACTOR = 1.0       # negligence baseline (no cause-driven uplift)

  # [SLASH-1 §3/§6] Ваги cause-driven penalty_factor uplift (дзеркало канону 05_05 §3 —
  # правити ТАМ). Comms-correlated сигнали (no-ack, Streamr gap) мають ОДИН root-cause
  # «вузол/шлюз offline» → комбінуються через max(), НЕ суму (SLASH-SAFETY §6, як sap+acoustic
  # max() у §7); фізична халатність — незалежна → additive. Promotable до SystemParameter коли
  # DAO калібрує (як GAMMA/PF_MAX). Комбінатор — #calculate_penalty_factor.
  PF_NO_ACK         = 0.5   # comms-correlated: непідтверджений critical EwsAlert (no ack)
  PF_STREAMR_GAP    = 0.25  # comms-correlated: tree-side Streamr gap (guarded hook)
  PF_NO_MAINTENANCE = 0.5   # independent: critical EwsAlert без MaintenanceRecord

  # @param contractual [Boolean] true — це погоджена контрактна форфейтура (early-exit
  #   `burn_accrued_points`, `ContractTerminationService`), НЕ slash-за-провину → гейт
  #   positive-A пропускається (інвестор сам розірвав, burn — погоджена умова, не Кат-A).
  def initialize(organization_id, naas_contract_id, source_tree: nil, contractual: false, target_date: nil)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
    @source_tree = source_tree
    @contractual = contractual
    # [ARCH.46] Дата для damage-ratio — прокинута від ContractHealthCheckService (де порахована
    # й де відбувся blackout-guard), щоб burn НЕ перевираховував local_yesterday у свій момент
    # (date-mismatch → запит на іншу добу → нуль записів → хибне 100%). Інші тригери
    # (tree-death/dClimate/contractual) дати не передають → дефолт local_yesterday (їх поведінка).
    @target_date = target_date
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

    # [SLASH-1 §3.2] Positive-A-evidence gate — на чокпоінті, накриває всі тригери burn.
    # Необоротний slash() лише за прямого доказу Кат-A (tamper); інакше freeze (Field Audit,
    # Кат-C) — відновлює канон-дефолт §2 «freeze-поки-не-A», а не палить-поки-не-відведено.
    # Контрактна форфейтура (early-exit) — свідомий виняток. Freeze дзеркалить flag_data_blackout!.
    unless @contractual || positive_a_evidence?
      return freeze_for_field_audit!
    end

    # [ARCH.45/ARCH.48] In-flight guard ПІСЛЯ positive-A gate (лише slash-шлях, НЕ freeze — інакше
    # intent-сміття для заморожених). `unsettled_within` (вкл. :manual_review), бо ambiguous slash
    # (broadcast невідомий) ескалюється у :manual_review і МУСИТЬ блокувати re-slash:
    #   :sent          → slash уже broadcast → :slashed без повтору (ConfirmationWorker дорезолвить);
    #   :manual_review → ambiguous (можливо-landed, ARCH.48) → НЕ повторюємо до ручної звірки;
    #   :pending       → крах ДО broadcast → старий intent у :failed, перепускаємо й re-slash-имо.
    existing_slash = BlockchainTransaction.where(sourceable: @naas_contract).unsettled_within(2.hours).order(created_at: :desc).first
    if existing_slash
      if existing_slash.status_sent?
        # Re-arm confirmation worker — на випадок краху до його планування на
        # першій спробі (ConfirmationWorker сам дедуплікує за tx_hash через unique_for).
        BlockchainConfirmationWorker.perform_in(30.seconds, existing_slash.tx_hash, existing_slash.created_at.iso8601) if existing_slash.tx_hash.present? # [ARCH.52] partition-prune
        return :slashed
      end

      if existing_slash.status_manual_review?
        # [ARCH.48] Попередній slash міг потрапити в мемпул до RPC-збою (intent escalate-нуто) —
        # blind re-slash = double-burn. Чекаємо ручну звірку на Polygonscan, не повторюємо.
        Rails.logger.warn "⚠️ [Slashing] ##{@naas_contract.id}: попередній slash у manual_review (можливо-landed) — НЕ повторюємо."
        return :manual_review
      end

      existing_slash.fail!("Superseded — re-slash після pre-broadcast краху (ARCH.45)")
    end

    # [КОЕФІЦІЄНТ ВТРАТ]: Спалюємо лише ту частку токенів, що відповідає
    # відсотку пошкодженої біомаси (розрахунок через AiInsight).
    # Це запобігає повній ануляції контракту при загибелі одного дерева з тисячі.
    # [05_05 §3] Progressive convex slash curve (damage_ratio^GAMMA × min(pf, MAX)),
    # NOT the old linear total × damage_ratio. See #calculate_slash_ratio.
    damage_ratio = calculate_damage_ratio

    # [ARCH.46] Genuine no-data (нуль AiInsight-записів за дату, fault-шлях без конкретного дерева)
    # → magnitude indeterminate → freeze (Кат-C), НЕ worst-case 100%. positive-A довів ПРИЧИНУ
    # (tamper), але РОЗМІР шкоди потребує власних даних (§3.2: burn необоротний, freeze — ні).
    # Дзеркало flag_data_blackout!; contractual-форфейтура сюди не доходить (damage_ratio → 1.0).
    return freeze_for_field_audit!(reason: :indeterminate_magnitude) if damage_ratio.nil?

    slash_ratio  = calculate_slash_ratio(damage_ratio, calculate_penalty_factor)
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

    audit = nil
    begin
      tx_hash = nil
      outcome = nil
      reason = @source_tree ? "загибель дерева #{@source_tree.did}" : "порушення умов кластера"

      Rails.logger.warn "🔥 [Slashing] Вилучення #{burn_amount}/#{total_minted_amount} SCC (damage #{(damage_ratio * 100).round(1)}% → slash #{(slash_ratio * 100).round(1)}%, 05_05 §3 γ=#{slash_gamma}) у #{@organization.name}. Причина: #{reason}."

      # [ARCH.45] Durable intent-marker (:pending, sourceable: contract) ПЕРЕД on-chain slash.
      # На краху retry бачить його через in-flight guard (вгорі) і не палить удруге.
      audit = create_slash_intent!(burn_amount, reason)
      SilkenNet::Metrics::SLASH_ATTEMPTS_TOTAL.increment

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
        # [ARCH.45] Intent → :sent (BlockchainConfirmationWorker дорезолвить :confirmed/:failed).
        audit.mark_as_sent!(tx_hash)
        SilkenNet::Metrics::SLASH_SUCCESS_TOTAL.increment

        # [ARCH.45] Воркер-підтверджувач планується ОДРАЗУ після mark_as_sent —
        # ДО breach-update. Інакше крах на breach-update лишав би :sent tx без жодного
        # confirmation-воркера (orphan), а retry рано-повертав би через in-flight guard.
        BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash, audit.created_at.iso8601) # [ARCH.52] partition-prune

        # Маркуємо контракт як розірваний. Це автоматично блокує майбутні виплати.
        @naas_contract.update!(status: :breached)

        # [OBSERVABILITY]: Track slashed tokens for Prometheus/Grafana
        SilkenNet::Metrics::SCC_SLASHED_TOTAL.increment(by: burn_amount)

        Rails.logger.info "✅ [Slashing] Виконано. TX: #{tx_hash}"
        outcome = :slashed
      end

      outcome

    rescue Kredis::LockTimeout => e
      # [ARCH.48] Лок НЕ взято → `transact` НЕ виконувався → tx НЕ у мемпулі → безпечно retry-ити.
      # Саме той мовчазний-abort, який ARCH.48 лікує: раніше rescue breach-ив контракт, а worker-guard
      # `return if status_breached?` глушив кожен retry → on-chain `slash()` ніколи не транслювався.
      # Тепер контракт лишається `:active`, intent → :failed (НЕ in-flight) → re-raise → Sidekiq retry re-slash-ить.
      # audit гарантовано створено (ПЕРЕД локом) і `:pending` (transact не виконувався).
      audit&.fail!("Slash lock-timeout: #{e.message}")
      handle_slashing_failure(e.message, total_minted_amount)
      raise e
    rescue StandardError => e
      if audit&.status_sent?
        # [ARCH.45] Broadcast УЖЕ стався (tx_hash отримано) — крах ПІСЛЯ `mark_as_sent` (ConfirmationWorker
        # / breach-update). Slash потрапить у ланцюг → контракт МАЄ бути `:breached` (як і раніше); re-arm
        # confirmation (`:sent` ⇒ tx_hash присутній — model-validated). Retry безпечний — guard побачить :sent.
        @naas_contract.update!(status: :breached)
        BlockchainConfirmationWorker.perform_in(30.seconds, audit.tx_hash, audit.created_at.iso8601) # [ARCH.52] partition-prune
        handle_slashing_failure(e.message, total_minted_amount)
        raise e
      end

      # [ARCH.48] Помилка З `transact`, intent ще `:pending` — AMBIGUOUS: tx міг піти в мемпул до того,
      # як RPC-відповідь загубилась (RPC-лаг) → blind retry = double-burn (свіжий nonce, другий
      # необоротний slash). ARCH.45-інваріант: ескалюй у manual_review, НІКОЛИ не re-attempt наосліп.
      # Контракт лишається `:active` (НЕ :breached); :manual_review блокує re-slash (in-flight guard вгорі).
      # НЕ raise → без Sidekiq retry; повертаємо :manual_review → людська звірка на Polygonscan.
      audit&.escalate_to_review!("Slash міг піти в мемпул до збою — звір на Polygonscan ПЕРЕД повтором: #{e.message}")
      handle_slashing_failure("AMBIGUOUS (можливо-landed — НЕ авто-повтор): #{e.message}", total_minted_amount)
      :manual_review
    end
  end

  private

  # [SLASH-1 §3.2] Чи є прямий доказ Категорії A для цього кластера. Дім сигналів —
  # Slashing::CauseEvidence (фаза-1 = tamper). source_tree пробрасується для майбутнього
  # per-tree звуження.
  def positive_a_evidence?
    Slashing::CauseEvidence.new(@cluster, source_tree: @source_tree).positive_a?
  end

  # [SLASH-1 §3.2] Freeze (Категорія C) — спалення заблоковано, бо немає прямого доказу A.
  # Дзеркалить ContractHealthCheckService#flag_data_blackout!: піднімає critical Field-Audit
  # алерт (system_fault), НЕ палить і НЕ breach-ить контракт (лишається :active до людської
  # класифікації A/B/C). Burn необоротний, freeze — ні (05_05 §3.2 асиметрія). Повертає :frozen.
  def freeze_for_field_audit!(reason: :no_category_a_evidence)
    # Контекст для аудитора (дзеркало slash-`reason`): конкретне дерево, якщо є джерело,
    # інакше — кластер. Дає Field-Audit з чого почати C→A класифікацію.
    context = @source_tree ? "дерево #{@source_tree.did}" : "кластер ##{@cluster.id}"

    # [ARCH.46] Два приводи для freeze (обидва → Кат-C, no burn/breach): немає прямого доказу A
    # (positive-A gate) АБО доказ A є, але РОЗМІР шкоди невизначений (нема AiInsight-даних). Меседж
    # диференціюємо, щоб Field-Audit мав чіткий triage-контекст (дедуп — 00_07 SLASH-1).
    detail = if reason == :indeterminate_magnitude
               "доказ Категорії A є, але РОЗМІР шкоди невизначений (нема AiInsight-даних за дату)"
    else
               "немає прямого доказу Категорії A"
    end

    Rails.logger.warn "🧊 [SLASH-1] NaasContract ##{@naas_contract.id} (#{context}): спалення заблоковано — #{detail} (05_05 §3.2) → Field Audit, без burn/breach."

    # [SLASH-1] :field_audit (не :system_fault): freeze — це НАШ вирок «слухай, не карай»,
    # а не доказ «вузол offline». Окремий тип не дає freeze самонакручувати penalty_factor
    # через comms_no_ack? (ARCH.46 gap-D) і не конфлатить аудит із comms-fault при дедупі.
    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :field_audit,
      message: "Слешинг заблоковано (#{context}): #{detail}. Кошти НЕ спалено — потрібен Field Audit (Категорія C, 05_05 §3.2/§5)."
    )

    :frozen
  end

  # [ARCH.45] Intent-marker :pending ДО on-chain slash (sourceable: contract = ключ in-flight
  # guard). mark_as_sent! проставить tx_hash після broadcast; BlockchainConfirmationWorker
  # дорезолвить :sent→:confirmed/:failed. Раніше створювався одразу :confirmed за фактом слешу.
  def create_slash_intent!(amount, reason)
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
      status:     :pending,
      notes:      "🚨 SLASHING: Кошти вилучено. Причина: #{reason}."
    )
  end

  # Розраховує частку біомаси, що підлягає вилученню (damage_ratio ∈ [0,1], або nil). Гілки:
  #   • contractual          → погоджене повне вилучення (early-exit форфейтура; ПЕРШОЮ — не damage-based)
  #   • critical>0           → пропорційно (stressed+dead / total — канон §3)
  #   • source_tree          → загибель конкретного дерева (1/total)
  #   • дані Є, 0 critical    → ліс здоровий → 0 шкоди → 0 slash
  #   • genuine no-data → nil → magnitude indeterminate → `perform` робить freeze (§3.2 асиметрія,
  #     дзеркало `flag_data_blackout!`), НЕ 100% worst-case
  # [ARCH.46] Поріг = `AiInsight::SLASH_STRESS_THRESHOLD` (= той самий, що ТРИГЕРИТЬ слеш у
  # `ContractHealthCheckService`; раніше хибне `≥ 1.0` → помірний стрес давав critical=0 → 100%
  # over-burn). Дата прокинута від health-check (`effective_target_date`), без перерахунку.
  def calculate_damage_ratio
    total_trees = @cluster.trees.count
    return 1.0 if total_trees.zero?
    # Contractual — ПЕРШОЮ: повне погоджене вилучення, не залежить від damage; AiInsight-запит зайвий.
    return 1.0 if @contractual

    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree", analyzable_id: @cluster.trees.select(:id), target_date: effective_target_date
    )
    critical_count = daily_insights.where("stress_index >= ?", AiInsight::SLASH_STRESS_THRESHOLD).count

    if critical_count.positive?
      [ critical_count.to_f / total_trees, 1.0 ].min   # пропорційно (stressed+dead / total)
    elsif @source_tree.present?
      [ 1.0 / total_trees, 1.0 ].min                   # загибель конкретного дерева
    elsif daily_insights.exists?
      0.0                                              # дані Є, ліс здоровий → 0 шкоди → 0 slash
    end
    # else: нуль AiInsight-записів → nil (genuine no-data) → perform → freeze_for_field_audit!
  end

  # [ARCH.46] Дата для AiInsight-запиту: прокинута від `ContractHealthCheckService` (де порахована
  # й де відпрацював blackout-guard), інакше дефолт `local_yesterday` (tree-death/dClimate/contractual).
  def effective_target_date
    @target_date || @cluster.local_yesterday
  end

  # [05_05 §3 Slashing curve] Progressive CONVEX penalty:
  #   slash_ratio = clamp(damage_ratio^GAMMA × min(penalty_factor, PENALTY_FACTOR_MAX), 0, 1.0)
  # Replaces the old LINEAR burn (total × damage_ratio — no GAMMA, no penalty_factor; the
  # verified code↔doc divergence, 05_05 §3 / 04_02 §11). GAMMA>1 makes the curve convex:
  # a small loss is punished gently (d=0.10 → ~5%) so an investor isn't wiped out over a
  # minor incident, yet full negligent loss reaches 100% (d=1.0, pf=1.0 → 1.0) — the
  # "no dead-zone" property (the old min(…, 0.40) ceiling that flat-lined 40%→100% damage
  # is removed). penalty_factor — baseline; cause-driven uplift із comms-loss DE-correlation
  # будує #calculate_penalty_factor (SLASH-1 §6, INERT за SystemParameter до DAO-confirm).
  # GAMMA + PENALTY_FACTOR_MAX are DAO-governed (SystemParameter ← ProtocolParameters.sol).
  def calculate_slash_ratio(damage_ratio, penalty_factor = DEFAULT_PENALTY_FACTOR)
    return 0.0 if damage_ratio <= 0.0

    effective_pf = [ penalty_factor, penalty_factor_max ].min
    ((damage_ratio**slash_gamma) * effective_pf).clamp(0.0, 1.0)
  end

  # [SLASH-1 §3/§6] Cause-driven penalty_factor (gated). INERT за замовчуванням
  # (gate :slash_cause_uplift_enabled, default false → baseline, без зміни живої поведінки);
  # активація — DAO/founder перед mainnet (05_05 §3). Сорсить сигнали → #combine_penalty_factor.
  def calculate_penalty_factor
    return DEFAULT_PENALTY_FACTOR unless cause_uplift_enabled?

    combine_penalty_factor(
      no_ack:         comms_no_ack?,
      streamr_gap:    streamr_gap?,
      no_maintenance: critical_unmaintained?
    )
  end

  # Pure de-correlation combiner (SLASH-SAFETY §6). no-ack і Streamr gap корельовані (спільний
  # root-cause «вузол offline») → max(), НЕ сума (інакше один outage карається багаторазово —
  # збитий/вкрадений шлюз); фізична халатність незалежна → additive. Виокремлено від сорсингу,
  # щоб інваріант був явним і тестувався прямо. Cluster-wide blackout відведено раніше (ContractHealthCheckService).
  def combine_penalty_factor(no_ack:, streamr_gap:, no_maintenance:)
    comms_loss  = [ no_ack ? PF_NO_ACK : 0.0, streamr_gap ? PF_STREAMR_GAP : 0.0 ].max
    independent = no_maintenance ? PF_NO_MAINTENANCE : 0.0

    DEFAULT_PENALTY_FACTOR + comms_loss + independent
  end

  # DAO/founder activation gate (05_05 §3). Default OFF → uplift inert до mainnet-confirm.
  # `defined?`-memo (не ||=), бо легітимне значення — false.
  def cause_uplift_enabled?
    return @cause_uplift_enabled if defined?(@cause_uplift_enabled)

    @cause_uplift_enabled = ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:slash_cause_uplift_enabled, default: false)
    )
  end

  # [comms-correlated] «No ack»: критичний node/gateway-offline алерт лишається непідтвердженим
  # (scope `critical` = severity_critical.unresolved).
  # [P1-3] Whitelist саме node-offline типів (§6 root-cause «вузол/шлюз offline»): `queen_offline`
  # (dead-man switch), `queen_uplink_lost` (Helium-крик), `system_fault` (шлюз доповів про збій).
  # Раніше рахувався БУДЬ-який critical (крім field_audit), включно з `vandalism_breach`, що ВЖЕ дав
  # `positive_a?` → той самий tamper-алерт накручував penalty на СОБІ (self-ref → множник завжди
  # сідав на стелю). tamper/fire/chainsaw = не comms-loss (свій root-cause), сюди не рахуємо.
  def comms_no_ack?
    @cluster.ews_alerts.critical
            .where(alert_type: [ :queen_offline, :queen_uplink_lost, :system_fault ])
            .exists?
  end

  # [comms-correlated] Tree-side Streamr broadcast gap (05_05 §6 нот.12 — ЛИШЕ tree-side;
  # backend-side збій Streamr-API не штрафується: доступність публічного спостерігача ≠ здоров'я
  # дерева). Guarded hook: сигнал ще не реалізовано → contributes 0; max()-структура вже коректна.
  def streamr_gap?
    false
  end

  # [independent] Фізична халатність: критичний EwsAlert без жодного MaintenanceRecord по спливу
  # вікна реакції (оператора алертнули, але він не виїхав). Незалежний від comms-loss → additive.
  def critical_unmaintained?
    # [SLASH-1 gap-D] Виключаємо :field_audit — наш власний audit-виклик «слухай» без
    # MaintenanceRecord ≠ операторська недбалість; рахуємо лише реальні tree/hardware-алерти.
    # [P1-3] Виключаємо і :vandalism_breach — коли він дав `positive_a?` (єдиний шлях до Cat-A
    # slash), «не виїхав на tamper» вже покарано НЕОБОРОТНИМ slash → накручувати penalty на тому
    # самому алерті = self-ref подвійне. Незалежна фізична недбалість = реальні tree/hardware-алерти.
    stale_critical = @cluster.ews_alerts.severity_critical
                             .where.not(alert_type: [ :field_audit, :vandalism_breach ])
                             .where(created_at: ..30.minutes.ago)
    return false unless stale_critical.exists?

    stale_critical.where.not(
      id: MaintenanceRecord.where.not(ews_alert_id: nil).select(:ews_alert_id)
    ).exists?
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
