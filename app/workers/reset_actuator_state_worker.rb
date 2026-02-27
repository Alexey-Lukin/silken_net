# frozen_string_literal: true

class ResetActuatorStateWorker
  include Sidekiq::Job
  
  # Використовуємо чергу downlink, оскільки це частина життєвого циклу управління лісом.
  # retry: 3 гарантує, що якщо БД тимчасово заблокована, стан все одно відновиться.
  sidekiq_options queue: "downlink", retry: 3

  def perform(actuator_id)
    # Використовуємо find_by, щоб уникнути Exception, якщо актуатор (або дерево) 
    # фізично знищили і видалили з бази під час його роботи.
    actuator = Actuator.find_by(id: actuator_id)

    unless actuator
      Rails.logger.warn "⚠️ [Actuator Lifecycle] Актуатор #{actuator_id} не знайдено. Можливо, вузол було демонтовано."
      return
    end

    # ПЕРЕВІРКА ІСТИНИ (Кенозис стану)
    # Ми переводимо в idle ТІЛЬКИ якщо він дійсно був active. 
    # Якщо лісник вручну перевів його в maintenance (обслуговування) або pending, ми не ламаємо цей стан.
    if actuator.state == "active"
      actuator.update!(state: :idle)
      Rails.logger.info "♻️ [Actuator Lifecycle] Механізм #{actuator.id} (Шлюз: #{actuator.gateway.uid}) завершив роботу і повернутий у стан :idle."
    else
      Rails.logger.info "ℹ️ [Actuator Lifecycle] Механізм #{actuator.id} має стан '#{actuator.state}', а не 'active'. Скидання проігноровано."
    end
  end
end
