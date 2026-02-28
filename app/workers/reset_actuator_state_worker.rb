# frozen_string_literal: true

class ResetActuatorStateWorker
  include Sidekiq::Job
  
  # Використовуємо чергу downlink. 
  # Це гарантує, що цикли управління не заблокують розпаковку телеметрії.
  sidekiq_options queue: "downlink", retry: 3

  # [ЗМІНА]: Приймаємо ID конкретної команди, щоб знати, ЩО САМЕ ми завершуємо
  def perform(command_id)
    command = ActuatorCommand.find_by(id: command_id)

    unless command
      Rails.logger.warn "⚠️ [Actuator Lifecycle] Команду #{command_id} не знайдено. Кенозис скасовано."
      return
    end

    actuator = command.actuator

    # ПЕРЕВІРКА ІСТИНИ (Кенозис стану)
    if actuator.state_active?
      ActiveRecord::Base.transaction do
        # 1. Повертаємо фізичний об'єкт у гомеостаз (використовуємо метод моделі)
        actuator.mark_idle!
        
        # 2. [ЗШИВКА З АУДИТОМ]: Закриваємо конкретний наказ
        command.update!(status: :confirmed)
      end

      Rails.logger.info "♻️ [Actuator Lifecycle] Механізм #{actuator.name} завершив наказ #{command.id} і заснув."
    else
      # Якщо стан вже змінився (наприклад, патрульний перевів у maintenance_needed)
      Rails.logger.info "ℹ️ [Actuator Lifecycle] Механізм #{actuator.name} перебуває у стані '#{actuator.state}'. Автоматичне скидання скасовано."
    end
  end
end
