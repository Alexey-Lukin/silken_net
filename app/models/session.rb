# frozen_string_literal: true

class Session < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user

  # --- ВАЛІДАЦІЇ ---
  validates :ip_address, presence: true
  validates :user_agent, presence: true

  # --- КОЛБЕКИ (Operational Pulse) ---
  # Оновлюємо пульс користувача при створенні сесії
  after_create :track_user_activity
  # При кожному оновленні (touch) сесії — оновлюємо і користувача
  after_touch :track_user_activity

  # --- СКОУПИ (Housekeeping) ---
  # Очищення застарілих сесій (Кенозис доступу)
  scope :stale, -> { where("updated_at < ?", 30.days.ago) }
  
  # [ВИПРАВЛЕНО]: Знаходження активних сесій лісників за останньою активністю (updated_at)
  scope :active_in_field, -> { 
    joins(:user)
      .where(users: { role: :forester })
      .where("sessions.updated_at > ?", 24.hours.ago) 
  }

  # --- МЕТОДИ (Device Intelligence) ---

  def mobile_app?
    user_agent.to_s.match?(/SilkenNetMobile/i)
  end

  # Повертає назву пристрою для аудиту безпеки
  def device_name
    case user_agent
    when /iPhone/i then "iPhone App"
    when /Android/i then "Android App"
    when /Chrome/i then "Desktop Chrome"
    when /Firefox/i then "Desktop Firefox"
    when /PostmanRuntime/i then "API Console (Dev)"
    when /Insomnia/i then "API Debugger"
    else "Unknown Node"
    end
  end

  # [НОВЕ]: Метод для оновлення активності, який буде викликатися в BaseController
  def touch_activity!
    touch
    user.update_column(:last_seen_at, Time.current)
  end

  private

  def track_user_activity
    # Використовуємо update_column, щоб не тригерити валідації та інші колбеки User
    user.update_column(:last_seen_at, Time.current) if user.respond_to?(:last_seen_at)
  end
end
