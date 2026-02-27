# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # [ВИПРАВЛЕНО]: В однині, як вимагає конвенція Rails
  belongs_to :actuator 
  # Команда може бути згенерована автоматично (від Оракула) або ручною (від Патрульного)
  belongs_to :ews_alert, optional: true 

  # --- СТАТУСИ (The Lifecycle of a Command) ---
  enum :status, {
    issued: 0,       # Створено в БД, очікує захоплення воркером
    sent: 1,         # Вистрілено через CoapClient на IP Королеви
    acknowledged: 2, # Отримано ACK від модема SIM7070G
    failed: 3        # Мережевий таймаут або помилка шифрування
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  # command_payload: "OPEN_VALVE", "SIREN_ON" тощо (або байт-код)
  # duration_seconds: скільки часу пристрій має працювати (напр. полив 600 сек)
  validates :command_payload, :duration_seconds, presence: true

  # --- КОЛБЕКИ (Zero-Lag Execution) ---
  # Як тільки наказ зафіксовано в блокноті БД, миттєво віддаємо його гінцю
  after_commit :dispatch_to_edge!, on: :create

  private

  def dispatch_to_edge!
    # Тільки якщо Актуатор готовий до роботи (щоб не забивати чергу мертвими запитами)
    if actuator.ready_for_deployment?
      ActuatorCommandWorker.perform_async(self.id)
    else
      # Якщо шлюз офлайн, миттєво маркуємо наказ як провалений
      update_columns(status: ActuatorCommand.statuses[:failed])
      Rails.logger.warn "🛑 [COMMAND] Скасовано: Актуатор #{actuator.name} недоступний."
    end
  end
end
