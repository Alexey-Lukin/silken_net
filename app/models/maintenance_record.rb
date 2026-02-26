# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  # Хто проводив роботи (Лісник / Інженер)
  belongs_to :user
  # До чого застосовувались роботи (Tree або Gateway)
  belongs_to :maintainable, polymorphic: true

  # Типи фізичного втручання
  enum :action_type, {
    installation: 0, # Встановлення анкера / шлюзу
    inspection: 1,   # Плановий або позаплановий (EWS) огляд
    cleaning: 2,     # Очищення від моху, бруду, снігу (особливо для сонячних панелей)
    repair: 3,       # Заміна компонентів (напр., антени)
    decommissioning: 4 # Зняття пристрою
  }, prefix: true

  validates :action_type, :performed_at, presence: true
  # notes: текст (опис того, що було зроблено)
  validates :notes, presence: true, length: { minimum: 10 }

  scope :recent, -> { order(performed_at: :desc) }
end
