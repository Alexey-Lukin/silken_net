# frozen_string_literal: true

# = ===================================================================
# 🌐 MARK WEB3 REQUESTS AS IO-BOUND (Puma 8.0+ — PUMA-IO-1, F-1 in 06_05)
# = ===================================================================
# Rack middleware that flags requests to known IO-heavy endpoints as
# IO-bound for Puma's thread pool. When such a request enters Puma, it is
# allowed to spawn additional threads beyond `max_threads` (capped by
# `max_io_threads`), so a slow Web3 RPC call cannot starve the entire
# worker.
#
# How it works:
#   - Puma 8.0+ sets `env["puma.mark_as_io_bound"]` to a lambda BEFORE
#     calling the Rack app (`puma/response.rb:75`).
#   - This middleware calls that lambda for matching requests.
#   - On non-Puma servers (Falcon, in tests) the env var is absent, so
#     `&.call` is a no-op — fully backward-compatible.
#
# Endpoint allowlist:
#   POST /api/v1/oracle_callbacks       — Chainlink callback (HMAC + DB)
#   POST /api/v1/provisioning/register  — peaq DID + Hadron KYC HTTP
#
# Why ONLY these two:
#   1. Both perform synchronous outbound HTTPS to third-party RPC/HTTP APIs
#      with p95 latency in the hundreds of ms to multiple seconds.
#   2. Both are called by external systems (Chainlink DON, Queen gateway)
#      that we cannot easily make async.
#   3. Other Web3-touching endpoints either (a) enqueue Sidekiq and return
#      immediately (e.g. `actuators#execute`, `firmwares#deploy`) or (b)
#      read from Solid Cache (e.g. `wallets#balance`).
#
# Future opt-in:
#   Add a path here, OR set `env["silken_net.io_bound"] = true` from a
#   controller `before_action` for declarative, per-action flagging.
#
# Cross-references:
#   - docs/06_05_Puma_Configuration.md (IO-bound thread pool)
#   - config/puma.rb (`max_io_threads 16`)
#   - https://github.com/puma/puma/blob/master/docs/architecture.md#io-bound-requests
class MarkWeb3RequestsAsIoBound
  PUMA_IO_BOUND_ENV_KEY = "puma.mark_as_io_bound"
  CONTROLLER_HINT_ENV_KEY = "silken_net.io_bound"

  # Frozen literal paths (no regex — fast O(1) Set lookup, zero allocations
  # in hot path). All routes match POST only — see config/routes.rb.
  IO_BOUND_PATHS = Set.new(
    %w[
      /api/v1/oracle_callbacks
      /api/v1/provisioning/register
    ]
  ).freeze

  IO_BOUND_METHOD = "POST"

  def initialize(app)
    @app = app
  end

  def call(env)
    if io_bound?(env)
      # `&.call` is essential: in dev (`bin/rails server` without Puma cluster
      # mode), `bin/rspec` (rack-test), or under non-Puma servers, this env
      # key is nil. The lambda is idempotent — Puma tracks per-thread state.
      env[PUMA_IO_BOUND_ENV_KEY]&.call
    end

    @app.call(env)
  end

  private

  def io_bound?(env)
    return true if env[CONTROLLER_HINT_ENV_KEY]

    # PATH_INFO is set for every Rack request and is already URL-decoded
    # to the route path (excludes query string). Method check first — most
    # requests are GET and short-circuit cheaply.
    env["REQUEST_METHOD"] == IO_BOUND_METHOD &&
      IO_BOUND_PATHS.include?(env["PATH_INFO"])
  end
end
