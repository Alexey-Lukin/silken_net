# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # [SEC.11] Lorenz K_seed — same shielding as the AES key. Optional only
  # because pre-SEC.11 records were provisioned without it. ⚠️ There is no
  # migration endpoint and there will not be one: `upgrade_seed` was an
  # explicit won't-do in SEC.11 (a seed lives in flash behind RDP — it is
  # re-provisioned at the bench, not back-filled over HTTP). The comment that
  # promised it survived here for months and got its path rewritten by the
  # [ARCH.77] sweep, which is how a fiction ends up looking freshly maintained.
  encrypts :lorenz_seed_hex

  # ---------------------------------------------------------------------------
  # SCALABILITY: Zero Cryptographic Jitter — усунення «Double Crypto Tax»
  # ---------------------------------------------------------------------------
  # [A-7 FIX]: Decrypted binary keys are cached in process-local RAM
  # (SinLruRedux::ThreadSafeCache) instead of Redis. This eliminates the risk
  # of mass key leakage if a Redis instance is compromised. Keys never leave
  # the Ruby process and vanish on restart/crash.
  #
  # [RACE CONDITION FIX]: Cache key now includes updated_at version stamp
  # (Cache Key Versioning pattern). After any update, updated_at changes →
  # new cache key → stale entry never matches → no race window between
  # UPDATE commit and after_commit callback. Old entries are naturally
  # evicted by LRU policy (max 10,000 keys). No after_commit needed.
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
  normalize_identifier :device_uid

  # --- ВАЛІДАЦІЇ ---
  validates :device_uid, presence: true, uniqueness: true

  # Post-ARCH.42 (2026-05-23, Variant B): aes_key_hex має conditional length за owner type.
  #   • Tree (Soldier LoRa channel) → 32 HEX chars (AES-128, 16 bytes) — вибір ARCH.42, не SE-constraint (SE = SE050 — 03_05 §3.7).
  #   • Gateway (Queen CoAP-to-Rails channel) → 64 HEX chars (AES-256, 32 bytes).
  # Format gate тільки на HEX-чарах; custom validator enforce довжину {32, 64} + owner-узгодженість.
  validates :aes_key_hex, presence: true,
                          format: { with: /\A[0-9A-F]+\z/i }
  validate  :aes_key_length_in_allowed_set
  validate  :aes_key_length_matches_owner_type

  # Попередній ключ: може бути порожнім, якщо ротації ще не було.
  # Та сама довжина, що і поточний (rotation у межах тієї самої device-type).
  validates :previous_aes_key_hex, format: { with: /\A[0-9A-F]+\z/i },
                                   allow_nil: true
  validate  :previous_aes_key_length_in_allowed_set

  # [FW.17] Hash-Ratchet версія LoRa-ключа (Tree-пристрої). 0 = заводський K0;
  # інкрементується ратчет-ротацією (HardwareKeyService); firmware-дзеркало
  # живе у Flash-KV 0x13. Стеля 0xFFFF — версія їде по дроту як u16 (0x9E).
  validates :key_version, presence: true,
                          numericality: { only_integer: true,
                                          greater_than_or_equal_to: 0,
                                          less_than_or_equal_to: 0xFFFF }

  # Ed25519 public key для M2M автентифікації (64 hex chars = 32 bytes)
  validates :ed25519_public_key_hex, length: { is: 64 },
                                     format: { with: /\A[0-9a-fA-F]+\z/ },
                                     allow_nil: true

  # [SEC.11] K_seed: 64 HEX chars (32 bytes). Required — every device
  # gets one at provisioning (HardwareKeyService.provision derives both
  # AES key and K_seed in a single call). No field-migration window:
  # this is a pre-production hard cutover.
  validates :lorenz_seed_hex, presence: true,
                              length: { is: 64 },
                              format: { with: /\A[0-9A-F]+\z/i }

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # КРИПТОГРАФІЧНІ МЕТОДИ
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Повертає сирі байти поточного ключа. Без ivar memoization — інакше
  # `update!(aes_key_hex: ...)` мовчки повертатиме stale байти, поки інстанс
  # не перезавантажиться. `pack("H*")` для 64 hex chars займає ~1µs, тож
  # перерахунок per-call безпечний; hot path йде через `cached_binary_key`.
  def binary_key
    [ aes_key_hex ].pack("H*")
  end

  # [A-7 FIX]: In-process LRU cache replaces Rails.cache (Redis).
  # Keys stay in worker RAM — never serialized to network storage.
  # [RACE CONDITION FIX]: Cache key includes updated_at version — self-invalidating
  # on any update. Eliminates the need for after_commit cache invalidation callbacks
  # and the race window between commit and callback execution.
  def cached_binary_key
    HARDWARE_KEY_CACHE.getset(versioned_cache_key) { binary_key }
  end

  # Повертає сирі байти попереднього ключа (для Grace Period).
  # Без ivar memoization (див. binary_key).
  def binary_previous_key
    return nil if previous_aes_key_hex.blank?
    [ previous_aes_key_hex ].pack("H*")
  end

  # [SEC.11] Raw 32 bytes of K_seed for SilkenNet::SeedDerivation.
  # Always present in steady state — `lorenz_seed_hex` is required. Nil
  # only on unsaved records that have not yet been provisioned.
  # Без ivar memoization (див. binary_key).
  def binary_lorenz_seed
    return nil if lorenz_seed_hex.blank?
    [ lorenz_seed_hex ].pack("H*")
  end

  # [DEPRECATED]: Use HardwareKeyService.rotate(device_uid) instead.
  # Service version includes downlink notification to the device.
  # This model method is kept for backward compatibility but logs a deprecation warning.
  # Post-ARCH.42: rotate produces a key of the same length as the current one
  # (16 bytes for Tree LoRa AES-128, 32 bytes for Gateway CoAP AES-256).
  def rotate_key!
    Rails.logger.warn "⚠️ [Deprecation] HardwareKey#rotate_key! called for #{device_uid}. " \
                      "Use HardwareKeyService.rotate(device_uid) for full rotation with downlink."

    # Match the existing key byte-length (Tree: 16 bytes / Gateway: 32 bytes)
    byte_len = aes_key_hex.length / 2
    new_key_hex = SecureRandom.hex(byte_len).upcase

    update!(
      previous_aes_key_hex: aes_key_hex,
      aes_key_hex: new_key_hex,
      rotated_at: Time.current
    )

    binary_key
  end

  # Метод для зачистки "хвостів" після успішної синхронізації.
  def clear_grace_period!
    return if previous_aes_key_hex.blank?

    update_columns(previous_aes_key_hex: nil)
    Rails.logger.info "✅ [KeyRotation] Синхронізація для #{device_uid} підтверджена. Резервний ключ видалено."
  end

  # Повертає фактичного власника ключа (Дерево або Шлюз)
  def owner
    tree || gateway
  end

  private

  # Versioned cache key: includes updated_at to auto-invalidate on any change.
  # After rotate_key! or update!, updated_at changes → new cache key →
  # stale binary key is never served from cache.
  def versioned_cache_key
    "#{device_uid}:v:#{updated_at.to_f}"
  end

  ALLOWED_AES_HEX_LENGTHS = [ 32, 64 ].freeze
  private_constant :ALLOWED_AES_HEX_LENGTHS

  # Post-ARCH.42 (2026-05-23): дозволені довжини aes_key_hex — рівно 32 або 64 hex chars.
  # 32 hex = 16 bytes = AES-128 (Tree LoRa); 64 hex = 32 bytes = AES-256 (Gateway CoAP).
  def aes_key_length_in_allowed_set
    return if aes_key_hex.blank?
    return if ALLOWED_AES_HEX_LENGTHS.include?(aes_key_hex.length)

    errors.add(
      :aes_key_hex,
      "must be 32 hex chars (AES-128 LoRa) or 64 hex chars (AES-256 CoAP), got #{aes_key_hex.length} [ARCH.42]"
    )
  end

  def previous_aes_key_length_in_allowed_set
    return if previous_aes_key_hex.blank?
    return if ALLOWED_AES_HEX_LENGTHS.include?(previous_aes_key_hex.length)

    errors.add(
      :previous_aes_key_hex,
      "must be 32 hex chars (AES-128 LoRa) or 64 hex chars (AES-256 CoAP), got #{previous_aes_key_hex.length} [ARCH.42]"
    )
  end

  # Post-ARCH.42 (2026-05-23): enforce aes_key_hex довжина узгоджена з owner type.
  # Tree (Soldier LoRa) → 32 hex (AES-128); Gateway (Queen CoAP) → 64 hex (AES-256).
  # Skip перевірку, якщо owner ще не визначений (наприклад, build без associations) —
  # довжина перевіряється `aes_key_length_in_allowed_set` валідатором незалежно.
  def aes_key_length_matches_owner_type
    return if aes_key_hex.blank?

    # Associations attach via device_uid → tree.did / gateway.uid (not via FK columns).
    # Use the in-memory association if it was set on the record (factory-style),
    # otherwise fall back to a Tree / Gateway lookup by device_uid.
    owner_kind = detect_owner_kind
    return if owner_kind.nil?

    expected = owner_kind == :tree ? 32 : 64
    return if aes_key_hex.length == expected

    actual_bits   = aes_key_hex.length * 4
    expected_bits = expected * 4
    owner_label   = owner_kind == :tree ? "Tree (LoRa AES-128)" : "Gateway (CoAP AES-256)"
    errors.add(
      :aes_key_hex,
      "must be #{expected} hex chars (#{expected_bits} bits) for #{owner_label}, got #{aes_key_hex.length} hex (#{actual_bits} bits) [ARCH.42]"
    )
  end

  def detect_owner_kind
    return :tree    if association(:tree).loaded? && association(:tree).target.present?
    return :gateway if association(:gateway).loaded? && association(:gateway).target.present?
    return :tree    if device_uid.present? && Tree.exists?(did: device_uid)
    return :gateway if device_uid.present? && Gateway.exists?(uid: device_uid)
    nil
  end
end
