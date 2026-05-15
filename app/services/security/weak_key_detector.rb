# frozen_string_literal: true

require "openssl"
require "base64"

# [SEC.9] Weak / known-test-vector detector for long-lived master secrets.
#
# Background
# ----------
# SEC.9 (`docs/00_08_Action_Plan_Tracker.md`, `docs/03_05_Hardware_AES256_and_Security.md` §3.1)
# documents that the historical hardcoded firmware AES key happened to share
# its first 16 bytes with the FIPS-197 Appendix B AES-128 test vector. The
# reaction documented in the tracker — "verify the NEW master key is not any
# known test vector" — is wrong-shaped if implemented as a one-time manual
# check:
#
#   * the entire HKDF derivation tree (HardwareKeyService → AES device keys,
#     OtaHmacKeyService → K_ota) collapses if PROVISIONING_MASTER_KEY is weak,
#   * future rotations could silently re-introduce a placeholder,
#   * one master is consumed by multiple services, doubling blast radius.
#
# This service replaces "manual check" with an automated detector. The
# companion initializer (`config/initializers/master_key_strength_check.rb`)
# refuses to boot the production / canopy environment if the master key
# matches any known test vector or degenerate pattern.
#
# Scope
# -----
# *Long-lived symmetric secrets only.* The current call site is
# `PROVISIONING_MASTER_KEY` (HKDF root for both `HardwareKeyService` and
# `OtaHmacKeyService`). The same detector can be re-used for any future
# static master (e.g. Chainlink HMAC root).
#
# How interpretations are checked
# -------------------------------
# Operators can paste a 32-byte master into ENV in three common shapes:
#
#   1. raw ASCII passphrase / bytes        — checked as-is
#   2. 32-char or 64-char hex string       — checked also after hex-decoding
#   3. base64 (rare)                       — checked also after base64 decoding,
#                                            only if it round-trips losslessly
#
# All three shapes are compared against the blocklist so that the same
# FIPS-197 vector cannot sneak in just because somebody pasted it
# hex-encoded into Kamal secrets while another operator pasted the raw
# bytes into firmware.
#
# Public API
# ----------
#   Security::WeakKeyDetector.detect(value, hint: "PROVISIONING_MASTER_KEY")
#     => nil                              # safe
#     => "FIPS-197 Appendix B (AES-128)"  # weak — reason string
module Security
  module WeakKeyDetector
    module_function

    # Public entry point. Returns nil if `value` looks safe, or a
    # human-readable string naming the weakness pattern that matched.
    #
    # `value` may be nil / empty — the caller is expected to handle
    # "missing" separately (SEC.11 services already raise `SecurityError`
    # when the master-key ENV is blank); this detector intentionally only
    # judges *content*.
    def detect(value, hint: nil)
      return nil if value.nil?

      candidates = candidate_byte_strings(value)
      return nil if candidates.empty?

      candidates.each do |bytes|
        %i[match_known_vector match_degenerate match_placeholder].each do |checker|
          reason = send(checker, bytes)
          return decorate(reason, hint) if reason
        end
      end

      nil
    end

    def weak?(value, hint: nil)
      !detect(value, hint: hint).nil?
    end

    # --- candidate expansion -------------------------------------------------

    def candidate_byte_strings(value)
      raw = value.to_s.b
      out = [ raw ]

      # Hex interpretation — only if the *whole* string is hex and length is
      # even. Accept any length so we catch 16/24/32-byte AES keys plus the
      # 20-/32-byte RFC HMAC vectors. Use `.b` (ASCII-8BIT) before regex so
      # non-UTF-8 raw bytes (e.g. `\xFF * 32`) don't blow up `String#match?`.
      stripped = raw.sub(/\A0[xX]/, "")
      if stripped.bytesize >= 2 && stripped.bytesize.even? && stripped.match?(/\A[0-9A-Fa-f]+\z/)
        decoded = [ stripped ].pack("H*")
        out << decoded unless decoded == raw
      end

      # Base64 interpretation — only if it round-trips losslessly. This
      # rejects ordinary passphrases that happen to use a-z0-9 only.
      if raw.bytesize >= 4 && raw.match?(%r{\A[A-Za-z0-9+/=]+\z})
        begin
          decoded = Base64.strict_decode64(raw)
          encoded_back = Base64.strict_encode64(decoded)
          out << decoded if encoded_back == raw && !out.include?(decoded)
        rescue ArgumentError
          # not base64 — ignore
        end
      end

      out.uniq
    end

    # --- pattern banks -------------------------------------------------------

    # Publicly known test vectors. Each entry is `[hex_bytes, name]`. Hex
    # form keeps the source readable while sidestepping any "is this a key?"
    # secret-scanner that flags raw byte literals.
    KNOWN_VECTORS_HEX = [
      # FIPS 197 Appendix B (AES-128 worked example).
      [ "2b7e151628aed2a6abf7158809cf4f3c",
        "FIPS-197 Appendix B (AES-128 worked example)" ],

      # FIPS 197 Appendix C.1 / C.2 / C.3 incrementing-bytes test inputs.
      [ "000102030405060708090a0b0c0d0e0f",
        "FIPS-197 Appendix C.1 (AES-128, incrementing bytes)" ],
      [ "000102030405060708090a0b0c0d0e0f1011121314151617",
        "FIPS-197 Appendix C.2 (AES-192, incrementing bytes)" ],
      [ "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        "FIPS-197 Appendix C.3 (AES-256, incrementing bytes)" ],

      # NIST SP 800-38A Block-Cipher Modes of Operation sample keys.
      [ "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4",
        "NIST SP 800-38A F.5 (AES-256 CTR sample key)" ],
      [ "8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b",
        "NIST SP 800-38A F.x (AES-192 sample key)" ],

      # RFC 3686 (AES-CTR test) widely-quoted sample key #1.
      [ "ae6852f8121067cc4bf7a5765577f39e",
        "RFC 3686 §6 (AES-CTR, test vector #1)" ],

      # RFC 4231 HMAC-SHA-256 published test cases — 20×0x0b, 20×0xaa,
      # 131×0xaa. Catch these because somebody who copy-pastes "the
      # standard HMAC test key" into ENV usually grabs one of them.
      [ ("0b" * 20),
        "RFC 4231 Test Case 1 (HMAC-SHA-256, 20×0x0b)" ],
      [ ("aa" * 20),
        "RFC 4231 Test Case 3 (HMAC-SHA-256, 20×0xaa)" ],
      [ ("aa" * 131),
        "RFC 4231 Test Case 6/7 (HMAC-SHA-256, 131×0xaa)" ],

      # FIPS 198-1 / RFC 2104 historical HMAC test keys.
      [ "0102030405060708090a0b0c0d0e0f10111213141516171819",
        "FIPS 198-1 §A.1 / RFC 2104 (HMAC test, 25-byte ascending)" ]
    ].freeze

    KNOWN_VECTORS = KNOWN_VECTORS_HEX
                    .map { |hex, name| [ [ hex ].pack("H*"), name ] }
                    # Longest vectors first so an exact 32-byte match (e.g. FIPS-197 C.3)
                    # wins over a 16-byte prefix match (e.g. C.1) when both apply.
                    .sort_by { |bytes, _name| -bytes.bytesize }
                    .freeze

    def match_known_vector(bytes)
      KNOWN_VECTORS.each do |vector, name|
        # Exact match — the most direct case.
        return "matches #{name}" if bytes == vector

        # Prefix match — the original BLOCKER was a 32-byte field whose
        # first 16 bytes matched a 16-byte vector. Flag whenever the known
        # short vector is a prefix of the longer master, but require at
        # least 8 leading bytes of overlap to keep false positives down.
        next unless vector.bytesize >= 8 && bytes.bytesize > vector.bytesize
        return "starts with #{name}" if bytes.byteslice(0, vector.bytesize) == vector
      end
      nil
    end

    # Cryptographically catastrophic byte patterns regardless of length.
    def match_degenerate(bytes)
      return nil if bytes.bytesize < 8

      uniq = bytes.bytes.uniq
      return "all-zero key" if uniq == [ 0 ]
      return "all-0xFF key" if uniq == [ 0xFF ]
      return format("single-byte repeat (0x%02x)", uniq.first) if uniq.length == 1

      # Strictly ascending or descending byte run (covers 00 01 02 …).
      diffs = bytes.bytes.each_cons(2).map { |a, b| b - a }.uniq
      if diffs.length == 1 && [ 1, -1 ].include?(diffs.first)
        return "strictly-monotonic byte run (delta=#{diffs.first})"
      end

      nil
    end

    # Human-typed placeholders that frequently leak into ENV during onboarding.
    PLACEHOLDER_NEEDLES = %w[
      changeme
      change-me
      change_me
      placeholder
      todo
      example
      default
      secret-here
      your-secret
      your-key
      your-master
      your-aes
      replace-me
      replaceme
      dev-only
      not-a-real-key
      silken-net-test-master-key
    ].freeze

    def match_placeholder(bytes)
      # Only inspect ASCII-printable candidates — otherwise this is binary noise.
      return nil unless bytes.bytes.all? { |b| b >= 0x20 && b < 0x7F }

      lower = bytes.downcase
      PLACEHOLDER_NEEDLES.each do |needle|
        return "contains placeholder substring #{needle.inspect}" if lower.include?(needle)
      end

      # Angle-bracketed placeholders like "<your-master-key>".
      return "looks like an unsubstituted <…> placeholder" if lower.match?(/<[^>]{3,}>/)

      nil
    end

    def decorate(reason, hint)
      hint ? "#{hint}: #{reason}" : reason
    end
  end
end
