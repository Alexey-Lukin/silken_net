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

# ---------------------------------------------------------------------------
# [SEC.22]: In-process cache for ENV-path HKDF derivations (crown-jewel reduction)
# ---------------------------------------------------------------------------
# PROVISIONING_MASTER_KEY-derived secrets re-derived on the hot path (iotex_seed —
# signed on every uplink, up to 5× on IotexVerificationWorker retry) are memoized
# here so a cache hit touches no master key. Same guarantees as HARDWARE_KEY_CACHE:
# secrets stay in worker RAM, never serialized, vanish on restart. Keyed by
# "<hkdf-info>\x00<salt>" (info = domain separator → no cross-key collision).
# Only the ENV path is cached; an explicit master_key: (SEC.3 DI) derives fresh.
# Valid for the whole process life because the master key is boot-immutable —
# rotation = fleet re-flash + redeploy (06_04 §5.2/§5.4) → restart clears this.
# ⚠️ Correctness rests on that immutability — the key OMITS the master by design.
# If a runtime master reload / per-tenant master is ever added, this would
# silently serve seeds from the stale root → Ed25519 attestations fail. Then key
# by a master fingerprint (or clear on reload) before shipping such a feature.
# ---------------------------------------------------------------------------
DERIVED_KEY_CACHE = SinLruRedux::ThreadSafeCache.new(10_000)
