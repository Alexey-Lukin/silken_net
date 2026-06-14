# frozen_string_literal: true

require "openssl"

# [FW.2 / ARCH.42 Variant B; wire-rev2 28B, founder decision 2026-06-12]
# AES-128-CCM authenticated decrypt + encrypt for the Soldier ↔ Queen LoRa
# channel.
#
# Wire format on the air (28 bytes) — see docs/03_05 §2.1 (CCM wire) +
# wire-budget ledger (the rev2 rationale):
#
#   ┌─ AAD (cleartext, MIC-protected) ──────────────────────────────────┐
#   │ DID[4] │ gossip_ts_lsb[1] │ FrameCounter[3 BE — справжня ширина]   │
#   ├─ Ciphertext (sensor payload, encrypted, 12B) ─────────────────────┤
#   │ Vcap[2 BE] │ temp[1] │ acoustic[1] │ dt[2 BE] │ status[1] │ ctrl[1]│
#   │ device_z[2 BE, ×512; 0xFFFF = none] │ diag[1] │ vpd_index[1]      │
#   ├─ MIC (CCM authentication tag, 64-bit) ────────────────────────────┤
#   │ tag[8]                                                             │
#   └────────────────────────────────────────────────────────────────────┘
#
# The gossip byte rides cleartext ON PURPOSE: neighbouring Soldiers refine
# their clocks from it without holding this Soldier's key (FW.20-S2 #5
# survives per-Soldier CCM keys); the backend authenticates it via the MIC.
#
# Nonce construction (12 bytes, byte-identical to wire-rev1 — the FC top
# byte was always 0x00 because the counter is 24-bit):
#
#   nonce = DID || FrameCounter(4 BE) || 0x00 × 4
#
# Per-(key, DID) the FrameCounter is monotonic in firmware (`RTC_BKP_DR15`),
# so each (key, nonce) pair is unique under normal operation — the constraint
# CCM requires for confidentiality. (Cold boot after VBAT loss floors from the
# Flash high-water anchor — fc_hiwater.h — with HRNG reseed as last fallback;
# see docs/03_05 §2.1.)
#
# Backend never holds firmware's CCM B0 block directly — OpenSSL builds it
# internally from `iv` (nonce), `auth_tag_len`, and `ccm_data_len`.
module Cryptography
  module LoraCcm
    NONCE_LEN     = 12 # bytes
    TAG_LEN       = 8  # MIC length (CCM allows {4,6,8,10,12,14,16}; we pick 8)
    AAD_LEN       = 8  # DID(4) + gossip(1) + FrameCounter(3 BE)
    PLAINTEXT_LEN = 12 # sensor payload size — FW.2 wire-rev2

    class AuthError < StandardError; end
    class InputError < ArgumentError; end

    module_function

    # Decrypt a single 28-byte LoRa packet payload and verify its MIC.
    # Returns the 12-byte sensor payload as a binary string, or raises
    # `AuthError` on MIC failure (tampered ciphertext/gossip byte, wrong key,
    # replayed FC with mutated bytes — anything breaking CCM authentication).
    #
    # Parameters:
    #   key            : 16-byte binary string (Tree LoRa AES-128 key)
    #   did_bytes      : 4-byte binary string (raw DID as on the wire)
    #   frame_counter  : Integer in [0, 2**24 - 1] (24-bit wire width)
    #   gossip_ts_lsb  : Integer in [0, 255] — AAD byte 4 (FW.20-S2 #5)
    #   ciphertext     : 12-byte binary string
    #   mic            : 8-byte binary string
    def decrypt(key:, did_bytes:, frame_counter:, ciphertext:, mic:, gossip_ts_lsb: 0)
      validate_inputs!(key: key, did_bytes: did_bytes, frame_counter: frame_counter,
                       gossip_ts_lsb: gossip_ts_lsb, payload: ciphertext, mic: mic)

      aad   = build_aad(did_bytes, gossip_ts_lsb, frame_counter)
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

    # Encrypt 12 bytes of sensor payload and produce ciphertext + 8-byte MIC.
    # Used by host-side tests and any future Rails-issued CCM downlinks. The
    # in-field encryption side is `HAL_CRYPEx_AESCCM_Encrypt` on Soldier.
    #
    # Returns `[ciphertext_bytes, mic_bytes]` (both binary strings).
    def encrypt(key:, did_bytes:, frame_counter:, plaintext:, gossip_ts_lsb: 0)
      validate_inputs!(key: key, did_bytes: did_bytes, frame_counter: frame_counter,
                       gossip_ts_lsb: gossip_ts_lsb, payload: plaintext, mic: nil)

      aad   = build_aad(did_bytes, gossip_ts_lsb, frame_counter)
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

    # AAD = DID || gossip || FC24 — the byte string CCM authenticates as
    # Additional Authenticated Data; anyone who flips a bit here (including
    # the cleartext gossip byte) will fail the MIC check.
    def build_aad(did_bytes, gossip_ts_lsb, frame_counter)
      did_bytes.b + [ gossip_ts_lsb ].pack("C") + [ frame_counter ].pack("N")[1..3]
    end

    # 12-byte nonce = DID || FC32 BE || 4 zero bytes — byte-identical to
    # wire-rev1 (gossip byte deliberately NOT part of the nonce: uniqueness
    # is carried by the FC alone). Matches firmware Build_CCM_Nonce.
    def build_nonce(did_bytes, frame_counter)
      did_bytes.b + [ frame_counter ].pack("N") + ("\x00".b * 4)
    end

    def validate_inputs!(key:, did_bytes:, frame_counter:, gossip_ts_lsb:, payload:, mic:)
      raise InputError, "key must be 16 bytes (AES-128)"          unless key.is_a?(String) && key.bytesize == 16
      raise InputError, "did_bytes must be 4 bytes"               unless did_bytes.is_a?(String) && did_bytes.bytesize == 4
      raise InputError, "frame_counter must fit in 24 bits"       unless frame_counter.is_a?(Integer) && (0..0xFF_FFFF).cover?(frame_counter)
      raise InputError, "gossip_ts_lsb must fit in one byte"      unless gossip_ts_lsb.is_a?(Integer) && (0..0xFF).cover?(gossip_ts_lsb)
      raise InputError, "payload must be #{PLAINTEXT_LEN} bytes"  unless payload.is_a?(String) && payload.bytesize == PLAINTEXT_LEN
      return if mic.nil? # encrypt path
      raise InputError, "mic must be #{TAG_LEN} bytes"            unless mic.is_a?(String) && mic.bytesize == TAG_LEN
    end
    private_class_method :validate_inputs!
  end
end
