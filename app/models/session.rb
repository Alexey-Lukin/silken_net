# frozen_string_literal: true

class Session < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user

  # --- ВАЛІДАЦІЇ ---
  validates :ip_address, presence: true
  validates :user_agent, presence: true

  # --- КОЛБЕКИ (Operational Pulse) ---
  after_create :track_user_activity
  # [СИНХРОНІЗОВАНО]: after_touch — це наш єдиний центр оновлення активності
  after_touch :track_user_activity

  # --- СКОУПИ ---
  scope :stale, -> { where("updated_at < ?", 30.days.ago) }
  scope :active_in_field, -> {
    joins(:user).where(users: { role: :forester }).where("sessions.updated_at > ?", 24.hours.ago)
  }

  # --- МЕТОДИ ---

  def mobile_app?
    user_agent.to_s.match?(/SilkenNetMobile/i)
  end

  # [ВИПРАВЛЕНО]: Ми ліквідували "Ефект Подвійного Удару".
  # Тепер метод touch просто тригерить after_touch колбек, який оновить користувача.
  def touch_activity!
    touch
  end

  private

  def track_user_activity
    # [ВИПРАВЛЕНО]: Видалено respond_to? та зайвий update_column.
    # Існування last_seen_at гарантоване схемою Матриці.
    user.update_column(:last_seen_at, Time.current)
  end
end
