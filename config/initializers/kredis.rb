# frozen_string_literal: true

# Extends Kredis with a Redis-based distributed lock using SET NX EX pattern.
#
# Kredis does not ship with a lock primitive. This adds Kredis.lock which uses
# the standard single-instance Redis lock algorithm (SET key value NX EX ttl).
#
# The lock is crash-safe: if the worker dies, the key expires after `expires_in`
# and another worker can acquire it. A UUID ownership token prevents accidental
# release of a lock held by a different process.
#
# Usage:
#   Kredis.lock("lock:web3:oracle:0xABC", expires_in: 30.seconds) { send_tx }

module Kredis
  class LockTimeout < StandardError; end

  # Acquire a distributed lock and yield, releasing it on completion.
  #
  # @param key [String]           Logical lock name (auto-namespaced by Kredis)
  # @param expires_in [Duration]  Maximum TTL — prevents infinite deadlocks
  # @param after_timeout [Symbol] :raise (default) → raise LockTimeout; :return → return nil
  # @param config [Symbol]        Kredis connection config name (default :shared)
  def lock(key, expires_in:, after_timeout: :raise, config: :shared)
    unless after_timeout.in?([ :raise, :return ])
      raise ArgumentError, "after_timeout must be :raise or :return, got #{after_timeout.inspect}"
    end

    redis = Kredis.redis(config: config)
    full_key = Kredis.namespaced_key(key)
    token = SecureRandom.uuid
    ttl = expires_in.to_i.clamp(1, 300)

    acquired = redis.set(full_key, token, nx: true, ex: ttl)

    unless acquired
      if after_timeout == :raise
        raise LockTimeout, "Could not acquire lock: #{key} (TTL: #{ttl}s)"
      end
      return nil
    end

    begin
      yield
    ensure
      # Release only if we still own the lock (prevents releasing another worker's lock).
      # Uses a Lua script for atomic GET + DEL to avoid TOCTOU race.
      redis.eval(
        "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end",
        keys: [ full_key ],
        argv: [ token ]
      )
    end
  end
end
