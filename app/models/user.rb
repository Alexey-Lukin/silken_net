# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ (Rails 8 Standard) ---
  has_secure_password

  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до фінансової мережі підлеглих дерев
  has_many :wallets, through: :organization
  
  # Зв'язок з журналом робіт: фіксуємо відповідальність за залізо
  has_many :maintenance_records, dependent: :restrict_with_error

  # --- НОРМАЛІЗАЦІЯ ТА ВАЛІДАЦІЯ ---
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Строгий E.164 для SMS-шлюзів (напр. Twilio)
  normalizes :phone_number, with: ->(p) { p.to_s.gsub(/[^0-9+]/, "") }
  validates :phone_number, format: { with: /\A\+?[1-9]\d{1,14}\z/ }, allow_blank: true

  # --- РОЛЬОВА МОДЕЛЬ (RBAC: Role-Based Access Control) ---
  enum :role, {
    investor: 0, # Тільки читання, фінансові звіти (SCC Treasury)
    forester: 1, # Доступ до актуаторів, мобільний додаток, ритуали обслуговування
    admin: 2     # Повний контроль системи, еволюція прошивок (OTA)
  }, prefix: true

  # --- СКОУПИ (The Watchers) ---
  scope :notifiable, -> { where.not(phone_number: [nil, ""]).or(where.not(telegram_chat_id: nil)) }
  scope :active_foresters, -> { role_forester.where("last_seen_at >= ?", 1.hour.ago) }

  # --- ТОКЕНИ (The Magic of Rails 8) ---
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

  # Для "Remember Me" або безпарольного доступу з мобільного додатка Патрульного
  generates_token_for :api_access

  # --- МЕТОДИ (The Identity) ---

  # Перевірка наявності повноважень для польових операцій
  def forest_commander?
    role_admin? || role_forester?
  end

  # Естетичне відображення імені в Сайдбарі та Логах
  def full_name
    [first_name, last_name].compact_blank.join(" ").presence || email_address
  end

  # Оновлення активності (викликається в BaseController для моніторингу присутності в Цитаделі)
  def touch_visit!
    update_columns(last_seen_at: Time.current)
  end

  private

  # Пароль не потрібен лише у випадку, якщо користувач надійно запечатаний 
  # через зовнішнього провайдера (Google/Apple ID)
  def password_required?
    identities.none? || password.present?
  end
end
