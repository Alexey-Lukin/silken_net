# frozen_string_literal: true

class HardwareKey < ApplicationRecord
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # БЕЗПЕКА ДАНИХ (ActiveRecord Encryption)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Шифруємо обидва ключі. Non-deterministic шифрування гарантує, що навіть
  # два однакові ключі в базі виглядатимуть по-різному.
  encrypts :aes_key_hex
  encrypts :previous_aes_key_hex

  # ---------------------------------------------------------------------------
  # SCALABILITY NOTE (Series D — High Concurrency Telemetry)
  # ---------------------------------------------------------------------------
  # При мільйонах запитів на розшифровку (decryption) десеріалізація зашифрованих
  # ключів ActiveRecord Encryption створить навантаження на CPU.
  # Рекомендується:
  # 1. Кешувати binary_key у захищеному Redis (з TTL 5-15 хв),
  #    щоб не дешифрувати їх із бази при кожному пакеті телеметрії.
  # 2. Ключ кешу: "hw_key:#{device_uid}:bin", значення: зашифровано на рівні Redis (TLS + ACL)
  # 3. Інвалідація: при rotate_key! видаляти кеш-запис негайно.
  # ---------------------------------------------------------------------------

  # --- ЗВ'ЯЗКИ ---
  # Зв'язок із Солдатом (Tree) через DID
  belongs_to :tree, foreign_key: :device_uid, primary_key: :did, optional: true

  # [ВИПРАВЛЕНО: Забута Королева]: Повертаємо ієрархічний зв'язок із Шлюзом
  belongs_to :gateway, foreign_key: :device_uid, primary_key: :uid, optional: true

  # ⚡ [СИНХРОНІЗАЦІЯ]: Висхідна навігація до ієрархії влади
  # Тепер ми можемо дістати контекст незалежно від того, хто власник ключа
  delegate :organization, :cluster, to: :owner, allow_nil: true

  # --- НОРМАЛІЗАЦІЯ ---
  normalizes :device_uid, with: ->(uid) { uid.to_s.strip.upcase }

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
end
