# SPDX-License-Identifier: AGPL-3.0-or-later
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

# 🔴 KEY NAMESPACE — load-bearing on TWO axes, neither of them cosmetic.
#
# Upstash (our managed Redis) exposes exactly ONE logical database: `SELECT 1`
# answers `ERR Only 0th database is supported!` (measured against our own
# instance 2026-08-30, not read off a doc). So the numbered-DB isolation this
# stack used to assume — Sidekiq/0, Kredis/1, Rack::Attack/2 — cannot exist in
# production, and every consumer now shares one keyspace. A prefix is what keeps
# them apart. Every production Kredis key already routes through
# `Kredis.namespaced_key` (the lock below, the QATT and M2M nonces), so setting
# this is sufficient — nothing needs a call-site change.
#
# 🔴 The second axis is the one that bites silently: `Kredis.clear_all` branches
# on this value. With no namespace the gem calls `FLUSHDB`; with one it deletes
# only `<namespace>:*`. On a shared keyspace an unnamespaced `clear_all` would
# wipe the Sidekiq queues and the Rack::Attack counters along with our locks.
# ⛔ Do not "simplify" this away because the keys look readable without it.
#
# Sidekiq deliberately gets NO namespace: it cannot have one (Sidekiq 7+ raises
# ArgumentError on `namespace:`), and it does not need one — its keys (`queue:`,
# `retry`, `dead`, `stat:`, `processes`) collide with nothing here.
#
# ⚠️ NO KEY MIGRATION WAS RUN, and the argument for why that is safe belongs
# here rather than in a commit message, because it is the thing a reader will
# doubt: adding a prefix ORPHANS every pre-existing unprefixed Kredis key, and
# some of those have no TTL (`solana_pending_payouts:*`) or a 30-day one
# (`qatt_nonce:*`). It is safe in PRODUCTION for exactly one reason — the old
# config derived `/1`, which Upstash rejects, so no production Kredis key ever
# existed to orphan. It is NOT automatically safe on a self-hosted Redis (a local
# stand, or any deploy that predates this change): there the old keys survive,
# invisible. If that ever applies, `Kredis::Migration` exists in the gem; the
# blast radius to check first is the pending-payout counters (no TTL), the mint
# circuit-breaker flag (fail-OPEN when lost) and the QATT replay nonces.
Kredis.global_namespace = "silken"

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
