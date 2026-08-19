# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class User < ApplicationRecord
  # --- АВТЕНТИФІКАЦІЯ (Argon2id — OWASP Recommended) ---
  # Argon2id замість bcrypt: memory-hard хешування, стійке до GPU/ASIC атак.
  # Інтерфейс сумісний з has_secure_password (password=, authenticate, password_salt).
  include HasArgon2Password

  # [S6.21] TOTP-секрет — at-rest ключ, той самий клас, що `hardware_keys.aes_key_hex`
  # (AR-encryption з ENV, SEC.22; boot-guard fail-closed без ключів).
  encrypts :otp_secret

  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  belongs_to :organization, optional: true

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до фінансової мережі підлеглих дерев
  has_many :wallets, through: :organization
  has_many :maintenance_records, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :restrict_with_error

  # [ARCH.57] Зміна ролі = привілейований RBAC-акт → audit-ланцюг. Хук на моделі
  # ловить УСІ шляхи запису (role-контролера сьогодні не існує — console-only).
  include Auditable
  after_update_commit :record_role_change_audit, if: :saved_change_to_role?

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

  # [I18N.1] Людська назва РОЛІ — дзеркало `Actuator::DEVICE_TYPE_LABEL_SCOPE`.
  # Скоуп належить домену МОДЕЛІ, не компоненту, який показав значення першим
  # (`04_04 §12.14`). ⚠️ Роль рендериться на кількох поверхнях, і одна з них —
  # сайдбар, тобто напис видно на КОЖНІЙ сторінці дашборда; доти всі вони
  # друкували англійський технічний токен у локалізованому інтерфейсі.
  # 🔴 Лічильник звідси ЗНЯТО: він казав «на ЧОТИРЬОХ», був правдивий у мить
  # написання — і саме тому пропустив пʼяту й шосту поверхні (`maintenance/show`
  # друкував `role.to_s.upcase` поруч із ПЕРЕКЛАДЕНОЮ міткою, водяний знак
  # `users/profile` — сирий токен). Периметр міряй властивістю «хто рендерить
  # атрибут», не числом; носій — `spec/quality/enum_label_call_site_spec.rb`.
  ROLE_LABEL_SCOPE = "users.roles"

  # ОДНА деривація ключа на застосунок. Fail-open: новий член enum'а рендериться
  # сирим значенням, доки мітка не доїде в локалі (гейт парності це червонить).
  def self.role_label(role)
    value = role.to_s
    I18n.t("#{ROLE_LABEL_SCOPE}.#{value}", default: value)
  end

  def role_label
    self.class.role_label(role)
  end

  # --- Series C (Privacy & Localization) ---
  # [I18N.1/I18N.3] Persisted мовна вподоба — джерело для ОБОХ контурів.
  # (а) пошта з Sidekiq, де ані cookie, ані сесії немає (`in_locale_of`);
  # (б) веб — третій щабель `LocaleSettable`, тобто те, що переживає зміну
  #     пристрою й чистку cookie. ⚠️ Пункт (б) дописано 2026-08-15: доти цей
  #     рядок казав «для НЕ-веб-контекстів», і то було не описом, а МЕЖЕЮ —
  #     колонку читала сама лише пошта, тож людина з обраною мовою бачила
  #     англійський сайт і діставала латиський лист.
  # `nil` = «не обрано» → базова локаль (саме тому
  # НЕ `presence: true`: дефолт-значення брехало б, що користувач зробив вибір).
  # Перелік деривується з єдиного дому — `config.i18n.available_locales`.
  #
  # ⚠️ Тут стояв TODO «додати поле locale колись» з власним списком `%w[uk en es]`,
  # у якому не було ні `lv`, ні `lt`, зате був `es`, якого нема в каталозі. Такий
  # коментар не просто застаріває — він **суперечить** конфігу й пережив би ще
  # кілька мов. Timezone справді лишається невзятим.
  validates :locale, inclusion: { in: ->(_user) { I18n.available_locales.map(&:to_s) } }, allow_nil: true

  # --- СКОУПИ ---
  scope :active_foresters, -> { role_forester.where("last_seen_at >= ?", 1.hour.ago) }
  scope :mfa_enabled, -> { where(otp_required_for_login: true) }

  # --- ТОКЕНИ (The Magic of Rails 8) ---
  # [I18N.1] Константа, бо це число видно КОРИСТУВАЧЕВІ: лист про скидання пароля
  # називає термін дії словами. Поки воно жило літералом у двох місцях, текст і
  # реальний TTL могли розійтись мовчки — тепер лист інтерполює це саме значення.
  PASSWORD_RESET_TTL = 15.minutes

  generates_token_for :password_reset, expires_in: PASSWORD_RESET_TTL do
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

  # [SEC.16] МАШИННИЙ токен — окремий purpose, і це несуче, а не косметика.
  #
  # `m2m_auth#create` видає його шлюзові, який довів володіння Ed25519-ключем.
  # Доти шлюз діставав `:api_access` першого org-admin'а, тобто **нерозрізнимий
  # від людського** admin-Bearer: компрометована польова Королева = повний
  # admin-API організації (2-га ланка cross-tenant-takeover з аудиту §04).
  #
  # Purpose ізолює криптографічно (перевірено рантаймом: токен одного purpose не
  # резолвиться іншим), тож `authenticate_user!` тепер ЗНАЄ, машина перед ним чи
  # людина, і `BaseController` тримає allowlist машинних екшенів.
  #
  # ⚠️ Прив'язка до `password_salt` СВІДОМО збережена: зміна пароля адміна гасить
  # і машинні токени його організації. Це не операційна проблема, а штатний
  # шлях — шлюз має Ed25519 і просто перевидає токен (крок 5 потоку `m2m_auth`);
  # натомість втрата цієї прив'язки лишила б флот без будь-якого відкликання
  # до кінця 30-денного TTL.
  generates_token_for :m2m_access, expires_in: 30.days do
    password_salt&.last(10)
  end

  # --- SESSION SALT-STAMP [SEC.16] ---
  #
  # Хвіст `password_salt`, яким cookie-сесія прив'язується до чинного пароля:
  # зміна пароля рухає сіль → украдений cookie гасне, не чекаючи своїх 14 днів.
  #
  # 🔴 **Дім тут — на МОДЕЛІ — обраний периметром, а не смаком: звіряльників
  # ЧОТИРИ, і спільного предка в них немає за побудовою** — `BaseController`,
  # `LocalesController` (успадковує сестру `ApplicationController`),
  # `ApplicationCable::Connection` (ActionCable, не ActionController) і
  # route-constraint `/sidekiq` у `config/routes.rb`. Єдине, що бачать усі
  # чотири, — сам `User`.
  #
  # ⚠️ **`&.` тут НЕ оборонний рефлекс, а дискримінатор.** Попередня форма
  # `password_salt.to_s.last(10)` для користувача без `password_digest` давала
  # `""`, і порожній стемп сесії згортався в `""` теж — тобто перевірка
  # ставала **істинною**, fail-OPEN, синхронно в усіх чотирьох місцях. Сьогодні
  # недосяжно (сесія вимагає логіну паролем), але це форма, що чекає свого
  # тригера: перший passwordless/OAuth-шлях, який не проставить пароля, зробить
  # її дірою МОВЧКИ. Тому предикат вимагає непорожнього очікуваного значення
  # ЯВНО, а не покладається на те, що порожнеча недосяжна.
  SESSION_STAMP_LENGTH = 10

  def session_salt_stamp
    password_salt&.last(SESSION_STAMP_LENGTH)
  end

  def session_salt_matches?(stamp)
    expected = session_salt_stamp
    expected.present? && stamp.to_s == expected
  end

  # --- МЕТОДИ ---

  def forest_commander?
    role_admin? || role_forester? || role_super_admin?
  end

  # --- RBAC: Розподіл повноважень (Series D) ---
  # Рівень ПОВНОВАЖЕНЬ ролі. Це НЕ скоуп даних.
  # :system  — платформені дії (super_admin): перемкнути контекст організації,
  #            редагувати глобальні довідники, читати системний аудит-ланцюг
  # :organization — повний набір дій у межах організації (admin)
  # :field — польові дії (forester)
  # :read_only — лише перегляд (investor)
  #
  # ⚠️ [SEC.25 Ф2] `:system` більше НЕ означає «бачить дані всіх організацій».
  # Скоуп даних відв'язаний від ролі й дається acting-організацією
  # (`BaseController#acting_organization`): super_admin працює в контексті ОДНІЄЇ
  # організації за раз і бачить рівно її, як і всі решта.
  #
  # 🔴 Розщеплювати цей метод на «здатність ⊥ скоуп» (як пропонував план) НЕ стали:
  # продових викликів у нього нуль — лише спеки й доки, — тож розщеплення додало б
  # абстракцію під нульовий попит. Знести теж не стали: на нього спирається
  # `docs/protocols/legal/securities_review.md` (аргумент про пасивність ролі
  # investor), і посилання має лишитись розв'язним. Тож лишається як опис
  # ПОВНОВАЖЕНЬ — і ця нота є єдиним, що змінилось, бо змінилось саме значення.
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

  # Дім формули «admin і вище». Її дзеркалили `authorize_admin!` і два приватні
  # предикати `ApplicationPolicy`, а роле-фільтр сайдбара [UI.5] став би четвертою
  # копією — і саме розходження меню з гардом він мусить робити неможливим.
  # ⚠️ НЕ плутати з `organization_admin?`: там `role_admin? && organization_id`,
  # тобто super_admin під неї не підпадає.
  def admin_or_above?
    role_admin? || role_super_admin?
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

  # [S6.21] Видає СВІЖИЙ секрет на кожен виклик setup-флоу до активації —
  # тобто кинутий напівшлях не лишає «мертвого» секрета, який хтось міг
  # підглянути. На вже активованому MFA не викликається (гард у контролері).
  def provision_otp_secret!
    update!(otp_secret: ROTP::Base32.random)
  end

  # otpauth:// URI для authenticator-застосунку (QR або ручне введення).
  def otp_provisioning_uri
    return nil if otp_secret.blank?

    ROTP::TOTP.new(otp_secret, issuer: "SilkenNet").provisioning_uri(email_address)
  end

  # [S6.21] Перевірка TOTP-коду з анти-replay: `after:` відкидає повтор того
  # самого (перехопленого) коду всередині 30-с вікна — успіх персистить мітку.
  # ±1 крок дрейфу (drift 30 с) — годинник телефона не зобовʼязаний збігатись
  # із серверним до секунди.
  def verify_totp!(code)
    return false if otp_secret.blank?

    timestep = ROTP::TOTP.new(otp_secret).verify(
      code.to_s.gsub(/\s+/, ""),
      drift_behind: 30, drift_ahead: 30,
      after: otp_last_used_at&.to_i
    )
    return false unless timestep

    update!(otp_last_used_at: Time.zone.at(timestep))
    true
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

  # [ARCH.57] Актор = система (oracle_executioner): ІНІЦІАТОРА на model-рівні не
  # видно, суб'єкт зміни = auditable. ⚠️ Тут доти стояло «Current-патерн не
  # заведено — YAGNI до першого role-UI»; перемикач організації [SEC.25 Ф2] і був
  # тим role-UI, тож `Current` тепер існує — і `Auditable#with_acting_context`
  # ним користується, домішуючи acting-контекст у метадані КОЖНОГО сліду, цього
  # зокрема. Актором він при цьому не стає: `Current` — діагностична мітка, а не
  # джерело авторства (`04_01 §5`).
  def record_role_change_audit
    from, to = saved_change_to_role
    record_audit_trail!(
      action: "user_role_changed",
      organization_id: organization_id,
      metadata: { from: from.to_s, to: to.to_s }
    )
  end

  # [ВИПРАВЛЕНО]: Тепер ця логіка реально керує валідацією.
  # Пароль не потрібен, якщо користувач прийшов через OAuth (`Identity::SUPPORTED_PROVIDERS`) і вже має Identity.
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
