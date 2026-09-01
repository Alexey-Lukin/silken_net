# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🔄 MINTING ROLLBACK SERVICE (The Absolute Integrity)
# = ===================================================================
# Відповідає за повернення заблокованих коштів після вичерпання всіх
# Sidekiq-ретраїв у MintCarbonCoinWorker. Запобігає "зависанню" капіталу
# у locked_balance, коли RPC Polygon перманентно недоступний.
#
# [DOUBLE-SPEND GUARD]: Якщо tx_hash вже існує (транзакція була відправлена
# в мемпул), НЕ розблоковуємо кошти автоматично — ескалюємо до manual_review.
# Це запобігає класичному Double-Spend: блокчейн може змінтити токени навіть
# якщо RPC відвалився до отримання підтвердження.
#
# Логіка:
#   1. tx_hash відсутній → безпечний rollback (транзакція не покинула бекенд)
#   2. tx_hash існує → спробувати getTransactionReceipt через RPC
#      a) receipt є (confirmed) → НЕ робити rollback, підтвердити транзакцію
#      b) receipt null (pending) → manual_review, кошти залишаються заблокованими
#      c) RPC timeout → manual_review, кошти залишаються заблокованими
#
# Використання:
#   MintingRollbackService.call(telemetry_log_id: 123, created_at_iso: "2026-01-01T00:00:00Z")
#   MintingRollbackService.call(transactions: txs)
class MintingRollbackService < ApplicationService
  def initialize(telemetry_log_id: nil, created_at_iso: nil, transactions: nil)
    @telemetry_log_id = telemetry_log_id
    @created_at_iso = created_at_iso
    @transactions = transactions
  end

  def perform
    txs = resolve_transactions
    return if txs.blank?

    txs.each { |tx| rollback_transaction!(tx) }
  end

  private

  def resolve_transactions
    return @transactions if @transactions.present?
    return unless @telemetry_log_id

    log = find_telemetry_log
    return unless log

    # log.tree non-nil: belongs_to :tree (required) + Tree dependent: :delete_all
    # видаляє логи разом із деревом, тож orphaned-log не існує (мертвий `&.` прибрано).
    wallet = log.tree.wallet
    return unless wallet

    wallet.blockchain_transactions.where(status: [ :pending, :processing, :sent ])
  end

  def find_telemetry_log
    # [S6.16] pruning-логіка (1с-вікно + degraded-облік) — One-Home
    # `TelemetryLog.partition_pruned`. Вікно толерантне до секундної
    # точності ISO (адмінський виклик за прикладом із шапки файлу) —
    # давня точна рівність тут мовчки промахувалась повз мікросекундний
    # created_at → rollback ставав no-op.
    TelemetryLog.where(id: @telemetry_log_id)
                .partition_pruned(@created_at_iso, metric_caller: "MintingRollbackService")
                .first
  end

  def rollback_transaction!(tx)
    # [GUARD]: Пропускаємо транзакції, що вже у термінальному стані
    return if tx.status.in?(%w[confirmed failed manual_review])

    # [DOUBLE-SPEND GUARD]: Якщо tx_hash існує, транзакція могла потрапити в мемпул.
    # Автоматичний rollback неприпустимий — перевіряємо стан на блокчейні.
    if tx.tx_hash.present?
      handle_transaction_with_hash(tx)
    else
      perform_safe_rollback(tx)
    end
  end

  # Транзакція з tx_hash — потенційно в мемпулі або вже підтверджена.
  # Спробуємо перевірити стан через RPC перед будь-яким рішенням.
  def handle_transaction_with_hash(tx)
    receipt = fetch_transaction_receipt(tx)

    case receipt
    when :confirmed
      # Транзакція успішно підтверджена на блокчейні — НЕ робимо rollback
      Rails.logger.info "✅ [Web3] Транзакція ##{tx.id} (#{tx.tx_hash}) підтверджена on-chain. Rollback скасовано."
      tx.confirm!
    when :reverted
      # Транзакція відхилена EVM — безпечно робити rollback
      Rails.logger.warn "↩️ [Web3] Транзакція ##{tx.id} (#{tx.tx_hash}) reverted on-chain. Виконуємо rollback."
      perform_safe_rollback(tx)
    else
      # :pending або :unknown — ескалюємо до manual_review
      escalate_to_manual_review(tx, "tx_hash існує (#{tx.tx_hash}), але стан на блокчейні невідомий (#{receipt})")
    end
  end

  # Перевіряємо стан транзакції на блокчейні через RPC.
  # Повертає :confirmed, :reverted, :pending або :unknown
  #
  # [MULTICHAIN]: Solana використовує інший RPC-метод (getTransaction),
  # тому обробка відрізняється від EVM-мереж (eth_getTransactionReceipt).
  def fetch_transaction_receipt(tx)
    if tx.solana_network?
      fetch_solana_transaction_status(tx)
    else
      fetch_evm_transaction_receipt(tx)
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] Не вдалося отримати receipt для TX ##{tx.id}: #{e.message}"
    :unknown
  end

  # EVM-мережі (Polygon, Celo): eth_getTransactionReceipt
  # [BUGFIX]: Eth gem (0.5.x) returns the full JSON-RPC envelope:
  # `{ "id" => ..., "jsonrpc" => "2.0", "result" => { "status" => "0x1", ... } }`.
  # Previously this method read `receipt["status"]` directly, which always
  # returned nil → every confirmed/pending TX was misclassified as :reverted,
  # triggering a safe_rollback that released `locked_balance` even when the
  # mint had already landed on-chain. That is the exact double-spend window
  # the service was supposed to close.
  def fetch_evm_transaction_receipt(tx)
    # [E.49]: для Celo використовуємо Celo-specific cascade, не Polygon.
    # Раніше для Celo-транзакцій fallback вказував на polygon-rpc.com (баг).
    if tx.celo_network?
      rpc_env_key       = "CELO_RPC_URL"
      # ⚖️ [2026-08-31] `nil` НЕ пропуск: `DEFAULT_RPC_URL` знято, і falsy-фолбек змушує
      # `client_for` робити `ENV.fetch` БЕЗ дефолту — тобто fail-loud на money-шляху.
      # ⚠️ Polygon-гілка нижче лишається зі СВОЇМ фолбеком свідомо: її хост — окремий
      # відкритий ⚖️ (`polygon-rpc.com` віддає 401), і зняття Celo його не вирішує.
      fallback_url      = nil
      fallback_env_keys = Celo::CommunityRewardService::RPC_FALLBACK_ENV_KEYS
    else
      rpc_env_key       = "ALCHEMY_POLYGON_RPC_URL"
      # 🔴 ЦЕЙ ФОЛБЕК БІЛЬШЕ НЕ ФОЛБЕК [ARCH.118, виміряно 2026-08-30]: хост живий і на
      # JSON-RPC тричі поспіль відмовляє `"API key disabled, tenant disabled"` — тобто
      # публічний ендпоінт вимкнено на боці провайдера, і каскад мовчки вироджується в
      # один Alchemy-URL.
      # 🔴 ДВА ЧИСЛА, І ПЛУТАТИ ЇХ КОШТУЄ ГЕЙТА (перемір 2026-08-31): HTTP-СТАТУС тут `401`,
      # а `403` стоїть ЛИШЕ в ТІЛІ відповіді (`"rest code: 403"`). Перший запис зафіксував
      # тіло як статус, тож гард, ключований на `403`, не спрацював би ЖОДНОГО разу.
      # ⛔ Не «виправляти» `401` назад на `403` за більшістю згадок — більшість тут старіша
      # за перемір; ключувати майбутній детектор ТІЛЬКИ на статус `401` або на рядок тіла,
      # і ніколи на «403» як на статус. Це також ПІДСТАВА дзеркального правила гарда («на testnet-слоті
      # порожній `ALCHEMY_POLYGON_RPC_URL` приземляється на mainnet»), тож заміна переписує
      # `Web3::NetworkGuard#hardcoded_fallback_violations`, а не лише цей рядок — ⚖️ 00_07 `ARCH.118`.
      fallback_url      = "https://polygon-rpc.com"
      fallback_env_keys = [ "INFURA_POLYGON_RPC_URL" ]
    end

    client = Web3::RpcConnectionPool.client_for(
      rpc_env_key,
      fallback: fallback_url,
      fallback_env_keys: fallback_env_keys
    )
    envelope = client.eth_get_transaction_receipt(tx.tx_hash)
    # [ARCH.50] tri-state classification extracted to the shared One-Home classifier.
    Web3::EvmReceiptClassifier.classify(envelope)
  end

  # Solana: JSON-RPC getTransaction
  # Solana не використовує eth gem, тому робимо HTTP-запит напряму.
  def fetch_solana_transaction_status(tx)
    solana_url = ENV.fetch("SOLANA_RPC_URL", nil)
    return :unknown unless solana_url

    response = Web3::HttpClient.post(solana_url,
      body: {
        jsonrpc: "2.0", id: 1, method: "getTransaction",
        params: [ tx.tx_hash, { encoding: "json", commitment: "confirmed" } ]
      },
      service_name: "Solana"
    )

    result = response.parsed_body&.dig("result")
    return :pending if result.nil?

    if result.dig("meta", "err").nil?
      :confirmed
    else
      :reverted
    end
  end

  # Безпечний rollback: тільки коли tx_hash ВІДСУТНІЙ (транзакція не покинула бекенд).
  def perform_safe_rollback(tx)
    Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx.id}. Запуск протоколу повернення активів..."

    # 🔴 [ARCH.101] СПАЛЕННЯ сюди доходить, і мовчазний дефолт нижче порахував би
    # його мінтом. `locked_points` у slash-інтенті `nil` ЗА КОНСТРУКЦІЄЮ
    # (`create_slash_intent!` його просто не ставить), тож `||`-гілка, написана під
    # legacy-мінти, ловить і його — а далі множить МОНЕТИ на 10 000 і «повертає»
    # вигадані бали з `locked_balance`. ⚠️ Корінь не в арифметиці, а в тому, що
    # `locked_points == nil` означає ДВІ різні речі («до нової ери» ⊥ «спалення»),
    # і дискримінатор написано лише під першу. Напрямок деривуємо, ніколи не
    # вгадуємо зі знака: slash пишеться ДОДАТНИМ.
    return rollback_burn_intent!(tx) if tx.burn?

    ActiveRecord::Base.transaction do
      tx.wallet.with_lock do
        # Legacy-fallback (rows до locked_points-ери мінтились на 10k-дефолті) —
        # свідомо КОНСТАНТА-дефолт, не DAO-live значення (GOV.1): governance-зміна
        # порогу не має переоцінювати історичний refund.
        refund_points = tx.locked_points || (tx.amount * TokenomicsEvaluatorWorker::EMISSION_THRESHOLD).to_i

        if tx.wallet.locked_balance >= refund_points
          tx.wallet.release_locked_funds!(refund_points)
        elsif tx.wallet.locked_balance > 0
          tx.wallet.release_locked_funds!(tx.wallet.locked_balance)
        end

        # [SAFE NAVIGATION]: Захист від nil-рефренсу при видаленому дереві
        tree_did = tx.wallet.tree&.did || "N/A"
        tx.update!(
          status: :failed,
          notes: "Rollback: Постійний збій RPC. Розблоковано #{refund_points} балів для DID: #{tree_did}"
        )
      end
    end

    # Трансляції балансу тут НЕМАЄ свідомо: її вже несе `after_update_commit` на
    # BlockchainTransaction (`broadcast_status_change` → `broadcast_balance_update` при
    # :failed), який файрить і на сирий `update!` вище. Не повертати власний виклик —
    # голий Turbo `broadcast_update` рендерив дефолтний неіснуючий партіал `wallets/_wallet`
    # → MissingTemplate обривав `txs.each`, лишаючи locked_balance решти батчу замороженим.
  end

  # [ARCH.101] Слеш-інтент, що не покинув бекенд (`tx_hash` відсутній — on-chain НЕ
  # сталося нічого). Балансів не чіпаємо взагалі: спалення нічого не блокувало, тож
  # «повертати» нема чого — і саме тут проходила б хибна арифметика мінт-гілки.
  # ⚠️ Слід гучний свідомо: вилучення БУЛО присуджено і не виконалось, а цей сервіс
  # переспроби слешингу не веде — тому подія мусить бути видною в логах, доки
  # повторний тракт не заведено (→ `00_07` ARCH.101).
  def rollback_burn_intent!(tx)
    Rails.logger.warn "🔥 [Web3] Слеш-інтент ##{tx.id} не виконано (RPC). Балансів НЕ змінено; повтор слешингу не автоматизовано."

    tx.update!(
      status: :failed,
      notes: "Rollback: Постійний збій RPC. Спалення НЕ виконано, балансів не змінено (ARCH.101)."
    )
  end

  # Ескалація до ручної перевірки: кошти залишаються заблокованими,
  # транзакція переходить у manual_review, адмін отримує алерт.
  def escalate_to_manual_review(tx, reason)
    Rails.logger.warn "⚠️ [Web3] Ескалація TX ##{tx.id} до manual_review: #{reason}"

    tx.escalate_to_review!(reason)
  end
end
