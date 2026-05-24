# frozen_string_literal: true

require "openssl"

# [FW.2 / ARCH.42 Variant B] AES-128-CCM authenticated decrypt + encrypt for
# the Soldier ↔ Queen LoRa channel.
#
# Wire format on the air (24 bytes) — see docs/03_05 §3.2 BLOCKER-2:
#
#   ┌─ AAD (cleartext, MIC-protected) ──────────────────────────────────┐
#   │ DID[4]  │ FrameCounter[4 BE]                                       │
#   ├─ Ciphertext (sensor payload, encrypted) ──────────────────────────┤
#   │ Vcap[2 BE] │ temp[1] │ acoustic[1] │ dt[2 BE] │ status[1] │ ctrl[1]│
#   ├─ MIC (CCM authentication tag, 64-bit) ────────────────────────────┤
#   │ tag[8]                                                             │
#   └────────────────────────────────────────────────────────────────────┘
#
# Nonce construction (12 bytes, matches firmware spec):
#
#   nonce = DID || FrameCounter || 0x00 × 4
#
# Per-(key, DID) the FrameCounter is monotonic in firmware (`RTC_BKP_DR2`),
# so each (key, nonce) pair is globally unique — the only constraint CCM
# requires for confidentiality.
#
# Backend never holds firmware's CCM B0 block directly — OpenSSL builds it
# internally from `iv` (nonce), `auth_tag_len`, and `ccm_data_len`.
module Cryptography
  module LoraCcm
    NONCE_LEN     = 12 # bytes
    TAG_LEN       = 8  # MIC length (CCM allows {4,6,8,10,12,14,16}; we pick 8)
    AAD_LEN       = 8  # DID(4) + FrameCounter(4 BE)
    PLAINTEXT_LEN = 8  # sensor payload size — fixed for FW.2

    class AuthError < StandardError; end
    class InputError < ArgumentError; end

    module_function

    # Decrypt a single 24-byte LoRa packet payload and verify its MIC.
    # Returns the 8-byte sensor payload as a binary string, or raises
    # `AuthError` on MIC failure (tampered ciphertext, wrong key, replayed
    # FC with mutated bytes — anything that breaks the CCM authentication).
    #
    # Parameters:
    #   key            : 16-byte binary string (Tree LoRa AES-128 key)
    #   did_bytes      : 4-byte binary string (raw DID as on the wire)
    #   frame_counter  : Integer in [0, 2**32 - 1]
    #   ciphertext     : 8-byte binary string
    #   mic            : 8-byte binary string
    def decrypt(key:, did_bytes:, frame_counter:, ciphertext:, mic:)
      validate_inputs!(key: key, did_bytes: did_bytes, frame_counter: frame_counter,
                       payload: ciphertext, mic: mic)

      aad   = build_aad(did_bytes, frame_counter)
      nonce = build_nonce(did_bytes, frame_counter)

      cipher = OpenSSL::Cipher.new("aes-128-ccm")
      cipher.decrypt
      cipher.iv_len        = NONCE_LEN
      cipher.auth_tag_len  = TAG_LEN
      cipher.key           = key
      cipher.iv            = nonce
      cipher.auth_tag      = mic
      cipher.ccm_data_len  = ciphertext.bytesize
      cipher.auth_data     = aad

      cipher.update(ciphertext) + cipher.final
    rescue OpenSSL::Cipher::CipherError => e
      raise AuthError, "CCM authentication failed: #{e.message}"
    end

    # Encrypt 8 bytes of sensor payload and produce ciphertext + 8-byte MIC.
    # Used by host-side tests and any future Rails-issued CCM downlinks. The
    # in-field encryption side is `HAL_CRYPEx_AESCCM_Encrypt` on Soldier.
    #
    # Returns `[ciphertext_bytes, mic_bytes]` (both binary strings).
    def encrypt(key:, did_bytes:, frame_counter:, plaintext:)
      validate_inputs!(key: key, did_bytes: did_bytes, frame_counter: frame_counter,
                       payload: plaintext, mic: nil)

      aad   = build_aad(did_bytes, frame_counter)
      nonce = build_nonce(did_bytes, frame_counter)

      cipher = OpenSSL::Cipher.new("aes-128-ccm")
      cipher.encrypt
      cipher.iv_len        = NONCE_LEN
      cipher.auth_tag_len  = TAG_LEN
      cipher.key           = key
      cipher.iv            = nonce
      cipher.ccm_data_len  = plaintext.bytesize
      cipher.auth_data     = aad

      ciphertext = cipher.update(plaintext) + cipher.final
      [ ciphertext, cipher.auth_tag(TAG_LEN) ]
    end

    # The DID+FC byte string CCM authenticates as Additional Authenticated
    # Data — anyone who flips a bit here will fail the MIC check.
    def build_aad(did_bytes, frame_counter)
      did_bytes.b + [ frame_counter ].pack("N")
    end

    # 12-byte nonce = AAD || 4 zero bytes. Matches firmware §3.2 spec.
    def build_nonce(did_bytes, frame_counter)
      build_aad(did_bytes, frame_counter) + ("\x00".b * 4)
    end

    def validate_inputs!(key:, did_bytes:, frame_counter:, payload:, mic:)
      raise InputError, "key must be 16 bytes (AES-128)"          unless key.is_a?(String) && key.bytesize == 16
      raise InputError, "did_bytes must be 4 bytes"               unless did_bytes.is_a?(String) && did_bytes.bytesize == 4
      raise InputError, "frame_counter must fit in uint32"        unless frame_counter.is_a?(Integer) && (0..0xFFFF_FFFF).cover?(frame_counter)
      raise InputError, "payload must be #{PLAINTEXT_LEN} bytes"  unless payload.is_a?(String) && payload.bytesize == PLAINTEXT_LEN
      return if mic.nil? # encrypt path
      raise InputError, "mic must be #{TAG_LEN} bytes"            unless mic.is_a?(String) && mic.bytesize == TAG_LEN
    end
    private_class_method :validate_inputs!
  end
end
