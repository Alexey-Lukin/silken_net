# frozen_string_literal: true

class ResetActuatorStateWorker
  include Sidekiq::Job
  
  # Використовуємо чергу downlink. Це гарантує, що цикли управління
  # не будуть заблоковані важкими фоновими розрахунками.
  sidekiq_options queue: "downlink", retry: 3

  def perform(actuator_id)
    # Безпечний пошук. Якщо дерево зрубали або актуатор демонтували — ми просто йдемо далі.
    actuator = Actuator.find_by(id: actuator_id)

    unless actuator
      Rails.logger.warn "⚠️ [Actuator Lifecycle] Актуатор #{actuator_id} не знайдено. Можливо, вузол було демонтовано під час виконання."
      return
    end

    # ПЕРЕВІРКА ІСТИНИ (Кенозис стану)
    # Використовуємо предикат енума для чистоти коду.
    if actuator.state_active?
      ActiveRecord::Base.transaction do
        actuator.update!(state: :idle)
        
        # [ЗШИВКА З АУДИТОМ]: Позначаємо останню команду як завершену (якщо ми впровадили ActuatorCommand)
        # Це дозволяє закрити часовий проміжок виконання в звіті інвестору.
        actuator.actuator_commands.where(status: :acknowledged).update_all(status: :confirmed)
      end

      Rails.logger.info "♻️ [Actuator Lifecycle] Механізм #{actuator.name} (ID: #{actuator.id}) завершив цикл і повернувся у гомеостаз (:idle)."
    else
      # Якщо стан вже змінився (наприклад, лісник перевів у maintenance_needed), ми не втручаємось.
      Rails.logger.info "ℹ️ [Actuator Lifecycle] Механізм #{actuator.id} перебуває у стані '#{actuator.state}'. Автоматичне скидання скасовано."
    end
  end
end
