# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Identity < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Authentication Anchor) ---
  belongs_to :user

  # --- БЕЗПЕКА (ActiveRecord Encryption) — OAuth-секрети at rest [SEC.22 / ARCH.57(4)] ---
  # Non-deterministic (дефолт): жодну з цих колонок не шукають за значенням — Identity
  # дістають лише за (provider, uid), тож deterministic_key тут не потрібен, а однакові
  # токени/профілі не колапсують у той самий шифротекст. auth_data — text-колонка (див.
  # міграцію) з JSON-coder, щоб Ruby-Hash round-trip'ив; serialize ОГОЛОШЕНО ПЕРЕД encrypts,
  # аби шифрування огорнуло вже JSON-кодований тип. Ключі — з ENV (production.rb, SEC.22).
  serialize :auth_data, coder: JSON
  encrypts :access_token
  encrypts :refresh_token
  encrypts :auth_data

  # ⚡ [СИНХРОНІЗАЦІЯ]: Прямий доступ до контексту через користувача
  # Це дозволяє робити виклики на кшталт identity.organization або identity.wallets
  delegate :organization, :role, to: :user, allow_nil: true
  delegate :wallets, to: :organization, allow_nil: true

  # --- ВАЛІДАЦІЇ ---
  # provider: "google_oauth2", "apple", "linkedin", "facebook", "twitter" тощо
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider, message: "Цей акаунт вже прив'язаний до іншого користувача." }

  # --- СКОУПИ ---
  scope :by_provider, ->(p) { where(provider: p) }
  scope :active, -> { where(locked_at: nil) }
  scope :locked, -> { where.not(locked_at: nil) }
  scope :primary_identity, -> { where(primary: true) }

  # --- ПІДТРИМУВАНІ ПРОВАЙДЕРИ ---
  SUPPORTED_PROVIDERS = %w[google_oauth2 facebook linkedin twitter].freeze

  # [I18N.1] Назви провайдерів — ВЛАСНІ, тобто locale-INVARIANT: «LinkedIn»
  # українською лишається «LinkedIn». Тому фрозен-мапа, а не YAML — той самий клас,
  # що тікер і назви мереж, і той самий аргумент: чотири копії одного слова в
  # локалях плюс обовʼязок їх синхронізувати.
  #
  # 🔴 Але дефект тут БУВ, просто не той, який шукали: `.titleize` (стояв на трьох
  # сайтах) бреше на ДВОХ значеннях із чотирьох — `google_oauth2` → «Google Oauth2»,
  # `linkedin` → «Linkedin». Тобто це дефект ПОКАЗУ, і локалізація його не лікує.
  # ⚠️ Fallback лишається `titleize` навмисно: новий провайдер має рендеритись
  # прийнятно ще до того, як хтось допише йому канонічне написання.
  PROVIDER_NAMES = {
    "google_oauth2" => "Google",
    "facebook"      => "Facebook",
    "linkedin"      => "LinkedIn",
    "twitter"       => "Twitter"
  }.freeze

  def self.provider_name(provider)
    PROVIDER_NAMES.fetch(provider.to_s) { provider.to_s.titleize }
  end

  def provider_name = self.class.provider_name(provider)

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # OMNIAUTH ІНТЕГРАЦІЯ (The Gateway Processor)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # [ВИПРАВЛЕНО]: Тепер метод приймає user як аргумент. Це запобігає
  # ActiveRecord::RecordInvalid (User must exist) при створенні нової ідентичності.
  def self.find_or_create_from_auth_hash(auth_hash, user: nil)
    identity = find_or_initialize_by(provider: auth_hash.provider, uid: auth_hash.uid)

    # Прив'язуємо користувача, якщо це новий запис.
    # Це закриває "дірку", через яку save! вибухав помилкою валідації.
    identity.user = user if identity.new_record? && user.present?

    # Якщо ідентичність заблокована — не оновлюємо та повертаємо як є
    return identity if identity.locked?

    # Завжди оновлюємо токени доступу, оскільки вони мають властивість "протухати"
    if auth_hash.credentials.present?
      identity.assign_attributes(
        access_token: auth_hash.credentials.token,
        refresh_token: auth_hash.credentials.refresh_token,
        # Зберігаємо повний зліпок профілю для безпекового аудиту та майбутніх потреб AI
        auth_data: auth_hash.to_h
      )

      # [ВИПРАВЛЕНО]: Додано .to_i для гарантії валідності Unix Timestamp.
      # Це захищає нас від "типового" хаосу, якщо провайдер надішле String замість Integer.
      if auth_hash.credentials.expires_at.present?
        identity.expires_at = Time.zone.at(auth_hash.credentials.expires_at.to_i)
      end
    end

    # Якщо це перша ідентичність користувача — робимо її первинною
    identity.primary = true if identity.new_record? && user.present? && user.identities.none?

    identity.save!
    identity
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # ЖИТТЄВИЙ ЦИКЛ ТОКЕНА
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перевірка надійності ключа. Якщо час вийшов — потребує повторної синхронізації.
  def token_expired?
    expires_at.present? && expires_at < Time.current
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # БЛОКУВАННЯ ІДЕНТИЧНОСТІ (Account Takeover Protection)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Перевірка чи ідентичність заблокована
  def locked?
    locked_at.present?
  end

  # Блокування ідентичності (напр. якщо Google-акаунт зламано)
  def lock!
    update!(locked_at: Time.current)
  end

  # Розблокування ідентичності
  def unlock!
    update!(locked_at: nil)
  end

  # Встановити як первинний метод входу.
  # Використовуємо update_all для масового оновлення без колбеків —
  # це єдиний атомарний спосіб гарантувати, що рівно одна ідентичність є primary.
  def make_primary!
    transaction do
      user.identities.where.not(id: id).update_all(primary: false)
      update!(primary: true)
    end
  end
end
