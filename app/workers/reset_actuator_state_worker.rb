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
    organization = actuator.gateway.cluster.organization

    # Перевіряємо, чи актуатор все ще активний
    if actuator.state_active?
      ActiveRecord::Base.transaction do
        # 1. Повертаємо фізичний об'єкт у гомеостаз (IDLE)
        actuator.mark_idle!

        # 2. Закриваємо наказ у базі даних (completed_at, якщо є така колонка, або просто update)
        command.update!(status: :confirmed)
        # command.update!(status: :confirmed, completed_at: Time.current) # Розкоментуй, якщо додав колонку
      end

      Rails.logger.info "♻️ [Actuator Lifecycle] Механізм #{actuator.name} виконав наказ ##{command.id} і повернувся в спокій."
    else
      # Якщо стан уже не active (наприклад, :maintenance_needed або :offline)
      Rails.logger.info "ℹ️ [Actuator Lifecycle] Скидання скасовано. Механізм #{actuator.name} у стані '#{actuator.state}'."

      # Ми все одно маркуємо команду як завершену, навіть якщо стан змінився ззовні
      command.update!(status: :confirmed) if command.status_acknowledged?
    end

    # ⚡ [СИНХРОНІЗАЦІЯ З UI]: Відправляємо фінальний імпульс Архітектору
    broadcast_final_state(command, organization)
  end

  private

  def broadcast_final_state(command, organization)
    # 1. Оновлюємо статус самої команди в списку недавніх активностей
    Turbo::StreamsChannel.broadcast_replace_to(
      organization,
      target: "command_status_#{command.id}",
      html: Views::Components::Actuators::CommandStatusBadge.new(command: command).call
    )

    # 2. Оновлюємо велику картку актуатора, знімаючи з неї пульсуючий ефект "Active"
    Turbo::StreamsChannel.broadcast_replace_to(
      organization,
      target: "actuator_card_#{command.actuator.id}",
      html: Views::Components::Actuators::Card.new(actuator: command.actuator).call
    )
  end
end
