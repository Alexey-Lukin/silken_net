# frozen_string_literal: true

class HardwareKey < ApplicationRecord
  include NormalizeIdentifier
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # БЕЗПЕКА ДАНИХ (ActiveRecord Encryption)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Шифруємо обидва ключі. Non-deterministic шифрування гарантує, що навіть
  # два однакові ключі в базі виглядатимуть по-різному.
  encrypts :aes_key_hex
  encrypts :previous_aes_key_hex

  # ---------------------------------------------------------------------------
  # SCALABILITY: Zero Cryptographic Jitter — усунення «Double Crypto Tax»
  # ---------------------------------------------------------------------------
  # При мільйонах запитів на розшифровку (decryption) десеріалізація зашифрованих
  # ключів ActiveRecord Encryption створює навантаження на CPU (~2 мс/виклик).
  # Розшифрований binary_key кешується в Rails.cache (Redis у prod) з TTL 15 хв.
  # Це усуває повторну AR Encryption десеріалізацію для кожного пакету телеметрії.
  # Безпека: ключі в PostgreSQL залишаються зашифрованими (AR Encryption).
  # Redis на проді має бути в ізольованій мережі (Private VPC) з TLS + ACL.
  # Інвалідація: after_commit на update/destroy + rotate_key! автоматично.
  # ---------------------------------------------------------------------------

  # Інвалідація кешу при будь-якій зміні або видаленні ключа
  after_commit :clear_key_cache, on: %i[update destroy]

  # --- ЗВ'ЯЗКИ ---
  # Зв'язок із Солдатом (Tree) через DID
  belongs_to :tree, foreign_key: :device_uid, primary_key: :did, optional: true

  # [ВИПРАВЛЕНО: Забута Королева]: Повертаємо ієрархічний зв'язок із Шлюзом
  belongs_to :gateway, foreign_key: :device_uid, primary_key: :uid, optional: true

  # ⚡ [СИНХРОНІЗАЦІЯ]: Висхідна навігація до ієрархії влади
  # Тепер ми можемо дістати контекст незалежно від того, хто власник ключа
  delegate :organization, :cluster, to: :owner, allow_nil: true

  # --- НОРМАЛІЗАЦІЯ ---
  normalize_identifier :device_uid

  # --- ВАЛІДАЦІЇ ---
  validates :device_uid, presence: true, uniqueness: true

  # Основний ключ: строго 64 HEX символи (AES-256)
  validates :aes_key_hex, presence: true, length: { is: 64 },
                          format: { with: /\A[0-9A-F]+\z/i }

  # Попередній ключ: може бути порожнім, якщо ротації ще не було
  validates :previous_aes_key_hex, length: { is: 64 },
                                   format: { with: /\A[0-9A-F]+\z/i },
                                   allow_nil: true

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # КРИПТОГРАФІЧНІ МЕТОДИ
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Повертає сирі байти поточного ключа
  def binary_key
    @binary_key ||= [ aes_key_hex ].pack("H*")
  end

  # Hot-path оптимізація: кешований binary_key через Rails.cache (Redis у prod).
  # Усуває «Double Crypto Tax» — AR Encryption десеріалізація відбувається лише
  # раз на 15 хв замість кожного пакету телеметрії.
  def cached_binary_key
    Rails.cache.fetch("hw_key:#{device_uid}:bin", expires_in: 15.minutes) { binary_key }
  end

  # Повертає сирі байти попереднього ключа (для Grace Period)
  def binary_previous_key
    return nil if previous_aes_key_hex.blank?
    @binary_previous_key ||= [ previous_aes_key_hex ].pack("H*")
  end

  # [СИНХРОНІЗОВАНО]: М'яка ротація ключа
  def rotate_key!
    new_key_hex = SecureRandom.hex(32).upcase

    # [ВИПРАВЛЕНО]: Прибрано зайвий transaction do, оскільки update!
    # вже обгорнутий у транзакцію на рівні ActiveRecord.
    update!(
      previous_aes_key_hex: aes_key_hex, # Стара істина стає резервною
      aes_key_hex: new_key_hex,          # Нова істина вступає в силу
      rotated_at: Time.current
    )

    # Скидаємо мемоізацію
    @binary_key = nil
    @binary_previous_key = nil

    Rails.logger.warn "🔄 [KeyRotation] Для #{device_uid} активовано Grace Period. Старий ключ збережено як резервний."
    binary_key
  end

  # Метод для зачистки "хвостів" після успішної синхронізації.
  def clear_grace_period!
    return if previous_aes_key_hex.blank?

    update_columns(previous_aes_key_hex: nil)
    @binary_previous_key = nil
    Rails.logger.info "✅ [KeyRotation] Синхронізація для #{device_uid} підтверджена. Резервний ключ видалено."
  end

  # Повертає фактичного власника ключа (Дерево або Шлюз)
  def owner
    tree || gateway
  end

  private

  # Інвалідація кешу — викликається через after_commit on: [:update, :destroy]
  def clear_key_cache
    Rails.cache.delete("hw_key:#{device_uid}:bin")
  end
end
