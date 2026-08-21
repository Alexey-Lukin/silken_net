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
  # provider ∈ `SUPPORTED_PROVIDERS` (нижче) — і перелік тут НЕ переказується
  # довільно: доти цей рядок називав `"apple"`, якого в константі немає, а
  # Privacy Policy (`docs/protocols/legal/b2c_tos_privacy.md`) написана за
  # РЕАЛЬНИМ списком. Тобто коментар обіцяв користувачеві провайдера, якого
  # застосунок не підтримує, і розходився з юридичним документом [ARCH.69].
  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider, message: "Цей акаунт вже прив'язаний до іншого користувача." }

  # --- СКОУПИ ---
  scope :by_provider, ->(p) { where(provider: p) }
  scope :active, -> { where(locked_at: nil) }
  scope :locked, -> { where.not(locked_at: nil) }
  scope :primary_identity, -> { where(primary: true) }

  # --- ПІДТРИМУВАНІ ПРОВАЙДЕРИ ---
  # ⚖️ **founder 2026-08-21: від Facebook / LinkedIn / Twitter відмовились
  # ЗОВСІМ — «нам не треба».** Це не «поки не дротуємо»: кожен провайдер коштує
  # окремого гема, окремої реєстрації застосунку і власного рядка в Privacy
  # Policy як НЕЗАЛЕЖНОГО контролера (`b2c_tos_privacy §B.5`), тобто ціна
  # тягнеться в юридичний шар, а не лише в Gemfile. Історичних записів у проді
  # немає за побудовою — OmniAuth не був задротований жодного дня ([ARCH.69]).
  #
  # 🔴 Ця константа — ДЖЕРЕЛО для Privacy Policy, а не її дзеркало: `b2c_tos_privacy`
  # прямо каже, що писана за реальним списком тут. Змінюючи її, оновлюй і §B.3/§B.5
  # того документа та `ropa_art30` — інакше юр-шар обіцяє третіх сторін, яких нема.
  SUPPORTED_PROVIDERS = %w[google_oauth2].freeze

  # [I18N.1] Назви провайдерів — ВЛАСНІ, тобто locale-INVARIANT: «Google»
  # українською лишається «Google». Тому фрозен-мапа, а не YAML — той самий клас,
  # що тікер і назви мереж, і той самий аргумент: копії одного слова в кожній
  # локалі плюс обовʼязок їх синхронізувати.
  #
  # 🔴 Дефект, заради якого мапа й зʼявилась, лишається чинним і на одному записі:
  # `.titleize` дає `google_oauth2` → «Google Oauth2». Тобто це дефект ПОКАЗУ, і
  # локалізація його не лікує. ⚠️ Мапа звузилась разом із `SUPPORTED_PROVIDERS`
  # (⚖️ 2026-08-21); історичного рядка з іншим провайдером у проді бути не може,
  # а якби він зʼявився — його прийме fallback нижче, як і будь-якого нового.
  # ⚠️ Fallback лишається `titleize` навмисно: новий провайдер має рендеритись
  # прийнятно ще до того, як хтось допише йому канонічне написання.
  PROVIDER_NAMES = {
    "google_oauth2" => "Google"
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
