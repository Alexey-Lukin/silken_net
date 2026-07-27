# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ResetActuatorStateWorker
  include Sidekiq::Job

  # Пріоритет downlink: завершення дії так само важливе, як і її початок.
  sidekiq_options queue: "downlink", retry: 3

  def perform(command_id)
    # Шукаємо через find_by, щоб уникнути зайвих виключень у логах при видаленні команд
    command = ActuatorCommand.find_by(id: command_id)

    unless command
      Rails.logger.warn "⚠️ [Actuator Lifecycle] Команду ##{command_id} не знайдено. Кенозис скасовано."
      return
    end

    actuator = command.actuator
    # Ланцюг gateway→cluster→organization більше не потрібен: стрім тепер вузький
    # (`[actuator, :commands]`, UI.4), тож організацію обчислювати нема для чого.

    # [ARCH.58] Закриваємо актуатор ЛИШЕ якщо цей наказ і володіє поточним
    # вікном. Інакше перший же Reset гасив чужу, ПІЗНІШУ команду: під
    # poll-семантикою кілька наказів на один актуатор видаються підряд (кожен
    # переозброює власний Reset), тож найстаріший таймер приходив першим і
    # обривав вікно найновішого — виміряно на серії аварійних чанків.
    # Витіснений наказ усе одно закривається нижче, просто без mark_idle!.
    #
    # ⚠️ Свідомо НЕ чіпаємо наказ у `:sent` (пункт просив «гартувати на
    # stale-:sent» — форма з push-ери): `:sent` лежить у скоупі `.pending`, тож
    # наступна poll-видача його ЛЕГАЛЬНО доакноледжить і переозброїть Reset.
    # `fail!` тут убив би доставну команду; мертвий шлюз — інша діагностика
    # (`queen_offline`, ARCH.54), не наша.
    if actuator.active? && !superseded?(command)
      ActiveRecord::Base.transaction do
        # 1. Повертаємо фізичний об'єкт у гомеостаз (IDLE)
        actuator.mark_idle!

        # 2. Закриваємо наказ у базі даних (AASM: acknowledged → confirmed)
        command.confirm! if command.may_confirm?
      end

      Rails.logger.info "♻️ [Actuator Lifecycle] Механізм #{actuator.name} виконав наказ ##{command.id} і повернувся в спокій."
    else
      # Якщо стан уже не active (наприклад, :maintenance_needed або :offline)
      Rails.logger.info "ℹ️ [Actuator Lifecycle] Скидання скасовано. Механізм #{actuator.name} у стані '#{actuator.state}'."

      # Ми все одно маркуємо команду як завершену, навіть якщо стан змінився ззовні
      command.confirm! if command.may_confirm?
    end

    # ⚡ [СИНХРОНІЗАЦІЯ З UI]: Відправляємо фінальний імпульс Архітектору
    broadcast_final_state(command)
  end

  private

  # [ARCH.58] Чи є на цьому актуаторі СТРОГО пізніший підтверджений наказ.
  # `sent_at` у `:acknowledged` завжди present (ставить `dispatch`, підстраховує
  # `acknowledge`), тож порівняння безпечне без nil-гарду. Строгість несуча:
  # при включному порівнянні два накази з однаковою міткою вважали б одне
  # одного пізнішими — і актуатор не закрив би ЖОДЕН.
  def superseded?(command)
    command.actuator.commands
           .status_acknowledged
           .where.not(id: command.id)
           .where("sent_at > ?", command.sent_at)
           .exists?
  end

  # Оновлюємо статус самої команди. Друга половина — заміна великої картки
  # актуатора — знята (UI.4): вона цілила в `actuator_card_{id}`, а `Actuators::Card`
  # рендерить `actuator_{id}`, тож ціль не існувала ніде. І сам фікс рядка був би
  # пасткою: `Card#render_controls` має гард на відсутність request-контексту, тож
  # картка з воркера приходить БЕЗ кнопок Execute — регресія у вигляді фічі.
  #
  # Реюз статичного методу свідомий: до 2026-07-27 тут жила ДРУГА, незалежна
  # реалізація того самого броадкасту (з іншим обчисленням organization), тож
  # будь-яка правка форми мусила лягати у два місця й одного разу не лягла б.
  # Тепер стрім, ціль і payload описані рівно один раз.
  #
  # ⚠️ Разом із формою успадковано й rescue-ізоляцію — і це ЗМІНА ПОВЕДІНКИ, не
  # лише дедуп: раніше збій cable тут піднімався в Sidekiq і джоба ретраїлась,
  # чесно повторюючи пульс (perform ідемпотентний). Тепер збій лише логується.
  # Обґрунтування — у самому `broadcast_command_state_static`.
  def broadcast_final_state(command)
    ActuatorCommandWorker.broadcast_command_state_static(command)
  end
end
