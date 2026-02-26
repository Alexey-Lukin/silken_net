# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  belongs_to :tree

  # Рівень критичності інциденту
  enum :severity, {
    low: 0,      # Потребує уваги при наступному обході
    medium: 1,   # Прогресуюча посуха або хвороба
    critical: 2  # Миттєва реакція (вандалізм, пожежа, спилювання)
  }, prefix: true

  # Тип загрози, який бекенд класифікує на основі даних телеметрії
  enum :alert_type, {
    drought: 0,    # Падіння вологості / зміна метаболізму
    pest: 1,       # Специфічна кавітація (Жук-короїд)
    vandalism: 2,  # Вібрація від бензопили (Акустика = 0xFF)
    system_fault: 3 # Анкер перестав виходити на зв'язок (впала напруга Vcap)
  }, prefix: true

  validates :severity, :alert_type, :description, presence: true

  # Скоупи для панелі управління лісника
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  # Метод для "закриття" інциденту після фізичного огляду дерева
  def resolve!
    update!(resolved_at: Time.current)
  end

  def resolved?
    resolved_at.present?
  end
end
