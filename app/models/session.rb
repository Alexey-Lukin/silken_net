# frozen_string_literal: true

class Session < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user

  # --- ВАЛІДАЦІЇ ---
  validates :ip_address, presence: true
  validates :user_agent, presence: true

  # --- КОЛБЕКИ (Operational Pulse) ---
  # [ПОКРАЩЕНО]: Ми оновлюємо last_seen_at не тільки при створенні,
  # а й при кожному зверненні (це зазвичай робиться через Current.session у контролері,
  # але логіка в моделі — хороший фолбек).
  after_create :track_user_activity

  # --- СКОУПИ (Housekeeping) ---
  # Очищення застарілих сесій (Кенозис доступу)
  scope :stale, -> { where("created_at < ?", 30.days.ago) }
  
  # [НОВЕ]: Знаходження активних сесій саме лісників у полі
  scope :active_in_field, -> { joins(:user).where(users: { role: :forester }).where("sessions.created_at > ?", 24.hours.ago) }

  # --- МЕТОДИ (Device Intelligence) ---

  def mobile_app?
    user_agent.match?(/SilkenNetMobile/i)
  end

  # Повертає назву пристрою для аудиту безпеки
  def device_name
    case user_agent
    when /iPhone/i then "iPhone App"
    when /Android/i then "Android App"
    when /Chrome/i then "Desktop Chrome"
    when /Firefox/i then "Desktop Firefox"
    when /PostmanRuntime/i then "API Console (Dev)"
    else "Unknown Node"
    end
  end

  private

  def track_user_activity
    # Використовуємо update_column, щоб не тригерити валідації та інші колбеки User
    user.update_column(:last_seen_at, Time.current) if user.respond_to?(:last_seen_at)
  end
end
