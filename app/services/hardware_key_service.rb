# frozen_string_literal: true

require "securerandom"
require "openssl"

class HardwareKeyService
  KEY_SIZE_BYTES = 32
  HKDF_INFO = "silken-aes-256-device-key"

  # Помилка подвійної ротації: пристрій ще не підтвердив попереднє оновлення ключа.
  class RotationPendingError < StandardError; end

  # =========================================================================
  # ПРОВІЗІОНУВАННЯ (Zero-Trust Key Derivation)
  # =========================================================================
  # [P0 BLOCKER FIX]: Замість генерації випадкового ключа та передачі через мережу,
  # використовуємо HKDF (HMAC-based Key Derivation Function) для деривації
  # однакового AES-256 ключа на обох сторонах (бекенд + прошивка).
  #
  # Обидві сторони знають:
  #   1. PROVISIONING_MASTER_KEY (встановлюється в env, прошивається при Factory Flashing)
  #   2. device_uid (унікальний серійник STM32)
  #
  # Формула: AES_KEY = HKDF-SHA256(ikm: master_key, salt: device_uid, info: "silken-aes-256-device-key")
  #
  # [SEC.11] Provisioning тепер також деривує Lorenz K_seed через
  # SilkenNet::SeedDerivation і зберігає його разом із AES ключем.
  # Метод повертає AES hex (для backwards-compat з існуючими callers);
  # K_seed читається з створеного `HardwareKey.lorenz_seed_hex`.
  #
  # Ключ НІКОЛИ не передається по мережі. Якщо PROVISIONING_MASTER_KEY не встановлено,
  # повертаємося до SecureRandom (TRL 4 lab mode) з попередженням у логах.
  def self.provision(device)
    device_uid = device.respond_to?(:did) ? device.did : device.uid
    new_hex_key = derive_device_key(device_uid)
    lorenz_seed = SilkenNet::SeedDerivation.derive_seed(device_uid)

    HardwareKey.create!(
      device_uid: device_uid,
      aes_key_hex: new_hex_key,
      lorenz_seed_hex: lorenz_seed
    )

    new_hex_key
  end

  # Деривація AES-256 ключа з master_key та device_uid через HKDF.
  # Повертає 64-символьний HEX-рядок (32 байти).
  #
  # [SEC.11] Always requires PROVISIONING_MASTER_KEY — there is no
  # SecureRandom fallback. Without master_key the backend would generate
  # values that do NOT match firmware HKDF derivation → silent system
  # breakage. Tests pin a stable value in spec/rails_helper.rb.
  def self.derive_device_key(device_uid)
    master_key = ENV["PROVISIONING_MASTER_KEY"]

    if master_key.blank?
      raise SecurityError,
            "PROVISIONING_MASTER_KEY ENV is required. Backend cannot derive " \
            "device AES key without it (would silently diverge from firmware " \
            "HKDF). See SEC.11 in docs/10_02_Action_Plan_Tracker.md."
    end

    derived = OpenSSL::KDF.hkdf(
      master_key,
      salt: device_uid.to_s,
      info: HKDF_INFO,
      length: KEY_SIZE_BYTES,
      hash: "SHA256"
    )

    derived.unpack1("H*").upcase
  end

  def self.rotate(device_uid)
    device = Tree.find_by(did: device_uid) || Gateway.find_by(uid: device_uid)
    raise "Пристрій #{device_uid} не знайдено" unless device

    new(device).rotate!
  end

  def initialize(device)
    @device = device
    @device_uid = device.respond_to?(:did) ? device.did : device.uid
  end

  # =========================================================================
  # РОТАЦІЯ (The Dual-Key Handshake)
  # =========================================================================
  def rotate!
    key_record = HardwareKey.find_by!(device_uid: @device_uid)

    # ⚡ [ЗАХИСТ ВІД ПОДВІЙНОЇ РОТАЦІЇ]: Якщо попередній ключ ще присутній,
    # це означає, що пристрій не підтвердив отримання нового ключа.
    # Повторна ротація затре old_key і ми назавжди втратимо доступ.
    if key_record.previous_aes_key_hex.present?
      raise RotationPendingError, "Ротація заблокована для #{@device_uid}: пристрій ще не підтвердив попередню ротацію. " \
            "Дочекайтесь першого пакету на новому ключі або очистіть Grace Period вручну."
    end

    # ⚡ [ЗАГАРТУВАННЯ]: Зберігаємо поточний ключ як попередній
    old_key = key_record.aes_key_hex
    new_hex_key = SecureRandom.hex(KEY_SIZE_BYTES).upcase

    # ⚡ [АТОМАРНІСТЬ]: Оновлення БД та постановка Downlink в чергу відбуваються
    # в одній транзакції. Якщо Redis/Sidekiq недоступний — транзакція відкочується,
    # і ключ у базі залишається незмінним.
    HardwareKey.transaction do
      key_record.update!(
        previous_aes_key_hex: old_key, # "Подушка безпеки"
        aes_key_hex: new_hex_key,
        rotated_at: Time.current
      )

      # Надсилаємо Downlink ВСЕРЕДИНІ транзакції.
      # ВАЖЛИВО: цей пакет має бути зашифрований OLD_KEY,
      # бо дерево ще не знає про NEW_KEY!
      trigger_key_update_downlink(new_hex_key, old_key)
    end

    Rails.logger.warn "🔄 [Zero-Trust] Ротація для #{@device_uid} активована. Старий ключ збережено як резервний."
    new_hex_key
  end

  private

  def trigger_key_update_downlink(new_key_hex, encryption_key)
    return unless @device.respond_to?(:ip_address) || @device.respond_to?(:gateway)
    target_ip = @device.respond_to?(:ip_address) ? @device.ip_address : @device.gateway.ip_address

    # Формуємо команду для STM32.
    # Воркер має використати 'encryption_key' для шифрування цієї команди.
    ActuatorCommandWorker.perform_async(
      @device_uid,
      "sys/key_update",
      { key: new_key_hex }.to_json,
      { use_key: encryption_key } # Передаємо конкретний ключ для цього завдання
    )
  end
end
