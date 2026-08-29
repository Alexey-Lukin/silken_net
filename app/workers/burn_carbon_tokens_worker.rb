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

    # [ІДЕМПОТЕНТНІСТЬ]: якщо попередній прохід уже виконав burn (але впав на створенні
    # MaintenanceRecord чи деінде нижче) — виходимо без повторного виклику.
    #
    # 🔴 [SLASH-1] Гард читає САМ ІНТЕНТ, а не статус контракту, і це не рефакторинг:
    # доти тут стояв `status_breached?`, тобто ознака, яку contractual-шлях перестав
    # ставити (бо форфейтура НЕ робить договір порушеним — див. `unless @contractual`
    # у сервісі). Лишити старий гард означало б лишити early-exit БЕЗ ідемпотентності:
    # per-contract claim у сервісі тримає лише вікно `unsettled_within(2.hours)`, тож
    # ретрай, що прийшов пізніше, зробив би ДРУГИЙ необоротний burn.
    # ⛔ Часового вікна тут свідомо НЕМАЄ: питання «чи вже палили за цим договором»
    # не має горизонту, а `status`-скан партиційної таблиці навмисно лишається
    # unbounded (CLAUDE §6 — межа тут ШКІДЛИВА, важіль = partial index [ARCH.52]).
    # `sourceable` індексований, тож це index-scan по одному договору, не скан партицій.
    settled_burn = BlockchainTransaction
                   .where(sourceable: naas_contract, direction: :burn, status: [ :sent, :confirmed ])
                   .exists?
    return Rails.logger.warn "⚠️ [Slashing] За контрактом ##{naas_contract_id} burn уже виконано (settled intent). Пропускаємо." if settled_burn

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

    # [S2.4] Track slashing event by reason for Prometheus monitoring.
    # 🔴 [SLASH-1] Вердикт читається ПЕРШИМ: contractual-форфейтура не є ані загибеллю
    # дерева, ані деградацією кластера — вона є добровільним виходом замовника. Доти
    # мітка деривувалась лише з наявності `source_tree`, тож кожен early-exit приходив
    # на панель як `cluster_degradation`, тобто як провина оператора. Дискримінатор
    # існував у сервісі (`verdict:` в audit-ланцюгу), просто сюди не доїжджав.
    reason = if contractual
               "contractual_forfeiture"
    elsif source_tree
               "tree_death"
    else
               "cluster_degradation"
    end
    SilkenNet::Metrics::SLASHING_EVENTS_TOTAL.increment(labels: { reason: reason })

    # 2. СИНХРОНІЗАЦІЯ ІСТИННИ (Atomic Audit)
    # Сервіс уже перевів контракт у термінальний стан (`:breached` на positive-A;
    # на contractual він лишається `:cancelled` — [SLASH-1]), а тут створюється
    # "надгробний камінь" у фізичному журналі обслуговування.
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
        # 🔴 [SLASH-1] Надгробок мусить називати ПРИЧИНУ, а не приписувати провину.
        # Доти цей текст був один на обидва шляхи, тож добровільний early-exit діставав
        # у фізичному журналі обслуговування напис «анульовано через порушення
        # біо-цілісності … Вердикт Оракула: BREACHED» — тобто запис, який людина потім
        # читає як доказ провини замовника. Дискримінатор той самий, що в мітці метрики.
        notes: if contractual
                 <<~NOTES
                   📄 CONTRACTUAL FORFEITURE.
                   Контракт ##{naas_contract_id} завершено достроково за ініціативою замовника.
                   Нараховані монети списано як погоджену умову (`burn_accrued_points`), НЕ як санкцію.
                   Порушення умов НЕ встановлено; статус контракту: CANCELLED.
                 NOTES
               else
                 <<~NOTES
                   🚨 SLASHING EXECUTED.
                   Контракт ##{naas_contract_id} анульовано через порушення біо-цілісності.
                   #{source_tree ? "Причина: Загибель Солдата #{source_tree.did}." : "Причина: Загальна деградація кластера."}
                   Вердикт Оракула: BREACHED.
                 NOTES
               end
      )
    end

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно анігільовано в системі."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Провал місії для контракту ##{naas_contract_id}: #{e.message}"
    # Sidekiq перехопить помилку для повторної спроби, якщо блокчейн був недоступний
    raise
  end
end
