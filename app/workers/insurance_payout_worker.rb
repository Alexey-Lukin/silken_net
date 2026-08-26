# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class InsurancePayoutWorker
  include ApplicationWeb3Worker
  # Найвищий пріоритет: виконання фінансових зобов'язань перед інвесторами
  # є критичним для репутації Цитаделі. Черга critical гарантує, що виплати
  # не застрягнуть за повільними Polygon-мінтингами у web3.
  sidekiq_options queue: "critical", retry: 10

  def perform(insurance_id)
    insurance = ParametricInsurance.includes(cluster: :organization).find_by(id: insurance_id)
    return unless insurance

    # [INS.1 kill-switch] Майстер-прапор money-path (default false). Стандарт = national-grid
    # SCADA (05_06 §5): flip off → виплати миттєво зупиняються, кандидати тримаються.
    return unless oracle_enabled?

    # 1. ПЕРЕВІРКА ТРИГЕРА
    # Виконуємо лише якщо Оракул активував тригер, але виплата ще не зафіксована як завершена.
    # [P1 FIX]: Також дозволяємо :paid для recovery orphaned Etherisc TX —
    # якщо claim! виконався, але tx.update! впав, insurance вже :paid,
    # а tx залишається :pending без BlockchainConfirmationWorker.
    return unless insurance.status_triggered? || insurance.status_paid?

    # [INS.1 dual-trigger / COSMIC EYE] Trigger-2: гроші рухає лише НЕЗАЛЕЖНЕ verified-
    # підтвердження (dClimate satellite fire/drought). Кандидат, озброєний AI-оракулом
    # (Trigger-1), тримається, поки незалежне джерело не підтвердить — закриває basis-risk
    # (не платимо лише за нашим сигналом, 05_05 §6).
    return if awaiting_independent_confirmation?(insurance)

    organization = insurance.cluster.organization

    # Шукаємо гаманець-якір для аудиторського логування в Ledger.
    # Спочатку шукаємо активне дерево; якщо катастрофа знищила всі активні дерева —
    # беремо будь-яке дерево кластера (незалежно від статусу) лише для аудит-зв'язку.
    audit_wallet = insurance.cluster.trees.active.first&.wallet ||
                   insurance.cluster.trees.first&.wallet

    unless audit_wallet
      Rails.logger.error "🛑 [Insurance] Спроба виплати ##{insurance_id} без жодного дерева в кластері."
      return
    end

    # [DOC-T.89] SFC-виплата зупиняється ТУТ, а не лише в мінт-лійці. Лійковий гард
    # мовчки повертає ПІСЛЯ `pay!`, тож поліс став би `:paid`, `INSURANCE_PAYOUT_SUCCESS_TOTAL`
    # інкрементнувся б (він лічить виклик, не результат), а tx лишився б вічним `:pending`,
    # якого recovery не бачить (тягне лише `:triggered`). Тобто система засвідчила б
    # виплату, якої не було. Лійковий гард лишається — він ловить УСІ шляхи, включно з
    # майбутнім admin-екраном; цей потрібен, щоб самосвідчення не брехало.
    # 🔦 Знімати разом із лійковим — грепай DOC-T.89.
    if insurance.token_type_forest_coin?
      Rails.logger.error "🛑 [DOC-T.89] Виплата ##{insurance_id} у SFC відхилена до активації " \
                         "governance (SEC.1): поліс лишається :triggered, tx не створюється."
      return
    end

    # 2. АТОМАРНА ФІКСАЦІЯ ВИПЛАТИ (Postgres Domain)
    tx = nil
    ActiveRecord::Base.transaction do
      # Pessimistic lock для запобігання подвійних виплат (Double Spend Protection)
      insurance.lock!
      # [next vs return]: next виходить тільки з блоку, а не з методу perform.
      # return тут виходив би з методу — семантична пастка при рефакторингу на proc/lambda.
      next unless insurance.status_triggered?

      # Створюємо запис у блокчейн-черзі для виконання емісії/переказу
      tx = insurance.create_blockchain_transaction!(
        wallet: audit_wallet,
        amount: insurance.payout_amount,
        token_type: insurance.token_type, # Тип токена обирається при підписанні контракту
        to_address: organization.crypto_public_address,
        status: :pending,
        notes: "Страхове відшкодування ##{insurance.id}. Подія: #{insurance.trigger_event}."
      )

      # Переводимо страховку в стан виплати (AASM: triggered → paid)
      insurance.pay!
    end

    # 3. WEB3 ЕКЗЕКУЦІЯ (Blockchain Domain)
    # Тепер, коли транзакція зафіксована в базі, ми передаємо її нашому
    # загартованому BlockchainMintingService для підпису та відправки в Polygon.
    # [ETHERISC DIP]: Якщо страховка прив'язана до Etherisc policy, система
    # працює як Oracle — тригерить зовнішній USDC payout замість внутрішнього мінтингу.
    # [P1 FIX]: при recovery insurance вже :paid → підхоплюємо orphaned pending TX.
    # (`if status_paid?` прибрано — AASM має лише triggered→paid, тож після transaction-блоку
    # статус ЗАВЖДИ :paid; умова була завжди-true → мертва гілка.)
    # [ARCH.45] recovered_tx — transaction-блок не створив tx (insurance вже :paid) → ми на
    # recovery-шляху (Sidekiq retry / InsurancePayoutRecoveryWorker), підхопили orphaned TX.
    recovered_tx = tx.nil?
    # Явний live-tx lookup замість has_one (повертає найстаріший рядок за id): money-path
    # idempotency не сміє спиратись на ORDER BY id — stale :failed-рядок дав би false на
    # status_pending? і пропустив escalation → re-claim. ⚠️ `unsettled_within` (модель) партицій
    # НЕ прунить — `OR` у скоупі знімає відбір цілком (виміряно EXPLAIN'ом); тут його беруть за
    # семантику in-flight, не за вартість. Fallback на has_one лишається для не-recovery шляхів.
    tx ||= BlockchainTransaction.where(sourceable: insurance)
                                .unsettled_within(7.days)
                                .order(created_at: :desc).first || insurance.blockchain_transaction

    if tx
      # [INS.1 SLO] Лічимо спробу виплати (знаменник success-rate SLO, 06_03 §2.8).
      SilkenNet::Metrics::INSURANCE_PAYOUT_ATTEMPTS_TOTAL.increment

      if insurance.uses_etherisc?
        # [ARCH.45] Double-claim crash-window guard: recovery-шлях + :pending = claim! міг бути
        # надісланий до краху tx.update(:sent) (зовнішній USDC payout). Сліпий re-claim = можливий
        # double-pay — DIP claim-once захищає, але ми НЕ контролюємо зовнішній контракт. Ескалюємо
        # в manual_review (як mint double-spend guard): людина звіряє DIP перед повтором. Точніша
        # on-chain claim-status звірка — майбутнє (потребує DIP getClaim ABI).
        # [P1-2] recovered + :pending → escalate (claim! міг бути надісланий); recovered +
        # :manual_review → вже під ручною звіркою (попередній recovery) → НЕ re-claim, НЕ re-arm.
        # Інакше age-unbounded `unsettled_within` знаходить старий :manual_review → повторний
        # `claim!` (double-pay-експозиція) + `mark_as_sent!` whiny-raise (:manual_review не в
        # from-state) → retry×10 циклить claim!.
        if recovered_tx && (tx.status_pending? || tx.status_manual_review?)
          if tx.may_escalate_to_review?
            tx.escalate_to_review!("Etherisc claim міг бути надісланий до краху update — ручна звірка DIP перед повтором (ARCH.45)")
          end
          Rails.logger.warn "🛡️ [Insurance] ##{insurance.id}: orphaned :#{tx.status} Etherisc TX → manual_review (можливий вже-надісланий claim; без re-claim)."
          return
        end

        Rails.logger.info "🛡️ [Insurance] Triggering Etherisc DIP claim for policy " \
                          "#{insurance.etherisc_policy_id} (insurance ##{insurance.id})..."

        # [P1 FIX IDEMPOTENCY]: Пропускаємо claim! якщо TX вже :sent/:confirmed
        unless tx.status_sent? || tx.status_confirmed?
          # [RATE LIMITED]: RPC виклик захищений глобальним лімітером.
          etherisc_tx_hash = within_rpc_limit do
            Etherisc::ClaimService.new(insurance).claim!
          end
          # [ARCH.55] mark_as_sent! (AASM) — проставляє sent_at, щоб stuck-:sent sweeper бачив
          # момент broadcast (голий update! лишав sent_at NULL).
          tx.mark_as_sent!(etherisc_tx_hash)
          SilkenNet::Metrics::INSURANCE_PAYOUT_SUCCESS_TOTAL.increment
        end

        # `.present?`-else = model-validation-dead: mark_as_sent! → :sent, а :sent-tx завжди
        # має tx_hash (validates if status_sent?) → гілка недосяжна (§B.4 leave).
        BlockchainConfirmationWorker.perform_in(30.seconds, tx.tx_hash, tx.created_at.iso8601) if tx.tx_hash.present? # [ARCH.52] partition-prune
      else
        # [ARCH.51] Internal-mint double-mint guard. `BlockchainMintingService.initialize`
        # filters ONLY `.where.not(status: :confirmed)`; this DIRECT `.call` bypasses the
        # batch paths' `:pending`-only filter, so a recovered `:sent`/`:processing` orphan
        # would be RE-MINTED. The mint flips `:pending`→`:processing` INSIDE its own lock
        # BEFORE broadcast → only a `:pending` tx is unambiguously un-minted. Invariant: we
        # (re-)submit ONLY a `:pending` tx; any non-`:pending` recovered tx may already be
        # on-chain → escalate (double-spend guard, mirrors the Etherisc branch), never
        # blindly re-mint. (`:pending` = fresh non-recovery tx OR a recovery where the mint
        # never entered its lock.)
        unless tx.status_pending?
          tx.escalate_to_review!("Internal insurance mint вже :#{tx.status} на попередній спробі — звір on-chain ПЕРЕД повтором (ARCH.51 double-mint guard)") if tx.may_escalate_to_review?
          Rails.logger.warn "🛡️ [Insurance] ##{insurance.id}: non-:pending internal-mint TX (:#{tx.status}) → no re-mint (можливий вже-надісланий mint)."
          return
        end

        # [INS.2] Reserve-backing gate ПЕРЕД mint — Internal-mode мінтить новий SCC (інфляція),
        # не забезпечений DAO_TREASURY-пулом. Gate капить сумарну емісію (aggregate correlated
        # stop-loss + reserve-adequacy); обидва пороги inert-default → без калібрування gate
        # завжди :ok (поведінка незмінна). Справжній breach → HOLD manual_review (людський
        # reconcile регіональної події); transient RPC-збій → raise (Sidekiq-retry) нижче.
        reserve_gate = Insurance::ReserveGate.call(insurance, current_tx_id: tx.id)
        unless reserve_gate.ok?
          # [INS.2] Transient RPC-збій (fail-closed :eval_error) → RAISE: лишаємо tx :pending,
          # Sidekiq retry(10) підхопить після відновлення (recovery-крон тягне лише :triggered,
          # ця вже :paid, тож БЕЗ raise вона застрягла б назавжди). Справжній breach
          # (aggregate/reserve) → escalate manual_review (persistent, людський розгляд події).
          raise "INS.2 reserve-gate transient RPC error: #{reserve_gate.detail}" if reserve_gate.reason == :eval_error

          # tx гарантовано :pending (guard вище) → escalate завжди легальний (AASM from :pending),
          # may-guard тут був би мертвою гілкою.
          tx.escalate_to_review!("INS.2 reserve-gate hold (#{reserve_gate.reason}): #{reserve_gate.detail}")
          EwsAlert.create(
            alert_type: :system_fault,
            severity: :critical,
            # Ключ від reason (він УЖЕ машинний символ), параметри — скаляри з
            # gate'а. Раніше сюди їхав `detail` — готове АНГЛІЙСЬКЕ речення з
            # чужого сервісу, тобто локалізована рамка з незмінною серединою.
            message_key: "insurance_reserve_hold_#{reserve_gate.reason}",
            message_params: reserve_gate.params.merge(id: insurance.id)
          )
          # [ARCH.82] Другий канал, і саме він доїде до людини: сам EwsAlert безкластерний,
          # тож жодна орг-поверхня його не показує (`has_many through: :clusters` = INNER JOIN),
          # а `manual_review`-gauge не розрізняє казначейський HOLD від double-spend-лімбо.
          SilkenNet::Metrics::INSURANCE_RESERVE_HOLD_TOTAL.increment(labels: { reason: reserve_gate.reason.to_s })
          Rails.logger.warn "🛡️ [Insurance] ##{insurance.id}: reserve-gate HOLD (#{reserve_gate.reason}) → manual_review (без mint)."
          return
        end

        Rails.logger.info "🚀 [Insurance] Ініціація виплати #{tx.amount} SCC для #{organization.name}..."
        # [RATE LIMITED]: RPC виклик захищений глобальним лімітером.
        within_rpc_limit do
          BlockchainMintingService.call(tx.id, created_at_span: tx.created_at) # [S6.16] partition-prune
        end
        SilkenNet::Metrics::INSURANCE_PAYOUT_SUCCESS_TOTAL.increment
      end
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Insurance] Запис ##{insurance_id} зник із Матриці."
  rescue StandardError => e
    Rails.logger.error "🚨 [Insurance Error] Критичний збій виплати ##{insurance_id}: #{e.message}"
    raise # Дозволяємо Sidekiq спробувати ще 10 разів (SLA 99.9%)
  end

  private

  # [INS.1 kill-switch] Майстер-прапор money-path (default false). defined?-memo (не ||=),
  # бо легітимне значення — false. Дзеркалить BlockchainBurningService#cause_uplift_enabled?.
  def oracle_enabled?
    return @oracle_enabled if defined?(@oracle_enabled)

    @oracle_enabled = ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:parametric_insurance_oracle_enabled, default: false)
    )
  end

  # [INS.1 dual-trigger / COSMIC EYE] Trigger-2: payout лише за НЕЗАЛЕЖНИМ verified-підтвердженням.
  # Кандидат, озброєний AI-оракулом (Trigger-1), НЕ платиться, поки незалежне джерело не підтвердить.
  # Повертає true (ТРИМАТИ виплату) якщо: жодного незалежного перил-алерту (basis-risk guard); unverified
  # (ще не підтверджено); inconclusive (потрібен ручний DAO / Field-Audit — сюди йдуть УСІ не-пожежні
  # перили: fire-супутник їх не адьюдикує, Dclimate::VerificationService).
  def awaiting_independent_confirmation?(insurance)
    cluster = insurance.cluster

    # 🔴 [INS.1] Гейт питає про ПЕРИЛ ЦЬОГО ПОЛІСА, а не «чи є в кластері хоч якийсь
    # verified-алерт». Доти фільтр брав ОБИДВА перил-типи й `trigger_event` не читав —
    # а `:verified` пише лише fire-гілка, тож поліс від посухи платився б за доказом
    # пожежі. Дім пари — `ParametricInsurance::PERIL_CONFIRMING_ALERT`.
    # ⛔ Рантайм-гарда на «перил без рядка в мапі» тут НЕМА свідомо: він був би мертвою
    # гілкою (обидва члени enum'а покриті, `trigger_event` має `validates presence`), а
    # мертвий гард лише імітує обачність. Причину ловить інваріант
    # `PERIL_CONFIRMING_ALERT покриває кожен trigger_event` у спеці моделі — тобто в CI,
    # а не в проді. ⊕ Навіть якби мапа розійшлась, поведінка лишається fail-closed
    # СТРУКТУРНО: `nil` → `where(alert_type: nil)` → `none?` → HOLD.
    confirming_type = insurance.confirming_alert_type

    # ⚖️ **Периметри двох половин РІЗНІ, і асиметрія тут несуча.**
    # ТРИМАЮТЬ — усі перил-алерти кластера (широко): HOLD оборотний, тож чужа
    # непевність цілком може відкласти виплату. ПЛАТИТЬ — лише verified-алерт
    # ВЛАСНОГО перилу (вузько): виплата необоротна, тож чужий доказ підставою не є.
    # Симетричне звуження обох половин було б хибним — воно зняло б працюючий гард
    # (fire-поліс перестав би чекати на непідтверджену посуху), тобто заплатило б за
    # фікс послабленням. Дім пари — `ParametricInsurance::PERIL_CONFIRMING_ALERT`.
    peril_alerts = cluster.ews_alerts
                          .where(alert_type: [ :fire_detected, :severe_drought ])
                          .where(status: :active)

    if peril_alerts.none?
      Rails.logger.info "🛡️ [Insurance] Кластер ##{cluster.id}: кандидат без незалежного підтвердження (Trigger-2) — тримаємо, payout НЕ запущено."
      return true
    end

    if peril_alerts.exists?(satellite_status: :unverified)
      Rails.logger.info "🛰️ [Insurance] Виплата відкладена — очікуємо незалежну верифікацію для кластера ##{cluster.id}."
      return true
    end

    if peril_alerts.exists?(satellite_status: :inconclusive)
      Rails.logger.warn "☁️ [Insurance] Виплата заблокована — потрібен ручний DAO / Field-Audit для кластера ##{cluster.id}."
      return true
    end

    # [INS.1] Платимо ЛИШЕ за VERIFIED незалежним підтвердженням ВЛАСНОГО перилу.
    # `:rejected_fraud` буває лише для fire-алерту (заявлено пожежу, супутник вогню не
    # бачить) — ВІДМОВА, не confirmation → hold. Не-пожежний перил іде у :inconclusive
    # (Field Audit), НІКОЛИ rejected_fraud.
    # ⚠️ Наслідок звуження, який треба бачити прямо: `severe_drought`-алерт НЕ МАЄ
    # у дереві жодного писача `:verified`, тож поліс від посухи структурно недосяжний
    # для авто-виплати доти, доки не приземлиться реальне drought-джерело (S3.2 /
    # UNI.12). Це не регресія — це та сама діра, яку доти ХОВАВ чужий доказ.
    return false if peril_alerts.exists?(alert_type: confirming_type, satellite_status: :verified)

    Rails.logger.info "🛡️ [Insurance] Кластер ##{cluster.id}: незалежний алерт є, але НЕ verified (можливо rejected) — тримаємо, payout НЕ запущено."
    true
  end
end
