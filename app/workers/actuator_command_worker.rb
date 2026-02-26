# frozen_string_literal: true

class ActuatorCommandWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  def perform(actuator_id, command_code, duration_seconds)
    actuator = Actuator.find(actuator_id)
    gateway = actuator.gateway

    # Переводимо статус у базі в 'active'
    actuator.update!(state: :active)

    # Формуємо CoAP/UDP Payload.
    # Наприклад: "CMD:OPEN_VALVE:7200:ACT_ID_12"
    payload = "CMD:#{command_code}:#{duration_seconds}:#{actuator.id}"

    # Відправляємо команду на IP-адресу Королеви
    CoapClient.put("coap://#{gateway.ip_address}/actuator", payload)

    Rails.logger.info "⚡ [Downlink] Команда #{command_code} успішно відправлена на шлюз #{gateway.uid}"

    # Плануємо фонову задачу, яка поверне статус механізму назад в idle,
    # коли час роботи (duration_seconds) вийде.
    ResetActuatorStateWorker.perform_in(duration_seconds.seconds, actuator_id)
  end
end
