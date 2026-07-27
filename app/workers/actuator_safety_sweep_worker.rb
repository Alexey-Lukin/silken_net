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
#   ✅ Розчакловує актуатор. До нього єдиний вихід із залипання — акт ремонту
#      (`MaintenanceRecord` action_type=repair → EcosystemHealingWorker), тобто
#      виїзд у ліс заради бухгалтерської втрати.
#   ✅ Чесний слід: наказ дістає термінальний стан із причиною, а не висить
#      `acknowledged` вічно (ARCH.57-ланцюг отримує `actuator_to_failed`).
#   ⚠️ Фізичного закриття НЕ дає: актуаторної прошивки не існує взагалі
#      (`queen/main.c` після «передаємо на виконання актуатору» не має жодного
#      рядка драйвера), тож `CMD:STOP` — forward-контракт, як і `duration_seconds`.
#   ⚠️ Алерт-нога напівмертва, доки ARCH.60 не оживить зовнішні канали.
#   ⚠️ Клас «БД чиста, а фізики не було» (втрачена 2.05) цей sweep НЕ ловить —
#      там `confirmed` виглядає бездоганно. Дім того класу — FW.63.
#
# Черга `downlink`(4), а не `alerts`(2) як у сусідніх dead-man switch'ів:
# продукт проходу — downlink-наказ (STOP), і він мусить дренажитись разом з
# рештою downlink-роботи; алерт тут побічний. Каденс — кожні 30 хв: флаш
# Королеви йде щонайбільше раз на годину (ARCH.75), тож частіший прохід нічого
# не пришвидшив би.
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

    Actuator.active.includes(:gateway, :commands).find_each do |actuator|
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
      # Часткове відновлення самолікується наступним проходом: наш же STOP уже
      # лічиться живим pending, тож другого не буде, а бухгалтерія дожметься.
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

  # Порядок несучий: спершу ФІЗИЧНА спроба, потім бухгалтерія. Крах між ногами
  # лишає STOP у черзі, а не порожнечу — голий force-idle відновив би лише
  # БД-правду й дав нуль фізичної безпеки.
  def recover!(actuator, newest)
    stop_queued = queue_stop_override!(actuator)
    close_lost_commands!(actuator)
    actuator.deactivate! if actuator.may_deactivate?
    raise_stuck_alert(actuator, newest, stop_queued)

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

  # `.pending` МІНУС протерміновані: протермінований наказ фейлиться лише в
  # момент poll-видачі, тож без цього фільтра мертві трупи в черзі глушили б
  # ногу STOP назавжди саме там, де Королева перестала питати.
  def live_pending?(actuator)
    actuator.commands.pending
            .where("expires_at IS NULL OR expires_at > ?", Time.current)
            .exists?
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
