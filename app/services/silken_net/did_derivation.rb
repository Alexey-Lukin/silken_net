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
  end
end
