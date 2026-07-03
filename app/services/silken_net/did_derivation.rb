# frozen_string_literal: true

module SilkenNet
  # [FW.54 Вісь 2] DID = f(UID) — Ruby-дзеркало firmware
  # `firmware/soldier/did_derive.h` (murmur3-fmix32 ланцюгом по трьох словах
  # 96-бітного STM32-UID). Біт-у-біт ідентичне: golden-вектори заморожені
  # обабіч (test_soldier_logic.c ↔ did_derivation_spec.rb).
  #
  # Споживач — фабричний провіженінг (SEC.3): host читає UID по SWD ще ДО
  # прошивки, деривує той самий DID, що пристрій порахує собі на boot, і
  # одразу створює Tree + HardwareKey + запікає K_seed — однопрохідно.
  # Колізію 32-біт DID ловить DB-unique на `trees.did` до поля.
  #
  # DID == 0 зарезервовано під Королеву-Сентінель — фінальний guard
  # відображає нуль у SEED-константу, як і firmware.
  module DidDerivation
    SEED  = 0x534E4554 # "SNET"
    MASK  = 0xFFFFFFFF
    WIRE_PREFIX = "SNET-"

    module_function

    # murmur3 fmix32 — лавина у 32 бітах (дзеркало Did_Mix32).
    def mix32(h)
      h ^= h >> 16
      h = (h * 0x85EBCA6B) & MASK
      h ^= h >> 13
      h = (h * 0xC2B2AE35) & MASK
      h ^ (h >> 16)
    end

    # Три слова UID (little-endian uint32 з 0x1FFF7590/94/98) → 32-біт DID.
    # Ніколи не повертає 0.
    def did_from_uid_words(w0, w1, w2)
      h = SEED
      [ w0, w1, w2 ].each { |w| h = mix32(h ^ (w & MASK)) }
      h.zero? ? SEED : h
    end

    # Канонічна wire-форма для `trees.did`: "SNET-XXXXXXXX".
    def wire_did(w0, w1, w2)
      format("#{WIRE_PREFIX}%08X", did_from_uid_words(w0, w1, w2))
    end

    # Канонічна hex-форма 96-біт UID: три %08X-слова у порядку регістрів
    # (0x1FFF7590 перше), конкатеновані = 24 hex — так їх віддає SWD-read
    # (`-r32 0x1FFF7590`) і так їх бачить firmware через `*(uint32_t*)`.
    UID_HEX_FORMAT = /\A[0-9A-F]{24}\z/

    # "0039002F3138511538323634" → [0x0039002F, 0x31385115, 0x38323634].
    # Невалідний вхід → ArgumentError: фабрика мусить впасти голосно, а не
    # деривувати DID від сміття (одрук у UID = чужі ключі запечені мовчки).
    def uid_words(uid_hex)
      normalized = uid_hex.to_s.strip.upcase
      unless UID_HEX_FORMAT.match?(normalized)
        raise ArgumentError,
              "UID must be 24 hex chars (three %08X words, register order), got #{uid_hex.inspect}"
      end
      normalized.scan(/.{8}/).map { |w| Integer(w, 16) }
    end

    # 24-hex UID-рядок → канонічний `trees.did`.
    def wire_did_from_uid_hex(uid_hex)
      wire_did(*uid_words(uid_hex))
    end
  end
end
