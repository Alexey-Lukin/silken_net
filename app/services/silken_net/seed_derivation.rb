# frozen_string_literal: true

module SilkenNet
  # [SEC.11] Lorenz Seed Provenance — derivation primitives.
  #
  # Two operations:
  #   1. derive_seed(device_uid)
  #        K_seed = HKDF-SHA256(
  #          ikm    = ENV["PROVISIONING_MASTER_KEY"],
  #          salt   = "silken-lorenz-v1",
  #          info   = device_uid,
  #          length = 32 bytes
  #        )
  #      Used at provisioning. Production raises if the master key is
  #      missing (see SEC.11 production guard); lab/dev mode falls back
  #      to SecureRandom for the same reason as HardwareKeyService — so
  #      the first integration test on a TRL-4 bench is not blocked.
  #
  #   2. initial_state(seed_bytes, epoch_day)
  #        digest = HMAC-SHA256(seed_bytes, "init|" || epoch_day_be8)
  #        x₀ = signed_unit_float(digest[ 0.. 7])  ∈ [-1, +1]
  #        y₀ = signed_unit_float(digest[ 8..15])
  #        z₀ = signed_unit_float(digest[16..23])
  #      Daily epoch rotation. Both firmware (mbedTLS) and backend
  #      (OpenSSL) compute byte-identical (x₀, y₀, z₀) for the same
  #      (K_seed, epoch_day) tuple, which is what makes the numeric Z
  #      divergence check possible after the field migration.
  #
  # The signed-unit-float unpacker treats the 8 digest bytes as a
  # big-endian uint64 and maps it from [0, 2^64-1] to [-1, +1]. This is
  # bit-exact across architectures because it is pure integer math
  # followed by a single Float division — IEEE-754 round-to-nearest is
  # deterministic for the result value range.
  module SeedDerivation
    HKDF_HASH        = "SHA256"
    HKDF_SALT        = "silken-lorenz-v1"
    HKDF_INFO_PREFIX = "silken-lorenz-seed"
    HMAC_INFO        = "init"
    SEED_BYTES       = 32
    EPOCH_SECONDS    = 86_400 # daily rotation

    UINT64_MAX_F = 18_446_744_073_709_551_615.0
    UINT64_HALF  = 9_223_372_036_854_775_807.5 # (2^64 - 1) / 2

    module_function

    # Derive a 32-byte K_seed for a device. Returns the upper-cased HEX
    # representation (64 chars) so it can be stored in the same column
    # shape as `aes_key_hex`. Always requires PROVISIONING_MASTER_KEY —
    # there is no SecureRandom fallback (SEC.11 hard cutover, see
    # docs/03_05 §3.4а).
    def derive_seed(device_uid)
      master_key = ENV["PROVISIONING_MASTER_KEY"]

      if master_key.blank?
        raise SecurityError,
              "PROVISIONING_MASTER_KEY ENV is required. Without it backend " \
              "would generate K_seed values that do NOT match firmware HKDF " \
              "derivation, breaking Dual Computation Integrity. " \
              "See SEC.11 in docs/00_08_Action_Plan_Tracker.md."
      end

      derived = OpenSSL::KDF.hkdf(
        master_key,
        salt: HKDF_SALT,
        info: "#{HKDF_INFO_PREFIX}|#{device_uid}",
        length: SEED_BYTES,
        hash: HKDF_HASH
      )

      derived.unpack1("H*").upcase
    end

    # Compute the daily-rotated initial Lorenz state for a given K_seed.
    # `seed_bytes` must be the raw 32-byte K_seed (use
    # HardwareKey#binary_lorenz_seed). `epoch_day` defaults to today's
    # UTC epoch. Returns [x0, y0, z0] as Floats in [-1, +1].
    def initial_state(seed_bytes, epoch_day = current_epoch_day)
      raise ArgumentError, "seed_bytes must be 32 bytes" unless seed_bytes&.bytesize == SEED_BYTES

      epoch_be = [ epoch_day ].pack("Q>") # 8-byte big-endian
      info     = "#{HMAC_INFO}|".b + epoch_be
      digest   = OpenSSL::HMAC.digest(HKDF_HASH, seed_bytes, info)

      [
        signed_unit_float(digest[0, 8]),
        signed_unit_float(digest[8, 8]),
        signed_unit_float(digest[16, 8])
      ]
    end

    # UTC epoch day for `Time#to_i / 86_400`. Default time = now.
    def current_epoch_day(time = Time.now.utc)
      time.to_i / EPOCH_SECONDS
    end

    # 8 raw bytes (big-endian uint64) → Float in [-1, +1].
    # Centered at 0.0 by subtracting (2^64 - 1) / 2 then dividing by the
    # same half-range. The mapping is bit-exact between OpenSSL (Ruby)
    # and mbedTLS (firmware) when both perform the integer subtract and
    # the single Float division.
    def signed_unit_float(bytes)
      n = bytes.unpack1("Q>")
      (n - UINT64_HALF) / UINT64_HALF
    end
  end
end
