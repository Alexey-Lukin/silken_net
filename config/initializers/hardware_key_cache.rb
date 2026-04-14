# frozen_string_literal: true

# ---------------------------------------------------------------------------
# [A-7 FIX]: In-Process Memory Cache for AES Hardware Keys
# ---------------------------------------------------------------------------
# Decrypted AES binary keys are cached in process-local RAM instead of Redis.
# This eliminates the risk of mass key leakage if a Redis instance is compromised.
#
# Trade-offs:
#   ✅ Keys never leave the Ruby process — no network exposure
#   ✅ Keys vanish on process restart/crash — zero residual footprint
#   ✅ No serialization overhead (binary values stay as-is)
#   ⚠️ Each Sidekiq worker/Puma thread has its own cache (no sharing)
#   ⚠️ Memory: 10,000 keys × ~32 bytes ≈ 320 KB per process — negligible
#
# SinLruRedux is already a transitive dependency (via tailwind_merge).
# ---------------------------------------------------------------------------
require "sin_lru_redux"

HARDWARE_KEY_CACHE = SinLruRedux::ThreadSafeCache.new(10_000)
