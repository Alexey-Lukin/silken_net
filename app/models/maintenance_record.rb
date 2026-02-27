# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  # Хто проводив роботи (Лісник / Інженер)
  belongs_to :user
  # До чого застосовувались роботи (Tree або Gateway)
  belongs_to :maintainable, polymorphic: true
  # (Опційно) Посилання на тривогу, яка спричинила виїзд
  belongs_to :ews_alert, optional: true

  enum :action_type, {
    installation: 0, 
    inspection: 1,   
    cleaning: 2,     
    repair: 3,       
    decommissioning: 4 
  }, prefix: true

  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }

  scope :recent, -> { order(performed_at: :desc) }

  # [НОВЕ]: Після обслуговування "освіжаємо" пристрій
  after_create :refresh_maintainable_status

  private

  def refresh_maintainable_status
    # Якщо ми обслужили шлюз, оновлюємо його last_seen_at
    if maintainable.respond_to?(:mark_seen!)
      maintainable.mark_seen!
    end
  end
end
