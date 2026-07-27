# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =========================================================================
# 🔧 ACTUATOR SAFETY SWEEP [ARCH.58] — сторож загубленого сліду
# =========================================================================
# Актуатор числиться `active` довше за вікно своєї найновішої команди —
# отже Rails загубив слід власного наказу: втрачена scheduled-джоба Reset
# (Redis), крах між комітом видачі та `perform_in`, вичерпані ретраї воркера.
#
# 🔒 Що цей sweep РЕАЛЬНО дає сьогодні — і чого НЕ дає (чесна стеля):
#   ✅ Розчакловує актуатор ДЕТЕРМІНОВАНО. Без нього виходів було два, і обидва
#      випадкові: акт ремонту (`MaintenanceRecord` repair → EcosystemHealingWorker)
#      або наступний EWS-інцидент — `EmergencyResponseService` таргетить
#      `state: [:idle, :active]`, тож його `insert_all` минає readiness-гейт, і
#      Reset тієї команди закриє актуатор. Тобто залипання «самолікувалось»
#      чужим трафіком; команда ВІД ЛЮДИНИ цього не вміла (гине при створенні).
#      ⚠️ Обидва випадкові виходи ще й ненадійні: на рідкому флоті EWS-команди
#      мруть за власним 15-хв TTL до першого poll'а (ARCH.75).
#   ✅ Чесний слід: загублений наказ дістає термінальний стан із причиною
#      (ARCH.57-ланцюг отримує `actuator_to_failed`). ⚠️ Стеля вужча, ніж
#      здається: витіснений наказ закриває сам Reset (else-гілка), а якщо
#      загублено ОБИДВА Reset'и — актуатор лишається active, і прохід закриє
#      обидва накази. Вічно висить лише комбінація «мій Reset загублено, чужий
#      спрацював»: актуатор уже `idle`, а прохід сканує тільки `Actuator.active`.
#   ⚠️ Фізичного закриття НЕ дає: актуаторної прошивки не існує взагалі
#      (`queen/main.c` після «передаємо на виконання актуатору» не має жодного
#      рядка драйвера), тож `CMD:STOP` — forward-контракт, як і `duration_seconds`.
#   ⚠️ Алерт-нога напівмертва, доки ARCH.60 не оживить зовнішні канали.
#   ⚠️ Клас «БД чиста, а фізики не було» (втрачена 2.05) цей sweep НЕ ловить —
#      там `confirmed` виглядає бездоганно. Дім того класу — FW.63.
#
# Черга `downlink`(4), а не `alerts`(2) як у сусідніх dead-man switch'ів —
# доменна приналежність, НЕ механіка доставки: STOP їде не Sidekiq-чергою, а
# рядком БД, який синхронно віддає CoAP-демон при poll'і, тож черга воркера на
# швидкість доставки не впливає ніяк. Каденс 30 хв — прагматика, і НИЖНЬОЇ межі
# частоти флашу не існує взагалі: таймерний флаш гейтований `cache_count > 0 ||
# ed25519_ready`, тож legacy-Королева (без QATT-підпису) з порожнім кешем не
# флашить і не поллить НІКОЛИ. На завантаженому кластері частіший прохід
# доставляв би STOP раніше; на мовчазній legacy-Королеві не допоміг би жоден.
class ActuatorSafetySweepWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 2

  # Люфт на планувальну затримку Sidekiq між `perform_in` і фактичним запуском
  # Reset'а. Інженерний факт, не біо-параметр → константа, а не SystemParameter
  # (дзеркало STUCK_THRESHOLD у StuckSentTransactionSweeperWorker).
  STUCK_MARGIN = 5.minutes

  # TTL нашого ж STOP. Мусить пережити найгірший каденс poll'а (флаш ≤ година +
  # джиттер — ARCH.75), але мусить і згаснути: безсмертний невиданий STOP навіки
  # тримав би `live_pending?` істинним і глушив би цю саму ногу на цьому
  # актуаторі.
  STOP_TTL = 6.hours
  STOP_DURATION_S = 1

  def perform
    recovered = 0

    # `includes(:commands)` тут БУВ би марним: усі три споживачі додають власні
    # скоупи, тож прелоад не реюзається, а на великому флоті тягнув би в RAM усю
    # історію команд. Прелоадимо лише `:gateway` (читається як є).
    Actuator.active.includes(:gateway).find_each do |actuator|
      newest = newest_acknowledged(actuator)
      # Активний актуатор БЕЗ жодного підтвердженого наказу — вікна для присуду
      # не існує, тож мовчимо. Продовим шляхом це недосяжно (`mark_active!`
      # живе рівно в одній транзакції з `acknowledge!`); стеля названа свідомо.
      next if newest.nil?
      next if Time.current < deadline_for(newest)

      recover!(actuator, newest)
      recovered += 1
    rescue ActiveRecord::ActiveRecordError, AASM::InvalidTransition => e
      # Rescue НА ЗАПИС (дзеркало StuckSentAnchorSweeper/FilecoinVerificationSweep):
      # один проблемний актуатор не сміє обірвати прохід для решти флоту.
      # Транзакція вище вже відкотила ВЕСЬ набір по цьому актуатору (STOP теж
      # не персистувався), тож наступний прохід починає з чистого стуку —
      # не з половини.
      Rails.logger.error "🛑 [ARCH.58] Актуатор ##{actuator.id} не розчакловано: #{e.message}"
    end

    Rails.logger.warn "🔧 [ARCH.58] Safety sweep: розчакловано #{recovered} актуатор(ів)" if recovered.positive?
  end

  private

  def newest_acknowledged(actuator)
    actuator.commands.status_acknowledged.where.not(sent_at: nil).order(:sent_at).last
  end

  def deadline_for(command)
    command.sent_at + command.duration_seconds.seconds + STUCK_MARGIN
  end

  # 🔴 Атомарність тут не стиль, а лік від реального дефекту: `close_lost_commands!`
  # спалює ПАЛИВО ВЛАСНОГО ПРЕДИКАТА (усі прострочені `:acknowledged`), тож крах
  # між ним і `deactivate!` лишив би актуатор `active` БЕЗ жодного підтвердженого
  # наказу — `newest_acknowledged` віддав би nil, і прохід мовчки скіпав би його
  # НАЗАВЖДИ. Дзеркально крах перед алертом лишив би idle-актуатор без сліду (idle
  # не сканується взагалі). Транзакція робить обидва стани недосяжними: або весь
  # набір, або нічого й повтор наступним проходом.
  #
  # Порядок усередині лишається змістовним (спершу фізична спроба, потім
  # бухгалтерія), але вже не несе гарантії — її несе транзакція.
  def recover!(actuator, newest)
    stop_queued = false

    ActiveRecord::Base.transaction do
      stop_queued = queue_stop_override!(actuator)
      close_lost_commands!(actuator)
      actuator.deactivate! if actuator.may_deactivate?
      raise_stuck_alert(actuator, newest, stop_queued)
    end

    SilkenNet::Metrics::ACTUATOR_STUCK_RECOVERED_TOTAL.increment(
      labels: { device_type: actuator.device_type }
    )
  end

  # STOP їде лише коли черга порожня. Якщо в ній є ЖИВИЙ наказ — наступна
  # poll-видача сама переозброїть Reset, а override дорогою знищив би чергу
  # (`cancel_pending_for_actuator!`): аварійні чанки поливу під час пожежі.
  # Заразом це природний дедуп власного STOP — невиданий STOP сам лічиться
  # живим pending.
  def queue_stop_override!(actuator)
    return false if live_pending?(actuator)

    actuator.commands.create!(
      command_payload: "STOP",
      duration_seconds: STOP_DURATION_S,
      expires_at: STOP_TTL.from_now,
      status: :issued
    )
    true
  end

  # Скоуп `live_pending` (дім — модель) МІНУС старші за `STOP_TTL`. Вік-межа
  # потрібна поверх скоупа, бо наказ БЕЗ `expires_at` протермінуватись не може
  # взагалі — а таким є КОЖНА команда від контролера ([ARCH.75]), тож людський
  # STOP на мертвому шлюзі інакше глушив би цю ногу ВІЧНО. Якщо наказ чекає
  # довше, ніж прожив би наш власний STOP, він більше не є сигналом «черга
  # ось-ось переозброїть Reset».
  def live_pending?(actuator)
    actuator.commands.live_pending.where(created_at: STOP_TTL.ago..).exists?
  end

  # `fail!`, а не `confirm!`: ми НЕ знаємо, чи наказ виконався. `confirm!` тут
  # був би тією самою брехнею, що й таймерне підтвердження — лише записаною
  # сторожем, який прийшов її виправити.
  def close_lost_commands!(actuator)
    actuator.commands.status_acknowledged.where.not(sent_at: nil).find_each do |command|
      next if Time.current < deadline_for(command)

      command.fail!("Слід наказу загублено: актуатор числився активним понад вікно (ARCH.58)")
    end
  end

  # Дедуп по `message_params ->> 'actuator_id'`, а не по кластеру: на одному
  # кластері може бути кілька актуаторів, і cluster-scoped guard (як у
  # Queen-sweeper'а, де Королева одна) глушив би сусідів. `actuator_id` у
  # параметрах несе саме цю роль — у тексті він не інтерполюється.
  #
  # Машинного resolve НЕМА свідомо: фізичний стан пристрою нам невідомий, тож
  # закрити алерт може лише людина, що подивилась на залізо.
  def raise_stuck_alert(actuator, newest, stop_queued)
    # `cluster_id` завжди present: `Gateway#belongs_to :cluster` обов'язковий, а
    # колонка — NOT NULL. Гард тут був би мертвою гілкою (перевірено тестом).
    cluster_id = actuator.gateway.cluster_id
    return if stuck_alert_exists?(cluster_id, actuator)

    EwsAlert.create!(
      cluster_id: cluster_id,
      severity: :critical,
      alert_type: :actuator_stuck,
      message_key: stop_queued ? "actuator_stuck_stop_queued" : "actuator_stuck",
      message_params: {
        name: actuator.name, endpoint: actuator.endpoint,
        stuck_for_min: ((Time.current - deadline_for(newest)) / 60).round,
        command_id: newest.id, actuator_id: actuator.id
      }
    )
  end

  def stuck_alert_exists?(cluster_id, actuator)
    EwsAlert.unresolved.alert_type_actuator_stuck
            .where(cluster_id: cluster_id)
            .where("message_params ->> 'actuator_id' = ?", actuator.id.to_s)
            .exists?
  end
end
