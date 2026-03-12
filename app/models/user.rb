# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ (Argon2id — OWASP Recommended) ---
  # Argon2id замість bcrypt: memory-hard хешування, стійке до GPU/ASIC атак.
  # Інтерфейс сумісний з has_secure_password (password=, authenticate, password_salt).
  include HasArgon2Password

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

  # Валідація: роль обов'язкова для коректної роботи RBAC
  validates :role, presence: true

  # --- РОЛЬОВА МОДЕЛЬ (RBAC) ---
  enum :role, {
    investor: 0,
    forester: 1,
    admin: 2,
    super_admin: 3
  }, prefix: true, default: :investor

  # --- Series C (Privacy & Localization) ---
  # TODO: Додати поля timezone та locale при розширенні на міжнародні ринки.
  # validates :timezone, presence: true, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  # validates :locale, presence: true, inclusion: { in: %w[uk en es] }

  # --- СКОУПИ ---
  scope :notifiable, -> { where.not(phone_number: [ nil, "" ]).or(where.not(telegram_chat_id: nil)) }
  scope :active_foresters, -> { role_forester.where("last_seen_at >= ?", 1.hour.ago) }
  scope :mfa_enabled, -> { where(otp_required_for_login: true) }

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

  generates_token_for :stream_access, expires_in: 1.hour do
    password_salt&.last(10)
  end

  # --- МЕТОДИ ---

  def forest_commander?
    role_admin? || role_forester? || role_super_admin?
  end

  # --- RBAC: Розподіл повноважень (Series D) ---
  # Повертає рівень доступу для використання в контролерах та політиках.
  # :system  — повний доступ до всієї системи (super_admin)
  # :organization — повний доступ в межах своєї організації (admin, прив'язаний до org)
  # :field — польовий доступ (forester, прив'язаний до org)
  # :read_only — лише перегляд власних ресурсів (investor)
  def access_level
    if role_super_admin?
      :system
    elsif role_admin? && organization_id.present?
      :organization
    elsif role_forester? && organization_id.present?
      :field
    else
      :read_only
    end
  end

  # --- RBAC: Зручні методи-делегати (Series D) ---
  # Уніфіковане іменування (без role_ префікса) для використання в authorize_ методах.
  def super_admin?
    role_super_admin?
  end

  def organization_admin?
    role_admin? && organization_id.present?
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

  # --- MFA / TOTP (Зона 4: Security) ---
  # Перевірка чи MFA активовано для цього користувача
  def mfa_enabled?
    otp_required_for_login?
  end

  # Кількість невикористаних recovery codes
  def recovery_codes_remaining
    parsed_recovery_codes.size
  end

  # Перевірка recovery code (одноразового використання)
  def consume_recovery_code!(code)
    codes = parsed_recovery_codes
    return false unless codes.include?(code)

    codes.delete(code)
    update!(recovery_codes: codes.to_json)
    true
  end

  # Генерація нового набору recovery codes (10 штук)
  def generate_recovery_codes!
    codes = Array.new(10) { SecureRandom.hex(4) }
    update!(recovery_codes: codes.to_json)
    codes
  end

  private

  # [ВИПРАВЛЕНО]: Тепер ця логіка реально керує валідацією.
  # Пароль не потрібен, якщо користувач прийшов через Google/Apple і вже має Identity.
  def password_required?
    identities.none?
  end

  # Парсимо recovery_codes з JSON тексту
  def parsed_recovery_codes
    return [] if recovery_codes.blank?
    JSON.parse(recovery_codes)
  rescue JSON::ParserError => e
    Rails.logger.warn "⚠️ [User##{id}] Malformed recovery_codes JSON: #{e.message}"
    []
  end
end
