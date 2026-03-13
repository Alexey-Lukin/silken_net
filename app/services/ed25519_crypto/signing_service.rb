# frozen_string_literal: true

require "ed25519"

module Ed25519Crypto
  # =========================================================================
  # 🔐 ED25519 SIGNING SERVICE (Криптографічний модуль для non-EVM мереж)
  # =========================================================================
  # Надає Ed25519-криптографію для підпису транзакцій у мережах, що не використовують
  # secp256k1 (EVM). Гем `eth` покриває лише EVM-мережі (Polygon, Ethereum),
  # тоді як Solana та peaq (Substrate) потребують Ed25519.
  #
  # Використання:
  #   # Генерація нової пари ключів
  #   keypair = Ed25519Crypto::SigningService.generate_keypair
  #
  #   # Підпис повідомлення
  #   signature = Ed25519Crypto::SigningService.sign(seed_hex, message)
  #
  #   # Верифікація підпису
  #   valid = Ed25519Crypto::SigningService.verify(public_key_hex, signature_hex, message)
  #
  # Мережі:
  #   - Solana: підпис транзакцій мікро-винагород (USDC SPL Token Transfer)
  #   - peaq: підпис DID-документів для Machine Identity Passport
  # =========================================================================
  class SigningService
    SEED_BYTES = 32
    PUBLIC_KEY_BYTES = 32
    SIGNATURE_BYTES = 64

    class SigningError < StandardError; end

    # Генерує нову пару Ed25519-ключів.
    # Повертає Hash з :seed_hex (приватний ключ) та :public_key_hex.
    def self.generate_keypair
      signing_key = ::Ed25519::SigningKey.generate
      {
        seed_hex: signing_key.seed.unpack1("H*"),
        public_key_hex: signing_key.verify_key.to_bytes.unpack1("H*")
      }
    end

    # Відновлює Ed25519-ключ з hex-encoded seed (приватного ключа).
    # Повертає публічний ключ у hex-форматі.
    def self.public_key_from_seed(seed_hex)
      validate_hex!(seed_hex, SEED_BYTES, "seed")
      seed_bytes = [ seed_hex ].pack("H*")
      signing_key = ::Ed25519::SigningKey.new(seed_bytes)
      signing_key.verify_key.to_bytes.unpack1("H*")
    end

    # Підписує повідомлення Ed25519-ключем.
    # seed_hex — 32-байтний приватний ключ у hex-форматі.
    # message — рядок або бінарні дані для підпису.
    # Повертає 64-байтний підпис у hex-форматі.
    def self.sign(seed_hex, message)
      validate_hex!(seed_hex, SEED_BYTES, "seed")
      seed_bytes = [ seed_hex ].pack("H*")
      signing_key = ::Ed25519::SigningKey.new(seed_bytes)
      signature = signing_key.sign(message.to_s)
      signature.unpack1("H*")
    end

    # Верифікує Ed25519-підпис.
    # public_key_hex — 32-байтний публічний ключ у hex-форматі.
    # signature_hex — 64-байтний підпис у hex-форматі.
    # message — оригінальне повідомлення.
    # Повертає true/false.
    def self.verify(public_key_hex, signature_hex, message)
      validate_hex!(public_key_hex, PUBLIC_KEY_BYTES, "public_key")
      validate_hex!(signature_hex, SIGNATURE_BYTES, "signature")

      public_key_bytes = [ public_key_hex ].pack("H*")
      signature_bytes = [ signature_hex ].pack("H*")

      verify_key = ::Ed25519::VerifyKey.new(public_key_bytes)
      verify_key.verify(signature_bytes, message.to_s)
      true
    rescue ::Ed25519::VerifyError
      false
    end

    # Валідація hex-рядка на коректність формату та довжину.
    def self.validate_hex!(hex_string, expected_bytes, field_name)
      raise SigningError, "#{field_name} is required" if hex_string.nil? || hex_string.empty?
      unless hex_string.match?(/\A[0-9a-fA-F]+\z/)
        raise SigningError, "#{field_name} must be a valid hex string"
      end
      unless hex_string.length == expected_bytes * 2
        raise SigningError, "#{field_name} must be exactly #{expected_bytes} bytes (#{expected_bytes * 2} hex characters)"
      end
    end
    private_class_method :validate_hex!
  end
end
