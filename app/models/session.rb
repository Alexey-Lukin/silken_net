# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user

  # ip_address: рядок (IP, з якого здійснено вхід)
  # user_agent: рядок (Браузер або модель мобільного телефону)

  validates :ip_address, presence: true
  validates :user_agent, presence: true

  # Скоуп для знаходження старих сесій, які варто очистити (наприклад, старші 30 днів)
  scope :stale, -> { where("created_at < ?", 30.days.ago) }

  # Метод для перевірки, чи сесія належить мобільному додатку (по User-Agent)
  def mobile_app?
    user_agent.match?(/SilkenNetMobile/i)
  end
end
