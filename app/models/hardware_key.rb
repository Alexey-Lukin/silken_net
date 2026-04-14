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
  # [A-7 FIX]: Decrypted binary keys are cached in process-local RAM
  # (SinLruRedux::ThreadSafeCache) instead of Redis. This eliminates the risk
  # of mass key leakage if a Redis instance is compromised. Keys never leave
  # the Ruby process and vanish on restart/crash.
  # Previous implementation used Rails.cache (Redis) with TTL 15 min.
  # Now keys are cached in-process with LRU eviction (max 10,000 keys).
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

  # Ed25519 public key для M2M автентифікації (64 hex chars = 32 bytes)
  validates :ed25519_public_key_hex, length: { is: 64 },
                                     format: { with: /\A[0-9a-fA-F]+\z/ },
                                     allow_nil: true

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # КРИПТОГРАФІЧНІ МЕТОДИ
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Повертає сирі байти поточного ключа
  def binary_key
    @binary_key ||= [ aes_key_hex ].pack("H*")
  end

  # [A-7 FIX]: In-process LRU cache replaces Rails.cache (Redis).
  # Keys stay in worker RAM — never serialized to network storage.
  def cached_binary_key
    HARDWARE_KEY_CACHE.getset(device_uid) { binary_key }
  end

  # Повертає сирі байти попереднього ключа (для Grace Period)
  def binary_previous_key
    return nil if previous_aes_key_hex.blank?
    @binary_previous_key ||= [ previous_aes_key_hex ].pack("H*")
  end

  # [DEPRECATED]: Use HardwareKeyService.rotate!(device_uid) instead.
  # Service version includes downlink notification to the device.
  # This model method is kept for backward compatibility but logs a deprecation warning.
  def rotate_key!
    Rails.logger.warn "⚠️ [Deprecation] HardwareKey#rotate_key! called for #{device_uid}. " \
                      "Use HardwareKeyService.rotate(device_uid) for full rotation with downlink."

    new_key_hex = SecureRandom.hex(32).upcase

    update!(
      previous_aes_key_hex: aes_key_hex,
      aes_key_hex: new_key_hex,
      rotated_at: Time.current
    )

    # Скидаємо мемоізацію
    @binary_key = nil
    @binary_previous_key = nil

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

  # [A-7 FIX]: Invalidate in-process LRU cache (not Redis)
  def clear_key_cache
    HARDWARE_KEY_CACHE.delete(device_uid)
  end
end
