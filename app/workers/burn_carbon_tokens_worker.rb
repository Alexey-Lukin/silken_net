# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class BurnCarbonTokensWorker
  include ApplicationWeb3Worker
  # Використовуємо чергу critical, бо фінансова відплата має бути негайною,
  # щоб запобігти виводу токенів інвестором.
  # [ARCH.53] Job-dedup (`unique_for: SLASH_CLAIM_TTL`) додати з покупкою Sidekiq
  # Enterprise (шим no-op, 04_02 DOC-R.10); до того TOCTOU закриває per-contract
  # claim у BlockchainBurningService (defense-in-depth, не заміна).
  sidekiq_options queue: "critical", retry: 5

  # ⚠️ `stress_threshold` — 6-й позиційний, і ІМʼЯ параметра тут єдиний носій семантики:
  # Sidekiq-аргументи позиційні, kwarg сервісу сюди не дотягується (той самий урок, що
  # ARCH.95 купив на одиниці). `nil` для тригерів, які розміру з вибірки не питають
  # (tree-death / dClimate / contractual), і для джоб, поставлених у чергу до цієї зміни.
  #   `stress_threshold` · `slash_gamma` · `penalty_factor_max`. [DOC-T.89]
  #   Один хеш, а не три позиційні аргументи: воркер уже ніс шість, а формула
  #   вироку множить ТРИ DAO-параметри — кожен новий як окремий слот перетворив би
  #   сигнатуру на власну поверхню дрейфу. Ключі РЯДКОВІ: Sidekiq `strict_args`
  #   пропускає лише JSON-нативне, символи не переживають серіалізацію.
  #   `nil` → сервіс читає DAO-live сам (див. оголошену стелю в його шапці).
  def perform(organization_id, naas_contract_id, tree_id = nil, contractual = false,
              target_date = nil, verdict_params = nil)
    frozen = verdict_params || {}
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    return Rails.logger.error "🛑 [Slashing] Контракт ##{naas_contract_id} не знайдено." unless naas_contract

    # [ІДЕМПОТЕНТНІСТЬ]: Якщо контракт вже розірвано (попередній ретрай виконав слешинг, але впав
    # на створенні MaintenanceRecord) — виходимо без повторного виклику. [ARCH.48] Інваріант тепер
    # ТОЧНИЙ: `:breached` ставить ЛИШЕ happy-path сервісу на РЕАЛЬНОМУ слешингу (rescue на збої більше
    # НЕ breach-ить) → :breached ≡ «вже слешено», тож цей skip не маскує тихий burn-abort на RPC-збої.
    return Rails.logger.warn "⚠️ [Slashing] Контракт ##{naas_contract_id} вже розірвано. Пропускаємо." if naas_contract.status_breached?

    organization = Organization.find(organization_id)
    cluster = naas_contract.cluster
    source_tree = Tree.find_by(id: tree_id) if tree_id

    Rails.logger.warn "🔥 [Slashing Protocol] Виконання вироку для #{organization.name} (Кластер: #{cluster.name})."

    # 1. WEB3 ЕКЗЕКУЦІЯ (The Judgment Stroke)
    # source_tree — доказ порушення для on-chain логу; contractual — early-exit форфейтура
    # пропускає positive-A gate. Сервіс повертає :slashed (реальний burn) / :frozen (cause-gate
    # freeze, SLASH-1 §3.2) / nil (no-op: нема minted або zero burn).
    outcome = with_web3_error_handling("Polygon", "Slashing Contract ##{naas_contract_id}") do
      BlockchainBurningService.call(
        organization_id,
        naas_contract_id,
        source_tree: source_tree,
        contractual: contractual,
        # [ARCH.46] target_date прокинутий від ContractHealthCheckService (Sidekiq → String ISO8601);
        # nil/blank → сервіс дефолтить на `AiInsight.reporting_date` (tree-death/dClimate/contractual).
        target_date: (Date.parse(target_date) if target_date.present?),
        # [SLASH-1 / DOC-T.89] Закон вироку, зафіксований тригером — координати 2-4
        # того самого інваріанта «тригер ≡ розмір» (перша — дата, ARCH.46).
        stress_threshold: frozen["stress_threshold"],
        slash_gamma: frozen["slash_gamma"],
        penalty_factor_max: frozen["penalty_factor_max"]
      )
    end

    # [SLASH-1] Лише реальний slash тягне «надгробок». Freeze (нема прямого доказу Кат-A) /
    # no-op → НЕ розриваємо контракт і НЕ б'ємо на сполох: Field-Audit алерт уже піднято
    # сервісом (Категорія C), кошти не спалено.
    unless outcome == :slashed
      Rails.logger.info "🧊 [Slashing Protocol] Контракт ##{naas_contract_id}: outcome=#{outcome.inspect} (freeze/no-op) — без розриву."
      return
    end

    # [S2.4] Track slashing event by reason for Prometheus monitoring
    reason = source_tree ? "tree_death" : "cluster_degradation"
    SilkenNet::Metrics::SLASHING_EVENTS_TOTAL.increment(labels: { reason: reason })

    # 2. СИНХРОНІЗАЦІЯ ІСТИННИ (Atomic Audit)
    # Ми маркуємо контракт як BREACHED вже всередині сервісу, але тут
    # створюємо "надгробний камінь" у фізичному журналі обслуговування.
    ActiveRecord::Base.transaction do
      # Шукаємо системного інквізитора (Oracle Executioner) для підпису запису.
      # Якщо бот відсутній у DB — fallback на першого адміна, щоб не зламати транзакцію.
      executioner = User.oracle_executioner || User.find_by(role: :admin) || User.first

      MaintenanceRecord.create!(
        maintainable: cluster,
        user: executioner,
        action_type: :decommissioning,
        performed_at: Time.current,
        # Підписант — бот, тож рядок машинний; на валідацію це не впливає
        # (`decommissioning` фото не вимагає), але провенанс мусить бути чесний.
        system_generated: true,
        notes: <<~NOTES
          🚨 SLASHING EXECUTED.
          Контракт ##{naas_contract_id} анульовано через порушення біо-цілісності.
          #{source_tree ? "Причина: Загибель Солдата #{source_tree.did}." : "Причина: Загальна деградація кластера."}
          Вердикт Оракула: BREACHED.
        NOTES
      )
    end

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно анігільовано в системі."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Провал місії для контракту ##{naas_contract_id}: #{e.message}"
    # Sidekiq перехопить помилку для повторної спроби, якщо блокчейн був недоступний
    raise
  end
end
