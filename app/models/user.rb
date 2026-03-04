# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ (Rails 8 Standard) ---
  # [ВИПРАВЛЕНО]: Вимикаємо стандартні валідації, щоб наш password_required? запрацював.
  has_secure_password validations: false

  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до фінансової мережі підлеглих дерев
  has_many :wallets, through: :organization
  has_many :maintenance_records, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :restrict_with_error

  # --- НОРМАЛІЗАЦІЯ ТА ВАЛІДАЦІЯ ---
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # [ВИПРАВЛЕНО]: Тепер пароль вимагається лише тоді, коли немає зовнішніх ідентичностей.
  # confirmation: true додає автоматичну перевірку password_confirmation.
  validates :password, presence: true, confirmation: true, on: :create, if: :password_required?
  validates :password, length: { minimum: 12 }, allow_blank: true

  # Строгий E.164 для SMS-шлюзів (напр. Twilio)
  normalizes :phone_number, with: ->(p) { p.to_s.gsub(/[^0-9+]/, "") }
  validates :phone_number, format: { with: /\A\+?[1-9]\d{1,14}\z/ }, allow_blank: true

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0,
    forester: 1,
    admin: 2,
    super_admin: 3
  }, prefix: true

  # --- СКОУПИ ---
  scope :notifiable, -> { where.not(phone_number: [ nil, "" ]).or(where.not(telegram_chat_id: nil)) }
  scope :active_foresters, -> { role_forester.where("last_seen_at >= ?", 1.hour.ago) }

  # --- ТОКЕНИ (The Magic of Rails 8) ---
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email_address
  end

  # [ВИПРАВЛЕНО]: "Вічний Токен" тепер має термін придатності та прив'язку до пароля.
  # Якщо змінити пароль — password_salt зміниться, і токен на вкраденому пристрої згорить.
  generates_token_for :api_access, expires_in: 30.days do
    password_salt&.last(10)
  end

  # --- МЕТОДИ ---

  def forest_commander?
    role_admin? || role_forester? || role_super_admin?
  end

  # [ORACLE EXECUTIONER]: Системний бот для автоматичних операцій.
  # Використовується замість User.find_by(role: :admin) || User.first,
  # щоб у журналах було чітко видно: це рішення системи, а не дія конкретної людини.
  def self.oracle_executioner
    find_by(email_address: "oracle.executioner@system.silken.net")
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email_address
  end

  def touch_visit!
    return if last_seen_at.present? && last_seen_at > 5.minutes.ago
    update_columns(last_seen_at: Time.current)
  end

  private

  # [ВИПРАВЛЕНО]: Тепер ця логіка реально керує валідацією.
  # Пароль не потрібен, якщо користувач прийшов через Google/Apple і вже має Identity.
  def password_required?
    identities.none?
  end
end
