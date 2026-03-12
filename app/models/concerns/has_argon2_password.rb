# frozen_string_literal: true

require "argon2id"

# Замінює Rails `has_secure_password` на Argon2id — сучасний стандарт
# хешування паролів (переможець Password Hashing Competition, рекомендація OWASP).
# Стійкий до GPU/ASIC атак завдяки memory-hardness.
#
# Інтерфейс повністю сумісний з has_secure_password:
#   - password= / password_confirmation=
#   - authenticate(password)
#   - password_salt (для generates_token_for)
module HasArgon2Password
  extend ActiveSupport::Concern

  included do
    attr_reader :password
    attr_accessor :password_confirmation
  end

  def password=(unencrypted_password)
    if unencrypted_password.nil?
      @password = nil
      self.password_digest = nil
    elsif !unencrypted_password.empty?
      @password = unencrypted_password
      self.password_digest = Argon2id::Password.create(unencrypted_password).to_s
    end
  end

  def authenticate(unencrypted_password)
    return false unless password_digest.present?

    Argon2id::Password.new(password_digest).is_password?(unencrypted_password) && self
  end

  alias_method :authenticate_password, :authenticate

  def password_salt
    return nil unless password_digest?

    Argon2id::Password.new(password_digest).salt.unpack1("H*")
  end
end
