# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user

  # ip_address: рядок (IP, з якого здійснено вхід)
  # user_agent: рядок (Браузер або модель мобільного телефону)

  validates :ip_address, presence: true
  validates :user_agent, presence: true

  # [НОВЕ]: Оновлюємо час останньої активності користувача при кожному запиті
  # Це дозволить у Gateway показувати "Online" статус лісників
  after_create { user.touch(:last_seen_at) if user.respond_to?(:last_seen_at) }

  # Скоуп для знаходження старих сесій, які варто очистити (наприклад, старші 30 днів)
  scope :stale, -> { where("created_at < ?", 30.days.ago) }

  # Метод для перевірки, чи сесія належить мобільному додатку (по User-Agent)
  def mobile_app?
    user_agent.match?(/SilkenNetMobile/i)
  end

  # [НОВЕ]: Повертає людську назву пристрою для дашборду безпеки
  def device_name
    case user_agent
    when /iPhone/i then "iPhone App"
    when /Android/i then "Android App"
    when /Chrome/i then "Google Chrome"
    when /Firefox/i then "Mozilla Firefox"
    else "Unknown Device"
    end
  end
end
