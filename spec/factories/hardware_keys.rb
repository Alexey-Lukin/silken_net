# frozen_string_literal: true

FactoryBot.define do
  factory :hardware_key do
    sequence(:device_uid, 900_000) { |n| "SNET-%08X" % n }
    # Post-ARCH.42: default — Gateway shape (32 bytes / 64 hex / AES-256 CoAP),
    # бо більшість legacy specs створюють :hardware_key без owner-traits. Trait :for_tree
    # перепакує до 16 bytes / 32 hex / AES-128 LoRa (вибір ARCH.42; SE = SE050 — 03_05 §3.7).
    aes_key_hex { SecureRandom.hex(32).upcase }
    # [SEC.11] K_seed is required by the model. Random hex is fine for
    # factory-built records — specs that need an HKDF-derived value
    # call SilkenNet::SeedDerivation.derive_seed directly.
    lorenz_seed_hex { SecureRandom.hex(32).upcase }
    previous_aes_key_hex { nil }

    trait :for_tree do
      association :tree, factory: :tree, strategy: :create
      device_uid { tree.did }
      # ARCH.42 Variant B — Tree LoRa channel is AES-128 (16 bytes).
      aes_key_hex { SecureRandom.hex(16).upcase }
    end

    trait :for_gateway do
      association :gateway, factory: :gateway, strategy: :create
      device_uid { gateway.uid }
      # Gateway CoAP channel залишається AES-256 (32 bytes) після ARCH.42.
      aes_key_hex { SecureRandom.hex(32).upcase }
    end

    trait :with_grace_period do
      # Same byte-length as the parent record (Tree=16 / Gateway=32). Default до 32 bytes,
      # бо :hardware_key default — Gateway shape; коли поєднано з :for_tree, цей trait
      # викликається ПІСЛЯ для тих самих atts, тому довжина буде узгоджена кастомним
      # `aes_key_length_matches_owner_type` валідатором.
      previous_aes_key_hex { SecureRandom.hex(aes_key_hex.length / 2).upcase }
    end
  end
end
